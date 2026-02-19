--[[
	MarketVolatilityService Server Module

	Handles synthetic volatility for the stock market, including:
	- Perlin noise jitter
	- Synthetic trend generation (Bull/Bear runs)
	- Smooth trend application
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MarketConfig = require(Shared:WaitForChild("MarketConfig"))
local CONFIG = MarketConfig.CONFIG

local MarketVolatilityService = {}

-- State
local sectorTrends = {} -- { [sector] = currentSmoothedTrend }

-- Generate a unique numeric seed from a sector name
local function getSectorSeed(sectorName: string): number
	local seed = 0
	for i = 1, #sectorName do
		seed = seed + string.byte(sectorName, i) * i
	end
	return seed
end

--[[
	Perlin Noise Jitter: smooth ±5% micro-fluctuations.
	Uses math.noise for natural-looking waves instead of jagged random spikes.
	Each sector has a unique seed so they don't move in lockstep.
]]
local function getJitter(sectorName: string): number
	local seed = getSectorSeed(sectorName)
	-- FIX: Synchronized global time (workspace:GetServerTimeNow() is synced via NTP)
	local globalTime = workspace:GetServerTimeNow() 
	local timeOffset = globalTime * CONFIG.JITTER_SPEED
	local noise = math.noise(timeOffset, seed * 0.1, 0) -- Returns -0.5 to 0.5
	return 1 + (noise * CONFIG.JITTER_AMPLITUDE)
end

--[[
	Synthetic Trend ("Market Maker Bot"): deterministic wave shared by all servers.
	Every TREND_PERIOD seconds, each sector gets a new trend direction.
	20% chance of a BULL RUN (1.4x), otherwise normal drift (0.9-1.1x).
	Deterministic via timeKey + seed so all servers agree.
]]
local function getSyntheticTrend(sectorName: string): number
	local seed = getSectorSeed(sectorName)
	local globalTime = workspace:GetServerTimeNow()
	
	-- FIX: Add the seed to the time so sectors drift independently
	local timeKey = math.floor((globalTime + seed) / CONFIG.TREND_PERIOD)
	
	local rng = Random.new(timeKey)

	local roll = rng:NextNumber()

	if roll < CONFIG.HYPE_CHANCE then
		return CONFIG.HYPE_MULTIPLIER -- BULL RUN! (Stonks)
	elseif roll < (CONFIG.HYPE_CHANCE + CONFIG.CRASH_CHANCE) then
		return CONFIG.CRASH_MULTIPLIER -- BEAR RUN! (Crash)
	else
		return rng:NextNumber(CONFIG.TREND_MIN, CONFIG.TREND_MAX) -- Normal drift
	end
end

-- Initialize service state
function MarketVolatilityService.Init()
	for _, sector in ipairs(MarketConfig.SECTORS) do
		sectorTrends[sector] = 1.0
	end
end

--[[
	Calculates the volatility multiplier for a given sector.
	Updates the internal trend state.

	@param sector string - The market sector
	@param dt number - Time delta for smoothing (usually READ_INTERVAL or LOCAL_UPDATE_INTERVAL)
	@return number - The volatility multiplier (trend * jitter)
]]
function MarketVolatilityService.CalculateVolatility(sector: string, dt: number)
	local alpha = math.clamp(CONFIG.TREND_DAMPING * dt, 0, 1)

	local targetTrend = getSyntheticTrend(sector)
	local currentTrend = sectorTrends[sector] or 1.0

	-- Smoothly move current trend towards target
	local smoothedTrend = currentTrend + (targetTrend - currentTrend) * alpha
	sectorTrends[sector] = smoothedTrend

	-- Apply jitter
	local jitter = getJitter(sector)

	return smoothedTrend, jitter
end

function MarketVolatilityService.GetSmoothedTrend(sector: string)
	return sectorTrends[sector] or 1.0
end

return MarketVolatilityService
