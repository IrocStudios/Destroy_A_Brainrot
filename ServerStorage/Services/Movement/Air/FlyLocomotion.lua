--!strict
-- FlyLocomotion
-- Sustained flight locomotion using AlignPosition + AlignOrientation.
-- Maintains a cruise altitude, moves toward targets in 3D space.

local Workspace = game:GetService("Workspace")

local FlyLocomotion = {}
FlyLocomotion.Name = "Fly"
FlyLocomotion.Type = "Air"

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[FlyLoco]", ...) end
end

export type FlyState = {
	AlignPos: AlignPosition?,
	AlignOri: AlignOrientation?,
	Attachment: Attachment?,
	CruiseAltitude: number,
	Initialized: boolean,
}

local DEFAULT_ALTITUDE = 35
local MOVE_RESPONSIVENESS = 8
local ORIENT_RESPONSIVENESS = 6
local MAX_FORCE = 50000
local ARRIVAL_DIST = 5

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function getState(entry: any): FlyState
	if not entry._flyLoco then
		entry._flyLoco = {
			AlignPos = nil,
			AlignOri = nil,
			Attachment = nil,
			CruiseAltitude = DEFAULT_ALTITUDE,
			Initialized = false,
		}
	end
	return entry._flyLoco
end

local function getAltitude(entry: any): number
	local alt = entry.EnemyInfo and entry.EnemyInfo:GetAttribute("FlightAltitude")
	if typeof(alt) == "number" and alt > 0 then return alt end

	-- Check model attribute
	alt = entry.Model and entry.Model:GetAttribute("FlightAltitude")
	if typeof(alt) == "number" and alt > 0 then return alt end

	return DEFAULT_ALTITUDE
end

local function getGroundY(pos: Vector3): number
	local rayResult = Workspace:Raycast(
		Vector3.new(pos.X, pos.Y + 100, pos.Z),
		Vector3.new(0, -500, 0)
	)
	if rayResult then
		return rayResult.Position.Y
	end
	return 0
end

----------------------------------------------------------------------
-- Interface
----------------------------------------------------------------------

function FlyLocomotion:Init(entry: any)
	local state = getState(entry)
	if state.Initialized then return end

	local hrp: BasePart = entry.HRP
	if not hrp then return end

	state.CruiseAltitude = getAltitude(entry)

	-- Disable gravity on HRP
	hrp.Anchored = false

	-- Create attachment for AlignPosition/AlignOrientation
	local att = Instance.new("Attachment")
	att.Name = "FlyAttachment"
	att.Parent = hrp
	state.Attachment = att

	-- AlignPosition for movement
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.MaxForce = MAX_FORCE
	ap.Responsiveness = MOVE_RESPONSIVENESS
	ap.Position = hrp.Position
	ap.Parent = hrp
	state.AlignPos = ap

	-- AlignOrientation for facing
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = MAX_FORCE
	ao.Responsiveness = ORIENT_RESPONSIVENESS
	ao.CFrame = hrp.CFrame
	ao.Parent = hrp
	state.AlignOri = ao

	-- Prevent humanoid gravity from pulling it down
	if entry.Humanoid then
		entry.Humanoid.PlatformStand = true
	end

	state.Initialized = true
	dprint("Fly init for", entry.Model and entry.Model.Name or "?")
end

function FlyLocomotion:MoveTo(entry: any, targetPos: Vector3)
	local state = getState(entry)
	if not state.Initialized then
		self:Init(entry)
	end

	local hrp: BasePart = entry.HRP
	if not hrp then return end

	-- Maintain cruise altitude above ground at target position
	local groundY = getGroundY(targetPos)
	local flyY = groundY + state.CruiseAltitude
	local flyTarget = Vector3.new(targetPos.X, flyY, targetPos.Z)

	-- Set position target
	if state.AlignPos then
		state.AlignPos.Position = flyTarget
	end

	-- Face the target
	if state.AlignOri then
		local lookDir = (flyTarget - hrp.Position)
		if lookDir.Magnitude > 1 then
			local lookCF = CFrame.lookAt(hrp.Position, flyTarget)
			state.AlignOri.CFrame = lookCF
		end
	end
end

function FlyLocomotion:Stop(entry: any)
	local state = getState(entry)
	if not state.Initialized then return end

	local hrp: BasePart = entry.HRP
	if hrp and state.AlignPos then
		-- Hold current position
		state.AlignPos.Position = hrp.Position
	end
end

function FlyLocomotion:IsFlying(): boolean
	return true
end

function FlyLocomotion:Cleanup(entry: any)
	local state = getState(entry)
	if state.AlignPos then state.AlignPos:Destroy() end
	if state.AlignOri then state.AlignOri:Destroy() end
	if state.Attachment then state.Attachment:Destroy() end
	if entry.Humanoid then
		entry.Humanoid.PlatformStand = false
	end
	state.Initialized = false
	entry._flyLoco = nil
	dprint("Fly cleanup for", entry.Model and entry.Model.Name or "?")
end

return FlyLocomotion
