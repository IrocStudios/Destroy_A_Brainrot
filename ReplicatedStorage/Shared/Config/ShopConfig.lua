-- ReplicatedStorage/Shared/Config/ShopConfig.lua
-- Shop structure, categories, item grouping, featured items, and sorting metadata.
-- References WeaponConfig keys (weapon ids) so ShopService can build listings.

local ShopConfig = {
	Version = 1,

	-- UI category order
	Categories = {
		{
			Id = "featured",
			DisplayName = "Featured",
			Order = 1,
			Layout = {
				CardStyle = "Large",
				GridColumns = 2,
			},
		},
		{
			Id = "primary",
			DisplayName = "Primary",
			Order = 2,
			Layout = {
				CardStyle = "Standard",
				GridColumns = 3,
			},
		},
		{
			Id = "secondary",
			DisplayName = "Secondary",
			Order = 3,
			Layout = {
				CardStyle = "Standard",
				GridColumns = 3,
			},
		},
		{
			Id = "special",
			DisplayName = "Special",
			Order = 4,
			Layout = {
				CardStyle = "Standard",
				GridColumns = 2,
			},
		},
	},

	-- Sorting rules are metadata only; service decides how to apply.
	Sorting = {
		-- Suggested: first enforce StageRequirement <= player stage, then sort.
		DefaultSort = {
			PrimaryKey = "StageRequirement", -- asc
			SecondaryKey = "Price", -- asc
			TertiaryKey = "RarityDisplayOrder", -- asc via RarityConfig.DisplayOrder
		},
	},

	-- Featured items are referenced by WeaponConfig weapon ids.
	Featured = {
		Rotation = {
			-- Metadata for rotation system (if you have one)
			Enabled = true,
			RefreshHours = 12,
			MaxFeatured = 4,
		},

		Items = {
			-- These are curated picks; can be seasonal without touching services.
			"doomscroll_rifle",
			"sigma_shotgun",
			"algorithm_lance",
			"meme_smg",
		},
	},

	-- Category contents. Each entry references WeaponConfig weapon ids.
	Inventory = {
		primary = {
			DisplayOrder = 1,
			Items = {
				"plastic_spoon",
				"stapler_pistol",
				"meme_smg",
				"doomscroll_rifle",
				"sigma_shotgun",
			},
		},

		secondary = {
			DisplayOrder = 2,
			Items = {
				"adblocker_blade",
			},
		},

		special = {
			DisplayOrder = 3,
			Items = {
				"algorithm_lance",
				"mythic_ping_cannon",
			},
		},
	},

	-- Optional UI grouping ribbons/tags (pure metadata)
	Badges = {
		-- Example usage: show a "New" badge for specific items until removed.
		New = {
			Enabled = true,
			ItemIds = {
				"mythic_ping_cannon",
			},
		},
		BestValue = {
			Enabled = true,
			ItemIds = {
				"stapler_pistol",
				"meme_smg",
			},
		},
	},
}

return ShopConfig