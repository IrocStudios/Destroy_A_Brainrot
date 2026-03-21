--!strict
-- MovementRegistry
-- Loads locomotion modules, resolves brainrot → locomotion type.
-- Each locomotion module implements: Init, MoveTo, Stop, IsFlying, Cleanup.

local ServerStorage = game:GetService("ServerStorage")

local MovementRegistry = {}

local _modules: { [string]: any } = {}
local _loaded = false

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[MovementRegistry]", ...) end
end

function MovementRegistry:Init()
	if _loaded then return end
	_loaded = true

	local movementFolder = ServerStorage:FindFirstChild("Services")
		and ServerStorage.Services:FindFirstChild("Movement")
	if not movementFolder then
		warn("[MovementRegistry] Movement folder not found under Services")
		return
	end

	-- Load Ground locomotion modules
	local ground = movementFolder:FindFirstChild("Ground")
	if ground then
		for _, mod in ipairs(ground:GetChildren()) do
			if mod:IsA("ModuleScript") then
				local ok, result = pcall(require, mod)
				if ok and type(result) == "table" and result.Name then
					_modules[result.Name] = result
					dprint("Loaded ground locomotion:", result.Name)
				else
					warn("[MovementRegistry] Failed to load:", mod.Name, result)
				end
			end
		end
	end

	-- Load Air locomotion modules
	local air = movementFolder:FindFirstChild("Air")
	if air then
		for _, mod in ipairs(air:GetChildren()) do
			if mod:IsA("ModuleScript") then
				local ok, result = pcall(require, mod)
				if ok and type(result) == "table" and result.Name then
					_modules[result.Name] = result
					dprint("Loaded air locomotion:", result.Name)
				else
					warn("[MovementRegistry] Failed to load:", mod.Name, result)
				end
			end
		end
	end

	dprint("Init complete.", "Loaded:", #self:GetAllNames(), "modules")
end

--- Get a locomotion module by name. Falls back to "Walk" if not found.
function MovementRegistry:Get(name: string?): any
	local key = name or "Walk"
	local mod = _modules[key]
	if mod then return mod end

	-- Fallback to Walk
	if key ~= "Walk" then
		mod = _modules["Walk"]
		if mod then return mod end
	end

	return nil
end

--- Get all loaded module names.
function MovementRegistry:GetAllNames(): { string }
	local names = {}
	for k in pairs(_modules) do
		table.insert(names, k)
	end
	return names
end

return MovementRegistry
