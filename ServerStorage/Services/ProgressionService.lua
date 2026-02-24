--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionService = {}

-- Derive XP curve from ProgressionConfig so server + client always agree.
local function loadXPCurve()
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ProgressionConfig"))
	end)
	if ok and cfg and cfg.XPCurve then
		return cfg.XPCurve
	end
	return nil
end

local _xpCurve: any = nil

local function xpRequiredForLevel(level: number): number
	level = math.max(1, math.floor(level))

	if not _xpCurve then
		_xpCurve = loadXPCurve() or {}
	end

	-- Check overrides first
	if type(_xpCurve.Overrides) == "table" and _xpCurve.Overrides[level] then
		return tonumber(_xpCurve.Overrides[level]) or 100
	end

	-- Use config formula: floor(Base + Growth * (level ^ Power))
	local base   = tonumber(_xpCurve.Base)   or 65
	local growth = tonumber(_xpCurve.Growth) or 14.5
	local power  = tonumber(_xpCurve.Power)  or 1.62
	return math.floor(base + growth * (level ^ power))
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

	if self.NetService then
		self.NetService:QueueDelta(player, "XP", newXP)
		if leveledUp then
			self.NetService:QueueDelta(player, "Level", newLevel)
		end
		self.NetService:FlushDelta(player)
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

	if self.NetService then
		self.NetService:QueueDelta(player, "Level", newLevel)
		self.NetService:FlushDelta(player)
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

	if self.NetService then
		self.NetService:QueueDelta(player, "StageUnlocked", newStage)
		self.NetService:FlushDelta(player)
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

	if self.NetService then
		self.NetService:QueueDelta(player, "Rebirths", newRebirths)
		self.NetService:FlushDelta(player)
	end

	return true, newRebirths
end

return ProgressionService