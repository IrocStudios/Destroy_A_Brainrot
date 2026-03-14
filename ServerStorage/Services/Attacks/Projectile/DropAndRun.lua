--!strict
-- DropAndRun
-- Light projectile: drop a projectile at current position, then flee away.
-- Effective as a trap — works well with Fearful/Skittish personalities.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DropAndRun = {}
DropAndRun.Name = "DropAndRun"
DropAndRun.Type = "Projectile"
DropAndRun.Weight = "Light"
DropAndRun.AnimationKey = "DropAndRun"

local function getAttackFXRemote(): RemoteEvent?
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Net")
		and ReplicatedStorage.Shared.Net:FindFirstChild("Remotes")
	if not net then return nil end
	local re = net:FindFirstChild("BrainrotAttackFX")
	return (re and re:IsA("RemoteEvent")) and re :: RemoteEvent or nil
end

function DropAndRun:CanExecute(entry: any, target: any, dist: number): boolean
	-- Only drop when target is relatively close (trap range)
	return dist <= 12
end

function DropAndRun:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local windupTime = (moveConfig and moveConfig.WindupTime) or 0.1
	local fleeTime = (moveConfig and moveConfig.FleeTime) or 2.0

	task.wait(windupTime)

	local dropPos = hrp.Position
	local aoeRadius = 6 -- small AoE for the dropped projectile

	-- Projectile skin
	local projectileSkin = (moveConfig and moveConfig.Projectile) or "Rock"
	local brainrotSkin = entry.Model and entry.Model:GetAttribute("ProjectileSkin")
	if type(brainrotSkin) == "string" and brainrotSkin ~= "" then
		projectileSkin = brainrotSkin
	end

	-- Fire FX for drop
	local fxRemote = getAttackFXRemote()
	if fxRemote then
		fxRemote:FireAllClients({
			AttackType = "Drop",
			MoveName = "DropAndRun",
			Origin = dropPos,
			ProjectileSkin = projectileSkin,
			AoERadius = aoeRadius,
			BrainrotId = entry.Id,
		})
	end

	-- Flee immediately
	local targetChar = target and target.Character
	local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
	if targetHRP and targetHRP:IsA("BasePart") then
		local away = (hrp.Position - targetHRP.Position)
		if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
		away = away.Unit

		local runSpeed = 20
		if entry.EnemyInfo then
			local rs = entry.EnemyInfo:GetAttribute("Runspeed")
			if typeof(rs) == "number" then runSpeed = rs end
		end
		hum.WalkSpeed = runSpeed * 1.3
		hum:MoveTo(hrp.Position + away * 30)
	end

	-- Delayed AoE damage at drop location (fuse time)
	task.wait(0.8)

	local baseDamage = 10
	if entry.EnemyInfo then
		local d = entry.EnemyInfo:GetAttribute("AttackDamage")
		if typeof(d) == "number" then baseDamage = d end
	end
	local damageMult = (moveConfig and moveConfig.DamageMult) or 1.2
	local finalDamage = math.floor(baseDamage * damageMult + 0.5)

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if not char then continue end
		local pHRP = char:FindFirstChild("HumanoidRootPart")
		local pHum = char:FindFirstChildOfClass("Humanoid")
		if not pHRP or not pHRP:IsA("BasePart") or not pHum or pHum.Health <= 0 then continue end

		local d = (pHRP.Position - dropPos).Magnitude
		if d > aoeRadius then continue end

		local falloff = 1 - (d / aoeRadius) * 0.4
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

	-- Wait remainder of flee time
	task.wait(math.max(0, fleeTime - 0.8))
end

function DropAndRun:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return DropAndRun
