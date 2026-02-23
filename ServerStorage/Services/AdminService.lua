--!strict
-- AdminService.lua
-- Server-side handler for in-game admin / developer commands.
-- Commands arrive via CommandAction RemoteFunction from CommandModule (client).
--
-- ADD YOUR ROBLOX USER ID to ADMIN_IDS to grant admin access.
-- Commands are intentionally safe (no destructive rollback; no delete-all).
--
-- Supported commands (all case-insensitive):
--   give cash <amount>                     Give self cash
--   give xp <amount>                       Give self XP
--   give [player] cash <amount>            Give named player cash
--   give [player] xp <amount>             Give named player XP
--   set level <value>                      Set self level
--   set stage <value>                      Set self stage
--   set speed <value>                      Set self walkspeed (via Humanoid)
--   set [player] level <value>             Set named player level
--   set [player] stage <value>             Set named player stage
--   reload data                            Resend full snapshot to self
--   reload data [player]                   Resend snapshot to named player
--   brainrots kill                         Kill all active brainrots (calls BrainrotService)
--   spawn <brainrotId>                     Spawn a brainrot near self
--   tp <stageName|stageNumber>             Teleport self to stage gate
--   notify <message>                       Fire a test notification to self
--   list players                           List all players and their UserId

local Players = game:GetService("Players")

local AdminService = {}
AdminService.__index = AdminService

-- ── Auth ──────────────────────────────────────────────────────────────────────
-- Add the Roblox UserIds of admins here. 0 = any player can use (DEV/TEST ONLY).
local ADMIN_IDS: { [number]: boolean } = {
	-- [12345678] = true,   -- Your UserId here
}
local DEV_MODE = true   -- true = all players are admin (disable for production!)

local function isAdmin(player: Player): boolean
	if DEV_MODE then return true end
	return ADMIN_IDS[player.UserId] == true
end

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function findPlayer(name: string): Player?
	local lower = name:lower()
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Name:lower():find(lower, 1, true) then
			return p
		end
	end
	return nil
end

local function ok(msg: string)   return { ok = true,  output = msg } end
local function err(msg: string)  return { ok = false, output = msg } end

-- Tokenises a command string into lowercase words
local function tokenise(raw: string): { string }
	local tokens: { string } = {}
	for word in raw:gmatch("[^%s]+") do
		table.insert(tokens, word:lower())
	end
	return tokens
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────
function AdminService:Init(services)
	self.Services = services
end

function AdminService:Start() end

-- ── Main entry-point ─────────────────────────────────────────────────────────
function AdminService:HandleCommand(player: Player, payload: any)
	if not isAdmin(player) then
		return err("Permission denied.")
	end

	if type(payload) ~= "table" then return err("Bad payload.") end
	local raw: string = tostring(payload.command or ""):match("^%s*(.-)%s*$")
	if #raw == 0 then return err("Empty command.") end

	local tokens = tokenise(raw)
	local cmd    = tokens[1] or ""

	-- Route to handler
	if cmd == "give" then
		return self:_cmdGive(player, tokens)
	elseif cmd == "set" then
		return self:_cmdSet(player, tokens)
	elseif cmd == "reload" then
		return self:_cmdReload(player, tokens)
	elseif cmd == "brainrots" then
		return self:_cmdBrainrots(player, tokens)
	elseif cmd == "spawn" then
		return self:_cmdSpawn(player, tokens)
	elseif cmd == "tp" or cmd == "teleport" then
		return self:_cmdTeleport(player, tokens)
	elseif cmd == "notify" then
		return self:_cmdNotify(player, tokens)
	elseif cmd == "list" then
		return self:_cmdList(player, tokens)
	elseif cmd == "help" then
		return self:_cmdHelp()
	else
		return err(("Unknown command '%s'. Type 'help' for a list."):format(cmd))
	end
end

-- ── give ─────────────────────────────────────────────────────────────────────
-- give cash <amount>
-- give xp <amount>
-- give <player> cash <amount>
-- give <player> xp <amount>
function AdminService:_cmdGive(caller: Player, t: { string })
	local DataService = self.Services.DataService
	local NetService  = self.Services.NetService
	if not DataService or not NetService then return err("DataService/NetService unavailable.") end

	-- Determine target player and resource
	-- Patterns: give cash 500 | give xp 500 | give PlayerName cash 500
	local target: Player = caller
	local resource: string
	local amount: number

	if t[2] == "cash" or t[2] == "xp" then
		-- give <resource> <amount>
		resource = t[2]
		amount   = tonumber(t[3] or "") or 0
	elseif t[3] == "cash" or t[3] == "xp" then
		-- give <player> <resource> <amount>
		local found = findPlayer(t[2] or "")
		if not found then return err(("Player '%s' not found."):format(t[2] or "?")) end
		target   = found
		resource = t[3]
		amount   = tonumber(t[4] or "") or 0
	else
		return err("Usage: give [player] cash|xp <amount>")
	end

	if amount <= 0 then return err("Amount must be > 0.") end

	local profile = DataService:GetProfile(target)
	if not profile then return err(("Profile not loaded for %s."):format(target.Name)) end

	if resource == "cash" then
		profile.Currency = profile.Currency or {}
		profile.Currency.Cash = (profile.Currency.Cash or 0) + amount
		NetService:QueueDelta(target, "Cash", profile.Currency.Cash)
		NetService:FlushDelta(target)
		return ok(("Gave %d cash to %s. New total: %d"):format(amount, target.Name, profile.Currency.Cash))

	elseif resource == "xp" then
		profile.Progression = profile.Progression or {}
		profile.Progression.XP = (profile.Progression.XP or 0) + amount
		NetService:QueueDelta(target, "XP", profile.Progression.XP)
		NetService:FlushDelta(target)
		return ok(("Gave %d XP to %s. New total: %d"):format(amount, target.Name, profile.Progression.XP))
	end

	return err("Unknown resource.")
end

-- ── set ──────────────────────────────────────────────────────────────────────
-- set level <n> | set stage <n> | set speed <n>
-- set <player> level <n> | set <player> stage <n>
function AdminService:_cmdSet(caller: Player, t: { string })
	local DataService = self.Services.DataService
	local NetService  = self.Services.NetService
	if not DataService then return err("DataService unavailable.") end

	local target: Player = caller
	local field: string
	local value: number

	-- set speed is special (no save)
	if t[2] == "speed" then
		value = tonumber(t[3] or "") or 0
		local char = caller.Character
		local hum  = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return err("Humanoid not found.") end
		hum.WalkSpeed = math.clamp(value, 1, 500)
		return ok(("Set your WalkSpeed to %d."):format(hum.WalkSpeed))
	end

	if t[2] == "level" or t[2] == "stage" then
		field = t[2]; value = tonumber(t[3] or "") or 0
	elseif t[3] == "level" or t[3] == "stage" then
		local found = findPlayer(t[2] or "")
		if not found then return err(("Player '%s' not found."):format(t[2] or "?")) end
		target = found; field = t[3]; value = tonumber(t[4] or "") or 0
	else
		return err("Usage: set [player] level|stage|speed <value>")
	end

	if value < 0 then return err("Value must be >= 0.") end

	local profile = DataService:GetProfile(target)
	if not profile then return err(("Profile not loaded for %s."):format(target.Name)) end

	profile.Progression = profile.Progression or {}

	if field == "level" then
		profile.Progression.Level = value
		if NetService then NetService:QueueDelta(target, "Level", value); NetService:FlushDelta(target) end
		return ok(("Set %s's Level to %d."):format(target.Name, value))

	elseif field == "stage" then
		profile.Progression.StageUnlocked = value
		if NetService then NetService:QueueDelta(target, "StageUnlocked", value); NetService:FlushDelta(target) end
		return ok(("Set %s's StageUnlocked to %d."):format(target.Name, value))
	end

	return err("Unknown field.")
end

-- ── reload ────────────────────────────────────────────────────────────────────
-- reload data [player]
function AdminService:_cmdReload(caller: Player, t: { string })
	local NetService = self.Services.NetService
	if not NetService then return err("NetService unavailable.") end

	local target: Player = caller
	if t[3] then
		local found = findPlayer(t[3])
		if not found then return err(("Player '%s' not found."):format(t[3])) end
		target = found
	end

	NetService:BuildAndSendSnapshot(target)
	return ok(("Snapshot sent to %s."):format(target.Name))
end

-- ── brainrots ─────────────────────────────────────────────────────────────────
-- brainrots kill
function AdminService:_cmdBrainrots(caller: Player, t: { string })
	local sub = t[2] or ""
	if sub == "kill" then
		local BrainrotService = self.Services.BrainrotService
		if BrainrotService and type(BrainrotService.KillAll) == "function" then
			BrainrotService:KillAll()
			return ok("All active brainrots killed.")
		end
		return err("BrainrotService.KillAll not available.")
	end
	return err("Usage: brainrots kill")
end

-- ── spawn ─────────────────────────────────────────────────────────────────────
-- spawn <brainrotId>
function AdminService:_cmdSpawn(caller: Player, t: { string })
	local brainrotId = t[2]
	if not brainrotId then return err("Usage: spawn <brainrotId>") end

	local BrainrotService = self.Services.BrainrotService
	if not BrainrotService or type(BrainrotService.SpawnAt) ~= "function" then
		return err("BrainrotService.SpawnAt not available.")
	end

	local char = caller.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return err("HumanoidRootPart not found.") end

	local spawnPos = root.Position + Vector3.new(0, 0, -8)
	local success, msg = BrainrotService:SpawnAt(brainrotId, CFrame.new(spawnPos))
	if success then
		return ok(("Spawned '%s' near you."):format(brainrotId))
	else
		return err(("Failed to spawn '%s': %s"):format(brainrotId, tostring(msg)))
	end
end

-- ── teleport ──────────────────────────────────────────────────────────────────
-- tp <stage number or part name>
function AdminService:_cmdTeleport(caller: Player, t: { string })
	local dest = t[2]
	if not dest then return err("Usage: tp <stage|partName>") end

	local workspace = game:GetService("Workspace")
	-- Try by stage number first (look for a Gate or SpawnPoint named "Stage<N>")
	local stageNum = tonumber(dest)
	local target: BasePart?
	if stageNum then
		for _, name in ipairs({ "Stage" .. dest, "Gate" .. dest, "SpawnPoint" .. dest }) do
			local part = workspace:FindFirstChild(name, true) :: BasePart?
			if part and part:IsA("BasePart") then target = part; break end
		end
	else
		target = workspace:FindFirstChild(dest, true) :: BasePart?
	end

	if not target or not target:IsA("BasePart") then
		return err(("No part named '%s' found in Workspace."):format(dest))
	end

	local char = caller.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return err("HumanoidRootPart not found.") end

	root.CFrame = target.CFrame + Vector3.new(0, 5, 0)
	return ok(("Teleported to '%s'."):format(target.Name))
end

-- ── notify ────────────────────────────────────────────────────────────────────
-- notify <message text>
function AdminService:_cmdNotify(caller: Player, t: { string })
	local NetService = self.Services.NetService
	if not NetService then return err("NetService unavailable.") end

	local parts: { string } = {}
	for i = 2, #t do table.insert(parts, t[i]) end
	local message = table.concat(parts, " ")
	if #message == 0 then return err("Usage: notify <message>") end

	NetService:Notify(caller, { type = "alert", title = "Admin", message = message })
	return ok(("Notification sent: %s"):format(message))
end

-- ── list ──────────────────────────────────────────────────────────────────────
-- list players
function AdminService:_cmdList(_caller: Player, _t: { string })
	local lines: { string } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(lines, ("%s (UserId: %d)"):format(p.Name, p.UserId))
	end
	return ok(table.concat(lines, "\n"))
end

-- ── help ──────────────────────────────────────────────────────────────────────
function AdminService:_cmdHelp()
	local help = [[
Available Commands:
  give [player] cash <n>      Give cash
  give [player] xp <n>        Give XP
  set [player] level <n>      Set level
  set [player] stage <n>      Set stage
  set speed <n>               Set your walkspeed
  reload data [player]        Resend full snapshot
  brainrots kill              Kill all active brainrots
  spawn <id>                  Spawn brainrot near you
  tp <stage|name>             Teleport to stage/part
  notify <message>            Send yourself a notification
  list players                List all online players
  help                        Show this help]]
	return { ok = true, output = help }
end

return AdminService
