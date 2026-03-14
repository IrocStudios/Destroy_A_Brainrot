--!strict
-- StandAndHurl
-- Ranged projectile attack: stop moving, wind up, hurl a projectile at the target.
-- Server does damage via raycast/proximity at impact. Fires RemoteEvent for client FX.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local StandAndHurl = {}
StandAndHurl.Name = "StandAndHurl"
StandAndHurl.Type = "Projectile"
StandAndHurl.Weight = "Light"
StandAndHurl.AnimationKey = "StandAndHurl"

local function getAttackFXRemote(): RemoteEvent?
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Net")
		and ReplicatedStorage.Shared.Net:FindFirstChild("Remotes")
	if not net then return nil end
	local remote = net:FindFirstChild("BrainrotAttackFX")
	if remote and remote:IsA("RemoteEvent") then
		return remote :: RemoteEvent
	end
	return nil
end

function StandAndHurl:CanExecute(entry: any, target: any, dist: number): boolean
	return dist >= 8 -- don't throw at point-blank range
end

function StandAndHurl:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	if not hum or hum.Health <= 0 then return end

	-- Stop moving during throw
	hum.WalkSpeed = 0
	hum:Move(Vector3.zero, false)

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

	-- Determine projectile skin
	local projectileSkin = (moveConfig and moveConfig.Projectile) or "Rock"
	-- Per-brainrot override
	local brainrotSkin = entry.Model and entry.Model:GetAttribute("ProjectileSkin")
	if type(brainrotSkin) == "string" and brainrotSkin ~= "" then
		projectileSkin = brainrotSkin
	end

	-- Fire client FX remote
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

	-- Server-side damage: simulate projectile travel time then apply
	local dist = (targetPos - origin).Magnitude
	local speed = 80 -- default; could read from AttackConfig.Projectiles
	local travelTime = math.clamp(dist / speed, 0.05, 2.0)

	task.wait(travelTime)

	-- Re-check target position (they may have moved)
	targetChar = target and target.Character
	if not targetChar then return end
	targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return end
	targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then return end

	-- Check if projectile would have hit (proximity at time of impact)
	local impactDist = (targetHRP.Position - targetPos).Magnitude
	if impactDist > 10 then return end -- target dodged

	-- Calculate damage
	local baseDamage = 10
	local enemyInfo = entry.EnemyInfo
	if enemyInfo then
		local d = enemyInfo:GetAttribute("AttackDamage")
		if typeof(d) == "number" then baseDamage = d end
	end

	local damageMult = (moveConfig and moveConfig.DamageMult) or 0.8
	local finalDamage = math.floor(baseDamage * damageMult + 0.5)

	pcall(function()
		local armorSvc = services and services.ArmorService
		if armorSvc and target then
			local absorbed, overflow = armorSvc:DamageArmor(target, finalDamage)
			if overflow > 0 then
				targetHum:TakeDamage(overflow)
			end
		else
			targetHum:TakeDamage(finalDamage)
		end
	end)
end

function StandAndHurl:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return StandAndHurl
