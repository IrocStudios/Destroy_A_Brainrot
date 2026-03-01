-- ReplicatedStorage/Shared/Config/GiftConfig.lua
-- Gift definitions keyed by asset folder name (e.g. "Blue", "Purple").
-- Each gift is a *key* to a loot table — the gift asset in ShopAssets/Gifts
-- holds the icon and display info, this config holds the items inside.
--
-- Gift asset folders live at: ReplicatedStorage.ShopAssets.Gifts.[Key]
--   Each has: Icon [ImageLabel], @DisplayName attribute

local GiftConfig = {}

--------------------------------------------------------------
-- Loot tables keyed by gift folder name
-- weight = relative probability, kind = reward type, tier = pity classification (1-7)
--------------------------------------------------------------
GiftConfig.Gifts = {
	--------------------------------------------------------------
	-- BLUE  (common-tier gift)
	--------------------------------------------------------------
	Blue = {
		pity = { threshold = 15, minTier = 3 },
		loot = {
			{ weight = 30, kind = "Cash",      amount = 200,   tier = 1 },
			{ weight = 20, kind = "XP",        amount = 50,    tier = 1 },
			{ weight = 10, kind = "Cash",      amount = 800,   tier = 2 },
			{ weight = 15, kind = "Weapon",    weaponKey = "StarterWeapon", dupeCashValue = 150, tier = 2 },
			{ weight = 12, kind = "Weapon",    weaponKey = "BasicSword",    dupeCashValue = 150, tier = 2 },
			{ weight = 8,  kind = "Weapon",    weaponKey = "AK12",          dupeCashValue = 300, tier = 3 },
			{ weight = 3,  kind = "ArmorStep", steps = 1,      tier = 3 },
			{ weight = 2,  kind = "SpeedStep", steps = 1,      tier = 3 },
		},
	},

	--------------------------------------------------------------
	-- PURPLE  (uncommon-tier gift — placeholder loot, tune later)
	--------------------------------------------------------------
	Purple = {
		pity = { threshold = 12, minTier = 3 },
		loot = {
			{ weight = 25, kind = "Cash",      amount = 500,   tier = 1 },
			{ weight = 18, kind = "XP",        amount = 100,   tier = 1 },
			{ weight = 12, kind = "Cash",      amount = 2000,  tier = 2 },
			{ weight = 15, kind = "Weapon",    weaponKey = "AK12",          dupeCashValue = 300, tier = 2 },
			{ weight = 10, kind = "ArmorStep", steps = 2,      tier = 3 },
			{ weight = 8,  kind = "SpeedStep", steps = 2,      tier = 3 },
			{ weight = 7,  kind = "Cash",      amount = 5000,  tier = 3 },
			{ weight = 5,  kind = "XP",        amount = 500,   tier = 3 },
		},
	},
}

--------------------------------------------------------------
-- Helpers
--------------------------------------------------------------

--- Get the gift definition by its key (folder name).
function GiftConfig.GetGift(key: string)
	return GiftConfig.Gifts[key]
end

--- Get display name from the ShopAssets folder's @DisplayName attribute.
--- Falls back to the key itself if asset is not available (server-side).
function GiftConfig.GetDisplayName(key: string): string
	-- Try reading from the asset at runtime
	local ok, result = pcall(function()
		local rs = game:GetService("ReplicatedStorage")
		local folder = rs:FindFirstChild("ShopAssets")
			and rs.ShopAssets:FindFirstChild("Gifts")
			and rs.ShopAssets.Gifts:FindFirstChild(key)
		if folder then
			return folder:GetAttribute("DisplayName") or key
		end
		return key
	end)
	return (ok and result) or key
end

return GiftConfig
