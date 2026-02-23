--!strict
-- CodesService.lua
-- Server-side promo code redemption.
-- Add new codes to CODES table: [code] = { reward = { type, amount } }
-- Redeemed codes are stored in player's profile under Data.RedeemedCodes (a set).

local CodesService = {}
CodesService.__index = CodesService

-- ── Define your promo codes here ─────────────────────────────────────────────
-- type = "cash" | "xp" | "rebirths"
local CODES: { [string]: { reward: { type: string, amount: number } } } = {
	["BRAINROT100"]  = { reward = { type = "cash", amount = 100   } },
	["LAUNCH500"]    = { reward = { type = "cash", amount = 500   } },
	["BIGXP"]        = { reward = { type = "xp",   amount = 2500  } },
	["FREECASH"]     = { reward = { type = "cash", amount = 1000  } },
}
-- ─────────────────────────────────────────────────────────────────────────────

function CodesService:Init(services)
	self.Services = services
end

function CodesService:Start() end

-- Returns { ok = true, reward = { type, amount } } or { ok = false, reason = string }
function CodesService:HandleCodesAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return { ok = false, reason = "Invalid" }
	end

	local raw: string = tostring(payload.code or "")
	local code = raw:upper():match("^%s*(.-)%s*$")  -- trim & uppercase

	local entry = CODES[code]
	if not entry then
		return { ok = false, reason = "Invalid" }
	end

	-- Check DataService for the profile
	local DataService = self.Services.DataService
	if not DataService or type(DataService.GetProfile) ~= "function" then
		return { ok = false, reason = "ServerError" }
	end

	local profile = DataService:GetProfile(player)
	if not profile then
		return { ok = false, reason = "ServerError" }
	end

	-- Initialise redemption set if missing
	profile.RedeemedCodes = profile.RedeemedCodes or {}
	if profile.RedeemedCodes[code] then
		return { ok = false, reason = "AlreadyRedeemed" }
	end

	-- Mark redeemed before granting (prevents double-grant on race)
	profile.RedeemedCodes[code] = true

	-- Grant the reward
	local reward = entry.reward
	local NetService = self.Services.NetService

	if reward.type == "cash" then
		profile.Currency = profile.Currency or {}
		profile.Currency.Cash = (profile.Currency.Cash or 0) + reward.amount
		if NetService then
			NetService:QueueDelta(player, "Cash", profile.Currency.Cash)
			NetService:FlushDelta(player)
		end

	elseif reward.type == "xp" then
		profile.Progression = profile.Progression or {}
		profile.Progression.XP = (profile.Progression.XP or 0) + reward.amount
		if NetService then
			NetService:QueueDelta(player, "XP", profile.Progression.XP)
			NetService:FlushDelta(player)
		end

	elseif reward.type == "rebirths" then
		profile.Progression = profile.Progression or {}
		profile.Progression.Rebirths = (profile.Progression.Rebirths or 0) + reward.amount
		if NetService then
			NetService:QueueDelta(player, "Rebirths", profile.Progression.Rebirths)
			NetService:FlushDelta(player)
		end
	end

	-- Notify the player with a popup
	if NetService then
		NetService:Notify(player, {
			type    = "alert",
			title   = "Code Redeemed!",
			message = ("You received %d %s!"):format(reward.amount, reward.type),
		})
	end

	-- Return a human-readable reward string so CodesModule can display it
	local rewardText = ("%d %s"):format(reward.amount, reward.type)
	return { ok = true, reward = rewardText, rewardData = reward }
end

return CodesService
