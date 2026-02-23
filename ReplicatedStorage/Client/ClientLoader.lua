local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientLoader = {}
ClientLoader.__index = ClientLoader

local function safeRequire(mod)
	local ok, res = pcall(require, mod)
	if not ok then
		error(("Failed requiring %s: %s"):format(mod:GetFullName(), tostring(res)))
	end
	return res
end

function ClientLoader.new()
	local self = setmetatable({}, ClientLoader)
	self.Controllers = {}
	return self
end

function ClientLoader:LoadAll()
	local clientFolder = ReplicatedStorage:WaitForChild("Client")
	local controllersFolder = clientFolder:WaitForChild("Controllers")

	local modules = {}
	for _, inst in ipairs(controllersFolder:GetChildren()) do
		if inst:IsA("ModuleScript") then
			table.insert(modules, inst)
		end
	end

	table.sort(modules, function(a, b)
		local ao = a:GetAttribute("Order") or 1000
		local bo = b:GetAttribute("Order") or 1000
		if ao == bo then
			return a.Name < b.Name
		end
		return ao < bo
	end)

	for _, mod in ipairs(modules) do
		local ctrl = safeRequire(mod)
		if type(ctrl) == "table" then
			ctrl.Name = ctrl.Name or mod.Name
			self.Controllers[ctrl.Name] = ctrl
		end
	end

	for _, ctrl in pairs(self.Controllers) do
		if type(ctrl.Init) == "function" then
			ctrl:Init(self.Controllers)
		end
	end

	for _, ctrl in pairs(self.Controllers) do
		if type(ctrl.Start) == "function" then
			task.spawn(function()
				ctrl:Start()
			end)
		end
	end

	return self.Controllers
end

return ClientLoader