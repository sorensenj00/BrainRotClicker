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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MarketConfig = require(Shared:WaitForChild("MarketConfig"))
local MarketVolatilityService = require(script.Parent:WaitForChild("MarketVolatilityService"))

local CONFIG = MarketConfig.CONFIG
local SECTORS = MarketConfig.SECTORS

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local StockMarketManager = {}
local _Services = {}

local sectorRates = {}        -- { [sector] = currentMarketRate (DISPLAY RATE) }
local baseSectorRates = {}    -- { [sector] = underlyingBaseRate (REAL VALUE) }
local itemRates = {}          -- { [itemId] = currentItemRate }
local bailoutRates = {}       -- { [sector] = bailoutRate }
local sectorHistories = {}
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

local function serializeItemRates()
	local t = {}
	for id, r in pairs(itemRates) do t[id] = math.floor(r * 1000) / 1000 end
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
	local vol = MarketConfig.SECTOR_VOLATILITY[sector] or CONFIG.BASE_VOLATILITY
	local base = (math.random() - 0.5) * 2 * vol
	if math.random() < CONFIG.SPIKE_CHANCE then base *= CONFIG.SPIKE_MULTIPLIER end
	local rev = (CONFIG.STARTING_RATE - current) * CONFIG.MEAN_REVERSION
	return math.clamp(current + base + rev, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
end

--------------------------------------------------------------------------------
-- ITEM JITTER (Missing Global Fix)
--------------------------------------------------------------------------------

local function getItemJitter(itemId, volatility)
	-- Generate deterministic seed from ItemId
	local seed = 0
	for i = 1, #itemId do
		seed = seed + string.byte(itemId, i)
	end
	
	-- Use a slightly different time & scale so items don't sync perfectly with sectors
	local timeOffset = os.clock() * (CONFIG.JITTER_SPEED or 1) * 1.5
	
	-- Perlin noise returns -0.5 to 0.5
	local noise = math.noise(timeOffset, seed * 0.13, 0)
	
	-- Volatility is the amplitude (e.g. 0.1 means ±5%)
	return 1 + (noise * (volatility or 0.1))
end

--------------------------------------------------------------------------------
-- MEMORYSTORE: SHARDED READER
--------------------------------------------------------------------------------

local function readGlobalVolumes(): {[string]: number}
	local totalVolumes: {[string]: number} = {}
	for _, sector in ipairs(SECTORS) do totalVolumes[sector] = 0 end
	
	for shardId = 1, CONFIG.NUM_SHARDS do
		local key = "GlobalVol_Shard_" .. shardId
		-- Read AND CLEAR the shard atomically
		pcall(function()
			GlobalMarketMap:UpdateAsync(key, function(oldData)
				if oldData and type(oldData) == "table" then
					for sector, vol in pairs(oldData) do
						if totalVolumes[sector] then
							totalVolumes[sector] += (tonumber(vol) or 0)
						end
					end
				end
				return nil -- Returning nil DELETES the key, clearing the volume
			end, CONFIG.SHARD_EXPIRATION)
		end)
	end
	
	return totalVolumes
end

local function computeGlobalRates(totalVolumes: {[string]: number})
	local dt = CONFIG.READ_INTERVAL

	for _, sector in ipairs(SECTORS) do
		local vol = totalVolumes[sector] or 0
		
		-- FIX: Get the LAST rate, not the STARTING rate. Use a separate base rate to avoid feedback loops from jitter.
		-- Note: We need to ensure baseSectorRates is initialized in Init. For now, fall back to current sectorRates or Start.
		local currentBaseRate = baseSectorRates[sector] or sectorRates[sector] or CONFIG.STARTING_RATE
		
		-- Subtract impact and add recovery
		-- Note: Impact depends on Volume * ImpactFactor. Since volume is now value-weighted, this works.
		local rawRate = currentBaseRate - (vol * CONFIG.IMPACT_FACTOR) + (CONFIG.RECOVERY_RATE * dt)
		
		-- Get volatility from service
		-- rawRate is the "real" economic value. targetTrend is the "market maker" target.
		local targetTrend, jitter = MarketVolatilityService.CalculateVolatility(sector, dt)
		
		-- Smoothly drift the real economy towards the artificial trend (Market Maker) when volume is low
		if vol < CONFIG.DEAD_MARKET_THRESHOLD then
			rawRate = rawRate + (targetTrend - rawRate) * (CONFIG.TREND_DAMPING * dt)
		end
		
		-- Final clamp on the BASE rate
		rawRate = math.clamp(rawRate, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
		
		-- Save the REAL underlying value for next time
		baseSectorRates[sector] = rawRate
		
		-- Apply JITTER: Always-on Perlin noise micro-fluctuation
		-- This is the "Display Rate" / "Actual Sale Price"
		local displayRate = math.clamp(rawRate * jitter, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
		
		sectorRates[sector] = displayRate
		bailoutRates[sector] = math.max(displayRate, CONFIG.BAILOUT_FLOOR)
		
		-- Record history
		table.insert(sectorHistories[sector], displayRate)
		if #sectorHistories[sector] > CONFIG.MAX_HISTORY then
			table.remove(sectorHistories[sector], 1)
		end
	end
	
	-- Update Item Rates based on new Sector Rates
	local ItemConfig = require(ReplicatedStorage.Shared.ItemConfig)
	for itemId, itemDef in pairs(ItemConfig.Items) do
		local sector = ItemConfig.GetSector(itemDef.displayName) -- Optimization: Cache this if slow
		local baseRate = sectorRates[sector] or 1.0
		
		-- Apply individual item volatility
		-- Items with high volatility (Tier 4) deviate more from the sector average
		local divergence = getItemJitter(itemId, itemDef.volatility or 0.1)
		
		local finalRate = baseRate * divergence
		finalRate = math.clamp(finalRate, CONFIG.MIN_RATE, 5.0) -- Items can go slightly higher than sector cap
		
		itemRates[itemId] = finalRate
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
	stockMarketFolder:SetAttribute("ItemRates", serializeItemRates())
	stockMarketFolder:SetAttribute("SectorHistories", serializeSectorHistories())
	stockMarketFolder:SetAttribute("Sectors", HttpService:JSONEncode(SECTORS))
	stockMarketFolder:SetAttribute("SectorColors", HttpService:JSONEncode(MarketConfig.SECTOR_COLORS))
	
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

	for _, cat in ipairs(SECTORS) do
		local nr = calculateLocalRate(cat)
		
		-- Get volatility from service
		local smoothedTrend, jitter = MarketVolatilityService.CalculateVolatility(cat, dt)
		
		nr *= smoothedTrend
		
		-- Apply jitter even in fallback mode for smooth wiggling
		nr *= jitter
		nr = math.clamp(nr, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
		sectorRates[cat] = nr
		bailoutRates[cat] = math.max(nr, CONFIG.BAILOUT_FLOOR)
		table.insert(sectorHistories[cat], nr)
		if #sectorHistories[cat] > CONFIG.MAX_HISTORY then
			table.remove(sectorHistories[cat], 1)
		end
	end
	
	-- Update Item Rates (Local Fallback)
	local ItemConfig = require(ReplicatedStorage.Shared.ItemConfig)
	for itemId, itemDef in pairs(ItemConfig.Items) do
		local sector = ItemConfig.GetSector(itemDef.displayName)
		local baseRate = sectorRates[sector] or 1.0
		local divergence = getItemJitter(itemId, itemDef.volatility or 0.1)
		local finalRate = baseRate * divergence
		
		itemRates[itemId] = math.clamp(finalRate, CONFIG.MIN_RATE, 5.0)
	end
	
	replicateToClients()
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function StockMarketManager.Init(services)
	print("   StockMarketManager (Module) - Initializing")
	Services = services or {}
	
	MarketVolatilityService.Init()

	-- Create or find the ReplicatedStorage folder for client access
	stockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket") or Instance.new("Folder")
	stockMarketFolder.Name = "StockMarket"
	stockMarketFolder.Parent = ReplicatedStorage
	
	-- Initialize all sector rates
	for _, cat in ipairs(SECTORS) do
		sectorRates[cat] = CONFIG.STARTING_RATE
		baseSectorRates[cat] = CONFIG.STARTING_RATE
		bailoutRates[cat] = CONFIG.STARTING_RATE
		sectorHistories[cat] = {}
		for i = 1, CONFIG.MAX_HISTORY do
			table.insert(sectorHistories[cat], CONFIG.STARTING_RATE)
		end
		ServerSalesBuffer[cat] = 0
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
StockMarketManager.GetItemRate = function(id) return itemRates[id] or 1.0 end
StockMarketManager.GetBailoutRate = function(c) return bailoutRates[c] or CONFIG.BAILOUT_FLOOR end
StockMarketManager.GetAllSectorRates = function() return table.clone(sectorRates) end
StockMarketManager.GetAllBailoutRates = function() return table.clone(bailoutRates) end
StockMarketManager.GetSectors = function() return SECTORS end
StockMarketManager.IsGlobalPricingActive = function() return useGlobalPricing end

return StockMarketManager
