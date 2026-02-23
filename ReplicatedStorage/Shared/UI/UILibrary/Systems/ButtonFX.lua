--!strict

local TweenService  = game:GetService("TweenService")
local SoundService  = game:GetService("SoundService")

local ButtonFX = {}

-- ── helpers ──────────────────────────────────────────────────────────────────

local function tweenObj(object: Instance, props: { [string]: any }, time: number, style: Enum.EasingStyle?)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	local t = TweenService:Create(object, info, props)
	t:Play()
	return t
end

local function ensureUIScale(button: Instance): UIScale
	local us = button:FindFirstChildOfClass("UIScale")
	if not us then
		us = Instance.new("UIScale")
		us.Name  = "UIScale"
		;(us :: UIScale).Scale = 1
		us.Parent = button
	end
	return us :: UIScale
end

local function setInitialFade(label: TextLabel?)
	if not label then return end
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then (stroke :: UIStroke).Transparency = 1 end
	label.TextTransparency = 1
end

local function tweenFade(label: TextLabel?, textTarget: number, strokeTarget: number)
	if not label then return end
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		tweenObj(stroke, { Transparency = strokeTarget }, 0.1)
	end
	tweenObj(label, { TextTransparency = textTarget }, 0.1)
end

-- ── core apply ───────────────────────────────────────────────────────────────

function ButtonFX:_Apply(button: GuiButton)
	if button:GetAttribute("ButtonAnimation") == false then return end

	local uiScale = ensureUIScale(button)

	-- Optional BG child (Frame or child named "BG") for position tween on click
	local bg: Frame? = button:FindFirstChild("BG") :: Frame?
		or button:FindFirstChildWhichIsA("Frame") :: Frame?

	-- Optional text-fade labels (requires "textdisplay" attribute on button)
	local textLabel: TextLabel?  = nil
	local titleLabel: TextLabel? = nil
	if button:GetAttribute("textdisplay") and bg then
		textLabel  = bg:FindFirstChildWhichIsA("TextLabel") :: TextLabel?
		titleLabel = textLabel and textLabel:FindFirstChildWhichIsA("TextLabel") :: TextLabel?
	end

	setInitialFade(textLabel)
	setInitialFade(titleLabel)

	local hovering = false

	button.MouseEnter:Connect(function()
		hovering = true
		tweenObj(uiScale, { Scale = 1.05 }, 0.05)
		pcall(function() SoundService["RBLX UI Hover 01 (SFX)"]:Play() end)
		tweenFade(textLabel,  0, 0)
		tweenFade(titleLabel, 0, 0)
	end)

	button.MouseLeave:Connect(function()
		hovering = false
		tweenObj(uiScale, { Scale = 1 }, 0.05)
		tweenFade(textLabel,  1, 1)
		tweenFade(titleLabel, 1, 1)
	end)

	button.MouseButton1Down:Connect(function()
		tweenObj(uiScale, { Scale = 0.95 }, 0.05)
		pcall(function() SoundService.cartoon_pop:Play() end)
		if bg then
			tweenObj(bg, { Position = UDim2.new(0.5, 0, 0.5, 0) }, 0.1)
		end
	end)

	button.MouseButton1Up:Connect(function()
		tweenObj(uiScale, { Scale = hovering and 1.05 or 1 }, 0.05)
		pcall(function() SoundService.cartoon_pop2:Play() end)
		if bg then
			tweenObj(bg, {
				Position = hovering
					and UDim2.new(0.5, 0, 0.44, 0)
					or  UDim2.new(0.5, 0, 0.5,  0),
			}, 0.1)
		end
	end)
end

-- ── public API ───────────────────────────────────────────────────────────────

function ButtonFX:Bind(root: Instance)
	for _, gui in ipairs(root:GetDescendants()) do
		if gui:IsA("GuiButton") then
			self:_Apply(gui :: GuiButton)
		end
	end

	root.DescendantAdded:Connect(function(desc)
		if desc:IsA("GuiButton") then
			self:_Apply(desc :: GuiButton)
		end
	end)
end

return ButtonFX
