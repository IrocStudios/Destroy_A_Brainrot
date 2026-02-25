--!strict
-- RebirthModule.lua  |  Frame: Rebirth
-- Shows current rebirth count, requirements, and next multiplier.
-- Validates eligibility client-side for UX; server enforces truth.
--
-- WIRE-UP NOTES:
--   Frame "Rebirth"
--     ├─ RebirthCount  (TextLabel – "Rebirths: N")
--     ├─ NextMultiplier(TextLabel – "+X% Cash per kill")
--     ├─ RequireLvl    (TextLabel – "Level 60")
--     ├─ RequireStage  (TextLabel – "Stage 5")
--     ├─ RequireCash   (TextLabel – "$50,000")
--     ├─ RebirthButton (TextButton)
--     └─ XButton   (TextButton)

local RebirthModule = {}
RebirthModule.__index = RebirthModule

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e9 then return ("$%.2fb"):format(n / 1e9)
	elseif n >= 1e6 then return ("$%.2fm"):format(n / 1e6)
	elseif n >= 1e3 then return ("$%.2fk"):format(n / 1e3)
	end
	return "$" .. tostring(n)
end

local function getState(ctx: any): any
	return (ctx.State and ctx.State.State) or {}
end

-- ── Eligibility ───────────────────────────────────────────────────────────────

function RebirthModule:_checkEligible(): boolean
	local ctx  = self._ctx
	local cfg  = ctx.Config.ProgressionConfig
	if not cfg then return false end

	local req  = cfg.Rebirth.Requirement
	local s    = getState(ctx)
	local prog = s.Progression or {}
	local curr = s.Currency   or {}

	local lvl   = prog.Level          or 0
	local stage = prog.StageUnlocked  or 0
	local cash  = curr.Cash           or 0

	return lvl >= req.MinLevel and stage >= req.MinStage and cash >= (req.CashCost or 0)
end

-- ── Refresh ───────────────────────────────────────────────────────────────────

function RebirthModule:_refresh(state: any)
	if not self._frame then return end
	local ctx   = self._ctx
	local cfg   = ctx.Config.ProgressionConfig
	if not cfg  then return end

	local s      = getState(ctx)
	local prog   = s.Progression or {}
	local curr   = s.Currency    or {}
	local reb    = prog.Rebirths  or 0
	local level  = prog.Level     or 0
	local stage  = prog.StageUnlocked or 0
	local cash   = curr.Cash      or 0

	local req    = cfg.Rebirth.Requirement
	local scale  = cfg.Rebirth.Scaling

	local nextCashBonus = math.floor(scale.CashMultiplierPerRebirth * (reb + 1) * 100 + 0.5)

	local function setLabel(name, text)
		local lbl = find(self._frame, name) :: TextLabel?
		if lbl then lbl.Text = text end
	end

	setLabel("RebirthCount",   "Rebirths: " .. tostring(reb))
	setLabel("NextMultiplier", "+" .. tostring(nextCashBonus) .. "% Cash Bonus")
	setLabel("RequireLvl",     "Level: " .. tostring(level) .. " / " .. tostring(req.MinLevel))
	setLabel("RequireStage",   "Stage: " .. tostring(stage) .. " / " .. tostring(req.MinStage))
	setLabel("RequireCash",    "Cash: $" .. fmt(cash) .. " / $" .. fmt(req.CashCost or 0))

	-- Enable/disable rebirth button
	local eligible   = self:_checkEligible()
	local rebirthBtn = find(self._frame, "RebirthButton") :: TextButton?
	if rebirthBtn then
		rebirthBtn.Active = eligible
		rebirthBtn.Text   = eligible and "REBIRTH!" or "Requirements not met"
	end
end

-- ── Rebirth action ────────────────────────────────────────────────────────────

function RebirthModule:_onRebirth()
	local ctx = self._ctx

	if not self:_checkEligible() then
		local btn = find(self._frame, "RebirthButton")
		if btn then ctx.UI.Effects.Shake(btn, 7, 0.35, 0.12) end
		ctx.UI.Sound:Play("cartoon_pop2")
		return
	end

	-- Confirm via AlertModule
	local AlertMod = require(script.Parent.AlertModule)
	AlertMod:Show({
		title   = "Rebirth?",
		message = "This will reset your cash, level, gates, and weapons. You'll earn a permanent cash and XP bonus!",
		confirm = "Rebirth!",
		cancel  = "Cancel",
		callback = function(confirmed: boolean)
			if not confirmed then return end
			task.spawn(function()
				local rf = ctx.Net:GetFunction("RebirthAction")
				local ok, result = pcall(function()
					return rf:InvokeServer({ action = "rebirth" })
				end)

				if ok and type(result) == "table" and result.ok then
					ctx.UI.Sound:Play("cartoon_pop")
					if ctx.Router then ctx.Router:Close("Rebirth") end
				else
					local reason = (type(result) == "table" and result.reason) or "Server error"
					ctx.UI.Effects.Shake(self._frame, 6, 0.3, 0.12)
					warn("[RebirthModule] Rebirth failed:", reason)
				end
			end)
		end,
	})
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function RebirthModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Rebirth")
	if not self._frame then warn("[RebirthModule] Frame 'Rebirth' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("Rebirth") end
		end))
	end

	local rebirthBtn = find(self._frame, "RebirthButton")
	if rebirthBtn then
		self._janitor:Add((rebirthBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onRebirth()
		end))
	end

	self:_refresh({})
end

function RebirthModule:Start()
	if not self._frame then return end
	self._janitor:Add(self._ctx.State.Changed:Connect(function(state, _)
		self:_refresh(state)
	end))
end

function RebirthModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return RebirthModule
