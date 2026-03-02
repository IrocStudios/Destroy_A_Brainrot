--!strict
-- GiftsClaimModule.lua  |  Frame: GiftsClaim
-- Displays 9 playtime gift slots with live countdown timers.
-- Gifts unlock based on cumulative daily playtime (resets at midnight UTC).
-- When a slot's timer reaches 0 → text changes to "Claim!".
-- When clicked → fires RewardAction RF → OpenGiftModule prompt appears.
-- When claimed → slot is greyed out, text → "Claimed".
--
-- Reads: ctx.State.State.Rewards.PlaytimeGifts
--   { Date, TodaySeconds, Claimed, SyncedAt }
-- Client computes local elapsed since SyncedAt for smooth countdowns.
--
-- WIRE-UP (Studio frame hierarchy):
--   GiftsClaim [Frame]
--     Canvas [CanvasGroup]
--       Header > Title "Gifts"
--     Container [ScrollingFrame]
--       UIGridLayout
--       Reward1..9 [TextButton]
--         Frame [Frame]
--           Title [TextLabel] — gift name ("Small Gift" etc.)
--             Title [TextLabel] — shadow
--           Title [TextLabel] — timer/status ("00:00" / "Claim!" / "Claimed")
--             Title [TextLabel] — shadow
--           ImageLabel [ImageLabel] — gift icon
--           Stud [ImageLabel]
--           GiftGradient [UIGradient]
--           GiftGradientStroke [UIGradient]
--         Gift [ObjectValue] — .Value = Blue/Purple/Gold folder
--     XButton [TextButton]
--     UIScale [UIScale]

local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GiftsClaimModule = {}
GiftsClaimModule.__index = GiftsClaimModule

-- ── Constants ───────────────────────────────────────────────────────

local GREY_COLOR       = Color3.fromRGB(80, 80, 80)
local GREY_ICON_ALPHA  = 0.6
local TIMER_INTERVAL   = 0.5  -- seconds between timer label updates (not every frame)

local GIFT_GRADIENT_MAP = {
	Blue   = "GiftBlue",
	Purple = "GiftPurple",
	Gold   = "GiftGold",
}

-- ── Helpers ─────────────────────────────────────────────────────────

local function formatTime(seconds: number): string
	if seconds <= 0 then return "Claim!" end
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return ("%d:%02d"):format(m, s)
end

-- ── Slot Caching ────────────────────────────────────────────────────

type SlotCache = {
	index: number,
	button: TextButton,
	backdrop: Frame,
	nameLabel: TextLabel,
	nameShadow: TextLabel?,
	timerLabel: TextLabel,
	timerShadow: TextLabel?,
	icon: ImageLabel?,
	giftKey: string,
	originalBGColor: Color3,
	originalIconAlpha: number,
	strokeGradient: UIGradient?,
	originalStrokeColor: ColorSequence?,
}

function GiftsClaimModule:_cacheSlots()
	self._slots = {} :: { SlotCache }
	local container = self._frame:FindFirstChild("Canvas")
		and self._frame.Canvas:FindFirstChild("Container")
		or self._frame:FindFirstChild("Container")
	if not container then
		warn("[GiftsClaimModule] Container not found")
		return
	end

	for i = 1, 9 do
		local btn = container:FindFirstChild("Reward" .. i) :: TextButton?
		if not btn then continue end

		local inner = btn:FindFirstChild("Frame") :: Frame?
		if not inner then continue end

		-- Collect the two Title labels: first = name, second = timer (by position)
		local nameLabel: TextLabel? = nil
		local timerLabel: TextLabel? = nil
		for _, child in inner:GetChildren() do
			if child.Name == "Title" and child:IsA("TextLabel") then
				if not nameLabel then
					nameLabel = child :: TextLabel
				else
					timerLabel = child :: TextLabel
				end
			end
		end

		-- Determine which is which by Y position (name is near top, timer near bottom)
		if nameLabel and timerLabel then
			if nameLabel.Position.Y.Scale > timerLabel.Position.Y.Scale then
				nameLabel, timerLabel = timerLabel, nameLabel
			end
		end

		-- Gift ObjectValue → giftKey
		local giftOV = btn:FindFirstChild("Gift")
		local giftKey = "Blue"
		if giftOV and giftOV:IsA("ObjectValue") and giftOV.Value then
			giftKey = giftOV.Value.Name
		end

		-- Icon
		local icon: ImageLabel? = nil
		for _, desc in inner:GetChildren() do
			if desc:IsA("ImageLabel") and desc.Name == "ImageLabel" then
				icon = desc :: ImageLabel
				break
			end
		end

		-- Stroke gradient (for greying out on claim)
		local strokeGrad: UIGradient? = nil
		local existingStroke = inner:FindFirstChild("GiftGradientStroke")
		if existingStroke and existingStroke:IsA("UIGradient") then
			strokeGrad = existingStroke :: UIGradient
		end

		local slot: SlotCache = {
			index = i,
			button = btn,
			backdrop = inner,
			nameLabel = nameLabel :: TextLabel,
			nameShadow = nameLabel and (nameLabel :: Instance):FindFirstChild("Title") :: TextLabel?,
			timerLabel = timerLabel :: TextLabel,
			timerShadow = timerLabel and (timerLabel :: Instance):FindFirstChild("Title") :: TextLabel?,
			icon = icon,
			giftKey = giftKey,
			originalBGColor = inner.BackgroundColor3,
			originalIconAlpha = icon and icon.ImageTransparency or 0,
			strokeGradient = strokeGrad,
			originalStrokeColor = strokeGrad and strokeGrad.Color or nil,
		}

		table.insert(self._slots, slot)
	end

	-- Sort by index
	table.sort(self._slots, function(a, b) return a.index < b.index end)
end

-- ── Apply ShopGradients ─────────────────────────────────────────────

function GiftsClaimModule:_applyGradients()
	local shopGrads = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("ShopGradients")
	if not shopGrads then return end

	for _, slot in self._slots do
		local gradName = GIFT_GRADIENT_MAP[slot.giftKey] or "GiftBlue"

		-- Apply fill gradient
		local giftGrad = slot.backdrop:FindFirstChild("GiftGradient")
		local sourceGrad = shopGrads:FindFirstChild(gradName)
		if giftGrad and giftGrad:IsA("UIGradient") and sourceGrad and sourceGrad:IsA("UIGradient") then
			giftGrad.Color = sourceGrad.Color
		end

		-- Apply stroke gradient
		local giftStroke = slot.backdrop:FindFirstChild("GiftGradientStroke")
		local sourceStroke = shopGrads:FindFirstChild(gradName .. "Stroke")
		if giftStroke and giftStroke:IsA("UIGradient") and sourceStroke and sourceStroke:IsA("UIGradient") then
			giftStroke.Color = sourceStroke.Color
		end
	end
end

-- ── Apply Gift Icons ──────────────────────────────────────────────

function GiftsClaimModule:_applyIcons()
	local giftsFolder = ReplicatedStorage:FindFirstChild("ShopAssets")
		and ReplicatedStorage.ShopAssets:FindFirstChild("Gifts")
	if not giftsFolder then return end

	for _, slot in self._slots do
		local giftAsset = giftsFolder:FindFirstChild(slot.giftKey)
		if not giftAsset then continue end

		local sourceIcon = giftAsset:FindFirstChild("Icon")
		if not sourceIcon or not sourceIcon:IsA("ImageLabel") then continue end

		-- Clone icon from gift asset
		local clone = sourceIcon:Clone()

		-- Copy layout from existing placeholder icon
		local placeholder = slot.icon
		if placeholder then
			clone.Size = placeholder.Size
			clone.Position = placeholder.Position
			clone.AnchorPoint = placeholder.AnchorPoint
			clone.ZIndex = placeholder.ZIndex
			clone.LayoutOrder = placeholder.LayoutOrder
			clone.BackgroundTransparency = 1
			placeholder:Destroy()
		end

		clone.Name = "GiftIcon"
		clone.Parent = slot.backdrop

		-- Update slot reference to the live clone
		slot.icon = clone
		slot.originalIconAlpha = clone.ImageTransparency

		self._janitor:Add(clone)
	end
end

-- ── Slot Visual States ──────────────────────────────────────────────

function GiftsClaimModule:_setSlotCountdown(slot: SlotCache, remaining: number)
	local text = formatTime(remaining)
	slot.timerLabel.Text = text
	if slot.timerShadow then slot.timerShadow.Text = text end

	-- Restore original colors
	slot.backdrop.BackgroundColor3 = slot.originalBGColor
	if slot.icon then slot.icon.ImageTransparency = slot.originalIconAlpha end
	if slot.strokeGradient and slot.originalStrokeColor then
		slot.strokeGradient.Color = slot.originalStrokeColor
	end
end

function GiftsClaimModule:_setSlotReady(slot: SlotCache)
	slot.timerLabel.Text = "Claim!"
	if slot.timerShadow then slot.timerShadow.Text = "Claim!" end

	-- Restore original colors
	slot.backdrop.BackgroundColor3 = slot.originalBGColor
	if slot.icon then slot.icon.ImageTransparency = slot.originalIconAlpha end
	if slot.strokeGradient and slot.originalStrokeColor then
		slot.strokeGradient.Color = slot.originalStrokeColor
	end
end

function GiftsClaimModule:_setSlotClaimed(slot: SlotCache)
	slot.timerLabel.Text = "Claimed"
	if slot.timerShadow then slot.timerShadow.Text = "Claimed" end

	-- Grey out backdrop, icon, and stroke gradient
	slot.backdrop.BackgroundColor3 = GREY_COLOR
	if slot.icon then slot.icon.ImageTransparency = GREY_ICON_ALPHA end
	if slot.strokeGradient then
		slot.strokeGradient.Color = ColorSequence.new(GREY_COLOR)
	end
end

-- ── Timer Update Loop ───────────────────────────────────────────────

function GiftsClaimModule:_updateTimers()
	if not self._frame or not self._frame.Visible then return end

	local ctx = self._ctx
	local state = ctx.State and ctx.State.State or {}
	local rewards = state.Rewards or {}
	local pg = rewards.PlaytimeGifts
	if type(pg) ~= "table" then return end

	local ptConfig = ctx.Config and ctx.Config.PlaytimeGiftConfig
	if not ptConfig then return end

	local todaySeconds = tonumber(pg.TodaySeconds) or 0
	local syncedAt = tonumber(pg.SyncedAt) or os.time()
	local devMult = tonumber(ptConfig.DEV_TIME_MULTIPLIER) or 1
	local elapsed = (os.time() - syncedAt) * devMult
	local liveSeconds = todaySeconds + elapsed

	local claimed = pg.Claimed or {}

	for _, slot in self._slots do
		local slotDef = ptConfig.Slots and ptConfig.Slots[slot.index]
		if not slotDef then continue end

		if claimed[tostring(slot.index)] then
			self:_setSlotClaimed(slot)
		else
			local remaining = slotDef.time - liveSeconds
			if remaining <= 0 then
				self:_setSlotReady(slot)
			else
				self:_setSlotCountdown(slot, remaining)
			end
		end
	end
end

-- ── Refresh (from state delta) ──────────────────────────────────────

function GiftsClaimModule:_refresh()
	self:_updateTimers()
end

-- ── Claim Handler ───────────────────────────────────────────────────

function GiftsClaimModule:_onClaim(slotIndex: number)
	if self._claiming then return end

	local ctx = self._ctx
	local state = ctx.State and ctx.State.State or {}
	local rewards = state.Rewards or {}
	local pg = rewards.PlaytimeGifts
	if type(pg) ~= "table" then return end

	local ptConfig = ctx.Config and ctx.Config.PlaytimeGiftConfig
	if not ptConfig then return end

	local claimed = pg.Claimed or {}
	if claimed[tostring(slotIndex)] then return end

	local slotDef = ptConfig.Slots and ptConfig.Slots[slotIndex]
	if not slotDef then return end

	-- Check time (apply dev multiplier for client-side interpolation)
	local todaySeconds = tonumber(pg.TodaySeconds) or 0
	local syncedAt = tonumber(pg.SyncedAt) or os.time()
	local devMult = tonumber(ptConfig.DEV_TIME_MULTIPLIER) or 1
	local elapsed = (os.time() - syncedAt) * devMult
	local liveSeconds = todaySeconds + elapsed
	if liveSeconds < slotDef.time then return end

	self._claiming = true

	task.spawn(function()
		local rf = ctx.Net:GetFunction("RewardAction")
		local ok, result = pcall(function()
			return rf:InvokeServer({ Action = "ClaimPlaytimeGift", Slot = slotIndex })
		end)

		self._claiming = false

		if ok and type(result) == "table" and result.ok then
			-- Server sends giftReceived notify → OpenGiftModule handles the prompt
			-- State delta will update Claimed map → _refresh greys out the slot
			print("[GiftsClaimModule] Claimed slot", slotIndex, "→", result.giftKey)
		else
			local reason = (type(result) == "table" and result.error) or "Try again"
			warn("[GiftsClaimModule] Claim failed slot", slotIndex, ":", reason)
		end
	end)
end

-- ── Lifecycle ───────────────────────────────────────────────────────

function GiftsClaimModule:Init(ctx: any)
	self._ctx = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._claiming = false

	self._frame = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("GiftsClaim")
	if not self._frame then
		warn("[GiftsClaimModule] Frame 'GiftsClaim' not found")
		return
	end

	-- Cache all 9 reward slot references
	self:_cacheSlots()

	-- Apply ShopGradients to each slot based on its gift key
	self:_applyGradients()

	-- Clone gift icons from ShopAssets/Gifts/[Key]/Icon into each slot
	self:_applyIcons()

	-- Wire close button
	local closeBtn = self._frame:FindFirstChild("XButton")
	if closeBtn and closeBtn:IsA("GuiButton") then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("GiftsClaim") end
		end))
	end

	-- Wire claim buttons
	for _, slot in self._slots do
		self._janitor:Add(slot.button.MouseButton1Click:Connect(function()
			self:_onClaim(slot.index)
		end))
	end

	-- Initial timer update
	self:_updateTimers()

	print("[GiftsClaimModule] Init OK")
end

function GiftsClaimModule:Start()
	if not self._frame then return end
	local ctx = self._ctx

	-- React to state changes (server pushes PlaytimeGifts every 10s)
	self._janitor:Add(ctx.State.Changed:Connect(function(_, _)
		self:_refresh()
	end))

	-- Smooth timer tick (every 0.5s instead of every frame for perf)
	local accumulator = 0
	self._janitor:Add(RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator >= TIMER_INTERVAL then
			accumulator = 0
			self:_updateTimers()
		end
	end))

	print("[GiftsClaimModule] Start OK")
end

function GiftsClaimModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return GiftsClaimModule
