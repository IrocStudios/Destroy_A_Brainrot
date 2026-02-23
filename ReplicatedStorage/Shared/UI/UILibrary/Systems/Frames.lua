--!strict

local TweenService = game:GetService("TweenService")

local Frames = {}
Frames.__index = Frames

-- ── helpers ──────────────────────────────────────────────────────────────────

local function ensureUIScale(obj: Instance): UIScale
	local ui = obj:FindFirstChildOfClass("UIScale")
	if not ui then
		ui = Instance.new("UIScale")
		ui.Parent = obj
	end
	return ui :: UIScale
end

local function tweenScale(uiScale: UIScale, target: number, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
	TweenService:Create(uiScale, info, { Scale = target }):Play()
end

-- Staggered bounce-in for all frames and buttons inside a Container child.
-- Mirrors animateContainer() from Ref/Frames.lua exactly.
local function animateContainer(container: Instance)
	local frames: { Frame }         = {}
	local directBtns: { GuiButton } = {}

	for _, item in ipairs(container:GetChildren()) do
		if item:IsA("Frame") then
			table.insert(frames, item :: Frame)
		elseif item:IsA("TextButton") or item:IsA("ImageButton") then
			table.insert(directBtns, item :: GuiButton)
		end
	end

	-- Animate each Frame row, then the buttons inside it
	for i, frame in ipairs(frames) do
		task.delay(i * 0.05, function()
			local ui = frame:FindFirstChildOfClass("UIScale")
			if not ui then
				ui = Instance.new("UIScale")
				;(ui :: UIScale).Scale = 0
				ui.Parent = frame
			end
			tweenScale(ui :: UIScale, 1.1, 0.15)
			task.delay(0.15, function()
				tweenScale(ui :: UIScale, 1, 0.1)
			end)

			local btns: { GuiButton } = {}
			for _, child in ipairs(frame:GetChildren()) do
				if child:IsA("TextButton") or child:IsA("ImageButton") then
					table.insert(btns, child :: GuiButton)
					local uiB = child:FindFirstChildOfClass("UIScale")
					if not uiB then
						uiB = Instance.new("UIScale")
						;(uiB :: UIScale).Scale = 0
						uiB.Parent = child
					end
				end
			end
			table.sort(btns, function(a, b)
				return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
			end)
			for j, btn in ipairs(btns) do
				task.delay(j * 0.05, function()
					local uiB = btn:FindFirstChildOfClass("UIScale") :: UIScale?
					if uiB then
						tweenScale(uiB, 1.1, 0.15)
						task.delay(0.15, function() tweenScale(uiB, 1, 0.1) end)
					end
				end)
			end
		end)
	end

	-- Animate buttons directly inside Container (not nested in a frame row)
	table.sort(directBtns, function(a, b)
		return (a.LayoutOrder or 0) < (b.LayoutOrder or 0)
	end)
	for k, btn in ipairs(directBtns) do
		task.delay(k * 0.05, function()
			local ui = btn:FindFirstChildOfClass("UIScale")
			if not ui then
				ui = Instance.new("UIScale")
				;(ui :: UIScale).Scale = 0
				ui.Parent = btn
			end
			tweenScale(ui :: UIScale, 1.1, 0.15)
			task.delay(0.15, function() tweenScale(ui :: UIScale, 1, 0.1) end)
		end)
	end
end

-- Resets all UIScales inside a frame's Container child back to 0.
-- Children with Animate attribute == false are left at scale 1.
local function resetContainerScales(frame: Instance)
	local container = frame:FindFirstChild("Container")
	if not container then return end

	for _, child in ipairs(container:GetChildren()) do
		local skip = child:GetAttribute("Animate") == false
		if child:IsA("Frame") then
			local ui = child:FindFirstChildOfClass("UIScale")
			if not ui then
				ui = Instance.new("UIScale")
				ui.Parent = child
			end
			;(ui :: UIScale).Scale = skip and 1 or 0

			for _, btn in ipairs(child:GetChildren()) do
				if btn:IsA("TextButton") or btn:IsA("ImageButton") then
					local uiB = btn:FindFirstChildOfClass("UIScale")
					if not uiB then
						uiB = Instance.new("UIScale")
						uiB.Parent = btn
					end
					;(uiB :: UIScale).Scale = skip and 1 or 0
				end
			end

		elseif child:IsA("TextButton") or child:IsA("ImageButton") then
			local uiB = child:FindFirstChildOfClass("UIScale")
			if not uiB then
				uiB = Instance.new("UIScale")
				uiB.Parent = child
			end
			;(uiB :: UIScale).Scale = skip and 1 or 0
		end
	end
end

-- ── Frames router ─────────────────────────────────────────────────────────────

function Frames.new(options: { FramesFolder: Instance })
	local self = setmetatable({}, Frames)
	self.FramesFolder = options.FramesFolder
	self.Current      = nil :: Instance?
	return self
end

-- Pre-register a single frame: UIScale = 0, container reset.
function Frames:RegisterFrame(frame: Frame)
	ensureUIScale(frame).Scale = 0
	resetContainerScales(frame)
end

-- Reset every Frame in FramesFolder to scale 0 on boot.
function Frames:ResetAll()
	for _, frame in ipairs(self.FramesFolder:GetChildren()) do
		if frame:IsA("Frame") then
			ensureUIScale(frame).Scale = 0
			resetContainerScales(frame)
		end
	end
	self.Current = nil
end

-- ── internal open / close ────────────────────────────────────────────────────

function Frames:_openFrame(frame: Instance)
	local ui = ensureUIScale(frame)
	ui.Scale = 0
	tweenScale(ui, 1.1, 0.15)
	task.delay(0.15, function()
		tweenScale(ui, 1, 0.1)
		local container = frame:FindFirstChild("Container")
		if container then
			animateContainer(container)
		end
	end)
	self.Current = frame
end

function Frames:_closeFrame(frame: Instance)
	local ui = ensureUIScale(frame)
	tweenScale(ui, 1.1, 0.15)
	task.delay(0.15, function()
		tweenScale(ui, 0, 0.1)
		resetContainerScales(frame)
	end)
	if self.Current == frame then
		self.Current = nil
	end
end

-- ── public API ───────────────────────────────────────────────────────────────

function Frames:Open(name: string)
	local frame = self.FramesFolder:FindFirstChild(name)
	if not frame then
		warn(("[Frames] Open: %q not found in FramesFolder"):format(name))
		return
	end

	-- Toggle off if already showing
	if self.Current == frame then
		self:_closeFrame(frame)
		return
	end

	-- Close current, then open new after a short gap (matching Ref behaviour)
	if self.Current then
		self:_closeFrame(self.Current)
		task.delay(0.1, function()
			self:_openFrame(frame)
		end)
	else
		self:_openFrame(frame)
	end
end

function Frames:Close(name: string)
	local frame = self.FramesFolder:FindFirstChild(name)
	if not frame then return end
	self:_closeFrame(frame)
end

function Frames:Toggle(name: string)
	local frame = self.FramesFolder:FindFirstChild(name)
	if not frame then return end
	if self.Current == frame then
		self:_closeFrame(frame)
	else
		self:Open(name)
	end
end

-- Wire all GuiButtons with a "Frame" StringAttribute to toggle that frame.
-- Watches DescendantAdded so late-added buttons are automatically covered.
function Frames:BindButtons(root: Instance)
	local function hookBtn(btn: Instance)
		if not (btn:IsA("TextButton") or btn:IsA("ImageButton")) then return end
		;(btn :: GuiButton).MouseButton1Click:Connect(function()
			local frameName = btn:GetAttribute("Frame")
			if frameName then
				self:Toggle(frameName :: string)
			end
		end)
	end

	for _, btn in ipairs(root:GetDescendants()) do
		hookBtn(btn)
	end
	root.DescendantAdded:Connect(hookBtn)
end

return Frames
