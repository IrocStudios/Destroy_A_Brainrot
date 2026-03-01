-- ServerStorage/Services/RewardGranter.lua
-- Universal reward granting utility (server-only).
-- NOT a service (no Init/Start lifecycle). Other services require() it directly.
--
-- Call Setup(services) once during the owning service's Init, then use:
--   RewardGranter.Grant(player, entry) → (success, description)
--   RewardGranter.GrantBatch(player, entries) → array of { entry, success, description }
--
-- Supports kinds: Cash, XP, Weapon, ArmorStep, SpeedStep, Boost

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RewardGranter = {}

local _services = nil
local _SpeedConfig = nil
local _ArmorConfig = nil

----------------------------------------------------------------------
-- Setup: called once with the services table
----------------------------------------------------------------------
function RewardGranter.Setup(services)
	_services = services

	-- Require configs (safe)
	local ConfigFolder = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Config")

	if ConfigFolder then
		local ok1, mod1 = pcall(require, ConfigFolder:FindFirstChild("SpeedConfig"))
		if ok1 then _SpeedConfig = mod1 end

		local ok2, mod2 = pcall(require, ConfigFolder:FindFirstChild("ArmorConfig"))
		if ok2 then _ArmorConfig = mod2 end
	end
end

----------------------------------------------------------------------
-- Grant: award a single reward entry to a player
-- Returns (success: boolean, description: string)
----------------------------------------------------------------------
function RewardGranter.Grant(player, entry)
	if type(entry) ~= "table" then
		return false, "InvalidEntry"
	end
	if not _services then
		warn("[RewardGranter] Setup() not called yet")
		return false, "NotSetup"
	end

	local kind = entry.kind

	--------------------------------------------------------------
	-- Cash
	--------------------------------------------------------------
	if kind == "Cash" then
		local amount = math.floor(tonumber(entry.amount) or 0)
		if amount <= 0 then return false, "InvalidAmount" end
		if _services.EconomyService then
			_services.EconomyService:AddCash(player, amount, "LootReward")
		end
		return true, ("+$%d Cash"):format(amount)

	--------------------------------------------------------------
	-- XP
	--------------------------------------------------------------
	elseif kind == "XP" then
		local amount = math.floor(tonumber(entry.amount) or 0)
		if amount <= 0 then return false, "InvalidAmount" end
		if _services.ProgressionService then
			_services.ProgressionService:AddXP(player, amount, "LootReward")
		end
		return true, ("+%d XP"):format(amount)

	--------------------------------------------------------------
	-- Weapon
	--------------------------------------------------------------
	elseif kind == "Weapon" then
		local weaponKey = entry.weaponKey
		if type(weaponKey) ~= "string" or weaponKey == "" then
			return false, "MissingWeaponKey"
		end

		-- Duplicate check: if owned, give cash fallback
		if _services.InventoryService and _services.InventoryService:OwnsWeapon(player, weaponKey) then
			local fallback = math.floor(tonumber(entry.dupeCashValue) or 500)
			if _services.EconomyService then
				_services.EconomyService:AddCash(player, fallback, "DupeWeaponFallback")
			end
			return true, ("+$%d (duplicate weapon)"):format(fallback)
		end

		if _services.InventoryService then
			_services.InventoryService:GrantTool(player, weaponKey)
		end
		return true, ("Weapon: %s"):format(weaponKey)

	--------------------------------------------------------------
	-- ArmorStep: grant N armor step upgrades
	--------------------------------------------------------------
	elseif kind == "ArmorStep" then
		local steps = math.max(1, math.floor(tonumber(entry.steps) or 1))

		if not _ArmorConfig or not _services.ArmorService then
			return false, "ArmorServiceUnavailable"
		end

		local totalAdded = 0
		for _ = 1, steps do
			local currentArmor = _services.ArmorService:GetArmor(player)
			local effectiveStep = _ArmorConfig.GetEffectiveStep(currentArmor)
			local amount = _ArmorConfig.GetStep(effectiveStep)
			if amount <= 0 then break end -- maxed out

			_services.ArmorService:AddArmor(player, amount)
			_services.ArmorService:IncrementStep(player)
			totalAdded = totalAdded + amount
		end

		return true, ("+%d Armor (%d step%s)"):format(totalAdded, steps, steps > 1 and "s" or "")

	--------------------------------------------------------------
	-- SpeedStep: grant N speed step upgrades
	--------------------------------------------------------------
	elseif kind == "SpeedStep" then
		local steps = math.max(1, math.floor(tonumber(entry.steps) or 1))

		if not _SpeedConfig or not _services.DataService then
			return false, "SpeedConfigUnavailable"
		end

		local granted = 0
		for _ = 1, steps do
			local currentStep = _services.DataService:GetValue(player, "Progression.SpeedStep") or 0
			local amount = _SpeedConfig.GetStep(currentStep)
			if amount == 0 then break end -- maxed out

			local newStep = currentStep + 1
			_services.DataService:SetValue(player, "Progression.SpeedStep", newStep)

			-- Sync deltas to client
			if _services.NetService then
				local speedBoost = _SpeedConfig.GetBoostForStep(newStep)
				_services.NetService:QueueDelta(player, "SpeedBoost", speedBoost)
				_services.NetService:QueueDelta(player, "SpeedStep", newStep)
				_services.NetService:FlushDelta(player)
			end

			granted = granted + 1
		end

		return true, ("+%d Speed Step%s"):format(granted, granted > 1 and "s" or "")

	--------------------------------------------------------------
	-- Boost: timed multiplier
	--------------------------------------------------------------
	elseif kind == "Boost" then
		local boostType = tostring(entry.boostType or "CashMult")
		local mult = tonumber(entry.mult) or 1.5
		local duration = tonumber(entry.duration) or 300

		if _services.DataService then
			_services.DataService:AddTimedBoost(player, boostType, mult, duration)
		end
		return true, ("%.1fx %s for %ds"):format(mult, boostType, duration)
	end

	warn(("[RewardGranter] Unknown kind: %s"):format(tostring(kind)))
	return false, "UnknownKind"
end

----------------------------------------------------------------------
-- GrantBatch: grant multiple reward entries
-- Returns array of { entry, success, description }
----------------------------------------------------------------------
function RewardGranter.GrantBatch(player, entries)
	if type(entries) ~= "table" then
		return {}
	end
	local results = table.create(#entries)
	for i, entry in ipairs(entries) do
		local ok, desc = RewardGranter.Grant(player, entry)
		results[i] = { entry = entry, success = ok, description = desc }
	end
	return results
end

return RewardGranter
