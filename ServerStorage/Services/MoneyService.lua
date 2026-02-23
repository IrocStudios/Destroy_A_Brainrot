--!strict
-- MoneyService
-- Spawns client-only money stacks (visuals on client), validates collection on server via RemoteFunction "MoneyCollect".
-- NetService routes MoneyCollect -> MoneyService:HandleMoneyCollect(player, payload)

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Services = { [string]: any }

type DropRecord = {
	DropId: string,
	UserId: number,
	Value: number,
	ExpiresAt: number,
	Pos: Vector3,
	Claimed: boolean,
}

local MoneyService = {}
MoneyService.__index = MoneyService

local DEBUG = true
local function dprint(...)
	if DEBUG then
		print("[MoneyService]", ...)
	end
end
local function dwarn(...)
	if DEBUG then
		warn("[MoneyService]", ...)
	end
end

function MoneyService:Init(services: Services)
	self.Services = services
	self.NetService = services.NetService
	self.EconomyService = services.EconomyService

	self.Drops = {} :: { [string]: DropRecord }

	-- where the client clones from
	self.MoneyTemplate = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Money"):WaitForChild("MoneyStack")

	-- Remotes (created by command bar script / RemoteService system)
	local sharedNet = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")
	local remotes = sharedNet:WaitForChild("Remotes"):WaitForChild("RemoteEvents")
	self.MoneySpawnRE = remotes:WaitForChild("MoneySpawn") :: RemoteEvent

	self._janitorRunning = false

	dprint("Init OK. MoneyTemplate=", self.MoneyTemplate:GetFullName(), "MoneySpawnRE=", self.MoneySpawnRE:GetFullName())
end

function MoneyService:Start()
	if not self._janitorRunning then
		self._janitorRunning = true
		task.spawn(function()
			while true do
				task.wait(20)
				self:_CleanupExpired()
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		-- remove their unclaimed drops
		for id, rec in pairs(self.Drops) do
			if rec.UserId == player.UserId then
				self.Drops[id] = nil
			end
		end
	end)

	dprint("Start OK.")
end

-- NetService route wrapper (REQUIRED)
-- NetService calls: RouteAction("MoneyService","HandleMoneyCollect", player, payload)
function MoneyService:HandleMoneyCollect(player: Player, payload: any)
	local dropId: any = payload
	if type(payload) == "table" then
		dropId = payload.dropId or payload.id or payload[1]
	end
	return self:MoneyCollect(player, dropId)
end

-- Server -> Client: spawn visuals only for that player.
-- Client will call MoneyCollect(dropId) when touched.
function MoneyService:SpawnMoneyStacks(position: Vector3, totalValue: number, player: Player)
	if totalValue <= 0 then
		dwarn("SpawnMoneyStacks called with non-positive value:", totalValue, "for", player and player.Name)
		return
	end
	if not player or not player:IsA("Player") then
		dwarn("SpawnMoneyStacks called with invalid player")
		return
	end

	-- Clamp & normalize
	totalValue = math.floor(totalValue + 0.5)
	totalValue = math.clamp(totalValue, 1, 10 ^ 12)

	local stacks = math.random(1, 15)
	stacks = math.clamp(stacks, 1, 15)

	-- random weights -> integer values that sum to totalValue
	local weights = table.create(stacks, 0)
	local sumW = 0
	for i = 1, stacks do
		local w = math.random()
		weights[i] = w
		sumW += w
	end

	local values = table.create(stacks, 0)
	local remainder = totalValue
	for i = 1, stacks do
		local v
		if i == stacks then
			v = remainder
		else
			v = math.max(1, math.floor((totalValue * (weights[i] / sumW)) + 0.5))
			v = math.min(v, remainder - (stacks - i)) -- leave at least 1 for remaining
			remainder -= v
		end
		values[i] = v
	end

	local payloadOut = {} :: { any }
	local baseY = position.Y + 1.0

	for i = 1, stacks do
		local dropId = HttpService:GenerateGUID(false)
		local angle = math.rad(math.random(0, 359))
		local radius = math.random(6, 14) + math.random()

		local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local pos = Vector3.new(position.X, baseY, position.Z) + offset

		self.Drops[dropId] = {
			DropId = dropId,
			UserId = player.UserId,
			Value = values[i],
			ExpiresAt = os.clock() + 45, -- seconds
			Pos = pos,
			Claimed = false,
		}

		table.insert(payloadOut, {
			id = dropId,
			value = values[i],
			pos = { pos.X, pos.Y, pos.Z },
		})
	end

	dprint("Dropping cash:", totalValue, "stacks=", stacks, "to=", player.Name, "at=", tostring(position))

	-- FireClient to ONLY this player, so the drops are local-only.
	self.MoneySpawnRE:FireClient(player, payloadOut)

	return payloadOut
end

-- RemoteFunction entrypoint (via NetService routing)
-- MoneyCollect(dropId) -> { ok=true/false, amount=?, reason=? }
function MoneyService:MoneyCollect(player: Player, dropId: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return { ok = false, reason = "BadPlayer" }
	end
	if type(dropId) ~= "string" then
		return { ok = false, reason = "BadDropId" }
	end

	local rec = self.Drops[dropId]
	if not rec then
		return { ok = false, reason = "UnknownDrop" }
	end
	if rec.UserId ~= player.UserId then
		return { ok = false, reason = "NotYours" }
	end
	if rec.Claimed then
		return { ok = false, reason = "AlreadyClaimed" }
	end
	if os.clock() > rec.ExpiresAt then
		self.Drops[dropId] = nil
		return { ok = false, reason = "Expired" }
	end

	rec.Claimed = true
	self.Drops[dropId] = nil

	-- grant cash via EconomyService only
	if self.EconomyService and self.EconomyService.AddCash then
		self.EconomyService:AddCash(player, rec.Value, "MoneyDropCollect")
		dprint("Collected:", player.Name, "amount=", rec.Value, "dropId=", dropId)
	else
		dwarn("EconomyService.AddCash missing; collection succeeded but no currency awarded.")
	end

	return { ok = true, amount = rec.Value }
end

function MoneyService:_CleanupExpired()
	local now = os.clock()
	local n = 0
	for id, rec in pairs(self.Drops) do
		if rec.Claimed or now > rec.ExpiresAt then
			self.Drops[id] = nil
			n += 1
		end
	end
	if n > 0 then
		dprint("Cleaned expired drops:", n)
	end
end

return MoneyService