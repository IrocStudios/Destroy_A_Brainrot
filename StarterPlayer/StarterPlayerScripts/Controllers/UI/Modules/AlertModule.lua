--!strict
-- AlertModule.lua  |  Frame: Alert
-- General-purpose modal used by other modules: Show(config) → confirm/cancel.

local AlertModule = {}
AlertModule.__index = AlertModule

AlertModule._ctx      = nil :: any
AlertModule._janitor  = nil :: any
AlertModule._frame    = nil :: any
AlertModule._callback = nil :: any

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

function AlertModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Alert")
	if not self._frame then warn("[AlertModule] Frame 'Alert' not found") return end

	local confirmBtn = find(self._frame, "ConfirmButton")
	if confirmBtn then
		self._janitor:Add((confirmBtn :: GuiButton).MouseButton1Click:Connect(function()
			if self._callback then self._callback(true); self._callback = nil end
			self:Hide()
		end))
	end

	local cancelBtn = find(self._frame, "CancelButton")
	if cancelBtn then
		cancelBtn.Visible = false
		self._janitor:Add((cancelBtn :: GuiButton).MouseButton1Click:Connect(function()
			if self._callback then self._callback(false); self._callback = nil end
			self:Hide()
		end))
	end

	self._frame.Visible = false
end

function AlertModule:Start() end

-- config = { title, message, confirm?, cancel?, warning?, callback? }
function AlertModule:Show(config: any)
	if not self._frame then return end

	local titleLbl   = find(self._frame, "Title")
	local messageLbl = find(self._frame, "Message")
	local confirmBtn = find(self._frame, "ConfirmButton")
	local cancelBtn  = find(self._frame, "CancelButton")

	if titleLbl   then (titleLbl   :: TextLabel).Text = config.title   or "" end
	if messageLbl then (messageLbl :: TextLabel).Text = config.message or "" end
	if confirmBtn then (confirmBtn :: TextButton).Text = config.confirm or "OK" end

	if cancelBtn then
		cancelBtn.Visible = config.cancel ~= nil
		if config.cancel then (cancelBtn :: TextButton).Text = config.cancel end
	end

	if config.warning then
		self._ctx.UI.Effects.Shake(self._frame, 6, 0.3, 0.15)
	end

	self._callback = config.callback
	if self._ctx.Router then self._ctx.Router:Open("Alert") end
end

function AlertModule:Hide()
	if not self._frame then return end
	if self._ctx.Router then self._ctx.Router:Close("Alert") end
	self._callback = nil
end

function AlertModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return AlertModule