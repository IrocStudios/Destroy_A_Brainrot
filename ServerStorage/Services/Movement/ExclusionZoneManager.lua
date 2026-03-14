--!strict
-- ExclusionZoneManager
-- Scans Workspace.ExclusionZones for zone parts with a Weight attribute.
-- Provides queries for point-in-zone, pathfinding costs, and nearest-edge points.
-- Used by AIService (decision-making), BrainrotService (spawn rejection), and
-- Movement modules (pathfinding cost tables).

local Workspace = game:GetService("Workspace")

local DEBUG = false
local function dprint(...)
	if DEBUG then print("[ExclusionZones]", ...) end
end

export type ZoneEntry = {
	Part: BasePart,
	Weight: number, -- 0-100
	HalfSize: Vector3,
	CFrame: CFrame,
}

local ExclusionZoneManager = {}

local _zones: { ZoneEntry } = {}
local _folder: Folder? = nil
local _connections: { RBXScriptConnection } = {}

----------------------------------------------------------------------
-- Internal helpers
----------------------------------------------------------------------

local function readWeight(part: BasePart): number
	local w = part:GetAttribute("Weight")
	if typeof(w) == "number" then
		return math.clamp(w, 0, 100)
	end
	return 50 -- default if attribute missing
end

local function makeEntry(part: BasePart): ZoneEntry
	return {
		Part = part,
		Weight = readWeight(part),
		HalfSize = part.Size * 0.5,
		CFrame = part.CFrame,
	}
end

local function refreshEntry(entry: ZoneEntry)
	entry.Weight = readWeight(entry.Part)
	entry.HalfSize = entry.Part.Size * 0.5
	entry.CFrame = entry.Part.CFrame
end

local function isPointInsideBox(cf: CFrame, halfSize: Vector3, point: Vector3): boolean
	local localPos = cf:PointToObjectSpace(point)
	return math.abs(localPos.X) <= halfSize.X
		and math.abs(localPos.Y) <= halfSize.Y
		and math.abs(localPos.Z) <= halfSize.Z
end

----------------------------------------------------------------------
-- Scanning
----------------------------------------------------------------------

local function addZonePart(part: BasePart)
	-- Check if already tracked
	for _, z in ipairs(_zones) do
		if z.Part == part then
			refreshEntry(z)
			return
		end
	end
	local entry = makeEntry(part)
	table.insert(_zones, entry)
	dprint("Added zone:", part.Name, "Weight=", entry.Weight)
end

local function removeZonePart(part: BasePart)
	for i = #_zones, 1, -1 do
		if _zones[i].Part == part then
			dprint("Removed zone:", part.Name)
			table.remove(_zones, i)
			return
		end
	end
end

local function scanFolder(folder: Folder)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			addZonePart(child)
		end
	end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

--- Initialize: find or wait for Workspace.ExclusionZones, scan and listen.
function ExclusionZoneManager:Init()
	local folder = Workspace:FindFirstChild("ExclusionZones")
	if not folder then
		dprint("ExclusionZones folder not found, creating empty watcher")
		-- Watch for it to appear later
		table.insert(_connections, Workspace.ChildAdded:Connect(function(child)
			if child.Name == "ExclusionZones" and child:IsA("Folder") then
				_folder = child :: Folder
				self:_bindFolder(child :: Folder)
			end
		end))
		return
	end

	_folder = folder :: Folder
	self:_bindFolder(folder :: Folder)
end

function ExclusionZoneManager:_bindFolder(folder: Folder)
	scanFolder(folder)

	table.insert(_connections, folder.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then
			addZonePart(child)
		end
	end))

	table.insert(_connections, folder.ChildRemoved:Connect(function(child)
		if child:IsA("BasePart") then
			removeZonePart(child)
		end
	end))

	dprint("Bound to ExclusionZones folder,", #_zones, "zones loaded")
end

--- Refresh cached CFrames/sizes (call periodically if zones move at runtime).
function ExclusionZoneManager:Refresh()
	for _, z in ipairs(_zones) do
		if z.Part and z.Part.Parent then
			refreshEntry(z)
		end
	end
end

--- Check if a point is inside any exclusion zone.
--- Returns: isInside, highestWeight, zone entry (or nil)
function ExclusionZoneManager:Query(point: Vector3): (boolean, number, ZoneEntry?)
	local highestWeight = 0
	local highestZone: ZoneEntry? = nil

	for _, z in ipairs(_zones) do
		if z.Part.Parent and isPointInsideBox(z.CFrame, z.HalfSize, point) then
			if z.Weight > highestWeight then
				highestWeight = z.Weight
				highestZone = z
			end
		end
	end

	if highestZone then
		return true, highestWeight, highestZone
	end
	return false, 0, nil
end

--- Check if a point is inside any exclusion zone with weight >= minWeight.
function ExclusionZoneManager:IsBlocked(point: Vector3, minWeight: number?): boolean
	local threshold = minWeight or 1
	for _, z in ipairs(_zones) do
		if z.Weight >= threshold and z.Part.Parent then
			if isPointInsideBox(z.CFrame, z.HalfSize, point) then
				return true
			end
		end
	end
	return false
end

--- Get the nearest point OUTSIDE a specific zone (for WaitAtEdge behavior).
--- Projects the point to the closest face of the zone box.
function ExclusionZoneManager:GetNearestEdgePoint(point: Vector3, zone: ZoneEntry): Vector3
	local localPos = zone.CFrame:PointToObjectSpace(point)
	local hs = zone.HalfSize

	-- Find which face is closest and push the point just outside it
	local pushDist = 3 -- studs outside the edge

	local dists = {
		{ axis = "X", sign =  1, dist = hs.X - localPos.X },
		{ axis = "X", sign = -1, dist = hs.X + localPos.X },
		{ axis = "Z", sign =  1, dist = hs.Z - localPos.Z },
		{ axis = "Z", sign = -1, dist = hs.Z + localPos.Z },
	}

	local best = dists[1]
	for i = 2, #dists do
		if dists[i].dist < best.dist then
			best = dists[i]
		end
	end

	local edgeLocal: Vector3
	if best.axis == "X" then
		edgeLocal = Vector3.new(hs.X * best.sign + pushDist * best.sign, localPos.Y, localPos.Z)
	else
		edgeLocal = Vector3.new(localPos.X, localPos.Y, hs.Z * best.sign + pushDist * best.sign)
	end

	return zone.CFrame:PointToWorldSpace(edgeLocal)
end

--- Build a PathfindingService-compatible cost table from exclusion zones.
--- Zones must be labeled (via CollectionService tag or Material override) for this to work.
--- For now, returns a table mapping zone Weight ranges to cost multipliers
--- that can be used when configuring PathfindingModifiers.
function ExclusionZoneManager:GetPathCostMultiplier(weight: number): number
	if weight >= 80 then
		return math.huge -- impassable
	elseif weight >= 50 then
		return 10.0
	elseif weight >= 20 then
		return 4.0
	elseif weight >= 1 then
		return 1.5
	end
	return 1.0
end

--- Get all zone entries (for external iteration, e.g., setting up PathfindingModifiers).
function ExclusionZoneManager:GetAllZones(): { ZoneEntry }
	return _zones
end

--- Get all zone parts (convenience for OverlapParams exclusion lists).
function ExclusionZoneManager:GetAllZoneParts(): { BasePart }
	local parts = {}
	for _, z in ipairs(_zones) do
		if z.Part.Parent then
			table.insert(parts, z.Part)
		end
	end
	return parts
end

return ExclusionZoneManager
