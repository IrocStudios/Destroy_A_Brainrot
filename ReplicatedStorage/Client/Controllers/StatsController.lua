local StatsController = {}
StatsController.__index = StatsController

function StatsController:Init(controllers)
	self.State = controllers.StateController
end

function StatsController:Start()
end

return setmetatable({}, StatsController)