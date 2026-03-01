-- ReplicatedStorage/Shared/Config/SpeedConfig.lua
-- Step-based speed progression.
--
-- Speed is a persistent upgrade number:
--   • Each purchase adds +1 to WalkSpeed (via SpeedBoost delta).
--   • Base speed = 16, max speed = 120 → 104 total steps.
--   • Price grows exponentially: price = StartPrice * PriceGrowth ^ step
--     → Step 0 ≈ $500, Step 103 ≈ $900M
--   • Persistent unless inventory is 'dropped' on death.

local SpeedConfig = {}

SpeedConfig.BaseSpeed     = 16     -- Roblox default walk speed
SpeedConfig.MaxSpeed      = 120    -- maximum walk speed after all upgrades
SpeedConfig.SpeedPerStep  = 1      -- each purchase adds +1 speed

SpeedConfig.StartPrice    = 550    -- step 0 costs $550 (10% above base)
SpeedConfig.PriceGrowth   = 1.15   -- ~15% more per step (consistent with ArmorConfig)

-- Derived constants
SpeedConfig._maxSteps = math.floor((SpeedConfig.MaxSpeed - SpeedConfig.BaseSpeed) / SpeedConfig.SpeedPerStep) -- 104
SpeedConfig._maxBoost = SpeedConfig.MaxSpeed - SpeedConfig.BaseSpeed -- 104

function SpeedConfig.GetMaxSteps(): number
	return SpeedConfig._maxSteps -- 104
end

function SpeedConfig.GetMaxBoost(): number
	return SpeedConfig._maxBoost -- 104
end

--- Returns (amount, price) for a given step index (0-based).
--- amount = speed bonus from this single purchase (+1 always).
--- Returns (0, 0) if already maxed.
function SpeedConfig.GetStep(step: number): (number, number)
	if step >= SpeedConfig._maxSteps then
		return 0, 0
	end

	local price = math.floor(SpeedConfig.StartPrice * SpeedConfig.PriceGrowth ^ step)
	return SpeedConfig.SpeedPerStep, price
end

--- Returns total speed bonus for a player at a given step count.
--- SpeedBoost = steps * SpeedPerStep (capped at _maxBoost).
function SpeedConfig.GetBoostForStep(step: number): number
	return math.min(step * SpeedConfig.SpeedPerStep, SpeedConfig._maxBoost)
end

--- Given a current speed boost value, determine the effective step.
--- effectiveStep = floor(currentBoost / SpeedPerStep), clamped to [0, _maxSteps].
function SpeedConfig.GetEffectiveStep(currentBoost: number): number
	if currentBoost <= 0 then return 0 end
	return math.min(math.floor(currentBoost / SpeedConfig.SpeedPerStep), SpeedConfig._maxSteps)
end

return SpeedConfig
