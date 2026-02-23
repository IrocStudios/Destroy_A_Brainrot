-- ReplicatedStorage/Shared/Config/EconomyConfig.lua
-- Global economy tuning. Data-only.

local EconomyConfig = {
	Version = 1,

	-- Starting balances for new players
	StartingCash = 120,

	-- Global multipliers (events / seasons can bump these)
	GlobalCashMultiplier = 1.00,
	GlobalXPMultiplier = 1.00,

	-- Money stack drop behavior on brainrot death
	-- (Your RewardService decides how it spawns; this is just the tuning.)
	MoneyStackMin = 1,
	MoneyStackMax = 15,
	MoneyScatterRadius = 14, -- studs around death position
	MoneyLifetime = 22, -- seconds before cleanup (if not collected)

	-- Rebirth bonuses (stacking rules controlled by services)
	-- Recommended interpretation: each rebirth adds these bonuses on top of previous.
	RebirthCashMultiplierBonus = 0.12, -- +12% cash per rebirth
	RebirthXPBonus = 0.08, -- +8% XP per rebirth

	-- How to round per-player earnings (value * damage/maxHealth).
	-- Examples: "Floor", "Round", "Ceil", "FloorToNearest5"
	DropValueRoundingRule = "FloorToNearest5",

	-- Optional gift drop baseline (if your RewardService uses a base chance)
	-- RarityConfig.GiftChanceMultiplier can multiply this.
	BaseGiftChance = 0.035, -- 3.5% at Common baseline
}

return EconomyConfig