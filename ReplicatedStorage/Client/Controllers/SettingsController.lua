local SettingsController = {}
SettingsController.__index = SettingsController

function SettingsController:Init(controllers)
	self.State = controllers.StateController
	-- No settings-specific RemoteFunction exists yet; placeholder for future use.
end

function SettingsController:Start() end

return setmetatable({}, SettingsController)
