--!strict
-- ReplicatedStorage/Shared/Config/AttackConfig.lua
-- Data-only definitions for attack moves and projectile skins.
-- Used by AttackRegistry (server) and AttackFXController (client).

local AttackConfig = {

	----------------------------------------------------------------------
	-- Projectile skins
	-- Key = skin name referenced by moves. Asset = ReplicatedStorage.Assets.Projectiles child name.
	----------------------------------------------------------------------
	----------------------------------------------------------------------
	-- Projectile skins
	-- Key = skin name referenced by moves. Asset = ReplicatedStorage.Assets.Projectiles child name.
	--
	-- Fields:
	--   Asset: string          — child name under Assets.Projectiles
	--   Speed: number          — studs per second travel speed
	--   MaxRange: number?      — max distance the projectile can travel (nil = unlimited)
	--   Gravity: boolean       — whether the projectile follows an arc
	--   ArcHeight: number      — arc height multiplier (fraction of distance, e.g. 0.3 = 30%)
	--   ArcHeightCap: number   — max arc height in studs
	--   Size: Vector3          — fallback size if no asset found
	--   Bounce: boolean        — whether the projectile bounces off the ground on impact
	--   BounceCount: number    — how many times it bounces (0 = no bounce)
	--   BounceDamping: number  — height/speed retained per bounce (0-1, e.g. 0.5 = halved)
	--   Damage: number?        — flat damage override (nil = uses move's DamageMult * AttackDamage)
	----------------------------------------------------------------------
	Projectiles = {
		Rock = {
			Asset = "Rock",
			Speed = 80,
			MaxRange = 60,
			Gravity = true,
			ArcHeight = 0.3,
			ArcHeightCap = 15,
			Size = Vector3.new(2, 2, 2),
			Bounce = false,
			BounceCount = 0,
			BounceDamping = 0,
			Damage = nil,
		},
		Tomato = {
			Asset = "Tomato",
			Speed = 60,
			MaxRange = 45,
			Gravity = true,
			ArcHeight = 0.25,
			ArcHeightCap = 12,
			Size = Vector3.new(1.5, 1.5, 1.5),
			Bounce = false,
			BounceCount = 0,
			BounceDamping = 0,
			Damage = nil,
		},
		Pizza = {
			Asset = "Pizza",
			Speed = 25,
			MaxRange = 60,
			Gravity = true,
			ArcHeight = 0.15,
			ArcHeightCap = 5,
			Size = Vector3.new(2, 0.4, 2),
			Bounce = true,
			BounceCount = 2,
			BounceDamping = 0.5,
			Damage = nil,
		},
		Fireball = {
			Asset = "Fireball",
			Speed = 120,
			MaxRange = 80,
			Gravity = false,
			ArcHeight = 0,
			ArcHeightCap = 0,
			Size = Vector3.new(3, 3, 3),
			Bounce = false,
			BounceCount = 0,
			BounceDamping = 0,
			Damage = nil,
		},
		Bullet = {
			Asset = "Bullet",
			Speed = 300,
			MaxRange = 200,
			Gravity = false,
			ArcHeight = 0,
			ArcHeightCap = 0,
			Size = Vector3.new(0.3, 0.3, 2),
			Bounce = false,
			BounceCount = 0,
			BounceDamping = 0,
			Damage = nil,
		},
		Bomb = {
			Asset = "Bomb",
			Speed = 40,
			MaxRange = 40,
			Gravity = true,
			ArcHeight = 0.2,
			ArcHeightCap = 8,
			Size = Vector3.new(2.5, 2.5, 2.5),
			Bounce = false,
			BounceCount = 0,
			BounceDamping = 0,
			Damage = nil,
		},
		Waterball = {
			Asset = "Waterball",
			Speed = 65,
			MaxRange = 75,
			Gravity = true,
			ArcHeight = 0.18,
			ArcHeightCap = 10,
			Size = Vector3.new(1.8, 1.8, 1.8),
			Bounce = false,
			BounceCount = 0,
			BounceDamping = 0,
			Damage = nil,
		},
	},

	----------------------------------------------------------------------
	-- Attack move definitions
	-- Each entry defines the base parameters for that move.
	-- Attack modules read these; values can be overridden per-brainrot via BrainrotConfig.
	----------------------------------------------------------------------
	Moves = {
		---------- MELEE ----------
		BasicMelee = {
			Type = "Melee",
			Weight = "Light",
			Range = 6,
			Cooldown = 1.25,
			WindupTime = 0.2,
			DamageMult = 1.0,
		},
		HeavyMelee = {
			Type = "Melee",
			Weight = "Heavy",
			Range = 7,
			Cooldown = 3.0,
			WindupTime = 0.8,
			DamageMult = 2.5,
		},
		JumpStomp = {
			Type = "Melee",
			Weight = "Heavy",
			Range = 12,
			Cooldown = 4.0,
			WindupTime = 0.6,
			DamageMult = 2.0,
			AoERadius = 8,
			LeapHeight = 20,
		},
		HitAndRun = {
			Type = "Melee",
			Weight = "Light",
			Range = 6,
			Cooldown = 2.5,
			WindupTime = 0.15,
			DamageMult = 0.8,
			FleeTime = 1.5,
		},
		MultiSwing = {
			Type = "Melee",
			Weight = "Light",
			Range = 6,
			Cooldown = 2.5,
			WindupTime = 0.1,
			DamageMult = 0.5,   -- per swing
			Swings = 3,
			SwingDelay = 0.25,
		},
		SwoopStrike = {
			Type = "Melee",
			Weight = "Heavy",
			Range = 15,
			Cooldown = 3.5,
			WindupTime = 1.0,
			DamageMult = 2.2,
		},
		Lunge = {
			Type = "Melee",
			Weight = "Heavy",
			Range = 18,           -- gap-closer range (6-18 studs)
			Cooldown = 3.5,
			WindupTime = 0.4,     -- short crouch before leap
			DamageMult = 1.8,
			LeapHeight = 12,      -- low arc, forward-biased
			LeapSpeed = 55,       -- studs/sec forward velocity
			HitRadius = 10,       -- landing hit detection radius
		},

		---------- PROJECTILE ----------
		-- Spread: accuracy deviation in studs (0 = perfect aim, higher = worse)
		-- AnimationKey: override for animation name (default per-module)
		StandAndHurl = {
			Type = "Projectile",
			Weight = "Light",
			Range = 50,
			Cooldown = 2.0,
			WindupTime = 0.4,
			DamageMult = 0.8,
			Projectile = "Rock",
			Spread = 2,            -- slight inaccuracy by default
			AnimationKey = "Throw",
		},
		ChaseAndHurl = {
			Type = "Projectile",
			Weight = "Light",
			Range = 35,
			Cooldown = 1.5,
			WindupTime = 0.3,
			DamageMult = 0.6,
			Projectile = "Tomato",
			Spread = 3,            -- harder to aim while running
			AnimationKey = "Throw",
		},
		DropAndRun = {
			Type = "Projectile",
			Weight = "Light",
			Range = 8,
			Cooldown = 3.0,
			WindupTime = 0.1,
			DamageMult = 1.2,
			Projectile = "Rock",
			FleeTime = 2.0,
		},
		GunStyle = {
			Type = "Projectile",
			Weight = "Light",
			Range = 80,
			Cooldown = 0.3,
			WindupTime = 0.05,
			DamageMult = 0.25,  -- per bullet
			Projectile = "Bullet",
			BurstCount = 3,
			BurstDelay = 0.08,
			Spread = 1,
		},
		BombDrop = {
			Type = "Projectile",
			Weight = "Heavy",
			Range = 25,
			Cooldown = 4.0,
			WindupTime = 0.5,
			DamageMult = 2.0,
			Projectile = "Bomb",
			AoERadius = 12,
		},
	},
}

return AttackConfig
