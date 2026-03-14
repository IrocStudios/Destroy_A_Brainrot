--!strict
-- AttackFXController
-- Client-side controller that renders brainrot attack visuals.
-- Listens to BrainrotAttackFX RemoteEvent and spawns projectile parts,
-- AoE effects, swoop trails, etc.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

type ControllerCtx = { [string]: any }

local AttackFXController = {}

local _projectileAssets: Folder? = nil
local _fxRemote: RemoteEvent? = nil

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[AttackFX]", ...) end
end

----------------------------------------------------------------------
-- Asset loading
----------------------------------------------------------------------

local function getProjectilesFolder(): Folder?
	if _projectileAssets then return _projectileAssets end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	local proj = assets:FindFirstChild("Projectiles")
	if proj and proj:IsA("Folder") then
		_projectileAssets = proj :: Folder
		return proj :: Folder
	end
	return nil
end

local function cloneProjectileModel(skinName: string): BasePart?
	local folder = getProjectilesFolder()
	if not folder then return nil end

	local template = folder:FindFirstChild(skinName)
	if not template then
		-- Fallback: try to find any child
		template = folder:FindFirstChild("Rock") or folder:GetChildren()[1]
	end
	if not template then return nil end

	local clone: Instance
	if template:IsA("BasePart") then
		clone = template:Clone()
	elseif template:IsA("Model") then
		clone = template:Clone()
		-- For models, we need a primary part or first BasePart
		local pp = (clone :: Model).PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
		if pp then
			return pp :: BasePart
		end
	else
		return nil
	end

	return clone :: BasePart
end

local function createFallbackPart(size: Vector3?): BasePart
	local p = Instance.new("Part")
	p.Size = size or Vector3.new(1.5, 1.5, 1.5)
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(139, 90, 43)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

----------------------------------------------------------------------
-- FX handlers
----------------------------------------------------------------------

local function handleProjectile(data: { [string]: any })
	local origin: Vector3 = data.Origin
	local target: Vector3 = data.Target
	if not origin or not target then return end

	local skinName = data.ProjectileSkin or "Rock"

	-- Clone or create projectile part
	local projectile = cloneProjectileModel(skinName) or createFallbackPart()
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanQuery = false
	projectile.CanTouch = false
	projectile.CFrame = CFrame.lookAt(origin, target)
	projectile.Parent = Workspace

	-- Tween to target
	local dist = (target - origin).Magnitude
	local speed = 80
	if skinName == "Bullet" then speed = 300
	elseif skinName == "Tomato" then speed = 60
	elseif skinName == "Fireball" then speed = 120
	elseif skinName == "Bomb" then speed = 40
	end

	local travelTime = math.clamp(dist / speed, 0.05, 3.0)

	-- Gravity arc for physics-affected projectiles
	local gravity = (skinName ~= "Bullet" and skinName ~= "Fireball")
	local midPoint: Vector3
	if gravity then
		local mid = (origin + target) * 0.5
		local arcHeight = math.min(dist * 0.3, 15)
		midPoint = mid + Vector3.new(0, arcHeight, 0)
	else
		midPoint = (origin + target) * 0.5
	end

	-- Simple two-phase tween for arc
	local halfTime = travelTime * 0.5

	local tween1 = TweenService:Create(projectile, TweenInfo.new(halfTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = CFrame.lookAt(midPoint, target),
	})
	tween1:Play()
	tween1.Completed:Wait()

	local tween2 = TweenService:Create(projectile, TweenInfo.new(halfTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.lookAt(target, target + (target - midPoint).Unit),
	})
	tween2:Play()
	tween2.Completed:Wait()

	-- Impact effect: quick scale down + transparency
	local impactTween = TweenService:Create(projectile, TweenInfo.new(0.15), {
		Size = projectile.Size * 0.3,
		Transparency = 1,
	})
	impactTween:Play()
	Debris:AddItem(projectile, 0.3)
end

local function handleAoE(data: { [string]: any })
	local origin: Vector3 = data.Origin
	local radius = data.AoERadius or 8
	if not origin then return end

	-- Create expanding ring effect
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 1, 1) -- thin cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 200, 50)
	ring.Transparency = 0.3
	ring.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace

	-- Expand ring to AoE radius
	local expandTween = TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		Transparency = 1,
	})
	expandTween:Play()
	Debris:AddItem(ring, 0.6)

	-- Dust cloud
	local dust = Instance.new("Part")
	dust.Shape = Enum.PartType.Ball
	dust.Size = Vector3.new(2, 2, 2)
	dust.Anchored = true
	dust.CanCollide = false
	dust.CanQuery = false
	dust.CanTouch = false
	dust.Material = Enum.Material.SmoothPlastic
	dust.Color = Color3.fromRGB(180, 160, 130)
	dust.Transparency = 0.4
	dust.CFrame = CFrame.new(origin)
	dust.Parent = Workspace

	local dustTween = TweenService:Create(dust, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius, radius * 0.5, radius),
		Transparency = 1,
	})
	dustTween:Play()
	Debris:AddItem(dust, 0.8)
end

local function handleBombDrop(data: { [string]: any })
	-- Show bomb falling, then AoE on impact
	local origin: Vector3 = data.Origin
	local target: Vector3 = data.Target
	if not origin or not target then return end

	-- Falling bomb
	local bomb = cloneProjectileModel(data.ProjectileSkin or "Bomb") or createFallbackPart(Vector3.new(2.5, 2.5, 2.5))
	bomb.Anchored = true
	bomb.CanCollide = false
	bomb.CanQuery = false
	bomb.CanTouch = false
	bomb.CFrame = CFrame.new(origin)
	bomb.Parent = Workspace

	local fallTime = math.clamp(math.sqrt(math.abs(origin.Y - target.Y) / 20), 0.3, 2.5)

	local fallTween = TweenService:Create(bomb, TweenInfo.new(fallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(target),
	})
	fallTween:Play()
	fallTween.Completed:Wait()

	bomb:Destroy()

	-- Explosion AoE
	handleAoE({
		Origin = target,
		AoERadius = data.AoERadius or 12,
	})
end

local function handleDrop(data: { [string]: any })
	local origin: Vector3 = data.Origin
	if not origin then return end

	local drop = cloneProjectileModel(data.ProjectileSkin or "Rock") or createFallbackPart()
	drop.Anchored = true
	drop.CanCollide = false
	drop.CanQuery = false
	drop.CanTouch = false
	drop.CFrame = CFrame.new(origin)
	drop.Parent = Workspace

	-- Pulsing glow before detonation
	local pulse = TweenService:Create(drop, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), {
		Size = drop.Size * 1.3,
	})
	pulse:Play()

	task.delay(0.8, function()
		if drop.Parent then
			local pos = drop.Position
			drop:Destroy()
			handleAoE({
				Origin = pos,
				AoERadius = data.AoERadius or 6,
			})
		end
	end)
end

local function handleSwoop(data: { [string]: any })
	local origin: Vector3 = data.Origin
	if not origin then return end

	-- Wind trail effect
	local trail = Instance.new("Part")
	trail.Size = Vector3.new(1, 1, 8)
	trail.Anchored = true
	trail.CanCollide = false
	trail.CanQuery = false
	trail.CanTouch = false
	trail.Material = Enum.Material.Neon
	trail.Color = Color3.fromRGB(200, 220, 255)
	trail.Transparency = 0.5
	trail.CFrame = CFrame.new(origin)
	trail.Parent = Workspace

	local swoopTween = TweenService:Create(trail, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 0.2, 20),
		Transparency = 1,
	})
	swoopTween:Play()
	Debris:AddItem(trail, 0.7)
end

----------------------------------------------------------------------
-- Controller lifecycle
----------------------------------------------------------------------

function AttackFXController:Init(ctx: ControllerCtx)
	-- Find the remote
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Net")
		and ReplicatedStorage.Shared.Net:FindFirstChild("Remotes")
		and ReplicatedStorage.Shared.Net.Remotes:FindFirstChild("RemoteEvents")
	if net then
		local remote = net:FindFirstChild("BrainrotAttackFX")
		if remote and remote:IsA("RemoteEvent") then
			_fxRemote = remote :: RemoteEvent
		end
	end

	dprint("Init OK, remote:", _fxRemote and "found" or "missing")
end

function AttackFXController:Start()
	if not _fxRemote then
		warn("[AttackFX] BrainrotAttackFX RemoteEvent not found")
		return
	end

	_fxRemote.OnClientEvent:Connect(function(data: any)
		if type(data) ~= "table" then return end

		local attackType = data.AttackType
		dprint("FX received:", attackType, data.MoveName)

		if attackType == "Projectile" then
			task.spawn(handleProjectile, data)
		elseif attackType == "AoE" then
			task.spawn(handleAoE, data)
		elseif attackType == "BombDrop" then
			task.spawn(handleBombDrop, data)
		elseif attackType == "Drop" then
			task.spawn(handleDrop, data)
		elseif attackType == "Swoop" then
			task.spawn(handleSwoop, data)
		end
	end)

	dprint("Start OK, listening for BrainrotAttackFX")
end

return AttackFXController
