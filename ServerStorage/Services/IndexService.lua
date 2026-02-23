--!strict
local IndexService = {}

function IndexService:Init(services)
	self.Services = services
	self.DataService = services.DataService
	self.NetService = services.NetService
end

function IndexService:Start() end

function IndexService:RegisterKill(player: Player, brainrotId: string)
	if typeof(brainrotId) ~= "string" or brainrotId == "" then
		return false, "InvalidBrainrotId"
	end

	local newCount = 0
	local mapCopy = nil

	self.DataService:Update(player, function(profile)
		profile.Index = profile.Index or {}
		profile.Index.BrainrotsKilled = profile.Index.BrainrotsKilled or {}

		local m = profile.Index.BrainrotsKilled
		m[brainrotId] = (m[brainrotId] or 0) + 1
		newCount = m[brainrotId]
		mapCopy = m
		return profile
	end)

	if self.NetService and self.NetService.SendDelta then
		-- set whole map (simple + robust). You can later upgrade to per-key ops.
		self.NetService:SendDelta(player, { op = "set", path = "Index.BrainrotsKilled", value = mapCopy })
	end

	return true, newCount
end

function IndexService:RegisterDiscovery(player: Player, brainrotId: string, brainrotName: string?, rarityName: string?)
	if typeof(brainrotId) ~= "string" or brainrotId == "" then
		return false, "InvalidBrainrotId"
	end

	local alreadyDiscovered = false
	local mapCopy = nil

	self.DataService:Update(player, function(profile)
		profile.Index = profile.Index or {}
		profile.Index.BrainrotsDiscovered = profile.Index.BrainrotsDiscovered or {}

		local m = profile.Index.BrainrotsDiscovered
		if m[brainrotId] then
			alreadyDiscovered = true
		else
			m[brainrotId] = true
		end
		mapCopy = m
		return profile
	end)

	if not alreadyDiscovered then
		if self.NetService and self.NetService.SendDelta then
			self.NetService:SendDelta(player, { op = "set", path = "Index.BrainrotsDiscovered", value = mapCopy })
		end

		-- optional notify (client UI binding in Chat 10)
		if self.NetService and self.NetService.Notify then
			self.NetService:Notify(player, {
				type = "Discovery",
				brainrotId = brainrotId,
				name = brainrotName or "Brainrot",
				rarity = rarityName or "Common",
			})
		end
	end

	return true, not alreadyDiscovered
end

return IndexService