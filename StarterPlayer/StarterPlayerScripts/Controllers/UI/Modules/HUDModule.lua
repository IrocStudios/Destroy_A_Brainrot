--!strict
-- Find me 1
-- HUDModule.lua  |  Frame: HUD  (persistent overlay)
-- Manages the main heads-up display:
--   • Cash display with animated gain/loss popups
--   • Speed display (reads "BaseSpeed" attribute on Player)
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

-- ── Speed (attribute-based) ──────────────────────────────────────────────────
-- Speed is the player's base speed, stored as an attribute on the Player instance.
-- It updates when upgraded (not every frame). Default = 16.
local SPEED_ATTR = "BaseSpeed"

local function getBaseSpeed(player: Player): number
	local v = player:GetAttribute(SPEED_ATTR)
	return (type(v) == "number" and v > 0) and v or 16
end

-- ── Init ─────────────────────────────────────────────────────────────────────
function HUDModule:Init(ctx: any)
	print("[HUDController] - Init started")
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()

	-- Track previous cash for popup deltas
	self._prevCash = nil :: number?

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

	-- Initial speed display (from player attribute)
	local initSpeed = getBaseSpeed(ctx.Player)
	print("[HUDController] - Initial BaseSpeed attr: " .. tostring(initSpeed))
	self:_updateSpeed(initSpeed)

	-- Initial state refresh
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

	-- Listen for BaseSpeed attribute changes (set by server when speed is upgraded)
	self._janitor:Add(ctx.Player:GetAttributeChangedSignal(SPEED_ATTR):Connect(function()
		local newSpeed = getBaseSpeed(ctx.Player)
		print("[HUDController] - BaseSpeed attribute changed: " .. tostring(newSpeed))
		self:_updateSpeed(newSpeed)
	end))

	print("[HUDController] - Start complete")
end

-- ── Speed Helper ─────────────────────────────────────────────────────────────

function HUDModule:_updateSpeed(speed: number)
	local lbl = self._speedLabel :: TextLabel?
	if lbl then
		lbl.Text = "Speed: " .. fmt(speed)
	end
end

-- ── Refresh (Cash / XP / Level) ──────────────────────────────────────────────
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
