--!strict
-- DiscoveryModule.lua  |  Frame: Discovery
-- Popup that appears when the player discovers a new brainrot for the first time.
-- Triggered by server Notify event or BrainrotClientController.
-- Auto-closes after a delay.
--
-- WIRE-UP NOTES:
--   Frame "Discovery"
--     ├─ BrainrotIcon   (ImageLabel)
--     ├─ BrainrotName   (TextLabel)
--     ├─ RarityLabel    (TextLabel)
--     ├─ RarityBar      (Frame)
--     ├─ FlavorText     (TextLabel – "New Discovery!")
--     └─ XButton    (TextButton)

local DiscoveryModule = {}
DiscoveryModule.__index = DiscoveryModule

local AUTO_CLOSE_DELAY = 5

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

function DiscoveryModule:Init(ctx: any)
	self._ctx       = ctx
	self._janitor   = ctx.UI.Cleaner.new()
	self._autoClose = nil :: thread?
	self._frame     = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Discovery")
	if not self._frame then warn("[DiscoveryModule] Frame 'Discovery' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_hide()
		end))
	end

	self._frame.Visible = false
end

function DiscoveryModule:Start()
	if not self._frame then return end
	local ctx = self._ctx

	-- Server fires Notify with type "discovery" when a new brainrot is discovered
	local notifyRE = ctx.Net:GetEvent("Notify")
	self._janitor:Add(notifyRE.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.type == "discovery" then
			self:Show(payload.brainrotId or payload.id or "")
		end
	end))
end

-- Show popup for a given brainrot key
function DiscoveryModule:Show(brainrotKey: string)
	if not self._frame then return end
	local ctx      = self._ctx
	local brainCfg = ctx.Config.BrainrotConfig or {}
	local rarCfg   = ctx.Config.RarityConfig
	local data     = brainCfg[brainrotKey] or {}

	local nameLbl   = find(self._frame, "BrainrotName") :: TextLabel?
	local rarLbl    = find(self._frame, "RarityLabel")  :: TextLabel?
	local rarBar    = find(self._frame, "RarityBar")    :: Frame?
	local iconLbl   = find(self._frame, "BrainrotIcon") :: ImageLabel?
	local flavorLbl = find(self._frame, "FlavorText")   :: TextLabel?

	if nameLbl   then nameLbl.Text   = data.DisplayName or brainrotKey end
	if flavorLbl then flavorLbl.Text = "New Discovery!" end

	local rname = data.RarityName or "Common"
	if rarLbl then
		rarLbl.Text = rname
		if rarCfg then
			local rData = rarCfg.Rarities[rname]
			if rData then rarLbl.TextColor3 = rData.Color end
		end
	end
	if rarBar and rarCfg then
		local rData = rarCfg.Rarities[rname]
		if rData then rarBar.BackgroundColor3 = rData.Color end
	end

	-- Open frame and animate icon
	if ctx.Router then ctx.Router:Open("Discovery") end
	ctx.UI.Sound:Play("cartoon_pop")

	if iconLbl then
		local spinH = ctx.UI.Effects.Spin(iconLbl, 1.0)
		local pulseH = ctx.UI.Effects.Pulse(iconLbl, 1.5, 0.05)
		task.delay(2, function()
			spinH:Destroy()
			pulseH:Destroy()
		end)
	end

	-- Auto-close
	if self._autoClose then task.cancel(self._autoClose) end
	self._autoClose = task.delay(AUTO_CLOSE_DELAY, function()
		self:_hide()
		self._autoClose = nil
	end)
end

function DiscoveryModule:_hide()
	if self._autoClose then task.cancel(self._autoClose); self._autoClose = nil end
	if not self._frame then return end
	if self._ctx.Router then self._ctx.Router:Close("Discovery") end
end

function DiscoveryModule:Destroy()
	if self._autoClose then task.cancel(self._autoClose) end
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return DiscoveryModule
