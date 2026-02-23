local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local MarketplaceServiceService = {}
MarketplaceServiceService.__index = MarketplaceServiceService

MarketplaceServiceService.DevProducts = {
	-- Replace IDs + grants with your actual products
	-- [123456789] = { Kind = "Cash", Amount = 5000 },
	-- [234567890] = { Kind = "XP", Amount = 2500 },
	-- [345678901] = { Kind = "Tool", ToolName = "GoldenBat" },
	-- [456789012] = { Kind = "RarityBoost", Multiplier = 1.25, DurationSec = 1800 },
}

MarketplaceServiceService.Gamepasses = {
	-- Replace IDs + perks with your actual passes
	-- CashMultiplierPassId = 11111111,
	-- XPMultiplierPassId = 22222222,
	-- RarityBoostPassId = 33333333,
	-- StarterToolPassId = 44444444,
	--
	-- CashMultiplier = 2,
	-- XPMultiplier = 2,
	-- RarityMultiplier = 1.15,
	-- StarterToolName = "VIPStick",
}

function MarketplaceServiceService.new()
	return setmetatable({
		Services = nil,

		_econ = nil,
		_inv = nil,
		_prog = nil,
		_data = nil,
		_net = nil,

		_receiptSessionCache = {},
		_gamepassCache = {},
		_tempBoostCache = {},

		_receiptBound = false,

		DevProducts = MarketplaceServiceService.DevProducts,
		Gamepasses = MarketplaceServiceService.Gamepasses,
	}, MarketplaceServiceService)
end

function MarketplaceServiceService:Init(services)
	self.Services = services
	self._econ = services.EconomyService
	self._inv = services.InventoryService
	self._prog = services.ProgressionService
	self._data = services.DataService
	self._net = services.NetService

	self._receiptSessionCache = self._receiptSessionCache or {}
	self._gamepassCache = self._gamepassCache or {}
	self._tempBoostCache = self._tempBoostCache or {}
	self._receiptBound = self._receiptBound or false

	self.DevProducts = self.DevProducts or MarketplaceServiceService.DevProducts or {}
	self.Gamepasses = self.Gamepasses or MarketplaceServiceService.Gamepasses or {}
end

local function now()
	return os.time()
end

function MarketplaceServiceService:_getUserKey(player)
	return tostring(player.UserId)
end

function MarketplaceServiceService:_markReceiptGranted(player, purchaseId)
	local userKey = self:_getUserKey(player)
	self._receiptSessionCache[userKey] = self._receiptSessionCache[userKey] or {}
	self._receiptSessionCache[userKey][purchaseId] = true
end

function MarketplaceServiceService:_isReceiptGrantedSession(player, purchaseId)
	local userKey = self:_getUserKey(player)
	return self._receiptSessionCache[userKey] and self._receiptSessionCache[userKey][purchaseId] == true
end

function MarketplaceServiceService:_isReceiptGrantedPersistent(player, purchaseId)
	local profile = self._data and self._data:GetProfile(player)
	if not profile then
		return false
	end
	local purchases = profile.Purchases
	if not purchases then
		return false
	end
	local receipts = purchases.Receipts
	if not receipts then
		return false
	end
	return receipts[purchaseId] == true
end

function MarketplaceServiceService:_persistReceiptGranted(player, purchaseId)
	if not self._data then
		return
	end
	self._data:Update(player, function(p)
		p.Purchases = p.Purchases or {}
		p.Purchases.Receipts = p.Purchases.Receipts or {}
		p.Purchases.Receipts[purchaseId] = true
		return p
	end)
end

function MarketplaceServiceService:_applyGrant(player, grant, context)
	if not player or not player.Parent then
		return false, "NoPlayer"
	end
	if type(grant) ~= "table" then
		return false, "BadGrant"
	end

	local kind = grant.Kind

	if kind == "Cash" then
		local amount = tonumber(grant.Amount) or 0
		if amount <= 0 then return false, "BadAmount" end
		if not self._econ or type(self._econ.AddCash) ~= "function" then return false, "NoEconomy" end
		self._econ:AddCash(player, amount, context or "Marketplace")
		return true

	elseif kind == "XP" then
		local amount = tonumber(grant.Amount) or 0
		if amount <= 0 then return false, "BadAmount" end
		if not self._prog or type(self._prog.AddXP) ~= "function" then return false, "NoProgression" end
		self._prog:AddXP(player, amount, context or "Marketplace")
		return true

	elseif kind == "Tool" then
		local toolName = grant.ToolName
		if type(toolName) ~= "string" or toolName == "" then return false, "BadTool" end
		if not self._inv or type(self._inv.GrantTool) ~= "function" then return false, "NoInventory" end
		self._inv:GrantTool(player, toolName)
		return true

	elseif kind == "RarityBoost" then
		local mult = tonumber(grant.Multiplier) or 1
		local dur = tonumber(grant.DurationSec) or 0
		if mult <= 1 or dur <= 0 then return false, "BadBoost" end

		self._tempBoostCache[player.UserId] = {
			EndsAt = now() + dur,
			Multiplier = mult,
		}

		if self._data then
			self._data:Update(player, function(p)
				p.Purchases = p.Purchases or {}
				p.Purchases.TempRarityBoost = {
					EndsAt = now() + dur,
					Multiplier = mult,
				}
				return p
			end)
		end

		return true
	end

	return false, "UnknownKind"
end

function MarketplaceServiceService:HasGamepass(player, gamepassId)
	if not player or not player.Parent then
		return false
	end
	gamepassId = tonumber(gamepassId)
	if not gamepassId or gamepassId <= 0 then
		return false
	end

	local cache = self._gamepassCache[player.UserId]
	if cache and cache[gamepassId] ~= nil and cache._ts and (now() - cache._ts) < 120 then
		return cache[gamepassId] == true
	end

	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
	end)

	self._gamepassCache[player.UserId] = self._gamepassCache[player.UserId] or { _ts = now() }
	self._gamepassCache[player.UserId]._ts = now()
	self._gamepassCache[player.UserId][gamepassId] = (ok and owns) == true

	return self._gamepassCache[player.UserId][gamepassId] == true
end

function MarketplaceServiceService:GetCashMultiplier(player)
	local gp = self.Gamepasses or {}
	local passId = tonumber(gp.CashMultiplierPassId)
	local mult = tonumber(gp.CashMultiplier) or 1
	if passId and passId > 0 and mult > 1 then
		if self:HasGamepass(player, passId) then
			return mult
		end
	end
	return 1
end

function MarketplaceServiceService:GetXPMultiplier(player)
	local gp = self.Gamepasses or {}
	local passId = tonumber(gp.XPMultiplierPassId)
	local mult = tonumber(gp.XPMultiplier) or 1
	if passId and passId > 0 and mult > 1 then
		if self:HasGamepass(player, passId) then
			return mult
		end
	end
	return 1
end

function MarketplaceServiceService:GetRarityMultiplier(player)
	local gp = self.Gamepasses or {}
	local passId = tonumber(gp.RarityBoostPassId)
	local mult = tonumber(gp.RarityMultiplier) or 1

	local passMult = 1
	if passId and passId > 0 and mult > 1 then
		if self:HasGamepass(player, passId) then
			passMult = mult
		end
	end

	local tempMult = 1
	local temp = self._tempBoostCache[player.UserId]
	if not temp and self._data then
		local profile = self._data:GetProfile(player)
		if profile and profile.Purchases and profile.Purchases.TempRarityBoost then
			temp = profile.Purchases.TempRarityBoost
			if type(temp) == "table" and temp.EndsAt and temp.Multiplier then
				self._tempBoostCache[player.UserId] = temp
			end
		end
	end

	if type(temp) == "table" and tonumber(temp.EndsAt) and tonumber(temp.Multiplier) then
		if now() < tonumber(temp.EndsAt) then
			tempMult = tonumber(temp.Multiplier) or 1
		else
			self._tempBoostCache[player.UserId] = nil
			if self._data then
				self._data:Update(player, function(p)
					if p.Purchases and p.Purchases.TempRarityBoost then
						p.Purchases.TempRarityBoost = nil
					end
					return p
				end)
			end
		end
	end

	return passMult * tempMult
end

function MarketplaceServiceService:_grantGamepassEntitlements(player)
	local gp = self.Gamepasses or {}
	local starterPassId = tonumber(gp.StarterToolPassId)
	local starterTool = gp.StarterToolName
	if starterPassId and starterPassId > 0 and type(starterTool) == "string" and starterTool ~= "" then
		if self:HasGamepass(player, starterPassId) then
			if self._inv and type(self._inv.GrantTool) == "function" then
				self._inv:GrantTool(player, starterTool)
			end
		end
	end
end

function MarketplaceServiceService:_processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	if self:_isReceiptGrantedSession(player, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if self:_isReceiptGrantedPersistent(player, purchaseId) then
		self:_markReceiptGranted(player, purchaseId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productId = tonumber(receiptInfo.ProductId)
	local grant = (self.DevProducts and self.DevProducts[productId]) or nil
	if not grant then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local okGrant = self:_applyGrant(player, grant, "DevProduct")
	if not okGrant then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	self:_persistReceiptGranted(player, purchaseId)
	self:_markReceiptGranted(player, purchaseId)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MarketplaceServiceService:Start()
	if not self._receiptBound then
		self._receiptBound = true
		MarketplaceService.ProcessReceipt = function(receiptInfo)
			return self:_processReceipt(receiptInfo)
		end
	end

	Players.PlayerAdded:Connect(function(player)
		self._gamepassCache[player.UserId] = nil
		self._tempBoostCache[player.UserId] = nil

		task.defer(function()
			if not player.Parent then return end
			self:_grantGamepassEntitlements(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._gamepassCache[player.UserId] = nil
		self._tempBoostCache[player.UserId] = nil
	end)
end

return MarketplaceServiceService