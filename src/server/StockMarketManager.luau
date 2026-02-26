--[[
	StockMarketManager Server Module
	
	═══════════════════════════════════════════════════════════════════════════════
	              GLOBAL SHARDED AMM WITH WELFARE
	═══════════════════════════════════════════════════════════════════════════════
	
	PURPOSE:
	  Implements a true Automated Market Maker (AMM) backed by global liquidity
	  pools. Prices are derived from the ratio of GlobalCash to GlobalItems per
	  sector, stored in MemoryStoreService via sharded delta writes.
	
	ARCHITECTURE:
	  • POOL STATE  — Each sector has { globalItems, globalCash } starting at
	    virtual liquidity (100k/100k). This is the "truth" for pricing.
	  • READ LOOP   (every 5s)  — Read all shards, sum deltas, apply to pool
	    state, recompute rates, replicate via attributes.
	  • WRITE LOOP  (every 10s) — Flush this server's buffered pool deltas into
	    one random shard to avoid key-lock contention.
	  • PRICING     — BaseRate = (GlobalCash / GlobalItems) * CalibrationConstant
	    Perlin noise (MarketVolatilityService) is applied as visual jitter only.
	  • FALLBACK    — If MemoryStore fails (Studio / offline), gracefully degrade
	    to the old random local pricing so gameplay isn't blocked.
	
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
local _Services: any = {}

local sectorRates = {}        -- { [sector] = currentMarketRate (DISPLAY RATE) }
local baseSectorRates = {}    -- { [sector] = underlyingBaseRate (REAL VALUE from AMM) }
local itemRates = {}          -- { [itemId] = currentItemRate (GLOBAL) }
local localItemRates = {}     -- { [itemId] = localRate (SERVER-SPECIFIC, subject to shocks) }
local bailoutRates = {}       -- { [sector] = bailoutRate }
local sectorHistories = {}
local stockMarketFolder = nil

-- AMM Liquidity Pool State (local cache, authoritative = MemoryStore)
local poolState = {}          -- { [sector] = { globalItems: number, globalCash: number } }

-- MemoryStore state
local GlobalPoolMap = nil         -- MemoryStoreService sorted map for pool deltas
local PoolDeltaBuffer = {}        -- { [sector] = { deltaItems: number, deltaCash: number } }
local useGlobalPricing = false    -- true once MemoryStore is confirmed working
local nextReadTime = 0
local nextWriteTime = 0
local nextLocalUpdate = 0
local lastReboundTick = os.clock() -- For elastic rebound delta-time
local localRatesDirty = false
local localRatesReplicationAccumulator = 0
local LOCAL_RATES_REPLICATION_INTERVAL = 0.25 -- 4Hz max
local LOCAL_REBOUND_EPSILON = 0.002 -- Align with 3dp serialization precision
local lastLocalItemRatesJson = ""

-- Legacy compatibility
local ServerSalesBuffer = {}      -- Kept for AddSalesVolume backward compat

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

local function serializeLocalItemRates()
	local t = {}
	for id, r in pairs(localItemRates) do t[id] = math.floor(r * 1000) / 1000 end
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
-- ITEM JITTER
--------------------------------------------------------------------------------

local function getItemJitter(itemId, volatility)
	local seed = 0
	for i = 1, #itemId do
		seed = seed + string.byte(itemId, i)
	end
	local timeOffset = os.clock() * (CONFIG.JITTER_SPEED or 1) * 1.5
	local noise = math.noise(timeOffset, seed * 0.13, 0)
	return 1 + (noise * (volatility or 0.1))
end

--------------------------------------------------------------------------------
-- AMM PRICING: Compute rates from pool state
--------------------------------------------------------------------------------

--[[
	Computes sector rates from AMM pool state.
	BaseRate = (GlobalCash / GlobalItems) * CalibrationConstant
	Then applies Perlin jitter as display-only overlay.
]]
local function computeAMMRates()
	local dt = CONFIG.READ_INTERVAL

	for _, sector in ipairs(SECTORS) do
		local pool = poolState[sector]
		if not pool then continue end

		-- Global Mean Reversion (self-healing market):
		-- slowly pull pool state back toward virtual baseline over time.
		local itemDiff = CONFIG.VIRTUAL_ITEMS - pool.globalItems
		local cashDiff = CONFIG.VIRTUAL_CASH - pool.globalCash
		pool.globalItems = pool.globalItems + (itemDiff * CONFIG.RECOVERY_RATE * dt)
		pool.globalCash = pool.globalCash + (cashDiff * CONFIG.RECOVERY_RATE * dt)
		pool.globalItems = math.max(pool.globalItems, CONFIG.VIRTUAL_ITEMS * 0.01)
		pool.globalCash = math.max(pool.globalCash, CONFIG.VIRTUAL_CASH * 0.01)

		-- AMM Core Formula
		local items = math.max(pool.globalItems, 1)  -- Prevent division by zero
		local cash = math.max(pool.globalCash, 0)
		local ammBaseRate = (cash / items) * CONFIG.CALIBRATION_CONSTANT

		-- Get volatility from service (for visual jitter only)
		local targetTrend, jitter = MarketVolatilityService.CalculateVolatility(sector, dt)

		-- In low-volume conditions, drift AMM rate gently towards synthetic trend
		-- This keeps the market "alive" visually even when nobody trades
		local totalVolume = math.abs(pool.globalItems - CONFIG.VIRTUAL_ITEMS) + math.abs(pool.globalCash - CONFIG.VIRTUAL_CASH)
		if totalVolume < CONFIG.DEAD_MARKET_THRESHOLD then
			local clampedTrend = math.clamp(targetTrend, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
			ammBaseRate = ammBaseRate + (clampedTrend - ammBaseRate) * (CONFIG.TREND_DAMPING * dt)
		end

		-- Clamp the real base rate
		ammBaseRate = math.clamp(ammBaseRate, CONFIG.MIN_RATE, CONFIG.MAX_RATE)

		-- Save the REAL underlying value
		baseSectorRates[sector] = ammBaseRate

		-- Apply JITTER: Always-on Perlin noise micro-fluctuation (display only)
		local displayRate = math.clamp(ammBaseRate * jitter, CONFIG.MIN_RATE, CONFIG.MAX_RATE)

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
		local sector = ItemConfig.GetSector(itemDef.displayName)
		local baseRate = sectorRates[sector] or 1.0
		local divergence = getItemJitter(itemId, itemDef.volatility or 0.1)
		local finalRate = baseRate * divergence
		finalRate = math.clamp(finalRate, CONFIG.MIN_RATE, 5.0)
		itemRates[itemId] = finalRate
	end
end

--------------------------------------------------------------------------------
-- MEMORYSTORE: SHARDED POOL READER
--------------------------------------------------------------------------------

--[[
	Reads all shards, sums up {deltaItems, deltaCash} per sector,
	and applies them to the virtual liquidity baseline.
	Clears shards atomically after reading.
]]
local function readGlobalPools(): boolean
	local totalDeltas: {[string]: {deltaItems: number, deltaCash: number}} = {}
	for _, sector in ipairs(SECTORS) do
		totalDeltas[sector] = { deltaItems = 0, deltaCash = 0 }
	end

	for shardId = 1, CONFIG.NUM_SHARDS do
		local key = "AMMPool_Shard_" .. shardId
		pcall(function()
			GlobalPoolMap:UpdateAsync(key, function(oldData)
				if oldData and type(oldData) == "table" then
					for sector, deltas in pairs(oldData) do
						if totalDeltas[sector] and type(deltas) == "table" then
							totalDeltas[sector].deltaItems += (tonumber(deltas.deltaItems) or 0)
							totalDeltas[sector].deltaCash += (tonumber(deltas.deltaCash) or 0)
						end
					end
				end
				return nil -- Clear the shard after reading
			end, CONFIG.SHARD_EXPIRATION)
		end)
	end

	-- Apply accumulated deltas to pool state (on top of virtual liquidity)
	for _, sector in ipairs(SECTORS) do
		local pool = poolState[sector]
		local deltas = totalDeltas[sector]
		if pool and deltas then
			pool.globalItems = pool.globalItems + deltas.deltaItems
			pool.globalCash = pool.globalCash + deltas.deltaCash

			-- Safety: Ensure pool never goes below a minimum (virtual liquidity floor)
			pool.globalItems = math.max(pool.globalItems, CONFIG.VIRTUAL_ITEMS * 0.01)  -- Min 1% of seed
			pool.globalCash = math.max(pool.globalCash, CONFIG.VIRTUAL_CASH * 0.01)     -- Min 1% of seed
		end
	end

	return true
end

local function performGlobalRead()
	local ok, err = pcall(readGlobalPools)
	if ok then
		computeAMMRates()
		return true
	else
		warn("StockMarketManager: MemoryStore pool read failed:", err)
		return false
	end
end

--------------------------------------------------------------------------------
-- MEMORYSTORE: SHARDED POOL WRITER
--------------------------------------------------------------------------------

--[[
	Flushes this server's buffered pool deltas to a random shard.
	Keeps the sharding pattern to avoid key contention across servers.
]]
local function flushPoolDeltas()
	-- Snapshot and clear buffer atomically
	local snapshot = PoolDeltaBuffer
	PoolDeltaBuffer = {}
	for _, sector in ipairs(SECTORS) do
		PoolDeltaBuffer[sector] = { deltaItems = 0, deltaCash = 0 }
	end

	-- Check if there's anything to write
	local hasData = false
	for _, deltas in pairs(snapshot) do
		if deltas.deltaItems ~= 0 or deltas.deltaCash ~= 0 then
			hasData = true
			break
		end
	end
	if not hasData then return end

	-- Pick a random shard to minimize key contention
	local shardId = math.random(1, CONFIG.NUM_SHARDS)
	local key = "AMMPool_Shard_" .. shardId

	local ok, err = pcall(function()
		GlobalPoolMap:UpdateAsync(key, function(old)
			old = old or {}
			for sector, deltas in pairs(snapshot) do
				if deltas.deltaItems ~= 0 or deltas.deltaCash ~= 0 then
					if not old[sector] then
						old[sector] = { deltaItems = 0, deltaCash = 0 }
					end
					old[sector].deltaItems = (old[sector].deltaItems or 0) + deltas.deltaItems
					old[sector].deltaCash = (old[sector].deltaCash or 0) + deltas.deltaCash
				end
			end
			return old
		end, CONFIG.SHARD_EXPIRATION)
	end)

	if ok then
		local totalItems, totalCash = 0, 0
		for _, d in pairs(snapshot) do totalItems += d.deltaItems; totalCash += d.deltaCash end
		if totalItems ~= 0 or totalCash ~= 0 then
			print(string.format("StockMarketManager: Flushed pool deltas to shard %d (ΔItems=%.0f, ΔCash=%.0f)", 
				shardId, totalItems, totalCash))
		end
	else
		-- Restore buffer on failure (don't lose data)
		for sector, deltas in pairs(snapshot) do
			PoolDeltaBuffer[sector].deltaItems += deltas.deltaItems
			PoolDeltaBuffer[sector].deltaCash += deltas.deltaCash
		end
		warn("StockMarketManager: MemoryStore pool write failed (shard " .. shardId .. "):", err)
	end
end

--------------------------------------------------------------------------------
-- ATTRIBUTE REPLICATION
--------------------------------------------------------------------------------

local function replicateToClients()
	local sum = 0; for _, r in pairs(sectorRates) do sum += r end
	local avgRate = sum / #SECTORS

	local localRatesJson = serializeLocalItemRates()
	lastLocalItemRatesJson = localRatesJson
	localRatesDirty = false
	stockMarketFolder:SetAttribute("SectorRates", serializeSectorRates())
	stockMarketFolder:SetAttribute("ItemRates", serializeItemRates())
	stockMarketFolder:SetAttribute("LocalItemRates", localRatesJson)
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

	-- Per-sector bailout rates for welfare check
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
		local smoothedTrend, jitter = MarketVolatilityService.CalculateVolatility(cat, dt)
		nr *= smoothedTrend
		nr *= jitter
		nr = math.clamp(nr, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
		sectorRates[cat] = nr
		bailoutRates[cat] = math.max(nr, CONFIG.BAILOUT_FLOOR)
		table.insert(sectorHistories[cat], nr)
		if #sectorHistories[cat] > CONFIG.MAX_HISTORY then
			table.remove(sectorHistories[cat], 1)
		end
	end

	-- Also apply local pool adjustments to pool state for fallback pricing
	for _, sector in ipairs(SECTORS) do
		local pool = poolState[sector]
		local deltas = PoolDeltaBuffer[sector]
		if pool and deltas then
			pool.globalItems += deltas.deltaItems
			pool.globalCash += deltas.deltaCash
			pool.globalItems = math.max(pool.globalItems, CONFIG.VIRTUAL_ITEMS * 0.01)
			pool.globalCash = math.max(pool.globalCash, CONFIG.VIRTUAL_CASH * 0.01)
			deltas.deltaItems = 0
			deltas.deltaCash = 0
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
	_Services = services or {}

	MarketVolatilityService.Init()

	-- Create or find the ReplicatedStorage folder for client access
	stockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket") or Instance.new("Folder")
	stockMarketFolder.Name = "StockMarket"
	stockMarketFolder.Parent = ReplicatedStorage

	-- Initialize all sector rates AND pool state
	for _, cat in ipairs(SECTORS) do
		sectorRates[cat] = CONFIG.STARTING_RATE
		baseSectorRates[cat] = CONFIG.STARTING_RATE
		bailoutRates[cat] = CONFIG.STARTING_RATE
		sectorHistories[cat] = {}
		for i = 1, CONFIG.MAX_HISTORY do
			table.insert(sectorHistories[cat], CONFIG.STARTING_RATE)
		end
		ServerSalesBuffer[cat] = 0 -- Legacy compat

		-- Seed AMM liquidity pools with virtual liquidity
		poolState[cat] = {
			globalItems = CONFIG.VIRTUAL_ITEMS,
			globalCash = CONFIG.VIRTUAL_CASH,
		}
		PoolDeltaBuffer[cat] = { deltaItems = 0, deltaCash = 0 }
	end

	-- Static attributes
	stockMarketFolder:SetAttribute("MinRate", CONFIG.MIN_RATE)
	stockMarketFolder:SetAttribute("MaxRate", CONFIG.MAX_RATE)
	stockMarketFolder:SetAttribute("BailoutFloor", CONFIG.BAILOUT_FLOOR)

	-- Try to connect to MemoryStoreService
	local initOk, initErr = pcall(function()
		GlobalPoolMap = MemoryStoreService:GetSortedMap("AMMPool_v1")
	end)

	if initOk and GlobalPoolMap then
		-- Test read to verify MemoryStore is working
		local testOk = pcall(function()
			GlobalPoolMap:GetAsync("AMMPool_Shard_1")
		end)
		if testOk then
			useGlobalPricing = true
			print("   StockMarketManager: ✓ MemoryStore connected — AMM global pricing ACTIVE")
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
	RunService.Heartbeat:Connect(function(dt)
		local now2 = os.time()

		if useGlobalPricing then
			-- GLOBAL MODE: Read pool state from MemoryStore shards
			if now2 >= nextReadTime then
				nextReadTime = now2 + CONFIG.READ_INTERVAL
				task.spawn(function()
					performGlobalRead()
					replicateToClients()
					stockMarketFolder:SetAttribute("NextUpdate", nextReadTime)
				end)
			end

			-- Flush pool delta buffer to a random shard
			if now2 >= nextWriteTime then
				local poolSyncInterval = CONFIG.POOL_SYNC_INTERVAL or CONFIG.WRITE_INTERVAL
				nextWriteTime = now2 + poolSyncInterval
				task.spawn(flushPoolDeltas)
			end
		else
			-- FALLBACK MODE: Old random local pricing
			if now2 >= nextLocalUpdate then
				nextLocalUpdate = now2 + CONFIG.LOCAL_UPDATE_INTERVAL
				updateMarketLocal()
				stockMarketFolder:SetAttribute("NextUpdate", nextLocalUpdate)
			end
		end

		-- ELASTIC REBOUND: Smoothly lerp localItemRates back towards global itemRates
		local clockNow = os.clock()
		local reboundDt = clockNow - lastReboundTick
		lastReboundTick = clockNow
		local alpha = math.clamp(CONFIG.LOCAL_REBOUND_SPEED * reboundDt, 0, 1)
		local changed = false
		for itemId, localRate in pairs(localItemRates) do
			local globalRate = itemRates[itemId] or 1.0
			if math.abs(localRate - globalRate) > LOCAL_REBOUND_EPSILON then
				localItemRates[itemId] = localRate + (globalRate - localRate) * alpha
				changed = true
			else
				localItemRates[itemId] = globalRate
			end
		end
		if changed then
			localRatesDirty = true
		end

		localRatesReplicationAccumulator += dt
		if localRatesReplicationAccumulator < LOCAL_RATES_REPLICATION_INTERVAL then
			return
		end
		localRatesReplicationAccumulator -= LOCAL_RATES_REPLICATION_INTERVAL

		-- Replicate local rates at fixed cadence only when materially changed.
		if localRatesDirty then
			local localRatesJson = serializeLocalItemRates()
			if localRatesJson ~= lastLocalItemRatesJson then
				lastLocalItemRatesJson = localRatesJson
				localRatesDirty = false
				stockMarketFolder:SetAttribute("LocalItemRates", localRatesJson)
			end
		end
	end)

	print("✓ StockMarketManager Initialized (" 
		.. (useGlobalPricing and "AMM GLOBAL" or "LOCAL FALLBACK") .. " mode)")
end

--[[
	AdjustPool: Called by MarketManager after a player buys or sells items.
	Buffers the delta to be flushed to MemoryStore on the next write cycle.
	
	For SELLING: deltaItems > 0, deltaCash < 0 (items enter pool, cash leaves)
	For BUYING:  deltaItems < 0, deltaCash > 0 (items leave pool, cash enters)
	
	@param sector string - The market sector (e.g., "Food", "Animals")
	@param deltaItems number - Change in items (positive = items added to pool)
	@param deltaCash number - Change in cash (positive = cash added to pool)
]]
function StockMarketManager.AdjustPool(sector: string, deltaItems: number, deltaCash: number)
	if not sector then return end
	if not deltaItems or not deltaCash then return end

	-- Buffer for next flush
	local buf = PoolDeltaBuffer[sector]
	if buf then
		buf.deltaItems += deltaItems
		buf.deltaCash += deltaCash
	end

	-- Also apply immediately to local pool state for instant price feedback
	local pool = poolState[sector]
	if pool then
		pool.globalItems = math.max(pool.globalItems + deltaItems, CONFIG.VIRTUAL_ITEMS * 0.01)
		pool.globalCash = math.max(pool.globalCash + deltaCash, CONFIG.VIRTUAL_CASH * 0.01)
	end
end

--[[
	AddSalesVolume: LEGACY backward compatibility.
	Redirects to AdjustPool with sell semantics:
	items enter pool (+), cash leaves pool (-) proportional to volume weight.
	
	@param sector string - The market sector
	@param economicWeight number - Value-weighted volume (count * basePrice)
]]
function StockMarketManager.AddSalesVolume(sector: string, economicWeight: number)
	if not sector or not economicWeight or economicWeight <= 0 then return end
	-- Legacy: treat economic weight as items entering, cash leaving
	StockMarketManager.AdjustPool(sector, economicWeight * CONFIG.IMPACT_FACTOR * 1000000, -economicWeight * CONFIG.IMPACT_FACTOR * 1000000)
end

-- Getters (backward compatible)
StockMarketManager.GetSectorRate = function(c) return sectorRates[c] or 1.0 end
StockMarketManager.GetItemRate = function(id) return itemRates[id] or 1.0 end
StockMarketManager.GetLocalItemRate = function(id) return localItemRates[id] or itemRates[id] or 1.0 end
StockMarketManager.GetBailoutRate = function(c) return bailoutRates[c] or CONFIG.BAILOUT_FLOOR end
StockMarketManager.GetAllSectorRates = function() return table.clone(sectorRates) end
StockMarketManager.GetAllBailoutRates = function() return table.clone(bailoutRates) end
StockMarketManager.GetSectors = function() return SECTORS end
StockMarketManager.IsGlobalPricingActive = function() return useGlobalPricing end

StockMarketManager.GetPoolState = function(sector)
	local pool = poolState[sector]
	if pool then
		return { globalItems = pool.globalItems, globalCash = pool.globalCash }
	end
	return { globalItems = CONFIG.VIRTUAL_ITEMS, globalCash = CONFIG.VIRTUAL_CASH }
end

--[[
	ApplyLocalShock: Instantly spikes or crashes the local item rate on THIS server.
	Called by MarketManager after a buy/sell. The elastic rebound in Heartbeat
	will smoothly pull it back toward the global rate over time.

	Buying  → fewer items available locally → price spikes UP
	Selling → more items available locally  → price crashes DOWN

	@param itemId string - The item being traded
	@param volume number - How many items were traded
	@param isBuy boolean - true if player bought, false if player sold
]]
function StockMarketManager.ApplyLocalShock(itemId: string, volume: number, isBuy: boolean)
	if not itemId or not volume or volume <= 0 then return end

	local currentLocal = localItemRates[itemId] or itemRates[itemId] or 1.0
	local ItemConfig = require(ReplicatedStorage.Shared:WaitForChild("ItemConfig"))
	local itemDef = ItemConfig.Items and ItemConfig.Items[itemId]
	local basePrice = tonumber(itemDef and (itemDef.basePrice or itemDef.BasePrice or itemDef.price or itemDef.Price)) or 1
	basePrice = math.max(basePrice, 1)

	local economicWeight = math.max(1, math.log10(basePrice))
	local shockMagnitude = volume * economicWeight * (CONFIG.LOCAL_SHOCK_FACTOR * 0.5)

	local newRate
	if isBuy then
		-- Buying drives LOCAL price UP (scarcity)
		newRate = currentLocal * (1 + shockMagnitude)
	else
		-- Selling drives LOCAL price DOWN (surplus)
		newRate = currentLocal * (1 - math.min(shockMagnitude, 0.6)) -- Cap at 60% crash
	end

	localItemRates[itemId] = math.clamp(newRate, CONFIG.MIN_RATE * 0.5, CONFIG.MAX_RATE * 2)

	-- Immediately replicate the shock to clients
	local localRatesJson = serializeLocalItemRates()
	lastLocalItemRatesJson = localRatesJson
	localRatesDirty = false
	stockMarketFolder:SetAttribute("LocalItemRates", localRatesJson)
end

--[[
	ForceLocalShock: Admin testing function. Simulates a massive local trade.
	@param isMoon boolean - true for moon (price spike), false for crash
]]
function StockMarketManager.ForceLocalShock(isMoon: boolean)
	local ItemConfig = require(ReplicatedStorage.Shared.ItemConfig)
	for itemId, _ in pairs(ItemConfig.Items) do
		local currentLocal = localItemRates[itemId] or itemRates[itemId] or 1.0
		if isMoon then
			localItemRates[itemId] = math.clamp(currentLocal * 2.5, CONFIG.MIN_RATE, CONFIG.MAX_RATE * 2)
		else
			localItemRates[itemId] = math.clamp(currentLocal * 0.3, CONFIG.MIN_RATE * 0.5, CONFIG.MAX_RATE)
		end
	end
	local localRatesJson = serializeLocalItemRates()
	lastLocalItemRatesJson = localRatesJson
	localRatesDirty = false
	stockMarketFolder:SetAttribute("LocalItemRates", localRatesJson)
end

return StockMarketManager
