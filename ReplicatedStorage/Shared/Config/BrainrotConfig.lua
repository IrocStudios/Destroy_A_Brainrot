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
	-- Noobini Pizzanini — the starter brainrot
	-- Passive/fearful. Spots you from far away (75 studs) but only throws
	-- up to 50 studs. If you get within 6 studs, he panics and RUNS.
	-- No melee — pure ranged coward.
	-----------------------------------------------------------------------
	["Noobini_Pizzanini"] = {
		DisplayName = "Noobini Pizzanini",

		Health = 100,
		Walkspeed = 10,
		Runspeed = 14,

		Attackspeed = 20,
		HealRate = 0,

		AttackDamage = 5,
		AttackRange = 50,     -- throw detection range (doubled from 25)
		AttackCooldown = 2.0,

		Price = 100,

		RarityName = "Common",
		Personality = "Fearful",
		LocomotionType = "Walk",

		-- Ranged only — no melee, just runs if you get close
		AttackMoves = { "StandAndHurl" },

		-- Per-brainrot personality overrides (merged on top of Fearful defaults)
		PersonalityOverrides = {
			AggroDistance = 75,        -- spots you from 75 studs (tripled)
			ChaseRange = 30,          -- gives up quickly
			AttackChance = 0.04,      -- rarely initiates
			RunChance = 0.85,
			RunWhenAttacked = 0.90,
			FearDistance = 6,          -- panics and runs at ~6 studs
			Forgive = 0.95,
			ForgiveTime = 6,
			PreferRanged = 1.0,       -- always throws, never melee
			HeavyAttackBias = 0.0,
			RetaliateOnDamage = true,
			RetaliateAggression = 0.10, -- almost always flees when hit
			PursuitTenacity = 0.0,
			CorneredAggression = 0.3,  -- even cornered, tries to flee
		},

		-- Override StandAndHurl range, projectile, accuracy, and cooldown for this brainrot
		MoveOverrides = {
			StandAndHurl = {
				Range = 50,
				Projectile = "Pizza",
				Spread = 8,         -- very inaccurate throws
				Cooldown = 4.0,     -- throws slowly (every ~4.5s with windup)
				WindupTime = 0.6,   -- slow clumsy windup
				MinRange = 10,      -- won't throw if player is closer than 10 studs
			},
		},
	},

	-----------------------------------------------------------------------
	-- Garamararam — passive until provoked, then relentless charger
	-- Normally slow (walk 6), speeds up chasing (12), charges at 16.
	-- Won't forgive — once aggro'd, stays locked on.
	-----------------------------------------------------------------------
	["Garamararam"] = {
		DisplayName = "Garamararam",

		Health = 250,
		Walkspeed = 6,
		Runspeed = 12,           -- chase speed

		Attackspeed = 18,
		HealRate = 0,

		AttackDamage = 15,
		AttackRange = 7,
		AttackCooldown = 1.8,

		Price = 500,

		RarityName = "Common",
		Personality = "Passive",
		LocomotionType = "Charge", -- uses ChargeLocomotion (1.8x burst → ~16 walkspeed during charge)

		-- Melee only — no projectiles
		AttackMoves = { "BasicMelee", "HeavyMelee" },

		PersonalityOverrides = {
			AggroDistance = 20,        -- doesn't notice until close
			ChaseRange = 120,          -- once aggro'd, chases far
			AttackChance = 0.08,       -- rarely attacks unprovoked
			RunChance = 0.05,          -- almost never runs
			RunWhenAttacked = 0.03,    -- fights back instead
			FearTime = 1.0,
			Forgive = 0.05,            -- almost never forgives
			ForgiveTime = 30,          -- remembers for a long time
			ForgiveDistance = 80,       -- has to be very far to forgive
			RetaliateOnDamage = true,
			RetaliateAggression = 0.95, -- almost always retaliates
			PursuitTenacity = 0.90,    -- very persistent chaser
			HeavyAttackBias = 0.35,    -- sometimes uses heavy melee
			CorneredAggression = 1.0,
			LeashStrength = 0.3,       -- will leave territory to chase
		},
	},

	-----------------------------------------------------------------------
	-- Burbaloni Loliloli — giant rat/mole, territorial melee brawler
	-- Somewhat territorial: attacks on approach, may run if damaged but
	-- likely to attack back. Charge = "running over" (~20% chance).
	-- Scratch/paw swipe otherwise. No projectiles.
	-----------------------------------------------------------------------
	["Burbaloni_Loliloli"] = {
		DisplayName = "Burbaloni Loliloli",

		Health = 300,
		Walkspeed = 8,
		Runspeed = 14,

		Attackspeed = 22,
		HealRate = 0,

		AttackDamage = 12,
		AttackRange = 6,
		AttackCooldown = 1.4,

		Price = 600,

		RarityName = "Common",
		Personality = "Territorial",
		LocomotionType = "Charge", -- charge = "running them over"

		-- Melee only — scratch/swipe (BasicMelee ~80%) + charge/trample (HeavyMelee ~20%)
		AttackMoves = { "BasicMelee", "HeavyMelee" },

		PersonalityOverrides = {
			AggroDistance = 35,        -- notices you approaching territory
			ChaseRange = 70,           -- chases within territory range
			AttackChance = 0.55,       -- likely to attack on sight
			RunChance = 0.20,          -- may run if damaged
			RunWhenAttacked = 0.25,    -- more likely to fight than flee
			FearTime = 1.5,
			FearDistance = 25,
			Forgive = 0.50,
			ForgiveTime = 12,
			RetaliateOnDamage = true,
			RetaliateAggression = 0.75,
			PursuitTenacity = 0.45,
			HeavyAttackBias = 0.20,    -- ~20% charge/trample, ~80% scratch
			CorneredAggression = 0.90,
			LeashStrength = 0.85,      -- stays near territory
		},

		MoveOverrides = {
			BasicMelee = { WindupTime = 0.15, DamageMult = 0.9 },   -- quick scratch
			HeavyMelee = { WindupTime = 0.4, DamageMult = 1.8, Range = 8 }, -- charge/trample
		},

		-- Pack animal: signals nearby Burbalonis to share attack/flee state
		-- SignalRange = 0.5 means half the territory size
		PackBehavior = {
			Enabled = true,
			SignalRange = 0.5,
			ShareStates = { "Chase", "Flee" },
		},
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