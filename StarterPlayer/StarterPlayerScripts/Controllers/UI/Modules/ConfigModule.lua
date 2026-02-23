--!strict
-- ConfigModule.lua  |  Frame: Config
-- Settings panel: music toggle, SFX toggle, UI scale slider.
-- Toggles apply immediately and sync to server via state delta.
--
-- WIRE-UP NOTES:
--   Frame "Config"
--     ├─ MusicToggle    (TextButton – shows "ON"/"OFF")
--     ├─ SFXToggle      (TextButton – shows "ON"/"OFF")
--     ├─ ScaleSlider    (Frame containing a draggable knob – optional)
--     └─ XButton    (TextButton)

local SoundService = game:GetService("SoundService")

local ConfigModule = {}
ConfigModule.__index = ConfigModule

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function getSettings(ctx: any): any
	local s = (ctx.State and ctx.State.State) or {}
	return s.Settings or {}
end

-- ── Apply settings ────────────────────────────────────────────────────────────

local function applyMusic(on: boolean)
	-- Mute/unmute the Music group in SoundService (adjust as needed)
	local musicGroup = SoundService:FindFirstChild("Music")
	if musicGroup then
		musicGroup.Volume = on and 1 or 0
	end
end

local function applySFX(on: boolean)
	local sfxGroup = SoundService:FindFirstChild("SFX")
	if sfxGroup then
		sfxGroup.Volume = on and 1 or 0
	end
end

-- ── Refresh labels ────────────────────────────────────────────────────────────

function ConfigModule:_refresh(state: any)
	if not self._frame then return end
	local settings = getSettings(self._ctx)

	local musicBtn = find(self._frame, "MusicToggle") :: TextButton?
	local sfxBtn   = find(self._frame, "SFXToggle")   :: TextButton?

	if musicBtn then
		local on = settings.MusicOn ~= false -- default on
		musicBtn.Text = "Music: " .. (on and "ON" or "OFF")
	end

	if sfxBtn then
		local on = settings.SFXOn ~= false -- default on
		sfxBtn.Text = "SFX: " .. (on and "ON" or "OFF")
	end
end

-- ── Toggles ───────────────────────────────────────────────────────────────────

function ConfigModule:_toggleMusic()
	local ctx    = self._ctx
	local settings = getSettings(ctx)
	local newVal = not (settings.MusicOn ~= false)

	applyMusic(newVal)

	-- Persist to server / DataService profile
	task.spawn(function()
		local rf = ctx.Net and ctx.Net:GetFunction("SettingsAction")
		if rf then
			pcall(function() rf:InvokeServer({ setting = "Music", value = newVal }) end)
		end
	end)

	self:_refresh({})
end

function ConfigModule:_toggleSFX()
	local ctx    = self._ctx
	local settings = getSettings(ctx)
	local newVal = not (settings.SFXOn ~= false)

	applySFX(newVal)

	task.spawn(function()
		local rf = ctx.Net and ctx.Net:GetFunction("SettingsAction")
		if rf then
			pcall(function() rf:InvokeServer({ setting = "SFX", value = newVal }) end)
		end
	end)

	self:_refresh({})
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function ConfigModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Config")
	if not self._frame then warn("[ConfigModule] Frame 'Config' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("Config") end
		end))
	end

	local musicBtn = find(self._frame, "MusicToggle")
	if musicBtn then
		self._janitor:Add((musicBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_toggleMusic()
		end))
	end

	local sfxBtn = find(self._frame, "SFXToggle")
	if sfxBtn then
		self._janitor:Add((sfxBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_toggleSFX()
		end))
	end

	self:_refresh({})
end

function ConfigModule:Start()
	if not self._frame then return end
	-- Apply persisted settings on initial state snapshot
	self._janitor:Add(self._ctx.State.Changed:Connect(function(state, _)
		local settings = getSettings(self._ctx)
		applyMusic(settings.MusicOn ~= false)
		applySFX(settings.SFXOn ~= false)
		self:_refresh(state)
	end))
end

function ConfigModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return ConfigModule
