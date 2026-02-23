--!strict

local SoundService = game:GetService("SoundService")

local Sound = {}

function Sound:Play(name: string)
	local sound = SoundService:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

return Sound