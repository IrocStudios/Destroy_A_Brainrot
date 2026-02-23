--!strict

local Util = {}

function Util.EnsureUIScale(gui: GuiObject)
	local ui = gui:FindFirstChildOfClass("UIScale")
	if not ui then
		ui = Instance.new("UIScale")
		ui.Scale = 1
		ui.Parent = gui
	end
	return ui
end

function Util.IsGuiVisible(inst: Instance?): boolean
	if not inst then return false end
	local cur: Instance? = inst
	while cur do
		if cur:IsA("GuiObject") and cur.Visible == false then
			return false
		end
		cur = cur.Parent
	end
	return true
end

return Util