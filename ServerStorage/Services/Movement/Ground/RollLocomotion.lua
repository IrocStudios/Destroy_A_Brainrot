--!strict
-- RollLocomotion
-- Ground locomotion for constantly-rolling enemies (e.g. Boneca_Ambalabu).
-- Delegates pathfinding to WalkLocomotion but adds:
--   • Wander chaining: ShouldChainWander() keeps them driving
--   • Forced-idle immunity: IsImmuneToForcedIdle()
--   • Stuck override: OnStuck() — 180 reverse instead of hopping
--   • Wall avoidance: AdjustWanderPoint() reverses blocked points
--
-- Config: BrainrotConfig.RollConfig = { IdleChance }

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WalkLocomotion = require(
	ServerStorage:WaitForChild("Services"):WaitForChild("Movement")
		:WaitForChild("Ground"):WaitForChild("WalkLocomotion")
)

local RollLocomotion = {}
RollLocomotion.Name = "Roll"
RollLocomotion.Type = "Ground"

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[RollLoco]", ...) end
end

local DEFAULT_IDLE_CHANCE = 0.25
local STUCK_VELOCITY_THRESHOLD = 1.0
local STUCK_TICKS_TO_REVERSE = 5      -- ~0.5s stuck = reverse
local REVERSE_DISTANCE = 15

-- Shared raycast setup
local _rayParams: RaycastParams? = nil
local _filterCache: { Instance } = {}

local function buildFilter(entry: any): RaycastParams
	if not _rayParams then
		_rayParams = RaycastParams.new()
		_rayParams.FilterType = Enum.RaycastFilterType.Exclude
	end
	if #_filterCache == 0 then
		local territories = Workspace:FindFirstChild("Territories")
		local exclusionZones = Workspace:FindFirstChild("ExclusionZones")
		local enemies = Workspace:FindFirstChild("Enemies")
		if territories then table.insert(_filterCache, territories) end
		if exclusionZones then table.insert(_filterCache, exclusionZones) end
		if enemies then table.insert(_filterCache, enemies) end
	end
	local filter = table.clone(_filterCache)
	if entry.Model then table.insert(filter, entry.Model) end
	_rayParams.FilterDescendantsInstances = filter
	return _rayParams
end

--- Pick a reversed point: 180 from current facing direction
local function reversePoint(entry: any): Vector3?
	local hrp = entry.HRP
	if not hrp then return nil end
	local backDir = -hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	if backDir.Magnitude < 0.1 then return nil end
	backDir = backDir.Unit
	return hrp.Position + backDir * REVERSE_DISTANCE
end

export type RollState = {
	IdleChance: number,
	StuckTicks: number,
}

----------------------------------------------------------------------
-- Config reader
----------------------------------------------------------------------

local function readRollConfig(brainrotName: string): number
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local configFolder = shared and shared:FindFirstChild("Config")
	local bCfgMod = configFolder and configFolder:FindFirstChild("BrainrotConfig")
	if not bCfgMod or not bCfgMod:IsA("ModuleScript") then return DEFAULT_IDLE_CHANCE end
	local ok, bCfg = pcall(require, bCfgMod)
	if not ok or type(bCfg) ~= "table" then return DEFAULT_IDLE_CHANCE end
	local entry = bCfg[brainrotName]
	if not entry or type(entry.RollConfig) ~= "table" then return DEFAULT_IDLE_CHANCE end
	return tonumber(entry.RollConfig.IdleChance) or DEFAULT_IDLE_CHANCE
end

----------------------------------------------------------------------
-- Interface
----------------------------------------------------------------------

function RollLocomotion:Init(entry: any)
	WalkLocomotion:Init(entry)
	local brainrotName = tostring(entry.BrainrotName or "Default")
	entry._rollLoco = {
		IdleChance = readRollConfig(brainrotName),
		StuckTicks = 0,
	} :: RollState
	dprint("Init:", brainrotName)
end

function RollLocomotion:MoveTo(entry: any, targetPos: Vector3)
	local rollState: RollState? = entry._rollLoco
	local hrp = entry.HRP

	-- Internal stuck detection: if near-zero velocity for too long, reverse
	if rollState and hrp then
		local vel = hrp.AssemblyLinearVelocity
		local xzSpeed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)

		if xzSpeed < STUCK_VELOCITY_THRESHOLD then
			rollState.StuckTicks = rollState.StuckTicks + 1

			if rollState.StuckTicks >= STUCK_TICKS_TO_REVERSE then
				rollState.StuckTicks = 0
				WalkLocomotion:Stop(entry)
				local rev = reversePoint(entry)
				if rev then
					dprint("STUCK — 180 reverse!")
					if entry.State == "Wander" then
						entry.WanderTarget = rev
					end
					WalkLocomotion:MoveTo(entry, rev)
					return
				end
			end
		else
			rollState.StuckTicks = 0
		end
	end

	-- No proactive wall check here — let WalkLocomotion pathfind normally.
	-- Wall avoidance happens at point-picking time (AdjustWanderPoint)
	-- and when stuck (OnStuck / internal stuck detection above).
	WalkLocomotion:MoveTo(entry, targetPos)
end

function RollLocomotion:Stop(entry: any)
	WalkLocomotion:Stop(entry)
	if entry._rollLoco then
		entry._rollLoco.StuckTicks = 0
	end
end

function RollLocomotion:IsFlying(): boolean
	return false
end

function RollLocomotion:ShouldChainWander(entry: any): boolean
	local rollState: RollState? = entry._rollLoco
	if not rollState then return false end
	return math.random() > rollState.IdleChance
end

--- Not fully immune — uses delayed idle check instead.
--- Returns false so the velocity check runs, but AIService checks ForcedIdleDelay.
function RollLocomotion:IsImmuneToForcedIdle(): boolean
	return false
end

--- Ticks of sustained near-zero velocity before forcing idle anim.
--- Prevents flicker during direction changes but catches actual stops/stuck.
function RollLocomotion:GetForcedIdleDelay(): number
	return 5 -- ~0.5 seconds
end

--- Called by AIService stuck-hop system instead of hopping.
--- Rollers don't hop — they reverse direction.
function RollLocomotion:OnStuck(entry: any): boolean
	-- Reset internal stuck counter to stay in sync with AIService's counter
	if entry._rollLoco then entry._rollLoco.StuckTicks = 0 end

	local rev = reversePoint(entry)
	if rev then
		dprint("OnStuck — 180 reverse (no hop)")
		WalkLocomotion:Stop(entry)
		if entry.State == "Wander" then
			entry.WanderTarget = rev
		end
		WalkLocomotion:MoveTo(entry, rev)
		return true
	end
	return false
end

--- Adjust a candidate wander point. Raycasts toward it — if blocked, 180 reverse.
function RollLocomotion:AdjustWanderPoint(entry: any, candidatePos: Vector3): Vector3
	local hrp = entry.HRP
	if not hrp then return candidatePos end

	local origin = hrp.Position
	local flatDir = Vector3.new(candidatePos.X - origin.X, 0, candidatePos.Z - origin.Z)
	local dist = flatDir.Magnitude
	if dist < 3 then return candidatePos end

	local params = buildFilter(entry)
	local result = Workspace:Raycast(origin, flatDir.Unit * dist, params)

	if result then
		local hitDist = (result.Position - origin).Magnitude
		if hitDist < dist * 0.8 then
			local reverseDist = math.max(dist * 0.6, 8)
			local reversed = Vector3.new(
				origin.X - flatDir.Unit.X * reverseDist,
				candidatePos.Y,
				origin.Z - flatDir.Unit.Z * reverseDist
			)
			dprint(("AdjustWander: wall '%s' at %.0f — reversed"):format(result.Instance.Name, hitDist))
			return reversed
		end
	end

	return candidatePos
end

function RollLocomotion:Cleanup(entry: any)
	WalkLocomotion:Cleanup(entry)
	entry._rollLoco = nil
end

return RollLocomotion
