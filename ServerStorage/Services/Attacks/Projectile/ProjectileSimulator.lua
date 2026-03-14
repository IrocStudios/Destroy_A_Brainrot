--!strict
-- ProjectileSimulator
-- Pure utility for server-side projectile collision detection.
-- Pre-calculates wall collisions (static) and provides per-step player raycasting (real-time).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ProjectileSimulator = {}

local ARC_STEPS = 16

----------------------------------------------------------------------
-- Arc math
----------------------------------------------------------------------

--- Generate N+1 points along a parabolic arc from origin to target.
--- XZ = linear lerp, Y = lerp + parabolic offset 4*h*t*(1-t).
function ProjectileSimulator.CalculateArcPoints(
	origin: Vector3,
	target: Vector3,
	pCfg: { [string]: any },
	steps: number?
): { Vector3 }
	local n = steps or ARC_STEPS
	local dist = (target - origin).Magnitude

	local arcHeight = 0
	if pCfg.Gravity then
		local arcMult = pCfg.ArcHeight or 0.3
		local arcCap = pCfg.ArcHeightCap or 15
		arcHeight = math.min(dist * arcMult, arcCap)
	end

	local points: { Vector3 } = {}
	for i = 0, n do
		local t = i / n
		-- XZ + base Y: linear lerp
		local pos = origin:Lerp(target, t)
		-- Parabolic Y offset (peaks at t=0.5)
		local yOffset = 4 * arcHeight * t * (1 - t)
		table.insert(points, pos + Vector3.new(0, yOffset, 0))
	end

	return points
end

----------------------------------------------------------------------
-- Character detection
----------------------------------------------------------------------

--- Walk up parent chain to find a character Model with a Humanoid.
--- Returns (characterModel, player) or (nil, nil).
function ProjectileSimulator.FindCharacterFromHit(instance: Instance): (Model?, Player?)
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local hum = current:FindFirstChildOfClass("Humanoid")
			if hum then
				local player = Players:GetPlayerFromCharacter(current)
				if player then
					return current :: Model, player
				end
				-- Model with Humanoid but no player = brainrot/NPC, skip
				return nil, nil
			end
		end
		current = current.Parent :: Instance
	end
	return nil, nil
end

----------------------------------------------------------------------
-- Wall pre-calculation
----------------------------------------------------------------------

--- Raycast the arc path excluding all characters (players + brainrots).
--- Returns the adjusted target (wall hit point or original) and the
--- fraction of the arc traveled before hitting (1.0 = no wall).
function ProjectileSimulator.CheckWalls(
	origin: Vector3,
	target: Vector3,
	pCfg: { [string]: any },
	excludeList: { Instance }
): (Vector3, number)
	local points = ProjectileSimulator.CalculateArcPoints(origin, target, pCfg)
	local n = #points - 1

	-- Build exclude list: brainrot model + all player characters
	local fullExclude: { Instance } = {}
	for _, inst in ipairs(excludeList) do
		table.insert(fullExclude, inst)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(fullExclude, player.Character)
		end
	end

	-- Also exclude any NPC/brainrot models (Models with Humanoids in Workspace)
	-- We only want to hit terrain/parts/walls
	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		for _, child in ipairs(enemies:GetChildren()) do
			if child:IsA("Model") then
				table.insert(fullExclude, child)
			end
		end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = fullExclude

	for i = 1, n do
		local from = points[i]
		local to = points[i + 1]
		local dir = to - from
		local result = Workspace:Raycast(from, dir, rayParams)
		if result then
			local fraction = (i - 1) / n + (result.Position - from).Magnitude / (dir.Magnitude * n)
			fraction = math.clamp(fraction, 0, 1)
			return result.Position, fraction
		end
	end

	return target, 1.0
end

----------------------------------------------------------------------
-- Per-step player raycast
----------------------------------------------------------------------

--- Single-segment raycast for real-time player detection.
--- Call this each step during flight with rayParams that INCLUDE player characters.
function ProjectileSimulator.StepAndCheck(
	from: Vector3,
	to: Vector3,
	rayParams: RaycastParams
): RaycastResult?
	local dir = to - from
	if dir.Magnitude < 0.01 then return nil end
	return Workspace:Raycast(from, dir, rayParams)
end

----------------------------------------------------------------------
-- Convenience: build RaycastParams for the step loop
----------------------------------------------------------------------

--- Create RaycastParams that excludes only the brainrot model (and optionally Enemies folder).
--- Player characters are NOT excluded — we want to detect them.
function ProjectileSimulator.MakePlayerCheckParams(brainrotModel: Model?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if brainrotModel then
		table.insert(exclude, brainrotModel)
	end
	-- Exclude other brainrot models so projectiles don't hit friendly NPCs
	local enemies = Workspace:FindFirstChild("Enemies")
	if enemies then
		for _, child in ipairs(enemies:GetChildren()) do
			if child:IsA("Model") then
				table.insert(exclude, child)
			end
		end
	end
	params.FilterDescendantsInstances = exclude
	return params
end

return ProjectileSimulator
