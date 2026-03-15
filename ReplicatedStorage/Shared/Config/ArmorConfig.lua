-- ReplicatedStorage/Shared/Config/ArmorConfig.lua
-- Bracket-based armor progression.
--
-- Armor is a single "chargeable" number:
--   • Each purchase adds armor (amount escalates through brackets).
--   • Taking damage subtracts armor. Overflow hits health.
--   • Once all steps are purchased, armor is maxed.
--
-- Amount per step grows through 10 brackets (10 steps each) + 1 final step = 101 total.
-- Price grows exponentially: price = StartPrice * PriceGrowth ^ step
--   → Step 0 ≈ $1k, Step 99 ≈ $1B, Step 100 = $1.5B (final capstone)

local ArmorConfig = {}

ArmorConfig.StartPrice  = 500     -- step 0 costs $500 (cheaper early curve)
ArmorConfig.PriceGrowth = 1.158   -- ~15.8 % more per step → converges to ~$1B at step 99

-- Brackets: each defines a run of steps and the armor awarded per step.
-- Players progress through brackets in order.
ArmorConfig.Brackets = {
	{ steps = 10, amount = 10    },  -- Steps  0-9:   +10     (100 total)
	{ steps = 10, amount = 20    },  -- Steps 10-19:  +20     (200 → 300 cumul)
	{ steps = 10, amount = 50    },  -- Steps 20-29:  +50     (500 → 800)
	{ steps = 10, amount = 100   },  -- Steps 30-39:  +100    (1,000 → 1,800)
	{ steps = 10, amount = 200   },  -- Steps 40-49:  +200    (2,000 → 3,800)
	{ steps = 10, amount = 500   },  -- Steps 50-59:  +500    (5,000 → 8,800)
	{ steps = 10, amount = 1000  },  -- Steps 60-69:  +1,000  (10,000 → 18,800)
	{ steps = 10, amount = 2000  },  -- Steps 70-79:  +2,000  (20,000 → 38,800)
	{ steps = 10, amount = 5000  },  -- Steps 80-89:  +5,000  (50,000 → 88,800)
	{ steps = 10, amount = 10000 },  -- Steps 90-99:  +10,000 (100,000 → 188,800)
	{ steps = 1,  amount = 11200, price = 1500000000 }, -- Step 100: +11,200 (→ 200,000) @ $1.5B
}

-- Precompute totals from brackets
ArmorConfig._maxSteps = 0
ArmorConfig._maxArmor = 0
for _, b in ipairs(ArmorConfig.Brackets) do
	ArmorConfig._maxSteps += b.steps
	ArmorConfig._maxArmor += b.steps * b.amount
end

function ArmorConfig.GetMaxSteps(): number
	return ArmorConfig._maxSteps -- 101
end

function ArmorConfig.GetMaxArmor(): number
	return ArmorConfig._maxArmor -- 100,000
end

-- Returns (amount, price) for a given step index (0-based).
-- Returns (0, 0) if already maxed.
function ArmorConfig.GetStep(step: number): (number, number)
	if step >= ArmorConfig._maxSteps then
		return 0, 0
	end

	-- Find which bracket this step falls in
	local amount = 0
	local customPrice = nil
	local remaining = step
	for _, b in ipairs(ArmorConfig.Brackets) do
		if remaining < b.steps then
			amount = b.amount
			customPrice = b.price -- optional per-bracket override
			break
		end
		remaining -= b.steps
	end

	-- Price: cheap intro ramp for first 5 steps, then normal exponential curve
	local raw
	if customPrice then
		raw = customPrice
	elseif step < 5 then
		-- Steps 0-4: $100 → $750, easing into the exponential curve at step 5 (~$1k)
		local introRamp = { 100, 200, 350, 500, 750 }
		raw = introRamp[step + 1]
	else
		-- Steps 5+: normal exponential curve (starting where step 5 would naturally land)
		raw = math.floor(ArmorConfig.StartPrice * ArmorConfig.PriceGrowth ^ step)
	end
	local price = math.floor(raw / 100 + 0.5) * 100  -- round to nearest 100
	if price < 100 then price = 100 end               -- minimum $100
	return amount, price
end

--- Given a current armor value, determine the effective step.
--- This is the step index the player is "at" based on their actual armor.
--- Used for pricing: losing armor to damage lowers the effective step → cheaper price.
function ArmorConfig.GetEffectiveStep(currentArmor: number): number
	if currentArmor <= 0 then return 0 end
	if currentArmor >= ArmorConfig._maxArmor then return ArmorConfig._maxSteps end

	local cumulative = 0
	local stepIdx = 0
	for _, b in ipairs(ArmorConfig.Brackets) do
		for _ = 1, b.steps do
			cumulative += b.amount
			if cumulative > currentArmor then
				return stepIdx
			end
			stepIdx += 1
		end
	end
	return ArmorConfig._maxSteps
end

return ArmorConfig
