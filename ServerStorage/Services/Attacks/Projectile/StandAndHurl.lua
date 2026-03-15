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
	local baseTargetPos = targetHRP.Position

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
	local maxRange = projCfg.MaxRange

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
		-- Check if target is knocked back (invulnerable)
		if services and services.KnockbackService
			and services.KnockbackService:IsKnockedBack(hitPlayer) then
			return
		end
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

	-- Multi-projectile support: calculate spread targets
	local projectileCount = (moveConfig and moveConfig.ProjectileCount) or 1
	local spreadAngleDeg = (moveConfig and moveConfig.SpreadAngle) or 0
	local baseSpread = (moveConfig and moveConfig.Spread) or 0

	-- Build list of target positions for each projectile
	local targetList = {}
	if projectileCount <= 1 then
		-- Single projectile: use normal accuracy spread
		local tp = baseTargetPos
		if baseSpread > 0 then
			tp = tp + Vector3.new(
				(math.random() - 0.5) * 2 * baseSpread,
				(math.random() - 0.5) * baseSpread * 0.5,
				(math.random() - 0.5) * 2 * baseSpread
			)
		end
		table.insert(targetList, tp)
	else
		-- Multi-projectile shotgun spread: fan evenly across spreadAngle
		local dir = (baseTargetPos - origin) * Vector3.new(1, 0, 1) -- XZ direction
		if dir.Magnitude < 0.1 then dir = Vector3.new(0, 0, 1) end
		dir = dir.Unit
		local dist2D = (baseTargetPos - origin).Magnitude

		local halfAngle = math.rad(spreadAngleDeg / 2)
		for i = 1, projectileCount do
			-- Evenly distribute angles from -halfAngle to +halfAngle
			local frac = (i - 1) / math.max(projectileCount - 1, 1)
			local angle = -halfAngle + frac * (halfAngle * 2)
			-- Rotate direction around Y axis
			local cosA = math.cos(angle)
			local sinA = math.sin(angle)
			local rotDir = Vector3.new(
				dir.X * cosA - dir.Z * sinA,
				0,
				dir.X * sinA + dir.Z * cosA
			)
			local tp = origin + rotDir * dist2D + Vector3.new(0, baseTargetPos.Y - origin.Y, 0)
			-- Add per-projectile accuracy jitter
			if baseSpread > 0 then
				tp = tp + Vector3.new(
					(math.random() - 0.5) * 2 * baseSpread,
					(math.random() - 0.5) * baseSpread * 0.5,
					(math.random() - 0.5) * 2 * baseSpread
				)
			end
			table.insert(targetList, tp)
		end
	end

	-- Fire each projectile (spawn concurrently for multi-projectile)
	local function fireOneProjectile(targetPos: Vector3)
		local dist = (targetPos - origin).Magnitude
		if maxRange and dist > maxRange then return end

		local sim = getSimulator()
		if not sim then
			-- Fallback: no simulator
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
			local tc = target and target.Character
			if tc then
				local th = tc:FindFirstChildOfClass("Humanoid")
				local tr = tc:FindFirstChild("HumanoidRootPart")
				if th and th.Health > 0 and tr and tr:IsA("BasePart") then
					if (tr.Position - targetPos).Magnitude <= 10 then
						applyDamageToPlayer(target)
					end
				end
			end
			return
		end

		-- Phase 1: Pre-calc wall collisions
		local adjustedTarget, wallFrac = sim.CheckWalls(origin, targetPos, projCfg, { entry.Model })
		local hitWall = wallFrac < 0.99

		-- Fire client FX
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

		-- Phase 2: Stepped player detection along the arc
		local arcPoints = sim.CalculateArcPoints(origin, adjustedTarget, projCfg)
		local numSteps = #arcPoints - 1
		local adjustedDist = (adjustedTarget - origin).Magnitude
		local travelTime = math.clamp(adjustedDist / speed, 0.05, 2.0)
		local stepDt = travelTime / numSteps

		local playerRayParams = sim.MakePlayerCheckParams(entry.Model)

		for i = 1, numSteps do
			task.wait(stepDt)
			local result = sim.StepAndCheck(arcPoints[i], arcPoints[i + 1], playerRayParams)
			if result then
				local hitChar, hitPlayer = sim.FindCharacterFromHit(result.Instance)
				if hitPlayer then
					applyDamageToPlayer(hitPlayer)
					return
				end
			end
		end

		if hitWall then return end

		-- End-of-arc proximity check (dodge mechanic)
		local tc = target and target.Character
		if not tc then return end
		local th = tc:FindFirstChildOfClass("Humanoid")
		if not th or th.Health <= 0 then return end
		local tr = tc:FindFirstChild("HumanoidRootPart")
		if not tr or not tr:IsA("BasePart") then return end

		local impactDist = (tr.Position - adjustedTarget).Magnitude
		if impactDist > 10 then return end

		applyDamageToPlayer(target)
	end

	-- Launch all projectiles
	if #targetList == 1 then
		fireOneProjectile(targetList[1])
	else
		-- Multi-projectile: fire all concurrently
		for _, tp in ipairs(targetList) do
			task.spawn(fireOneProjectile, tp)
		end
	end
end

function StandAndHurl:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return StandAndHurl
