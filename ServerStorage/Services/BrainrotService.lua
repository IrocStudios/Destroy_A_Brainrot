--!strict
-- BrainrotService
-- Spawns brainrots per Territory zone config, parents live NPCs to Workspace.Enemies,
-- tracks membership via ObjectValues under zone.Occupants, and registers with CombatService.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local ExclusionZoneManager = require(ServerStorage:WaitForChild("Services"):WaitForChild("Movement"):WaitForChild("ExclusionZoneManager"))

type Services = { [string]: any }

type ZoneRuntime = {
	Name: string,
	Zone: Instance,
	Territory: BasePart,
	Config: Configuration,
	Occupants: Folder,

	EnemyWeights: { { Name: string, Weight: number } },
	MinOcc: number,
	MaxOcc: number,
	SpawnRate: number,

	NextSpawnAt: number,
}

type EnemyRuntime = {
	Id: string,
	Model: Model,
	Humanoid: Humanoid,
	HRP: BasePart,

	ZoneName: string,
	BrainrotName: string,

	OccupantPointer: ObjectValue,
	AncestryConn: RBXScriptConnection?,
}

local BrainrotService = {}
BrainrotService.__index = BrainrotService

local DEBUG = true
local function dprint(...)
	if DEBUG then
		print("[BrainrotService]", ...)
	end
end
local function dwarn(...)
	if DEBUG then
		warn("[BrainrotService]", ...)
	end
end

local function getOrCreateFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then return f end
	local nf = Instance.new("Folder")
	nf.Name = name
	nf.Parent = parent
	return nf
end

local function ensureEnemiesFolder(): Folder
	return getOrCreateFolder(Workspace, "Enemies")
end

local function getTemplate(): Model
	local templates = ServerStorage:WaitForChild("Templates")
	local t = templates:WaitForChild("BrainrotTemplate")
	assert(t and t:IsA("Model"), "ServerStorage.Templates.BrainrotTemplate must be a Model")
	return t
end

local function ensureEnemyInfo(model: Model): Configuration
	local info = model:FindFirstChild("EnemyInfo")
	if info and info:IsA("Configuration") then
		return info
	end
	local c = Instance.new("Configuration")
	c.Name = "EnemyInfo"
	c.Parent = model
	return c
end

local function ensureCurrentAnimation(model: Model): StringValue
	local sv = model:FindFirstChild("CurrentAnimation")
	if sv and sv:IsA("StringValue") then
		return sv
	end
	local nsv = Instance.new("StringValue")
	nsv.Name = "CurrentAnimation"
	nsv.Value = "Idle"
	nsv.Parent = model
	return nsv
end

local function getHumanoidAndHRP(model: Model): (Humanoid, BasePart)
	local hum = model:FindFirstChildOfClass("Humanoid")
	assert(hum and hum:IsA("Humanoid"), "BrainrotTemplate must contain a Humanoid")

	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hum, hrp
	end

	local pp = model.PrimaryPart
	assert(pp and pp:IsA("BasePart"), "BrainrotTemplate must have HumanoidRootPart or PrimaryPart")
	return hum, pp
end

-- Each brainrot in ReplicatedStorage.Brainrots is a Folder: { Body [Model], Icon, Info [Configuration] }
local function getBrainrotFolder(brainrotName: string): Folder?
	local folder = ReplicatedStorage:FindFirstChild("Brainrots")
	if not folder or not folder:IsA("Folder") then
		dwarn("ReplicatedStorage.Brainrots folder missing.")
		return nil
	end
	local f = folder:FindFirstChild(brainrotName)
	if f then return f :: Folder end
	local def = folder:FindFirstChild("Default")
	if def then return def :: Folder end
	return nil
end

local function getBodyTemplate(brainrotName: string): Model?
	local brainrotFolder = getBrainrotFolder(brainrotName)
	if not brainrotFolder then return nil end
	local body = brainrotFolder:FindFirstChild("Body")
	if body and body:IsA("Model") then return body end
	return nil
end

-- Read stats from the Info Configuration inside the brainrot folder
local function readInfoConfig(brainrotName: string): { [string]: any }
	local brainrotFolder = getBrainrotFolder(brainrotName)
	if not brainrotFolder then return {} end
	local infoCfg = brainrotFolder:FindFirstChild("Info")
	if not infoCfg then return {} end
	return infoCfg:GetAttributes()
end

local function computeBodyExtentsSize(bodyTemplate: Model): Vector3?
	local clone: Model
	local okClone, errClone = pcall(function()
		clone = bodyTemplate:Clone()
	end)
	if not okClone then
		dwarn("Failed to clone body template for extents:", bodyTemplate:GetFullName(), errClone)
		return nil
	end

	clone.Parent = nil

	local ok, sizeOrErr = pcall(function()
		return clone:GetExtentsSize()
	end)

	clone:Destroy()

	if not ok then
		dwarn("GetExtentsSize failed for body template:", bodyTemplate.Name, sizeOrErr)
		return nil
	end

	return sizeOrErr :: Vector3
end

local function clampInt(n: number, lo: number, hi: number): number
	n = math.floor(n)
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

local function parseOccupancyLimit(v: any): (number, number)
	if typeof(v) == "NumberRange" then
		return clampInt(v.Min, 0, 9999), clampInt(v.Max, 0, 9999)
	end
	if typeof(v) == "Vector2" then
		return clampInt(v.X, 0, 9999), clampInt(v.Y, 0, 9999)
	end
	if type(v) == "table" then
		local a = tonumber(v[1]) or 0
		local b = tonumber(v[2]) or a
		return clampInt(a, 0, 9999), clampInt(b, 0, 9999)
	end
	if type(v) == "string" then
		local a, b = v:match("(%-?%d+)%s*[, ]%s*(%-?%d+)")
		if a and b then
			return clampInt(tonumber(a) or 0, 0, 9999), clampInt(tonumber(b) or 0, 0, 9999)
		end
	end
	if typeof(v) == "number" then
		local n = clampInt(v, 0, 9999)
		return n, n
	end
	return 1, 3
end

local function parseEnemyWeights(attr: any): { { Name: string, Weight: number } }
	local out: { { Name: string, Weight: number } } = {}

	local function add(name: any, weight: any)
		local n = tostring(name or "")
		if n == "" then return end
		local w = tonumber(weight) or 1
		if w <= 0 then w = 1 end
		table.insert(out, { Name = n, Weight = w })
	end

	if type(attr) == "string" then
		local s = attr
		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(s)
		end)
		if ok and type(decoded) == "table" then
			for _, entry in ipairs(decoded) do
				if type(entry) == "table" then
					add(entry[1] or entry.Name or entry.name, entry[2] or entry.Weight or entry.weight)
				end
			end
		else
			if s:find(":") then
				for token in string.gmatch(s, "([^,]+)") do
					local n, w = token:match("^%s*(.-)%s*:%s*(%-?%d+%.?%d*)%s*$")
					if n and w then
						add(n, tonumber(w))
					end
				end
			else
				add(s, 1)
			end
		end
	elseif type(attr) == "table" then
		for _, entry in ipairs(attr) do
			if type(entry) == "table" then
				add(entry[1], entry[2])
			end
		end
	end

	if #out == 0 then
		add("Default", 1)
	end
	return out
end

local function weightedPick(list: { { Name: string, Weight: number } }): string
	local total = 0
	for _, e in ipairs(list) do
		total += math.max(0, e.Weight)
	end
	if total <= 0 then
		return list[1].Name
	end
	local r = math.random() * total
	local acc = 0
	for _, e in ipairs(list) do
		acc += math.max(0, e.Weight)
		if r <= acc then
			return e.Name
		end
	end
	return list[1].Name
end

local function rarityNameFromNumber(n: number): string
	return (n == 1 and "Common")
		or (n == 2 and "Uncommon")
		or (n == 3 and "Rare")
		or (n == 4 and "Epic")
		or (n == 5 and "Legendary")
		or (n == 6 and "Mythic")
		or "Common"
end

----------------------------------------------------------------------
-- BrainrotConfig loader (for SizeVariation, AttackMoves, etc.)
----------------------------------------------------------------------

local _brainrotConfig: { [string]: any }? = nil
local function getBrainrotConfig(): { [string]: any }
	if _brainrotConfig then return _brainrotConfig end
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local cfg = shared:WaitForChild("Config")
	local ok, mod = pcall(function()
		return require(cfg:WaitForChild("BrainrotConfig"))
	end)
	if ok and type(mod) == "table" then
		_brainrotConfig = mod
		return mod
	end
	_brainrotConfig = {}
	return _brainrotConfig :: { [string]: any }
end

----------------------------------------------------------------------
-- Variant system (replaces old SizeVariation)
-- Each brainrot can define Variants: array of named variants with
-- Weight, SizeMultiplier, NameTag, SizeTier, StatOverrides, etc.
-- Returns the chosen variant table (or nil for default/no variants).
----------------------------------------------------------------------

type VariantResult = {
	Name: string,
	NameTag: string?,
	SizeMultiplier: number,
	SizeTier: string,
	StatOverrides: { [string]: number }?,
	VariantMoveOverrides: { [string]: any }?,
	VariantPersonalityOverrides: { [string]: any }?,
	VariantPrice: number?,
}

local function rollVariant(brainrotName: string): VariantResult
	local config = getBrainrotConfig()
	local entry = config[brainrotName]

	-- Default result (no variant)
	local defaultResult: VariantResult = {
		Name = "Normal",
		NameTag = nil,
		SizeMultiplier = 1.0,
		SizeTier = "normal",
	}

	if not entry or type(entry.Variants) ~= "table" or #entry.Variants == 0 then
		return defaultResult
	end

	-- Weighted pick from Variants array
	local totalWeight = 0
	for _, v in ipairs(entry.Variants) do
		totalWeight += (tonumber(v.Weight) or 0)
	end
	if totalWeight <= 0 then return defaultResult end

	local roll = math.random() * totalWeight
	local acc = 0
	local chosen = nil
	for _, v in ipairs(entry.Variants) do
		acc += (tonumber(v.Weight) or 0)
		if roll <= acc then
			chosen = v
			break
		end
	end

	if not chosen then return defaultResult end

	return {
		Name = chosen.Name or "Normal",
		NameTag = chosen.NameTag,
		SizeMultiplier = tonumber(chosen.SizeMultiplier) or 1.0,
		SizeTier = chosen.SizeTier or "normal",
		StatOverrides = type(chosen.StatOverrides) == "table" and chosen.StatOverrides or nil,
		VariantMoveOverrides = type(chosen.VariantMoveOverrides) == "table" and chosen.VariantMoveOverrides or nil,
		VariantPersonalityOverrides = type(chosen.VariantPersonalityOverrides) == "table" and chosen.VariantPersonalityOverrides or nil,
		VariantPrice = tonumber(chosen.VariantPrice),
	}
end

local function randomPointInTerritory(territory: BasePart): Vector3
	local cf = territory.CFrame
	local size = territory.Size
	local rx = (math.random() - 0.5) * size.X
	local rz = (math.random() - 0.5) * size.Z
	local p = (cf * CFrame.new(rx, 0, rz)).Position
	return Vector3.new(p.X, territory.Position.Y, p.Z)
end

local Players = game:GetService("Players")

local function getMinPlayerDistance(pos: Vector3): number
	local minDist = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local d = (hrp.Position - pos).Magnitude
			if d < minDist then minDist = d end
		end
	end
	return minDist
end

local function findSafeSpawnPoint(territory: BasePart, tries: number, boxSize: Vector3?): Vector3
	local checkSize = boxSize or Vector3.new(6, 10, 6)
	local terrTop = territory.Position.Y + (territory.Size.Y * 0.5)

	-- Exclude: territory zone folder, existing enemies, terrain, baseplate
	local excludeList: { Instance } = {}
	if territory.Parent then
		table.insert(excludeList, territory.Parent)
	end
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if enemiesFolder then
		table.insert(excludeList, enemiesFolder)
	end
	if Workspace.Terrain then
		table.insert(excludeList, Workspace.Terrain)
	end
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		table.insert(excludeList, baseplate)
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeList

	-- Collect valid candidate positions, scored by distance from players
	local candidates: { { pos: Vector3, dist: number } } = {}

	for attempt = 1, tries do
		local p = randomPointInTerritory(territory)
		-- Place at territory top surface
		p = Vector3.new(p.X, terrTop + checkSize.Y * 0.5, p.Z)

		-- Reject if inside any exclusion zone
		if ExclusionZoneManager:IsBlocked(p, 1) then
			continue
		end

		-- Overlap check: ensure no collidable parts at spawn point
		local boxCF = CFrame.new(p)
		local hits = Workspace:GetPartBoundsInBox(boxCF, checkSize, params)
		local blocked = false
		for _, part in ipairs(hits) do
			if part.CanCollide and part.Transparency < 1 then
				blocked = true
				break
			end
		end
		if not blocked then
			table.insert(candidates, { pos = p, dist = getMinPlayerDistance(p) })
		end
	end

	-- Pick from candidates: prefer positions far from players (top 3, with randomness)
	if #candidates > 0 then
		table.sort(candidates, function(a, b) return a.dist > b.dist end)
		local pick = candidates[math.random(1, math.min(3, #candidates))]
		return pick.pos
	end

	-- Fallback: territory center at top surface
	dwarn("findSafeSpawnPoint exhausted all options for", territory:GetFullName())
	return Vector3.new(territory.Position.X, terrTop + checkSize.Y * 0.5, territory.Position.Z)
end

local function getZoneParts(zone: Instance): (BasePart, Configuration, Folder)
	local territory = zone:FindFirstChild("Territory")
	assert(territory and territory:IsA("BasePart"), ("Zone %s missing Territory BasePart"):format(zone.Name))

	local cfg = zone:FindFirstChild("Configuration")
	assert(cfg and cfg:IsA("Configuration"), ("Zone %s missing Configuration"):format(zone.Name))

	local occ = zone:FindFirstChild("Occupants")
	assert(occ and occ:IsA("Folder"), ("Zone %s missing Occupants Folder"):format(zone.Name))

	return territory, cfg, occ
end

local function readZoneConfig(cfg: Configuration): (number, number, number, { { Name: string, Weight: number } })
	local enemiesAttr = cfg:GetAttribute("Enemies")
	local occAttr = cfg:GetAttribute("OccupancyLimit")
	local spawnRateAttr = cfg:GetAttribute("SpawnRate")

	local minOcc, maxOcc = parseOccupancyLimit(occAttr)
	if maxOcc < minOcc then
		maxOcc = minOcc
	end

	local spawnRate = tonumber(spawnRateAttr) or 20
	if spawnRate < 0.25 then spawnRate = 0.25 end

	local weights = parseEnemyWeights(enemiesAttr)

	return minOcc, maxOcc, spawnRate, weights
end

function BrainrotService.new()
	local self = setmetatable({}, BrainrotService)

	self.Services = nil :: Services?
	self.TerritoriesFolder = nil :: Folder?

	self.Zones = {} :: { [string]: ZoneRuntime }
	self.EnemiesById = {} :: { [string]: EnemyRuntime }

	self.BrainrotSpawned = Instance.new("BindableEvent")
	self.BrainrotDespawned = Instance.new("BindableEvent")

	self._running = false
	return self
end

function BrainrotService:Init(services: Services)
	self.Services = services
	self.TerritoriesFolder = Workspace:WaitForChild("Territories") :: Folder
	ensureEnemiesFolder()
	ExclusionZoneManager:Init()
end

function BrainrotService:Start()
	if self._running then return end
	self._running = true

	self:_scanZones()

	self.TerritoriesFolder.ChildAdded:Connect(function()
		task.defer(function()
			self:_scanZones()
		end)
	end)
	self.TerritoriesFolder.ChildRemoved:Connect(function()
		task.defer(function()
			self:_scanZones()
		end)
	end)

	-- Spawn loop
	task.spawn(function()
		while self._running do
			if not RunService:IsRunning() then
				task.wait(0.5)
				continue
			end

			local now = os.clock()
			for _, zoneRt in pairs(self.Zones) do
				local minOcc, maxOcc, spawnRate, weights = readZoneConfig(zoneRt.Config)
				zoneRt.MinOcc = minOcc
				zoneRt.MaxOcc = maxOcc
				zoneRt.SpawnRate = spawnRate
				zoneRt.EnemyWeights = weights

				local alive = self:_countOccupants(zoneRt)

				if alive < zoneRt.MinOcc then
					self:_spawnOne(zoneRt)
					zoneRt.NextSpawnAt = now + zoneRt.SpawnRate
				elseif alive < zoneRt.MaxOcc and now >= zoneRt.NextSpawnAt then
					self:_spawnOne(zoneRt)
					zoneRt.NextSpawnAt = now + zoneRt.SpawnRate
				end
			end

			task.wait(0.25)
		end
	end)

	-- Integrity check loop: catch fallen, broken, or orphaned brainrots
	local VOID_Y = -50
	local INTEGRITY_INTERVAL = 2.0 -- check every 2 seconds (not perf-critical)
	task.spawn(function()
		while self._running do
			task.wait(INTEGRITY_INTERVAL)
			if not RunService:IsRunning() then continue end

			local toRemove: { string } = {}
			for guid, rt in pairs(self.EnemiesById) do
				local model = rt.Model
				local hrp = rt.HRP
				local hum = rt.Humanoid

				-- Check 1: model removed from game
				if not model or not model.Parent then
					dprint("Integrity: model missing for", guid)
					table.insert(toRemove, guid)
					continue
				end

				-- Check 2: HRP destroyed/removed (model is orphaned shell)
				if not hrp or not hrp.Parent then
					dprint("Integrity: HRP missing for", guid, "- despawning")
					table.insert(toRemove, guid)
					continue
				end

				-- Check 3: Humanoid destroyed/removed
				if not hum or not hum.Parent then
					dprint("Integrity: Humanoid missing for", guid, "- despawning")
					table.insert(toRemove, guid)
					continue
				end

				-- Check 4: fell through map
				if hrp.Position.Y < VOID_Y then
					-- Try to recover: teleport back to territory
					local zoneName = rt.ZoneName
					local zoneRt = self.Zones[zoneName]
					if zoneRt and zoneRt.Territory and hum.Health > 0 then
						local terr = zoneRt.Territory
						local spawnY = terr.Position.Y + terr.Size.Y * 0.5 + 3
						local spawnPos = Vector3.new(
							terr.Position.X + (math.random() - 0.5) * terr.Size.X * 0.5,
							spawnY,
							terr.Position.Z + (math.random() - 0.5) * terr.Size.Z * 0.5
						)
						dprint("Integrity: fell through map, recovering", guid, "to", tostring(spawnPos))
						pcall(function()
							model:PivotTo(CFrame.new(spawnPos))
							hrp.AssemblyLinearVelocity = Vector3.zero
						end)
					else
						-- Can't recover (no territory or already dead) — despawn
						dprint("Integrity: fell through map, can't recover", guid, "- despawning")
						table.insert(toRemove, guid)
					end
				end
			end

			-- Process removals outside iteration
			for _, guid in ipairs(toRemove) do
				self:Despawn(guid, "integrity")
			end
		end
	end)

	-- Cleanup loop: remove orphaned models from Enemies folder that aren't tracked
	task.spawn(function()
		task.wait(5) -- initial delay to let spawns finish
		while self._running do
			task.wait(10) -- check every 10 seconds
			if not RunService:IsRunning() then continue end

			local enemiesFolder = Workspace:FindFirstChild("Enemies")
			if not enemiesFolder then continue end

			for _, child in ipairs(enemiesFolder:GetChildren()) do
				local guid = child:GetAttribute("BrainrotId")
				if guid and not self.EnemiesById[guid] then
					-- Orphaned model: tracked ID but no runtime entry
					dprint("Cleanup: orphaned model", child.Name, "guid=", guid)
					child:Destroy()
				elseif not guid then
					-- No ID at all — shouldn't be in Enemies folder
					dprint("Cleanup: untracked model", child.Name)
					child:Destroy()
				end
			end
		end
	end)
end

function BrainrotService:_scanZones()
	table.clear(self.Zones)

	for _, zone in ipairs(self.TerritoriesFolder:GetChildren()) do
		if zone:IsA("Folder") or zone:IsA("Model") then
			local territory, cfg, occ = getZoneParts(zone)
			local minOcc, maxOcc, spawnRate, weights = readZoneConfig(cfg)

			self.Zones[zone.Name] = {
				Name = zone.Name,
				Zone = zone,
				Territory = territory,
				Config = cfg,
				Occupants = occ,

				EnemyWeights = weights,
				MinOcc = minOcc,
				MaxOcc = maxOcc,
				SpawnRate = spawnRate,

				NextSpawnAt = os.clock() + 0.25,
			}
		end
	end
end

function BrainrotService:_countOccupants(zoneRt: ZoneRuntime): number
	local n = 0
	for _, child in ipairs(zoneRt.Occupants:GetChildren()) do
		if child:IsA("ObjectValue") and child.Value ~= nil then
			n += 1
		end
	end
	return n
end

function BrainrotService:_applyBaseline(model: Model, brainrotName: string): (number, number, string)
	-- BrainrotConfig.lua is the primary source of truth (code-managed, version-controlled).
	-- Studio-side Info Configuration is a fallback for brainrots not yet in config.
	local infoEntry = readInfoConfig(brainrotName)
	local cfgEntry = getBrainrotConfig()[brainrotName] or getBrainrotConfig()["Default"] or {}

	local hum, _ = getHumanoidAndHRP(model)
	local enemyInfo = ensureEnemyInfo(model)

	local displayName = cfgEntry.DisplayName or infoEntry.DisplayName or brainrotName

	-- Rarity: BrainrotConfig stores RarityName string. Info stores numeric Rarity (1-6).
	local rarityNum = tonumber(infoEntry.Rarity) or 1
	local rarityName = "Common"
	if type(cfgEntry.RarityName) == "string" and cfgEntry.RarityName ~= "" then
		rarityName = cfgEntry.RarityName
	elseif type(infoEntry.RarityName) == "string" and infoEntry.RarityName ~= "" then
		rarityName = infoEntry.RarityName
	elseif type(infoEntry.Rarity) == "number" then
		rarityName = rarityNameFromNumber(infoEntry.Rarity)
	end

	local price = cfgEntry.Price or tonumber(infoEntry.Price) or 0

	-- Health: BrainrotConfig > Body template Humanoid > Info > 100
	local maxHealth = cfgEntry.Health or tonumber(infoEntry.Health) or 100
	if not cfgEntry.Health then
		local bodyTemplate = getBodyTemplate(brainrotName)
		if bodyTemplate then
			local bodyHum = bodyTemplate:FindFirstChildOfClass("Humanoid")
			if bodyHum and bodyHum.MaxHealth > 0 then
				maxHealth = bodyHum.MaxHealth
			end
		end
	end

	local walk = cfgEntry.Walkspeed or tonumber(infoEntry.Walkspeed) or 16
	local run = cfgEntry.Runspeed or tonumber(infoEntry.Runspeed) or (walk + 6)
	local atkSpeed = cfgEntry.Attackspeed or tonumber(infoEntry.Attackspeed) or 20
	local healRate = cfgEntry.HealRate or tonumber(infoEntry.HealRate) or 0

	local personality = cfgEntry.Personality or infoEntry.Personality
	if type(personality) ~= "string" or personality == "" then
		personality = "Passive"
	end

	hum.MaxHealth = maxHealth
	hum.Health = maxHealth
	hum.WalkSpeed = walk

	enemyInfo:SetAttribute("DisplayName", displayName)
	enemyInfo:SetAttribute("Price", price)
	enemyInfo:SetAttribute("Rarity", rarityNum)
	enemyInfo:SetAttribute("RarityName", rarityName)
	enemyInfo:SetAttribute("Walkspeed", walk)
	enemyInfo:SetAttribute("Runspeed", run)
	enemyInfo:SetAttribute("Attackspeed", atkSpeed)
	enemyInfo:SetAttribute("HealRate", healRate)
	enemyInfo:SetAttribute("Personality", personality)

	local atkDmg = cfgEntry.AttackDamage or infoEntry.AttackDamage
	local atkRange = cfgEntry.AttackRange or infoEntry.AttackRange
	local atkCd = cfgEntry.AttackCooldown or infoEntry.AttackCooldown
	if atkDmg ~= nil then enemyInfo:SetAttribute("AttackDamage", atkDmg) end
	if atkRange ~= nil then enemyInfo:SetAttribute("AttackRange", atkRange) end
	if atkCd ~= nil then enemyInfo:SetAttribute("AttackCooldown", atkCd) end

	local totalValue = price
	if totalValue <= 0 then
		totalValue = math.max(1, maxHealth)
	end

	dprint("ApplyBaseline:", brainrotName, "HP=", maxHealth, "Price=", price, "Rarity=", rarityName, "Walk=", walk)

	return maxHealth, totalValue, rarityName
end

function BrainrotService:_spawnOne(zoneRt: ZoneRuntime): EnemyRuntime?
	local enemiesFolder = ensureEnemiesFolder()
	local template = getTemplate()

	local brainrotName = weightedPick(zoneRt.EnemyWeights)
	local guid = HttpService:GenerateGUID(false)

	-- Roll variant (replaces old SizeVariation)
	local variant = rollVariant(brainrotName)
	local sizeMult = variant.SizeMultiplier

	dprint("Spawning brainrot:", "Name=", brainrotName, "Zone=", zoneRt.Name, "Id=", guid,
		"Variant=", variant.Name, "Size=", sizeMult, "Tier=", variant.SizeTier)

	local model = template:Clone()
	model.Name = ("Brainrot_%s"):format(guid)

	model:SetAttribute("BrainrotId", guid)
	model:SetAttribute("BrainrotName", brainrotName)
	model:SetAttribute("ZoneName", zoneRt.Name)
	model:SetAttribute("IsDead", false)
	model:SetAttribute("SizeMultiplier", sizeMult)
	model:SetAttribute("EffectiveMultiplier", sizeMult) -- effective = size (no inversion)
	model:SetAttribute("VariantName", variant.Name)
	model:SetAttribute("SizeTier", variant.SizeTier)

	-- Store variant name tag for display name modification
	if variant.NameTag then
		model:SetAttribute("VariantNameTag", variant.NameTag)
	end

	-- Propagate special combat flags from BrainrotConfig to model attributes
	local cfgEntry = getBrainrotConfig()[brainrotName]
	if cfgEntry and cfgEntry.IgnoreKnockbackInvuln then
		model:SetAttribute("IgnoreKnockbackInvuln", true)
	end

	local currentAnim = ensureCurrentAnimation(model)
	currentAnim.Value = "Idle"

	local hum, hrp = getHumanoidAndHRP(model)

	-- Compute spawn box size based on brainrot's actual size (scaled)
	local baseBoxSize = Vector3.new(6, 10, 6)
	local spawnBoxSize = baseBoxSize * sizeMult
	local spawnPos = findSafeSpawnPoint(zoneRt.Territory, 30, spawnBoxSize)
	model:PivotTo(CFrame.new(spawnPos))

	local maxHealth, totalValue, rarityName = self:_applyBaseline(model, brainrotName)

	-- Apply variant stat overrides (multipliers on base stats)
	local statOverrides = variant.StatOverrides
	if statOverrides then
		local enemyInfo = model:FindFirstChild("EnemyInfo")
		if enemyInfo and enemyInfo:IsA("Configuration") then
			for statName, mult in pairs(statOverrides) do
				local base = enemyInfo:GetAttribute(statName)
				if typeof(base) == "number" then
					enemyInfo:SetAttribute(statName, math.floor(base * mult + 0.5))
				end
			end
		end
		-- Health lives on the Humanoid, not EnemyInfo — handle separately
		if statOverrides.Health then
			maxHealth = math.floor(maxHealth * statOverrides.Health + 0.5)
			hum.MaxHealth = maxHealth
			hum.Health = maxHealth
		end
	end

	-- Apply variant name tag to display name
	if variant.NameTag then
		local enemyInfo = model:FindFirstChild("EnemyInfo")
		if enemyInfo and enemyInfo:IsA("Configuration") then
			local displayName = enemyInfo:GetAttribute("DisplayName")
			if type(displayName) == "string" then
				enemyInfo:SetAttribute("DisplayName", displayName .. " " .. variant.NameTag)
			end
		end
	end

	-- Apply size scaling to model + stats
	if sizeMult ~= 1.0 then
		-- Scale model RELATIVE to its original scale (multiply, not set absolute)
		pcall(function()
			local originalScale = model:GetScale()
			model:ScaleTo(originalScale * sizeMult)
		end)

		-- Scale HP and value by size
		maxHealth = math.floor(maxHealth * sizeMult + 0.5)
		hum.MaxHealth = maxHealth
		hum.Health = maxHealth

		totalValue = math.floor(totalValue * sizeMult + 0.5)

		local enemyInfo = model:FindFirstChild("EnemyInfo")
		if enemyInfo and enemyInfo:IsA("Configuration") then
			enemyInfo:SetAttribute("Price", totalValue)
		end

		dprint("Size-scaled stats:", brainrotName, "HP=", maxHealth, "Value=", totalValue,
			"SizeMult=", sizeMult)
	end

	-- Per-variant absolute price override (bypasses basePrice × sizeMult calculation)
	if variant.VariantPrice then
		totalValue = variant.VariantPrice
		local enemyInfo = model:FindFirstChild("EnemyInfo")
		if enemyInfo and enemyInfo:IsA("Configuration") then
			enemyInfo:SetAttribute("Price", totalValue)
		end
		dprint("VariantPrice override:", brainrotName, variant.Name, "=", totalValue)
	end

	-- Resize HRP to match body (after scaling)
	do
		local bodyTemplate = getBodyTemplate(brainrotName)
		if bodyTemplate then
			local customSize = bodyTemplate:GetAttribute("CustomSize")
			local finalSize: Vector3? = nil
			if typeof(customSize) == "Vector3" then
				finalSize = customSize * sizeMult
				dprint("Using CustomSize for", brainrotName, "->", tostring(finalSize))
			else
				finalSize = computeBodyExtentsSize(bodyTemplate)
				if finalSize then
					finalSize = finalSize * sizeMult
				end
			end
			if finalSize then
				local okSize = pcall(function()
					hrp.Size = finalSize
				end)
				if okSize then
					dprint("Resized HRP:", model.Name, "->", tostring(finalSize))
				end
			end
		end
	end

	-- Re-position AFTER HRP resize so we use the final HRP size
	-- Ground = top surface of territory (Position.Y + Size.Y/2)
	-- Place HRP so its bottom sits on the ground + 1 stud buffer
	do
		local terrTop = zoneRt.Territory.Position.Y + (zoneRt.Territory.Size.Y * 0.5)
		local adjustedY = terrTop + (hrp.Size.Y * 0.5) + 1
		model:PivotTo(CFrame.new(spawnPos.X, adjustedY, spawnPos.Z))
	end

	model.Parent = enemiesFolder

	-- Create a dedicated collision block welded to HRP.
	-- Roblox's Humanoid auto-manages CanCollide on character parts (resets to false),
	-- but this separate part is NOT a Humanoid limb, so it stays CanCollide=true permanently.
	-- CanQuery/CanTouch=false means raycasts (combat hitbox) ignore it — physics only.
	if hrp then
		local collider = Instance.new("Part")
		collider.Name = "CollisionBlock"
		collider.Size = hrp.Size -- match HRP dimensions (already scaled)
		collider.Transparency = 1
		collider.Anchored = false
		collider.CanCollide = true
		collider.CanQuery = false  -- invisible to raycasts (no hitbox impact)
		collider.CanTouch = false  -- no touch events
		collider.Massless = true   -- doesn't affect physics weight
		collider.CFrame = hrp.CFrame
		collider.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hrp
		weld.Part1 = collider
		weld.Parent = collider
	end

	-- Build index key: base name for Normal, "BaseName:VariantName" for non-default variants
	local indexKey = brainrotName
	if variant.Name ~= "Normal" and variant.Name ~= "" then
		indexKey = brainrotName .. ":" .. variant.Name
	end
	model:SetAttribute("IndexKey", indexKey)

	local ptr = Instance.new("ObjectValue")
	ptr.Name = "Enemy"
	ptr.Value = model
	ptr.Parent = zoneRt.Occupants

	local rt: EnemyRuntime = {
		Id = guid,
		Model = model,
		Humanoid = hum,
		HRP = hrp,
		ZoneName = zoneRt.Name,
		BrainrotName = brainrotName,
		OccupantPointer = ptr,
		AncestryConn = nil,
	}
	self.EnemiesById[guid] = rt

	local combat = self.Services and self.Services.CombatService
	if combat and type(combat.RegisterBrainrot) == "function" then
		pcall(function()
			combat:RegisterBrainrot(guid, hum, hrp, maxHealth, totalValue, rarityName, indexKey)
		end)
	else
		dwarn("CombatService missing or RegisterBrainrot missing; no payouts will occur.")
	end

	hum.Died:Connect(function()
		if not self.EnemiesById[guid] then return end

		dprint("Humanoid.Died:", guid, "BrainrotName=", brainrotName, "Zone=", zoneRt.Name)

		model:SetAttribute("IsDead", true)
		if currentAnim and currentAnim.Parent then
			currentAnim.Value = "Die"
		end

		if rt.OccupantPointer and rt.OccupantPointer.Parent then
			rt.OccupantPointer:Destroy()
		end

		if combat then
			local fn = (combat :: any).OnBrainrotDied or (combat :: any).HandleBrainrotDeath or (combat :: any).BrainrotDied
			if type(fn) == "function" then
				pcall(function()
					fn(combat, guid)
				end)
			end
		end

		task.delay(1.25, function()
			if self.EnemiesById[guid] then
				self:Despawn(guid, "died")
			end
		end)
	end)

	rt.AncestryConn = model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			self:Despawn(guid, "removed")
		end
	end)

	self.BrainrotSpawned:Fire(guid, model)

	dprint("Spawned OK:", model.Name, "Value=", totalValue, "HP=", hum.MaxHealth, "Rarity=", rarityName)

	return rt
end

function BrainrotService:Despawn(guid: string, reason: string?)
	local rt = self.EnemiesById[guid]
	if not rt then return end
	self.EnemiesById[guid] = nil

	reason = reason or "manual"

	dprint("Despawning:", guid, "Reason=", reason)

	if rt.AncestryConn then rt.AncestryConn:Disconnect() end

	local combat = self.Services and self.Services.CombatService
	if combat and type(combat.UnregisterBrainrot) == "function" then
		pcall(function()
			combat:UnregisterBrainrot(guid)
		end)
	end

	self.BrainrotDespawned:Fire(guid, rt.Model, reason)

	if rt.OccupantPointer and rt.OccupantPointer.Parent then
		rt.OccupantPointer:Destroy()
	end

	if rt.Model and rt.Model.Parent then
		rt.Model:Destroy()
	end
end

function BrainrotService:GetAllActive()
	return self.EnemiesById
end

function BrainrotService:GetActiveById(guid: string): EnemyRuntime?
	return self.EnemiesById[guid]
end

return BrainrotService.new()