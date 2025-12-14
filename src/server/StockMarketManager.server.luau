--[[
	StockMarketManager Server Script
	
	Handles the dynamic brainrot stock market with per-category price indexes.
	- 6 independent category rates: Skibidi, Bombardiro, Tralalero, BrrBrr, Sigma, Mewer
	- Each category has independent volatility and mean reversion
	- Continuous rate range from 0.5x to 3.0x per category
	- Updates every 20 seconds with random walk + mean reversion
	- Stores 60 data points of history per category for graph display
	- Replicates rates and histories to clients via Attributes
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- Configuration
local CONFIG = {
	UPDATE_INTERVAL = 20, -- Seconds between updates
	
	-- Rate Range
	MIN_RATE = 0.5,
	MAX_RATE = 3.0,
	STARTING_RATE = 1.0,
	
	-- Base Movement Settings
	BASE_VOLATILITY = 0.25,   -- Normal change range
	SPIKE_CHANCE = 0.10,      -- 10% chance of larger move
	SPIKE_MULTIPLIER = 2.5,   -- Spikes are 2.5x normal volatility
	MEAN_REVERSION = 0.05,    -- Strength of pull towards 1.0
	
	-- History
	MAX_HISTORY = 60,         -- 60 data points = 20 minutes of data
}

-- Category-specific volatility modifiers
local CATEGORY_VOLATILITY = {
	Skibidi = 0.25,     -- Low volatility (stable)
	Bombardiro = 0.45,  -- High volatility (explosive)
	Tralalero = 0.30,   -- Medium volatility
	BrrBrr = 0.35,      -- Medium-high volatility
	Sigma = 0.40,       -- High volatility
	Mewer = 0.20,       -- Very stable
}

-- All category names
local CATEGORIES = {"Skibidi", "Bombardiro", "Tralalero", "BrrBrr", "Sigma", "Mewer"}

-- Category display info (colors for client reference)
local CATEGORY_COLORS = {
	Skibidi = {148, 103, 189},    -- Purple
	Bombardiro = {255, 127, 14},  -- Orange
	Tralalero = {44, 160, 44},    -- Green
	BrrBrr = {31, 119, 180},      -- Blue
	Sigma = {214, 39, 40},        -- Red
	Mewer = {227, 119, 194},      -- Pink
}

-- State per category
local categoryRates = {}
local categoryHistories = {}

-- Initialize state for all categories
for _, category in ipairs(CATEGORIES) do
	categoryRates[category] = CONFIG.STARTING_RATE
	categoryHistories[category] = {}
	-- Fill history with starting rate
	for i = 1, CONFIG.MAX_HISTORY do
		table.insert(categoryHistories[category], CONFIG.STARTING_RATE)
	end
end

local nextUpdate = 0

-- Setup ReplicatedStorage container
local stockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket")
if not stockMarketFolder then
	stockMarketFolder = Instance.new("Folder")
	stockMarketFolder.Name = "StockMarket"
	stockMarketFolder.Parent = ReplicatedStorage
end

--[[
	Serializes a single category's history to comma-separated string.
]]
local function serializeHistory(history: {number}): string
	local parts = {}
	for _, rate in ipairs(history) do
		table.insert(parts, string.format("%.3f", rate))
	end
	return table.concat(parts, ",")
end

--[[
	Serializes all category rates to JSON for attribute storage.
]]
local function serializeCategoryRates(): string
	local ratesTable = {}
	for category, rate in pairs(categoryRates) do
		ratesTable[category] = math.floor(rate * 1000) / 1000 -- Round to 3 decimals
	end
	return HttpService:JSONEncode(ratesTable)
end

--[[
	Serializes all category histories to JSON for attribute storage.
]]
local function serializeCategoryHistories(): string
	local historiesTable = {}
	for category, history in pairs(categoryHistories) do
		historiesTable[category] = serializeHistory(history)
	end
	return HttpService:JSONEncode(historiesTable)
end

--[[
	Calculates the global rate name based on the average rate.
]]
local function getGlobalRateName(): string
	local sum = 0
	for _, rate in pairs(categoryRates) do
		sum = sum + rate
	end
	local avgRate = sum / #CATEGORIES
	
	if avgRate >= 2.5 then
		return "HYPER INFLATION"
	elseif avgRate >= 1.5 then
		return "STONKS"
	elseif avgRate <= 0.7 then
		return "CRASH"
	else
		return "NORMAL"
	end
end

--[[
	Calculates the average rate across all categories for backwards compatibility.
]]
local function getAverageRate(): number
	local sum = 0
	for _, rate in pairs(categoryRates) do
		sum = sum + rate
	end
	return sum / #CATEGORIES
end

--[[
	Calculates a new rate for a specific category using random walk with mean reversion.
]]
local function calculateNewRate(category: string): number
	local currentRate = categoryRates[category]
	local volatility = CATEGORY_VOLATILITY[category] or CONFIG.BASE_VOLATILITY
	
	-- Base random change with category-specific volatility
	local baseChange = (math.random() - 0.5) * 2 * volatility
	
	-- Occasional larger moves (volatility spikes)
	if math.random() < CONFIG.SPIKE_CHANCE then
		baseChange = baseChange * CONFIG.SPIKE_MULTIPLIER
	end
	
	-- Mean reversion: gently pull towards 1.0
	local reversion = (CONFIG.STARTING_RATE - currentRate) * CONFIG.MEAN_REVERSION
	
	-- Apply changes
	local newRate = currentRate + baseChange + reversion
	
	-- Clamp to valid range
	return math.clamp(newRate, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
end

--[[
	Updates the market with new rates for all categories.
]]
local function updateMarket()
	-- Update each category
	for _, category in ipairs(CATEGORIES) do
		local newRate = calculateNewRate(category)
		categoryRates[category] = newRate
		
		-- Update history
		table.insert(categoryHistories[category], newRate)
		if #categoryHistories[category] > CONFIG.MAX_HISTORY then
			table.remove(categoryHistories[category], 1)
		end
	end
	
	-- Calculate average for backwards compatibility
	local avgRate = getAverageRate()
	local globalRateName = getGlobalRateName()
	
	-- Update Attributes for clients
	-- Per-category data (new)
	stockMarketFolder:SetAttribute("CategoryRates", serializeCategoryRates())
	stockMarketFolder:SetAttribute("CategoryHistories", serializeCategoryHistories())
	stockMarketFolder:SetAttribute("Categories", HttpService:JSONEncode(CATEGORIES))
	stockMarketFolder:SetAttribute("CategoryColors", HttpService:JSONEncode(CATEGORY_COLORS))
	
	-- Global data (backwards compatible)
	stockMarketFolder:SetAttribute("CurrentRate", avgRate)
	stockMarketFolder:SetAttribute("RateName", globalRateName)
	stockMarketFolder:SetAttribute("RateHistory", serializeHistory(categoryHistories.Skibidi)) -- Legacy fallback
	stockMarketFolder:SetAttribute("LastUpdate", os.time())
	stockMarketFolder:SetAttribute("UpdateInterval", CONFIG.UPDATE_INTERVAL)
end

-- Initialize Attributes
stockMarketFolder:SetAttribute("Categories", HttpService:JSONEncode(CATEGORIES))
stockMarketFolder:SetAttribute("CategoryColors", HttpService:JSONEncode(CATEGORY_COLORS))
stockMarketFolder:SetAttribute("CategoryRates", serializeCategoryRates())
stockMarketFolder:SetAttribute("CategoryHistories", serializeCategoryHistories())
stockMarketFolder:SetAttribute("CurrentRate", CONFIG.STARTING_RATE)
stockMarketFolder:SetAttribute("RateName", "NORMAL")
stockMarketFolder:SetAttribute("RateHistory", serializeHistory(categoryHistories.Skibidi))
stockMarketFolder:SetAttribute("LastUpdate", os.time())
stockMarketFolder:SetAttribute("UpdateInterval", CONFIG.UPDATE_INTERVAL)
stockMarketFolder:SetAttribute("MinRate", CONFIG.MIN_RATE)
stockMarketFolder:SetAttribute("MaxRate", CONFIG.MAX_RATE)

-- Main Loop
RunService.Heartbeat:Connect(function()
	local now = os.time()
	if now >= nextUpdate then
		updateMarket()
		nextUpdate = now + CONFIG.UPDATE_INTERVAL
		stockMarketFolder:SetAttribute("NextUpdate", nextUpdate)
	end
end)

-- Initial update
nextUpdate = os.time() + CONFIG.UPDATE_INTERVAL
stockMarketFolder:SetAttribute("NextUpdate", nextUpdate)

-- Export API for other scripts to get category rates
_G.StockMarketManager = {
	GetCategoryRate = function(category: string): number
		return categoryRates[category] or 1.0
	end,
	GetAllCategoryRates = function(): {[string]: number}
		return table.clone(categoryRates)
	end,
	GetCategories = function(): {string}
		return CATEGORIES
	end,
}

print("✓ StockMarketManager initialized (6 category stocks: 0.5x - 3.0x)")
