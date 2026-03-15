--!strict
-- CollisionSetup.server.lua
-- Bullet-blocking barriers that players can walk through.
--
-- Strategy: NoShoot parts stay in Default collision group (CanCollide=true)
-- so the WeaponsSystem raycasts hit them normally. Player CHARACTERS are
-- put in a "PlayerCharacter" group that doesn't collide with NoShoot parts,
-- so players phase through while bullets stop.
--
-- In Studio, place parts named "NoShoot" inside any ExclusionZone folder:
--   Workspace > ExclusionZones > [ZoneName] > NoShoot
--
-- Part properties (set in Studio):
--   CanCollide   = true
--   Anchored     = true
--   Transparency = 0.5–0.7
--   Material     = ForceField
--   CastShadow   = false

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

----------------------------------------------------------------------
-- 1. Register collision groups
----------------------------------------------------------------------
PhysicsService:RegisterCollisionGroup("PlayerCharacter")
PhysicsService:RegisterCollisionGroup("NoShoot")

----------------------------------------------------------------------
-- 2. Collision rules
--    PlayerCharacter ↔ NoShoot  = NO collision  (players walk through)
--    Default ↔ NoShoot          = YES collision  (raycasts/bullets hit)
--    PlayerCharacter ↔ Default  = YES collision  (normal world collision)
--    PlayerCharacter ↔ PlayerCharacter = NO collision (no player-player blocking)
----------------------------------------------------------------------
PhysicsService:CollisionGroupSetCollidable("PlayerCharacter", "NoShoot", false)
PhysicsService:CollisionGroupSetCollidable("PlayerCharacter", "PlayerCharacter", false)
-- Default ↔ NoShoot stays collidable (default behavior) — bullets hit NoShoot parts

----------------------------------------------------------------------
-- 3. Assign player character parts to PlayerCharacter group
----------------------------------------------------------------------
local function assignCharacterGroup(character: Model)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "PlayerCharacter"
		end
	end
	-- Watch for parts added later (accessories, tools, etc.)
	character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = "PlayerCharacter"
		end
	end)
end

local function onPlayerAdded(player: Player)
	if player.Character then
		assignCharacterGroup(player.Character)
	end
	player.CharacterAdded:Connect(assignCharacterGroup)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)

----------------------------------------------------------------------
-- 4. Assign NoShoot parts to the NoShoot collision group
----------------------------------------------------------------------
local function assignNoShoot(part: BasePart)
	part.CollisionGroup = "NoShoot"
end

local function scanFolder(folder: Instance)
	for _, desc in ipairs(folder:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == "NoShoot" then
			assignNoShoot(desc)
		end
	end
end

local exZones = Workspace:FindFirstChild("ExclusionZones")
if exZones then
	scanFolder(exZones)

	exZones.DescendantAdded:Connect(function(child)
		if child:IsA("BasePart") and child.Name == "NoShoot" then
			assignNoShoot(child)
		end
	end)
end

print("[CollisionSetup] NoShoot + PlayerCharacter collision groups ready")
