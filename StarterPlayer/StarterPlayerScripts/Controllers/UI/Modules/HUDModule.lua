--!strict
-- HUDModule.lua  |  Frame: HUD  (persistent overlay)
-- Manages the main heads-up display:
--   • Cash / Level / XP bar always visible at the top
--   • Navigation buttons that open other frames
--   • Wires named buttons → router:Toggle(frameName)
--
-- WIRE-UP NOTES (create these in the ScreenGui, NOT inside Frames/):
--   Frame "HUD"  (NOT inside Frames/ – always visible)
--     ├─ CashLabel      (TextLabel – "$12,345")
--     ├─ LevelLabel     (TextLabel – "Lv 7")
--     ├─ XPLabel        (TextLabel – "XP 1234/5000")  [optional]
--     ├─ XPBar          (Frame    – width scales with XP progress)  [optional]
--     ├─ RebirthsLabel  (TextLabel)  [optional]
--     └─ NavBar (Frame or Folder)
--           ├─ ShopBtn       → opens "Shop"
--           ├─ IndexBtn      → opens "Index"
--           ├─ StatsBtn      → opens "Stats"
--           ├─ CodesBtn      → opens "Codes"
--           ├─ SettingsBtn   → opens "Config"
--           ├─ GearShopBtn   → opens "GearShop"
--           ├─ SpeedShopBtn  → opens "SpeedShop"
--           ├─ RebirthBtn    → opens "Rebirth"
--           ├─ DailyBtn      → opens "DailyGifts"
--           └─ GiftsBtn      → opens "Gifts"
--
-- Also supports any button anywhere in the ScreenGui that has a
-- "Frame" StringAttribute – the router's BindButtons() already handles those.
-- This module adds the *named-button* fallback for easier Studio setup.

local HUDModule = {}
HUDModule.__index = HUDModule

-- Maps Studio button name → frame name to toggle.
-- Covers both the real HUD button names (LeftButtons / RightButtons) and the
-- legacy "Btn"-suffixed names in case the Studio setup used those instead.
local NAV_MAP: { [string]: string } = {
	-- Real HUD button names (as they appear in LeftButtons / RightButtons)
	Shop         = "Shop",
	Config       = "Config",
	Rebirth      = "Rebirth",
	Gifts        = "Gifts",
	Index        = "Index",
	Stats        = "Stats",
	DailyGifts   = "DailyGifts",
	Codes        = "Codes",
	OPBrainrot   = "OPBrainrot",
	GearShop     = "GearShop",
	SpeedShop    = "SpeedShop",
	-- Legacy "Btn"-suffixed fallbacks
	ShopBtn      = "Shop",
	IndexBtn     = "Index",
	StatsBtn     = "Stats",
	CodesBtn     = "Codes",
	SettingsBtn  = "Config",
	GearShopBtn  = "GearShop",
	SpeedShopBtn = "SpeedShop",
	RebirthBtn   = "Rebirth",
	DailyBtn     = "DailyGifts",
	GiftsBtn     = "Gifts",
}

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
	if n >= 1e3 then return ("%.1fK"):format(n / 1e3) end
	return tostring(n)
end

-- ── Init ──────────────────────────────────────────────────────────────────────
function HUDModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()

	-- HUD lives directly in the ScreenGui, not inside FramesFolder
	-- Try ScreenGui root first, then FramesFolder as fallback
	local root = ctx.RootGui
	self._hud = root and (root:FindFirstChild("HUD") or
		(ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("HUD")))

	if not self._hud then
		warn("[HUDModule] Frame 'HUD' not found – create it directly in the ScreenGui.")
		return
	end

	-- Make HUD always visible (it is NOT managed by the router)
	self._hud.Visible = true

	-- Wire named nav buttons
	if ctx.Router then
		for btnName, frameName in pairs(NAV_MAP) do
			local btn = find(self._hud, btnName)
			if btn and btn:IsA("GuiButton") then
				self._janitor:Add((btn :: GuiButton).MouseButton1Click:Connect(function()
					ctx.Router:Toggle(frameName)
				end))
			end
		end
	end

	-- Initial display update
	self:_refresh(ctx.State and ctx.State.State or {})
end

-- ── Start ─────────────────────────────────────────────────────────────────────
function HUDModule:Start()
	if not self._hud then return end
	local ctx = self._ctx

	self._janitor:Add(ctx.State.Changed:Connect(function(state: any, _deltas: any)
		self:_refresh(state)
	end))
end

-- ── Refresh ───────────────────────────────────────────────────────────────────
function HUDModule:_refresh(state: any)
	if not self._hud then return end
	local ctx = self._ctx

	local currency    = (type(state) == "table" and state.Currency)    or {}
	local progression = (type(state) == "table" and state.Progression) or {}

	local cash     = tonumber(currency.Cash)               or 0
	local level    = tonumber(progression.Level)           or 1
	local xp       = tonumber(progression.XP)              or 0
	local rebirths = tonumber(progression.Rebirths)        or 0

	-- Cash label
	local cashLbl = find(self._hud, "CashLabel") :: TextLabel?
	if cashLbl then cashLbl.Text = "$" .. fmt(cash) end

	-- Level label
	local lvlLbl = find(self._hud, "LevelLabel") :: TextLabel?
	if lvlLbl then lvlLbl.Text = "Lv " .. tostring(level) end

	-- Rebirths label
	local rebLbl = find(self._hud, "RebirthsLabel") :: TextLabel?
	if rebLbl then rebLbl.Text = "⟳ " .. tostring(rebirths) end

	-- XP label + bar
	local xpLbl = find(self._hud, "XPLabel") :: TextLabel?
	local progCfg = ctx.Config and ctx.Config.ProgressionConfig
	local xpNeeded = self:_xpForLevel(level, progCfg)

	if xpLbl then
		xpLbl.Text = ("XP %s / %s"):format(fmt(xp), fmt(xpNeeded))
	end

	local xpBar = find(self._hud, "XPBar") :: Frame?
	if xpBar then
		local ratio = (xpNeeded > 0) and math.clamp(xp / xpNeeded, 0, 1) or 0
		ctx.UI.Tween:Play(xpBar, { Size = UDim2.new(ratio, 0, 1, 0) }, 0.3)
	end
end

-- Derive XP needed for next level from ProgressionConfig or a simple formula
function HUDModule:_xpForLevel(level: number, cfg: any): number
	if cfg and type(cfg.XPCurve) == "table" then
		local curve = cfg.XPCurve
		local base   = tonumber(curve.Base)   or 100
		local growth = tonumber(curve.Growth) or 50
		local power  = tonumber(curve.Power)  or 1.2
		-- Override table: specific levels with exact XP cost
		if type(curve.Overrides) == "table" and curve.Overrides[level] then
			return tonumber(curve.Overrides[level]) or 0
		end
		return math.floor(base + growth * (level ^ power))
	end
	-- Fallback simple curve
	return math.floor(100 * (1.15 ^ (level - 1)))
end

-- ── Destroy ───────────────────────────────────────────────────────────────────
function HUDModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return HUDModule
