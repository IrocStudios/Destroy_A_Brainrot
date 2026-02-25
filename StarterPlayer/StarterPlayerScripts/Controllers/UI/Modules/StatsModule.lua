--!strict
-- StatsModule.lua  |  Frame: Stats
-- Shows player lifetime stats. Updates live whenever state changes.
--
-- WIRE-UP (Studio frame hierarchy):
--   Stats [Frame]
--     Canvas [CanvasGroup]
--       Header [Frame] > Title [TextLabel]
--     Container [ScrollingFrame]
--       TotalCash [Frame] > Main > Frame > Title [TextLabel] > Title [TextLabel shadow]
--       Rebirths  [Frame] > Main > Frame > Title [TextLabel] > Title [TextLabel shadow]
--       Gifts     [Frame] > Main > Frame > Title [TextLabel] > Title [TextLabel shadow]
--       Captured  [Frame] > Main > Frame > Title [TextLabel] > Title [TextLabel shadow]
--       Deaths    [Frame] > Main > Frame > Title [TextLabel] > Title [TextLabel shadow]
--     XButton [TextButton]

local StatsModule = {}
StatsModule.__index = StatsModule

-- Number formatting — project standard: lowercase, 2 decimal places
local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e9 then return ("$%.2fb"):format(n / 1e9)
	elseif n >= 1e6 then return ("$%.2fm"):format(n / 1e6)
	elseif n >= 1e3 then return ("$%.2fk"):format(n / 1e3)
	end
	return "$" .. tostring(n)
end

local function fmtInt(n: number): string
	return tostring(math.floor(n or 0))
end

-- ── Stat row definitions ──────────────────────────────────────────────────
-- Each entry maps a frame name to:  { prefix, formatter, getValue(state) }

local STAT_ROWS = {
	{
		frame   = "TotalCash",
		prefix  = "Total Cash: ",
		format  = fmt,
		getValue = function(s: any): number
			local stats = s.Stats or {}
			return tonumber(stats.TotalCashEarned) or 0
		end,
	},
	{
		frame   = "Rebirths",
		prefix  = "Rebirths: ",
		format  = fmtInt,
		getValue = function(s: any): number
			local prog = s.Progression or {}
			return tonumber(prog.Rebirths) or 0
		end,
	},
	{
		frame   = "Gifts",
		prefix  = "Gifts Opened: ",
		format  = fmtInt,
		getValue = function(s: any): number
			local rewards = s.Rewards or {}
			local gifts = rewards.Gifts or {}
			local nextIdx = tonumber(gifts.NextIndex) or 1
			return math.max(0, nextIdx - 1)
		end,
	},
	{
		frame   = "Captured",
		prefix  = "Captured: ",
		format  = fmtInt,
		getValue = function(s: any): number
			local idx = s.Index or {}
			local discovered = idx.BrainrotsDiscovered
			if type(discovered) ~= "table" then return 0 end
			local count = 0
			for _ in pairs(discovered) do
				count += 1
			end
			return count
		end,
	},
	{
		frame   = "Deaths",
		prefix  = "Deaths: ",
		format  = fmtInt,
		getValue = function(s: any): number
			local stats = s.Stats or {}
			return tonumber(stats.Deaths) or 0
		end,
	},
}

-- ── Helpers ────────────────────────────────────────────────────────────────

-- Navigate: StatRow > Main > Frame > Title (TextLabel)
-- Shadow:   Title > Title (TextLabel)
local function findLabel(statFrame: Instance): (TextLabel?, TextLabel?)
	local main = statFrame:FindFirstChild("Main")
	if not main then return nil, nil end
	local inner = main:FindFirstChild("Frame")
	if not inner then return nil, nil end
	local title = inner:FindFirstChild("Title")
	if not title or not title:IsA("TextLabel") then return nil, nil end
	local shadow = title:FindFirstChild("Title")
	if shadow and shadow:IsA("TextLabel") then
		return title, shadow
	end
	return title, nil
end

-- ── Lifecycle ──────────────────────────────────────────────────────────────

function StatsModule:_refresh()
	if not self._frame then return end
	local state = (self._ctx.State and self._ctx.State.State) or {}

	for _, row in STAT_ROWS do
		local statFrame = self._container and self._container:FindFirstChild(row.frame)
		if not statFrame then continue end

		local value = row.getValue(state)
		local text = row.prefix .. row.format(value)

		local label, shadow = findLabel(statFrame)
		if label then
			label.Text = text
		end
		if shadow then
			shadow.Text = text
		end
	end
end

function StatsModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Stats")
	if not self._frame then warn("[StatsModule] Frame 'Stats' not found") return end

	self._container = self._frame:FindFirstChild("Container")

	-- Close button
	local closeBtn = self._frame:FindFirstChild("XButton")
	if closeBtn and closeBtn:IsA("GuiButton") then
		self._janitor:Add(closeBtn.MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("Stats") end
		end))
	end

	-- Initial fill
	self:_refresh()
end

function StatsModule:Start()
	if not self._frame then return end

	-- Update on every state change
	self._janitor:Add(self._ctx.State.Changed:Connect(function(_state, _deltas)
		self:_refresh()
	end))
end

function StatsModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return StatsModule
