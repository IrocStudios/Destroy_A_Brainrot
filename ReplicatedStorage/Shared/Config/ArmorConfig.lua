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

ArmorConfig.StartPrice  = 1000    -- step 0 costs $1,000
ArmorConfig.PriceGrowth = 1.15    -- ~15 % more per step → step 99 ≈ $1B

-- Brackets: each defines a run of steps and the armor awarded per step.
-- Players progress through brackets in order.
ArmorConfig.Brackets = {
	{ steps = 10, amount = 5     },  -- Steps  0-9:   +5      (50 total)
	{ steps = 10, amount = 10    },  -- Steps 10-19:  +10     (100 → 150 cumul)
	{ steps = 10, amount = 25    },  -- Steps 20-29:  +25     (250 → 400)
	{ steps = 10, amount = 50    },  -- Steps 30-39:  +50     (500 → 900)
	{ steps = 10, amount = 100   },  -- Steps 40-49:  +100    (1,000 → 1,900)
	{ steps = 10, amount = 250   },  -- Steps 50-59:  +250    (2,500 → 4,400)
	{ steps = 10, amount = 500   },  -- Steps 60-69:  +500    (5,000 → 9,400)
	{ steps = 10, amount = 1000  },  -- Steps 70-79:  +1,000  (10,000 → 19,400)
	{ steps = 10, amount = 2500  },  -- Steps 80-89:  +2,500  (25,000 → 44,400)
	{ steps = 10, amount = 5000  },  -- Steps 90-99:  +5,000  (50,000 → 94,400)
	{ steps = 1,  amount = 5600, price = 1500000000 }, -- Step 100: +5,600 (→ 100,000) @ $1.5B
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

	-- Price: bracket override or exponential formula
	local price = customPrice or math.floor(ArmorConfig.StartPrice * ArmorConfig.PriceGrowth ^ step)
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
