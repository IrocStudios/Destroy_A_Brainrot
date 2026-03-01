--!strict
-- ServerStorage/Services/DataService
-- Destroy a Brainrot � DataService (Save/Load Everything)
--
-- Uses ServerStorage/Services/ProfileService (custom minimal ProfileService-like manager).
-- Services framework: ServerStorage/Services/ServerLoader loads via :Init(services) then :Start().
--
-- Contract:
--  - DataService owns all persistent player data.
--  - Other services must NEVER mutate profile tables directly.
--  - Use DataService APIs: Update / GetValue / SetValue / Increment / PushToList / SetInMap / IncrementMap
--
-- Events:
--  - OnProfileLoaded(player, data)
--  - OnProfileReleased(player)
--  - OnValueChanged(player, pathString, newValue)

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

type Player = Player

--////////////////////////////
-- Signal (Shared/Util/Signal if present, else minimal)
--////////////////////////////
local function MakeSignal()
	local ok, SignalMod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))
	end)
	if ok and type(SignalMod) == "table" then
		if type((SignalMod :: any).new) == "function" then
			return (SignalMod :: any).new()
		elseif type((SignalMod :: any).New) == "function" then
			return (SignalMod :: any).New()
		end
	end

	local signal = {}
	signal._bindable = Instance.new("BindableEvent")
	function signal:Connect(fn) return self._bindable.Event:Connect(fn) end
	function signal:Once(fn)
		local conn
		conn = self._bindable.Event:Connect(function(...)
			conn:Disconnect()
			fn(...)
		end)
		return conn
	end
	function signal:Fire(...) self._bindable:Fire(...) end
	function signal:Destroy() self._bindable:Destroy() end
	return signal
end

--////////////////////////////
-- Config defaults (optional)
--////////////////////////////
local function safeRequire(path: Instance): any?
	local ok, mod = pcall(function()
		return require(path)
	end)
	if ok then return mod end
	return nil
end

local ConfigFolder = ReplicatedStorage:FindFirstChild("Shared")
	and (ReplicatedStorage.Shared :: any):FindFirstChild("Config")

local EconomyConfig = ConfigFolder and (ConfigFolder :: Instance):FindFirstChild("EconomyConfig")
	and safeRequire((ConfigFolder :: any).EconomyConfig)

local ProgressionConfig = ConfigFolder and (ConfigFolder :: Instance):FindFirstChild("ProgressionConfig")
	and safeRequire((ConfigFolder :: any).ProgressionConfig)

local function getStartingCash(): number
	local v = EconomyConfig and (EconomyConfig :: any).StartingCash
	if type(v) == "number" then return v end
	return 0
end

local function getStartingStage(): number
	local v = ProgressionConfig and (ProgressionConfig :: any).StartingStage
	if type(v) == "number" then return v end
	return 1
end

local function getStartingLevel(): number
	local v = ProgressionConfig and (ProgressionConfig :: any).StartingLevel
	if type(v) == "number" then return v end
	return 1
end

--////////////////////////////
-- Deep utils
--////////////////////////////
local function deepCopy(t: any)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do
		out[k] = deepCopy(v)
	end
	return out
end

local function deepMerge(dst: any, src: any)
	if type(dst) ~= "table" or type(src) ~= "table" then return dst end
	for k, v in pairs(src) do
		if dst[k] == nil then
			dst[k] = deepCopy(v)
		else
			if type(dst[k]) == "table" and type(v) == "table" then
				deepMerge(dst[k], v)
			end
		end
	end
	return dst
end

local function splitPath(path: any): {string}
	if type(path) == "table" then
		local out = {}
		for i, seg in ipairs(path) do
			out[i] = tostring(seg)
		end
		return out
	end
	path = tostring(path)
	local out = {}
	for seg in string.gmatch(path, "[^%.]+") do
		table.insert(out, seg)
	end
	return out
end

local function getAtPath(root: any, pathArr: {string})
	local cur = root
	for _, seg in ipairs(pathArr) do
		if type(cur) ~= "table" then return nil end
		cur = cur[seg]
		if cur == nil then return nil end
	end
	return cur
end

local function ensureParent(root: any, pathArr: {string})
	local cur = root
	for i = 1, #pathArr - 1 do
		local seg = pathArr[i]
		if type(cur[seg]) ~= "table" then
			cur[seg] = {}
		end
		cur = cur[seg]
	end
	return cur, pathArr[#pathArr]
end

local function pathToString(pathArr: {string}): string
	return table.concat(pathArr, ".")
end

local function nowUnix(): number
	return os.time()
end

--////////////////////////////
-- Profile schema
--////////////////////////////
local CURRENT_VERSION = 6

local function MakeProfileTemplate()
	return {
		Version = CURRENT_VERSION,
		UserId = 0,
		CreatedAt = 0,
		LastSaveAt = 0,

		Currency = {
			Cash = getStartingCash(),
		},

		Progression = {
			XP = 0,
			Level = getStartingLevel(),
			StageUnlocked = getStartingStage(),
			Rebirths = 0,
			SpeedStep = 0, -- number of speed purchases made (0 = none)
		},

		Inventory = {
			ToolsOwned = {}, -- [ToolName] = true (legacy)
			EquippedTool = nil, -- ToolName (legacy)
			WeaponsOwned = { "StarterWeapon" }, -- weapon folder names the player owns
			SelectedWeapons = { "StarterWeapon" }, -- weapons active in toolbar (persisted)
		},

		Index = {
			BrainrotsDiscovered = {}, -- [brainrotId] = true
			BrainrotsKilled = {}, -- [brainrotId] = count
		},

		Rewards = {
			DailyLastClaim = 0,
			DailyStreak = 0,

			-- Progressive gifts:
			Gifts = {
				NextIndex = 1,
				Claimed = {},
				LastClaim = 0,
			},

			GiftCooldowns = {},

			-- RNG gift system: inventory of unopened gifts
			GiftInventory = {}, -- array of { id, rarity, source, receivedAt }
			NextGiftId = 1,     -- auto-increment counter for gift IDs

			-- Pity tracking: per loot source, { misses = number }
			-- Keys: "Gift_Common", "Gift_Rare", "Egg_Dragon", etc.
			Pity = {},
		},

		Boosts = {
			CashMult = 1,
			XPMult = 1,
			GiftChanceMult = 1,
			LuckMult = 1,
			Timed = {
				-- [BoostId] = { mult = number, expiresAt = unix }
			},
		},

		Monetization = {
			DevProductsPurchased = {}, -- [ProductId] = count
			GamepassesOwned = {}, -- [GamepassId] = true
			TotalSpentRobux = 0,
		},

		Settings = {
			MusicOn = true,
			SFXOn = true,
			Sensitivity = 1,
		},

		Defense = {
			Armor = 0,      -- current armor points (chargeable, no max)
			ArmorStep = 0,  -- number of armor purchases made (0 = none)
		},

		Stats = {
			TotalKills = 0,
			TotalCashEarned = 0,
			TotalXPEarned = 0,
			TotalPlaytimeSeconds = 0,
			Deaths = 0,
		},
	}
end

--////////////////////////////
-- Migrations
--////////////////////////////
local function ApplyMigrations(data: any)
	if type(data) ~= "table" then return end

	local v = tonumber(data.Version) or 0
	while v < CURRENT_VERSION do
		local nextV = v + 1

		if nextV == 1 then
			if data.Inventory and data.Inventory.WeaponsOwned and not data.Inventory.ToolsOwned then
				data.Inventory.ToolsOwned = data.Inventory.WeaponsOwned
				data.Inventory.WeaponsOwned = nil
			end
			if data.Rewards and data.Rewards.Gifts == nil then
				data.Rewards.Gifts = { NextIndex = 1, Claimed = {}, LastClaim = 0 }
			end
		end

		if nextV == 2 then
			if not data.Defense then
				data.Defense = { Armor = 0, MaxArmor = 0 }
			end
		end

		if nextV == 3 then
			if data.Progression and data.Progression.SpeedTier == nil then
				data.Progression.SpeedTier = 0
			end
			if data.Defense then
				if data.Defense.ArmorTier == nil then
					data.Defense.ArmorTier = 0
				end
			end
		end

		if nextV == 4 then
			-- Armor rework: tiered MaxArmor → single chargeable number.
			-- ArmorTier → ArmorStep (rename), MaxArmor removed.
			if data.Defense then
				if data.Defense.ArmorStep == nil then
					-- Carry over old ArmorTier as starting step count
					data.Defense.ArmorStep = data.Defense.ArmorTier or 0
				end
				data.Defense.ArmorTier = nil
				data.Defense.MaxArmor  = nil
			end
		end

		if nextV == 5 then
			-- Speed rework: tiered SpeedTier → step-based SpeedStep.
			-- Old tiers (1-5) are incompatible with new 104-step system; reset to 0.
			if data.Progression then
				if data.Progression.SpeedStep == nil then
					data.Progression.SpeedStep = 0
				end
				data.Progression.SpeedTier = nil
			end
		end

		if nextV == 6 then
			-- RNG gift system: add GiftInventory, NextGiftId, Pity tables
			if type(data.Rewards) == "table" then
				if data.Rewards.GiftInventory == nil then
					data.Rewards.GiftInventory = {}
				end
				if data.Rewards.NextGiftId == nil then
					data.Rewards.NextGiftId = 1
				end
				if data.Rewards.Pity == nil then
					data.Rewards.Pity = {}
				end
			end
		end

		v = nextV
		data.Version = v
	end

	deepMerge(data, MakeProfileTemplate())
end

--////////////////////////////
-- Dev: Auto-wipe UserIDs (always start fresh profile for these users)
--////////////////////////////
local DEV_WIPE_USERIDS: {[number]: boolean} = {
	[2705035] = true, -- irocz (dev)
}

--////////////////////////////
-- ProfileService (required in this project)
--////////////////////////////
local ProfileService: any? = nil
do
	local ok, mod = pcall(function()
		return require(ServerStorage:WaitForChild("Services"):WaitForChild("ProfileService"))
	end)
	if ok then
		ProfileService = mod
	else
		warn("[DataService] FAILED to require ServerStorage/Services/ProfileService:", mod)
	end
end

-- Fallback stores (only used if ProfileService fails to load)
local MAIN_STORE_NAME = "DAB_Profile_v1"
local LOCK_STORE_NAME = "DAB_ProfileLock_v1"
local MainStore = DataStoreService:GetDataStore(MAIN_STORE_NAME)
local LockStore = DataStoreService:GetDataStore(LOCK_STORE_NAME)

local function jitteredBackoff(attempt: number): number
	local base = math.min(8, 0.25 * (2 ^ (attempt - 1)))
	local jitter = math.random() * 0.15
	return base + jitter
end

local LOCK_TIMEOUT = 120
local function lockKey(userId: number): string
	return "Lock_" .. tostring(userId)
end
local function dataKey(userId: number): string
	return "Player_" .. tostring(userId)
end

local function tryAcquireLock(userId: number): (boolean, string?)
	local key = lockKey(userId)
	for attempt = 1, 8 do
		local ok, res = pcall(function()
			return LockStore:UpdateAsync(key, function(old)
				local t = nowUnix()
				if old == nil then
					return { jobId = game.JobId, acquiredAt = t, heartbeatAt = t }
				end
				if type(old) == "table" then
					local hb = tonumber(old.heartbeatAt) or 0
					local acquired = tonumber(old.acquiredAt) or 0
					local age = t - math.max(hb, acquired)
					if age > LOCK_TIMEOUT then
						return { jobId = game.JobId, acquiredAt = t, heartbeatAt = t }
					end
					return old
				end
				return { jobId = game.JobId, acquiredAt = t, heartbeatAt = t }
			end)
		end)
		if ok and type(res) == "table" and res.jobId == game.JobId then
			return true, nil
		end
		task.wait(jitteredBackoff(attempt))
	end
	return false, "LOCK_BUSY"
end

local function releaseLock(userId: number)
	local key = lockKey(userId)
	pcall(function()
		LockStore:RemoveAsync(key)
	end)
end

local function heartbeatLock(userId: number)
	local key = lockKey(userId)
	pcall(function()
		LockStore:UpdateAsync(key, function(old)
			if type(old) ~= "table" then
				return { jobId = game.JobId, acquiredAt = nowUnix(), heartbeatAt = nowUnix() }
			end
			if old.jobId ~= game.JobId then return old end
			old.heartbeatAt = nowUnix()
			return old
		end)
	end)
end

local function loadFallback(userId: number): (any?, string?)
	for attempt = 1, 8 do
		local ok, res = pcall(function()
			return MainStore:GetAsync(dataKey(userId))
		end)
		if ok then
			return res, nil
		end
		task.wait(jitteredBackoff(attempt))
	end
	return nil, "LOAD_FAILED"
end

local function saveFallback(userId: number, data: any): (boolean, string?)
	for attempt = 1, 8 do
		local ok = pcall(function()
			MainStore:SetAsync(dataKey(userId), data)
		end)
		if ok then
			return true, nil
		end
		task.wait(jitteredBackoff(attempt))
	end
	return false, "SAVE_FAILED"
end

--////////////////////////////
-- DataService
--////////////////////////////
local DataService = {}
DataService.__index = DataService

-- Debug flag
DataService.Debug = true

local function dprint(self, ...)
	if self.Debug then
		print("[DataService]", ...)
	end
end

local function dwarn(self, ...)
	warn("[DataService]", ...)
end

DataService.OnProfileLoaded = MakeSignal()
DataService.OnProfileReleased = MakeSignal()
DataService.OnValueChanged = MakeSignal()

-- internal
DataService._services = nil :: any?
DataService._net = nil :: any?

DataService._profiles = {} :: {[number]: any} -- userId -> profile object (ProfileService profile OR fallback wrapper)
DataService._data = {} :: {[number]: any}     -- userId -> live data table
DataService._locks = {} :: {[number]: boolean}

DataService._updating = {} :: {[number]: boolean}
DataService._queues = {} :: {[number]: {() -> ()}}

DataService._autosaveTask = nil :: thread?
DataService._lockHeartbeatTask = nil :: thread?

-- ProfileService bits
DataService._profileStore = nil :: any?
DataService._useProfileService = false

--/////////////
-- API: Init/Start
--/////////////
function DataService:Init(services)
	self._services = services
	self._net = services.NetService

	if ProfileService and type(ProfileService.GetProfileStore) == "function" then
		self._useProfileService = true
		self._profileStore = (ProfileService :: any).GetProfileStore(MAIN_STORE_NAME, MakeProfileTemplate())
		dprint(self, "Init OK - using ProfileService store:", MAIN_STORE_NAME)
	else
		self._useProfileService = false
		dwarn(self, "Init - ProfileService unavailable, using fallback DataStore mode.")
	end
end

function DataService:Start()
	-- Debug tap: log every value change (very noisy; turn Debug off later)
	self.OnValueChanged:Connect(function(player, pathStr, newVal)
		dprint(self, "ValueChanged", player.Name, pathStr, newVal)
	end)

	-- Autosave
	self._autosaveTask = task.spawn(function()
		while true do
			task.wait(90)
			for _, plr in ipairs(Players:GetPlayers()) do
				self:SaveProfile(plr)
			end
		end
	end)

	-- Fallback lock heartbeat
	self._lockHeartbeatTask = task.spawn(function()
		while true do
			task.wait(30)
			for _, plr in ipairs(Players:GetPlayers()) do
				local uid = plr.UserId
				if self._locks[uid] then
					heartbeatLock(uid)
				end
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			self:LoadProfile(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:ReleaseProfile(player)
	end)

	game:BindToClose(function()
		dprint(self, "BindToClose begin")
		local deadline = os.clock() + 8
		for _, plr in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				self:ReleaseProfile(plr)
			end)
		end
		while os.clock() < deadline do
			local anyLive = false
			for _, _ in pairs(self._profiles) do
				anyLive = true
				break
			end
			if not anyLive then
				break
			end
			task.wait(0.1)
		end
		dprint(self, "BindToClose end")
	end)

	dprint(self, "Start OK")
end

--/////////////
-- Internal: Per-player serialized update queue
--/////////////
function DataService:_enqueue(userId: number, fn: () -> ())
	if not self._queues[userId] then
		self._queues[userId] = {}
	end
	table.insert(self._queues[userId], fn)

	if self._updating[userId] then
		return
	end

	self._updating[userId] = true
	task.spawn(function()
		while true do
			local q = self._queues[userId]
			if not q or #q == 0 then
				break
			end
			local nextFn = table.remove(q, 1)
			local ok, err = pcall(nextFn)
			if not ok then
				dwarn(self, "Queue fn error for userId", userId, err)
			end
		end
		self._updating[userId] = false
	end)
end

--/////////////
-- API: Profile lifecycle
--/////////////
function DataService:GetProfile(player: Player)
	return self._data[player.UserId]
end

function DataService:LoadProfile(player: Player)
	local userId = player.UserId
	if self._profiles[userId] ~= nil then
		dprint(self, "LoadProfile skipped (already loaded)", player.Name, userId)
		return
	end

	dprint(self, "LoadProfile begin", player.Name, userId)

	if self._useProfileService then
		local profile = self._profileStore:LoadProfileAsync("Player_" .. tostring(userId), "ForceLoad")
		if not profile then
			dwarn(self, "LoadProfile FAILED (ProfileService)", player.Name, userId)
			player:Kick("Data failed to load. Please rejoin.")
			return
		end

		profile:AddUserId(userId)
		profile:Reconcile()

		ApplyMigrations(profile.Data)

		if (profile.Data.UserId or 0) == 0 then
			profile.Data.UserId = userId
		end
		if (profile.Data.CreatedAt or 0) == 0 then
			profile.Data.CreatedAt = nowUnix()
		end

		profile:ListenToRelease(function()
			dwarn(self, "Profile released remotely (loaded elsewhere)", player.Name, userId)
			self._profiles[userId] = nil
			self._data[userId] = nil
			if player and player.Parent then
				player:Kick("Your data was loaded on another server.")
			end
		end)

		if not player:IsDescendantOf(Players) then
			dprint(self, "LoadProfile: player left during load; releasing", player.Name, userId)
			profile:Release()
			return
		end

		-- Dev auto-wipe: reset profile to template for dev users
		if DEV_WIPE_USERIDS[userId] then
			dprint(self, "DEV WIPE: Resetting profile for", player.Name, userId)
			local template = MakeProfileTemplate()
			template.UserId = userId
			template.CreatedAt = nowUnix()
			for k, v in pairs(template) do
				profile.Data[k] = v
			end
		end

		self._profiles[userId] = profile
		self._data[userId] = profile.Data

		dprint(self, "LoadProfile success", player.Name, userId, "Version", tostring(profile.Data.Version))
		self.OnProfileLoaded:Fire(player, profile.Data)
		return
	end

	-- Fallback path
	local acquired, lockErr = tryAcquireLock(userId)
	if not acquired then
		dwarn(self, "LoadProfile FAILED (fallback lock busy)", player.Name, userId, lockErr)
		player:Kick("Data is busy. Please rejoin in a moment. (" .. tostring(lockErr) .. ")")
		return
	end
	self._locks[userId] = true

	local raw = loadFallback(userId)
	if type(raw) ~= "table" then
		raw = MakeProfileTemplate()
	end

	deepMerge(raw, MakeProfileTemplate())
	ApplyMigrations(raw)

	raw.UserId = userId
	if (raw.CreatedAt or 0) == 0 then raw.CreatedAt = nowUnix() end

	-- Dev auto-wipe: reset profile to template for dev users (fallback path)
	if DEV_WIPE_USERIDS[userId] then
		dprint(self, "DEV WIPE (fallback): Resetting profile for", player.Name, userId)
		raw = MakeProfileTemplate()
		raw.UserId = userId
		raw.CreatedAt = nowUnix()
	end

	self._profiles[userId] = { __fallback = true }
	self._data[userId] = raw

	dprint(self, "LoadProfile success (fallback)", player.Name, userId, "Version", tostring(raw.Version))
	self.OnProfileLoaded:Fire(player, raw)
end

function DataService:SaveProfile(player: Player)
	local userId = player.UserId
	local data = self._data[userId]
	if not data then
		return
	end

	-- playtime tracking
	local tNow = nowUnix()
	local lastTick = player:GetAttribute("DAB_LastPlaytimeTick")
	if typeof(lastTick) ~= "number" then
		lastTick = tNow
	end
	player:SetAttribute("DAB_LastPlaytimeTick", tNow)
	local delta = math.max(0, tNow - (lastTick :: number))

	if type(data.Stats) == "table" then
		data.Stats.TotalPlaytimeSeconds = (tonumber(data.Stats.TotalPlaytimeSeconds) or 0) + delta
	end

	data.LastSaveAt = tNow
	dprint(self, "SaveProfile", player.Name, userId, "LastSaveAt", data.LastSaveAt)

	if self._useProfileService then
		-- custom ProfileService autosaves; we just updated LastSaveAt.
		return
	end

	local okSave = saveFallback(userId, data)
	if not okSave then
		dwarn(self, "SaveProfile FAILED (fallback)", player.Name, userId)
	end
end

function DataService:ReleaseProfile(player: Player)
	local userId = player.UserId
	if not self._data[userId] then
		if self._locks[userId] then
			self._locks[userId] = nil
			releaseLock(userId)
		end
		return
	end

	dprint(self, "ReleaseProfile begin", player.Name, userId)

	local done = false
	self:_enqueue(userId, function()
		self:SaveProfile(player)

		if self._useProfileService then
			local profile = self._profiles[userId]
			if profile then
				profile:Release()
			end
			self._profiles[userId] = nil
			self._data[userId] = nil
		else
			self._profiles[userId] = nil
			self._data[userId] = nil
			if self._locks[userId] then
				self._locks[userId] = nil
				releaseLock(userId)
			end
		end

		self.OnProfileReleased:Fire(player)
		dprint(self, "ReleaseProfile done", player.Name, userId)
		done = true
	end)

	local deadline = os.clock() + 2
	while not done and os.clock() < deadline do
		task.wait(0.05)
	end
end

--/////////////
-- API: Safe Updating
--/////////////
function DataService:Update(player: Player, callback: (any) -> (boolean, any?))
	local userId = player.UserId
	local data = self._data[userId]
	if not data then
		return false, "PROFILE_NOT_LOADED"
	end

	local completed = false
	local okOut: any = nil
	local errOut: any = nil
	local resultOut: any = nil

	self:_enqueue(userId, function()
		local live = self._data[userId]
		if not live then
			okOut, errOut, resultOut = false, "PROFILE_NOT_LOADED", nil
			completed = true
			return
		end

		local ok, a, b = pcall(callback, live)
		if not ok then
			dwarn(self, "Update callback error", player.Name, userId, a)
			okOut, errOut, resultOut = false, "CALLBACK_ERROR", nil
			completed = true
			return
		end

		if a == false then
			okOut, errOut, resultOut = false, b or "UPDATE_REJECTED", nil
			completed = true
			return
		end

		okOut, errOut, resultOut = true, nil, b
		dprint(self, "Update applied", player.Name, userId)

		if type(b) == "table" and type((b :: any).Changed) == "table" then
			for pathStr, newVal in pairs((b :: any).Changed) do
				self.OnValueChanged:Fire(player, tostring(pathStr), newVal)
			end
		end

		completed = true
	end)

	local deadline = os.clock() + 4
	while not completed and os.clock() < deadline do
		task.wait(0.01)
	end

	if not completed then
		return false, "UPDATE_TIMEOUT"
	end

	return okOut, errOut, resultOut
end

--/////////////
-- API: Path utilities (these DO fire OnValueChanged)
--/////////////
function DataService:GetValue(player: Player, path: any)
	local data = self._data[player.UserId]
	if not data then return nil end
	local p = splitPath(path)
	return getAtPath(data, p)
end

function DataService:SetValue(player: Player, path: any, value: any)
	local userId = player.UserId
	if not self._data[userId] then return false, "PROFILE_NOT_LOADED" end

	local completed = false
	local okOut: any = nil
	local errOut: any = nil

	self:_enqueue(userId, function()
		local data = self._data[userId]
		if not data then
			okOut, errOut = false, "PROFILE_NOT_LOADED"
			completed = true
			return
		end
		local p = splitPath(path)
		local parent, key = ensureParent(data, p)
		parent[key] = value
		self.OnValueChanged:Fire(player, pathToString(p), value)
		okOut, errOut = true, nil
		completed = true
	end)

	local deadline = os.clock() + 4
	while not completed and os.clock() < deadline do
		task.wait(0.01)
	end
	if not completed then return false, "UPDATE_TIMEOUT" end
	return okOut, errOut
end

function DataService:Increment(player: Player, path: any, amount: number)
	amount = amount or 1
	local userId = player.UserId
	if not self._data[userId] then return false, "PROFILE_NOT_LOADED" end

	local completed = false
	local okOut: any = nil
	local errOut: any = nil
	local newValueOut: any = nil

	self:_enqueue(userId, function()
		local data = self._data[userId]
		if not data then
			okOut, errOut = false, "PROFILE_NOT_LOADED"
			completed = true
			return
		end
		local p = splitPath(path)
		local parent, key = ensureParent(data, p)
		local cur = tonumber(parent[key]) or 0
		local nv = cur + amount
		parent[key] = nv
		self.OnValueChanged:Fire(player, pathToString(p), nv)
		okOut, errOut, newValueOut = true, nil, nv
		completed = true
	end)

	local deadline = os.clock() + 4
	while not completed and os.clock() < deadline do
		task.wait(0.01)
	end
	if not completed then return false, "UPDATE_TIMEOUT" end
	return okOut, errOut, newValueOut
end

function DataService:PushToList(player: Player, path: any, value: any)
	local userId = player.UserId
	if not self._data[userId] then return false, "PROFILE_NOT_LOADED" end

	local completed = false
	local okOut: any = nil
	local errOut: any = nil

	self:_enqueue(userId, function()
		local data = self._data[userId]
		if not data then
			okOut, errOut = false, "PROFILE_NOT_LOADED"
			completed = true
			return
		end
		local p = splitPath(path)
		local parent, key = ensureParent(data, p)
		if type(parent[key]) ~= "table" then parent[key] = {} end
		table.insert(parent[key], value)
		self.OnValueChanged:Fire(player, pathToString(p), parent[key])
		okOut, errOut = true, nil
		completed = true
	end)

	local deadline = os.clock() + 4
	while not completed and os.clock() < deadline do
		task.wait(0.01)
	end
	if not completed then return false, "UPDATE_TIMEOUT" end
	return okOut, errOut
end

function DataService:SetInMap(player: Player, path: any, key: any, value: any)
	local userId = player.UserId
	if not self._data[userId] then return false, "PROFILE_NOT_LOADED" end

	local completed = false
	local okOut: any = nil
	local errOut: any = nil

	self:_enqueue(userId, function()
		local data = self._data[userId]
		if not data then
			okOut, errOut = false, "PROFILE_NOT_LOADED"
			completed = true
			return
		end
		local p = splitPath(path)
		local map = getAtPath(data, p)
		if type(map) ~= "table" then
			local parent, k = ensureParent(data, p)
			parent[k] = {}
			map = parent[k]
		end
		(map :: any)[key] = value -- safe: map is table
		self.OnValueChanged:Fire(player, pathToString(p) .. "." .. tostring(key), value)
		okOut, errOut = true, nil
		completed = true
	end)

	local deadline = os.clock() + 4
	while not completed and os.clock() < deadline do
		task.wait(0.01)
	end
	if not completed then return false, "UPDATE_TIMEOUT" end
	return okOut, errOut
end

function DataService:IncrementMap(player: Player, path: any, key: any, amount: number)
	amount = amount or 1
	local userId = player.UserId
	if not self._data[userId] then return false, "PROFILE_NOT_LOADED" end

	local completed = false
	local okOut: any = nil
	local errOut: any = nil
	local newValueOut: any = nil

	self:_enqueue(userId, function()
		local data = self._data[userId]
		if not data then
			okOut, errOut = false, "PROFILE_NOT_LOADED"
			completed = true
			return
		end
		local p = splitPath(path)
		local map = getAtPath(data, p)
		if type(map) ~= "table" then
			local parent, k = ensureParent(data, p)
			parent[k] = {}
			map = parent[k]
		end

		-- IMPORTANT: avoid line starting with '(' (Luau ambiguous syntax issue)
		local cur = tonumber((map :: any)[key]) or 0
		local nv = cur + amount
		map[key] = nv

		self.OnValueChanged:Fire(player, pathToString(p) .. "." .. tostring(key), nv)
		okOut, errOut, newValueOut = true, nil, nv
		completed = true
	end)

	local deadline = os.clock() + 4
	while not completed and os.clock() < deadline do
		task.wait(0.01)
	end
	if not completed then return false, "UPDATE_TIMEOUT" end
	return okOut, errOut, newValueOut
end

--/////////////
-- Optional helpers for this game (purely data-level; other services may call)
--/////////////
function DataService:ClearExpiredTimedBoosts(player: Player)
	return self:Update(player, function(data)
		local t = nowUnix()
		local timed = data.Boosts and data.Boosts.Timed
		if type(timed) ~= "table" then return false, "NO_TIMED" end
		local changed = false
		for boostId, info in pairs(timed) do
			if type(info) == "table" then
				local exp = tonumber(info.expiresAt) or 0
				if exp > 0 and exp <= t then
					timed[boostId] = nil
					changed = true
				end
			end
		end
		return changed
	end)
end

function DataService:AddTimedBoost(player: Player, boostId: string, mult: number, durationSeconds: number)
	return self:Update(player, function(data)
		local t = nowUnix()
		if type(data.Boosts) ~= "table" then data.Boosts = {} end
		if type(data.Boosts.Timed) ~= "table" then data.Boosts.Timed = {} end
		local timed = data.Boosts.Timed

		local cur = timed[boostId]
		if type(cur) == "table" then
			local exp = tonumber(cur.expiresAt) or 0
			if exp > t then
				cur.expiresAt = exp + durationSeconds
				cur.mult = math.max(tonumber(cur.mult) or 1, mult)
			else
				timed[boostId] = { mult = mult, expiresAt = t + durationSeconds }
			end
		else
			timed[boostId] = { mult = mult, expiresAt = t + durationSeconds }
		end

		return true, {
			Changed = {
				["Boosts.Timed." .. boostId] = timed[boostId],
			},
		}
	end)
end

function DataService:RecordDevProductPurchase(player: Player, productId: number, robuxSpent: number?)
	return self:Update(player, function(data)
		if type(data.Monetization) ~= "table" then data.Monetization = {} end
		if type(data.Monetization.DevProductsPurchased) ~= "table" then data.Monetization.DevProductsPurchased = {} end
		local m = data.Monetization
		local map = m.DevProductsPurchased
		local k = tostring(productId)
		map[k] = (tonumber(map[k]) or 0) + 1
		if robuxSpent and type(robuxSpent) == "number" then
			m.TotalSpentRobux = (tonumber(m.TotalSpentRobux) or 0) + robuxSpent
		end
		return true, {
			Changed = {
				["Monetization.DevProductsPurchased." .. k] = map[k],
				["Monetization.TotalSpentRobux"] = m.TotalSpentRobux,
			},
		}
	end)
end

-- Called by NetService for SettingsAction RF.
-- payload = { setting = "Music"|"SFX"|"Sensitivity", value = any }
function DataService:HandleSettingsAction(player: Player, payload: any)
	if type(payload) ~= "table" then return { ok = false, reason = "BadPayload" } end

	local setting = tostring(payload.setting or "")
	local value   = payload.value
	local NetService = self._services and self._services.NetService

	local ALLOWED = { Music = "MusicOn", SFX = "SFXOn", Sensitivity = "Sensitivity" }
	local field = ALLOWED[setting]
	if not field then return { ok = false, reason = "UnknownSetting" } end

	local ok, err = self:SetValue(player, { "Settings", field }, value)
	if not ok then return { ok = false, reason = tostring(err) } end

	-- Send delta so client state mirrors the saved value
	if NetService then
		if field == "MusicOn"     then NetService:QueueDelta(player, "MusicOn", value)
		elseif field == "SFXOn"   then NetService:QueueDelta(player, "SFXOn",   value)
		end
		NetService:FlushDelta(player)
	end

	return { ok = true }
end

return DataService