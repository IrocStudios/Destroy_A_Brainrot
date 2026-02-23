--!strict
local ProgressionService = {}

local function xpRequiredForLevel(level: number): number
	-- Simple curve; you can replace later without changing API.
	-- L1->100, L2->150, L3->225...
	level = math.max(1, math.floor(level))
	return math.floor(100 * (1.5 ^ (level - 1)))
end

function ProgressionService:Init(services)
	self.Services = services
	self.DataService = services.DataService
	self.NetService = services.NetService
end

function ProgressionService:Start() end

function ProgressionService:AddXP(player: Player, amount: number, reason: string?)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return false, "InvalidAmount"
	end

	local newXP = 0
	local newLevel = 1
	local leveledUp = false

	self.DataService:Update(player, function(profile)
		profile.Progression = profile.Progression or {}
		profile.Progression.XP = profile.Progression.XP or 0
		profile.Progression.Level = profile.Progression.Level or 1

		local xp = profile.Progression.XP + amount
		local lvl = profile.Progression.Level

		-- Level up loop
		while xp >= xpRequiredForLevel(lvl) do
			xp -= xpRequiredForLevel(lvl)
			lvl += 1
			leveledUp = true
		end

		profile.Progression.XP = xp
		profile.Progression.Level = lvl

		newXP = xp
		newLevel = lvl
		return profile
	end)

	if self.NetService and self.NetService.SendDelta then
		self.NetService:SendDelta(player, {
			op = "set",
			path = "Progression.XP",
			value = newXP,
			meta = { reason = reason or "AddXP" },
		})
		if leveledUp then
			self.NetService:SendDelta(player, {
				op = "set",
				path = "Progression.Level",
				value = newLevel,
				meta = { reason = "LevelUp" },
			})
		end
	end

	return true, { leveledUp = leveledUp, level = newLevel, xp = newXP }
end

function ProgressionService:LevelUp(player: Player)
	-- Manual level up hook (rarely needed; provided for API completeness)
	local newLevel = 1
	self.DataService:Update(player, function(profile)
		profile.Progression = profile.Progression or {}
		profile.Progression.Level = (profile.Progression.Level or 1) + 1
		newLevel = profile.Progression.Level
		return profile
	end)

	if self.NetService and self.NetService.SendDelta then
		self.NetService:SendDelta(player, { op = "set", path = "Progression.Level", value = newLevel })
	end

	return true, newLevel
end

function ProgressionService:UnlockStage(player: Player, stageNumber: number)
	stageNumber = math.floor(tonumber(stageNumber) or 0)
	if stageNumber <= 0 then
		return false, "InvalidStage"
	end

	local newStage = 1
	self.DataService:Update(player, function(profile)
		profile.Progression = profile.Progression or {}
		local cur = profile.Progression.StageUnlocked or 1
		newStage = math.max(cur, stageNumber)
		profile.Progression.StageUnlocked = newStage
		return profile
	end)

	if self.NetService and self.NetService.SendDelta then
		self.NetService:SendDelta(player, { op = "set", path = "Progression.StageUnlocked", value = newStage })
	end

	return true, newStage
end

function ProgressionService:AddRebirth(player: Player, amount: number?)
	amount = math.floor(tonumber(amount) or 1)
	if amount <= 0 then
		return false, "InvalidAmount"
	end

	local newRebirths = 0
	self.DataService:Update(player, function(profile)
		profile.Progression = profile.Progression or {}
		profile.Progression.Rebirths = profile.Progression.Rebirths or 0
		profile.Progression.Rebirths += amount
		newRebirths = profile.Progression.Rebirths
		return profile
	end)

	if self.NetService and self.NetService.SendDelta then
		self.NetService:SendDelta(player, { op = "set", path = "Progression.Rebirths", value = newRebirths })
	end

	return true, newRebirths
end

return ProgressionService