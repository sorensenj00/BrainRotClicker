--[[
	MarketManager Server Script
	
	Handles selling items from backpack for money at market prices.
	
	Features:
	- Sell individual items or all at once
	- Uses StockMarketManager multiplier for dynamic pricing
	- Tracks price history for trend indicators
	- Creates Market building on main island
	
	Part of the "Sell a Brainrot" system.
]]

-- Services
local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

-- Wait for StockMarket folder (from StockMarketManager)
local stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket")

-- Constants
local CONFIG = {
	MARKET_POSITION = Vector3.new(0, 32, -60), -- On main island
	MARKET_SIZE = Vector3.new(20, 15, 20),
}

-- Remote events and functions
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not RemoteEvents then
	RemoteEvents = Instance.new("Folder")
	RemoteEvents.Name = "RemoteEvents"
	RemoteEvents.Parent = ReplicatedStorage
end

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions")
if not RemoteFunctions then
	RemoteFunctions = Instance.new("Folder")
	RemoteFunctions.Name = "RemoteFunctions"
	RemoteFunctions.Parent = ReplicatedStorage
end

-- Create events
local ItemSoldEvent = RemoteEvents:FindFirstChild("ItemSold") or Instance.new("RemoteEvent")
ItemSoldEvent.Name = "ItemSold"
ItemSoldEvent.Parent = RemoteEvents

local MarketPricesEvent = RemoteEvents:FindFirstChild("MarketPrices") or Instance.new("RemoteEvent")
MarketPricesEvent.Name = "MarketPrices"
MarketPricesEvent.Parent = RemoteEvents

-- Create functions
local SellItemFunction = RemoteFunctions:FindFirstChild("SellItem") or Instance.new("RemoteFunction")
SellItemFunction.Name = "SellItem"
SellItemFunction.Parent = RemoteFunctions

local SellAllFunction = RemoteFunctions:FindFirstChild("SellAll") or Instance.new("RemoteFunction")
SellAllFunction.Name = "SellAll"
SellAllFunction.Parent = RemoteFunctions

local GetMarketPricesFunction = RemoteFunctions:FindFirstChild("GetMarketPrices") or Instance.new("RemoteFunction")
GetMarketPricesFunction.Name = "GetMarketPrices"
GetMarketPricesFunction.Parent = RemoteFunctions

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Gets the category that produces a given item.
	@param itemId string - The item ID
	@return string? - The category name or nil
]]
local function getItemCategory(itemId: string): string?
	-- Look through all category item mappings to find which produces this item
	for category, mapping in pairs(ItemConfig.BrainrotItems) do
		if mapping.tier1 == itemId or mapping.tier2 == itemId or 
		   mapping.tier3 == itemId or mapping.tier4 == itemId then
			return category
		end
	end
	return nil
end

--[[
	Gets the current market rate multiplier for a specific item.
	Uses the item's producing category rate.
	@param itemId string? - The item ID (optional, returns average if nil)
	@return number - The market rate (0.5x to 3.0x)
]]
local function getMarketRate(itemId: string?): number
	local StockMarketManager = _G.StockMarketManager
	
	if itemId and StockMarketManager then
		local category = getItemCategory(itemId)
		if category then
			return StockMarketManager.GetCategoryRate(category) or 1.0
		end
	end
	
	-- Fallback to attribute-based rate
	return stockMarketFolder:GetAttribute("CurrentRate") or 1.0
end

--[[
	Calculates the sell price for an item using its category's market rate.
	@param itemId string - The item to price
	@return number - The current sell price
]]
local function getItemPrice(itemId)
	local itemInfo = ItemConfig.Items[itemId]
	if not itemInfo then return 0 end
	
	local basePrice = itemInfo.basePrice or 1
	local marketRate = getMarketRate(itemId)
	
	return math.floor(basePrice * marketRate)
end

--[[
	Gets all current market prices for items with category info.
	@return table - { [itemId] = {basePrice, currentPrice, tier, category, categoryRate} }
]]
local function getAllPrices()
	local prices = {}
	local StockMarketManager = _G.StockMarketManager
	
	for itemId, itemInfo in pairs(ItemConfig.Items) do
		local basePrice = itemInfo.basePrice or 1
		local category = getItemCategory(itemId)
		local categoryRate = 1.0
		
		if category and StockMarketManager then
			categoryRate = StockMarketManager.GetCategoryRate(category) or 1.0
		end
		
		prices[itemId] = {
			basePrice = basePrice,
			currentPrice = math.floor(basePrice * categoryRate),
			tier = itemInfo.tier or 1,
			category = category,
			categoryRate = categoryRate,
		}
	end
	
	return prices
end


--------------------------------------------------------------------------------
-- SELLING FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Sells items from a player's backpack.
	@param player Player - The player
	@param itemId string - Item to sell
	@param count number - How many to sell
	@return number, number - Amount sold, money earned
]]
local function sellItem(player, itemId, count)
	local ItemStorageManager = _G.ItemStorageManager
	if not ItemStorageManager then return 0, 0 end
	
	-- Get how many are in backpack
	local backpack = ItemStorageManager.GetBackpackContents(player)
	local available = backpack[itemId] or 0
	
	if available <= 0 then return 0, 0 end
	
	local toSell = math.min(count, available)
	local pricePerItem = getItemPrice(itemId)
	local totalValue = toSell * pricePerItem
	
	-- Remove from backpack
	local removed = ItemStorageManager.RemoveFromBackpack(player, itemId, toSell)
	if removed <= 0 then return 0, 0 end
	
	-- Add money
	local leaderstats = player:FindFirstChild("leaderstats")
	local moneyValue = leaderstats and leaderstats:FindFirstChild("Money")
	
	if moneyValue then
		moneyValue.Value = moneyValue.Value + totalValue
	end
	
	-- Notify client
	ItemSoldEvent:FireClient(player, itemId, removed, totalValue)
	
	print(string.format("💰 %s sold %d x %s for $%d", player.Name, removed, itemId, totalValue))
	
	return removed, totalValue
end

--[[
	Sells all items in a player's backpack.
	@param player Player - The player
	@return number, number - Total items sold, total money earned
]]
local function sellAll(player)
	local ItemStorageManager = _G.ItemStorageManager
	if not ItemStorageManager then return 0, 0 end
	
	local backpack = ItemStorageManager.GetBackpackContents(player)
	local totalSold = 0
	local totalEarned = 0
	
	for itemId, count in pairs(backpack) do
		if count > 0 then
			local sold, earned = sellItem(player, itemId, count)
			totalSold = totalSold + sold
			totalEarned = totalEarned + earned
		end
	end
	
	if totalSold > 0 then
		print(string.format("💰 %s sold all: %d items for $%d total", player.Name, totalSold, totalEarned))
	end
	
	return totalSold, totalEarned
end

--------------------------------------------------------------------------------
-- MARKET BUILDING
--------------------------------------------------------------------------------

local function createMarketBuilding()
	-- Check if already exists
	local mainIsland = workspace:FindFirstChild("MainIsland")
	if mainIsland and mainIsland:FindFirstChild("MarketBuilding") then
		return mainIsland:FindFirstChild("MarketBuilding")
	end
	
	-- Create building
	local building = Instance.new("Part")
	building.Name = "MarketBuilding"
	building.Size = CONFIG.MARKET_SIZE
	building.Position = CONFIG.MARKET_POSITION
	building.Anchored = true
	building.CanCollide = true
	building.Material = Enum.Material.SmoothPlastic
	building.BrickColor = BrickColor.new("Deep orange")
	
	-- Billboard
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MarketSign"
	billboard.Size = UDim2.new(0, 200, 0, 60)
	billboard.StudsOffset = Vector3.new(0, 12, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = building
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	label.BackgroundTransparency = 0.2
	label.Text = "🏪 MARKET"
	label.TextColor3 = Color3.fromRGB(255, 200, 50)
	label.TextSize = 28
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label
	
	-- Proximity prompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MarketPrompt"
	prompt.ActionText = "Open Market"
	prompt.ObjectText = "Market Terminal"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 15
	prompt.Parent = building
	
	-- Parent to main island or workspace
	if mainIsland then
		building.Parent = mainIsland
	else
		building.Parent = workspace
	end
	
	print("✓ MarketBuilding created at " .. tostring(CONFIG.MARKET_POSITION))
	
	return building
end

--------------------------------------------------------------------------------
-- REMOTE FUNCTION HANDLERS
--------------------------------------------------------------------------------

SellItemFunction.OnServerInvoke = function(player, itemId, count)
	return sellItem(player, itemId, count or 1)
end

SellAllFunction.OnServerInvoke = function(player)
	return sellAll(player)
end

GetMarketPricesFunction.OnServerInvoke = function(player)
	return getAllPrices(), getMarketRate()
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   MarketManager - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Wait for main island
	task.wait(3)
	
	-- Create market building
	createMarketBuilding()
	
	print("✓ MarketManager initialized")
	print("  • Market rate: " .. string.format("%.2fx", getMarketRate()))
	print("═══════════════════════════════════════════")
end

initialize()

-- Export API for other scripts
_G.MarketManager = {
	SellItem = sellItem,
	SellAll = sellAll,
	GetItemPrice = getItemPrice,
	GetAllPrices = getAllPrices,
	GetMarketRate = getMarketRate,
}
