local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local IsServer = RunService:IsServer()

local WeaponsSystemFolder = script.Parent.Parent
local Libraries = WeaponsSystemFolder:WaitForChild("Libraries")
local BaseWeapon = require(Libraries:WaitForChild("BaseWeapon"))
local Parabola = require(Libraries:WaitForChild("Parabola"))
local Roblox = require(Libraries:WaitForChild("Roblox"))

local Effects = WeaponsSystemFolder:WaitForChild("Assets"):WaitForChild("Effects")
local ShotsFolder = Effects:WaitForChild("Shots")
local HitMarksFolder = Effects:WaitForChild("HitMarks")
local CasingsFolder = Effects:WaitForChild("Casings")

local NO_BULLET_DECALS = false
local NO_BULLET_CASINGS = false

--The ignore list will fill up over time. This is how many seconds it will go before
--being refreshed in order to keep it from filling up with instances that aren't in
--the datamodel anymore.
local IGNORE_LIST_LIFETIME = 5

local MAX_BULLET_TIME = 10

local localRandom = Random.new()
local localPlayer = not IsServer and Players.LocalPlayer

-- Brainrot-only helpers
local EnemiesFolder = Workspace:FindFirstChild("Enemies")

local function getEnemiesFolder(): Instance?
	EnemiesFolder = EnemiesFolder or Workspace:FindFirstChild("Enemies")
	return EnemiesFolder
end

local function getBrainrotModelFromHit(part: Instance?): Model?
	if not part then return nil end

	local enemies = getEnemiesFolder()
	if not enemies then return nil end

	local cur: Instance? = part
	while cur and cur ~= Workspace do
		if cur:IsA("Model") then
			-- Must be within Workspace.Enemies
			if cur:IsDescendantOf(enemies) then
				-- Must have BrainrotId attribute
				local id = cur:GetAttribute("BrainrotId")
				if type(id) == "string" and id ~= "" then
					return cur
				end
			end
		end
		cur = cur.Parent
	end
	return nil
end

local function getBrainrotHumanoid(brainrotModel: Model?): Humanoid?
	if not brainrotModel then return nil end
	return brainrotModel:FindFirstChildOfClass("Humanoid")
end

local function getDamageRemoteFunction()
	-- Uses your Shared/Net/RemoteService wrapper (same system as BrainrotClient)
	local net = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")
	local RemoteService = require(net:WaitForChild("RemoteService"))
	return RemoteService:GetFunction("DamageBrainrot")
end

local function getSelfDamageRemoteFunction()
	local net = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")
	local RemoteService = require(net:WaitForChild("RemoteService"))
	return RemoteService:GetFunction("SelfDamage")
end

local DamageBrainrotRF = nil
local SelfDamageRF = nil
if not IsServer then
	-- cache on client
	DamageBrainrotRF = getDamageRemoteFunction()
	SelfDamageRF = getSelfDamageRemoteFunction()
end

local BulletWeapon = {}
BulletWeapon.__index = BulletWeapon
setmetatable(BulletWeapon, BaseWeapon)

BulletWeapon.CanAimDownSights = true
BulletWeapon.CanBeFired = true
BulletWeapon.CanBeReloaded = true
BulletWeapon.CanHit = true

function BulletWeapon.new(weaponsSystem, instance)
	local self = BaseWeapon.new(weaponsSystem, instance)
	setmetatable(self, BulletWeapon)

	self.usesCharging = false
	self.charge = 0
	self.chargeSoundPitchMin = 0.5
	self.chargeSoundPitchMax = 1

	self.triggerDisconnected = false
	self.startupFinished = false -- TODO: make startup time use a configuration value
	self.burstFiring = false
	self.burstIdx = 0
	self.nextFireTime = 0

	self.recoilIntensity = 0
	self.aimPoint = Vector3.new()

	self:addOptionalDescendant("tipAttach", "TipAttachment")

	self:addOptionalDescendant("boltMotor", "BoltMotor")
	self:addOptionalDescendant("boltMotorStart", "BoltMotorStart")
	self:addOptionalDescendant("boltMotorTarget", "BoltMotorTarget")

	self:addOptionalDescendant("chargeGlowPart", "ChargeGlow")
	self:addOptionalDescendant("chargeCompleteParticles", "ChargeCompleteParticles")
	self:addOptionalDescendant("dischargeCompleteParticles", "DischargeCompleteParticles")

	self:addOptionalDescendant("muzzleFlash0", "MuzzleFlash0")
	self:addOptionalDescendant("muzzleFlash1", "MuzzleFlash1")
	self:addOptionalDescendant("muzzleFlashBeam", "MuzzleFlash")

	self.hitMarkTemplate = HitMarksFolder:FindFirstChild(self:getConfigValue("HitMarkEffect", "BulletHole"))

	self.casingTemplate = CasingsFolder:FindFirstChild(self:getConfigValue("CasingEffect", ""))
	self:addOptionalDescendant("casingEjectPoint", "CasingEjectPoint")

	self.ignoreList = {}
	self.ignoreListRefreshTime = 0

	self:addOptionalDescendant("handAttach", "LeftHandAttachment")
	self.handAlignPos = nil
	self.handAlignRot = nil

	self.chargingParticles = {}
	self.instance.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "ChargingParticles" and descendant:IsA("ParticleEmitter") then
			table.insert(self.chargingParticles, descendant)
		end
	end)
	for _, v in pairs(self.instance:GetDescendants()) do
		if v.Name == "ChargingParticles" and v:IsA("ParticleEmitter") then
			table.insert(self.chargingParticles, v)
		end
	end

	self:doInitialSetup()

	return self
end

function BulletWeapon:onEquippedChanged()
	BaseWeapon.onEquippedChanged(self)

	if not IsServer then
		if self.weaponsSystem.camera then
			if self.equipped then
				self.startupFinished = false
			end
		end

		if self.equipped then
			ContextActionService:BindAction("ReloadWeapon", function(...) self:onReloadAction(...) end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
		else
			ContextActionService:UnbindAction("ReloadWeapon")

			-- Stop charging/discharging sounds
			local chargingSound = self:getSound("Charging")
			local dischargingSound = self:getSound("Discharging")
			if chargingSound and chargingSound.Playing then
				chargingSound:Stop()
			end
			if dischargingSound and dischargingSound.Playing then
				dischargingSound:Stop()
			end
		end

		self.triggerDisconnected = false
	end
end

function BulletWeapon:onReloadAction(actionName, inputState, inputObj)
	if inputState == Enum.UserInputState.Begin and not self.reloading then
		self:reload()
	end
end

function BulletWeapon:animateBoltAction(isOpen)
	if not self.boltMotor or not self.boltMotorStart or not self.boltMotorTarget then
		return
	end

	if isOpen then
		self:tryPlaySound("BoltOpenSound")
	else
		self:tryPlaySound("BoltCloseSound")
	end

	local actionMoveTime = isOpen and self:getConfigValue("ActionOpenTime", 0.025) or self:getConfigValue("ActionCloseTime", 0.075)
	local targetCFrame = isOpen and self.boltMotorTarget.CFrame or self.boltMotorStart.CFrame

	local boltTween = TweenService:Create(self.boltMotor, TweenInfo.new(actionMoveTime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { C0 = targetCFrame })
	boltTween:Play()
	boltTween.Completed:Wait()
end

function BulletWeapon:getRandomSeedForId(id)
	return id
end

-- This function is only called on clients
function BulletWeapon:simulateFire(firingPlayer, fireInfo)
	BaseWeapon.simulateFire(self, fireInfo)

	-- Play "Fired" sound
	if self.lastFireSound then
		self.lastFireSound:Stop()
	end
	self.lastFireSound = self:tryPlaySound("Fired", self:getConfigValue("FiredPlaybackSpeedRange", 0.1))

	-- Simulate each projectile/bullet fired from current weapon
	local numProjectiles = self:getConfigValue("NumProjectiles", 1)
	local randomGenerator = Random.new(self:getRandomSeedForId(fireInfo.id))
	for i = 1, numProjectiles do
		self:simulateProjectile(firingPlayer, fireInfo, i, randomGenerator)
	end

	-- Animate the bolt if the current gun has one
	local actionOpenTime = self:getConfigValue("ActionOpenTime", 0.025)
	if self.boltMotor then
		coroutine.wrap(function()
			self:animateBoltAction(true)
			wait(actionOpenTime)
			self:animateBoltAction(false)
		end)()
	end

	-- Eject bullet casings and play "CasingHitSound" (child of casing) sound if applicable for current weapon
	if not NO_BULLET_CASINGS and self.casingTemplate and self.casingEjectPoint then
		local casing = self.casingTemplate:Clone()
		casing.Anchored = false
		casing.Archivable = false
		casing.CFrame = self.casingEjectPoint.WorldCFrame
		casing.Velocity = self.casingEjectPoint.Parent.Velocity + (self.casingEjectPoint.WorldAxis * localRandom:NextNumber(self:getConfigValue("CasingEjectSpeedMin", 15), self:getConfigValue("CasingEjectSpeedMax", 18)))
		casing.Parent = workspace.CurrentCamera
		CollectionService:AddTag(casing, "WeaponsSystemIgnore")

		local casingHitSound = casing:FindFirstChild("CasingHitSound")
		if casingHitSound then
			local touchedConn = nil
			touchedConn = casing.Touched:Connect(function(hitPart)
				if not hitPart:IsDescendantOf(self.instance) then
					casingHitSound:Play()
					touchedConn:Disconnect()
					touchedConn = nil
				end
			end)
		end

		Debris:AddItem(casing, 2)
	end

	if self.player == Players.LocalPlayer then
		coroutine.wrap(function()
			-- Wait for "RecoilDelayTime" before adding recoil
			local startTime = tick()
			local recoilDelayTime = self:getConfigValue("RecoilDelayTime", 0.07)
			while tick() < startTime + recoilDelayTime do
				RunService.RenderStepped:Wait()
			end
			RunService.RenderStepped:Wait()

			-- Add recoil to camera
			local recoilMin, recoilMax = self:getConfigValue("RecoilMin", 0.05), self:getConfigValue("RecoilMax", 0.5)
			local intensityToAdd = randomGenerator:NextNumber(recoilMin, recoilMax)
			local xIntensity = math.sin(tick() * 2) * intensityToAdd * math.rad(0.05)
			local yIntensity = intensityToAdd * 0.025
			self.weaponsSystem.camera:addRecoil(Vector2.new(xIntensity, yIntensity))

			if not (self.weaponsSystem.camera:isZoomed() and self:getConfigValue("HasScope", false)) then
				self.recoilIntensity = math.clamp(self.recoilIntensity * 1 + (intensityToAdd / 10), 0.005, 1)
			end

			-- Make crosshair reflect recoil/spread amount
			local weaponsGui = self.weaponsSystem.gui
			if weaponsGui then
				weaponsGui:setCrosshairScale(1 + intensityToAdd)
			end
		end)()
	end
end

function BulletWeapon:getIgnoreList(includeLocalPlayer)
	local now = tick()
	local ignoreList = self.ignoreList
	if not ignoreList or now - self.ignoreListRefreshTime > IGNORE_LIST_LIFETIME then
		ignoreList = {
			self.instanceIsTool and self.instance.Parent or self.instance,
			workspace.CurrentCamera
		}
		if not RunService:IsServer() then
			if includeLocalPlayer and Players.LocalPlayer and Players.LocalPlayer.Character then
				table.insert(ignoreList, Players.LocalPlayer.Character)
			end
		end
		self.ignoreList = ignoreList
	end
	return ignoreList
end

-- This function is only called on clients
function BulletWeapon:simulateProjectile(firingPlayer, fireInfo, projectileIdx, randomGenerator)
	local localPlayerInitiatedShot = self.player == Players.LocalPlayer

	-- Retrieve config values
	local bulletSpeed = self:getConfigValue("BulletSpeed", 1000)
	local maxDistance = self:getConfigValue("MaxDistance", 2000)
	local trailLength = self:getConfigValue("TrailLength", nil)
	local trailLengthFactor = self:getConfigValue("TrailLengthFactor", 1)
	local showEntireTrailUntilHit = self:getConfigValue("ShowEntireTrailUntilHit", false)
	local gravityFactor = self:getConfigValue("GravityFactor", 0)
	local minSpread = self:getConfigValue("MinSpread", 0)
	local maxSpread = self:getConfigValue("MaxSpread", 0)
	local shouldMovePart = self:getConfigValue("ShouldMovePart", false)
	local explodeOnImpact = self:getConfigValue("ExplodeOnImpact", false)
	local blastRadius = self:getConfigValue("BlastRadius", 8)

	-- Cheat the origin of the shot back if gun tip in wall/object
	if self.tipAttach ~= nil then
		local tipCFrame = self.tipAttach.WorldCFrame
		local tipPos = tipCFrame.Position
		local tipDir = tipCFrame.LookVector
		local amountToCheatBack = math.abs((self.instance:FindFirstChild("Handle").Position - tipPos):Dot(tipDir)) + 1
		local gunRay = Ray.new(tipPos - tipDir.Unit * amountToCheatBack, tipDir.Unit * amountToCheatBack)
		local hitPart, hitPoint = Roblox.penetrateCast(gunRay, self:getIgnoreList(localPlayerInitiatedShot))
		if hitPart and math.abs((tipPos - hitPoint).Magnitude) > 0 then
			fireInfo.origin = hitPoint - tipDir.Unit * 0.1
			fireInfo.dir = tipDir.Unit
		end
	end

	local origin, dir = fireInfo.origin, fireInfo.dir

	dir = Roblox.applySpread(dir, randomGenerator, math.rad(minSpread), math.rad(maxSpread))

	-- Initialize variables for visuals/particle effects
	local bulletEffect = self.bulletEffectTemplate:Clone()
	bulletEffect.CFrame = CFrame.new(origin, origin + dir)
	bulletEffect.Parent = workspace.CurrentCamera
	CollectionService:AddTag(bulletEffect, "WeaponsSystemIgnore")

	local leadingParticles = bulletEffect:FindFirstChild("LeadingParticles", true)
	local attachment0 = bulletEffect:FindFirstChild("Attachment0")
	local trailParticles = nil
	if attachment0 then
		trailParticles = attachment0:FindFirstChild("TrailParticles")
	end

	local hitAttach = bulletEffect:FindFirstChild("HitEffect")
	local hitParticles = bulletEffect:FindFirstChild("HitParticles", true)
	local numHitParticles = self:getConfigValue("NumHitParticles", 3)
	local hitSound = bulletEffect:FindFirstChild("HitSound", true)
	local flyingSound = bulletEffect:FindFirstChild("Flying", true)

	local muzzleFlashTime = self:getConfigValue("MuzzleFlashTime", 0.03)
	local muzzleFlashShown = false

	local beamThickness0 = self:getConfigValue("BeamWidth0", 1.5)
	local beamThickness1 = self:getConfigValue("BeamWidth1", 1.8)
	local beamFadeTime = self:getConfigValue("BeamFadeTime", nil)

	-- Enable beam trails for projectile
	local beam0 = bulletEffect:FindFirstChild("Beam0")
	if beam0 then
		beam0.Enabled = true
	end
	local beam1 = bulletEffect:FindFirstChild("Beam1")
	if beam1 then
		beam1.Enabled = true
	end

	-- Emit muzzle particles
	local muzzleParticles = bulletEffect:FindFirstChild("MuzzleParticles", true)
	local numMuzzleParticles = self:getConfigValue("NumMuzzleParticles", 50)
	if muzzleParticles then
		muzzleParticles.Parent.CFrame = CFrame.new(origin, origin + dir)
		local numSteps = 5
		for _ = 1, numSteps do
			muzzleParticles.Parent.Velocity = Vector3.new(localRandom:NextNumber(-10, 10), localRandom:NextNumber(-10, 10), localRandom:NextNumber(-10, 10))
			muzzleParticles:Emit(numMuzzleParticles / numSteps)
		end
	end

	-- Show muzzle flash
	if self.tipAttach and self.muzzleFlash0 and self.muzzleFlash1 and self.muzzleFlashBeam and projectileIdx == 1 then
		local minFlashRotation, maxFlashRotation = self:getConfigValue("MuzzleFlashRotation0", -math.pi), self:getConfigValue("MuzzleFlashRotation1", math.pi)
		local minFlashSize, maxFlashSize = self:getConfigValue("MuzzleFlashSize0", 1), self:getConfigValue("MuzzleFlashSize1", 1)
		local flashRotation = localRandom:NextNumber(minFlashRotation, maxFlashRotation)
		local flashSize = localRandom:NextNumber(minFlashSize, maxFlashSize)
		local baseCFrame = self.tipAttach.CFrame * CFrame.Angles(0, 0, flashRotation)
		self.muzzleFlash0.CFrame = baseCFrame * CFrame.new(flashSize * -0.5, 0, 0) * CFrame.Angles(0, math.pi, 0)
		self.muzzleFlash1.CFrame = baseCFrame * CFrame.new(flashSize * 0.5, 0, 0) * CFrame.Angles(0, math.pi, 0)

		self.muzzleFlashBeam.Enabled = true
		self.muzzleFlashBeam.Width0 = flashSize
		self.muzzleFlashBeam.Width1 = flashSize
		muzzleFlashShown = true
	end

	-- Play projectile flying sound
	if flyingSound then
		flyingSound:Play()
	end

	-- Enable trail particles
	if trailParticles then
		trailParticles.Enabled = true
	end

	-- Set up parabola for projectile path
	local parabola = Parabola.new()
	parabola:setPhysicsLaunch(origin, dir * bulletSpeed, nil, 35 * -gravityFactor)
	-- More samples for higher gravity since path will be more curved but raycasts can only be straight lines
	if gravityFactor > 0.66 then
		parabola:setNumSamples(3)
	elseif gravityFactor > 0.33 then
		parabola:setNumSamples(2)
	else
		parabola:setNumSamples(1)
	end

	-- Set up/initialize variables used in steppedCallback
	local stepConn = nil
	local pTravelDistance = 0
	local startTime = tick()
	local didHit = false
	local stoppedMotion = false
	local stoppedMotionAt = 0
	local timeSinceStart = 0
	local flyingVisualEffectsFinished = false
	local visualEffectsFinishTime = math.huge
	local visualEffectsLingerTime = 0
	if beamFadeTime then
		visualEffectsLingerTime = beamFadeTime
	end
	local hitInfo = {
		sid = fireInfo.id,
		pid = projectileIdx,
		maxDist = maxDistance,
		part = nil,
		p = nil,
		n = nil,
		m = Enum.Material.Air,
		d = 1e9,
	}

	local steppedCallback = function(dt)
		local nowTick = tick()
		timeSinceStart = nowTick - startTime

		local travelDist = bulletSpeed * dt
		trailLength = trailLength or travelDist * trailLengthFactor

		local projBack = pTravelDistance - trailLength
		local projFront = pTravelDistance
		local maxDist = hitInfo.maxDist or 0

		if showEntireTrailUntilHit then
			projBack = 0
		end

		projBack = math.clamp(projBack, 0, maxDist)
		projFront = math.clamp(projFront, 0, maxDist)

		if not didHit then
			local castProjBack, castProjFront = projFront, projFront + travelDist
			parabola:setDomain(castProjBack, castProjFront)
			local hitPart, hitPoint, hitNormal, hitMaterial, hitT = parabola:findPart(self.ignoreList)

			if hitPart then
				didHit = true
				projFront = castProjBack + hitT * (castProjFront - castProjBack)
				parabola:setDomain(projBack, projFront)

				hitInfo.part = hitPart
				hitInfo.p = hitPoint
				hitInfo.n = hitNormal
				hitInfo.m = hitMaterial
				hitInfo.d = (hitPoint - origin).Magnitude
				hitInfo.t = hitT
				hitInfo.maxDist = projFront

				self:onHit(hitInfo)

				-- Keep the original WeaponHit server notify for effects/anti-cheat systems if you use it
				if localPlayerInitiatedShot then
					local hitInfoClone = {}
					for hitInfoKey, value in pairs(hitInfo) do
						hitInfoClone[hitInfoKey] = value
					end
					self.weaponsSystem.getRemoteEvent("WeaponHit"):FireServer(self.instance, hitInfoClone)
				end

				if trailParticles then
					trailParticles.Enabled = false
				end

				if flyingSound and flyingSound.IsPlaying then
					flyingSound:Stop()
				end

				if bulletEffect then
					bulletEffect.Transparency = 1
				end

				if leadingParticles then
					leadingParticles.Rate = 0
					visualEffectsLingerTime = math.max(visualEffectsLingerTime, leadingParticles.Lifetime.Max)
				end

				-- Visual explosion ONLY (no server/player damage)
				if explodeOnImpact then
					local explosion = Instance.new("Explosion")
					explosion.Position = hitPoint + (hitNormal * 0.5)
					explosion.BlastRadius = blastRadius
					explosion.BlastPressure = 0
					explosion.ExplosionType = Enum.ExplosionType.NoCraters
					explosion.DestroyJointRadiusPercent = 0
					explosion.Visible = true
					explosion.Parent = workspace
				end

				if hitAttach and beam0 and beam0.Attachment1 then
					parabola:renderToBeam(beam0)
					hitAttach.CFrame = beam0.Attachment1.CFrame * CFrame.Angles(0, math.rad(90), 0)
				end

				local hitPartColor = hitPart and hitPart.Color or Color3.fromRGB(255, 255, 255)
				if hitPart and hitPart:IsA("Terrain") then
					hitPartColor = workspace.Terrain:GetMaterialColor(hitMaterial or Enum.Material.Sand)
				end

				-- Emit hit particles
				if hitParticles and numHitParticles > 0 then
					hitParticles:Emit(numHitParticles)
					visualEffectsLingerTime = math.max(visualEffectsLingerTime, hitParticles.Lifetime.Max)
				end

				if hitSound then
					hitSound:Play()
					visualEffectsLingerTime = math.max(visualEffectsLingerTime, hitSound.TimeLength)
				end

				-- Hit marks on non-humanoid surfaces only
				local hitPointObjectSpace = hitPart.CFrame:pointToObjectSpace(hitPoint)
				local hitNormalObjectSpace = hitPart.CFrame:vectorToObjectSpace(hitNormal)

				local brainrotModel = getBrainrotModelFromHit(hitPart)
				local hitIsBrainrot = (brainrotModel ~= nil)

				if not hitIsBrainrot and
					not NO_BULLET_DECALS and
					hitPart and
					hitPointObjectSpace and
					hitNormalObjectSpace and
					self.hitMarkTemplate
				then
					local hitMark = self.hitMarkTemplate:Clone()
					hitMark.Parent = hitPart
					CollectionService:AddTag(hitMark, "WeaponsSystemIgnore")

					local incomingVec = parabola:sampleVelocity(1).Unit
					if self:getConfigValue("AlignHitMarkToNormal", true) then
						local forward = hitNormalObjectSpace
						local up = incomingVec
						local right = -forward:Cross(up).Unit
						up = forward:Cross(right)
						local orientationCFrame = CFrame.fromMatrix(hitPointObjectSpace + hitNormalObjectSpace * 0.05, right, up, -forward)
						hitMark.CFrame = hitPart.CFrame:toWorldSpace(orientationCFrame)
					else
						hitMark.CFrame = hitPart.CFrame * CFrame.new(hitPointObjectSpace, hitPointObjectSpace + hitPart.CFrame:vectorToObjectSpace(incomingVec))
					end

					local weld = Instance.new("WeldConstraint")
					weld.Part0 = hitMark
					weld.Part1 = hitPart
					weld.Parent = hitMark

					Debris:AddItem(hitMark, 5)
				end

				flyingVisualEffectsFinished = true
				visualEffectsFinishTime = nowTick + visualEffectsLingerTime
			end
		end

		if projFront >= maxDist then
			if not stoppedMotion then
				stoppedMotion = true
				stoppedMotionAt = nowTick
			end

			if projBack >= maxDist and not flyingVisualEffectsFinished then
				flyingVisualEffectsFinished = true
				visualEffectsFinishTime = nowTick + visualEffectsLingerTime
			end
		end

		parabola:setDomain(projBack, projFront)

		if projBack < maxDist then
			pTravelDistance = math.max(0, timeSinceStart * bulletSpeed)
		end

		if shouldMovePart then
			local bulletPos = parabola:samplePoint(1)
			local bulletVelocity = parabola:sampleVelocity(1)
			bulletEffect.CFrame = CFrame.new(bulletPos, bulletPos + bulletVelocity)
			bulletEffect.Velocity = bulletVelocity.Unit * bulletSpeed
		end

		local thickness0 = self:getConfigValue("BeamWidth0", 1.5)
		local thickness1 = self:getConfigValue("BeamWidth1", 1.8)

		if beamFadeTime then
			local timeSinceEnd = stoppedMotion and (nowTick - stoppedMotionAt) or 0
			local fadeAlpha = math.clamp(timeSinceEnd / beamFadeTime, 0, 1)
			thickness0 = thickness0 * (1 - fadeAlpha)
			thickness1 = thickness1 * (1 - fadeAlpha)
		end

		if beam0 then
			beam0.Width0 = thickness0
			beam0.Width1 = thickness1
			parabola:renderToBeam(beam0)
		end
		if beam1 then
			beam1.Width0 = thickness0
			beam1.Width1 = thickness1
			parabola:renderToBeam(beam1)
		end

		if muzzleFlashShown and timeSinceStart > muzzleFlashTime and self.muzzleFlashBeam then
			self.muzzleFlashBeam.Enabled = false
			muzzleFlashShown = false
		end

		local timeSinceParticleEffectsFinished = nowTick - visualEffectsFinishTime
		if (flyingVisualEffectsFinished and timeSinceParticleEffectsFinished > 0) or timeSinceStart > MAX_BULLET_TIME then
			if bulletEffect then
				bulletEffect:Destroy()
				bulletEffect = nil
			end

			stepConn:Disconnect()
		end
	end

	stepConn = RunService.Heartbeat:Connect(steppedCallback)

	if not IsServer and self.usesCharging then
		self.charge = math.clamp(self.charge - self:getConfigValue("FireDischarge", 1), 0, 1)
	end
end

function BulletWeapon:calculateDamage(travelDistance)
	local zeroDamageDistance = self:getConfigValue("ZeroDamageDistance", 10000)
	local fullDamageDistance = self:getConfigValue("FullDamageDistance", 1000)
	local distRange = zeroDamageDistance - fullDamageDistance
	local falloff = math.clamp(1 - (math.max(0, travelDistance - fullDamageDistance) / math.max(1, distRange)), 0, 1)
	return math.max(self:getConfigValue("HitDamage", 10) * falloff, 0)
end

-- UPDATED: CombatService-only (client invokes DamageBrainrot)
function BulletWeapon:applyDamage(hitInfo)
	if IsServer then
		return
	end

	if self.player ~= Players.LocalPlayer then
		return
	end

	local damage = self:calculateDamage(hitInfo.d)
	if damage <= 0 then
		return
	end

	local hitPart = hitInfo.part
	if not hitPart then
		return
	end

	local brainrotModel = getBrainrotModelFromHit(hitPart)
	if not brainrotModel then
		-- Not a brainrot; do not damage anything else
		return
	end

	local brainrotId = brainrotModel:GetAttribute("BrainrotId")
	if type(brainrotId) ~= "string" or brainrotId == "" then
		return
	end

	-- Invoke CombatService via NetService RemoteFunction
	if not DamageBrainrotRF then
		DamageBrainrotRF = getDamageRemoteFunction()
	end

	local ok, res = pcall(function()
		return DamageBrainrotRF:InvokeServer(brainrotId, damage)
	end)

	-- Optional: hitmarker only when server accepted damage
	if ok and type(res) == "table" and res.ok == true then
		if self.weaponsSystem.gui then
			local hum = getBrainrotHumanoid(brainrotModel)
			if hum then
				self.weaponsSystem.gui:OnHitOtherPlayer(damage, hum)
			end
		end
	end
end

function BulletWeapon:_applyExplosionDamage(hitInfo)
	-- AOE explosion: damages all brainrots in blast radius + the shooter (self-damage).
	-- Does NOT damage other players.
	if IsServer then return end
	if self.player ~= Players.LocalPlayer then return end

	local blastRadius = self:getConfigValue("BlastRadius", 8)
	local hitPoint = hitInfo.p
	if not hitPoint then return end

	local damage = self:calculateDamage(hitInfo.d)
	if damage <= 0 then return end

	if not DamageBrainrotRF then
		DamageBrainrotRF = getDamageRemoteFunction()
	end

	-- 1) Damage all brainrots within blast radius
	local enemies = getEnemiesFolder()
	if enemies then
		local alreadyHit = {}
		for _, desc in enemies:GetDescendants() do
			if desc:IsA("BasePart") then
				local dist = (desc.Position - hitPoint).Magnitude
				if dist <= blastRadius then
					local brainrotModel = getBrainrotModelFromHit(desc)
					if brainrotModel and not alreadyHit[brainrotModel] then
						alreadyHit[brainrotModel] = true
						local brainrotId = brainrotModel:GetAttribute("BrainrotId")
						if type(brainrotId) == "string" and brainrotId ~= "" then
							local falloff = 1 - (dist / blastRadius) * 0.5
							local aoeDmg = math.floor(damage * falloff)
							if aoeDmg > 0 then
								local ok, res = pcall(function()
									return DamageBrainrotRF:InvokeServer(brainrotId, aoeDmg)
								end)
								if ok and type(res) == "table" and res.ok == true then
									if self.weaponsSystem.gui then
										local hum = getBrainrotHumanoid(brainrotModel)
										if hum then
											self.weaponsSystem.gui:OnHitOtherPlayer(aoeDmg, hum)
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- 2) Self-damage: route through server (armor absorbs first, overflow hits health)
	local char = Players.LocalPlayer.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = (hrp.Position - hitPoint).Magnitude
			if dist <= blastRadius then
				local falloff = 1 - (dist / blastRadius) * 0.5
				local selfDmg = math.floor(damage * falloff)
				if selfDmg > 0 then
					if not SelfDamageRF then
						SelfDamageRF = getSelfDamageRemoteFunction()
					end
					pcall(function()
						SelfDamageRF:InvokeServer(selfDmg)
					end)
				end
			end
		end
	end
end

function BulletWeapon:onHit(hitInfo)
	local hitPart = hitInfo.part
	if not (hitPart and hitPart.Parent) then
		return
	end

	-- Determine if this is a brainrot hit
	local brainrotModel = getBrainrotModelFromHit(hitPart)
	local isBrainrot = (brainrotModel ~= nil)

	-- Preserve hitInfo.h for effect logic (but DO NOT damage non-brainrots)
	if isBrainrot then
		hitInfo.h = getBrainrotHumanoid(brainrotModel) or hitPart
	else
		-- Not a brainrot → treat as non-humanoid surface
		hitInfo.h = hitPart
	end

	-- Check if this weapon explodes on impact (Bazooka, Grenade Launcher, etc.)
	local explodeOnImpact = self:getConfigValue("ExplodeOnImpact", false)

	if explodeOnImpact then
		-- AOE explosion damage: hits brainrots + self only (no other players)
		self:_applyExplosionDamage(hitInfo)
	elseif isBrainrot then
		-- Standard single-target: only apply damage if it is a brainrot
		self:applyDamage(hitInfo)
	end
end

function BulletWeapon:fire(origin, dir, charge)
	if not self:isCharged() then
		return
	end

	BaseWeapon.fire(self, origin, dir, charge)
end

function BulletWeapon:onFired(firingPlayer, fireInfo, fromNetwork)
	if not IsServer and firingPlayer == Players.LocalPlayer and fromNetwork then
		return
	end

	local cooldownTime = self:getConfigValue("ShotCooldown", 0.1)
	local fireMode = self:getConfigValue("FireMode", "Semiautomatic")
	local isSemiAuto = fireMode == "Semiautomatic"
	local isBurst = fireMode == "Burst"

	if isBurst and not self.burstFiring then
		self.burstIdx = 0
		self.burstFiring = true
	elseif isSemiAuto then
		self.triggerDisconnected = true
	end

	if self.burstFiring then
		self.burstIdx = self.burstIdx + 1
		if self.burstIdx >= self:getConfigValue("NumBurstShots", 3) then
			self.burstFiring = false
			self.triggerDisconnected = true
		else
			cooldownTime = self:getConfigValue("BurstShotCooldown", nil) or cooldownTime
		end
	end

	self.nextFireTime = tick() + cooldownTime

	BaseWeapon.onFired(self, firingPlayer, fireInfo, fromNetwork)
end

function BulletWeapon:onConfigValueChanged(valueName, newValue, oldValue)
	BaseWeapon.onConfigValueChanged(self, valueName, newValue, oldValue)
	if valueName == "ShotEffect" then
		self.bulletEffectTemplate = ShotsFolder:FindFirstChild(self:getConfigValue("ShotEffect", "Bullet"))
		if self.bulletEffectTemplate then
			local config = self.bulletEffectTemplate:FindFirstChildOfClass("Configuration")
			if config then
				self:importConfiguration(config)
			end

			local beam0 = self.bulletEffectTemplate:FindFirstChild("Beam0")
			if beam0 then
				coroutine.wrap(function()
					ContentProvider:PreloadAsync({ beam0 })
				end)()
			end
		end
	elseif valueName == "HitMarkEffect" then
		self.hitMarkTemplate = HitMarksFolder:FindFirstChild(self:getConfigValue("HitMarkEffect", "BulletHole"))
		if self.hitMarkTemplate then
			local config = self.hitMarkTemplate:FindFirstChildOfClass("Configuration")
			if config then
				self:importConfiguration(config)
			end
		end
	elseif valueName == "CasingEffect" then
		self.casingTemplate = CasingsFolder:FindFirstChild(self:getConfigValue("CasingEffect", ""))
		if self.casingTemplate then
			local config = self.casingTemplate:FindFirstChildOfClass("Configuration")
			if config then
				self:importConfiguration(config)
			end
		end
	elseif valueName == "ChargeRate" then
		self.usesCharging = newValue ~= nil
	end
end

function BulletWeapon:onActivatedChanged()
	BaseWeapon.onActivatedChanged(self)

	if not IsServer then
		if self.equipped and self:getAmmoInWeapon() <= 0 then
			self:reload()
			return
		end

		if self.activated and self.player == localPlayer and self:canFire() and tick() > self.nextFireTime then
			self:doLocalFire()
		end

		if not self.activated and self.triggerDisconnected and not self.burstFiring then
			self.triggerDisconnected = false
		end
	end
end

function BulletWeapon:onRenderStepped(dt)
	BaseWeapon.onRenderStepped(self, dt)
	if not self.tipAttach then return end
	if not self.equipped then return end

	local tipCFrame = self.tipAttach.WorldCFrame

	if self.player == Players.LocalPlayer then
		local aimTrack = self:getAnimTrack(self:getConfigValue("AimTrack", "RifleAim"))
		local aimZoomTrack = self:getAnimTrack(self:getConfigValue("AimZoomTrack", "RifleAimDownSights"))
		if aimTrack then
			local aimDir = tipCFrame.LookVector
			local gunLookRay = Ray.new(tipCFrame.p, aimDir * 500)
			local _, gunHitPoint = Roblox.penetrateCast(gunLookRay, self.ignoreList)

			if self.weaponsSystem.aimRayCallback then
				local _, hitPoint = Roblox.penetrateCast(self.weaponsSystem.aimRayCallback(), self.ignoreList)
				self.aimPoint = hitPoint
			else
				self.aimPoint = gunHitPoint
			end

			if not aimTrack.IsPlaying and not self.reloading then
				aimTrack:Play(0.15)
				coroutine.wrap(function()
					wait(self:getConfigValue("StartupTime", 0.2))
					self.startupFinished = true
				end)()
			end

			if aimZoomTrack and not self.reloading then
				if not aimZoomTrack.IsPlaying then
					aimZoomTrack:Play(0.15)
				end
				aimZoomTrack:AdjustSpeed(0.001)
				if self.weaponsSystem.camera:isZoomed() then
					if aimTrack.WeightTarget ~= 0 then
						aimZoomTrack:AdjustWeight(1)
						aimTrack:AdjustWeight(0)
					end
				elseif aimTrack.WeightTarget ~= 1 then
					aimZoomTrack:AdjustWeight(0)
					aimTrack:AdjustWeight(1)
				end
			end

			local MIN_ANGLE = -80
			local MAX_ANGLE = 80
			local aimYAngle = math.deg(self.recoilIntensity)
			if self.weaponsSystem.camera.enabled then
				aimYAngle = math.deg(self.weaponsSystem.camera:getRelativePitch() + self.weaponsSystem.camera.currentRecoil.Y + self.recoilIntensity)
			end
			local aimTimePos = 2 * ((aimYAngle - MIN_ANGLE) / (MAX_ANGLE - MIN_ANGLE))

			aimTrack:AdjustSpeed(0.001)
			aimTrack.TimePosition = math.clamp(aimTimePos, 0.001, 1.97)

			if aimZoomTrack then
				aimZoomTrack.TimePosition = math.clamp(aimTimePos, 0.001, 1.97)
			end

			local recoilDecay = self:getConfigValue("RecoilDecay", 0.825)
			self.recoilIntensity = math.clamp(self.recoilIntensity * recoilDecay, 0, math.huge)
		else
			warn("no aimTrack")
		end
	end
end

function BulletWeapon:setChargingParticles(charge)
	local ratePerCharge = self:getConfigValue("ChargingParticlesRatePerCharge", 20)
	local rate = ratePerCharge * charge
	for _, v in pairs(self.chargingParticles) do
		v.Rate = rate
	end
end

function BulletWeapon:onStepped(dt)
	if not self.tipAttach then return end
	if not self.equipped then return end

	BaseWeapon.onStepped(self, dt)

	local now = tick()

	local chargingSound = self:getSound("Charging")
	local dischargingSound = self:getSound("Discharging")

	if self.usesCharging then
		local chargeBefore = self.charge
		self:handleCharging(dt)
		local chargeDelta = self.charge - chargeBefore

		if chargeDelta > 0 then
			self:setChargingParticles(self.charge)
		else
			self:setChargingParticles(0)
		end

		if chargingSound then
			if chargingSound.Looped then
				if chargeDelta < 0 then
					chargingSound:Stop()
				else
					if not chargingSound.Playing and self.charge < 1 and chargeDelta > 0 then
						chargingSound:Play()
					end
					chargingSound.PlaybackSpeed = self.chargeSoundPitchMin + (self.charge * (self.chargeSoundPitchMax - self.chargeSoundPitchMin))
				end
			else
				if chargeDelta > 0 and self.charge <= 1 and not chargingSound.Playing then
					chargingSound.TimePosition = chargingSound.TimeLength * self.charge
					chargingSound:Play()
				elseif chargeDelta <= 0 and chargingSound.Playing then
					chargingSound:Stop()
				end
			end
		end
		if dischargingSound then
			if dischargingSound.Looped then
				if chargeDelta > 0 then
					dischargingSound:Stop()
				else
					if not dischargingSound.Playing and self.charge > 0 then
						dischargingSound:Play()
					end
					dischargingSound.PlaybackSpeed = self.chargeSoundPitchMin + (self.charge * (self.chargeSoundPitchMax - self.chargeSoundPitchMin))
				end
			else
				if chargeDelta < 0 and self.charge >= 0 and not dischargingSound.Playing then
					dischargingSound.TimePosition = dischargingSound.TimeLength * self.charge
					dischargingSound:Play()
				elseif chargeDelta >= 0 and dischargingSound.Playing then
					dischargingSound:Stop()
				end
			end
		end

		if chargeBefore < 1 and self.charge >= 1 then
			local chargeCompleteSound = self:getSound("ChargeComplete")
			if chargeCompleteSound then
				chargeCompleteSound:Play()
			end
			if chargingSound and chargingSound.Playing then
				chargingSound:Stop()
			end
			if self.chargeCompleteParticles then
				self.chargeCompleteParticles:Emit(self:getConfigValue("NumChargeCompleteParticles", 25))
			end
		end
		if chargeBefore > 0 and self.charge <= 0 then
			local dischargeCompleteSound = self:getSound("DischargeComplete")
			if dischargeCompleteSound then
				dischargeCompleteSound:Play()
			end
			if dischargingSound and dischargingSound.Playing then
				dischargingSound:Stop()
			end
			if self.dischargeCompleteParticles then
				self.dischargeCompleteParticles:Emit(self:getConfigValue("NumDischargeCompleteParticles", 25))
			end
		end

		self:renderCharge()
	else
		if chargingSound then
			chargingSound:Stop()
		end
		if dischargingSound then
			dischargingSound:Stop()
		end
	end

	if self.usesCharging and self.chargeGlowPart then
		self.chargeGlowPart.Transparency = 1 - self.charge
	end

	if self:canFire() and now > self.nextFireTime then
		self:doLocalFire()
	end
end

function BulletWeapon:handleCharging(dt)
	local chargeDelta
	local shouldCharge = self.activated or self.burstFiring or self:getConfigValue("ChargePassively", false)
	if self.reloading or self.triggerDisconnected then
		shouldCharge = false
	end

	if shouldCharge then
		chargeDelta = self:getConfigValue("ChargeRate", 0) * dt
	else
		chargeDelta = self:getConfigValue("DischargeRate", 0) * -dt
	end

	self.charge = math.clamp(self.charge + chargeDelta, 0, 1)
end

function BulletWeapon:isCharged()
	return not self.usesCharging or self.charge >= 1
end

function BulletWeapon:canFire()
	return self.player == Players.LocalPlayer and (self.burstFiring or self.activated) and not self.triggerDisconnected and not self.reloading and self:isCharged() and self.startupFinished
end

function BulletWeapon:doLocalFire()
	if self.tipAttach then
		local tipCFrame = self.tipAttach.WorldCFrame
		local tipPos = tipCFrame.Position
		local aimDir = (self.aimPoint - tipPos).Unit

		self:fire(tipPos, aimDir, self.charge)
	end
end

return BulletWeapon
