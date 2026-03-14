--!strict
-- MultiSwing
-- Light melee: rapid 2-3 hit combo with short delays between swings.
-- Lower per-hit damage but high total if all swings connect.

local MultiSwing = {}
MultiSwing.Name = "MultiSwing"
MultiSwing.Type = "Melee"
MultiSwing.Weight = "Light"
MultiSwing.AnimationKey = "MultiSwing"

function MultiSwing:CanExecute(entry: any, target: any, dist: number): boolean
	return true
end

function MultiSwing:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local swings = (moveConfig and moveConfig.Swings) or 3
	local swingDelay = (moveConfig and moveConfig.SwingDelay) or 0.25
	local windupTime = (moveConfig and moveConfig.WindupTime) or 0.1

	local baseDamage = 10
	if entry.EnemyInfo then
		local d = entry.EnemyInfo:GetAttribute("AttackDamage")
		if typeof(d) == "number" then baseDamage = d end
	end
	local damageMult = (moveConfig and moveConfig.DamageMult) or 0.5
	local perSwingDamage = math.floor(baseDamage * damageMult + 0.5)

	local range = (moveConfig and moveConfig.Range) or 6

	-- Initial windup
	task.wait(windupTime)

	for i = 1, swings do
		if hum.Health <= 0 then return end

		-- Verify target each swing
		local targetChar = target and target.Character
		if not targetChar then return end
		local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
		if not targetHum or targetHum.Health <= 0 then return end
		local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
		if not targetHRP or not targetHRP:IsA("BasePart") then return end

		local d = (targetHRP.Position - hrp.Position).Magnitude
		if d > range * 1.5 then return end -- target escaped mid-combo

		pcall(function()
			local armorSvc = services and services.ArmorService
			if armorSvc and target then
				local absorbed, overflow = armorSvc:DamageArmor(target, perSwingDamage)
				if overflow > 0 then targetHum:TakeDamage(overflow) end
			else
				targetHum:TakeDamage(perSwingDamage)
			end
		end)

		if i < swings then
			task.wait(swingDelay)
		end
	end
end

function MultiSwing:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return MultiSwing
