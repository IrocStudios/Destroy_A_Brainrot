--!strict
-- ServerStorage/Services/DeathService.lua
-- Handles player death -> Drop or Keep inventory choice.
-- Disables auto-respawn; first spawn happens after DataService loads profile.

local Players = game:GetService("Players")

local DeathService = {}
DeathService.__index = DeathService

function DeathService:Init(services)
	self.Services       = services
	self.DataService    = services.DataService
	self.NetService     = services.NetService
	self.EconomyService = services.EconomyService

	self._dead  = {} :: {[Player]: boolean}  -- true while waiting for Drop/Keep
	self._conns = {} :: {[Player]: {RBXScriptConnection}}

	-- Disable auto-respawn globally so we control when characters load.
	Players.CharacterAutoLoads = false
	print("[DeathService] Init OK – CharacterAutoLoads = false")
end

function DeathService:Start()
	local DataService = self.DataService

	-- First spawn: load character once the player's profile is ready.
	if DataService and DataService.OnProfileLoaded
		and type(DataService.OnProfileLoaded.Connect) == "function" then
		DataService.OnProfileLoaded:Connect(function(player)
			if player and player.Parent then
				print(("[DeathService] Profile loaded for %s – spawning character"):format(player.Name))
				player:LoadCharacter()
			end
		end)
	end

	-- Hook every player for death detection.
	Players.PlayerAdded:Connect(function(player)
		self:_hookPlayer(player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		self:_hookPlayer(player)
	end

	-- Cleanup on leave.
	Players.PlayerRemoving:Connect(function(player)
		self:_cleanup(player)
	end)

	print("[DeathService] Start OK")
end

---------------------------------------------------------------------------
-- Player / character hooks
---------------------------------------------------------------------------

function DeathService:_hookPlayer(player: Player)
	if self._conns[player] then return end
	self._conns[player] = {}

	local conn = player.CharacterAdded:Connect(function(character)
		self._dead[player] = nil  -- alive again
		self:_hookCharacterDeath(player, character)
	end)
	table.insert(self._conns[player], conn)

	-- If character already exists (edge case)
	if player.Character then
		self:_hookCharacterDeath(player, player.Character)
	end
end

function DeathService:_hookCharacterDeath(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then return end

	humanoid.Died:Connect(function()
		self:_onDeath(player)
	end)
end

---------------------------------------------------------------------------
-- Death handler
---------------------------------------------------------------------------

function DeathService:_onDeath(player: Player)
	if self._dead[player] then return end  -- prevent double-fire
	self._dead[player] = true

	-- Increment lifetime death counter
	local newDeaths = 0
	if self.DataService and type(self.DataService.Increment) == "function" then
		self.DataService:Increment(player, "Stats.Deaths", 1)
		local v = self.DataService:GetValue(player, "Stats.Deaths")
		newDeaths = tonumber(v) or 0
	end
	if self.NetService then
		self.NetService:QueueDelta(player, "Deaths", newDeaths)
		-- Don't flush yet — the Notify below will be a separate event
	end

	-- Calculate keepCost from player level
	local level = 1
	if self.DataService and type(self.DataService.GetValue) == "function" then
		local v = self.DataService:GetValue(player, "Progression.Level")
		if type(v) == "number" and v > 0 then
			level = v
		end
	end
	local keepCost = level * 1  -- $1 per level  (simple formula, expandable later)

	print(("[DeathService] %s died. Deaths=%d  Level=%d  KeepCost=$%d"):format(player.Name, newDeaths, level, keepCost))

	-- Flush stats delta + notify client to open the Died frame
	if self.NetService then
		self.NetService:FlushDelta(player)
		self.NetService:Notify(player, {
			type     = "died",
			keepCost = keepCost,
		})
	end
end

---------------------------------------------------------------------------
-- RemoteFunction handler  (routed via NetService -> "DeathAction")
---------------------------------------------------------------------------

function DeathService:HandleDeathAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return { ok = false, reason = "BadPayload" }
	end

	if not self._dead[player] then
		return { ok = false, reason = "NotDead" }
	end

	local action = tostring(payload.action or "")

	if action == "drop" then
		return self:_handleDrop(player)
	elseif action == "keep" then
		return self:_handleKeep(player)
	end

	return { ok = false, reason = "UnknownAction" }
end

---------------------------------------------------------------------------
-- DROP: clear inventory, respawn free
---------------------------------------------------------------------------

function DeathService:_handleDrop(player: Player)
	print(("[DeathService] %s chose DROP"):format(player.Name))

	-- Wipe inventory data
	self.DataService:Update(player, function(profile)
		profile.Inventory = profile.Inventory or {}
		profile.Inventory.WeaponsOwned   = {}
		profile.Inventory.EquippedWeapon = ""
		-- Also wipe template-side fields (ToolsOwned / EquippedTool)
		profile.Inventory.ToolsOwned  = {}
		profile.Inventory.EquippedTool = nil
		return profile
	end)

	-- Send deltas so client state updates
	if self.NetService then
		self.NetService:QueueDelta(player, "WeaponsOwned", {})
		self.NetService:QueueDelta(player, "EquippedWeapon", "")
		self.NetService:FlushDelta(player)
	end

	-- Destroy physical Tool instances
	self:_destroyAllTools(player)

	-- Respawn (defer so RF return reaches client before character loads)
	self._dead[player] = nil
	task.defer(function()
		if player and player.Parent then
			player:LoadCharacter()
		end
	end)

	return { ok = true }
end

---------------------------------------------------------------------------
-- KEEP: charge keepCost, respawn with inventory
---------------------------------------------------------------------------

function DeathService:_handleKeep(player: Player)
	-- Recalculate keepCost server-side (never trust client)
	local level = 1
	if self.DataService and type(self.DataService.GetValue) == "function" then
		local v = self.DataService:GetValue(player, "Progression.Level")
		if type(v) == "number" and v > 0 then
			level = v
		end
	end
	local keepCost = level * 1

	print(("[DeathService] %s chose KEEP. Cost=$%d"):format(player.Name, keepCost))

	-- Attempt to charge the player
	if not self.EconomyService then
		return { ok = false, reason = "ServerError" }
	end

	local chargeOk, chargeErr = self.EconomyService:SpendCash(player, keepCost)
	if not chargeOk then
		print(("[DeathService] %s can't afford Keep ($%d): %s"):format(
			player.Name, keepCost, tostring(chargeErr)))
		return { ok = false, reason = "InsufficientCash" }
	end

	-- Respawn with inventory intact
	self._dead[player] = nil
	task.defer(function()
		if player and player.Parent then
			player:LoadCharacter()
		end
	end)

	return { ok = true }
end

---------------------------------------------------------------------------
-- Utility: destroy all Tools in Backpack + Character
---------------------------------------------------------------------------

function DeathService:_destroyAllTools(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end

	local char = player.Character
	if char then
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

function DeathService:_cleanup(player: Player)
	self._dead[player] = nil
	local conns = self._conns[player]
	if conns then
		for _, conn in ipairs(conns) do
			if typeof(conn) == "RBXScriptConnection" then
				conn:Disconnect()
			end
		end
		self._conns[player] = nil
	end
end

return DeathService
