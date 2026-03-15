--!strict
-- ReplicatedStorage/Client/Controllers/RagdollController.lua
-- Client-side ragdoll handler. Listens for PlayerKnockback remote
-- from KnockbackService and toggles ragdoll state using RagdollUtil.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type ControllerCtx = { [string]: any }

local RagdollController = {}

local _remote: RemoteEvent? = nil
local _ragdollUtil: any = nil
local _isRagdolled: boolean = false
local _cleanupFn: (() -> ())? = nil

----------------------------------------------------------------------
-- Character setup
----------------------------------------------------------------------

local function onCharacterAdded(character: Model)
	-- Wait for humanoid to exist
	local hum = character:WaitForChild("Humanoid", 10)
	if not hum then return end

	-- Wait briefly for all Motor6Ds to replicate
	task.wait(0.1)

	-- Clean up previous character's constraints
	if _cleanupFn then
		pcall(_cleanupFn)
		_cleanupFn = nil
	end

	-- Pre-create ragdoll constraints
	_cleanupFn = _ragdollUtil.setup(character)
	_isRagdolled = false
end

----------------------------------------------------------------------
-- Knockback handler
----------------------------------------------------------------------

local function onKnockback(data: any)
	if type(data) ~= "table" then return end

	local ragdollDuration = data.ragdollDuration
	if type(ragdollDuration) ~= "number" or ragdollDuration <= 0 then return end

	-- Don't double-ragdoll
	if _isRagdolled then return end

	local player = Players.LocalPlayer
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Activate ragdoll
	_isRagdolled = true
	_ragdollUtil.activate(character)

	-- Schedule deactivation
	local currentChar = character -- capture for validity check
	task.delay(ragdollDuration, function()
		-- Verify character is still the same and alive
		if player.Character ~= currentChar then
			_isRagdolled = false
			return
		end
		if not currentChar.Parent then
			_isRagdolled = false
			return
		end

		local hum = currentChar:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			_ragdollUtil.deactivate(currentChar)
		end
		_isRagdolled = false
	end)
end

----------------------------------------------------------------------
-- Controller lifecycle
----------------------------------------------------------------------

function RagdollController:Init(ctx: ControllerCtx)
	-- Load RagdollUtil
	_ragdollUtil = require(
		ReplicatedStorage:WaitForChild("Shared")
			:WaitForChild("Util")
			:WaitForChild("RagdollUtil")
	)

	-- Find PlayerKnockback remote
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and (ReplicatedStorage :: any).Shared:FindFirstChild("Net")
		and (ReplicatedStorage :: any).Shared.Net:FindFirstChild("Remotes")
		and (ReplicatedStorage :: any).Shared.Net.Remotes:FindFirstChild("RemoteEvents")
	if net then
		local re = net:FindFirstChild("PlayerKnockback")
		if re and re:IsA("RemoteEvent") then
			_remote = re :: RemoteEvent
		end
	end
end

function RagdollController:Start()
	if not _remote then
		warn("[RagdollController] PlayerKnockback RemoteEvent not found")
		return
	end

	-- Setup ragdoll on current and future characters
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end

	-- Listen for knockback events from server
	_remote.OnClientEvent:Connect(onKnockback)
end

return RagdollController
