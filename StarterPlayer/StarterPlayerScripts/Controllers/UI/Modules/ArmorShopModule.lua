--!strict
-- ArmorShopModule.lua  |  Frame: ArmorShop
-- Shop for armor (MaxArmor) upgrade purchases. Sequential tiers — must buy in order.
--
-- WIRE-UP NOTES:
--   Frame "ArmorShop"
--     ├─ ItemList    (ScrollingFrame)
--     │    └─ ArmorCard (Template, Visible=false)
--     │         ├─ TierName   (TextLabel e.g. "Light Plating")
--     │         ├─ ArmorValue (TextLabel e.g. "+10 Armor")
--     │         ├─ PriceLabel (TextLabel)
--     │         └─ BuyButton  (TextButton)
--     ├─ CurrentArmor (TextLabel – shows current/max armor)
--     ├─ CashLabel    (TextLabel)
--     └─ XButton  (TextButton)

local ArmorShopModule = {}
ArmorShopModule.__index = ArmorShopModule

-- Inline fallback tier definitions until ArmorConfig exists
local DEFAULT_TIERS = {
	{ Name = "Light Plating",    ArmorBonus = 10,  Price = 750   },
	{ Name = "Steel Jacket",     ArmorBonus = 25,  Price = 2500  },
	{ Name = "Reinforced Suit",  ArmorBonus = 50,  Price = 7500  },
	{ Name = "Titan Armor",      ArmorBonus = 100, Price = 20000 },
	{ Name = "Fortress Shell",   ArmorBonus = 200, Price = 50000 },
}

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e9 then return ("%.2fb"):format(n / 1e9) end
	if n >= 1e6 then return ("%.2fm"):format(n / 1e6) end
	if n >= 1e3 then return ("%.2fk"):format(n / 1e3) end
	return tostring(n)
end

local function getCash(ctx: any): number
	local s = (ctx.State and ctx.State.State) or {}
	return (s.Currency and s.Currency.Cash) or 0
end

local function getArmorTier(ctx: any): number
	local s = (ctx.State and ctx.State.State) or {}
	return (s.Defense and s.Defense.ArmorTier) or 0
end

local function getArmorValues(ctx: any): (number, number)
	local s = (ctx.State and ctx.State.State) or {}
	local def = s.Defense or {}
	return (def.Armor or 0), (def.MaxArmor or 0)
end

function ArmorShopModule:_getTiers(): { any }
	local cfg = self._ctx.Config.ArmorConfig
	return (cfg and cfg.Tiers) or DEFAULT_TIERS
end

function ArmorShopModule:_buildCard(template: Frame, tier: any, index: number)
	local card = template:Clone()
	card.Name    = "Tier_" .. tostring(index)
	card.Visible = true

	local nameLbl  = find(card, "TierName")   :: TextLabel?
	local armorLbl = find(card, "ArmorValue")  :: TextLabel?
	local priceLbl = find(card, "PriceLabel")  :: TextLabel?
	local buyBtn   = find(card, "BuyButton")   :: TextButton?

	if nameLbl  then nameLbl.Text  = tier.Name or ("Tier " .. tostring(index)) end
	if armorLbl then armorLbl.Text = "+" .. tostring(tier.ArmorBonus) .. " Armor" end
	if priceLbl then priceLbl.Text = "$" .. fmt(tier.Price or 0) end

	self._cards[index] = {
		card   = card,
		tier   = tier,
		buyBtn = buyBtn,
	}

	if buyBtn then
		self._janitor:Add(buyBtn.MouseButton1Click:Connect(function()
			self:_onPurchase(index, tier)
		end))
	end

	return card
end

function ArmorShopModule:_populate()
	local itemList = find(self._frame, "ItemList")
	local template = itemList and find(itemList, "ArmorCard")
	if not (itemList and template) then return end

	for k, rec in pairs(self._cards) do rec.card:Destroy(); self._cards[k] = nil end

	for i, tier in ipairs(self:_getTiers()) do
		local card = self:_buildCard(template :: Frame, tier, i)
		if card then card.Parent = itemList end
	end

	self:_refreshCards()
end

function ArmorShopModule:_refreshCards()
	local cash      = getCash(self._ctx)
	local ownedTier = getArmorTier(self._ctx)

	for idx, rec in pairs(self._cards) do
		local btn = rec.buyBtn
		if not btn then continue end
		local price = rec.tier.Price or 0

		if idx <= ownedTier then
			-- Already purchased
			btn.Text   = "Owned"
			btn.Active = false
		elseif idx == ownedTier + 1 then
			-- Next available tier
			if cash >= price then
				btn.Text   = "Buy"
				btn.Active = true
			else
				btn.Text   = "Need $" .. fmt(price)
				btn.Active = false
			end
		else
			-- Locked — need previous tier first
			btn.Text   = "Locked"
			btn.Active = false
		end
	end
end

function ArmorShopModule:_onPurchase(index: number, tier: any)
	local ctx = self._ctx
	local rec = self._cards[index]

	if rec and rec.buyBtn and not rec.buyBtn.Active then
		ctx.UI.Effects.Shake(rec.buyBtn, 5, 0.25, 0.1)
		return
	end

	task.spawn(function()
		local rf = ctx.Net:GetFunction("ShopAction")
		local ok, result = pcall(function()
			return rf:InvokeServer({ action = "buyArmor", tierIndex = index })
		end)
		if ok and type(result) == "table" and result.ok then
			ctx.UI.Sound:Play("cartoon_pop")
		else
			if rec and rec.buyBtn then ctx.UI.Effects.Shake(rec.buyBtn, 6, 0.3, 0.12) end
		end
	end)
end

function ArmorShopModule:_refreshArmorLabel()
	local armor, maxArmor = getArmorValues(self._ctx)
	local lbl = find(self._frame, "CurrentArmor") :: TextLabel?
	if lbl then
		if maxArmor > 0 then
			lbl.Text = "Armor: " .. tostring(math.floor(armor)) .. "/" .. tostring(math.floor(maxArmor))
		else
			lbl.Text = "Armor: None"
		end
	end
	local cashLbl = find(self._frame, "CashLabel") :: TextLabel?
	if cashLbl then cashLbl.Text = "$" .. fmt(getCash(self._ctx)) end
end

function ArmorShopModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._cards   = {} :: { [number]: any }
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("ArmorShop")
	if not self._frame then warn("[ArmorShopModule] Frame 'ArmorShop' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("ArmorShop") end
		end))
	end

	self:_populate()
	self:_refreshArmorLabel()
end

function ArmorShopModule:Start()
	if not self._frame then return end
	self._janitor:Add(self._ctx.State.Changed:Connect(function(_, _)
		self:_refreshArmorLabel()
		self:_refreshCards()
	end))
end

function ArmorShopModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return ArmorShopModule
