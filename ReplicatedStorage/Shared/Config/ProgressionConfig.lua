-- ReplicatedStorage/Shared/Config/ProgressionConfig.lua
-- Leveling, stages, and rebirth requirements/scaling. Data-only.

local ProgressionConfig = {
	Version = 1,

	MaxLevel = 120,

	-- XP curve settings.
	-- Services can compute XPRequired(level) using these parameters (no functions here).
	XPCurve = {
		-- Recommended formula (for service implementation):
		-- XPToNext = floor(Base + (level ^ Power) * Growth)
		Base = 65,
		Growth = 14.5,
		Power = 1.62,

		-- Optional overrides for specific levels (rare use; keeps balancing painless).
		-- If set, override takes precedence for that level.
		Overrides = {
			-- [1] = 60,
			-- [10] = 320,
		},
	},

	-- Stages / gates
	-- Stages are where territories unlock and difficulty scales.
	Stages = {
		-- Stage numbers are stable identifiers.
		[1] = {
			DisplayName = "Starter Zone",
			Unlock = { Level = 1, Cash = 0 },
			Difficulty = { Health = 1.00, Damage = 1.00 },
			Reward = { Value = 1.00, XP = 1.00 },
		},

		[2] = {
			DisplayName = "Scroll Plains",
			Unlock = { Level = 8, Cash = 650 },
			Difficulty = { Health = 1.10, Damage = 1.05 },
			Reward = { Value = 1.06, XP = 1.04 },
		},

		[3] = {
			DisplayName = "Viral Valley",
			Unlock = { Level = 18, Cash = 2_750 },
			Difficulty = { Health = 1.22, Damage = 1.10 },
			Reward = { Value = 1.12, XP = 1.08 },
		},

		[4] = {
			DisplayName = "Algorithm Ridge",
			Unlock = { Level = 32, Cash = 9_500 },
			Difficulty = { Health = 1.38, Damage = 1.16 },
			Reward = { Value = 1.20, XP = 1.14 },
		},

		[5] = {
			DisplayName = "Feed Abyss",
			Unlock = { Level = 52, Cash = 28_000 },
			Difficulty = { Health = 1.60, Damage = 1.24 },
			Reward = { Value = 1.30, XP = 1.22 },
		},

		[6] = {
			DisplayName = "Myth Loop",
			Unlock = { Level = 74, Cash = 72_000 },
			Difficulty = { Health = 1.90, Damage = 1.34 },
			Reward = { Value = 1.45, XP = 1.32 },
		},

		[7] = {
			DisplayName = "Echo Citadel",
			Unlock = { Level = 92, Cash = 155_000 },
			Difficulty = { Health = 2.20, Damage = 1.46 },
			Reward = { Value = 1.60, XP = 1.42 },
		},

		[8] = {
			DisplayName = "Terminal Trend",
			Unlock = { Level = 110, Cash = 320_000 },
			Difficulty = { Health = 2.55, Damage = 1.60 },
			Reward = { Value = 1.80, XP = 1.55 },
		},
	},

	-- Rebirth system
	Rebirth = {
		-- nil means infinite rebirths allowed
		MaxRebirths = nil,

		-- Minimum requirements
		Requirement = {
			MinLevel = 60,
			MinStage = 5,
			-- Optional cost in cash (if your system uses it)
			CashCost = 50_000,
		},

		-- What resets on rebirth is controlled by services;
		-- these are the balancing knobs for what rebirth grants.
		Scaling = {
			-- Interpreted as multiplicative bonuses or additive bonuses depending on service design.
			-- Recommended: base multiplier = 1 + (Rebirths * CashMultiplierPerRebirth)
			CashMultiplierPerRebirth = 0.12,
			XPMultiplierPerRebirth = 0.08,

			-- Optional: Stage boost (if your game wants faster re-unlock)
			-- Example: start at stage 1 always; this can reduce unlock costs in UI.
			StageUnlockCostMultiplierPerRebirth = -0.04, -- each rebirth reduces stage cash requirements by 4% (clamp in service)
		},

		-- Optional clamps to keep things sane
		Clamps = {
			MinStageUnlockCostMultiplier = 0.55,
			MaxCashMultiplier = 6.00,
			MaxXPMultiplier = 5.00,
		},
	},
}

return ProgressionConfig