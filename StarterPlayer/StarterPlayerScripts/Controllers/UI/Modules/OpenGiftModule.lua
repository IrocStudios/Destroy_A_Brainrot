--!strict
-- OpenGiftModule.lua  |  Frame: OpenGift
-- "You received a gift!" prompt with Open / Keep buttons.
-- Triggered by:
--   1. Server Notify event with type = "giftReceived"  (daily, friend, etc.)
--   2. Programmatic call: OpenGiftModule:Prompt(giftObj)  (from inventory click)
-- Queues if another prompt is already showing.
--
-- On "Open": fires server OpenGift → receives reward → plays HatchSequence.
-- On "Keep": fires server KeepGift → gift stays in inventory.
--
-- WIRE-UP (Studio frame hierarchy):
--   OpenGift [Frame]
--     ├─ Canvas [CanvasGroup]  → header "Gift!"
--     ├─ XButton [TextButton]  → close = Keep
--     ├─ UIScale [UIScale]     → Router bounce
--     └─ Frame [Frame]         → content area
--        ├─ Frame [Frame]
--        │   └─ giftimage [ImageLabel]  → sway animation + gift icon
--        ├─ Title [TextLabel]   → gift display name
--        └─ Options [Frame]
--            ├─ Yes [TextButton]  → "Open"
--            └─ No  [TextButton]  → "Keep"

local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OpenGiftModule = {}
OpenGiftModule.__index = OpenGiftModule

-- ── Config ──────────────────────────────────────────────────────────────────

local SWAY_ANGLE    = 8      -- degrees each direction
local SWAY_DURATION = 1.8    -- seconds for one full left→right→left cycle

-- Gift asset folder: ReplicatedStorage.ShopAssets.Gifts.[giftKey]
local function getGiftAsset(giftKey: string): Folder?
	local ok, result = pcall(function()
		return ReplicatedStorage:FindFirstChild("ShopAssets")
			and ReplicatedStorage.ShopAssets:FindFirstChild("Gifts")
			and ReplicatedStorage.ShopAssets.Gifts:FindFirstChild(giftKey)
	end)
	return ok and result or nil
end

local function find(parent: Instance, name: string): Instance?
	return parent:FindFirstChild(name, true)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function OpenGiftModule:Init(ctx: any)
	self._ctx     = ctx
	self._janitor = ctx.UI.Cleaner.new()
	self._frame   = ctx.FramesFolder and ctx.FramesFolder:FindFirstChild("OpenGift")
	self._open    = false
	self._queue   = {}       -- queued gift prompts
	self._current = nil      -- currently displayed gift object { id, giftKey, source, ... }
	self._swayTween = nil :: Tween?

	if not self._frame then
		warn("[OpenGiftModule] Frame 'OpenGift' not found")
		return
	end

	-- Cache elements
	self._uiScale   = self._frame:FindFirstChildOfClass("UIScale") :: UIScale?
	self._giftImage = find(self._frame, "giftimage") :: ImageLabel?

	-- Content frame (direct child Frame that holds Title + Options)
	local contentFrame = nil
	for _, child in self._frame:GetChildren() do
		if child:IsA("Frame") and child.Name == "Frame" then
			contentFrame = child
			break
		end
	end
	self._contentFrame = contentFrame

	-- Title label inside content frame
	self._titleLbl = contentFrame and contentFrame:FindFirstChild("Title") :: TextLabel?

	-- Options
	local optionsFrame = contentFrame and contentFrame:FindFirstChild("Options")
	self._yesBtn = optionsFrame and optionsFrame:FindFirstChild("Yes") :: TextButton?
	self._noBtn  = optionsFrame and optionsFrame:FindFirstChild("No")  :: TextButton?

	-- XButton (close = Keep)
	local closeBtn = self._frame:FindFirstChild("XButton") :: TextButton?

	-- Wire buttons
	if self._yesBtn then
		self._janitor:Add((self._yesBtn :: TextButton).MouseButton1Click:Connect(function()
			self:_onOpen()
		end))
	end
	if self._noBtn then
		self._janitor:Add((self._noBtn :: TextButton).MouseButton1Click:Connect(function()
			self:_onKeep()
		end))
	end
	if closeBtn then
		self._janitor:Add((closeBtn :: TextButton).MouseButton1Click:Connect(function()
			self:_onKeep()
		end))
	end

	self._fromInventory = false

	-- Register on ctx so BackpackModule can call :Prompt()
	ctx.OpenGift = self

	self._frame.Visible = false
	print("[OpenGiftModule] Init OK")
end

function OpenGiftModule:Start()
	if not self._frame then return end

	-- Listen for server "giftReceived" notification
	local notifyRE = self._ctx.Net:GetEvent("Notify")
	self._janitor:Add(notifyRE.OnClientEvent:Connect(function(payload)
		print("[OpenGiftModule] Notify received:", type(payload), payload and payload.Type or "nil")
		if type(payload) == "table" and payload.Type == "giftReceived" then
			local data = payload.Data
			print("[OpenGiftModule] giftReceived data:", data and data.giftId or "nil", data and data.giftKey or "nil")
			if type(data) == "table" and data.giftId then
				self:Prompt({
					id          = data.giftId,
					giftKey     = data.giftKey or "Blue",
					source      = data.source or "unknown",
					displayName = data.displayName or "Gift",
				})
			end
		end
	end))

	print("[OpenGiftModule] Start OK")
end

-- ── Public API ──────────────────────────────────────────────────────────────

--- Show the Open/Keep prompt for a gift.
--- giftObj = { id = "gift_3", giftKey = "Blue", source = "daily", displayName = "Common Gift",
---            fromInventory = true? }
function OpenGiftModule:Prompt(giftObj: any)
	if self._open then
		table.insert(self._queue, giftObj)
		return
	end
	-- Track whether this prompt was opened from the backpack inventory
	self._fromInventory = (giftObj and giftObj.fromInventory == true) or false
	self:_showImmediate(giftObj)
end

-- ── Show / Hide ─────────────────────────────────────────────────────────────

function OpenGiftModule:_showImmediate(giftObj: any)
	if not self._frame then return end

	self._current = giftObj
	self._open = true

	local giftKey     = tostring(giftObj.giftKey or "Blue")
	local displayName = tostring(giftObj.displayName or "Gift")

	-- Load gift icon from ShopAssets.Gifts.[giftKey].Icon
	if self._giftImage then
		local asset = getGiftAsset(giftKey)
		if asset then
			local icon = asset:FindFirstChild("Icon") :: ImageLabel?
			if icon then
				(self._giftImage :: ImageLabel).Image = (icon :: ImageLabel).Image
			end
		end
	end

	-- Update title label with display name
	if self._titleLbl then
		(self._titleLbl :: TextLabel).Text = displayName
		-- Update the inner shadow Title too
		local inner = (self._titleLbl :: Instance):FindFirstChild("Title") :: TextLabel?
		if inner then
			inner.Text = displayName
		end
	end

	-- Open with bounce (bypass Router — we manage UIScale ourselves)
	self._frame.Visible = true
	if self._uiScale then
		(self._uiScale :: UIScale).Scale = 0
		local bounceUp = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local t1 = TweenService:Create(self._uiScale :: Instance, bounceUp, { Scale = 1.1 })
		t1.Completed:Once(function()
			local settle = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
			TweenService:Create(self._uiScale :: Instance, settle, { Scale = 1 }):Play()
		end)
		t1:Play()
	end

	-- Start sway animation on the gift image
	self:_startSway()

	-- Sound
	pcall(function() self._ctx.UI.Sound:Play("cartoon_pop") end)
end

function OpenGiftModule:_close()
	if not self._frame or not self._open then return end
	self._open = false
	self._current = nil

	self:_stopSway()

	-- Shrink out
	if self._uiScale then
		local info = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		local tw = TweenService:Create(self._uiScale :: Instance, info, { Scale = 0 })
		tw.Completed:Once(function()
			self._frame.Visible = false
			if self._uiScale then
				(self._uiScale :: UIScale).Scale = 1
			end
			-- Play next queued prompt
			self:_playNext()
		end)
		tw:Play()
	else
		self._frame.Visible = false
		self:_playNext()
	end
end

function OpenGiftModule:_playNext()
	if #self._queue == 0 then return end
	local nextGift = table.remove(self._queue, 1)
	self:_showImmediate(nextGift)
end

-- ── Button handlers ─────────────────────────────────────────────────────────

function OpenGiftModule:_onOpen()
	local gift = self._current
	if not gift or not gift.id then return end

	-- Capture gift data before close clears _current
	local giftKey     = gift.giftKey or "Blue"
	local displayName = gift.displayName or "Gift"
	local giftId      = gift.id
	local wasFromInventory = self._fromInventory

	-- Get the icon image for the hatch sequence
	local iconImage = ""
	local asset = getGiftAsset(giftKey)
	if asset then
		local icon = asset:FindFirstChild("Icon") :: ImageLabel?
		if icon then
			iconImage = (icon :: ImageLabel).Image
		end
	end

	-- Close the prompt (resets _fromInventory)
	self:_close()

	-- Fire server request → on success, play HatchSequence
	task.spawn(function()
		local rewardRF = self._ctx.Net:GetFunction("RewardAction")
		if not rewardRF then
			warn("[OpenGiftModule] No RewardAction RemoteFunction!")
			return
		end

		local result = rewardRF:InvokeServer({
			Action = "OpenGift",
			GiftId = giftId,
		})

		if type(result) == "table" and result.ok then
			-- Build gift data for hatch sequence
			local giftData = {
				giftKey     = giftKey,
				displayName = displayName,
				icon        = iconImage,
			}

			-- Build onComplete callback to reopen backpack if opened from inventory
			local onComplete = nil
			if wasFromInventory then
				onComplete = function()
					task.defer(function()
						local router = self._ctx.Router
						if router then
							router:Open("Backpack")
						end
					end)
				end
			end

			-- Play the hatch sequence with the reward result
			local hatch = self._ctx.HatchSequence
			if hatch and type(hatch.Play) == "function" then
				hatch:Play(giftData, result.result, onComplete)
			else
				print(("[OpenGiftModule] Gift opened! (no HatchSequence) Result: %s"):format(
					tostring(result.result and result.result.description or "unknown")
				))
				-- Still fire onComplete if no hatch sequence
				if onComplete then onComplete() end
			end
		else
			warn(("[OpenGiftModule] OpenGift failed: %s"):format(
				tostring(result and result.error or "unknown error")
			))
		end
	end)
end

function OpenGiftModule:_onKeep()
	local gift = self._current
	if not gift or not gift.id then
		self._fromInventory = false
		self:_close()
		return
	end

	local giftId = gift.id
	local wasFromInventory = self._fromInventory
	self._fromInventory = false

	-- Close the prompt
	self:_close()

	-- Tell server we're keeping it (gift stays in inventory)
	task.spawn(function()
		local rewardRF = self._ctx.Net:GetFunction("RewardAction")
		if not rewardRF then return end

		rewardRF:InvokeServer({
			Action = "KeepGift",
			GiftId = giftId,
		})
	end)

	-- Reopen backpack if this was opened from inventory
	if wasFromInventory then
		task.defer(function()
			local router = self._ctx.Router
			if router then router:Open("Backpack") end
		end)
	end
end

-- ── Sway Animation ──────────────────────────────────────────────────────────

function OpenGiftModule:_startSway()
	self:_stopSway()

	local img = self._giftImage
	if not img then return end

	-- Start tilted left so the reversal swings: -ANGLE → +ANGLE → -ANGLE (repeat)
	(img :: ImageLabel).Rotation = -SWAY_ANGLE

	local info = TweenInfo.new(
		SWAY_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1,         -- infinite repeats
		true        -- reverses (-ANGLE → +ANGLE → -ANGLE …)
	)
	self._swayTween = TweenService:Create(img :: Instance, info, { Rotation = SWAY_ANGLE })
	self._swayTween:Play()
end

function OpenGiftModule:_stopSway()
	if self._swayTween then
		self._swayTween:Cancel()
		self._swayTween = nil
	end
	if self._giftImage then
		(self._giftImage :: ImageLabel).Rotation = 0
	end
end

-- ── Cleanup ─────────────────────────────────────────────────────────────────

function OpenGiftModule:Destroy()
	self:_stopSway()
	if self._janitor then self._janitor:Cleanup(); self._janitor = nil end
end

return OpenGiftModule
