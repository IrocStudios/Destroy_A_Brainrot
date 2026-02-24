--!strict
-- MoneyClientController (LocalScript in StarterPlayerScripts)
-- Listens for server MoneySpawn payload and creates local-only money visuals.
-- On pickup (touch or prompt), calls RemoteFunction MoneyCollect (NetService routed).
--
-- Animation sequence per stack:
--   1. Pop + Arc  – scale 0→1 (Back overshoot) while arcing from origin to scatter pos
--   2. Bounce     – single ground bounce on landing
--   3. Idle       – slow Y rotation + gentle bob until collected
--   4. Collect    – rapid shrink to 0 (0.1s), then destroy

print("MoneyControllerClient Started on client")

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")

local LOCAL_PLAYER = Players.LocalPlayer

-- ── Sound helpers ────────────────────────────────────────────────────────────
local function getSoundFolder(): Folder?
	local pg = LOCAL_PLAYER:WaitForChild("PlayerGui", 10)
	if not pg then return nil end
	local gui = pg:WaitForChild("GUI", 10)
	if not gui then return nil end
	local lr = gui:FindFirstChild("LocalResources")
	if not lr then return nil end
	local snd = lr:FindFirstChild("Sound")
	if not snd then return nil end
	return snd:FindFirstChild("Money") :: Folder?
end

local _moneyDropSound: Sound? = nil
local _moneyDropSound2: Sound? = nil
local _moneyCollectSound: Sound? = nil
local _moneyCollectSound2: Sound? = nil

local function cacheSounds()
	local folder = getSoundFolder()
	if not folder then
		warn("[MoneyClient] Could not find LocalResources/Sound/Money")
		return
	end
	_moneyDropSound = folder:FindFirstChild("MoneyDrop") :: Sound?
	_moneyDropSound2 = folder:FindFirstChild("MoneyDrop2") :: Sound?
	_moneyCollectSound = folder:FindFirstChild("MoneyCollect") :: Sound?
	_moneyCollectSound2 = folder:FindFirstChild("MoneyCollect2") :: Sound?
end

local function playDropSounds()
	if _moneyDropSound then _moneyDropSound:Play() end
	if _moneyDropSound2 then _moneyDropSound2:Play() end
end

local function playCollectSounds()
	if _moneyCollectSound then _moneyCollectSound:Play() end
	if _moneyCollectSound2 then _moneyCollectSound2:Play() end
end

-- ── Animation constants ──────────────────────────────────────────────────────
local ARC_DURATION     = 0.5   -- seconds for pop + arc to landing position
local ARC_HEIGHT       = 5     -- studs above midpoint for the arc peak
local BOUNCE_DURATION  = 0.25  -- seconds for single ground bounce
local BOUNCE_HEIGHT    = 1.5   -- studs the bounce peaks above rest
local IDLE_ROT_SPEED   = 60    -- degrees per second Y rotation
local IDLE_BOB_AMP     = 0.3   -- studs bob amplitude
local IDLE_BOB_PERIOD  = 2     -- seconds per full bob cycle
local COLLECT_DURATION = 0.1   -- seconds for shrink-to-zero on collect

-- ── Cash formatting ──────────────────────────────────────────────────────────
local function formatCash(amount: number): string
	if amount >= 1e9 then
		return string.format("$%.2fb", amount / 1e9)
	elseif amount >= 1e6 then
		return string.format("$%.2fm", amount / 1e6)
	elseif amount >= 1e3 then
		return string.format("$%.2fk", amount / 1e3)
	else
		return "$" .. tostring(math.floor(amount))
	end
end

-- ── Easing ───────────────────────────────────────────────────────────────────
local function easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

-- ── Ground raycast ───────────────────────────────────────────────────────────
local function getGroundY(xzPos: Vector3): number
	local rayOrigin = Vector3.new(xzPos.X, xzPos.Y + 50, xzPos.Z)
	local rayDir = Vector3.new(0, -200, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excludeList = {} :: { Instance }
	local moneyDrops = workspace:FindFirstChild("MoneyDrops")
	if moneyDrops then table.insert(excludeList, moneyDrops) end
	local char = LOCAL_PLAYER.Character
	if char then table.insert(excludeList, char) end
	params.FilterDescendantsInstances = excludeList

	local result = workspace:Raycast(rayOrigin, rayDir, params)
	if result then
		return result.Position.Y
	end
	return xzPos.Y -- fallback
end

-- ── Idle tracking (single Heartbeat drives all idle stacks) ──────────────────
type IdleData = {
	model: Model,
	restCF: CFrame,
	time: number,
}

local _idleStacks: { [string]: IdleData } = {}

RunService.Heartbeat:Connect(function(dt: number)
	for dropId, data in pairs(_idleStacks) do
		if not data.model or not data.model.Parent then
			_idleStacks[dropId] = nil
			continue
		end
		data.time += dt
		local rotY = data.time * IDLE_ROT_SPEED
		local bobY = math.sin(data.time * (2 * math.pi / IDLE_BOB_PERIOD)) * IDLE_BOB_AMP
		data.model:PivotTo(data.restCF * CFrame.new(0, bobY, 0) * CFrame.Angles(0, math.rad(rotY), 0))
	end
end)

-- ── Network helpers ──────────────────────────────────────────────────────────
local function getNetRoot()
	return ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net")
end

local function getRemoteService()
	local net = getNetRoot()
	return require(net:WaitForChild("RemoteService"))
end

local function getMoneySpawnRE(): RemoteEvent
	local net = getNetRoot()
	local remotes = net:WaitForChild("Remotes")
	local events = remotes:WaitForChild("RemoteEvents")
	return events:WaitForChild("MoneySpawn") :: RemoteEvent
end

local function getMoneyCollectRF(): RemoteFunction
	local rs = getRemoteService()
	return rs:GetFunction("MoneyCollect")
end

local function getMoneyTemplate(): Model
	return ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Money"):WaitForChild("MoneyStack") :: Model
end

local function vec3FromArray(t: any): Vector3?
	if type(t) ~= "table" then return nil end
	local x, y, z = tonumber(t[1]), tonumber(t[2]), tonumber(t[3])
	if not x or not y or not z then return nil end
	return Vector3.new(x, y, z)
end

-- ── Debug ────────────────────────────────────────────────────────────────────
local DEBUG = true
local function dprint(...)
	if DEBUG then
		print("[MoneyClient]", ...)
	end
end
local function dwarn(...)
	if DEBUG then
		warn("[MoneyClient]", ...)
	end
end

-- ── MoneyClient class ────────────────────────────────────────────────────────
type LiveDrop = {
	id: string,
	value: number,
	model: Model,
	claimed: boolean,
	animating: boolean,
}

local MoneyClient = {}
MoneyClient.__index = MoneyClient

function MoneyClient.new()
	local self = setmetatable({}, MoneyClient)

	self.Template = getMoneyTemplate()
	self.MoneySpawnRE = getMoneySpawnRE()
	self.MoneyCollectRF = getMoneyCollectRF()
	self.Live = {} :: { [string]: LiveDrop }

	-- Cache half-height of the template at scale 1 for ground placement
	self.HalfHeight = self.Template:GetExtentsSize().Y / 2

	dprint("Bound MoneySpawnRE:", self.MoneySpawnRE:GetFullName())
	dprint("Bound MoneyCollectRF:", self.MoneyCollectRF:GetFullName())
	dprint("Template half-height:", self.HalfHeight)

	return self
end

-- ── Destroy / cleanup ────────────────────────────────────────────────────────

function MoneyClient:_destroyDrop(dropId: string)
	local rec = self.Live[dropId]
	if not rec then return end
	self.Live[dropId] = nil
	_idleStacks[dropId] = nil
	if rec.model and rec.model.Parent then
		rec.model:Destroy()
	end
end

-- ── Collect animation (shrink to 0) ─────────────────────────────────────────

function MoneyClient:_animateCollect(dropId: string)
	local rec = self.Live[dropId]
	if not rec or not rec.model or not rec.model.Parent then
		self:_destroyDrop(dropId)
		return
	end

	-- Remove from idle immediately so Heartbeat stops moving it
	_idleStacks[dropId] = nil
	rec.animating = true

	local model = rec.model
	local startTime = os.clock()

	task.spawn(function()
		while true do
			local t = math.clamp((os.clock() - startTime) / COLLECT_DURATION, 0, 1)
			local scale = 1 - t
			model:ScaleTo(math.max(scale, 0.001))
			if t >= 1 then break end
			task.wait()
		end
		self:_destroyDrop(dropId)
	end)
end

-- ── Claim (touch / prompt) ──────────────────────────────────────────────────

function MoneyClient:_claim(dropId: string)
	local rec = self.Live[dropId]
	if not rec or rec.claimed or rec.animating then return end
	rec.claimed = true

	local ok, result = pcall(function()
		return self.MoneyCollectRF:InvokeServer(dropId)
	end)

	if not ok then
		dwarn("MoneyCollect InvokeServer failed:", dropId, result)
		rec.claimed = false
		return
	end

	if type(result) == "table" and result.ok then
		dprint("Collected OK:", dropId, "amount=", result.amount)
		playCollectSounds()
		self:_animateCollect(dropId)
	else
		local reason = (type(result) == "table" and result.reason) or "Unknown"
		dprint("Collect denied:", dropId, "reason=", reason)
		rec.claimed = false
	end
end

-- ── Touch binding ────────────────────────────────────────────────────────────

function MoneyClient:_bindTouch(rootPart: BasePart, dropId: string)
	rootPart.Touched:Connect(function(hit)
		local char = LOCAL_PLAYER.Character
		if not char then return end
		if hit and hit:IsDescendantOf(char) then
			self:_claim(dropId)
		end
	end)
end

-- ── Spawn one stack with full animation ──────────────────────────────────────

function MoneyClient:_spawnOne(entry: any, origin: Vector3?)
	if type(entry) ~= "table" then return end
	local dropId = tostring(entry.id or "")
	if dropId == "" then return end
	if self.Live[dropId] then return end

	local value = tonumber(entry.value) or 0
	local targetPos = vec3FromArray(entry.pos)
	if not targetPos then
		dwarn("Bad drop pos for", dropId, entry.pos)
		return
	end

	local model = self.Template:Clone()
	model.Name = "MoneyDrop_" .. dropId

	local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not (pp and pp:IsA("BasePart")) then
		dwarn("MoneyStack template missing BasePart/PrimaryPart; cannot place.")
		model:Destroy()
		return
	end

	-- Set billboard amount to this stack's cash value
	local amountLabel = model:FindFirstChild("Amount", true) :: TextLabel?
	if amountLabel then
		amountLabel.Text = formatCash(value)
	end

	-- Ensure physics doesn't fling it
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
		end
	end

	-- Calculate ground rest position
	local groundY = getGroundY(targetPos)
	local halfH = self.HalfHeight
	local restY = groundY + halfH
	local restPos = Vector3.new(targetPos.X, restY, targetPos.Z)

	-- Start position (brainrot death center, or fallback to target)
	local startPos = origin or targetPos

	-- Start at origin, scale ~0, parent into world
	model:ScaleTo(0.001)
	model:PivotTo(CFrame.new(startPos))
	model.Parent = workspace.MoneyDrops

	-- Track as live drop
	self.Live[dropId] = {
		id = dropId,
		value = value,
		model = model,
		claimed = false,
		animating = true, -- prevent collection during animation
	}

	-- Play drop sounds
	playDropSounds()

	-- Pickup via touch (works during idle; animating flag blocks premature claims)
	self:_bindTouch(pp, dropId)

	-- Auto-cleanup on client after ~50s (server expires at 45)
	task.delay(50, function()
		if self.Live[dropId] then
			self:_destroyDrop(dropId)
		end
	end)

	-- ── Full animation sequence (runs in its own coroutine) ──────────────
	task.spawn(function()
		-- Phase 1: Pop + Arc  (scale 0→1 with Back overshoot, parabolic arc)
		local arcStart = os.clock()
		while true do
			local t = math.clamp((os.clock() - arcStart) / ARC_DURATION, 0, 1)

			-- Scale: reach full size in first 60% of arc, Back overshoot
			local scaleT = math.clamp(t / 0.6, 0, 1)
			local scale = easeOutBack(scaleT)
			model:ScaleTo(math.max(scale, 0.001))

			-- Position: lerp XZ, parabolic Y arc
			local easeT = 1 - (1 - t) ^ 2 -- ease-out quad for deceleration
			local x = startPos.X + (restPos.X - startPos.X) * easeT
			local z = startPos.Z + (restPos.Z - startPos.Z) * easeT
			-- Parabolic arc: peaks at ARC_HEIGHT above the midpoint
			local arcY = startPos.Y + (restPos.Y - startPos.Y) * easeT + ARC_HEIGHT * 4 * t * (1 - t)

			model:PivotTo(CFrame.new(x, arcY, z))

			if t >= 1 then break end
			task.wait()
		end

		-- Ensure scale is exactly 1
		model:ScaleTo(1)

		-- Phase 2: Single ground bounce
		local bounceStart = os.clock()
		while true do
			local t = math.clamp((os.clock() - bounceStart) / BOUNCE_DURATION, 0, 1)
			-- Half-sine: 0 → peak → 0 (one clean bounce)
			local bounceY = math.sin(math.pi * t) * BOUNCE_HEIGHT * (1 - t * 0.5)
			model:PivotTo(CFrame.new(restPos.X, restPos.Y + bounceY, restPos.Z))
			if t >= 1 then break end
			task.wait()
		end

		-- Snap to final rest position
		local restCF = CFrame.new(restPos)
		model:PivotTo(restCF)

		-- Phase 3: Enter idle (Heartbeat drives rotation + bob)
		local rec = self.Live[dropId]
		if rec then
			rec.animating = false -- now collectable
			_idleStacks[dropId] = {
				model = model,
				restCF = restCF,
				time = 0,
			}
		end
	end)

	dprint("Spawned visual:", dropId, "value=", value, "target=", tostring(restPos))
end

-- ── Start ────────────────────────────────────────────────────────────────────

function MoneyClient:Start()
	self.MoneySpawnRE.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			dwarn("MoneySpawn payload not table:", typeof(payload))
			return
		end

		-- New format: { origin = {x,y,z}, drops = { ... } }
		-- Fallback: raw array of drops (backward compat)
		local originArr = payload.origin
		local origin: Vector3? = nil
		if originArr then
			origin = vec3FromArray(originArr)
		end

		local drops = payload.drops or payload

		dprint("MoneySpawn received:", #drops, "origin=", tostring(origin))
		for _, entry in ipairs(drops) do
			self:_spawnOne(entry, origin)
		end
	end)

	dprint("Started. Listening for MoneySpawn.")
end

-- ── Boot ─────────────────────────────────────────────────────────────────────
cacheSounds()
local controller = MoneyClient.new()
controller:Start()
