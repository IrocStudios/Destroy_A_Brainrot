--!strict

local UILibrary = {}

local RESERVED: { [string]: boolean } = {
	Init = true,
	Load = true,
	Reload = true,
	Core = true,
	Systems = true,
}

local function loadFolderInto(target: any, folder: Instance)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local name = child.Name
			if not RESERVED[name] then
				local ok, mod = pcall(require, child)
				if ok then
					target[name] = mod
				else
					warn(("[UILibrary] Failed to require %s/%s: %s"):format(folder.Name, name, tostring(mod)))
				end
			end
		elseif child:IsA("Folder") then
			local sub = {}
			target[child.Name] = sub
			loadFolderInto(sub, child)
		end
	end
end

function UILibrary.Load(self: any)
	table.clear(self)
	loadFolderInto(self, script:WaitForChild("Core"))
	loadFolderInto(self, script:WaitForChild("Systems"))
	return self
end

function UILibrary.Init(self: any, _ctx: any?)
	return self:Load()
end

return UILibrary:Load()