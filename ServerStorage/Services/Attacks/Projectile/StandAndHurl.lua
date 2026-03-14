--!strict
-- StandAndHurl
-- Ranged projectile attack: stop moving, wind up, hurl a projectile at the target.
-- Server does stepped collision detection along arc path. Fires RemoteEvent for client FX.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local _attackConfig: any = nil
local function getAttackConfig(): any
	if _attackConfig then return _attackConfig end
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("AttackConfig"))
	end)
	if ok and type(mod) == "table" then
		_attackConfig = mod
		return mod
	end
	_attackConfig = { Projectiles = {}, Moves = {} }
	return _attackConfig
end

local _simulator: any = nil
local function getSimulator(): any
	if _simulator then return _simulator end
	local attacks = ServerStorage:FindFirstChild("Services")
		and ServerStorage.Services:FindFirstChild("Attacks")
		and ServerStorage.Services.Attacks:FindFirstChild("Projectile")
	if attacks then
		local mod = attacks:FindFirstChild("ProjectileSimulator")
		if mod then
			local ok, result = pcall(require, mod)
			if ok then _simulator = result end
		end
	end
	return _simulator
end

local StandAndHurl = {}
StandAndHurl.Name = "StandAndHurl"
StandAndHurl.Type = "Projectile"
StandAndHurl.Weight = "Light"
StandAndHurl.AnimationKey = "Throw"

local function getAttackFXRemote(): RemoteEvent?
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Net")
		and ReplicatedStorage.Shared.Net:FindFirstChild("Remotes")
		and ReplicatedStorage.Shared.Net.Remotes:FindFirstChild("RemoteEvents")
	if not net then return nil end
	local remote = net:FindFirstChild("BrainrotAttackFX")
	if remote and remote:IsA("RemoteEvent") then
		return remote :: RemoteEvent
	end
	return nil
end

function StandAndHurl:CanExecute(entry: any, target: any, dist: number, moveConfig: any?): boolean
	local minRange = (moveConfig and moveConfig.MinRange) or 8
	return dist >= minRange
end

function StandAndHurl:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	-- Stop moving during throw
	hum.WalkSpeed = 0
	hum:Move(Vector3.zero, false)

	-- Face the target during windup
	do
		local tChar = target and target.Character
		local tHRP = tChar and tChar:FindFirstChild("HumanoidRootPart")
		if tHRP and tHRP:IsA("BasePart") then
			local lookDir = (tHRP.Position - hrp.Position) * Vector3.new(1, 0, 1) -- XZ only
			if lookDir.Magnitude > 0.1 then
				hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir.Unit)
			end
		end
	end

	local windupTime = (moveConfig and moveConfig.WindupTime) or 0.4
	task.wait(windupTime)

	-- Verify target still valid
	local targetChar = target and target.Character
	if not targetChar then return end
	local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return end
	local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then return end
	if not entry.HRP then return end

	local origin = entry.HRP.Position + Vector3.new(0, 2, 0) -- throw from above head
	local targetPos = targetHRP.Position

	-- Apply accuracy spread
	local spread = (moveConfig and moveConfig.Spread) or 0
	if spread > 0 then
		targetPos = targetPos + Vector3.new(
			(math.random() - 0.5) * 2 * spread,
			(math.random() - 0.5) * spread * 0.5,
			(math.random() - 0.5) * 2 * spread
		)
	end

	-- Determine projectile skin
	local projectileSkin = (moveConfig and moveConfig.Projectile) or "Rock"
	-- Per-brainrot override
	local brainrotSkin = entry.Model and entry.Model:GetAttribute("ProjectileSkin")
	if type(brainrotSkin) == "string" and brainrotSkin ~= "" then
		projectileSkin = brainrotSkin
	end

	-- Read projectile config
	local projCfg = getAttackConfig().Projectiles and getAttackConfig().Projectiles[projectileSkin]
	if not projCfg then projCfg = { Speed = 80 } end
	local speed = projCfg.Speed or 80
	local dist = (targetPos - origin).Magnitude
	local maxRange = projCfg.MaxRange
	if maxRange and dist > maxRange then return end -- out of range

	-- Pre-calculate damage (used if we hit someone)
	local finalDamage: number
	local projDamageOverride = projCfg.Damage
	if typeof(projDamageOverride) == "number" then
		finalDamage = projDamageOverride
	else
		local baseDamage = 10
		local enemyInfo = entry.EnemyInfo
		if enemyInfo then
			local d = enemyInfo:GetAttribute("AttackDamage")
			if typeof(d) == "number" then baseDamage = d end
		end
		local damageMult = (moveConfig and moveConfig.DamageMult) or 0.8
		finalDamage = math.floor(baseDamage * damageMult + 0.5)
	end

	local function applyDamageToPlayer(hitPlayer: Player)
		pcall(function()
			local hitChar = hitPlayer.Character
			if not hitChar then return end
			local hitHum = hitChar:FindFirstChildOfClass("Humanoid")
			if not hitHum or hitHum.Health <= 0 then return end
			local armorSvc = services and services.ArmorService
			if armorSvc then
				local absorbed, overflow = armorSvc:DamageArmor(hitPlayer, finalDamage)
				if overflow > 0 then
					hitHum:TakeDamage(overflow)
				end
			else
				hitHum:TakeDamage(finalDamage)
			end
		end)
	end

	-- Collision detection via ProjectileSimulator
	local sim = getSimulator()
	if not sim then
		-- Fallback: old behavior if simulator not found
		local fxRemote = getAttackFXRemote()
		if fxRemote then
			fxRemote:FireAllClients({
				AttackType = "Projectile",
				MoveName = "StandAndHurl",
				Origin = origin,
				Target = targetPos,
				ProjectileSkin = projectileSkin,
				BrainrotId = entry.Id,
			})
		end
		local travelTime = math.clamp(dist / speed, 0.05, 2.0)
		task.wait(travelTime)
		targetChar = target and target.Character
		if targetChar then
			targetHum = targetChar:FindFirstChildOfClass("Humanoid")
			targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
			if targetHum and targetHum.Health > 0 and targetHRP and targetHRP:IsA("BasePart") then
				if (targetHRP.Position - targetPos).Magnitude <= 10 then
					applyDamageToPlayer(target)
				end
			end
		end
		return
	end

	-- Phase 1: Pre-calc wall collisions (adjust target so visual stops at walls)
	local adjustedTarget, wallFrac = sim.CheckWalls(origin, targetPos, projCfg, { entry.Model })
	local hitWall = wallFrac < 0.99

	-- Fire client FX with wall-adjusted target
	local fxRemote = getAttackFXRemote()
	if fxRemote then
		fxRemote:FireAllClients({
			AttackType = "Projectile",
			MoveName = "StandAndHurl",
			Origin = origin,
			Target = adjustedTarget,
			ProjectileSkin = projectileSkin,
			BrainrotId = entry.Id,
			HitType = hitWall and "wall" or nil,
		})
	end

	-- Phase 2: Real-time stepped player detection along the arc
	local arcPoints = sim.CalculateArcPoints(origin, adjustedTarget, projCfg)
	local numSteps = #arcPoints - 1
	local adjustedDist = (adjustedTarget - origin).Magnitude
	local travelTime = math.clamp(adjustedDist / speed, 0.05, 2.0)
	local stepDt = travelTime / numSteps

	local playerRayParams = sim.MakePlayerCheckParams(entry.Model)

	for i = 1, numSteps do
		task.wait(stepDt)

		-- Raycast this segment for player characters
		local result = sim.StepAndCheck(arcPoints[i], arcPoints[i + 1], playerRayParams)
		if result then
			local hitChar, hitPlayer = sim.FindCharacterFromHit(result.Instance)
			if hitPlayer then
				applyDamageToPlayer(hitPlayer)
				return -- projectile hit someone, done
			end
		end
	end

	-- Reached end of arc without hitting a player mid-flight
	if hitWall then
		return -- splatted against wall, no damage
	end

	-- No wall, no mid-flight hit: existing proximity check (dodge mechanic)
	targetChar = target and target.Character
	if not targetChar then return end
	targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return end
	targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then return end

	local impactDist = (targetHRP.Position - adjustedTarget).Magnitude
	if impactDist > 10 then return end -- target dodged

	applyDamageToPlayer(target)
end

function StandAndHurl:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return StandAndHurl
