local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopService = {}
ShopService.__index = ShopService

-- ── Config loading ──────────────────────────────────────────────────────────

local ConfigFolder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")

local function safeRequire(inst: Instance): any?
	local ok, mod = pcall(require, inst)
	return ok and mod or nil
end

local SpeedConfig = ConfigFolder:FindFirstChild("SpeedConfig") and safeRequire(ConfigFolder.SpeedConfig)
local ArmorConfig = ConfigFolder:FindFirstChild("ArmorConfig") and safeRequire(ConfigFolder.ArmorConfig)

-- ── Station helpers (existing weapon stand logic) ───────────────────────────

local function isBasePart(x)
	return typeof(x) == "Instance" and x:IsA("BasePart")
end

local function getPromptParent(station)
	if station:IsA("Model") then
		if station.PrimaryPart and isBasePart(station.PrimaryPart) then
			return station.PrimaryPart
		end
		local pp = station:FindFirstChildWhichIsA("BasePart", true)
		return pp or station
	end
	if isBasePart(station) then
		return station
	end
	return station
end

local function ensurePrompt(station)
	local parent = getPromptParent(station)
	if not parent or not parent:IsA("Instance") then return nil end

	local prompt = parent:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.Parent = parent
	end
	return prompt
end

local function readStationConfig(station)
	local toolName = station:GetAttribute("ToolName")
	local price = station:GetAttribute("Price")

	if typeof(toolName) ~= "string" then
		local tn = station:FindFirstChild("ToolName")
		if tn and tn:IsA("StringValue") then toolName = tn.Value end
	end
	if typeof(price) ~= "number" then
		local pv = station:FindFirstChild("Price")
		if pv and pv:IsA("NumberValue") then price = pv.Value end
	end

	return toolName, price
end

-- ── Init / Start ────────────────────────────────────────────────────────────

function ShopService:Init(services)
	self.Services     = services
	self.Net          = services.NetService
	self.Economy      = services.EconomyService
	self.Inventory    = services.InventoryService
	self.DataService  = services.DataService
	self.ArmorService = services.ArmorService

	self.StationsFolder = Workspace:FindFirstChild("WeaponStations")
	self._stationByKey = {}
	self._promptDebounce = {}
end

function ShopService:Start()
	self:_scanStations()

	-- On profile load, sync SpeedBoost + SpeedTier + ArmorTier to client
	if self.DataService then
		self.DataService.OnProfileLoaded:Connect(function(player, data)
			if not self.Net then return end

			-- Speed
			local speedTier = (data.Progression and data.Progression.SpeedTier) or 0
			local speedBonus = 0
			if speedTier > 0 and SpeedConfig and SpeedConfig.Tiers then
				local t = SpeedConfig.Tiers[speedTier]
				if t then speedBonus = tonumber(t.SpeedBonus) or 0 end
			end
			self.Net:QueueDelta(player, "SpeedBoost", speedBonus)
			self.Net:QueueDelta(player, "SpeedTier", speedTier)

			-- Armor tier (Armor + MaxArmor already synced by ArmorService)
			local armorTier = (data.Defense and data.Defense.ArmorTier) or 0
			self.Net:QueueDelta(player, "ArmorTier", armorTier)

			self.Net:FlushDelta(player)
		end)
	end
end

-- ── Public entry point (called by NetService:RouteAction) ───────────────────

function ShopService:HandleShopAction(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return { ok = false, reason = "BadPayload" }
	end

	local action = tostring(payload.action or "")

	if action == "buySpeed" then
		return self:_handleBuySpeed(player, payload)
	elseif action == "buyArmor" then
		return self:_handleBuyArmor(player, payload)
	else
		-- Legacy: weapon station purchase
		return self:_handleWeaponStation(player, payload)
	end
end

-- ── Buy Speed ───────────────────────────────────────────────────────────────

function ShopService:_handleBuySpeed(player: Player, payload: any)
	local tierIndex = tonumber(payload.tierIndex)
	if not tierIndex then
		return { ok = false, reason = "MissingTierIndex" }
	end

	local tiers = SpeedConfig and SpeedConfig.Tiers
	if not tiers then
		return { ok = false, reason = "NoSpeedConfig" }
	end

	local tier = tiers[tierIndex]
	if not tier then
		return { ok = false, reason = "InvalidTier" }
	end

	-- Sequential: must buy the next tier in order
	local currentTier = self.DataService:GetValue(player, "Progression.SpeedTier") or 0
	if tierIndex ~= currentTier + 1 then
		return { ok = false, reason = "WrongTier" }
	end

	-- Charge
	local price = tonumber(tier.Price) or 0
	if price > 0 then
		local chargeOk, chargeErr = self.Economy:SpendCash(player, price)
		if not chargeOk then
			return { ok = false, reason = chargeErr or "InsufficientCash" }
		end
	end

	-- Update profile
	self.DataService:SetValue(player, "Progression.SpeedTier", tierIndex)

	-- Sync deltas: SpeedBoost (the actual bonus number) + SpeedTier (for UI)
	local speedBonus = tonumber(tier.SpeedBonus) or 0
	if self.Net then
		self.Net:QueueDelta(player, "SpeedBoost", speedBonus)
		self.Net:QueueDelta(player, "SpeedTier", tierIndex)
		self.Net:FlushDelta(player)
	end

	return { ok = true, tierIndex = tierIndex, speedBonus = speedBonus }
end

-- ── Buy Armor ───────────────────────────────────────────────────────────────

function ShopService:_handleBuyArmor(player: Player, payload: any)
	local tierIndex = tonumber(payload.tierIndex)
	if not tierIndex then
		return { ok = false, reason = "MissingTierIndex" }
	end

	local tiers = ArmorConfig and ArmorConfig.Tiers
	if not tiers then
		return { ok = false, reason = "NoArmorConfig" }
	end

	local tier = tiers[tierIndex]
	if not tier then
		return { ok = false, reason = "InvalidTier" }
	end

	-- Sequential: must buy the next tier in order
	local currentTier = self.DataService:GetValue(player, "Defense.ArmorTier") or 0
	if tierIndex ~= currentTier + 1 then
		return { ok = false, reason = "WrongTier" }
	end

	-- Charge
	local price = tonumber(tier.Price) or 0
	if price > 0 then
		local chargeOk, chargeErr = self.Economy:SpendCash(player, price)
		if not chargeOk then
			return { ok = false, reason = chargeErr or "InsufficientCash" }
		end
	end

	-- Update ArmorTier in profile
	self.DataService:SetValue(player, "Defense.ArmorTier", tierIndex)

	-- Set MaxArmor via ArmorService (also fills armor to new max)
	local armorBonus = tonumber(tier.ArmorBonus) or 0
	if self.ArmorService then
		self.ArmorService:SetMaxArmor(player, armorBonus)
		self.ArmorService:ReplenishArmor(player)
	end

	-- Sync ArmorTier delta for UI (Armor + MaxArmor already synced by ArmorService)
	if self.Net then
		self.Net:QueueDelta(player, "ArmorTier", tierIndex)
		self.Net:FlushDelta(player)
	end

	return { ok = true, tierIndex = tierIndex, armorBonus = armorBonus }
end

-- ── Legacy weapon station purchase ──────────────────────────────────────────

function ShopService:_handleWeaponStation(player, payload)
	local key = payload.key or payload.stationKey or payload.stationId
	local toolName = payload.toolName
	local price = payload.price
	local accept = payload.accept

	if typeof(accept) ~= "boolean" then
		accept = true
	end

	if not accept then
		return { ok = true, reason = "Cancelled" }
	end

	local station = (typeof(key) == "string" and self._stationByKey[key]) or nil
	if station then
		local tn, pr = readStationConfig(station)
		if typeof(tn) == "string" and tn ~= "" then toolName = tn end
		if typeof(pr) == "number" then price = pr end
	end

	if typeof(toolName) ~= "string" or toolName == "" then
		return { ok = false, reason = "MissingToolName" }
	end

	price = tonumber(price) or 0
	if price < 0 then price = 0 end

	if self.Inventory and self.Inventory.OwnsWeapon and self.Inventory:OwnsWeapon(player, toolName) then
		if self.Net and self.Net.Notify then
			self.Net:Notify(player, "You already own this weapon.")
		end
		return { ok = true, reason = "AlreadyOwned" }
	end

	if self.Economy and self.Economy.SpendCash then
		local ok, err = self.Economy:SpendCash(player, price)
		if not ok then
			if self.Net and self.Net.Notify then
				self.Net:Notify(player, "Not enough cash.")
			end
			return { ok = false, reason = err or "InsufficientFunds" }
		end
	end

	if self.Inventory and self.Inventory.GrantTool then
		local ok, err = self.Inventory:GrantTool(player, toolName)
		if not ok then
			if self.Economy and self.Economy.AddCash and price > 0 then
				self.Economy:AddCash(player, price, "RefundShopGrantFail")
			end
			return { ok = false, reason = err or "GrantFailed" }
		end
	end

	if self.Net and self.Net.Notify then
		self.Net:Notify(player, ("Purchased %s!"):format(toolName))
	end

	return { ok = true, reason = "Purchased" }
end

-- ── Weapon station scanning (existing) ──────────────────────────────────────

function ShopService:_keyForStation(station)
	return station:GetAttribute("StationId") or station:GetFullName()
end

function ShopService:_sendBuyPrompt(player, station, toolName, price)
	if not self.Net then return end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end

	if self.Net.SendPrompt then
		self.Net:SendPrompt(player, {
			kind = "ShopPurchase",
			key = self:_keyForStation(station),
			title = "Buy Weapon?",
			body = string.format("Buy %s for $%d?", tostring(toolName), tonumber(price) or 0),
			data = { toolName = toolName, price = price },
		})
	elseif self.Net.Notify then
		self.Net:Notify(player, ("Open shop to buy %s ($%d)"):format(tostring(toolName), tonumber(price) or 0))
	end
end

function ShopService:_bindStation(station)
	local toolName, price = readStationConfig(station)
	if typeof(toolName) ~= "string" or toolName == "" then return end
	if typeof(price) ~= "number" then price = tonumber(price) or 0 end
	if price < 0 then price = 0 end

	local prompt = ensurePrompt(station)
	if not prompt then return end

	prompt.ActionText = "Buy"
	prompt.ObjectText = toolName

	local key = self:_keyForStation(station)
	self._stationByKey[key] = station

	if self._promptDebounce[key] == nil then
		self._promptDebounce[key] = {}
	end

	prompt.Triggered:Connect(function(player)
		local t = os.clock()
		local last = self._promptDebounce[key][player] or 0
		if t - last < 0.5 then return end
		self._promptDebounce[key][player] = t

		self:_sendBuyPrompt(player, station, toolName, price)
	end)
end

function ShopService:_scanStations()
	if not self.StationsFolder then return end

	for _, obj in ipairs(self.StationsFolder:GetChildren()) do
		self:_bindStation(obj)
	end

	self.StationsFolder.ChildAdded:Connect(function(child)
		task.defer(function()
			self:_bindStation(child)
		end)
	end)
end

return ShopService
