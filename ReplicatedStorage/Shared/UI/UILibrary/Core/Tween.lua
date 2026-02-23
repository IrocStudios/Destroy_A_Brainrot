--!strict

local TweenService = game:GetService("TweenService")

local Tween = {}

function Tween:Play(instance, properties, time, style, direction)
	local info = TweenInfo.new(
		time or 0.2,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(instance, info, properties)
	tween:Play()
	return tween
end

return Tween