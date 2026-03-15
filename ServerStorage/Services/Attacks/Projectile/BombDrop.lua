--!strict
-- BombDrop
-- Heavy projectile for flying enemies: drop a bomb from altitude, AoE on impact.
-- Large damage radius, gravity-affected projectile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local BombDrop = {}
BombDrop.Name = "BombDrop"
BombDrop.Type = "Projectile"
BombDrop.Weight = "Heavy"
BombDrop.AnimationKey = "BombDrop"

local function getAttackFXRemote(): RemoteEvent?
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Net")
		and ReplicatedStorage.Shared.Net:FindFirstChild("Remotes")
		and ReplicatedStorage.Shared.Net.Remotes:FindFirstChild("RemoteEvents")
	if not net then return nil end
	local re = net:FindFirstChild("BrainrotAttackFX")
	return (re and re:IsA("RemoteEvent")) and re :: RemoteEvent or nil
end

function BombDrop:CanExecute(entry: any, target: any, dist: number): boolean
	-- Need to be flying (above target)
	local loco = entry.Locomotion
	if not loco then return false end
	if type(loco.IsFlying) == "function" and not loco:IsFlying() then return false end
	return true
end

function BombDrop:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local windupTime = (moveConfig and moveConfig.WindupTime) or 0.5
	local aoeRadius = (moveConfig and moveConfig.AoERadius) or 12

	task.wait(windupTime)

	-- Verify target
	local targetChar = target and target.Character
	if not targetChar then return end
	local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then return end

	local dropOrigin = hrp.Position
	local impactPos = targetHRP.Position -- target position at time of drop

	-- Projectile skin
	local projectileSkin = (moveConfig and moveConfig.Projectile) or "Bomb"
	local brainrotSkin = entry.Model and entry.Model:GetAttribute("ProjectileSkin")
	if type(brainrotSkin) == "string" and brainrotSkin ~= "" then
		projectileSkin = brainrotSkin
	end

	-- Fire FX
	local fxRemote = getAttackFXRemote()
	if fxRemote then
		fxRemote:FireAllClients({
			AttackType = "BombDrop",
			MoveName = "BombDrop",
			Origin = dropOrigin,
			Target = impactPos,
			ProjectileSkin = projectileSkin,
			AoERadius = aoeRadius,
			BrainrotId = entry.Id,
		})
	end

	-- Simulate bomb fall time based on altitude
	local altitude = math.abs(dropOrigin.Y - impactPos.Y)
	local fallTime = math.clamp(math.sqrt(altitude / 20), 0.3, 2.5)
	task.wait(fallTime)

	-- AoE damage at impact position
	local baseDamage = 10
	if entry.EnemyInfo then
		local d = entry.EnemyInfo:GetAttribute("AttackDamage")
		if typeof(d) == "number" then baseDamage = d end
	end
	local damageMult = (moveConfig and moveConfig.DamageMult) or 2.0
	local finalDamage = math.floor(baseDamage * damageMult + 0.5)

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if not char then continue end
		local pHRP = char:FindFirstChild("HumanoidRootPart")
		local pHum = char:FindFirstChildOfClass("Humanoid")
		if not pHRP or not pHRP:IsA("BasePart") or not pHum or pHum.Health <= 0 then continue end

		local d = (pHRP.Position - impactPos).Magnitude
		if d > aoeRadius then continue end

		-- Check if target is knocked back (invulnerable)
		if services and services.KnockbackService
			and services.KnockbackService:IsKnockedBack(plr) then
			continue
		end

		local falloff = 1 - (d / aoeRadius) * 0.5
		local dmg = math.floor(finalDamage * falloff + 0.5)

		pcall(function()
			local armorSvc = services and services.ArmorService
			if armorSvc then
				local absorbed, overflow = armorSvc:DamageArmor(plr, dmg)
				if overflow > 0 then pHum:TakeDamage(overflow) end
			else
				pHum:TakeDamage(dmg)
			end
		end)
	end
end

function BombDrop:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return BombDrop
