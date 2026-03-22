--!strict
-- WalkLocomotion
-- Ground-based pathfinding locomotion using PathfindingService.
-- Replaces raw Humanoid:MoveTo() with proper waypoint-following navigation.
--
-- IMPORTANT: ComputeAsync runs in a background thread (task.spawn) so the
-- evaluator Heartbeat never yields.  While a new path is computing, the
-- brainrot keeps following its old waypoints or uses safe-fallback direct
-- movement — no micro-pauses.

local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

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
	Computing: boolean,
	BlockedConn: RBXScriptConnection?,
	ReachedConn: RBXScriptConnection?,
}

local RECOMPUTE_INTERVAL = 0.5       -- seconds between path re-computes
local RECOMPUTE_DIST_THRESHOLD = 4   -- re-compute if target moved this far (1 voxel)
local WAYPOINT_REACH_DIST = 4        -- how close before advancing past a waypoint (>= WaypointSpacing)
local DIRECT_MOVE_DIST = 16          -- within this range, skip pathfinding and MoveTo directly
local LOOK_AHEAD = 3                 -- MoveTo this many waypoints ahead of current (blends turns)

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
			Computing = false,
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

	-- For very short distances, use safe fallback (raycast check, no pathfinding overhead)
	local dist = distXZ(currentPos, targetPos)
	if dist < DIRECT_MOVE_DIST then
		-- Don't clean up path if a background compute is still running —
		-- it will swap itself in when ready.  Just stop following old waypoints.
		if not state.Computing then
			cleanupPath(state)
		end
		state.TargetPos = targetPos
		self:_safeFallbackMove(entry, targetPos)
		return
	end

	-- Check if we need to recompute the path
	local needsRecompute = false
	if not state.Path and not state.Computing then
		needsRecompute = true
	elseif not state.Computing and now - state.LastComputeAt > RECOMPUTE_INTERVAL then
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

	-- Follow current waypoints if we have them; otherwise safe-fallback
	-- so the brainrot keeps moving while a new path computes.
	if #state.Waypoints > 0 then
		self:_followWaypoints(entry)
	else
		state.TargetPos = targetPos
		self:_safeFallbackMove(entry, targetPos)
	end
end

function WalkLocomotion:Stop(entry: any)
	local hum: Humanoid = entry.Humanoid
	if hum then
		-- Cancel pending MoveTo by walking to current position, then clear MoveDirection
		local hrp = entry.HRP
		if hrp then
			pcall(function() hum:MoveTo(hrp.Position) end)
		end
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
-- Safe fallback: raycast toward target, stop before walls
----------------------------------------------------------------------

local _rayParams: RaycastParams? = nil
local function getRayParams(): RaycastParams
	if _rayParams then return _rayParams end
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = {}
	_rayParams = p
	return p
end

function WalkLocomotion:_safeFallbackMove(entry: any, targetPos: Vector3)
	local hrp: BasePart = entry.HRP
	local hum: Humanoid = entry.Humanoid
	if not hrp or not hum then return end

	local origin = hrp.Position
	local dir = (targetPos - origin)
	local dist = dir.Magnitude
	if dist < 0.5 then return end

	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	if flatDir.Magnitude < 0.1 then return end
	flatDir = flatDir.Unit

	-- Raycast forward to find walls (cast from waist height)
	local rayOrigin = Vector3.new(origin.X, origin.Y, origin.Z)
	local maxDist = math.min(dist, DIRECT_MOVE_DIST)
	local params = getRayParams()
	params.FilterDescendantsInstances = { entry.Model }

	local result = Workspace:Raycast(rayOrigin, flatDir * maxDist, params)
	if result then
		-- Wall found — move to 2 studs before the wall
		local safeDist = math.max(0, (result.Position - origin).Magnitude - 2)
		if safeDist < 1 then return end -- too close to wall, don't move
		local safePos = origin + flatDir * safeDist
		hum:MoveTo(Vector3.new(safePos.X, targetPos.Y, safePos.Z))
	else
		-- No wall — safe to MoveTo directly (within DIRECT_MOVE_DIST)
		local safePos = origin + flatDir * maxDist
		hum:MoveTo(Vector3.new(safePos.X, targetPos.Y, safePos.Z))
	end
end

----------------------------------------------------------------------
-- Path computation (non-blocking — runs in task.spawn)
----------------------------------------------------------------------

function WalkLocomotion:_computePath(entry: any, targetPos: Vector3)
	local hrp: BasePart = entry.HRP
	if not hrp then return end

	local state = getState(entry)

	-- Record intent immediately so the recompute check doesn't fire again
	-- while this computation is in flight.
	state.TargetPos = targetPos
	state.LastComputeAt = os.clock()
	state.Computing = true

	-- Capture values needed inside the background thread
	local startPos = hrp.Position
	local pathParams = buildPathParams(entry)

	task.spawn(function()
		local path = PathfindingService:CreatePath(pathParams)

		local ok, err = pcall(function()
			path:ComputeAsync(startPos, targetPos)
		end)

		-- Mark done regardless of outcome
		state.Computing = false

		-- Validate: entry still alive?
		if not entry.HRP or not entry.HRP.Parent then return end

		if not ok then
			dprint("ComputeAsync failed:", err)
			return -- next tick will fallback-move
		end

		if path.Status == Enum.PathStatus.NoPath then
			dprint("No path found")
			return -- next tick will fallback-move
		end

		local waypoints = path:GetWaypoints()
		if #waypoints < 2 then
			return -- next tick will fallback-move
		end

		-- Swap in the new path (clean up old connections first)
		cleanupPath(state)
		state.Path = path
		state.Waypoints = waypoints
		state.WaypointIndex = 2 -- skip first waypoint (current position)

		-- Listen for path blocked
		state.BlockedConn = path.Blocked:Connect(function(blockedWaypointIndex: number)
			dprint("Path blocked at waypoint", blockedWaypointIndex)
			-- Clear path — next MoveTo call will recompute
			cleanupPath(state)
		end)

		dprint("Path computed:", #waypoints, "waypoints")
	end)
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

	-- If we've passed all waypoints, path is done — move to final target
	if state.WaypointIndex > #state.Waypoints then
		cleanupPath(state)
		if state.TargetPos then
			hum:MoveTo(state.TargetPos)
		end
		return
	end

	-- Process jump actions on any upcoming waypoints we'll traverse
	for i = state.WaypointIndex, math.min(state.WaypointIndex + LOOK_AHEAD, #state.Waypoints) do
		if state.Waypoints[i].Action == Enum.PathWaypointAction.Jump then
			hum.Jump = true
			break
		end
	end

	-- Look-ahead: MoveTo a waypoint several steps ahead of the current one.
	-- This prevents the Humanoid from reaching its target between ticks and
	-- pausing — it always has a further destination and blends turns smoothly.
	local aheadIdx = math.min(state.WaypointIndex + LOOK_AHEAD, #state.Waypoints)
	hum:MoveTo(state.Waypoints[aheadIdx].Position)
end

return WalkLocomotion
