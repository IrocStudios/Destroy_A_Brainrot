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
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
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
	| "SeekHide" | "HideTree" | "HideUnderground" | "Grab"

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
	ReturnTarget: Vector3?,

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
	SafeZones: { BasePart },

	-- Idle fidget tracking
	ConsecutiveIdles: number, -- how many times in a row we picked "idle" action

	-- Territory return cooldown
	ReturnCooldownUntil: number, -- don't re-check _shouldReturn until this time

	-- Stuck-hop escalation
	StuckTicks: number, -- consecutive ticks of near-zero XZ velocity while trying to move
	StuckHopStage: number, -- 0=none, 1=baby hop done, 2=medium hop done, 3=big hop done
	LastHopAt: number, -- timestamp of last hop (cooldown)

	-- Pack hunt offset (pack wolves): random angle for approach direction
	HuntAngle: number?,

	-- Flee evasion state
	FleeZigDir: number, -- +1 or -1, alternates for zigzag
	FleeNextZig: number, -- tick when next zigzag flip happens

	-- Aggro meter (0-100 continuous anger)
	Aggro: number,
	AggroLockedUntil: number,  -- timestamp: aggro cannot decay below 100 until this time
	AC: { [string]: any },     -- resolved aggro curve parameters

	-- Ambush behavior (Orangutini Ananassini)
	IsAmbush: boolean?,           -- flag: uses ambush state machine
	HideSpot: BasePart?,          -- current tree or nil (underground = at current pos)
	HideType: string?,            -- "tree" | "underground" | nil
	HideUntil: number?,           -- patience timer expiry
	HideTween: Tween?,            -- active tween (cancelable)
	HideTweenDone: boolean?,      -- true when tween completed
	HideTreeSide: string?,        -- "north"|"south"|"east"|"west" — claimed side of tree
	GrabTarget: Player?,          -- player currently grabbed
	OriginalCFrame: CFrame?,      -- saved CFrame before hiding (for restore)

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

-- Find all SafeZone parts inside a zone folder (siblings of Territory)
local function getZoneSafeZones(zoneName: string): { BasePart }
	local territories = getTerritoriesFolder()
	local zone = territories:FindFirstChild(zoneName)
	if not zone then return {} end
	local zones = {}
	for _, child in ipairs(zone:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "SafeZone" then
			table.insert(zones, child)
		end
	end
	return zones
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

-- Pick a random point inside a SafeZone part (or near it if small)
local function randomPointInSafeZone(safeZone: BasePart, y: number): Vector3
	local cf = safeZone.CFrame
	local size = safeZone.Size
	local rx = (math.random() - 0.5) * size.X * 0.8
	local rz = (math.random() - 0.5) * size.Z * 0.8
	local p = (cf * CFrame.new(rx, 0, rz)).Position
	return Vector3.new(p.X, y, p.Z)
end

-- Find the nearest SafeZone to a position
local function nearestSafeZone(safeZones: { BasePart }, pos: Vector3): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, sz in ipairs(safeZones) do
		local d = (sz.Position - pos).Magnitude
		if d < bestDist then
			bestDist = d
			best = sz
		end
	end
	return best
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

-- Pack hunt offset (studs from target) for pack wolves approaching from random sides
local HUNT_OFFSET = 4

-- Ambush tween helper: starts a cancelable CFrame tween on the HRP.
-- Stores the tween on entry.HideTween so it can be cancelled by _onDamaged.
-- entry.HideTweenDone is set to true when complete.
local TWEEN_CLIMB_TIME = 2.5   -- seconds to climb up tree (slower, stealthy)
local TWEEN_DIG_TIME = 0.8     -- seconds to sink underground
local TWEEN_POP_TIME = 0.3     -- seconds to pop out of ground
local AMBUSH_MAX_PER_TREE = 4  -- max monkeys on one tree (one per side)
local AMBUSH_DIG_WEIGHT = 4    -- dig:tree ratio (4:1 favors underground)

-- Track which tree sides are occupied: _treeSideOccupants[treePart] = { [side] = entryId }
local _treeSideOccupants: { [BasePart]: { [string]: string } } = {}
local TREE_SIDES = { "north", "south", "east", "west" }

local function getTreeSideOffset(treePart: BasePart, side: string): Vector3
	local halfX = treePart.Size.X * 0.5
	local halfZ = treePart.Size.Z * 0.5
	if side == "north" then return Vector3.new(0, 0, -halfZ)
	elseif side == "south" then return Vector3.new(0, 0, halfZ)
	elseif side == "east" then return Vector3.new(halfX, 0, 0)
	else return Vector3.new(-halfX, 0, 0) end
end

local function claimTreeSide(treePart: BasePart, entryId: string): string?
	if not _treeSideOccupants[treePart] then
		_treeSideOccupants[treePart] = {}
	end
	local sides = _treeSideOccupants[treePart]
	-- Pick a random available side
	local available = {}
	for _, s in ipairs(TREE_SIDES) do
		if not sides[s] then table.insert(available, s) end
	end
	if #available == 0 then return nil end -- tree full
	local pick = available[math.random(1, #available)]
	sides[pick] = entryId
	return pick
end

local function releaseTreeSide(treePart: BasePart?, entryId: string)
	if not treePart or not _treeSideOccupants[treePart] then return end
	local sides = _treeSideOccupants[treePart]
	for side, id in pairs(sides) do
		if id == entryId then
			sides[side] = nil
			break
		end
	end
end

local function startAmbushTween(entry: any, targetCFrame: CFrame, duration: number)
	-- Cancel any existing tween
	if entry.HideTween then
		pcall(function() entry.HideTween:Cancel() end)
		entry.HideTween = nil
	end
	entry.HideTweenDone = false

	local hrp = entry.HRP
	if not hrp or not hrp.Parent then return end

	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tween = TweenService:Create(hrp, info, { CFrame = targetCFrame })

	tween.Completed:Connect(function(status)
		if status == Enum.PlaybackState.Completed then
			entry.HideTweenDone = true
		end
		entry.HideTween = nil
	end)

	entry.HideTween = tween
	tween:Play()
end

local function cancelAmbushTween(entry: any)
	if entry.HideTween then
		pcall(function() entry.HideTween:Cancel() end)
		entry.HideTween = nil
	end
	entry.HideTweenDone = false
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
-- Aggro curve resolution
--//////////////////////////////

local DEFAULT_AGGRO_CURVE = {
	IdleAggro = 0, DamageGain = 20, ProximityRate = 15, TerritoryRate = 5,
	CorneredRate = 8, PackGain = 30, DecayRate = 3.0, TerritoryDecayMult = 2.0,
	OutOfSightDecay = 5, DecayDelay = 4, AccelDecayMult = 2.0,
	ChaseThreshold = 35, PursuitThreshold = 60, BerserkThreshold = 85,
	FleeInversion = false, FleeThreshold = 20,
}

local function resolveAggroCurve(personalityTable: {[string]: any}, brainrotName: string, variantName: string?): {[string]: any}
	-- Start with defaults
	local ac = {}
	for k, v in pairs(DEFAULT_AGGRO_CURVE) do ac[k] = v end

	-- Layer 1: personality AggroCurve
	local pCurve = personalityTable.AggroCurve
	if type(pCurve) == "table" then
		for k, v in pairs(pCurve) do ac[k] = v end
	end

	-- Layer 2: per-brainrot AggroCurveOverrides
	local bCfg = getBrainrotConfig()
	local bEntry = bCfg[brainrotName]
	if bEntry and type(bEntry.AggroCurveOverrides) == "table" then
		for k, v in pairs(bEntry.AggroCurveOverrides) do ac[k] = v end
	end

	-- Layer 3: variant AggroCurveOverrides
	if variantName and bEntry and type(bEntry.Variants) == "table" then
		for _, variant in ipairs(bEntry.Variants) do
			if variant.Name == variantName then
				if type(variant.VariantAggroCurveOverrides) == "table" then
					for k, v in pairs(variant.VariantAggroCurveOverrides) do ac[k] = v end
				end
				break
			end
		end
	end

	return ac
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

	-- Leash radius: territory half-diagonal + buffer %, or personality default for non-territory
	local terrSpan = terr and math.max(terr.Size.X, terr.Size.Z) or 60
	local leashPct = pNumber(P, "TerritoryLeashPct", 0.20)
	local leashRadius = (terrSpan * 0.5) + (terrSpan * leashPct)
	-- Fallback: ensure at least the personality's absolute LeashRadius
	local configLeash = pNumber(P, "LeashRadius", self.Config.DefaultLeashRadius)
	if not terr then leashRadius = configLeash end

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
		FleeZigDir = 1,
		FleeNextZig = 0,
		_fleeCommitted = false,

		WanderTarget = nil,
		ReturnTarget = nil,

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
		SafeZones = getZoneSafeZones(zoneName),
		ConsecutiveIdles = 0,
		ReturnCooldownUntil = 0,
		StuckTicks = 0,
		StuckHopStage = 0,
		LastHopAt = 0,

		-- Pack hunt angle (nil = not a pack wolf)
		HuntAngle = nil,

		-- Aggro meter
		Aggro = 0,
		AggroLockedUntil = 0,
		AC = {},  -- filled below

		Conn = {},
	}

	-- Init locomotion
	if locomotion and type(locomotion.Init) == "function" then
		locomotion:Init(entry)
	end

	-- Init attack state
	AttackRegistry:InitEntry(entry)

	-- Resolve aggro curve (reuse variantName from line 576)
	entry.AC = resolveAggroCurve(P, brainrotName, variantName)
	entry.Aggro = entry.AC.IdleAggro or 0

	-- Pack wolves get a random hunt angle for approach direction
	local bCfgPack = getBrainrotConfig()[brainrotName]
	if bCfgPack and type(bCfgPack.PackBehavior) == "table" and bCfgPack.PackBehavior.Enabled then
		entry.HuntAngle = math.random() * math.pi * 2
	end

	-- Ambush brainrots: flag for ambush state machine
	if P.AmbushBehavior then
		entry.IsAmbush = true
	end

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
	if entry.IsAmbush then
		self:_setState(entry, "SeekHide")
	else
		self:_setState(entry, "Idle")
	end
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
		entry.ReturnTarget = nil
		entry.WaitEdgeZone = nil
		entry._isFidget = nil
		entry.Humanoid.WalkSpeed = 0
		if entry.Locomotion and type(entry.Locomotion.Stop) == "function" then
			entry.Locomotion:Stop(entry)
		end
		-- Cancel any pending MoveTo so Humanoid fully stops
		if entry.HRP then
			pcall(function() entry.Humanoid:MoveTo(entry.HRP.Position) end)
		end
		entry.Humanoid:Move(Vector3.zero, false)
		safeSetAnim(entry, "Idle")
	elseif state == "Wander" then
		entry.Target = nil
		safeSetAnim(entry, "Walk")
	elseif state == "Chase" then
		if entry.IsAmbush then
			-- Defensive cleanup: ensure not stuck anchored from a hiding state
			cancelAmbushTween(entry)
			if entry.HRP and entry.HRP.Parent then entry.HRP.Anchored = false end
			entry.Model:SetAttribute("HideBillboard", false)
		end
		safeSetAnim(entry, "Run")
	elseif state == "Attack" then
		safeSetAnim(entry, "Attack")
	elseif state == "Flee" then
		if entry.IsAmbush then
			-- Defensive cleanup: ensure not stuck anchored from a hiding state
			cancelAmbushTween(entry)
			if entry.HRP and entry.HRP.Parent then entry.HRP.Anchored = false end
			entry.Model:SetAttribute("HideBillboard", false)
		end
		safeSetAnim(entry, "Run")
	elseif state == "Return" then
		entry.Target = nil
		entry.WanderTarget = nil
		entry.ReturnTarget = nil
		entry.WaitEdgeZone = nil
		safeSetAnim(entry, "Walk")
	elseif state == "WaitAtEdge" then
		entry.Humanoid.WalkSpeed = 0
		entry.Humanoid:Move(Vector3.zero, false)
		safeSetAnim(entry, "Idle")
	elseif state == "SeekHide" then
		entry.Target = nil
		-- Full ambush state cleanup: cancel tweens, unanchor, release tree side
		cancelAmbushTween(entry)
		if entry.HRP and entry.HRP.Parent then entry.HRP.Anchored = false end
		releaseTreeSide(entry.HideSpot, entry.Id)
		entry.HideSpot = nil
		entry.HideType = nil
		entry.HideTreeSide = nil
		entry._popping = nil
		entry._popNextState = nil
		entry.OriginalCFrame = nil
		entry.Model:SetAttribute("HideBillboard", false)
		safeSetAnim(entry, "Run")
	elseif state == "HideTree" then
		entry.Humanoid.WalkSpeed = 0
		if entry.Locomotion and type(entry.Locomotion.Stop) == "function" then
			entry.Locomotion:Stop(entry)
		end
		entry.Model:SetAttribute("HideBillboard", true)
		safeSetAnim(entry, "Climb") -- climbing up; switches to Idle after tween done
	elseif state == "HideUnderground" then
		entry.Humanoid.WalkSpeed = 0
		if entry.Locomotion and type(entry.Locomotion.Stop) == "function" then
			entry.Locomotion:Stop(entry)
		end
		entry.Model:SetAttribute("HideBillboard", true)
		safeSetAnim(entry, "None") -- no animation while buried underground
	elseif state == "Grab" then
		entry.Humanoid.WalkSpeed = 0
		if entry.Locomotion and type(entry.Locomotion.Stop) == "function" then
			entry.Locomotion:Stop(entry)
		end
		safeSetAnim(entry, "Grab") -- looped hold animation while grabbing
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

	-- Ambush brainrots: flee from hiding when shot
	if entry.IsAmbush and (entry.State == "HideTree" or entry.State == "HideUnderground") then
		cancelAmbushTween(entry)

		if entry.State == "HideUnderground" then
			-- Shot underground: start pop tween (stay anchored), flee after pop
			if entry.OriginalCFrame and entry.HRP and entry.HRP.Parent then
				startAmbushTween(entry, entry.OriginalCFrame, TWEEN_POP_TIME)
				entry._popping = true
				-- Set flee info so evaluator picks it up after pop
				local plr = select(1, pickNearestPlayer(entry.OriginalCFrame.Position, 200))
				entry.FleeFrom = plr
				entry.FleeUntil = now() + TWEEN_POP_TIME + pNumber(entry.P, "FearTime", 3.0)
				entry._fleeCommitted = true
				entry._popNextState = "Flee"
			end
			entry.HideSpot = nil
			entry.HideType = nil
			-- Stay in HideUnderground — evaluator handles pop→unanchor→Flee
			return
		end

		-- Shot in tree: unanchor for physics freefall (no teleport!)
		if entry.State == "HideTree" then
			releaseTreeSide(entry.HideSpot, entry.Id)
			if entry.HRP then entry.HRP.Anchored = false end
			entry.HideTreeSide = nil
		end
		entry.HideSpot = nil
		entry.HideType = nil
		-- Flee!
		local plr = select(1, pickNearestPlayer(entry.HRP.Position, 200))
		entry.FleeFrom = plr
		entry.FleeUntil = now() + pNumber(entry.P, "FearTime", 3.0)
		entry._fleeCommitted = true
		self:_setState(entry, "Flee")
		return
	end

	-- Ambush brainrots in Grab: ignore damage, do NOT flee or change state
	if entry.IsAmbush and entry.State == "Grab" then
		return
	end

	-- Ambush brainrots exposed (Chase, SeekHide, etc.): very skittish, always flee on damage
	if entry.IsAmbush and entry.State ~= "Flee" then
		local plr = select(1, pickNearestPlayer(entry.HRP.Position, 200))
		entry.FleeFrom = plr
		entry.Target = nil
		entry.FleeUntil = now() + pNumber(entry.P, "FearTime", 3.0)
		entry._fleeCommitted = true
		self:_setState(entry, "Flee")
		return
	end

	-- Baby protection: if this is a baby-tier brainrot, rally the whole pack
	local sizeTier = entry.Model and entry.Model:GetAttribute("SizeTier")
	if sizeTier == "baby" or sizeTier == "small" then
		self:_signalBabyProtection(entry)
	end

	local ac = entry.AC
	local P = entry.P

	-- Boost aggro from damage
	local gain = ac and ac.DamageGain or 20

	-- Cornered bonus: extra aggro when low HP
	if entry.ThreatLevel > 0.7 then
		gain = gain + (ac and ac.CorneredRate or 8) * 2
	end

	entry.Aggro = math.clamp((entry.Aggro or 0) + gain, 0, 100)

	-- Wide search radius for finding attacker
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

	local fleeInversion = ac and ac.FleeInversion
	local fleeThreshold = ac and ac.FleeThreshold or 20
	local chaseThreshold = ac and ac.ChaseThreshold or 35

	-- If currently fleeing, don't re-evaluate
	if entry.State == "Flee" and now() < entry.FleeUntil then
		return
	end

	-- FleeInversion (Fearful-type): high aggro = flee, not fight
	if fleeInversion then
		if entry.Aggro >= fleeThreshold then
			doFlee()
			self:_signalPack(entry, "Flee")
			return
		end
	end

	-- Above chase threshold: retaliate (chase)
	if entry.Aggro >= chaseThreshold then
		if doChase() then
			self:_signalPack(entry, "Chase", entry.Target)
			return
		end
	end

	-- Between flee threshold and chase threshold: chance to flee
	if entry.Aggro >= fleeThreshold and not fleeInversion then
		local runChance = pNumber(P, "RunWhenAttacked", 0.25)
		if math.random() < runChance then
			doFlee()
			self:_signalPack(entry, "Flee")
			return
		end
		-- Didn't flee, try to chase anyway (retaliation on damage)
		local retaliates = P.RetaliateOnDamage
		if retaliates == nil then retaliates = true end
		if retaliates then
			if doChase() then
				self:_signalPack(entry, "Chase", entry.Target)
				return
			end
		end
	end

	-- Guaranteed fallback: never just stand there after being hit
	if entry.State == "Idle" or entry.State == "Wander" then
		doFlee(1.5)
	end
end

----------------------------------------------------------------------
-- Pack behavior signaling
----------------------------------------------------------------------

function AIService:_signalBabyProtection(entry: AIEntry, attacker: Player?)
	-- When a baby is damaged, ALL same-species pack members go max aggro
	local brainrotName = tostring(entry.Model:GetAttribute("BrainrotName") or "Default")
	local allCfg = getBrainrotConfig()
	local bCfg = allCfg[brainrotName]
	if not bCfg or type(bCfg.PackBehavior) ~= "table" then return end
	if not bCfg.PackBehavior.ProtectBaby then return end

	local signalFrac = bCfg.PackBehavior.SignalRange or 0.5
	local radius = 30
	if entry.Territory then
		local tSize = entry.Territory.Size
		radius = math.max(tSize.X, tSize.Z) * signalFrac
	end

	-- Find attacker (nearest player) if not provided
	if not attacker then
		attacker = select(1, pickNearestPlayer(entry.HRP.Position, radius * 2))
	end
	if not attacker then return end

	dprint("BABY PROTECTION! All", brainrotName, "rage toward", attacker.Name)

	for _, other in pairs(self._active) do
		if other.Id == entry.Id then continue end
		if other.State == "Dead" then continue end
		if other.ZoneName ~= entry.ZoneName then continue end
		if not other.HRP or not other.HRP.Parent then continue end
		-- Must be same species
		local otherName = tostring(other.Model:GetAttribute("BrainrotName") or "Default")
		if otherName ~= brainrotName then continue end

		local dist = (other.HRP.Position - entry.HRP.Position).Magnitude
		if dist > radius then continue end

		-- 100% join — no randomness, full rage
		other.Aggro = 100
		other.AggroLockedUntil = now() + 5  -- 5 seconds of pure rage, no decay
		other.Target = attacker
		self:_setState(other, "Chase")
	end
end

function AIService:_signalPack(entry: AIEntry, newState: string, target: Player?)
	-- Baby/small variants can't rally the pack — they flee alone
	-- (they trigger ProtectBaby instead, handled in _onDamaged)
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

	-- Signal nearby same-species brainrots
	for _, other in pairs(self._active) do
		if other.Id == entry.Id then continue end
		if other.State == "Dead" then continue end
		if other.ZoneName ~= entry.ZoneName then continue end
		if not other.HRP or not other.HRP.Parent then continue end
		local dist = (other.HRP.Position - entry.HRP.Position).Magnitude
		if dist > radius then continue end

		if newState == "Chase" and target then
			-- Already chasing? Just boost aggro, don't interrupt movement
			if other.State == "Chase" or other.State == "Attack" then
				local otherAC = other.AC
				local packGain = otherAC and otherAC.PackGain or 30
				other.Aggro = math.clamp((other.Aggro or 0) + packGain, 0, 100)
				continue
			end

			-- Smaller wolf can't rally a bigger wolf — only boost aggro
			local otherSizeMult = other.SizeMultiplier or 1
			local senderSizeMult = entry.SizeMultiplier or 1
			if senderSizeMult < otherSizeMult then
				local otherAC = other.AC
				local packGain = otherAC and otherAC.PackGain or 30
				other.Aggro = math.clamp((other.Aggro or 0) + packGain * 0.5, 0, 100)
				continue
			end

			-- Idle/Wander wolf gets rallied into chase
			local otherAC = other.AC
			local packGain = otherAC and otherAC.PackGain or 30
			other.Aggro = math.clamp((other.Aggro or 0) + packGain, 0, 100)
			other.Target = target
			other.HuntAngle = math.random() * math.pi * 2
			self:_setState(other, "Chase")

		elseif newState == "Flee" then
			if other.State ~= "Flee" then
				local otherAC = other.AC
				local packGain = otherAC and otherAC.PackGain or 30
				other.Aggro = math.clamp((other.Aggro or 0) + packGain * 0.5, 0, 100)
				other.FleeFrom = entry.FleeFrom
				other.FleeUntil = now() + pNumber(other.P, "FearTime", 2.5)
				self:_setState(other, "Flee")
			end
		end
	end
end

-- Returns how far (studs) this entry is beyond its territory edge.
-- Returns 0 if inside territory, nil if no territory.
function AIService:_overshootDistance(entry: AIEntry): number?
	local terr = entry.Territory
	if not terr then return nil end
	if isInsideTerritoryXZ(terr, entry.HRP.Position) then return 0 end

	local localPos = terr.CFrame:PointToObjectSpace(entry.HRP.Position)
	local halfX, halfZ = terr.Size.X * 0.5, terr.Size.Z * 0.5
	local overX = math.max(0, math.abs(localPos.X) - halfX)
	local overZ = math.max(0, math.abs(localPos.Z) - halfZ)
	return math.sqrt(overX * overX + overZ * overZ)
end

function AIService:_shouldReturn(entry: AIEntry): boolean
	local terr = entry.Territory
	local ac = entry.AC

	if not terr then
		local d = (entry.HRP.Position - entry.SpawnPos).Magnitude
		return d > entry.LeashRadius
	end

	local overshoot = self:_overshootDistance(entry) or 0

	-- Inside territory or within dead zone — never return
	if overshoot < 5 then
		return false
	end

	-- Aggro-based return: if calm (below chase threshold), always return when outside
	local chaseThreshold = ac and ac.ChaseThreshold or 35
	if entry.Aggro < chaseThreshold then
		return true
	end

	-- Above berserk threshold: never return (full rage, ignores leash)
	local berserkThreshold = ac and ac.BerserkThreshold or 85
	if entry.Aggro >= berserkThreshold then
		return false
	end

	-- Between chase and berserk: gradient based on aggro level and overshoot
	local span = math.max(terr.Size.X, terr.Size.Z)
	local leashPct = pNumber(entry.P, "TerritoryLeashPct", 0.25)
	local maxBuffer = math.max(span * leashPct, 15)

	local effectiveOvershoot = overshoot - 5
	local effectiveMax = math.max(maxBuffer - 5, 1)
	local distRatio = math.min(effectiveOvershoot / effectiveMax, 1.5)

	-- Higher aggro = less likely to return. Scale return chance inversely with aggro.
	local pursuitThreshold = ac and ac.PursuitThreshold or 60
	local aggroFactor = 1 - math.clamp((entry.Aggro - chaseThreshold) / (pursuitThreshold - chaseThreshold), 0, 1)
	local returnChance = distRatio * aggroFactor * 0.5
	return math.random() < returnChance
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
		-- SafeZone pull: chance to wander toward a SafeZone (default 25%, configurable via SafeZonePull)
		-- Higher values make brainrots stay closer to their den (wolves use ~70%)
		local safeZonePull = pNumber(entry.P, "SafeZonePull", 0.25)
		if #entry.SafeZones > 0 and math.random() < safeZonePull then
			local sz = entry.SafeZones[math.random(1, #entry.SafeZones)]
			local pt = randomPointInSafeZone(sz, y)
			if not ExclusionZoneManager:IsBlocked(pt, 1) then
				return pt
			end
		end

		-- Bias wander points toward center (inner 80%) to avoid edge-hugging.
		-- If brainrot is already near the edge, bias even more toward center.
		local localPos = terr.CFrame:PointToObjectSpace(entry.HRP.Position)
		local halfX, halfZ = terr.Size.X * 0.5, terr.Size.Z * 0.5
		local edgeFrac = math.max(math.abs(localPos.X) / halfX, math.abs(localPos.Z) / halfZ)
		-- Near center (edgeFrac<0.5): use 80% of territory. Near edge (edgeFrac>0.8): use 50%.
		local shrink = if edgeFrac > 0.8 then 0.5 elseif edgeFrac > 0.5 then 0.65 else 0.80

		-- Try up to 5 times to find a point not in an exclusion zone
		for _ = 1, 5 do
			local cf = terr.CFrame
			local size = terr.Size
			local rx = (math.random() - 0.5) * size.X * shrink
			local rz = (math.random() - 0.5) * size.Z * shrink
			local pp = (cf * CFrame.new(rx, 0, rz)).Position
			local p = Vector3.new(pp.X, y, pp.Z)
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

-- Pick a short fidget point: 3-6 studs from current position, stays in territory
function AIService:_pickFidgetPoint(entry: AIEntry): Vector3
	local hrp = entry.HRP
	local y = territoryY(entry.Territory, hrp.Position.Y)
	local dist = 3 + math.random() * 3 -- 3-6 studs
	local angle = math.random() * math.pi * 2
	local target = Vector3.new(
		hrp.Position.X + math.cos(angle) * dist,
		y,
		hrp.Position.Z + math.sin(angle) * dist
	)
	-- If we have a territory, clamp inside it
	local terr = entry.Territory
	if terr then
		local localP = terr.CFrame:PointToObjectSpace(target)
		local hx, hz = terr.Size.X * 0.45, terr.Size.Z * 0.45
		localP = Vector3.new(
			math.clamp(localP.X, -hx, hx),
			localP.Y,
			math.clamp(localP.Z, -hz, hz)
		)
		local world = terr.CFrame:PointToWorldSpace(localP)
		target = Vector3.new(world.X, y, world.Z)
	end
	return target
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
-- Aggro meter update (per-tick)
--//////////////////////////////

function AIService:_updateAggro(entry: AIEntry, dt: number)
	if entry.State == "Dead" then return end
	local ac = entry.AC
	if not ac then return end

	local t = now()

	-- Aggro lock (baby protection): no decay while locked
	if t < (entry.AggroLockedUntil or 0) then return end

	local pos = entry.HRP.Position
	local idleAggro = ac.IdleAggro or 0
	local aggro = entry.Aggro

	-- === SOURCES (increase aggro) ===

	-- Proximity: player within AggroDistance
	local aggroDist = pNumber(entry.P, "AggroDistance", self.Config.DefaultDetection)
	local nearPlayer, nearDist = pickNearestPlayer(pos, aggroDist)
	if nearPlayer then
		aggro = aggro + (ac.ProximityRate or 15) * dt

		-- Territory intrusion: player inside OUR territory (extra aggro)
		if entry.Territory then
			local thrp = getCharHRP(nearPlayer)
			if thrp and isInsideTerritoryXZ(entry.Territory, thrp.Position) then
				aggro = aggro + (ac.TerritoryRate or 5) * dt
			end
		end
	end

	-- Cornered: low HP boost
	if entry.ThreatLevel > 0.7 then
		aggro = aggro + (ac.CorneredRate or 8) * dt
	end

	-- === DRAINS (decrease aggro) ===

	local decay = (ac.DecayRate or 3.0) * dt

	-- Territory drain: faster decay when outside territory
	local overshoot = self:_overshootDistance(entry)
	if overshoot and overshoot > 5 then
		local territoryMult = ac.TerritoryDecayMult or 2.0
		local span = getTerritorySpan(entry)
		local overshootRatio = math.min(overshoot / math.max(span * 0.5, 20), 2.0)
		decay = decay + (ac.DecayRate or 3.0) * territoryMult * overshootRatio * dt
	end

	-- Out-of-sight drain: no valid target or target beyond chase range
	local chaseRange = pNumber(entry.P, "ChaseRange", self.Config.DefaultChaseRange)
	local hasVisibleTarget = false
	if entry.Target then
		local thrp = getCharHRP(entry.Target)
		if thrp then
			local d = (thrp.Position - pos).Magnitude
			if d <= chaseRange then hasVisibleTarget = true end
		end
	end
	if not hasVisibleTarget then
		decay = decay + (ac.OutOfSightDecay or 5) * dt
	end

	-- Accelerated decay after no damage for a while
	local sinceLastDamage = t - entry.LastDamagedAt
	if sinceLastDamage > (ac.DecayDelay or 4) then
		decay = decay * (ac.AccelDecayMult or 2.0)
	end

	-- Apply decay toward IdleAggro (not below)
	if aggro > idleAggro then
		aggro = math.max(idleAggro, aggro - decay)
	end

	entry.Aggro = math.clamp(aggro, 0, 100)
end

--//////////////////////////////
-- Main evaluator
--//////////////////////////////

function AIService:_stepAll()
	for id, entry in pairs(self._active) do
		if entry.Model.Parent == nil then
			self._active[id] = nil
		else
			self:_updateAggro(entry, self.Config.TickRate or 0.1)
			self:_stepOne(entry)
			self:_velocityAnimCheck(entry)
			self:_stuckHopCheck(entry)
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

	-- Scale attack range by size — bigger brainrots reach farther, smaller ones reach less
	local sizeMult = entry.SizeMultiplier or 1
	if sizeMult ~= 1 then
		attackRange = attackRange * sizeMult
	end

	local aggroDist = pNumber(entry.P, "AggroDistance", self.Config.DefaultDetection)
	local chaseRange = pNumber(entry.P, "ChaseRange", self.Config.DefaultChaseRange)
	local fearDist = pNumber(entry.P, "FearDistance", 40)
	local runMaxDist = pNumber(entry.P, "RunMaxDistance", 150)

	-- Determine effective attack range from available moves.
	-- Only expand to max move range for ranged-preference brainrots (sentries).
	-- Melee brainrots should chase until within base AttackRange (close up),
	-- and rely on PickMove to select gap-closers (Lunge) at longer range.
	local entryBrainrotName = tostring(entry.Model:GetAttribute("BrainrotName") or "Default")
	local prefersRanged = pNumber(entry.P, "PreferRanged", 0) >= 0.5
	if prefersRanged then
		local maxAttackRange = AttackRegistry:GetMaxRange(entry.AttackMoves, entryBrainrotName)
		if maxAttackRange > attackRange then
			attackRange = maxAttackRange
		end
	end

	-- Check if WE are in an exclusion zone (should leave ASAP)
	-- Skip for ambush brainrots while hiding (they're stationary and hidden)
	local selfInZone, selfZoneWeight = ExclusionZoneManager:Query(pos)
	if selfInZone and selfZoneWeight >= 50
		and entry.State ~= "HideTree" and entry.State ~= "HideUnderground" and entry.State ~= "Grab" then
		-- Get out! Move toward spawn/territory
		self:_setState(entry, "Return")
	end

	-- Return overrides neutral states (with cooldown to prevent ping-pong)
	-- Ambush states (HideTree, HideUnderground, SeekHide, Grab) are NOT interrupted by return
	if entry.State ~= "Return" and entry.State ~= "Chase" and entry.State ~= "Attack"
		and entry.State ~= "WaitAtEdge" and entry.State ~= "Flee"
		and entry.State ~= "HideTree" and entry.State ~= "HideUnderground"
		and entry.State ~= "SeekHide" and entry.State ~= "Grab" then
		if t >= (entry.ReturnCooldownUntil or 0) and self:_shouldReturn(entry) then
			self:_setState(entry, "Return")
		end
	end

	-- (Teleport rescue removed — leash is soft enough that brainrots
	-- naturally return on their own without forced teleportation)

	-- Acquire target on proximity (only in neutral states)
	if entry.State == "Idle" or entry.State == "Wander" then
		if not entry.Target then
			local near, nearDist = pickNearestPlayer(pos, aggroDist)
			if near then
				local ac = entry.AC
				local fleeInversion = ac and ac.FleeInversion
				local fleeThreshold = ac and ac.FleeThreshold or 20
				local chaseThreshold = ac and ac.ChaseThreshold or 35

				-- Fearful proximity flee: if player within FearDistance and aggro above flee threshold
				if fleeInversion and nearDist <= fearDist and entry.Aggro >= fleeThreshold then
					entry.FleeFrom = near
					entry.FleeUntil = now() + pNumber(entry.P, "FearTime", 2.5)
					self:_setState(entry, "Flee")
					self:_signalPack(entry, "Flee")

				-- Sentry behavior: Fearful + ranged brainrots attack from Idle
				elseif fleeInversion
					and pNumber(entry.P, "PreferRanged", 0) >= 0.8
					and nearDist <= attackRange
					and nearDist > fearDist then
					entry.Target = near
					self:_setState(entry, "Attack")

				-- Aggro threshold reached: chase
				elseif entry.Aggro >= chaseThreshold then
					local thrp = getCharHRP(near)
					if thrp then
						local inZone, zWeight, zone = checkTargetInExclusionZone(entry, thrp.Position)
						if inZone and zWeight >= 80 then
							-- Target in hard-blocked zone, don't chase
						else
							entry.Target = near
							self:_setState(entry, "Chase")
							self:_signalPack(entry, "Chase", near)
						end
					end
				end
			end
		end
	end

	---------- FLEE ----------
	if entry.State == "Flee" then
		entry.Humanoid.WalkSpeed = runSpeed

		-- Ambush opportunistic grab: if a player is within attack range while fleeing,
		-- 80% chance to grab them — assassins can't resist a close target
		if entry.IsAmbush and t >= entry.NextAttackAt then
			local near, nearD = pickNearestPlayer(pos, attackRange)
			if near and nearD <= attackRange and math.random() < 0.8 then
				entry.Target = near
				entry.FleeUntil = 0
				entry._fleeCommitted = nil
				self:_setState(entry, "Chase") -- will transition to Attack on next tick
				return
			end
		end

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
			-- Ambush brainrots: always go to SeekHide after flee
			if entry.IsAmbush then
				entry._fleeCommitted = nil
				entry.Target = nil
				self:_setState(entry, "SeekHide")
			-- Committed flee (FleeAfterAttack): always return, never re-chase
			elseif entry._fleeCommitted then
				entry._fleeCommitted = nil
				entry.Target = nil
				self:_setState(entry, "Return")
			elseif entry.Target then
				-- Normal flee (from damage): may re-chase if still angry
				local chaseThreshold = entry.AC and entry.AC.ChaseThreshold or 35
				if entry.Aggro >= chaseThreshold then
					local thrpCheck = getCharHRP(entry.Target)
					local thumCheck = entry.Target.Character and entry.Target.Character:FindFirstChildOfClass("Humanoid")
					if thrpCheck and thumCheck and thumCheck.Health > 0 then
						self:_setState(entry, "Chase")
					else
						entry.Target = nil
						self:_setState(entry, "Return")
					end
				else
					self:_setState(entry, "Return")
				end
			else
				self:_setState(entry, "Return")
			end
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
		-- FleeInversion proximity flee: even while returning, flee if player gets close
		if entry.AC and entry.AC.FleeInversion then
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

		-- Pick a return target: prefer SafeZone (stronger pull when damaged),
		-- otherwise inner 60% of territory
		if not entry.ReturnTarget then
			local terr = entry.Territory
			local y = territoryY(terr, pos.Y)
			local usedSafeZone = false

			-- SafeZone pull for return: 60% chance normally, 90% if recently damaged
			if #entry.SafeZones > 0 then
				local recentlyDamaged = (now() - entry.LastDamagedAt) < 5
				local szChance = if recentlyDamaged then 0.90 else 0.60
				if math.random() < szChance then
					local sz = nearestSafeZone(entry.SafeZones, pos)
					if sz then
						entry.ReturnTarget = randomPointInSafeZone(sz, y)
						usedSafeZone = true
					end
				end
			end

			if not usedSafeZone then
				if terr then
					-- Pick a point in the inner 60% of territory (toward center)
					local cf = terr.CFrame
					local size = terr.Size
					local rx = (math.random() - 0.5) * size.X * 0.6
					local rz = (math.random() - 0.5) * size.Z * 0.6
					local p = (cf * CFrame.new(rx, 0, rz)).Position
					entry.ReturnTarget = Vector3.new(p.X, y, p.Z)
				else
					entry.ReturnTarget = Vector3.new(entry.SpawnPos.X, y, entry.SpawnPos.Z)
				end
			end
		end

		local returnPos = entry.ReturnTarget
		moveToward(entry, returnPos)
		safeSetAnim(entry, "Walk")

		-- Arrival check: reached return target OR back inside territory
		local dToTarget = math.sqrt(
			(returnPos.X - pos.X)^2 + (returnPos.Z - pos.Z)^2
		)
		local insideTerritory = entry.Territory and isInsideTerritoryXZ(entry.Territory, pos)
		if dToTarget <= 5 or insideTerritory then
			entry.ReturnTarget = nil
			entry.ReturnCooldownUntil = now() + 3 -- brief cooldown before leash re-checks
			self:_setState(entry, if entry.IsAmbush then "SeekHide" else "Idle")
		elseif not entry.Territory and (pos - entry.SpawnPos).Magnitude <= 12 then
			entry.ReturnTarget = nil
			entry.ReturnCooldownUntil = now() + 3
			self:_setState(entry, if entry.IsAmbush then "SeekHide" else "Idle")
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
			self:_setState(entry, if entry.IsAmbush then "SeekHide" else "Idle")
			return
		end

		local d = (thrp.Position - pos).Magnitude

		-- FleeInversion proximity flee: if target gets within FearDistance, abandon attack
		local fleeInversion = entry.AC and entry.AC.FleeInversion
		if fleeInversion and d <= fearDist then
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

		-- Pursuit break-off: if aggro has decayed below chase threshold, give up
		if entry.State == "Chase" and not inOwnTerritory then
			local chaseThreshold = entry.AC and entry.AC.ChaseThreshold or 35
			if entry.Aggro < chaseThreshold then
				entry.Target = nil
				self:_setState(entry, "Return")
				return
			end
		end

		-- Territory pull: aggro decays faster outside territory (_updateAggro handles this).
		-- If aggro drops below pursuit threshold outside territory, return.
		if not inOwnTerritory and not recentlyDamaged then
			local pursuitThreshold = entry.AC and entry.AC.PursuitThreshold or 60
			if entry.Aggro < pursuitThreshold then
				local overshoot = self:_overshootDistance(entry)
				if overshoot and overshoot > 10 then
					-- Probability scales with distance: further out = more likely to break off
					local span = getTerritorySpan(entry)
					local ratio = math.min(overshoot / math.max(span * 0.5, 20), 2.0)
					local breakChance = ratio * 0.15
					if math.random() < breakChance then
						entry.Target = nil
						self:_setState(entry, "Return")
						return
					end
				end
			end
		end

		-- Check if target is in an exclusion zone
		local tInZone, tZoneWeight, tZone = checkTargetInExclusionZone(entry, thrp.Position)
		if tInZone and tZoneWeight > 0 then
			local blocked = self:_handleExclusionZone(entry, thrp.Position, tZoneWeight, tZone)
			if blocked then return end
		end

		-- Gap-closer check: while chasing and beyond melee range, try to pick
		-- a heavy move (like Lunge) that can execute at current distance.
		-- This fires the gap-closer mid-chase without stopping to walk up first.
		if entry.State == "Chase" and d > attackRange and t >= entry.NextAttackAt then
			local moveName, moveMod, moveCfg = AttackRegistry:PickMove(
				entry, target, d, entry.P, entry.AttackMoves
			)
			if moveMod and moveCfg and (moveCfg.Weight == "Heavy") then
				local bName = tostring(entry.Model:GetAttribute("BrainrotName") or "Default")
				local vName = entry.Model:GetAttribute("VariantName")
				moveCfg = applyMoveOverrides(bName, moveName :: string, moveCfg, vName)

				local animName = "Attack"
				if moveCfg.AnimationKey then
					animName = "attack_" .. moveCfg.AnimationKey
				elseif type(moveMod.GetAnimationName) == "function" then
					animName = moveMod:GetAnimationName()
				end
				safeSetAnim(entry, animName)

				local cd = moveCfg.Cooldown or self.Config.DefaultAttackCooldown
				local effectiveMult = entry.Model:GetAttribute("EffectiveMultiplier")
				if typeof(effectiveMult) == "number" and effectiveMult > 0 then
					cd = cd / effectiveMult
				end
				entry.NextAttackAt = t + cd
				AttackRegistry:RecordUse(entry, moveName :: string)

				task.spawn(function()
					moveMod:Execute(entry, target, self.Services, moveCfg)
				end)
			end
		end

		-- Attack or chase (melee range)
		if d <= attackRange then
			-- Peek at move config to check for NoStop (drive-by attacks)
			local moveName, moveMod, moveCfg
			if t >= entry.NextAttackAt then
				moveName, moveMod, moveCfg = AttackRegistry:PickMove(
					entry, target, d, entry.P, entry.AttackMoves
				)
				if moveMod and moveCfg then
					local bName = tostring(entry.Model:GetAttribute("BrainrotName") or "Default")
					local vName = entry.Model:GetAttribute("VariantName")
					moveCfg = applyMoveOverrides(bName, moveName :: string, moveCfg, vName)
				end
			end

			local noStop = moveCfg and moveCfg.NoStop

			if noStop then
				-- Drive-by: stay in Chase, keep moving, fire damage without stopping
				self:_setState(entry, "Chase")
				entry.Humanoid.WalkSpeed = runSpeed
				safeSetAnim(entry, "Run")
				moveToward(entry, thrp.Position)
			else
				-- Normal: stop and attack
				self:_setState(entry, "Attack")
				entry.Humanoid.WalkSpeed = 0
				entry.Humanoid:Move(Vector3.zero, false)
				if entry.Locomotion and type(entry.Locomotion.Stop) == "function" then
					entry.Locomotion:Stop(entry)
				end
			end

			if moveMod and moveCfg then
				-- Set animation
				local animName = if noStop then "Run" else "Attack"
				if not noStop then
					if moveCfg.AnimationKey then
						animName = "attack_" .. moveCfg.AnimationKey
					elseif type(moveMod.GetAnimationName) == "function" then
						animName = moveMod:GetAnimationName()
					end
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

				-- Execute the attack
				-- NoStop (drive-by): execute synchronously so damage lands on the
				-- same tick the range check passes (frog moves fast, can't defer)
				-- Normal attacks: task.spawn since they may yield for windup
				if noStop then
					pcall(moveMod.Execute, moveMod, entry, target, self.Services, moveCfg)
				else
					task.spawn(function()
						moveMod:Execute(entry, target, self.Services, moveCfg)
					end)
				end

				-- Pack wolves: re-roll hunt angle so next approach comes from a different side
				if entry.HuntAngle then
					entry.HuntAngle = math.random() * math.pi * 2
				end

				-- FleeAfterAttack: hit-and-run — commit to flee, no waffling
				if moveCfg.FleeAfterAttack then
					entry.FleeFrom = target
					entry.Target = nil                 -- always clear target
					local fearTime = pNumber(entry.P, "FearTime", 2.5)
					entry.FleeUntil = now() + fearTime
					entry._fleeCommitted = true        -- flag: don't re-chase when flee ends
					-- Drop aggro below chase threshold so it doesn't re-acquire immediately
					local chaseThreshold = entry.AC and entry.AC.ChaseThreshold or 35
					entry.Aggro = math.min(entry.Aggro, chaseThreshold * 0.5)
					self:_setState(entry, "Flee")
				end
			elseif not noStop and t >= entry.NextAttackAt then
				-- No valid move, fallback to basic damage (only for stop-attacks)
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
		else
			-- Chase: move toward target
			self:_setState(entry, "Chase")
			entry.Humanoid.WalkSpeed = runSpeed
			safeSetAnim(entry, "Run")

			-- Pack wolves: offset target by HuntAngle so they approach from different sides
			if entry.HuntAngle then
				local y = territoryY(entry.Territory, pos.Y)
				local huntPos = Vector3.new(
					thrp.Position.X + math.cos(entry.HuntAngle) * HUNT_OFFSET,
					y,
					thrp.Position.Z + math.sin(entry.HuntAngle) * HUNT_OFFSET
				)
				moveToward(entry, huntPos)
			else
				moveToward(entry, thrp.Position)
			end
		end

		return
	end

	---------- AMBUSH STATES (SeekHide / HideTree / HideUnderground / Grab) ----------
	if entry.State == "SeekHide" then
		entry.Humanoid.WalkSpeed = runSpeed
		safeSetAnim(entry, "Run")

		-- Choose hide type: 4:1 favoring underground over tree
		local treeTag = entry.P.TreeTag or "Tree"
		if not entry.HideType then
			local roll = math.random(1, AMBUSH_DIG_WEIGHT + 1) -- 1-5: 1=tree, 2-5=dig
			if roll == 1 then
				-- Try to find a tree with an open side
				local bestTree: BasePart? = nil
				local bestDist = math.huge
				for _, tree in ipairs(CollectionService:GetTagged(treeTag)) do
					local treePart = if tree:IsA("Model") then tree.PrimaryPart else tree
					if treePart and treePart:IsA("BasePart") then
						-- Check if tree has open sides
						local occ = _treeSideOccupants[treePart]
						local usedCount = 0
						if occ then for _ in pairs(occ) do usedCount += 1 end end
						if usedCount < AMBUSH_MAX_PER_TREE then
							local d = (treePart.Position - pos).Magnitude
							if d < bestDist and d < 200 then
								bestDist = d
								bestTree = treePart
							end
						end
					end
				end
				if bestTree then
					entry.HideSpot = bestTree
					entry.HideType = "tree"
				else
					entry.HideType = "underground" -- no tree available, dig
				end
			else
				entry.HideType = "underground"
			end
		end

		if entry.HideType == "tree" and entry.HideSpot then
			local treePart = entry.HideSpot
			local dToTree = (Vector3.new(treePart.Position.X, pos.Y, treePart.Position.Z) - pos).Magnitude
			if dToTree <= 6 then
				-- Arrived at tree — claim a side
				local side = claimTreeSide(treePart, entry.Id)
				if not side then
					-- Tree full, dig instead
					entry.HideSpot = nil
					entry.HideType = "underground"
				else
					entry.HideTreeSide = side
					local hpLo, hpHi = pRange(entry.P, "HidePatience", 15, 30)
					entry.HideUntil = now() + randRange(hpLo, hpHi)
					if entry.HRP and entry.HRP.Parent then
						entry.HRP.Anchored = true
						-- Climb target: top of the claimed side (not center)
						local sideOffset = getTreeSideOffset(treePart, side)
						local treeTopSide = treePart.Position
							+ Vector3.new(0, treePart.Size.Y * 0.5 + 2, 0)
							+ sideOffset
						-- Face outward from tree
						local lookDir = sideOffset.Unit
						local targetCF = CFrame.new(treeTopSide, treeTopSide + lookDir)
						startAmbushTween(entry, targetCF, TWEEN_CLIMB_TIME)
					end
					self:_setState(entry, "HideTree")
				end
			else
				moveToward(entry, treePart.Position)
			end
			-- If we switched to underground above, fall through
			if entry.HideType == "tree" then return end
		end

		if entry.HideType == "underground" then
			-- Dig underground: anchor and start sink tween
			local hpLo2, hpHi2 = pRange(entry.P, "HidePatience", 15, 30)
			entry.HideUntil = now() + randRange(hpLo2, hpHi2)
			if entry.HRP and entry.HRP.Parent then
				-- Compute upright ground CFrame regardless of current orientation
				-- Raycast down to find the actual ground surface
				local hrpPos = entry.HRP.Position
				local rayOrigin = Vector3.new(hrpPos.X, hrpPos.Y + 10, hrpPos.Z)
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = { entry.Model }
				local rayResult = Workspace:Raycast(
					rayOrigin,
					Vector3.new(0, -100, 0),
					rayParams
				)
				local groundY = rayResult and rayResult.Position.Y or hrpPos.Y
				-- Place HRP center at ground level + half HRP height (standing on ground)
				local halfH = entry.HRP.Size.Y * 0.5
				local uprightPos = Vector3.new(hrpPos.X, groundY + halfH, hrpPos.Z)
				-- Keep the monkey's facing direction (yaw only), discard tilt/roll
				local lookDir = entry.HRP.CFrame.LookVector
				local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z)
				if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end
				flatLook = flatLook.Unit

				local uprightCF = CFrame.new(uprightPos, uprightPos + flatLook)
				entry.OriginalCFrame = uprightCF -- pop-back target is upright on ground

				entry.HRP.Anchored = true
				-- Sink 80% of HRP height below the upright ground position
				local sinkDepth = entry.HRP.Size.Y * 0.8
				local sunkCF = uprightCF - Vector3.new(0, sinkDepth, 0)
				startAmbushTween(entry, sunkCF, TWEEN_DIG_TIME)
			end
			self:_setState(entry, "HideUnderground")
		end
		return
	end

	if entry.State == "HideTree" then
		local treePart = entry.HideSpot
		if not treePart or not treePart.Parent then
			-- Tree removed, cancel tween, release side, unanchor, seek new spot
			cancelAmbushTween(entry)
			releaseTreeSide(entry.HideSpot, entry.Id)
			entry.HideSpot = nil
			entry.HideTreeSide = nil
			if entry.HRP then entry.HRP.Anchored = false end
			self:_setState(entry, "SeekHide")
			return
		end

		entry.Humanoid.WalkSpeed = 0

		-- Still climbing? Wait for tween to finish
		if entry.HideTween and not entry.HideTweenDone then
			return
		end

		-- Climb tween done — sitting at tree top, switch to Idle
		safeSetAnim(entry, "Idle")

		-- At tree side top — scan for players (horizontal range + directly below)
		local sideOffset = entry.HideTreeSide and getTreeSideOffset(treePart, entry.HideTreeSide) or Vector3.zero
		local hidePos = treePart.Position + Vector3.new(0, treePart.Size.Y * 0.5 + 2, 0) + sideOffset
		local ambushRange = pNumber(entry.P, "AmbushRange", 25)
		local near, nearDist = pickNearestPlayer(hidePos, ambushRange)
		-- Also detect players walking directly under the tree (XZ within tree footprint + padding)
		if not near then
			local treeBase = treePart.Position
			local padX = treePart.Size.X * 0.5 + 8 -- generous padding
			local padZ = treePart.Size.Z * 0.5 + 8
			for _, plr in ipairs(Players:GetPlayers()) do
				local phrp = getCharHRP(plr)
				if phrp then
					local dx = math.abs(phrp.Position.X - treeBase.X)
					local dz = math.abs(phrp.Position.Z - treeBase.Z)
					if dx <= padX and dz <= padZ and phrp.Position.Y < treeBase.Y + treePart.Size.Y * 0.5 then
						near = plr
						break
					end
				end
			end
		end
		if near then
			-- Jump off tree — physics freefall! Unanchor and let gravity do the work
			entry.Target = near
			entry.NextAttackAt = 0 -- attack IMMEDIATELY after landing
			releaseTreeSide(treePart, entry.Id)
			entry.HideSpot = nil
			entry.HideType = nil
			entry.HideTreeSide = nil
			cancelAmbushTween(entry)
			if entry.HRP and entry.HRP.Parent then
				entry.HRP.Anchored = false
			end
			self:_setState(entry, "Chase")
			return
		end

		-- Patience timer: freefall off tree, then relocate
		if t >= (entry.HideUntil or 0) then
			releaseTreeSide(treePart, entry.Id)
			entry.HideSpot = nil
			entry.HideType = nil
			entry.HideTreeSide = nil
			cancelAmbushTween(entry)
			if entry.HRP and entry.HRP.Parent then
				entry.HRP.Anchored = false
			end
			self:_setState(entry, "SeekHide")
		end
		return
	end

	if entry.State == "HideUnderground" then
		entry.Humanoid.WalkSpeed = 0

		-- Phase 1: Sinking tween playing — wait
		if entry.HideTween and not entry.HideTweenDone then
			return
		end

		-- Phase 2: Popping up — tween is playing back to surface (still anchored)
		-- _popTarget stores who/what triggered the pop so we know where to go after
		if entry._popping then
			-- Still tweening up? Wait
			if entry.HideTween and not entry.HideTweenDone then
				return
			end
			-- Pop tween finished — HRP is at OriginalCFrame, fully above ground
			-- NOW unanchor and transition
			if entry.HRP and entry.HRP.Parent then
				entry.HRP.Anchored = false
			end
			local nextState = entry._popNextState or "SeekHide"
			entry._popping = nil
			entry._popNextState = nil
			entry.OriginalCFrame = nil
			entry.HideSpot = nil
			entry.HideType = nil
			self:_setState(entry, nextState)
			return
		end

		-- Phase 3: Fully underground, waiting — only pop when player is VERY close
		-- Use AmbushPopRange (fraction of attackRange) for underground detection
		local popFraction = pNumber(entry.P, "AmbushPopRange", 0.5)
		local undergroundPopRange = attackRange * popFraction
		local scanPos = entry.OriginalCFrame and entry.OriginalCFrame.Position or pos
		local near, nearDist = pickNearestPlayer(scanPos, undergroundPopRange)
		if near then
			-- Start pop-out tween (stay anchored during tween)
			entry.Target = near
			entry.NextAttackAt = 0 -- attack IMMEDIATELY after popping out
			if entry.OriginalCFrame and entry.HRP and entry.HRP.Parent then
				cancelAmbushTween(entry)
				startAmbushTween(entry, entry.OriginalCFrame, TWEEN_POP_TIME)
				entry._popping = true
				entry._popNextState = "Chase"
			end
			return
		end

		-- Patience timer: pop out, then relocate
		if t >= (entry.HideUntil or 0) then
			if entry.OriginalCFrame and entry.HRP and entry.HRP.Parent then
				cancelAmbushTween(entry)
				startAmbushTween(entry, entry.OriginalCFrame, TWEEN_POP_TIME)
				entry._popping = true
				entry._popNextState = "SeekHide"
			end
		end
		return
	end

	if entry.State == "Grab" then
		-- GrabAttack module manages the grab loop. AI just waits.
		-- If grab ended (GrabTarget cleared by GrabAttack), transition out.
		if not entry.GrabTarget then
			-- Grab ended — flee to re-hide
			local near = pickNearestPlayer(pos, 100)
			if near then
				entry.FleeFrom = near
				entry.FleeUntil = now() + pNumber(entry.P, "FearTime", 3.0)
				entry._fleeCommitted = true
				local chaseThreshold = entry.AC and entry.AC.ChaseThreshold or 35
				entry.Aggro = math.min(entry.Aggro, chaseThreshold * 0.5)
				self:_setState(entry, "Flee")
			else
				self:_setState(entry, "SeekHide")
			end
		end
		return
	end

	---------- IDLE / WANDER ----------
	if entry.State == "Idle" then
		entry.Humanoid.WalkSpeed = 0
		entry.Humanoid:Move(Vector3.zero, false)

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
			local pick = "walk"
			if type(actions) == "table" and #actions > 0 then
				pick = tostring(actions[math.random(1, #actions)])
			end

			-- Cap consecutive idles: after 2 in a row, force a fidget or walk
			if pick == "idle" then
				entry.ConsecutiveIdles = (entry.ConsecutiveIdles or 0) + 1
				if entry.ConsecutiveIdles >= 2 then
					-- Force movement: 60% fidget, 40% full wander
					pick = if math.random() < 0.60 then "fidget" else "walk"
					entry.ConsecutiveIdles = 0
				end
			else
				entry.ConsecutiveIdles = 0
			end

			if pick == "walk" then
				local wp = self:_pickWanderPoint(entry)
				if entry.Locomotion and type(entry.Locomotion.AdjustWanderPoint) == "function" then
					wp = entry.Locomotion:AdjustWanderPoint(entry, wp)
				end
				entry.WanderTarget = wp
				self:_setState(entry, "Wander")
			elseif pick == "fidget" then
				-- Short micro-movement: 3-6 studs at half walk speed
				entry.WanderTarget = self:_pickFidgetPoint(entry)
				entry._isFidget = true
				self:_setState(entry, "Wander")
			else
				-- Stay idle, but use a shorter timer to keep things lively
				local lo, hi = pRange(entry.P, "IdleFrequency", self.Config.DefaultIdleMin, self.Config.DefaultIdleMax)
				-- Shorten idle pauses: use 40-70% of the configured range
				entry.NextThinkAt = t + randRange(lo * 0.4, hi * 0.7)
			end
		end
		return
	end

	if entry.State == "Wander" then
		local isFidget = entry._isFidget
		-- Fidgets use half walk speed for a casual shuffle
		entry.Humanoid.WalkSpeed = if isFidget then math.max(walkSpeed * 0.5, 4) else walkSpeed
		safeSetAnim(entry, "Walk")

		if not entry.WanderTarget then
			entry.WanderTarget = self:_pickWanderPoint(entry)
		end

		local dXZ = math.sqrt(
			(entry.WanderTarget.X - pos.X)^2 + (entry.WanderTarget.Z - pos.Z)^2
		)
		-- Fidgets arrive at 2 studs (shorter), normal wander at 3
		local arrivalDist = if isFidget then 2 else 3
		if dXZ <= arrivalDist then
			entry._isFidget = nil

			-- Locomotion modules can chain wander (e.g. RollLocomotion keeps driving)
			if not isFidget and entry.Locomotion
				and type(entry.Locomotion.ShouldChainWander) == "function"
				and entry.Locomotion:ShouldChainWander(entry)
			then
				local candidate = self:_pickWanderPoint(entry)
				-- Locomotion can adjust the point to avoid walls
				if type(entry.Locomotion.AdjustWanderPoint) == "function" then
					candidate = entry.Locomotion:AdjustWanderPoint(entry, candidate)
				end
				entry.WanderTarget = candidate
				return -- stay in Wander, no pause
			end

			local lo, hi = pRange(entry.P, "WanderPause", self.Config.DefaultWanderPauseMin, self.Config.DefaultWanderPauseMax)
			-- Fidgets have shorter pause after (quick settle)
			if isFidget then
				entry.NextThinkAt = t + randRange(lo * 0.5, hi * 0.5)
			else
				entry.NextThinkAt = t + randRange(lo, hi)
			end
			self:_setState(entry, "Idle")
		else
			moveToward(entry, entry.WanderTarget)
		end
		return
	end
end

-- Velocity-based animation override: if the brainrot is physically not moving
-- but has a movement animation playing, switch to Idle animation.
-- This catches stuck-on-wall, pathfinding failure, territory edge, etc.
local MOVE_VELOCITY_THRESHOLD = 1.0 -- studs/sec; below this = "not moving"

function AIService:_velocityAnimCheck(entry: AIEntry)
	if entry.State == "Dead" then return end

	-- Skip for hidden/grab states (brainrot is intentionally stationary)
	if entry.State == "HideTree" or entry.State == "HideUnderground" or entry.State == "Grab" then
		return
	end

	-- Locomotion modules can opt out of forced idle (e.g. RollLocomotion)
	local loco = entry.Locomotion
	if loco and type(loco.IsImmuneToForcedIdle) == "function" and loco:IsImmuneToForcedIdle() then
		return
	end

	local hrp = entry.HRP
	if not hrp then return end

	local sv = entry.CurrentAnimation
	if not sv then return end
	local currentAnim = sv.Value

	-- Only override movement animations (Walk, Run)
	if currentAnim ~= "Walk" and currentAnim ~= "Run" then return end

	-- Don't switch to Idle if we're mid-hop — the brainrot is still trying to move,
	-- just physically stuck. The hop system will handle it.
	if (entry.StuckHopStage or 0) > 0 then return end
	-- Also skip if we just hopped recently (still in the air / landing)
	if now() - (entry.LastHopAt or 0) < 0.5 then return end

	-- Check actual velocity (XZ plane only, ignore Y for jumps/slopes)
	local vel = hrp.AssemblyLinearVelocity
	local xzSpeed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)

	if xzSpeed < MOVE_VELOCITY_THRESHOLD then
		-- Locomotion modules can request a delay before forcing idle
		-- (prevents flicker during direction changes, catches real stops)
		local delay = 0
		if loco and type(loco.GetForcedIdleDelay) == "function" then
			delay = loco:GetForcedIdleDelay()
		end

		if delay > 0 then
			entry._forcedIdleTicks = (entry._forcedIdleTicks or 0) + 1
			if entry._forcedIdleTicks < delay then
				return -- not stuck long enough yet
			end
		end

		safeSetAnim(entry, "Idle")
	else
		entry._forcedIdleTicks = 0
	end
end

--//////////////////////////////
-- Stuck-hop escalation system
--//////////////////////////////
-- When a brainrot is trying to move but stuck (near-zero XZ velocity),
-- escalate through increasingly powerful hops to clear obstacles.
-- Stage 0 → baby hop (clears seams/lips)
-- Stage 1 → medium hop (clears small ledges)
-- Stage 2 → big hop (clears larger obstacles)
-- Stage 3 → give up on current path, pick new destination

local STUCK_TICKS_BABY    = 8   -- 0.8s stuck → tiny pop (clears <1 stud)
local STUCK_TICKS_MEDIUM  = 16  -- 1.6s still stuck → medium hop
local STUCK_TICKS_BIG     = 25  -- 2.5s still stuck → big hop
local STUCK_TICKS_REPATH  = 35  -- 3.5s still stuck → abandon path
local HOP_COOLDOWN        = 2.0 -- seconds between hops

-- Hop power per stage (JumpPower values)
-- Stage 1 is a tiny pop — just enough to clear a seam/lip
local HOP_POWERS = { 10, 30, 50 } -- tiny pop, medium, big

-- Movement states where stuck-hop applies
local MOVEMENT_STATES: { [AIStateName]: boolean } = {
	Wander = true,
	Chase = true,
	Flee = true,
	Return = true,
	SeekHide = true,
}

function AIService:_stuckHopCheck(entry: AIEntry)
	if entry.State == "Dead" then return end
	local hrp = entry.HRP
	if not hrp then return end

	-- Only check during movement states
	if not MOVEMENT_STATES[entry.State] then
		entry.StuckTicks = 0
		entry.StuckHopStage = 0
		return
	end

	-- Skip flying brainrots
	if isFlying(entry) then return end

	-- Check XZ velocity
	local vel = hrp.AssemblyLinearVelocity
	local xzSpeed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)

	if xzSpeed >= MOVE_VELOCITY_THRESHOLD then
		-- Moving fine — reset stuck state
		entry.StuckTicks = 0
		entry.StuckHopStage = 0
		return
	end

	-- Stuck: increment counter
	entry.StuckTicks = (entry.StuckTicks or 0) + 1

	-- Locomotion override: some modules handle stuck themselves (e.g. RollLocomotion reverses)
	local loco = entry.Locomotion
	if loco and type(loco.OnStuck) == "function" then
		if entry.StuckTicks >= 4 then -- ~0.4s stuck
			if loco:OnStuck(entry) then
				entry.StuckTicks = 0
				entry.StuckHopStage = 0
				entry.LastHopAt = now()
				return -- locomotion handled it, skip hop logic
			end
			-- OnStuck failed — fall through to normal hop system as fallback
		else
			return -- not stuck long enough for OnStuck yet, skip hop too
		end
	end

	-- Cooldown check
	if now() - (entry.LastHopAt or 0) < HOP_COOLDOWN then
		return
	end

	local hum = entry.Humanoid

	-- Stage 3: repath — give up on current destination entirely
	if entry.StuckTicks >= STUCK_TICKS_REPATH then
		entry.StuckTicks = 0
		entry.StuckHopStage = 0
		entry.LastHopAt = now()

		-- Force a new path by clearing current target and re-entering state
		if entry.State == "Wander" then
			local wp = self:_pickWanderPoint(entry)
			if entry.Locomotion and type(entry.Locomotion.AdjustWanderPoint) == "function" then
				wp = entry.Locomotion:AdjustWanderPoint(entry, wp)
			end
			entry.WanderTarget = wp
			if entry.Locomotion and type(entry.Locomotion.Stop) == "function" then
				entry.Locomotion:Stop(entry)
			end
		elseif entry.State == "Return" then
			entry.ReturnTarget = nil -- will be re-picked next tick
			if entry.Locomotion and type(entry.Locomotion.Stop) == "function" then
				entry.Locomotion:Stop(entry)
			end
		end
		-- Chase/Flee: target is a player, path will recompute automatically
		-- via locomotion's MoveTo on next tick
		dprint(entry.Id, "stuck repath — giving up on current path")
		return
	end

	-- Determine which hop stage to attempt
	local stage = 0
	if entry.StuckTicks >= STUCK_TICKS_BIG then
		stage = 3
	elseif entry.StuckTicks >= STUCK_TICKS_MEDIUM then
		stage = 2
	elseif entry.StuckTicks >= STUCK_TICKS_BABY then
		stage = 1
	end

	-- Only hop if we haven't already done this stage
	if stage > 0 and stage > (entry.StuckHopStage or 0) then
		local basePower = HOP_POWERS[stage] or 50

		-- Per-brainrot hop multiplier (e.g. Garamararam = 0.7 for lower hops)
		local hopMult = 1.0
		local brainrotCfg = getBrainrotConfig()
		local bCfg = brainrotCfg[entry.BrainrotName]
		if bCfg and bCfg.StuckHopMult then
			hopMult = bCfg.StuckHopMult
		end

		local hopPower = basePower * hopMult

		-- Apply hop via Humanoid.Jump with temporary JumpPower override
		local origJumpPower = hum.JumpPower
		local origUseJumpPower = hum.UseJumpPower
		hum.UseJumpPower = true
		hum.JumpPower = hopPower
		hum.Jump = true

		-- Restore on next frame
		task.defer(function()
			if hum and hum.Parent then
				hum.JumpPower = origJumpPower
				hum.UseJumpPower = origUseJumpPower
			end
		end)

		entry.StuckHopStage = stage
		entry.LastHopAt = now()
		dprint(entry.Id, "stuck hop stage", stage, "power", hopPower)
	end
end

return AIService
