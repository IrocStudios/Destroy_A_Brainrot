local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewardController = {}
DailyRewardController.__index = DailyRewardController

function DailyRewardController:Init()
	self.Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("RemoteService"))
	self.RF = self.Remotes:GetFunction("RewardAction")
end

function DailyRewardController:Start() end

function DailyRewardController:ClaimDaily()
	return self.RF:InvokeServer({ action = "ClaimDaily" })
end

return setmetatable({}, DailyRewardController)