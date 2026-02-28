--!strict
-- ServerStorage/Services/ArmorService
-- Destroy a Brainrot — Armor system (server-authoritative)
--
-- Manages current armor + max armor per player.
-- Armor absorbs damage before health. Other services call DamageArmor()
-- to deduct armor first, then apply overflow to health.
--
-- Pattern mirrors EconomyService / SpeedController:
--   - Persistent values in DataService  (Defense.Armor, Defense.MaxArmor)
--   - State sync via NetService deltas   (NetIds: Armor=70, MaxArmor=71)
--   - Methods are thin wrappers so future systems (shop, pickups, etc.) just call ArmorService.

local ArmorService = {}

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
function ArmorService:Init(services)
	self.Services   = services
	self.DataService = services.DataService
	self.NetService  = services.NetService
end

function ArmorService:Start()
	-- When a profile loads, sync initial armor state to the client
	self.DataService.OnProfileLoaded:Connect(function(player, data)
		if not data.Defense then return end
		self:_syncArmor(player, data.Defense.Armor, data.Defense.MaxArmor)
	end)
end

----------------------------------------------------------------------
-- Internal: send Armor + MaxArmor deltas to client
----------------------------------------------------------------------
function ArmorService:_syncArmor(player: Player, armor: number, maxArmor: number)
	if not self.NetService then return end
	self.NetService:QueueDelta(player, "Armor", armor)
	self.NetService:QueueDelta(player, "MaxArmor", maxArmor)
	self.NetService:FlushDelta(player)
end

----------------------------------------------------------------------
-- Getters
----------------------------------------------------------------------
function ArmorService:GetArmor(player: Player): number
	local v = self.DataService:GetValue(player, "Defense.Armor")
	return (typeof(v) == "number") and v or 0
end

function ArmorService:GetMaxArmor(player: Player): number
	local v = self.DataService:GetValue(player, "Defense.MaxArmor")
	return (typeof(v) == "number") and v or 0
end

----------------------------------------------------------------------
-- SetMaxArmor  —  called by shop / upgrade systems to raise the cap
----------------------------------------------------------------------
function ArmorService:SetMaxArmor(player: Player, newMax: number)
	newMax = math.max(0, math.floor(tonumber(newMax) or 0))

	local armor = 0
	self.DataService:Update(player, function(data)
		data.Defense = data.Defense or { Armor = 0, MaxArmor = 0 }
		data.Defense.MaxArmor = newMax
		-- Clamp current armor to new max
		if data.Defense.Armor > newMax then
			data.Defense.Armor = newMax
		end
		armor = data.Defense.Armor
		return data
	end)

	self:_syncArmor(player, armor, newMax)
	return true
end

----------------------------------------------------------------------
-- SetArmor  —  directly set current armor (clamped to max)
----------------------------------------------------------------------
function ArmorService:SetArmor(player: Player, amount: number)
	amount = math.max(0, math.floor(tonumber(amount) or 0))

	local armor = 0
	local maxArmor = 0
	self.DataService:Update(player, function(data)
		data.Defense = data.Defense or { Armor = 0, MaxArmor = 0 }
		maxArmor = data.Defense.MaxArmor
		armor = math.min(amount, maxArmor)
		data.Defense.Armor = armor
		return data
	end)

	self:_syncArmor(player, armor, maxArmor)
	return true
end

----------------------------------------------------------------------
-- AddArmor  —  add points (clamped to max). Returns actual amount added.
----------------------------------------------------------------------
function ArmorService:AddArmor(player: Player, amount: number): number
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if amount == 0 then return 0 end

	local added = 0
	local armor = 0
	local maxArmor = 0

	self.DataService:Update(player, function(data)
		data.Defense = data.Defense or { Armor = 0, MaxArmor = 0 }
		maxArmor = data.Defense.MaxArmor
		local cur = data.Defense.Armor
		local newArmor = math.min(cur + amount, maxArmor)
		added = newArmor - cur
		data.Defense.Armor = newArmor
		armor = newArmor
		return data
	end)

	if added > 0 then
		self:_syncArmor(player, armor, maxArmor)
	end

	return added
end

----------------------------------------------------------------------
-- DamageArmor  —  absorb damage through armor first.
-- Returns:  armorAbsorbed, overflow
--   armorAbsorbed = how much damage the armor ate
--   overflow      = remaining damage that passes through to health
----------------------------------------------------------------------
function ArmorService:DamageArmor(player: Player, damage: number): (number, number)
	damage = math.max(0, tonumber(damage) or 0)
	if damage == 0 then return 0, 0 end

	local absorbed = 0
	local overflow = 0
	local armor = 0
	local maxArmor = 0

	self.DataService:Update(player, function(data)
		data.Defense = data.Defense or { Armor = 0, MaxArmor = 0 }
		maxArmor = data.Defense.MaxArmor
		local cur = data.Defense.Armor

		if cur >= damage then
			absorbed = damage
			overflow = 0
		else
			absorbed = cur
			overflow = damage - cur
		end

		data.Defense.Armor = cur - absorbed
		armor = data.Defense.Armor
		return data
	end)

	if absorbed > 0 then
		self:_syncArmor(player, armor, maxArmor)
	end

	return absorbed, overflow
end

----------------------------------------------------------------------
-- ReplenishArmor  —  fill current armor back to max
----------------------------------------------------------------------
function ArmorService:ReplenishArmor(player: Player): number
	local added = 0
	local maxArmor = 0

	self.DataService:Update(player, function(data)
		data.Defense = data.Defense or { Armor = 0, MaxArmor = 0 }
		maxArmor = data.Defense.MaxArmor
		added = maxArmor - data.Defense.Armor
		data.Defense.Armor = maxArmor
		return data
	end)

	if added > 0 then
		self:_syncArmor(player, maxArmor, maxArmor)
	end

	return added
end

return ArmorService
