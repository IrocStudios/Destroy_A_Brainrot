-- ReplicatedStorage/Shared/Config/GiftConfig.lua
-- Per-rarity gift loot table definitions.
-- Each gift has a weighted loot table and pity config.
-- Reward amounts are placeholder values — tune after playtesting.

local GiftConfig = {}

GiftConfig.Gifts = {
	--------------------------------------------------------------
	-- COMMON (Rarity 1)
	--------------------------------------------------------------
	Common = {
		displayName = "Common Gift",
		rarity = 1,
		pity = { threshold = 15, minTier = 3 },
		loot = {
			{ weight = 50, kind = "Cash",  amount = 200,   tier = 1 },
			{ weight = 30, kind = "XP",    amount = 50,    tier = 1 },
			{ weight = 12, kind = "Cash",  amount = 800,   tier = 2 },
			{ weight = 5,  kind = "XP",    amount = 200,   tier = 2 },
			{ weight = 2,  kind = "ArmorStep", steps = 1,  tier = 3 },
			{ weight = 1,  kind = "SpeedStep", steps = 1,  tier = 3 },
		},
	},

	--------------------------------------------------------------
	-- UNCOMMON (Rarity 2)
	--------------------------------------------------------------
	Uncommon = {
		displayName = "Uncommon Gift",
		rarity = 2,
		pity = { threshold = 12, minTier = 3 },
		loot = {
			{ weight = 40, kind = "Cash",  amount = 600,   tier = 1 },
			{ weight = 25, kind = "XP",    amount = 120,   tier = 1 },
			{ weight = 15, kind = "Cash",  amount = 2000,  tier = 2 },
			{ weight = 8,  kind = "ArmorStep", steps = 1,  tier = 2 },
			{ weight = 5,  kind = "SpeedStep", steps = 1,  tier = 3 },
			{ weight = 4,  kind = "Cash",  amount = 5000,  tier = 3 },
			{ weight = 3,  kind = "XP",    amount = 500,   tier = 3 },
		},
	},

	--------------------------------------------------------------
	-- RARE (Rarity 3)
	--------------------------------------------------------------
	Rare = {
		displayName = "Rare Gift",
		rarity = 3,
		pity = { threshold = 10, minTier = 4 },
		loot = {
			{ weight = 35, kind = "Cash",  amount = 2000,  tier = 2 },
			{ weight = 20, kind = "XP",    amount = 400,   tier = 2 },
			{ weight = 15, kind = "ArmorStep", steps = 2,  tier = 3 },
			{ weight = 10, kind = "SpeedStep", steps = 2,  tier = 3 },
			{ weight = 8,  kind = "Cash",  amount = 8000,  tier = 3 },
			{ weight = 7,  kind = "Cash",  amount = 15000, tier = 4 },
			{ weight = 3,  kind = "Boost", boostType = "CashMult", mult = 1.25, duration = 600, tier = 4 },
			{ weight = 2,  kind = "ArmorStep", steps = 5,  tier = 5 },
		},
	},

	--------------------------------------------------------------
	-- EPIC (Rarity 4)
	--------------------------------------------------------------
	Epic = {
		displayName = "Epic Gift",
		rarity = 4,
		pity = { threshold = 8, minTier = 5 },
		loot = {
			{ weight = 30, kind = "Cash",  amount = 8000,  tier = 3 },
			{ weight = 15, kind = "XP",    amount = 1000,  tier = 3 },
			{ weight = 12, kind = "ArmorStep", steps = 3,  tier = 3 },
			{ weight = 10, kind = "SpeedStep", steps = 3,  tier = 4 },
			{ weight = 10, kind = "Cash",  amount = 25000, tier = 4 },
			{ weight = 8,  kind = "ArmorStep", steps = 5,  tier = 5 },
			{ weight = 5,  kind = "Boost", boostType = "CashMult", mult = 1.5, duration = 900, tier = 5 },
			{ weight = 5,  kind = "Boost", boostType = "XPMult",   mult = 1.5, duration = 900, tier = 5 },
			{ weight = 5,  kind = "SpeedStep", steps = 5,  tier = 5 },
		},
	},

	--------------------------------------------------------------
	-- LEGENDARY (Rarity 5)
	--------------------------------------------------------------
	Legendary = {
		displayName = "Legendary Gift",
		rarity = 5,
		pity = { threshold = 6, minTier = 5 },
		loot = {
			{ weight = 25, kind = "Cash",  amount = 30000, tier = 3 },
			{ weight = 15, kind = "XP",    amount = 3000,  tier = 3 },
			{ weight = 12, kind = "ArmorStep", steps = 5,  tier = 4 },
			{ weight = 10, kind = "SpeedStep", steps = 5,  tier = 4 },
			{ weight = 10, kind = "Cash",  amount = 80000, tier = 5 },
			{ weight = 8,  kind = "Boost", boostType = "CashMult", mult = 2.0, duration = 1200, tier = 5 },
			{ weight = 8,  kind = "ArmorStep", steps = 8,  tier = 5 },
			{ weight = 5,  kind = "Boost", boostType = "LuckMult", mult = 1.5, duration = 1200, tier = 6 },
			{ weight = 5,  kind = "SpeedStep", steps = 8,  tier = 6 },
			{ weight = 2,  kind = "Cash",  amount = 200000, tier = 6 },
		},
	},

	--------------------------------------------------------------
	-- MYTHIC (Rarity 6)
	--------------------------------------------------------------
	Mythic = {
		displayName = "Mythic Gift",
		rarity = 6,
		pity = { threshold = 5, minTier = 6 },
		loot = {
			{ weight = 20, kind = "Cash",  amount = 100000, tier = 4 },
			{ weight = 12, kind = "XP",    amount = 8000,   tier = 4 },
			{ weight = 10, kind = "ArmorStep", steps = 8,   tier = 5 },
			{ weight = 10, kind = "SpeedStep", steps = 8,   tier = 5 },
			{ weight = 12, kind = "Cash",  amount = 250000, tier = 5 },
			{ weight = 8,  kind = "Boost", boostType = "CashMult", mult = 2.5, duration = 1800, tier = 6 },
			{ weight = 8,  kind = "Boost", boostType = "XPMult",   mult = 2.5, duration = 1800, tier = 6 },
			{ weight = 5,  kind = "Cash",  amount = 500000, tier = 6 },
			{ weight = 5,  kind = "SpeedStep", steps = 12,  tier = 6 },
			{ weight = 5,  kind = "Boost", boostType = "LuckMult", mult = 2.0, duration = 1800, tier = 7 },
			{ weight = 5,  kind = "ArmorStep", steps = 12,  tier = 7 },
		},
	},

	--------------------------------------------------------------
	-- TRANSCENDENT (Rarity 7)
	--------------------------------------------------------------
	Transcendent = {
		displayName = "Transcendent Gift",
		rarity = 7,
		pity = { threshold = 3, minTier = 7 },
		loot = {
			{ weight = 15, kind = "Cash",  amount = 500000,  tier = 5 },
			{ weight = 10, kind = "XP",    amount = 20000,   tier = 5 },
			{ weight = 10, kind = "ArmorStep", steps = 10,   tier = 6 },
			{ weight = 10, kind = "SpeedStep", steps = 10,   tier = 6 },
			{ weight = 12, kind = "Cash",  amount = 1000000, tier = 6 },
			{ weight = 10, kind = "Boost", boostType = "CashMult", mult = 3.0, duration = 3600, tier = 6 },
			{ weight = 10, kind = "Boost", boostType = "XPMult",   mult = 3.0, duration = 3600, tier = 6 },
			{ weight = 8,  kind = "Cash",  amount = 2500000, tier = 7 },
			{ weight = 8,  kind = "Boost", boostType = "LuckMult", mult = 3.0, duration = 3600, tier = 7 },
			{ weight = 7,  kind = "SpeedStep", steps = 20,  tier = 7 },
		},
	},
}

--------------------------------------------------------------
-- Helpers
--------------------------------------------------------------

GiftConfig.RarityToKey = {
	[1] = "Common",
	[2] = "Uncommon",
	[3] = "Rare",
	[4] = "Epic",
	[5] = "Legendary",
	[6] = "Mythic",
	[7] = "Transcendent",
}

function GiftConfig.GetGift(rarityOrKey)
	if type(rarityOrKey) == "number" then
		local key = GiftConfig.RarityToKey[rarityOrKey]
		return key and GiftConfig.Gifts[key]
	end
	return GiftConfig.Gifts[rarityOrKey]
end

function GiftConfig.GetDisplayName(rarityOrKey)
	local gift = GiftConfig.GetGift(rarityOrKey)
	return gift and gift.displayName or "Unknown Gift"
end

return GiftConfig
