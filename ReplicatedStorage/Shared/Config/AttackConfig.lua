--!strict
-- ReplicatedStorage/Shared/Config/AttackConfig.lua
-- Data-only definitions for attack moves and projectile skins.
-- Used by AttackRegistry (server) and AttackFXController (client).

local AttackConfig = {

	----------------------------------------------------------------------
	-- Projectile skins
	-- Key = skin name referenced by moves. Asset = ReplicatedStorage.Assets.Projectiles child name.
	----------------------------------------------------------------------
	Projectiles = {
		Rock = {
			Asset = "Rock",        -- folder/part name under Assets.Projectiles
			Speed = 80,
			Gravity = true,
			Size = Vector3.new(2, 2, 2),
		},
		Tomato = {
			Asset = "Tomato",
			Speed = 60,
			Gravity = true,
			Size = Vector3.new(1.5, 1.5, 1.5),
		},
		Fireball = {
			Asset = "Fireball",
			Speed = 120,
			Gravity = false,
			Size = Vector3.new(3, 3, 3),
		},
		Bullet = {
			Asset = "Bullet",
			Speed = 300,
			Gravity = false,
			Size = Vector3.new(0.3, 0.3, 2),
		},
		Bomb = {
			Asset = "Bomb",
			Speed = 40,
			Gravity = true,
			Size = Vector3.new(2.5, 2.5, 2.5),
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

		---------- PROJECTILE ----------
		StandAndHurl = {
			Type = "Projectile",
			Weight = "Light",
			Range = 50,
			Cooldown = 2.0,
			WindupTime = 0.4,
			DamageMult = 0.8,
			Projectile = "Rock",
		},
		ChaseAndHurl = {
			Type = "Projectile",
			Weight = "Light",
			Range = 35,
			Cooldown = 1.5,
			WindupTime = 0.3,
			DamageMult = 0.6,
			Projectile = "Tomato",
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
