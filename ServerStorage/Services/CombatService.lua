--!strict
-- CombatService
-- Tracks per-brainrot damage, applies server-authoritative damage, and pays out on death.
-- Damage entrypoint is RemoteFunction "DamageBrainrot" routed by NetService -> CombatService:HandleDamageBrainrot(player, guid, amount)

local Players = game:GetService("Players")

type Services = { [string]: any }

type BrainrotRecord = {
	Guid: string,
	BrainrotName: string,
	Humanoid: Humanoid,
	Root: BasePart,
	MaxHealth: number,
	TotalValue: number,
	Rarity: string?,
	DamageByUserId: { [number]: number },
	DiedConn: RBXScriptConnection?,
	CreatedAt: number,
}

local CombatService = {}
CombatService.__index = CombatService

local DEBUG = true
local function dprint(...)
	if DEBUG then
		print("[CombatService]", ...)
	end
end
local function dwarn(...)
	if DEBUG then
		warn("[CombatService]", ...)
	end
end

function CombatService:Init(services: Services)
	self.Services = services

	self.MoneyService = services.MoneyService
	self.ProgressionService = services.ProgressionService
	self.IndexService = services.IndexService
	self.RewardService = services.RewardService -- optional
	self.NetService = services.NetService
	self.RarityService = services.RarityService

	self.Brainrots = {} :: { [string]: BrainrotRecord }

	self._lastDamageAt = {} :: { [number]: number }

	dprint("Init OK.")
end

function CombatService:Start()
	dprint("Start OK.")
end

function CombatService:HandleDamageBrainrot(player: Player, brainrotGuid: any, damageAmount: any)
	return self:DamageBrainrot(player, brainrotGuid, damageAmount)
end

function CombatService:RegisterBrainrot(
	brainrotGuid: string,
	humanoid: Humanoid,
	root: BasePart,
	maxHealth: number?,
	totalValue: number?,
	rarityName: string?,
	brainrotName: string?
)
	assert(type(brainrotGuid) == "string" and brainrotGuid ~= "", "RegisterBrainrot requires guid")
	assert(humanoid and humanoid:IsA("Humanoid"), "RegisterBrainrot requires Humanoid")
	assert(root and root:IsA("BasePart"), "RegisterBrainrot requires Root BasePart")

	if self.Brainrots[brainrotGuid] then
		self:UnregisterBrainrot(brainrotGuid)
	end

	local mh = maxHealth or humanoid.MaxHealth
	if typeof(mh) ~= "number" or mh ~= mh or mh <= 0 then
		mh = 100
	end

	-- IMPORTANT FIX: 0 is truthy in Lua; we must treat 0 as invalid value.
	local tv = totalValue
	if typeof(tv) ~= "number" or tv ~= tv or tv <= 0 then
		tv = mh
	end

	local rn = (type(rarityName) == "string" and rarityName ~= "") and rarityName or "Common"

	local bn = (type(brainrotName) == "string" and brainrotName ~= "") and brainrotName or "Unknown"

	local rec: BrainrotRecord = {
		Guid = brainrotGuid,
		BrainrotName = bn,
		Humanoid = humanoid,
		Root = root,
		MaxHealth = mh,
		TotalValue = tv :: number,
		Rarity = rn,
		DamageByUserId = {},
		DiedConn = nil,
		CreatedAt = os.clock(),
	}

	rec.DiedConn = humanoid.Died:Connect(function()
		dprint("Humanoid.Died fired:", brainrotGuid, "Rarity=", rn, "Value=", tv, "Root=", root:GetFullName())
		self:_OnBrainrotDied(brainrotGuid)
	end)

	self.Brainrots[brainrotGuid] = rec

	dprint("Registered:", brainrotGuid, "MH=", mh, "TV=", tv, "Rarity=", rn, "Humanoid=", humanoid:GetFullName())
end

function CombatService:UnregisterBrainrot(brainrotGuid: string)
	local rec = self.Brainrots[brainrotGuid]
	if not rec then return end
	if rec.DiedConn then
		rec.DiedConn:Disconnect()
	end
	self.Brainrots[brainrotGuid] = nil
	dprint("Unregistered:", brainrotGuid)
end

function CombatService:DamageBrainrot(player: Player, brainrotGuid: any, damageAmount: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return { ok = false, reason = "BadPlayer" }
	end
	if type(brainrotGuid) ~= "string" then
		return { ok = false, reason = "BadGuid" }
	end
	if type(damageAmount) ~= "number" then
		return { ok = false, reason = "BadDamage" }
	end

	local now = os.clock()
	local last = self._lastDamageAt[player.UserId]
	if last and (now - last) < 0.03 then
		return { ok = false, reason = "RateLimited" }
	end
	self._lastDamageAt[player.UserId] = now

	local rec = self.Brainrots[brainrotGuid]
	if not rec then
		return { ok = false, reason = "UnknownBrainrot" }
	end

	if rec.Humanoid.Health <= 0 then
		return { ok = false, reason = "Dead" }
	end

	local char = player.Character
	if not char then
		return { ok = false, reason = "NoCharacter" }
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return { ok = false, reason = "NoHRP" }
	end

	local dist = (hrp.Position - rec.Root.Position).Magnitude
	if dist > 250 then
		return { ok = false, reason = "TooFar" }
	end

	if damageAmount ~= damageAmount then
		return { ok = false, reason = "NaN" }
	end
	damageAmount = math.clamp(damageAmount, 0, 1e6)

	if damageAmount <= 0 then
		return { ok = true, health = rec.Humanoid.Health }
	end

	-- DEBUG: show incoming damage
	dprint("Damage:", player.Name, "->", brainrotGuid, "amt=", damageAmount, "HP(before)=", rec.Humanoid.Health)

	self:RegisterDamage(rec, player, damageAmount)

	return { ok = true, health = rec.Humanoid.Health }
end

function CombatService:RegisterDamage(brainrot: BrainrotRecord, player: Player, amount: number)
	local uid = player.UserId
	brainrot.DamageByUserId[uid] = (brainrot.DamageByUserId[uid] or 0) + amount
	brainrot.Humanoid:TakeDamage(amount)
end

function CombatService:_GetRarityMultipliers(rarityName: string?): (number, number, number)
	local rn = (type(rarityName) == "string" and rarityName ~= "") and rarityName or "Common"
	local valueMult, cashMult, xpMult = 1.0, 1.0, 1.0

	local rs = self.RarityService
	if rs and type(rs.GetMultipliers) == "function" then
		local ok, multipliers = pcall(function()
			return rs:GetMultipliers(rn)
		end)
		if ok and type(multipliers) == "table" then
			local vm = multipliers.Value or multipliers.value
			local cm = multipliers.Cash or multipliers.cash
			local xm = multipliers.XP or multipliers.xp
			if typeof(vm) == "number" then valueMult = vm end
			if typeof(cm) == "number" then cashMult = cm end
			if typeof(xm) == "number" then xpMult = xm end
		end
	else
		-- Not fatal
	end

	return valueMult, cashMult, xpMult
end

function CombatService:_OnBrainrotDied(brainrotGuid: string)
	local rec = self.Brainrots[brainrotGuid]
	if not rec then
		dwarn("OnBrainrotDied called but record missing:", brainrotGuid)
		return
	end

	-- If nobody damaged it via CombatService, nobody gets anything.
	local contributors = 0
	for _ in pairs(rec.DamageByUserId) do
		contributors += 1
	end

	dprint("Brainrot died:", brainrotGuid, "contributors=", contributors)

	if contributors == 0 then
		dwarn("No DamageByUserId entries for", brainrotGuid, "-> no cash/XP will be awarded. (Weapon not using DamageBrainrot?)")
		self:UnregisterBrainrot(brainrotGuid)
		return
	end

	-- Determine majority damager
	local topUserId = 0
	local topDamage = -1
	for uid, dmg in pairs(rec.DamageByUserId) do
		if dmg > topDamage then
			topDamage = dmg
			topUserId = uid
		end
	end

	local maxHealth = (rec.MaxHealth and rec.MaxHealth > 0) and rec.MaxHealth or rec.Humanoid.MaxHealth
	if maxHealth <= 0 then maxHealth = 100 end

	local valueMult, cashMult, xpMult = self:_GetRarityMultipliers(rec.Rarity)

	local baseValue = rec.TotalValue
	if typeof(baseValue) ~= "number" or baseValue ~= baseValue or baseValue <= 0 then
		baseValue = maxHealth
	end

	local effectiveValue = baseValue * valueMult

	for uid, dmg in pairs(rec.DamageByUserId) do
		local plr = Players:GetPlayerByUserId(uid)
		if plr then
			local frac = math.clamp(dmg / maxHealth, 0, 1)

			local cashShare = math.floor((effectiveValue * frac * cashMult) + 0.5)
			if cashShare > 0 and self.MoneyService and self.MoneyService.SpawnMoneyStacks then
				dprint("Award cash:", plr.Name, "cash=", cashShare, "frac=", frac, "rarity=", rec.Rarity)
				self.MoneyService:SpawnMoneyStacks(rec.Root.Position, cashShare, plr)
			else
				dprint("Cash computed 0 for", plr.Name, "frac=", frac, "effectiveValue=", effectiveValue, "cashMult=", cashMult)
			end

			local xpBase = (effectiveValue * 0.35)
			local xpShare = math.floor((xpBase * frac * xpMult) + 0.5)
			if xpShare > 0 and self.ProgressionService and self.ProgressionService.AddXP then
				dprint("Award XP:", plr.Name, "xp=", xpShare, "frac=", frac, "xpMult=", xpMult)
				self.ProgressionService:AddXP(plr, xpShare, "BrainrotDamage")
			end
		end
	end

	if topUserId ~= 0 then
		local killer = Players:GetPlayerByUserId(topUserId)
		if killer and self.IndexService then
			if type(self.IndexService.RegisterKill) == "function" then
				dprint("RegisterKill:", killer.Name, "brainrot=", rec.BrainrotName)
				self.IndexService:RegisterKill(killer, rec.BrainrotName)
			end
			if type(self.IndexService.RegisterDiscovery) == "function" then
				dprint("RegisterDiscovery:", killer.Name, "brainrot=", rec.BrainrotName)
				self.IndexService:RegisterDiscovery(killer, rec.BrainrotName, nil, rec.Rarity)
			end
		end

		if killer and self.RewardService then
			local fn = self.RewardService.OnBrainrotKilled or self.RewardService.TryDropGift
			if type(fn) == "function" then
				pcall(function()
					fn(self.RewardService, killer, brainrotGuid, rec.Rarity)
				end)
			end
		end
	end

	self:UnregisterBrainrot(brainrotGuid)
end

return CombatService