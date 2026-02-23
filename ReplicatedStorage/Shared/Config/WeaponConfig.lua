-- ReplicatedStorage/Shared/Config/WeaponConfig.lua
-- Weapons are already implemented Tools.
-- This is metadata only: pricing, requirements, UI stats, categorization.

local WeaponConfig = {
	Version = 1,

	-- Optional category order for UI
	CategoryOrder = {
		"Primary",
		"Secondary",
		"Special",
	},

	Weapons = {
		-- Stage 1
		["plastic_spoon"] = {
			ToolName = "PlasticSpoon", -- must match Tool instance name
			DisplayName = "Plastic Spoon",
			Description = "Lightweight, suspiciously sharp. Great for starting out.",
			Category = "Primary",
			Rarity = "Common",

			Price = 0,
			StageRequirement = 1,

			-- Display-only stats
			Damage = 9,
			FireRate = 2.2, -- attacks/sec (or shots/sec) for UI only

			IconId = nil,
		},

		["stapler_pistol"] = {
			ToolName = "StaplerPistol",
			DisplayName = "Stapler Pistol",
			Description = "Office-grade aggression with a satisfying click.",
			Category = "Primary",
			Rarity = "Uncommon",

			Price = 650,
			StageRequirement = 1,

			Damage = 14,
			FireRate = 3.1,

			IconId = nil,
		},

		-- Stage 2
		["meme_smg"] = {
			ToolName = "MemeSMG",
			DisplayName = "Meme SMG",
			Description = "Sprays hot takes at high velocity.",
			Category = "Primary",
			Rarity = "Rare",

			Price = 3_250,
			StageRequirement = 2,

			Damage = 11,
			FireRate = 8.8,

			IconId = nil,
		},

		["adblocker_blade"] = {
			ToolName = "AdblockerBlade",
			DisplayName = "Adblocker Blade",
			Description = "Cuts through clutter. Surprisingly effective at close range.",
			Category = "Secondary",
			Rarity = "Uncommon",

			Price = 2_100,
			StageRequirement = 2,

			Damage = 22,
			FireRate = 1.8,

			IconId = nil,
		},

		-- Stage 3
		["doomscroll_rifle"] = {
			ToolName = "DoomscrollRifle",
			DisplayName = "Doomscroll Rifle",
			Description = "Long-range negativity with consistent output.",
			Category = "Primary",
			Rarity = "Epic",

			Price = 11_500,
			StageRequirement = 3,

			Damage = 26,
			FireRate = 4.0,

			IconId = nil,
		},

		-- Stage 4
		["sigma_shotgun"] = {
			ToolName = "SigmaShotgun",
			DisplayName = "Sigma Shotgun",
			Description = "Close-range confidence booster. Deletes problems quickly.",
			Category = "Primary",
			Rarity = "Epic",

			Price = 24_000,
			StageRequirement = 4,

			Damage = 48,
			FireRate = 1.2,

			IconId = nil,
		},

		-- Stage 5+
		["algorithm_lance"] = {
			ToolName = "AlgorithmLance",
			DisplayName = "Algorithm Lance",
			Description = "Recommends pain directly to the target.",
			Category = "Special",
			Rarity = "Legendary",

			Price = 85_000,
			StageRequirement = 5,

			Damage = 72,
			FireRate = 0.95,

			IconId = nil,
		},

		["mythic_ping_cannon"] = {
			ToolName = "MythicPingCannon",
			DisplayName = "Mythic Ping Cannon",
			Description = "One ping. One regret. Built for late-game clearing.",
			Category = "Special",
			Rarity = "Mythic",

			Price = 220_000,
			StageRequirement = 7,

			Damage = 115,
			FireRate = 0.7,

			IconId = nil,
		},
	},
}

return WeaponConfig