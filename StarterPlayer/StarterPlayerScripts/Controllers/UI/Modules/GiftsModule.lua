--!strict
-- GiftsModule.lua  |  Frame: Gifts
-- Shows gift inventory. On click, calls server to open a gift and hands
-- the reward payload to GiftModule for the reveal popup.
--
-- WIRE-UP NOTES:
--   Frame "Gifts"
--     ├─ GiftList     (ScrollingFrame)
--     │    └─ GiftCard (Template, Visible=false)
--     │         ├─ Icon       (ImageLabel)
--     │         ├─ GiftName   (TextLabel)
--     │         └─ OpenButton (TextButton)
--     ├─ BadgeCount  (TextLabel – shows pending gift count)
--     └─ XButton (TextButton)

local GiftsModule = {}
GiftsModule.__index = GiftsModule

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function getGiftCooldowns(ctx: any): { [string]: number }
	local s = (ctx.State and ctx.State.State) or {}
	local rewards = s.Rewards or {}
	return rewards.GiftCooldowns or {}
end

-- ── Card building ─────────────────────────────────────────────────────────────

function GiftsModule:_buildCard(template: Frame, giftKey: string, isReady: boolean)
	local card = template:Clone()
	card.Name    = giftKey
	card.Visible = true

	local nameLbl  = find(card, "GiftName")   :: TextLabel?
	local openBtn  = find(card, "OpenButton") :: TextButton?

	if nameLbl  then nameLbl.Text = giftKey end

	if openBtn then
		if isReady then
			openBtn.Text = "Open"
			openBtn.Active = true
		else
			openBtn.Text = "Cooldown"
			openBtn.Active = false
		end

		self._janitor:Add(openBtn.MouseButton1Click:Connect(function()
			if isReady then self:_openGift(giftKey) end
		end))
	end

	return card
end

-- ── Populate ──────────────────────────────────────────────────────────────────

function GiftsModule:_populate()
	local ctx      = self._ctx
	local giftList = find(self._frame, "GiftList")
	local template = giftList and find(giftList, "GiftCard")
	if not (giftList and template) then return end

	for _, child in ipairs(giftList:GetChildren()) do
		if child.Name ~= "GiftCard" and child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local cooldowns = getGiftCooldowns(ctx)
	local now       = os.time()
	local readyCount = 0

	for giftKey, expiresAt in pairs(cooldowns) do
		local isReady = expiresAt == 0 or now >= expiresAt
		if isReady then readyCount += 1 end
		local card = self:_buildCard(template :: Frame, giftKey, isReady)
		card.Parent = giftList
	end

	-- Update badge
	local badge = find(self._frame, "BadgeCount") :: TextLabel?
	if badge then
		badge.Text    = tostring(readyCount)
		badge.Visible = readyCount > 0
	end
end

-- ── Open gift ─────────────────────────────────────────────────────────────────

function GiftsModule:_openGift(giftKey: string)
	local ctx = self._ctx
	ctx.UI.Sound:Play("cartoon_pop")

	task.spawn(function()
		local rf = ctx.Net:GetFunction("RewardAction")
		local ok, result = pcall(function()
			return rf:InvokeServer({ action = "openGift", giftId = giftKey })
		end)

		if ok and type(result) == "table" and result.ok then
			-- Hand off to GiftModule for the reveal popup
			local GiftModule = require(script.Parent.GiftModule)
			GiftModule:ShowReward(result.reward or {})
			-- Refresh our list (cooldowns updated via state delta)
		else
			ctx.UI.Effects.Shake(self._frame, 5, 0.25, 0.1)
			local reason = (type(result) == "table" and result.reason) or "Try again"
			warn("[GiftsModule] openGift failed:", reason)
		end
	end)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function GiftsModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Gifts")
	if not self._frame then warn("[GiftsModule] Frame 'Gifts' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("Gifts") end
		end))
	end

	self:_populate()
end

function GiftsModule:Start()
	if not self._frame then return end
	self._janitor:Add(self._ctx.State.Changed:Connect(function(_, _)
		self:_populate()
	end))
end

function GiftsModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return GiftsModule
