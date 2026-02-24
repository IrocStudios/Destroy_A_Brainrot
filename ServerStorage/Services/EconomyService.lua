--!strict
local EconomyService = {}

local function clampNonNeg(n: number): number
	if n ~= n then return 0 end
	if n < 0 then return 0 end
	return n
end

function EconomyService:Init(services)
	self.Services = services
	self.DataService = services.DataService
	self.NetService = services.NetService
end

function EconomyService:Start() end

function EconomyService:GetCash(player: Player): number
	local v = self.DataService:GetValue(player, "Currency.Cash")
	if typeof(v) ~= "number" then return 0 end
	return v
end

function EconomyService:AddCash(player: Player, amount: number, reason: string?)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return false, "InvalidAmount"
	end

	local newCash: number = 0
	self.DataService:Update(player, function(profile)
		local cur = profile.Currency.Cash or 0
		newCash = cur + amount
		profile.Currency.Cash = newCash
		return profile
	end)

	-- Send delta to client
	if self.NetService then
		self.NetService:QueueDelta(player, "Cash", newCash)
		self.NetService:FlushDelta(player)
	end

	return true
end

function EconomyService:SpendCash(player: Player, amount: number)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return false, "InvalidAmount"
	end

	local ok = false
	local newCash: number = 0

	self.DataService:Update(player, function(profile)
		local cur = profile.Currency.Cash or 0
		if cur < amount then
			ok = false
			newCash = cur
			return profile
		end
		ok = true
		newCash = cur - amount
		profile.Currency.Cash = newCash
		return profile
	end)

	if ok and self.NetService then
		self.NetService:QueueDelta(player, "Cash", clampNonNeg(newCash))
		self.NetService:FlushDelta(player)
	end

	return ok, ok and nil or "InsufficientCash"
end

return EconomyService