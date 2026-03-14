--!strict
-- GunStyle
-- Light projectile: rapid-fire burst of fast projectiles (hitscan-like).
-- Short cooldown per burst, multiple shots per burst.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GunStyle = {}
GunStyle.Name = "GunStyle"
GunStyle.Type = "Projectile"
GunStyle.Weight = "Light"
GunStyle.AnimationKey = "GunStyle"

local function getAttackFXRemote(): RemoteEvent?
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Net")
		and ReplicatedStorage.Shared.Net:FindFirstChild("Remotes")
	if not net then return nil end
	local re = net:FindFirstChild("BrainrotAttackFX")
	return (re and re:IsA("RemoteEvent")) and re :: RemoteEvent or nil
end

function GunStyle:CanExecute(entry: any, target: any, dist: number): boolean
	return dist >= 8 -- don't shoot at point-blank
end

function GunStyle:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	local burstCount = (moveConfig and moveConfig.BurstCount) or 3
	local burstDelay = (moveConfig and moveConfig.BurstDelay) or 0.08
	local windupTime = (moveConfig and moveConfig.WindupTime) or 0.05

	-- Stop to shoot
	hum.WalkSpeed = 0
	hum:Move(Vector3.zero, false)

	task.wait(windupTime)

	local projectileSkin = (moveConfig and moveConfig.Projectile) or "Bullet"
	local brainrotSkin = entry.Model and entry.Model:GetAttribute("ProjectileSkin")
	if type(brainrotSkin) == "string" and brainrotSkin ~= "" then
		projectileSkin = brainrotSkin
	end

	local baseDamage = 10
	if entry.EnemyInfo then
		local d = entry.EnemyInfo:GetAttribute("AttackDamage")
		if typeof(d) == "number" then baseDamage = d end
	end
	local damageMult = (moveConfig and moveConfig.DamageMult) or 0.25
	local perBulletDamage = math.max(1, math.floor(baseDamage * damageMult + 0.5))

	local fxRemote = getAttackFXRemote()

	for i = 1, burstCount do
		if hum.Health <= 0 then return end

		-- Verify target each shot
		local targetChar = target and target.Character
		if not targetChar then return end
		local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
		if not targetHum or targetHum.Health <= 0 then return end
		local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
		if not targetHRP or not targetHRP:IsA("BasePart") then return end

		local origin = hrp.Position + Vector3.new(0, 1.5, 0)
		local targetPos = targetHRP.Position

		-- Add slight spread
		local spread = Vector3.new(
			(math.random() - 0.5) * 2,
			(math.random() - 0.5) * 1,
			(math.random() - 0.5) * 2
		)
		targetPos = targetPos + spread

		-- Fire FX per bullet
		if fxRemote then
			fxRemote:FireAllClients({
				AttackType = "Projectile",
				MoveName = "GunStyle",
				Origin = origin,
				Target = targetPos,
				ProjectileSkin = projectileSkin,
				BrainrotId = entry.Id,
			})
		end

		-- Hitscan-like: raycast for hit detection
		local direction = (targetPos - origin).Unit
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { entry.Model }

		local result = Workspace:Raycast(origin, direction * 200, rayParams)
		if result and result.Instance then
			-- Check if we hit the target's character
			local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
			if hitModel and hitModel == targetChar then
				pcall(function()
					local armorSvc = services and services.ArmorService
					if armorSvc and target then
						local absorbed, overflow = armorSvc:DamageArmor(target, perBulletDamage)
						if overflow > 0 then targetHum:TakeDamage(overflow) end
					else
						targetHum:TakeDamage(perBulletDamage)
					end
				end)
			end
		end

		if i < burstCount then
			task.wait(burstDelay)
		end
	end
end

function GunStyle:GetAnimationName(): string
	return "attack_" .. self.AnimationKey
end

return GunStyle
