-- ReplicatedStorage/Shared/Util/LootTable.lua
-- Reusable weighted RNG engine with pity protection.
-- Used by gift opening, egg hatching, crates, etc.
--
-- Usage:
--   local lt = LootTable.new({
--       { weight = 50, kind = "Cash", amount = 200, tier = 1 },
--       { weight = 10, kind = "Weapon", weaponKey = "ak12", tier = 5 },
--   })
--   local entry = lt:Roll()
--   local entries = lt:RollN(10)
--   local entry = lt:RollWithPity(pityState, pityConfig)

local LootTable = {}
LootTable.__index = LootTable

----------------------------------------------------------------------
-- Private: binary search on cumulative weight array
----------------------------------------------------------------------
local function binarySearch(cumWeights, r)
	local lo, hi = 1, #cumWeights
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if cumWeights[mid] < r then
			lo = mid + 1
		else
			hi = mid
		end
	end
	return lo
end

----------------------------------------------------------------------
-- Private: build cumulative weight array from entries
----------------------------------------------------------------------
local function buildCumWeights(entries)
	local cumWeights = {}
	local total = 0
	for i, entry in ipairs(entries) do
		total = total + (tonumber(entry.weight) or 0)
		cumWeights[i] = total
	end
	return cumWeights, total
end

----------------------------------------------------------------------
-- Constructor
----------------------------------------------------------------------
function LootTable.new(entries)
	assert(type(entries) == "table" and #entries > 0, "LootTable.new: entries must be a non-empty array")

	local self = setmetatable({}, LootTable)
	self._entries = entries
	self._cumWeights, self._totalWeight = buildCumWeights(entries)
	return self
end

----------------------------------------------------------------------
-- Roll: pick one weighted random entry
----------------------------------------------------------------------
function LootTable:Roll()
	if self._totalWeight <= 0 then
		return self._entries[1]
	end

	local r = math.random() * self._totalWeight
	local idx = binarySearch(self._cumWeights, r)
	return self._entries[idx]
end

----------------------------------------------------------------------
-- RollN: pick N entries (with replacement)
----------------------------------------------------------------------
function LootTable:RollN(n)
	n = math.max(1, tonumber(n) or 1)
	local results = table.create(n)
	for i = 1, n do
		results[i] = self:Roll()
	end
	return results
end

----------------------------------------------------------------------
-- RollWithPity: pick one entry with pity protection
--
-- pityState: mutable table { misses = number } (caller owns, stored in profile)
-- pityConfig: { threshold = number, minTier = number }
--
-- After `threshold` consecutive rolls without hitting tier >= minTier,
-- forces the next roll from only entries that qualify.
----------------------------------------------------------------------
function LootTable:RollWithPity(pityState, pityConfig)
	if type(pityState) ~= "table" then
		return self:Roll()
	end
	if type(pityConfig) ~= "table" then
		return self:Roll()
	end

	local threshold = tonumber(pityConfig.threshold) or 999999
	local minTier = tonumber(pityConfig.minTier) or 1
	local misses = tonumber(pityState.misses) or 0

	-- Pity triggered: build filtered table and roll from it
	if misses >= threshold then
		local filtered = {}
		for _, entry in ipairs(self._entries) do
			if (tonumber(entry.tier) or 1) >= minTier then
				table.insert(filtered, entry)
			end
		end

		-- If no qualifying entries exist, fall through to normal roll
		if #filtered > 0 then
			local cumW, totalW = buildCumWeights(filtered)
			if totalW > 0 then
				local r = math.random() * totalW
				local idx = binarySearch(cumW, r)
				pityState.misses = 0
				return filtered[idx]
			end
		end
	end

	-- Normal roll
	local entry = self:Roll()
	local entryTier = tonumber(entry.tier) or 1

	if entryTier >= minTier then
		pityState.misses = 0
	else
		pityState.misses = misses + 1
	end

	return entry
end

----------------------------------------------------------------------
-- RollNWithPity: batch roll with pity carried across all rolls
----------------------------------------------------------------------
function LootTable:RollNWithPity(n, pityState, pityConfig)
	n = math.max(1, tonumber(n) or 1)
	local results = table.create(n)
	for i = 1, n do
		results[i] = self:RollWithPity(pityState, pityConfig)
	end
	return results
end

----------------------------------------------------------------------
-- GetEntries: returns the raw entries (for UI display / odds calculation)
----------------------------------------------------------------------
function LootTable:GetEntries()
	return self._entries
end

----------------------------------------------------------------------
-- GetTotalWeight: returns total weight (for probability math)
----------------------------------------------------------------------
function LootTable:GetTotalWeight()
	return self._totalWeight
end

return LootTable
