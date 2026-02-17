--[[
	StockMarketManager Server Module
	
	Handles the dynamic brainrot stock market.
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

local SECTOR_VOLATILITY = {
	Food = 0.20, Animals = 0.25, Entertainment = 0.30,
	Mystic = 0.40, Tech = 0.35, Action = 0.45,
}
local SECTORS = {"Food", "Animals", "Entertainment", "Mystic", "Tech", "Action"}
local SECTOR_COLORS = {
	Food = {227, 119, 194}, Animals = {44, 160, 44}, Entertainment = {255, 127, 14},
	Mystic = {148, 103, 189}, Tech = {31, 119, 180}, Action = {214, 39, 40},
}

local StockMarketManager = {}
local Services = {}
local sectorRates = {}
local sectorHistories = {}
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

local function calculateNewRate(sector)
	local current = sectorRates[sector]
	local vol = SECTOR_VOLATILITY[sector] or CONFIG.BASE_VOLATILITY
	local base = (math.random() - 0.5) * 2 * vol
	if math.random() < CONFIG.SPIKE_CHANCE then base *= CONFIG.SPIKE_MULTIPLIER end
	local rev = (CONFIG.STARTING_RATE - current) * CONFIG.MEAN_REVERSION
	return math.clamp(current + base + rev, CONFIG.MIN_RATE, CONFIG.MAX_RATE)
end

local function updateMarket()
	for _, cat in ipairs(SECTORS) do
		local nr = calculateNewRate(cat)
		sectorRates[cat] = nr
		table.insert(sectorHistories[cat], nr)
		if #sectorHistories[cat] > CONFIG.MAX_HISTORY then table.remove(sectorHistories[cat], 1) end
	end
	
	local sum = 0; for _, r in pairs(sectorRates) do sum += r end
	local avgRate = sum / #SECTORS
	
	stockMarketFolder:SetAttribute("SectorRates", serializeSectorRates())
	stockMarketFolder:SetAttribute("SectorHistories", serializeSectorHistories())
	stockMarketFolder:SetAttribute("Sectors", HttpService:JSONEncode(SECTORS))
	stockMarketFolder:SetAttribute("SectorColors", HttpService:JSONEncode(SECTOR_COLORS))
	
	stockMarketFolder:SetAttribute("CurrentRate", avgRate)
	stockMarketFolder:SetAttribute("RateName", getGlobalRateName())
	stockMarketFolder:SetAttribute("RateHistory", serializeHistory(sectorHistories.Food))
	stockMarketFolder:SetAttribute("LastUpdate", os.time())
	stockMarketFolder:SetAttribute("UpdateInterval", CONFIG.UPDATE_INTERVAL)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function StockMarketManager.Init(services)
	print("   StockMarketManager (Module) - Initializing")
	Services = services or {}
	
	stockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket") or Instance.new("Folder")
	stockMarketFolder.Name = "StockMarket"
	stockMarketFolder.Parent = ReplicatedStorage
	
	for _, cat in ipairs(SECTORS) do
		sectorRates[cat] = CONFIG.STARTING_RATE
		sectorHistories[cat] = {}
		for i = 1, CONFIG.MAX_HISTORY do table.insert(sectorHistories[cat], CONFIG.STARTING_RATE) end
	end
	
	stockMarketFolder:SetAttribute("Sectors", HttpService:JSONEncode(SECTORS))
	stockMarketFolder:SetAttribute("SectorColors", HttpService:JSONEncode(SECTOR_COLORS))
	stockMarketFolder:SetAttribute("SectorRates", serializeSectorRates())
	stockMarketFolder:SetAttribute("SectorHistories", serializeSectorHistories())
	stockMarketFolder:SetAttribute("CurrentRate", CONFIG.STARTING_RATE)
	stockMarketFolder:SetAttribute("RateName", "NORMAL")
	stockMarketFolder:SetAttribute("RateHistory", serializeHistory(sectorHistories.Food))
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

StockMarketManager.GetSectorRate = function(c) return sectorRates[c] or 1.0 end
StockMarketManager.GetAllSectorRates = function() return table.clone(sectorRates) end
StockMarketManager.GetSectors = function() return SECTORS end

return StockMarketManager
