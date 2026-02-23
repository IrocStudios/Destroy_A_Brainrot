-- ReplicatedStorage/Shared/Config/PersonalityConfig.lua
-- Data-only personality definitions used by AIService.
-- All fields are OPTIONAL; AIService supplies safe defaults.

local PersonalityConfig = {

	-- Calm, mostly wanders, usually flees when attacked.
	Passive = {
		IdleFrequency = { 2, 10 },
		IdleActions = { "idle", "walk" },

		-- Aggro / attack behavior
		Aggressive = 0.10,        -- chance to become aggressive when a player is nearby
		AggroDistance = 45,       -- distance to consider aggro checks
		ChaseRange = 90,          -- how far it will chase a target before giving up
		AttackChance = 0.05,      -- chance to respond to being damaged by becoming aggressive

		-- Flee behavior
		RunChance = 0.60,         -- general run response chance on damage
		RunWhenAttacked = 0.60,   -- explicit (AI prefers this if present)
		FearTime = 3.0,           -- seconds it runs before returning
		FearDistance = 45,        -- "step away" target distance (used as run step)
		RunMaxDistance = 120,     -- cap flee step distance

		-- Territory / roaming
		LeashRadius = 170,        -- how far from territory center/spawn before forced Return
		PatrolRadius = 28,        -- fallback when no Territory exists
		WanderPause = { 0.8, 2.2 },

		-- Optional forgiveness knobs (reserved for later expansion)
		Forgive = 0.80,
		ForgiveTime = 10,
		ForgiveDistance = 50,
	},

	-- Will almost always run; very unlikely to chase or attack.
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
	},

	-- Likes to fight; often aggroes when near and usually attacks when damaged.
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
	},

	-- Short fuse: often aggroes, but leash is tighter and returns quickly.
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

		LeashRadius = 140, -- tight leash
		PatrolRadius = 26,
		WanderPause = { 0.6, 1.4 },

		Forgive = 0.55,
		ForgiveTime = 10,
		ForgiveDistance = 40,
	},

	-- Random energy: idles less, wanders more, sometimes runs even if not needed.
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
	},

	-- Rarely aggroes on proximity, but if damaged it may retaliate or flee (coinflip-ish).
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
	},

	-- Always looking for a fight; long chase range, almost never flees.
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
	},
}

return PersonalityConfig