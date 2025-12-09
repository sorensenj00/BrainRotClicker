--[[
	StockMarketManager Server Script
	
	Handles the dynamic "Sauce" economy with a realistic stock market simulation.
	- Continuous rate range from 0.5x to 3.0x
	- Updates every 10 seconds with random walk + mean reversion
	- Stores 60 data points of history for graph display
	- Replicates rate and history to clients via Attributes
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Configuration
local CONFIG = {
	UPDATE_INTERVAL = 20, -- Seconds between updates
	
	-- Rate Range
	MIN_RATE = 0.5,
	MAX_RATE = 3.0,
	STARTING_RATE = 1.0,
	
	-- Movement Settings
	BASE_VOLATILITY = 0.3,    -- Normal change range (-0.3 to +0.3)
	SPIKE_CHANCE = 0.10,      -- 10% chance of larger move
	SPIKE_MULTIPLIER = 2.5,   -- Spikes are 2.5x normal volatility
	MEAN_REVERSION = 0.05,    -- Strength of pull towards 1.0
	
	-- History
	MAX_HISTORY = 60,         -- 60 data points = 10 minutes of data
}

-- State
local currentRate = CONFIG.STARTING_RATE
local nextUpdate = 0
local history = {}

-- Initialize history with starting rate
for i = 1, CONFIG.MAX_HISTORY do
	table.insert(history, CONFIG.STARTING_RATE)
end

-- Setup ReplicatedStorage container
local stockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket")
if not stockMarketFolder then
	stockMarketFolder = Instance.new("Folder")
	stockMarketFolder.Name = "StockMarket"
	stockMarketFolder.Parent = ReplicatedStorage
end

--[[
	Serializes the history array to a comma-separated string for attribute storage.
]]
local function serializeHistory(): string
	local parts = {}
	for _, rate in ipairs(history) do
		table.insert(parts, string.format("%.3f", rate))
	end
	return table.concat(parts, ",")
end

--[[
	Calculates the rate name based on the current rate value.
]]
local function getRateName(rate: number): string
	if rate >= 2.5 then
		return "HYPER INFLATION"
	elseif rate >= 1.5 then
		return "STONKS"
	elseif rate <= 0.7 then
		return "CRASH"
	else
		return "NORMAL"
	end
end

--[[
	Calculates a new rate using random walk with mean reversion.
	Creates realistic stock-like movement patterns.
]]
local function calculateNewRate(): number
	-- Base random change
	local baseChange = (math.random() - 0.5) * 2 * CONFIG.BASE_VOLATILITY
	
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
	Updates the market with a new rate.
]]
local function updateMarket()
	-- Calculate new rate
	local newRate = calculateNewRate()
	currentRate = newRate
	
	-- Update history (add to end, remove from start if needed)
	table.insert(history, newRate)
	if #history > CONFIG.MAX_HISTORY then
		table.remove(history, 1)
	end
	
	-- Get rate name for display
	local rateName = getRateName(newRate)
	
	-- Update Attributes for clients
	stockMarketFolder:SetAttribute("CurrentRate", newRate)
	stockMarketFolder:SetAttribute("RateName", rateName)
	stockMarketFolder:SetAttribute("RateHistory", serializeHistory())
	stockMarketFolder:SetAttribute("LastUpdate", os.time())
	stockMarketFolder:SetAttribute("UpdateInterval", CONFIG.UPDATE_INTERVAL)
	
	--print(string.format("📈 Stock Market: %.2fx (%s)", newRate, rateName))
end

-- Initialize Attributes
stockMarketFolder:SetAttribute("CurrentRate", currentRate)
stockMarketFolder:SetAttribute("RateName", getRateName(currentRate))
stockMarketFolder:SetAttribute("RateHistory", serializeHistory())
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

print("✓ StockMarketManager initialized (Continuous Range: 0.5x - 3.0x)")
