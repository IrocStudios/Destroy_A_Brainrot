--!strict
-- BuySpeedModule.lua  |  Frame: BuySpeed
-- Proximity-based speed upgrade popup.
-- Speed is a persistent upgrade — each purchase adds +1 WalkSpeed
-- (formula-driven via SpeedConfig.GetStep).  104 total steps (16 → 120).
--
-- Scans Workspace.BuyStands for PriceBrick descendants with BuySpeed (ObjectValue)
-- pointing to the Speed shop asset. When player walks within RANGE studs, shows popup
-- with current speed, +amount, and cost. Buy sends ShopAction RF; frame stays open
-- and refreshes with new step info after each purchase.
--
-- WIRE-UP (Studio frame hierarchy):
--   BuySpeed [Frame]
--     Canvas [CanvasGroup]
--       Header > Title [TextLabel]
--       Header > Shines > Shine [Frame] (spin continuously)
--     Stud [ImageLabel]
--     XButton [TextButton]
--     UIScale [UIScale]
--     container [Frame]
--       infobox [Frame]
--         upgradeinfo [Frame]
--           label [TextLabel] ("Increase Speed")
--           stats [Frame]
--             Before [TextLabel] — current speed value
--             After  [TextLabel] — speed after purchase
--         shoeicon [Frame]
--           Icon [ImageLabel]
--             Shine [ImageLabel] — spin continuously
--       costbox [Frame]
--         Cost [TextLabel]
--       Options [Frame]
--         No [TextButton]
--         Yes [TextButton]

local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local TweenService         = game:GetService("TweenService")
local SoundService         = game:GetService("SoundService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace            = game:GetService("Workspace")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")

local BuySpeedModule = {}
BuySpeedModule.__index = BuySpeedModule

-- ── Constants ───────────────────────────────────────────────────────────────
local RANGE               = 10      -- studs to trigger popup
local PROX_INTERVAL       = 0.5     -- seconds between proximity checks
local FRAME_OPEN_DURATION = 0.4     -- seconds for popup to pop open
local INTERACT_ACTION     = "BuySpeedInteract" -- ContextActionService action name

-- Icon animation
local ICON_ROCK_DEGREES   = 2
local ICON_ROCK_DURATION  = 1.5

-- Shine spin
local SHINE_SPIN_DURATION = 4

-- Display shoe float animation (matches BuyWeapon / BuyArmor display model)
local BOB_AMPLITUDE       = 0.5
local BOB_PERIOD_MIN      = 8
local BOB_PERIOD_MAX      = 14
local ROCK_DEGREES        = 10
local ROCK_PERIOD         = 12.6
local LEAN_DEGREES        = 7.5
local LEAN_PERIOD         = 16.5

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e9 then return ("$%.2fb"):format(n / 1e9) end
	if n >= 1e6 then return ("$%.2fm"):format(n / 1e6) end
	if n >= 1e3 then return ("$%.2fk"):format(n / 1e3) end
	return "$" .. tostring(n)
end

local function getSpeedBoost(ctx: any): number
	local s = (ctx.State and ctx.State.State) or {}
	return (s.Progression and tonumber(s.Progression.SpeedBoost)) or 0
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

-- ── SpeedConfig access ──────────────────────────────────────────────────────

local _speedConfig: any = nil

local function getSpeedConfig(): any
	if _speedConfig then return _speedConfig end
	local ok, cfg = pcall(function()
		local shared = ReplicatedStorage:WaitForChild("Shared", 5)
		local cfgFolder = shared and shared:WaitForChild("Config", 5)
		return cfgFolder and require(cfgFolder:WaitForChild("SpeedConfig", 5))
	end)
	if ok and cfg then _speedConfig = cfg end
	return _speedConfig
end

local function getStepValues(step: number): (number, number)
	local cfg = getSpeedConfig()
	if cfg and cfg.GetStep then
		return cfg.GetStep(step)
	end
	-- Fallback if config not loaded
	return 1, 500
end

local function getBaseSpeed(): number
	local cfg = getSpeedConfig()
	return (cfg and cfg.BaseSpeed) or 16
end

-- Effective step based on current speed boost (not purchase count).
-- Future-proof: if speed could ever be lost, this ensures correct pricing.
local function getSpeedStep(ctx: any): number
	local boost = getSpeedBoost(ctx)
	local cfg = getSpeedConfig()
	if cfg and cfg.GetEffectiveStep then
		return cfg.GetEffectiveStep(boost)
	end
	return 0
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function BuySpeedModule:Init(ctx: any)
	self._ctx             = ctx
	self._janitor         = ctx.UI.Cleaner.new()
	self._open            = false
	self._processing      = false
	self._activeStand     = nil :: any
	self._stands          = {} :: { any }
	self._displayShoes    = {} :: { any } -- { {model, connection} }
	self._frame           = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("BuySpeed")

	if not self._frame then
		warn("[BuySpeedModule] Frame 'BuySpeed' not found")
		return
	end

	-- Cache refs
	self._frameUIScale   = self._frame:FindFirstChildOfClass("UIScale") :: UIScale?
	self._frameOpenTween = nil :: Tween?

	-- Buttons
	self._yesBtn   = find(self._frame, "Yes")     :: TextButton?
	self._noBtn    = find(self._frame, "No")       :: TextButton?
	self._closeBtn = find(self._frame, "XButton")  :: TextButton?

	-- Info labels
	self._beforeLbl = find(self._frame, "Before")  :: TextLabel?
	self._afterLbl  = find(self._frame, "After")   :: TextLabel?
	self._costLbl   = find(self._frame, "Cost")    :: TextLabel?

	-- Shoe icon (for rock animation)
	local shoeIcon = find(self._frame, "shoeicon")
	self._shoeIcon = shoeIcon and shoeIcon:FindFirstChild("Icon") :: ImageLabel?

	-- Shine (for spin animation) — inside Icon
	self._shine = self._shoeIcon and (self._shoeIcon :: Instance):FindFirstChild("Shine") :: ImageLabel?

	-- Animation tweens
	self._iconRockTween   = nil :: Tween?
	self._shineTween      = nil :: Tween?

	-- Wire Yes button → buy
	if self._yesBtn then
		self._janitor:Add((self._yesBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onBuy()
		end))
	end

	-- Wire No button → decline
	if self._noBtn then
		self._janitor:Add((self._noBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onDecline()
		end))
	end

	-- Wire X button → same as decline
	if self._closeBtn then
		self._janitor:Add((self._closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onDecline()
		end))
	end

	-- Scan buy stands
	self:_scanStands()

	print("[BuySpeedModule] Init OK")
end

function BuySpeedModule:Start()
	if not self._frame then return end

	-- Proximity loop
	self._proxLoop = true
	task.spawn(function()
		while self._proxLoop do
			task.wait(PROX_INTERVAL)
			self:_proximityCheck()
		end
	end)

	-- Listen for state changes to refresh values while popup is open
	self._janitor:Add(self._ctx.State.Changed:Connect(function(_, _)
		if self._open and self._activeStand then
			self:_refreshValues()
			self:_updateBillboards()
		end
	end))

	print("[BuySpeedModule] Start OK")
end

-- ── Stand scanning ─────────────────────────────────────────────────────────

function BuySpeedModule:_scanStands()
	local standsFolder = Workspace:WaitForChild("BuyStands", 15)
	if not standsFolder then
		warn("[BuySpeedModule] Workspace.BuyStands not found after 15s")
		return
	end

	self._standsFolder = standsFolder

	-- Scan all descendants for PriceBrick with BuySpeed child
	for _, desc in ipairs(standsFolder:GetDescendants()) do
		if desc.Name == "PriceBrick" and desc:IsA("BasePart") then
			self:_registerStand(desc)
		end
	end

	-- Listen for new stands added at runtime
	self._janitor:Add(standsFolder.DescendantAdded:Connect(function(child)
		if child.Name == "PriceBrick" and child:IsA("BasePart") then
			task.defer(function()
				self:_registerStand(child)
			end)
		end
	end))
end

function BuySpeedModule:_registerStand(priceBrick: BasePart)
	-- Prevent duplicate registration
	for _, existing in ipairs(self._stands) do
		if existing.priceBrick == priceBrick then return end
	end

	-- Must have BuySpeed (ObjectValue) child pointing to Speed shop asset
	local buySpeedOV = priceBrick:FindFirstChild("BuySpeed")
	if not buySpeedOV or not buySpeedOV:IsA("ObjectValue") then return end

	local speedAsset = buySpeedOV.Value
	if not speedAsset then
		warn("[BuySpeedModule] BuySpeed OV has no Value on PriceBrick:", priceBrick:GetFullName())
		return
	end

	local standData = {
		priceBrick = priceBrick,
		speedAsset = speedAsset,
		dismissed  = false,
		inRange    = false,
	}
	table.insert(self._stands, standData)

	-- Spawn floating shoe display model
	self:_spawnDisplayShoe(standData)

	-- Initial billboard update
	self:_updateStandBillboard(standData)

	print(("[BuySpeedModule] Registered speed stand: %s"):format(priceBrick:GetFullName()))
end

-- ── Billboard update ──────────────────────────────────────────────────────

function BuySpeedModule:_updateStandBillboard(standData: any)
	local priceBrick = standData.priceBrick

	-- Walk up to stand root
	local standRoot = priceBrick
	while standRoot and standRoot.Parent ~= self._standsFolder do
		standRoot = standRoot.Parent
	end
	if not standRoot then return end

	local currentStep = getSpeedStep(self._ctx)
	local amount, price = getStepValues(currentStep)
	local isMaxed = (amount == 0)

	for _, desc in ipairs(standRoot:GetDescendants()) do
		if desc:IsA("BillboardGui") then
			local frame = desc:FindFirstChild("Frame")
			if not frame then continue end

			-- Title label (amount preview)
			local titleLbl = frame:FindFirstChild("Title") :: TextLabel?
			if titleLbl then
				titleLbl.Text = isMaxed and "MAX Speed" or ("+" .. tostring(amount) .. " Speed")
			end

			-- Value label (price)
			local valueLbl = frame:FindFirstChild("Value") :: TextLabel?
			if valueLbl then
				valueLbl.Text = isMaxed and "MAX" or fmt(price)
			end
			break
		end
	end
end

function BuySpeedModule:_updateBillboards()
	for _, standData in ipairs(self._stands) do
		self:_updateStandBillboard(standData)
	end
end

-- ── Display shoe (floating model in glass tube) ─────────────────────────

function BuySpeedModule:_spawnDisplayShoe(standData: any)
	local priceBrick = standData.priceBrick

	-- Find stand root
	local standRoot = priceBrick
	while standRoot and standRoot.Parent ~= self._standsFolder do
		standRoot = standRoot.Parent
	end
	if not standRoot then return end

	-- Find the Shoe model
	local shoeModel: Model? = nil
	for _, desc in ipairs(standRoot:GetDescendants()) do
		if desc.Name == "Shoe" and desc:IsA("Model") then
			shoeModel = desc :: Model
			break
		end
	end
	if not shoeModel then return end

	-- Anchor all parts
	for _, desc in ipairs(shoeModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end

	-- Store the base CFrame for animation
	local baseCF = shoeModel:GetBoundingBox()

	-- Start Heartbeat animation: bob + rock + lean
	local startTime = os.clock()
	local bobPeriod = BOB_PERIOD_MIN + math.random() * (BOB_PERIOD_MAX - BOB_PERIOD_MIN)
	local connection = RunService.Heartbeat:Connect(function()
		if not shoeModel or not shoeModel.Parent then return end
		local t = os.clock() - startTime

		-- Bob: sine wave on Y axis
		local bobY = math.sin(t * (2 * math.pi / bobPeriod)) * BOB_AMPLITUDE

		-- Rock: Y-axis rotation
		local rockAngle = math.rad(math.sin(t * (2 * math.pi / ROCK_PERIOD)) * ROCK_DEGREES)

		-- Lean: Z-axis sway
		local leanAngle = math.rad(math.sin(t * (2 * math.pi / LEAN_PERIOD)) * LEAN_DEGREES)

		local animCF = baseCF
			* CFrame.new(0, bobY, 0)
			* CFrame.Angles(0, rockAngle, leanAngle)

		shoeModel:PivotTo(animCF)
	end)

	table.insert(self._displayShoes, {
		model      = shoeModel,
		connection = connection,
	})
end

-- ── Proximity ───────────────────────────────────────────────────────────────

function BuySpeedModule:_proximityCheck()
	if self._processing then return end

	local player = self._ctx.Player
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		if self._open then self:_hide(true) end
		return
	end

	local playerPos = (hrp :: BasePart).Position

	-- Find nearest stand within range
	local nearestStand = nil
	local nearestDist  = RANGE + 1

	for _, standData in ipairs(self._stands) do
		local brick = standData.priceBrick
		if brick and brick.Parent then
			local dist = (brick.Position - playerPos).Magnitude
			local wasInRange = standData.inRange
			standData.inRange = dist <= RANGE

			-- Clear dismissed when player leaves range
			if wasInRange and not standData.inRange then
				standData.dismissed = false
			end

			if standData.inRange and dist < nearestDist then
				nearestDist = dist
				nearestStand = standData
			end
		end
	end

	-- Show/hide logic
	if nearestStand and not nearestStand.dismissed then
		if not self._open then
			self:_show(nearestStand)
		elseif self._activeStand ~= nearestStand then
			self:_hide(true)
			self:_show(nearestStand)
		end
	else
		if self._open then
			self:_hide(true)
		end
	end
end

-- ── Show / Hide ─────────────────────────────────────────────────────────────

function BuySpeedModule:_show(standData: any)
	if not self._frame then return end
	if self._open then return end

	self._activeStand = standData

	-- Populate values
	self:_refreshValues()

	-- Start icon animations (shine spin + icon rock)
	self:_startIconAnim()
	self:_startShineSpin()

	-- Pop sound
	pcall(function() SoundService.cartoon_pop:Play() end)

	self._open = true

	-- Direct UIScale tween (no Router — BuySpeed must persist across purchases)
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

	-- Bind 'E' key to purchase
	ContextActionService:BindAction(INTERACT_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self:_onBuy()
		end
	end, false, Enum.KeyCode.E)
end

function BuySpeedModule:_hide(playSound: boolean?)
	if not self._frame then return end
	if not self._open then return end
	if self._processing then return end -- Don't close during an active purchase
	self._open = false
	self._activeStand = nil

	-- Unbind 'E' key
	ContextActionService:UnbindAction(INTERACT_ACTION)

	-- Stop icon animations
	self:_stopIconAnim()
	self:_stopShineSpin()

	if playSound then
		pcall(function() SoundService.cartoon_pop2:Play() end)
	end

	-- Direct UIScale close tween (no Router)
	if self._frameOpenTween then
		self._frameOpenTween:Cancel()
		self._frameOpenTween = nil
	end
	if self._frameUIScale then
		local us = self._frameUIScale :: UIScale
		local closeInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(us :: Instance, closeInfo, { Scale = 0 }):Play()
	end
end

-- ── Refresh values ──────────────────────────────────────────────────────────

function BuySpeedModule:_refreshValues()
	local currentStep  = getSpeedStep(self._ctx)
	local currentBoost = getSpeedBoost(self._ctx)
	local baseSpeed    = getBaseSpeed()
	local currentSpeed = math.floor(baseSpeed + currentBoost)
	local amount, price = getStepValues(currentStep)
	local isMaxed = (amount == 0) -- GetStep returns 0,0 when maxed

	-- Before = current total speed
	if self._beforeLbl then
		local text = tostring(currentSpeed)
		local lbl = self._beforeLbl :: TextLabel
		lbl.Text = text
		local title = (self._beforeLbl :: Instance):FindFirstChild("Title") :: TextLabel?
		if title then title.Text = text end
	end

	-- After = current speed + amount (or "MAX")
	if self._afterLbl then
		local text = isMaxed and "MAX" or tostring(currentSpeed + amount)
		local lbl = self._afterLbl :: TextLabel
		lbl.Text = text
		local title = (self._afterLbl :: Instance):FindFirstChild("Title") :: TextLabel?
		if title then title.Text = text end
	end

	-- Cost
	if self._costLbl then
		local lbl = self._costLbl :: TextLabel
		lbl.Text = isMaxed and "MAX" or fmt(price)
	end

	-- Yes button: "Buy" or "Maxed"
	if self._yesBtn then
		local label = isMaxed and "Maxed" or "Buy"
		local titleFrame = find(self._yesBtn, "Title") :: TextLabel?
		if titleFrame then
			local innerTitle = titleFrame:FindFirstChild("Title") :: TextLabel?
			if innerTitle then innerTitle.Text = label end
			titleFrame.Text = label
		end
	end
end

-- ── Icon animation (rock) ──────────────────────────────────────────────────

function BuySpeedModule:_startIconAnim()
	self:_stopIconAnim()

	local icon = self._shoeIcon :: ImageLabel?
	if not icon then return end

	local img = icon :: ImageLabel
	img.Rotation = -ICON_ROCK_DEGREES
	local rockInfo = TweenInfo.new(
		ICON_ROCK_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,    -- repeat forever
		true   -- reverses
	)
	self._iconRockTween = TweenService:Create(icon :: Instance, rockInfo, { Rotation = ICON_ROCK_DEGREES })
	self._iconRockTween:Play()
end

function BuySpeedModule:_stopIconAnim()
	if self._iconRockTween then
		self._iconRockTween:Cancel()
		self._iconRockTween = nil
	end
	if self._shoeIcon then
		local img = self._shoeIcon :: ImageLabel
		img.Rotation = 0
	end
end

-- ── Shine spin ──────────────────────────────────────────────────────────────

function BuySpeedModule:_startShineSpin()
	self:_stopShineSpin()

	local shine = self._shine :: ImageLabel?
	if not shine then return end

	local shineImg = shine :: ImageLabel
	shineImg.Rotation = 0
	local spinInfo = TweenInfo.new(
		SHINE_SPIN_DURATION,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.InOut,
		-1,    -- repeat forever
		false  -- no reverse
	)
	self._shineTween = TweenService:Create(shine :: Instance, spinInfo, { Rotation = 360 })
	self._shineTween:Play()
end

function BuySpeedModule:_stopShineSpin()
	if self._shineTween then
		self._shineTween:Cancel()
		self._shineTween = nil
	end
	if self._shine then
		local shineImg = self._shine :: ImageLabel
		shineImg.Rotation = 0
	end
end

-- ── Buy action ──────────────────────────────────────────────────────────────

function BuySpeedModule:_onBuy()
	if self._processing then return end
	if not self._activeStand then return end

	-- Check maxed client-side before sending request
	local amount, _ = getStepValues(getSpeedStep(self._ctx))
	if amount == 0 then
		if self._yesBtn then shakeButton(self._yesBtn :: GuiButton) end
		return
	end

	self._processing = true

	local rf = self._ctx.Net:GetFunction("ShopAction")
	task.spawn(function()
		local ok, result = pcall(function()
			return rf:InvokeServer({
				action = "buySpeed",
			})
		end)

		if not ok then
			warn("[BuySpeedModule] Buy invoke error:", result)
			self._processing = false
			return
		end

		if type(result) == "table" and result.ok then
			-- Success! Frame stays open — just refresh values
			pcall(function() SoundService.cartoon_pop:Play() end)
			self:_refreshValues()
			self:_updateBillboards()
		else
			-- Failed — shake the buy button
			if self._yesBtn then
				shakeButton(self._yesBtn :: GuiButton)
			end
		end

		self._processing = false
	end)
end

-- ── Decline action ──────────────────────────────────────────────────────────

function BuySpeedModule:_onDecline()
	if self._activeStand then
		self._activeStand.dismissed = true
	end
	self:_hide(false)
end

-- ── Cleanup ─────────────────────────────────────────────────────────────────

function BuySpeedModule:Destroy()
	self._proxLoop = false
	pcall(function() ContextActionService:UnbindAction(INTERACT_ACTION) end)
	if self._frameOpenTween then self._frameOpenTween:Cancel() end
	self:_stopIconAnim()
	self:_stopShineSpin()

	-- Clean up display shoes
	for _, entry in ipairs(self._displayShoes) do
		if entry.connection then entry.connection:Disconnect() end
	end
	self._displayShoes = {}

	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return BuySpeedModule
