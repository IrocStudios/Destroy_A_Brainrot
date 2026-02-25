--!strict
-- IndexModule.lua  |  Frame: Index
-- Builds a categorised index of all brainrots (Normal / Golden / Diamond).
-- Each row is a Holder (up to 4 cards). Cards use Template_Locked or
-- Template_Unlocked depending on the player's discovered set.
--
-- Data source: ReplicatedStorage/Brainrots/<Name> folders
--   - Category attribute on the folder ("Normal" / "Gold" / "Diamond")
--   - Icon (ImageLabel) for unlocked icon
--   - Icon_Locked (ImageLabel) for locked silhouette
--   - Info (Configuration) with DisplayName, Rarity (1-6)
--
-- Discovery state: ctx.State.State.Index.BrainrotsDiscovered

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local IndexModule = {}
IndexModule.__index = IndexModule

-- ── Constants ───────────────────────────────────────────────────────────────
local ITEMS_PER_ROW = 4

-- Numeric rarity → display name (matches RarityConfig.DisplayOrder)
local RARITY_NAMES = {
	[1] = "Common",
	[2] = "Uncommon",
	[3] = "Rare",
	[4] = "Epic",
	[5] = "Legendary",
	[6] = "Mythic",
}

-- Category attribute value → container name / tab button name
local CATEGORY_MAP = {
	Normal  = { container = "Container",         button = "Normal"  },
	Gold    = { container = "Container_Gold",     button = "Golden"  },
	Diamond = { container = "Container_Diamond",  button = "Diamond" },
}

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function getDiscoveredSet(ctx: any): { [string]: boolean }
	local s = ctx.State and ctx.State.State or {}
	local raw = s.Index and s.Index.BrainrotsDiscovered or {}
	local set: { [string]: boolean } = {}
	if type(raw) == "table" then
		-- Support both array { "a", "b" } and map { a = true }
		for k, v in pairs(raw) do
			if type(v) == "string" then
				set[v] = true  -- array style
			elseif v == true then
				set[k] = true  -- map style
			end
		end
	end
	return set
end

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

--- Collect all brainrot folders from ReplicatedStorage/Brainrots, grouped by category.
--- Returns { Normal = { {folder, info, ...}, ... }, Gold = { ... }, Diamond = { ... } }
local function collectBrainrots(): { [string]: { any } }
	local brainrotsFolder = ReplicatedStorage:FindFirstChild("Brainrots")
	if not brainrotsFolder then
		warn("[IndexModule] ReplicatedStorage/Brainrots not found")
		return {}
	end

	local grouped: { [string]: { any } } = {
		Normal  = {},
		Gold    = {},
		Diamond = {},
	}

	for _, folder in brainrotsFolder:GetChildren() do
		local info = folder:FindFirstChild("Info")
		if not info then continue end

		local category = folder:GetAttribute("Category") or "Normal"
		if not grouped[category] then
			category = "Normal" -- fallback
		end

		local rarity = info:GetAttribute("Rarity") or 1
		local displayName = info:GetAttribute("DisplayName") or folder.Name

		-- Icon images
		local icon = folder:FindFirstChild("Icon")
		local iconLocked = folder:FindFirstChild("Icon_Locked")
		local iconImage = icon and icon:IsA("ImageLabel") and icon.Image or ""
		local lockedImage = iconLocked and iconLocked:IsA("ImageLabel") and iconLocked.Image or iconImage

		table.insert(grouped[category], {
			key = folder.Name,
			displayName = displayName,
			rarity = rarity,
			rarityName = getRarityName(rarity),
			iconImage = iconImage,
			lockedImage = lockedImage,
		})
	end

	-- Sort each category by rarity descending, then name ascending
	for _, list in grouped do
		table.sort(list, function(a, b)
			if a.rarity ~= b.rarity then return a.rarity > b.rarity end
			return a.displayName < b.displayName
		end)
	end

	return grouped
end

-- ── Populate ────────────────────────────────────────────────────────────────

function IndexModule:_clearContainer(container: ScrollingFrame)
	for _, child in container:GetChildren() do
		if child:IsA("Frame") and child.Name ~= "_bumpertop" and child.Name ~= "_bumperbottom" then
			child:Destroy()
		end
	end
end

function IndexModule:_buildCard(data: any, discovered: boolean): TextButton
	local ctx = self._ctx
	local resources = self._resources

	if discovered then
		local card = resources.Template_Unlocked:Clone()
		card.Visible = true
		card.Name = data.key

		-- Icon
		local iconHolder = card:FindFirstChild("container") and card.container:FindFirstChild("IconHolder")
		if iconHolder then
			local img = iconHolder:FindFirstChild("x")
			if img and img:IsA("ImageLabel") then
				img.Image = data.iconImage
				img.Visible = true
			end
		end

		-- Title (and shadow)
		local container = card:FindFirstChild("container")
		if container then
			local title = container:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.Text = data.displayName
				local shadow = title:FindFirstChild("Title2")
				if shadow and shadow:IsA("TextLabel") then
					shadow.Text = data.displayName
				end
			end

			-- Rarity
			local rarLabel = container:FindFirstChild("Rarity")
			if rarLabel and rarLabel:IsA("TextLabel") then
				rarLabel.Text = data.rarityName
				rarLabel.TextColor3 = getRarityColor(ctx, data.rarityName)
				local shadow = rarLabel:FindFirstChild("Rarity2")
				if shadow and shadow:IsA("TextLabel") then
					shadow.Text = data.rarityName
				end
			end
		end

		-- ObjectValue
		local brainrotVal = card:FindFirstChild("Brainrot")
		if brainrotVal and brainrotVal:IsA("ObjectValue") then
			local folder = ReplicatedStorage:FindFirstChild("Brainrots") and ReplicatedStorage.Brainrots:FindFirstChild(data.key)
			if folder then
				brainrotVal.Value = folder
			end
		end

		return card
	else
		local card = resources.Template_Locked:Clone()
		card.Visible = true
		card.Name = data.key

		-- Locked icon
		local container = card:FindFirstChild("container")
		if container then
			local iconHolder = container:FindFirstChild("IconHolder")
			if iconHolder then
				local img = iconHolder:FindFirstChild("x")
				if img and img:IsA("ImageLabel") then
					img.Image = data.lockedImage
					img.Visible = true
				end
			end
		end

		return card
	end
end

function IndexModule:_populateContainer(container: ScrollingFrame, brainrotList: { any }, discovered: { [string]: boolean })
	self:_clearContainer(container)

	local resources = self._resources
	local holderTemplate = resources.Holder

	local currentHolder: Frame? = nil
	local countInRow = 0

	for _, data in brainrotList do
		-- Need a new holder row?
		if countInRow == 0 or countInRow >= ITEMS_PER_ROW then
			currentHolder = holderTemplate:Clone()
			currentHolder.Visible = true
			currentHolder.Name = "Row"
			currentHolder.Parent = container
			countInRow = 0
		end

		local isDiscovered = discovered[data.key] == true
		local card = self:_buildCard(data, isDiscovered)
		card.Parent = currentHolder
		countInRow += 1
	end
end

function IndexModule:_populateAll()
	local discovered = getDiscoveredSet(self._ctx)
	local grouped = collectBrainrots()

	-- Cache brainrot data by key for quick lookup during live swaps
	self._brainrotData = {}
	for _, list in grouped do
		for _, data in list do
			self._brainrotData[data.key] = data
		end
	end

	for categoryKey, mapping in CATEGORY_MAP do
		local container = self._frame:FindFirstChild(mapping.container)
		if container and container:IsA("ScrollingFrame") then
			local list = grouped[categoryKey] or {}
			self:_populateContainer(container, list, discovered)
		end
	end
end

-- ── Live card swap ─────────────────────────────────────────────────────────

function IndexModule:_swapToUnlocked(key: string)
	local data = self._brainrotData and self._brainrotData[key]
	if not data then return end

	-- Search all containers for the locked card by name
	for _, mapping in CATEGORY_MAP do
		local container = self._frame:FindFirstChild(mapping.container)
		if not container then continue end

		for _, holder in container:GetChildren() do
			if not holder:IsA("Frame") or holder.Name == "_bumpertop" or holder.Name == "_bumperbottom" then
				continue
			end

			local oldCard = holder:FindFirstChild(key)
			if oldCard then
				local layoutOrder = oldCard.LayoutOrder

				-- Destroy locked card
				oldCard:Destroy()

				-- Build unlocked replacement at the same position
				local newCard = self:_buildCard(data, true)
				newCard.LayoutOrder = layoutOrder
				newCard.Parent = holder

				-- Show "New!" label on freshly discovered card
				local container = newCard:FindFirstChild("container")
				if container then
					local newLabel = container:FindFirstChild("newlabel")
					if newLabel and newLabel:IsA("GuiObject") then
						newLabel.Visible = true
					end
				end
				self._newKeys[key] = true

				return
			end
		end
	end
end

-- ── Tab switching ───────────────────────────────────────────────────────────

-- Category key → suffix for named UIStroke/UIGradient on the Index frame
local STYLE_SUFFIXES = {
	Normal  = "Normal",
	Gold    = "Gold",
	Diamond = "Diamond",
}

function IndexModule:_switchTab(categoryKey: string)
	self._activeTab = categoryKey

	-- Show/hide containers + themed UIStroke/UIGradient
	for catKey, mapping in CATEGORY_MAP do
		local isActive = (catKey == categoryKey)

		local container = self._frame:FindFirstChild(mapping.container)
		if container and container:IsA("GuiObject") then
			container.Visible = isActive
		end

		local suffix = STYLE_SUFFIXES[catKey]
		if suffix then
			local stroke = self._frame:FindFirstChild("UIStroke_" .. suffix)
			if stroke and stroke:IsA("UIStroke") then
				stroke.Enabled = isActive
			end
			local gradient = self._frame:FindFirstChild("UIGradient_" .. suffix)
			if gradient and gradient:IsA("UIGradient") then
				gradient.Enabled = isActive
			end
		end
	end
end

-- ── Notification badge ──────────────────────────────────────────────────────
-- Animation: scale 0 → 1.3 (overshoot) → 1 with a full 360° rotation

local NOTIF_POP_DURATION = 0.35
local NOTIF_SETTLE_DURATION = 0.15

function IndexModule:_findNotification()
	-- HUD > ... > Index [TextButton] > Frame > Notification
	local hud = self._ctx.RootGui:FindFirstChild("HUD")
	if not hud then return nil end
	local indexBtn = hud:FindFirstChild("Index", true)
	if not indexBtn then return nil end
	local frame = indexBtn:FindFirstChild("Frame")
	if not frame then return nil end
	return frame:FindFirstChild("Notification")
end

function IndexModule:_setNotifText(count: number)
	local notif = self._notifFrame
	if not notif then return end
	local inner = notif:FindFirstChild("Frame")
	if not inner then return end
	local title = inner:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = tostring(count)
		local shadow = title:FindFirstChild("Title")
		if shadow and shadow:IsA("TextLabel") then
			shadow.Text = tostring(count)
		end
	end
end

function IndexModule:_popNotification()
	local notif = self._notifFrame
	if not notif then return end

	-- Ensure UIScale exists
	local uiScale = notif:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = notif
	end

	-- Show and start from scale 0, rotation 0
	notif.Visible = true
	uiScale.Scale = 0
	notif.Rotation = 0

	-- Phase 1: pop up to 1.3 + full 360° spin
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

	-- Phase 2: settle to scale 1
	popTween.Completed:Once(function()
		TweenService:Create(uiScale,
			TweenInfo.new(NOTIF_SETTLE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1 }
		):Play()
		-- Reset rotation to 0 instantly so future pops start clean
		task.delay(NOTIF_SETTLE_DURATION, function()
			notif.Rotation = 0
		end)
	end)
end

function IndexModule:_bumpNotification()
	self._notifCount = (self._notifCount or 0) + 1
	self:_setNotifText(self._notifCount)
	self:_popNotification()
end

function IndexModule:_clearNotification()
	self._notifCount = 0
	if self._notifFrame then
		local uiScale = self._notifFrame:FindFirstChildOfClass("UIScale")
		if uiScale then
			uiScale.Scale = 0
		end
		self._notifFrame.Visible = false
	end
end

--- Hide "New!" labels on all cards that were flagged as newly discovered
function IndexModule:_clearNewLabels()
	if not self._newKeys then return end
	for key in self._newKeys do
		-- Find the card across all containers
		for _, mapping in CATEGORY_MAP do
			local container = self._frame:FindFirstChild(mapping.container)
			if not container then continue end
			for _, holder in container:GetChildren() do
				if not holder:IsA("Frame") then continue end
				local card = holder:FindFirstChild(key)
				if card then
					local cont = card:FindFirstChild("container")
					if cont then
						local newLabel = cont:FindFirstChild("newlabel")
						if newLabel and newLabel:IsA("GuiObject") then
							newLabel.Visible = false
						end
					end
				end
			end
		end
	end
	self._newKeys = {}
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function IndexModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Index")
	if not self._frame then warn("[IndexModule] Frame 'Index' not found") return end

	self._resources = self._frame:FindFirstChild("resources")
	if not self._resources then warn("[IndexModule] resources folder not found in Index") return end

	self._activeTab = "Normal"
	self._notifCount = 0
	self._newKeys = {} :: { [string]: boolean } -- keys with "New!" label showing
	self._notifFrame = self:_findNotification()
	if self._notifFrame then
		self._notifFrame.Visible = false
	end

	-- Close button
	local closeBtn = self._frame:FindFirstChild("XButton")
	if closeBtn and closeBtn:IsA("GuiButton") then
		self._janitor:Add(closeBtn.MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("Index") end
		end))
	end

	-- Router uses UIScale (not Visible) to open/close frames.
	-- Watch the frame's UIScale to detect open (>0) and close (==0).
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
	self:_populateAll()

	-- Show Normal tab by default
	self:_switchTab("Normal")
end

function IndexModule:Start()
	if not self._frame then return end

	-- Track discovered set and swap cards in-place on new discoveries
	local prevDiscovered = getDiscoveredSet(self._ctx)

	self._janitor:Add(self._ctx.State.Changed:Connect(function(_state, _deltas)
		local newDiscovered = getDiscoveredSet(self._ctx)
		for key in pairs(newDiscovered) do
			if not prevDiscovered[key] then
				self:_swapToUnlocked(key)
				self:_bumpNotification()
			end
		end
		prevDiscovered = newDiscovered
	end))
end

function IndexModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return IndexModule
