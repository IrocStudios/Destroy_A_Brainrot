--!strict
-- BackpackModule.lua  |  Frame: Backpack
-- Displays all weapons the player owns. Each card can be toggled to
-- select / deselect the weapon in the toolbar. Selection is persisted.
--
-- Data source: ReplicatedStorage/Weapons/<FolderName> folders
--   - @DisplayName (string), @Damage (number), @Rarity (1-6), @Category ("Normal"/"Gold"/"Diamond")
--   - Tool [Tool] child — the actual equippable tool
--   - Icon [ImageLabel] child — card icon
--
-- State: ctx.State.State.Inventory.WeaponsOwned  (array of folder names)
--        ctx.State.State.Inventory.SelectedWeapons (array of folder names)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local BackpackModule = {}
BackpackModule.__index = BackpackModule

-- ── Rarity gradient helper ──────────────────────────────────────────────────
local _rarityConfigInst = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RarityConfig")

local TEXTLABEL_DARKEN = 0.85 -- 15% darker on TextLabels

local function darkenColorSequence(cs: ColorSequence, factor: number): ColorSequence
	local kps = {}
	for _, kp in ipairs(cs.Keypoints) do
		local c = kp.Value
		table.insert(kps, ColorSequenceKeypoint.new(kp.Time,
			Color3.new(c.R * factor, c.G * factor, c.B * factor)))
	end
	return ColorSequence.new(kps)
end

local CollectionService = game:GetService("CollectionService")

local function applyRarityGradients(parent: Instance, rarityName: string)
	local isTranscendent = rarityName == "Transcendent"
	for _, desc in parent:GetDescendants() do
		if desc:IsA("UIGradient") then
			if desc.Name == "RarityGradient" then
				local source = _rarityConfigInst:FindFirstChild(rarityName)
				if source and source:IsA("UIGradient") then
					local color = source.Color
					if desc.Parent and desc.Parent:IsA("TextLabel") then
						color = darkenColorSequence(color, TEXTLABEL_DARKEN)
					end
					desc.Color = color
				end
				if isTranscendent then
					CollectionService:AddTag(desc, "RainbowGradient")
				else
					CollectionService:RemoveTag(desc, "RainbowGradient")
				end
			elseif desc.Name == "RarityGradientStroke" then
				local source = _rarityConfigInst:FindFirstChild(rarityName .. "Stroke")
				if source and source:IsA("UIGradient") then
					desc.Color = source.Color
				end
				if isTranscendent then
					CollectionService:AddTag(desc, "RainbowGradient")
					desc.Rotation = 90
				else
					CollectionService:RemoveTag(desc, "RainbowGradient")
				end
			end
		end
	end
end

-- ── Constants ─────────────────────────────────────────────────────────────────
local ITEMS_PER_ROW = 3

local RARITY_NAMES = {
	[1] = "Common",
	[2] = "Uncommon",
	[3] = "Rare",
	[4] = "Epic",
	[5] = "Legendary",
	[6] = "Mythic",
	[7] = "Transcendent",
}

-- Category attribute value → tab button name in ButtonsContainer
local CATEGORY_MAP = {
	Normal  = { button = "Normal"  },
	Gold    = { button = "Golden"  },
	Diamond = { button = "Diamond" },
}

-- Notification badge animation durations
local NOTIF_POP_DURATION    = 0.35
local NOTIF_SETTLE_DURATION = 0.15

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getRarityName(numericRarity: number?): string
	return RARITY_NAMES[numericRarity or 1] or "Common"
end

local function getRarityColor(ctx: any, rarityName: string): Color3
	local rarCfg = ctx.Config and ctx.Config.RarityConfig
	if rarCfg and rarCfg.Rarities and rarCfg.Rarities[rarityName] then
		return rarCfg.Rarities[rarityName].Color
	end
	return Color3.fromRGB(190, 190, 190)
end

local function getOwnedSet(ctx: any): { [string]: boolean }
	local inv = ctx.State and ctx.State.State and ctx.State.State.Inventory or {}
	local raw = inv.WeaponsOwned or {}
	local set: { [string]: boolean } = {}
	if type(raw) == "table" then
		for _, v in ipairs(raw) do
			if type(v) == "string" then
				set[v] = true
			end
		end
	end
	return set
end

local function getSelectedSet(ctx: any): { [string]: boolean }
	local inv = ctx.State and ctx.State.State and ctx.State.State.Inventory or {}
	local raw = inv.SelectedWeapons or {}
	local set: { [string]: boolean } = {}
	if type(raw) == "table" then
		for _, v in ipairs(raw) do
			if type(v) == "string" then
				set[v] = true
			end
		end
	end
	return set
end

local function getOwnedList(ctx: any): { string }
	local inv = ctx.State and ctx.State.State and ctx.State.State.Inventory or {}
	local raw = inv.WeaponsOwned or {}
	if type(raw) == "table" then return raw end
	return {}
end

--- Collect weapon metadata from ReplicatedStorage/Weapons, grouped by category
local function collectWeapons(): { [string]: { any } }
	local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
	if not weaponsFolder then
		warn("[BackpackModule] ReplicatedStorage/Weapons not found")
		return {}
	end

	local grouped: { [string]: { any } } = {
		Normal  = {},
		Gold    = {},
		Diamond = {},
	}

	for _, folder in weaponsFolder:GetChildren() do
		if not folder:IsA("Folder") then continue end

		local displayName = folder:GetAttribute("DisplayName") or folder.Name
		local damage      = folder:GetAttribute("Damage") or 0
		local rarity      = folder:GetAttribute("Rarity") or 1
		local category    = folder:GetAttribute("Category") or "Normal"

		if not grouped[category] then
			category = "Normal" -- fallback
		end

		-- Icon image
		local icon = folder:FindFirstChild("Icon")
		local iconImage = icon and icon:IsA("ImageLabel") and icon.Image or ""

		-- Find Tool child name
		local toolName = nil
		for _, child in folder:GetChildren() do
			if child:IsA("Tool") then
				toolName = child.Name
				break
			end
		end

		table.insert(grouped[category], {
			key = folder.Name,      -- weapon folder name (used in data arrays)
			displayName = displayName,
			damage = damage,
			rarity = rarity,
			rarityName = getRarityName(rarity),
			category = category,
			iconImage = iconImage,
			toolName = toolName,
		})
	end

	-- Sort: rarity descending, then display name ascending
	for _, list in grouped do
		table.sort(list, function(a, b)
			if a.rarity ~= b.rarity then return a.rarity > b.rarity end
			return a.displayName < b.displayName
		end)
	end

	return grouped
end

-- ── Populate ──────────────────────────────────────────────────────────────────

function BackpackModule:_clearContainer()
	local container = self._container
	if not container then return end
	for _, child in container:GetChildren() do
		if child:IsA("Frame") and child.Name ~= "_bumpertop" and child.Name ~= "_bumperbottom" then
			child:Destroy()
		end
	end
end

function BackpackModule:_buildCard(data: any, isSelected: boolean): TextButton
	local ctx = self._ctx
	local card = self._resources.Template_Weapon:Clone()
	card.Visible = true
	card.Name = data.key

	local container = card:FindFirstChild("container")
	if container then
		-- Title + shadow
		local title = container:FindFirstChild("Title")
		if title and title:IsA("TextLabel") then
			title.Text = data.displayName
			local shadow = title:FindFirstChild("Title2")
			if shadow and shadow:IsA("TextLabel") then
				shadow.Text = data.displayName
			end
		end

		-- Rarity + shadow + color
		local rarLabel = container:FindFirstChild("Rarity")
		if rarLabel and rarLabel:IsA("TextLabel") then
			rarLabel.Text = data.rarityName
			rarLabel.TextColor3 = getRarityColor(ctx, data.rarityName)
			local shadow = rarLabel:FindFirstChild("Rarity2")
			if shadow and shadow:IsA("TextLabel") then
				shadow.Text = data.rarityName
			end
		end

		-- Rarity gradients (fill + stroke)
		applyRarityGradients(container, data.rarityName)

		-- Damage + shadow
		local dmgLabel = container:FindFirstChild("Damage")
		if dmgLabel and dmgLabel:IsA("TextLabel") then
			dmgLabel.Text = tostring(data.damage)
			local shadow = dmgLabel:FindFirstChild("Damage2")
			if shadow and shadow:IsA("TextLabel") then
				shadow.Text = tostring(data.damage)
			end
		end

		-- Icon
		local iconHolder = container:FindFirstChild("IconHolder")
		if iconHolder then
			local img = iconHolder:FindFirstChild("x")
			if img and img:IsA("ImageLabel") then
				img.Image = data.iconImage
				img.Visible = true
			end
		end

		-- Selected frame
		local selected = container:FindFirstChild("Selected")
		if selected and selected:IsA("GuiObject") then
			selected.Visible = isSelected
		end

		-- New label (default hidden; set visible externally for new weapons)
		local newLabel = container:FindFirstChild("newlabel")
		if newLabel and newLabel:IsA("GuiObject") then
			newLabel.Visible = false
		end
	end

	-- Store weapon reference in ObjectValue
	local brainrotVal = card:FindFirstChild("Brainrot")
	if brainrotVal and brainrotVal:IsA("ObjectValue") then
		local weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")
		if weaponsFolder then
			local folder = weaponsFolder:FindFirstChild(data.key)
			if folder then
				brainrotVal.Value = folder
			end
		end
	end

	-- Click handler: toggle select/deselect
	card.MouseButton1Click:Connect(function()
		self:_toggleWeapon(data.key)
	end)

	return card
end

function BackpackModule:_populateContainer()
	self:_clearContainer()

	local ownedSet = getOwnedSet(self._ctx)
	local selectedSet = getSelectedSet(self._ctx)
	local category = self._activeTab or "Normal"

	local weaponList = self._weaponGrouped[category] or {}
	local holderTemplate = self._resources.Holder

	local currentHolder: Frame? = nil
	local countInRow = 0

	for _, data in weaponList do
		-- Only show weapons the player owns
		if not ownedSet[data.key] then continue end

		-- Need a new holder row?
		if countInRow == 0 or countInRow >= ITEMS_PER_ROW then
			currentHolder = holderTemplate:Clone()
			currentHolder.Visible = true
			currentHolder.Name = "Row"
			currentHolder.Parent = self._container
			countInRow = 0
		end

		local isSelected = selectedSet[data.key] == true
		local card = self:_buildCard(data, isSelected)

		-- Show "New!" label if this weapon is newly acquired
		if self._newKeys[data.key] then
			local cont = card:FindFirstChild("container")
			if cont then
				local nl = cont:FindFirstChild("newlabel")
				if nl and nl:IsA("GuiObject") then
					nl.Visible = true
				end
			end
		end

		card.Parent = currentHolder
		countInRow += 1
	end
end

-- ── Toggle weapon select/deselect ─────────────────────────────────────────────

function BackpackModule:_toggleWeapon(weaponKey: string)
	local selectedSet = getSelectedSet(self._ctx)
	local isCurrentlySelected = selectedSet[weaponKey] == true

	local action = isCurrentlySelected and "deselect" or "select"

	-- Invoke server via WeaponAction RF
	local rf = self._ctx.Net:GetFunction("WeaponAction")
	if not rf then
		warn("[BackpackModule] WeaponAction RF not found")
		return
	end

	task.spawn(function()
		local ok, result = pcall(function()
			return rf:InvokeServer({ action = action, weapon = weaponKey })
		end)
		if not ok then
			warn("[BackpackModule] WeaponAction error:", result)
		elseif type(result) == "table" and not result.ok then
			warn("[BackpackModule] WeaponAction failed:", result.reason)
		end
		-- UI updates reactively via State.Changed → _populateContainer
	end)
end

-- ── Tab switching ────────────────────────────────────────────────────────────

function BackpackModule:_switchTab(categoryKey: string)
	self._activeTab = categoryKey
	self:_populateContainer()
end

-- ── Notification badge ──────────────────────────────────────────────────────

function BackpackModule:_findNotification()
	local hud = self._ctx.RootGui:FindFirstChild("HUD")
	if not hud then return nil end
	local bpBtn = hud:FindFirstChild("Backpack", true)
	if not bpBtn then return nil end
	local frame = bpBtn:FindFirstChild("Frame")
	if not frame then return nil end
	return frame:FindFirstChild("Notification")
end

function BackpackModule:_setNotifText(count: number)
	local notif = self._notifFrame
	if not notif then return end
	local inner = notif:FindFirstChild("Frame")
	if not inner then return end
	local title = inner:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = tostring(count)
		-- Shadow title (nested Title inside Title)
		local shadow = title:FindFirstChild("Title")
		if shadow and shadow:IsA("TextLabel") then
			shadow.Text = tostring(count)
		end
	end
end

function BackpackModule:_popNotification()
	local notif = self._notifFrame
	if not notif then return end

	local uiScale = notif:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = notif
	end

	notif.Visible = true
	uiScale.Scale = 0
	notif.Rotation = 0

	-- Phase 1: pop up to 1.3 + 360 spin
	local popTween = TweenService:Create(uiScale,
		TweenInfo.new(NOTIF_POP_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.3 }
	)
	local spinTween = TweenService:Create(notif,
		TweenInfo.new(NOTIF_POP_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Rotation = 360 }
	)

	popTween:Play()
	spinTween:Play()

	-- Phase 2: settle to 1
	popTween.Completed:Once(function()
		TweenService:Create(uiScale,
			TweenInfo.new(NOTIF_SETTLE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
		task.delay(NOTIF_SETTLE_DURATION, function()
			notif.Rotation = 0
		end)
	end)
end

function BackpackModule:_bumpNotification()
	self._notifCount = (self._notifCount or 0) + 1
	self:_setNotifText(self._notifCount)
	self:_popNotification()
end

function BackpackModule:_clearNotification()
	self._notifCount = 0
	if self._notifFrame then
		local uiScale = self._notifFrame:FindFirstChildOfClass("UIScale")
		if uiScale then
			uiScale.Scale = 0
		end
		self._notifFrame.Visible = false
	end
end

--- Hide "New!" labels on all cards that were flagged
function BackpackModule:_clearNewLabels()
	if not self._newKeys then return end

	-- Walk all Holder rows in the Container
	if self._container then
		for _, holder in self._container:GetChildren() do
			if not holder:IsA("Frame") then continue end
			for _, card in holder:GetChildren() do
				if not card:IsA("TextButton") then continue end
				local cont = card:FindFirstChild("container")
				if cont then
					local nl = cont:FindFirstChild("newlabel")
					if nl and nl:IsA("GuiObject") then
						nl.Visible = false
					end
				end
			end
		end
	end

	self._newKeys = {}
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function BackpackModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Backpack")
	if not self._frame then warn("[BackpackModule] Frame 'Backpack' not found") return end

	self._resources = self._frame:FindFirstChild("resources")
	if not self._resources then warn("[BackpackModule] resources folder not found in Backpack") return end

	self._container = self._frame:FindFirstChild("Container")
	if not self._container then warn("[BackpackModule] Container not found in Backpack") return end

	self._activeTab  = "Normal"
	self._notifCount = 0
	self._newKeys    = {} :: { [string]: boolean }
	self._notifFrame = self:_findNotification()
	if self._notifFrame then
		self._notifFrame.Visible = false
	end

	-- Collect all weapon data (grouped by category)
	self._weaponGrouped = collectWeapons()
	-- Flat lookup by key
	self._weaponData = {}
	for _, list in self._weaponGrouped do
		for _, data in list do
			self._weaponData[data.key] = data
		end
	end

	-- Close button
	local closeBtn = self._frame:FindFirstChild("XButton")
	if closeBtn and closeBtn:IsA("GuiButton") then
		self._janitor:Add(closeBtn.MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("Backpack") end
		end))
	end

	-- Watch UIScale for open/close detection (Router uses UIScale)
	local frameUIScale = self._frame:FindFirstChildOfClass("UIScale")
	if frameUIScale then
		local wasOpen = false
		self._janitor:Add(frameUIScale:GetPropertyChangedSignal("Scale"):Connect(function()
			local isOpen = frameUIScale.Scale > 0.01
			if isOpen and not wasOpen then
				-- Frame just opened
				self:_clearNotification()
			elseif not isOpen and wasOpen then
				-- Frame just closed
				self:_clearNewLabels()
			end
			wasOpen = isOpen
		end))
	end

	-- Tab buttons
	local buttonsContainer = self._frame:FindFirstChild("ButtonsContainer")
	if buttonsContainer then
		for categoryKey, mapping in CATEGORY_MAP do
			local btn = buttonsContainer:FindFirstChild(mapping.button)
			if btn and btn:IsA("GuiButton") then
				self._janitor:Add(btn.MouseButton1Click:Connect(function()
					self:_switchTab(categoryKey)
				end))
			end
		end
	end

	-- Initial populate
	self:_populateContainer()

	-- Show Normal tab by default
	self:_switchTab("Normal")
end

function BackpackModule:Start()
	if not self._frame then return end

	-- Track previous owned set to detect new weapons
	local prevOwned = getOwnedSet(self._ctx)

	self._janitor:Add(self._ctx.State.Changed:Connect(function(_state, _deltas)
		-- Check for new weapons (for "New!" labels only)
		local newOwned = getOwnedSet(self._ctx)
		for key in pairs(newOwned) do
			if not prevOwned[key] then
				self._newKeys[key] = true
			end
		end
		prevOwned = newOwned

		-- Rebuild current tab (handles both ownership and selection changes)
		self:_populateContainer()
	end))

	-- Bump notification badge on every purchase (new or not)
	local notifyRE = self._ctx.Net:GetEvent("Notify")
	self._janitor:Add(notifyRE.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.type == "purchased" then
			self:_bumpNotification()
		end
	end))
end

function BackpackModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return BackpackModule
