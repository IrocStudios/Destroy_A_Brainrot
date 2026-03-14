--!strict
-- WalkLocomotion
-- Ground-based pathfinding locomotion using PathfindingService.
-- Replaces raw Humanoid:MoveTo() with proper waypoint-following navigation.

local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local ExclusionZoneManager = require(
	ServerStorage:WaitForChild("Services"):WaitForChild("Movement"):WaitForChild("ExclusionZoneManager")
)

local WalkLocomotion = {}
WalkLocomotion.Name = "Walk"
WalkLocomotion.Type = "Ground"

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[WalkLoco]", ...) end
end

-- Per-entry state stored on entry._walkLoco
export type WalkState = {
	Path: Path?,
	Waypoints: { PathWaypoint },
	WaypointIndex: number,
	TargetPos: Vector3?,
	LastComputeAt: number,
	BlockedConn: RBXScriptConnection?,
	ReachedConn: RBXScriptConnection?,
}

local RECOMPUTE_INTERVAL = 0.5       -- seconds between path re-computes
local RECOMPUTE_DIST_THRESHOLD = 8   -- re-compute if target moved this far
local WAYPOINT_REACH_DIST = 3        -- how close to a waypoint before advancing
local DIRECT_MOVE_DIST = 12          -- within this range, skip pathfinding and MoveTo directly

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function getHRPSize(entry: any): (number, number)
	local hrp = entry.HRP
	if not hrp then return 2, 5 end
	return hrp.Size.X * 0.5, hrp.Size.Y
end

local function distXZ(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function buildPathParams(entry: any): { [string]: any }
	local radius, height = getHRPSize(entry)
	return {
		AgentRadius = math.max(1, radius),
		AgentHeight = math.max(2, height),
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 4,
	}
end

local function getState(entry: any): WalkState
	if not entry._walkLoco then
		entry._walkLoco = {
			Path = nil,
			Waypoints = {},
			WaypointIndex = 1,
			TargetPos = nil,
			LastComputeAt = 0,
			BlockedConn = nil,
			ReachedConn = nil,
		}
	end
	return entry._walkLoco
end

local function cleanupPath(state: WalkState)
	if state.BlockedConn then
		state.BlockedConn:Disconnect()
		state.BlockedConn = nil
	end
	if state.ReachedConn then
		state.ReachedConn:Disconnect()
		state.ReachedConn = nil
	end
	state.Path = nil
	state.Waypoints = {}
	state.WaypointIndex = 1
end

----------------------------------------------------------------------
-- Interface
----------------------------------------------------------------------

function WalkLocomotion:Init(entry: any)
	-- Ensure state table exists
	getState(entry)
end

function WalkLocomotion:MoveTo(entry: any, targetPos: Vector3)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local state = getState(entry)
	local now = os.clock()
	local currentPos = hrp.Position

	-- For very short distances, just use direct MoveTo (no pathfinding overhead)
	local dist = distXZ(currentPos, targetPos)
	if dist < DIRECT_MOVE_DIST then
		cleanupPath(state)
		state.TargetPos = targetPos
		hum:MoveTo(targetPos)
		return
	end

	-- Check if we need to recompute the path
	local needsRecompute = false
	if not state.Path then
		needsRecompute = true
	elseif now - state.LastComputeAt > RECOMPUTE_INTERVAL then
		if state.TargetPos then
			local targetMoved = distXZ(targetPos, state.TargetPos) > RECOMPUTE_DIST_THRESHOLD
			if targetMoved then
				needsRecompute = true
			end
		else
			needsRecompute = true
		end
	end

	if needsRecompute then
		self:_computePath(entry, targetPos)
	end

	-- Follow current waypoint
	self:_followWaypoints(entry)
end

function WalkLocomotion:Stop(entry: any)
	local hum: Humanoid = entry.Humanoid
	if hum then
		hum:Move(Vector3.zero, false)
	end
	local state = getState(entry)
	cleanupPath(state)
	state.TargetPos = nil
end

function WalkLocomotion:IsFlying(): boolean
	return false
end

function WalkLocomotion:Cleanup(entry: any)
	local state = getState(entry)
	cleanupPath(state)
	entry._walkLoco = nil
end

----------------------------------------------------------------------
-- Path computation
----------------------------------------------------------------------

function WalkLocomotion:_computePath(entry: any, targetPos: Vector3)
	local hrp: BasePart = entry.HRP
	if not hrp then return end

	local state = getState(entry)
	cleanupPath(state)

	state.TargetPos = targetPos
	state.LastComputeAt = os.clock()

	local pathParams = buildPathParams(entry)
	local path = PathfindingService:CreatePath(pathParams)

	local ok, err = pcall(function()
		path:ComputeAsync(hrp.Position, targetPos)
	end)

	if not ok then
		dprint("ComputeAsync failed:", err)
		-- Fallback to direct MoveTo
		entry.Humanoid:MoveTo(targetPos)
		return
	end

	if path.Status == Enum.PathStatus.NoPath then
		dprint("No path found, falling back to direct MoveTo")
		entry.Humanoid:MoveTo(targetPos)
		return
	end

	local waypoints = path:GetWaypoints()
	if #waypoints < 2 then
		entry.Humanoid:MoveTo(targetPos)
		return
	end

	state.Path = path
	state.Waypoints = waypoints
	state.WaypointIndex = 2 -- skip first waypoint (current position)

	-- Listen for path blocked
	state.BlockedConn = path.Blocked:Connect(function(blockedWaypointIndex: number)
		dprint("Path blocked at waypoint", blockedWaypointIndex)
		-- Re-compute on next MoveTo call
		cleanupPath(state)
	end)

	dprint("Path computed:", #waypoints, "waypoints")
end

----------------------------------------------------------------------
-- Waypoint following
----------------------------------------------------------------------

function WalkLocomotion:_followWaypoints(entry: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp then return end

	local state = getState(entry)
	if #state.Waypoints == 0 then
		-- No path, direct move to target
		if state.TargetPos then
			hum:MoveTo(state.TargetPos)
		end
		return
	end

	-- Advance past reached waypoints
	while state.WaypointIndex <= #state.Waypoints do
		local wp = state.Waypoints[state.WaypointIndex]
		local dist = distXZ(hrp.Position, wp.Position)
		if dist <= WAYPOINT_REACH_DIST then
			state.WaypointIndex += 1
		else
			break
		end
	end

	-- If we've passed all waypoints, we're done
	if state.WaypointIndex > #state.Waypoints then
		cleanupPath(state)
		if state.TargetPos then
			hum:MoveTo(state.TargetPos)
		end
		return
	end

	local wp = state.Waypoints[state.WaypointIndex]

	-- Handle jump waypoints
	if wp.Action == Enum.PathWaypointAction.Jump then
		hum.Jump = true
	end

	hum:MoveTo(wp.Position)
end

return WalkLocomotion
