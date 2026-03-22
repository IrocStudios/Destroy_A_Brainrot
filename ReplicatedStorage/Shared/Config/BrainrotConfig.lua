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
		Price = 120,

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

		Health = 50,
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
			TerritoryLeashPct = 0.15,  -- can wander 15% beyond territory
			LeashStrength = 0.6,       -- moderate pull back
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

		-- Named variants: each spawns at a weighted chance with unique stats/behavior.
		-- NameTag appends to DisplayName. SizeTier drives AI behavior ("baby"/"big"/"huge").
		-- StatOverrides multiply base stats. VariantMoveOverrides merge on top of base MoveOverrides.
		-- VariantPersonalityOverrides merge on top of base PersonalityOverrides.
		-- NOT a new discovery — same brainrot, different index slot.
		Variants = {
			{
				Name = "Normal",
				Weight = 80,
				-- No overrides: uses base config as-is
			},
			{
				Name = "Small",
				NameTag = "(Small)",
				Weight = 15,
				SizeMultiplier = 0.65,
				SizeTier = "baby",
				StatOverrides = {
					AttackDamage = 0.5,   -- half damage (multiplier)
				},
				VariantMoveOverrides = {
					StandAndHurl = {
						Cooldown = 2.0,   -- throws 2x faster
					},
				},
				VariantPersonalityOverrides = {
					Aggressive = 0.02,
					RunChance = 0.90,
					RunWhenAttacked = 0.95,
					RetaliateAggression = 0.05,
					PursuitTenacity = 0.0,
				},
			},
			{
				Name = "Huge",
				NameTag = "(Huge)",
				Weight = 5,
				SizeMultiplier = 1.5,
				SizeTier = "huge",
				StatOverrides = {
					Health = 1.34,        -- 50 × 1.34 = 67, × 1.5 sizeMult ≈ 100 HP
				},
				VariantMoveOverrides = {
					StandAndHurl = {
						ProjectileCount = 5,  -- fires 5 pizzas at once
						SpreadAngle = 25,     -- degrees of spread for shotgun pattern
						Cooldown = 5.0,       -- slower between volleys
						WindupTime = 0.8,     -- heavier windup
					},
				},
				VariantPersonalityOverrides = {
					Aggressive = 0.60,
					RunChance = 0.10,
					RunWhenAttacked = 0.10,
					RetaliateAggression = 0.95,
					PursuitTenacity = 0.80,
					CorneredAggression = 0.95,
				},
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

		Health = 150,
		Walkspeed = 6,
		Runspeed = 12,           -- chase speed

		Attackspeed = 19,        -- +1 charge speed
		HealRate = 0,

		AttackDamage = 11,           -- 30% reduction from original 15
		AttackRange = 7,
		AttackCooldown = 1.8,

		Price = 500,

		RarityName = "Common",
		Personality = "Passive",
		LocomotionType = "Charge", -- uses ChargeLocomotion (1.8x burst → ~16 walkspeed during charge)
		StuckHopMult = 0.7,        -- lower hops (block shape, just needs to clear seams)

		-- Melee only — no projectiles
		AttackMoves = { "BasicMelee", "HeavyMelee" },

		PersonalityOverrides = {
			AggroDistance = 28,         -- wider detection range
			ChaseRange = 200,          -- once aggro'd, chases very far
			AttackChance = 0.08,       -- rarely attacks unprovoked
			RunChance = 0,             -- NEVER runs
			RunWhenAttacked = 0,       -- NEVER flees from damage
			FearTime = 0,
			Forgive = 0,               -- never forgives mid-chase
			ForgiveTime = 999,         -- remembers for a long time
			ForgiveDistance = 200,      -- but leash distance will force return first
			RetaliateOnDamage = true,
			RetaliateAggression = 1.0,  -- always retaliates
			PursuitTenacity = 1.0,     -- never gives up chase voluntarily
			HeavyAttackBias = 0.35,    -- sometimes uses heavy melee
			CorneredAggression = 1.0,
			TerritoryLeashPct = 0.60,  -- chases up to 60% beyond territory edge
			LeashStrength = 0.15,      -- light pull, but it exists
		},

		-- Aggro curve: relentless while in range, but territory distance drains aggro
		AggroCurveOverrides = {
			DamageGain = 50,           -- one hit = instant rage
			ProximityRate = 25,        -- builds fast from proximity alone
			CorneredRate = 15,         -- low HP makes them angrier
			DecayRate = 0.5,           -- slow base decay (stays angry a long time)
			TerritoryDecayMult = 4.0,  -- BUT aggro drains fast when far from territory
			OutOfSightDecay = 3,       -- calms down if target runs out of sight
			DecayDelay = 8,            -- 8s before accelerated decay kicks in
			AccelDecayMult = 2.0,      -- accelerated decay is meaningful
			ChaseThreshold = 15,       -- very easy to trigger chase
			PursuitThreshold = 30,     -- stays committed near territory
			BerserkThreshold = 80,     -- only ignores leash at full rage
			FleeThreshold = 0,         -- will NEVER flee
		},

		MoveOverrides = {
			BasicMelee = {
				Knockback = {
					Type = "push",          -- small shove on regular hit
					Magnitude = 40,
					RagdollDuration = 0,    -- no ragdoll, just a push
				},
			},
			HeavyMelee = {
				WindupTime = 1.0,       -- slow charge-up headbutt
				DamageMult = 3.0,       -- devastating hit
				Range = 8,              -- longer reach (charge momentum)
				Knockback = {
					Type = "fling",         -- BIG exaggerated launch
					Magnitude = 140,        -- massive force
					RagdollDuration = 3.0,  -- 3 second ragdoll
				},
			},
		},

		-- Garamararam ignores knockback invulnerability — keeps ramming while you're down
		IgnoreKnockbackInvuln = true,

		Variants = {
			{
				Name = "Normal",
				Weight = 90,
			},
			{
				Name = "Big",
				NameTag = "(Big)",
				Weight = 10,              -- 10% spawn rate
				SizeMultiplier = 1.3,
				SizeTier = "big",
				VariantPrice = 1250,          -- explicit $1250 (bypasses base × sizeMult)
				StatOverrides = {
					Health = 1.077,       -- 150 × 1.077 × 1.3 ≈ 210 HP (down from 260)
					Walkspeed = 1.5,      -- +3 speed (6 → 9)
					Runspeed = 1.25,      -- +3 speed (12 → 15)
					Attackspeed = 1.16,   -- +3 speed (19 → ~22)
				},
			},
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

		Health = 350,
		Walkspeed = 8,
		Runspeed = 14,

		Attackspeed = 22,
		HealRate = 0,

		AttackDamage = 10,         -- 15% reduction from 12, rounded
		AttackRange = 6,
		AttackCooldown = 1.4,

		Price = 2750,

		RarityName = "Common",
		Personality = "Territorial",
		LocomotionType = "Charge", -- charge = "running them over"

		-- Melee only — scratch/swipe (BasicMelee ~80%) + charge/trample (HeavyMelee ~20%)
		AttackMoves = { "BasicMelee", "HeavyMelee" },

		PersonalityOverrides = {
			AggroDistance = 45,         -- notices you approaching territory
			ChaseRange = 150,          -- will chase far when provoked
			AttackChance = 0.55,       -- likely to attack on sight
			RunChance = 0.20,          -- may run if damaged
			RunWhenAttacked = 0.25,    -- more likely to fight than flee
			FearTime = 1.5,
			FearDistance = 25,
			Forgive = 0.50,
			ForgiveTime = 12,
			RetaliateOnDamage = true,
			RetaliateAggression = 0.85, -- very likely to fight back
			PursuitTenacity = 0.70,    -- commits to chase (was 0.45 — too low)
			HeavyAttackBias = 0.20,    -- ~20% charge/trample, ~80% scratch
			CorneredAggression = 0.90,
			TerritoryLeashPct = 0.25,  -- 25% beyond territory edge
			LeashStrength = 0.40,      -- light pull (chases freely, gradually returns)
		},

		MoveOverrides = {
			BasicMelee = { WindupTime = 0.15, DamageMult = 0.9 },   -- quick scratch
			HeavyMelee = { WindupTime = 0.4, DamageMult = 1.8, Range = 8 }, -- charge/trample
		},

		-- Named variants: normal/baby/big/huge moles with different combat styles
		Variants = {
			{
				Name = "Normal",
				Weight = 50,
				-- No overrides: uses base config as-is
			},
			{
				Name = "Baby",
				NameTag = "(Baby)",
				Weight = 25,
				SizeMultiplier = 0.5,
				SizeTier = "baby",
				VariantPrice = 1750,

				StatOverrides = {
					AttackDamage = 0.5,   -- half damage
				},
				VariantMoveOverrides = {
					BasicMelee = { DamageMult = 0.5 },  -- weaker scratch
				},
				VariantPersonalityOverrides = {
					Aggressive = 0.02,
					RunChance = 0.85,
					RunWhenAttacked = 0.90,
					AttackChance = 0.05,
					RetaliateAggression = 0.10,
					PursuitTenacity = 0.0,
				},
			},
			{
				Name = "Big",
				NameTag = "(Big)",
				Weight = 15,
				SizeMultiplier = 1.2,
				SizeTier = "big",
				VariantPrice = 3500,

				StatOverrides = {
					AttackDamage = 1.3,   -- 30% more damage
					Health = 1.3,
				},
				VariantPersonalityOverrides = {
					Aggressive = 0.70,
					RunChance = 0.08,
					RunWhenAttacked = 0.10,
					RetaliateAggression = 0.95,
					PursuitTenacity = 0.85,
					CorneredAggression = 0.95,
				},
			},
			{
				Name = "Huge",
				NameTag = "(Huge)",
				Weight = 5,
				SizeMultiplier = 1.5,
				SizeTier = "huge",
				VariantPrice = 4000,

				StatOverrides = {
					AttackDamage = 1.8,   -- near-double damage
					Health = 1.8,
				},
				VariantMoveOverrides = {
					HeavyMelee = { DamageMult = 2.5, Range = 10 }, -- devastating charge
				},
				VariantPersonalityOverrides = {
					Aggressive = 0.85,
					RunChance = 0.03,
					RunWhenAttacked = 0.03,
					RetaliateAggression = 1.0,
					PursuitTenacity = 0.95,
					CorneredAggression = 1.0,
					HeavyAttackBias = 0.40, -- charges more often
				},
			},
		},

		-- Pack animal: signals nearby Burbalonis to share attack/flee state
		-- SignalRange = 0.75 means 3/4 of territory size
		PackBehavior = {
			Enabled = true,
			SignalRange = 0.75,
			ShareStates = { "Chase", "Flee" },
			PackJoinChance = 0.80, -- high chance neighbors join a Chase (distance falloff on top)
			ProtectBaby = true,    -- ALL pack members rage when a Baby is damaged
		},
	},



	-----------------------------------------------------------------------
	-- Trippi Troppi — shrimp-cat water sentry
	-- Lives in packs. Stands still and rapid-fires waterballs from long
	-- range (every 0.5–1.5s). Low damage per hit but high volume.
	-- If a player gets within 25 studs the whole pack scatters, then
	-- repositions and resumes firing. No melee at all.
	-----------------------------------------------------------------------
	["Trippi_Troppi"] = {
		DisplayName = "Trippi Troppi",

		Health = 200,
		Walkspeed = 16,
		Runspeed = 25,

		Attackspeed = 20,
		HealRate = 3,

		AttackDamage = 3,
		AttackRange = 70,
		AttackCooldown = 1.0,

		Price = 1500,

		RarityName = "Common",
		Personality = "Fearful",
		LocomotionType = "Walk",

		-- Ranged only — no melee, pure sentry
		AttackMoves = { "StandAndHurl" },

		PersonalityOverrides = {
			AggroDistance = 80,        -- spots threats from far away
			ChaseRange = 20,          -- never chases
			AttackChance = 0.08,      -- fires when enemy in range, not aggressive
			RunChance = 0.95,         -- almost always runs when close
			RunWhenAttacked = 0.95,
			FearDistance = 25,         -- scatter trigger distance
			FearTime = 3.0,
			Forgive = 0.90,
			ForgiveTime = 5,          -- quick to forget and resettle
			PreferRanged = 1.0,       -- always ranged, never melee
			HeavyAttackBias = 0.0,
			RetaliateOnDamage = false, -- doesn't fight back, just runs
			RetaliateAggression = 0.0,
			PursuitTenacity = 0.0,    -- never pursues
			CorneredAggression = 0.15, -- even cornered, tries to flee
			FleeStyle = "scatter",    -- scatter in random directions
			TerritoryLeashPct = 0.20,  -- 20% beyond territory edge
			LeashStrength = 0.60,      -- moderate pull back after flee
		},

		MoveOverrides = {
			StandAndHurl = {
				Range = 70,
				Projectile = "Waterball",
				Spread = 2,            -- pretty accurate
				Cooldown = 0.8,        -- rapid fire (~0.5-1.5s with windup)
				WindupTime = 0.3,
				MinRange = 25,         -- won't shoot if player is within 25 studs (flee instead)
			},
		},

		-- Pack behavior: scatter together when one flees
		PackBehavior = {
			Enabled = true,
			SignalRange = 0.80,
			ShareStates = { "Flee" },
			PackJoinChance = 0.90, -- very likely to scatter together
		},

		Variants = {
			{
				Name = "Small",
				NameTag = "(Small)",
				Weight = 60,
				SizeMultiplier = 0.5,
				SizeTier = "baby",
				VariantPrice = 500,

				StatOverrides = {
					AttackDamage = 0.6, -- slightly less damage
					-- Health: no override — sizeMult 0.5 gives 200 × 0.5 = 100 HP
				},
				VariantPersonalityOverrides = {
					RunChance = 0.98,
					RunWhenAttacked = 0.98,
				},
			},
			{
				Name = "Normal",
				Weight = 30,
				-- No overrides: uses base config as-is
			},
			{
				Name = "Big",
				NameTag = "(Big)",
				Weight = 10,
				SizeMultiplier = 1.4,
				SizeTier = "big",
				VariantPrice = 2500,

				StatOverrides = {
					AttackDamage = 2.0,   -- 2x damage
					Health = 1.61,        -- 200 × 1.61 = 322, × 1.4 sizeMult ≈ 450 HP
				},
				VariantMoveOverrides = {
					StandAndHurl = {
						ProjectileCount = 1,
						Cooldown = 1.0,   -- slightly slower
						WindupTime = 0.4,
					},
				},
				VariantPersonalityOverrides = {
					RunChance = 0.80,     -- slightly braver
					RunWhenAttacked = 0.85,
					CorneredAggression = 0.30,
				},
			},
		},
	},

	-----------------------------------------------------------------------
	-- Pipi Kiwi — kiwi wolf, pack hunter
	-- Travels in packs. When a player enters territory, the pack splits
	-- to surround, circling at walk speed (12). Once positioned, they
	-- flip to chase speed (20) and attack from all sides.
	-- Aggressive but individually cowardly — flees briefly when damaged,
	-- then pack signal pulls them back in.
	-- Bites (BasicMelee) + lunging leap attacks (Lunge).
	-----------------------------------------------------------------------
	["Pipi_Kiwi"] = {
		DisplayName = "Pipi Kiwi",

		Health = 400,
		Walkspeed = 14,           -- idle patrol speed (+1)
		Runspeed = 22,            -- chase/attack commit speed (+1)

		Attackspeed = 22,
		HealRate = 0,

		AttackDamage = 12,        -- +20% +2 across the board
		AttackRange = 7,          -- bite range (accounts for hitbox)
		AttackCooldown = 1.0,     -- fast repeated bites

		Price = 12000,

		RarityName = "Common",
		Personality = "Territorial",
		LocomotionType = "Walk",

		-- Melee only: quick bites + lunging leap
		AttackMoves = { "BasicMelee", "Lunge" },

		PersonalityOverrides = {
			AggroDistance = 55,         -- pack notices you from decent range
			ChaseRange = 120,          -- will chase fairly far once committed
			AttackChance = 0.60,       -- aggressive on territory intrusion
			RunChance = 0.55,          -- individually flees when damaged
			RunWhenAttacked = 0.55,    -- flees when hit...
			FearTime = 1.5,            -- ...but only briefly
			FearDistance = 18,         -- doesn't run far
			RunMaxDistance = 60,
			Forgive = 0.30,
			ForgiveTime = 15,
			ForgiveDistance = 50,
			RetaliateOnDamage = true,
			RetaliateAggression = 0.50, -- more willing to fight back
			PursuitTenacity = 0.75,    -- committed once chasing
			HeavyAttackBias = 0.30,    -- ~30% lunge, ~70% bite
			CorneredAggression = 0.95,
			TerritoryTenacity = 0.90,
			TerritoryLeashPct = 0.30,
			LeashStrength = 0.50,
			FleeStyle = "straight",
			PreferRanged = 0.0,
			SafeZonePull = 0.70,
			PatrolRadius = 18,
		},

		-- Aggro curve: fast engage, pack signal instantly commits
		AggroCurveOverrides = {
			IdleAggro = 5,             -- alert
			DamageGain = 20,           -- damage builds aggro faster
			ProximityRate = 30,        -- builds quickly from proximity
			TerritoryRate = 18,        -- territory entry triggers fast
			CorneredRate = 12,
			PackGain = 60,             -- pack signal = instant commit
			DecayRate = 3.0,
			TerritoryDecayMult = 2.5,
			OutOfSightDecay = 4,
			DecayDelay = 5,
			AccelDecayMult = 2.0,
			ChaseThreshold = 20,       -- very easy to trigger chase
			PursuitThreshold = 45,
			BerserkThreshold = 75,
			FleeInversion = false,
			FleeThreshold = 0,
		},

		MoveOverrides = {
			BasicMelee = {
				WindupTime = 0.12,     -- fast snap bite
				DamageMult = 1.0,
				Cooldown = 1.0,
				Range = 7,
			},
			Lunge = {
				WindupTime = 0.35,     -- short crouch before pounce
				DamageMult = 1.8,
				Range = 20,
				LeapHeight = 18,
				LeapSpeed = 75,
				HitRadius = 6,
				Cooldown = 4.0,
			},
		},

		-- Pack behavior: chase signal rallies all wolves, no flee sharing
		PackBehavior = {
			Enabled = true,
			SignalRange = 0.80,
			ShareStates = { "Chase" },
			ProtectBaby = true,
		},

		-- Named variants
		Variants = {
			{
				Name = "Baby",
				NameTag = "(Pup)",
				Weight = 20,
				SizeMultiplier = 0.5,
				SizeTier = "baby",
				VariantPrice = 7200,
				StatOverrides = {
					Health = 0.75,             -- 400 × 0.75 × 0.5 = 150 HP
					AttackDamage = 0.5,        -- 4 damage per bite
					Walkspeed = 1.14,          -- 16 walk
					Runspeed = 1.09,           -- 24 run
				},
				VariantPersonalityOverrides = {
					RunChance = 0.80,          -- extra skittish
					RunWhenAttacked = 0.85,
					RetaliateAggression = 0.15,
					PursuitTenacity = 0.30,
				},
			},
			{
				Name = "Normal",
				Weight = 55,
			},
			{
				Name = "Big",
				NameTag = "(Alpha)",
				Weight = 20,
				SizeMultiplier = 1.2,
				SizeTier = "big",
				VariantPrice = 15000,
				StatOverrides = {
					AttackDamage = 1.2,        -- ~10 damage per bite
					Walkspeed = 1.07,          -- 15 walk
					Runspeed = 1.045,          -- 23 run
				},
				VariantPersonalityOverrides = {
					RunChance = 0.40,
					RunWhenAttacked = 0.45,
					RetaliateAggression = 0.70,
					PursuitTenacity = 0.85,
					HeavyAttackBias = 0.40,    -- lunges more often
					SafeZonePull = 0.40,
					PatrolRadius = 28,
				},
			},
			{
				Name = "Huge",
				NameTag = "(Dire)",
				Weight = 5,
				SizeMultiplier = 2.0,
				SizeTier = "huge",
				VariantPrice = 28000,
				StatOverrides = {
					Health = 1.375,            -- 400 × 1.375 × 2.0 = 1100 HP
					AttackDamage = 2.0,        -- 16 damage per bite
					Walkspeed = 1.36,          -- 19 walk
					Runspeed = 1.23,           -- 27 run
				},
				-- Huge wolf: lunge-only
				VariantMoveOverrides = {
					Lunge = {
						WindupTime = 0.45,
						DamageMult = 2.2,
						LeapHeight = 22,
						LeapSpeed = 85,
						HitRadius = 8,
						Cooldown = 3.0,
						Range = 25,
					},
				},
				VariantPersonalityOverrides = {
					RunChance = 0.15,
					RunWhenAttacked = 0.20,
					RetaliateAggression = 0.90,
					PursuitTenacity = 0.95,
					CorneredAggression = 1.0,
					HeavyAttackBias = 1.0,     -- lunge-only
					SafeZonePull = 0.25,
					PatrolRadius = 35,
				},
			},
		},
	},

	-----------------------------------------------------------------------
	-- Example brainrots (edit/add as needed)
	-- Zone Configuration.Enemies must reference these keys
	-----------------------------------------------------------------------

	-----------------------------------------------------------------------
	-- Boneca_Ambalabu — Wheel Frog (Level 2, first enemy)
	-- Fast roller: always moving, drive-by bites, panics on damage.
	-- No pack behavior. NoStop = true means it never pauses to attack.
	-----------------------------------------------------------------------
	["Boneca_Ambalabu"] = {
		DisplayName = "Boneca Ambalabu",

		Health = 450,
		Walkspeed = 21,           -- idle rolling (+2)
		Runspeed = 34,            -- charge speed (+3)

		Attackspeed = 29,
		HealRate = 0,

		AttackDamage = 10,        -- base damage (2.5x via DamageMult = 25 effective)
		AttackRange = 4,          -- must physically ram into you
		AttackCooldown = 1.0,     -- once per pass

		Price = 10000,
		RarityName = "Common",

		Personality = "Skittish",

		AttackMoves = { "BasicMelee" },
		LocomotionType = "Roll",

		-- RollLocomotion config: constant driving, rare idle
		RollConfig = {
			IdleChance = 0.25,        -- 25% chance to idle between drives
		},

		PersonalityOverrides = {
			IdleFrequency = { 3.0, 6.0 },     -- long pause between rolls (3-6 seconds)
			IdleActions = { "walk", "walk", "walk", "idle" },

			AggroDistance = 60,                -- decent detection range
			ChaseRange = 100,                  -- committed pursuit
			AttackChance = 0.80,               -- aggressive — charges on sight

			RunChance = 0.95,                  -- almost always flees AFTER attack
			RunWhenAttacked = 0.95,            -- first hit = gone
			RetaliateOnDamage = false,         -- never fights back
			RetaliateAggression = 0.0,

			FearTime = 4.0,                    -- commits to running
			FearDistance = 80,                 -- runs FAR before stopping
			RunMaxDistance = 160,

			FleeStyle = "zigzag",              -- hard to chase down
			PursuitTenacity = 0.60,            -- committed to the charge
			CorneredAggression = 0.30,         -- even cornered, prefers to flee
			TerritoryTenacity = 0.20,
			TerritoryLeashPct = 0.40,
			LeashStrength = 0.30,

			SafeZonePull = 0.10,               -- barely uses den — always roaming
			PatrolRadius = 35,                 -- big wander area
		},

		AggroCurveOverrides = {
			IdleAggro = 5,                     -- calm at rest, builds fast via ProximityRate
			DamageGain = 3,
			ProximityRate = 60,                -- 5→15 in ~0.17s — locks on fast when player nearby
			TerritoryRate = 10,
			CorneredRate = 4,
			DecayRate = 10.0,                  -- drops fast when player leaves
			TerritoryDecayMult = 1.5,
			OutOfSightDecay = 15,              -- forgets quickly out of sight
			DecayDelay = 2,
			AccelDecayMult = 2.5,
			ChaseThreshold = 15,               -- needs proximity to trigger (not instant)
			PursuitThreshold = 30,
			BerserkThreshold = 95,
			FleeInversion = false,
			FleeThreshold = 0,
		},

		MoveOverrides = {
			BasicMelee = {
				WindupTime = 0.06,             -- near-instant snap
				DamageMult = 2.5,              -- heavy ram hit (10 × 2.5 = 25)
				Cooldown = 1.0,
				Range = 4,                     -- must physically touch
				NoStop = true,                 -- drive-by: no pause, keep rolling
				FleeAfterAttack = true,        -- hit and run: always flee after landing
			},
		},

		Variants = {
			{
				Name = "Normal",
				Weight = 45,
				-- Base frog: 120 HP, 19/31 speed, 25 effective dmg, $2000
			},
			{
				Name = "Tadpole",
				NameTag = "(Tadpole)",
				Weight = 30,
				SizeMultiplier = 0.6,
				SizeTier = "baby",
				VariantPrice = 6000,               -- 60% of $10000
				StatOverrides = {
					Health = 1.296,                -- 450 × 1.296 × 0.6 ≈ 350 HP
					AttackDamage = 0.6,            -- 10 × 0.6 = 6 base (× 2.5 = 15 eff)
					Walkspeed = 1.43,              -- 21 × 1.43 ≈ 30 walk (zippy)
					Runspeed = 1.44,               -- 34 × 1.44 ≈ 49 run (fast)
					Attackspeed = 1.5,             -- 29 × 1.5 ≈ 43
				},
				VariantPersonalityOverrides = {
					RunChance = 1.0,               -- ALWAYS flees on damage
					RunWhenAttacked = 1.0,         -- first hit = gone, every time
					FearTime = 5.0,                -- runs for a long time
					FearDistance = 60,             -- runs far
					AttackChance = 0.40,           -- timid
					PursuitTenacity = 0.20,        -- gives up chase easily
				},
			},
			{
				Name = "Toad",
				NameTag = "(Toad)",
				Weight = 15,
				SizeMultiplier = 1.25,
				SizeTier = "big",
				VariantPrice = 12500,              -- 125% of $10000
				StatOverrides = {
					Health = 1.022,                -- 450 × 1.022 × 1.25 ≈ 575 HP
					AttackDamage = 1.4,            -- 10 × 1.4 = 14 base (× 2.5 = 35 effective)
					Walkspeed = 0.905,             -- 21 × 0.905 ≈ 19
					Runspeed = 0.912,              -- 34 × 0.912 ≈ 31
				},
				VariantPersonalityOverrides = {
					RunChance = 0.75,              -- flees less than normal
					RunWhenAttacked = 0.75,
					FearTime = 2.5,                -- shorter flee
				},
			},
			{
				Name = "Bullfrog",
				NameTag = "(Bullfrog)",
				Weight = 10,
				SizeMultiplier = 1.75,
				SizeTier = "huge",
				VariantPrice = 20000,              -- 2x of $10000
				StatOverrides = {
					Health = 0.889,                -- 450 × 0.889 × 1.75 ≈ 700 HP
					AttackDamage = 1.2,            -- 10 × 1.2 = 12 base (× 2.5 = 30 effective)
					Walkspeed = 1.143,             -- 21 × 1.143 ≈ 24 (+3)
					Runspeed = 1.088,              -- 34 × 1.088 ≈ 37 (+3)
				},
				VariantPersonalityOverrides = {
					AttackChance = 0.95,           -- ultra aggressive
					PursuitTenacity = 0.85,        -- very committed
					RunChance = 0.40,              -- rarely flees on damage
					RunWhenAttacked = 0.45,        -- tanky — stands its ground
					FearTime = 1.5,                -- short flee when it does run
				},
			},
		},
	},

	["Default2"] = {
		DisplayName = "Default 2",
		Health = 140,
		Walkspeed = 15,
		Runspeed = 21,

		AttackDamage = 12,
		AttackRange = 6.5,
		AttackCooldown = 1.35,

		Price = 350,
		RarityName = "Uncommon",
		Personality = "Skittish",
	},

	-----------------------------------------------------------------------
	-- Orangutini Ananassini — Ambush Assassin Monkey
	-- Hides in trees or underground, leaps out to grab players.
	-- Players must spam-jump to break free (breakpower mechanic).
	-- Never idles in the open — always hiding or traveling to a hiding spot.
	-----------------------------------------------------------------------
	["Orangutini_Ananassini"] = {
		DisplayName = "Orangutini Ananassini",

		Health = 350,
		Walkspeed = 12,
		Runspeed = 28,           -- quick but not crazy

		Attackspeed = 28,
		HealRate = 0,

		AttackDamage = 2,        -- very low tick damage while grabbing
		AttackRange = 15,        -- grab reach
		AttackCooldown = 0.3,    -- near-instant re-grab

		Price = 15000,
		RarityName = "Rare",

		Personality = "Ambush",
		LocomotionType = "Walk",

		AttackMoves = { "GrabAttack" },

		PersonalityOverrides = {
			AmbushBehavior = true,        -- flag: AIService uses ambush state machine
			AggroDistance = 18,            -- very short — only reacts when close
			ChaseRange = 30,              -- short chase — if you escape, it re-hides
			HidePatience = { 15, 30 },    -- seconds to wait in hide before relocating
			AmbushRange = 18,             -- only pop when player is close
			AmbushPopRange = 0.5,         -- underground: pop at 50% of attack range
			FleeDistance = 100,           -- min flee distance before digging underground
			TreeTag = "Tree",             -- CollectionService tag for climbable trees
			RunWhenAttacked = 0.95,       -- almost always flees when hit
		},

		AggroCurveOverrides = {
			ChaseThreshold = 5,           -- binary: any proximity = instant chase
			ProximityRate = 50,           -- aggro maxes immediately when close
		},

		MoveOverrides = {
			GrabAttack = {
				Range = 15,
				Cooldown = 0.3,
				WindupTime = 0,      -- zero windup — instant assassin grab
				FleeAfterAttack = true,
				TickDamage = 2,
				TickInterval = 1.0,
				BreakThreshold = 70,
				JumpPower = 20,
				BreakDecay = 4,
			},
		},

		Variants = {
			{ Name = "Normal", Weight = 64 },
			{ Name = "Baby", Weight = 20, NameTag = "(Baby)", SizeMultiplier = 0.6, SizeTier = "baby",
			  StatOverrides = { AttackDamage = 0.5, Health = 0.5 } },
			{ Name = "Silverback", Weight = 15, NameTag = "(Silverback)", SizeMultiplier = 1.3, SizeTier = "big",
			  StatOverrides = { Health = 1.5, AttackDamage = 1.5 },
			  VariantMoveOverrides = { GrabAttack = { BreakThreshold = 95 } } },
			{ Name = "King", Weight = 1, NameTag = "(King)", SizeMultiplier = 1.8, SizeTier = "huge",
			  StatOverrides = { Health = 2.5, AttackDamage = 2.0 },
			  VariantMoveOverrides = { GrabAttack = { BreakThreshold = 120, BreakDecay = 6 } } },
		},
	},
}

return BrainrotConfig