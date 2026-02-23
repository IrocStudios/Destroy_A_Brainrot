local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GiftController = {}
GiftController.__index = GiftController

function GiftController:Init()
	self.Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("RemoteService"))
	self.RF = self.Remotes:GetFunction("RewardAction")
end

function GiftController:Start() end

function GiftController:ClaimGift()
	return self.RF:InvokeServer({ action = "ClaimGift" })
end

return setmetatable({}, GiftController)