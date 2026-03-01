local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StateController = {}
StateController.__index = StateController

local function getRemotes()
	local net = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")
	return require(net:WaitForChild("RemoteService"))
end

local function getNetIds()
	local net = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")
	return require(net:WaitForChild("NetIds"))
end

local function makeSignal()
	local be = Instance.new("BindableEvent")
	return {
		Fire = function(_, ...)
			be:Fire(...)
		end,
		Connect = function(_, fn)
			return be.Event:Connect(fn)
		end,
		Destroy = function()
			be:Destroy()
		end,
	}
end

function StateController.new()
	local self = setmetatable({}, StateController)
	self.Remotes = getRemotes()
	self.NetIds = getNetIds()
	self.State = {}
	self.Changed = makeSignal()
	self._reStateDelta = self.Remotes:GetEvent("StateDelta")
	self._rfSnapshot = self.Remotes:GetFunction("GetStateSnapshot")
	return self
end

function StateController:Init(controllers)
	self.Controllers = controllers
end

local function applySnapshot(dst, snap)
	for k, v in pairs(snap) do
		dst[k] = v
	end
end

function StateController:ApplyDelta(deltaList)
	for _, d in ipairs(deltaList) do
		local key = self.NetIds.Decode[d.k]
		if key == "Cash" then
			self.State.Currency = self.State.Currency or {}
			self.State.Currency.Cash = d.v
		elseif key == "XP" then
			self.State.Progression = self.State.Progression or {}
			self.State.Progression.XP = d.v
		elseif key == "Level" then
			self.State.Progression = self.State.Progression or {}
			self.State.Progression.Level = d.v
		elseif key == "StageUnlocked" then
			self.State.Progression = self.State.Progression or {}
			self.State.Progression.StageUnlocked = d.v
		elseif key == "Rebirths" then
			self.State.Progression = self.State.Progression or {}
			self.State.Progression.Rebirths = d.v
		elseif key == "WeaponsOwned" then
			self.State.Inventory = self.State.Inventory or {}
			self.State.Inventory.WeaponsOwned = d.v
		elseif key == "EquippedWeapon" then
			self.State.Inventory = self.State.Inventory or {}
			self.State.Inventory.EquippedWeapon = d.v
		elseif key == "SelectedWeapons" then
			self.State.Inventory = self.State.Inventory or {}
			self.State.Inventory.SelectedWeapons = d.v
		elseif key == "BrainrotsKilled" then
			self.State.Index = self.State.Index or {}
			self.State.Index.BrainrotsKilled = d.v
		elseif key == "BrainrotsDiscovered" then
			self.State.Index = self.State.Index or {}
			self.State.Index.BrainrotsDiscovered = d.v
		elseif key == "DailyLastClaim" then
			self.State.Rewards = self.State.Rewards or {}
			self.State.Rewards.DailyLastClaim = d.v
		elseif key == "DailyStreak" then
			self.State.Rewards = self.State.Rewards or {}
			self.State.Rewards.DailyStreak = d.v
		elseif key == "GiftCooldowns" then
			self.State.Rewards = self.State.Rewards or {}
			self.State.Rewards.GiftCooldowns = d.v
		elseif key == "GiftInventory" then
			self.State.Rewards = self.State.Rewards or {}
			self.State.Rewards.GiftInventory = d.v
		elseif key == "MusicOn" then
			self.State.Settings = self.State.Settings or {}
			self.State.Settings.MusicOn = d.v
		elseif key == "SFXOn" then
			self.State.Settings = self.State.Settings or {}
			self.State.Settings.SFXOn = d.v
		elseif key == "TotalKills" then
			self.State.Stats = self.State.Stats or {}
			self.State.Stats.TotalKills = d.v
		elseif key == "TotalCashEarned" then
			self.State.Stats = self.State.Stats or {}
			self.State.Stats.TotalCashEarned = d.v
		elseif key == "Deaths" then
			self.State.Stats = self.State.Stats or {}
			self.State.Stats.Deaths = d.v
		elseif key == "Armor" then
			self.State.Defense = self.State.Defense or {}
			self.State.Defense.Armor = d.v
		elseif key == "ArmorStep" then
			self.State.Defense = self.State.Defense or {}
			self.State.Defense.ArmorStep = d.v
		elseif key == "SpeedBoost" then
			self.State.Progression = self.State.Progression or {}
			self.State.Progression.SpeedBoost = d.v
		elseif key == "SpeedStep" then
			self.State.Progression = self.State.Progression or {}
			self.State.Progression.SpeedStep = d.v
		end
	end
	self.Changed:Fire(self.State, deltaList)
end

function StateController:RequestSnapshot()
	local ok, snap = pcall(function()
		return self._rfSnapshot:InvokeServer()
	end)
	if ok and type(snap) == "table" then
		applySnapshot(self.State, snap)
		self.Changed:Fire(self.State, { { k = -1, v = "snapshot" } })
	end
end

function StateController:Start()
	self._reStateDelta.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.t == "s" and type(payload.s) == "table" then
			applySnapshot(self.State, payload.s)
			self.Changed:Fire(self.State, { { k = -1, v = "snapshot" } })
		elseif payload.t == "d" and type(payload.d) == "table" then
			self:ApplyDelta(payload.d)
		end
	end)

	self:RequestSnapshot()
end

function StateController:GetState()
	return self.State
end

return StateController.new()