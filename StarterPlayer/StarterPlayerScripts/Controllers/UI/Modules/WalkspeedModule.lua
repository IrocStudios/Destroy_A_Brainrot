--!strict
-- WalkspeedModule.lua  |  Frame: Walkspeed
-- Displays and animates the player's current walkspeed.
-- Updates whenever the character's Humanoid WalkSpeed changes.
--
-- WIRE-UP NOTES:
--   Frame "Walkspeed"
--     ├─ SpeedLabel  (TextLabel – e.g. "16 WS")
--     ├─ SpeedBar    (Frame – width scaled to speed ratio)
--     └─ XButton (TextButton)

local RunService = game:GetService("RunService")

local WalkspeedModule = {}
WalkspeedModule.__index = WalkspeedModule

local BASE_SPEED  = 16  -- default Roblox walkspeed; adjust as needed
local MAX_DISPLAY = 60  -- upper bound for bar scaling

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

function WalkspeedModule:_getSpeed(): number
	local char = self._ctx.Player.Character
	if not char then return BASE_SPEED end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum and hum.WalkSpeed or BASE_SPEED
end

function WalkspeedModule:_updateDisplay(speed: number)
	if not self._frame then return end
	local ctx = self._ctx

	local lbl = find(self._frame, "SpeedLabel") :: TextLabel?
	local bar = find(self._frame, "SpeedBar")   :: Frame?

	if lbl then
		local prev = lbl.Text
		lbl.Text = tostring(math.floor(speed)) .. " WS"
		if prev ~= lbl.Text then
			local h = ctx.UI.Effects.Pulse(lbl, 6, 0.06)
			task.delay(0.4, function() h:Destroy() end)
		end
	end

	if bar then
		local ratio = math.clamp(speed / MAX_DISPLAY, 0, 1)
		ctx.UI.Tween:Play(bar, { Size = UDim2.new(ratio, 0, 1, 0) }, 0.25)
	end
end

function WalkspeedModule:_bindCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
	if not hum then return end

	-- Update immediately
	self:_updateDisplay(hum.WalkSpeed)

	-- Listen for speed changes
	local conn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		self:_updateDisplay(hum.WalkSpeed)
	end)
	self._janitor:Add(conn)
end

function WalkspeedModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("Walkspeed")
	if not self._frame then warn("[WalkspeedModule] Frame 'Walkspeed' not found") return end

	local closeBtn = find(self._frame, "XButton")
	if closeBtn then
		self._janitor:Add((closeBtn :: GuiButton).MouseButton1Click:Connect(function()
			if ctx.Router then ctx.Router:Close("Walkspeed") end
		end))
	end

	self:_updateDisplay(self:_getSpeed())
end

function WalkspeedModule:Start()
	if not self._frame then return end
	local player = self._ctx.Player

	-- Bind current character
	if player.Character then
		self:_bindCharacter(player.Character)
	end

	-- Re-bind on respawn
	self._janitor:Add(player.CharacterAdded:Connect(function(char)
		self:_bindCharacter(char)
	end))
end

function WalkspeedModule:Destroy()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return WalkspeedModule
