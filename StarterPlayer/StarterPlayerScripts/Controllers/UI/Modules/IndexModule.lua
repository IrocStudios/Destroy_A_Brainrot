--!strict
-- IndexModule.lua  |  Frame: Index
-- Displays all brainrots from BrainrotConfig; shows discovered vs silhouette.
-- Sorts by rarity descending, discovered first.
--
-- WIRE-UP NOTES:
--   Frame "Index"
--     ├─ EntryList      (ScrollingFrame)
--     │    └─ EntryCard (Template, Visible=false)
--     │         ├─ Icon        (ImageLabel)
--     │         ├─ EntryName   (TextLabel)
--     │         ├─ RarityLabel (TextLabel)
--     │         └─ RarityBar   (Frame)
--     ├─ FilterAll      (TextButton – show all)
--     ├─ FilterFound    (TextButton – show discovered only)
--     └─ XButton    (TextButton)

local IndexModule = {}
IndexModule.__index = IndexModule

local RARITY_ORDER = { Mythic=6, Legendary=5, Epic=4, Rare=3, Uncommon=2, Common=1 }

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function getDiscovered(ctx: any): { [string]: boolean }
	local s = (ctx.State and ctx.State.State) or {}
	local raw = (s.Index and s.Index.BrainrotsDiscovered) or {}
	local set: { [string]: boolean } = {}
	if type(raw) == "table" then
		for _, id in ipairs(raw) do set[id] = true end
	end
	return set
end

-- ── Sorting ───────────────────────────────────────────────────────────────────

function IndexModule:_sortedKeys(discovered: { [string]: boolean }): { string }
	local ctx       = self._ctx
	local brainCfg  = ctx.Config.BrainrotConfig or {}
	local keys: { string } = {}

	for k in pairs(brainCfg) do table.insert(keys, k) end

	table.sort(keys, function(a, b)
		local ca = brainCfg[a]
		local cb = brainCfg[b]
		local ra = RARITY_ORDER[ca and ca.RarityName or "Common"] or 1
		local rb = RARITY_ORDER[cb and cb.RarityName or "Common"] or 1
		if ra ~= rb then return ra > rb end -- rarity descending
		local da = discovered[a] and 1 or 0
		local db = discovered[b] and 1 or 0
		if da ~= db then return da > db end -- discovered first
		return a < b
	end)

	return keys
end

-- ── Card building ─────────────────────────────────────────────────────────────

function IndexModule:_buildCard(template: Frame, key: string, discovered: { [string]: boolean })
	local ctx      = self._ctx
	local brainCfg = ctx.Config.BrainrotConfig or {}
	local rarCfg   = ctx.Config.RarityConfig
	local data     = brainCfg[key]
	if not data then return end

	local isFound  = discovered[key] == true
	local card     = template:Clone()
	card.Name      = key
	card.Visible   = true

	local iconLbl    = find(card, "Icon")        :: ImageLabel?
	local nameLbl    = find(card, "EntryName")   :: TextLabel?
	local rarLbl     = find(card, "RarityLabel") :: TextLabel?
	local rarBar     = find(card, "RarityBar")   :: Frame?

	if isFound then
		if nameLbl  then nameLbl.Text  = data.DisplayName or key end
		if rarLbl   then
			local rname = data.RarityName or "Common"
			rarLbl.Text = rname
			if rarCfg then
				local rData = rarCfg.Rarities[rname]
				if rData then rarLbl.TextColor3 = rData.Color end
			end
		end
		if rarBar and rarCfg then
			local rData = rarCfg.Rarities[data.RarityName or "Common"]
			if rData then rarBar.BackgroundColor3 = rData.Color end
		end
		if iconLbl then iconLbl.ImageTransparency = 0 end
	else
		-- Undiscovered: hide info
		if nameLbl  then nameLbl.Text  = "???" end
		if rarLbl   then rarLbl.Text   = "???" ; rarLbl.TextColor3 = Color3.fromRGB(120,120,120) end
		if iconLbl  then iconLbl.ImageTransparency = 0.8 end
		if rarBar   then rarBar.BackgroundColor3 = Color3.fromRGB(80,80,80) end
	end

	return card
end

-- ── Populate ──────────────────────────────────────────────────────────────────

function IndexModule:_populate(filterDiscoveredOnly: boolean?)
	local ctx      = self._ctx
	local entryList = find(self._frame, "EntryList")
	local template  = entryList and find(entryList, "EntryCard")
	if not (entryList and template) then return end

	-- Clear existing cards
	for _, child in ipairs(entryList:GetChildren()) do
		if child.Name ~= "EntryCard" and child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local discovered = getDiscovered(ctx)
	local keys       = self:_sortedKeys(discovered)

	for _, key in ipairs(keys) do
		if filterDiscoveredOnly and not discovered[key] then continue end
		local card = self:_buildCard(template :: Frame, key, discovered)
		if card then card.Parent = entryList end
	end
end

-- ── New-discovery highlight ───────────────────────────────────────────────────

-- Call this when a new brainrot is discovered mid-session.
function IndexModule:_onNewDiscovery(key: string)
	local ctx      = self._ctx
	local entryList = find(self._frame, "EntryList")
	if not entryList then return end

	local card = entryList:FindFirstChild(key)
	if card and card:IsA("GuiObject") then
		local handle = ctx.UI.Effects.Pulse(card, 2.0, 0.06)
		task.delay(3, function() handle:Destroy() end)
	end
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function IndexModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Index")
	if not self._frame then warn("[IndexModule] Frame 'Index' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("Index") end
		end))
	end

	local filterAll = find(self._frame, "FilterAll")
	if filterAll then
		self._janitor:Add((filterAll :: GuiButton).MouseButton1Click:Connect(function()
			self:_populate(false)
		end))
	end

	local filterFound = find(self._frame, "FilterFound")
	if filterFound then
		self._janitor:Add((filterFound :: GuiButton).MouseButton1Click:Connect(function()
			self:_populate(true)
		end))
	end

	self:_populate(false)
end

function IndexModule:Start()
	if not self._frame then return end
	local prevDiscovered: { [string]: boolean } = {}

	self._janitor:Add(self._ctx.State.Changed:Connect(function(state, _)
		local newDiscovered = getDiscovered(self._ctx)
		-- Check for newly discovered entries to animate
		for key in pairs(newDiscovered) do
			if not prevDiscovered[key] then
				self:_onNewDiscovery(key)
			end
		end
		prevDiscovered = newDiscovered
		self:_populate(false)
	end))
end

function IndexModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return IndexModule
