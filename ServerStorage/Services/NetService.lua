local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetService = {}
NetService.__index = NetService

local function deepCopy(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end
	local out = {}
	for k, v in pairs(tbl) do
		out[k] = deepCopy(v)
	end
	return out
end

local function getNetRoot()
	local shared = ReplicatedStorage:WaitForChild("Shared")
	return shared:WaitForChild("Net")
end

local function ensureFolder(name, parent)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function ensureRemote(className, name, parent)
	local r = parent:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = parent
	end
	return r
end

-- Creates all Remote folders and instances so clients can WaitForChild on them.
-- Must run before any service calls RemoteService:GetEvent/GetFunction.
function NetService:_buildRemotes(netFolder, netIds)
	local remotesFolder = ensureFolder("Remotes", netFolder)
	local eventsFolder  = ensureFolder("RemoteEvents", remotesFolder)
	local funcsFolder   = ensureFolder("RemoteFunctions", remotesFolder)

	for name in pairs(netIds.RemoteEvents) do
		ensureRemote("RemoteEvent", name, eventsFolder)
	end
	for name in pairs(netIds.RemoteFunctions) do
		ensureRemote("RemoteFunction", name, funcsFolder)
	end
end

function NetService:Init(services)
	self.Services = services

	local netFolder = getNetRoot()
	self.NetIds = require(netFolder:WaitForChild("NetIds"))

	-- Create all Remotes first so clients and services can find them immediately.
	self:_buildRemotes(netFolder, self.NetIds)

	self.RemoteService = require(netFolder:WaitForChild("RemoteService"))

	self._reStateDelta      = self.RemoteService:GetEvent("StateDelta")
	self._reNotify          = self.RemoteService:GetEvent("Notify")
	self._rePrompt          = self.RemoteService:GetEvent("Prompt")
	self._reWeaponFX        = self.RemoteService:GetEvent("WeaponFX")
	self._reAnimationSignal = self.RemoteService:GetEvent("AnimationSignal")
	self._reMoneySpawn      = self.RemoteService:GetEvent("MoneySpawn")

	self._rfGetSnapshot      = self.RemoteService:GetFunction("GetStateSnapshot")
	self._rfShop             = self.RemoteService:GetFunction("ShopAction")
	self._rfGate             = self.RemoteService:GetFunction("GateAction")
	self._rfReward           = self.RemoteService:GetFunction("RewardAction")
	self._rfRebirth          = self.RemoteService:GetFunction("RebirthAction")
	self._rfWeapon           = self.RemoteService:GetFunction("WeaponAction")
	self._rfMoneyCollect     = self.RemoteService:GetFunction("MoneyCollect")
	self._rfDamageBrainrot   = self.RemoteService:GetFunction("DamageBrainrot")
	self._rfDiscoveryReport  = self.RemoteService:GetFunction("DiscoveryReport")

	self._rfCodes    = self.RemoteService:GetFunction("CodesAction")
	self._rfSettings = self.RemoteService:GetFunction("SettingsAction")
	self._rfCommand  = self.RemoteService:GetFunction("CommandAction")
	self._rfDeath    = self.RemoteService:GetFunction("DeathAction")

	self._pending = {}
end

function NetService:Start()
	self._rfGetSnapshot.OnServerInvoke = function(player)
		return self:BuildAndSendSnapshot(player)
	end

	self._rfShop.OnServerInvoke = function(player, payload)
		return self:RouteAction("ShopService", "HandleShopAction", player, payload)
	end

	self._rfGate.OnServerInvoke = function(player, payload)
		return self:RouteAction("GateService", "HandleGateAction", player, payload)
	end

	self._rfReward.OnServerInvoke = function(player, payload)
		return self:RouteAction("RewardService", "HandleRewardAction", player, payload)
	end

	self._rfRebirth.OnServerInvoke = function(player, payload)
		return self:RouteAction("ProgressionService", "HandleRebirthAction", player, payload)
	end

	self._rfWeapon.OnServerInvoke = function(player, payload)
		return self:RouteAction("InventoryService", "HandleWeaponAction", player, payload)
	end

	self._rfMoneyCollect.OnServerInvoke = function(player, payload)
		return self:RouteAction("MoneyService", "HandleMoneyCollect", player, payload)
	end

	self._rfDamageBrainrot.OnServerInvoke = function(player, brainrotGuid, damageAmount)
		return self:RouteAction("CombatService", "HandleDamageBrainrot", player, brainrotGuid, damageAmount)
	end

	self._rfDiscoveryReport.OnServerInvoke = function(player, brainrotId)
		return self:RouteAction("IndexService", "HandleDiscoveryReport", player, brainrotId)
	end

	self._rfCodes.OnServerInvoke = function(player, payload)
		return self:RouteAction("CodesService", "HandleCodesAction", player, payload)
	end

	self._rfSettings.OnServerInvoke = function(player, payload)
		return self:RouteAction("DataService", "HandleSettingsAction", player, payload)
	end

	self._rfCommand.OnServerInvoke = function(player, payload)
		return self:RouteAction("AdminService", "HandleCommand", player, payload)
	end

	self._rfDeath.OnServerInvoke = function(player, payload)
		return self:RouteAction("DeathService", "HandleDeathAction", player, payload)
	end

	local DataService = self.Services.DataService
	if DataService and DataService.OnProfileLoaded and type(DataService.OnProfileLoaded.Connect) == "function" then
		DataService.OnProfileLoaded:Connect(function(player)
			self:BuildAndSendSnapshot(player)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		self._pending[player] = nil
	end)
end

function NetService:RouteAction(serviceName, methodName, player, ...)
	local svc = self.Services[serviceName]
	if not svc then
		return false, ("Missing service %s"):format(serviceName)
	end

	local args = table.pack(...)

	local fn = svc[methodName]
	if type(fn) ~= "function" then
		if type(svc.HandleAction) == "function" then
			return svc:HandleAction(player, methodName, table.unpack(args, 1, args.n))
		end
		return false, ("Missing handler %s on %s"):format(methodName, serviceName)
	end

	local ok, r1, r2, r3, r4 = pcall(function()
		return fn(svc, player, table.unpack(args, 1, args.n))
	end)

	if not ok then
		warn(("Net route error %s.%s: %s"):format(serviceName, methodName, tostring(r1)))
		return false, "ServerError"
	end

	return r1, r2, r3, r4
end

function NetService:BuildSnapshotFromProfile(profile)
	if type(profile) ~= "table" then
		return nil
	end

	return {
		Currency = deepCopy(profile.Currency or {}),
		Inventory = deepCopy(profile.Inventory or {}),
		Progression = deepCopy(profile.Progression or {}),
		Index = deepCopy(profile.Index or {}),
		Rewards = deepCopy(profile.Rewards or {}),
		Settings = deepCopy(profile.Settings or {}),
		Stats = deepCopy(profile.Stats or {}),
	}
end

function NetService:BuildAndSendSnapshot(player)
	local DataService = self.Services.DataService
	if not DataService or type(DataService.GetProfile) ~= "function" then
		return nil
	end

	local profile = DataService:GetProfile(player)
	local snap = self:BuildSnapshotFromProfile(profile)

	if snap then
		self._reStateDelta:FireClient(player, {
			t = "s",
			s = snap,
			ts = os.time(),
		})
	end

	return snap
end

function NetService:QueueDelta(player, keyOrId, value)
	if not player then
		return
	end

	local id = keyOrId
	if type(keyOrId) == "string" and self.NetIds and self.NetIds.Encode then
		id = self.NetIds.Encode[keyOrId]
	end

	if type(id) ~= "number" then
		return
	end

	self._pending[player] = self._pending[player] or {}
	table.insert(self._pending[player], { k = id, v = value })
end

function NetService:FlushDelta(player)
	local list = self._pending[player]
	if not list or #list == 0 then
		return
	end

	self._pending[player] = {}
	self._reStateDelta:FireClient(player, {
		t = "d",
		d = list,
		ts = os.time(),
	})
end

function NetService:PushDelta(player, deltas)
	if not player or type(deltas) ~= "table" then
		return
	end

	self._reStateDelta:FireClient(player, {
		t = "d",
		d = deltas,
		ts = os.time(),
	})
end

function NetService:Notify(player, payload)
	self._reNotify:FireClient(player, payload)
end

function NetService:NotifyAll(payload)
	self._reNotify:FireAllClients(payload)
end

function NetService:Prompt(player, payload)
	self._rePrompt:FireClient(player, payload)
end

function NetService:SignalAnimation(player, payload)
	self._reAnimationSignal:FireClient(player, payload)
end

function NetService:SignalAnimationAll(payload)
	self._reAnimationSignal:FireAllClients(payload)
end

return NetService