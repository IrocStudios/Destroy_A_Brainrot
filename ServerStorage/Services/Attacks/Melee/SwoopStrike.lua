--!strict
-- SwoopStrike
-- Heavy melee for flying enemies: dive from altitude, strike on contact, recover to altitude.
-- Integrates with SwoopLocomotion's dive/recover phases.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SwoopStrike = {}
SwoopStrike.Name = "SwoopStrike"
SwoopStrike.Type = "Melee"
SwoopStrike.Weight = "Heavy"
SwoopStrike.AnimationKey = "SwoopStrike"

local function getAttackFXRemote(): RemoteEvent?
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Net")
		and ReplicatedStorage.Shared.Net:FindFirstChild("Remotes")
		and ReplicatedStorage.Shared.Net.Remotes:FindFirstChild("RemoteEvents")
	if not net then return nil end
	local re = net:FindFirstChild("BrainrotAttackFX")
	return (re and re:IsA("RemoteEvent")) and re :: RemoteEvent or nil
end

function SwoopStrike:CanExecute(entry: any, target: any, dist: number): boolean
	-- Must be a flying entity with SwoopLocomotion
	local loco = entry.Locomotion
	if not loco or loco.Name ~= "Swoop" then return false end

	-- Must be in cruise phase (not already diving/recovering)
	if type(loco.GetPhase) == "function" then
		local phase = loco:GetPhase(entry)
		if phase ~= "Cruise" then return false end
	end

	return true
end

function SwoopStrike:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local loco = entry.Locomotion
	local windupTime = (moveConfig and moveConfig.WindupTime) or 1.0

	-- Trigger dive phase
	if loco and type(loco.StartDive) == "function" then
		loco:StartDive(entry)
	end

	-- Fire FX for swoop
	local fxRemote = getAttackFXRemote()
	if fxRemote then
		fxRemote:FireAllClients({
			AttackType = "Swoop",
			MoveName = "SwoopStrike",
			Origin = hrp.Position,
			BrainrotId = entry.Id,
		})
	end

	-- Wait for dive to reach target area
	task.wait(windupTime)

	-- Check target still valid
	local targetChar = target and target.Character
	if not targetChar then
		if loco and type(loco.EndDive) == "function" then loco:EndDive(entry) end
		return
	end
	local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then
		if loco and type(loco.EndDive) == "function" then loco:EndDive(entry) end
		return
	end
	local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then
		if loco and type(loco.EndDive) == "function" then loco:EndDive(entry) end
		return
	end

	-- Check proximity at impact
	local d = (targetHRP.Position - hrp.Position).Magnitude
	local range = (moveConfig and moveConfig.Range) or 15

	if d <= range then
		local baseDamage = 10
		if entry.EnemyInfo then
			local dmg = entry.EnemyInfo:GetAttribute("AttackDamage")
			if typeof(dmg) == "number" then baseDamage = dmg end
		end
		local damageMult = (moveConfig and moveConfig.DamageMult) or 2.2
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

	-- Recover: climb back to altitude
	if loco and type(loco.EndDive) == "function" then
		loco:EndDive(entry)
	end
end

function SwoopStrike:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return SwoopStrike
