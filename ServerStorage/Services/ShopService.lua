local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ShopService = {}
ShopService.__index = ShopService

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

function ShopService:Init(services)
	self.Services = services
	self.Net = services.NetService
	self.Economy = services.EconomyService
	self.Inventory = services.InventoryService

	self.StationsFolder = Workspace:FindFirstChild("WeaponStations")
	self._stationByKey = {}
	self._promptDebounce = {}
end

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

function ShopService:_handleShopAction(player, payload)
	if typeof(payload) ~= "table" then return false, "BadPayload" end

	local key = payload.key or payload.stationKey or payload.stationId
	local toolName = payload.toolName
	local price = payload.price
	local accept = payload.accept

	if typeof(accept) ~= "boolean" then
		accept = true
	end

	if not accept then
		return true, "Cancelled"
	end

	local station = (typeof(key) == "string" and self._stationByKey[key]) or nil
	if station then
		local tn, pr = readStationConfig(station)
		if typeof(tn) == "string" and tn ~= "" then toolName = tn end
		if typeof(pr) == "number" then price = pr end
	end

	if typeof(toolName) ~= "string" or toolName == "" then
		return false, "MissingToolName"
	end

	price = tonumber(price) or 0
	if price < 0 then price = 0 end

	if self.Inventory and self.Inventory.OwnsWeapon and self.Inventory:OwnsWeapon(player, toolName) then
		if self.Net and self.Net.Notify then
			self.Net:Notify(player, "You already own this weapon.")
		end
		return true, "AlreadyOwned"
	end

	if self.Economy and self.Economy.SpendCash then
		local ok, err = self.Economy:SpendCash(player, price)
		if not ok then
			if self.Net and self.Net.Notify then
				self.Net:Notify(player, "Not enough cash.")
			end
			return false, err or "InsufficientFunds"
		end
	end

	if self.Inventory and self.Inventory.GrantTool then
		local ok, err = self.Inventory:GrantTool(player, toolName)
		if not ok then
			if self.Economy and self.Economy.AddCash and price > 0 then
				self.Economy:AddCash(player, price, "RefundShopGrantFail")
			end
			return false, err or "GrantFailed"
		end
	end

	if self.Net and self.Net.Notify then
		self.Net:Notify(player, ("Purchased %s!"):format(toolName))
	end

	return true, "Purchased"
end

function ShopService:Start()
	self:_scanStations()

	if self.Net then
		if self.Net.RouteFunction then
			self.Net:RouteFunction("ShopAction", function(player, payload)
				return self:_handleShopAction(player, payload)
			end)
		elseif self.Net.BindFunction then
			self.Net:BindFunction("ShopAction", function(player, payload)
				return self:_handleShopAction(player, payload)
			end)
		elseif self.Net.RegisterFunction then
			self.Net:RegisterFunction("ShopAction", function(player, payload)
				return self:_handleShopAction(player, payload)
			end)
		end
	end
end

return ShopService