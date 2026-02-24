--!strict
-- StatsModule.lua  |  Frame: Stats
-- Shows player lifetime stats: kills, cash, discoveries, rebirths.
-- Updates live whenever state changes.
--
-- WIRE-UP NOTES:
--   Frame "Stats"
--     ├─ KillsLabel       (TextLabel)
--     ├─ CashLabel        (TextLabel)
--     ├─ DiscoveriesLabel (TextLabel)
--     ├─ RebirthsLabel    (TextLabel)
--     ├─ LevelLabel       (TextLabel)
--     └─ XButton      (TextButton)

local StatsModule = {}
StatsModule.__index = StatsModule

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e9 then return ("%.1fB"):format(n/1e9)
	elseif n >= 1e6 then return ("%.1fM"):format(n/1e6)
	elseif n >= 1e3 then return ("%.1fK"):format(n/1e3)
	end
	return tostring(n)
end

local function getState(ctx: any): any
	return (ctx.State and ctx.State.State) or {}
end

function StatsModule:_refresh(state: any)
	if not self._frame then return end
	local s    = getState(self._ctx)
	local prog = s.Progression or {}
	local curr = s.Currency    or {}
	local idx  = s.Index       or {}

	-- BrainrotsKilled is a map {[brainrotId] = count} — sum all values
	local kills = 0
	if type(idx.BrainrotsKilled) == "table" then
		for _, count in pairs(idx.BrainrotsKilled) do
			kills += (tonumber(count) or 0)
		end
	elseif type(idx.BrainrotsKilled) == "number" then
		kills = idx.BrainrotsKilled
	end

	-- BrainrotsDiscovered is a map {[brainrotId] = true} — count keys
	local discoveries = 0
	if type(idx.BrainrotsDiscovered) == "table" then
		for _ in pairs(idx.BrainrotsDiscovered) do
			discoveries += 1
		end
	end
	local cash     = curr.Cash          or 0
	local rebirths = prog.Rebirths      or 0
	local level    = prog.Level         or 0

	local function set(name, text)
		local lbl = find(self._frame, name) :: TextLabel?
		if lbl then
			local prev = lbl.Text
			lbl.Text = text
			-- Pulse label briefly when value changes
			if prev ~= text then
				local h = self._ctx.UI.Effects.Pulse(lbl, 4, 0.05)
				task.delay(0.5, function() h:Destroy() end)
			end
		end
	end

	set("KillsLabel",       "Kills: "        .. fmt(kills))
	set("CashLabel",        "Cash Earned: $" .. fmt(cash))
	set("DiscoveriesLabel", "Discovered: "   .. tostring(discoveries))
	set("RebirthsLabel",    "Rebirths: "     .. tostring(rebirths))
	set("LevelLabel",       "Level: "        .. tostring(level))
end

function StatsModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Stats")
	if not self._frame then warn("[StatsModule] Frame 'Stats' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("Stats") end
		end))
	end

	self:_refresh({})
end

function StatsModule:Start()
	if not self._frame then return end
	self._janitor:Add(self._ctx.State.Changed:Connect(function(state, _)
		self:_refresh(state)
	end))
end

function StatsModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return StatsModule
