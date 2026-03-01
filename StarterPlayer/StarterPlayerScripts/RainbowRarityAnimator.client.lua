--!strict
-- RainbowRarityAnimator.client.lua
-- Continuously shifts the hue of all UIGradients tagged "RainbowGradient"
-- to create a flowing rainbow effect for Transcendent rarity items.
--
-- Also animates:
--   "RainbowNeonPart"  – BasePart.Color cycles at SPEED (same as gradients)
--   "RainbowHighlight" – Highlight OutlineColor/FillColor cycles at HIGHLIGHT_SPEED (faster)
--
-- Tags are applied by applyRarityGradients() in UI modules and BuyWeaponModule.

local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local GRADIENT_TAG    = "RainbowGradient"
local NEON_TAG        = "RainbowNeonPart"
local HIGHLIGHT_TAG   = "RainbowHighlight"

local SPEED           = 0.15   -- hue cycles/sec for gradients + neon parts
local HIGHLIGHT_SPEED = 0.25   -- hue cycles/sec for highlights (~67% faster)
local NUM_KEYPOINTS   = 8      -- keypoints in the rainbow sequence

-- Tracking dicts
local gradients:  { [UIGradient]: true }  = {}
local neonParts:  { [BasePart]: true }    = {}
local highlights: { [Highlight]: true }   = {}

-- Build a rainbow ColorSequence with hue shifted by hueOffset (0-1)
local function buildRainbow(hueOffset: number): ColorSequence
	local kps = {}
	for i = 0, NUM_KEYPOINTS do
		local t = i / NUM_KEYPOINTS
		local hue = (t + hueOffset) % 1
		table.insert(kps, ColorSequenceKeypoint.new(t, Color3.fromHSV(hue, 0.85, 1)))
	end
	return ColorSequence.new(kps)
end

--/////////////////////////////
-- Gradient tag handlers
--/////////////////////////////
local function onGradientAdded(inst: Instance)
	if inst:IsA("UIGradient") then
		gradients[inst] = true
	end
end
local function onGradientRemoved(inst: Instance)
	if inst:IsA("UIGradient") then
		gradients[inst] = nil
	end
end

--/////////////////////////////
-- Neon part tag handlers
--/////////////////////////////
local function onNeonAdded(inst: Instance)
	if inst:IsA("BasePart") then
		neonParts[inst :: BasePart] = true
	end
end
local function onNeonRemoved(inst: Instance)
	if inst:IsA("BasePart") then
		neonParts[inst :: BasePart] = nil
	end
end

--/////////////////////////////
-- Highlight tag handlers
--/////////////////////////////
local function onHighlightAdded(inst: Instance)
	if inst:IsA("Highlight") then
		highlights[inst :: Highlight] = true
	end
end
local function onHighlightRemoved(inst: Instance)
	if inst:IsA("Highlight") then
		highlights[inst :: Highlight] = nil
	end
end

-- Pick up any already-tagged instances
for _, inst in CollectionService:GetTagged(GRADIENT_TAG) do onGradientAdded(inst) end
for _, inst in CollectionService:GetTagged(NEON_TAG) do onNeonAdded(inst) end
for _, inst in CollectionService:GetTagged(HIGHLIGHT_TAG) do onHighlightAdded(inst) end

CollectionService:GetInstanceAddedSignal(GRADIENT_TAG):Connect(onGradientAdded)
CollectionService:GetInstanceRemovedSignal(GRADIENT_TAG):Connect(onGradientRemoved)
CollectionService:GetInstanceAddedSignal(NEON_TAG):Connect(onNeonAdded)
CollectionService:GetInstanceRemovedSignal(NEON_TAG):Connect(onNeonRemoved)
CollectionService:GetInstanceAddedSignal(HIGHLIGHT_TAG):Connect(onHighlightAdded)
CollectionService:GetInstanceRemovedSignal(HIGHLIGHT_TAG):Connect(onHighlightRemoved)

-- Animate hue shift every frame
local elapsed = 0

RunService.RenderStepped:Connect(function(dt: number)
	elapsed += dt

	-- ── UIGradients (rainbow color sequence) ──
	local hueOffset = (elapsed * SPEED) % 1
	local rainbow = buildRainbow(hueOffset)

	for grad in gradients do
		if grad.Parent then
			grad.Color = rainbow
		else
			gradients[grad] = nil
		end
	end

	-- ── Neon BaseParts (single color, same speed as gradients) ──
	local neonColor = Color3.fromHSV(hueOffset, 0.85, 1)

	for part in neonParts do
		if part.Parent then
			part.Color = neonColor
		else
			neonParts[part] = nil
		end
	end

	-- ── Highlights (single color, faster cycle) ──
	local hlHue = (elapsed * HIGHLIGHT_SPEED) % 1
	local hlOutline = Color3.fromHSV(hlHue, 0.85, 1)
	local hlFill    = Color3.fromHSV(hlHue, 0.50, 1) -- lighter / less saturated fill

	for hl in highlights do
		if hl.Parent then
			hl.OutlineColor = hlOutline
			hl.FillColor = hlFill
		else
			highlights[hl] = nil
		end
	end
end)

print("[RainbowRarityAnimator] Started")
