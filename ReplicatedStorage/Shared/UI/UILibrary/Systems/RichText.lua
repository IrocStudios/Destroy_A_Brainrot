--!strict

local RichText = {}

local function isHex(s)
	return typeof(s) == "string" and s:match("^#%x%x%x%x%x%x$")
end

local function escapePattern(s)
	return (s:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])","%%%1"))
end

local function apply(label: TextLabel)
	label.RichText = true
	local text = label.Text
	local attrs = label:GetAttributes()

	local keys = {}
	for name, value in pairs(attrs) do
		if isHex(value) then
			table.insert(keys, name)
		end
	end

	table.sort(keys, function(a, b)
		return #a > #b
	end)

	for _, name in ipairs(keys) do
		local hex = attrs[name]
		local pattern = "%f[%w_]" .. escapePattern(name) .. "%f[^%w_]"
		text = text:gsub(pattern, '<font color="' .. hex .. '">' .. name .. '</font>')
	end

	label.Text = text
end

local function watchLabel(label: TextLabel)
	apply(label)
	label:GetPropertyChangedSignal("Text"):Connect(function()
		apply(label)
	end)
	label.AttributeChanged:Connect(function()
		apply(label)
	end)
end

function RichText:Bind(root)
	for _, obj in ipairs(root:GetDescendants()) do
		if obj:IsA("TextLabel") then
			watchLabel(obj :: TextLabel)
		end
	end

	root.DescendantAdded:Connect(function(obj)
		if obj:IsA("TextLabel") then
			watchLabel(obj :: TextLabel)
		end
	end)
end

return RichText