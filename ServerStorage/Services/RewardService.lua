local RewardService = {}

local Players = game:GetService("Players")

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

function RewardService:Init(services)
	self.Services = services
	self.DataService = services.DataService
	self.NetService = services.NetService
	self.EconomyService = services.EconomyService
	self.InventoryService = services.InventoryService
	self.ProgressionService = services.ProgressionService
	self.RarityService = services.RarityService
	self.CombatService = services.CombatService

	self.DailyRewards = {
		{ cash = 150, xp = 10 },
		{ cash = 250, xp = 15 },
		{ cash = 400, xp = 20 },
		{ cash = 600, xp = 30 },
		{ cash = 900, xp = 40 },
		{ cash = 1300, xp = 55 },
		{ cash = 1800, xp = 75 },
	}

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

function RewardService:Start()
	local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local net = shared:WaitForChild("Net")
	local remotes = net:WaitForChild("Remotes")
	local rf = remotes:WaitForChild("RemoteFunctions")
	local rewardRF = rf:WaitForChild("RewardAction")

	rewardRF.OnServerInvoke = function(player, payload)
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
		else
			return { ok = false, error = "UnknownAction" }
		end
	end

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

function RewardService:Notify(player, title, body)
	local payload = { Title = title, Body = body }

	if self.NetService and type(self.NetService.Notify) == "function" then
		self.NetService:Notify(player, payload)
		return
	end

	local rs = game:GetService("ReplicatedStorage")
	local e = rs:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Remotes"):WaitForChild("RemoteEvents")
	local notifyRE = e:FindFirstChild("Notify")
	if notifyRE then
		notifyRE:FireClient(player, payload)
	end
end

function RewardService:GetProfile(player)
	if not self.DataService then return nil end
	return self.DataService:GetProfile(player)
end

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

	return {
		ok = true,
		Daily = {
			canClaim = canDaily,
			streak = streak,
			lastClaim = lastClaim,
		},
		Gifts = gifts,
		ServerTime = t,
	}
end

function RewardService:FlushStatus(player)
	self:GetStatus(player)
end

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

function RewardService:GrantReward(player, reward)
	if type(reward) ~= "table" then return end
	if reward.kind == "Cash" then
		if self.EconomyService then
			self.EconomyService:AddCash(player, tonumber(reward.amount) or 0, "Gift")
		end
	elseif reward.kind == "XP" then
		if self.ProgressionService then
			self.ProgressionService:AddXP(player, tonumber(reward.amount) or 0, "Gift")
		end
	elseif reward.kind == "Tool" then
		if self.InventoryService and type(reward.toolName) == "string" then
			self.InventoryService:GrantTool(player, reward.toolName)
		end
	end
end

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

function RewardService:OnBrainrotKilled(player, brainrotInfo)
	if not player or not player.Parent then return end

	local rarityName = nil
	if type(brainrotInfo) == "table" then
		rarityName = brainrotInfo.rarity or brainrotInfo.Rarity
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

	local giftId = "KillGift"
	local def = self.Gifts[giftId]
	if not def then return end

	pcall(function()
		self.DataService:Update(player, function(data)
			data.Rewards = data.Rewards or {}
			data.Rewards.GiftCooldowns = data.Rewards.GiftCooldowns or {}
			local giftCooldowns = data.Rewards.GiftCooldowns

			local entry = getOrInitGiftEntry(giftCooldowns, giftId)
			local maxPending = tonumber(def.maxPending) or 5
			entry.pending = clamp(entry.pending + 1, 0, maxPending)
			if type(entry.next) ~= "number" then entry.next = 0 end
			if entry.next < 0 then entry.next = 0 end

			return true
		end)
	end)

	self:Notify(player, "Gift Drop!", "A gift was added. Claim it in the Gifts menu.")
end

return RewardService