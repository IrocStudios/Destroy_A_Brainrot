--!strict
-- DiscoveryModule.lua  |  Frame: Discovery
-- Toast popup when the player discovers a new brainrot for the first time.
-- Triggered by server Notify event with type = "discovery".
-- Auto-closes after AUTO_CLOSE_SECONDS.
--
-- WIRE-UP (Studio frame hierarchy):
--   Discovery [Frame]
--     Canvas [CanvasGroup]
--       Header [Frame]
--         newlable [TextLabel] "New!"
--         Title [TextLabel]          ← brainrot display name
--           Title2 [TextLabel]       ← shadow copy of display name
--         Rarity [TextLabel]         ← rarity name
--         Shines [CanvasGroup]
--           Shine [Frame] x2
--         Stud [ImageLabel]
--     IconHolder [Frame]
--       Shine [ImageLabel]           ← spin this
--     UIScale [UIScale]

local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DiscoveryModule = {}
DiscoveryModule.__index = DiscoveryModule

-- ── Rarity gradient helper ──────────────────────────────────────────────────
local _rarityConfigInst = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("RarityConfig")

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

local DISPLAY_SECONDS  = 5     -- how long the popup stays fully visible
local SHRINK_DURATION  = 1.0   -- how long the shrink-out tween takes
local SPIN_DURATION    = 12    -- seconds per full shine rotation (slower = more elegant)

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function DiscoveryModule:Init(ctx: any)
	self._ctx         = ctx
	self._janitor     = ctx.UI.Cleaner.new()
	self._autoClose   = nil :: thread?
	self._spinTween   = nil :: Tween?
	self._shrinkTween = nil :: Tween?
	self._open        = false
	self._frame       = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Discovery")

	if not self._frame then
		warn("[DiscoveryModule] Frame 'Discovery' not found")
		return
	end

	-- Cache refs
	self._titleLbl      = find(self._frame, "Title")      :: TextLabel?  -- inside Header
	self._rarityLbl     = find(self._frame, "Rarity")     :: TextLabel?
	self._iconHolder    = self._frame:FindFirstChild("IconHolder") :: Frame?
	self._iconHolderShine = self._iconHolder and self._iconHolder:FindFirstChild("Shine") :: ImageLabel?
	self._uiScale         = self._frame:FindFirstChildOfClass("UIScale") :: UIScale?

	-- Brainrots folder in ReplicatedStorage (each child is a Folder with Body + Icon)
	self._brainrotsFolder = ReplicatedStorage:FindFirstChild("Brainrots")

	-- Discovery sound from LocalResources/Sound
	local localRes = ctx.RootGui and ctx.RootGui:FindFirstChild("LocalResources")
	local soundFolder = localRes and localRes:FindFirstChild("Sound")
	self._discoverySound = soundFolder and soundFolder:FindFirstChild("Discovery_Sound") :: Sound?
end

function DiscoveryModule:Start()
	if not self._frame then return end

	-- Listen for server discovery notification
	local notifyRE = self._ctx.Net:GetEvent("Notify")
	self._janitor:Add(notifyRE.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.type == "discovery" then
			self:Show(payload)
		end
	end))
end

-- ── Show / Hide ──────────────────────────────────────────────────────────────

function DiscoveryModule:Show(payload: any)
	if not self._frame then return end

	local brainrotId  = tostring(payload.brainrotId or payload.id or "")
	local displayName = tostring(payload.name or brainrotId)
	local rarityName  = tostring(payload.rarity or "Common")

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

	-- Clone icon from ReplicatedStorage.Brainrots[brainrotId].Icon into IconHolder
	self:_setIcon(brainrotId)

	-- Spin the Shine in IconHolder
	self:_startShine()

	-- Cancel any previous shrink / auto-close
	self:_cancelTimers()

	-- Play discovery sound
	if self._discoverySound then
		self._discoverySound:Play()
	end

	-- Open like a menu via Router (bounce tween in)
	self._open = true
	if self._ctx.Router then
		self._ctx.Router:Open("Discovery")
	end

	-- After DISPLAY_SECONDS, smoothly shrink to 0 then hide
	self._autoClose = task.delay(DISPLAY_SECONDS, function()
		self:_shrinkOut()
		self._autoClose = nil
	end)
end

function DiscoveryModule:_cancelTimers()
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
function DiscoveryModule:_shrinkOut()
	if not self._open then return end
	if not self._uiScale then
		-- No UIScale found, fall back to Router close
		self:_hide()
		return
	end

	local info = TweenInfo.new(SHRINK_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	self._shrinkTween = TweenService:Create(self._uiScale :: Instance, info, { Scale = 0 })
	self._shrinkTween.Completed:Once(function()
		self._shrinkTween = nil
		-- We already animated to scale 0, so hide directly without Router:Close
		-- (Router:Close would run its own scale-down animation, causing a double-close)
		self._open = false
		self:_stopShine()
		self._frame.Visible = false
		-- Reset UIScale to 1 so the next Show() / Router:Open works correctly
		if self._uiScale then
			(self._uiScale :: UIScale).Scale = 1
		end
	end)
	self._shrinkTween:Play()
end

function DiscoveryModule:_hide()
	if not self._frame then return end
	if not self._open then return end
	self._open = false

	self:_cancelTimers()
	self:_stopShine()

	if self._ctx.Router then
		self._ctx.Router:Close("Discovery")
	end
end

-- ── Icon ─────────────────────────────────────────────────────────────────────

function DiscoveryModule:_setIcon(brainrotId: string)
	if not self._iconHolder then return end

	-- Clear any previously cloned icon (anything that isn't the Shine)
	for _, child in ipairs((self._iconHolder :: Frame):GetChildren()) do
		if child.Name ~= "Shine" and not child:IsA("UIConstraint") and not child:IsA("UIAspectRatioConstraint") then
			child:Destroy()
		end
	end

	if not self._brainrotsFolder then return end

	-- Each brainrot is a Folder: { Body [Model], Icon [ImageLabel] }
	local brainrotFolder = self._brainrotsFolder:FindFirstChild(brainrotId)
	if not brainrotFolder then
		-- Fallback to Default
		brainrotFolder = self._brainrotsFolder:FindFirstChild("Default")
	end
	if not brainrotFolder then return end

	local iconTemplate = brainrotFolder:FindFirstChild("Icon")
	if not iconTemplate then return end

	local iconClone = iconTemplate:Clone()
	iconClone.Name = "BrainrotIcon"

	-- Fill the holder
	if iconClone:IsA("GuiObject") then
		iconClone.Size = UDim2.fromScale(1, 1)
		iconClone.Position = UDim2.fromScale(0.5, 0.5)
		iconClone.AnchorPoint = Vector2.new(0.5, 0.5)
	end

	iconClone.Parent = self._iconHolder
end

-- ── Shine Spin ───────────────────────────────────────────────────────────────

function DiscoveryModule:_startShine()
	self:_stopShine()

	local shine = self._iconHolderShine
	if not shine then return end

	-- Slow continuous 360 spin
	(shine :: ImageLabel).Rotation = 0
	local tweenInfo = TweenInfo.new(SPIN_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	self._spinTween = TweenService:Create(shine :: Instance, tweenInfo, { Rotation = 360 })
	self._spinTween:Play()
end

function DiscoveryModule:_stopShine()
	if self._spinTween then
		self._spinTween:Cancel()
		self._spinTween = nil
	end
end

-- ── Cleanup ──────────────────────────────────────────────────────────────────

function DiscoveryModule:Destroy()
	self:_cancelTimers()
	self:_stopShine()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return DiscoveryModule
