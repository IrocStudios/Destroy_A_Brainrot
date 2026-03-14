--!strict
-- BasicMelee
-- Standard melee attack: stand still, deal damage when in range.
-- This is the extraction of the original hardcoded AIService attack behavior.

local BasicMelee = {}
BasicMelee.Name = "BasicMelee"
BasicMelee.Type = "Melee"
BasicMelee.Weight = "Light"
BasicMelee.AnimationKey = "BasicMelee" -- resolves to "attack_BasicMelee"

function BasicMelee:CanExecute(entry: any, target: any, dist: number): boolean
	-- Basic melee can always execute if in range
	return true
end

function BasicMelee:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	if not hum or hum.Health <= 0 then return end

	-- Get target humanoid
	local targetChar = target and target.Character
	if not targetChar then return end
	local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return end

	-- Calculate damage
	local baseDamage = 10
	local enemyInfo = entry.EnemyInfo
	if enemyInfo then
		local d = enemyInfo:GetAttribute("AttackDamage")
		if typeof(d) == "number" then baseDamage = d end
	end

	local damageMult = (moveConfig and moveConfig.DamageMult) or 1.0
	local finalDamage = math.floor(baseDamage * damageMult + 0.5)

	-- Route damage through armor first, overflow hits health
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

function BasicMelee:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return BasicMelee
