--!strict
-- ServerStorage/Services/ArmorService
-- Destroy a Brainrot — Armor system (server-authoritative)
--
-- Armor is a single "chargeable" number:
--   • Buying armor ADDS points.  Taking damage SUBTRACTS points.
--   • There is no max — only a current value (Defense.Armor).
--   • Defense.ArmorStep tracks how many purchases the player has made.
--
-- Other services call:
--   AddArmor(player, amount)   – shop purchases / pickups
--   DamageArmor(player, dmg)   – brainrot attacks (absorb → overflow)
--   GetArmor(player)           – read current armor

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
		self:_syncArmor(player, data.Defense.Armor, data.Defense.ArmorStep)
	end)
end

----------------------------------------------------------------------
-- Internal: send Armor + ArmorStep deltas to client
----------------------------------------------------------------------
function ArmorService:_syncArmor(player: Player, armor: number, step: number)
	if not self.NetService then return end
	self.NetService:QueueDelta(player, "Armor", armor)
	self.NetService:QueueDelta(player, "ArmorStep", step)
	self.NetService:FlushDelta(player)
end

----------------------------------------------------------------------
-- Getters
----------------------------------------------------------------------
function ArmorService:GetArmor(player: Player): number
	local v = self.DataService:GetValue(player, "Defense.Armor")
	return (typeof(v) == "number") and v or 0
end

function ArmorService:GetArmorStep(player: Player): number
	local v = self.DataService:GetValue(player, "Defense.ArmorStep")
	return (typeof(v) == "number") and v or 0
end

----------------------------------------------------------------------
-- AddArmor  —  add points (no cap). Returns actual amount added.
----------------------------------------------------------------------
function ArmorService:AddArmor(player: Player, amount: number): number
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if amount == 0 then return 0 end

	local armor = 0
	local step  = 0

	self.DataService:Update(player, function(data)
		data.Defense = data.Defense or { Armor = 0, ArmorStep = 0 }
		data.Defense.Armor = (data.Defense.Armor or 0) + amount
		armor = data.Defense.Armor
		step  = data.Defense.ArmorStep or 0
		return data
	end)

	self:_syncArmor(player, armor, step)
	return amount
end

----------------------------------------------------------------------
-- IncrementStep  —  bump ArmorStep by 1 after a purchase
----------------------------------------------------------------------
function ArmorService:IncrementStep(player: Player): number
	local armor = 0
	local step  = 0

	self.DataService:Update(player, function(data)
		data.Defense = data.Defense or { Armor = 0, ArmorStep = 0 }
		data.Defense.ArmorStep = (data.Defense.ArmorStep or 0) + 1
		armor = data.Defense.Armor or 0
		step  = data.Defense.ArmorStep
		return data
	end)

	self:_syncArmor(player, armor, step)
	return step
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
	local step  = 0

	self.DataService:Update(player, function(data)
		data.Defense = data.Defense or { Armor = 0, ArmorStep = 0 }
		local cur = data.Defense.Armor or 0

		if cur >= damage then
			absorbed = damage
			overflow = 0
		else
			absorbed = cur
			overflow = damage - cur
		end

		data.Defense.Armor = cur - absorbed
		armor = data.Defense.Armor
		step  = data.Defense.ArmorStep or 0
		return data
	end)

	if absorbed > 0 then
		self:_syncArmor(player, armor, step)
	end

	return absorbed, overflow
end

return ArmorService
