--!strict
-- JumpyLocomotion
-- Ground locomotion with periodic hops during movement.
-- Uses PathfindingService for navigation but triggers Humanoid.Jump at intervals.

local PathfindingService = game:GetService("PathfindingService")
local ServerStorage = game:GetService("ServerStorage")

local ExclusionZoneManager = require(
	ServerStorage:WaitForChild("Services"):WaitForChild("Movement"):WaitForChild("ExclusionZoneManager")
)

local JumpyLocomotion = {}
JumpyLocomotion.Name = "Jumpy"
JumpyLocomotion.Type = "Ground"

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[JumpyLoco]", ...) end
end

export type JumpyState = {
	Path: Path?,
	Waypoints: { PathWaypoint },
	WaypointIndex: number,
	TargetPos: Vector3?,
	LastComputeAt: number,
	BlockedConn: RBXScriptConnection?,
	NextJumpAt: number,
}

local RECOMPUTE_INTERVAL = 0.5
local RECOMPUTE_DIST_THRESHOLD = 8
local WAYPOINT_REACH_DIST = 3
local DIRECT_MOVE_DIST = 12
local JUMP_INTERVAL_MIN = 0.6
local JUMP_INTERVAL_MAX = 1.8

local function distXZ(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function getState(entry: any): JumpyState
	if not entry._jumpyLoco then
		entry._jumpyLoco = {
			Path = nil,
			Waypoints = {},
			WaypointIndex = 1,
			TargetPos = nil,
			LastComputeAt = 0,
			BlockedConn = nil,
			NextJumpAt = os.clock() + math.random() * JUMP_INTERVAL_MAX,
		}
	end
	return entry._jumpyLoco
end

local function cleanupPath(state: JumpyState)
	if state.BlockedConn then
		state.BlockedConn:Disconnect()
		state.BlockedConn = nil
	end
	state.Path = nil
	state.Waypoints = {}
	state.WaypointIndex = 1
end

local function getHRPSize(entry: any): (number, number)
	local hrp = entry.HRP
	if not hrp then return 2, 5 end
	return hrp.Size.X * 0.5, hrp.Size.Y
end

function JumpyLocomotion:Init(entry: any)
	getState(entry)
end

function JumpyLocomotion:MoveTo(entry: any, targetPos: Vector3)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local state = getState(entry)
	local now = os.clock()
	local dist = distXZ(hrp.Position, targetPos)

	-- Periodic jumps while moving
	if now >= state.NextJumpAt then
		hum.Jump = true
		state.NextJumpAt = now + JUMP_INTERVAL_MIN + math.random() * (JUMP_INTERVAL_MAX - JUMP_INTERVAL_MIN)
	end

	-- Short distance: direct move
	if dist < DIRECT_MOVE_DIST then
		cleanupPath(state)
		state.TargetPos = targetPos
		hum:MoveTo(targetPos)
		return
	end

	-- Pathfinding
	local needsRecompute = false
	if not state.Path then
		needsRecompute = true
	elseif now - state.LastComputeAt > RECOMPUTE_INTERVAL then
		if state.TargetPos and distXZ(targetPos, state.TargetPos) > RECOMPUTE_DIST_THRESHOLD then
			needsRecompute = true
		end
	end

	if needsRecompute then
		cleanupPath(state)
		state.TargetPos = targetPos
		state.LastComputeAt = now

		local radius, height = getHRPSize(entry)
		local path = PathfindingService:CreatePath({
			AgentRadius = math.max(1, radius),
			AgentHeight = math.max(2, height),
			AgentCanJump = true,
			WaypointSpacing = 4,
		})

		local ok = pcall(function()
			path:ComputeAsync(hrp.Position, targetPos)
		end)

		if ok and path.Status ~= Enum.PathStatus.NoPath then
			local waypoints = path:GetWaypoints()
			if #waypoints >= 2 then
				state.Path = path
				state.Waypoints = waypoints
				state.WaypointIndex = 2
				state.BlockedConn = path.Blocked:Connect(function()
					cleanupPath(state)
				end)
			end
		end
	end

	-- Follow waypoints
	if #state.Waypoints > 0 then
		while state.WaypointIndex <= #state.Waypoints do
			local wp = state.Waypoints[state.WaypointIndex]
			if distXZ(hrp.Position, wp.Position) <= WAYPOINT_REACH_DIST then
				state.WaypointIndex += 1
			else
				break
			end
		end

		if state.WaypointIndex > #state.Waypoints then
			cleanupPath(state)
			hum:MoveTo(targetPos)
		else
			local wp = state.Waypoints[state.WaypointIndex]
			if wp.Action == Enum.PathWaypointAction.Jump then
				hum.Jump = true
			end
			hum:MoveTo(wp.Position)
		end
	else
		hum:MoveTo(targetPos)
	end
end

function JumpyLocomotion:Stop(entry: any)
	local hum: Humanoid = entry.Humanoid
	if hum then hum:Move(Vector3.zero, false) end
	local state = getState(entry)
	cleanupPath(state)
	state.TargetPos = nil
end

function JumpyLocomotion:IsFlying(): boolean
	return false
end

function JumpyLocomotion:Cleanup(entry: any)
	local state = getState(entry)
	cleanupPath(state)
	entry._jumpyLoco = nil
end

return JumpyLocomotion
