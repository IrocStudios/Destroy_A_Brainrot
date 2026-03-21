-- ReplicatedStorage/Shared/Config/PersonalityConfig.lua
-- Data-only personality definitions used by AIService.
-- All fields are OPTIONAL; AIService supplies safe defaults.
--
-- Combat fields:
--   DefaultAttackMoves: fallback move list if BrainrotConfig doesn't specify
--   PreferRanged: 0=always melee, 1=always ranged when both available
--   HeavyAttackBias: chance to pick heavy over light when both valid
--   RetaliateOnDamage: whether this personality fights back when hit
--   RetaliateAggression: chance to retaliate vs flee when hit
--   PursuitTenacity: how long it chases (0=gives up fast, 1=relentless)
--   CorneredAggression: aggression boost when health low + can't flee
--   TerritoryTenacity: relentlessness inside own territory (Territorial only)
--   LeashStrength: how strongly it obeys leash radius (0=ignores, 1=strict)
--
-- ExclusionBehavior:
--   LowThreshold: ignores zones below this weight
--   WaitAtEdge: parks at zone boundary when blocked
--   WaitPatience: seconds to wait before abandoning
--   PushThroughCost: willingness to enter medium-weight zones (0=never, 1=always)
--   PacingRadius: how far to pace while waiting at edge
--
-- AggroCurve — continuous anger meter (0-100) parameters:
--   IdleAggro: resting aggro level (0 = calm by default)
--   DamageGain: aggro added per damage event
--   ProximityRate: aggro/sec when player within AggroDistance
--   TerritoryRate: aggro/sec when player inside territory
--   CorneredRate: aggro/sec when health low
--   PackGain: aggro added from pack ally signal
--   DecayRate: base aggro/sec passive decay back toward IdleAggro
--   TerritoryDecayMult: extra decay multiplier when outside own territory
--   OutOfSightDecay: extra aggro/sec drain when target not visible/in range
--   DecayDelay: seconds after last damage before decay accelerates
--   AccelDecayMult: decay speed multiplier after DecayDelay expires
--   ChaseThreshold: aggro level to start chasing (30=hard to anger, 12=hair-trigger)
--   PursuitThreshold: aggro level for aggressive pursuit outside territory
--   BerserkThreshold: aggro level to ignore leash entirely
--   FleeInversion: if true, high aggro = Flee instead of Chase (Fearful personality)
--   FleeThreshold: aggro level at which flee triggers (for FleeInversion or damage-flee)

local PersonalityConfig = {

	----------------------------------------------------------------------
	-- Passive: calm, mostly wanders, retaliates if attacked
	----------------------------------------------------------------------
	Passive = {
		IdleFrequency = { 2, 6 },
		IdleActions = { "idle", "fidget", "walk" },

		Aggressive = 0.10,
		AggroDistance = 45,
		ChaseRange = 90,
		AttackChance = 0.05,

		RunChance = 0.60,
		RunWhenAttacked = 0.60,
		FearTime = 3.0,
		FearDistance = 45,
		RunMaxDistance = 120,

		LeashRadius = 170,
		PatrolRadius = 28,
		WanderPause = { 0.8, 2.2 },

		Forgive = 0.80,
		ForgiveTime = 10,
		ForgiveDistance = 50,

		-- Combat defaults
		DefaultAttackMoves = { "BasicMelee" },
		PreferRanged = 0.0,
		HeavyAttackBias = 0.1,
		RetaliateOnDamage = true,
		RetaliateAggression = 0.45,
		PursuitTenacity = 0.2,
		CorneredAggression = 0.7,
		LeashStrength = 0.7,

		-- Flee style: "straight" | "zigzag" | "scatter"
		FleeStyle = "straight",

		-- Exclusion zone behavior
		ExclusionBehavior = {
			LowThreshold = 20,
			WaitAtEdge = false,
			WaitPatience = 0,
			PushThroughCost = 0.15,
			PacingRadius = 0,
		},

		-- Aggro curve: slow to anger, fast to calm down
		AggroCurve = {
			IdleAggro = 0,
			DamageGain = 20,
			ProximityRate = 12,
			TerritoryRate = 4,
			CorneredRate = 8,
			PackGain = 30,
			DecayRate = 4.0,
			TerritoryDecayMult = 2.0,
			OutOfSightDecay = 5,
			DecayDelay = 4,
			AccelDecayMult = 2.0,
			ChaseThreshold = 40,
			PursuitThreshold = 65,
			BerserkThreshold = 90,
			FleeInversion = false,
			FleeThreshold = 25,
		},
	},

	----------------------------------------------------------------------
	-- Fearful: always runs, only attacks if cornered
	----------------------------------------------------------------------
	Fearful = {
		IdleFrequency = { 2, 7 },
		IdleActions = { "idle", "fidget", "walk" },

		Aggressive = 0.03,
		AggroDistance = 35,
		ChaseRange = 65,
		AttackChance = 0.02,

		RunChance = 0.85,
		RunWhenAttacked = 0.90,
		FearTime = 4.25,
		FearDistance = 60,
		RunMaxDistance = 160,

		LeashRadius = 190,
		PatrolRadius = 30,
		WanderPause = { 0.6, 1.8 },

		Forgive = 0.95,
		ForgiveTime = 8,
		ForgiveDistance = 60,

		-- Combat defaults
		DefaultAttackMoves = { "BasicMelee" },
		PreferRanged = 0.8,
		HeavyAttackBias = 0.05,
		RetaliateOnDamage = false,
		RetaliateAggression = 0.08,
		PursuitTenacity = 0.0,
		CorneredAggression = 0.9,
		LeashStrength = 0.5,

		-- Flee style: scatter by default for fearful types
		FleeStyle = "scatter",

		-- Exclusion zone behavior
		ExclusionBehavior = {
			LowThreshold = 10,
			WaitAtEdge = false,
			WaitPatience = 0,
			PushThroughCost = 0.05,
			PacingRadius = 0,
		},

		-- Aggro curve: gets scared fast, calms down fast, flees instead of chasing
		AggroCurve = {
			IdleAggro = 0,
			DamageGain = 25,
			ProximityRate = 25,
			TerritoryRate = 2,
			CorneredRate = 12,
			PackGain = 40,
			DecayRate = 5.0,
			TerritoryDecayMult = 1.5,
			OutOfSightDecay = 8,
			DecayDelay = 3,
			AccelDecayMult = 2.5,
			ChaseThreshold = 80,
			PursuitThreshold = 90,
			BerserkThreshold = 95,
			FleeInversion = true,
			FleeThreshold = 15,
		},
	},

	----------------------------------------------------------------------
	-- Aggressive: likes to fight, chases hard, pushes into zones
	----------------------------------------------------------------------
	Aggressive = {
		IdleFrequency = { 1.0, 3.5 },
		IdleActions = { "walk", "walk", "fidget", "idle" },

		Aggressive = 0.70,
		AggroDistance = 75,
		ChaseRange = 140,
		AttackChance = 0.65,

		RunChance = 0.08,
		RunWhenAttacked = 0.10,
		FearTime = 1.25,
		FearDistance = 30,
		RunMaxDistance = 90,

		LeashRadius = 210,
		PatrolRadius = 34,
		WanderPause = { 0.4, 1.2 },

		Forgive = 0.35,
		ForgiveTime = 16,
		ForgiveDistance = 45,

		-- Combat defaults
		DefaultAttackMoves = { "BasicMelee", "HeavyMelee" },
		PreferRanged = 0.3,
		HeavyAttackBias = 0.4,
		RetaliateOnDamage = true,
		RetaliateAggression = 0.90,
		PursuitTenacity = 0.75,
		CorneredAggression = 0.95,
		LeashStrength = 0.4,

		-- Exclusion zone behavior
		ExclusionBehavior = {
			LowThreshold = 35,
			WaitAtEdge = true,
			WaitPatience = 12,
			PushThroughCost = 0.6,
			PacingRadius = 8,
		},

		-- Aggro curve: quick to anger, slow to calm, low thresholds
		AggroCurve = {
			IdleAggro = 8,
			DamageGain = 30,
			ProximityRate = 40,
			TerritoryRate = 6,
			CorneredRate = 12,
			PackGain = 45,
			DecayRate = 1.5,
			TerritoryDecayMult = 1.5,
			OutOfSightDecay = 3,
			DecayDelay = 6,
			AccelDecayMult = 1.5,
			ChaseThreshold = 18,
			PursuitThreshold = 40,
			BerserkThreshold = 70,
			FleeInversion = false,
			FleeThreshold = 0,
		},
	},

	----------------------------------------------------------------------
	-- Territorial: protects its area, tight leash, unlikely to chase outside
	----------------------------------------------------------------------
	Territorial = {
		IdleFrequency = { 1.5, 5.0 },
		IdleActions = { "walk", "fidget", "idle" },

		Aggressive = 0.55,
		AggroDistance = 60,
		ChaseRange = 95,
		AttackChance = 0.50,

		RunChance = 0.10,
		RunWhenAttacked = 0.12,
		FearTime = 1.5,
		FearDistance = 28,
		RunMaxDistance = 90,

		LeashRadius = 140,
		PatrolRadius = 26,
		WanderPause = { 0.6, 1.4 },

		Forgive = 0.55,
		ForgiveTime = 10,
		ForgiveDistance = 40,

		-- Combat defaults
		DefaultAttackMoves = { "BasicMelee", "HeavyMelee" },
		PreferRanged = 0.2,
		HeavyAttackBias = 0.5,
		RetaliateOnDamage = true,
		RetaliateAggression = 0.80,
		PursuitTenacity = 0.4,
		TerritoryTenacity = 1.0,
		CorneredAggression = 0.85,
		LeashStrength = 0.55,

		-- Exclusion zone behavior
		ExclusionBehavior = {
			LowThreshold = 25,
			WaitAtEdge = true,
			WaitPatience = 5,
			PushThroughCost = 0.2,
			PacingRadius = 6,
		},

		-- Aggro curve: territory intrusion is the BIG trigger, fast decay outside
		AggroCurve = {
			IdleAggro = 5,
			DamageGain = 28,
			ProximityRate = 20,
			TerritoryRate = 35,
			CorneredRate = 10,
			PackGain = 40,
			DecayRate = 2.5,
			TerritoryDecayMult = 3.0,
			OutOfSightDecay = 4,
			DecayDelay = 5,
			AccelDecayMult = 2.0,
			ChaseThreshold = 22,
			PursuitThreshold = 55,
			BerserkThreshold = 82,
			FleeInversion = false,
			FleeThreshold = 0,
		},
	},

	----------------------------------------------------------------------
	-- Jumpy: random energy, idles less, wanders more, unpredictable
	----------------------------------------------------------------------
	Jumpy = {
		IdleFrequency = { 0.8, 3.0 },
		IdleActions = { "walk", "walk", "fidget", "idle" },

		Aggressive = 0.22,
		AggroDistance = 55,
		ChaseRange = 105,
		AttackChance = 0.18,

		RunChance = 0.45,
		RunWhenAttacked = 0.55,
		FearTime = 2.0,
		FearDistance = 55,
		RunMaxDistance = 140,

		LeashRadius = 180,
		PatrolRadius = 36,
		WanderPause = { 0.2, 0.8 },

		Forgive = 0.85,
		ForgiveTime = 9,
		ForgiveDistance = 55,

		-- Combat defaults
		DefaultAttackMoves = { "BasicMelee", "HitAndRun" },
		PreferRanged = 0.4,
		HeavyAttackBias = 0.2,
		RetaliateOnDamage = true,
		RetaliateAggression = 0.50,
		PursuitTenacity = 0.35,
		CorneredAggression = 0.7,
		LeashStrength = 0.6,

		-- Exclusion zone behavior
		ExclusionBehavior = {
			LowThreshold = 20,
			WaitAtEdge = false,
			WaitPatience = 3,
			PushThroughCost = 0.3,
			PacingRadius = 12,
		},

		-- Aggro curve: moderate, unpredictable, may flee at mid-levels
		AggroCurve = {
			IdleAggro = 3,
			DamageGain = 22,
			ProximityRate = 18,
			TerritoryRate = 5,
			CorneredRate = 8,
			PackGain = 35,
			DecayRate = 3.0,
			TerritoryDecayMult = 2.0,
			OutOfSightDecay = 5,
			DecayDelay = 4,
			AccelDecayMult = 2.0,
			ChaseThreshold = 30,
			PursuitThreshold = 55,
			BerserkThreshold = 85,
			FleeInversion = false,
			FleeThreshold = 20,
		},
	},

	----------------------------------------------------------------------
	-- Skittish: rarely aggroes, but may retaliate or flee (coinflip)
	----------------------------------------------------------------------
	Skittish = {
		IdleFrequency = { 1.8, 6.0 },
		IdleActions = { "idle", "fidget", "walk" },

		Aggressive = 0.07,
		AggroDistance = 50,
		ChaseRange = 85,
		AttackChance = 0.35,

		RunChance = 0.55,
		RunWhenAttacked = 0.60,
		FearTime = 3.25,
		FearDistance = 55,
		RunMaxDistance = 150,

		LeashRadius = 175,
		PatrolRadius = 30,
		WanderPause = { 0.8, 2.0 },

		Forgive = 0.90,
		ForgiveTime = 8,
		ForgiveDistance = 60,

		-- Combat defaults
		DefaultAttackMoves = { "BasicMelee" },
		PreferRanged = 0.5,
		HeavyAttackBias = 0.15,
		RetaliateOnDamage = true,
		RetaliateAggression = 0.35,
		PursuitTenacity = 0.15,
		CorneredAggression = 0.6,
		LeashStrength = 0.65,

		-- Exclusion zone behavior
		ExclusionBehavior = {
			LowThreshold = 15,
			WaitAtEdge = false,
			WaitPatience = 2,
			PushThroughCost = 0.1,
			PacingRadius = 0,
		},

		-- Aggro curve: slow to anger, fast to forget, coinflip flee/fight
		AggroCurve = {
			IdleAggro = 0,
			DamageGain = 18,
			ProximityRate = 8,
			TerritoryRate = 3,
			CorneredRate = 7,
			PackGain = 25,
			DecayRate = 4.5,
			TerritoryDecayMult = 2.5,
			OutOfSightDecay = 6,
			DecayDelay = 3,
			AccelDecayMult = 2.5,
			ChaseThreshold = 45,
			PursuitThreshold = 65,
			BerserkThreshold = 90,
			FleeInversion = false,
			FleeThreshold = 25,
		},
	},

	----------------------------------------------------------------------
	-- Berserk: always looking for a fight, almost never flees, ignores zones
	----------------------------------------------------------------------
	Berserk = {
		IdleFrequency = { 0.6, 2.2 },
		IdleActions = { "walk", "walk", "walk", "fidget" },

		Aggressive = 0.90,
		AggroDistance = 85,
		ChaseRange = 180,
		AttackChance = 0.85,

		RunChance = 0.02,
		RunWhenAttacked = 0.02,
		FearTime = 0.8,
		FearDistance = 20,
		RunMaxDistance = 60,

		LeashRadius = 240,
		PatrolRadius = 38,
		WanderPause = { 0.2, 0.7 },

		Forgive = 0.10,
		ForgiveTime = 22,
		ForgiveDistance = 40,

		-- Combat defaults
		DefaultAttackMoves = { "BasicMelee", "HeavyMelee" },
		PreferRanged = 0.1,
		HeavyAttackBias = 0.6,
		RetaliateOnDamage = true,
		RetaliateAggression = 1.0,
		PursuitTenacity = 0.95,
		CorneredAggression = 1.0,
		LeashStrength = 0.2,

		-- Exclusion zone behavior
		ExclusionBehavior = {
			LowThreshold = 50,
			WaitAtEdge = true,
			WaitPatience = 20,
			PushThroughCost = 0.85,
			PacingRadius = 10,
		},

		-- Aggro curve: always angry, barely decays, compressed thresholds
		AggroCurve = {
			IdleAggro = 15,
			DamageGain = 35,
			ProximityRate = 55,
			TerritoryRate = 8,
			CorneredRate = 15,
			PackGain = 50,
			DecayRate = 0.5,
			TerritoryDecayMult = 1.2,
			OutOfSightDecay = 1,
			DecayDelay = 8,
			AccelDecayMult = 1.2,
			ChaseThreshold = 12,
			PursuitThreshold = 30,
			BerserkThreshold = 50,
			FleeInversion = false,
			FleeThreshold = 0,
		},
	},

	----------------------------------------------------------------------
	-- Ambush: Hides in trees or underground, leaps out to grab players.
	-- Never idles in the open. Flees to re-hide after attacks.
	----------------------------------------------------------------------
	Ambush = {
		-- Assassin: hides, waits, grabs when close, flees when exposed
		Aggressive = 0.40,
		AggroDistance = 18,            -- very short — only reacts up close
		ChaseRange = 30,              -- short chase leash — re-hides if target escapes
		AttackRange = 15,
		AttackChance = 0.95,          -- almost always attacks if in range
		RunChance = 0.02,             -- rarely flees randomly (only on damage)
		RunWhenAttacked = 0.95,       -- almost always flees when hit while exposed

		IdleFrequency = { 0.3, 0.6 },
		WanderPause = { 0.2, 0.5 },
		FearTime = 4.0,               -- long flee — gets far away before re-hiding
		FearDistance = 15,

		PreferRanged = 0.0,           -- melee only (grab)
		HeavyAttackBias = 1.0,       -- always heavy (GrabAttack is Heavy)

		RetaliateOnDamage = false,    -- never fights back — always runs
		RetaliateAggression = 0.0,
		PursuitTenacity = 0.15,       -- gives up chase quickly if target runs
		CorneredAggression = 0.3,     -- even cornered, prefers to flee
		TerritoryTenacity = 0.2,
		LeashStrength = 0.8,          -- tight leash — sticks near territory

		FleeStyle = "scatter",

		DefaultAttackMoves = { "GrabAttack" },

		ExclusionBehavior = {
			LowThreshold = 20,
			WaitAtEdge = false,
			WaitPatience = 0,
			PushThroughCost = 0.8,
		},

		AggroCurve = {
			IdleAggro = 0,             -- completely calm at rest
			DamageGain = 5,            -- damage doesn't make them angry, just scared
			ProximityRate = 50,        -- aggro spikes instantly when player is close
			TerritoryRate = 5,
			CorneredRate = 10,
			PackGain = 0,
			DecayRate = 20,            -- aggro drops fast — lose interest quickly
			TerritoryDecayMult = 3.0,
			OutOfSightDecay = 30,      -- forgets VERY fast when player leaves
			DecayDelay = 0.5,
			AccelDecayMult = 2.0,
			ChaseThreshold = 5,        -- binary: any proximity = instant reaction
			PursuitThreshold = 15,
			BerserkThreshold = 90,     -- almost never berserks
			FleeInversion = false,
			FleeThreshold = 0,
		},
	},
}

return PersonalityConfig
