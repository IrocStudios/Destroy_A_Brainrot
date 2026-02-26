--!strict
-- GateModule.lua  |  Frame: Gate
-- Proximity-based gate purchase popup.
-- When player walks within RANGE studs of a locked gate, shows popup with
-- formatted price. Buy button purchases gate, fades gate model to invisible
-- and non-collidable. Close button or walking out of range dismisses popup.
-- Lockicon animates (pop + rock) while the popup is visible.
--
-- WIRE-UP (Studio frame hierarchy):
--   Gate [Frame]
--     container [Frame]
--       Input [Frame]
--         Buy [TextButton]
--       Frame [Frame]
--         lockicon [ImageLabel]
--           UIScale [UIScale]
--       Frame [Frame]
--         Title [TextLabel] "Unlock Gate: "
--         UnlockCost [TextLabel]
--       Title [TextLabel] "Locked!"
--     Backdrop [Frame]
--       Drop2 [TextButton] "X"   ← close button
--     UIScale [UIScale]          ← frame pop animation
--     UIAspectRatioConstraint

local RunService       = game:GetService("RunService")
local SoundService     = game:GetService("SoundService")
local TweenService     = game:GetService("TweenService")
local Workspace        = game:GetService("Workspace")

local GateModule = {}
GateModule.__index = GateModule

-- ── Constants ───────────────────────────────────────────────────────────────
local RANGE               = 30     -- studs to trigger popup
local PROX_INTERVAL       = 0.5    -- seconds between proximity checks
local FRAME_OPEN_DURATION = 0.4    -- seconds for popup to pop open
local ICON_POP_DURATION   = 0.525  -- seconds for lockicon scale 0→1
local ICON_ROCK_DURATION  = 1.5    -- seconds per rock cycle (±degrees)
local ICON_ROCK_DEGREES   = 5      -- rotation amplitude
local FADE_DURATION       = 0.8    -- seconds for gate model fade-out

-- ── Helpers ─────────────────────────────────────────────────────────────────

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

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function GateModule:Init(ctx: any)
	self._ctx         = ctx
	self._janitor     = ctx.UI.Cleaner.new()
	self._open        = false
	self._processing  = false
	self._activeGate  = nil :: any  -- currently displayed gate data
	self._proxTimer   = 0
	self._frame       = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Gate")

	if not self._frame then
		warn("[GateModule] Frame 'Gate' not found")
		return
	end

	-- Cache refs
	self._buyBtn        = find(self._frame, "Buy")        :: TextButton?
	self._closeBtn      = find(self._frame, "Drop2")      :: TextButton?
	self._unlockCostLbl = find(self._frame, "UnlockCost") :: TextLabel?
	self._lockIcon      = find(self._frame, "lockicon")    :: ImageLabel?
	self._lockIconScale = self._lockIcon and (self._lockIcon :: Instance):FindFirstChildOfClass("UIScale") :: UIScale?
	self._frameUIScale  = self._frame:FindFirstChildOfClass("UIScale") :: UIScale?

	-- Animation state
	self._frameOpenTween = nil :: Tween?
	self._iconPopTween   = nil :: Tween?
	self._iconRockTween  = nil :: Tween?

	-- Gate data cache: array of { model, order, price, stageId, part, unlocked }
	self._gates = {} :: { any }

	-- Gate unlock sounds from LocalResources/Sound
	local localRes = ctx.RootGui and ctx.RootGui:FindFirstChild("LocalResources")
	local soundFolder = localRes and localRes:FindFirstChild("Sound")
	self._unlockSound1 = soundFolder and soundFolder:FindFirstChild("GateUnlock1") :: Sound?
	self._unlockSound2 = soundFolder and soundFolder:FindFirstChild("GateUnlock2") :: Sound?

	-- Scan workspace gates
	self:_scanGates()

	-- Wire Buy button
	if self._buyBtn then
		self._janitor:Add((self._buyBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onBuy()
		end))
	end

	-- Wire Close (X) button (sound handled by ButtonFX, so no extra sound here)
	if self._closeBtn then
		self._janitor:Add((self._closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_hide(false)
		end))
	end

	print("[GateModule] Init OK")
end

function GateModule:Start()
	if not self._frame then return end

	-- Check initial unlock state — instantly hide already-unlocked gates
	self:_refreshUnlockStates(true)

	-- Listen for state changes (StageUnlocked updates)
	self._janitor:Add(self._ctx.State.Changed:Connect(function(_state, _deltas)
		self:_refreshUnlockStates(false)
	end))

	-- Proximity loop
	self._proxLoop = true
	task.spawn(function()
		while self._proxLoop do
			task.wait(PROX_INTERVAL)
			self:_proximityCheck()
		end
	end)

	print("[GateModule] Start OK")
end

-- ── Gate scanning ───────────────────────────────────────────────────────────

function GateModule:_scanGates()
	-- WaitForChild so we survive streaming / late replication
	local gatesFolder = Workspace:WaitForChild("Gates", 15)
	if not gatesFolder then
		warn("[GateModule] Workspace.Gates not found after 15s")
		return
	end

	self._gatesFolder = gatesFolder
	print("[GateModule] Gates folder found, scanning", #gatesFolder:GetChildren(), "gates")

	-- Register each gate in its own thread so WaitForChild doesn't block Init
	for _, gate in ipairs(gatesFolder:GetChildren()) do
		task.spawn(function()
			self:_registerGate(gate)
		end)
	end

	-- Listen for new gates added at runtime (streaming / late replication)
	self._janitor:Add(gatesFolder.ChildAdded:Connect(function(child)
		task.defer(function()
			self:_registerGate(child)
		end)
	end))
end

function GateModule:_registerGate(gate: Instance)
	-- Prevent duplicate registration (GetChildren + ChildAdded race)
	for _, existing in ipairs(self._gates) do
		if existing.model == gate then return end
	end

	local order = gate:GetAttribute("Order")
	local price = gate:GetAttribute("Price") or 0
	-- stageId: prefer StageId attribute, fall back to Order (matches GateService)
	local stageId = gate:GetAttribute("StageId") or tostring(order or "")

	-- Resolve position anchor part — wait for parts to stream in
	local part: BasePart? = nil
	if gate:IsA("Model") then
		part = gate.PrimaryPart or gate:FindFirstChildWhichIsA("BasePart")
		if not part then
			-- Parts haven't streamed in yet — wait for one
			part = gate:WaitForChild("Core", 15) :: BasePart?
			if not part then
				part = gate:FindFirstChildWhichIsA("BasePart")
			end
		end
	elseif gate:IsA("BasePart") then
		part = gate :: BasePart
	end
	if not part then
		warn("[GateModule] No BasePart found in gate:", gate.Name)
		return
	end

	-- Disable any server-created ProximityPrompts (we use our own range detection)
	for _, desc in ipairs(gate:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			desc.Enabled = false
		end
	end

	local gateData = {
		model   = gate,
		order   = order,
		price   = price,
		stageId = stageId,
		part    = part,
		unlocked = false,
	}
	table.insert(self._gates, gateData)

	-- Update SurfaceGui price on the gate model immediately
	self:_updateGateSurfacePrice(gateData)

	print(("[GateModule] Registered gate: %s | StageId=%s | Price=%s"):format(
		gate.Name, tostring(stageId), tostring(price)))
end

-- ── Unlock state sync ───────────────────────────────────────────────────────

function GateModule:_refreshUnlockStates(instant: boolean)
	local state = self._ctx.State.State
	local stageUnlocked = state and state.Progression and state.Progression.StageUnlocked

	for _, gateData in ipairs(self._gates) do
		local wasUnlocked = gateData.unlocked
		local isUnlocked = false

		if typeof(stageUnlocked) == "table" then
			isUnlocked = stageUnlocked[gateData.stageId] == true
		end

		gateData.unlocked = isUnlocked

		-- Fade out gate if it just became unlocked (or was already on load)
		if isUnlocked and not wasUnlocked then
			self:_fadeOutGate(gateData, instant)
		end
	end
end

-- ── Proximity ───────────────────────────────────────────────────────────────

function GateModule:_proximityCheck()
	if self._processing then return end

	local player = self._ctx.Player
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		if self._open then self:_hide(true) end
		return
	end

	local playerPos = (hrp :: BasePart).Position

	-- Find nearest locked gate within range
	local nearestGate = nil
	local nearestDist = RANGE + 1

	for _, gateData in ipairs(self._gates) do
		if not gateData.unlocked and gateData.part and gateData.part.Parent then
			local dist = (gateData.part.Position - playerPos).Magnitude
			if dist <= RANGE and dist < nearestDist then
				nearestDist = dist
				nearestGate = gateData
			end
		end
	end

	if nearestGate then
		if not self._open then
			self:_show(nearestGate)
		elseif self._activeGate ~= nearestGate then
			-- Switched to a different gate while popup was open
			self:_hide(true)
			self:_show(nearestGate)
		end
	else
		if self._open then
			-- Walked out of range — play click sound on close
			self:_hide(true)
		end
	end
end

-- ── Show / Hide ─────────────────────────────────────────────────────────────

function GateModule:_show(gateData: any)
	if not self._frame then return end
	if self._open then return end  -- prevent double-show

	self._activeGate = gateData

	-- Update UnlockCost label
	if self._unlockCostLbl then
		(self._unlockCostLbl :: TextLabel).Text = fmt(gateData.price)
	end

	-- Update SurfaceGui Price on the gate model itself
	self:_updateGateSurfacePrice(gateData)

	-- Pre-set UIScale to 0 BEFORE Router:Open so the Router's fast tween
	-- starts from 0 and never visually flashes.
	if self._frameUIScale then
		(self._frameUIScale :: UIScale).Scale = 0
	end

	-- Pop sound on open (same as ButtonFX press sound)
	pcall(function() SoundService.cartoon_pop:Play() end)

	-- Open via Router
	self._open = true
	if self._ctx.Router then
		self._ctx.Router:Open("Gate")
	end

	-- Override Router's fast open tween with our slower Back tween
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

	-- Start lockicon animation (pop + rock)
	self:_startLockIconAnim()
end

function GateModule:_hide(playSound: boolean?)
	if not self._frame then return end
	if not self._open then return end
	self._open = false
	self._activeGate = nil

	-- Play button click sound (same as ButtonFX) when dismissing
	if playSound then
		pcall(function() SoundService.cartoon_pop2:Play() end)
	end

	-- Stop animations
	self:_stopLockIconAnim()

	if self._frameOpenTween then
		self._frameOpenTween:Cancel()
		self._frameOpenTween = nil
	end

	if self._ctx.Router then
		self._ctx.Router:Close("Gate")
	end
end

-- ── Buy action ──────────────────────────────────────────────────────────────

function GateModule:_onBuy()
	if self._processing then return end
	if not self._activeGate then return end
	self._processing = true

	local gateData = self._activeGate

	-- Close immediately for instant feedback (no sound — unlock sounds play on success)
	self:_hide(false)

	local rf = self._ctx.Net:GetFunction("GateAction")
	task.spawn(function()
		local ok, result, reason = pcall(function()
			return rf:InvokeServer({
				stageId = gateData.stageId,
				price   = gateData.price,
				accept  = true,
			})
		end)

		if not ok then
			warn("[GateModule] Buy invoke error:", result)
			self._processing = false
			return
		end

		-- GateService returns (bool, string) via RouteAction
		-- result = true/false, reason = "Unlocked"/"InsufficientFunds"/etc.
		if result == false then
			-- Purchase failed — re-open popup and shake Buy button
			self._processing = false
			self:_show(gateData)
			if self._buyBtn then
				shakeButton(self._buyBtn :: GuiButton)
			end
			return
		end

		-- Success! Play unlock sounds, mark as unlocked, fade gate model
		if self._unlockSound1 then self._unlockSound1:Play() end
		if self._unlockSound2 then self._unlockSound2:Play() end
		gateData.unlocked = true
		self:_fadeOutGate(gateData, false)
		self._processing = false
	end)
end

-- ── Gate model fade-out ─────────────────────────────────────────────────────

function GateModule:_fadeOutGate(gateData: any, instant: boolean?)
	local model = gateData.model
	if not model or not model.Parent then return end

	if instant then
		-- Instantly hide — used for already-unlocked gates on join
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
				desc.Transparency = 1
			elseif desc:IsA("SurfaceGui") or desc:IsA("BillboardGui") then
				desc.Enabled = false
			elseif desc:IsA("Light") then
				desc.Enabled = false
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				desc.Transparency = 1
			end
		end
	else
		-- Animate fade
		local fadeInfo = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, desc in ipairs(model:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
				TweenService:Create(desc, fadeInfo, { Transparency = 1 }):Play()
			elseif desc:IsA("SurfaceGui") or desc:IsA("BillboardGui") then
				desc.Enabled = false
			elseif desc:IsA("Light") then
				desc.Enabled = false
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				TweenService:Create(desc, fadeInfo, { Transparency = 1 }):Play()
			end
		end
	end
end

-- ── SurfaceGui price update ─────────────────────────────────────────────────

function GateModule:_updateGateSurfacePrice(gateData: any)
	local model = gateData.model
	if not model then return end

	-- Gate model → Core → SurfaceGui → Frame → Frame → Price [TextLabel]
	local priceLbl = find(model, "Price")
	if priceLbl and priceLbl:IsA("TextLabel") then
		priceLbl.Text = fmt(gateData.price)
	end
end

-- ── Lock Icon Animation ─────────────────────────────────────────────────────
-- Same pattern as DiedModule: pop 0→1 (Back easing), then rock ±degrees forever.

function GateModule:_startLockIconAnim()
	self:_stopLockIconAnim()

	local us   = self._lockIconScale :: UIScale?
	local icon = self._lockIcon :: ImageLabel?
	if not us or not icon then return end

	-- Start at scale 0
	(us :: UIScale).Scale = 0

	-- Pop 0→1 with Back overshoot
	local popInfo = TweenInfo.new(ICON_POP_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	self._iconPopTween = TweenService:Create(us :: Instance, popInfo, { Scale = 1 })

	-- Once pop finishes, start the endless rock
	self._iconPopTween.Completed:Once(function()
		self._iconPopTween = nil
		if not self._open then return end

		-- Rock: start at -degrees, tween to +degrees, reverse infinitely
		(icon :: ImageLabel).Rotation = -ICON_ROCK_DEGREES
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

function GateModule:_stopLockIconAnim()
	if self._iconPopTween then
		self._iconPopTween:Cancel()
		self._iconPopTween = nil
	end
	if self._iconRockTween then
		self._iconRockTween:Cancel()
		self._iconRockTween = nil
	end
	-- Reset icon state for next show
	if self._lockIconScale then
		(self._lockIconScale :: UIScale).Scale = 0
	end
	if self._lockIcon then
		(self._lockIcon :: ImageLabel).Rotation = 0
	end
end

-- ── Cleanup ─────────────────────────────────────────────────────────────────

function GateModule:Destroy()
	self._proxLoop = false
	self:_stopLockIconAnim()
	if self._frameOpenTween then self._frameOpenTween:Cancel() end
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return GateModule
