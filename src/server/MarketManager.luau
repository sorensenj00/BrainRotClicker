--[[
	MarketManager Server Module
	
	Handles selling items from backpack for money at market prices.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

local stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket", 10) or ReplicatedStorage

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local ItemSoldEvent = RemoteEvents:FindFirstChild("ItemSold") or Instance.new("RemoteEvent")
ItemSoldEvent.Name = "ItemSold"
ItemSoldEvent.Parent = RemoteEvents

local SellItemFunction = RemoteFunctions:FindFirstChild("SellItem") or Instance.new("RemoteFunction")
SellItemFunction.Name = "SellItem"
SellItemFunction.Parent = RemoteFunctions

local SellAllFunction = RemoteFunctions:FindFirstChild("SellAll") or Instance.new("RemoteFunction")
SellAllFunction.Name = "SellAll"
SellAllFunction.Parent = RemoteFunctions

local GetMarketPricesFunction = RemoteFunctions:FindFirstChild("GetMarketPrices") or Instance.new("RemoteFunction")
GetMarketPricesFunction.Name = "GetMarketPrices"
GetMarketPricesFunction.Parent = RemoteFunctions

local CONFIG = {
	MARKET_POSITION = Vector3.new(0, 32, -60),
	MARKET_SIZE = Vector3.new(20, 15, 20),
	ENDGAME_EARNINGS_THRESHOLD = 1000000000, -- $1B total money to lose welfare protection
}

local MarketManager = {}
local Services = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getItemSector(itemId)
	if not itemId then return nil end
	
	-- Scan BrainrotItems to find which model produces this item
	for modelName, mapping in pairs(ItemConfig.BrainrotItems) do
		if mapping.tier1 == itemId or mapping.tier2 == itemId or 
		   mapping.tier3 == itemId or mapping.tier4 == itemId then
			return ItemConfig.GetSector(modelName)
		end
	end
	return "Neutral"
end

--[[
	Determines if a player is "endgame" (no welfare protection).
	Endgame = total money exceeds threshold.
	Simple check — can be replaced with a more nuanced metric later.
]]
local function isEndgame(player)
	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	if m and m.Value >= CONFIG.ENDGAME_EARNINGS_THRESHOLD then
		return true
	end
	return false
end

--[[
	Gets the appropriate market rate for a player+item combo.
	- Endgame players get the true MarketRate (can be very low)
	- New players get the BailoutRate (welfare-protected floor)
]]
local function getPlayerRate(player, itemId)
	local SM = rawget(Services, "StockMarketManager")
	if not SM then
		return stockMarketFolder:GetAttribute("CurrentRate") or 1.0
	end
	
	local sector = getItemSector(itemId)
	if not sector or sector == "Neutral" then
		return SM.GetSectorRate("Food") or 1.0
	end
	
	if isEndgame(player) then
		return SM.GetSectorRate(sector) or 1.0
	else
		return SM.GetBailoutRate(sector) or 1.0
	end
end

-- Legacy compat: returns MarketRate (endgame/true rate)
local function getMarketRate(itemId)
	local SM = rawget(Services, "StockMarketManager")
	if itemId and SM then
		local sector = getItemSector(itemId)
		if sector and sector ~= "Neutral" then 
			return SM.GetSectorRate(sector) or 1.0 
		end
	end
	return stockMarketFolder:GetAttribute("CurrentRate") or 1.0
end

local function getItemPrice(itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	return math.floor((info.basePrice or 1) * getMarketRate(itemId))
end

-- Player-specific price (uses welfare check)
local function getPlayerItemPrice(player, itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	return math.floor((info.basePrice or 1) * getPlayerRate(player, itemId))
end

-- Report sold volume to StockMarketManager for global price influence
local function reportSalesVolume(itemId, count)
	local SM = rawget(Services, "StockMarketManager")
	if SM and SM.AddSalesVolume then
		local sector = getItemSector(itemId)
		if sector and sector ~= "Neutral" then
			SM.AddSalesVolume(sector, count)
		end
	end
end

local function createMarketBuilding()
	local mainIsland = workspace:FindFirstChild("MainIsland")
	if mainIsland and mainIsland:FindFirstChild("MarketBuilding") then return end
	
	local building = Instance.new("Part")
	building.Name = "MarketBuilding"
	building.Size = CONFIG.MARKET_SIZE
	building.Position = CONFIG.MARKET_POSITION
	building.Anchored = true
	building.BrickColor = BrickColor.new("Deep orange")
	building.Material = Enum.Material.SmoothPlastic
	
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0,200,0,60)
	bb.StudsOffset = Vector3.new(0,12,0)
	bb.Parent = building
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1,0,1,0)
	lbl.BackgroundTransparency = 0.2
	lbl.BackgroundColor3 = Color3.fromRGB(30,30,40)
	lbl.Text = "🏪 MARKET"
	lbl.TextColor3 = Color3.fromRGB(255,200,50)
	lbl.TextScaled=true
	lbl.Parent=bb
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0,12)
	
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Open Market"
	pp.ObjectText = "Market Terminal"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = building
	
	if mainIsland then building.Parent = mainIsland else building.Parent = workspace end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function MarketManager.Init(services)
	print("   MarketManager (Module) - Initializing")
	Services = services or {}
	
	task.spawn(function()
		task.wait(3)
		createMarketBuilding() -- Wait for MainIsland
	end)
	
	SellItemFunction.OnServerInvoke = function(p, id, c) return MarketManager.SellItem(p, id, c) end
	SellAllFunction.OnServerInvoke = function(p) return MarketManager.SellAll(p) end
	GetMarketPricesFunction.OnServerInvoke = function(p) return MarketManager.GetAllPrices(p), getMarketRate() end

	print("✓ MarketManager Initialized")
end

function MarketManager.SellItem(player, itemId, count)
	local ISM = rawget(Services, "ItemStorageManager")
	if not ISM then return 0, 0 end
	
	local bp = ISM.GetBackpackContents(player)
	local avail = bp[itemId] or 0
	if avail <= 0 then return 0,0 end
	
	local toSell = math.min(count or 1, avail)
	local price = getPlayerItemPrice(player, itemId) -- Welfare-aware price
	local total = toSell * price
	
	local removed = ISM.RemoveFromBackpack(player, itemId, toSell)
	if removed <= 0 then return 0,0 end
	
	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	if m then m.Value += total end
	
	-- Report to global market (influences prices across all servers)
	reportSalesVolume(itemId, removed)
	
	ItemSoldEvent:FireClient(player, itemId, removed, total)
	return removed, total
end

function MarketManager.SellAll(player)
	local ISM = rawget(Services, "ItemStorageManager")
	if not ISM then return 0,0 end
	
	local bp = ISM.GetBackpackContents(player)
	local sold, earned = 0, 0
	
	for id, c in pairs(bp) do
		if c > 0 then
			local s, e = MarketManager.SellItem(player, id, c)
			sold += s; earned += e
		end
	end
	return sold, earned
end

function MarketManager.SellCartContents(player, cartInventory)
	if not cartInventory then return 0, 0 end
	local sold, earned = 0, 0
	
	for itemId, count in pairs(cartInventory) do
		if count > 0 then
			local price = getPlayerItemPrice(player, itemId) -- Welfare-aware price
			local total = count * price
			
			sold += count
			earned += total
			
			-- Report to global market
			reportSalesVolume(itemId, count)
		end
	end
	
	if earned > 0 then
		local ls = player:FindFirstChild("leaderstats")
		local m = ls and ls:FindFirstChild("Money")
		if m then m.Value += earned end
		
		for itemId, count in pairs(cartInventory) do
			if count > 0 then
				local price = getPlayerItemPrice(player, itemId)
				ItemSoldEvent:FireClient(player, itemId, count, count * price)
			end
		end
	end
	
	return sold, earned
end

function MarketManager.GetAllPrices(player)
	local p = {}
	local SM = rawget(Services, "StockMarketManager")
	local endgame = player and isEndgame(player)
	
	for id, info in pairs(ItemConfig.Items) do
		local bp = info.basePrice or 1
		local sector = getItemSector(id)
		local marketRate = 1.0
		local bailoutRate = 1.0
		if sector and SM then 
			marketRate = SM.GetSectorRate(sector) or 1.0 
			bailoutRate = SM.GetBailoutRate(sector) or 1.0
		end
		local effectiveRate = (endgame == true) and marketRate or bailoutRate
		p[id] = {
			basePrice = bp,
			currentPrice = math.floor(bp * effectiveRate),
			marketPrice = math.floor(bp * marketRate),
			bailoutPrice = math.floor(bp * bailoutRate),
			tier = info.tier or 1,
			sector = sector,
			sectorRate = effectiveRate,
			isEndgame = endgame or false,
		}
	end
	return p
end

-- Public helpers
MarketManager.GetItemPrice = getItemPrice
MarketManager.GetPlayerItemPrice = getPlayerItemPrice
MarketManager.GetMarketRate = getMarketRate
MarketManager.IsEndgame = isEndgame

return MarketManager
