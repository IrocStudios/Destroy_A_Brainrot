--!strict
-- SpeedShopModule.lua  |  Frame: SpeedShop
-- Shop for walkspeed boost purchases. Items defined by a SpeedConfig or
-- a dedicated category in ShopConfig. Each tier grants a permanent speed boost.
--
-- WIRE-UP NOTES:
--   Frame "SpeedShop"
--     ├─ ItemList    (ScrollingFrame)
--     │    └─ SpeedCard (Template, Visible=false)
--     │         ├─ TierName   (TextLabel e.g. "Speed Tier 1")
--     │         ├─ SpeedValue (TextLabel e.g. "+2 WalkSpeed")
--     │         ├─ PriceLabel (TextLabel)
--     │         └─ BuyButton  (TextButton)
--     ├─ CurrentSpeed (TextLabel – shows current walkspeed)
--     ├─ CashLabel    (TextLabel)
--     └─ XButton  (TextButton)
--
-- Add a SpeedConfig to ReplicatedStorage/Shared/Config/ with tiers:
--   SpeedConfig = { Tiers = { { Name, SpeedBonus, Price } } }

local SpeedShopModule = {}
SpeedShopModule.__index = SpeedShopModule

-- Inline fallback tier definitions until SpeedConfig exists
local DEFAULT_TIERS = {
	{ Name = "Quick Feet",   SpeedBonus = 2,  Price = 500   },
	{ Name = "Jogger",       SpeedBonus = 4,  Price = 1500  },
	{ Name = "Runner",       SpeedBonus = 7,  Price = 4000  },
	{ Name = "Sprinter",     SpeedBonus = 12, Price = 10000 },
	{ Name = "Speedrunner",  SpeedBonus = 20, Price = 30000 },
}

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e3 then return ("%.1fK"):format(n/1e3) end
	return tostring(n)
end

local function getCash(ctx: any): number
	local s = (ctx.State and ctx.State.State) or {}
	return (s.Currency and s.Currency.Cash) or 0
end

function SpeedShopModule:_getTiers(): { any }
	local cfg = self._ctx.Config.SpeedConfig
	return (cfg and cfg.Tiers) or DEFAULT_TIERS
end

function SpeedShopModule:_buildCard(template: Frame, tier: any, index: number)
	local card = template:Clone()
	card.Name    = "Tier_" .. tostring(index)
	card.Visible = true

	local nameLbl  = find(card, "TierName")   :: TextLabel?
	local speedLbl = find(card, "SpeedValue")  :: TextLabel?
	local priceLbl = find(card, "PriceLabel")  :: TextLabel?
	local buyBtn   = find(card, "BuyButton")   :: TextButton?

	if nameLbl  then nameLbl.Text  = tier.Name or ("Tier " .. tostring(index)) end
	if speedLbl then speedLbl.Text = "+" .. tostring(tier.SpeedBonus) .. " Speed" end
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

function SpeedShopModule:_populate()
	local ctx      = self._ctx
	local itemList = find(self._frame, "ItemList")
	local template = itemList and find(itemList, "SpeedCard")
	if not (itemList and template) then return end

	for k, rec in pairs(self._cards) do rec.card:Destroy(); self._cards[k] = nil end

	for i, tier in ipairs(self:_getTiers()) do
		local card = self:_buildCard(template :: Frame, tier, i)
		if card then card.Parent = itemList end
	end

	self:_refreshCards()
end

function SpeedShopModule:_refreshCards()
	local cash = getCash(self._ctx)
	for _, rec in pairs(self._cards) do
		local btn = rec.buyBtn
		if not btn then continue end
		local price = rec.tier.Price or 0
		btn.Active = cash >= price
		btn.Text   = cash >= price and "Buy" or ("Need $" .. fmt(price))
	end
end

function SpeedShopModule:_onPurchase(index: number, tier: any)
	local ctx = self._ctx
	local rec = self._cards[index]

	if rec and rec.buyBtn and not rec.buyBtn.Active then
		ctx.UI.Effects.Shake(rec.buyBtn, 5, 0.25, 0.1)
		return
	end

	task.spawn(function()
		local rf = ctx.Net:GetFunction("ShopAction")
		local ok, result = pcall(function()
			return rf:InvokeServer({ action = "buySpeed", tierIndex = index })
		end)
		if ok and type(result) == "table" and result.ok then
			ctx.UI.Sound:Play("cartoon_pop")
		else
			if rec and rec.buyBtn then ctx.UI.Effects.Shake(rec.buyBtn, 6, 0.3, 0.12) end
		end
	end)
end

function SpeedShopModule:_refreshSpeedLabel()
	local lbl = find(self._frame, "CurrentSpeed") :: TextLabel?
	local char = self._ctx.Player.Character
	if lbl and char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then lbl.Text = "Speed: " .. tostring(math.floor(hum.WalkSpeed)) end
	end
	local cashLbl = find(self._frame, "CashLabel") :: TextLabel?
	if cashLbl then cashLbl.Text = "$" .. fmt(getCash(self._ctx)) end
end

function SpeedShopModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._cards   = {} :: { [number]: any }
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("SpeedShop")
	if not self._frame then warn("[SpeedShopModule] Frame 'SpeedShop' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("SpeedShop") end
		end))
	end

	self:_populate()
	self:_refreshSpeedLabel()
end

function SpeedShopModule:Start()
	if not self._frame then return end
	self._janitor:Add(self._ctx.State.Changed:Connect(function(_, _)
		self:_refreshSpeedLabel()
		self:_refreshCards()
	end))
end

function SpeedShopModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return SpeedShopModule
