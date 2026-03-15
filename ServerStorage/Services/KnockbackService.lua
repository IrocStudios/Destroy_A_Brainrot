--!strict
-- ServerStorage/Services/KnockbackService.lua
-- Universal player knockback system. Any server code can call
-- ApplyKnockback() to push, throw, fling, catapult, or punch a player.
-- Fires PlayerKnockback RemoteEvent to client for ragdoll handling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

type Services = { [string]: any }

----------------------------------------------------------------------
-- Force type presets
----------------------------------------------------------------------

local FORCE_PRESETS = {
	punch = {
		horizontalMult = 1.0,
		verticalMult = 0.1,
		baseMagnitude = 30,
		duration = 0.15,
		defaultRagdoll = 0,
	},
	push = {
		horizontalMult = 1.0,
		verticalMult = 0.2,
		baseMagnitude = 50,
		duration = 0.25,
		defaultRagdoll = 0,
	},
	throw = {
		horizontalMult = 0.7,
		verticalMult = 0.6,
		baseMagnitude = 70,
		duration = 0.35,
		defaultRagdoll = 2.0,
	},
	fling = {
		horizontalMult = 0.8,
		verticalMult = 0.8,
		baseMagnitude = 100,
		duration = 0.4,
		defaultRagdoll = 3.0,
	},
	catapult = {
		horizontalMult = 0.3,
		verticalMult = 1.0,
		baseMagnitude = 120,
		duration = 0.5,
		defaultRagdoll = 4.0,
	},
}

----------------------------------------------------------------------
-- Service
----------------------------------------------------------------------

local KnockbackService = {}

function KnockbackService:Init(services: Services)
	self.Services = services
	self._knockbackRemote = nil :: RemoteEvent?
	self._activeKnockbacks = {} :: { [Player]: boolean }
end

function KnockbackService:Start()
	local net = ReplicatedStorage:FindFirstChild("Shared")
		and (ReplicatedStorage :: any).Shared:FindFirstChild("Net")
		and (ReplicatedStorage :: any).Shared.Net:FindFirstChild("Remotes")
		and (ReplicatedStorage :: any).Shared.Net.Remotes:FindFirstChild("RemoteEvents")
	if net then
		local re = net:FindFirstChild("PlayerKnockback")
		if re and re:IsA("RemoteEvent") then
			self._knockbackRemote = re :: RemoteEvent
		end
	end

	-- Clean up tracking when players leave
	Players.PlayerRemoving:Connect(function(player: Player)
		self._activeKnockbacks[player] = nil
	end)

	if not self._knockbackRemote then
		warn("[KnockbackService] PlayerKnockback RemoteEvent not found")
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

export type KnockbackOptions = {
	direction: Vector3?,
	originPosition: Vector3?,
	magnitude: number?,
	ragdollDuration: number?,
	invulnerableDuration: number?,
	ignoreActiveKnockback: boolean?, -- force re-knockback even if already knocked back
}

--- Apply a knockback force to a player.
--- forceType: "punch" | "push" | "throw" | "fling" | "catapult"
function KnockbackService:ApplyKnockback(player: Player, forceType: string, options: KnockbackOptions?)
	local opts = options or {}

	-- Validate player character
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Prevent chain-stun (unless caller explicitly overrides)
	if self._activeKnockbacks[player] and not opts.ignoreActiveKnockback then return end

	-- Look up preset
	local preset = FORCE_PRESETS[forceType]
	if not preset then
		warn("[KnockbackService] Unknown forceType:", forceType)
		return
	end

	-- Mark as active
	self._activeKnockbacks[player] = true

	-- Run async so caller isn't blocked
	task.spawn(function()
		-- Compute direction
		local dir: Vector3

		if opts.direction then
			dir = opts.direction.Unit
		elseif opts.originPosition then
			local away = hrp.Position - opts.originPosition
			if away.Magnitude < 0.1 then
				away = Vector3.new(1, 0, 0)
			end
			-- Flatten for horizontal component
			dir = Vector3.new(away.X, 0, away.Z).Unit
		else
			-- Default: random horizontal direction
			local angle = math.random() * math.pi * 2
			dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		end

		-- Build velocity
		local magnitude = opts.magnitude or preset.baseMagnitude
		local hMult = preset.horizontalMult
		local vMult = preset.verticalMult

		local velocity = Vector3.new(
			dir.X * magnitude * hMult,
			magnitude * vMult,
			dir.Z * magnitude * hMult
		)

		local ragdollDuration = opts.ragdollDuration
		if ragdollDuration == nil then
			ragdollDuration = preset.defaultRagdoll
		end

		local invulnDuration = opts.invulnerableDuration
		if invulnDuration == nil then
			invulnDuration = (ragdollDuration :: number) + 0.5
		end

		-- Set network ownership to server for physics authority
		pcall(function()
			(hrp :: BasePart):SetNetworkOwner(nil)
		end)

		-- Apply BodyVelocity (consistent with JumpStomp pattern)
		local bodyVel = Instance.new("BodyVelocity")
		bodyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
		bodyVel.Velocity = velocity
		bodyVel.Parent = hrp

		-- Fire ragdoll remote to client
		if self._knockbackRemote and ragdollDuration :: number > 0 then
			self._knockbackRemote:FireClient(player, {
				ragdollDuration = ragdollDuration,
			})
		end

		-- Wait for force duration, then clean up BodyVelocity
		task.wait(preset.duration)
		if bodyVel.Parent then
			bodyVel:Destroy()
		end

		-- Return network ownership to player
		pcall(function()
			if hrp.Parent and player.Parent then
				(hrp :: BasePart):SetNetworkOwner(player)
			end
		end)

		-- Wait invulnerability period
		if invulnDuration :: number > 0 then
			task.wait(invulnDuration :: number)
		end

		-- Clear active flag
		self._activeKnockbacks[player] = nil
	end)
end

--- Check if a player is currently in knockback (invulnerable).
function KnockbackService:IsKnockedBack(player: Player): boolean
	return self._activeKnockbacks[player] == true
end

return KnockbackService
