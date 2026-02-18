--[[
	MarketConfig Shared Module

	Centralizes market configuration, sectors, and volatility settings.
]]

local MarketConfig = {}

MarketConfig.CONFIG = {
	-- Timing
	READ_INTERVAL = 5,       -- seconds between MemoryStore reads
	WRITE_INTERVAL = 10,     -- seconds between buffer flushes
	LOCAL_UPDATE_INTERVAL = 20, -- fallback local update rate (Studio mode)

	-- Sharding
	NUM_SHARDS = 5,
	SHARD_EXPIRATION = 300,  -- MemoryStore key TTL (5 minutes)

	-- Pricing
	MIN_RATE = 0.3,
	MAX_RATE = 4.0,
	STARTING_RATE = 1.0,
	BAILOUT_FLOOR = 0.8,     -- Minimum rate for welfare-protected players
	IMPACT_FACTOR = 0.00005, -- How much each sold unit depresses price
	RECOVERY_RATE = 0.005,    -- Natural price recovery per read cycle

	-- Synthetic Volatility (keeps market alive at low player count)
	JITTER_SPEED = 0.3,      -- Perlin noise time multiplier (lower = slower waves)
	JITTER_AMPLITUDE = 0.12, -- ±12% micro-fluctuation
	TREND_PERIOD = 120,      -- seconds per synthetic trend cycle (2 minutes)
	TREND_DAMPING = 0.05,    -- Smoothing factor (per second). Higher = faster reaction.
	HYPE_CHANCE = 0.20,      -- 20% chance of a bull run per cycle
	HYPE_MULTIPLIER = 2.3,   -- Bull run rate multiplier
	CRASH_CHANCE = 0.15,     -- 15% chance of a bear run (crash)
	CRASH_MULTIPLIER = 0.4,  -- Price drops to 40%
	TREND_MIN = 0.6,         -- Normal drift minimum
	TREND_MAX = 1.7,         -- Normal drift maximum
	DEAD_MARKET_THRESHOLD = 1000, -- Volume below this triggers ghost trading

	-- Fallback (old random pricing for Studio)
	BASE_VOLATILITY = 0.25,
	SPIKE_CHANCE = 0.10,
	SPIKE_MULTIPLIER = 2.5,
	MEAN_REVERSION = 0.05,

	-- History
	MAX_HISTORY = 60,
}

MarketConfig.SECTOR_VOLATILITY = {
	Food = 0.20, Animals = 0.25, Entertainment = 0.30,
	Mystic = 0.40, Tech = 0.35, Action = 0.45,
}

MarketConfig.SECTORS = {"Food", "Animals", "Entertainment", "Mystic", "Tech", "Action"}

MarketConfig.SECTOR_COLORS = {
	Food = {227, 119, 194}, Animals = {44, 160, 44}, Entertainment = {255, 127, 14},
	Mystic = {148, 103, 189}, Tech = {31, 119, 180}, Action = {214, 39, 40},
}

return MarketConfig
