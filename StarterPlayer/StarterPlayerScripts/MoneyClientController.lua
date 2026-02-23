--!strict
-- MoneyClientController (LocalScript in StarterPlayerScripts)
-- Listens for server MoneySpawn payload and creates local-only money visuals.
-- On pickup (touch or prompt), calls RemoteFunction MoneyCollect (NetService routed).

print("MoneyControllerClient Started on client")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOCAL_PLAYER = Players.LocalPlayer

local function getNetRoot()
	return ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")
end

local function getRemoteService()
	local net = getNetRoot()
	return require(net:WaitForChild("RemoteService"))
end

-- IMPORTANT FIX:
-- Server MoneyService fires ReplicatedStorage.Shared.Net.Remotes.RemoteEvents.MoneySpawn
-- (MoneySpawn is under Remotes/RemoteEvents, not directly under Remotes)
local function getMoneySpawnRE(): RemoteEvent
	local net = getNetRoot()
	local remotes = net:WaitForChild("Remotes")
	local events = remotes:WaitForChild("RemoteEvents")
	return events:WaitForChild("MoneySpawn") :: RemoteEvent
end

local function getMoneyCollectRF(): RemoteFunction
	-- Prefer RemoteService wrapper (consistent with your project)
	local rs = getRemoteService()
	return rs:GetFunction("MoneyCollect")
end

local function getMoneyTemplate(): Model
	return ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Money"):WaitForChild("MoneyStack") :: Model
end

local function vec3FromArray(t: any): Vector3?
	if type(t) ~= "table" then return nil end
	local x, y, z = tonumber(t[1]), tonumber(t[2]), tonumber(t[3])
	if not x or not y or not z then return nil end
	return Vector3.new(x, y, z)
end

local DEBUG = true
local function dprint(...)
	if DEBUG then
		print("[MoneyClient]", ...)
	end
end
local function dwarn(...)
	if DEBUG then
		warn("[MoneyClient]", ...)
	end
end

type LiveDrop = {
	id: string,
	value: number,
	model: Model,
	claimed: boolean,
}

local MoneyClient = {}
MoneyClient.__index = MoneyClient

function MoneyClient.new()
	local self = setmetatable({}, MoneyClient)

	self.Template = getMoneyTemplate()
	self.MoneySpawnRE = getMoneySpawnRE()
	self.MoneyCollectRF = getMoneyCollectRF()
	self.Live = {} :: { [string]: LiveDrop }

	-- Helpful startup info to prove we are bound to the correct RemoteEvent
	dprint("Bound MoneySpawnRE:", self.MoneySpawnRE:GetFullName())
	dprint("Bound MoneyCollectRF:", self.MoneyCollectRF:GetFullName())

	return self
end

function MoneyClient:_destroyDrop(dropId: string)
	local rec = self.Live[dropId]
	if not rec then return end
	self.Live[dropId] = nil
	if rec.model and rec.model.Parent then
		rec.model:Destroy()
	end
end

function MoneyClient:_claim(dropId: string)
	local rec = self.Live[dropId]
	if not rec or rec.claimed then return end
	rec.claimed = true

	local ok, result = pcall(function()
		-- NetService wrapper allows payload to be string or table
		return self.MoneyCollectRF:InvokeServer(dropId)
	end)

	if not ok then
		dwarn("MoneyCollect InvokeServer failed:", dropId, result)
		rec.claimed = false
		return
	end

	-- result expected { ok=true/false, amount=?, reason=? }
	if type(result) == "table" and result.ok then
		dprint("Collected OK:", dropId, "amount=", result.amount)
		self:_destroyDrop(dropId)
	else
		local reason = (type(result) == "table" and result.reason) or "Unknown"
		dprint("Collect denied:", dropId, "reason=", reason)
		-- allow retry
		rec.claimed = false
	end
end

function MoneyClient:_ensurePrompt(rootPart: BasePart, dropId: string)
	-- If template already has a prompt, don't duplicate
	local existing = rootPart:FindFirstChildOfClass("ProximityPrompt")
	if existing then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.ActionText = "Collect"
	prompt.ObjectText = "Cash"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = rootPart

	prompt.Triggered:Connect(function(player: Player)
		if player == LOCAL_PLAYER then
			self:_claim(dropId)
		end
	end)
end

function MoneyClient:_bindTouch(rootPart: BasePart, dropId: string)
	rootPart.Touched:Connect(function(hit)
		local char = LOCAL_PLAYER.Character
		if not char then return end
		if hit and hit:IsDescendantOf(char) then
			self:_claim(dropId)
		end
	end)
end

function MoneyClient:_spawnOne(entry: any)
	-- entry: { id=string, value=number, pos={x,y,z} }
	if type(entry) ~= "table" then return end
	local dropId = tostring(entry.id or "")
	if dropId == "" then return end
	if self.Live[dropId] then return end

	local value = tonumber(entry.value) or 0
	local pos = vec3FromArray(entry.pos)
	if not pos then
		dwarn("Bad drop pos for", dropId, entry.pos)
		return
	end

	local model = self.Template:Clone()
	model.Name = "MoneyDrop_" .. dropId
	model.Parent = workspace.MoneyDrops

	-- place it
	local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not (pp and pp:IsA("BasePart")) then
		dwarn("MoneyStack template missing BasePart/PrimaryPart; cannot place.")
		model:Destroy()
		return
	end

	-- Ensure physics doesn't fling it
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
		end
	end

	model:PivotTo(CFrame.new(pos))

	self.Live[dropId] = {
		id = dropId,
		value = value,
		model = model,
		claimed = false,
	}

	-- Pickup mechanisms
	--self:_ensurePrompt(pp, dropId)
	self:_bindTouch(pp, dropId)

	-- Auto-cleanup on client after ~50s (server expires at 45)
	task.delay(50, function()
		if self.Live[dropId] then
			self:_destroyDrop(dropId)
		end
	end)

	dprint("Spawned visual:", dropId, "value=", value, "pos=", tostring(pos))
end

function MoneyClient:Start()
	self.MoneySpawnRE.OnClientEvent:Connect(function(payload)
		-- payload is array of drops
		if type(payload) ~= "table" then
			dwarn("MoneySpawn payload not table:", typeof(payload))
			return
		end

		dprint("MoneySpawn received:", #payload)
		for _, entry in ipairs(payload) do
			self:_spawnOne(entry)
		end
	end)

	dprint("Started. Listening for MoneySpawn.")
end

-- IMPORTANT FIX:
-- This file should be a LocalScript. ModuleScripts won't run unless required.
-- Start immediately.
local controller = MoneyClient.new()
controller:Start()