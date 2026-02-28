--!strict
-- BuyWeaponModule.lua  |  Frame: BuyWeapon
-- Proximity-based weapon purchase popup.
-- Scans Workspace.BuyStands for PriceBrick descendants with SellObj (ObjectValue)
-- pointing to a weapon folder. When player walks within RANGE studs, shows popup
-- with weapon info. Buy sends WeaponAction RF; decline/close dismisses until
-- player leaves range and returns.
--
-- WIRE-UP (Studio frame hierarchy):
--   BuyWeapon [Frame]
--     Canvas [CanvasGroup]
--       Header [Frame]
--         Title [TextLabel]
--         Shines [CanvasGroup]
--         Stud [ImageLabel]
--         RarityGradient, RarityGradientStroke
--     Stud [ImageLabel]
--     XButton [TextButton]
--     UIScale [UIScale]
--     container [Frame]
--       infobox [Frame]
--         weapontemplateholder [Frame]
--           Template_Weapon [TextButton]
--             container > IconHolder > x [ImageLabel]
--             container > Title > Title2 [TextLabel]
--             container > Damage > Damage2 [TextLabel]
--             container > newlabel [TextLabel]
--             container > RarityGradient, RarityGradientStroke
--         weaponinfo [Frame]
--           Rarity [TextLabel]
--           WeaponName > Title [TextLabel]
--       costbox [Frame]
--         Cost [TextLabel]
--       Options [Frame]
--         No [TextButton]
--         Yes [TextButton]
--     CurrentWeapon [ObjectValue]

local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local TweenService         = game:GetService("TweenService")
local SoundService         = game:GetService("SoundService")
local CollectionService    = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace            = game:GetService("Workspace")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")

local BuyWeaponModule = {}
BuyWeaponModule.__index = BuyWeaponModule

-- ── Constants ───────────────────────────────────────────────────────────────
local RANGE               = 10    -- studs to trigger popup
local PROX_INTERVAL       = 0.5   -- seconds between proximity checks
local FRAME_OPEN_DURATION = 0.4   -- seconds for popup to pop open
local INTERACT_ACTION     = "BuyWeaponInteract" -- ContextActionService action name

-- Display weapon animation (slow, dreamy float)
local BOB_AMPLITUDE       = 1      -- studs up/down
local BOB_PERIOD_MIN      = 8      -- minimum seconds per bob cycle
local BOB_PERIOD_MAX      = 14     -- maximum seconds per bob cycle
local ROCK_DEGREES        = 10     -- ± degrees (Y axis twist)
local ROCK_PERIOD         = 12.6   -- seconds per full cycle (40% slower)
local LEAN_DEGREES        = 7.5    -- ± degrees (Z axis lean-back sway)
local LEAN_PERIOD         = 16.5   -- seconds per full cycle (50% slower)

local RARITY_NAMES = {
	[1] = "Common",
	[2] = "Uncommon",
	[3] = "Rare",
	[4] = "Epic",
	[5] = "Legendary",
	[6] = "Mythic",
	[7] = "Transcendent",
}

local TEXTLABEL_DARKEN = 0.85

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function fmt(n: number): string
	n = math.floor(n or 0)
	if n >= 1e9 then return ("$%.2fb"):format(n / 1e9) end
	if n >= 1e6 then return ("$%.2fm"):format(n / 1e6) end
	if n >= 1e3 then return ("$%.2fk"):format(n / 1e3) end
	return "$" .. tostring(n)
end

-- ── Rarity config ───────────────────────────────────────────────────────────

local _rarityConfigInst = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RarityConfig")
local _rarityConfigData = require(_rarityConfigInst)

local PRODUCT_RARITY_TAG = "UseProductRarityColor"

local function getRarityColor(rarityNum: number): Color3
	local name = RARITY_NAMES[rarityNum] or "Common"
	local entry = _rarityConfigData.Rarities[name]
	return (entry and entry.Color) or Color3.fromRGB(190, 190, 190)
end

local function lightenColor(c: Color3, amount: number): Color3
	return Color3.new(
		math.min(1, c.R + (1 - c.R) * amount),
		math.min(1, c.G + (1 - c.G) * amount),
		math.min(1, c.B + (1 - c.B) * amount)
	)
end

-- ── Rarity gradient helper (mirrors PurchasedModule) ────────────────────────

local function darkenColorSequence(cs: ColorSequence, factor: number): ColorSequence
	local kps = {}
	for _, kp in ipairs(cs.Keypoints) do
		local c = kp.Value
		table.insert(kps, ColorSequenceKeypoint.new(kp.Time,
			Color3.new(c.R * factor, c.G * factor, c.B * factor)))
	end
	return ColorSequence.new(kps)
end

local function applyRarityGradients(parent: Instance, rarityName: string)
	local isTranscendent = rarityName == "Transcendent"
	for _, desc in parent:GetDescendants() do
		if desc:IsA("UIGradient") then
			if desc.Name == "RarityGradient" then
				local source = _rarityConfigInst:FindFirstChild(rarityName)
				if source and source:IsA("UIGradient") then
					local color = source.Color
					if desc.Parent and desc.Parent:IsA("TextLabel") then
						color = darkenColorSequence(color, TEXTLABEL_DARKEN)
					end
					desc.Color = color
				end
				if isTranscendent then
					CollectionService:AddTag(desc, "RainbowGradient")
				else
					CollectionService:RemoveTag(desc, "RainbowGradient")
				end
			elseif desc.Name == "RarityGradientStroke" then
				local source = _rarityConfigInst:FindFirstChild(rarityName .. "Stroke")
				if source and source:IsA("UIGradient") then
					desc.Color = source.Color
				end
				if isTranscendent then
					CollectionService:AddTag(desc, "RainbowGradient")
					desc.Rotation = 90
				else
					CollectionService:RemoveTag(desc, "RainbowGradient")
				end
			end
		end
	end
end

-- Quick horizontal shake to signal "can't afford" / "already owned"
local function shakeButton(btn: GuiButton)
	local orig = btn.Position
	local info = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local offsets = {
		UDim2.new(orig.X.Scale, orig.X.Offset + 6, orig.Y.Scale, orig.Y.Offset),
		UDim2.new(orig.X.Scale, orig.X.Offset - 6, orig.Y.Scale, orig.Y.Offset),
		UDim2.new(orig.X.Scale, orig.X.Offset + 4, orig.Y.Scale, orig.Y.Offset),
		UDim2.new(orig.X.Scale, orig.X.Offset - 4, orig.Y.Scale, orig.Y.Offset),
		orig,
	}
	local i = 0
	local function step()
		i += 1
		if i > #offsets then return end
		local tw = TweenService:Create(btn, info, { Position = offsets[i] })
		tw.Completed:Once(step)
		tw:Play()
	end
	step()
end

-- ── Owned check ─────────────────────────────────────────────────────────────

local function ownsWeapon(ctx: any, weaponKey: string): boolean
	local s = (ctx.State and ctx.State.State) or {}
	local inv = s.Inventory or {}
	local owned = inv.WeaponsOwned
	if typeof(owned) ~= "table" then return false end
	for _, k in ipairs(owned) do
		if k == weaponKey then return true end
	end
	return false
end

-- ── Greyscale helpers for owned buy button ──────────────────────────────────

local function desaturateColor(c: Color3, amount: number): Color3
	-- amount 0 = full color, 1 = full grey
	local grey = c.R * 0.299 + c.G * 0.587 + c.B * 0.114 -- luminance
	return Color3.new(
		c.R + (grey - c.R) * amount,
		c.G + (grey - c.G) * amount,
		c.B + (grey - c.B) * amount
	)
end

local function desaturateColorSequence(cs: ColorSequence, amount: number): ColorSequence
	local kps = {}
	for _, kp in ipairs(cs.Keypoints) do
		table.insert(kps, ColorSequenceKeypoint.new(kp.Time, desaturateColor(kp.Value, amount)))
	end
	return ColorSequence.new(kps)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function BuyWeaponModule:Init(ctx: any)
	self._ctx             = ctx
	self._janitor         = ctx.UI.Cleaner.new()
	self._open            = false
	self._processing      = false
	self._activeStand     = nil :: any
	self._stands          = {} :: { any }
	self._displayWeapons  = {} :: { any } -- { {model, baseCF, connection} }
	self._frame       = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("BuyWeapon")

	if not self._frame then
		warn("[BuyWeaponModule] Frame 'BuyWeapon' not found")
		return
	end

	-- Cache refs
	self._frameUIScale   = self._frame:FindFirstChildOfClass("UIScale") :: UIScale?
	self._frameOpenTween = nil :: Tween?

	-- Yes / No / X buttons
	self._yesBtn   = find(self._frame, "Yes")     :: TextButton?
	self._noBtn    = find(self._frame, "No")       :: TextButton?
	self._closeBtn = find(self._frame, "XButton")  :: TextButton?

	-- Info labels
	self._weaponNameLbl = find(self._frame, "WeaponName") :: TextLabel?
	self._rarityLbl     = find(self._frame, "Rarity")     :: TextLabel?
	self._costLbl       = find(self._frame, "Cost")        :: TextLabel?

	-- Template_Weapon card refs
	local templateWeapon = find(self._frame, "Template_Weapon")
	self._templateWeapon = templateWeapon
	if templateWeapon then
		local twContainer = templateWeapon:FindFirstChild("container")
		if twContainer then
			self._cardIconHolder = find(twContainer, "IconHolder") :: Frame?
			self._cardTitleLbl   = twContainer:FindFirstChild("Title") :: TextLabel?
			self._cardDamageLbl  = find(twContainer, "Damage")         :: TextLabel?
			self._cardNewLabel   = find(twContainer, "newlabel")       :: TextLabel?
		end
	end

	-- CurrentWeapon ObjectValue (for tracking)
	self._currentWeaponOV = self._frame:FindFirstChild("CurrentWeapon") :: ObjectValue?

	-- Cache original Yes button gradient colors for greyscale toggle
	self._yesBtnGradients = {} -- { {gradient, originalColor} }
	if self._yesBtn then
		for _, desc in (self._yesBtn :: Instance):GetDescendants() do
			if desc:IsA("UIGradient") then
				table.insert(self._yesBtnGradients, { gradient = desc, originalColor = desc.Color })
			end
		end
	end

	-- Wire Yes button → buy
	if self._yesBtn then
		self._janitor:Add((self._yesBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onBuy()
		end))
	end

	-- Wire No button → decline
	if self._noBtn then
		self._janitor:Add((self._noBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onDecline()
		end))
	end

	-- Wire X button → same as decline
	if self._closeBtn then
		self._janitor:Add((self._closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onDecline()
		end))
	end

	-- Scan buy stands
	self:_scanStands()

	print("[BuyWeaponModule] Init OK")
end

function BuyWeaponModule:Start()
	if not self._frame then return end

	-- Proximity loop
	self._proxLoop = true
	task.spawn(function()
		while self._proxLoop do
			task.wait(PROX_INTERVAL)
			self:_proximityCheck()
		end
	end)

	-- Listen for state changes to refresh owned status while popup is open
	self._janitor:Add(self._ctx.State.Changed:Connect(function(_, _)
		if self._open and self._activeStand then
			self:_refreshOwnedState()
		end
	end))

	print("[BuyWeaponModule] Start OK")
end

-- ── Stand scanning ─────────────────────────────────────────────────────────

function BuyWeaponModule:_scanStands()
	local standsFolder = Workspace:WaitForChild("BuyStands", 15)
	if not standsFolder then
		warn("[BuyWeaponModule] Workspace.BuyStands not found after 15s")
		return
	end

	self._standsFolder = standsFolder

	-- Scan all descendants for PriceBrick with SellObj child
	for _, desc in ipairs(standsFolder:GetDescendants()) do
		if desc.Name == "PriceBrick" and desc:IsA("BasePart") then
			self:_registerStand(desc)
		end
	end

	-- Listen for new stands added at runtime
	self._janitor:Add(standsFolder.DescendantAdded:Connect(function(child)
		if child.Name == "PriceBrick" and child:IsA("BasePart") then
			task.defer(function()
				self:_registerStand(child)
			end)
		end
	end))
end

function BuyWeaponModule:_registerStand(priceBrick: BasePart)
	-- Prevent duplicate registration
	for _, existing in ipairs(self._stands) do
		if existing.priceBrick == priceBrick then return end
	end

	-- Must have SellObj (ObjectValue) child pointing to weapon folder
	local sellObj = priceBrick:FindFirstChild("SellObj")
	if not sellObj or not sellObj:IsA("ObjectValue") then return end

	local weaponFolder = sellObj.Value
	if not weaponFolder then
		warn("[BuyWeaponModule] SellObj has no Value on PriceBrick:", priceBrick:GetFullName())
		return
	end

	-- Read weapon attributes from the folder
	local cost        = tonumber(weaponFolder:GetAttribute("Cost")) or 0
	local displayName = weaponFolder:GetAttribute("DisplayName") or weaponFolder.Name
	local rarity      = tonumber(weaponFolder:GetAttribute("Rarity")) or 1
	local damage      = tonumber(weaponFolder:GetAttribute("Damage")) or 0
	local weaponKey   = weaponFolder.Name -- used as key for WeaponAction RF

	local standData = {
		priceBrick   = priceBrick,
		weaponFolder = weaponFolder,
		weaponKey    = weaponKey,
		cost         = cost,
		displayName  = displayName,
		rarity       = rarity,
		damage       = damage,
		dismissed    = false,
		inRange      = false,
	}
	table.insert(self._stands, standData)

	-- Colorize stand parts/highlights to match weapon rarity
	self:_colorizeStand(standData)

	-- Spawn floating display weapon (if DummyWeapon exists in the weapon folder)
	self:_spawnDisplayWeapon(standData)

	print(("[BuyWeaponModule] Registered stand: %s → %s ($%d)"):format(
		priceBrick:GetFullName(), displayName, cost))
end

-- ── Stand colorization ─────────────────────────────────────────────────────

function BuyWeaponModule:_colorizeStand(standData: any)
	local priceBrick = standData.priceBrick
	local rarityColor = getRarityColor(standData.rarity)
	local fillColor   = lightenColor(rarityColor, 0.25)

	-- Walk up from PriceBrick to find the stand root (direct child of BuyStands)
	local standRoot = priceBrick
	while standRoot and standRoot.Parent ~= self._standsFolder do
		standRoot = standRoot.Parent
	end
	if not standRoot then return end

	-- Paint every tagged BasePart to the rarity color
	for _, desc in ipairs(standRoot:GetDescendants()) do
		if desc:IsA("BasePart") and CollectionService:HasTag(desc, PRODUCT_RARITY_TAG) then
			desc.Color = rarityColor
		end
	end

	-- Set every Highlight: outline = rarity color, fill = 25% lighter
	for _, desc in ipairs(standRoot:GetDescendants()) do
		if desc:IsA("Highlight") then
			desc.OutlineColor = rarityColor
			desc.FillColor = fillColor
		end
	end

	-- ── Update StandBoard BillboardGui ──
	local rarityName = RARITY_NAMES[standData.rarity] or "Common"

	for _, desc in ipairs(standRoot:GetDescendants()) do
		if desc:IsA("BillboardGui") and desc.Name == "StandBoard" then
			-- WeaponName + shadow Title
			local weaponNameLbl = desc:FindFirstChild("Frame") and desc.Frame:FindFirstChild("WeaponName")
			if weaponNameLbl and weaponNameLbl:IsA("TextLabel") then
				weaponNameLbl.Text = standData.displayName
				local title = weaponNameLbl:FindFirstChild("Title")
				if title and title:IsA("TextLabel") then
					title.Text = standData.displayName
				end
			end

			-- Rarity text + gradient
			local rarityLbl = desc:FindFirstChild("Frame") and desc.Frame:FindFirstChild("Rarity")
			if rarityLbl and rarityLbl:IsA("TextLabel") then
				rarityLbl.Text = rarityName
				-- Apply rarity gradient from RarityConfig
				applyRarityGradients(rarityLbl, rarityName)
			end

			-- Cost
			local costLbl = desc:FindFirstChild("Frame") and desc.Frame:FindFirstChild("Cost")
			if costLbl and costLbl:IsA("TextLabel") then
				costLbl.Text = fmt(standData.cost)
			end

			break
		end
	end
end

-- ── Display weapon (floating prop in glass tube) ────────────────────────────

function BuyWeaponModule:_spawnDisplayWeapon(standData: any)
	local weaponFolder = standData.weaponFolder
	local priceBrick   = standData.priceBrick

	-- Only spawn if the weapon folder has a DummyWeapon model
	local dummyTemplate = weaponFolder:FindFirstChild("DummyWeapon")
	if not dummyTemplate or not dummyTemplate:IsA("Model") then return end

	-- Find the Glass part in this stand
	local standRoot = priceBrick
	while standRoot and standRoot.Parent ~= self._standsFolder do
		standRoot = standRoot.Parent
	end
	if not standRoot then return end

	local glassPart: BasePart? = nil
	for _, desc in ipairs(standRoot:GetDescendants()) do
		if desc.Name == "Glass" and desc:IsA("BasePart") then
			glassPart = desc :: BasePart
			break
		end
	end
	if not glassPart then
		warn("[BuyWeaponModule] No Glass part found in stand for display weapon")
		return
	end

	-- Clone the dummy weapon
	local clone = dummyTemplate:Clone()
	clone.Name = "DisplayWeapon_" .. standData.weaponKey

	-- Anchor all parts so physics don't interfere
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
		end
	end

	-- Find the "Center" attachment for offset, or use bounding box center
	local centerAttachment: Attachment? = nil
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("Attachment") and desc.Name == "Center" then
			centerAttachment = desc :: Attachment
			break
		end
	end

	-- Calculate the base CFrame at the Glass center
	local glassCenter = (glassPart :: BasePart).CFrame.Position

	-- Temporarily parent the clone so we can read world positions
	clone.Parent = Workspace

	local baseCF: CFrame
	if centerAttachment then
		-- Offset so the Center attachment aligns with Glass center
		local attachWorldPos = (centerAttachment :: Attachment).WorldPosition
		local primaryCF = clone.PrimaryPart and clone.PrimaryPart.CFrame or clone:GetBoundingBox()
		local offset = attachWorldPos - primaryCF.Position
		baseCF = CFrame.new(glassCenter - offset)
	else
		-- No Center attachment — use bounding box center
		local modelCF = clone:GetBoundingBox()
		baseCF = CFrame.new(glassCenter)
	end

	-- Position the clone at base
	if clone.PrimaryPart then
		clone:PivotTo(baseCF)
	end

	-- Add a rarity Highlight to the display weapon
	local rarityColor = getRarityColor(standData.rarity)
	local fillColor   = lightenColor(rarityColor, 0.25)
	local highlight = Instance.new("Highlight")
	highlight.Adornee = clone
	highlight.OutlineColor = rarityColor
	highlight.FillColor = fillColor
	highlight.FillTransparency = 0.8
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = clone

	-- Store the base CFrame (rotation-neutral at Glass center) for animation
	-- We want the weapon's default orientation preserved, just positioned at Glass
	local animBaseCF = clone.PrimaryPart and clone.PrimaryPart.CFrame or baseCF

	-- Start Heartbeat animation: bob + rock + lean
	local startTime = os.clock()
	local bobPeriod = BOB_PERIOD_MIN + math.random() * (BOB_PERIOD_MAX - BOB_PERIOD_MIN) -- random 8-14s per instance
	local connection = RunService.Heartbeat:Connect(function()
		if not clone.Parent or not clone.PrimaryPart then return end
		local t = os.clock() - startTime

		-- Bob: sine wave on Y axis, ±BOB_AMPLITUDE studs
		local bobY = math.sin(t * (2 * math.pi / bobPeriod)) * BOB_AMPLITUDE

		-- Rock: Y-axis rotation, ±ROCK_DEGREES
		local rockAngle = math.rad(math.sin(t * (2 * math.pi / ROCK_PERIOD)) * ROCK_DEGREES)

		-- Lean: Z-axis sway, ±LEAN_DEGREES
		local leanAngle = math.rad(math.sin(t * (2 * math.pi / LEAN_PERIOD)) * LEAN_DEGREES)

		local animCF = animBaseCF
			* CFrame.new(0, bobY, 0)
			* CFrame.Angles(0, rockAngle, leanAngle)

		clone:PivotTo(animCF)
	end)

	-- Track for cleanup
	table.insert(self._displayWeapons, {
		model      = clone,
		connection = connection,
	})
end

-- ── Proximity ───────────────────────────────────────────────────────────────

function BuyWeaponModule:_proximityCheck()
	if self._processing then return end

	local player = self._ctx.Player
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		if self._open then self:_hide(true) end
		return
	end

	local playerPos = (hrp :: BasePart).Position

	-- Find nearest stand within range, update per-stand state
	local nearestStand = nil
	local nearestDist  = RANGE + 1

	for _, standData in ipairs(self._stands) do
		local brick = standData.priceBrick
		if brick and brick.Parent then
			local dist = (brick.Position - playerPos).Magnitude
			local wasInRange = standData.inRange
			standData.inRange = dist <= RANGE

			-- Clear dismissed when player leaves range
			if wasInRange and not standData.inRange then
				standData.dismissed = false
			end

			if standData.inRange and dist < nearestDist then
				nearestDist = dist
				nearestStand = standData
			end
		end
	end

	-- Show/hide logic
	if nearestStand and not nearestStand.dismissed then
		if not self._open then
			self:_show(nearestStand)
		elseif self._activeStand ~= nearestStand then
			-- Switched to a different stand while popup was open
			self:_hide(true)
			self:_show(nearestStand)
		end
	else
		if self._open then
			self:_hide(true)
		end
	end
end

-- ── Show / Hide ─────────────────────────────────────────────────────────────

function BuyWeaponModule:_show(standData: any)
	if not self._frame then return end
	if self._open then return end

	self._activeStand = standData
	local rarityName = RARITY_NAMES[standData.rarity] or "Common"

	-- ── Populate weapon info labels ──
	if self._weaponNameLbl then
		-- Set WeaponName itself + its Title child (shadow pair)
		(self._weaponNameLbl :: TextLabel).Text = standData.displayName
		local title = (self._weaponNameLbl :: Instance):FindFirstChild("Title") :: TextLabel?
		if title then
			title.Text = standData.displayName
			local title2 = title:FindFirstChild("Title") :: TextLabel?
			if title2 then title2.Text = standData.displayName end
		end
	end

	if self._rarityLbl then
		(self._rarityLbl :: TextLabel).Text = rarityName
	end

	if self._costLbl then
		(self._costLbl :: TextLabel).Text = fmt(standData.cost)
	end

	-- ── Populate Template_Weapon card ──
	if self._cardTitleLbl then
		(self._cardTitleLbl :: TextLabel).Text = standData.displayName
		local title2 = (self._cardTitleLbl :: Instance):FindFirstChild("Title2") :: TextLabel?
		if title2 then title2.Text = standData.displayName end
	end

	if self._cardDamageLbl then
		(self._cardDamageLbl :: TextLabel).Text = tostring(standData.damage)
		local dmg2 = (self._cardDamageLbl :: Instance):FindFirstChild("Damage2") :: TextLabel?
		if dmg2 then dmg2.Text = tostring(standData.damage) end
	end

	-- Clone icon from weapon folder into IconHolder
	self:_setIcon(standData.weaponFolder)

	-- Apply rarity gradients to the entire frame
	applyRarityGradients(self._frame, rarityName)

	-- Track current weapon via ObjectValue
	if self._currentWeaponOV then
		(self._currentWeaponOV :: ObjectValue).Value = standData.weaponFolder
	end

	-- Owned / New check
	self:_refreshOwnedState()

	-- UIScale override pattern: set to 0 BEFORE Router:Open
	if self._frameUIScale then
		(self._frameUIScale :: UIScale).Scale = 0
	end

	-- Pop sound
	pcall(function() SoundService.cartoon_pop:Play() end)

	-- Open via Router
	self._open = true
	if self._ctx.Router then
		self._ctx.Router:Open("BuyWeapon")
	end

	-- Override Router's fast tween with our slower Back tween
	if self._frameUIScale then
		local us = self._frameUIScale :: UIScale
		if self._frameOpenTween then
			(self._frameOpenTween :: Tween):Cancel()
		end
		us.Scale = 0
		local openInfo = TweenInfo.new(FRAME_OPEN_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		self._frameOpenTween = TweenService:Create(us :: Instance, openInfo, { Scale = 1 })
		self._frameOpenTween:Play()
	end

	-- Bind 'E' key to purchase
	ContextActionService:BindAction(INTERACT_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self:_onBuy()
		end
	end, false, Enum.KeyCode.E)
end

function BuyWeaponModule:_hide(playSound: boolean?)
	if not self._frame then return end
	if not self._open then return end
	self._open = false
	self._activeStand = nil

	-- Unbind 'E' key
	ContextActionService:UnbindAction(INTERACT_ACTION)

	if playSound then
		pcall(function() SoundService.cartoon_pop2:Play() end)
	end

	if self._frameOpenTween then
		self._frameOpenTween:Cancel()
		self._frameOpenTween = nil
	end

	if self._ctx.Router then
		self._ctx.Router:Close("BuyWeapon")
	end
end

-- ── Refresh owned state (called on show + state changes) ────────────────────

function BuyWeaponModule:_refreshOwnedState()
	local standData = self._activeStand
	if not standData then return end

	local isOwned = ownsWeapon(self._ctx, standData.weaponKey)
	local label = isOwned and "Owned" or "Buy"

	-- Yes button: show "Owned" or "Buy" text — always stays active (duplicates allowed)
	if self._yesBtn then
		local titleFrame = find(self._yesBtn, "Title") :: TextLabel?
		if titleFrame then
			local innerTitle = titleFrame:FindFirstChild("Title") :: TextLabel?
			if innerTitle then
				innerTitle.Text = label
			end
			titleFrame.Text = label
		end

		-- Greyscale toggle: 50% desaturation when owned, restore originals when not
		for _, entry in ipairs(self._yesBtnGradients) do
			if isOwned then
				entry.gradient.Color = desaturateColorSequence(entry.originalColor, 0.5)
			else
				entry.gradient.Color = entry.originalColor
			end
		end
	end

	-- New label: show only if NOT owned
	if self._cardNewLabel then
		(self._cardNewLabel :: TextLabel).Visible = not isOwned
	end
end

-- ── Icon ─────────────────────────────────────────────────────────────────────

function BuyWeaponModule:_setIcon(weaponFolder: Instance)
	if not self._cardIconHolder then return end

	local holder = self._cardIconHolder :: Frame

	-- Clear any previously cloned icon (preserve the template "x" ImageLabel)
	local existingIcon = holder:FindFirstChild("WeaponIcon")
	if existingIcon then existingIcon:Destroy() end

	local iconTemplate = weaponFolder:FindFirstChild("Icon")
	if not iconTemplate then return end

	local iconClone = iconTemplate:Clone()
	iconClone.Name = "WeaponIcon"

	-- Fill the holder
	if iconClone:IsA("GuiObject") then
		iconClone.Size = UDim2.fromScale(1, 1)
		iconClone.Position = UDim2.fromScale(0.5, 0.5)
		iconClone.AnchorPoint = Vector2.new(0.5, 0.5)
	end

	iconClone.Parent = holder

	-- Hide the template "x" placeholder image
	local placeholder = holder:FindFirstChild("x")
	if placeholder and placeholder:IsA("GuiObject") then
		placeholder.Visible = false
	end
end

-- ── Buy action ──────────────────────────────────────────────────────────────

function BuyWeaponModule:_onBuy()
	if self._processing then return end
	if not self._activeStand then return end

	local standData = self._activeStand
	self._processing = true

	-- Dismiss immediately so proximity loop won't re-open while we process
	standData.dismissed = true

	-- Close immediately for instant feedback
	self:_hide(false)

	local rf = self._ctx.Net:GetFunction("WeaponAction")
	task.spawn(function()
		local ok, result = pcall(function()
			return rf:InvokeServer({
				action = "buy",
				weapon = standData.weaponKey,
				cost   = standData.cost,
			})
		end)

		if not ok then
			warn("[BuyWeaponModule] Buy invoke error:", result)
			standData.dismissed = false -- allow retry
			self._processing = false
			return
		end

		if type(result) == "table" and result.ok then
			-- Success! PurchasedModule handles the toast via Notify event.
			-- Keep dismissed = true so popup won't reappear until player leaves range
			pcall(function() SoundService.cartoon_pop:Play() end)
		else
			-- Failed — clear dismiss so re-show works, then re-show popup and shake
			standData.dismissed = false
			self:_show(standData)
			if self._yesBtn then
				shakeButton(self._yesBtn :: GuiButton)
			end
		end

		self._processing = false
	end)
end

-- ── Decline action ──────────────────────────────────────────────────────────

function BuyWeaponModule:_onDecline()
	if self._activeStand then
		self._activeStand.dismissed = true
	end
	self:_hide(false)
end

-- ── Cleanup ─────────────────────────────────────────────────────────────────

function BuyWeaponModule:Destroy()
	self._proxLoop = false
	pcall(function() ContextActionService:UnbindAction(INTERACT_ACTION) end)
	if self._frameOpenTween then self._frameOpenTween:Cancel() end

	-- Clean up display weapons
	for _, entry in ipairs(self._displayWeapons) do
		if entry.connection then entry.connection:Disconnect() end
		if entry.model and entry.model.Parent then entry.model:Destroy() end
	end
	self._displayWeapons = {}

	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return BuyWeaponModule
