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

	-- Cache configs for rebirth
	local cfgFolder = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Config")

	if cfgFolder then
		local ok1, pc = pcall(function()
			return require(cfgFolder:FindFirstChild("ProgressionConfig"))
		end)
		self._progressionConfig = ok1 and pc or nil

		local ok2, ec = pcall(function()
			return require(cfgFolder:FindFirstChild("EconomyConfig"))
		end)
		self._economyConfig = ok2 and ec or nil
	end
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

---------------------------------------------------------------------------
-- Rebirth action (invoked via NetService → "RebirthAction")
---------------------------------------------------------------------------
-- Resets: Cash, Level, XP, StageUnlocked, Weapons/Tools
-- Keeps:  Discoveries (Index), Rebirths count, Gifts, Stats, Settings
-- Grants: Updated CashMult and XPMult boosts based on new rebirth count

function ProgressionService:HandleRebirthAction(player: Player, payload: any)
	if type(payload) ~= "table" or payload.action ~= "rebirth" then
		return { ok = false, reason = "BadPayload" }
	end

	-- Load configs
	local progCfg = self._progressionConfig
	if not progCfg or not progCfg.Rebirth then
		warn("[ProgressionService] ProgressionConfig.Rebirth missing")
		return { ok = false, reason = "ServerError" }
	end

	local req    = progCfg.Rebirth.Requirement
	local scale  = progCfg.Rebirth.Scaling
	local clamps = progCfg.Rebirth.Clamps or {}
	local maxReb = progCfg.Rebirth.MaxRebirths -- nil = unlimited

	-- ── Validate requirements ──────────────────────────────────────────
	local profile = self.DataService:GetProfile(player)
	if not profile then
		return { ok = false, reason = "ProfileNotLoaded" }
	end

	local prog = profile.Progression or {}
	local curr = profile.Currency or {}

	local lvl   = prog.Level          or 0
	local stage = prog.StageUnlocked  or 0
	local cash  = curr.Cash           or 0
	local rebs  = prog.Rebirths       or 0

	if maxReb and rebs >= maxReb then
		return { ok = false, reason = "MaxRebirthsReached" }
	end
	if lvl < (req.MinLevel or 60) then
		return { ok = false, reason = "LevelTooLow" }
	end
	if stage < (req.MinStage or 5) then
		return { ok = false, reason = "StageTooLow" }
	end
	local cashCost = req.CashCost or 0
	if cash < cashCost then
		return { ok = false, reason = "InsufficientCash" }
	end

	-- ── Calculate new boost multipliers ────────────────────────────────
	local newRebirths = rebs + 1
	local newCashMult = 1 + (newRebirths * (scale.CashMultiplierPerRebirth or 0.12))
	local newXPMult   = 1 + (newRebirths * (scale.XPMultiplierPerRebirth or 0.08))
	newCashMult = math.min(newCashMult, clamps.MaxCashMultiplier or 6.00)
	newXPMult   = math.min(newXPMult,   clamps.MaxXPMultiplier   or 5.00)

	-- Starting values from config
	local startingCash = 0
	local ecoCfg = self._economyConfig
	if ecoCfg and type(ecoCfg.StartingCash) == "number" then
		startingCash = ecoCfg.StartingCash
	end

	-- ── Apply rebirth in one atomic Update ─────────────────────────────
	self.DataService:Update(player, function(p)
		-- Increment rebirths
		p.Progression = p.Progression or {}
		p.Progression.Rebirths = newRebirths

		-- Reset progression
		p.Progression.Level = 1
		p.Progression.XP = 0
		p.Progression.StageUnlocked = 1

		-- Reset cash to starting amount
		p.Currency = p.Currency or {}
		p.Currency.Cash = startingCash

		-- Clear weapons/tools
		p.Inventory = p.Inventory or {}
		p.Inventory.ToolsOwned = {}
		p.Inventory.EquippedTool = nil
		p.Inventory.WeaponsOwned = {}
		p.Inventory.EquippedWeapon = ""

		-- Update boost multipliers
		p.Boosts = p.Boosts or {}
		p.Boosts.CashMult = newCashMult
		p.Boosts.XPMult = newXPMult

		return p
	end)

	print(("[ProgressionService] %s rebirthed! Rebirths=%d  CashMult=%.2f  XPMult=%.2f"):format(
		player.Name, newRebirths, newCashMult, newXPMult))

	-- ── Send all deltas to client ──────────────────────────────────────
	if self.NetService then
		self.NetService:QueueDelta(player, "Rebirths", newRebirths)
		self.NetService:QueueDelta(player, "Level", 1)
		self.NetService:QueueDelta(player, "XP", 0)
		self.NetService:QueueDelta(player, "StageUnlocked", 1)
		self.NetService:QueueDelta(player, "Cash", startingCash)
		self.NetService:QueueDelta(player, "WeaponsOwned", {})
		self.NetService:QueueDelta(player, "EquippedWeapon", "")
		self.NetService:FlushDelta(player)
	end

	-- ── Destroy physical tools in Backpack + Character ─────────────────
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then child:Destroy() end
		end
	end
	local char = player.Character
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") then child:Destroy() end
		end
	end

	-- ── Respawn with clean state ───────────────────────────────────────
	task.defer(function()
		if player and player.Parent then
			player:LoadCharacter()
		end
	end)

	return { ok = true, rebirths = newRebirths, cashMult = newCashMult, xpMult = newXPMult }
end

return ProgressionService