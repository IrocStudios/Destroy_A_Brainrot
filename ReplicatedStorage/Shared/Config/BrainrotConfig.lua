-- ReplicatedStorage/Shared/Config/BrainrotConfig.lua
-- Minimal baseline metadata per brainrot name (keyed by brainrotName).
-- Used by BrainrotService to populate EnemyInfo + humanoid stats and by AIService via EnemyInfo.

local BrainrotConfig = {

	-- KEEP (fallback baseline used when a brainrotName is missing)
	["Default"] = {
		DisplayName = "Default",

		-- Baseline stats
		Health = 100,
		Walkspeed = 5,
		Runspeed = 14,

		-- Optional movement/combat fields (stored in EnemyInfo; AI will use if present)
		Attackspeed = 20,
		HealRate = 0,

		AttackDamage = 10,
		AttackRange = 6,
		AttackCooldown = 1.5,

		-- Economy baseline (CombatService applies rarity multipliers on payout)
		Price = 50,

		-- Rarity + personality
		RarityName = "Common",
		Personality = "Passive",
	},

	-----------------------------------------------------------------------
	-- Example brainrots (edit/add as needed)
	-- Zone Configuration.Enemies must reference these keys
	-----------------------------------------------------------------------

	["Default2"] = {
		DisplayName = "Default 2",
		Health = 140,
		Walkspeed = 15,
		Runspeed = 21,

		AttackDamage = 12,
		AttackRange = 6.5,
		AttackCooldown = 1.35,

		Price = 85,
		RarityName = "Uncommon",
		Personality = "Skittish",
	},

	["glazed_goober"] = {
		DisplayName = "Glazed Goober",
		Health = 240,
		Walkspeed = 11,
		Runspeed = 16,

		AttackDamage = 8,
		AttackRange = 6.5,
		AttackCooldown = 1.15,

		Price = 42,
		RarityName = "Common",
		Personality = "Passive",
	},

	["tinfoil_todd"] = {
		DisplayName = "Tinfoil Todd",
		Health = 320,
		Walkspeed = 12,
		Runspeed = 18,

		AttackDamage = 10,
		AttackRange = 7.0,
		AttackCooldown = 1.10,

		Price = 58,
		RarityName = "Common",
		Personality = "Territorial",
	},

	["meme_marauder"] = {
		DisplayName = "Meme Marauder",
		Health = 520,
		Walkspeed = 12.5,
		Runspeed = 19,

		AttackDamage = 14,
		AttackRange = 7.5,
		AttackCooldown = 1.00,

		Price = 95,
		RarityName = "Uncommon",
		Personality = "Aggressive",
	},

	["doomscroll_demon"] = {
		DisplayName = "Doomscroll Demon",
		Health = 880,
		Walkspeed = 13,
		Runspeed = 20,

		AttackDamage = 20,
		AttackRange = 8.0,
		AttackCooldown = 0.95,

		Price = 165,
		RarityName = "Rare",
		Personality = "Aggressive",
	},

	["sigma_specter"] = {
		DisplayName = "Sigma Specter",
		Health = 1450,
		Walkspeed = 14,
		Runspeed = 22,

		AttackDamage = 28,
		AttackRange = 8.5,
		AttackCooldown = 0.90,

		Price = 290,
		RarityName = "Epic",
		Personality = "Territorial",
	},

	["algorithm_angel"] = {
		DisplayName = "Algorithm Angel",
		Health = 2200,
		Walkspeed = 14.5,
		Runspeed = 23,

		AttackDamage = 36,
		AttackRange = 9.0,
		AttackCooldown = 0.85,

		Price = 460,
		RarityName = "Legendary",
		Personality = "Berserk",
	},
}

return BrainrotConfig