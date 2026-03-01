--!strict
-- ArmorShopModule.lua  |  Frame: ArmorShop
-- Frame-based armor shop. Shows the next several upgrade steps using
-- the formula-based ArmorConfig (infinite scaling, no fixed tiers).
--
-- WIRE-UP NOTES:
--   Frame "ArmorShop"
--     ├─ ItemList    (ScrollingFrame)
--     │    └─ ArmorCard (Template, Visible=false)
--     │         ├─ TierName   (TextLabel e.g. "Step 3")
--     │         ├─ ArmorValue (TextLabel e.g. "+25 Armor")
--     │         ├─ PriceLabel (TextLabel)
--     │         └─ BuyButton  (TextButton)
--     ├─ CurrentArmor (TextLabel – shows current armor)
--     ├─ CashLabel    (TextLabel)
--     └─ XButton  (TextButton)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArmorShopModule = {}
ArmorShopModule.__index = ArmorShopModule

local PREVIEW_COUNT = 5 -- how many upcoming steps to show

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

local function getArmorStep(ctx: any): number
	local s = (ctx.State and ctx.State.State) or {}
	return (s.Defense and s.Defense.ArmorStep) or 0
end

local function getCurrentArmor(ctx: any): number
	local s = (ctx.State and ctx.State.State) or {}
	return (s.Defense and tonumber(s.Defense.Armor)) or 0
end

-- Load ArmorConfig for formula
local _armorConfig: any = nil
local function getArmorConfig(): any
	if _armorConfig then return _armorConfig end
	local ok, cfg = pcall(function()
		local shared = ReplicatedStorage:WaitForChild("Shared", 5)
		local cfgFolder = shared and shared:WaitForChild("Config", 5)
		return cfgFolder and require(cfgFolder:WaitForChild("ArmorConfig", 5))
	end)
	if ok and cfg then _armorConfig = cfg end
	return _armorConfig
end

local function getStepValues(step: number): (number, number)
	local cfg = getArmorConfig()
	if cfg and cfg.GetStep then return cfg.GetStep(step) end
	return 10, 500
end

function ArmorShopModule:_buildCard(template: Frame, stepIndex: number)
	local amount, price = getStepValues(stepIndex)

	local card = template:Clone()
	card.Name    = "Step_" .. tostring(stepIndex)
	card.Visible = true

	local nameLbl  = find(card, "TierName")   :: TextLabel?
	local armorLbl = find(card, "ArmorValue")  :: TextLabel?
	local priceLbl = find(card, "PriceLabel")  :: TextLabel?
	local buyBtn   = find(card, "BuyButton")   :: TextButton?

	if nameLbl  then nameLbl.Text  = "Step " .. tostring(stepIndex + 1) end
	if armorLbl then armorLbl.Text = "+" .. tostring(amount) .. " Armor" end
	if priceLbl then priceLbl.Text = "$" .. fmt(price) end

	self._cards[stepIndex] = {
		card   = card,
		amount = amount,
		price  = price,
		buyBtn = buyBtn,
	}

	if buyBtn then
		self._janitor:Add(buyBtn.MouseButton1Click:Connect(function()
			self:_onPurchase(stepIndex)
		end))
	end

	return card
end

function ArmorShopModule:_populate()
	local itemList = find(self._frame, "ItemList")
	local template = itemList and find(itemList, "ArmorCard")
	if not (itemList and template) then return end

	-- Clear old cards
	for k, rec in pairs(self._cards) do rec.card:Destroy(); self._cards[k] = nil end

	-- Build cards for the next PREVIEW_COUNT steps
	local currentStep = getArmorStep(self._ctx)
	for i = 0, PREVIEW_COUNT - 1 do
		local stepIdx = currentStep + i
		local card = self:_buildCard(template :: Frame, stepIdx)
		if card then card.Parent = itemList end
	end

	self:_refreshCards()
end

function ArmorShopModule:_refreshCards()
	local cash        = getCash(self._ctx)
	local currentStep = getArmorStep(self._ctx)

	for stepIdx, rec in pairs(self._cards) do
		local btn = rec.buyBtn
		if not btn then continue end

		if stepIdx < currentStep then
			-- Already purchased (shouldn't normally appear, but handle it)
			btn.Text   = "Owned"
			btn.Active = false
		elseif stepIdx == currentStep then
			-- Next purchasable step
			local _, price = getStepValues(stepIdx)
			if cash >= price then
				btn.Text   = "Buy"
				btn.Active = true
			else
				btn.Text   = "Need $" .. fmt(price)
				btn.Active = false
			end
		else
			-- Future steps — locked until previous purchased
			btn.Text   = "Locked"
			btn.Active = false
		end
	end
end

function ArmorShopModule:_onPurchase(stepIndex: number)
	local ctx = self._ctx
	local rec = self._cards[stepIndex]

	if rec and rec.buyBtn and not rec.buyBtn.Active then
		ctx.UI.Effects.Shake(rec.buyBtn, 5, 0.25, 0.1)
		return
	end

	task.spawn(function()
		local rf = ctx.Net:GetFunction("ShopAction")
		local ok, result = pcall(function()
			return rf:InvokeServer({ action = "buyArmor" })
		end)
		if ok and type(result) == "table" and result.ok then
			ctx.UI.Sound:Play("cartoon_pop")
			-- Re-populate to shift the step window forward
			self:_populate()
		else
			if rec and rec.buyBtn then ctx.UI.Effects.Shake(rec.buyBtn, 6, 0.3, 0.12) end
		end
	end)
end

function ArmorShopModule:_refreshArmorLabel()
	local armor = getCurrentArmor(self._ctx)
	local lbl = find(self._frame, "CurrentArmor") :: TextLabel?
	if lbl then
		lbl.Text = "Armor: " .. tostring(math.floor(armor))
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
