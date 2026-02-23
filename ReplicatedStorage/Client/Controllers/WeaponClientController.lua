local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponClientController = {}
WeaponClientController.__index = WeaponClientController

function WeaponClientController:Init()
	self.Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("RemoteService"))
	self.RF = self.Remotes:GetFunction("WeaponAction")
end

function WeaponClientController:Start() end

function WeaponClientController:Equip(weaponName)
	return self.RF:InvokeServer({ action = "Equip", weaponName = weaponName })
end

return setmetatable({}, WeaponClientController)