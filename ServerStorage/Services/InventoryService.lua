--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local InventoryService = {}

local MAX_SELECTED = 5 -- max weapons in toolbar at once

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function findOrCreateOwnedList(profile)
	profile.Inventory = profile.Inventory or {}
	profile.Inventory.WeaponsOwned = profile.Inventory.WeaponsOwned or {}
	return profile.Inventory.WeaponsOwned
end

local function findOrCreateSelectedList(profile)
	profile.Inventory = profile.Inventory or {}
	profile.Inventory.SelectedWeapons = profile.Inventory.SelectedWeapons or {}
	return profile.Inventory.SelectedWeapons
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

-- ── Lifecycle ────────────────────────────────────────────────────────────────

function InventoryService:Init(services)
	self.Services = services
	self.DataService = services.DataService
	self.NetService = services.NetService
	self.EconomyService = services.EconomyService

	self.WeaponsFolder = ServerStorage:FindFirstChild("Weapons")
	self.RSWeaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
	print("[InventoryService] Init OK. RSWeapons=" .. tostring(self.RSWeaponsFolder))
end

function InventoryService:Start()
	-- ensure folder refs
	if not self.WeaponsFolder then
		self.WeaponsFolder = ServerStorage:WaitForChild("Weapons", 5)
	end
	if not self.RSWeaponsFolder then
		self.RSWeaponsFolder = ReplicatedStorage:WaitForChild("Weapons", 5)
	end

	print("[InventoryService] Start OK. RSWeapons=" .. tostring(self.RSWeaponsFolder))

	-- Grant selected weapons on every spawn/respawn
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				self:GrantSelectedWeapons(player)
			end)
		end)
	end)
	-- Handle players already in game
	for _, player in ipairs(Players:GetPlayers()) do
		player.CharacterAdded:Connect(function()
			task.defer(function()
				self:GrantSelectedWeapons(player)
			end)
		end)
		-- If character already exists
		if player.Character then
			task.defer(function()
				self:GrantSelectedWeapons(player)
			end)
		end
	end
end

-- ── Tool template lookup ────────────────────────────────────────────────────

--- Find the Tool child inside a weapon folder in ReplicatedStorage/Weapons
function InventoryService:_getWeaponTool(weaponKey: string): Tool?
	if not self.RSWeaponsFolder then return nil end
	local folder = self.RSWeaponsFolder:FindFirstChild(weaponKey)
	if not folder then return nil end
	-- Find the first Tool child inside the folder
	for _, child in folder:GetChildren() do
		if child:IsA("Tool") then
			return child
		end
	end
	return nil
end

--- Legacy: find Tool directly in ServerStorage/Weapons by name
function InventoryService:_getToolTemplate(toolName: string): Tool?
	if not self.WeaponsFolder then return nil end
	local inst = self.WeaponsFolder:FindFirstChild(toolName)
	if inst and inst:IsA("Tool") then
		return inst
	end
	return nil
end

-- ── Ownership ───────────────────────────────────────────────────────────────

function InventoryService:OwnsWeapon(player: Player, weaponName: string): boolean
	local owned = self.DataService:GetValue(player, "Inventory.WeaponsOwned")
	if typeof(owned) ~= "table" then return false end
	return listHas(owned, weaponName)
end

function InventoryService:GrantTool(player: Player, toolName: string)
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
	local selectedListCopy = nil

	self.DataService:Update(player, function(profile)
		local list = findOrCreateOwnedList(profile)
		removed = listRemove(list, toolName)
		ownedListCopy = list

		-- Also remove from SelectedWeapons if present
		local selected = findOrCreateSelectedList(profile)
		listRemove(selected, toolName)
		selectedListCopy = selected

		profile.Inventory.EquippedWeapon = profile.Inventory.EquippedWeapon
		if profile.Inventory.EquippedWeapon == toolName then
			profile.Inventory.EquippedWeapon = ""
		end
		return profile
	end)

	-- Remove physical instances if present
	self:_destroyWeaponInstances(player, toolName)

	if removed and self.NetService then
		self.NetService:QueueDelta(player, "WeaponsOwned", ownedListCopy)
		self.NetService:QueueDelta(player, "SelectedWeapons", selectedListCopy)
		self.NetService:FlushDelta(player)
	end

	return removed
end

-- ── Weapon select/deselect (Backpack UI) ────────────────────────────────────

function InventoryService:HandleWeaponAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return { ok = false, reason = "BadPayload" }
	end

	local action = tostring(payload.action or "")
	local weaponKey = tostring(payload.weapon or "")

	if weaponKey == "" then
		return { ok = false, reason = "MissingWeapon" }
	end

	if action == "select" then
		return self:_selectWeapon(player, weaponKey)
	elseif action == "deselect" then
		return self:_deselectWeapon(player, weaponKey)
	elseif action == "buy" then
		local cost = tonumber(payload.cost) or 0
		return self:_buyWeapon(player, weaponKey, cost)
	end

	return { ok = false, reason = "UnknownAction" }
end

function InventoryService:_selectWeapon(player: Player, weaponKey: string)
	-- Must own the weapon
	if not self:OwnsWeapon(player, weaponKey) then
		return { ok = false, reason = "NotOwned" }
	end

	-- Check toolbar limit — if full, bump the last slot to make room
	local currentSelected = self.DataService:GetValue(player, "Inventory.SelectedWeapons")
	if typeof(currentSelected) == "table"
		and #currentSelected >= MAX_SELECTED
		and not listHas(currentSelected, weaponKey)
	then
		local lastKey = currentSelected[#currentSelected]
		if lastKey then
			self:_deselectWeapon(player, lastKey)
		end
	end

	-- Find the Tool template
	local toolTemplate = self:_getWeaponTool(weaponKey)
	if not toolTemplate then
		return { ok = false, reason = "ToolNotFound" }
	end

	local selectedListCopy = nil

	self.DataService:Update(player, function(profile)
		local selected = findOrCreateSelectedList(profile)
		if not listHas(selected, weaponKey) then
			table.insert(selected, weaponKey)
		end
		selectedListCopy = selected
		return profile
	end)

	-- Clone tool into player's Roblox Backpack
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		-- Remove duplicate if exists
		self:_destroyWeaponInstances(player, nil, toolTemplate.Name)
		local clone = toolTemplate:Clone()
		clone.Parent = backpack
	end

	if self.NetService then
		self.NetService:QueueDelta(player, "SelectedWeapons", selectedListCopy)
		self.NetService:FlushDelta(player)
	end

	return { ok = true }
end

function InventoryService:_deselectWeapon(player: Player, weaponKey: string)
	local selectedListCopy = nil

	self.DataService:Update(player, function(profile)
		local selected = findOrCreateSelectedList(profile)
		listRemove(selected, weaponKey)
		selectedListCopy = selected
		return profile
	end)

	-- Find the tool name from the weapon folder to destroy instances
	local toolTemplate = self:_getWeaponTool(weaponKey)
	if toolTemplate then
		self:_destroyWeaponInstances(player, nil, toolTemplate.Name)
	end

	if self.NetService then
		self.NetService:QueueDelta(player, "SelectedWeapons", selectedListCopy)
		self.NetService:FlushDelta(player)
	end

	return { ok = true }
end

-- ── Buy weapon ──────────────────────────────────────────────────────────────

function InventoryService:_buyWeapon(player: Player, weaponKey: string, cost: number)
	-- Validate weapon exists
	if not self.RSWeaponsFolder or not self.RSWeaponsFolder:FindFirstChild(weaponKey) then
		return { ok = false, reason = "InvalidWeapon" }
	end

	-- Always charge (even re-purchases)
	if not self.EconomyService then
		return { ok = false, reason = "ServerError" }
	end
	if cost <= 0 then
		return { ok = false, reason = "InvalidCost" }
	end
	local chargeOk, chargeErr = self.EconomyService:SpendCash(player, cost)
	if not chargeOk then
		return { ok = false, reason = "InsufficientCash" }
	end

	-- Grant weapon (always adds to WeaponsOwned, even duplicates)
	local isNew = not self:OwnsWeapon(player, weaponKey)
	local ownedListCopy = nil
	self.DataService:Update(player, function(profile)
		local list = findOrCreateOwnedList(profile)
		table.insert(list, weaponKey)
		ownedListCopy = list
		return profile
	end)
	if self.NetService then
		self.NetService:QueueDelta(player, "WeaponsOwned", ownedListCopy)
		self.NetService:FlushDelta(player)
	end

	print(("[InventoryService] %s purchased %s for $%d (isNew=%s)"):format(
		player.Name, weaponKey, cost, tostring(isNew)))

	-- Auto-select into toolbar if there's room and not already selected
	local selected = self.DataService:GetValue(player, "Inventory.SelectedWeapons")
	local count = (typeof(selected) == "table") and #selected or 0
	if count < MAX_SELECTED and not (typeof(selected) == "table" and listHas(selected, weaponKey)) then
		self:_selectWeapon(player, weaponKey)
	end

	-- Read weapon metadata for the notification
	local folder = self.RSWeaponsFolder:FindFirstChild(weaponKey)
	local displayName = folder and folder:GetAttribute("DisplayName") or weaponKey
	local rarity = folder and folder:GetAttribute("Rarity") or 1

	-- Fire notification to client
	if self.NetService then
		self.NetService:Notify(player, {
			type      = "purchased",
			weaponKey = weaponKey,
			isNew     = isNew,
			name      = displayName,
			rarity    = rarity,
		})
	end

	-- DEV: Grant all 6 test weapons for free on AK12 purchase
	if weaponKey == "AK12" then
		local testWeapons = { "testcommon", "testuncommon", "testrare", "testepic", "testlegendary", "testmythic" }
		for _, tw in ipairs(testWeapons) do
			if not self:OwnsWeapon(player, tw) then
				self:GrantTool(player, tw)
				print(("[InventoryService] DEV: Granted free %s to %s"):format(tw, player.Name))
			end
		end
	end

	return { ok = true, isNew = isNew }
end

-- ── Grant selected weapons on spawn ─────────────────────────────────────────

function InventoryService:GrantSelectedWeapons(player: Player)
	print("[InventoryService] GrantSelectedWeapons for " .. player.Name)
	local selectedRaw = self.DataService:GetValue(player, "Inventory.SelectedWeapons")
	if typeof(selectedRaw) ~= "table" then return end

	local ownedRaw = self.DataService:GetValue(player, "Inventory.WeaponsOwned")
	local ownedSet: { [string]: boolean } = {}
	if typeof(ownedRaw) == "table" then
		for _, v in ipairs(ownedRaw) do
			ownedSet[v] = true
		end
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end

	local staleKeys: { string } = {}

	for _, weaponKey in ipairs(selectedRaw) do
		-- Validate still owned
		if not ownedSet[weaponKey] then
			table.insert(staleKeys, weaponKey)
			continue
		end

		local toolTemplate = self:_getWeaponTool(weaponKey)
		if not toolTemplate then continue end

		-- Don't duplicate if already in backpack
		local existing = backpack:FindFirstChild(toolTemplate.Name)
		if existing and existing:IsA("Tool") then continue end

		-- Also check character
		local char = player.Character
		if char then
			local inChar = char:FindFirstChild(toolTemplate.Name)
			if inChar and inChar:IsA("Tool") then continue end
		end

		local clone = toolTemplate:Clone()
		clone.Parent = backpack
		print("[InventoryService] Granted tool: " .. clone.Name .. " for " .. player.Name)
	end

	-- Clean stale entries (weapons no longer owned but still in selected)
	if #staleKeys > 0 then
		local selectedListCopy = nil
		self.DataService:Update(player, function(profile)
			local selected = findOrCreateSelectedList(profile)
			for _, key in staleKeys do
				listRemove(selected, key)
			end
			selectedListCopy = selected
			return profile
		end)
		if self.NetService then
			self.NetService:QueueDelta(player, "SelectedWeapons", selectedListCopy)
			self.NetService:FlushDelta(player)
		end
	end
end

-- ── Legacy equip (single-weapon system) ─────────────────────────────────────

function InventoryService:EquipWeapon(player: Player, weaponName: string)
	if weaponName ~= "" and not self:OwnsWeapon(player, weaponName) then
		return false, "NotOwned"
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false, "NoBackpack"
	end

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

-- ── Utilities ───────────────────────────────────────────────────────────────

--- Destroy tool instances from player's Backpack and Character.
--- Pass weaponKey to look up the tool name, or pass toolName directly.
function InventoryService:_destroyWeaponInstances(player: Player, weaponKey: string?, toolName: string?)
	local name = toolName
	if not name and weaponKey then
		local tmpl = self:_getWeaponTool(weaponKey)
		if tmpl then name = tmpl.Name end
	end
	if not name then return end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		local t = backpack:FindFirstChild(name)
		if t and t:IsA("Tool") then t:Destroy() end
	end
	local char = player.Character
	if char then
		local t = char:FindFirstChild(name)
		if t and t:IsA("Tool") then t:Destroy() end
	end
end

return InventoryService
