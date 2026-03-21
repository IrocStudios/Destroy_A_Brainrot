--!strict
-- ReplicatedStorage/Client/Controllers/GrabController.lua
-- Client-side grab handler. Listens for GrabState remote from server
-- and reports jump inputs via GrabBreakfree remote.
-- UI feedback will be added later.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type ControllerCtx = { [string]: any }

local GrabController = {}

local _grabStateRemote: RemoteEvent? = nil
local _grabBreakfreeRemote: RemoteEvent? = nil
local _isGrabbed: boolean = false
local _jumpConn: RBXScriptConnection? = nil

----------------------------------------------------------------------
-- Jump detection
----------------------------------------------------------------------

local function onJumpRequest()
	if not _isGrabbed then return end
	if not _grabBreakfreeRemote then return end

	-- Fire to server — server validates timing
	_grabBreakfreeRemote:FireServer()
end

----------------------------------------------------------------------
-- Grab state handler
----------------------------------------------------------------------

local function onGrabState(data: any)
	if type(data) ~= "table" then return end

	local action = data.action
	if action == "start" then
		if _isGrabbed then return end
		_isGrabbed = true

		-- Connect jump detection
		if _jumpConn then
			_jumpConn:Disconnect()
		end
		_jumpConn = UserInputService.JumpRequest:Connect(onJumpRequest)

	elseif action == "end" then
		_isGrabbed = false

		-- Disconnect jump detection
		if _jumpConn then
			_jumpConn:Disconnect()
			_jumpConn = nil
		end
	end
end

----------------------------------------------------------------------
-- Controller lifecycle
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

function GrabController:Init(ctx: ControllerCtx)
	_grabStateRemote = getRemote("GrabState")
	_grabBreakfreeRemote = getRemote("GrabBreakfree")
end

function GrabController:Start()
	if not _grabStateRemote then
		warn("[GrabController] GrabState RemoteEvent not found")
		return
	end

	-- Listen for grab state changes from server
	_grabStateRemote.OnClientEvent:Connect(onGrabState)

	-- Clean up on respawn
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function()
		if _isGrabbed then
			_isGrabbed = false
			if _jumpConn then
				_jumpConn:Disconnect()
				_jumpConn = nil
			end
		end
	end)
end

return GrabController
