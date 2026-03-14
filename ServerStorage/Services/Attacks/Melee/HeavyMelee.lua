--!strict
-- HeavyMelee
-- Slow, powerful melee attack with a windup delay before damage.
-- Higher damage multiplier, longer cooldown.

local HeavyMelee = {}
HeavyMelee.Name = "HeavyMelee"
HeavyMelee.Type = "Melee"
HeavyMelee.Weight = "Heavy"
HeavyMelee.AnimationKey = "HeavyMelee"

function HeavyMelee:CanExecute(entry: any, target: any, dist: number): boolean
	return true
end

function HeavyMelee:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	if not hum or hum.Health <= 0 then return end

	local windupTime = (moveConfig and moveConfig.WindupTime) or 0.8

	-- Windup delay (animation plays during this)
	task.wait(windupTime)

	-- Verify target is still valid and in range after windup
	local targetChar = target and target.Character
	if not targetChar then return end
	local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return end

	local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then return end
	if not entry.HRP then return end

	local dist2 = (targetHRP.Position - entry.HRP.Position).Magnitude
	local range = (moveConfig and moveConfig.Range) or 7
	if dist2 > range * 1.5 then return end -- target escaped during windup

	-- Calculate damage
	local baseDamage = 10
	local enemyInfo = entry.EnemyInfo
	if enemyInfo then
		local d = enemyInfo:GetAttribute("AttackDamage")
		if typeof(d) == "number" then baseDamage = d end
	end

	local damageMult = (moveConfig and moveConfig.DamageMult) or 2.5
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

function HeavyMelee:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return HeavyMelee
