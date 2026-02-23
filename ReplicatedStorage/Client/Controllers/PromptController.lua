local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PromptController = {}
PromptController.__index = PromptController

function PromptController:Init()
	self.Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("RemoteService"))
	self.PromptRE = self.Remotes:GetEvent("Prompt")
	self.NotifyRE = self.Remotes:GetEvent("Notify")
	self.Gui = nil
	self.Label = nil
end

local function ensureGui(self)
	if self.Gui and self.Gui.Parent then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "BrainrotClientUI"
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "Toast"
	label.Size = UDim2.fromScale(0.6, 0.08)
	label.Position = UDim2.fromScale(0.2, 0.08)
	label.BackgroundTransparency = 0.25
	label.TextScaled = true
	label.Text = ""
	label.Visible = false
	label.Parent = gui

	self.Gui = gui
	self.Label = label
end

local function toast(self, text)
	ensureGui(self)
	local label = self.Label
	label.Text = tostring(text or "")
	label.Visible = true
	label.TextTransparency = 1
	label.BackgroundTransparency = 1

	TweenService:Create(label, TweenInfo.new(0.15), { TextTransparency = 0, BackgroundTransparency = 0.25 }):Play()
	task.delay(2.0, function()
		if not label.Parent then
			return
		end
		local t = TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 1, BackgroundTransparency = 1 })
		t:Play()
		t.Completed:Wait()
		if label.Parent then
			label.Visible = false
		end
	end)
end

function PromptController:Start()
	self.NotifyRE.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.type == "Notify" then
			toast(self, payload.text)
		end
	end)

	self.PromptRE.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.type == "Prompt" then
			toast(self, payload.text)
		end
	end)
end

return setmetatable({}, PromptController)