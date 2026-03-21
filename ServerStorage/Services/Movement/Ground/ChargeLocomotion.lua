--!strict
-- ChargeLocomotion
-- Ground locomotion with burst sprints toward targets.
-- Delegates pathfinding to WalkLocomotion (wall-safe) and adds periodic
-- speed bursts when chasing (simulates an aggressive charge).

local ServerStorage = game:GetService("ServerStorage")

local WalkLocomotion = require(
	ServerStorage:WaitForChild("Services"):WaitForChild("Movement")
		:WaitForChild("Ground"):WaitForChild("WalkLocomotion")
)

local ChargeLocomotion = {}
ChargeLocomotion.Name = "Charge"
ChargeLocomotion.Type = "Ground"

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[ChargeLoco]", ...) end
end

local CHARGE_DURATION = 1.2       -- seconds of burst speed
local CHARGE_COOLDOWN = 3.0       -- seconds between charges
local CHARGE_SPEED_MULT = 1.8     -- speed multiplier during charge
local CHARGE_MIN_DIST = 15        -- minimum distance to trigger charge

local function distXZ(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

export type ChargeState = {
	ChargeUntil: number,
	ChargeCooldownUntil: number,
	BaseSpeed: number,
}

function ChargeLocomotion:Init(entry: any)
	WalkLocomotion:Init(entry)
	entry._chargeLoco = {
		ChargeUntil = 0,
		ChargeCooldownUntil = 0,
		BaseSpeed = 16,
	} :: ChargeState
end

function ChargeLocomotion:MoveTo(entry: any, targetPos: Vector3)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local state: ChargeState = entry._chargeLoco
	if not state then
		WalkLocomotion:MoveTo(entry, targetPos)
		return
	end

	local now = os.clock()
	local dist = distXZ(hrp.Position, targetPos)

	-- Charge burst logic: if chasing and off cooldown, trigger a charge
	if entry.State == "Chase" and now >= state.ChargeCooldownUntil and dist > CHARGE_MIN_DIST then
		state.ChargeUntil = now + CHARGE_DURATION
		state.ChargeCooldownUntil = now + CHARGE_DURATION + CHARGE_COOLDOWN
		state.BaseSpeed = hum.WalkSpeed
		dprint("CHARGE! for", entry.Model and entry.Model.Name or "?")
	end

	-- Apply charge speed boost
	if now < state.ChargeUntil then
		hum.WalkSpeed = state.BaseSpeed * CHARGE_SPEED_MULT
	end

	-- Delegate all pathfinding + wall avoidance to WalkLocomotion
	WalkLocomotion:MoveTo(entry, targetPos)
end

function ChargeLocomotion:Stop(entry: any)
	WalkLocomotion:Stop(entry)
end

function ChargeLocomotion:IsFlying(): boolean
	return false
end

function ChargeLocomotion:Cleanup(entry: any)
	WalkLocomotion:Cleanup(entry)
	entry._chargeLoco = nil
end

return ChargeLocomotion
