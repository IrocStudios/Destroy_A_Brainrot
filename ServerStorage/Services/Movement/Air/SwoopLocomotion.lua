--!strict
-- SwoopLocomotion
-- Flying locomotion with circling patrol and dive-bomb attack approach.
-- Extends the same AlignPosition/AlignOrientation pattern as FlyLocomotion
-- but adds a circling idle behavior and a dive phase for attacks.

local Workspace = game:GetService("Workspace")

local SwoopLocomotion = {}
SwoopLocomotion.Name = "Swoop"
SwoopLocomotion.Type = "Air"

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[SwoopLoco]", ...) end
end

export type SwoopState = {
	AlignPos: AlignPosition?,
	AlignOri: AlignOrientation?,
	Attachment: Attachment?,
	CruiseAltitude: number,
	CircleAngle: number,
	CircleRadius: number,
	CircleCenter: Vector3,
	Phase: "Cruise" | "Dive" | "Recover",
	DiveStartY: number,
	Initialized: boolean,
}

local DEFAULT_ALTITUDE = 40
local CIRCLE_RADIUS = 25
local CIRCLE_SPEED = 0.8 -- radians per second
local MOVE_RESPONSIVENESS = 10
local ORIENT_RESPONSIVENESS = 8
local MAX_FORCE = 50000
local DIVE_RESPONSIVENESS = 20
local RECOVER_ALTITUDE_OFFSET = 10 -- studs above cruise to recover to

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function getState(entry: any): SwoopState
	if not entry._swoopLoco then
		entry._swoopLoco = {
			AlignPos = nil,
			AlignOri = nil,
			Attachment = nil,
			CruiseAltitude = DEFAULT_ALTITUDE,
			CircleAngle = math.random() * math.pi * 2,
			CircleRadius = CIRCLE_RADIUS,
			CircleCenter = Vector3.zero,
			Phase = "Cruise",
			DiveStartY = 0,
			Initialized = false,
		}
	end
	return entry._swoopLoco
end

local function getAltitude(entry: any): number
	if entry.EnemyInfo then
		local alt = entry.EnemyInfo:GetAttribute("FlightAltitude")
		if typeof(alt) == "number" and alt > 0 then return alt end
	end
	if entry.Model then
		local alt = entry.Model:GetAttribute("FlightAltitude")
		if typeof(alt) == "number" and alt > 0 then return alt end
	end
	return DEFAULT_ALTITUDE
end

local function getGroundY(pos: Vector3): number
	local rayResult = Workspace:Raycast(
		Vector3.new(pos.X, pos.Y + 100, pos.Z),
		Vector3.new(0, -500, 0)
	)
	return rayResult and rayResult.Position.Y or 0
end

----------------------------------------------------------------------
-- Interface
----------------------------------------------------------------------

function SwoopLocomotion:Init(entry: any)
	local state = getState(entry)
	if state.Initialized then return end

	local hrp: BasePart = entry.HRP
	if not hrp then return end

	state.CruiseAltitude = getAltitude(entry)
	state.CircleCenter = hrp.Position

	hrp.Anchored = false

	local att = Instance.new("Attachment")
	att.Name = "SwoopAttachment"
	att.Parent = hrp
	state.Attachment = att

	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.MaxForce = MAX_FORCE
	ap.Responsiveness = MOVE_RESPONSIVENESS
	ap.Position = hrp.Position
	ap.Parent = hrp
	state.AlignPos = ap

	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = MAX_FORCE
	ao.Responsiveness = ORIENT_RESPONSIVENESS
	ao.CFrame = hrp.CFrame
	ao.Parent = hrp
	state.AlignOri = ao

	if entry.Humanoid then
		entry.Humanoid.PlatformStand = true
	end

	state.Initialized = true
	dprint("Swoop init for", entry.Model and entry.Model.Name or "?")
end

--- MoveTo: when given a target, fly toward it at cruise altitude.
--- The AI evaluator controls when to trigger a dive vs cruise.
function SwoopLocomotion:MoveTo(entry: any, targetPos: Vector3)
	local state = getState(entry)
	if not state.Initialized then
		self:Init(entry)
	end

	local hrp: BasePart = entry.HRP
	if not hrp then return end

	local groundY = getGroundY(targetPos)
	local cruiseY = groundY + state.CruiseAltitude
	local flyTarget = Vector3.new(targetPos.X, cruiseY, targetPos.Z)

	if state.Phase == "Dive" then
		-- Diving: go directly at the target (low altitude)
		if state.AlignPos then
			state.AlignPos.Responsiveness = DIVE_RESPONSIVENESS
			state.AlignPos.Position = Vector3.new(targetPos.X, targetPos.Y + 3, targetPos.Z)
		end
	elseif state.Phase == "Recover" then
		-- Recovering: climb back up above cruise altitude
		local recoverTarget = Vector3.new(hrp.Position.X, cruiseY + RECOVER_ALTITUDE_OFFSET, hrp.Position.Z)
		if state.AlignPos then
			state.AlignPos.Responsiveness = MOVE_RESPONSIVENESS
			state.AlignPos.Position = recoverTarget
		end
		-- Transition back to Cruise once we reach altitude
		if hrp.Position.Y >= cruiseY then
			state.Phase = "Cruise"
		end
	else
		-- Cruise: fly toward target at cruise altitude
		if state.AlignPos then
			state.AlignPos.Responsiveness = MOVE_RESPONSIVENESS
			state.AlignPos.Position = flyTarget
		end
	end

	-- Face movement direction
	if state.AlignOri then
		local target = state.AlignPos and state.AlignPos.Position or flyTarget
		local lookDir = (target - hrp.Position)
		if lookDir.Magnitude > 1 then
			state.AlignOri.CFrame = CFrame.lookAt(hrp.Position, target)
		end
	end
end

--- Circle: idle circling behavior (called by AIService during Idle/Wander).
function SwoopLocomotion:Circle(entry: any, centerPos: Vector3, dt: number)
	local state = getState(entry)
	if not state.Initialized then
		self:Init(entry)
	end

	local hrp: BasePart = entry.HRP
	if not hrp then return end

	state.CircleCenter = centerPos
	state.CircleAngle += CIRCLE_SPEED * dt
	state.Phase = "Cruise"

	local groundY = getGroundY(centerPos)
	local cruiseY = groundY + state.CruiseAltitude

	local cx = centerPos.X + math.cos(state.CircleAngle) * state.CircleRadius
	local cz = centerPos.Z + math.sin(state.CircleAngle) * state.CircleRadius

	local circlePos = Vector3.new(cx, cruiseY, cz)

	if state.AlignPos then
		state.AlignPos.Responsiveness = MOVE_RESPONSIVENESS
		state.AlignPos.Position = circlePos
	end

	-- Face tangent direction (perpendicular to radius)
	if state.AlignOri then
		local tangent = Vector3.new(
			-math.sin(state.CircleAngle),
			0,
			math.cos(state.CircleAngle)
		)
		local lookTarget = circlePos + tangent * 10
		state.AlignOri.CFrame = CFrame.lookAt(circlePos, lookTarget)
	end
end

--- StartDive: begin a dive-bomb toward the target.
function SwoopLocomotion:StartDive(entry: any)
	local state = getState(entry)
	state.Phase = "Dive"
	state.DiveStartY = entry.HRP and entry.HRP.Position.Y or 0
	dprint("Dive started for", entry.Model and entry.Model.Name or "?")
end

--- EndDive: transition to recovery phase (climb back up).
function SwoopLocomotion:EndDive(entry: any)
	local state = getState(entry)
	state.Phase = "Recover"
	dprint("Dive ended, recovering for", entry.Model and entry.Model.Name or "?")
end

--- Get current phase.
function SwoopLocomotion:GetPhase(entry: any): string
	local state = getState(entry)
	return state.Phase
end

function SwoopLocomotion:Stop(entry: any)
	local hrp: BasePart = entry.HRP
	local state = getState(entry)
	if hrp and state.AlignPos then
		state.AlignPos.Position = hrp.Position
	end
	state.Phase = "Cruise"
end

function SwoopLocomotion:IsFlying(): boolean
	return true
end

function SwoopLocomotion:Cleanup(entry: any)
	local state = getState(entry)
	if state.AlignPos then state.AlignPos:Destroy() end
	if state.AlignOri then state.AlignOri:Destroy() end
	if state.Attachment then state.Attachment:Destroy() end
	if entry.Humanoid then
		entry.Humanoid.PlatformStand = false
	end
	state.Initialized = false
	entry._swoopLoco = nil
	dprint("Swoop cleanup for", entry.Model and entry.Model.Name or "?")
end

return SwoopLocomotion
