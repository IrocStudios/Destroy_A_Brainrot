-- Button Animation Module

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local sservice = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
	Players.PlayerAdded:Wait()
	LocalPlayer = Players.LocalPlayer
end

local function tweenObject(object, properties, time, style, direction)
	local tweenInfo = TweenInfo.new(0.175, style or Enum.EasingStyle.Bounce, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(object, tweenInfo, properties)
	tween:Play()
	return tween
end

local function applyButtonEffects(button)
	if not button:IsA("GuiButton") then return end
	if button:GetAttribute("ButtonAnimation") == false then return end

	-- UIScale dla buttona
	local uiScale = button:FindFirstChild("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "UIScale"
		uiScale.Scale = 1
		uiScale.Parent = button
	end

	local bg = button:FindFirstChild("BG") or button:FindFirstChildWhichIsA("Frame")

	local textLabel, titleLabel
	if button:GetAttribute("textdisplay") then
		if bg then
			textLabel = bg:FindFirstChildWhichIsA("TextLabel")
			titleLabel = textLabel and textLabel:FindFirstChildWhichIsA("TextLabel")
		end
	end

	local defaultScale = 1
	local hoverScale = 1.05
	local clickScale = 0.95

	local isHovering = false

	-- ustawienie poczatkowe dla fade textu
	local function setInitialFade(label)
		if not label then return end
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 1
		end
		label.TextTransparency = 1
	end

	setInitialFade(textLabel)
	setInitialFade(titleLabel)

	local function tweenFade(label, textTarget, strokeTarget)
		if not label then return end
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			tweenObject(stroke, {Transparency = strokeTarget}, 0.1)
		end
		tweenObject(label, {TextTransparency = textTarget}, 0.1)
	end

	button.MouseEnter:Connect(function()
		isHovering = true
		tweenObject(uiScale, {Scale = hoverScale}, 0.05)
		sservice["RBLX UI Hover 01 (SFX)"]:Play()
		tweenFade(textLabel, 0, 0)
		tweenFade(titleLabel, 0, 0)
	end)

	button.MouseLeave:Connect(function()
		isHovering = false
		tweenObject(uiScale, {Scale = defaultScale}, 0.05)
		tweenFade(textLabel, 1, 1)
		tweenFade(titleLabel, 1, 1)
	end)

	button.MouseButton1Down:Connect(function()
		tweenObject(uiScale, {Scale = clickScale}, 0.05)
		sservice.cartoon_pop:Play()
		if bg then
			tweenObject(bg, {Position = UDim2.new(0.5,0,0.5,0)}, 0.1)
		end
	end)

	button.MouseButton1Up:Connect(function()
		local targetScale = isHovering and hoverScale or defaultScale
		tweenObject(uiScale, {Scale = targetScale}, 0.05)
		sservice.cartoon_pop2:Play()
		if bg then
			tweenObject(bg, {Position = isHovering and UDim2.new(0.5,0,0.44,0) or UDim2.new(0.5,0,0.5,0)}, 0.1)
		end
	end)
end



local function applyAllGuiButtons(parent)
	parent = parent or LocalPlayer:WaitForChild("PlayerGui")

	while not parent do
		RunService.Heartbeat:Wait()
		parent = LocalPlayer:FindFirstChild("PlayerGui")
	end

	for _, gui in ipairs(parent:GetDescendants()) do
		if gui:IsA("GuiButton") then
			applyButtonEffects(gui)
		end
	end

	parent.DescendantAdded:Connect(function(desc)
		if desc:IsA("GuiButton") then
			applyButtonEffects(desc)
		end
	end)
end

task.spawn(applyAllGuiButtons)

return true
