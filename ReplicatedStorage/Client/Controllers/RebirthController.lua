local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthController = {}
RebirthController.__index = RebirthController

function RebirthController:Init()
	self.Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("RemoteService"))
	self.RF = self.Remotes:GetFunction("RebirthAction")
end

function RebirthController:Start() end

function RebirthController:Rebirth()
	return self.RF:InvokeServer({ action = "Rebirth" })
end

return setmetatable({}, RebirthController)
