--[[
	StockMarketManager Server Module
	
	Handles the dynamic brainrot stock market.
	
	CONVERTED TO MODULE SCRIPT
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local CONFIG = {
	UPDATE_INTERVAL = 20,
	MIN_RATE = 0.5,
	MAX_RATE = 3.0,
	STARTING_RATE = 1.0,
	BASE_VOLATILITY = 0.25,
	SPIKE_CHANCE = 0.10,
	SPIKE_MULTIPLIER = 2.5,
	MEAN_REVERSION = 0.05,
	MAX_HISTORY = 60,
}

local CATEGORY_VOLATILITY = {
	Skibidi = 0.25, Bombardiro = 0.45, Tralalero = 0.30,
	BrrBrr = 0.35, Sigma = 0.40, Mewer = 0.20,
}
local CATEGORIES = {"Skibidi", "Bombardiro", "Tralalero", "BrrBrr", "Sigma", "Mewer"}
local CATEGORY_COLORS = {
	Skibidi = {148, 103, 189}, Bombardiro = {255, 127, 14}, Tralalero = {44, 160, 44},
	BrrBrr = {31, 119, 180}, Sigma = {214, 39, 40}, Mewer = {227, 119, 194},
}

local StockMarketManager = {}
local categoryRates = {}
local categoryHistories = {}
local nextUpdate = 0
local stockMarketFolder = nil

--------------------------------------------------------------------------------
-- HELPER
--------------------------------------------------------------------------------

local function serializeHistory(history)
	local parts = {}
	for _, rate in ipairs(history) do table.insert(parts, string.format("%.3f", rate)) end
	return table.concat(parts, ",")
end

local function serializeCategoryRates()
	local t = {}
	for c, r in pairs(categoryRates) do t[c] = math.floor(r * 1000) / 1000 end
	return HttpService:JSONEncode(t)
end

local function serializeCategoryHistories()
	local t = {}
	for c, h in pairs(categoryHistories) do t[c] = serializeHistory(h) end
	return HttpService:JSONEncode(t)
end

local function getGlobalRateName()
	local sum = 0; for _, r in pairs(categoryRates) do sum += r end
	local avg = sum / #CATEGORIES
	if avg >= 2.5 then return "HYPER INFLATION"
	elseif avg >= 1.5 then return "STONKS"
	elseif avg <= 0.7 then return "CRASH"
	else return "NORMAL" end
end

local function calculateNewRate(category)
	local current = categoryRates[category]
	local vol = CATEGORY_VOLATILITY[category] or CONFIG.BASE_VOLATILITY
	local base = (math.random() - 0.5) * 2 * vol
	if math.random() < CONFIG.SPIKE_CHANCE then base *= CONFIG.SPIKE_MULTIPLIER end
	local rev = (CONFIG.STARTING_RATE - current) * CONFIG.MEAN_REVERSION
	return math.clamp(current + base + rev, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
end

local function updateMarket()
	for _, cat in ipairs(CATEGORIES) do
		local nr = calculateNewRate(cat)
		categoryRates[cat] = nr
		table.insert(categoryHistories[cat], nr)
		if #categoryHistories[cat] > CONFIG.MAX_HISTORY then table.remove(categoryHistories[cat], 1) end
	end
	
	local sum = 0; for _, r in pairs(categoryRates) do sum += r end
	local avgRate = sum / #CATEGORIES
	
	stockMarketFolder:SetAttribute("CategoryRates", serializeCategoryRates())
	stockMarketFolder:SetAttribute("CategoryHistories", serializeCategoryHistories())
	stockMarketFolder:SetAttribute("Categories", HttpService:JSONEncode(CATEGORIES))
	stockMarketFolder:SetAttribute("CategoryColors", HttpService:JSONEncode(CATEGORY_COLORS))
	
	stockMarketFolder:SetAttribute("CurrentRate", avgRate)
	stockMarketFolder:SetAttribute("RateName", getGlobalRateName())
	stockMarketFolder:SetAttribute("RateHistory", serializeHistory(categoryHistories.Skibidi))
	stockMarketFolder:SetAttribute("LastUpdate", os.time())
	stockMarketFolder:SetAttribute("UpdateInterval", CONFIG.UPDATE_INTERVAL)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function StockMarketManager.Init()
	print("   StockMarketManager (Module) - Initializing")
	
	stockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket") or Instance.new("Folder")
	stockMarketFolder.Name = "StockMarket"
	stockMarketFolder.Parent = ReplicatedStorage
	
	for _, cat in ipairs(CATEGORIES) do
		categoryRates[cat] = CONFIG.STARTING_RATE
		categoryHistories[cat] = {}
		for i = 1, CONFIG.MAX_HISTORY do table.insert(categoryHistories[cat], CONFIG.STARTING_RATE) end
	end
	
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
	
	nextUpdate = os.time() + CONFIG.UPDATE_INTERVAL
	stockMarketFolder:SetAttribute("NextUpdate", nextUpdate)
	
	RunService.Heartbeat:Connect(function()
		local now = os.time()
		if now >= nextUpdate then
			updateMarket()
			nextUpdate = now + CONFIG.UPDATE_INTERVAL
			stockMarketFolder:SetAttribute("NextUpdate", nextUpdate)
		end
	end)
	
	print("✓ StockMarketManager Initialized")
end

StockMarketManager.GetCategoryRate = function(c) return categoryRates[c] or 1.0 end
StockMarketManager.GetAllCategoryRates = function() return table.clone(categoryRates) end
StockMarketManager.GetCategories = function() return CATEGORIES end

return StockMarketManager
