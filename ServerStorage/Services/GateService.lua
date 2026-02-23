local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local GateService = {}
GateService.__index = GateService

local function isBasePart(x)
	return typeof(x) == "Instance" and x:IsA("BasePart")
end

local function getGatePromptParent(gate)
	if gate:IsA("Model") then
		if gate.PrimaryPart and isBasePart(gate.PrimaryPart) then
			return gate.PrimaryPart
		end
		local p = gate:FindFirstChildWhichIsA("BasePart", true)
		return p or gate
	end
	if isBasePart(gate) then
		return gate
	end
	return gate
end

local function ensurePrompt(gate)
	local parent = getGatePromptParent(gate)
	if not parent or not parent:IsA("Instance") then return nil end

	local prompt = parent:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.Parent = parent
	end
	return prompt
end

local function readGateConfig(gate)
	local stage = gate:GetAttribute("StageId")
	local price = gate:GetAttribute("Price")

	if stage == nil then
		local sv = gate:FindFirstChild("StageId")
		if sv and (sv:IsA("IntValue") or sv:IsA("StringValue") or sv:IsA("NumberValue")) then
			stage = sv.Value
		end
	end

	if typeof(price) ~= "number" then
		local pv = gate:FindFirstChild("Price")
		if pv and pv:IsA("NumberValue") then price = pv.Value end
	end

	if typeof(stage) == "number" then
		stage = tostring(stage)
	elseif typeof(stage) ~= "string" then
		stage = nil
	end

	return stage, tonumber(price) or 0
end

function GateService:Init(services)
	self.Services = services
	self.Net = services.NetService
	self.Economy = services.EconomyService
	self.Progression = services.ProgressionService
	self.Data = services.DataService

	self.GatesFolder = Workspace:FindFirstChild("Gates")
	self._gateByKey = {}
	self._gateTouchDebounce = {}
end

function GateService:_keyForGate(gate)
	return gate:GetAttribute("GateId") or gate:GetFullName()
end

function GateService:_isUnlocked(player, stageId)
	if not stageId then return false end
	if self.Progression and self.Progression.IsStageUnlocked then
		return self.Progression:IsStageUnlocked(player, stageId)
	end

	if self.Data and self.Data.GetValue then
		local v = self.Data:GetValue(player, "Progression.StageUnlocked")
		if typeof(v) == "table" then
			return v[stageId] == true
		elseif typeof(v) == "string" then
			return v == stageId
		elseif typeof(v) == "number" then
			return tostring(v) == stageId
		end
	end

	return false
end

function GateService:_notifyLocked(player, stageId, price)
	if not self.Net then return end
	if self.Net.SendPrompt then
		self.Net:SendPrompt(player, {
			kind = "GatePurchase",
			key = stageId,
			title = "Unlock Gate?",
			body = string.format("Unlock Stage %s for $%d?", tostring(stageId), tonumber(price) or 0),
			data = { stageId = stageId, price = price },
		})
	elseif self.Net.Notify then
		self.Net:Notify(player, ("Gate locked. Unlock Stage %s ($%d)."):format(tostring(stageId), tonumber(price) or 0))
	end
end

function GateService:_pushBackCharacter(player, gatePart)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp or not isBasePart(hrp) then return end
	if not gatePart or not isBasePart(gatePart) then return end

	local back = gatePart:FindFirstChild("Back")
	if back and back:IsA("Attachment") then
		hrp.CFrame = CFrame.new(back.WorldPosition) * CFrame.new(0, 3, 0)
		return
	end

	local cf = gatePart.CFrame
	hrp.CFrame = cf * CFrame.new(0, 3, 6)
end

function GateService:_bindGate(gate)
	local stageId, price = readGateConfig(gate)
	if not stageId then return end
	if price < 0 then price = 0 end

	local key = self:_keyForGate(gate)
	self._gateByKey[key] = gate

	local prompt = ensurePrompt(gate)
	if prompt then
		prompt.ActionText = "Unlock"
		prompt.ObjectText = "Stage " .. stageId
		prompt.Triggered:Connect(function(player)
			if self:_isUnlocked(player, stageId) then
				if self.Net and self.Net.Notify then
					self.Net:Notify(player, "Gate already unlocked.")
				end
				return
			end
			self:_notifyLocked(player, stageId, price)
		end)
	end

	local gatePart = getGatePromptParent(gate)
	if gatePart and isBasePart(gatePart) then
		gatePart.Touched:Connect(function(hit)
			local char = hit and hit.Parent
			local plr = char and Players:GetPlayerFromCharacter(char)
			if not plr then return end

			local now = os.clock()
			local last = self._gateTouchDebounce[plr] or 0
			if now - last < 0.5 then return end
			self._gateTouchDebounce[plr] = now

			if not self:_isUnlocked(plr, stageId) then
				self:_pushBackCharacter(plr, gatePart)
				if self.Net and self.Net.Notify then
					self.Net:Notify(plr, ("Gate locked: Stage %s"):format(stageId))
				end
			end
		end)
	end
end

function GateService:_scanGates()
	if not self.GatesFolder then return end

	for _, obj in ipairs(self.GatesFolder:GetChildren()) do
		self:_bindGate(obj)
	end

	self.GatesFolder.ChildAdded:Connect(function(child)
		task.defer(function()
			self:_bindGate(child)
		end)
	end)
end

function GateService:_handleGateAction(player, payload)
	if typeof(payload) ~= "table" then return false, "BadPayload" end

	local stageId = payload.stageId or payload.key or payload.stage
	local price = payload.price
	local accept = payload.accept

	if typeof(stageId) == "number" then stageId = tostring(stageId) end
	if typeof(stageId) ~= "string" or stageId == "" then
		return false, "MissingStageId"
	end

	if typeof(accept) ~= "boolean" then accept = true end
	if not accept then
		return true, "Cancelled"
	end

	price = tonumber(price) or nil
	if price == nil then
		for _, g in pairs(self._gateByKey) do
			local s, p = readGateConfig(g)
			if s == stageId then
				price = p
				break
			end
		end
	end
	price = tonumber(price) or 0
	if price < 0 then price = 0 end

	if self:_isUnlocked(player, stageId) then
		return true, "AlreadyUnlocked"
	end

	if self.Economy and self.Economy.SpendCash then
		local ok, err = self.Economy:SpendCash(player, price)
		if not ok then
			if self.Net and self.Net.Notify then
				self.Net:Notify(player, "Not enough cash.")
			end
			return false, err or "InsufficientFunds"
		end
	end

	if self.Progression and self.Progression.UnlockStage then
		self.Progression:UnlockStage(player, stageId)
	elseif self.Data and self.Data.SetValue then
		local t = self.Data:GetValue(player, "Progression.StageUnlocked")
		if typeof(t) ~= "table" then t = {} end
		t[stageId] = true
		self.Data:SetValue(player, "Progression.StageUnlocked", t)
	end

	if self.Net and self.Net.Notify then
		self.Net:Notify(player, ("Unlocked Stage %s!"):format(stageId))
	end

	return true, "Unlocked"
end

function GateService:Start()
	self:_scanGates()

	if self.Net then
		if self.Net.RouteFunction then
			self.Net:RouteFunction("GateAction", function(player, payload)
				return self:_handleGateAction(player, payload)
			end)
		elseif self.Net.BindFunction then
			self.Net:BindFunction("GateAction", function(player, payload)
				return self:_handleGateAction(player, payload)
			end)
		elseif self.Net.RegisterFunction then
			self.Net:RegisterFunction("GateAction", function(player, payload)
				return self:_handleGateAction(player, payload)
			end)
		end
	end
end

return GateService