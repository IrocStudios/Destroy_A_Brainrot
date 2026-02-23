--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RarityService = {}
RarityService.__index = RarityService

local _config = nil -- loaded in Init; avoids require at module scope

function RarityService:Init(services)
	self.Services = services
	_config = require(
		ReplicatedStorage
			:WaitForChild("Shared")
			:WaitForChild("Config")
			:WaitForChild("RarityConfig")
	)
end

function RarityService:Start() end

-- Returns { Color, Category, Multipliers = { Cash, XP, Value } }
-- Falls back to Common if the rarity name is unknown.
function RarityService:GetRarityData(rarityName: string)
	local rarities = _config and _config.Rarities
	if not rarities then
		return {
			Color = Color3.fromRGB(190, 190, 190),
			Category = "Common",
			Multipliers = { Cash = 1.0, XP = 1.0, Value = 1.0 },
		}
	end

	local entry = rarities[rarityName]
		or rarities[_config.DefaultRarity]
		or rarities.Common
	return {
		Color    = entry.Color,
		Category = rarityName,
		-- ValueMultiplier drives both the cash payout and the brainrot's displayed value.
		Multipliers = {
			Cash  = entry.ValueMultiplier,
			XP    = entry.XPMultiplier,
			Value = entry.ValueMultiplier,
		},
	}
end

function RarityService:GetColor(rarityName: string): Color3
	return self:GetRarityData(rarityName).Color
end

function RarityService:GetMultipliers(rarityName: string)
	return self:GetRarityData(rarityName).Multipliers
end

return RarityService
