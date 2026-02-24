local ServerStorage = game:GetService("ServerStorage")

local ServerLoader = require(ServerStorage:WaitForChild("Services"):WaitForChild("ServerLoader"))
local loader = ServerLoader.new()
loader:LoadAll()