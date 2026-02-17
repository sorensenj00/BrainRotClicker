--[[
	StockMarketManager Server Module
	
	═══════════════════════════════════════════════════════════════════════════════
	              GLOBAL SHARDED MARKET WITH WELFARE
	═══════════════════════════════════════════════════════════════════════════════
	
	PURPOSE:
	  Replaces the old random-local sector pricing with a player-driven global
	  market. Prices are derived from REAL cross-server sales volume stored in
	  MemoryStoreService. All servers read a sharded volume dataset and compute
	  synchronized rates.
	
	ARCHITECTURE:
	  • READ LOOP  (every 5s)  — Read 5 MemoryStore shards, sum volumes, compute
	    MarketRate + BailoutRate per sector, replicate via attributes.
	  • WRITE LOOP (every 10s) — Flush this server's buffered sales volume into
	    one random shard to avoid key-lock contention.
	  • FALLBACK — If MemoryStore fails (Studio / offline), gracefully degrade to
	    the old random local pricing so gameplay isn't blocked.
	
	═══════════════════════════════════════════════════════════════════════════════
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
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

local SECTOR_VOLATILITY = {
	Food = 0.20, Animals = 0.25, Entertainment = 0.30,
	Mystic = 0.40, Tech = 0.35, Action = 0.45,
}
local SECTORS = {"Food", "Animals", "Entertainment", "Mystic", "Tech", "Action"}
local SECTOR_COLORS = {
	Food = {227, 119, 194}, Animals = {44, 160, 44}, Entertainment = {255, 127, 14},
	Mystic = {148, 103, 189}, Tech = {31, 119, 180}, Action = {214, 39, 40},
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local StockMarketManager = {}
local Services = {}

local sectorRates = {}        -- { [sector] = currentMarketRate }
local bailoutRates = {}       -- { [sector] = bailoutRate }
local sectorHistories = {}
local sectorTrends = {}       -- { [sector] = currentSmoothedTrend }
local stockMarketFolder = nil

-- MemoryStore state
local GlobalMarketMap = nil       -- MemoryStoreService sorted map
local ServerSalesBuffer = {}      -- { [sector] = volumeToFlush }
local useGlobalPricing = false    -- true once MemoryStore is confirmed working
local nextReadTime = 0
local nextWriteTime = 0
local nextLocalUpdate = 0

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function serializeHistory(history)
	local parts = {}
	for _, rate in ipairs(history) do table.insert(parts, string.format("%.3f", rate)) end
	return table.concat(parts, ",")
end

local function serializeSectorRates()
	local t = {}
	for c, r in pairs(sectorRates) do t[c] = math.floor(r * 1000) / 1000 end
	return HttpService:JSONEncode(t)
end

local function serializeSectorHistories()
	local t = {}
	for c, h in pairs(sectorHistories) do t[c] = serializeHistory(h) end
	return HttpService:JSONEncode(t)
end

local function getGlobalRateName()
	local sum = 0; for _, r in pairs(sectorRates) do sum += r end
	local avg = sum / #SECTORS
	if avg >= 2.5 then return "HYPER INFLATION"
	elseif avg >= 1.5 then return "STONKS"
	elseif avg <= 0.7 then return "CRASH"
	else return "NORMAL" end
end

-- Fallback random pricing (same as old logic, used in Studio)
local function calculateLocalRate(sector)
	local current = sectorRates[sector]
	local vol = SECTOR_VOLATILITY[sector] or CONFIG.BASE_VOLATILITY
	local base = (math.random() - 0.5) * 2 * vol
	if math.random() < CONFIG.SPIKE_CHANCE then base *= CONFIG.SPIKE_MULTIPLIER end
	local rev = (CONFIG.STARTING_RATE - current) * CONFIG.MEAN_REVERSION
	return math.clamp(current + base + rev, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
end

--------------------------------------------------------------------------------
-- SYNTHETIC VOLATILITY
--------------------------------------------------------------------------------

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
	local timeOffset = os.clock() * CONFIG.JITTER_SPEED
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
	local timeKey = math.floor(os.time() / CONFIG.TREND_PERIOD)
	local seed = getSectorSeed(sectorName)
	local rng = Random.new(timeKey + seed)
	
	local roll = rng:NextNumber()
	
	if roll < CONFIG.HYPE_CHANCE then
		return CONFIG.HYPE_MULTIPLIER -- BULL RUN! (Stonks)
	elseif roll < (CONFIG.HYPE_CHANCE + CONFIG.CRASH_CHANCE) then
		return CONFIG.CRASH_MULTIPLIER -- BEAR RUN! (Crash)
	else
		return rng:NextNumber(CONFIG.TREND_MIN, CONFIG.TREND_MAX) -- Normal drift
	end
end

--------------------------------------------------------------------------------
-- MEMORYSTORE: SHARDED READER
--------------------------------------------------------------------------------

local function readGlobalVolumes(): {[string]: number}
	local totalVolumes: {[string]: number} = {}
	for _, sector in ipairs(SECTORS) do totalVolumes[sector] = 0 end
	
	for shardId = 1, CONFIG.NUM_SHARDS do
		local key = "GlobalVol_Shard_" .. shardId
		local ok, data = pcall(function()
			return GlobalMarketMap:GetAsync(key)
		end)
		if ok and data and type(data) == "table" then
			for sector, vol in pairs(data) do
				if totalVolumes[sector] then
					totalVolumes[sector] += (tonumber(vol) or 0)
				end
			end
		end
	end
	
	return totalVolumes
end

local function computeGlobalRates(totalVolumes: {[string]: number})
	local dt = CONFIG.READ_INTERVAL
	local alpha = math.clamp(CONFIG.TREND_DAMPING * dt, 0, 1)

	for _, sector in ipairs(SECTORS) do
		local vol = totalVolumes[sector] or 0
		
		-- Base rate from real player volume
		local rawRate = CONFIG.STARTING_RATE * (1 - (vol * CONFIG.IMPACT_FACTOR))
		rawRate += CONFIG.RECOVERY_RATE
		
		-- SYNTHETIC VOLATILITY: Apply Market Maker (Smoothed)
		-- We calculate trend regardless of volume, but might only apply it fully if volume is low.
		-- Ideally, the trend influences the price as a multiplier always, to keep it fun.
		local targetTrend = getSyntheticTrend(sector)
		local currentTrend = sectorTrends[sector] or 1.0
		
		-- Smoothly move current trend towards target
		local smoothedTrend = currentTrend + (targetTrend - currentTrend) * alpha
		sectorTrends[sector] = smoothedTrend
		
		if vol < CONFIG.DEAD_MARKET_THRESHOLD then
			rawRate *= smoothedTrend
		else
			-- Even if players are trading, let the trend have *some* influence (e.g. 50%)
			-- so Bear/Bull runs can fight player volume.
			rawRate *= (1 + (smoothedTrend - 1) * 0.5)
		end
		
		-- JITTER: Always-on Perlin noise micro-fluctuation
		local jitter = getJitter(sector)
		rawRate *= jitter
		
		-- Final clamp
		rawRate = math.clamp(rawRate, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
		
		sectorRates[sector] = rawRate
		bailoutRates[sector] = math.max(rawRate, CONFIG.BAILOUT_FLOOR)
		
		-- Record history
		table.insert(sectorHistories[sector], rawRate)
		if #sectorHistories[sector] > CONFIG.MAX_HISTORY then
			table.remove(sectorHistories[sector], 1)
		end
	end
end

local function performGlobalRead()
	local ok, vol = pcall(readGlobalVolumes)
	if ok and vol then
		computeGlobalRates(vol)
		return true
	else
		warn("StockMarketManager: MemoryStore read failed:", vol)
		return false
	end
end

--------------------------------------------------------------------------------
-- MEMORYSTORE: SHARDED WRITER
--------------------------------------------------------------------------------

local function flushSalesBuffer()
	-- Snapshot and clear buffer atomically
	local snapshot = ServerSalesBuffer
	ServerSalesBuffer = {}
	
	-- Check if there's anything to write
	local hasData = false
	for _, v in pairs(snapshot) do
		if v > 0 then hasData = true; break end
	end
	if not hasData then return end
	
	-- Pick a random shard to minimize key contention
	local shardId = math.random(1, CONFIG.NUM_SHARDS)
	local key = "GlobalVol_Shard_" .. shardId
	
	local ok, err = pcall(function()
		GlobalMarketMap:UpdateAsync(key, function(old)
			old = old or {}
			for sector, amount in pairs(snapshot) do
				old[sector] = (old[sector] or 0) + amount
			end
			return old
		end, CONFIG.SHARD_EXPIRATION)
	end)
	
	if ok then
		local totalFlushed = 0
		for _, v in pairs(snapshot) do totalFlushed += v end
		if totalFlushed > 0 then
			print("StockMarketManager: Flushed " .. totalFlushed .. " volume to shard " .. shardId)
		end
	else
		-- Restore buffer on failure (don't lose data)
		for sector, amount in pairs(snapshot) do
			ServerSalesBuffer[sector] = (ServerSalesBuffer[sector] or 0) + amount
		end
		warn("StockMarketManager: MemoryStore write failed (shard " .. shardId .. "):", err)
	end
end

--------------------------------------------------------------------------------
-- ATTRIBUTE REPLICATION
--------------------------------------------------------------------------------

local function replicateToClients()
	local sum = 0; for _, r in pairs(sectorRates) do sum += r end
	local avgRate = sum / #SECTORS
	
	stockMarketFolder:SetAttribute("SectorRates", serializeSectorRates())
	stockMarketFolder:SetAttribute("SectorHistories", serializeSectorHistories())
	stockMarketFolder:SetAttribute("Sectors", HttpService:JSONEncode(SECTORS))
	stockMarketFolder:SetAttribute("SectorColors", HttpService:JSONEncode(SECTOR_COLORS))
	
	-- Legacy compat
	stockMarketFolder:SetAttribute("CurrentRate", avgRate)
	stockMarketFolder:SetAttribute("RateName", getGlobalRateName())
	stockMarketFolder:SetAttribute("RateHistory", serializeHistory(sectorHistories.Food))
	stockMarketFolder:SetAttribute("LastUpdate", os.time())
	stockMarketFolder:SetAttribute("UpdateInterval", 
		useGlobalPricing and CONFIG.READ_INTERVAL or CONFIG.LOCAL_UPDATE_INTERVAL)
	
	-- NEW: Per-sector bailout rates for welfare check
	local bailoutJson = {}
	for sector, rate in pairs(bailoutRates) do
		bailoutJson[sector] = math.floor(rate * 1000) / 1000
	end
	stockMarketFolder:SetAttribute("BailoutRates", HttpService:JSONEncode(bailoutJson))
	
	-- Flag for clients to know which pricing model is active
	stockMarketFolder:SetAttribute("GlobalPricingActive", useGlobalPricing)
end

-- Fallback: old-style random local update (with jitter for liveliness)
local function updateMarketLocal()
	local dt = CONFIG.LOCAL_UPDATE_INTERVAL
	local alpha = math.clamp(CONFIG.TREND_DAMPING * dt, 0, 1)

	for _, cat in ipairs(SECTORS) do
		local nr = calculateLocalRate(cat)
		
		-- ALSO apply Synthetic Trend in local mode now, so we can test Hype/Crash logic
		local targetTrend = getSyntheticTrend(cat)
		local currentTrend = sectorTrends[cat] or 1.0
		local smoothedTrend = currentTrend + (targetTrend - currentTrend) * alpha
		sectorTrends[cat] = smoothedTrend
		
		nr *= smoothedTrend
		
		-- Apply jitter even in fallback mode for smooth wiggling
		nr *= getJitter(cat)
		nr = math.clamp(nr, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
		sectorRates[cat] = nr
		bailoutRates[cat] = math.max(nr, CONFIG.BAILOUT_FLOOR)
		table.insert(sectorHistories[cat], nr)
		if #sectorHistories[cat] > CONFIG.MAX_HISTORY then
			table.remove(sectorHistories[cat], 1)
		end
	end
	replicateToClients()
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function StockMarketManager.Init(services)
	print("   StockMarketManager (Module) - Initializing")
	Services = services or {}
	
	-- Create or find the ReplicatedStorage folder for client access
	stockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket") or Instance.new("Folder")
	stockMarketFolder.Name = "StockMarket"
	stockMarketFolder.Parent = ReplicatedStorage
	
	-- Initialize all sector rates
	for _, cat in ipairs(SECTORS) do
		sectorRates[cat] = CONFIG.STARTING_RATE
		bailoutRates[cat] = CONFIG.STARTING_RATE
		sectorHistories[cat] = {}
		for i = 1, CONFIG.MAX_HISTORY do
			table.insert(sectorHistories[cat], CONFIG.STARTING_RATE)
		end
		ServerSalesBuffer[cat] = 0
		sectorTrends[cat] = 1.0
	end
	
	-- Static attributes
	stockMarketFolder:SetAttribute("MinRate", CONFIG.MIN_RATE)
	stockMarketFolder:SetAttribute("MaxRate", CONFIG.MAX_RATE)
	stockMarketFolder:SetAttribute("BailoutFloor", CONFIG.BAILOUT_FLOOR)
	
	-- Try to connect to MemoryStoreService
	local initOk, initErr = pcall(function()
		GlobalMarketMap = MemoryStoreService:GetSortedMap("GlobalMarket_v1")
	end)
	
	if initOk and GlobalMarketMap then
		-- Test read to verify MemoryStore is working
		local testOk = pcall(function()
			GlobalMarketMap:GetAsync("GlobalVol_Shard_1")
		end)
		if testOk then
			useGlobalPricing = true
			print("   StockMarketManager: ✓ MemoryStore connected — global pricing ACTIVE")
		else
			print("   StockMarketManager: MemoryStore read test failed — using local fallback")
		end
	else
		warn("   StockMarketManager: MemoryStore init failed:", initErr, "— using local fallback")
	end
	
	-- Initial replication
	replicateToClients()
	
	local now = os.time()
	nextReadTime = now + CONFIG.READ_INTERVAL
	nextWriteTime = now + CONFIG.WRITE_INTERVAL
	nextLocalUpdate = now + CONFIG.LOCAL_UPDATE_INTERVAL
	stockMarketFolder:SetAttribute("NextUpdate", nextReadTime)
	
	-- Main heartbeat loop
	RunService.Heartbeat:Connect(function()
		local now2 = os.time()
		
		if useGlobalPricing then
			-- GLOBAL MODE: Read from MemoryStore shards
			if now2 >= nextReadTime then
				nextReadTime = now2 + CONFIG.READ_INTERVAL
				task.spawn(function()
					performGlobalRead()
					replicateToClients()
					stockMarketFolder:SetAttribute("NextUpdate", nextReadTime)
				end)
			end
			
			-- Flush sales buffer to a random shard
			if now2 >= nextWriteTime then
				nextWriteTime = now2 + CONFIG.WRITE_INTERVAL
				task.spawn(flushSalesBuffer)
			end
		else
			-- FALLBACK MODE: Old random local pricing
			if now2 >= nextLocalUpdate then
				nextLocalUpdate = now2 + CONFIG.LOCAL_UPDATE_INTERVAL
				updateMarketLocal()
				stockMarketFolder:SetAttribute("NextUpdate", nextLocalUpdate)
			end
		end
	end)
	
	print("✓ StockMarketManager Initialized (" 
		.. (useGlobalPricing and "GLOBAL" or "LOCAL FALLBACK") .. " mode)")
end

--[[
	AddSalesVolume: Called by MarketManager after a player sells items.
	Buffers the volume to be flushed to MemoryStore on the next write cycle.
	
	@param sector string - The market sector (e.g., "Food", "Animals")
	@param count number - Number of items sold
]]
function StockMarketManager.AddSalesVolume(sector: string, count: number)
	if not sector or not count or count <= 0 then return end
	ServerSalesBuffer[sector] = (ServerSalesBuffer[sector] or 0) + count
end

-- Getters (backward compatible)
StockMarketManager.GetSectorRate = function(c) return sectorRates[c] or 1.0 end
StockMarketManager.GetBailoutRate = function(c) return bailoutRates[c] or CONFIG.BAILOUT_FLOOR end
StockMarketManager.GetAllSectorRates = function() return table.clone(sectorRates) end
StockMarketManager.GetAllBailoutRates = function() return table.clone(bailoutRates) end
StockMarketManager.GetSectors = function() return SECTORS end
StockMarketManager.IsGlobalPricingActive = function() return useGlobalPricing end

return StockMarketManager
