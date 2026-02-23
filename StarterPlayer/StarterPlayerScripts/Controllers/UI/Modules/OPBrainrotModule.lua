--!strict
-- OPBrainrotModule.lua  |  Frame: OPBrainrot
-- Displays info about a rare / event brainrot currently active in the world.
-- Server fires a Notify event with type "opBrainrot" to show/hide this panel.
-- Uses Spin + Pulse for the boss icon.
--
-- WIRE-UP NOTES:
--   Frame "OPBrainrot"
--     ├─ BossIcon     (ImageLabel – spins + pulses while active)
--     ├─ BossName     (TextLabel)
--     ├─ RarityLabel  (TextLabel)
--     ├─ HealthBar    (Frame – scaled width)
--     ├─ TimerLabel   (TextLabel – optional countdown)
--     ├─ RewardLabel  (TextLabel – "Bonus: +X%")
--     └─ XButton  (TextButton)

local OPBrainrotModule = {}
OPBrainrotModule.__index = OPBrainrotModule

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

function OPBrainrotModule:_startEffects()
	local ctx     = self._ctx
	local iconLbl = find(self._frame, "BossIcon") :: ImageLabel?
	if not iconLbl then return end

	self._spinHandle  = ctx.UI.Effects.Spin(iconLbl, 0.4)
	self._pulseHandle = ctx.UI.Effects.Pulse(iconLbl, 1.2, 0.04)
end

function OPBrainrotModule:_stopEffects()
	if self._spinHandle  then self._spinHandle:Destroy();  self._spinHandle  = nil end
	if self._pulseHandle then self._pulseHandle:Destroy(); self._pulseHandle = nil end
end

function OPBrainrotModule:Show(payload: any)
	if not self._frame then return end
	local ctx      = self._ctx
	local brainCfg = ctx.Config.BrainrotConfig or {}
	local rarCfg   = ctx.Config.RarityConfig

	local brainKey = payload.brainrotId or ""
	local data     = brainCfg[brainKey] or {}
	local rname    = data.RarityName or payload.rarity or "Legendary"

	local nameLbl   = find(self._frame, "BossName")    :: TextLabel?
	local rarLbl    = find(self._frame, "RarityLabel")  :: TextLabel?
	local rewardLbl = find(self._frame, "RewardLabel")  :: TextLabel?
	local timerLbl  = find(self._frame, "TimerLabel")   :: TextLabel?

	if nameLbl   then nameLbl.Text   = data.DisplayName or brainKey end
	if rewardLbl then rewardLbl.Text = payload.rewardBonus and ("Bonus: +" .. tostring(payload.rewardBonus) .. "%") or "" end

	if rarLbl then
		rarLbl.Text = rname
		if rarCfg then
			local rData = rarCfg.Rarities[rname]
			if rData then rarLbl.TextColor3 = rData.Color end
		end
	end

	if ctx.Router then ctx.Router:Open("OPBrainrot") end
	ctx.UI.Sound:Play("cartoon_pop")
	self:_startEffects()

	-- Optional countdown timer
	if payload.timer and timerLbl then
		if self._timerThread then task.cancel(self._timerThread) end
		local t = payload.timer
		self._timerThread = task.spawn(function()
			while t > 0 do
				timerLbl.Text = "Despawns in: " .. tostring(t) .. "s"
				task.wait(1)
				t -= 1
			end
			timerLbl.Text = ""
			self:Hide()
		end)
	end
end

function OPBrainrotModule:Hide()
	if not self._frame then return end
	if self._timerThread then task.cancel(self._timerThread); self._timerThread = nil end
	self:_stopEffects()
	if self._ctx.Router then self._ctx.Router:Close("OPBrainrot") end
end

function OPBrainrotModule:Init(ctx: any)
	self._ctx         = ctx
	self._janitor     = ctx.UI.Cleaner.new()
	self._spinHandle  = nil :: any
	self._pulseHandle = nil :: any
	self._timerThread = nil :: thread?

	self._frame = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("OPBrainrot")
	if not self._frame then warn("[OPBrainrotModule] Frame 'OPBrainrot' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:Hide()
		end))
	end

	self._frame.Visible = false
end

function OPBrainrotModule:Start()
	if not self._frame then return end
	local ctx = self._ctx

	local notifyRE = ctx.Net:GetEvent("Notify")
	self._janitor:Add(notifyRE.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		if payload.type == "opBrainrot" then
			self:Show(payload)
		elseif payload.type == "opBrainrotDied" then
			self:Hide()
		end
	end))
end

function OPBrainrotModule:Destroy()
	if self._timerThread then task.cancel(self._timerThread) end
	self:_stopEffects()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return OPBrainrotModule
