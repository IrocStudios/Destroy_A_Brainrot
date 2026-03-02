--!strict
-- Find me 1
-- HUDModule.lua  |  Frame: HUD  (persistent overlay)
-- Manages the main heads-up display:
--   • Cash display with animated gain/loss popups
--   • Speed display (reads SpeedBoost from state, adds to base 16)
--   • XP bar + XP label + Level label
--   • Nav buttons wired by Frames:BindButtons() via "Frame" attribute
--
-- STUDIO HIERARCHY (HUD lives directly in ScreenGui, NOT inside Frames/):
--   HUD [Frame]
--     ├─ InfoHolder [Frame]
--     │    ├─ CashHolder [Frame]
--     │    │    ├─ CashValue       (TextLabel – "$2.8k")
--     │    │    └─ Popups [Frame]
--     │    │         ├─ CashGainTemplate (TextLabel – cloned for +$ popups)
--     │    │         └─ CashLostTemplate (TextLabel – cloned for -$ popups)
--     │    ├─ SpeedHolder [Frame]
--     │    │    └─ Value            (TextLabel – "Speed: 99")
--     │    └─ XPHolder [Frame]
--     │         ├─ XPValue          (TextLabel – "XP: 100")
--     │         ├─ LvlValue         (TextLabel – "Lvl. 1")
--     │         └─ BarHolder [Frame]
--     │              └─ backdrop > barcontainer > Bar  (Frame – width = XP ratio)
--     ├─ LeftButtons / RightButtons  (nav buttons → router:Toggle)
--     └─ ...

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local HUDModule = {}
HUDModule.__index = HUDModule

-- ── Number Formatting ────────────────────────────────────────────────────────
-- All numbers in the game follow: k (thousands), m (millions), b (billions)
-- Rounded to 2 decimal places. Below 1,000 shown as-is.

local function fmt(n: number): string
	local abs = math.abs(n)
	if abs >= 1e9 then
		return ("%.2fb"):format(n / 1e9)
	elseif abs >= 1e6 then
		return ("%.2fm"):format(n / 1e6)
	elseif abs >= 1e3 then
		return ("%.2fk"):format(n / 1e3)
	end
	return tostring(math.floor(n))
end

-- Nav buttons are wired automatically by Frames:BindButtons() via "Frame"
-- StringAttribute on each button in Studio. No manual NAV_MAP needed here.

-- ── Cash Popup Animation ─────────────────────────────────────────────────────
-- Clones the appropriate template, shows the delta, tweens up + fades out.

local POPUP_DURATION = 1.0 -- seconds
local POPUP_RISE_PX  = 30  -- pixels to float upward

local function spawnCashPopup(ctx: any, popupsFrame: Frame, templateName: string, delta: number)
	local template = popupsFrame:FindFirstChild(templateName)
	if not template then return end

	local clone = template:Clone()
	clone.Visible = true

	-- Set text
	local prefix = delta >= 0 and "+$" or "-$"
	;(clone :: TextLabel).Text = prefix .. fmt(math.abs(delta))

	-- Start at template's original position
	local origin = clone.Position
	clone.TextTransparency = 0

	-- Also reset stroke transparency if it has a UIStroke
	local stroke = clone:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Transparency = 0 end

	-- Start UIScale at 0 for pop-in effect
	local uiScale = clone:FindFirstChildOfClass("UIScale")
	if uiScale then
		(uiScale :: UIScale).Scale = 0
	end

	clone.Parent = popupsFrame

	-- Pop scale 0 → 1 with Back overshoot
	if uiScale then
		local popInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(uiScale :: Instance, popInfo, { Scale = 1 }):Play()
	end

	-- Tween upward + fade out
	local targetPos = origin + UDim2.new(0, 0, 0, -POPUP_RISE_PX)
	ctx.UI.Tween:Play(clone, { Position = targetPos, TextTransparency = 1 }, POPUP_DURATION)
	if stroke then
		ctx.UI.Tween:Play(stroke, { Transparency = 1 }, POPUP_DURATION)
	end

	-- Cleanup after tween
	task.delay(POPUP_DURATION + 0.1, function()
		clone:Destroy()
	end)
end

-- ── Speed (state-based) ─────────────────────────────────────────────────────
-- Speed = base walk speed (16) + SpeedBoost from Progression state.
local BASE_WALK_SPEED = 16

-- ── Init ─────────────────────────────────────────────────────────────────────
function HUDModule:Init(ctx: any)
	print("[HUDController] - Init started")
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()

	-- Track previous values for popup deltas
	self._prevCash  = nil :: number?
	self._prevSpeed = nil :: number?
	self._prevArmor = nil :: number?

	-- HUD lives directly in the ScreenGui, not inside FramesFolder
	local root = ctx.RootGui
	self._hud = root and (root:FindFirstChild("HUD") or
		(ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("HUD")))

	if not self._hud then
		warn("[HUDController] - Frame 'HUD' not found in ScreenGui!")
		return
	end
	print("[HUDController] - Found HUD: " .. self._hud:GetFullName())

	-- Make HUD always visible (it is NOT managed by the router)
	self._hud.Visible = true

	-- Cache InfoHolder references
	local infoHolder = self._hud:FindFirstChild("InfoHolder")
	self._infoHolder = infoHolder

	if not infoHolder then
		warn("[HUDController] - InfoHolder not found inside HUD!")
	else
		print("[HUDController] - Found InfoHolder")

		-- Cash
		local cashHolder = infoHolder:FindFirstChild("CashHolder")
		self._cashValue = cashHolder and cashHolder:FindFirstChild("CashValue")
		self._popups    = cashHolder and cashHolder:FindFirstChild("Popups")
		self._cashGainTemplate = self._popups and self._popups:FindFirstChild("CashGainTemplate")
		self._cashLostTemplate = self._popups and self._popups:FindFirstChild("CashLostTemplate")

		-- UIScale on CashValue for pop animation
		self._cashUIScale = self._cashValue and (self._cashValue :: Instance):FindFirstChildOfClass("UIScale")

		print("[HUDController] - CashHolder: " .. tostring(cashHolder ~= nil))
		print("[HUDController] - CashValue: " .. tostring(self._cashValue ~= nil))
		print("[HUDController] - CashUIScale: " .. tostring(self._cashUIScale ~= nil))
		print("[HUDController] - Popups: " .. tostring(self._popups ~= nil))
		print("[HUDController] - CashGainTemplate: " .. tostring(self._cashGainTemplate ~= nil))
		print("[HUDController] - CashLostTemplate: " .. tostring(self._cashLostTemplate ~= nil))

		-- Hide templates
		if self._cashGainTemplate then (self._cashGainTemplate :: TextLabel).Visible = false end
		if self._cashLostTemplate then (self._cashLostTemplate :: TextLabel).Visible = false end

		-- Speed
		local speedHolder = infoHolder:FindFirstChild("SpeedHolder")
		self._speedLabel = speedHolder and speedHolder:FindFirstChild("Value")
		print("[HUDController] - SpeedHolder: " .. tostring(speedHolder ~= nil))
		print("[HUDController] - SpeedLabel (Value): " .. tostring(self._speedLabel ~= nil))

		-- Speed valchange template (inside Value label)
		self._speedValchange = self._speedLabel and (self._speedLabel :: Instance):FindFirstChild("valchange")
		if self._speedValchange then (self._speedValchange :: TextLabel).Visible = false end
		print("[HUDController] - SpeedValchange: " .. tostring(self._speedValchange ~= nil))

		-- Armor
		local armorHolder = infoHolder:FindFirstChild("ArmorHolder")
		self._armorLabel = armorHolder and armorHolder:FindFirstChild("Value")
		print("[HUDController] - ArmorHolder: " .. tostring(armorHolder ~= nil))
		print("[HUDController] - ArmorLabel (Value): " .. tostring(self._armorLabel ~= nil))

		-- Armor valchange template (inside Value label)
		self._armorValchange = self._armorLabel and (self._armorLabel :: Instance):FindFirstChild("valchange")
		if self._armorValchange then (self._armorValchange :: TextLabel).Visible = false end
		print("[HUDController] - ArmorValchange: " .. tostring(self._armorValchange ~= nil))

		-- XP
		local xpHolder = infoHolder:FindFirstChild("XPHolder")
		self._xpValue  = xpHolder and xpHolder:FindFirstChild("XPValue")
		self._lvlValue = xpHolder and xpHolder:FindFirstChild("LvlValue")
		print("[HUDController] - XPHolder: " .. tostring(xpHolder ~= nil))
		print("[HUDController] - XPValue: " .. tostring(self._xpValue ~= nil))
		print("[HUDController] - LvlValue: " .. tostring(self._lvlValue ~= nil))

		-- XP Bar: XPHolder > BarHolder > backdrop > barcontainer > Bar
		local barHolder = xpHolder and xpHolder:FindFirstChild("BarHolder")
		local backdrop  = barHolder and barHolder:FindFirstChild("backdrop")
		local barContainer = backdrop and backdrop:FindFirstChild("barcontainer")
		self._xpBar = barContainer and barContainer:FindFirstChild("Bar")
		print("[HUDController] - BarHolder: " .. tostring(barHolder ~= nil))
		print("[HUDController] - backdrop: " .. tostring(backdrop ~= nil))
		print("[HUDController] - barcontainer: " .. tostring(barContainer ~= nil))
		print("[HUDController] - Bar: " .. tostring(self._xpBar ~= nil))
	end

	-- Nav buttons are handled by Frames:BindButtons() via "Frame" attribute.
	-- No manual wiring here to avoid double-toggle.
	print("[HUDController] - Nav buttons handled by Frames:BindButtons()")

	-- Gift button countdown label (LeftButtons > Gifts > Frame > Title)
	local leftButtons = self._hud:FindFirstChild("LeftButtons")
	if leftButtons then
		local giftBtn = leftButtons:FindFirstChild("Gifts", true)
		if giftBtn then
			local giftFrame = giftBtn:FindFirstChild("Frame")
			if giftFrame then
				self._giftTitle = giftFrame:FindFirstChild("Title") :: TextLabel?
				self._giftTitleDefault = self._giftTitle and (self._giftTitle :: TextLabel).Text or "Gift"
			end
		end
	end
	print("[HUDController] - GiftTitle: " .. tostring(self._giftTitle ~= nil))

	-- Initial state refresh (speed is read from state, not player attribute)
	local initState = ctx.State and ctx.State.State or {}
	print("[HUDController] - Initial state keys: " .. tostring(initState.Currency ~= nil and "Currency " or "") .. tostring(initState.Progression ~= nil and "Progression " or ""))
	self:_refresh(initState)

	print("[HUDController] - Init complete")
end

-- ── Start ────────────────────────────────────────────────────────────────────
function HUDModule:Start()
	print("[HUDController] - Start called")
	if not self._hud then
		warn("[HUDController] - Start aborted, no HUD reference")
		return
	end
	local ctx = self._ctx

	-- State changes (cash, xp, level)
	self._janitor:Add(ctx.State.Changed:Connect(function(state: any, _deltas: any)
		self:_refresh(state)
	end))
	print("[HUDController] - Subscribed to State.Changed")

	-- Gift button countdown: tick every 1 second for accurate timer
	local giftTickAccum = 0
	self._janitor:Add(RunService.Heartbeat:Connect(function(dt: number)
		giftTickAccum += dt
		if giftTickAccum >= 1 then
			giftTickAccum = 0
			self:_refreshGiftButton()
		end
	end))
	print("[HUDController] - Gift button Heartbeat timer started")

	print("[HUDController] - Start complete")
end

-- ── Valchange Popup ──────────────────────────────────────────────────────────
-- Clones the valchange template, shows the delta text, tweens up + fades out.
-- Parent is the Value label itself — the popup floats above it.

local function spawnValchangePopup(ctx: any, parentLabel: TextLabel, template: TextLabel, delta: number)
	local clone = template:Clone()
	clone.Visible = true

	-- Set text: "+5" or "-50"
	if delta >= 0 then
		(clone :: TextLabel).Text = "+" .. tostring(math.floor(delta))
	else
		(clone :: TextLabel).Text = tostring(math.floor(delta))
	end

	-- Start at template's original position
	local origin = clone.Position
	clone.TextTransparency = 0

	-- Reset stroke transparency if it has a UIStroke
	local stroke = clone:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Transparency = 0 end

	-- Start UIScale at 0 for pop-in effect
	local uiScale = clone:FindFirstChildOfClass("UIScale")
	if uiScale then
		(uiScale :: UIScale).Scale = 0
	end

	clone.Parent = parentLabel

	-- Pop scale 0 → 1 with Back overshoot
	if uiScale then
		local popInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(uiScale :: Instance, popInfo, { Scale = 1 }):Play()
	end

	-- Tween upward + fade out
	local targetPos = origin + UDim2.new(0, 0, 0, -POPUP_RISE_PX)
	ctx.UI.Tween:Play(clone, { Position = targetPos, TextTransparency = 1 }, POPUP_DURATION)
	if stroke then
		ctx.UI.Tween:Play(stroke, { Transparency = 1 }, POPUP_DURATION)
	end

	-- Cleanup after tween
	task.delay(POPUP_DURATION + 0.1, function()
		clone:Destroy()
	end)
end

-- ── Refresh (Cash / XP / Level / Speed / Armor) ─────────────────────────────
function HUDModule:_refresh(state: any)
	if not self._hud then return end
	local ctx = self._ctx
	print("[HUDController] - _refresh fired")

	local currency    = (type(state) == "table" and state.Currency)    or {}
	local progression = (type(state) == "table" and state.Progression) or {}

	local cash  = tonumber(currency.Cash)      or 0
	local level = tonumber(progression.Level)  or 1
	local xp    = tonumber(progression.XP)     or 0

	-- ── Cash ─────────────────────────────────────────────────────────────────
	local cashLbl = self._cashValue :: TextLabel?
	if cashLbl then
		cashLbl.Text = "$" .. fmt(cash)
	end

	-- Cash popup: show gain/loss delta + CashValue pop
	if self._prevCash ~= nil and self._popups then
		local delta = cash - self._prevCash
		if delta ~= 0 then
			if delta > 0 then
				spawnCashPopup(ctx, self._popups :: Frame, "CashGainTemplate", delta)
			else
				spawnCashPopup(ctx, self._popups :: Frame, "CashLostTemplate", delta)
			end

			-- Pop the CashValue label: punch up to 1.15 then settle back to 1
			if self._cashUIScale then
				local us = self._cashUIScale :: UIScale
				-- Cancel any in-flight pop
				if self._cashPopTween then
					(self._cashPopTween :: Tween):Cancel()
				end
				us.Scale = 1.15
				local settleInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				local tw = TweenService:Create(us :: Instance, settleInfo, { Scale = 1 })
				self._cashPopTween = tw
				tw:Play()
			end
		end
	end
	self._prevCash = cash

	-- ── Level ────────────────────────────────────────────────────────────────
	local lvlLbl = self._lvlValue :: TextLabel?
	if lvlLbl then
		lvlLbl.Text = "Lvl. " .. tostring(level)
	end

	-- ── XP label + bar ───────────────────────────────────────────────────────
	local xpLbl = self._xpValue :: TextLabel?
	local progCfg = ctx.Config and ctx.Config.ProgressionConfig
	local xpNeeded = self:_xpForLevel(level, progCfg)

	if xpLbl then
		xpLbl.Text = "XP: " .. fmt(xp)
	end

	local xpBar = self._xpBar :: Frame?
	if xpBar then
		local ratio = (xpNeeded > 0) and math.clamp(xp / xpNeeded, 0, 1) or 0
		ctx.UI.Tween:Play(xpBar, { Size = UDim2.new(ratio, 0, 1, 0) }, 0.3)
	end

	-- ── Speed (from state) ───────────────────────────────────────────────────
	local speedBoost = tonumber(progression.SpeedBoost) or 0
	local totalSpeed = math.floor(BASE_WALK_SPEED + speedBoost)
	local speedLbl = self._speedLabel :: TextLabel?
	if speedLbl then
		speedLbl.Text = "Speed: " .. tostring(totalSpeed)
	end

	-- Speed valchange popup
	if self._prevSpeed ~= nil and self._speedValchange and speedLbl then
		local speedDelta = totalSpeed - self._prevSpeed
		if speedDelta ~= 0 then
			spawnValchangePopup(ctx, speedLbl :: TextLabel, self._speedValchange :: TextLabel, speedDelta)
		end
	end
	self._prevSpeed = totalSpeed

	-- ── Armor ────────────────────────────────────────────────────────────────
	local defense  = (type(state) == "table" and state.Defense) or {}
	local curArmor = tonumber(defense.Armor) or 0
	local armorLbl = self._armorLabel :: TextLabel?
	if armorLbl then
		armorLbl.Text = "Armor: " .. tostring(math.floor(curArmor))
	end

	-- Armor valchange popup
	if self._prevArmor ~= nil and self._armorValchange and armorLbl then
		local armorDelta = curArmor - self._prevArmor
		if math.abs(armorDelta) >= 1 then
			spawnValchangePopup(ctx, armorLbl :: TextLabel, self._armorValchange :: TextLabel, armorDelta)
		end
	end
	self._prevArmor = curArmor

	-- ── Gift Button Countdown (also ticked by Heartbeat every 1s) ──
	self:_refreshGiftButton()
end

-- ── Gift Button Countdown ───────────────────────────────────────────────────
-- Called from _refresh (on state change) AND from Heartbeat (every 1s) so the
-- HUD countdown always shows an accurate timer, not just every 10s sync.
function HUDModule:_refreshGiftButton()
	if not self._giftTitle then return end
	local ctx = self._ctx
	local state = ctx.State and ctx.State.State or {}
	local rewards = (type(state) == "table" and state.Rewards) or {}
	local pg = rewards.PlaytimeGifts
	if not pg or type(pg) ~= "table" then return end

	local ptConfig = ctx.Config and ctx.Config.PlaytimeGiftConfig
	if not ptConfig or not ptConfig.Slots then return end

	local todaySeconds = tonumber(pg.TodaySeconds) or 0
	local syncedAt = tonumber(pg.SyncedAt) or os.time()
	local devMult = tonumber(ptConfig.DEV_TIME_MULTIPLIER) or 1
	local elapsed = (os.time() - syncedAt) * devMult
	local liveSeconds = todaySeconds + elapsed

	local claimed = pg.Claimed or {}
	local nextUnclaimedTime: number? = nil
	local anyReady = false
	local allClaimed = true

	for i = 1, (ptConfig.SlotCount or 9) do
		local slot = ptConfig.Slots[i]
		if slot and not claimed[tostring(i)] then
			allClaimed = false
			local remaining = slot.time - liveSeconds
			if remaining <= 0 then
				anyReady = true
				break
			else
				if not nextUnclaimedTime or remaining < nextUnclaimedTime then
					nextUnclaimedTime = remaining
				end
			end
		end
	end

	local gTitle = self._giftTitle :: TextLabel
	local gShadow = gTitle:FindFirstChild("Title") :: TextLabel?
	local text: string
	if anyReady then
		text = "Ready!"
	elseif allClaimed then
		text = self._giftTitleDefault or "Gift"
	elseif nextUnclaimedTime then
		local mins = math.floor(nextUnclaimedTime / 60)
		local secs = math.floor(nextUnclaimedTime % 60)
		text = ("%d:%02d"):format(mins, secs)
	else
		text = self._giftTitleDefault or "Gift"
	end
	gTitle.Text = text
	if gShadow then gShadow.Text = text end
end

-- Derive XP needed for next level from ProgressionConfig or a simple formula.
-- Formula: floor(Base + Growth * (level ^ Power))
-- Defaults match ProgressionConfig so server + client always agree.
function HUDModule:_xpForLevel(level: number, cfg: any): number
	local curve = (cfg and type(cfg.XPCurve) == "table") and cfg.XPCurve or nil

	-- Check overrides first
	if curve and type(curve.Overrides) == "table" and curve.Overrides[level] then
		return tonumber(curve.Overrides[level]) or 100
	end

	-- Defaults match ProgressionConfig values
	local base   = (curve and tonumber(curve.Base))   or 65
	local growth = (curve and tonumber(curve.Growth)) or 14.5
	local power  = (curve and tonumber(curve.Power))  or 1.62
	return math.floor(base + growth * (level ^ power))
end

-- ── Destroy ──────────────────────────────────────────────────────────────────
function HUDModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return HUDModule
