--!strict
-- Lunge
-- Heavy melee: crouch, then leap toward target with a speed boost.
-- Single-target bite on arrival (no AoE). Used by wolf-type brainrots.
-- Adapted from JumpStomp but lower arc, forward-biased, single-target.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lunge = {}
Lunge.Name = "Lunge"
Lunge.Type = "Melee"
Lunge.Weight = "Heavy"
Lunge.AnimationKey = "Lunge"

local function getAttackFXRemote(): RemoteEvent?
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Net")
		and ReplicatedStorage.Shared.Net:FindFirstChild("Remotes")
		and ReplicatedStorage.Shared.Net.Remotes:FindFirstChild("RemoteEvents")
	if not net then return nil end
	local re = net:FindFirstChild("BrainrotAttackFX")
	return (re and re:IsA("RemoteEvent")) and re :: RemoteEvent or nil
end

function Lunge:CanExecute(entry: any, target: any, dist: number, moveConfig: any): boolean
	-- Lunge is a gap-closer: needs some distance to leap (too close = use BasicMelee)
	local minRange = 6
	local maxRange = (moveConfig and moveConfig.Range) or 18
	return dist >= minRange and dist <= maxRange
end

function Lunge:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local windupTime = (moveConfig and moveConfig.WindupTime) or 0.4
	local leapHeight = (moveConfig and moveConfig.LeapHeight) or 12
	local leapSpeed = (moveConfig and moveConfig.LeapSpeed) or 55

	-- Windup: crouch/coil phase — stop moving
	hum.WalkSpeed = 0
	task.wait(windupTime)

	-- Verify target still valid
	local targetChar = target and target.Character
	if not targetChar then return end
	local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then return end
	local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return end

	-- Calculate leap trajectory with lead prediction
	-- Aim where the target WILL be, not where they are now
	local toTarget = targetHRP.Position - hrp.Position
	local flatDist = Vector3.new(toTarget.X, 0, toTarget.Z).Magnitude
	local travelEst = math.clamp(flatDist / leapSpeed, 0.15, 0.6)

	-- Predict target movement during travel time
	local targetVel = targetHRP.AssemblyLinearVelocity
	local predictedPos = targetHRP.Position + targetVel * travelEst * 0.7 -- 70% lead (don't overshoot)
	local toPredicted = predictedPos - hrp.Position
	local direction = toPredicted.Unit
	local launchVelocity = Vector3.new(direction.X * leapSpeed, leapHeight, direction.Z * leapSpeed)

	-- Fire FX remote for the leap visual
	local fxRemote = getAttackFXRemote()
	if fxRemote then
		fxRemote:FireAllClients({
			AttackType = "Lunge",
			MoveName = "Lunge",
			Origin = hrp.Position,
			Target = targetHRP.Position,
			BrainrotId = entry.Id,
		})
	end

	-- Launch: apply velocity
	local bodyVel = Instance.new("BodyVelocity")
	bodyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bodyVel.Velocity = launchVelocity
	bodyVel.Parent = hrp

	-- Travel time based on distance (clamped)
	local travelTime = math.clamp(flatDist / leapSpeed, 0.15, 0.6)
	task.wait(travelTime)
	bodyVel:Destroy()

	-- Landing: deal single-target damage if still in range
	local landDist = 0
	if targetHRP and targetHRP.Parent then
		landDist = (hrp.Position - targetHRP.Position).Magnitude
	end

	local hitRange = (moveConfig and moveConfig.HitRadius) or 10
	if landDist > hitRange then return end
	if not targetHum or targetHum.Health <= 0 then return end

	-- Check if target is knocked back (invulnerable)
	local ignoreInvuln = entry.Model and entry.Model:GetAttribute("IgnoreKnockbackInvuln")
	if not ignoreInvuln and services and services.KnockbackService
		and services.KnockbackService:IsKnockedBack(target) then
		return
	end

	-- Calculate damage
	local baseDamage = 10
	if entry.EnemyInfo then
		local d = entry.EnemyInfo:GetAttribute("AttackDamage")
		if typeof(d) == "number" then baseDamage = d end
	end
	local damageMult = (moveConfig and moveConfig.DamageMult) or 1.8
	local finalDamage = math.floor(baseDamage * damageMult + 0.5)

	-- Route damage through armor
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

	-- Apply knockback if configured (opt-in via MoveOverrides)
	local knockbackCfg = moveConfig and moveConfig.Knockback
	if knockbackCfg and services and services.KnockbackService then
		services.KnockbackService:ApplyKnockback(target, knockbackCfg.Type or "push", {
			originPosition = hrp.Position,
			magnitude = knockbackCfg.Magnitude,
			ragdollDuration = knockbackCfg.RagdollDuration,
		})
	end
end

function Lunge:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return Lunge
