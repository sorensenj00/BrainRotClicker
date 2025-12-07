--[[
	StockMarketManager Server Script
	
	Handles the dynamic "Sauce" economy.
	- Updates global market rate every 30 seconds
	- Manages RNG for crashes and hyper inflation
	- Replicates rate to clients via Attributes on ReplicatedStorage
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
-- Players service will be used for future sound broadcasting

-- Configuration
local CONFIG = {
	UPDATE_INTERVAL = 30, -- Seconds between updates
	
	-- Rate Definitions
	RATES = {
		CRASH = { multiplier = 0.5, chance = 0.15, name = "CRASH", color = Color3.fromRGB(255, 50, 50) },
		NORMAL = { multiplier = 1.0, chance = 0.60, name = "NORMAL", color = Color3.fromRGB(255, 255, 255) },
		STONKS = { multiplier = 1.5, chance = 0.20, name = "STONKS", color = Color3.fromRGB(50, 255, 50) },
		HYPER = { multiplier = 3.0, chance = 0.05, name = "HYPER INFLATION", color = Color3.fromRGB(255, 215, 0) },
	},
	
	SOUNDS = {
		CRASH = "rbxassetid://15656647153", -- Womp Womp (Placeholder ID)
		HYPER = "rbxassetid://138081500",   -- Cha-ching (Placeholder)
	}
}

-- State
local nextUpdate = 0
local history = {}
local MAX_HISTORY = 10

-- Setup ReplicatedStorage container
local stockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket")
if not stockMarketFolder then
	stockMarketFolder = Instance.new("Folder")
	stockMarketFolder.Name = "StockMarket"
	stockMarketFolder.Parent = ReplicatedStorage
end

-- Initialize Attributes
if not stockMarketFolder:GetAttribute("CurrentRate") then
	stockMarketFolder:SetAttribute("CurrentRate", 1.0)
	stockMarketFolder:SetAttribute("RateName", "NORMAL")
	stockMarketFolder:SetAttribute("NextUpdate", 0)
end

--[[
	Selects a new rate based on chances.
]]
local function rollNewRate()
	local roll = math.random()
	local cumulative = 0
	
	-- Sort keys to ensure deterministic order (or just hardcode check order)
	local checkOrder = {"HYPER", "STONKS", "CRASH", "NORMAL"}
	
	for _, key in ipairs(checkOrder) do
		local data = CONFIG.RATES[key]
		cumulative = cumulative + data.chance
		if roll <= cumulative then
			return data
		end
	end
	
	return CONFIG.RATES.NORMAL
end

--[[
	Updates the market.
]]
local function updateMarket()
	local newRateData = rollNewRate()
	
	-- Update Attributes
	stockMarketFolder:SetAttribute("CurrentRate", newRateData.multiplier)
	stockMarketFolder:SetAttribute("RateName", newRateData.name)
	stockMarketFolder:SetAttribute("LastUpdate", os.time())
	
	-- Update History (store as JSON string or just simple string for now)
	table.insert(history, 1, newRateData.multiplier)
	if #history > MAX_HISTORY then
		table.remove(history)
	end
	-- We could serialize history to an attribute if clients need the graph
	-- For now, let's just keep it simple.
	
	print(string.format("📈 Stock Market Update: %s (x%.1f)", newRateData.name, newRateData.multiplier))
	
	-- Play global sounds based on event
	if newRateData.name == "CRASH" then
		-- In a real game, fire a remote to play sound for all
		-- For now, we'll rely on client listening to attribute change
	elseif newRateData.name == "HYPER INFLATION" then
		-- Hype sound
	end
end

-- Main Loop
RunService.Heartbeat:Connect(function(dt)
	local now = os.time()
	if now >= nextUpdate then
		updateMarket()
		nextUpdate = now + CONFIG.UPDATE_INTERVAL
		stockMarketFolder:SetAttribute("NextUpdate", nextUpdate)
	end
end)

-- Initial update
updateMarket()
