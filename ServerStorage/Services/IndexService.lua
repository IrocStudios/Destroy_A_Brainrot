--!strict
-- IndexService
-- Tracks brainrot kills and first-time discoveries.
-- RegisterKill: increments kill counter by brainrot type name.
-- RegisterDiscovery: marks first discovery, fires Notify to client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IndexService = {}

function IndexService:Init(services)
	self.Services = services
	self.DataService = services.DataService
	self.NetService = services.NetService

	-- Cache BrainrotConfig for display name lookups
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("BrainrotConfig"))
	end)
	self._brainrotConfig = ok and cfg or {}
end

function IndexService:Start() end

function IndexService:RegisterKill(player: Player, brainrotName: string)
	if typeof(brainrotName) ~= "string" or brainrotName == "" then
		return false, "InvalidBrainrotName"
	end

	local newCount = 0
	local mapCopy = nil

	self.DataService:Update(player, function(profile)
		profile.Index = profile.Index or {}
		profile.Index.BrainrotsKilled = profile.Index.BrainrotsKilled or {}

		local m = profile.Index.BrainrotsKilled
		m[brainrotName] = (m[brainrotName] or 0) + 1
		newCount = m[brainrotName]
		mapCopy = m
		return profile
	end)

	if self.NetService then
		self.NetService:QueueDelta(player, "BrainrotsKilled", mapCopy)
		self.NetService:FlushDelta(player)
	end

	return true, newCount
end

function IndexService:RegisterDiscovery(player: Player, brainrotName: string, brainrotDisplayName: string?, rarityName: string?)
	if typeof(brainrotName) ~= "string" or brainrotName == "" then
		return false, "InvalidBrainrotName"
	end

	local alreadyDiscovered = false
	local mapCopy = nil

	self.DataService:Update(player, function(profile)
		profile.Index = profile.Index or {}
		profile.Index.BrainrotsDiscovered = profile.Index.BrainrotsDiscovered or {}

		local m = profile.Index.BrainrotsDiscovered
		if m[brainrotName] then
			alreadyDiscovered = true
		else
			m[brainrotName] = true
		end
		mapCopy = m
		return profile
	end)

	if not alreadyDiscovered then
		-- Send delta so client state updates
		if self.NetService then
			self.NetService:QueueDelta(player, "BrainrotsDiscovered", mapCopy)
			self.NetService:FlushDelta(player)
		end

		-- Look up display name from config if not provided
		local displayName = brainrotDisplayName
		if not displayName or displayName == "" then
			local entry = self._brainrotConfig[brainrotName]
			displayName = entry and entry.DisplayName or brainrotName
		end

		-- Notify client to show Discovery popup
		if self.NetService and self.NetService.Notify then
			self.NetService:Notify(player, {
				type       = "discovery",
				brainrotId = brainrotName,
				name       = displayName,
				rarity     = rarityName or "Common",
			})
		end

		print(("[IndexService] %s discovered: %s (%s)"):format(player.Name, displayName, rarityName or "Common"))
	end

	return true, not alreadyDiscovered
end

return IndexService
