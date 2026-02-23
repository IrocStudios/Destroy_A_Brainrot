-- ReplicatedStorage/Shared/Net/NetClient
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetIds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("NetIds"))

local NetClient = {}
NetClient.__index = NetClient

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k,v in pairs(t) do out[k] = deepCopy(v) end
	return out
end

local function ensurePath(root, path, create)
	local cur = root
	for i = 1, #path do
		local key = path[i]
		if cur[key] == nil then
			if create then
				cur[key] = {}
			else
				return nil
			end
		end
		cur = cur[key]
		if type(cur) ~= "table" and i < #path then
			if create then
				cur = {}
				-- overwrite the non-table with a table
				local parent = root
				for j = 1, i-1 do parent = parent[path[j]] end
				parent[key] = cur
			else
				return nil
			end
		end
	end
	return cur
end

local function applyOp(state, op)
	local opType = op.op
	local path = op.path or {}

	if opType == "set" then
		if #path == 0 then
			-- replace whole state
			return deepCopy(op.value)
		end
		local parentPath = {}
		for i=1,#path-1 do parentPath[i] = path[i] end
		local parent = ensurePath(state, parentPath, true)
		parent[path[#path]] = op.value

	elseif opType == "inc" then
		local parentPath = {}
		for i=1,#path-1 do parentPath[i] = path[i] end
		local parent = ensurePath(state, parentPath, true)
		local leaf = path[#path]
		local cur = parent[leaf]
		if type(cur) ~= "number" then cur = 0 end
		parent[leaf] = cur + (op.value or 0)

	elseif opType == "insert" then
		local container = ensurePath(state, path, true)
		container[op.key] = op.value

	elseif opType == "remove" then
		local container = ensurePath(state, path, false)
		if container then
			container[op.key] = nil
		end
	end

	return state
end

function NetClient.new()
	local self = setmetatable({}, NetClient)

	self.State = {}
	self.OnSnapshot = Instance.new("BindableEvent")
	self.OnDelta = Instance.new("BindableEvent")

	local sharedNet = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")
	local remotes = sharedNet:WaitForChild("Remotes")
	local events = remotes:WaitForChild("RemoteEvents")
	local functions = remotes:WaitForChild("RemoteFunctions")

	self._events = events
	self._functions = functions

	events:WaitForChild(NetIds.RemoteEvents.StateDelta).OnClientEvent:Connect(function(delta)
		self:ApplyDelta(delta)
	end)

	return self
end

function NetClient:GetState()
	return self.State
end

function NetClient:ApplySnapshot(snapshot)
	self.State = deepCopy(snapshot or {})
	self.OnSnapshot:Fire(self.State)
end

function NetClient:ApplyDelta(delta)
	if type(delta) ~= "table" then return end
	for _,op in ipairs(delta) do
		self.State = applyOp(self.State, op)
	end
	self.OnDelta:Fire(delta, self.State)
end

function NetClient:RequestSnapshot()
	local rf = self._functions:WaitForChild(NetIds.RemoteFunctions.GetStateSnapshot)
	local ok, snapshot = pcall(function()
		return rf:InvokeServer()
	end)
	if ok then
		self:ApplySnapshot(snapshot)
		return true, snapshot
	end
	return false, snapshot
end

function NetClient:Invoke(actionName, payload)
	local rf = self._functions:FindFirstChild(actionName)
	if not rf then
		return false, ("RemoteFunction not found: %s"):format(tostring(actionName))
	end
	local ok, res = pcall(function()
		return rf:InvokeServer(payload)
	end)
	if not ok then
		return false, res
	end
	return true, res
end

function NetClient:OnEvent(eventName, fn)
	local re = self._events:FindFirstChild(eventName)
	if not re then
		warn(("RemoteEvent not found: %s"):format(tostring(eventName)))
		return function() end
	end
	local conn = re.OnClientEvent:Connect(fn)
	return function() conn:Disconnect() end
end

return NetClient