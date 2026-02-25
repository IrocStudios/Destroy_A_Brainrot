-- ReplicatedStorage/Shared/Net/NetIds
local NetIds = {}

NetIds.RemoteEvents = {
	StateDelta      = "StateDelta",
	Prompt          = "Prompt",
	Notify          = "Notify",
	WeaponFX        = "WeaponFX",
	AnimationSignal = "AnimationSignal",
	MoneySpawn      = "MoneySpawn",
}

NetIds.RemoteFunctions = {
	GetStateSnapshot = "GetStateSnapshot",

	ShopAction      = "ShopAction",
	GateAction      = "GateAction",
	RewardAction    = "RewardAction",
	RebirthAction   = "RebirthAction",
	WeaponAction    = "WeaponAction",

	MoneyCollect    = "MoneyCollect",
	DamageBrainrot  = "DamageBrainrot",
	DiscoveryReport = "DiscoveryReport",

	-- Added: codes, settings persistence, admin commands
	CodesAction     = "CodesAction",
	SettingsAction  = "SettingsAction",
	CommandAction   = "CommandAction",
	DeathAction     = "DeathAction",
}



NetIds.Encode = {
	Cash = 1,
	XP = 2,
	Level = 3,
	StageUnlocked = 4,
	Rebirths = 5,

	WeaponsOwned = 10,
	EquippedWeapon = 11,

	BrainrotsKilled = 20,
	BrainrotsDiscovered = 21,

	DailyLastClaim = 30,
	DailyStreak = 31,
	GiftCooldowns = 32,

	MusicOn = 40,
	SFXOn = 41,

	-- Stats (lifetime counters)
	TotalKills = 50,
	TotalCashEarned = 51,
	Deaths = 52,
}

NetIds.Decode = {}
for k, v in pairs(NetIds.Encode) do
	NetIds.Decode[v] = k
end


return NetIds
