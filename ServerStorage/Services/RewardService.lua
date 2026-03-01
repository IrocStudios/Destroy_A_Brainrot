local RewardService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DAY_SECONDS = 24 * 60 * 60

local function now()
	return os.time()
end

local function utcDayNumber(t)
	local dt = os.date("!*t", t)
	dt.hour, dt.min, dt.sec = 0, 0, 0
	return os.time(dt) / DAY_SECONDS
end

local function clamp(n, a, b)
	if n < a then return a end
	if n > b then return b end
	return n
end

local function getOrInitGiftEntry(giftCooldowns, giftId)
	local entry = giftCooldowns[giftId]
	if type(entry) ~= "table" then
		entry = { next = 0, pending = 0 }
		giftCooldowns[giftId] = entry
	else
		if type(entry.next) ~= "number" then entry.next = 0 end
		if type(entry.pending) ~= "number" then entry.pending = 0 end
	end
	return entry
end

local function getRewardsTableFromProfile(profile)
	if type(profile) ~= "table" then return nil end
	if type(profile.Rewards) == "table" then
		return profile.Rewards
	end
	if type(profile.Data) == "table" and type(profile.Data.Rewards) == "table" then
		return profile.Data.Rewards
	end
	return nil
end

----------------------------------------------------------------------
-- Shared module references (set in Init)
----------------------------------------------------------------------
local LootTable = nil
local GiftConfig = nil
local RewardGranter = nil

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------
function RewardService:Init(services)
	self.Services = services
	self.DataService = services.DataService
	self.NetService = services.NetService
	self.EconomyService = services.EconomyService
	self.InventoryService = services.InventoryService
	self.ProgressionService = services.ProgressionService
	self.RarityService = services.RarityService
	self.CombatService = services.CombatService

	-- Require shared modules
	local SharedUtil = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util")
	local SharedConfig = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")

	LootTable = require(SharedUtil:WaitForChild("LootTable"))
	GiftConfig = require(SharedConfig:WaitForChild("GiftConfig"))
	RewardGranter = require(ServerStorage:WaitForChild("Services"):WaitForChild("RewardGranter"))
	RewardGranter.Setup(services)

	self.DailyRewards = {
		{ cash = 150, xp = 10 },
		{ cash = 250, xp = 15 },
		{ cash = 400, xp = 20 },
		{ cash = 600, xp = 30 },
		{ cash = 900, xp = 40 },
		{ cash = 1300, xp = 55 },
		{ cash = 1800, xp = 75 },
	}

	-- Legacy kill gift cooldown system (still used by OnBrainrotKilled)
	self.Gifts = {
		KillGift = {
			cooldown = 60 * 10,
			maxPending = 5,
			rewards = {
				{ w = 70, kind = "Cash", amount = 250 },
				{ w = 25, kind = "XP", amount = 25 },
				{ w = 5, kind = "Cash", amount = 1200 },
			},
		},
	}

	self.KillGiftDropChanceBase = 0.08
	self.KillGiftDropChanceMax = 0.25
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function RewardService:Start()
	-- NOTE: RewardAction OnServerInvoke is handled by NetService → HandleRewardAction.
	-- We no longer bind it directly here.

	if self.CombatService then
		local sig = rawget(self.CombatService, "BrainrotKilled")

		if typeof(sig) == "RBXScriptSignal" then
			sig:Connect(function(player, brainrotInfo)
				self:OnBrainrotKilled(player, brainrotInfo)
			end)
		elseif type(sig) == "table" then
			local connectFn = sig.Connect
			if type(connectFn) == "function" then
				connectFn(sig, function(player, brainrotInfo)
					self:OnBrainrotKilled(player, brainrotInfo)
				end)
			end
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		pcall(function()
			self:FlushStatus(player)
		end)
	end)
end

----------------------------------------------------------------------
-- HandleRewardAction: entry point called by NetService:RouteAction
----------------------------------------------------------------------
function RewardService:HandleRewardAction(player, payload)
	if type(payload) ~= "table" then
		return { ok = false, error = "BadPayload" }
	end

	local action = payload.Action
	if action == "ClaimDaily" then
		return self:ClaimDaily(player)
	elseif action == "ClaimGift" then
		return self:ClaimGift(player, payload.GiftId)
	elseif action == "GetStatus" then
		return self:GetStatus(player)
	elseif action == "OpenGift" then
		return self:OpenGift(player, payload.GiftId)
	elseif action == "KeepGift" then
		return self:KeepGift(player, payload.GiftId)
	elseif action == "GetInventory" then
		return self:GetGiftInventory(player)
	else
		return { ok = false, error = "UnknownAction" }
	end
end

----------------------------------------------------------------------
-- Notify helper
----------------------------------------------------------------------
function RewardService:Notify(player, title, body)
	local p = { Title = title, Body = body }

	if self.NetService and type(self.NetService.Notify) == "function" then
		self.NetService:Notify(player, p)
		return
	end

	local rs = game:GetService("ReplicatedStorage")
	local e = rs:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Remotes"):WaitForChild("RemoteEvents")
	local notifyRE = e:FindFirstChild("Notify")
	if notifyRE then
		notifyRE:FireClient(player, p)
	end
end

----------------------------------------------------------------------
-- NotifyEvent: fire a typed event to the client (for gift received prompt)
----------------------------------------------------------------------
function RewardService:NotifyEvent(player, eventType, data)
	local p = { Type = eventType, Data = data }

	local rs = game:GetService("ReplicatedStorage")
	local ok, re = pcall(function()
		return rs:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Remotes"):WaitForChild("RemoteEvents"):FindFirstChild("Notify")
	end)
	if ok and re then
		re:FireClient(player, p)
	end
end

----------------------------------------------------------------------
-- GetProfile
----------------------------------------------------------------------
function RewardService:GetProfile(player)
	if not self.DataService then return nil end
	return self.DataService:GetProfile(player)
end

----------------------------------------------------------------------
-- GetStatus (existing)
----------------------------------------------------------------------
function RewardService:GetStatus(player)
	local profile = self:GetProfile(player)
	if not profile then
		return { ok = false, error = "NoProfile" }
	end

	local r = getRewardsTableFromProfile(profile)
	if type(r) ~= "table" then
		return { ok = false, error = "NoRewards" }
	end

	local t = now()
	local today = utcDayNumber(t)
	local lastClaim = tonumber(r.DailyLastClaim) or 0
	local lastDay = utcDayNumber(lastClaim)

	local streak = tonumber(r.DailyStreak) or 0
	local canDaily = (lastClaim == 0) or (lastDay < today)

	local giftCooldowns = r.GiftCooldowns
	if type(giftCooldowns) ~= "table" then giftCooldowns = {} end

	local gifts = {}
	for giftId, def in pairs(self.Gifts) do
		local entry = getOrInitGiftEntry(giftCooldowns, giftId)
		gifts[giftId] = {
			pending = entry.pending,
			next = entry.next,
			cooldown = def.cooldown,
		}
	end

	-- Include gift inventory count
	local invCount = 0
	if type(r.GiftInventory) == "table" then
		invCount = #r.GiftInventory
	end

	return {
		ok = true,
		Daily = {
			canClaim = canDaily,
			streak = streak,
			lastClaim = lastClaim,
		},
		Gifts = gifts,
		GiftInventoryCount = invCount,
		ServerTime = t,
	}
end

function RewardService:FlushStatus(player)
	self:GetStatus(player)
end

----------------------------------------------------------------------
-- ClaimDaily (existing)
----------------------------------------------------------------------
function RewardService:ClaimDaily(player)
	local profile = self:GetProfile(player)
	if not profile then
		return { ok = false, error = "NoProfile" }
	end

	local t = now()
	local today = utcDayNumber(t)

	local ok, res = pcall(function()
		return self.DataService:Update(player, function(data)
			data.Rewards = data.Rewards or {}
			local r = data.Rewards

			local lastClaim = tonumber(r.DailyLastClaim) or 0
			local lastDay = utcDayNumber(lastClaim)

			if lastClaim ~= 0 and lastDay >= today then
				return false, "AlreadyClaimed"
			end

			local streak = tonumber(r.DailyStreak) or 0
			if lastClaim == 0 then
				streak = 1
			else
				local diffDays = (today - lastDay)
				if diffDays == 1 then
					streak = streak + 1
				else
					streak = 1
				end
			end

			streak = clamp(streak, 1, #self.DailyRewards)
			r.DailyStreak = streak
			r.DailyLastClaim = t

			return true, {
				streak = streak,
				reward = self.DailyRewards[streak],
			}
		end)
	end)

	if not ok then
		return { ok = false, error = "UpdateFailed" }
	end

	if res == false then
		return { ok = false, error = "AlreadyClaimed" }
	end

	local streak = res.streak
	local reward = res.reward or self.DailyRewards[1]

	if self.EconomyService and reward.cash and reward.cash > 0 then
		self.EconomyService:AddCash(player, reward.cash, "DailyReward")
	end
	if self.ProgressionService and reward.xp and reward.xp > 0 then
		self.ProgressionService:AddXP(player, reward.xp, "DailyReward")
	end

	self:Notify(player, "Daily Reward", ("Claimed Day %d reward!"):format(streak))

	return {
		ok = true,
		streak = streak,
		reward = reward,
	}
end

----------------------------------------------------------------------
-- pickWeighted (legacy, used by ClaimGift for kill gifts)
----------------------------------------------------------------------
function RewardService:pickWeighted(list)
	local total = 0
	for _, item in ipairs(list) do
		total += (tonumber(item.w) or 0)
	end
	if total <= 0 then
		return nil
	end
	local r = math.random() * total
	local acc = 0
	for _, item in ipairs(list) do
		acc += (tonumber(item.w) or 0)
		if r <= acc then
			return item
		end
	end
	return list[#list]
end

----------------------------------------------------------------------
-- GrantReward (updated to use RewardGranter for universal kinds)
----------------------------------------------------------------------
function RewardService:GrantReward(player, reward)
	if type(reward) ~= "table" then return end

	-- Legacy kill gift rewards use "w" instead of "weight" and "Tool" kind
	-- Route them through the old path for compatibility
	if reward.kind == "Tool" then
		if self.InventoryService and type(reward.toolName) == "string" then
			self.InventoryService:GrantTool(player, reward.toolName)
		end
		return
	end

	-- All other kinds go through the universal granter
	RewardGranter.Grant(player, reward)
end

----------------------------------------------------------------------
-- ClaimGift (existing kill gift cooldown system)
----------------------------------------------------------------------
function RewardService:ClaimGift(player, giftId)
	if type(giftId) ~= "string" then
		return { ok = false, error = "BadGiftId" }
	end

	local def = self.Gifts[giftId]
	if not def then
		return { ok = false, error = "UnknownGift" }
	end

	local t = now()

	local ok, result = pcall(function()
		return self.DataService:Update(player, function(data)
			data.Rewards = data.Rewards or {}
			data.Rewards.GiftCooldowns = data.Rewards.GiftCooldowns or {}
			local giftCooldowns = data.Rewards.GiftCooldowns

			local entry = getOrInitGiftEntry(giftCooldowns, giftId)

			if entry.pending <= 0 then
				return false, "NoPending"
			end
			if t < (tonumber(entry.next) or 0) then
				return false, "OnCooldown"
			end

			entry.pending -= 1
			entry.next = t + (tonumber(def.cooldown) or 0)

			return true, {
				next = entry.next,
				pending = entry.pending,
			}
		end)
	end)

	if not ok then
		return { ok = false, error = "UpdateFailed" }
	end
	if result == false then
		return { ok = false, error = "ClaimFailed" }
	end

	local picked = self:pickWeighted(def.rewards)
	if picked then
		self:GrantReward(player, picked)
	end

	self:Notify(player, "Gift Claimed", "You claimed a gift!")

	return {
		ok = true,
		giftId = giftId,
		reward = picked,
		state = result,
	}
end

----------------------------------------------------------------------
-- OnBrainrotKilled: existing kill gift drop + NEW rarity gift to inventory
----------------------------------------------------------------------
function RewardService:OnBrainrotKilled(player, brainrotInfo)
	if not player or not player.Parent then return end

	local rarityName = nil
	local rarityNum = 1
	if type(brainrotInfo) == "table" then
		rarityName = brainrotInfo.rarity or brainrotInfo.Rarity
		rarityNum = tonumber(brainrotInfo.rarityNum or brainrotInfo.RarityNum) or 1
	end

	local chance = self.KillGiftDropChanceBase
	if self.RarityService and type(self.RarityService.GetMultipliers) == "function" and rarityName then
		local mult = self.RarityService:GetMultipliers(rarityName)
		if type(mult) == "table" and type(mult.giftChance) == "number" then
			chance = chance * mult.giftChance
		end
	end
	chance = clamp(chance, 0, self.KillGiftDropChanceMax)

	if math.random() > chance then
		return
	end

	-- Determine gift rarity from killed brainrot's rarity
	-- Map name to number if needed
	if rarityNum <= 1 and rarityName then
		local RarityToNum = {
			Common = 1, Uncommon = 2, Rare = 3, Epic = 4,
			Legendary = 5, Mythic = 6, Transcendent = 7,
		}
		rarityNum = RarityToNum[rarityName] or 1
	end

	-- Add gift directly to inventory (enemy drops skip the prompt)
	self:ReceiveGift(player, rarityNum, "kill", true)
end

----------------------------------------------------------------------
-- ReceiveGift: add a gift to the player's inventory
-- skipPrompt = true for enemy drops (silent → inventory only)
-- skipPrompt = false for daily/friend gifts (fires prompt notification)
----------------------------------------------------------------------
function RewardService:ReceiveGift(player, rarity, source, skipPrompt)
	rarity = tonumber(rarity) or 1
	rarity = clamp(rarity, 1, 7)
	source = tostring(source or "unknown")

	local t = now()
	local giftObj = nil

	pcall(function()
		self.DataService:Update(player, function(data)
			data.Rewards = data.Rewards or {}
			data.Rewards.GiftInventory = data.Rewards.GiftInventory or {}
			data.Rewards.NextGiftId = data.Rewards.NextGiftId or 1

			local id = "gift_" .. tostring(data.Rewards.NextGiftId)
			data.Rewards.NextGiftId = data.Rewards.NextGiftId + 1

			giftObj = {
				id = id,
				rarity = rarity,
				source = source,
				receivedAt = t,
			}
			table.insert(data.Rewards.GiftInventory, giftObj)
			return true
		end)
	end)

	if not giftObj then return nil end

	-- Sync inventory to client
	if self.NetService then
		local profile = self:GetProfile(player)
		local inv = profile and profile.Rewards and profile.Rewards.GiftInventory or {}
		self.NetService:QueueDelta(player, "GiftInventory", inv)
		self.NetService:FlushDelta(player)
	end

	if not skipPrompt then
		-- Fire notification so client shows Open/Keep prompt
		local displayName = GiftConfig.GetDisplayName(rarity)
		self:NotifyEvent(player, "giftReceived", {
			giftId = giftObj.id,
			rarity = rarity,
			source = source,
			displayName = displayName,
		})
	else
		-- Silent add — just notify they got a gift drop
		self:Notify(player, "Gift Drop!", "A gift was added to your inventory.")
	end

	return giftObj
end

----------------------------------------------------------------------
-- OpenGift: consume a gift from inventory, roll loot, grant reward
----------------------------------------------------------------------
function RewardService:OpenGift(player, giftId)
	if type(giftId) ~= "string" then
		return { ok = false, error = "BadGiftId" }
	end

	-- Find and remove the gift from inventory atomically
	local giftObj = nil
	local removeOk = false

	pcall(function()
		local ok2 = self.DataService:Update(player, function(data)
			data.Rewards = data.Rewards or {}
			data.Rewards.GiftInventory = data.Rewards.GiftInventory or {}

			for i, gift in ipairs(data.Rewards.GiftInventory) do
				if type(gift) == "table" and gift.id == giftId then
					giftObj = gift
					table.remove(data.Rewards.GiftInventory, i)
					return true
				end
			end
			return false, "GiftNotFound"
		end)
		removeOk = ok2
	end)

	if not removeOk or not giftObj then
		return { ok = false, error = "GiftNotFound" }
	end

	local rarity = tonumber(giftObj.rarity) or 1
	local giftDef = GiftConfig.GetGift(rarity)
	if not giftDef then
		return { ok = false, error = "NoGiftConfig" }
	end

	-- Build loot entries, applying luck boost if applicable
	local lootEntries = giftDef.loot
	local profile = self:GetProfile(player)
	local luckMult = 1
	if profile and type(profile.Boosts) == "table" then
		luckMult = tonumber(profile.Boosts.LuckMult) or 1
	end

	if luckMult > 1 then
		-- Scale weights of high-tier entries by luck multiplier
		local adjusted = {}
		for i, entry in ipairs(lootEntries) do
			local e = {}
			for k, v in pairs(entry) do
				e[k] = v
			end
			if (tonumber(e.tier) or 1) >= 3 then
				e.weight = e.weight * luckMult
			end
			adjusted[i] = e
		end
		lootEntries = adjusted
	end

	local lt = LootTable.new(lootEntries)

	-- Load pity state
	local giftKey = GiftConfig.RarityToKey[rarity] or "Common"
	local pityStateKey = "Gift_" .. giftKey
	local pityState = { misses = 0 }

	pcall(function()
		self.DataService:Update(player, function(data)
			data.Rewards = data.Rewards or {}
			data.Rewards.Pity = data.Rewards.Pity or {}
			if type(data.Rewards.Pity[pityStateKey]) ~= "table" then
				data.Rewards.Pity[pityStateKey] = { misses = 0 }
			end
			pityState = data.Rewards.Pity[pityStateKey]
			return true
		end)
	end)

	-- Roll with pity
	local rolledEntry = lt:RollWithPity(pityState, giftDef.pity)

	-- Save pity state back
	pcall(function()
		self.DataService:Update(player, function(data)
			data.Rewards = data.Rewards or {}
			data.Rewards.Pity = data.Rewards.Pity or {}
			data.Rewards.Pity[pityStateKey] = pityState
			return true
		end)
	end)

	-- Grant the reward
	local grantOk, grantDesc = RewardGranter.Grant(player, rolledEntry)

	-- Sync updated inventory to client
	if self.NetService then
		local prof = self:GetProfile(player)
		local inv = prof and prof.Rewards and prof.Rewards.GiftInventory or {}
		self.NetService:QueueDelta(player, "GiftInventory", inv)
		self.NetService:FlushDelta(player)
	end

	return {
		ok = true,
		giftKey = giftKey,
		rarity = rarity,
		result = {
			kind = rolledEntry.kind,
			tier = rolledEntry.tier or 1,
			description = grantDesc,
			success = grantOk,
			weaponKey = rolledEntry.weaponKey,
			amount = rolledEntry.amount,
			steps = rolledEntry.steps,
			boostType = rolledEntry.boostType,
			mult = rolledEntry.mult,
			duration = rolledEntry.duration,
		},
	}
end

----------------------------------------------------------------------
-- KeepGift: gift stays in inventory (no-op, dismisses prompt)
----------------------------------------------------------------------
function RewardService:KeepGift(player, giftId)
	if type(giftId) ~= "string" then
		return { ok = false, error = "BadGiftId" }
	end

	-- Verify the gift exists
	local profile = self:GetProfile(player)
	if not profile then
		return { ok = false, error = "NoProfile" }
	end

	local inv = profile.Rewards and profile.Rewards.GiftInventory
	if type(inv) ~= "table" then
		return { ok = false, error = "NoInventory" }
	end

	for _, gift in ipairs(inv) do
		if type(gift) == "table" and gift.id == giftId then
			return { ok = true, kept = true, giftId = giftId }
		end
	end

	return { ok = false, error = "GiftNotFound" }
end

----------------------------------------------------------------------
-- GetGiftInventory: return the player's gift inventory for UI
----------------------------------------------------------------------
function RewardService:GetGiftInventory(player)
	local profile = self:GetProfile(player)
	if not profile then
		return { ok = false, error = "NoProfile" }
	end

	local inv = profile.Rewards and profile.Rewards.GiftInventory or {}
	return {
		ok = true,
		inventory = inv,
	}
end

return RewardService
