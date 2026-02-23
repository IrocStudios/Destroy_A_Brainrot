local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopController = {}
ShopController.__index = ShopController

function ShopController:Init(controllers)
	self.Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("RemoteService"))
	self.RF = self.Remotes:GetFunction("ShopAction")
end

function ShopController:Start() end

function ShopController:Buy(toolName)
	return self.RF:InvokeServer({ action = "Buy", toolName = toolName })
end

return setmetatable({}, ShopController)
