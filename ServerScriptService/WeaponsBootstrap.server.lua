--!strict
-- WeaponsBootstrap.server.lua
-- Standalone bootstrapper for the WeaponsSystem.
-- Initializes weapon assets, runs WeaponsSystem.setup(), and distributes
-- the ClientWeaponsScript to every player's PlayerGui.
--
-- This replaces the per-tool ServerWeaponsScript copies that previously
-- lived inside each weapon's WeaponsSystemIGNORE folder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for the canonical WeaponsSystem folder (Rojo-managed scripts + Studio-only assets)
local weaponsSystemFolder = ReplicatedStorage:WaitForChild("WeaponsSystem", 30)
if not weaponsSystemFolder then
	warn("[WeaponsBootstrap] ReplicatedStorage.WeaponsSystem not found after 30s — aborting")
	return
end

-- ── Initialize weapon effect assets ──────────────────────────────────────────
local assetsFolder = weaponsSystemFolder:FindFirstChild("Assets")
if assetsFolder then
	local effectsFolder = assetsFolder:FindFirstChild("Effects")
	if effectsFolder then
		local partNonZeroTransparencyValues = {
			["BulletHole"] = 1, ["Explosion"] = 1, ["Pellet"] = 1, ["Scorch"] = 1,
			["Bullet"] = 1, ["Plasma"] = 1, ["Railgun"] = 1,
		}
		local decalNonZeroTransparencyValues = { ["ScorchMark"] = 0.25 }
		local particleEmittersToDisable = { ["Smoke"] = true }
		local imageLabelNonZeroTransparencyValues = { ["Impact"] = 0.25 }

		for _, descendant in pairs(effectsFolder:GetDescendants()) do
			if descendant:IsA("BasePart") then
				if partNonZeroTransparencyValues[descendant.Name] ~= nil then
					descendant.Transparency = partNonZeroTransparencyValues[descendant.Name]
				else
					descendant.Transparency = 0
				end
			elseif descendant:IsA("Decal") then
				if decalNonZeroTransparencyValues[descendant.Name] ~= nil then
					descendant.Transparency = decalNonZeroTransparencyValues[descendant.Name]
				else
					descendant.Transparency = 0
				end
			elseif descendant:IsA("ParticleEmitter") then
				if particleEmittersToDisable[descendant.Name] ~= nil then
					descendant.Enabled = false
				else
					descendant.Enabled = true
				end
			elseif descendant:IsA("ImageLabel") then
				if imageLabelNonZeroTransparencyValues[descendant.Name] ~= nil then
					descendant.ImageTransparency = imageLabelNonZeroTransparencyValues[descendant.Name]
				else
					descendant.ImageTransparency = 0
				end
			end
		end
	end
end

-- ── Run server-side WeaponsSystem setup ──────────────────────────────────────
local WeaponsSystem = require(weaponsSystemFolder:WaitForChild("WeaponsSystem"))
if not WeaponsSystem.doingSetup and not WeaponsSystem.didSetup then
	WeaponsSystem.setup()
end

-- ── Distribute ClientWeaponsScript to every player ───────────────────────────
local clientScriptTemplate = weaponsSystemFolder:FindFirstChild("ClientWeaponsScript")
if not clientScriptTemplate then
	warn("[WeaponsBootstrap] ClientWeaponsScript not found in WeaponsSystem folder")
	return
end

local function setupClientWeaponsScript(player: Player)
	-- Wait for PlayerGui to exist
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		playerGui = player:WaitForChild("PlayerGui", 15)
	end
	if not playerGui then return end

	if playerGui:FindFirstChild("ClientWeaponsScript") then return end
	local clone = clientScriptTemplate:Clone()
	clone.Parent = playerGui
end

Players.PlayerAdded:Connect(setupClientWeaponsScript)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupClientWeaponsScript, player)
end

print("[WeaponsBootstrap] WeaponsSystem initialized OK")
