--!strict
-- AttackRegistry
-- Loads all attack modules from Attacks/Melee/ and Attacks/Projectile/.
-- Resolves brainrot → available moves, handles per-tick move selection
-- with range-based preference, light/heavy weighting, and cooldown tracking.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttackRegistry = {}

local _modules: { [string]: any } = {}
local _attackConfig: any = nil
local _loaded = false

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[AttackRegistry]", ...) end
end

----------------------------------------------------------------------
-- Config loading
----------------------------------------------------------------------

local function getAttackConfig(): any
	if _attackConfig then return _attackConfig end
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local cfg = shared:WaitForChild("Config")
	local ok, mod = pcall(function()
		return require(cfg:WaitForChild("AttackConfig"))
	end)
	if ok and type(mod) == "table" then
		_attackConfig = mod
		return mod
	end
	_attackConfig = { Moves = {}, Projectiles = {} }
	return _attackConfig
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------

function AttackRegistry:Init()
	if _loaded then return end
	_loaded = true

	local attacksFolder = ServerStorage:FindFirstChild("Services")
		and ServerStorage.Services:FindFirstChild("Attacks")
	if not attacksFolder then
		warn("[AttackRegistry] Attacks folder not found under Services")
		return
	end

	-- Load Melee modules
	local melee = attacksFolder:FindFirstChild("Melee")
	if melee then
		for _, mod in ipairs(melee:GetChildren()) do
			if mod:IsA("ModuleScript") then
				local ok, result = pcall(require, mod)
				if ok and type(result) == "table" and result.Name then
					_modules[result.Name] = result
					dprint("Loaded melee attack:", result.Name)
				else
					warn("[AttackRegistry] Failed to load:", mod.Name, result)
				end
			end
		end
	end

	-- Load Projectile modules
	local projectile = attacksFolder:FindFirstChild("Projectile")
	if projectile then
		for _, mod in ipairs(projectile:GetChildren()) do
			if mod:IsA("ModuleScript") then
				local ok, result = pcall(require, mod)
				if ok and type(result) == "table" and result.Name then
					_modules[result.Name] = result
					dprint("Loaded projectile attack:", result.Name)
				else
					warn("[AttackRegistry] Failed to load:", mod.Name, result)
				end
			end
		end
	end

	dprint("Init complete.", "Loaded", self:_countModules(), "attack modules")
end

function AttackRegistry:_countModules(): number
	local n = 0
	for _ in pairs(_modules) do n += 1 end
	return n
end

----------------------------------------------------------------------
-- Module access
----------------------------------------------------------------------

--- Get an attack module by name.
function AttackRegistry:GetModule(name: string): any?
	return _modules[name]
end

--- Get the config for a move from AttackConfig.Moves.
function AttackRegistry:GetMoveConfig(moveName: string): any?
	local cfg = getAttackConfig()
	return cfg.Moves and cfg.Moves[moveName]
end

--- Get projectile config by skin name.
function AttackRegistry:GetProjectileConfig(skinName: string): any?
	local cfg = getAttackConfig()
	return cfg.Projectiles and cfg.Projectiles[skinName]
end

----------------------------------------------------------------------
-- Move selection
----------------------------------------------------------------------

--- Initialize per-entry attack state (call when registering a brainrot in AIService).
function AttackRegistry:InitEntry(entry: any)
	entry._attackCooldowns = entry._attackCooldowns or {}
	entry._lastMoveUsed = nil
end

--- Check if a specific move is off cooldown for this entry.
function AttackRegistry:IsOffCooldown(entry: any, moveName: string): boolean
	local cooldowns = entry._attackCooldowns or {}
	local lastUsed = cooldowns[moveName]
	if not lastUsed then return true end

	local moveCfg = self:GetMoveConfig(moveName)
	local cd = (moveCfg and moveCfg.Cooldown) or 1.0

	-- Apply effective multiplier (size scaling affects cooldown)
	local effectiveMult = entry.Model and entry.Model:GetAttribute("EffectiveMultiplier")
	if typeof(effectiveMult) == "number" and effectiveMult > 0 then
		cd = cd / effectiveMult
	end

	return os.clock() - lastUsed >= cd
end

--- Record that a move was used (sets cooldown timestamp).
function AttackRegistry:RecordUse(entry: any, moveName: string)
	if not entry._attackCooldowns then
		entry._attackCooldowns = {}
	end
	entry._attackCooldowns[moveName] = os.clock()
	entry._lastMoveUsed = moveName
end

--- Pick the best move for the current situation.
--- Parameters:
---   entry: AIEntry with HRP, Model, EnemyInfo, etc.
---   target: Player target
---   dist: current distance to target
---   personality: personality config table (with PreferRanged, HeavyAttackBias, etc.)
---   availableMoves: list of move names this brainrot can use
--- Returns: moveName, moveModule, moveConfig (or nil if nothing valid)
function AttackRegistry:PickMove(
	entry: any,
	target: any,
	dist: number,
	personality: { [string]: any },
	availableMoves: { string }
): (string?, any?, any?)
	if #availableMoves == 0 then return nil, nil, nil end

	-- Gather valid candidates (off cooldown + in range + CanExecute)
	local meleeCandidates: { { name: string, mod: any, cfg: any, weight: string } } = {}
	local rangedCandidates: { { name: string, mod: any, cfg: any, weight: string } } = {}

	for _, moveName in ipairs(availableMoves) do
		local mod = _modules[moveName]
		local cfg = self:GetMoveConfig(moveName)
		if not mod or not cfg then continue end

		-- Check cooldown
		if not self:IsOffCooldown(entry, moveName) then continue end

		-- Check range
		local range = cfg.Range or 6
		if dist > range * 1.2 then continue end -- allow slight overshoot

		-- Check module-level CanExecute if it exists
		if type(mod.CanExecute) == "function" then
			local canExec = mod:CanExecute(entry, target, dist)
			if not canExec then continue end
		end

		local candidate = { name = moveName, mod = mod, cfg = cfg, weight = cfg.Weight or "Light" }

		if cfg.Type == "Projectile" then
			table.insert(rangedCandidates, candidate)
		else
			table.insert(meleeCandidates, candidate)
		end
	end

	-- Decide melee vs ranged preference
	local preferRanged = (personality and personality.PreferRanged) or 0.3
	local heavyBias = (personality and personality.HeavyAttackBias) or 0.3

	local candidates: typeof(meleeCandidates)
	local hasMelee = #meleeCandidates > 0
	local hasRanged = #rangedCandidates > 0

	if hasMelee and hasRanged then
		-- Distance-based adjustment: farther = more likely ranged
		local rangeFactor = math.clamp(dist / 20, 0, 1)
		local rangedChance = preferRanged + rangeFactor * 0.4
		if math.random() < rangedChance then
			candidates = rangedCandidates
		else
			candidates = meleeCandidates
		end
	elseif hasRanged then
		candidates = rangedCandidates
	elseif hasMelee then
		candidates = meleeCandidates
	else
		return nil, nil, nil -- nothing valid
	end

	-- Within chosen category, pick light vs heavy
	local lightCandidates: typeof(meleeCandidates) = {}
	local heavyCandidates: typeof(meleeCandidates) = {}
	for _, c in ipairs(candidates) do
		if c.weight == "Heavy" then
			table.insert(heavyCandidates, c)
		else
			table.insert(lightCandidates, c)
		end
	end

	local pool: typeof(meleeCandidates)
	if #heavyCandidates > 0 and #lightCandidates > 0 then
		if math.random() < heavyBias then
			pool = heavyCandidates
		else
			pool = lightCandidates
		end
	elseif #heavyCandidates > 0 then
		pool = heavyCandidates
	else
		pool = lightCandidates
	end

	if #pool == 0 then pool = candidates end

	-- Random pick from pool
	local pick = pool[math.random(1, #pool)]
	return pick.name, pick.mod, pick.cfg
end

--- Get the maximum effective range across all available moves for this brainrot.
--- Used by AIService to determine when to stop chasing and start attacking.
function AttackRegistry:GetMaxRange(availableMoves: { string }): number
	local maxRange = 6
	for _, moveName in ipairs(availableMoves) do
		local cfg = self:GetMoveConfig(moveName)
		if cfg and cfg.Range and cfg.Range > maxRange then
			maxRange = cfg.Range
		end
	end
	return maxRange
end

--- Get the minimum range (for positioning — don't get closer than melee range if you have ranged).
function AttackRegistry:GetMinRange(availableMoves: { string }): number
	local minRange = 999
	for _, moveName in ipairs(availableMoves) do
		local cfg = self:GetMoveConfig(moveName)
		if cfg and cfg.Range and cfg.Range < minRange then
			minRange = cfg.Range
		end
	end
	return minRange < 999 and minRange or 6
end

return AttackRegistry
