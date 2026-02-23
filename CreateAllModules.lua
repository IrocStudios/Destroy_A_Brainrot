local SG  = game:GetService("StarterGui")
local SP  = game:GetService("StarterPlayer")
local SS  = game:GetService("ServerStorage")
local RS  = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local created = {}
local skipped = {}

local function ef(parent, name)
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then return f end
	if f then f:Destroy() end
	local n = Instance.new("Folder")
	n.Name = name
	n.Parent = parent
	return n
end

local function em(parent, name)
	local e = parent:FindFirstChild(name)
	if e and e:IsA("ModuleScript") then
		table.insert(skipped, e:GetFullName())
		return e
	end
	if e then e:Destroy() end
	local m = Instance.new("ModuleScript")
	m.Name = name
	m.Source = "return {}"
	m.Parent = parent
	table.insert(created, m:GetFullName())
	return m
end

local function els(parent, name)
	local e = parent:FindFirstChild(name)
	if e and e:IsA("LocalScript") then
		table.insert(skipped, e:GetFullName())
		return e
	end
	if e then e:Destroy() end
	local s = Instance.new("LocalScript")
	s.Name = name
	s.Source = ""
	s.Parent = parent
	table.insert(created, s:GetFullName())
	return s
end

local function es(parent, name)
	local e = parent:FindFirstChild(name)
	if e and e:IsA("Script") then
		table.insert(skipped, e:GetFullName())
		return e
	end
	if e then e:Destroy() end
	local s = Instance.new("Script")
	s.Name = name
	s.Source = ""
	s.Disabled = true
	s.Parent = parent
	table.insert(created, s:GetFullName())
	return s
end

es(SSS, "ServerBoot")

local svcs = ef(SS, "Services")
local serviceNames = {
	"ServerLoader", "NetService",   "DataService",       "ProfileService",
	"BrainrotService", "CombatService", "AIService",     "InventoryService",
	"ShopService",     "GateService",   "RewardService", "ProgressionService",
	"EconomyService",  "MoneyService",  "IndexService",  "RarityService",
	"MarketplaceService", "AdminService", "WeaponService", "AnalyticsService",
	"CodesService",
}
for _, n in ipairs(serviceNames) do em(svcs, n) end

local client     = ef(RS, "Client")
em(client, "ClientLoader")
local clientCtrl = ef(client, "Controllers")
local clientControllerNames = {
	"StateController",       "ShopController",    "RebirthController",
	"SettingsController",    "IndexController",   "DailyRewardController",
	"GiftController",        "PromptController",  "StatsController",
	"WeaponClientController","BrainrotClientController",
}
for _, n in ipairs(clientControllerNames) do em(clientCtrl, n) end

local shared  = ef(RS,     "Shared")
local netDir  = ef(shared, "Net")
em(netDir, "NetIds")
em(netDir, "RemoteService")

local cfgDir = ef(shared, "Config")
local configNames = {
	"BrainrotConfig", "RarityConfig",     "WeaponConfig",
	"ProgressionConfig", "ShopConfig",    "EconomyConfig",
	"PersonalityConfig",
}
for _, n in ipairs(configNames) do em(cfgDir, n) end

local utilDir = ef(shared, "Util")
em(utilDir, "Signal")
em(utilDir, "Janitor")

local uiDir  = ef(shared, "UI")
local uiLib  = em(uiDir,  "UILibrary")
local core   = ef(uiLib,  "Core")
local sys    = ef(uiLib,  "Systems")
local coreNames = { "Cleaner", "Signal", "Sound", "Tween", "Util" }
local sysNames  = { "ButtonFX", "Effects", "Frames", "RichText" }
for _, n in ipairs(coreNames) do em(core, n) end
for _, n in ipairs(sysNames)  do em(sys,  n) end

local sps        = SP:FindFirstChild("StarterPlayerScripts")
if not sps then
	sps = Instance.new("StarterPlayerScripts")
	sps.Parent = SP
	table.insert(created, sps:GetFullName())
end

els(sps, "ClientBoot")

local ctrl = ef(sps, "Controllers")
local ui   = ef(ctrl, "UI")
els(ui, "MasterUIController")

local modsDir = ef(ui, "Modules")
local moduleNames = {
	"AlertModule",     "CodesModule",     "ConfigModule",    "CommandModule",
	"DailyGiftsModule","DiedModule",      "DiscoveryModule", "GearShopModule",
	"GiftModule",      "GiftsModule",     "HUDModule",       "IndexModule",
	"OPBrainrotModule","RebirthModule",   "ShopModule",      "SpeedShopModule",
	"StatsModule",     "WalkspeedModule",
}
for _, n in ipairs(moduleNames) do em(modsDir, n) end

print("")
print("=== MODULE CREATION COMPLETE ===")
print("Created  : " .. tostring(#created))
for _, v in ipairs(created)  do print("  + " .. v) end
print("Skipped (already existed) : " .. tostring(#skipped))
for _, v in ipairs(skipped) do print("  ~ " .. v) end
print("=================================")
