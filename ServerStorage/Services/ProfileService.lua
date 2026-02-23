--!strict
-- ServerStorage/Services/ProfileService
-- Minimal ProfileService-like implementation (no HTTP, DataStore-backed).
-- Provides:
--   ProfileService.GetProfileStore(storeName, templateTable)
--   store:LoadProfileAsync(key, "ForceLoad"|"Steal"|"Cancel")
--   profile.Data (table)
--   profile:Reconcile()
--   profile:AddUserId(userId)
--   profile:ListenToRelease(fn)
--   profile:Release()

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ProfileService = {}
ProfileService.__index = ProfileService

-- Tuning
local LOCK_TIMEOUT = 120         -- stale lock age (seconds)
local HEARTBEAT_INTERVAL = 30    -- refresh lock (seconds)
local SAVE_INTERVAL = 90         -- periodic save (seconds)
local LOAD_RETRIES = 8
local SAVE_RETRIES = 8

local function now(): number
	return os.time()
end

local function jitteredBackoff(attempt: number): number
	local base = math.min(8, 0.25 * (2 ^ (attempt - 1)))
	return base + (math.random() * 0.15)
end

local function deepCopy(v: any)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, vv in pairs(v) do
		out[k] = deepCopy(vv)
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

--////////////////////////////
-- Profile object
--////////////////////////////
local Profile = {}
Profile.__index = Profile

function Profile:AddUserId(_userId: number)
	-- Compatibility stub: real ProfileService uses this for compliance & tooling.
	-- We keep it so DataService code stays the same.
end

function Profile:Reconcile()
	deepMerge(self.Data, self._template)
end

function Profile:ListenToRelease(fn: (any) -> ())
	table.insert(self._releaseListeners, fn)
end

function Profile:_fireRelease()
	if self._released then return end
	self._released = true
	for _, fn in ipairs(self._releaseListeners) do
		task.spawn(fn, self)
	end
end

function Profile:Release()
	if self._released then return end
	self._released = true

	-- Stop background tasks
	if self._heartbeatTask then
		task.cancel(self._heartbeatTask)
		self._heartbeatTask = nil
	end
	if self._autosaveTask then
		task.cancel(self._autosaveTask)
		self._autosaveTask = nil
	end

	-- Best-effort final save + unlock (bounded retries)
	self:_saveNowBestEffort(true)
	self:_unlockBestEffort()

	self:_fireRelease()
end

function Profile:_unlockBestEffort()
	for attempt = 1, 4 do
		local ok = pcall(function()
			self._lockStore:RemoveAsync(self._lockKey)
		end)
		if ok then
			return
		end
		task.wait(jitteredBackoff(attempt))
	end
end

function Profile:_heartbeatLoop()
	while not self._released do
		task.wait(HEARTBEAT_INTERVAL)
		if self._released then break end
		pcall(function()
			self._lockStore:UpdateAsync(self._lockKey, function(old)
				if type(old) ~= "table" then
					return { jobId = self._jobId, acquiredAt = now(), heartbeatAt = now() }
				end
				if old.jobId ~= self._jobId then
					-- Someone else owns lock now
					return old
				end
				old.heartbeatAt = now()
				return old
			end)
		end)
	end
end

function Profile:_autosaveLoop()
	while not self._released do
		task.wait(SAVE_INTERVAL)
		if self._released then break end
		self:_saveNowBestEffort(false)
	end
end

function Profile:_saveNowBestEffort(isFinal: boolean)
	-- Do not attempt if we don't own lock
	if self._released and not isFinal then return end

	local payload = self.Data
	for attempt = 1, SAVE_RETRIES do
		local ok, err = pcall(function()
			self._dataStore:SetAsync(self._dataKey, payload)
		end)
		if ok then
			return
		end
		if isFinal and attempt >= 3 then
			-- Keep shutdown bounded
			return
		end
		task.wait(jitteredBackoff(attempt))
	end
end

--////////////////////////////
-- Store object
--////////////////////////////
local Store = {}
Store.__index = Store

function Store:_makeKeys(key: string): (string, string)
	-- lock key and data key separated by storeName prefix
	return ("Lock_%s_%s"):format(self._storeName, key), ("Data_%s_%s"):format(self._storeName, key)
end

function Store:_tryAcquire(lockKey: string, behavior: string?): (boolean, string?)
	local t = now()
	local wantForce = (behavior == "ForceLoad" or behavior == "Steal")
	local cancel = (behavior == "Cancel")

	for attempt = 1, LOAD_RETRIES do
		local ok, res = pcall(function()
			return self._lockStore:UpdateAsync(lockKey, function(old)
				local curT = now()

				if old == nil then
					return { jobId = game.JobId, acquiredAt = curT, heartbeatAt = curT }
				end

				if type(old) ~= "table" then
					return { jobId = game.JobId, acquiredAt = curT, heartbeatAt = curT }
				end

				local hb = tonumber(old.heartbeatAt) or 0
				local acq = tonumber(old.acquiredAt) or 0
				local age = curT - math.max(hb, acq)

				if old.jobId == game.JobId then
					-- We already own it
					old.heartbeatAt = curT
					return old
				end

				if age > LOCK_TIMEOUT then
					-- stale lock, steal
					return { jobId = game.JobId, acquiredAt = curT, heartbeatAt = curT }
				end

				-- active lock owned by someone else
				if cancel then
					return old
				end
				if wantForce then
					-- ForceLoad: we won't overwrite the lock here (unsafe),
					-- but we will keep retrying until it's stale OR released.
					return old
				end
				return old
			end)
		end)

		if ok and type(res) == "table" and res.jobId == game.JobId then
			return true, nil
		end

		if cancel then
			return false, "LOCKED"
		end

		task.wait(jitteredBackoff(attempt))
	end

	return false, "LOCKED"
end

function Store:_loadData(dataKey: string): any
	for attempt = 1, LOAD_RETRIES do
		local ok, res = pcall(function()
			return self._dataStore:GetAsync(dataKey)
		end)
		if ok then
			return res
		end
		task.wait(jitteredBackoff(attempt))
	end
	return nil
end

function Store:LoadProfileAsync(key: string, behavior: string?)
	local lockKey, dataKey = self:_makeKeys(key)

	local acquired, err = self:_tryAcquire(lockKey, behavior)
	if not acquired then
		return nil
	end

	local raw = self:_loadData(dataKey)
	if type(raw) ~= "table" then
		raw = deepCopy(self._template)
	end

	-- Profile object
	local profile = setmetatable({}, Profile)
	profile.Data = raw
	profile._template = self._template
	profile._released = false
	profile._releaseListeners = {}
	profile._jobId = game.JobId
	profile._lockStore = self._lockStore
	profile._dataStore = self._dataStore
	profile._lockKey = lockKey
	profile._dataKey = dataKey

	-- Reconcile immediately (like real ProfileService)
	profile:Reconcile()

	-- Start maintenance loops
	profile._heartbeatTask = task.spawn(function()
		profile:_heartbeatLoop()
	end)
	profile._autosaveTask = task.spawn(function()
		profile:_autosaveLoop()
	end)

	return profile
end

--////////////////////////////
-- Public API
--////////////////////////////
function ProfileService.GetProfileStore(storeName: string, template: table)
	local store = setmetatable({}, Store)
	store._storeName = storeName
	store._template = deepCopy(template)

	-- Separate underlying stores for data vs lock (safer operations)
	store._dataStore = DataStoreService:GetDataStore(storeName .. "_DATA")
	store._lockStore = DataStoreService:GetDataStore(storeName .. "_LOCK")

	return store
end

return ProfileService