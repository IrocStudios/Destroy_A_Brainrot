--!strict
-- ShopModule.lua  |  Frame: Shop
-- Renders weapon product cards from ShopConfig/WeaponConfig.
-- Handles cash/gamepass/devproduct purchases and reflects owned/locked states.
--
-- WIRE-UP NOTES (match to your Studio hierarchy):
--   Frame "Shop"
--     ├─ CategoryTabs            (Folder or Frame containing tab buttons)
--     │    each tab button has Attribute "Category" = "Featured"|"Primary" etc.
--     ├─ ItemList                (ScrollingFrame – cards are cloned here)
--     │    └─ ItemCard           (Template frame, Visible=false)
--     │         ├─ Icon          (ImageLabel)
--     │         ├─ ItemName      (TextLabel)
--     │         ├─ PriceLabel    (TextLabel)
--     │         ├─ RarityBar     (Frame – BackgroundColor3 set to rarity color)
--     │         └─ ActionButton  (TextButton – "Buy" / "Owned" / "Locked")
--     ├─ CashLabel               (TextLabel – current cash display)
--     └─ XButton             (TextButton)

local ShopModule = {}
ShopModule.__index = ShopModule

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e9 then return ("%.1fB"):format(n / 1e9)
	elseif n >= 1e6 then return ("%.1fM"):format(n / 1e6)
	elseif n >= 1e3 then return ("%.1fK"):format(n / 1e3)
	end
	return tostring(n)
end

local function getState(ctx: any)
	return (ctx.State and ctx.State.State) or {}
end

local function getCash(ctx: any): number
	local s = getState(ctx)
	return (s.Currency and s.Currency.Cash) or 0
end

local function getOwned(ctx: any): { [string]: boolean }
	local s = getState(ctx)
	local list = (s.Inventory and s.Inventory.WeaponsOwned) or {}
	local set: { [string]: boolean } = {}
	for _, name in ipairs(list) do set[name] = true end
	return set
end

local function getStageUnlocked(ctx: any): number
	local s = getState(ctx)
	return (s.Progression and s.Progression.StageUnlocked) or 1
end

-- ── Card building ─────────────────────────────────────────────────────────────

function ShopModule:_buildCard(template: Frame, itemKey: string)
	local ctx        = self._ctx
	local weaponCfg  = ctx.Config.WeaponConfig  and ctx.Config.WeaponConfig[itemKey]
	local rarityCfg  = ctx.Config.RarityConfig
	if not weaponCfg then return end

	local card = template:Clone()
	card.Name    = itemKey
	card.Visible = true

	local iconLbl    = find(card, "Icon")        :: ImageLabel?
	local nameLbl    = find(card, "ItemName")    :: TextLabel?
	local priceLbl   = find(card, "PriceLabel")  :: TextLabel?
	local rarityBar  = find(card, "RarityBar")   :: Frame?
	local actionBtn  = find(card, "ActionButton") :: TextButton?

	if nameLbl  then nameLbl.Text  = weaponCfg.DisplayName or itemKey end
	if priceLbl then priceLbl.Text = "$" .. fmt(weaponCfg.Price or 0) end

	if rarityBar and rarityCfg then
		local rData = rarityCfg.Rarities[weaponCfg.Rarity or "Common"]
		if rData then rarityBar.BackgroundColor3 = rData.Color end
	end

	-- Track this card for state refreshes
	self._cards[itemKey] = {
		card      = card,
		itemKey   = itemKey,
		price     = weaponCfg.Price or 0,
		stageReq  = weaponCfg.StageRequired or 1,
		actionBtn = actionBtn,
		priceLbl  = priceLbl,
	}

	-- Bind purchase
	if actionBtn then
		self._janitor:Add(actionBtn.MouseButton1Click:Connect(function()
			self:_onPurchase(itemKey)
		end))
	end

	-- Pulse featured items
	if self._activeCategory == "Featured" and iconLbl then
		local handle = ctx.UI.Effects.Pulse(iconLbl, 1.0, 0.04)
		self._janitor:Add(handle, "Destroy")
	end

	return card
end

function ShopModule:_populateList(category: string)
	local ctx       = self._ctx
	local shopCfg   = ctx.Config.ShopConfig
	if not shopCfg then return end

	local catData = shopCfg.Categories and shopCfg.Categories[category]
	if not catData then return end

	local itemList = find(self._frame, "ItemList")
	local template = itemList and find(itemList, "ItemCard")
	if not (itemList and template) then return end

	-- Clear previous cards
	for key, rec in pairs(self._cards) do
		rec.card:Destroy()
		self._cards[key] = nil
	end

	self._activeCategory = category

	for _, itemKey in ipairs(catData.Items or {}) do
		local card = self:_buildCard(template :: Frame, itemKey)
		if card then
			card.Parent = itemList
		end
	end

	self:_refreshCards()
end

-- ── State refresh ─────────────────────────────────────────────────────────────

function ShopModule:_refreshCashLabel()
	local cashLbl = find(self._frame, "CashLabel") :: TextLabel?
	if cashLbl then cashLbl.Text = "$" .. fmt(getCash(self._ctx)) end
end

function ShopModule:_refreshCards()
	local ctx     = self._ctx
	local cash    = getCash(ctx)
	local owned   = getOwned(ctx)
	local stage   = getStageUnlocked(ctx)

	for itemKey, rec in pairs(self._cards) do
		local btn = rec.actionBtn
		if not btn then continue end

		if owned[itemKey] then
			btn.Text = "Owned"
			btn.Active = false
		elseif stage < rec.stageReq then
			btn.Text = "Stage " .. rec.stageReq
			btn.Active = false
		elseif cash < rec.price then
			btn.Text = "Need $" .. fmt(rec.price)
			btn.Active = false
		else
			btn.Text = "Buy"
			btn.Active = true
		end
	end
end

function ShopModule:_refresh(state: any)
	self:_refreshCashLabel()
	self:_refreshCards()
end

-- ── Purchase ──────────────────────────────────────────────────────────────────

function ShopModule:_onPurchase(itemKey: string)
	local ctx = self._ctx
	local rec = self._cards[itemKey]
	if not rec then return end

	local actionBtn = rec.actionBtn
	if actionBtn and not actionBtn.Active then
		ctx.UI.Effects.Shake(actionBtn, 5, 0.25, 0.1)
		ctx.UI.Sound:Play("cartoon_pop2")
		return
	end

	task.spawn(function()
		local rf = ctx.Net:GetFunction("ShopAction")
		local ok, result = pcall(function()
			return rf:InvokeServer({ action = "buy", item = itemKey })
		end)

		if not ok or not (type(result) == "table" and result.ok) then
			-- Purchase failed
			if actionBtn then
				ctx.UI.Effects.Shake(actionBtn, 6, 0.3, 0.12)
			end
			local reason = (type(result) == "table" and result.reason) or "Unknown error"
			ctx.UI.Sound:Play("cartoon_pop2")
			-- Optionally surface via AlertModule
			local AlertMod = require(script.Parent.AlertModule)
			AlertMod:Show({ title = "Purchase Failed", message = reason, confirm = "OK", warning = true })
		else
			ctx.UI.Sound:Play("cartoon_pop")
			-- State will update via StateDelta → refresh happens automatically
		end
	end)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function ShopModule:Init(ctx: any)
	self._ctx            = ctx
	self._janitor        = ctx.UI.Cleaner.new()
	self._cards          = {} :: { [string]: any }
	self._activeCategory = "Featured"

	self._frame = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Shop")
	if not self._frame then warn("[ShopModule] Frame 'Shop' not found") return end

	-- Close button
	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("Shop") end
		end))
	end

	-- Category tab buttons
	local tabsFolder = find(self._frame, "CategoryTabs")
	if tabsFolder then
		for _, btn in ipairs(tabsFolder:GetChildren()) do
			if btn:IsA("GuiButton") then
				local cat = btn:GetAttribute("Category") :: string?
				if cat then
					self._janitor:Add(btn.MouseButton1Click:Connect(function()
						self:_populateList(cat)
					end))
				end
			end
		end
	end

	-- Build default category
	self:_populateList("Featured")
	self:_refreshCashLabel()
end

function ShopModule:Start()
	if not self._frame then return end
	self._janitor:Add(self._ctx.State.Changed:Connect(function(state, _)
		self:_refresh(state)
	end))
end

function ShopModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return ShopModule
