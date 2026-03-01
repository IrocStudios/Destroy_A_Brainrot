--!strict
-- AIService
-- Server-side behavior controller for brainrots spawned by BrainrotService.
-- Uses PersonalityConfig to decide roam/chase/flee/attack, and sets CurrentAnimation (replicated to clients).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

type Services = { [string]: any }

type AIStateName = "Idle" | "Wander" | "Chase" | "Attack" | "Flee" | "Return" | "Dead"

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

	Conn: { RBXScriptConnection },
}

local AIService = {}

--//////////////////////////////
-- Config loaders
--//////////////////////////////

local function getPersonalityConfig()
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local cfg = shared:WaitForChild("Config")
	return require(cfg:WaitForChild("PersonalityConfig"))
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

	local spawnPos = hrp.Position
	local leashRadius = pNumber(P, "LeashRadius", self.Config.DefaultLeashRadius)

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

		Conn = {},
	}

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
		entry.Humanoid.WalkSpeed = 0
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
		safeSetAnim(entry, "Walk")
	elseif state == "Dead" then
		entry.Target = nil
		entry.WanderTarget = nil
		entry.Humanoid.WalkSpeed = 0
		safeSetAnim(entry, "Dead")
	end
end

function AIService:_onDamaged(entry: AIEntry)
	if entry.State == "Dead" then return end

	local attackChance = pNumber(entry.P, "AttackChance", 0.10)
	local runChance = pNumber(entry.P, "RunWhenAttacked", pNumber(entry.P, "RunChance", 0.25))

	if entry.State == "Flee" and now() < entry.FleeUntil then
		return
	end

	if math.random() < runChance then
		local aggroDist = pNumber(entry.P, "AggroDistance", self.Config.DefaultDetection)
		local plr = select(1, pickNearestPlayer(entry.HRP.Position, aggroDist))
		entry.FleeFrom = plr
		entry.FleeUntil = now() + pNumber(entry.P, "FearTime", 2.5)
		self:_setState(entry, "Flee")
		return
	end

	if math.random() < attackChance then
		local aggroDist = pNumber(entry.P, "AggroDistance", self.Config.DefaultDetection)
		local plr = select(1, pickNearestPlayer(entry.HRP.Position, aggroDist))
		if plr then
			entry.Target = plr
			self:_setState(entry, "Chase")
		end
	end
end

function AIService:_shouldReturn(entry: AIEntry): boolean
	local terr = entry.Territory
	local leash = entry.LeashRadius

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

	if terr then
		return randomPointInTerritory(terr, y)
	end

	local r = pNumber(entry.P, "PatrolRadius", 28)
	local theta = math.random() * math.pi * 2
	local rad = math.random() * r
	return Vector3.new(entry.SpawnPos.X + math.cos(theta) * rad, y, entry.SpawnPos.Z + math.sin(theta) * rad)
end

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

	local walkSpeed = getAttrNumber(entry.EnemyInfo, "Walkspeed", 16)
	local runSpeed = getAttrNumber(entry.EnemyInfo, "Runspeed", walkSpeed + 6)

	local attackDamage = getAttrNumber(entry.EnemyInfo, "AttackDamage", self.Config.DefaultAttackDamage)
	local attackRange = getAttrNumber(entry.EnemyInfo, "AttackRange", self.Config.DefaultAttackRange)
	local attackCd = getAttrNumber(entry.EnemyInfo, "AttackCooldown", self.Config.DefaultAttackCooldown)

	local aggroDist = pNumber(entry.P, "AggroDistance", self.Config.DefaultDetection)
	local chaseRange = pNumber(entry.P, "ChaseRange", self.Config.DefaultChaseRange)
	local fearDist = pNumber(entry.P, "FearDistance", 40)
	local runMaxDist = pNumber(entry.P, "RunMaxDistance", 150)

	-- Return overrides neutral states
	if entry.State ~= "Return" and entry.State ~= "Chase" and entry.State ~= "Attack" then
		if self:_shouldReturn(entry) then
			self:_setState(entry, "Return")
		end
	end

	-- Acquire target on proximity
	if entry.State ~= "Flee" and entry.State ~= "Return" then
		if not entry.Target then
			local near = select(1, pickNearestPlayer(pos, aggroDist))
			if near then
				local aggChance = pNumber(entry.P, "Aggressive", 0.25)
				if math.random() < aggChance then
					entry.Target = near
					self:_setState(entry, "Chase")
				end
			end
		end
	end

	-- Flee
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
		local fleePos = Vector3.new(pos.X + away.X * step, y, pos.Z + away.Z * step)

		entry.Humanoid:MoveTo(fleePos)
		safeSetAnim(entry, "Run")

		if t >= entry.FleeUntil then
			self:_setState(entry, "Return")
		end
		return
	end

	-- Return
	if entry.State == "Return" then
		entry.Humanoid.WalkSpeed = walkSpeed

		local terr = entry.Territory
		local y = territoryY(terr, pos.Y)
		local targetPos: Vector3
		if terr then
			targetPos = Vector3.new(terr.Position.X, y, terr.Position.Z)
		else
			targetPos = Vector3.new(entry.SpawnPos.X, y, entry.SpawnPos.Z)
		end

		entry.Humanoid:MoveTo(targetPos)
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

	-- Chase/Attack
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
		if d > chaseRange then
			entry.Target = nil
			self:_setState(entry, "Return")
			return
		end

		if d <= attackRange then
			self:_setState(entry, "Attack")
		else
			self:_setState(entry, "Chase")
			entry.Humanoid.WalkSpeed = runSpeed
			entry.Humanoid:MoveTo(thrp.Position)
			safeSetAnim(entry, "Run")
		end

		if entry.State == "Attack" then
			entry.Humanoid.WalkSpeed = 0
			entry.Humanoid:Move(Vector3.zero, false)
			safeSetAnim(entry, "Attack")

			if t >= entry.NextAttackAt then
				entry.NextAttackAt = t + attackCd
				pcall(function()
					-- Route damage through armor first, overflow hits health
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

		return
	end

	-- Idle / Wander
	if entry.State == "Idle" then
		entry.Humanoid.WalkSpeed = 0
		safeSetAnim(entry, "Idle")

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

		local d = (entry.WanderTarget - pos).Magnitude
		if d <= 3 then
			local lo, hi = pRange(entry.P, "WanderPause", self.Config.DefaultWanderPauseMin, self.Config.DefaultWanderPauseMax)
			entry.NextThinkAt = t + randRange(lo, hi)
			self:_setState(entry, "Idle")
		else
			entry.Humanoid:MoveTo(entry.WanderTarget)
		end
		return
	end
end

return AIService