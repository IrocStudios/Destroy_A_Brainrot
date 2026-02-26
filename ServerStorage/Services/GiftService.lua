--!strict
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GiftService = {}

-- ── Constants ────────────────────────────────────────────────────────────────

local DATASTORE_NAME = "DAB_PendingGifts_v1"
local MAX_PENDING    = 50   -- max pending gifts per recipient

-- ── Lifecycle ────────────────────────────────────────────────────────────────

function GiftService:Init(services)
	self.Services          = services
	self.DataService       = services.DataService
	self.NetService        = services.NetService
	self.InventoryService  = services.InventoryService
	self.EconomyService    = services.EconomyService

	self._giftStore = DataStoreService:GetDataStore(DATASTORE_NAME)

	self.RSWeaponsFolder = ReplicatedStorage:FindFirstChild("Weapons")

	print("[GiftService] Init OK")
end

function GiftService:Start()
	-- Claim pending gifts after profile is loaded
	if self.DataService and self.DataService.OnProfileLoaded then
		self.DataService.OnProfileLoaded:Connect(function(player)
			task.defer(function()
				self:ClaimPendingGifts(player)
			end)
		end)
	end

	-- Handle players already in game (edge case: service starts after some profiles loaded)
	for _, player in ipairs(Players:GetPlayers()) do
		if self.DataService:GetProfile(player) then
			task.defer(function()
				self:ClaimPendingGifts(player)
			end)
		end
	end

	print("[GiftService] Start OK")
end

-- ── Gift Item Schema ─────────────────────────────────────────────────────────
--
-- A gift item is a table with a `kind` field describing what it is.
-- Supported kinds (extensible):
--   { kind = "weapon",  weaponKey = "AK12" }
--   { kind = "cash",    amount = 500 }
--   { kind = "xp",      amount = 100 }
--
-- When stored in the pending DataStore, additional metadata is attached:
--   { kind, ..., senderName, senderUserId, sentAt }
--

-- ── Grant a single gift item to a player ─────────────────────────────────────

function GiftService:GrantGiftItem(player: Player, item: any): (boolean, string?)
	if type(item) ~= "table" or type(item.kind) ~= "string" then
		return false, "InvalidItem"
	end

	local kind = item.kind

	if kind == "weapon" then
		local weaponKey = item.weaponKey
		if type(weaponKey) ~= "string" or weaponKey == "" then
			return false, "MissingWeaponKey"
		end
		if self.InventoryService then
			self.InventoryService:GrantTool(player, weaponKey)
			return true, nil
		end
		return false, "NoInventoryService"

	elseif kind == "cash" then
		local amount = tonumber(item.amount) or 0
		if amount <= 0 then return false, "InvalidAmount" end
		if self.EconomyService then
			self.EconomyService:AddCash(player, amount, "Gift")
			return true, nil
		end
		return false, "NoEconomyService"

	elseif kind == "xp" then
		local amount = tonumber(item.amount) or 0
		if amount <= 0 then return false, "InvalidAmount" end
		local progService = self.Services.ProgressionService
		if progService and type(progService.AddXP) == "function" then
			progService:AddXP(player, amount, "Gift")
			return true, nil
		end
		return false, "NoProgressionService"
	end

	-- Unknown kind — future-proofing: log but don't crash
	warn(("[GiftService] Unknown gift kind '%s', skipping"):format(tostring(kind)))
	return false, "UnknownKind"
end

-- ── Validate a gift item before sending ──────────────────────────────────────

function GiftService:_validateGiftItem(sender: Player, item: any): (boolean, string?)
	if type(item) ~= "table" or type(item.kind) ~= "string" then
		return false, "InvalidItem"
	end

	local kind = item.kind

	if kind == "weapon" then
		local weaponKey = item.weaponKey
		if type(weaponKey) ~= "string" or weaponKey == "" then
			return false, "MissingWeaponKey"
		end
		-- Validate weapon exists in RS.Weapons
		if not self.RSWeaponsFolder or not self.RSWeaponsFolder:FindFirstChild(weaponKey) then
			return false, "InvalidWeapon"
		end
		-- Validate sender owns it
		if not self.InventoryService:OwnsWeapon(sender, weaponKey) then
			return false, "NotOwned"
		end
		return true, nil

	elseif kind == "cash" then
		local amount = tonumber(item.amount) or 0
		if amount <= 0 then return false, "InvalidAmount" end
		-- Validate sender has enough cash
		if self.EconomyService then
			local cash = self.EconomyService:GetCash(sender)
			if cash < amount then
				return false, "InsufficientCash"
			end
		end
		return true, nil

	elseif kind == "xp" then
		-- XP gifts don't require sender to "have" XP — it's a one-way gift
		local amount = tonumber(item.amount) or 0
		if amount <= 0 then return false, "InvalidAmount" end
		return true, nil
	end

	return false, "UnknownKind"
end

-- ── Deduct from sender ───────────────────────────────────────────────────────

function GiftService:_deductFromSender(sender: Player, item: any): (boolean, string?)
	local kind = item.kind

	if kind == "weapon" then
		local removed = self.InventoryService:RemoveTool(sender, item.weaponKey)
		if not removed then
			return false, "RemoveFailed"
		end
		return true, nil

	elseif kind == "cash" then
		local ok, err = self.EconomyService:SpendCash(sender, tonumber(item.amount) or 0)
		if not ok then
			return false, err or "SpendFailed"
		end
		return true, nil

	elseif kind == "xp" then
		-- XP gifts are free to send (no deduction)
		return true, nil
	end

	return false, "UnknownKind"
end

-- ── Send Gift ────────────────────────────────────────────────────────────────

function GiftService:SendGift(sender: Player, recipientUserId: number, item: any)
	-- Validate recipient
	if type(recipientUserId) ~= "number" or recipientUserId <= 0 then
		return { ok = false, reason = "InvalidRecipient" }
	end
	-- Can't gift yourself
	if recipientUserId == sender.UserId then
		return { ok = false, reason = "CannotGiftSelf" }
	end

	-- Validate the gift item
	local valid, valErr = self:_validateGiftItem(sender, item)
	if not valid then
		return { ok = false, reason = valErr }
	end

	-- Deduct from sender first
	local deducted, dedErr = self:_deductFromSender(sender, item)
	if not deducted then
		return { ok = false, reason = dedErr }
	end

	-- Check if recipient is online in this server
	local recipient = Players:GetPlayerByUserId(recipientUserId)
	if recipient and recipient.Parent then
		-- Direct transfer
		local grantOk, grantErr = self:GrantGiftItem(recipient, item)
		if not grantOk then
			-- Rollback: re-grant to sender
			warn(("[GiftService] Direct grant failed (%s), rolling back"):format(tostring(grantErr)))
			self:GrantGiftItem(sender, item)
			return { ok = false, reason = "GrantFailed" }
		end

		-- Notify both
		if self.NetService then
			self.NetService:Notify(recipient, {
				type         = "giftReceived",
				kind         = item.kind,
				senderName   = sender.Name,
				senderUserId = sender.UserId,
				item         = item,
			})
			self.NetService:Notify(sender, {
				type            = "giftSent",
				kind            = item.kind,
				recipientName   = recipient.Name,
				recipientUserId = recipientUserId,
				item            = item,
			})
		end

		print(("[GiftService] %s gifted %s (%s) to %s (online)"):format(
			sender.Name, item.kind, tostring(item.weaponKey or item.amount or ""), recipient.Name))

		return { ok = true, delivered = true }
	end

	-- Recipient is offline — save to pending DataStore
	local giftData = {
		kind         = item.kind,
		weaponKey    = item.weaponKey,
		amount       = item.amount,
		senderName   = sender.Name,
		senderUserId = sender.UserId,
		sentAt       = os.time(),
	}

	local saveOk, saveErr = self:_savePendingGift(recipientUserId, giftData)
	if not saveOk then
		-- Rollback: re-grant to sender
		warn(("[GiftService] DataStore save failed (%s), rolling back"):format(tostring(saveErr)))
		self:GrantGiftItem(sender, item)
		return { ok = false, reason = saveErr }
	end

	-- Notify sender
	if self.NetService then
		self.NetService:Notify(sender, {
			type            = "giftSent",
			kind            = item.kind,
			recipientUserId = recipientUserId,
			item            = item,
			pending         = true,
		})
	end

	print(("[GiftService] %s gifted %s (%s) to userId %d (offline, saved to pending)"):format(
		sender.Name, item.kind, tostring(item.weaponKey or item.amount or ""), recipientUserId))

	return { ok = true, delivered = false }
end

-- ── Pending Gift DataStore ───────────────────────────────────────────────────

function GiftService:_savePendingGift(recipientUserId: number, giftData: any): (boolean, string?)
	local key = "gifts_" .. tostring(recipientUserId)

	local ok, err = pcall(function()
		self._giftStore:UpdateAsync(key, function(old)
			old = old or {}
			if #old >= MAX_PENDING then
				-- Return nil to abort (don't save)
				return nil
			end
			table.insert(old, giftData)
			return old
		end)
	end)

	if not ok then
		return false, "DataStoreError: " .. tostring(err)
	end

	return true, nil
end

function GiftService:ClaimPendingGifts(player: Player)
	local key = "gifts_" .. tostring(player.UserId)
	local gifts = nil

	-- Atomic read + clear
	local ok, err = pcall(function()
		self._giftStore:UpdateAsync(key, function(old)
			if type(old) ~= "table" or #old == 0 then
				return nil -- nothing to change
			end
			gifts = old
			return {} -- clear the list
		end)
	end)

	if not ok then
		warn(("[GiftService] Failed to read pending gifts for %s: %s"):format(player.Name, tostring(err)))
		return
	end

	if not gifts or #gifts == 0 then
		return
	end

	print(("[GiftService] Claiming %d pending gift(s) for %s"):format(#gifts, player.Name))

	for _, gift in ipairs(gifts) do
		local grantOk, grantErr = self:GrantGiftItem(player, gift)
		if grantOk then
			-- Notify the player
			if self.NetService then
				self.NetService:Notify(player, {
					type         = "giftReceived",
					kind         = gift.kind,
					senderName   = gift.senderName or "Unknown",
					senderUserId = gift.senderUserId,
					item         = gift,
				})
			end
			print(("[GiftService]   Granted: %s (%s) from %s"):format(
				tostring(gift.kind), tostring(gift.weaponKey or gift.amount or ""), tostring(gift.senderName)))
		else
			warn(("[GiftService]   Failed to grant pending gift: %s (%s)"):format(
				tostring(gift.kind), tostring(grantErr)))
		end
	end
end

function GiftService:GetPendingGifts(userId: number): any
	local key = "gifts_" .. tostring(userId)
	local result = nil

	local ok, err = pcall(function()
		result = self._giftStore:GetAsync(key)
	end)

	if not ok then
		warn(("[GiftService] Failed to read pending gifts for %d: %s"):format(userId, tostring(err)))
		return nil
	end

	return result or {}
end

-- ── Remote Handler ───────────────────────────────────────────────────────────

function GiftService:HandleGiftAction(player: Player, payload: any)
	if type(payload) ~= "table" then
		return { ok = false, reason = "BadPayload" }
	end

	local action = tostring(payload.action or "")

	if action == "send" then
		local recipientUserId = tonumber(payload.recipientUserId)
		if not recipientUserId then
			return { ok = false, reason = "MissingRecipient" }
		end

		-- Build the gift item from payload
		local item = payload.item
		if type(item) ~= "table" then
			return { ok = false, reason = "MissingItem" }
		end

		return self:SendGift(player, recipientUserId, item)

	elseif action == "getPending" then
		local gifts = self:GetPendingGifts(player.UserId)
		return { ok = true, gifts = gifts }
	end

	return { ok = false, reason = "UnknownAction" }
end

return GiftService
