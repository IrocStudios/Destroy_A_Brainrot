--!strict
-- GrabAttack
-- Heavy melee: monkey grabs the player and holds them via WeldConstraint.
-- Player must spam-jump to build breakpower and escape.
-- Server-authoritative: tracks breakpower, tick damage, and release.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GrabAttack = {}
GrabAttack.Name = "GrabAttack"
GrabAttack.Type = "Melee"
GrabAttack.Weight = "Heavy"

----------------------------------------------------------------------
-- CanExecute: valid grab target within range
----------------------------------------------------------------------

function GrabAttack:CanExecute(entry: any, target: any, dist: number, moveConfig: any): boolean
	local maxRange = (moveConfig and moveConfig.Range) or 6
	if dist > maxRange then return false end

	-- Don't grab someone already grabbed
	local grabSvc = entry._grabService
	if grabSvc and grabSvc:IsGrabbed(target) then return false end

	-- Don't grab knocked-back players
	local knockSvc = entry._knockbackService
	if knockSvc and knockSvc:IsKnockedBack(target) then return false end

	return true
end

----------------------------------------------------------------------
-- Execute: grab, hold, tick damage, wait for breakfree
----------------------------------------------------------------------

function GrabAttack:Execute(entry: any, target: any, services: any, moveConfig: any)
	local hum: Humanoid = entry.Humanoid
	local hrp: BasePart = entry.HRP
	if not hum or not hrp or hum.Health <= 0 then return end

	-- Resolve services
	local grabService = services and services.GrabService
	local armorService = services and services.ArmorService
	local knockbackService = services and services.KnockbackService

	-- Cache services on entry for CanExecute checks
	entry._grabService = grabService
	entry._knockbackService = knockbackService

	-- Validate target
	local targetChar = target and target.Character
	if not targetChar then return end
	local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetHRP or not targetHRP:IsA("BasePart") then return end
	local targetHum = targetChar:FindFirstChildOfClass("Humanoid")
	if not targetHum or targetHum.Health <= 0 then return end

	-- Don't grab someone who is knocked back
	if knockbackService and knockbackService:IsKnockedBack(target) then return end

	-- Already grabbed by someone else
	if grabService and grabService:IsGrabbed(target) then return end

	-- Windup
	local windupTime = (moveConfig and moveConfig.WindupTime) or 0.3
	hum.WalkSpeed = 0
	task.wait(windupTime)

	-- Re-validate after windup
	if not targetHRP.Parent or not targetHum or targetHum.Health <= 0 then
		return
	end
	local postWindupDist = (hrp.Position - targetHRP.Position).Magnitude
	if postWindupDist > ((moveConfig and moveConfig.Range) or 6) * 1.5 then
		return
	end

	-- ===== GRAB START =====
	-- Register grab in service
	if grabService then
		grabService:RegisterGrab(target, entry.Id)
	end

	-- Set AI state to Grab (AIService will pause normal evaluation)
	entry.State = "Grab"
	entry.GrabTarget = target

	-- Switch to looped Grab hold animation (replaces the brief attack_Grab)
	local animSv = entry.Model and entry.Model:FindFirstChild("CurrentAnimation")
	if animSv and animSv:IsA("StringValue") then
		animSv.Value = "Grab"
	end

	-- Middleman part: player welds to this, this welds to monkey.
	-- When monkey dies, we destroy the middleman → player is safely released.
	-- Direct weld to monkey HRP would rip the player when the monkey model is destroyed.
	local grabOffset = hrp.CFrame.LookVector * 3
	local grabPos = hrp.Position + grabOffset
	targetHRP.CFrame = CFrame.new(grabPos, hrp.Position)

	-- Take network ownership for physics authority
	pcall(function()
		targetHRP:SetNetworkOwner(nil)
	end)

	-- Create invisible middleman anchor part
	local grabAnchor = Instance.new("Part")
	grabAnchor.Name = "GrabAnchor"
	grabAnchor.Size = Vector3.new(1, 1, 1)
	grabAnchor.Transparency = 1
	grabAnchor.CanCollide = false
	grabAnchor.CanQuery = false
	grabAnchor.CanTouch = false
	grabAnchor.Massless = true
	grabAnchor.CFrame = targetHRP.CFrame
	grabAnchor.Parent = Workspace

	-- Weld 1: middleman → monkey HRP (monkey owns the middleman's position)
	local weldToMonkey = Instance.new("WeldConstraint")
	weldToMonkey.Part0 = hrp
	weldToMonkey.Part1 = grabAnchor
	weldToMonkey.Name = "GrabWeld_Monkey"
	weldToMonkey.Parent = grabAnchor

	-- Weld 2: player → middleman (player follows the middleman)
	local weldToPlayer = Instance.new("WeldConstraint")
	weldToPlayer.Part0 = grabAnchor
	weldToPlayer.Part1 = targetHRP
	weldToPlayer.Name = "GrabWeld_Player"
	weldToPlayer.Parent = grabAnchor

	-- ===== MOVEMENT LOCKDOWN =====
	-- Save original values, freeze movement, track any external changes
	local savedWalkSpeed = targetHum.WalkSpeed
	local savedJumpPower = targetHum.JumpPower
	local savedUseJumpPower = targetHum.UseJumpPower
	local pendingWalkSpeed = savedWalkSpeed -- tracks external changes during grab
	local pendingJumpPower = savedJumpPower

	targetHum.WalkSpeed = 0
	targetHum.UseJumpPower = true
	targetHum.JumpPower = 1 -- near-zero: jumps register as input but don't physically jump
	targetHum.PlatformStand = true -- disable all player movement input (WASD, rotation)

	-- Watch for external WalkSpeed/JumpPower changes (e.g. speed upgrade purchase)
	local walkSpeedConn: RBXScriptConnection? = nil
	local jumpPowerConn: RBXScriptConnection? = nil

	walkSpeedConn = targetHum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		local newVal = targetHum.WalkSpeed
		if newVal ~= 0 then -- someone else changed it (not us)
			print("[GrabAttack] WalkSpeed changed externally to " .. newVal .. " — queued for release")
			pendingWalkSpeed = newVal
			targetHum.WalkSpeed = 0 -- re-lock
		end
	end)

	jumpPowerConn = targetHum:GetPropertyChangedSignal("JumpPower"):Connect(function()
		local newVal = targetHum.JumpPower
		if newVal ~= 1 then -- someone else changed it (not us)
			print("[GrabAttack] JumpPower changed externally to " .. newVal .. " — queued for release")
			pendingJumpPower = newVal
			targetHum.JumpPower = 1 -- re-lock
		end
	end)

	-- Config values
	local tickDamage = (moveConfig and moveConfig.TickDamage) or 2
	local tickInterval = (moveConfig and moveConfig.TickInterval) or 1.0
	local breakThreshold = (moveConfig and moveConfig.BreakThreshold) or 100
	local jumpPower = (moveConfig and moveConfig.JumpPower) or 20
	local breakDecay = (moveConfig and moveConfig.BreakDecay) or 5

	-- Apply stat overrides (variant multipliers affect AttackDamage which is tickDamage base)
	local baseDamage = tickDamage
	if entry.EnemyInfo then
		local d = entry.EnemyInfo:GetAttribute("AttackDamage")
		if typeof(d) == "number" then baseDamage = d end
	end

	-- ===== SAFETY: immediate release if monkey dies =====
	-- Destroy the middleman anchor instantly so the player isn't dragged with the corpse
	local grabBroken = false
	local diedConn: RBXScriptConnection? = nil
	diedConn = hum.Died:Connect(function()
		grabBroken = true
		if grabAnchor and grabAnchor.Parent then
			grabAnchor:Destroy()
		end
		-- Immediately restore player controls so they aren't stuck
		pcall(function()
			if targetHum and targetHum.Parent then
				targetHum.PlatformStand = false
			end
		end)
	end)

	-- ===== GRAB HOLD LOOP =====
	local TICK_RATE = 0.1
	local lastTickDamageAt = os.clock()
	local lastJumpProcessed = 0

	while true do
		task.wait(TICK_RATE)

		-- Check monkey alive (immediate flag from Died + health check)
		if grabBroken then break end
		if not hum or hum.Health <= 0 then break end
		if not hrp or not hrp.Parent then break end

		-- Check target alive and still in game
		if not target or not target.Parent then break end
		local tChar = target.Character
		if not tChar then break end
		local tHum = tChar:FindFirstChildOfClass("Humanoid")
		if not tHum or tHum.Health <= 0 then break end
		local tHRP = tChar:FindFirstChild("HumanoidRootPart")
		if not tHRP or not tHRP.Parent then break end

		-- Check grab anchor still exists
		if not grabAnchor or not grabAnchor.Parent then break end

		local now = os.clock()
		local dt = TICK_RATE

		-- Process jump inputs from GrabService
		if grabService then
			local record = grabService:GetRecord(target)
			if record and record.LastJumpAt > lastJumpProcessed then
				lastJumpProcessed = record.LastJumpAt
				grabService:AddBreakPower(target, jumpPower)
			end

			-- Decay breakpower
			grabService:DecayBreakPower(target, dt, breakDecay)

			-- Check breakfree
			if grabService:GetBreakPower(target) >= breakThreshold then
				break
			end
		end

		-- Tick damage (every tickInterval seconds)
		if now - lastTickDamageAt >= tickInterval then
			lastTickDamageAt = now

			-- Route through armor
			pcall(function()
				if armorService and target then
					local absorbed, overflow = armorService:DamageArmor(target, baseDamage)
					if overflow > 0 and tHum then
						tHum:TakeDamage(overflow)
					end
				elseif tHum then
					tHum:TakeDamage(baseDamage)
				end
			end)
		end
	end

	-- ===== GRAB RELEASE =====
	-- Disconnect all watchers
	if diedConn then diedConn:Disconnect() end
	if walkSpeedConn then walkSpeedConn:Disconnect() end
	if jumpPowerConn then jumpPowerConn:Disconnect() end

	-- Destroy middleman anchor (this severs both welds cleanly)
	if grabAnchor and grabAnchor.Parent then
		grabAnchor:Destroy()
	end

	-- Restore player movement — use pending values (may have been updated during grab)
	pcall(function()
		if target and target.Parent then
			local tChar = target.Character
			local tHum2 = tChar and tChar:FindFirstChildOfClass("Humanoid")
			if tHum2 then
				tHum2.PlatformStand = false
				tHum2.WalkSpeed = pendingWalkSpeed
				tHum2.UseJumpPower = savedUseJumpPower
				tHum2.JumpPower = pendingJumpPower
				print("[GrabAttack] Restored WalkSpeed=" .. pendingWalkSpeed .. " JumpPower=" .. pendingJumpPower)
			end
		end
	end)

	-- Return network ownership to player
	pcall(function()
		if target and target.Parent then
			local tChar = target.Character
			if tChar then
				local tHRP = tChar:FindFirstChild("HumanoidRootPart")
				if tHRP and tHRP:IsA("BasePart") then
					tHRP:SetNetworkOwner(target)
				end
			end
		end
	end)

	-- Release in service
	if grabService then
		grabService:ReleaseGrab(target)
	end

	-- Clear AI grab state
	entry.GrabTarget = nil
	-- AIService's FleeAfterAttack handles state transition from here
end

function GrabAttack:GetAnimationName(): string
	return "Grab" -- plays "Grab" directly, not "attack_Grab"
end

return GrabAttack
