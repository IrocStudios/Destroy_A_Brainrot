--!strict
-- CodesModule.lua  |  Frame: Codes
-- Lets players enter promo codes. Requires a "CodesAction" RemoteFunction
-- on the server (add it to NetIds + NetService when you implement code redemption).
--
-- WIRE-UP NOTES:
--   Frame "Codes"
--     ├─ CodeInput    (TextBox – player types code here)
--     ├─ SubmitButton (TextButton)
--     ├─ ResultLabel  (TextLabel – success / error feedback)
--     └─ XButton  (TextButton)

local CodesModule = {}
CodesModule.__index = CodesModule

local RESULT_CLEAR_DELAY = 3 -- seconds before result label clears

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

function CodesModule:_setResult(text: string, isError: boolean)
	local lbl = find(self._frame, "ResultLabel") :: TextLabel?
	if not lbl then return end

	lbl.Text = text
	lbl.TextColor3 = isError
		and Color3.fromRGB(255, 80, 80)
		or  Color3.fromRGB(80, 255, 100)

	if self._clearThread then task.cancel(self._clearThread) end
	self._clearThread = task.delay(RESULT_CLEAR_DELAY, function()
		lbl.Text = ""
		self._clearThread = nil
	end)
end

function CodesModule:_onSubmit()
	local ctx      = self._ctx
	local inputBox = find(self._frame, "CodeInput") :: TextBox?
	if not inputBox then return end

	local code = inputBox.Text:match("^%s*(.-)%s*$") -- trim whitespace
	if code == "" then
		self:_setResult("Enter a code first!", true)
		ctx.UI.Effects.Shake(inputBox, 5, 0.2, 0.1)
		return
	end

	-- Disable submit while processing
	local submitBtn = find(self._frame, "SubmitButton") :: TextButton?
	if submitBtn then submitBtn.Active = false; submitBtn.Text = "..." end

	task.spawn(function()
		-- NOTE: "CodesAction" must be added to NetIds.RemoteFunctions and NetService
		local rf = ctx.Net:GetFunction("CodesAction")
		local ok, result = pcall(function()
			return rf:InvokeServer({ action = "redeem", code = code })
		end)

		if submitBtn then submitBtn.Active = true; submitBtn.Text = "Submit" end

		if not ok then
			self:_setResult("Server error. Try again.", true)
			ctx.UI.Effects.Shake(self._frame, 5, 0.25, 0.1)
			return
		end

		if type(result) == "table" then
			if result.ok then
				self:_setResult("Code redeemed! " .. (result.reward or ""), false)
				ctx.UI.Sound:Play("cartoon_pop")
				inputBox.Text = ""
			elseif result.reason == "AlreadyRedeemed" then
				self:_setResult("Code already redeemed.", true)
				ctx.UI.Effects.Shake(inputBox, 5, 0.25, 0.1)
			elseif result.reason == "Invalid" then
				self:_setResult("Invalid code.", true)
				ctx.UI.Effects.Shake(inputBox, 5, 0.25, 0.1)
			else
				self:_setResult(result.reason or "Failed.", true)
			end
		end
	end)
end

function CodesModule:Init(ctx: any)
	self._ctx         = ctx
	self._janitor     = ctx.UI.Cleaner.new()
	self._clearThread = nil :: thread?
	self._frame       = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Codes")
	if not self._frame then warn("[CodesModule] Frame 'Codes' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("Codes") end
		end))
	end

	local submitBtn = find(self._frame, "SubmitButton")
	if submitBtn then
		self._janitor:Add((submitBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onSubmit()
		end))
	end

	-- Allow Enter key to submit
	local inputBox = find(self._frame, "CodeInput") :: TextBox?
	if inputBox then
		self._janitor:Add(inputBox.FocusLost:Connect(function(enterPressed)
			if enterPressed then self:_onSubmit() end
		end))
	end
end

function CodesModule:Start() end

function CodesModule:Destroy()
	if self._clearThread then task.cancel(self._clearThread) end
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return CodesModule
