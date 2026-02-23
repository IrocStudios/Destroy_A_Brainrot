--!strict
-- CommandModule.lua  |  Frame: CommandPrompt (created at runtime)
-- In-game admin / developer command prompt.
--
-- Toggle with: F8 key  (or via a CommandBtn button with Frame="CommandPrompt")
-- Type a command and press Enter or click Submit.
-- Output appears in a scrolling log below the input bar.
--
-- All commands are forwarded to AdminService on the server via CommandAction RF.
-- AdminService.DEV_MODE must be true, OR your UserId must be in ADMIN_IDS.
--
-- The frame is created programmatically so no Studio setup is required.

local UserInputService = game:GetService("UserInputService")

local CommandModule = {}
CommandModule.__index = CommandModule

local TOGGLE_KEY   = Enum.KeyCode.F8
local MAX_LOG_LINES = 50
local BG_COLOR  = Color3.fromRGB(15, 15, 20)
local OK_COLOR  = Color3.fromRGB(100, 255, 120)
local ERR_COLOR = Color3.fromRGB(255, 90, 90)
local SYS_COLOR = Color3.fromRGB(180, 180, 255)
local FONT      = Enum.Font.Code

-- ── Build GUI ─────────────────────────────────────────────────────────────────
local function buildUI(playerGui: Instance): (Frame, TextBox, TextButton, ScrollingFrame)
	local screen = Instance.new("ScreenGui")
	screen.Name            = "CommandPromptGui"
	screen.ResetOnSpawn    = false
	screen.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder    = 99
	screen.IgnoreGuiInset  = true
	screen.Enabled         = true
	screen.Parent          = playerGui

	-- Outer frame (450×340, centred)
	local outer = Instance.new("Frame")
	outer.Name            = "CommandPrompt"
	outer.Size            = UDim2.new(0, 500, 0, 360)
	outer.Position        = UDim2.new(0.5, -250, 0.5, -180)
	outer.BackgroundColor3 = BG_COLOR
	outer.BackgroundTransparency = 0.08
	outer.BorderSizePixel = 0
	outer.Visible         = false
	outer.Parent          = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = outer

	local stroke = Instance.new("UIStroke")
	stroke.Color     = Color3.fromRGB(80, 80, 120)
	stroke.Thickness = 1
	stroke.Parent    = outer

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name            = "TitleBar"
	titleBar.Size            = UDim2.new(1, 0, 0, 30)
	titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 50)
	titleBar.BorderSizePixel  = 0
	titleBar.Parent           = outer

	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, 8)
	titleCorner.Parent = titleBar

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Text          = "⌨  Admin Command Console  [F8]"
	titleLbl.Size          = UDim2.new(1, -40, 1, 0)
	titleLbl.Position      = UDim2.new(0, 8, 0, 0)
	titleLbl.TextColor3    = Color3.fromRGB(200, 200, 255)
	titleLbl.TextSize      = 14
	titleLbl.Font          = FONT
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.BackgroundTransparency = 1
	titleLbl.Parent = titleBar

	-- Close X
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name             = "CloseBtn"
	closeBtn.Text             = "✕"
	closeBtn.Size             = UDim2.new(0, 28, 0, 28)
	closeBtn.Position         = UDim2.new(1, -30, 0, 1)
	closeBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	closeBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
	closeBtn.TextSize         = 14
	closeBtn.Font             = FONT
	closeBtn.BorderSizePixel  = 0
	closeBtn.Parent           = titleBar

	local closeBtnCorner = Instance.new("UICorner")
	closeBtnCorner.CornerRadius = UDim.new(0, 4)
	closeBtnCorner.Parent = closeBtn

	-- Log area
	local logFrame = Instance.new("ScrollingFrame")
	logFrame.Name               = "LogFrame"
	logFrame.Size               = UDim2.new(1, -16, 1, -78)
	logFrame.Position           = UDim2.new(0, 8, 0, 36)
	logFrame.BackgroundColor3   = Color3.fromRGB(8, 8, 12)
	logFrame.BackgroundTransparency = 0.2
	logFrame.BorderSizePixel    = 0
	logFrame.ScrollBarThickness = 4
	logFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	logFrame.CanvasSize         = UDim2.new(0, 0, 0, 0)
	logFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	logFrame.Parent             = outer

	local logCorner = Instance.new("UICorner")
	logCorner.CornerRadius = UDim.new(0, 4)
	logCorner.Parent = logFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding   = UDim.new(0, 2)
	listLayout.Parent    = logFrame

	local logPad = Instance.new("UIPadding")
	logPad.PaddingLeft   = UDim.new(0, 6)
	logPad.PaddingRight  = UDim.new(0, 6)
	logPad.PaddingTop    = UDim.new(0, 4)
	logPad.PaddingBottom = UDim.new(0, 4)
	logPad.Parent        = logFrame

	-- Input row
	local inputRow = Instance.new("Frame")
	inputRow.Name            = "InputRow"
	inputRow.Size            = UDim2.new(1, -16, 0, 32)
	inputRow.Position        = UDim2.new(0, 8, 1, -40)
	inputRow.BackgroundColor3 = Color3.fromRGB(20, 20, 35)
	inputRow.BorderSizePixel  = 0
	inputRow.Parent           = outer

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 6)
	inputCorner.Parent = inputRow

	local inputBox = Instance.new("TextBox")
	inputBox.Name              = "InputBox"
	inputBox.Size              = UDim2.new(1, -70, 1, 0)
	inputBox.Position          = UDim2.new(0, 8, 0, 0)
	inputBox.BackgroundTransparency = 1
	inputBox.TextColor3        = Color3.fromRGB(230, 230, 255)
	inputBox.PlaceholderText   = "> type command here…"
	inputBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 140)
	inputBox.TextSize          = 14
	inputBox.Font              = FONT
	inputBox.ClearTextOnFocus  = false
	inputBox.TextXAlignment    = Enum.TextXAlignment.Left
	inputBox.Parent            = inputRow

	local submitBtn = Instance.new("TextButton")
	submitBtn.Name            = "SubmitBtn"
	submitBtn.Text            = "⏎ Run"
	submitBtn.Size            = UDim2.new(0, 60, 1, -4)
	submitBtn.Position        = UDim2.new(1, -64, 0, 2)
	submitBtn.BackgroundColor3 = Color3.fromRGB(60, 100, 200)
	submitBtn.TextColor3      = Color3.fromRGB(255, 255, 255)
	submitBtn.TextSize        = 12
	submitBtn.Font            = FONT
	submitBtn.BorderSizePixel = 0
	submitBtn.Parent          = inputRow

	local submitCorner = Instance.new("UICorner")
	submitCorner.CornerRadius = UDim.new(0, 4)
	submitCorner.Parent = submitBtn

	return outer, inputBox, submitBtn, logFrame
end

-- ── Log line builder ──────────────────────────────────────────────────────────
local function makeLogLine(text: string, color: Color3, layoutOrder: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Text             = text
	lbl.TextColor3       = color
	lbl.BackgroundTransparency = 1
	lbl.TextSize         = 13
	lbl.Font             = FONT
	lbl.TextXAlignment   = Enum.TextXAlignment.Left
	lbl.TextWrapped      = true
	lbl.AutomaticSize    = Enum.AutomaticSize.Y
	lbl.Size             = UDim2.new(1, 0, 0, 0)
	lbl.LayoutOrder      = layoutOrder
	return lbl
end

-- ── Module ────────────────────────────────────────────────────────────────────
function CommandModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._logLines = {} :: { TextLabel }
	self._layoutOrder = 0
	self._open    = false

	-- Build UI programmatically
	local frame, inputBox, submitBtn, logFrame = buildUI(ctx.PlayerGui)
	self._frame      = frame
	self._inputBox   = inputBox
	self._submitBtn  = submitBtn
	self._logFrame   = logFrame

	-- Wire close button
	local closeBtn = frame:FindFirstChild("CloseBtn", true)
	if closeBtn then
		self._janitor:Add((closeBtn :: TextButton).MouseButton1Click:Connect(function()
			self:_hide()
		end))
	end

	-- Wire submit button
	self._janitor:Add(submitBtn.MouseButton1Click:Connect(function()
		self:_submit()
	end))

	-- Wire Enter key in input box
	self._janitor:Add(inputBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then self:_submit() end
	end))

	-- Print welcome
	self:_log("Command Console ready. Type 'help' for commands.", SYS_COLOR)
end

function CommandModule:Start()
	-- Toggle on F8
	self._janitor:Add(UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == TOGGLE_KEY then
			self:_toggle()
		end
	end))
end

-- ── Actions ───────────────────────────────────────────────────────────────────
function CommandModule:_toggle()
	if self._open then self:_hide() else self:_show() end
end

function CommandModule:_show()
	self._open = true
	self._frame.Visible = true
	self._inputBox:CaptureFocus()
end

function CommandModule:_hide()
	self._open = false
	self._frame.Visible = false
end

function CommandModule:_submit()
	local raw: string = self._inputBox.Text:match("^%s*(.-)%s*$")
	if #raw == 0 then return end

	-- Show what was typed
	self:_log("> " .. raw, Color3.fromRGB(220, 220, 255))
	self._inputBox.Text = ""

	-- Fire to server
	local ctx = self._ctx
	local net = ctx.Net
	if not net then
		self:_log("❌ Net not available.", ERR_COLOR)
		return
	end

	local rf = net:GetFunction("CommandAction")
	task.spawn(function()
		local ok, result = pcall(function()
			return rf:InvokeServer({ command = raw })
		end)

		if not ok then
			self:_log("❌ Network error: " .. tostring(result), ERR_COLOR)
			return
		end

		if type(result) ~= "table" then
			self:_log("❌ Bad response from server.", ERR_COLOR)
			return
		end

		local output = tostring(result.output or "")
		if output == "" then output = result.ok and "OK." or "Failed." end

		-- Multi-line output support
		for line in (output .. "\n"):gmatch("([^\n]*)\n") do
			if #line > 0 then
				self:_log(line, result.ok and OK_COLOR or ERR_COLOR)
			end
		end
	end)
end

function CommandModule:_log(text: string, color: Color3)
	self._layoutOrder += 1
	local lbl = makeLogLine(text, color, self._layoutOrder)
	lbl.Parent = self._logFrame

	table.insert(self._logLines, lbl)

	-- Trim oldest lines if over limit
	while #self._logLines > MAX_LOG_LINES do
		local oldest = table.remove(self._logLines, 1)
		oldest:Destroy()
	end

	-- Scroll to bottom
	task.defer(function()
		self._logFrame.CanvasPosition = Vector2.new(
			0,
			math.max(0, self._logFrame.AbsoluteCanvasSize.Y - self._logFrame.AbsoluteSize.Y)
		)
	end)
end

-- ── Destroy ───────────────────────────────────────────────────────────────────
function CommandModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
	if self._frame and self._frame.Parent then
		-- Destroy the whole ScreenGui we created
		local sg = self._frame.Parent
		if sg and sg:IsA("ScreenGui") then sg:Destroy() end
	end
end

return CommandModule
