--!strict
-- ChaseAndHurl
-- Light projectile: continues moving toward target while periodically throwing.
-- Does NOT stop to throw — fires mid-chase for pressure.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChaseAndHurl = {}
ChaseAndHurl.Name = "ChaseAndHurl"
ChaseAndHurl.Type = "Projectile"
ChaseAndHurl.Weight = "Light"
ChaseAndHurl.AnimationKey = "ChaseAndHurl"

local function getAttackFXRemote(): RemoteEvent?
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Net")
		and ReplicatedStorage.Shared.Net:FindFirstChild("Remotes")
	if not net then return nil end
	local re = net:FindFirstChild("BrainrotAttackFX")
	return (re and re:IsA("RemoteEvent")) and re :: RemoteEvent or nil
end

function ChaseAndHurl:CanExecute(entry: any, target: any, dist: number): boolean
	return dist >= 5
end

function ChaseAndHurl:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	-- Keep moving — do NOT stop walkspeed
	local windupTime = (moveConfig and moveConfig.WindupTime) or 0.3
	task.wait(windupTime)

	-- Verify target
	local targetChar = target and target.Character
	if not targetChar then return end
	local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return end
	local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then return end

	local origin = hrp.Position + Vector3.new(0, 2, 0)
	local targetPos = targetHRP.Position

	-- Projectile skin
	local projectileSkin = (moveConfig and moveConfig.Projectile) or "Tomato"
	local brainrotSkin = entry.Model and entry.Model:GetAttribute("ProjectileSkin")
	if type(brainrotSkin) == "string" and brainrotSkin ~= "" then
		projectileSkin = brainrotSkin
	end

	-- Fire FX
	local fxRemote = getAttackFXRemote()
	if fxRemote then
		fxRemote:FireAllClients({
			AttackType = "Projectile",
			MoveName = "ChaseAndHurl",
			Origin = origin,
			Target = targetPos,
			ProjectileSkin = projectileSkin,
			BrainrotId = entry.Id,
		})
	end

	-- Server-side damage after travel time
	local dist2 = (targetPos - origin).Magnitude
	local speed = 60
	local travelTime = math.clamp(dist2 / speed, 0.05, 2.0)
	task.wait(travelTime)

	-- Re-check target
	targetChar = target and target.Character
	if not targetChar then return end
	targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return end
	targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then return end

	-- Hit check: did target dodge?
	if (targetHRP.Position - targetPos).Magnitude > 12 then return end

	local baseDamage = 10
	if entry.EnemyInfo then
		local d = entry.EnemyInfo:GetAttribute("AttackDamage")
		if typeof(d) == "number" then baseDamage = d end
	end
	local damageMult = (moveConfig and moveConfig.DamageMult) or 0.6
	local finalDamage = math.floor(baseDamage * damageMult + 0.5)

	pcall(function()
		local armorSvc = services and services.ArmorService
		if armorSvc and target then
			local absorbed, overflow = armorSvc:DamageArmor(target, finalDamage)
			if overflow > 0 then targetHum:TakeDamage(overflow) end
		else
			targetHum:TakeDamage(finalDamage)
		end
	end)
end

function ChaseAndHurl:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return ChaseAndHurl
