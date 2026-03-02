--!strict
-- HatchSequenceModule.lua  |  Frame: HatchSequence
-- Full gift opening animation: intro -> click -> hatch -> reveal -> auto-close.
-- Called by OpenGiftModule after the server confirms the gift is opened.
--
-- Public API:
--   HatchSequenceModule:Play(giftData, rewardResult)
--     giftData    = { giftKey, displayName, icon (imageId string) }
--     rewardResult = server result.result table from OpenGift
--
-- WIRE-UP (Studio frame hierarchy):
--   HatchSequence [Frame]
--     ├─ holder [Frame]
--     │   ├─ gift [ImageLabel]   → drops from above, rocks, shrinks
--     │   ├─ Title [TextLabel]   → "Click To Open" (UIScale starts ~0)
--     │   ├─ glow [ImageLabel]   → soft background glow
--     │   └─ UIScale             → holder scale (rest = 0.73)
--     └─ hatched [Frame]
--         ├─ glow [ImageLabel]
--         ├─ Template_Weapon [TextButton]  → weapon reward card
--         ├─ Template_Armor  [TextButton]  → armor reward card
--         ├─ Template_Speed  [TextButton]  → speed reward card
--         ├─ Shine [ImageLabel]            → spinning starburst
--         └─ UIScale                       → hatched scale (starts ~0)

local TweenService      = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local CollectionService  = game:GetService("CollectionService")

local HatchSequenceModule = {}
HatchSequenceModule.__index = HatchSequenceModule

-- ── Config ──────────────────────────────────────────────────────────────────

local HOLDER_REST_SCALE  = 0.73   -- holder's resting UIScale (matches Studio)
local ROCK_ANGLE         = 18     -- degrees each direction for rocking
local ROCK_DURATION      = 0.4    -- seconds per rock half-cycle
local SHRINK_DURATION    = 0.8    -- seconds for gift shrink + shake
local REVEAL_DURATION    = 0.35   -- seconds for hatched bounce-in
local SPIN_DURATION      = 8      -- seconds per full Shine rotation
local AUTO_CLOSE_DELAY   = 3      -- seconds the reward card shows before closing
local PULSE_DURATION     = 1.2    -- seconds per pulse cycle on reward card

local RARITY_NAMES = {
	[1] = "Common",  [2] = "Uncommon", [3] = "Rare",    [4] = "Epic",
	[5] = "Legendary", [6] = "Mythic", [7] = "Transcendent",
}

-- ── Rarity gradient helpers (shared with PurchasedModule pattern) ───────────

local _rarityGradients: Instance? = nil
pcall(function()
	_rarityGradients = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("RarityGradients")
end)

local TEXTLABEL_DARKEN = 0.85

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
	if not _rarityGradients then return end
	local isTranscendent = rarityName == "Transcendent"
	for _, desc in parent:GetDescendants() do
		if desc:IsA("UIGradient") then
			if desc.Name == "RarityGradient" then
				local source = (_rarityGradients :: Instance):FindFirstChild(rarityName)
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
				local source = (_rarityGradients :: Instance):FindFirstChild(rarityName .. "Stroke")
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

-- ── Gift asset helper ───────────────────────────────────────────────────────

local function getGiftAsset(giftKey: string): Folder?
	local ok, result = pcall(function()
		return ReplicatedStorage:FindFirstChild("ShopAssets")
			and ReplicatedStorage.ShopAssets:FindFirstChild("Gifts")
			and ReplicatedStorage.ShopAssets.Gifts:FindFirstChild(giftKey)
	end)
	return ok and result or nil
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function HatchSequenceModule:Init(ctx: any)
	self._ctx       = ctx
	self._janitor   = ctx.UI.Cleaner.new()
	self._frame     = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("HatchSequence")
	self._playing   = false
	self._rockTween = nil :: Tween?
	self._spinTween = nil :: Tween?
	self._pulseTween = nil :: Tween?
	self._shakeConn = nil :: RBXScriptConnection?

	if not self._frame then
		warn("[HatchSequenceModule] Frame 'HatchSequence' not found")
		return
	end

	-- HatchSequence's own UIScale (starts ~0, tween to 1 when opening)
	self._frameScale = self._frame:FindFirstChildOfClass("UIScale") :: UIScale?

	-- Cache holder elements
	self._holder = self._frame:FindFirstChild("holder")
	self._hatched = self._frame:FindFirstChild("hatched")

	if self._holder then
		self._holderScale = self._holder:FindFirstChildOfClass("UIScale") :: UIScale?
		self._gift        = self._holder:FindFirstChild("gift") :: ImageLabel?
		self._title       = self._holder:FindFirstChild("Title") :: TextLabel?
		self._titleScale  = self._title and (self._title :: Instance):FindFirstChildOfClass("UIScale") :: UIScale?
		-- Gift's own UIScale (starts ~0, used for drop-in and shrink)
		self._giftScale   = self._gift and (self._gift :: Instance):FindFirstChildOfClass("UIScale") :: UIScale?
	end

	-- Cache hatched elements
	if self._hatched then
		self._hatchedScale    = self._hatched:FindFirstChildOfClass("UIScale") :: UIScale?
		self._shine           = self._hatched:FindFirstChild("Shine") :: ImageLabel?
		self._templateWeapon  = self._hatched:FindFirstChild("Template_Weapon")
		self._templateArmor   = self._hatched:FindFirstChild("Template_Armor")
		self._templateSpeed   = self._hatched:FindFirstChild("Template_Speed")
	end

	-- External asset folders
	self._weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")

	-- Register on ctx so OpenGiftModule can call :Play()
	ctx.HatchSequence = self

	self._frame.Visible = false
	print("[HatchSequenceModule] Init OK")
end

function HatchSequenceModule:Start()
	-- No runtime listeners needed
end

-- ── Public API ──────────────────────────────────────────────────────────────

--- Play the full hatching sequence.
--- giftData    = { giftKey = "Blue", displayName = "Common Gift", icon = "rbxassetid://..." }
--- rewardResult = { kind, tier, description, success, weaponKey?, amount?, steps?, ... }
--- onComplete  = optional callback fired after the sequence finishes
function HatchSequenceModule:Play(giftData: any, rewardResult: any, onComplete: (() -> ())?)
	if self._playing then return end
	if not self._frame or not self._holder or not self._hatched then return end

	self._playing = true
	task.spawn(function()
		local ok, err = pcall(function()
			self:_runSequence(giftData, rewardResult)
		end)
		if not ok then
			warn("[HatchSequenceModule] Sequence error:", err)
		end
		self._playing = false
		if onComplete then
			pcall(onComplete)
		end
	end)
end

-- ── Main Sequence ───────────────────────────────────────────────────────────

function HatchSequenceModule:_runSequence(giftData, rewardResult)
	self:_resetAll()

	-- Set gift icon — clone full Icon from ShopAssets.Gifts.[giftKey]
	-- (supports multi-layer icons with child ImageLabels)
	if self._gift and giftData and giftData.giftKey then
		local gift = self._gift :: ImageLabel
		-- Clear any previously cloned icon
		for _, child in (gift :: Instance):GetChildren() do
			if child.Name == "GiftIcon" then child:Destroy() end
		end
		gift.Image = ""

		local asset = getGiftAsset(giftData.giftKey)
		if asset then
			local sourceIcon = asset:FindFirstChild("Icon")
			if sourceIcon and sourceIcon:IsA("ImageLabel") then
				local clone = sourceIcon:Clone()
				clone.Name = "GiftIcon"
				clone.Size = UDim2.new(1, 0, 1, 0)
				clone.Position = UDim2.new(0.5, 0, 0.5, 0)
				clone.AnchorPoint = Vector2.new(0.5, 0.5)
				clone.BackgroundTransparency = 1
				clone.Parent = gift
			end
		end
	end

	-- ─── Phase 1: Intro (holder drops in) ───────────────────────────────

	self._frame.Visible = true
	self._holder.Visible = true

	-- Initial states
	if self._frameScale then (self._frameScale :: UIScale).Scale = 0 end
	if self._holderScale then (self._holderScale :: UIScale).Scale = 0 end
	if self._hatchedScale then (self._hatchedScale :: UIScale).Scale = 0 end
	if self._giftScale then (self._giftScale :: UIScale).Scale = 0 end
	if self._gift then
		local g = self._gift :: ImageLabel
		g.Position = UDim2.new(0.5, 0, -1, 0)  -- above frame
		g.Visible  = true
	end
	if self._titleScale then (self._titleScale :: UIScale).Scale = 0 end

	-- Tween HatchSequence frame UIScale from 0 → 1
	if self._frameScale then
		local frameInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(self._frameScale :: Instance, frameInfo, { Scale = 1 }):Play()
	end

	-- Tween holder scale in
	if self._holderScale then
		local info = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(self._holderScale :: Instance, info, { Scale = HOLDER_REST_SCALE }):Play()
	end
	task.wait(0.2)

	-- Tween gift UIScale from 0 → 1 (reveal) and drop from above into center
	if self._giftScale then
		local giftScaleInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(self._giftScale :: Instance, giftScaleInfo, { Scale = 1 }):Play()
	end
	if self._gift then
		local dropInfo = TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
		local dropTween = TweenService:Create(self._gift :: Instance, dropInfo, {
			Position = UDim2.new(0.5, 0, 0.5, 0),
		})
		dropTween:Play()
		dropTween.Completed:Wait()
	end

	-- Show "Click To Open" title
	if self._titleScale then
		local titleInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(self._titleScale :: Instance, titleInfo, { Scale = 1 }):Play()
	end
	task.wait(0.1)

	-- Start rocking animation
	self:_startRocking()

	-- Sound
	pcall(function() self._ctx.UI.Sound:Play("cartoon_pop") end)

	-- ─── Phase 2: Wait for click ────────────────────────────────────────

	local clicked = false
	local clickConn: RBXScriptConnection? = nil

	if self._gift then
		local giftImg = self._gift :: ImageLabel
		giftImg.Active = true
		clickConn = giftImg.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				clicked = true
			end
		end)
	end

	-- Safety timeout: 30 seconds
	local waitStart = tick()
	while not clicked and (tick() - waitStart) < 30 do
		task.wait()
	end
	if clickConn then (clickConn :: RBXScriptConnection):Disconnect() end

	-- ─── Phase 3: Hatch (shrink + shake gift) ───────────────────────────

	self:_stopRocking()

	-- Hide "Click To Open"
	if self._titleScale then
		TweenService:Create(
			self._titleScale :: Instance,
			TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = 0 }
		):Play()
	end

	-- Shrink + shake the gift image (uses giftScale if available, else Size)
	self:_shrinkAndShake()
	task.wait(0.05)

	-- ─── Phase 4: Reveal ────────────────────────────────────────────────

	-- Shrink holder UIScale to 0 (transition away from landing screen)
	if self._holderScale then
		TweenService:Create(
			self._holderScale :: Instance,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = 0 }
		):Play()
	end
	task.wait(0.15)

	-- Populate the correct reward template
	local template = self:_populateTemplate(rewardResult)

	-- Tween hatched UIScale in with bounce (transition to hatched screen)
	if self._hatchedScale then
		local revealInfo = TweenInfo.new(REVEAL_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(self._hatchedScale :: Instance, revealInfo, { Scale = HOLDER_REST_SCALE }):Play()
	end

	-- Spin the Shine
	self:_startShineSpin()

	-- Pulse the reward card
	if template then
		self:_startPulse(template)
	end

	-- Sound
	pcall(function() self._ctx.UI.Sound:Play("cartoon_pop") end)

	-- ─── Phase 5: Auto-close ────────────────────────────────────────────

	task.wait(AUTO_CLOSE_DELAY)

	-- Shrink hatched out
	if self._hatchedScale then
		local closeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		local closeTween = TweenService:Create(self._hatchedScale :: Instance, closeInfo, { Scale = 0 })
		closeTween:Play()
		closeTween.Completed:Wait()
	end

	-- Shrink the master frame UIScale to 0
	if self._frameScale then
		local frameClose = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local frameTween = TweenService:Create(self._frameScale :: Instance, frameClose, { Scale = 0 })
		frameTween:Play()
		frameTween.Completed:Wait()
	end

	self:_cleanup()
end

-- ── Reset / Cleanup ─────────────────────────────────────────────────────────

function HatchSequenceModule:_resetAll()
	self:_stopRocking()
	self:_stopShineSpin()
	self:_stopPulse()
	self:_stopShake()

	if self._frameScale then (self._frameScale :: UIScale).Scale = 0 end
	if self._holderScale then (self._holderScale :: UIScale).Scale = 0 end
	if self._hatchedScale then (self._hatchedScale :: UIScale).Scale = 0 end
	if self._giftScale then (self._giftScale :: UIScale).Scale = 0 end
	if self._titleScale then (self._titleScale :: UIScale).Scale = 0 end

	if self._gift then
		local g = self._gift :: ImageLabel
		g.Position = UDim2.new(0.5, 0, -1, 0)
		g.Rotation = 0
		g.Visible  = true
		-- Clean up cloned gift icons
		for _, child in (g :: Instance):GetChildren() do
			if child.Name == "GiftIcon" then child:Destroy() end
		end
	end

	-- Hide all templates
	if self._templateWeapon then self._templateWeapon.Visible = false end
	if self._templateArmor then self._templateArmor.Visible = false end
	if self._templateSpeed then self._templateSpeed.Visible = false end

	self._frame.Visible = false
end

function HatchSequenceModule:_cleanup()
	self:_stopRocking()
	self:_stopShineSpin()
	self:_stopPulse()
	self:_stopShake()

	-- Hide templates
	if self._templateWeapon then self._templateWeapon.Visible = false end
	if self._templateArmor then self._templateArmor.Visible = false end
	if self._templateSpeed then self._templateSpeed.Visible = false end

	-- Reset all UIScales to 0
	if self._frameScale then (self._frameScale :: UIScale).Scale = 0 end
	if self._holderScale then (self._holderScale :: UIScale).Scale = 0 end
	if self._hatchedScale then (self._hatchedScale :: UIScale).Scale = 0 end
	if self._giftScale then (self._giftScale :: UIScale).Scale = 0 end
	if self._titleScale then (self._titleScale :: UIScale).Scale = 0 end

	-- Reset gift position
	if self._gift then
		local g = self._gift :: ImageLabel
		g.Position = UDim2.new(0.5, 0, -1, 0)
		g.Rotation = 0
		g.Visible  = true
		-- Clean up cloned gift icons
		for _, child in (g :: Instance):GetChildren() do
			if child.Name == "GiftIcon" then child:Destroy() end
		end
	end

	self._frame.Visible = false
	self._holder.Visible = true
end

-- ── Rocking Animation ───────────────────────────────────────────────────────

function HatchSequenceModule:_startRocking()
	self:_stopRocking()
	if not self._gift then return end

	local giftImg = self._gift :: ImageLabel
	giftImg.Rotation = -ROCK_ANGLE
	local info = TweenInfo.new(
		ROCK_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,    -- infinite
		true   -- reverses
	)
	self._rockTween = TweenService:Create(giftImg :: Instance, info, { Rotation = ROCK_ANGLE })
	self._rockTween:Play()
end

function HatchSequenceModule:_stopRocking()
	if self._rockTween then
		self._rockTween:Cancel()
		self._rockTween = nil
	end
	if self._gift then
		(self._gift :: ImageLabel).Rotation = 0
	end
end

-- ── Shrink + Shake ──────────────────────────────────────────────────────────

function HatchSequenceModule:_shrinkAndShake()
	if not self._gift then return end

	local gift = self._gift :: ImageLabel
	local startTime = tick()
	local done = false

	-- Shake via Heartbeat (random XY jitter)
	self._shakeConn = RunService.Heartbeat:Connect(function()
		if done then return end
		local elapsed = tick() - startTime
		local progress = math.min(elapsed / SHRINK_DURATION, 1)

		local intensity = math.max(2, math.floor(8 * (1 - progress)))
		local ox = math.random(-intensity, intensity)
		local oy = math.random(-intensity, intensity)
		gift.Position = UDim2.new(0.5, ox, 0.5, oy)

		if progress >= 1 then
			done = true
		end
	end)

	-- Shrink via giftScale (UIScale) if available, else fall back to Size
	local shrinkInfo = TweenInfo.new(SHRINK_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local shrinkTween
	if self._giftScale then
		shrinkTween = TweenService:Create(self._giftScale :: Instance, shrinkInfo, { Scale = 0 })
	else
		shrinkTween = TweenService:Create(gift :: Instance, shrinkInfo, {
			Size = UDim2.fromScale(0, 0),
		})
	end
	shrinkTween:Play()
	shrinkTween.Completed:Wait()

	self:_stopShake()
	gift.Visible = false
end

function HatchSequenceModule:_stopShake()
	if self._shakeConn then
		self._shakeConn:Disconnect()
		self._shakeConn = nil
	end
end

-- ── Shine Spin ──────────────────────────────────────────────────────────────

function HatchSequenceModule:_startShineSpin()
	self:_stopShineSpin()
	if not self._shine then return end

	local shineImg = self._shine :: ImageLabel
	shineImg.Rotation = 0
	local info = TweenInfo.new(SPIN_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	self._spinTween = TweenService:Create(shineImg :: Instance, info, { Rotation = 360 })
	self._spinTween:Play()
end

function HatchSequenceModule:_stopShineSpin()
	if self._spinTween then
		self._spinTween:Cancel()
		self._spinTween = nil
	end
end

-- ── Pulse ───────────────────────────────────────────────────────────────────

function HatchSequenceModule:_startPulse(template: Instance)
	self:_stopPulse()

	local uiScale = template:FindFirstChildOfClass("UIScale")
	if not uiScale then return end

	local us = uiScale :: UIScale
	us.Scale = 1
	local info = TweenInfo.new(
		PULSE_DURATION / 2,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,    -- infinite
		true   -- reverses 1 -> 1.05 -> 1
	)
	self._pulseTween = TweenService:Create(uiScale :: Instance, info, { Scale = 1.05 })
	self._pulseTween:Play()
end

function HatchSequenceModule:_stopPulse()
	if self._pulseTween then
		self._pulseTween:Cancel()
		self._pulseTween = nil
	end
end

-- ── Template Population ─────────────────────────────────────────────────────

function HatchSequenceModule:_populateTemplate(rewardResult: any): Instance?
	if not rewardResult then return nil end

	local kind = rewardResult.kind
	if kind == "Weapon" then
		return self:_populateWeaponTemplate(rewardResult)
	elseif kind == "ArmorStep" then
		return self:_populateArmorTemplate(rewardResult)
	elseif kind == "SpeedStep" then
		return self:_populateSpeedTemplate(rewardResult)
	else
		-- Cash / XP / Boost → fallback to weapon template with custom text
		return self:_populateFallbackTemplate(rewardResult)
	end
end

function HatchSequenceModule:_populateWeaponTemplate(result: any): Instance?
	local template = self._templateWeapon
	if not template then return nil end

	local weaponKey = result.weaponKey or ""
	local container = template:FindFirstChild("container")
	if not container then template.Visible = true; return template end

	-- Read weapon data from ReplicatedStorage.Weapons
	local weaponFolder = self._weaponsFolder and self._weaponsFolder:FindFirstChild(weaponKey)
	local displayName = weaponKey
	local rarityNum = 1
	local damage = 10

	if weaponFolder then
		displayName = weaponFolder:GetAttribute("DisplayName") or weaponKey
		rarityNum   = weaponFolder:GetAttribute("Rarity") or 1
		damage      = weaponFolder:GetAttribute("Damage") or 10
	end

	local rarityName = RARITY_NAMES[rarityNum] or "Common"

	-- Title
	local titleLbl = container:FindFirstChild("Title") :: TextLabel?
	if titleLbl then
		(titleLbl :: TextLabel).Text = displayName
		local title2 = (titleLbl :: Instance):FindFirstChild("Title2") :: TextLabel?
		if title2 then title2.Text = displayName end
	end

	-- Rarity
	local rarityLbl = container:FindFirstChild("Rarity") :: TextLabel?
	if rarityLbl then
		(rarityLbl :: TextLabel).Text = rarityName
		local rarity2 = (rarityLbl :: Instance):FindFirstChild("Rarity2") :: TextLabel?
		if rarity2 then rarity2.Text = rarityName end
	end

	-- Damage
	local damageLbl = container:FindFirstChild("Damage") :: TextLabel?
	if damageLbl then
		local dmgLbl = damageLbl :: TextLabel
		dmgLbl.Text = tostring(damage)
		dmgLbl.Visible = true
		local damage2 = (damageLbl :: Instance):FindFirstChild("Damage2") :: TextLabel?
		if damage2 then damage2.Text = tostring(damage) end
	end

	-- Clone weapon icon into IconHolder
	local iconHolder = container:FindFirstChild("IconHolder") :: Frame?
	if iconHolder then
		-- Clear previously cloned icons (keep constraints)
		for _, child in ipairs((iconHolder :: Frame):GetChildren()) do
			if not child:IsA("UIConstraint")
				and not child:IsA("UIAspectRatioConstraint") then
				child:Destroy()
			end
		end

		if weaponFolder then
			local iconSource = weaponFolder:FindFirstChild("Icon")
			if iconSource then
				local iconClone = iconSource:Clone()
				iconClone.Name = "WeaponIcon"
				if iconClone:IsA("GuiObject") then
					(iconClone :: GuiObject).Size        = UDim2.fromScale(1, 1)
					;(iconClone :: GuiObject).Position    = UDim2.fromScale(0.5, 0.5)
					;(iconClone :: GuiObject).AnchorPoint = Vector2.new(0.5, 0.5)
				end
				iconClone.Parent = iconHolder
			end
		end
	end

	-- Rarity gradients
	applyRarityGradients(template, rarityName)

	-- Show "New!" for weapons
	local newLabel = container:FindFirstChild("newlabel") :: TextLabel?
	if newLabel then (newLabel :: TextLabel).Visible = true end

	template.Visible = true
	return template
end

function HatchSequenceModule:_populateArmorTemplate(result: any): Instance?
	local template = self._templateArmor
	if not template then return nil end

	local steps = result.steps or 1
	local container = template:FindFirstChild("container")
	if not container then template.Visible = true; return template end

	-- Step amount
	local stepLbl = container:FindFirstChild("Step") :: TextLabel?
	if stepLbl then
		(stepLbl :: TextLabel).Text = "+" .. tostring(steps)
		local step2 = (stepLbl :: Instance):FindFirstChild("Damage2") :: TextLabel?
		if step2 then step2.Text = "+" .. tostring(steps) end
	end

	-- Hide "New!"
	local newLabel = container:FindFirstChild("newlabel") :: TextLabel?
	if newLabel then (newLabel :: TextLabel).Visible = false end

	template.Visible = true
	return template
end

function HatchSequenceModule:_populateSpeedTemplate(result: any): Instance?
	local template = self._templateSpeed
	if not template then return nil end

	local steps = result.steps or 1
	local container = template:FindFirstChild("container")
	if not container then template.Visible = true; return template end

	-- Step amount
	local stepLbl = container:FindFirstChild("Step") :: TextLabel?
	if stepLbl then
		(stepLbl :: TextLabel).Text = "+" .. tostring(steps)
		local step2 = (stepLbl :: Instance):FindFirstChild("Damage2") :: TextLabel?
		if step2 then step2.Text = "+" .. tostring(steps) end
	end

	-- Hide "New!"
	local newLabel = container:FindFirstChild("newlabel") :: TextLabel?
	if newLabel then (newLabel :: TextLabel).Visible = false end

	template.Visible = true
	return template
end

function HatchSequenceModule:_populateFallbackTemplate(result: any): Instance?
	-- Cash / XP / Boost → reuse the weapon template with custom text
	local template = self._templateWeapon
	if not template then return nil end

	local container = template:FindFirstChild("container")
	if not container then template.Visible = true; return template end

	local kind   = result.kind or "Cash"
	local amount = result.amount or 0

	-- Title
	local titleText = kind
	if kind == "Cash" then
		titleText = "$" .. tostring(amount)
	elseif kind == "XP" then
		titleText = tostring(amount) .. " XP"
	elseif kind == "Boost" then
		titleText = (result.boostType or "Boost")
	end

	local titleLbl = container:FindFirstChild("Title") :: TextLabel?
	if titleLbl then
		(titleLbl :: TextLabel).Text = titleText
		local title2 = (titleLbl :: Instance):FindFirstChild("Title2") :: TextLabel?
		if title2 then title2.Text = titleText end
	end

	-- Rarity label → show the kind
	local rarityLbl = container:FindFirstChild("Rarity") :: TextLabel?
	if rarityLbl then
		(rarityLbl :: TextLabel).Text = kind
		local rarity2 = (rarityLbl :: Instance):FindFirstChild("Rarity2") :: TextLabel?
		if rarity2 then rarity2.Text = kind end
	end

	-- Hide damage
	local damageLbl = container:FindFirstChild("Damage") :: TextLabel?
	if damageLbl then (damageLbl :: TextLabel).Visible = false end

	-- Hide "New!"
	local newLabel = container:FindFirstChild("newlabel") :: TextLabel?
	if newLabel then (newLabel :: TextLabel).Visible = false end

	-- Clear icon holder (no specific icon for cash/xp)
	local iconHolder = container:FindFirstChild("IconHolder") :: Frame?
	if iconHolder then
		for _, child in ipairs((iconHolder :: Frame):GetChildren()) do
			if not child:IsA("UIConstraint")
				and not child:IsA("UIAspectRatioConstraint") then
				child:Destroy()
			end
		end
	end

	template.Visible = true
	return template
end

-- ── Destroy ─────────────────────────────────────────────────────────────────

function HatchSequenceModule:Destroy()
	self:_cleanup()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return HatchSequenceModule
