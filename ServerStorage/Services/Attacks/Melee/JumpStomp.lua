--!strict
-- JumpStomp
-- Heavy melee: leap toward target, deal AoE damage on landing.
-- Windup = crouch, then launch upward, then slam down.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JumpStomp = {}
JumpStomp.Name = "JumpStomp"
JumpStomp.Type = "Melee"
JumpStomp.Weight = "Heavy"
JumpStomp.AnimationKey = "JumpStomp"

local function getAttackFXRemote(): RemoteEvent?
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Net")
		and ReplicatedStorage.Shared.Net:FindFirstChild("Remotes")
		and ReplicatedStorage.Shared.Net.Remotes:FindFirstChild("RemoteEvents")
	if not net then return nil end
	local re = net:FindFirstChild("BrainrotAttackFX")
	return (re and re:IsA("RemoteEvent")) and re :: RemoteEvent or nil
end

function JumpStomp:CanExecute(entry: any, target: any, dist: number): boolean
	-- Need enough distance to make the leap meaningful, but not too far
	return dist >= 4 and dist <= (entry.EnemyInfo and entry.EnemyInfo:GetAttribute("AttackRange") or 12) * 1.5
end

function JumpStomp:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local windupTime = (moveConfig and moveConfig.WindupTime) or 0.6
	local leapHeight = (moveConfig and moveConfig.LeapHeight) or 20
	local aoeRadius = (moveConfig and moveConfig.AoERadius) or 8

	-- Windup: crouch phase
	hum.WalkSpeed = 0
	task.wait(windupTime * 0.4)

	-- Verify target
	local targetChar = target and target.Character
	if not targetChar then return end
	local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then return end

	local landingPos = targetHRP.Position

	-- Launch phase: apply upward + forward velocity
	local direction = (landingPos - hrp.Position).Unit
	local launchVelocity = direction * 40 + Vector3.new(0, leapHeight * 2, 0)

	local bodyVel = Instance.new("BodyVelocity")
	bodyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bodyVel.Velocity = launchVelocity
	bodyVel.Parent = hrp

	task.wait(windupTime * 0.3)
	bodyVel:Destroy()

	-- Slam down
	local slamVel = Instance.new("BodyVelocity")
	slamVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	slamVel.Velocity = Vector3.new(direction.X * 20, -leapHeight * 3, direction.Z * 20)
	slamVel.Parent = hrp

	task.wait(windupTime * 0.3)
	slamVel:Destroy()

	-- Fire FX remote for landing impact
	local fxRemote = getAttackFXRemote()
	if fxRemote then
		fxRemote:FireAllClients({
			AttackType = "AoE",
			MoveName = "JumpStomp",
			Origin = hrp.Position,
			AoERadius = aoeRadius,
			BrainrotId = entry.Id,
		})
	end

	-- AoE damage to all players in radius
	local baseDamage = 10
	if entry.EnemyInfo then
		local d = entry.EnemyInfo:GetAttribute("AttackDamage")
		if typeof(d) == "number" then baseDamage = d end
	end
	local damageMult = (moveConfig and moveConfig.DamageMult) or 2.0
	local finalDamage = math.floor(baseDamage * damageMult + 0.5)
	local impactPos = hrp.Position

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

		-- Distance falloff: 100% at center, 50% at edge
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

function JumpStomp:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return JumpStomp
