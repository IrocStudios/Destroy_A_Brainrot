--!strict
-- RainbowRarityAnimator.client.lua
-- Continuously shifts the hue of all UIGradients tagged "RainbowGradient"
-- to create a flowing rainbow effect for Transcendent rarity items.
-- Tags are applied by applyRarityGradients() in UI modules.

local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local TAG = "RainbowGradient"
local SPEED = 0.15          -- hue cycles per second (lower = slower, smoother)
local NUM_KEYPOINTS = 8     -- keypoints in the rainbow sequence (more = smoother)

-- Track all tagged gradients
local gradients: { [UIGradient]: true } = {}

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

local function onAdded(inst: Instance)
	if inst:IsA("UIGradient") then
		gradients[inst] = true
	end
end

local function onRemoved(inst: Instance)
	if inst:IsA("UIGradient") then
		gradients[inst] = nil
	end
end

-- Pick up any already-tagged gradients
for _, inst in CollectionService:GetTagged(TAG) do
	onAdded(inst)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(onAdded)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(onRemoved)

-- Animate hue shift every frame
local elapsed = 0

RunService.RenderStepped:Connect(function(dt: number)
	elapsed += dt
	local hueOffset = (elapsed * SPEED) % 1
	local rainbow = buildRainbow(hueOffset)

	for grad in gradients do
		if grad.Parent then
			grad.Color = rainbow
		else
			-- Orphaned; clean up
			gradients[grad] = nil
		end
	end
end)

print("[RainbowRarityAnimator] Started")
