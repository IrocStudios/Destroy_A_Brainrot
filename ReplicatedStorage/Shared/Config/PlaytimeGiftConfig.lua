-- ReplicatedStorage/Shared/Config/PlaytimeGiftConfig.lua
-- Configurable unlock times for the 9 playtime gift slots.
-- Each slot defines the cumulative daily playtime (in seconds) required
-- before the gift can be claimed.  Gift key comes from the ObjectValue
-- in Studio, but is echoed here for server-side validation.
--
-- Times are in clean 5-minute steps.

local PlaytimeGiftConfig = {}

--------------------------------------------------------------
-- !! TEMPORARY: 10x speed for testing. Set to 1 before shipping !!
--------------------------------------------------------------
PlaytimeGiftConfig.DEV_TIME_MULTIPLIER = 10

--------------------------------------------------------------
-- Slot definitions
-- time     = seconds of daily playtime required to unlock
-- giftKey  = gift folder name in ShopAssets/Gifts (Blue/Purple/Gold)
--------------------------------------------------------------
PlaytimeGiftConfig.Slots = {
	[1] = { time = 300,  giftKey = "Blue"   },  --  5:00
	[2] = { time = 600,  giftKey = "Blue"   },  -- 10:00
	[3] = { time = 900,  giftKey = "Blue"   },  -- 15:00
	[4] = { time = 1200, giftKey = "Blue"   },  -- 20:00
	[5] = { time = 1500, giftKey = "Purple" },  -- 25:00
	[6] = { time = 1800, giftKey = "Purple" },  -- 30:00
	[7] = { time = 2400, giftKey = "Purple" },  -- 40:00
	[8] = { time = 3000, giftKey = "Gold"   },  -- 50:00
	[9] = { time = 3600, giftKey = "Gold"   },  -- 60:00
}

PlaytimeGiftConfig.SlotCount = 9

--- Get a single slot definition by 1-based index.
function PlaytimeGiftConfig.GetSlot(index: number)
	return PlaytimeGiftConfig.Slots[index]
end

return PlaytimeGiftConfig
