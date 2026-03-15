--!strict
-- HitAndRun
-- Light melee: quick strike then brief flee away from target.
-- Lower damage but safe — the brainrot disengages after each hit.

local HitAndRun = {}
HitAndRun.Name = "HitAndRun"
HitAndRun.Type = "Melee"
HitAndRun.Weight = "Light"
HitAndRun.AnimationKey = "HitAndRun"

function HitAndRun:CanExecute(entry: any, target: any, dist: number): boolean
	return true
end

function HitAndRun:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local windupTime = (moveConfig and moveConfig.WindupTime) or 0.15

	-- Quick windup
	task.wait(windupTime)

	-- Verify target
	local targetChar = target and target.Character
	if not targetChar then return end
	local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return end
	local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then return end

	local d = (targetHRP.Position - hrp.Position).Magnitude
	local range = (moveConfig and moveConfig.Range) or 6
	if d > range * 1.5 then return end

	-- Check if target is knocked back (invulnerable)
	if services and services.KnockbackService
		and services.KnockbackService:IsKnockedBack(target) then
		return
	end

	-- Deal damage
	local baseDamage = 10
	if entry.EnemyInfo then
		local dmg = entry.EnemyInfo:GetAttribute("AttackDamage")
		if typeof(dmg) == "number" then baseDamage = dmg end
	end
	local damageMult = (moveConfig and moveConfig.DamageMult) or 0.8
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

	-- Flee phase: run away briefly
	local fleeTime = (moveConfig and moveConfig.FleeTime) or 1.5
	local away = (hrp.Position - targetHRP.Position)
	if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
	away = away.Unit

	local runSpeed = 20
	if entry.EnemyInfo then
		local rs = entry.EnemyInfo:GetAttribute("Runspeed")
		if typeof(rs) == "number" then runSpeed = rs end
	end

	hum.WalkSpeed = runSpeed * 1.2
	local fleeTarget = hrp.Position + away * 25
	hum:MoveTo(fleeTarget)

	task.wait(fleeTime)

	-- Return to chase state will be handled by AIService on next tick
end

function HitAndRun:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return HitAndRun
