--!strict
-- ReplicatedStorage/Shared/Util/RagdollUtil.lua
-- Lightweight full-body ragdoll utility.
-- Pre-creates BallSocket/Hinge constraints alongside Motor6Ds,
-- then toggles between motor-driven and physics-driven states.
-- Used by RagdollController (client) on the local character.

local RagdollUtil = {}

----------------------------------------------------------------------
-- R15 joint constraint definitions
----------------------------------------------------------------------

local JOINT_INFO = {
	LeftShoulder  = { Cone = 70,  Twist = 30 },
	LeftElbow     = { Lower = 0,  Upper = 160 },
	LeftWrist     = { Cone = 90,  Twist = 90 },
	RightShoulder = { Cone = 70,  Twist = 30 },
	RightElbow    = { Lower = 0,  Upper = 160 },
	RightWrist    = { Cone = 90,  Twist = 90 },
	Waist         = { Lower = -45, Upper = 30 },
	Neck          = { Cone = 20,  Twist = 20 },
	LeftHip       = { Cone = 40,  Twist = 2.5 },
	LeftKnee      = { Lower = 0,  Upper = 120 },
	LeftAnkle     = { Cone = 10,  Twist = 0.5 },
	RightHip      = { Cone = 40,  Twist = 2.5 },
	RightKnee     = { Lower = 0,  Upper = 120 },
	RightAnkle    = { Cone = 10,  Twist = 0.5 },
}

----------------------------------------------------------------------
-- Module-level cache: character → { joints, cleanup }
----------------------------------------------------------------------

local _cache: { [Model]: any } = {}

--- Find a Motor6D anywhere inside the character by name.
local function findMotor(character: Model, name: string): Motor6D?
	local inst = character:FindFirstChild(name, true)
	if inst and inst:IsA("Motor6D") then
		return inst :: Motor6D
	end
	return nil
end

----------------------------------------------------------------------
-- setup: pre-create constraints (call once per character spawn)
----------------------------------------------------------------------

function RagdollUtil.setup(character: Model): () -> ()
	if _cache[character] then
		return _cache[character].cleanup
	end

	local joints: { {
		motor: Motor6D,
		constraint: Instance,
		originalPart1: BasePart,
	} } = {}

	for jointName, limits in pairs(JOINT_INFO) do
		local motor = findMotor(character, jointName)
		if not motor or not motor.Part0 or not motor.Part1 then continue end

		local rigAttName = jointName .. "RigAttachment"
		local att0 = motor.Part0:FindFirstChild(rigAttName)
		local att1 = motor.Part1:FindFirstChild(rigAttName)
		if not att0 or not att1 then continue end

		-- Determine constraint type
		local isBall = limits.Cone ~= nil
		local constraint: Instance

		if isBall then
			local bs = Instance.new("BallSocketConstraint")
			bs.LimitsEnabled = true
			bs.UpperAngle = limits.Cone :: number
			bs.TwistLimitsEnabled = true
			bs.TwistLowerAngle = -(limits.Twist :: number)
			bs.TwistUpperAngle = limits.Twist :: number
			bs.Attachment0 = att0 :: Attachment
			bs.Attachment1 = att1 :: Attachment
			bs.Enabled = false
			bs.Name = jointName .. "RagdollConstraint"
			bs.Parent = motor.Parent
			constraint = bs
		else
			local hc = Instance.new("HingeConstraint")
			hc.LimitsEnabled = true
			hc.LowerAngle = limits.Lower :: number
			hc.UpperAngle = limits.Upper :: number
			hc.Attachment0 = att0 :: Attachment
			hc.Attachment1 = att1 :: Attachment
			hc.Enabled = false
			hc.Name = jointName .. "RagdollConstraint"
			hc.Parent = motor.Parent
			constraint = hc
		end

		table.insert(joints, {
			motor = motor,
			constraint = constraint,
			originalPart1 = motor.Part1,
		})
	end

	local function cleanup()
		local cached = _cache[character]
		if not cached then return end
		_cache[character] = nil

		-- Restore motors and destroy constraints
		for _, j in ipairs(cached.joints) do
			if j.motor and j.motor.Parent then
				j.motor.Part1 = j.originalPart1
			end
			if j.constraint and j.constraint.Parent then
				j.constraint:Destroy()
			end
		end
	end

	_cache[character] = { joints = joints, cleanup = cleanup }

	-- Auto-cleanup on character destruction
	character.Destroying:Connect(function()
		_cache[character] = nil
	end)

	return cleanup
end

----------------------------------------------------------------------
-- activate: switch to ragdoll (physics-driven)
----------------------------------------------------------------------

function RagdollUtil.activate(character: Model)
	local cached = _cache[character]
	if not cached then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	for _, j in ipairs(cached.joints) do
		j.constraint.Enabled = true
		j.motor.Part1 = nil
	end

	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
end

----------------------------------------------------------------------
-- deactivate: restore motors (animation-driven)
----------------------------------------------------------------------

function RagdollUtil.deactivate(character: Model)
	local cached = _cache[character]
	if not cached then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	for _, j in ipairs(cached.joints) do
		j.constraint.Enabled = false
		j.motor.Part1 = j.originalPart1
	end

	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

----------------------------------------------------------------------
-- isRagdolled: check current state
----------------------------------------------------------------------

function RagdollUtil.isRagdolled(character: Model): boolean
	local cached = _cache[character]
	if not cached or #cached.joints == 0 then return false end
	-- Check first joint — if motor is disconnected, we're ragdolled
	return cached.joints[1].motor.Part1 == nil
end

return RagdollUtil
