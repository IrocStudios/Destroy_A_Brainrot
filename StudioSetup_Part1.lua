local StarterGui     = game:GetService("StarterGui")
local StarterPlayer  = game:GetService("StarterPlayer")
local ServerStorage  = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local results = { tagged = {}, created = {}, missing = {}, ok = {} }

local function tag(inst)
	if inst:FindFirstChild("TAGFORREMOVAL") then return end
	local cfg = Instance.new("Configuration")
	cfg.Name = "TAGFORREMOVAL"
	cfg.Parent = inst
	table.insert(results.tagged, inst:GetFullName())
end

local function note(t, msg) table.insert(results[t], msg) end

local function ensure(parent, cls, name, props)
	local e = parent:FindFirstChild(name)
	if e then
		if e:IsA(cls) then return e, false end
		tag(e)
	end
	local i = Instance.new(cls)
	i.Name = name
	if props then
		for k, v in pairs(props) do pcall(function() i[k] = v end) end
	end
	i.Parent = parent
	note("created", cls .. " " .. i:GetFullName())
	return i, true
end

local function eFolder(parent, name) return ensure(parent, "Folder", name) end

local function eFrame(parent, name, sz, pos, col, vis)
	return ensure(parent, "Frame", name, {
		Size                 = sz  or UDim2.new(0.45, 0, 0.55, 0),
		Position             = pos or UDim2.new(0.275, 0, 0.225, 0),
		BackgroundColor3     = col or Color3.fromRGB(22, 22, 32),
		BorderSizePixel      = 0,
		Visible              = vis ~= nil and vis or false,
	})
end

local function eLabel(parent, name, text, sz, pos)
	return ensure(parent, "TextLabel", name, {
		Text                 = text or name,
		Size                 = sz  or UDim2.new(1, 0, 0, 28),
		Position             = pos or UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		TextColor3           = Color3.fromRGB(240, 240, 255),
		Font                 = Enum.Font.GothamBold,
		TextScaled           = true,
		TextXAlignment       = Enum.TextXAlignment.Left,
	})
end

local function eButton(parent, name, text, sz, pos, col)
	return ensure(parent, "TextButton", name, {
		Text             = text or name,
		Size             = sz  or UDim2.new(0, 110, 0, 34),
		Position         = pos or UDim2.new(0, 8, 1, -42),
		BackgroundColor3 = col or Color3.fromRGB(55, 110, 210),
		TextColor3       = Color3.fromRGB(255, 255, 255),
		Font             = Enum.Font.GothamBold,
		TextSize         = 13,
		BorderSizePixel  = 0,
	})
end

local function eScrolling(parent, name, sz, pos)
	return ensure(parent, "ScrollingFrame", name, {
		Size                 = sz  or UDim2.new(1, -16, 1, -54),
		Position             = pos or UDim2.new(0, 8, 0, 46),
		BackgroundTransparency = 1,
		BorderSizePixel      = 0,
		ScrollBarThickness   = 5,
		AutomaticCanvasSize  = Enum.AutomaticSize.Y,
		CanvasSize           = UDim2.new(0, 0, 0, 0),
		ScrollingDirection   = Enum.ScrollingDirection.Y,
	})
end

local function eImage(parent, name, sz, pos)
	return ensure(parent, "ImageLabel", name, {
		Size                 = sz  or UDim2.new(0, 60, 0, 60),
		Position             = pos or UDim2.new(0, 6, 0, 6),
		BackgroundTransparency = 1,
		Image                = "",
	})
end

local function eTextBox(parent, name, placeholder, sz, pos)
	return ensure(parent, "TextBox", name, {
		PlaceholderText      = placeholder or "Type here...",
		Text                 = "",
		Size                 = sz  or UDim2.new(1, -16, 0, 34),
		Position             = pos or UDim2.new(0, 8, 0, 50),
		BackgroundColor3     = Color3.fromRGB(38, 38, 52),
		TextColor3           = Color3.fromRGB(240, 240, 255),
		PlaceholderColor3    = Color3.fromRGB(120, 120, 150),
		Font                 = Enum.Font.Gotham,
		TextSize             = 14,
		BorderSizePixel      = 0,
		ClearTextOnFocus     = false,
	})
end

local function corner(parent, r)
	if not parent:FindFirstChildOfClass("UICorner") then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r or 10)
		c.Parent = parent
	end
end

local function listLayout(parent)
	if not parent:FindFirstChildOfClass("UIListLayout") then
		local ll = Instance.new("UIListLayout")
		ll.SortOrder = Enum.SortOrder.LayoutOrder
		ll.Padding   = UDim.new(0, 4)
		ll.Parent    = parent
	end
end

local function stdClose(frame)
	eButton(frame, "CloseButton", "✕ Close",
		UDim2.new(0, 90, 0, 28), UDim2.new(1, -98, 0, 8),
		Color3.fromRGB(170, 55, 55))
	corner(frame, 10)
end

local function itemCard(list, cardName, childDefs)
	local t = list:FindFirstChild(cardName)
	if not t then
		t = Instance.new("Frame")
		t.Name             = cardName
		t.Size             = UDim2.new(1, -8, 0, 68)
		t.BackgroundColor3 = Color3.fromRGB(38, 38, 52)
		t.BorderSizePixel  = 0
		t.Visible          = false
		t.Parent           = list
		corner(t, 6)
		note("created", "Template " .. t:GetFullName())
	end
	for _, d in ipairs(childDefs) do
		pcall(function()
			if d[1] == "Label"  then eLabel(t, d[2], d[3], d[4], d[5])
			elseif d[1] == "Button" then eButton(t, d[2], d[3], d[4], d[5], d[6])
			elseif d[1] == "Image"  then eImage(t, d[2], d[3], d[4])
			elseif d[1] == "Frame"  then
				local f2 = eFrame(t, d[2], d[3], d[4], d[5], true)
				if f2 then corner(f2, 3) end
			end
		end)
	end
	return t
end

print("=== BRAINROT STUDIO SETUP ===")

print("[1] Scanning for dead/deleted scripts...")
local DEAD = { "UIController", "UIContext", "PlayerStateClient" }
for _, inst in ipairs(game:GetDescendants()) do
	if inst:IsA("ModuleScript") or inst:IsA("LocalScript") or inst:IsA("Script") then
		for _, dead in ipairs(DEAD) do
			if inst.Name == dead then
				tag(inst)
			end
		end
	end
end

print("[2] Building StarterGui / ScreenGui structure...")
local gui = ensure(StarterGui, "ScreenGui", "GUI", {
	ResetOnSpawn   = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder   = 1,
})

local hud = eFrame(gui, "HUD",
	UDim2.new(1, 0, 0, 52),
	UDim2.new(0, 0, 0, 0),
	Color3.fromRGB(14, 14, 22),
	true)
eLabel(hud, "CashLabel",     "$0",       UDim2.new(0, 110, 1, -8), UDim2.new(0, 10, 0, 4))
eLabel(hud, "LevelLabel",    "Lv 1",     UDim2.new(0, 70,  1, -8), UDim2.new(0, 130, 0, 4))
eLabel(hud, "XPLabel",       "XP 0/100", UDim2.new(0, 110, 0, 16), UDim2.new(0, 212, 0, 4))
eFrame(hud, "XPBar", UDim2.new(0, 0, 0, 10), UDim2.new(0, 212, 0, 22), Color3.fromRGB(70, 195, 90), true)
eLabel(hud, "RebirthsLabel", "⟳ 0",      UDim2.new(0, 60,  1, -8), UDim2.new(0, 332, 0, 4))

local nav = eFrame(hud, "NavBar",
	UDim2.new(0, 590, 1, -4),
	UDim2.new(1, -600, 0, 2),
	Color3.fromRGB(20, 20, 30),
	true)

local navDefs = {
	{"ShopBtn",      "🏪 Shop"},    {"IndexBtn",     "📖 Index"},
	{"StatsBtn",     "📊 Stats"},   {"CodesBtn",     "🎁 Codes"},
	{"SettingsBtn",  "⚙ Config"},   {"GearShopBtn",  "⚔ Gear"},
	{"SpeedShopBtn", "⚡ Speed"},   {"RebirthBtn",   "⟳ Rebirth"},
	{"DailyBtn",     "📅 Daily"},   {"GiftsBtn",     "🎀 Gifts"},
}
for i, nd in ipairs(navDefs) do
	eButton(nav, nd[1], nd[2],
		UDim2.new(0, 56, 1, -4),
		UDim2.new(0, (i - 1) * 59, 0, 2),
		Color3.fromRGB(38, 58, 100))
end

print("[3] Building Frames folder and all panel frames...")
local framesFolder = eFolder(gui, "Frames")

do
	local f = eFrame(framesFolder, "Shop",
		UDim2.new(0, 520, 0, 600), UDim2.new(0.5, -260, 0.5, -300),
		Color3.fromRGB(18, 18, 30))
	stdClose(f)
	eLabel(f, "Title", "Shop", UDim2.new(1, -110, 0, 38), UDim2.new(0, 10, 0, 6))
	eLabel(f, "CashLabel", "$0", UDim2.new(0, 100, 0, 26), UDim2.new(0, 10, 1, -34))
	eFrame(f, "CategoryTabs",
		UDim2.new(1, -16, 0, 34), UDim2.new(0, 8, 0, 50),
		Color3.fromRGB(28, 28, 42), true)
	local list = eScrolling(f, "ItemList",
		UDim2.new(1, -16, 1, -130), UDim2.new(0, 8, 0, 90))
	listLayout(list)
	itemCard(list, "ItemCard", {
		{"Image",  "Icon",         nil,                      UDim2.new(0, 54, 0, 54), UDim2.new(0, 4, 0, 4)},
		{"Label",  "ItemName",     "Item",                   UDim2.new(1, -130, 0, 22), UDim2.new(0, 66, 0, 6)},
		{"Label",  "PriceLabel",   "$0",                     UDim2.new(0, 80, 0, 20),  UDim2.new(0, 66, 0, 32)},
		{"Frame",  "RarityBar",    UDim2.new(0, 4, 0, 50),   UDim2.new(0, 0, 0, 4),   Color3.fromRGB(200, 200, 50)},
		{"Button", "ActionButton", "Buy",                    UDim2.new(0, 76, 0, 28),  UDim2.new(1, -86, 0.5, -14), Color3.fromRGB(55, 155, 55)},
	})
end

do
	local f = eFrame(framesFolder, "Index",
		UDim2.new(0, 500, 0, 580), UDim2.new(0.5, -250, 0.5, -290),
		Color3.fromRGB(16, 16, 28))
	stdClose(f)
	eLabel(f, "Title", "Brainrot Index", UDim2.new(1, -110, 0, 38), UDim2.new(0, 10, 0, 6))
	eButton(f, "FilterAll",   "All",        UDim2.new(0, 78, 0, 26), UDim2.new(0, 10, 0, 50), Color3.fromRGB(55, 100, 175))
	eButton(f, "FilterFound", "Discovered", UDim2.new(0, 100, 0, 26), UDim2.new(0, 96, 0, 50), Color3.fromRGB(55, 140, 55))
	local list = eScrolling(f, "EntryList",
		UDim2.new(1, -16, 1, -90), UDim2.new(0, 8, 0, 82))
	listLayout(list)
	itemCard(list, "EntryCard", {
		{"Image", "Icon",       nil,                    UDim2.new(0, 50, 0, 50), UDim2.new(0, 6, 0, 4)},
		{"Label", "EntryName",  "???",                  UDim2.new(1, -120, 0, 22), UDim2.new(0, 64, 0, 8)},
		{"Label", "RarityLabel","Common",               UDim2.new(0, 80, 0, 18),  UDim2.new(0, 64, 0, 34)},
		{"Frame", "RarityBar",  UDim2.new(0, 4, 0, 48), UDim2.new(0, 0, 0, 4),  Color3.fromRGB(200, 200, 50)},
	})
end

do
	local f = eFrame(framesFolder, "Stats",
		UDim2.new(0, 360, 0, 400), UDim2.new(0.5, -180, 0.5, -200),
		Color3.fromRGB(16, 16, 28))
	stdClose(f)
	eLabel(f, "Title", "Stats", UDim2.new(1, -110, 0, 38), UDim2.new(0, 10, 0, 6))
	local rows = {
		{"KillsLabel",      "Kills: 0"},
		{"CashLabel",       "Cash Earned: $0"},
		{"DiscoveriesLabel","Discoveries: 0"},
		{"RebirthsLabel",   "Rebirths: 0"},
		{"LevelLabel",      "Level: 1"},
	}
	for i, rd in ipairs(rows) do
		eLabel(f, rd[1], rd[2],
			UDim2.new(1, -16, 0, 30),
			UDim2.new(0, 8, 0, 48 + (i - 1) * 36))
	end
end

do
	local f = eFrame(framesFolder, "Codes",
		UDim2.new(0, 380, 0, 210), UDim2.new(0.5, -190, 0.5, -105),
		Color3.fromRGB(18, 18, 30))
	stdClose(f)
	eLabel(f, "Title", "Redeem Code", UDim2.new(1, -110, 0, 38), UDim2.new(0, 10, 0, 6))
	eTextBox(f, "CodeInput", "Enter code here...",
		UDim2.new(1, -16, 0, 34), UDim2.new(0, 8, 0, 52))
	eButton(f, "SubmitButton", "Redeem",
		UDim2.new(1, -16, 0, 34), UDim2.new(0, 8, 0, 92),
		Color3.fromRGB(55, 155, 55))
	eLabel(f, "ResultLabel", "",
		UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, 132))
end

do
	local f = eFrame(framesFolder, "Config",
		UDim2.new(0, 340, 0, 270), UDim2.new(0.5, -170, 0.5, -135),
		Color3.fromRGB(16, 16, 28))
	stdClose(f)
	eLabel(f, "Title", "Settings", UDim2.new(1, -110, 0, 38), UDim2.new(0, 10, 0, 6))
	eButton(f, "MusicToggle", "Music: ON",
		UDim2.new(1, -16, 0, 40), UDim2.new(0, 8, 0, 52),
		Color3.fromRGB(55, 100, 175))
	eButton(f, "SFXToggle", "SFX: ON",
		UDim2.new(1, -16, 0, 40), UDim2.new(0, 8, 0, 100),
		Color3.fromRGB(55, 100, 175))
end

do
	local f = eFrame(framesFolder, "GearShop",
		UDim2.new(0, 500, 0, 560), UDim2.new(0.5, -250, 0.5, -280),
		Color3.fromRGB(18, 18, 30))
	stdClose(f)
	eLabel(f, "Title", "Gear Shop", UDim2.new(1, -110, 0, 38), UDim2.new(0, 10, 0, 6))
	eLabel(f, "CashLabel", "$0", UDim2.new(0, 100, 0, 26), UDim2.new(0, 10, 1, -34))
	local list = eScrolling(f, "ItemList",
		UDim2.new(1, -16, 1, -80), UDim2.new(0, 8, 0, 50))
	listLayout(list)
	itemCard(list, "ItemCard", {
		{"Image",  "Icon",         nil,                    UDim2.new(0, 54, 0, 54), UDim2.new(0, 4, 0, 4)},
		{"Label",  "ItemName",     "Item",                 UDim2.new(1, -130, 0, 22), UDim2.new(0, 66, 0, 6)},
		{"Label",  "PriceLabel",   "$0",                   UDim2.new(0, 80, 0, 20),  UDim2.new(0, 66, 0, 32)},
		{"Frame",  "RarityBar",    UDim2.new(0, 4, 0, 50), UDim2.new(0, 0, 0, 4),   Color3.fromRGB(200, 200, 50)},
		{"Button", "ActionButton", "Buy",                  UDim2.new(0, 76, 0, 28),  UDim2.new(1, -86, 0.5, -14), Color3.fromRGB(55, 155, 55)},
	})
end

do
	local f = eFrame(framesFolder, "SpeedShop",
		UDim2.new(0, 420, 0, 520), UDim2.new(0.5, -210, 0.5, -260),
		Color3.fromRGB(18, 18, 30))
	stdClose(f)
	eLabel(f, "Title",        "Speed Shop",   UDim2.new(1, -110, 0, 38), UDim2.new(0, 10, 0, 6))
	eLabel(f, "CurrentSpeed", "Speed: 16",    UDim2.new(1, -16, 0, 24),  UDim2.new(0, 8, 0, 50))
	eLabel(f, "CashLabel",    "$0",           UDim2.new(0, 100, 0, 26),  UDim2.new(0, 8, 1, -34))
	local list = eScrolling(f, "ItemList",
		UDim2.new(1, -16, 1, -100), UDim2.new(0, 8, 0, 78))
	listLayout(list)
	itemCard(list, "SpeedCard", {
		{"Label",  "TierName",   "Quick Feet",  UDim2.new(1, -160, 0, 22), UDim2.new(0, 10, 0, 8)},
		{"Label",  "SpeedValue", "+2 Speed",    UDim2.new(0, 90, 0, 20),   UDim2.new(0, 10, 0, 34)},
		{"Label",  "PriceLabel", "$500",        UDim2.new(0, 80, 0, 20),   UDim2.new(1, -170, 0, 8)},
		{"Button", "BuyButton",  "Buy",         UDim2.new(0, 68, 0, 28),   UDim2.new(1, -82, 0.5, -14), Color3.fromRGB(55, 155, 55)},
	})
end

do
	local f = eFrame(framesFolder, "Rebirth",
		UDim2.new(0, 380, 0, 440), UDim2.new(0.5, -190, 0.5, -220),
		Color3.fromRGB(20, 16, 32))
	stdClose(f)
	eLabel(f, "Title",           "Rebirth",             UDim2.new(1, -110, 0, 38),  UDim2.new(0, 10,  0, 6))
	eLabel(f, "RebirthCount",    "Rebirths: 0",         UDim2.new(1, -16,  0, 30),  UDim2.new(0, 8,   0, 50))
	eLabel(f, "NextMultiplier",  "Next Bonus: +12%",    UDim2.new(1, -16,  0, 28),  UDim2.new(0, 8,   0, 86))
	eLabel(f, "RequireLvl",      "Level Required: 60",  UDim2.new(1, -16,  0, 24),  UDim2.new(0, 8,   0, 126))
	eLabel(f, "RequireStage",    "Stage Required: 5",   UDim2.new(1, -16,  0, 24),  UDim2.new(0, 8,   0, 156))
	eLabel(f, "RequireCash",     "Cash: $50,000",       UDim2.new(1, -16,  0, 24),  UDim2.new(0, 8,   0, 186))
	eButton(f, "RebirthButton",  "⟳ Rebirth Now",
		UDim2.new(1, -16, 0, 44), UDim2.new(0, 8, 0, 224),
		Color3.fromRGB(155, 55, 210))
end

print("Part 1 complete – continuing to Part 2...")
print("Tagged:", #results.tagged, "  Created:", #results.created)
