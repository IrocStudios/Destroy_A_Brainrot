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
local _attackConfig: any = nil

local function getAttackConfig(): any
	if _attackConfig then return _attackConfig end
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("AttackConfig"))
	end)
	if ok and type(mod) == "table" then
		_attackConfig = mod
		return mod
	end
	_attackConfig = { Projectiles = {}, Moves = {} }
	return _attackConfig
end

local function getProjectileConfig(skinName: string): { [string]: any }
	local cfg = getAttackConfig()
	local p = cfg.Projectiles and cfg.Projectiles[skinName]
	if type(p) == "table" then return p end
	-- Fallback defaults
	return {
		Speed = 80, Gravity = true, ArcHeight = 0.3, ArcHeightCap = 15,
		Bounce = false, BounceCount = 0, BounceDamping = 0.5,
	}
end

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

--- Clone a projectile asset. Returns (rootPart, container).
--- rootPart: the BasePart to tween (PrimaryPart for models, the part itself for parts).
--- container: the Instance to parent to Workspace and destroy on cleanup (Model or Part).
--- For a Model, tweening rootPart.CFrame moves the whole model via PrimaryPart linkage.
local function cloneProjectile(skinName: string): (BasePart?, Instance?)
	local folder = getProjectilesFolder()
	if not folder then return nil, nil end

	local template = folder:FindFirstChild(skinName)
	if not template then
		template = folder:FindFirstChild("Rock") or folder:GetChildren()[1]
	end
	if not template then return nil, nil end

	local clone = template:Clone()

	if clone:IsA("BasePart") then
		return clone, clone
	elseif clone:IsA("Model") then
		local pp = (clone :: Model).PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
		if pp then
			-- Anchor all parts so the model doesn't fall
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Anchored = true
					desc.CanCollide = false
					desc.CanQuery = false
					desc.CanTouch = false
				end
			end
			return pp :: BasePart, clone
		end
		clone:Destroy()
	else
		clone:Destroy()
	end
	return nil, nil
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

--- Tween a projectile along a two-phase arc from `from` to `to`.
--- Returns the landing position (same as `to`).
local function tweenArc(
	projectile: BasePart,
	from: Vector3,
	to: Vector3,
	pCfg: { [string]: any }
)
	local dist = (to - from).Magnitude
	local speed = pCfg.Speed or 80
	local travelTime = math.clamp(dist / speed, 0.05, 3.0)

	local midPoint: Vector3
	if pCfg.Gravity then
		local mid = (from + to) * 0.5
		local arcMult = pCfg.ArcHeight or 0.3
		local arcCap = pCfg.ArcHeightCap or 15
		local arcHeight = math.min(dist * arcMult, arcCap)
		midPoint = mid + Vector3.new(0, arcHeight, 0)
	else
		midPoint = (from + to) * 0.5
	end

	local halfTime = travelTime * 0.5

	local tween1 = TweenService:Create(projectile,
		TweenInfo.new(halfTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.lookAt(midPoint, to) }
	)
	tween1:Play()
	tween1.Completed:Wait()

	local tween2 = TweenService:Create(projectile,
		TweenInfo.new(halfTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ CFrame = CFrame.lookAt(to, to + (to - midPoint).Unit) }
	)
	tween2:Play()
	tween2.Completed:Wait()
end

--- Find the ground Y at an XZ position via raycast.
local function findGroundY(pos: Vector3): number
	local result = Workspace:Raycast(
		Vector3.new(pos.X, pos.Y + 10, pos.Z),
		Vector3.new(0, -100, 0)
	)
	if result then return result.Position.Y end
	return pos.Y
end

local function handleProjectile(data: { [string]: any })
	local origin: Vector3 = data.Origin
	local target: Vector3 = data.Target
	if not origin or not target then return end

	local skinName = data.ProjectileSkin or "Rock"
	local pCfg = getProjectileConfig(skinName)

	-- Clone projectile asset (model or part)
	local rootPart, container = cloneProjectile(skinName)
	if not rootPart then
		-- Fallback
		local fb = createFallbackPart(pCfg.Size)
		rootPart = fb
		container = fb
	end

	rootPart.Anchored = true
	rootPart.CanCollide = false
	rootPart.CanQuery = false
	rootPart.CanTouch = false
	rootPart.CFrame = CFrame.lookAt(origin, target)
	container.Parent = Workspace

	-- Main arc to target (tween rootPart — if it's a Model's PrimaryPart, the whole model moves)
	tweenArc(rootPart, origin, target, pCfg)

	-- Bounce logic (suppressed on wall hits — pizza shouldn't bounce off a wall mid-arc)
	local bounce = pCfg.Bounce
	local bounceCount = (bounce and pCfg.BounceCount) or 0
	local bounceDamping = pCfg.BounceDamping or 0.5

	if data.HitType == "wall" then
		bounce = false
		bounceCount = 0
	end

	if bounce and bounceCount > 0 then
		local currentPos = target
		local direction = (target - origin)
		local horizDir = Vector3.new(direction.X, 0, direction.Z)
		if horizDir.Magnitude > 0.01 then
			horizDir = horizDir.Unit
		else
			horizDir = Vector3.new(1, 0, 0)
		end

		local bounceSpeed = pCfg.Speed or 80
		local bounceArcMult = pCfg.ArcHeight or 0.3

		for i = 1, bounceCount do
			local dampFactor = bounceDamping ^ i
			local bounceDist = math.max(3, (direction.Magnitude * 0.4) * dampFactor)
			local bounceTarget = currentPos + horizDir * bounceDist
			local groundY = findGroundY(bounceTarget)
			bounceTarget = Vector3.new(bounceTarget.X, groundY + (rootPart.Size.Y * 0.5), bounceTarget.Z)

			local bouncePCfg = {
				Speed = bounceSpeed,
				Gravity = true,
				ArcHeight = bounceArcMult * dampFactor,
				ArcHeightCap = (pCfg.ArcHeightCap or 10) * dampFactor,
			}

			tweenArc(rootPart, currentPos, bounceTarget, bouncePCfg)
			currentPos = bounceTarget
		end
	end

	-- Impact effect: quick scale down + transparency on rootPart
	local impactTween = TweenService:Create(rootPart, TweenInfo.new(0.15), {
		Size = rootPart.Size * 0.3,
		Transparency = 1,
	})
	impactTween:Play()
	Debris:AddItem(container, 0.3)
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
	local bombRoot, bombContainer = cloneProjectile(data.ProjectileSkin or "Bomb")
	if not bombRoot then
		local fb = createFallbackPart(Vector3.new(2.5, 2.5, 2.5))
		bombRoot = fb
		bombContainer = fb
	end
	bombRoot.Anchored = true
	bombRoot.CanCollide = false
	bombRoot.CanQuery = false
	bombRoot.CanTouch = false
	bombRoot.CFrame = CFrame.new(origin)
	bombContainer.Parent = Workspace

	local fallTime = math.clamp(math.sqrt(math.abs(origin.Y - target.Y) / 20), 0.3, 2.5)

	local fallTween = TweenService:Create(bombRoot, TweenInfo.new(fallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(target),
	})
	fallTween:Play()
	fallTween.Completed:Wait()

	bombContainer:Destroy()

	-- Explosion AoE
	handleAoE({
		Origin = target,
		AoERadius = data.AoERadius or 12,
	})
end

local function handleDrop(data: { [string]: any })
	local origin: Vector3 = data.Origin
	if not origin then return end

	local dropRoot, dropContainer = cloneProjectile(data.ProjectileSkin or "Rock")
	if not dropRoot then
		local fb = createFallbackPart()
		dropRoot = fb
		dropContainer = fb
	end
	dropRoot.Anchored = true
	dropRoot.CanCollide = false
	dropRoot.CanQuery = false
	dropRoot.CanTouch = false
	dropRoot.CFrame = CFrame.new(origin)
	dropContainer.Parent = Workspace

	-- Pulsing glow before detonation
	local pulse = TweenService:Create(dropRoot, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true), {
		Size = dropRoot.Size * 1.3,
	})
	pulse:Play()

	task.delay(0.8, function()
		if dropContainer.Parent then
			local pos = dropRoot.Position
			dropContainer:Destroy()
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
