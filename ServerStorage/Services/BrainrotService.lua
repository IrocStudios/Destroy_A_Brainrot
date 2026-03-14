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
-- Size variation
----------------------------------------------------------------------

local function rollSizeMultiplier(brainrotName: string): (number, number, boolean)
	local config = getBrainrotConfig()
	local entry = config[brainrotName]
	if not entry or type(entry.SizeVariation) ~= "table" then
		return 1.0, 1.0, false -- sizeMultiplier, effectiveMultiplier, inverted
	end

	local sv = entry.SizeVariation
	local dist = sv.Distribution
	local inverted = (sv.Inverted == true)

	if type(dist) ~= "table" or #dist == 0 then
		return 1.0, 1.0, inverted
	end

	-- Weighted bucket pick
	local totalWeight = 0
	for _, bucket in ipairs(dist) do
		totalWeight += (tonumber(bucket.Weight) or 0)
	end
	if totalWeight <= 0 then
		return 1.0, 1.0, inverted
	end

	local roll = math.random() * totalWeight
	local acc = 0
	local chosenRange = { 1.0, 1.0 }
	for _, bucket in ipairs(dist) do
		acc += (tonumber(bucket.Weight) or 0)
		if roll <= acc then
			if type(bucket.Range) == "table" and #bucket.Range >= 2 then
				chosenRange = bucket.Range
			end
			break
		end
	end

	local lo = tonumber(chosenRange[1]) or 1.0
	local hi = tonumber(chosenRange[2]) or lo
	if hi < lo then hi = lo end

	local sizeMult = lo + math.random() * (hi - lo)
	sizeMult = math.floor(sizeMult * 100 + 0.5) / 100 -- round to 2 decimals

	local effectiveMult: number
	if inverted then
		effectiveMult = 1 / sizeMult
	else
		effectiveMult = sizeMult
	end

	return sizeMult, effectiveMult, inverted
end

local function randomPointInTerritory(territory: BasePart): Vector3
	local cf = territory.CFrame
	local size = territory.Size
	local rx = (math.random() - 0.5) * size.X
	local rz = (math.random() - 0.5) * size.Z
	local p = (cf * CFrame.new(rx, 0, rz)).Position
	return Vector3.new(p.X, territory.Position.Y, p.Z)
end

local function findSafeSpawnPoint(territory: BasePart, tries: number, boxSize: Vector3?): Vector3
	local checkSize = boxSize or Vector3.new(6, 10, 6)

	-- Exclude: territory zone folder, existing enemies, and exclusion zone parts
	local excludeList: { Instance } = {}
	if territory.Parent then
		table.insert(excludeList, territory.Parent)
	end
	local enemiesFolder = Workspace:FindFirstChild("Enemies")
	if enemiesFolder then
		table.insert(excludeList, enemiesFolder)
	end
	-- Exclusion zone parts should not block the overlap check (they're non-collidable
	-- invisible volumes), but we reject points inside them separately below.

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeList

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = excludeList

	for attempt = 1, tries do
		local p = randomPointInTerritory(territory)

		-- Reject if inside any exclusion zone (regardless of weight)
		if ExclusionZoneManager:IsBlocked(p, 1) then
			continue
		end

		-- Downward raycast to find ground surface
		local rayOrigin = Vector3.new(p.X, p.Y + 50, p.Z)
		local rayResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -200, 0), rayParams)
		if rayResult then
			p = Vector3.new(p.X, rayResult.Position.Y + checkSize.Y * 0.5, p.Z)
		end

		-- Overlap check: ensure no collidable geometry at spawn point
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
			return p
		end
	end

	-- Fallback: try territory edge points instead of center
	local terrCF = territory.CFrame
	local terrSize = territory.Size
	local edges = {
		(terrCF * CFrame.new(terrSize.X * 0.4, 0, 0)).Position,
		(terrCF * CFrame.new(-terrSize.X * 0.4, 0, 0)).Position,
		(terrCF * CFrame.new(0, 0, terrSize.Z * 0.4)).Position,
		(terrCF * CFrame.new(0, 0, -terrSize.Z * 0.4)).Position,
	}
	for _, ep in ipairs(edges) do
		if not ExclusionZoneManager:IsBlocked(ep, 1) then
			return ep
		end
	end

	-- Last resort: territory center (better than nil)
	dwarn("findSafeSpawnPoint exhausted all options for", territory:GetFullName())
	return Vector3.new(territory.Position.X, territory.Position.Y, territory.Position.Z)
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
	-- Read stats from the Info Configuration inside ReplicatedStorage.Brainrots[name]
	local entry = readInfoConfig(brainrotName)

	local hum, _ = getHumanoidAndHRP(model)
	local enemyInfo = ensureEnemyInfo(model)

	local displayName = entry.DisplayName or brainrotName

	-- Rarity: Info stores as number (1-6). Convert to name.
	local rarityNum = tonumber(entry.Rarity) or 1
	local rarityName = "Common"
	if type(entry.RarityName) == "string" and entry.RarityName ~= "" then
		rarityName = entry.RarityName
	elseif type(entry.Rarity) == "number" then
		rarityName = rarityNameFromNumber(entry.Rarity)
	end

	local price = tonumber(entry.Price) or 0

	-- Health: read from the Body template Humanoid, fall back to Info or 100
	local maxHealth = tonumber(entry.Health) or 100
	local bodyTemplate = getBodyTemplate(brainrotName)
	if bodyTemplate then
		local bodyHum = bodyTemplate:FindFirstChildOfClass("Humanoid")
		if bodyHum and bodyHum.MaxHealth > 0 then
			maxHealth = bodyHum.MaxHealth
		end
	end

	local walk = tonumber(entry.Walkspeed) or 16
	local run = tonumber(entry.Runspeed) or (walk + 6)
	local atkSpeed = tonumber(entry.Attackspeed) or 20
	local healRate = tonumber(entry.HealRate) or 0

	local personality = entry.Personality
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

	if entry.AttackDamage ~= nil then enemyInfo:SetAttribute("AttackDamage", entry.AttackDamage) end
	if entry.AttackRange ~= nil then enemyInfo:SetAttribute("AttackRange", entry.AttackRange) end
	if entry.AttackCooldown ~= nil then enemyInfo:SetAttribute("AttackCooldown", entry.AttackCooldown) end

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

	-- Roll size variation
	local sizeMult, effectiveMult, sizeInverted = rollSizeMultiplier(brainrotName)

	dprint("Spawning brainrot:", "Name=", brainrotName, "Zone=", zoneRt.Name, "Id=", guid,
		"Size=", sizeMult, "Effective=", effectiveMult, "Inverted=", sizeInverted)

	local model = template:Clone()
	model.Name = ("Brainrot_%s"):format(guid)

	model:SetAttribute("BrainrotId", guid)
	model:SetAttribute("BrainrotName", brainrotName)
	model:SetAttribute("ZoneName", zoneRt.Name)
	model:SetAttribute("IsDead", false)
	model:SetAttribute("SizeMultiplier", sizeMult)
	model:SetAttribute("EffectiveMultiplier", effectiveMult)
	model:SetAttribute("SizeInverted", sizeInverted)

	local currentAnim = ensureCurrentAnimation(model)
	currentAnim.Value = "Idle"

	local hum, hrp = getHumanoidAndHRP(model)

	-- Compute spawn box size based on brainrot's actual size (scaled)
	local baseBoxSize = Vector3.new(6, 10, 6)
	local spawnBoxSize = baseBoxSize * sizeMult
	local spawnPos = findSafeSpawnPoint(zoneRt.Territory, 30, spawnBoxSize)
	model:PivotTo(CFrame.new(spawnPos))

	local maxHealth, totalValue, rarityName = self:_applyBaseline(model, brainrotName)

	-- Apply size scaling to stats
	if sizeMult ~= 1.0 then
		-- Scale model physically
		pcall(function()
			model:ScaleTo(sizeMult)
		end)

		-- Scale stats by effective multiplier
		maxHealth = math.floor(maxHealth * effectiveMult + 0.5)
		hum.MaxHealth = maxHealth
		hum.Health = maxHealth

		totalValue = math.floor(totalValue * effectiveMult + 0.5)

		-- Scale attack damage and cooldown on EnemyInfo
		local enemyInfo = model:FindFirstChild("EnemyInfo")
		if enemyInfo and enemyInfo:IsA("Configuration") then
			local baseDmg = enemyInfo:GetAttribute("AttackDamage")
			if typeof(baseDmg) == "number" then
				enemyInfo:SetAttribute("AttackDamage", math.floor(baseDmg * effectiveMult + 0.5))
			end

			local baseCd = enemyInfo:GetAttribute("AttackCooldown")
			if typeof(baseCd) == "number" then
				enemyInfo:SetAttribute("AttackCooldown", baseCd / effectiveMult)
			end

			-- Scale movement speed: bigger = slightly slower (physical, not inverted)
			-- Uses S^0.3 so a 1.8x brainrot is ~17% slower, not 80%
			local speedScale = 1 / (sizeMult ^ 0.3)
			local baseWalk = enemyInfo:GetAttribute("Walkspeed")
			if typeof(baseWalk) == "number" then
				enemyInfo:SetAttribute("Walkspeed", math.floor(baseWalk * speedScale * 100 + 0.5) / 100)
			end
			local baseRun = enemyInfo:GetAttribute("Runspeed")
			if typeof(baseRun) == "number" then
				enemyInfo:SetAttribute("Runspeed", math.floor(baseRun * speedScale * 100 + 0.5) / 100)
			end

			-- Update Price for value payout
			enemyInfo:SetAttribute("Price", totalValue)
		end

		dprint("Size-scaled stats:", brainrotName, "HP=", maxHealth, "Value=", totalValue,
			"SizeMult=", sizeMult, "EffMult=", effectiveMult)
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

	model.Parent = enemiesFolder

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
			combat:RegisterBrainrot(guid, hum, hrp, maxHealth, totalValue, rarityName, brainrotName)
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