--!strict
-- GiftModule.lua  |  Frame: Gift
-- Single gift reveal popup. Called by GiftsModule:_openGift via GiftModule:ShowReward(reward).
-- Animates the reveal, then auto-closes after a delay.
--
-- WIRE-UP NOTES:
--   Frame "Gift"
--     ├─ RewardIcon   (ImageLabel – spins during reveal)
--     ├─ RewardName   (TextLabel)
--     ├─ RewardAmount (TextLabel)
--     ├─ RarityLabel  (TextLabel)
--     └─ XButton  (TextButton)

local GiftModule = {}
GiftModule.__index = GiftModule

GiftModule._ctx     = nil :: any
GiftModule._janitor = nil :: any
GiftModule._frame   = nil :: any

local AUTO_CLOSE_DELAY = 4 -- seconds

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

function GiftModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Gift")
	if not self._frame then warn("[GiftModule] Frame 'Gift' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_close()
		end))
	end

	self._frame.Visible = false
end

function GiftModule:Start() end

-- Called externally by GiftsModule after a successful gift open.
-- reward = { name?, amount?, rarity?, imageId? }
function GiftModule:ShowReward(reward: any)
	if not self._frame then return end
	local ctx = self._ctx

	local iconLbl    = find(self._frame, "RewardIcon")   :: ImageLabel?
	local nameLbl    = find(self._frame, "RewardName")   :: TextLabel?
	local amountLbl  = find(self._frame, "RewardAmount") :: TextLabel?
	local rarityLbl  = find(self._frame, "RarityLabel")  :: TextLabel?

	-- Populate fields
	if nameLbl   then nameLbl.Text   = reward.name   or "Gift Reward" end
	if amountLbl then amountLbl.Text = reward.amount and ("x" .. tostring(reward.amount)) or "" end

	if rarityLbl then
		local rname = reward.rarity or "Common"
		rarityLbl.Text = rname
		if ctx.Config.RarityConfig then
			local rData = ctx.Config.RarityConfig.Rarities[rname]
			if rData then rarityLbl.TextColor3 = rData.Color end
		end
	end

	if iconLbl and reward.imageId then
		iconLbl.Image = "rbxassetid://" .. tostring(reward.imageId)
	end

	-- Open the frame
	if ctx.Router then ctx.Router:Open("Gift") end
	ctx.UI.Sound:Play("cartoon_pop")

	-- Spin icon during reveal
	local spinHandle
	if iconLbl then
		spinHandle = ctx.UI.Effects.Spin(iconLbl, 1.5)
	end

	-- Stop spin after 1.5s, then auto-close
	task.delay(1.5, function()
		if spinHandle then spinHandle:Destroy() end
	end)
	task.delay(AUTO_CLOSE_DELAY, function()
		self:_close()
	end)
end

function GiftModule:_close()
	if not self._frame then return end
	if self._ctx.Router then self._ctx.Router:Close("Gift") end
end

function GiftModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return GiftModule
