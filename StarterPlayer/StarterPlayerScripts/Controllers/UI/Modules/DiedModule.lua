--!strict
-- DiedModule.lua  |  Frame: Died
-- Triggered by server Notify event on player death. Shows respawn countdown
-- and last-run stats. Auto-closes when the character respawns.
--
-- WIRE-UP NOTES:
--   Frame "Died"
--     ├─ TimerLabel    (TextLabel – countdown)
--     ├─ KillsLabel    (TextLabel)
--     ├─ CashLabel     (TextLabel)
--     └─ RespawnButton (TextButton – optional manual respawn)

local Players    = game:GetService("Players")
local DiedModule = {}
DiedModule.__index = DiedModule

local RESPAWN_SECONDS = 5

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e6 then return ("%.1fM"):format(n/1e6)
	elseif n >= 1e3 then return ("%.1fK"):format(n/1e3)
	end
	return tostring(n)
end

-- ── Show / hide ───────────────────────────────────────────────────────────────

function DiedModule:_show(payload: any)
	if not self._frame then return end
	local ctx = self._ctx

	local killsLbl = find(self._frame, "KillsLabel") :: TextLabel?
	local cashLbl  = find(self._frame, "CashLabel")  :: TextLabel?

	if killsLbl then killsLbl.Text = "Kills: " .. fmt(payload.kills or 0) end
	if cashLbl  then cashLbl.Text  = "Cash: $" .. fmt(payload.cash  or 0) end

	if ctx.Router then ctx.Router:Open("Died") end
	ctx.UI.Sound:Play("cartoon_pop2")

	-- Start countdown
	if self._countdownThread then task.cancel(self._countdownThread) end
	self._countdownThread = task.spawn(function()
		local timer = find(self._frame, "TimerLabel") :: TextLabel?
		local t = RESPAWN_SECONDS
		while t > 0 do
			if timer then timer.Text = "Respawning in " .. tostring(t) .. "..." end
			task.wait(1)
			t -= 1
		end
		if timer then timer.Text = "Respawning..." end
	end)
end

function DiedModule:_hide()
	if not self._frame then return end
	if self._countdownThread then
		task.cancel(self._countdownThread)
		self._countdownThread = nil
	end
	if self._ctx.Router then self._ctx.Router:Close("Died") end
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function DiedModule:Init(ctx: any)
	self._ctx              = ctx
	self._janitor          = ctx.UI.Cleaner.new()
	self._countdownThread  = nil :: thread?
	self._frame            = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Died")
	if not self._frame then warn("[DiedModule] Frame 'Died' not found") return end

	self._frame.Visible = false

	-- Optional manual respawn button
	local respawnBtn = find(self._frame, "RespawnButton")
	if respawnBtn then
		self._janitor:Add((respawnBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_hide()
		end))
	end
end

function DiedModule:Start()
	if not self._frame then return end
	local ctx    = self._ctx
	local player = ctx.Player

	-- Listen for death notification from server
	local notifyRE = ctx.Net:GetEvent("Notify")
	self._janitor:Add(notifyRE.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.type == "died" then
			self:_show(payload)
		end
	end))

	-- Auto-close when character respawns
	self._janitor:Add(player.CharacterAdded:Connect(function()
		self:_hide()
	end))
end

function DiedModule:Destroy()
	if self._countdownThread then task.cancel(self._countdownThread) end
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return DiedModule
