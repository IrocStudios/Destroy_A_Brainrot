local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteService = {}

local function getNetRoot()
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local net = shared:WaitForChild("Net")
	return net:WaitForChild("Remotes")
end

function RemoteService:GetEvent(name)
	local remotes = getNetRoot()
	local events = remotes:WaitForChild("RemoteEvents")
	return events:WaitForChild(name)
end

function RemoteService:GetFunction(name)
	local remotes = getNetRoot()
	local funcs = remotes:WaitForChild("RemoteFunctions")
	return funcs:WaitForChild(name)
end

return RemoteService
