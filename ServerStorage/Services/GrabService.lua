--!strict
-- GrabService
-- Tracks active grabs: which players are grabbed, by which brainrot.
-- Manages breakpower accumulation, decay, and release.
-- GrabAttack module delegates to this for state; GrabController (client) sends jump events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GrabService = {}
GrabService.Name = "GrabService"

type GrabRecord = {
	BrainrotId: string,
	BreakPower: number,
	LastJumpAt: number,
	LastTickAt: number,
	StartedAt: number,
}

local _activeGrabs: { [Player]: GrabRecord } = {}
local _grabStateRemote: RemoteEvent? = nil
local _grabBreakfreeRemote: RemoteEvent? = nil

-- Anti-cheat: minimum time between accepted jumps (Roblox jump cooldown ~0.3s)
local JUMP_COOLDOWN = 0.25

----------------------------------------------------------------------
-- Remote lookup
----------------------------------------------------------------------

local function getRemote(name: string): RemoteEvent?
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and (ReplicatedStorage :: any).Shared:FindFirstChild("Net")
		and (ReplicatedStorage :: any).Shared.Net:FindFirstChild("Remotes")
		and (ReplicatedStorage :: any).Shared.Net.Remotes:FindFirstChild("RemoteEvents")
	if not net then return nil end
	local re = net:FindFirstChild(name)
	return (re and re:IsA("RemoteEvent")) and re :: RemoteEvent or nil
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function GrabService:IsGrabbed(player: Player): boolean
	return _activeGrabs[player] ~= nil
end

function GrabService:RegisterGrab(player: Player, brainrotId: string)
	local now = os.clock()
	_activeGrabs[player] = {
		BrainrotId = brainrotId,
		BreakPower = 0,
		LastJumpAt = 0,
		LastTickAt = now,
		StartedAt = now,
	}

	-- Notify client
	if _grabStateRemote then
		_grabStateRemote:FireClient(player, {
			action = "start",
			brainrotId = brainrotId,
		})
	end
end

function GrabService:ReleaseGrab(player: Player)
	if not _activeGrabs[player] then return end
	_activeGrabs[player] = nil

	-- Notify client
	if _grabStateRemote then
		_grabStateRemote:FireClient(player, {
			action = "end",
		})
	end
end

function GrabService:ProcessJump(player: Player): boolean
	local record = _activeGrabs[player]
	if not record then return false end

	local now = os.clock()

	-- Anti-cheat: rate limit jumps
	if now - record.LastJumpAt < JUMP_COOLDOWN then
		return false
	end

	record.LastJumpAt = now
	-- JumpPower is applied by GrabAttack (it knows the moveConfig)
	-- We just mark the time; GrabAttack reads LastJumpAt to detect new jumps
	return true
end

function GrabService:GetRecord(player: Player): GrabRecord?
	return _activeGrabs[player]
end

function GrabService:AddBreakPower(player: Player, amount: number)
	local record = _activeGrabs[player]
	if not record then return end
	record.BreakPower = record.BreakPower + amount
end

function GrabService:DecayBreakPower(player: Player, dt: number, decayRate: number)
	local record = _activeGrabs[player]
	if not record then return end
	record.BreakPower = math.max(0, record.BreakPower - decayRate * dt)
end

function GrabService:GetBreakPower(player: Player): number
	local record = _activeGrabs[player]
	if not record then return 0 end
	return record.BreakPower
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function GrabService:Init(deps: { [string]: any })
	_grabStateRemote = getRemote("GrabState")
	_grabBreakfreeRemote = getRemote("GrabBreakfree")
end

function GrabService:Start()
	if not _grabBreakfreeRemote then
		warn("[GrabService] GrabBreakfree RemoteEvent not found")
		return
	end

	-- Listen for client jump reports
	_grabBreakfreeRemote.OnServerEvent:Connect(function(player: Player)
		self:ProcessJump(player)
	end)

	-- Clean up on player leave
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		_activeGrabs[player] = nil
	end)
end

return GrabService
