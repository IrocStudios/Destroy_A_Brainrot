local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function isHex(s)
	return typeof(s) == "string" and s:match("^#%x%x%x%x%x%x$")
end

local function escapePattern(s)
	return (s:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])","%%%1"))
end

-- zamienia wszystkie slowa na kolorowe wersje
local function replaceWithHex(label)
	if not label or not label:IsA("TextLabel") then return end
	label.RichText = true -- wlacz RichText

	local original = label.Text
	local newTxt = original
	local attrs = label:GetAttributes()

	local keys = {}
	for name, value in pairs(attrs) do
		if isHex(value) then
			table.insert(keys, name)
		end
	end
	table.sort(keys, function(a, b) return #a > #b end)

	for _, name in ipairs(keys) do
		local value = attrs[name]
		local safeName = escapePattern(name)

		local pattern = "%f[%w_]" .. safeName .. "%f[^%w_]"
		newTxt = newTxt:gsub(pattern, '<font color="' .. value .. '">' .. name .. '</font>')
	end

	label.Text = newTxt
end

-- podpina eventy pod pojedynczy label
local function watchLabel(label)
	if not label:IsA("TextLabel") then return end
	replaceWithHex(label)

	label:GetPropertyChangedSignal("Text"):Connect(function()
		replaceWithHex(label)
	end)

	label.AttributeChanged:Connect(function()
		replaceWithHex(label)
	end)
end

-- skanuje caly gui
local function scanGui(gui)
	for _, obj in ipairs(gui:GetDescendants()) do
		if obj:IsA("TextLabel") then
			watchLabel(obj)
		end
	end

	gui.DescendantAdded:Connect(function(obj)
		if obj:IsA("TextLabel") then
			watchLabel(obj)
		end
	end)
end

-- AUTO-START
task.spawn(function()
	scanGui(playerGui)
end)

return true
