--!strict
-- SpeedController.client.lua
-- Standalone sprint + walkspeed controller.
-- Sole authority for Humanoid.WalkSpeed — always active, weapon or not.
-- ADS slowdown communicated via IsADS BoolValue on character (set by ShoulderCamera).

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

-- SpringService from WeaponsSystem for smooth speed transitions
local SpringService = require(
	ReplicatedStorage:WaitForChild("WeaponsSystem"):WaitForChild("Libraries"):WaitForChild("SpringService")
)

-- ── Constants ────────────────────────────────────────────────────────────────
local BASE_WALK_SPEED   = 16
local SPRINT_BONUS      = 8
local SPRING_DAMPING    = 0.95
local SPRING_FREQ       = 4
local SPRINT_ACTION     = "SpeedControllerSprint"
local SPRINT_INPUTS     = { Enum.KeyCode.LeftShift }
local THUMBSTICK_SPRINT = 0.9 -- 90%+ thumbstick = auto-sprint

-- ── State ────────────────────────────────────────────────────────────────────
local currentHumanoid: Humanoid? = nil
local currentCharacter: Model? = nil
local controlModule: any = nil

local sprintKeyHeld      = false
local isADS              = false
local speedBoost         = 0   -- from speed shop purchases (future)
local gamepadMoveMag     = 0   -- magnitude of gamepad left stick

-- ── Input ────────────────────────────────────────────────────────────────────

local function onSprintAction(_actionName: string, inputState: Enum.UserInputState, _inputObj: InputObject)
	sprintKeyHeld = inputState == Enum.UserInputState.Begin
end

local function isTouchSprinting(): boolean
	if not controlModule then return false end
	local ok, moveVector = pcall(function() return controlModule:GetMoveVector() end)
	if not ok or not moveVector then return false end
	local ok2, activeCtrl = pcall(function() return controlModule:GetActiveController() end)
	if not ok2 or not activeCtrl then return false end
	local isTouch = activeCtrl.thumbstickFrame ~= nil or activeCtrl.thumbpadFrame ~= nil
	if isTouch then
		return moveVector.Magnitude >= THUMBSTICK_SPRINT
	end
	return false
end

local function isGamepadSprinting(): boolean
	return gamepadMoveMag > THUMBSTICK_SPRINT
end

local function isSprinting(): boolean
	return sprintKeyHeld or isTouchSprinting() or isGamepadSprinting()
end

-- ── Gamepad thumbstick tracking ──────────────────────────────────────────────

local function onInputChanged(inputObj: InputObject, _processed: boolean)
	if inputObj.KeyCode == Enum.KeyCode.Thumbstick1 then
		gamepadMoveMag = Vector2.new(inputObj.Position.X, inputObj.Position.Y).Magnitude
	end
end

local function onInputEnded(inputObj: InputObject, _processed: boolean)
	if inputObj.KeyCode == Enum.KeyCode.Thumbstick1 then
		gamepadMoveMag = 0
	end
end

-- ── Per-frame speed update ───────────────────────────────────────────────────

local function onHeartbeat()
	if not currentHumanoid or currentHumanoid.Health <= 0 then return end

	local baseSpeed = BASE_WALK_SPEED + speedBoost

	local targetSpeed: number
	if isADS then
		targetSpeed = baseSpeed / 2
	elseif isSprinting() then
		targetSpeed = baseSpeed + SPRINT_BONUS
	else
		targetSpeed = baseSpeed
	end

	SpringService:Target(currentHumanoid, SPRING_DAMPING, SPRING_FREQ, { WalkSpeed = targetSpeed })
end

-- ── Character setup ──────────────────────────────────────────────────────────

local function onCharacterAdded(character: Model)
	currentCharacter = character

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	currentHumanoid = humanoid
	humanoid.WalkSpeed = BASE_WALK_SPEED + speedBoost

	-- Create IsADS BoolValue for WeaponsSystem to write to
	if not character:FindFirstChild("IsADS") then
		local adsVal = Instance.new("BoolValue")
		adsVal.Name = "IsADS"
		adsVal.Value = false
		adsVal.Parent = character
		adsVal.Changed:Connect(function(val)
			isADS = val
		end)
	else
		local existing = character:FindFirstChild("IsADS") :: BoolValue
		isADS = existing.Value
		existing.Changed:Connect(function(val)
			isADS = val
		end)
	end

	-- Acquire control module for touch sprint detection
	local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
	if playerScripts then
		local playerModule = playerScripts:FindFirstChild("PlayerModule")
		if playerModule then
			local cm = playerModule:FindFirstChild("ControlModule")
			if cm then
				local ok, mod = pcall(require, cm)
				if ok then controlModule = mod end
			end
		end
	end
end

local function onCharacterRemoving()
	currentHumanoid = nil
	currentCharacter = nil
	controlModule = nil
	sprintKeyHeld = false
	isADS = false
	gamepadMoveMag = 0
end

-- ── Boot ─────────────────────────────────────────────────────────────────────

ContextActionService:BindAction(SPRINT_ACTION, onSprintAction, false, unpack(SPRINT_INPUTS))

RunService.Heartbeat:Connect(onHeartbeat)
UserInputService.InputChanged:Connect(onInputChanged)
UserInputService.InputEnded:Connect(onInputEnded)

LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
LocalPlayer.CharacterRemoving:Connect(onCharacterRemoving)
if LocalPlayer.Character then
	task.spawn(onCharacterAdded, LocalPlayer.Character)
end

print("[SpeedController] Started")
