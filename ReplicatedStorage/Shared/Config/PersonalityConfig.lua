-- ReplicatedStorage/Shared/Config/PersonalityConfig.lua
-- Data-only personality definitions used by AIService.
-- All fields are OPTIONAL; AIService supplies safe defaults.
--
-- Combat fields (new):
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
-- ExclusionBehavior (new):
--   LowThreshold: ignores zones below this weight
--   WaitAtEdge: parks at zone boundary when blocked
--   WaitPatience: seconds to wait before abandoning
--   PushThroughCost: willingness to enter medium-weight zones (0=never, 1=always)
--   PacingRadius: how far to pace while waiting at edge

local PersonalityConfig = {

	----------------------------------------------------------------------
	-- Passive: calm, mostly wanders, retaliates if attacked
	----------------------------------------------------------------------
	Passive = {
		IdleFrequency = { 2, 10 },
		IdleActions = { "idle", "walk" },

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
	},

	----------------------------------------------------------------------
	-- Fearful: always runs, only attacks if cornered
	----------------------------------------------------------------------
	Fearful = {
		IdleFrequency = { 2.5, 12 },
		IdleActions = { "idle", "walk" },

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
	},

	----------------------------------------------------------------------
	-- Aggressive: likes to fight, chases hard, pushes into zones
	----------------------------------------------------------------------
	Aggressive = {
		IdleFrequency = { 1.2, 4.5 },
		IdleActions = { "walk", "walk", "idle" },

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
	},

	----------------------------------------------------------------------
	-- Territorial: protects its area, tight leash, unlikely to chase outside
	----------------------------------------------------------------------
	Territorial = {
		IdleFrequency = { 1.8, 6.0 },
		IdleActions = { "walk", "idle" },

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
		LeashStrength = 0.95,

		-- Exclusion zone behavior
		ExclusionBehavior = {
			LowThreshold = 25,
			WaitAtEdge = true,
			WaitPatience = 5,
			PushThroughCost = 0.2,
			PacingRadius = 6,
		},
	},

	----------------------------------------------------------------------
	-- Jumpy: random energy, idles less, wanders more, unpredictable
	----------------------------------------------------------------------
	Jumpy = {
		IdleFrequency = { 0.9, 3.5 },
		IdleActions = { "walk", "walk", "idle" },

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
	},

	----------------------------------------------------------------------
	-- Skittish: rarely aggroes, but may retaliate or flee (coinflip)
	----------------------------------------------------------------------
	Skittish = {
		IdleFrequency = { 2.0, 9.0 },
		IdleActions = { "idle", "walk" },

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
	},

	----------------------------------------------------------------------
	-- Berserk: always looking for a fight, almost never flees, ignores zones
	----------------------------------------------------------------------
	Berserk = {
		IdleFrequency = { 0.8, 2.8 },
		IdleActions = { "walk", "walk", "walk", "idle" },

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
	},
}

return PersonalityConfig
