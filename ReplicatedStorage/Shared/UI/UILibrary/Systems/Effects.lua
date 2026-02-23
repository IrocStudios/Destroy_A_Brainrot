--!strict

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Util = require(script.Parent.Parent.Core.Util)

local Effects = {}

local function makeHandle(stopFn)
	return {
		Destroy = stopFn,
		Stop = stopFn
	}
end

function Effects.Spin(gui: GuiObject, speedRPS: number)
	local alive = true
	local deg = speedRPS * 360

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not alive then return end
		if not Util.IsGuiVisible(gui) then
			alive = false
			conn:Disconnect()
			return
		end
		gui.Rotation += deg * dt
	end)

	return makeHandle(function()
		alive = false
		if conn then conn:Disconnect() end
	end)
end

function Effects.Pulse(gui: GuiObject, speed: number, amount: number)
	local ui = Util.EnsureUIScale(gui)
	local base = ui.Scale
	local t = 0
	local alive = true

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not alive then return end
		if not Util.IsGuiVisible(gui) then
			alive = false
			conn:Disconnect()
			return
		end
		t += dt
		ui.Scale = base + math.sin(t * speed * math.pi * 2) * amount
	end)

	return makeHandle(function()
		alive = false
		if conn then conn:Disconnect() end
		ui.Scale = base
	end)
end

function Effects.Shake(gui: GuiObject, amount: number, t: number, settle: number)
	local origin = gui.Position
	local elapsed = 0
	local alive = true

	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not alive then return end
		elapsed += dt

		if elapsed >= t then
			conn:Disconnect()
			local tween = TweenService:Create(gui,
				TweenInfo.new(settle, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = origin }
			)
			tween:Play()
			alive = false
			return
		end

		local ox = (math.random()*2-1) * amount
		local oy = (math.random()*2-1) * amount
		gui.Position = origin + UDim2.new(0, ox, 0, oy)
	end)

	return makeHandle(function()
		alive = false
		if conn then conn:Disconnect() end
		gui.Position = origin
	end)
end

return Effects