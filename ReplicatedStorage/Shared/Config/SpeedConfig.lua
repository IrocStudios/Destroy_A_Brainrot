-- ReplicatedStorage/Shared/Config/SpeedConfig.lua
-- Sequential speed upgrade tiers. SpeedBonus is the TOTAL bonus at that tier.
-- Player must purchase tiers in order (tier 1 → tier 2 → …).

local SpeedConfig = {
	Tiers = {
		{ Name = "Quick Feet",   SpeedBonus = 2,  Price = 500   },
		{ Name = "Jogger",       SpeedBonus = 4,  Price = 1500  },
		{ Name = "Runner",       SpeedBonus = 7,  Price = 4000  },
		{ Name = "Sprinter",     SpeedBonus = 12, Price = 10000 },
		{ Name = "Speedrunner",  SpeedBonus = 20, Price = 30000 },
	},
}

return SpeedConfig
