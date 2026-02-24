--!strict
-- DiedModule.lua  |  Frame: Died
-- Opens on death (server Notify type="died"). Player must choose Drop or Keep.
-- Drop = lose all inventory, free respawn.
-- Keep = pay keepCost (server-calculated), respawn with inventory.
--
-- WIRE-UP (Studio frame hierarchy):
--   Died [Frame]
--     container [Frame]
--       Timer [Frame]
--         Frame > CanvasGroup > Bar [Frame]  ← 30s countdown bar
--       Title [TextLabel]  ← "You Died! Keep Your Inventory?"
--       Input [Frame]
--         Drop [TextButton]
--         Keep [TextButton]
--           KeepCost [TextLabel]  ← "$X.XXk"
--       Frame > deathicon [ImageLabel]  ← pop + rock animation
--     Backdrop [Frame]
--       Drop2 [TextButton]    ← secondary Drop button
--     shadow [Frame]           ← glow/flash overlay

local TweenService = game:GetService("TweenService")

local DiedModule = {}
DiedModule.__index = DiedModule

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e9 then return ("$%.2fb"):format(n / 1e9)
	elseif n >= 1e6 then return ("$%.2fm"):format(n / 1e6)
	elseif n >= 1e3 then return ("$%.2fk"):format(n / 1e3)
	end
	return "$" .. tostring(n)
end

-- Quick horizontal shake to signal "can't afford"
local function shakeButton(btn: GuiButton)
	local orig = btn.Position
	local info = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local offsets = {
		UDim2.new(orig.X.Scale, orig.X.Offset + 6, orig.Y.Scale, orig.Y.Offset),
		UDim2.new(orig.X.Scale, orig.X.Offset - 6, orig.Y.Scale, orig.Y.Offset),
		UDim2.new(orig.X.Scale, orig.X.Offset + 4, orig.Y.Scale, orig.Y.Offset),
		UDim2.new(orig.X.Scale, orig.X.Offset - 4, orig.Y.Scale, orig.Y.Offset),
		orig,
	}
	local i = 0
	local function step()
		i += 1
		if i > #offsets then return end
		local tw = TweenService:Create(btn, info, { Position = offsets[i] })
		tw.Completed:Once(step)
		tw:Play()
	end
	step()
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function DiedModule:Init(ctx: any)
	self._ctx        = ctx
	self._janitor    = ctx.UI.Cleaner.new()
	self._processing = false
	self._open       = false
	self._frame      = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Died")

	if not self._frame then
		warn("[DiedModule] Frame 'Died' not found")
		return
	end

	-- Cache button refs
	self._dropBtn     = find(self._frame, "Drop")     :: TextButton?
	self._keepBtn     = find(self._frame, "Keep")     :: TextButton?
	self._keepCostLbl = find(self._frame, "KeepCost") :: TextLabel?

	-- Drop2 (renamed from XButton in Backdrop) — functions identically to Drop
	local drop2Btn = find(self._frame, "Drop2")
	if drop2Btn then
		(drop2Btn :: GuiObject).Visible = true
		self._janitor:Add((drop2Btn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onDrop()
		end))
	end

	-- Death icon: pop + rock animation
	local deathIcon = find(self._frame, "deathicon")
	self._deathIcon = deathIcon :: ImageLabel?
	self._deathIconScale = deathIcon and deathIcon:FindFirstChildOfClass("UIScale") :: UIScale?
	self._iconPopTween = nil :: Tween?
	self._iconRockTween = nil :: Tween?

	-- Timer bar: 30s countdown, auto-drops on expiry
	local timerFrame = find(self._frame, "Timer")
	self._timerFrame = timerFrame :: Frame?
	self._timerBar = timerFrame and find(timerFrame, "Bar") :: Frame?
	self._timerTween = nil :: Tween?

	-- Frame's root UIScale for custom slower open animation
	self._frameUIScale = self._frame:FindFirstChildOfClass("UIScale") :: UIScale?
	self._frameOpenTween = nil :: Tween?

	-- Wire Drop button
	if self._dropBtn then
		self._janitor:Add((self._dropBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onDrop()
		end))
	end

	-- Wire Keep button
	if self._keepBtn then
		self._janitor:Add((self._keepBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onKeep()
		end))
	end
end

function DiedModule:Start()
	if not self._frame then return end
	local ctx    = self._ctx
	local player = ctx.Player

	-- Listen for death notification from server
	local notifyRE = ctx.Net:GetEvent("Notify")
	self._janitor:Add(notifyRE.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.type == "died" then
			self:_show(payload)
		end
	end))

	-- Auto-close when character respawns (Drop/Keep succeeded)
	self._janitor:Add(player.CharacterAdded:Connect(function()
		self:_hide()
	end))
end

-- ── Animation constants ──────────────────────────────────────────────────────
local FRAME_OPEN_DURATION = 0.4   -- seconds for the whole Died frame to pop open
local ICON_POP_DURATION   = 0.525 -- seconds for deathicon scale 0→1
local ICON_ROCK_DURATION  = 1.5   -- seconds per rock cycle (±5°)
local ICON_ROCK_DEGREES   = 5     -- rotation amplitude
local TIMER_DURATION      = 30    -- seconds for the bar to drain

-- ── Show / Hide ──────────────────────────────────────────────────────────────

function DiedModule:_show(payload: any)
	if not self._frame then return end
	self._processing = false

	-- Update KeepCost label
	local keepCost = tonumber(payload.keepCost) or 1
	self._lastKeepCost = keepCost
	if self._keepCostLbl then
		(self._keepCostLbl :: TextLabel).Text = "-" .. fmt(keepCost)
	end

	-- Pre-set UIScale to 0 BEFORE Router:Open so the Router's fast tween
	-- starts from 0 and never visually flashes. Our slower tween below
	-- will override the Router's tween on the same UIScale property.
	if self._frameUIScale then
		(self._frameUIScale :: UIScale).Scale = 0
	end

	-- Open the Died frame WITHOUT sound (no cartoon_pop2)
	self._open = true
	if self._ctx.Router then
		self._ctx.Router:Open("Died")
	end

	-- Override the Router's fast open tween with our slower one
	if self._frameUIScale then
		local us = self._frameUIScale :: UIScale
		if self._frameOpenTween then
			(self._frameOpenTween :: Tween):Cancel()
		end
		us.Scale = 0
		local openInfo = TweenInfo.new(FRAME_OPEN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		self._frameOpenTween = TweenService:Create(us :: Instance, openInfo, { Scale = 1 })
		self._frameOpenTween:Play()
	end

	-- ── Death icon: pop scale 0→1, then rock ±5° ─────────────────────────
	self:_startIconAnim()

	-- ── Timer bar: show + drain over 30s, auto-drop on expiry ────────────
	self:_startTimer()
end

function DiedModule:_hide()
	if not self._frame then return end
	if not self._open then return end  -- already closed, prevent double-close
	self._open = false
	self._processing = false

	-- Stop animations
	self:_stopIconAnim()
	self:_stopTimer()

	if self._ctx.Router then
		self._ctx.Router:Close("Died")
	end
end

-- ── Actions ──────────────────────────────────────────────────────────────────

function DiedModule:_onDrop()
	if self._processing then return end
	self._processing = true

	-- Close immediately so the player sees instant feedback
	self:_hide()

	local rf = self._ctx.Net:GetFunction("DeathAction")
	task.spawn(function()
		local ok, result = pcall(function()
			return rf:InvokeServer({ action = "drop" })
		end)

		if not ok then
			warn("[DiedModule] Drop invoke error:", result)
			self:_show({ keepCost = 0 })  -- re-open on failure
			return
		end

		if type(result) == "table" and result.ok == false then
			warn("[DiedModule] Drop failed:", result.reason)
			self:_show({ keepCost = 0 })  -- re-open on failure
		end
	end)
end

function DiedModule:_onKeep()
	if self._processing then return end
	self._processing = true

	-- Close immediately so the player sees instant feedback
	self:_hide()

	local rf = self._ctx.Net:GetFunction("DeathAction")
	task.spawn(function()
		local ok, result = pcall(function()
			return rf:InvokeServer({ action = "keep" })
		end)

		if not ok then
			warn("[DiedModule] Keep invoke error:", result)
			self:_show({ keepCost = self._lastKeepCost or 1 })
			return
		end

		if type(result) == "table" and result.ok == false then
			-- Can't afford — re-open and shake the Keep button
			self:_show({ keepCost = self._lastKeepCost or 1 })
			if result.reason == "InsufficientCash" and self._keepBtn then
				shakeButton(self._keepBtn :: GuiButton)
			end
			return
		end
	end)
end

-- ── Death Icon Animation ─────────────────────────────────────────────────────

function DiedModule:_startIconAnim()
	self:_stopIconAnim()

	local us = self._deathIconScale :: UIScale?
	local icon = self._deathIcon :: ImageLabel?
	if not us or not icon then return end

	-- Start at scale 0
	us.Scale = 0

	-- Pop 0→1 with Back overshoot
	local popInfo = TweenInfo.new(ICON_POP_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	self._iconPopTween = TweenService:Create(us :: Instance, popInfo, { Scale = 1 })

	-- Once pop finishes, start the endless rock
	self._iconPopTween.Completed:Once(function()
		self._iconPopTween = nil
		if not self._open then return end

		-- Rock: start at -5°, tween to +5°, reverse infinitely
		icon.Rotation = -ICON_ROCK_DEGREES
		local rockInfo = TweenInfo.new(
			ICON_ROCK_DURATION,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,    -- repeat forever
			true   -- reverses
		)
		self._iconRockTween = TweenService:Create(icon :: Instance, rockInfo, { Rotation = ICON_ROCK_DEGREES })
		self._iconRockTween:Play()
	end)

	self._iconPopTween:Play()
end

function DiedModule:_stopIconAnim()
	if self._iconPopTween then
		self._iconPopTween:Cancel()
		self._iconPopTween = nil
	end
	if self._iconRockTween then
		self._iconRockTween:Cancel()
		self._iconRockTween = nil
	end
	-- Reset icon state for next death
	if self._deathIconScale then
		(self._deathIconScale :: UIScale).Scale = 0
	end
	if self._deathIcon then
		(self._deathIcon :: ImageLabel).Rotation = 0
	end
end

-- ── Timer Bar ────────────────────────────────────────────────────────────────

function DiedModule:_startTimer()
	self:_stopTimer()

	local timerFrame = self._timerFrame :: Frame?
	local bar = self._timerBar :: Frame?
	if not timerFrame or not bar then return end

	-- Show the timer frame and set bar to full width
	timerFrame.Visible = true
	bar.Size = UDim2.new(1, 0, bar.Size.Y.Scale, bar.Size.Y.Offset)

	-- Linear drain over TIMER_DURATION seconds
	local drainInfo = TweenInfo.new(TIMER_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
	self._timerTween = TweenService:Create(bar :: Instance, drainInfo, {
		Size = UDim2.new(0, 0, bar.Size.Y.Scale, bar.Size.Y.Offset),
	})

	-- When the bar reaches 0, auto-drop
	self._timerTween.Completed:Once(function()
		self._timerTween = nil
		if self._open and not self._processing then
			self:_onDrop()
		end
	end)

	self._timerTween:Play()
end

function DiedModule:_stopTimer()
	if self._timerTween then
		self._timerTween:Cancel()
		self._timerTween = nil
	end
	-- Hide timer frame
	if self._timerFrame then
		(self._timerFrame :: Frame).Visible = false
	end
end

-- ── Cleanup ──────────────────────────────────────────────────────────────────

function DiedModule:Destroy()
	self:_stopIconAnim()
	self:_stopTimer()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return DiedModule
