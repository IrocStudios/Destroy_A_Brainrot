--!strict
-- StarterPlayerScripts/Controllers/BrainrotClient.lua
-- Client-side visuals: attaches Body models + billboard UI + plays animations based on server CurrentAnimation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer

local BrainrotClient = {}
BrainrotClient.__index = BrainrotClient

local DEBUG = true
local function dprint(...)
	if DEBUG then
		print("[BrainrotClient]", ...)
	end
end
local function dwarn(...)
	if DEBUG then
		warn("[BrainrotClient]", ...)
	end
end

type ActiveEntry = {
	Model: Model,
	HRP: BasePart,
	Humanoid: Humanoid,

	Body: Model?,
	BodyRoot: BasePart?,
	Weld: WeldConstraint?,
	Billboard: BillboardGui?,

	AnimTracks: { [string]: AnimationTrack },
	LastPlayedAnimName: string?,
	Conn: { RBXScriptConnection },
}

local function getEnemiesFolder(): Folder
	return Workspace:WaitForChild("Enemies") :: Folder
end

local function getBrainrotsFolder(): Folder
	return ReplicatedStorage:WaitForChild("Brainrots") :: Folder
end

local function getBillboardTemplate(): BillboardGui?
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local bb = assets:FindFirstChild("InfoBoard")
	if bb and bb:IsA("BillboardGui") then
		return bb
	end
	return nil
end

local function getLocalHRP(): BasePart?
	local char = LOCAL_PLAYER.Character
	if not char then return nil end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return (hrp and hrp:IsA("BasePart")) and hrp or nil
end

local function findHRP(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	local pp = model.PrimaryPart
	if pp and pp:IsA("BasePart") then return pp end
	return nil
end

local function findHumanoid(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid")
end

local function findBodyRoot(body: Model): BasePart?
	if body.PrimaryPart and body.PrimaryPart:IsA("BasePart") then
		return body.PrimaryPart
	end
	local hrp = body:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then return hrp end
	for _, d in ipairs(body:GetDescendants()) do
		if d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function setNoCollideMassless(model: Instance)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
		end
	end
end

local function ensureAnimator(body: Model): Animator?
	local hum = body:FindFirstChildOfClass("Humanoid")
	if hum then
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = hum
		end
		return animator
	end

	local ac = body:FindFirstChildOfClass("AnimationController")
	if not ac then
		ac = Instance.new("AnimationController")
		ac.Name = "AnimationController"
		ac.Parent = body
	end
	local animator = ac:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = ac
	end
	return animator
end

local function lowerKey(s: string): string
	return string.lower(s)
end

local function findAnim(animFolder: Folder, name: string): Animation?
	local a = animFolder:FindFirstChild(name)
	if a and a:IsA("Animation") then return a end
	local target = lowerKey(name)
	for _, child in ipairs(animFolder:GetChildren()) do
		if child:IsA("Animation") and lowerKey(child.Name) == target then
			return child
		end
	end
	return nil
end

function BrainrotClient.new()
	local self = setmetatable({}, BrainrotClient)
	self.RenderDistance = 220
	self._active = {} :: { [Model]: ActiveEntry }
	self._running = false
	self._forceAttachOnJoin = true
	return self
end

function BrainrotClient:_refreshBillboard(entry: ActiveEntry)
	local bb = entry.Billboard
	if not bb then return end

	local info = entry.Model:FindFirstChild("EnemyInfo")
	local displayName = "Unknown"
	local rarityName = "Common"
	local price = 0

	if info and info:IsA("Configuration") then
		displayName = tostring(info:GetAttribute("DisplayName") or displayName)
		rarityName = tostring(info:GetAttribute("RarityName") or rarityName)
		price = tonumber(info:GetAttribute("Price")) or price
	end

	local function findText(name: string): TextLabel?
		local obj = bb:FindFirstChild(name, true)
		return (obj and obj:IsA("TextLabel")) and obj or nil
	end

	local title = findText("Title") or findText("EnemyName")
	if title then title.Text = displayName end

	local rarityText = findText("Rarity")
	if rarityText then rarityText.Text = rarityName end

	local priceText = findText("Price")
	if priceText then
		local txt = "$" .. tostring(price)
		if price >= 1000 then
			txt = ("$%.1fk"):format(price / 1000)
		end
		priceText.Text = txt
	end

	local healthBar = bb:FindFirstChild("Health", true)
	if healthBar and healthBar:IsA("Frame") then
		local maxH = math.max(1, entry.Humanoid.MaxHealth)
		local pct = math.clamp(entry.Humanoid.Health / maxH, 0, 1)
		healthBar.Size = UDim2.new(pct, 0, healthBar.Size.Y.Scale, healthBar.Size.Y.Offset)
	end

	local studLabel = findText("Stud")
	if studLabel then
		studLabel.Text = tostring(math.floor(entry.Humanoid.Health + 0.5))
	end
end

function BrainrotClient:_playAnimByName(entry: ActiveEntry, animName: string)
	if not entry.Body or not entry.Body.Parent then
		dwarn("PlayAnim called but Body missing for", entry.Model:GetFullName(), "requested:", animName)
		return
	end

	local animFolder = entry.Body:FindFirstChild("Animations")
	if not animFolder or not animFolder:IsA("Folder") then
		dwarn("Missing Body.Animations folder for", entry.Model:GetFullName(), "requested:", animName)
		return
	end

	local animObj = findAnim(animFolder, animName)
	if not animObj then
		dwarn("Animation not found:", animName, "in", animFolder:GetFullName(), "for", entry.Model:GetFullName())
		return
	end

	if animObj.AnimationId == nil or animObj.AnimationId == "" then
		dwarn("AnimationId EMPTY for", animObj:GetFullName(), "name:", animObj.Name)
		return
	end

	local animator = ensureAnimator(entry.Body)
	if not animator then
		dwarn("No animator available for", entry.Model:GetFullName(), "anim:", animObj.Name)
		return
	end

	local key = animObj.AnimationId .. "|" .. animObj.Name
	local track = entry.AnimTracks[key]
	if not track then
		local ok, loadedOrErr = pcall(function()
			return animator:LoadAnimation(animObj)
		end)
		if not ok then
			dwarn("LoadAnimation FAILED for", entry.Model:GetFullName(), "anim:", animObj.Name, "err:", loadedOrErr)
			return
		end
		track = loadedOrErr
		entry.AnimTracks[key] = track
		dprint("Loaded track:", animObj.Name, "len=", track.Length, "id=", animObj.AnimationId, "model=", entry.Model.Name)
	end

	if entry.LastPlayedAnimName == animObj.Name and track.IsPlaying then
		return
	end

	for _, tr in pairs(entry.AnimTracks) do
		if tr ~= track and tr.IsPlaying then
			pcall(function()
				tr:Stop(0.1)
			end)
		end
	end

	entry.LastPlayedAnimName = animObj.Name
	dprint("Playing anim:", animObj.Name, "requested:", animName, "model=", entry.Model.Name)
	track:Play(0.1, 1, 1)
end

function BrainrotClient:_refreshAnim(entry: ActiveEntry)
	if not entry.Body or not entry.Body.Parent then return end

	local animValue = entry.Model:FindFirstChild("CurrentAnimation")
	if not animValue or not animValue:IsA("StringValue") then
		return
	end

	local desired = animValue.Value
	if type(desired) ~= "string" or desired == "" then
		desired = "Idle"
	end

	local animFolder = entry.Body:FindFirstChild("Animations")
	if not animFolder or not animFolder:IsA("Folder") then
		return
	end

	if not findAnim(animFolder, desired) then
		if findAnim(animFolder, "Idle") then
			desired = "Idle"
		elseif findAnim(animFolder, "Walk") then
			desired = "Walk"
		else
			return
		end
	end

	self:_playAnimByName(entry, desired)
end

function BrainrotClient:_attach(entry: ActiveEntry)
	if entry.Body and entry.Body.Parent then return end

	local brainrotName = entry.Model:GetAttribute("BrainrotName")
	if type(brainrotName) ~= "string" or brainrotName == "" then
		return
	end

	local source = getBrainrotsFolder():FindFirstChild(brainrotName)
	if not source or not source:IsA("Model") then
		dwarn("Attach failed: missing source model in ReplicatedStorage.Brainrots for", brainrotName, "enemy=", entry.Model:GetFullName())
		return
	end

	local body = source:Clone()
	body.Name = "Body"
	body.Parent = entry.Model

	setNoCollideMassless(body)

	local bodyRoot = findBodyRoot(body)
	if not bodyRoot then
		dwarn("Attach failed: could not find BodyRoot for", entry.Model:GetFullName(), "brainrotName=", brainrotName)
		body:Destroy()
		return
	end

	bodyRoot.CFrame = entry.HRP.CFrame

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = entry.HRP
	weld.Part1 = bodyRoot
	weld.Parent = entry.HRP

	entry.Body = body
	entry.BodyRoot = bodyRoot
	entry.Weld = weld

	dprint("Body attached:", entry.Model.Name, "brainrotName=", brainrotName, "BodyRoot=", bodyRoot.Name)

	local bbTemplate = getBillboardTemplate()
	if bbTemplate then
		local bb = bbTemplate:Clone()
		bb.Name = "InfoBoard"
		bb.Adornee = entry.HRP
		bb.Parent = entry.Model
		entry.Billboard = bb
	end

	self:_refreshBillboard(entry)
	self:_refreshAnim(entry)
end

function BrainrotClient:_detach(entry: ActiveEntry)
	if entry.Weld then
		entry.Weld:Destroy()
		entry.Weld = nil
	end

	if entry.Body and entry.Body.Parent then
		entry.Body:Destroy()
	end
	entry.Body = nil
	entry.BodyRoot = nil

	if entry.Billboard and entry.Billboard.Parent then
		entry.Billboard:Destroy()
	end
	entry.Billboard = nil

	for _, tr in pairs(entry.AnimTracks) do
		pcall(function()
			tr:Stop(0.1)
			tr:Destroy()
		end)
	end
	table.clear(entry.AnimTracks)
	entry.LastPlayedAnimName = nil
end

function BrainrotClient:_removeBillboardNow(entry: ActiveEntry)
	if entry.Billboard and entry.Billboard.Parent then
		dprint("Removing billboard (death):", entry.Model.Name)
		entry.Billboard:Destroy()
	end
	entry.Billboard = nil
end

function BrainrotClient:_trackEnemy(model: Model)
	if self._active[model] then return end

	local hum = findHumanoid(model)
	local hrp = findHRP(model)
	if not hum or not hrp then return end

	local entry: ActiveEntry = {
		Model = model,
		HRP = hrp,
		Humanoid = hum,

		Body = nil,
		BodyRoot = nil,
		Weld = nil,
		Billboard = nil,

		AnimTracks = {},
		LastPlayedAnimName = nil,
		Conn = {},
	}

	dprint("Tracking enemy:", model.Name)

	local animSv = model:FindFirstChild("CurrentAnimation")
	if animSv and animSv:IsA("StringValue") then
		table.insert(entry.Conn, animSv.Changed:Connect(function()
			self:_refreshAnim(entry)
		end))
	end

	table.insert(entry.Conn, model:GetAttributeChangedSignal("BrainrotName"):Connect(function()
		self:_attach(entry)
	end))

	table.insert(entry.Conn, hum.HealthChanged:Connect(function()
		self:_refreshBillboard(entry)
	end))

	table.insert(entry.Conn, hum.Died:Connect(function()
		dprint("Enemy died:", model.Name)
		self:_removeBillboardNow(entry)
	end))

	table.insert(entry.Conn, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			self:_untrackEnemy(model)
		end
	end))

	self._active[model] = entry
end

function BrainrotClient:_trackEnemyWithRetry(model: Model)
	if self._active[model] then return end

	task.spawn(function()
		local start = os.clock()
		while os.clock() - start < 8 do
			if not model:IsDescendantOf(game) then
				return
			end
			local hum = findHumanoid(model)
			local hrp = findHRP(model)
			if hum and hrp then
				self:_trackEnemy(model)
				local entry = self._active[model]
				if entry and self._forceAttachOnJoin then
					self:_attach(entry)
				end
				return
			end
			task.wait(0.1)
		end
		dwarn("TrackEnemyWithRetry timed out:", model:GetFullName())
	end)
end

function BrainrotClient:_untrackEnemy(model: Model)
	local entry = self._active[model]
	if not entry then return end
	self._active[model] = nil

	dprint("Untracking enemy:", model.Name)

	self:_detach(entry)

	for _, c in ipairs(entry.Conn) do
		c:Disconnect()
	end
end

function BrainrotClient:_updateRange()
	local myHRP = getLocalHRP()
	if not myHRP then return end

	for _, entry in pairs(self._active) do
		if entry.Model.Parent == nil then
			self:_untrackEnemy(entry.Model)
		else
			local d = (myHRP.Position - entry.HRP.Position).Magnitude
			if d <= self.RenderDistance then
				self:_attach(entry)
			else
				self:_detach(entry)
			end
		end
	end
end

function BrainrotClient:Start()
	if self._running then return end
	self._running = true

	local enemies = getEnemiesFolder()

	enemies.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			dprint("Enemies.ChildAdded:", child.Name)
			self:_trackEnemyWithRetry(child)
		end
	end)

	enemies.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			dprint("Enemies.ChildRemoved:", child.Name)
			self:_untrackEnemy(child)
		end
	end)

	for _, child in ipairs(enemies:GetChildren()) do
		if child:IsA("Model") then
			self:_trackEnemyWithRetry(child)
		end
	end

	task.spawn(function()
		while self._running do
			self:_updateRange()
			task.wait(0.25)
		end
	end)
end

return BrainrotClient.new()