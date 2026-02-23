-- ReplicatedStorage/Shared/Config/RarityConfig.lua
-- Central rarity tier definitions + modifiers used across combat/rewards/UI.

local RarityConfig = {
	Version = 1,

	-- Order for UI display / sorting
	DisplayOrder = {
		"Common",
		"Uncommon",
		"Rare",
		"Epic",
		"Legendary",
		"Mythic",
	},

	-- If a service needs a default rarity.
	DefaultRarity = "Common",

	Rarities = {
		Common = {
			DisplayName = "Common",
			Color = Color3.fromRGB(190, 190, 190),

			HealthMultiplier = 1.00,
			ValueMultiplier = 1.00,
			XPMultiplier = 1.00,

			-- Multiplies the brainrot's base gift drop chance (if your RewardService uses one).
			GiftChanceMultiplier = 1.00,

			-- Global rarity spawn weight (optional layer). Higher => more common.
			SpawnWeight = 100,

			-- Optional UI cosmetics
			AnnouncementStyle = "None",
		},

		Uncommon = {
			DisplayName = "Uncommon",
			Color = Color3.fromRGB(95, 210, 120),

			HealthMultiplier = 1.18,
			ValueMultiplier = 1.22,
			XPMultiplier = 1.12,

			GiftChanceMultiplier = 1.20,
			SpawnWeight = 55,

			AnnouncementStyle = "Subtle",
		},

		Rare = {
			DisplayName = "Rare",
			Color = Color3.fromRGB(90, 145, 255),

			HealthMultiplier = 1.45,
			ValueMultiplier = 1.55,
			XPMultiplier = 1.35,

			GiftChanceMultiplier = 1.55,
			SpawnWeight = 25,

			AnnouncementStyle = "Toast",
		},

		Epic = {
			DisplayName = "Epic",
			Color = Color3.fromRGB(185, 95, 255),

			HealthMultiplier = 1.85,
			ValueMultiplier = 2.05,
			XPMultiplier = 1.85,

			GiftChanceMultiplier = 2.20,
			SpawnWeight = 10,

			UIGradient = {
				-- Optional gradient data for UI consumers (safe to ignore).
				-- Example usage: UIGradient.Color = ColorSequence.new(...)
				Colors = {
					Color3.fromRGB(200, 120, 255),
					Color3.fromRGB(140, 80, 255),
				},
			},

			AnnouncementStyle = "Banner",
		},

		Legendary = {
			DisplayName = "Legendary",
			Color = Color3.fromRGB(255, 200, 75),

			HealthMultiplier = 2.45,
			ValueMultiplier = 2.85,
			XPMultiplier = 2.40,

			GiftChanceMultiplier = 3.10,
			SpawnWeight = 3,

			UIGradient = {
				Colors = {
					Color3.fromRGB(255, 220, 120),
					Color3.fromRGB(255, 170, 60),
				},
			},

			AnnouncementStyle = "BannerLoud",
		},

		-- Future-proof tier (keep, even if not used often yet)
		Mythic = {
			DisplayName = "Mythic",
			Color = Color3.fromRGB(255, 85, 125),

			HealthMultiplier = 3.30,
			ValueMultiplier = 4.10,
			XPMultiplier = 3.10,

			GiftChanceMultiplier = 4.80,
			SpawnWeight = 1,

			UIGradient = {
				Colors = {
					Color3.fromRGB(255, 120, 170),
					Color3.fromRGB(255, 70, 120),
				},
			},

			AnnouncementStyle = "Global",
		},
	},
}

return RarityConfig