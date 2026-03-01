--!strict
-- PurchasedModule.lua  |  Frame: Purchased
-- Toast popup when the player purchases a weapon.
-- Triggered by server Notify event with type = "purchased".
-- Auto-closes after DISPLAY_SECONDS.
-- Shows "New!" label + spinning Shine ONLY when isNew == true.
--
-- WIRE-UP (Studio frame hierarchy):
--   Purchased [Frame]
--     Canvas [CanvasGroup]
--       Header [Frame]
--         newlable [TextLabel] "New!"          ← conditional visibility
--         Title [TextLabel]                     ← weapon display name
--           Title2 [TextLabel]                  ← shadow copy
--         Rarity [TextLabel]                    ← rarity name
--         Shines [CanvasGroup]                  ← conditional visibility
--           Shine [Frame] x2
--         Stud [ImageLabel]
--     IconHolder [Frame]
--       Shine [ImageLabel]                      ← spin this (conditional)
--       UIAspectRatioConstraint
--     UIScale [UIScale]

local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PurchasedModule = {}
PurchasedModule.__index = PurchasedModule

-- ── Rarity gradient helper ──────────────────────────────────────────────────
local _rarityGradients = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("RarityGradients")

local TEXTLABEL_DARKEN = 0.85 -- 15% darker on TextLabels

local function darkenColorSequence(cs: ColorSequence, factor: number): ColorSequence
	local kps = {}
	for _, kp in ipairs(cs.Keypoints) do
		local c = kp.Value
		table.insert(kps, ColorSequenceKeypoint.new(kp.Time,
			Color3.new(c.R * factor, c.G * factor, c.B * factor)))
	end
	return ColorSequence.new(kps)
end

local CollectionService = game:GetService("CollectionService")

local function applyRarityGradients(parent: Instance, rarityName: string)
	local isTranscendent = rarityName == "Transcendent"
	for _, desc in parent:GetDescendants() do
		if desc:IsA("UIGradient") then
			if desc.Name == "RarityGradient" then
				local source = _rarityGradients:FindFirstChild(rarityName)
				if source and source:IsA("UIGradient") then
					local color = source.Color
					if desc.Parent and desc.Parent:IsA("TextLabel") then
						color = darkenColorSequence(color, TEXTLABEL_DARKEN)
					end
					desc.Color = color
				end
				-- Tag/untag for rainbow animation (fill only)
				if isTranscendent then
					CollectionService:AddTag(desc, "RainbowGradient")
				else
					CollectionService:RemoveTag(desc, "RainbowGradient")
				end
			elseif desc.Name == "RarityGradientStroke" then
				local source = _rarityGradients:FindFirstChild(rarityName .. "Stroke")
				if source and source:IsA("UIGradient") then
					desc.Color = source.Color
				end
				-- Tag/untag for rainbow animation (stroke only)
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

local DISPLAY_SECONDS  = 4     -- how long the popup stays fully visible
local SHRINK_DURATION  = 1.0   -- how long the shrink-out tween takes
local SPIN_DURATION    = 12    -- seconds per full shine rotation
local BOUNCE_UP_TIME   = 0.15  -- tween to 1.1
local BOUNCE_DOWN_TIME = 0.1   -- settle to 1

local RARITY_NAMES = {
	[1] = "Common",
	[2] = "Uncommon",
	[3] = "Rare",
	[4] = "Epic",
	[5] = "Legendary",
	[6] = "Mythic",
	[7] = "Transcendent",
}

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function PurchasedModule:Init(ctx: any)
	self._ctx         = ctx
	self._janitor     = ctx.UI.Cleaner.new()
	self._autoClose   = nil :: thread?
	self._spinTween   = nil :: Tween?
	self._shrinkTween = nil :: Tween?
	self._open        = false
	self._showing     = false -- true while a purchase sequence is active (show → shrink → done)
	self._queue       = {}    -- queued payloads waiting to show
	self._frame       = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Purchased")

	if not self._frame then
		warn("[PurchasedModule] Frame 'Purchased' not found")
		return
	end

	-- Cache refs
	self._titleLbl        = find(self._frame, "Title")      :: TextLabel?
	self._rarityLbl       = find(self._frame, "Rarity")     :: TextLabel?
	self._iconHolder      = self._frame:FindFirstChild("IconHolder") :: Frame?
	self._iconHolderShine = self._iconHolder and self._iconHolder:FindFirstChild("Shine") :: ImageLabel?
	self._uiScale         = self._frame:FindFirstChildOfClass("UIScale") :: UIScale?
	self._newlable        = find(self._frame, "newlable")   :: TextLabel?  -- Studio typo preserved
	self._shines          = find(self._frame, "Shines")     :: CanvasGroup?

	-- Weapons folder in ReplicatedStorage
	self._weaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")

	-- Wire GIVEGUNTEXTBUTTON (dev buy button)
	local gui = ctx.RootGui
	if gui then
		local buyBtn = gui:FindFirstChild("GIVEGUNTEXTBUTTON")
		if buyBtn and buyBtn:IsA("TextButton") then
			self._janitor:Add(buyBtn.MouseButton1Click:Connect(function()
				local weaponActionRF = ctx.Net:GetFunction("WeaponAction")
				if weaponActionRF then
					weaponActionRF:InvokeServer({
						action = "buy",
						weapon = "AK12",
						cost   = 5000,
					})
				end
			end))
			print("[PurchasedModule] GIVEGUNTEXTBUTTON wired")
		end
	end

	print("[PurchasedModule] Init OK")
end

function PurchasedModule:Start()
	if not self._frame then return end

	-- Listen for server purchased notification
	local notifyRE = self._ctx.Net:GetEvent("Notify")
	self._janitor:Add(notifyRE.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.type == "purchased" then
			self:_enqueue(payload)
		end
	end))

	print("[PurchasedModule] Start OK")
end

-- ── Queue ────────────────────────────────────────────────────────────────────

function PurchasedModule:_enqueue(payload: any)
	if self._showing then
		-- Another purchase is playing — queue this one
		table.insert(self._queue, payload)
		return
	end
	self:_showImmediate(payload)
end

function PurchasedModule:_playNext()
	if #self._queue == 0 then
		self._showing = false
		return
	end
	local next = table.remove(self._queue, 1)
	self:_showImmediate(next)
end

-- ── Show / Hide ──────────────────────────────────────────────────────────────

function PurchasedModule:_showImmediate(payload: any)
	if not self._frame then return end

	self._showing = true

	local weaponKey  = tostring(payload.weaponKey or "")
	local isNew      = payload.isNew == true
	local displayName = tostring(payload.name or weaponKey)
	local rarityNum  = tonumber(payload.rarity) or 1
	local rarityName = RARITY_NAMES[rarityNum] or "Common"

	-- Populate title + shadow
	if self._titleLbl then
		(self._titleLbl :: TextLabel).Text = displayName
		local title2 = (self._titleLbl :: Instance):FindFirstChild("Title2") :: TextLabel?
		if title2 then
			title2.Text = displayName
		end
	end

	-- Populate rarity
	if self._rarityLbl then
		(self._rarityLbl :: TextLabel).Text = rarityName
	end

	-- Rarity gradients (fill + stroke)
	applyRarityGradients(self._frame, rarityName)

	-- Clone icon from ReplicatedStorage.Weapons[weaponKey].Icon into IconHolder
	self:_setIcon(weaponKey)

	-- Conditional new/shine
	if self._newlable then
		(self._newlable :: TextLabel).Visible = isNew
	end
	if self._shines then
		(self._shines :: CanvasGroup).Visible = isNew
	end
	if self._iconHolderShine then
		(self._iconHolderShine :: ImageLabel).Visible = isNew
	end

	if isNew then
		self:_startShine()
	else
		self:_stopShine()
	end

	-- Cancel any previous shrink / auto-close
	self:_cancelTimers()

	-- Open directly (bypass Router — this is a toast, not a menu frame)
	self._open = true
	self._frame.Visible = true
	if self._uiScale then
		(self._uiScale :: UIScale).Scale = 0
		local bounceInfo = TweenInfo.new(BOUNCE_UP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local t1 = TweenService:Create(self._uiScale :: Instance, bounceInfo, { Scale = 1.1 })
		t1.Completed:Once(function()
			local settleInfo = TweenInfo.new(BOUNCE_DOWN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			TweenService:Create(self._uiScale :: Instance, settleInfo, { Scale = 1 }):Play()
		end)
		t1:Play()
	end

	-- After DISPLAY_SECONDS, smoothly shrink to 0 then hide
	self._autoClose = task.delay(DISPLAY_SECONDS, function()
		self:_shrinkOut()
		self._autoClose = nil
	end)
end

function PurchasedModule:_cancelTimers()
	if self._autoClose then
		task.cancel(self._autoClose)
		self._autoClose = nil
	end
	if self._shrinkTween then
		self._shrinkTween:Cancel()
		self._shrinkTween = nil
	end
end

-- Smoothly scale the popup down to 0, then clean up
function PurchasedModule:_shrinkOut()
	if not self._open then return end
	if not self._uiScale then
		self:_hide()
		return
	end

	local info = TweenInfo.new(SHRINK_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	self._shrinkTween = TweenService:Create(self._uiScale :: Instance, info, { Scale = 0 })
	self._shrinkTween.Completed:Once(function()
		self._shrinkTween = nil
		self._open = false
		self:_stopShine()
		self._frame.Visible = false
		-- Reset UIScale so the next bounce-in starts clean
		if self._uiScale then
			(self._uiScale :: UIScale).Scale = 1
		end
		-- Play next queued purchase if any
		self:_playNext()
	end)
	self._shrinkTween:Play()
end

function PurchasedModule:_hide()
	if not self._frame then return end
	if not self._open then return end
	self._open = false

	self:_cancelTimers()
	self:_stopShine()
	self._frame.Visible = false

	-- Play next queued purchase if any
	self:_playNext()
end

-- ── Icon ─────────────────────────────────────────────────────────────────────

function PurchasedModule:_setIcon(weaponKey: string)
	if not self._iconHolder then return end

	-- Clear any previously cloned icon (preserve Shine + constraints)
	for _, child in ipairs((self._iconHolder :: Frame):GetChildren()) do
		if child.Name ~= "Shine"
			and not child:IsA("UIConstraint")
			and not child:IsA("UIAspectRatioConstraint") then
			child:Destroy()
		end
	end

	if not self._weaponsFolder then return end

	local weaponFolder = self._weaponsFolder:FindFirstChild(weaponKey)
	if not weaponFolder then return end

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

	iconClone.Parent = self._iconHolder
end

-- ── Shine Spin ───────────────────────────────────────────────────────────────

function PurchasedModule:_startShine()
	self:_stopShine()

	local shine = self._iconHolderShine
	if not shine then return end

	-- Slow continuous 360 spin
	(shine :: ImageLabel).Rotation = 0
	local tweenInfo = TweenInfo.new(SPIN_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	self._spinTween = TweenService:Create(shine :: Instance, tweenInfo, { Rotation = 360 })
	self._spinTween:Play()
end

function PurchasedModule:_stopShine()
	if self._spinTween then
		self._spinTween:Cancel()
		self._spinTween = nil
	end
end

-- ── Cleanup ──────────────────────────────────────────────────────────────────

function PurchasedModule:Destroy()
	self:_cancelTimers()
	self:_stopShine()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return PurchasedModule
