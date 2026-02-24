local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientLoader = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("ClientLoader"))
local loader = ClientLoader.new()
loader:LoadAll()