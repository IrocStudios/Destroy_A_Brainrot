local ServerStorage = game:GetService("ServerStorage")

local ServerLoader = {}
ServerLoader.__index = ServerLoader

function ServerLoader.new()
	local self = setmetatable({}, ServerLoader)
	self.Services = {}
	self._started = false
	return self
end

local function safeRequire(mod)
	local ok, res = pcall(require, mod)
	if not ok then
		error(("Failed requiring %s: %s"):format(mod:GetFullName(), tostring(res)))
	end
	return res
end

local function safeCall(label, fn)
	local ok, err = pcall(fn)
	if not ok then
		error(("%s failed: %s"):format(label, tostring(err)))
	end
end

function ServerLoader:LoadAll()
	if self._started then
		return self.Services
	end

	local servicesFolder = ServerStorage:WaitForChild("Services")

	local modules = {}
	for _, inst in ipairs(servicesFolder:GetChildren()) do
		if inst:IsA("ModuleScript") and inst.Name ~= "ServerLoader" then
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
		local service = safeRequire(mod)

		if type(service) ~= "table" then
			warn(("Service module %s must return a table; got %s"):format(mod:GetFullName(), typeof(service)))
		else
			local keyName = rawget(service, "Name")
			if type(keyName) ~= "string" or keyName == "" then
				keyName = mod.Name
				rawset(service, "Name", keyName)
			end

			if self.Services[keyName] and self.Services[keyName] ~= service then
				error(("Duplicate service name '%s' from %s. Rename the module or set service.Name uniquely."):format(
					keyName,
					mod:GetFullName()
					))
			end

			self.Services[keyName] = service
		end
	end

	for _, mod in ipairs(modules) do
		local keyName = mod.Name
		local svc = self.Services[keyName] or self.Services[(function()
			local s = safeRequire(mod)
			return type(s) == "table" and s.Name or nil
		end)()]

		if svc and type(svc.Init) == "function" then
			safeCall(("Init %s"):format(keyName), function()
				svc:Init(self.Services)
			end)
		end
	end

	for _, mod in ipairs(modules) do
		local keyName = mod.Name
		local svc = self.Services[keyName]
		if svc and type(svc.Start) == "function" then
			task.spawn(function()
				local ok, err = pcall(function()
					svc:Start()
				end)
				if not ok then
					warn(("Start %s failed: %s"):format(keyName, tostring(err)))
				end
			end)
		end
	end

	self._started = true
	return self.Services
end

function ServerLoader:Get(serviceName)
	return self.Services[serviceName]
end

return ServerLoader