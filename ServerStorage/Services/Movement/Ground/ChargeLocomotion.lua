--!strict
-- ChargeLocomotion
-- Ground locomotion with burst sprints toward targets.
-- Uses PathfindingService for navigation but adds periodic speed bursts
-- when chasing (simulates an aggressive charge).

local PathfindingService = game:GetService("PathfindingService")
local ServerStorage = game:GetService("ServerStorage")

local ExclusionZoneManager = require(
	ServerStorage:WaitForChild("Services"):WaitForChild("Movement"):WaitForChild("ExclusionZoneManager")
)

local ChargeLocomotion = {}
ChargeLocomotion.Name = "Charge"
ChargeLocomotion.Type = "Ground"

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[ChargeLoco]", ...) end
end

export type ChargeState = {
	Path: Path?,
	Waypoints: { PathWaypoint },
	WaypointIndex: number,
	TargetPos: Vector3?,
	LastComputeAt: number,
	BlockedConn: RBXScriptConnection?,
	-- Charge-specific
	ChargeUntil: number,
	ChargeCooldownUntil: number,
	BaseSpeed: number,
}

local RECOMPUTE_INTERVAL = 0.5
local RECOMPUTE_DIST_THRESHOLD = 8
local WAYPOINT_REACH_DIST = 3
local DIRECT_MOVE_DIST = 15
local CHARGE_DURATION = 1.2       -- seconds of burst speed
local CHARGE_COOLDOWN = 3.0       -- seconds between charges
local CHARGE_SPEED_MULT = 1.8     -- speed multiplier during charge

local function distXZ(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function getState(entry: any): ChargeState
	if not entry._chargeLoco then
		entry._chargeLoco = {
			Path = nil,
			Waypoints = {},
			WaypointIndex = 1,
			TargetPos = nil,
			LastComputeAt = 0,
			BlockedConn = nil,
			ChargeUntil = 0,
			ChargeCooldownUntil = 0,
			BaseSpeed = 16,
		}
	end
	return entry._chargeLoco
end

local function cleanupPath(state: ChargeState)
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

function ChargeLocomotion:Init(entry: any)
	getState(entry)
end

function ChargeLocomotion:MoveTo(entry: any, targetPos: Vector3)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local state = getState(entry)
	local now = os.clock()
	local currentPos = hrp.Position
	local dist = distXZ(currentPos, targetPos)

	-- Charge burst logic: if chasing and off cooldown, trigger a charge
	if entry.State == "Chase" and now >= state.ChargeCooldownUntil and dist > 15 then
		state.ChargeUntil = now + CHARGE_DURATION
		state.ChargeCooldownUntil = now + CHARGE_DURATION + CHARGE_COOLDOWN
		state.BaseSpeed = hum.WalkSpeed
		dprint("CHARGE! for", entry.Model and entry.Model.Name or "?")
	end

	-- Apply charge speed boost
	if now < state.ChargeUntil then
		hum.WalkSpeed = state.BaseSpeed * CHARGE_SPEED_MULT
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

function ChargeLocomotion:Stop(entry: any)
	local hum: Humanoid = entry.Humanoid
	if hum then hum:Move(Vector3.zero, false) end
	local state = getState(entry)
	cleanupPath(state)
	state.TargetPos = nil
end

function ChargeLocomotion:IsFlying(): boolean
	return false
end

function ChargeLocomotion:Cleanup(entry: any)
	local state = getState(entry)
	cleanupPath(state)
	entry._chargeLoco = nil
end

return ChargeLocomotion
