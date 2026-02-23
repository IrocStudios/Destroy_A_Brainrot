local IndexController = {}
IndexController.__index = IndexController

function IndexController:Init(controllers)
	self.State = controllers.StateController
end

function IndexController:Start() end

return setmetatable({}, IndexController)
