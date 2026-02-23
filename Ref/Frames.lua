local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FRAMES_FOLDER = playerGui:WaitForChild("GUI"):WaitForChild("Frames")

local currentFrame = nil

local function ensureUIScale(frame)
	local uiScale = frame:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Parent = frame
	end
	return uiScale
end

local function tweenScale(uiScale, targetScale, duration)
	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
	local tween = TweenService:Create(uiScale, tweenInfo, {Scale = targetScale})
	tween:Play()
	return tween
end

local function animateContainer(container)
	local frames = {}
	local directButtons = {}

	-- rozdzielamy frame'y i bezposrednie buttony
	for _, item in ipairs(container:GetChildren()) do
		if item:IsA("Frame") then
			table.insert(frames, item)
		elseif item:IsA("TextButton") or item:IsA("ImageButton") then
			table.insert(directButtons, item)
		end
	end

	-- animacja frame + buttony wewnatrz frame
	for i, frame in ipairs(frames) do
		task.delay(i * 0.05, function()
			local ui = frame:FindFirstChildOfClass("UIScale")
			if not ui then
				ui = Instance.new("UIScale")
				ui.Parent = frame
				ui.Scale = 0
			end
			tweenScale(ui, 1.1, 0.15)
			task.delay(0.15, function()
				tweenScale(ui, 1, 0.1)
			end)

			-- buttony w frame, sortowanie LayoutOrder
			local buttons = {}
			for _, child in ipairs(frame:GetChildren()) do
				if child:IsA("TextButton") or child:IsA("ImageButton") then
					table.insert(buttons, child)
					local uiChild = child:FindFirstChildOfClass("UIScale")
					if not uiChild then
						uiChild = Instance.new("UIScale")
						uiChild.Parent = child
						uiChild.Scale = 0
					end
				end
			end
			table.sort(buttons, function(a,b) return (a.LayoutOrder or 0) < (b.LayoutOrder or 0) end)

			for j, btn in ipairs(buttons) do
				task.delay(j * 0.05, function()
					local ui = btn:FindFirstChildOfClass("UIScale")
					if ui then
						tweenScale(ui, 1.1, 0.15)
						task.delay(0.15, function()
							tweenScale(ui, 1, 0.1)
						end)
					end
				end)
			end
		end)
	end

	-- animacja buttonów bezposrednio w containerze
	table.sort(directButtons, function(a, b)
		return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
	end)

	for k, btn in ipairs(directButtons) do
		task.delay(k * 0.05, function()
			local ui = btn:FindFirstChildOfClass("UIScale")
			if not ui then
				ui = Instance.new("UIScale")
				ui.Parent = btn
				ui.Scale = 0
			end
			tweenScale(ui, 1.1, 0.15)
			task.delay(0.15, function()
				tweenScale(ui, 1, 0.1)
			end)
		end)
	end
end

local function resetContainerScales(frame)
	local container = frame:FindFirstChild("Container")
	if not container then return end

	-- reset frame'ów w containerze
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") then
			local ui = child:FindFirstChildOfClass("UIScale")
			if not ui then
				ui = Instance.new("UIScale")
				ui.Parent = child
			end
			if child:GetAttribute("Animate") == false then
				ui.Scale = 1
			else
				ui.Scale = 0
			end


			-- reset buttonów wewnatrz frame
			for _, btn in ipairs(child:GetChildren()) do
				if btn:IsA("TextButton") or btn:IsA("ImageButton") then
					local uiBtn = btn:FindFirstChildOfClass("UIScale")
					if not uiBtn then
						uiBtn = Instance.new("UIScale")
						uiBtn.Parent = btn
					end
					if child:GetAttribute("Animate") == false then
						uiBtn.Scale = 1
					else
						uiBtn.Scale = 0
					end
				end
			end
		elseif child:IsA("TextButton") or child:IsA("ImageButton") then
			-- reset buttonów bezposrednio w containerze
			local uiBtn = child:FindFirstChildOfClass("UIScale")
			if not uiBtn then
				uiBtn = Instance.new("UIScale")
				uiBtn.Parent = child
			end
			if child:GetAttribute("Animate") == false then
				uiBtn.Scale = 1
			else
				uiBtn.Scale = 0
			end

		end
	end
end



local function closeFrame(frame)
	if not frame then return end
	local uiScale = ensureUIScale(frame)
	tweenScale(uiScale, 1.1, 0.15)
	task.delay(0.15, function()
		tweenScale(uiScale, 0, 0.1)
		resetContainerScales(frame)
	end)
	if currentFrame == frame then
		currentFrame = nil
	end
end

local function openFrame(frame)

	if currentFrame == frame then
		closeFrame(frame)
		return
	end


	if currentFrame and currentFrame ~= frame then
		closeFrame(currentFrame)
		task.delay(0.1, function()

			if currentFrame ~= frame then
				local uiScale = ensureUIScale(frame)
				uiScale.Scale = 0
				tweenScale(uiScale, 1.1, 0.15)
				task.delay(0.15, function()
					tweenScale(uiScale, 1, 0.1)
					local container = frame:FindFirstChild("Container")
					if container then
						animateContainer(container)
					end
				end)
				currentFrame = frame
			end
		end)
	else

		local uiScale = ensureUIScale(frame)
		uiScale.Scale = 0
		tweenScale(uiScale, 1.1, 0.15)
		task.delay(0.15, function()
			tweenScale(uiScale, 1, 0.1)
			local container = frame:FindFirstChild("Container")
			if container then
				animateContainer(container)
			end
		end)
		currentFrame = frame
	end
end


local function watchXButtons(frame)

	if frame:FindFirstChild("XButton") then
		local btn = frame:WaitForChild("XButton")
			btn.MouseButton1Click:Connect(function()
				closeFrame(frame)
			end)
		end
	end

local function watchButtons(root)
	for _, btn in ipairs(root:GetDescendants()) do
		if btn:IsA("TextButton") or btn:IsA("ImageButton") then
			btn.MouseButton1Click:Connect(function()
				local frameName = btn:GetAttribute("Frame")
				if frameName then
					local frame = FRAMES_FOLDER:FindFirstChild(frameName)
					if frame then
						openFrame(frame)
					end
				end
			end)
		end
	end

	root.DescendantAdded:Connect(function(btn)
		if btn:IsA("TextButton") or btn:IsA("ImageButton") then
			btn.MouseButton1Click:Connect(function()
				local frameName = btn:GetAttribute("Frame")
				if frameName then
					local frame = FRAMES_FOLDER:FindFirstChild(frameName)
					if frame then
						openFrame(frame)
					end
				end
			end)
		end
	end)
end

local function resetAllFrames()
	for _, frame in ipairs(FRAMES_FOLDER:GetChildren()) do
		if frame:IsA("Frame") then
			local ui = ensureUIScale(frame)
			ui.Scale = 0
			resetContainerScales(frame)
		end
	end
	currentFrame = nil
end

local function watchFrames()
	for _, frame in ipairs(FRAMES_FOLDER:GetChildren()) do
		if frame:IsA("Frame") then
			watchXButtons(frame)
		end
	end

	FRAMES_FOLDER.ChildAdded:Connect(function(frame)
		if frame:IsA("Frame") then
			watchXButtons(frame)
		end
	end)
end

task.spawn(function()
	resetAllFrames()
	watchButtons(playerGui)
	watchFrames()
end)
-- === OPEN FRAMES FROM WORKSPACE PARTS (TOUCH - FIXED) ===

--local OpenParts = workspace:WaitForChild("OpenParts")
local debounce = {}

local function hookOpenPart(part)
	if not part:IsA("BasePart") then return end

	part.Touched:Connect(function(hit)
		local character = player.Character
		if not character then return end

		if not hit:IsDescendantOf(character) then return end

		if debounce[part] then return end
		debounce[part] = true

		local frame = FRAMES_FOLDER:FindFirstChild(part.Name)
		if frame then
			openFrame(frame)
		end

		task.delay(0.5, function()
			debounce[part] = false
		end)
	end)
end
--[[
-- istniejace party
for _, part in ipairs(OpenParts:GetChildren()) do
	hookOpenPart(part)
end

-- party dodane pózniej
OpenParts.ChildAdded:Connect(function(part)
	hookOpenPart(part)
end)
]]

return true
