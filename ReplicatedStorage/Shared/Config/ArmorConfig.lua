-- ReplicatedStorage/Shared/Config/ArmorConfig.lua
-- Sequential armor upgrade tiers. ArmorBonus is the TOTAL MaxArmor at that tier.
-- Player must purchase tiers in order (tier 1 → tier 2 → …).

local ArmorConfig = {
	Tiers = {
		{ Name = "Light Plating",    ArmorBonus = 10,  Price = 750   },
		{ Name = "Steel Jacket",     ArmorBonus = 25,  Price = 2500  },
		{ Name = "Reinforced Suit",  ArmorBonus = 50,  Price = 7500  },
		{ Name = "Titan Armor",      ArmorBonus = 100, Price = 20000 },
		{ Name = "Fortress Shell",   ArmorBonus = 200, Price = 50000 },
	},
}

return ArmorConfig
