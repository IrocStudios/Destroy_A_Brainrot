do
	local f = eFrame(framesFolder, "DailyGifts",
		UDim2.new(0, 500, 0, 360), UDim2.new(0.5, -250, 0.5, -180),
		Color3.fromRGB(18, 18, 30))
	stdClose(f)
	eLabel(f, "Title", "Daily Rewards", UDim2.new(1, -110, 0, 38), UDim2.new(0, 10, 0, 6))
	local tiles = eFrame(f, "DayTiles",
		UDim2.new(1, -16, 0, 155), UDim2.new(0, 8, 0, 50),
		Color3.fromRGB(28, 28, 42), true)
	for day = 1, 7 do
		local tile = ensure(tiles, "Frame", "Day" .. tostring(day), {
			Size             = UDim2.new(0, 62, 1, -8),
			Position         = UDim2.new(0, (day - 1) * 66 + 4, 0, 4),
			BackgroundColor3 = Color3.fromRGB(38, 38, 52),
			BorderSizePixel  = 0,
		})
		corner(tile, 6)
		eLabel(tile, "DayLabel",    "Day " .. tostring(day), UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0, 4))
		eLabel(tile, "RewardLabel", "Reward",                UDim2.new(1, 0, 0, 20), UDim2.new(0, 0, 0.5, -4))
		ensure(tile, "ImageLabel", "CheckMark", {
			Size                 = UDim2.new(0, 24, 0, 24),
			Position             = UDim2.new(0.5, -12, 1, -28),
			BackgroundTransparency = 1,
			Image                = "rbxassetid://3926307971",
			Visible              = false,
		})
	end
	eButton(f, "ClaimButton", "Claim Reward!",
		UDim2.new(1, -16, 0, 40), UDim2.new(0, 8, 0, 214),
		Color3.fromRGB(215, 165, 35))
	eLabel(f, "StatusLabel", "Come back tomorrow!",
		UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 262))
end

do
	local f = eFrame(framesFolder, "Gifts",
		UDim2.new(0, 420, 0, 500), UDim2.new(0.5, -210, 0.5, -250),
		Color3.fromRGB(20, 16, 30))
	stdClose(f)
	eLabel(f, "Title",      "Gifts",    UDim2.new(1, -110, 0, 38), UDim2.new(0, 10, 0, 6))
	eLabel(f, "BadgeCount", "0 ready",  UDim2.new(0, 80,   0, 26), UDim2.new(1, -98, 0, 50))
	local list = eScrolling(f, "GiftList",
		UDim2.new(1, -16, 1, -90), UDim2.new(0, 8, 0, 82))
	listLayout(list)
	itemCard(list, "GiftCard", {
		{"Image",  "Icon",       nil,      UDim2.new(0, 50, 0, 50), UDim2.new(0, 6, 0, 4)},
		{"Label",  "GiftName",   "Gift",   UDim2.new(1, -130, 0, 22), UDim2.new(0, 64, 0, 10)},
		{"Button", "OpenButton", "Open",   UDim2.new(0, 68, 0, 28),   UDim2.new(1, -82, 0.5, -14), Color3.fromRGB(55, 155, 55)},
	})
end

do
	local f = eFrame(framesFolder, "OPBrainrot",
		UDim2.new(0, 360, 0, 270), UDim2.new(0.5, -180, 0, 10),
		Color3.fromRGB(28, 8, 8))
	stdClose(f)
	eImage(f,  "BossIcon",    UDim2.new(0, 80, 0, 80), UDim2.new(0, 10, 0, 44))
	eLabel(f,  "BossName",    "Boss Brainrot",  UDim2.new(1, -108, 0, 28),  UDim2.new(0, 98, 0, 44))
	eLabel(f,  "RarityLabel", "Legendary",      UDim2.new(1, -108, 0, 22),  UDim2.new(0, 98, 0, 78))
	eFrame(f,  "HealthBar",   UDim2.new(1, -108, 0, 14), UDim2.new(0, 98, 0, 106),  Color3.fromRGB(215, 55, 55), true)
	eLabel(f,  "TimerLabel",  "Despawns in: 60s", UDim2.new(1, -16, 0, 22),  UDim2.new(0, 8, 0, 130))
	eLabel(f,  "RewardLabel", "Bonus: +50%",      UDim2.new(1, -16, 0, 22),  UDim2.new(0, 8, 0, 156))
end

do
	local f = eFrame(framesFolder, "Discovery",
		UDim2.new(0, 380, 0, 340), UDim2.new(0.5, -190, 0.5, -170),
		Color3.fromRGB(16, 16, 28))
	stdClose(f)
	eImage(f,  "BrainrotIcon", UDim2.new(0, 100, 0, 100), UDim2.new(0.5, -50, 0, 8))
	eLabel(f,  "BrainrotName", "New Brainrot!",  UDim2.new(1, -16, 0, 28),  UDim2.new(0, 8, 0, 116))
	eLabel(f,  "RarityLabel",  "Common",         UDim2.new(1, -16, 0, 22),  UDim2.new(0, 8, 0, 150))
	eFrame(f,  "RarityBar",    UDim2.new(1, 0, 0, 6), UDim2.new(0, 0, 0, 177), Color3.fromRGB(200, 200, 50), true)
	eLabel(f,  "FlavorText",   "New Discovery!", UDim2.new(1, -16, 0, 22),  UDim2.new(0, 8, 0, 190))
end

do
	local f = eFrame(framesFolder, "Died",
		UDim2.new(0, 320, 0, 270), UDim2.new(0.5, -160, 0.5, -135),
		Color3.fromRGB(20, 6, 6))
	corner(f, 10)
	eLabel(f, "Title",         "You Died",           UDim2.new(1, 0, 0, 40),   UDim2.new(0, 0, 0, 8))
	eLabel(f, "TimerLabel",    "Respawning in 5s",   UDim2.new(1, -16, 0, 28), UDim2.new(0, 8, 0, 56))
	eLabel(f, "KillsLabel",    "Kills: 0",           UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 90))
	eLabel(f, "CashLabel",     "Cash: $0",           UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 122))
	eButton(f, "RespawnButton","Respawn Now",
		UDim2.new(1, -16, 0, 40), UDim2.new(0, 8, 0, 158),
		Color3.fromRGB(55, 100, 200))
end

do
	local f = eFrame(framesFolder, "Alert",
		UDim2.new(0, 360, 0, 220), UDim2.new(0.5, -180, 0.5, -110),
		Color3.fromRGB(24, 20, 36))
	corner(f, 10)
	eLabel(f,  "Title",         "Alert",         UDim2.new(1, -16, 0, 36),   UDim2.new(0, 8, 0, 8))
	eLabel(f,  "Message",       "Are you sure?", UDim2.new(1, -16, 0, 50),   UDim2.new(0, 8, 0, 50))
	eButton(f, "ConfirmButton", "Confirm",
		UDim2.new(0, 130, 0, 38), UDim2.new(0, 8, 0, 112),
		Color3.fromRGB(55, 155, 55))
	eButton(f, "CancelButton",  "Cancel",
		UDim2.new(0, 130, 0, 38), UDim2.new(1, -140, 0, 112),
		Color3.fromRGB(175, 55, 55))
end

do
	local f = eFrame(framesFolder, "Gift",
		UDim2.new(0, 320, 0, 300), UDim2.new(0.5, -160, 0.5, -150),
		Color3.fromRGB(22, 16, 34))
	stdClose(f)
	eImage(f,  "RewardIcon",   UDim2.new(0, 90, 0, 90),   UDim2.new(0.5, -45, 0, 8))
	eLabel(f,  "RewardName",   "Reward!",  UDim2.new(1, -16, 0, 28), UDim2.new(0, 8, 0, 106))
	eLabel(f,  "RewardAmount", "x1",       UDim2.new(1, -16, 0, 24), UDim2.new(0, 8, 0, 138))
	eLabel(f,  "RarityLabel",  "Common",   UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 0, 168))
end

do
	local f = eFrame(framesFolder, "Walkspeed",
		UDim2.new(0, 220, 0, 100), UDim2.new(0, 10, 1, -120),
		Color3.fromRGB(18, 18, 30))
	stdClose(f)
	eLabel(f, "SpeedLabel", "16 WS",
		UDim2.new(0, 80, 0, 28), UDim2.new(0, 8, 0, 8))
	eFrame(f, "SpeedBar",
		UDim2.new(0, 0, 0, 12), UDim2.new(0, 8, 0, 42),
		Color3.fromRGB(70, 195, 90), true)
end

print("[4] Verifying StarterPlayerScripts layout...")
local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
if sps then
	local ctrl     = eFolder(sps, "Controllers")
	local ui       = eFolder(ctrl, "UI")
	local modsDir  = eFolder(ui, "Modules")

	local expectedMods = {
		"AlertModule", "CodesModule", "ConfigModule", "CommandModule",
		"DailyGiftsModule", "DiedModule", "DiscoveryModule",
		"GearShopModule", "GiftModule", "GiftsModule", "HUDModule",
		"IndexModule", "OPBrainrotModule", "RebirthModule",
		"ShopModule", "SpeedShopModule", "StatsModule", "WalkspeedModule",
	}
	for _, mn in ipairs(expectedMods) do
		if not modsDir:FindFirstChild(mn) then
			note("missing", "Module: " .. mn .. " (create in UI/Modules/)")
		else
			note("ok", mn .. " present")
		end
	end

	if not ui:FindFirstChild("MasterUIController") then
		note("missing", "MasterUIController (create in Controllers/UI/)")
	else
		note("ok", "MasterUIController present")
	end

	if not sps:FindFirstChild("ClientBoot") then
		note("missing", "ClientBoot (create in StarterPlayerScripts/)")
	else
		note("ok", "ClientBoot present")
	end
else
	note("missing", "StarterPlayerScripts itself not found")
end

print("[5] Verifying ServerStorage/Services...")
local svcs = ServerStorage:FindFirstChild("Services") or eFolder(ServerStorage, "Services")
local expectedSvcs = {
	"ServerLoader", "NetService", "DataService", "ProfileService",
	"BrainrotService", "CombatService", "AIService", "InventoryService",
	"ShopService", "GateService", "RewardService", "ProgressionService",
	"EconomyService", "MoneyService", "IndexService", "RarityService",
	"MarketplaceService", "AdminService", "WeaponService", "AnalyticsService",
	"CodesService",
}
for _, sn in ipairs(expectedSvcs) do
	if not svcs:FindFirstChild(sn) then
		note("missing", "Service: " .. sn)
	else
		note("ok", sn .. " present")
	end
end

print("[6] Verifying ReplicatedStorage layout...")
local shared  = eFolder(ReplicatedStorage, "Shared")
local netDir  = eFolder(shared, "Net")
local utilDir = eFolder(shared, "Util")
local cfgDir  = eFolder(shared, "Config")
local uiDir   = eFolder(shared, "UI")
local client  = eFolder(ReplicatedStorage, "Client")
local ctrlDir = eFolder(client, "Controllers")

local netChecks  = { "NetIds", "RemoteService" }
local utilChecks = { "Signal", "Janitor" }
local cfgChecks  = {
	"BrainrotConfig", "RarityConfig", "WeaponConfig",
	"ProgressionConfig", "ShopConfig", "EconomyConfig", "PersonalityConfig",
}
local ctrlChecks = {
	"StateController", "ShopController", "RebirthController",
	"SettingsController", "IndexController", "DailyRewardController",
	"GiftController", "PromptController", "StatsController",
	"WeaponClientController", "BrainrotClientController",
}

for _, n in ipairs(netChecks)  do
	if not netDir:FindFirstChild(n)  then note("missing", "Net/" .. n) else note("ok", "Net/" .. n) end
end
for _, n in ipairs(utilChecks) do
	if not utilDir:FindFirstChild(n) then note("missing", "Util/" .. n) else note("ok", "Util/" .. n) end
end
for _, n in ipairs(cfgChecks)  do
	if not cfgDir:FindFirstChild(n)  then note("missing", "Config/" .. n) else note("ok", "Config/" .. n) end
end
if not uiDir:FindFirstChild("UILibrary") then
	note("missing", "UI/UILibrary")
else
	note("ok", "UI/UILibrary present")
end
for _, n in ipairs(ctrlChecks) do
	if not ctrlDir:FindFirstChild(n) then note("missing", "Controllers/" .. n) else note("ok", "Controllers/" .. n) end
end
if not client:FindFirstChild("ClientLoader") then
	note("missing", "Client/ClientLoader")
else
	note("ok", "ClientLoader present")
end

print("[7] Verifying ServerScriptService...")
local sss = game:GetService("ServerScriptService")
if not sss:FindFirstChild("ServerBoot") then
	note("missing", "ServerScriptService/ServerBoot")
else
	note("ok", "ServerBoot present")
end

print("")
print("===  BRAINROT SETUP REPORT  ===")
print("Tagged for removal  :", #results.tagged)
for _, v in ipairs(results.tagged)  do print("  TAGGED   :", v) end

print("Created (new)       :", #results.created)
for _, v in ipairs(results.created) do print("  CREATED  :", v) end

print("Missing (need action):", #results.missing)
for _, v in ipairs(results.missing) do print("  MISSING  :", v) end

print("OK checks           :", #results.ok)
print("===  SETUP COMPLETE  ===")
print("Search the Explorer for 'TAGFORREMOVAL' Configuration objects to find tagged instances.")
