--!strict
-- AIService
-- Server-side behavior controller for brainrots spawned by BrainrotService.
-- Uses PersonalityConfig for behavior, AttackRegistry for combat moves,
-- MovementRegistry for pathfinding locomotion, and ExclusionZoneManager
-- for zone-aware decision-making.
--
-- Evaluator loop: each tick, every brainrot re-evaluates its situation
-- (threat level, exclusion zones, target validity, attack selection).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ExclusionZoneManager = require(
	ServerStorage:WaitForChild("Services"):WaitForChild("Movement"):WaitForChild("ExclusionZoneManager")
)
local MovementRegistry = require(
	ServerStorage:WaitForChild("Services"):WaitForChild("Movement"):WaitForChild("MovementRegistry")
)
local AttackRegistry = require(
	ServerStorage:WaitForChild("Services"):WaitForChild("Attacks"):WaitForChild("AttackRegistry")
)

type Services = { [string]: any }

type AIStateName = "Idle" | "Wander" | "Chase" | "Attack" | "Flee" | "Return" | "Dead" | "WaitAtEdge"

type AIEntry = {
	Id: string,
	Model: Model,
	Humanoid: Humanoid,
	HRP: BasePart,

	ZoneName: string,
	Territory: BasePart?,
	SpawnPos: Vector3,

	EnemyInfo: Configuration?,
	CurrentAnimation: StringValue?,

	PersonalityName: string,
	P: { [string]: any },

	State: AIStateName,
	Target: Player?,

	NextThinkAt: number,
	NextAttackAt: number,

	LastHealth: number,
	LastDamagedAt: number,

	LeashRadius: number,
	FleeUntil: number,
	FleeFrom: Player?,

	WanderTarget: Vector3?,

	-- New fields
	LocomotionType: string,
	Locomotion: any?,
	AttackMoves: { string },
	ThreatLevel: number,
	WaitEdgeZone: any?,
	WaitEdgeUntil: number,

	-- Size tier: "baby" | "normal" | "big" | "huge" (affects behavior)
	SizeTier: string,
	SizeMultiplier: number,
	BrainrotName: string,

	-- Flee evasion state
	FleeZigDir: number, -- +1 or -1, alternates for zigzag
	FleeNextZig: number, -- tick when next zigzag flip happens

	Conn: { RBXScriptConnection },
}

local AIService = {}

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[AIService]", ...) end
end

--//////////////////////////////
-- Config loaders
--//////////////////////////////

local _personalityConfig: any? = nil
local function getPersonalityConfig()
	if _personalityConfig then return _personalityConfig end
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local cfg = shared:WaitForChild("Config")
	_personalityConfig = require(cfg:WaitForChild("PersonalityConfig"))
	return _personalityConfig
end

local _brainrotConfig: any? = nil
local function getBrainrotConfig()
	if _brainrotConfig then return _brainrotConfig end
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local cfg = shared:WaitForChild("Config")
	local ok, mod = pcall(function()
		return require(cfg:WaitForChild("BrainrotConfig"))
	end)
	if ok and type(mod) == "table" then
		_brainrotConfig = mod
	else
		_brainrotConfig = {}
	end
	return _brainrotConfig
end

local function getTerritoriesFolder(): Folder
	return Workspace:WaitForChild("Territories") :: Folder
end

local function getZoneTerritory(zoneName: string): BasePart?
	local territories = getTerritoriesFolder()
	local zone = territories:FindFirstChild(zoneName)
	if not zone then return nil end
	local terr = zone:FindFirstChild("Territory")
	return (terr and terr:IsA("BasePart")) and terr or nil
end

--//////////////////////////////
-- Utility
--//////////////////////////////

local function now(): number
	return os.clock()
end

local function randRange(a: number, b: number): number
	return a + (math.random() * (b - a))
end

local function getCharHRP(plr: Player): BasePart?
	local char = plr.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return (hrp and hrp:IsA("BasePart")) and hrp or nil
end

local function getCharHumanoid(plr: Player): Humanoid?
	local char = plr.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function distSq(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return dx * dx + dy * dy + dz * dz
end

local function pickNearestPlayer(pos: Vector3, maxDist: number): (Player?, number)
	local best: Player? = nil
	local bestD2 = maxDist * maxDist
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = getCharHRP(plr)
		if hrp then
			local d2 = distSq(pos, hrp.Position)
			if d2 <= bestD2 then
				bestD2 = d2
				best = plr
			end
		end
	end
	if best then
		return best, math.sqrt(bestD2)
	end
	return nil, maxDist
end

local function territoryY(terr: BasePart?, fallbackY: number): number
	return terr and terr.Position.Y or fallbackY
end

local function randomPointInTerritory(terr: BasePart, y: number): Vector3
	local cf = terr.CFrame
	local size = terr.Size
	local rx = (math.random() - 0.5) * size.X
	local rz = (math.random() - 0.5) * size.Z
	local p = (cf * CFrame.new(rx, 0, rz)).Position
	return Vector3.new(p.X, y, p.Z)
end

local function isInsideTerritoryXZ(terr: BasePart, pos: Vector3): boolean
	local localPos = terr.CFrame:PointToObjectSpace(pos)
	return math.abs(localPos.X) <= terr.Size.X * 0.5 and math.abs(localPos.Z) <= terr.Size.Z * 0.5
end

--- Get the effective "reach" of a territory — the larger of X or Z extent.
--- Returns a fallback (60) if no territory is assigned.
local function getTerritorySpan(entry: any): number
	local terr = entry.Territory
	if not terr then return 60 end
	return math.max(terr.Size.X, terr.Size.Z)
end

local function getAttrNumber(info: Configuration?, name: string, default: number): number
	if not info then return default end
	local v = info:GetAttribute(name)
	return (typeof(v) == "number") and v or default
end

local function getAttrString(info: Configuration?, name: string, default: string): string
	if not info then return default end
	local v = info:GetAttribute(name)
	return (type(v) == "string" and v ~= "") and v or default
end

local function safeSetAnim(entry: AIEntry, anim: string)
	local sv = entry.CurrentAnimation
	if not sv then return end
	if entry.State == "Dead" and anim ~= "Dead" then return end
	sv.Value = anim
end

-- Personality access helpers
local function pNumber(P: { [string]: any }, key: string, default: number): number
	local v = P[key]
	return (type(v) == "number") and v or default
end

local function pRange(P: { [string]: any }, key: string, a: number, b: number): (number, number)
	local v = P[key]
	if type(v) == "table" then
		local lo = tonumber(v[1]) or a
		local hi = tonumber(v[2]) or b
		if hi < lo then hi = lo end
		return lo, hi
	end
	return a, b
end

local function pTable(P: { [string]: any }, key: string): { [string]: any }?
	local v = P[key]
	return type(v) == "table" and v or nil
end

--//////////////////////////////
-- Resolve brainrot attack moves + locomotion type
--//////////////////////////////

local function resolveAttackMoves(brainrotName: string, personality: { [string]: any }): { string }
	local bCfg = getBrainrotConfig()
	local entry = bCfg[brainrotName]

	-- Priority 1: per-brainrot override
	if entry and type(entry.AttackMoves) == "table" and #entry.AttackMoves > 0 then
		return entry.AttackMoves
	end

	-- Priority 2: personality default
	local pMoves = personality.DefaultAttackMoves
	if type(pMoves) == "table" and #pMoves > 0 then
		return pMoves
	end

	-- Priority 3: hardcoded fallback
	return { "BasicMelee" }
end

--- Merge per-brainrot MoveOverrides + VariantMoveOverrides on top of a move config (shallow copy).
--- Layer order: baseCfg → BrainrotConfig.MoveOverrides → Variant.VariantMoveOverrides
local function applyMoveOverrides(brainrotName: string, moveName: string, baseCfg: { [string]: any }, variantName: string?): { [string]: any }
	local bCfg = getBrainrotConfig()
	local bEntry = bCfg[brainrotName]
	if not bEntry then return baseCfg end

	-- Start with base
	local merged = {}
	for k, v in pairs(baseCfg) do merged[k] = v end

	-- Layer 1: base MoveOverrides from BrainrotConfig
	if type(bEntry.MoveOverrides) == "table" then
		local overrides = bEntry.MoveOverrides[moveName]
		if type(overrides) == "table" then
			for k, v in pairs(overrides) do merged[k] = v end
		end
	end

	-- Layer 2: VariantMoveOverrides from the specific variant
	if variantName and type(bEntry.Variants) == "table" then
		for _, variant in ipairs(bEntry.Variants) do
			if variant.Name == variantName then
				if type(variant.VariantMoveOverrides) == "table" then
					local vOverrides = variant.VariantMoveOverrides[moveName]
					if type(vOverrides) == "table" then
						for k, v in pairs(vOverrides) do merged[k] = v end
					end
				end
				break
			end
		end
	end

	return merged
end

local function resolveLocomotionType(brainrotName: string): string
	local bCfg = getBrainrotConfig()
	local entry = bCfg[brainrotName]
	if entry and type(entry.LocomotionType) == "string" and entry.LocomotionType ~= "" then
		return entry.LocomotionType
	end
	return "Walk"
end

--//////////////////////////////
-- Threat assessment
--//////////////////////////////

local function computeThreatLevel(entry: AIEntry): number
	local hum = entry.Humanoid
	if not hum or hum.MaxHealth <= 0 then return 0 end

	local hpFrac = 1 - (hum.Health / hum.MaxHealth) -- 0=full, 1=dead
	local recentDamage = (now() - entry.LastDamagedAt < 3) and 0.3 or 0

	-- Count nearby players
	local nearbyPlayers = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		local hrp = getCharHRP(plr)
		if hrp then
			local d = (hrp.Position - entry.HRP.Position).Magnitude
			if d < 50 then nearbyPlayers += 1 end
		end
	end
	local crowdThreat = math.min(nearbyPlayers * 0.15, 0.5)

	return math.clamp(hpFrac + recentDamage + crowdThreat, 0, 1)
end

--//////////////////////////////
-- Service
--//////////////////////////////

function AIService:Init(services: Services)
	self.Services = services
	self.BrainrotService = services.BrainrotService

	self.PersonalityConfig = getPersonalityConfig()

	self._active = {} :: { [string]: AIEntry }
	self._hbConn = nil :: RBXScriptConnection?

	self.Config = {
		TickRate = 0.1,

		DefaultDetection = 70,
		DefaultChaseRange = 120,
		DefaultAttackRange = 6,
		DefaultAttackCooldown = 1.25,
		DefaultAttackDamage = 10,

		DefaultIdleMin = 1.5,
		DefaultIdleMax = 3.5,

		DefaultWanderPauseMin = 0.8,
		DefaultWanderPauseMax = 2.2,

		DefaultLeashRadius = 180,
	}

	-- Init subsystems
	MovementRegistry:Init()
	AttackRegistry:Init()
end

function AIService:Start()
	self:_bootstrapExisting()

	-- Listen to BrainrotService bindables
	if self.BrainrotService then
		local spawned = self.BrainrotService.BrainrotSpawned
		if spawned and typeof(spawned.Event) == "RBXScriptSignal" then
			spawned.Event:Connect(function(id: string, model: Model)
				self:Register(id, model)
			end)
		end

		local despawned = self.BrainrotService.BrainrotDespawned
		if despawned and typeof(despawned.Event) == "RBXScriptSignal" then
			despawned.Event:Connect(function(id: string)
				self:Unregister(id)
			end)
		end
	end

	local acc = 0
	self._hbConn = RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < self.Config.TickRate then return end
		acc = 0
		self:_stepAll()
	end)
end

function AIService:_bootstrapExisting()
	if not self.BrainrotService then return end
	if type(self.BrainrotService.GetAllActive) ~= "function" then return end

	local registry = self.BrainrotService:GetAllActive()
	if type(registry) ~= "table" then return end

	for id, rt in pairs(registry) do
		local model: any = rt
		if type(rt) == "table" then
			model = rt.Model or rt.RootModel or rt.Instance
		end
		if typeof(model) == "Instance" and model:IsA("Model") then
			self:Register(tostring(id), model)
		end
	end
end

function AIService:Register(brainrotId: string, model: Model)
	if self._active[brainrotId] then return end
	if not model or model.Parent == nil then return end

	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not hum or not hrp or not hrp:IsA("BasePart") then return end

	local infoObj = model:FindFirstChild("EnemyInfo")
	local enemyInfo = (infoObj and infoObj:IsA("Configuration")) and infoObj or nil

	local ca = model:FindFirstChild("CurrentAnimation")
	local currentAnim = (ca and ca:IsA("StringValue")) and ca or nil

	local zoneName = tostring(model:GetAttribute("ZoneName") or "")
	local terr = (zoneName ~= "") and getZoneTerritory(zoneName) or nil

	local personalityName = getAttrString(enemyInfo, "Personality", "Passive")
	local P = self.PersonalityConfig[personalityName]
	if type(P) ~= "table" then
		P = self.PersonalityConfig["Passive"]
		if type(P) ~= "table" then P = {} end
		personalityName = "Passive"
	end

	local brainrotName = tostring(model:GetAttribute("BrainrotName") or "Default")

	-- Merge per-brainrot personality overrides on top of base personality
	local bCfg = getBrainrotConfig()
	local brainrotEntry = bCfg[brainrotName]
	if brainrotEntry and type(brainrotEntry.PersonalityOverrides) == "table" then
		-- Shallow copy P so we don't mutate the shared PersonalityConfig table
		local merged = {}
		for k, v in pairs(P) do merged[k] = v end
		for k, v in pairs(brainrotEntry.PersonalityOverrides) do merged[k] = v end
		P = merged
	end

	-- Variant system: read size tier and variant name from model attributes
	-- (set by BrainrotService from the Variants config)
	local sizeMult = model:GetAttribute("SizeMultiplier")
	if typeof(sizeMult) ~= "number" then sizeMult = 1.0 end

	local sizeTier = tostring(model:GetAttribute("SizeTier") or "normal")
	local variantName = tostring(model:GetAttribute("VariantName") or "Normal")

	-- Apply variant-specific personality overrides from BrainrotConfig.Variants
	if brainrotEntry and type(brainrotEntry.Variants) == "table" then
		for _, v in ipairs(brainrotEntry.Variants) do
			if v.Name == variantName and type(v.VariantPersonalityOverrides) == "table" then
				-- Ensure P is a mutable copy
				local merged = {}
				for k, val in pairs(P) do merged[k] = val end
				for k, val in pairs(v.VariantPersonalityOverrides) do merged[k] = val end
				P = merged
				break
			end
		end
	end

	-- Size tier personality defaults (for any brainrot with variants, as fallback)
	-- These apply if the variant didn't set explicit personality overrides for these fields
	if sizeTier == "baby" then
		-- Babies default to fearful behavior if variant didn't override
		if P.Aggressive == nil or P.Aggressive > 0.10 then
			P.Aggressive = math.min(P.Aggressive or 0.25, 0.05)
		end
		personalityName = "Fearful"
	elseif sizeTier == "huge" then
		-- Huge defaults to aggressive if variant didn't override
		if P.Aggressive == nil or P.Aggressive < 0.50 then
			P.Aggressive = math.max(P.Aggressive or 0.25, 0.90)
		end
		personalityName = "Aggressive"
	end

	local spawnPos = hrp.Position

	-- Leash radius: use personality config value, but ensure it covers at least 3/4 of territory
	-- so brainrots in large territories aren't artificially constrained.
	local configLeash = pNumber(P, "LeashRadius", self.Config.DefaultLeashRadius)
	local terrSpanForLeash = terr and math.max(terr.Size.X, terr.Size.Z) * 0.75 or 45
	local leashRadius = math.max(configLeash, terrSpanForLeash)

	-- Resolve locomotion type and attack moves
	local locoType = resolveLocomotionType(brainrotName)
	local locomotion = MovementRegistry:Get(locoType)
	local attackMoves = resolveAttackMoves(brainrotName, P)

	local entry: AIEntry = {
		Id = brainrotId,
		Model = model,
		Humanoid = hum,
		HRP = hrp,

		ZoneName = zoneName,
		Territory = terr,
		SpawnPos = spawnPos,

		EnemyInfo = enemyInfo,
		CurrentAnimation = currentAnim,

		PersonalityName = personalityName,
		P = P,

		State = "Idle",
		Target = nil,

		NextThinkAt = now() + randRange(self.Config.DefaultIdleMin, self.Config.DefaultIdleMax),
		NextAttackAt = 0,

		LastHealth = hum.Health,
		LastDamagedAt = -1e9,

		LeashRadius = leashRadius,
		FleeUntil = 0,
		FleeFrom = nil,

		WanderTarget = nil,

		-- New fields
		LocomotionType = locoType,
		Locomotion = locomotion,
		AttackMoves = attackMoves,
		ThreatLevel = 0,
		WaitEdgeZone = nil,
		WaitEdgeUntil = 0,

		-- Size info
		SizeTier = sizeTier,
		SizeMultiplier = sizeMult,
		BrainrotName = brainrotName,

		Conn = {},
	}

	-- Init locomotion
	if locomotion and type(locomotion.Init) == "function" then
		locomotion:Init(entry)
	end

	-- Init attack state
	AttackRegistry:InitEntry(entry)

	-- Damage reaction via health drops
	table.insert(entry.Conn, hum.HealthChanged:Connect(function(h: number)
		local prev = entry.LastHealth
		entry.LastHealth = h
		if h < prev then
			entry.LastDamagedAt = now()
			self:_onDamaged(entry)
		end
	end))

	table.insert(entry.Conn, hum.Died:Connect(function()
		self:_setState(entry, "Dead")
	end))

	table.insert(entry.Conn, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			self:Unregister(brainrotId)
		end
	end))

	self._active[brainrotId] = entry
	self:_setState(entry, "Idle")
end

function AIService:Unregister(brainrotId: string)
	local entry = self._active[brainrotId]
	if not entry then return end
	self._active[brainrotId] = nil

	-- Cleanup locomotion
	if entry.Locomotion and type(entry.Locomotion.Cleanup) == "function" then
		entry.Locomotion:Cleanup(entry)
	end

	for _, c in ipairs(entry.Conn) do
		c:Disconnect()
	end
end

function AIService:_setState(entry: AIEntry, state: AIStateName)
	if entry.State == state then return end
	entry.State = state

	local idleMin, idleMax = pRange(entry.P, "IdleFrequency", self.Config.DefaultIdleMin, self.Config.DefaultIdleMax)
	entry.NextThinkAt = now() + randRange(idleMin, idleMax)

	if state == "Idle" then
		entry.Target = nil
		entry.WanderTarget = nil
		entry.WaitEdgeZone = nil
		entry.Humanoid.WalkSpeed = 0
		if entry.Locomotion and type(entry.Locomotion.Stop) == "function" then
			entry.Locomotion:Stop(entry)
		end
		safeSetAnim(entry, "Idle")
	elseif state == "Wander" then
		entry.Target = nil
		safeSetAnim(entry, "Walk")
	elseif state == "Chase" then
		safeSetAnim(entry, "Run")
	elseif state == "Attack" then
		safeSetAnim(entry, "Attack")
	elseif state == "Flee" then
		safeSetAnim(entry, "Run")
	elseif state == "Return" then
		entry.Target = nil
		entry.WanderTarget = nil
		entry.WaitEdgeZone = nil
		safeSetAnim(entry, "Walk")
	elseif state == "WaitAtEdge" then
		entry.Humanoid.WalkSpeed = 0
		safeSetAnim(entry, "Idle")
	elseif state == "Dead" then
		entry.Target = nil
		entry.WanderTarget = nil
		entry.Humanoid.WalkSpeed = 0
		if entry.Locomotion and type(entry.Locomotion.Stop) == "function" then
			entry.Locomotion:Stop(entry)
		end
		safeSetAnim(entry, "Dead")
	end
end

function AIService:_onDamaged(entry: AIEntry)
	if entry.State == "Dead" then return end

	local P = entry.P
	local pName = entry.PersonalityName

	-- When damaged, search a MUCH larger radius — damage means you know where they are.
	-- Scale with territory size: 1.5x territory span, minimum 3x aggro distance.
	local aggroDist = pNumber(P, "AggroDistance", self.Config.DefaultDetection)
	local terrSpan = getTerritorySpan(entry)
	local damageSearchRange = math.max(aggroDist * 3, terrSpan * 1.5)

	-- Helper: flee from nearest player
	local function doFlee(fearTime: number?)
		local plr = select(1, pickNearestPlayer(entry.HRP.Position, damageSearchRange))
		entry.FleeFrom = plr
		entry.FleeUntil = now() + (fearTime or pNumber(P, "FearTime", 2.5))
		self:_setState(entry, "Flee")
	end

	-- Helper: chase nearest player
	local function doChase(): boolean
		local plr = select(1, pickNearestPlayer(entry.HRP.Position, damageSearchRange))
		if plr then
			entry.Target = plr
			self:_setState(entry, "Chase")
			return true
		end
		return false
	end

	-- Fearful: ALWAYS flee on damage, even interrupt current attacks
	if pName == "Fearful" then
		doFlee()
		self:_signalPack(entry, "Flee")
		return
	end

	-- If currently fleeing, don't re-evaluate
	if entry.State == "Flee" and now() < entry.FleeUntil then
		return
	end

	-- Aggressive/Berserk: ALWAYS retaliate, never flee
	if pName == "Aggressive" or pName == "Berserk" then
		if doChase() then
			self:_signalPack(entry, "Chase", entry.Target)
		end
		return
	end

	-- Territorial: ALWAYS retaliate when damaged (damage is damage, range doesn't matter).
	-- Territory position only affects pursuit tenacity, not the initial reaction.
	if pName == "Territorial" then
		if doChase() then
			self:_signalPack(entry, "Chase", entry.Target)
		else
			-- No player in aggro range to chase — flee briefly instead of standing idle
			doFlee(1.5)
			self:_signalPack(entry, "Flee")
		end
		return
	end

	-- All other personalities: probabilistic but with guaranteed fallback
	local retaliates = P.RetaliateOnDamage
	if retaliates == nil then retaliates = true end

	local retaliateChance = pNumber(P, "RetaliateAggression", pNumber(P, "AttackChance", 0.10))
	local runChance = pNumber(P, "RunWhenAttacked", pNumber(P, "RunChance", 0.25))

	-- Cornered aggression: if health is low and can't easily flee, boost aggression
	local threat = computeThreatLevel(entry)
	if threat > 0.7 then
		local cornered = pNumber(P, "CorneredAggression", 0.5)
		retaliateChance = math.max(retaliateChance, cornered)
		runChance = runChance * (1 - cornered)
	end

	if math.random() < runChance then
		doFlee()
		self:_signalPack(entry, "Flee")
		return
	end

	if retaliates and math.random() < retaliateChance then
		if doChase() then
			self:_signalPack(entry, "Chase", entry.Target)
			return
		end
	end

	-- Guaranteed fallback: never just stand there after being hit
	if entry.State == "Idle" or entry.State == "Wander" then
		if pName == "Skittish" or pName == "Jumpy" then
			doFlee(1.5) -- brief scatter
		else
			-- Passive or unknown: flee briefly
			doFlee(2.0)
		end
	end
end

----------------------------------------------------------------------
-- Pack behavior signaling
----------------------------------------------------------------------

function AIService:_signalPack(entry: AIEntry, newState: string, target: Player?)
	-- Baby/small variants can't rally the pack — they flee alone
	local sizeTier = entry.Model and entry.Model:GetAttribute("SizeTier")
	if sizeTier == "baby" or sizeTier == "small" then return end

	local brainrotName = tostring(entry.Model:GetAttribute("BrainrotName") or "Default")
	local allCfg = getBrainrotConfig()
	local bCfg = allCfg[brainrotName]
	if not bCfg or type(bCfg.PackBehavior) ~= "table" or not bCfg.PackBehavior.Enabled then
		return
	end

	local packCfg = bCfg.PackBehavior
	local shareStates = packCfg.ShareStates
	if type(shareStates) ~= "table" then return end

	-- Check if this state should propagate
	local shouldShare = false
	for _, s in ipairs(shareStates) do
		if s == newState then shouldShare = true; break end
	end
	if not shouldShare then return end

	-- Calculate signal radius (fraction of territory size)
	local signalFrac = packCfg.SignalRange or 0.5
	local radius = 30 -- fallback
	if entry.Territory then
		local tSize = entry.Territory.Size
		radius = math.max(tSize.X, tSize.Z) * signalFrac
	end

	-- Chase join chance: neighbors aren't guaranteed to fully commit.
	-- Closer neighbors are more likely to join. Base chance from config (default 0.6).
	local baseJoinChance = packCfg.PackJoinChance or 0.6

	-- Signal nearby brainrots in same zone
	for _, other in pairs(self._active) do
		if other.Id == entry.Id then continue end
		if other.State == "Dead" then continue end
		if other.ZoneName ~= entry.ZoneName then continue end
		if not other.HRP or not other.HRP.Parent then continue end

		local dist = (other.HRP.Position - entry.HRP.Position).Magnitude
		if dist > radius then continue end

		-- Distance falloff: closer = more likely to join (100% at 0, baseJoinChance at edge)
		local distFactor = 1 - (dist / radius) -- 1.0 at center, 0.0 at edge
		local joinChance = baseJoinChance + (1 - baseJoinChance) * distFactor * 0.5

		if newState == "Chase" and target then
			-- Already chasing same target? Skip
			if other.State == "Chase" and other.Target == target then continue end

			if math.random() < joinChance then
				other.Target = target
				self:_setState(other, "Chase")
			end
		elseif newState == "Flee" then
			-- Flee signal is stronger — pack animals scatter together
			if other.State ~= "Flee" then
				other.FleeFrom = entry.FleeFrom
				other.FleeUntil = now() + pNumber(other.P, "FearTime", 2.5)
				self:_setState(other, "Flee")
			end
		end
	end
end

function AIService:_shouldReturn(entry: AIEntry): boolean
	local terr = entry.Territory
	local leash = entry.LeashRadius
	local leashStrength = pNumber(entry.P, "LeashStrength", 0.7)

	-- Weaker leash = chance to ignore
	if leashStrength < 1.0 and math.random() > leashStrength then
		return false
	end

	if terr then
		local d = (entry.HRP.Position - terr.Position).Magnitude
		return d > leash
	else
		local d = (entry.HRP.Position - entry.SpawnPos).Magnitude
		return d > leash
	end
end

function AIService:_pickWanderPoint(entry: AIEntry): Vector3
	local terr = entry.Territory
	local y = territoryY(terr, entry.HRP.Position.Y)

	-- Baby brainrots: 60% chance to wander toward nearest big/huge brainrot (like staying near adults)
	if entry.SizeTier == "baby" and math.random() < 0.60 then
		local bestDist = math.huge
		local bestPos: Vector3? = nil
		for _, other in pairs(self._active) do
			if other.Id == entry.Id then continue end
			if other.State == "Dead" then continue end
			if other.ZoneName ~= entry.ZoneName then continue end
			if other.SizeTier ~= "big" and other.SizeTier ~= "huge" then continue end
			if not other.HRP or not other.HRP.Parent then continue end
			local d = (other.HRP.Position - entry.HRP.Position).Magnitude
			if d < bestDist then
				bestDist = d
				bestPos = other.HRP.Position
			end
		end
		if bestPos then
			-- Wander to a point near the big one (within 8 studs)
			local offset = Vector3.new((math.random() - 0.5) * 16, 0, (math.random() - 0.5) * 16)
			return Vector3.new(bestPos.X + offset.X, y, bestPos.Z + offset.Z)
		end
	end

	if terr then
		-- Try up to 5 times to find a point not in an exclusion zone
		for _ = 1, 5 do
			local p = randomPointInTerritory(terr, y)
			if not ExclusionZoneManager:IsBlocked(p, 1) then
				return p
			end
		end
		return randomPointInTerritory(terr, y)
	end

	local r = pNumber(entry.P, "PatrolRadius", 28)
	local theta = math.random() * math.pi * 2
	local rad = math.random() * r
	return Vector3.new(entry.SpawnPos.X + math.cos(theta) * rad, y, entry.SpawnPos.Z + math.sin(theta) * rad)
end

--//////////////////////////////
-- Movement helpers (use locomotion module)
--//////////////////////////////

local function moveToward(entry: AIEntry, targetPos: Vector3)
	local loco = entry.Locomotion
	if loco and type(loco.MoveTo) == "function" then
		loco:MoveTo(entry, targetPos)
	else
		-- Fallback: raw MoveTo
		entry.Humanoid:MoveTo(targetPos)
	end
end

local function isFlying(entry: AIEntry): boolean
	local loco = entry.Locomotion
	return loco and type(loco.IsFlying) == "function" and loco:IsFlying()
end

--//////////////////////////////
-- Exclusion zone checks
--//////////////////////////////

local function checkTargetInExclusionZone(entry: AIEntry, targetPos: Vector3): (boolean, number, any?)
	return ExclusionZoneManager:Query(targetPos)
end

function AIService:_handleExclusionZone(entry: AIEntry, targetPos: Vector3, zoneWeight: number, zone: any): boolean
	-- Returns true if the brainrot should NOT pursue (abandon/wait)
	local eb = pTable(entry.P, "ExclusionBehavior")
	if not eb then return zoneWeight >= 80 end -- default: only block on high weight

	local lowThreshold = tonumber(eb.LowThreshold) or 20
	local waitAtEdge = eb.WaitAtEdge == true
	local waitPatience = tonumber(eb.WaitPatience) or 0
	local pushCost = tonumber(eb.PushThroughCost) or 0

	-- High weight (80+): always blocked
	if zoneWeight >= 80 then
		if waitAtEdge and zone then
			entry.WaitEdgeZone = zone
			entry.WaitEdgeUntil = now() + waitPatience
			self:_setState(entry, "WaitAtEdge")
		else
			entry.Target = nil
			self:_setState(entry, "Return")
		end
		return true
	end

	-- Below personality threshold: ignore zone
	if zoneWeight < lowThreshold then
		return false
	end

	-- Medium weight: personality-based decision
	if math.random() < pushCost then
		return false -- push through
	end

	if waitAtEdge and zone then
		entry.WaitEdgeZone = zone
		entry.WaitEdgeUntil = now() + waitPatience
		self:_setState(entry, "WaitAtEdge")
	else
		entry.Target = nil
		self:_setState(entry, "Return")
	end
	return true
end

--//////////////////////////////
-- Main evaluator
--//////////////////////////////

function AIService:_stepAll()
	for id, entry in pairs(self._active) do
		if entry.Model.Parent == nil then
			self._active[id] = nil
		else
			self:_stepOne(entry)
		end
	end
end

function AIService:_stepOne(entry: AIEntry)
	if entry.State == "Dead" then return end
	if entry.Humanoid.Health <= 0 then
		self:_setState(entry, "Dead")
		return
	end

	local t = now()
	local pos = entry.HRP.Position

	-- Update threat level
	entry.ThreatLevel = computeThreatLevel(entry)

	local walkSpeed = getAttrNumber(entry.EnemyInfo, "Walkspeed", 16)
	local runSpeed = getAttrNumber(entry.EnemyInfo, "Runspeed", walkSpeed + 6)

	local attackDamage = getAttrNumber(entry.EnemyInfo, "AttackDamage", self.Config.DefaultAttackDamage)
	local attackRange = getAttrNumber(entry.EnemyInfo, "AttackRange", self.Config.DefaultAttackRange)

	local aggroDist = pNumber(entry.P, "AggroDistance", self.Config.DefaultDetection)
	local chaseRange = pNumber(entry.P, "ChaseRange", self.Config.DefaultChaseRange)
	local fearDist = pNumber(entry.P, "FearDistance", 40)
	local runMaxDist = pNumber(entry.P, "RunMaxDistance", 150)

	-- Determine effective attack range from available moves
	local entryBrainrotName = tostring(entry.Model:GetAttribute("BrainrotName") or "Default")
	local maxAttackRange = AttackRegistry:GetMaxRange(entry.AttackMoves, entryBrainrotName)
	if maxAttackRange > attackRange then
		attackRange = maxAttackRange
	end

	-- Check if WE are in an exclusion zone (should leave ASAP)
	local selfInZone, selfZoneWeight = ExclusionZoneManager:Query(pos)
	if selfInZone and selfZoneWeight >= 50 then
		-- Get out! Move toward spawn/territory
		self:_setState(entry, "Return")
	end

	-- Return overrides neutral states
	if entry.State ~= "Return" and entry.State ~= "Chase" and entry.State ~= "Attack"
		and entry.State ~= "WaitAtEdge" then
		if self:_shouldReturn(entry) then
			self:_setState(entry, "Return")
		end
	end

	-- Acquire target on proximity (only in neutral states)
	if entry.State == "Idle" or entry.State == "Wander" then
		if not entry.Target then
			local near, nearDist = pickNearestPlayer(pos, aggroDist)
			if near then
				-- Fearful proximity flee: if player is within FearDistance, flee immediately
				if entry.PersonalityName == "Fearful" and nearDist <= fearDist then
					entry.FleeFrom = near
					entry.FleeUntil = now() + pNumber(entry.P, "FearTime", 2.5)
					self:_setState(entry, "Flee")
					self:_signalPack(entry, "Flee")

				-- Sentry behavior: Fearful + ranged brainrots attack from Idle if target
				-- is within attack range but outside fear distance (no chase needed)
				elseif entry.PersonalityName == "Fearful"
					and pNumber(entry.P, "PreferRanged", 0) >= 0.8
					and nearDist <= attackRange
					and nearDist > fearDist then
					entry.Target = near
					self:_setState(entry, "Attack")
				else
					local aggChance = pNumber(entry.P, "Aggressive", 0.25)

					-- Territorial intrusion: if the player is inside OUR territory,
					-- aggro is near-guaranteed (0.95) regardless of base aggression
					if entry.PersonalityName == "Territorial" and entry.Territory then
						local thrp = getCharHRP(near)
						if thrp and isInsideTerritoryXZ(entry.Territory, thrp.Position) then
							aggChance = 0.95
						end
					end

					if math.random() < aggChance then
						-- Check if target is in exclusion zone before chasing
						local thrp = getCharHRP(near)
						if thrp then
							local inZone, zWeight, zone = checkTargetInExclusionZone(entry, thrp.Position)
							if inZone and zWeight >= 80 then
								-- Target in hard-blocked zone, don't aggro
							else
								entry.Target = near
								self:_setState(entry, "Chase")
								-- Pack animals alert nearby allies when they spot a target
								self:_signalPack(entry, "Chase", near)
							end
						end
					end
				end
			end
		end
	end

	---------- FLEE ----------
	if entry.State == "Flee" then
		entry.Humanoid.WalkSpeed = runSpeed
		local from = entry.FleeFrom
		local fromHRP = from and getCharHRP(from) or nil
		if not fromHRP then
			entry.FleeUntil = 0
			self:_setState(entry, "Return")
			return
		end

		local away = (pos - fromHRP.Position)
		local d = away.Magnitude
		if d < 0.1 then away = Vector3.new(1, 0, 0) end
		away = away.Unit

		local step = math.min(runMaxDist, math.max(20, fearDist))
		local y = territoryY(entry.Territory, pos.Y)

		-- FleeStyle: "straight" (default), "zigzag", "scatter"
		local fleeStyle = entry.P.FleeStyle or "straight"

		local fleeX = pos.X + away.X * step
		local fleeZ = pos.Z + away.Z * step

		if fleeStyle == "zigzag" then
			-- Alternate perpendicular offsets to dodge in a zigzag pattern
			if not entry.FleeZigDir then entry.FleeZigDir = 1 end
			if not entry.FleeNextZig then entry.FleeNextZig = 0 end

			if t >= entry.FleeNextZig then
				entry.FleeZigDir = -entry.FleeZigDir
				entry.FleeNextZig = t + 0.4 + math.random() * 0.4 -- flip every 0.4-0.8s
			end

			-- Perpendicular vector (rotate 90 degrees on XZ plane)
			local perpX = -away.Z
			local perpZ = away.X
			local zigOffset = entry.FleeZigDir * (step * 0.35) -- 35% of step sideways

			fleeX = fleeX + perpX * zigOffset
			fleeZ = fleeZ + perpZ * zigOffset

		elseif fleeStyle == "scatter" then
			-- Random angle offset each tick: flee roughly away but with ±60° scatter
			local scatterAngle = math.rad(math.random(-60, 60))
			local cosA = math.cos(scatterAngle)
			local sinA = math.sin(scatterAngle)

			-- Rotate the away vector by scatterAngle on XZ plane
			local rotX = away.X * cosA - away.Z * sinA
			local rotZ = away.X * sinA + away.Z * cosA

			fleeX = pos.X + rotX * step
			fleeZ = pos.Z + rotZ * step
		end

		local fleePos = Vector3.new(fleeX, y, fleeZ)

		moveToward(entry, fleePos)
		safeSetAnim(entry, "Run")

		if t >= entry.FleeUntil then
			self:_setState(entry, "Return")
		end
		return
	end

	---------- WAIT AT EDGE ----------
	if entry.State == "WaitAtEdge" then
		local target = entry.Target
		local thrp = target and getCharHRP(target) or nil

		-- Check if target left the zone
		if thrp then
			local inZone, zWeight = ExclusionZoneManager:Query(thrp.Position)
			if not inZone or zWeight < 50 then
				-- Target is out, re-engage!
				self:_setState(entry, "Chase")
				return
			end
		end

		-- Check patience
		if t >= entry.WaitEdgeUntil then
			entry.Target = nil
			entry.WaitEdgeZone = nil
			self:_setState(entry, "Return")
			return
		end

		-- Pace at edge
		local eb = pTable(entry.P, "ExclusionBehavior")
		local pacingRadius = (eb and tonumber(eb.PacingRadius)) or 0
		if pacingRadius > 0 and entry.WaitEdgeZone then
			local edgePoint = ExclusionZoneManager:GetNearestEdgePoint(
				thrp and thrp.Position or pos, entry.WaitEdgeZone
			)
			local paceOffset = Vector3.new(
				math.cos(t * 1.5) * pacingRadius,
				0,
				math.sin(t * 1.5) * pacingRadius
			)
			entry.Humanoid.WalkSpeed = walkSpeed * 0.5
			moveToward(entry, edgePoint + paceOffset)
			safeSetAnim(entry, "Walk")
		else
			entry.Humanoid.WalkSpeed = 0
			safeSetAnim(entry, "Idle")
		end
		return
	end

	---------- RETURN ----------
	if entry.State == "Return" then
		-- Fearful proximity flee: even while returning, flee if player gets close
		if entry.PersonalityName == "Fearful" then
			local near, nearDist = pickNearestPlayer(pos, fearDist)
			if near and nearDist <= fearDist then
				entry.FleeFrom = near
				entry.FleeUntil = now() + pNumber(entry.P, "FearTime", 2.5)
				self:_setState(entry, "Flee")
				self:_signalPack(entry, "Flee")
				return
			end
		end

		entry.Humanoid.WalkSpeed = walkSpeed

		local terr = entry.Territory
		local y = territoryY(terr, pos.Y)
		local targetPos: Vector3
		if terr then
			targetPos = Vector3.new(terr.Position.X, y, terr.Position.Z)
		else
			targetPos = Vector3.new(entry.SpawnPos.X, y, entry.SpawnPos.Z)
		end

		moveToward(entry, targetPos)
		safeSetAnim(entry, "Walk")

		if terr then
			if isInsideTerritoryXZ(terr, pos) then
				self:_setState(entry, "Idle")
			end
		else
			if (pos - entry.SpawnPos).Magnitude <= 12 then
				self:_setState(entry, "Idle")
			end
		end
		return
	end

	---------- CHASE / ATTACK ----------
	if entry.State == "Chase" or entry.State == "Attack" then
		local target = entry.Target
		local thrp = target and getCharHRP(target) or nil
		local thum = target and getCharHumanoid(target) or nil

		if not thrp or not thum or thum.Health <= 0 then
			entry.Target = nil
			self:_setState(entry, "Idle")
			return
		end

		local d = (thrp.Position - pos).Magnitude

		-- Fearful proximity flee: if target gets within FearDistance, abandon attack and flee
		if entry.PersonalityName == "Fearful" and d <= fearDist then
			entry.Target = nil
			entry.FleeFrom = target
			entry.FleeUntil = now() + pNumber(entry.P, "FearTime", 2.5)
			self:_setState(entry, "Flee")
			self:_signalPack(entry, "Flee")
			return
		end

		-- Recently damaged = committed to chase for at least 3 seconds (no give-up rolls)
		local recentlyDamaged = (t - entry.LastDamagedAt) < 3.0

		-- Territory tenacity: if Territorial and inside own territory, never give up chase
		local terrTenacity = pNumber(entry.P, "TerritoryTenacity", 0)
		local inOwnTerritory = terrTenacity > 0 and entry.Territory
			and isInsideTerritoryXZ(entry.Territory, pos)

		-- Check chase range (scale with territory; recently damaged = commit further)
		-- Ranged sentries (Fearful + PreferRanged) use attackRange as their effective range,
		-- not chaseRange — they don't chase, they stand and shoot from distance
		local entryTerrSpan = getTerritorySpan(entry)
		local damagedChaseRange = math.max(chaseRange, entryTerrSpan * 1.5)
		local effectiveChaseRange = recentlyDamaged and damagedChaseRange or chaseRange

		-- Ranged sentries stay engaged as long as target is within attack range
		if entry.State == "Attack" and pNumber(entry.P, "PreferRanged", 0) >= 0.8 then
			effectiveChaseRange = math.max(effectiveChaseRange, attackRange)
		end

		if d > effectiveChaseRange then
			if not inOwnTerritory then
				entry.Target = nil
				self:_setState(entry, "Return")
				return
			end
		end

		-- Pursuit tenacity: chance to give up chase over time
		-- Skip if recently damaged (committed) or inside own territory (territorial defense)
		if entry.State == "Chase" and d > aggroDist and not recentlyDamaged and not inOwnTerritory then
			local tenacity = pNumber(entry.P, "PursuitTenacity", 0.5)
			if math.random() > tenacity then
				entry.Target = nil
				self:_setState(entry, "Return")
				return
			end
		end

		-- Check if target is in an exclusion zone
		local tInZone, tZoneWeight, tZone = checkTargetInExclusionZone(entry, thrp.Position)
		if tInZone and tZoneWeight > 0 then
			local blocked = self:_handleExclusionZone(entry, thrp.Position, tZoneWeight, tZone)
			if blocked then return end
		end

		-- Attack or chase
		if d <= attackRange then
			-- RE-EVALUATE: pick best attack move
			self:_setState(entry, "Attack")
			entry.Humanoid.WalkSpeed = 0
			if entry.Locomotion and type(entry.Locomotion.Stop) == "function" then
				entry.Locomotion:Stop(entry)
			end

			if t >= entry.NextAttackAt then
				local moveName, moveMod, moveCfg = AttackRegistry:PickMove(
					entry, target, d, entry.P, entry.AttackMoves
				)

				if moveMod and moveCfg then
					-- Apply per-brainrot + variant move overrides
					local bName = tostring(entry.Model:GetAttribute("BrainrotName") or "Default")
					local vName = entry.Model:GetAttribute("VariantName")
					moveCfg = applyMoveOverrides(bName, moveName :: string, moveCfg, vName)

					-- Set animation (moveConfig AnimationKey override > module default)
					local animName = "Attack"
					if moveCfg.AnimationKey then
						animName = "attack_" .. moveCfg.AnimationKey
					elseif type(moveMod.GetAnimationName) == "function" then
						animName = moveMod:GetAnimationName()
					end
					safeSetAnim(entry, animName)

					-- Calculate cooldown
					local cd = moveCfg.Cooldown or self.Config.DefaultAttackCooldown
					local effectiveMult = entry.Model:GetAttribute("EffectiveMultiplier")
					if typeof(effectiveMult) == "number" and effectiveMult > 0 then
						cd = cd / effectiveMult
					end
					entry.NextAttackAt = t + cd

					-- Record usage for per-move cooldown
					AttackRegistry:RecordUse(entry, moveName :: string)

					-- Execute the attack (may yield for windup)
					task.spawn(function()
						moveMod:Execute(entry, target, self.Services, moveCfg)
					end)
				else
					-- No valid move, fallback to basic damage
					safeSetAnim(entry, "Attack")
					entry.NextAttackAt = t + self.Config.DefaultAttackCooldown
					pcall(function()
						local armorSvc = self.Services and self.Services.ArmorService
						if armorSvc and target then
							local absorbed, overflow = armorSvc:DamageArmor(target, attackDamage)
							if overflow > 0 then
								thum:TakeDamage(overflow)
							end
						else
							thum:TakeDamage(attackDamage)
						end
					end)
				end
			end
		else
			-- Chase
			self:_setState(entry, "Chase")
			entry.Humanoid.WalkSpeed = runSpeed
			moveToward(entry, thrp.Position)
			safeSetAnim(entry, "Run")
		end

		return
	end

	---------- IDLE / WANDER ----------
	if entry.State == "Idle" then
		entry.Humanoid.WalkSpeed = 0

		-- Flying entities circle instead of standing
		if isFlying(entry) and entry.Locomotion then
			local center = entry.Territory and entry.Territory.Position or entry.SpawnPos
			if type(entry.Locomotion.Circle) == "function" then
				entry.Locomotion:Circle(entry, center, self.Config.TickRate)
				safeSetAnim(entry, "Walk")
			else
				safeSetAnim(entry, "Idle")
			end
		else
			safeSetAnim(entry, "Idle")
		end

		if t >= entry.NextThinkAt then
			local actions = entry.P.IdleActions
			local doWalk = true
			if type(actions) == "table" and #actions > 0 then
				local pick = actions[math.random(1, #actions)]
				doWalk = (tostring(pick) == "walk")
			end
			if doWalk then
				entry.WanderTarget = self:_pickWanderPoint(entry)
				self:_setState(entry, "Wander")
			else
				local lo, hi = pRange(entry.P, "IdleFrequency", self.Config.DefaultIdleMin, self.Config.DefaultIdleMax)
				entry.NextThinkAt = t + randRange(lo, hi)
			end
		end
		return
	end

	if entry.State == "Wander" then
		entry.Humanoid.WalkSpeed = walkSpeed
		safeSetAnim(entry, "Walk")

		if not entry.WanderTarget then
			entry.WanderTarget = self:_pickWanderPoint(entry)
		end

		local dXZ = math.sqrt(
			(entry.WanderTarget.X - pos.X)^2 + (entry.WanderTarget.Z - pos.Z)^2
		)
		if dXZ <= 3 then
			local lo, hi = pRange(entry.P, "WanderPause", self.Config.DefaultWanderPauseMin, self.Config.DefaultWanderPauseMax)
			entry.NextThinkAt = t + randRange(lo, hi)
			self:_setState(entry, "Idle")
		else
			moveToward(entry, entry.WanderTarget)
		end
		return
	end
end

return AIService
