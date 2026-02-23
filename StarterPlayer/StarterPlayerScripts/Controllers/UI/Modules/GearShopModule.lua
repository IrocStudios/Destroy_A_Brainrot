--!strict
-- GearShopModule.lua  |  Frame: GearShop
-- Same card pattern as ShopModule but scoped to gear items only.
-- Gear items are identified by ShopConfig.Categories.Special (or a dedicated GearConfig).
--
-- WIRE-UP NOTES (same card structure as ShopModule):
--   Frame "GearShop"
--     ├─ ItemList    (ScrollingFrame)
--     │    └─ ItemCard (Template, Visible=false)
--     │         ├─ Icon, ItemName, PriceLabel, RarityBar, ActionButton
--     ├─ CashLabel   (TextLabel)
--     └─ XButton (TextButton)

local GearShopModule = {}
GearShopModule.__index = GearShopModule

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e3 then return ("%.1fK"):format(n/1e3) end
	return tostring(n)
end

local function getState(ctx: any): any
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
	for _, k in ipairs(list) do set[k] = true end
	return set
end

-- ── Card building ─────────────────────────────────────────────────────────────

function GearShopModule:_buildCard(template: Frame, itemKey: string, weaponData: any)
	local card = template:Clone()
	card.Name    = itemKey
	card.Visible = true

	local nameLbl  = find(card, "ItemName")    :: TextLabel?
	local priceLbl = find(card, "PriceLabel")  :: TextLabel?
	local actionBtn = find(card, "ActionButton") :: TextButton?

	if nameLbl  then nameLbl.Text  = weaponData.DisplayName or itemKey end
	if priceLbl then priceLbl.Text = "$" .. fmt(weaponData.Price or 0) end

	self._cards[itemKey] = {
		card      = card,
		price     = weaponData.Price or 0,
		actionBtn = actionBtn,
	}

	if actionBtn then
		self._janitor:Add(actionBtn.MouseButton1Click:Connect(function()
			self:_onPurchase(itemKey)
		end))
	end

	return card
end

function GearShopModule:_populate()
	local ctx      = self._ctx
	local shopCfg  = ctx.Config.ShopConfig
	local weaponCfg = ctx.Config.WeaponConfig
	if not (shopCfg and weaponCfg) then return end

	local itemList = find(self._frame, "ItemList")
	local template = itemList and find(itemList, "ItemCard")
	if not (itemList and template) then return end

	for key, rec in pairs(self._cards) do
		rec.card:Destroy()
		self._cards[key] = nil
	end

	-- Use ShopConfig "Special" category as gear items; adjust category name as needed
	local gearCategory = shopCfg.Categories and (shopCfg.Categories["Special"] or shopCfg.Categories["GearShop"])
	local items = (gearCategory and gearCategory.Items) or {}

	for _, itemKey in ipairs(items) do
		local data = weaponCfg[itemKey]
		if data then
			local card = self:_buildCard(template :: Frame, itemKey, data)
			if card then card.Parent = itemList end
		end
	end

	self:_refreshCards()
end

function GearShopModule:_refreshCashLabel()
	local lbl = find(self._frame, "CashLabel") :: TextLabel?
	if lbl then lbl.Text = "$" .. fmt(getCash(self._ctx)) end
end

function GearShopModule:_refreshCards()
	local cash  = getCash(self._ctx)
	local owned = getOwned(self._ctx)

	for itemKey, rec in pairs(self._cards) do
		local btn = rec.actionBtn
		if not btn then continue end
		if owned[itemKey] then
			btn.Text = "Owned"; btn.Active = false
		elseif cash < rec.price then
			btn.Text = "Need $" .. fmt(rec.price); btn.Active = false
		else
			btn.Text = "Buy"; btn.Active = true
		end
	end
end

function GearShopModule:_onPurchase(itemKey: string)
	local ctx = self._ctx
	local rec = self._cards[itemKey]
	if not rec then return end

	if rec.actionBtn and not rec.actionBtn.Active then
		ctx.UI.Effects.Shake(rec.actionBtn, 5, 0.25, 0.1)
		return
	end

	task.spawn(function()
		local rf = ctx.Net:GetFunction("ShopAction")
		local ok, result = pcall(function()
			return rf:InvokeServer({ action = "buy", item = itemKey })
		end)
		if not (ok and type(result) == "table" and result.ok) then
			if rec.actionBtn then ctx.UI.Effects.Shake(rec.actionBtn, 6, 0.3, 0.12) end
		else
			ctx.UI.Sound:Play("cartoon_pop")
		end
	end)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function GearShopModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._cards   = {} :: { [string]: any }
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("GearShop")
	if not self._frame then warn("[GearShopModule] Frame 'GearShop' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("GearShop") end
		end))
	end

	self:_populate()
	self:_refreshCashLabel()
end

function GearShopModule:Start()
	if not self._frame then return end
	self._janitor:Add(self._ctx.State.Changed:Connect(function(_, _)
		self:_refreshCashLabel()
		self:_refreshCards()
	end))
end

function GearShopModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return GearShopModule
