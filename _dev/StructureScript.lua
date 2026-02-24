--[[
	StructureScript.lua
	Paste into Studio Command Bar and run to print the full instance hierarchy.
	Output is printed to the Output window — copy/paste it into _dev/structure_dump.txt
	then tell Claude "I updated the structure file" in a new chat.

	USAGE:
	  1. Open Studio → View → Output  (so you can see the result)
	  2. Open Studio → View → Command Bar
	  3. Paste this entire script and press Enter
	  4. Copy the Output → save as _dev/structure_dump.txt in your project folder
--]]

local MAX_DEPTH = 6  -- how deep to traverse (increase for more detail)

-- Which services/instances to scan. Comment out ones you don't need.
local ROOTS = {
	game:GetService("StarterGui"),
	game:GetService("ReplicatedStorage"),
	game:GetService("ServerStorage"),
	game:GetService("ServerScriptService"),
	game:GetService("StarterPlayer"),
	game:GetService("Workspace"),
}

-- Classes to skip children of (to avoid spamming with mesh data etc.)
local SKIP_CHILDREN = {
	MeshPart       = true,
	SpecialMesh    = true,
	UnionOperation = true,
	Decal          = true,
	Texture        = true,
	Sound          = true,
}

local output = {}

local function push(line)
	table.insert(output, line)
end

local function printTree(inst, depth)
	if depth > MAX_DEPTH then return end

	local indent = string.rep("  ", depth)
	local className = inst.ClassName
	local name = inst.Name

	-- Build attribute string
	local attrParts = {}
	local ok, attrs = pcall(function() return inst:GetAttributes() end)
	if ok and attrs then
		for k, v in pairs(attrs) do
			table.insert(attrParts, k .. "=" .. tostring(v))
		end
	end
	local attrStr = #attrParts > 0 and ("  {" .. table.concat(attrParts, ", ") .. "}") or ""

	push(indent .. name .. " [" .. className .. "]" .. attrStr)

	if SKIP_CHILDREN[className] then return end

	local children = inst:GetChildren()
	table.sort(children, function(a, b) return a.Name < b.Name end)
	for _, child in ipairs(children) do
		printTree(child, depth + 1)
	end
end

-- Run
push("=" .. string.rep("=", 60))
push("  GAME STRUCTURE DUMP")
push("  " .. os.date("%Y-%m-%d %H:%M:%S"))
push("=" .. string.rep("=", 60))

for _, root in ipairs(ROOTS) do
	push("")
	push(">>> " .. root.Name .. " <<<")
	local children = root:GetChildren()
	table.sort(children, function(a, b) return a.Name < b.Name end)
	for _, child in ipairs(children) do
		printTree(child, 1)
	end
end

push("")
push("=" .. string.rep("=", 60))
push("  END OF DUMP")
push("=" .. string.rep("=", 60))

-- Print all at once
print(table.concat(output, "\n"))
