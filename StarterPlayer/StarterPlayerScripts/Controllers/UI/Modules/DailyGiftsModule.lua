--!strict
-- DailyGiftsModule.lua  |  Frame: DailyGifts
-- Shows daily login reward calendar. Highlights claimable day; disables claimed days.
--
-- WIRE-UP NOTES:
--   Frame "DailyGifts"
--     ├─ DayList      (Frame or ScrollingFrame containing day buttons)
--     │    └─ Day1 .. Day7 (TextButton or Frame per day, Attribute "Day"=1..7)
--     │         ├─ DayLabel    (TextLabel "Day N")
--     │         ├─ RewardIcon  (ImageLabel)
--     │         ├─ RewardValue (TextLabel)
--     │         └─ CheckMark   (ImageLabel – shown when claimed)
--     ├─ ClaimButton  (TextButton – claims today's reward)
--     ├─ StreakLabel  (TextLabel – "Streak: N days")
--     └─ XButton  (TextButton)

local DailyGiftsModule = {}
DailyGiftsModule.__index = DailyGiftsModule

local SECONDS_PER_DAY = 86400

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

local function getRewards(ctx: any): any
	local s = (ctx.State and ctx.State.State) or {}
	return s.Rewards or {}
end

local function canClaim(rewards: any): boolean
	local lastClaim = rewards.DailyLastClaim or 0
	return os.time() - lastClaim >= SECONDS_PER_DAY
end

-- ── Refresh ───────────────────────────────────────────────────────────────────

function DailyGiftsModule:_refresh(state: any)
	if not self._frame then return end
	local ctx     = self._ctx
	local rewards = getRewards(ctx)
	local streak  = rewards.DailyStreak or 0
	local claimable = canClaim(rewards)

	-- Update streak label
	local streakLbl = find(self._frame, "StreakLabel") :: TextLabel?
	if streakLbl then streakLbl.Text = "Streak: " .. tostring(streak) .. " days" end

	-- Update claim button
	local claimBtn = find(self._frame, "ClaimButton") :: TextButton?
	if claimBtn then
		claimBtn.Active = claimable
		claimBtn.Text   = claimable and "Claim Reward!" or "Come back tomorrow!"
	end

	-- Update day tiles (Day1..Day7)
	local dayList = find(self._frame, "DayList")
	if dayList then
		for _, dayFrame in ipairs(dayList:GetChildren()) do
			local dayNum = dayFrame:GetAttribute("Day") :: number?
			if not dayNum then continue end

			local check = find(dayFrame, "CheckMark")
			if check then
				check.Visible = (dayNum <= streak)
			end

			-- Highlight today's claimable day
			if dayNum == (streak + 1) and claimable then
				dayFrame.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
			elseif dayNum <= streak then
				dayFrame.BackgroundColor3 = Color3.fromRGB(80, 200, 80)
			else
				dayFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
			end
		end
	end
end

-- ── Claim ─────────────────────────────────────────────────────────────────────

function DailyGiftsModule:_onClaim()
	local ctx = self._ctx
	ctx.UI.Sound:Play("cartoon_pop")

	task.spawn(function()
		local rf = ctx.Net:GetFunction("RewardAction")
		local ok, result = pcall(function()
			return rf:InvokeServer({ action = "claimDaily" })
		end)

		if ok and type(result) == "table" and result.ok then
			ctx.UI.Sound:Play("cartoon_pop")
			-- Pulse the claim button as feedback
			local claimBtn = find(self._frame, "ClaimButton")
			if claimBtn then
				local h = ctx.UI.Effects.Pulse(claimBtn, 3, 0.08)
				task.delay(1, function() h:Destroy() end)
			end
			-- State delta will update Rewards; refresh happens via Changed
		else
			ctx.UI.Effects.Shake(self._frame, 5, 0.25, 0.1)
			local reason = (type(result) == "table" and result.reason) or "Cannot claim yet"
			warn("[DailyGiftsModule] Claim failed:", reason)
		end
	end)
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function DailyGiftsModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("DailyGifts")
	if not self._frame then warn("[DailyGiftsModule] Frame 'DailyGifts' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("DailyGifts") end
		end))
	end

	local claimBtn = find(self._frame, "ClaimButton")
	if claimBtn then
		self._janitor:Add((claimBtn :: GuiButton).MouseButton1Click:Connect(function()
			self:_onClaim()
		end))
	end

	self:_refresh({})
end

function DailyGiftsModule:Start()
	if not self._frame then return end
	self._janitor:Add(self._ctx.State.Changed:Connect(function(state, _)
		self:_refresh(state)
	end))
end

function DailyGiftsModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return DailyGiftsModule
