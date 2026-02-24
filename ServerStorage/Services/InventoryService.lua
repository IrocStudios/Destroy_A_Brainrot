--!strict
local ServerStorage = game:GetService("ServerStorage")

local InventoryService = {}

local function findOrCreateOwnedList(profile)
	profile.Inventory = profile.Inventory or {}
	profile.Inventory.WeaponsOwned = profile.Inventory.WeaponsOwned or {}
	return profile.Inventory.WeaponsOwned
end

local function listHas(list, value: string): boolean
	for _, v in ipairs(list) do
		if v == value then return true end
	end
	return false
end

local function listRemove(list, value: string)
	for i = #list, 1, -1 do
		if list[i] == value then
			table.remove(list, i)
			return true
		end
	end
	return false
end

function InventoryService:Init(services)
	self.Services = services
	self.DataService = services.DataService
	self.NetService = services.NetService

	self.WeaponsFolder = ServerStorage:FindFirstChild("Weapons")
end

function InventoryService:Start()
	-- ensure folder ref updated if created later
	if not self.WeaponsFolder then
		self.WeaponsFolder = ServerStorage:WaitForChild("Weapons")
	end
end

function InventoryService:_getToolTemplate(toolName: string): Tool?
	if not self.WeaponsFolder then return nil end
	local inst = self.WeaponsFolder:FindFirstChild(toolName)
	if inst and inst:IsA("Tool") then
		return inst
	end
	return nil
end

function InventoryService:OwnsWeapon(player: Player, weaponName: string): boolean
	local owned = self.DataService:GetValue(player, "Inventory.WeaponsOwned")
	if typeof(owned) ~= "table" then return false end
	return listHas(owned, weaponName)
end

function InventoryService:GrantTool(player: Player, toolName: string)
	local template = self:_getToolTemplate(toolName)
	if not template then
		return false, "ToolMissingInServerStorage"
	end

	local alreadyOwned = false
	local ownedListCopy = nil

	self.DataService:Update(player, function(profile)
		local list = findOrCreateOwnedList(profile)
		alreadyOwned = listHas(list, toolName)
		if not alreadyOwned then
			table.insert(list, toolName)
		end
		ownedListCopy = list
		return profile
	end)

	if not alreadyOwned and self.NetService then
		self.NetService:QueueDelta(player, "WeaponsOwned", ownedListCopy)
		self.NetService:FlushDelta(player)
	end

	return true
end

function InventoryService:RemoveTool(player: Player, toolName: string)
	local removed = false
	local ownedListCopy = nil
	local equippedName: string? = nil

	self.DataService:Update(player, function(profile)
		local list = findOrCreateOwnedList(profile)
		removed = listRemove(list, toolName)
		ownedListCopy = list

		profile.Inventory.EquippedWeapon = profile.Inventory.EquippedWeapon
		if profile.Inventory.EquippedWeapon == toolName then
			profile.Inventory.EquippedWeapon = ""
		end
		equippedName = profile.Inventory.EquippedWeapon
		return profile
	end)

	-- remove physical instances if present
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		local t = backpack:FindFirstChild(toolName)
		if t and t:IsA("Tool") then t:Destroy() end
	end
	local char = player.Character
	if char then
		local t = char:FindFirstChild(toolName)
		if t and t:IsA("Tool") then t:Destroy() end
	end

	if removed and self.NetService then
		self.NetService:QueueDelta(player, "WeaponsOwned", ownedListCopy)
		self.NetService:QueueDelta(player, "EquippedWeapon", equippedName or "")
		self.NetService:FlushDelta(player)
	end

	return removed
end

function InventoryService:EquipWeapon(player: Player, weaponName: string)
	-- must own first
	if weaponName ~= "" and not self:OwnsWeapon(player, weaponName) then
		return false, "NotOwned"
	end

	-- remove currently equipped physical tools (optional safety)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false, "NoBackpack"
	end

	-- If weaponName empty => unequip
	if weaponName == "" then
		self.DataService:SetValue(player, "Inventory.EquippedWeapon", "")
		if self.NetService then
			self.NetService:QueueDelta(player, "EquippedWeapon", "")
			self.NetService:FlushDelta(player)
		end
		return true
	end

	local template = self:_getToolTemplate(weaponName)
	if not template then
		return false, "ToolMissingInServerStorage"
	end

	-- destroy duplicates of same tool before cloning
	local existing = backpack:FindFirstChild(weaponName)
	if existing and existing:IsA("Tool") then
		existing:Destroy()
	end
	local char = player.Character
	if char then
		local ex2 = char:FindFirstChild(weaponName)
		if ex2 and ex2:IsA("Tool") then
			ex2:Destroy()
		end
	end

	local clone = template:Clone()
	clone.Parent = backpack

	self.DataService:SetValue(player, "Inventory.EquippedWeapon", weaponName)

	if self.NetService then
		self.NetService:QueueDelta(player, "EquippedWeapon", weaponName)
		self.NetService:FlushDelta(player)
	end

	return true
end

return InventoryService