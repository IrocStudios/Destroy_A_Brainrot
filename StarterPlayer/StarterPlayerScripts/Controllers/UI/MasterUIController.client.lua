--!strict
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LOCAL_PLAYER = Players.LocalPlayer

local function findRootGui(playerGui: PlayerGui): ScreenGui
	-- Wait for StarterGui contents to replicate into PlayerGui.
	-- Without WaitForChild, the script can boot before the GUI exists.
	for _, name in ipairs({ "GUI", "BrainrotGui", "MainGui" }) do
		local g = playerGui:WaitForChild(name, 10)
		if g and g:IsA("ScreenGui") then
			print("[MasterUIController] Found RootGui via WaitForChild: " .. name)
			return g :: ScreenGui
		end
	end
	-- Fall back to the first ScreenGui already present
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") then
			print("[MasterUIController] Fallback RootGui: " .. child.Name)
			return child :: ScreenGui
		end
	end
	-- Last resort: create one so the rest of the system doesn't error
	warn("[MasterUIController] No ScreenGui found after waiting – creating empty GUI")
	local sg = Instance.new("ScreenGui")
	sg.Name = "GUI"
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = playerGui
	return sg
end

local function findFramesFolder(rootGui: ScreenGui): Instance?
	-- 1. Direct child named "Frames"
	local f = rootGui:FindFirstChild("Frames")
	if f then return f end
	-- 2. Any Frame/Folder child named "Frames" deeper
	for _, child in ipairs(rootGui:GetChildren()) do
		if child.Name == "Frames" then return child end
	end
	return nil
end

local function loadConfig(): any
	local out = {}
	local cfgFolder = ReplicatedStorage:FindFirstChild("Shared") and
		ReplicatedStorage.Shared:FindFirstChild("Config")
	if not cfgFolder then return out end

	for _, child in ipairs(cfgFolder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, mod = pcall(require, child)
			if ok then
				out[child.Name] = mod
			else
				warn(("[MasterUIController] Failed to require Config.%s: %s"):format(child.Name, tostring(mod)))
			end
		end
	end
	return out
end

local function loadNet(): any?
	local netRoot = ReplicatedStorage:FindFirstChild("Shared")
		and ReplicatedStorage.Shared:FindFirstChild("Net")
	if not netRoot then return nil end
	local remoteService = netRoot:FindFirstChild("RemoteService")
	if not remoteService or not remoteService:IsA("ModuleScript") then return nil end

	local ok, rs = pcall(require, remoteService)
	if not ok then
		warn("[MasterUIController] Failed to require RemoteService:", rs)
		return nil
	end
	return rs
end

-- Gets StateController (the client state manager loaded by ClientBoot/ClientLoader).
-- Requires it directly from ReplicatedStorage so both scripts share the same module table.
local function loadPlayerState(): any
	local ok, ctrl = pcall(function()
		return require(
			ReplicatedStorage
				:WaitForChild("Client")
				:WaitForChild("Controllers")
				:WaitForChild("StateController")
		)
	end)
	if ok and type(ctrl) == "table" then
		return ctrl
	end
	warn("[MasterUIController] Could not load StateController; State will be empty.")
	return {}
end

local function getModulesFolder(): Folder?
	-- script.Parent is the "UI" folder at runtime (cloned into PlayerScripts).
	-- Modules/ is a direct child of UI/. This is the reliable path.
	local ui = script.Parent
	local m = ui:FindFirstChild("Modules")
	if m and m:IsA("Folder") then return m :: Folder end

	-- Fallback: walk through PlayerScripts in case folder depth differs
	local ps = LOCAL_PLAYER:FindFirstChild("PlayerScripts")
	if ps then
		local ctrl = ps:FindFirstChild("Controllers")
		if ctrl then
			local uiF = ctrl:FindFirstChild("UI")
			if uiF then
				local m2 = uiF:FindFirstChild("Modules")
				if m2 and m2:IsA("Folder") then return m2 :: Folder end
			end
		end
	end
	return nil
end

local function requireAllModules(modulesFolder: Folder): { [string]: any }
	local loaded: { [string]: any } = {}
	for _, child in ipairs(modulesFolder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, mod = pcall(require, child)
			if ok then
				loaded[child.Name] = mod
			else
				warn(("[MasterUIController] Failed to require module %s: %s"):format(child.Name, tostring(mod)))
			end
		end
	end
	return loaded
end

-- Modules that must Init/Start in order before others
local PRIORITY_MODULES = { "AlertModule", "GiftModule" }

local function startModules(mods: { [string]: any }, ctx: any)
	-- Init priority modules first (others may depend on them)
	for _, name in ipairs(PRIORITY_MODULES) do
		local mod = mods[name]
		if mod and type(mod.Init) == "function" then
			local ok, err = pcall(function() mod:Init(ctx) end)
			if not ok then
				warn(("[MasterUIController] %s:Init failed: %s"):format(name, tostring(err)))
			end
		end
	end
	-- Init all remaining modules
	for name, mod in pairs(mods) do
		if type(mod) == "table" and type(mod.Init) == "function" then
			-- Skip already-initialized priority modules
			local alreadyDone = false
			for _, p in ipairs(PRIORITY_MODULES) do
				if p == name then alreadyDone = true; break end
			end
			if not alreadyDone then
				local ok, err = pcall(function() mod:Init(ctx) end)
				if not ok then
					warn(("[MasterUIController] %s:Init failed: %s"):format(name, tostring(err)))
				end
			end
		end
	end

	-- Start all modules concurrently (each in its own thread)
	for name, mod in pairs(mods) do
		if type(mod) == "table" and type(mod.Start) == "function" then
			task.spawn(function()
				local ok, err = pcall(function() mod:Start() end)
				if not ok then
					warn(("[MasterUIController] %s:Start failed: %s"):format(name, tostring(err)))
				end
			end)
		end
	end
end

local function bindCoreUISystems(UI: any, rootGui: Instance, framesFolder: Instance?): any
	if UI.ButtonFX and type(UI.ButtonFX.Bind) == "function" then
		pcall(function() UI.ButtonFX:Bind(rootGui) end)
	end

	if UI.RichText and type(UI.RichText.Bind) == "function" then
		pcall(function() UI.RichText:Bind(rootGui) end)
	end

	local router = nil
	if UI.Frames and type(UI.Frames.new) == "function" and framesFolder then
		local ok, r = pcall(function()
			return UI.Frames.new({ FramesFolder = framesFolder })
		end)
		if ok then
			router = r
			-- Reset all frames to scale 0 before any module opens them
			if router and type(router.ResetAll) == "function" then
				pcall(function() router:ResetAll() end)
			end
			if router and type(router.BindButtons) == "function" then
				pcall(function() router:BindButtons(rootGui) end)
			end
		else
			warn("[MasterUIController] Failed to create Frame router:", r)
		end
	end

	return router
end

-- ── Boot ──────────────────────────────────────────────────────────────────────

print("[MasterUIController] Booting…")

local playerGui    = LOCAL_PLAYER:WaitForChild("PlayerGui")
local rootGui      = findRootGui(playerGui)
local framesFolder = findFramesFolder(rootGui)

print("[MasterUIController] RootGui: " .. rootGui:GetFullName() .. " [" .. rootGui.ClassName .. "]")
if framesFolder then
	print("[MasterUIController] FramesFolder: " .. framesFolder:GetFullName() .. " [" .. framesFolder.ClassName .. "]")
else
	warn("[MasterUIController] FramesFolder not found – frame-based modules will be skipped")
end

local UILibModule = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UI"):WaitForChild("UILibrary")
local UI = require(UILibModule)
if type(UI) == "table" and type(UI.Init) == "function" then
	pcall(function() UI:Init() end)
end

local router = bindCoreUISystems(UI, rootGui, framesFolder)
local config  = loadConfig()
local net     = loadNet()
local state   = loadPlayerState()

local ctx = {
	UI           = UI,
	Router       = router,
	Net          = net,
	Config       = config,
	State        = state,
	Player       = LOCAL_PLAYER,
	PlayerGui    = playerGui,
	RootGui      = rootGui,
	FramesFolder = framesFolder,
}

print("[MasterUIController] Config keys loaded: " .. tostring(#config > 0 or next(config) ~= nil))
print("[MasterUIController] Net loaded: " .. tostring(net ~= nil))
print("[MasterUIController] State loaded: " .. tostring(state ~= nil) .. " (has Changed: " .. tostring(type(state) == "table" and state.Changed ~= nil) .. ")")
print("[MasterUIController] Router created: " .. tostring(router ~= nil))

local modulesFolder = getModulesFolder()
if not modulesFolder then
	warn("[MasterUIController] Modules folder not found – expected StarterPlayerScripts/Controllers/UI/Modules/")
else
	print("[MasterUIController] Modules folder: " .. modulesFolder:GetFullName())
	local modules = requireAllModules(modulesFolder)
	local count = 0
	for name, _ in pairs(modules) do
		count += 1
		print("[MasterUIController] Loaded module: " .. name)
	end
	startModules(modules, ctx)
	print(("[MasterUIController] Boot complete – %d modules loaded"):format(count))
end
