--!strict
-- ToolbarController (LocalScript in StarterPlayerScripts)
-- Hides the default Roblox backpack UI and manages a custom toolbar.
-- Clones a Template button for each Tool in the player's Backpack,
-- handles equip/unequip on click, and syncs the Selected highlight.

local Players           = game:GetService("Players")
local StarterGui        = game:GetService("StarterGui")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local UserInputService  = game:GetService("UserInputService")

local LOCAL_PLAYER = Players.LocalPlayer

-- ── Disable default backpack ────────────────────────────────────────────────
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

-- ── UI references ───────────────────────────────────────────────────────────
local playerGui   = LOCAL_PLAYER:WaitForChild("PlayerGui")
local gui         = playerGui:WaitForChild("GUI")
local toolsFrame  = gui:WaitForChild("Tools")   :: Frame
local resources   = toolsFrame:WaitForChild("resources") :: Folder
local template    = resources:WaitForChild("Template") :: TextButton

template.Visible = false -- ensure template stays hidden

-- ── State ───────────────────────────────────────────────────────────────────
local backpack: Backpack = LOCAL_PLAYER:WaitForChild("Backpack") :: Backpack
local buttonMap: { [Tool]: TextButton } = {} -- Tool → cloned button
local selectedTool: Tool? = nil
local dead = false -- true while player is dead; blocks all tool interaction
local backpackConns: { RBXScriptConnection } = {} -- current backpack listeners
local _layoutCounter = 0 -- increments per button so newest tools appear last

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function getCharacter(): Model?
	return LOCAL_PLAYER.Character
end

local function isToolEquipped(tool: Tool): boolean
	local char = getCharacter()
	return char ~= nil and tool.Parent == char
end

local function updateSelected(button: TextButton, selected: boolean)
	local sel = button:FindFirstChild("Selected")
	if sel and sel:IsA("GuiObject") then
		sel.Visible = selected
	end
end

local function updateAllSelections()
	for tool, button in buttonMap do
		updateSelected(button, isToolEquipped(tool))
	end
end

-- ── Slot numbering ────────────────────────────────────────────────────────
local function renumberSlots()
	-- Gather visible tool buttons in layout order
	local buttons: { TextButton } = {}
	for _, child in toolsFrame:GetChildren() do
		if child:IsA("TextButton") and child.Visible and child ~= template then
			table.insert(buttons, child)
		end
	end
	table.sort(buttons, function(a, b)
		if a.LayoutOrder == b.LayoutOrder then
			return a.Name < b.Name
		end
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i, btn in buttons do
		local counter = btn:FindFirstChild("Counter")
		if counter and counter:IsA("TextLabel") then
			counter.Visible = true
			counter.Text = tostring(i)
		end
	end
end

-- ── Equip / Unequip ────────────────────────────────────────────────────────
local function equipTool(tool: Tool)
	local humanoid = getCharacter() and (getCharacter() :: Model):FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(tool)
	end
	selectedTool = tool
	updateAllSelections()
end

local function unequipTool()
	local humanoid = getCharacter() and (getCharacter() :: Model):FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
	selectedTool = nil
	updateAllSelections()
end

local function toggleTool(tool: Tool)
	if dead then return end
	if isToolEquipped(tool) then
		unequipTool()
	else
		equipTool(tool)
	end
end

-- ── Clear all buttons (used on death/respawn) ─────────────────────────────
local function clearAllButtons()
	for tool, button in buttonMap do
		button:Destroy()
	end
	buttonMap = {}
	selectedTool = nil
	_layoutCounter = 0
end

-- ── Button creation / removal ──────────────────────────────────────────────
local function createButton(tool: Tool)
	if buttonMap[tool] then return end

	local button = template:Clone()
	button.Name = tool.Name
	button.Visible = true

	-- Set icon from Tool.TextureId
	local icon = button:FindFirstChild("Icon")
	if icon and icon:IsA("ImageLabel") then
		icon.Image = tool.TextureId
	end

	-- Store reference in ObjectValue
	local toolValue = button:FindFirstChild("Tool")
	if toolValue and toolValue:IsA("ObjectValue") then
		toolValue.Value = tool
	end

	-- Start with Selected hidden
	updateSelected(button, false)

	-- Click handler
	button.MouseButton1Click:Connect(function()
		toggleTool(tool)
	end)

	_layoutCounter += 1
	button.LayoutOrder = _layoutCounter
	button.Parent = toolsFrame
	buttonMap[tool] = button
	renumberSlots()
end

local function removeButton(tool: Tool)
	local button = buttonMap[tool]
	if button then
		button:Destroy()
		buttonMap[tool] = nil
	end
	if selectedTool == tool then
		selectedTool = nil
	end
	renumberSlots()
end

-- ── Button click animation (mirrors ButtonFX press/release) ────────────────
local function playClickAnim(button: TextButton)
	local uiScale = button:FindFirstChildOfClass("UIScale")
	if not uiScale then return end

	-- Press: scale down + pop sound
	TweenService:Create(uiScale, TweenInfo.new(0.05, Enum.EasingStyle.Linear), { Scale = 0.95 }):Play()
	pcall(function() SoundService.cartoon_pop:Play() end)

	-- Release after brief hold: scale back up + pop2 sound
	task.delay(0.05, function()
		TweenService:Create(uiScale, TweenInfo.new(0.05, Enum.EasingStyle.Linear), { Scale = 1 }):Play()
		pcall(function() SoundService.cartoon_pop2:Play() end)
	end)
end

-- ── Keyboard hotbar (keys 1-9) ─────────────────────────────────────────────
local HOTBAR_KEYS = {
	[Enum.KeyCode.One]   = 1,
	[Enum.KeyCode.Two]   = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four]  = 4,
	[Enum.KeyCode.Five]  = 5,
	[Enum.KeyCode.Six]   = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine]  = 9,
}

local function getToolAtSlot(slot: number): Tool?
	-- UIListLayout orders children by LayoutOrder then Name
	-- Gather only visible tool buttons (not template, not resources)
	local buttons: { TextButton } = {}
	for _, child in toolsFrame:GetChildren() do
		if child:IsA("TextButton") and child.Visible and child ~= template then
			table.insert(buttons, child)
		end
	end
	-- Sort by LayoutOrder then Name to match UIListLayout
	table.sort(buttons, function(a, b)
		if a.LayoutOrder == b.LayoutOrder then
			return a.Name < b.Name
		end
		return a.LayoutOrder < b.LayoutOrder
	end)
	local btn = buttons[slot]
	if not btn then return nil end
	local toolVal = btn:FindFirstChild("Tool")
	if toolVal and toolVal:IsA("ObjectValue") and toolVal.Value and toolVal.Value:IsA("Tool") then
		return toolVal.Value :: Tool
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	local slot = HOTBAR_KEYS[input.KeyCode]
	if not slot then return end
	local tool = getToolAtSlot(slot)
	if tool then
		local button = buttonMap[tool]
		if button then
			playClickAnim(button)
		end
		toggleTool(tool)
	end
end)

-- ── Backpack listeners ─────────────────────────────────────────────────────
local function onChildAdded(child: Instance)
	if child:IsA("Tool") then
		createButton(child)
	end
end

local function onChildRemoved(child: Instance)
	if child:IsA("Tool") then
		-- Only remove button if tool went somewhere other than character (dropped/deleted)
		-- If equipped to character, keep the button alive
		task.defer(function()
			if not child.Parent or (child.Parent ~= getCharacter() and child.Parent ~= backpack) then
				removeButton(child)
			else
				updateAllSelections()
			end
		end)
	end
end

-- Roblox creates a new Backpack instance on every respawn.
-- This function disconnects old listeners and rebinds to the current one.
local function bindBackpack()
	-- Disconnect previous backpack listeners
	for _, conn in backpackConns do
		conn:Disconnect()
	end
	backpackConns = {}

	-- Get the (possibly new) Backpack
	backpack = LOCAL_PLAYER:WaitForChild("Backpack") :: Backpack

	table.insert(backpackConns, backpack.ChildAdded:Connect(onChildAdded))
	table.insert(backpackConns, backpack.ChildRemoved:Connect(onChildRemoved))

	-- Scan existing tools in the new backpack
	for _, child in backpack:GetChildren() do
		if child:IsA("Tool") then
			createButton(child)
		end
	end
end

-- Also track character tool changes (equip/unequip fires ChildAdded/Removed on character)
local function bindCharacter(character: Model)
	-- On death: lock toolbar, unequip, deselect all
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			dead = true
			selectedTool = nil
			-- Force-deselect all buttons visually
			for _, button in buttonMap do
				updateSelected(button, false)
			end
		end)
	end

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			updateAllSelections()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			-- Tool returned to backpack or was removed
			task.defer(function()
				if not child.Parent or child.Parent == backpack then
					updateAllSelections()
				else
					removeButton(child)
				end
			end)
		end
	end)
end

-- Bind current character
if LOCAL_PLAYER.Character then
	bindCharacter(LOCAL_PLAYER.Character)
end
LOCAL_PLAYER.CharacterAdded:Connect(function(character)
	-- Respawn: clear old buttons, unlock toolbar, rebind to new backpack
	clearAllButtons()
	dead = false
	bindCharacter(character)
	bindBackpack()
end)

-- ── Initial bind ────────────────────────────────────────────────────────────
bindBackpack()

print("[ToolbarController] Custom toolbar ready")
