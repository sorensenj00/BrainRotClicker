--[[
	MarketManager Server Module
	
	Handles selling AND buying items at market prices.
	Uses StockMarketManager's AMM liquidity pools for price discovery.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local MarketConfig = require(Shared:WaitForChild("MarketConfig"))

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

local CartSoldEvent = RemoteEvents:FindFirstChild("CartSold") or Instance.new("RemoteEvent")
CartSoldEvent.Name = "CartSold"
CartSoldEvent.Parent = RemoteEvents

local ItemBoughtEvent = RemoteEvents:FindFirstChild("ItemBought") or Instance.new("RemoteEvent")
ItemBoughtEvent.Name = "ItemBought"
ItemBoughtEvent.Parent = RemoteEvents

local SellItemFunction = RemoteFunctions:FindFirstChild("SellItem") or Instance.new("RemoteFunction")
SellItemFunction.Name = "SellItem"
SellItemFunction.Parent = RemoteFunctions

local SellAllFunction = RemoteFunctions:FindFirstChild("SellAll") or Instance.new("RemoteFunction")
SellAllFunction.Name = "SellAll"
SellAllFunction.Parent = RemoteFunctions

local BuyItemFunction = RemoteFunctions:FindFirstChild("BuyItem") or Instance.new("RemoteFunction")
BuyItemFunction.Name = "BuyItem"
BuyItemFunction.Parent = RemoteFunctions

local BuyToCartFunction = RemoteFunctions:FindFirstChild("BuyToCart") or Instance.new("RemoteFunction")
BuyToCartFunction.Name = "BuyToCart"
BuyToCartFunction.Parent = RemoteFunctions

local SellFromCartFunction = RemoteFunctions:FindFirstChild("SellFromCart") or Instance.new("RemoteFunction")
SellFromCartFunction.Name = "SellFromCart"
SellFromCartFunction.Parent = RemoteFunctions

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
local ITEM_SECTOR_MAP = {}

for modelName, mapping in pairs(ItemConfig.BrainrotItems) do
	local sector = ItemConfig.GetSector(modelName)
	if mapping.tier1 then ITEM_SECTOR_MAP[mapping.tier1] = sector end
	if mapping.tier2 then ITEM_SECTOR_MAP[mapping.tier2] = sector end
	if mapping.tier3 then ITEM_SECTOR_MAP[mapping.tier3] = sector end
	if mapping.tier4 then ITEM_SECTOR_MAP[mapping.tier4] = sector end
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getItemSector(itemId)
	if not itemId then return nil end
	return ITEM_SECTOR_MAP[itemId] or "Neutral"
end

--[[
	Determines if a player is "endgame" (no welfare protection).
	Endgame = total money exceeds threshold.
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
	Gets the SELL rate for a player+item combo (welfare-aware).
	- Endgame players get the true MarketRate (can be very low)
	- New players get the BailoutRate (welfare-protected floor)
]]
local function getPlayerSellRate(player, itemId)
	local SM = rawget(Services, "StockMarketManager")
	if not SM then
		return stockMarketFolder:GetAttribute("CurrentRate") or 1.0
	end
	
	local sector = getItemSector(itemId)
	if not sector or sector == "Neutral" then
		return SM.GetSectorRate("Food") or 1.0
	end
	
	-- Use LOCAL rate for trading (enables arbitrage)
	local localRate = SM.GetLocalItemRate(itemId) or 1.0
	
	if isEndgame(player) then
		return localRate
	else
		-- Welfare floor: ensure noobs never sell below bailout rate
		local bailout = SM.GetBailoutRate(sector) or 1.0
		return math.max(localRate, bailout)
	end
end

--[[
	Gets the BUY rate for an item. ALWAYS uses raw LOCAL market rate.
	NO welfare floor — noobs should be able to buy cheap during crashes.
]]
local function getBuyRate(itemId)
	local SM = rawget(Services, "StockMarketManager")
	if not SM then
		return stockMarketFolder:GetAttribute("CurrentRate") or 1.0
	end
	return SM.GetLocalItemRate(itemId) or 1.0
end

-- Legacy compat: returns MarketRate (endgame/true rate)
local function getMarketRate(itemId)
	local SM = rawget(Services, "StockMarketManager")
	if itemId and SM then
		return SM.GetItemRate(itemId) or 1.0
	end
	return stockMarketFolder:GetAttribute("CurrentRate") or 1.0
end

local function getItemPrice(itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	return math.floor((info.basePrice or 1) * getMarketRate(itemId))
end

-- Player-specific SELL price (uses welfare check + global bonuses)
local function getPlayerSellPrice(player, itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	
	local basePrice = info.basePrice or 1
	local marketRate = getPlayerSellRate(player, itemId)
	
	local multi = 1.0
	local BonusManager = rawget(Services, "BonusManager")
	if BonusManager and BonusManager.GetTotalIncomeMultiplier then
		multi = BonusManager.GetTotalIncomeMultiplier(player)
	end
	
	return math.floor(basePrice * marketRate * multi)
end

-- BUY price: raw market rate, no welfare, no bonus multipliers
local function getBuyPrice(player, itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	
	local basePrice = info.basePrice or 1
	local marketRate = getBuyRate(itemId)
	
	-- FIX: If they are on welfare, they cannot buy cheaper than their bailout sell price
	if player and not isEndgame(player) then
		local sector = getItemSector(itemId)
		local SM = rawget(Services, "StockMarketManager")
		local bailout = SM and SM.GetBailoutRate(sector) or 1.0
		marketRate = math.max(marketRate, bailout)
	end
	
	-- Buy price uses raw market rate — no welfare floor, no income bonuses
	return math.max(1, math.floor(basePrice * marketRate))
end

-- Adjust AMM pool and apply local shock after a trade
local function adjustAMMPool(itemId, deltaItems, deltaCash)
	local SM = rawget(Services, "StockMarketManager")
	if SM and SM.AdjustPool then
		local sector = getItemSector(itemId)
		if sector and sector ~= "Neutral" then
			SM.AdjustPool(sector, deltaItems, deltaCash)
		end
	end
end

local function applyLocalShock(itemId, volume, isBuy)
	local SM = rawget(Services, "StockMarketManager")
	if SM and SM.ApplyLocalShock then
		SM.ApplyLocalShock(itemId, volume, isBuy)
	end
end

-- Admin bypass (mirrors AdminService)
local ADMIN_USER_IDS = { [1340966465] = true }
local IS_STUDIO = RunService:IsStudio()
local function isAdmin(player)
	if IS_STUDIO then return true end
	if ADMIN_USER_IDS[player.UserId] then return true end
	if player.UserId == game.CreatorId then return true end
	return false
end

local function isNearMarket(player)
	if isAdmin(player) then return true end
	
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	
	local distance = (hrp.Position - CONFIG.MARKET_POSITION).Magnitude
	return distance <= 30
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function MarketManager.Init(services)
	print("   MarketManager (Module) - Initializing")
	Services = services or {}
	
	
	SellItemFunction.OnServerInvoke = function(p, id, c) return MarketManager.SellItem(p, id, c) end
	SellAllFunction.OnServerInvoke = function(p) return MarketManager.SellAll(p) end
	BuyItemFunction.OnServerInvoke = function(p, id, c) return MarketManager.BuyItem(p, id, c) end
	BuyToCartFunction.OnServerInvoke = function(p, id, c) return MarketManager.BuyToCart(p, id, c) end
	SellFromCartFunction.OnServerInvoke = function(p, id, c) return MarketManager.SellFromCart(p, id, c) end
	GetMarketPricesFunction.OnServerInvoke = function(p) return MarketManager.GetAllPrices(p), getMarketRate() end

	print("✓ MarketManager Initialized (Buy + Sell)")
end

--[[
	SellItem: Sells items from player's backpack for money.
	Adjusts AMM pool: items enter pool (+), cash leaves pool (-).
]]
function MarketManager.SellItem(player, itemId, count)
	if not isNearMarket(player) then
		warn(player.Name .. " attempted to sell while far away from the market!")
		return 0, 0
	end

	local ISM = rawget(Services, "ItemStorageManager")
	if not ISM then return 0, 0 end
	
	local bp = ISM.GetBackpackContents(player)
	local avail = bp[itemId] or 0
	if avail <= 0 then return 0,0 end
	
	local toSell = math.min(count or 1, avail)
	local price = getPlayerSellPrice(player, itemId) -- Welfare-aware sell price
	local total = toSell * price
	
	local removed = ISM.RemoveFromBackpack(player, itemId, toSell)
	if removed <= 0 then return 0,0 end
	
	local DataService = rawget(Services, "DataService")
	if DataService then
		DataService.AddMoney(player, total)
	end
	
	-- Adjust AMM pool: items enter pool, cash leaves pool
	adjustAMMPool(itemId, removed, -(total * 0.9))
	
	-- Apply local shock: selling crashes local price
	applyLocalShock(itemId, removed, false)
	
	ItemSoldEvent:FireClient(player, itemId, removed, total)
	return removed, total
end

function MarketManager.SellAll(player)
	if not isNearMarket(player) then
		warn(player.Name .. " attempted to SellAll while far away from the market!")
		return 0, 0
	end

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

--[[
	BuyItem: Buys items from the AMM and places them in the player's storage silo.
	
	- Uses RAW market rate (no welfare floor — lets noobs buy cheap during crashes)
	- Capped at MAX_BUY_PER_TRANSACTION for slippage protection
	- Storage-capacity-aware: only deducts cash for items actually stored
	- Adjusts AMM pool: items leave pool (-), cash enters pool (+)
	
	@param player Player
	@param itemId string - The item to buy
	@param count number - How many to buy (will be clamped)
	@return (boughtCount: number, totalCost: number)
]]
function MarketManager.BuyItem(player, itemId, count)
	-- Input validation
	if type(itemId) ~= "string" or type(count) ~= "number" then return 0, 0 end
	if count <= 0 then return 0, 0 end
	
	-- Verify item exists
	local itemInfo = ItemConfig.Items[itemId]
	if not itemInfo then
		warn(player.Name .. " attempted to buy unknown item: " .. tostring(itemId))
		return 0, 0
	end
	
	-- Proximity check
	if not isNearMarket(player) then
		warn(player.Name .. " attempted to buy while far away from the market!")
		return 0, 0
	end
	
	-- Slippage protection: cap per-transaction volume
	local maxBuy = MarketConfig.CONFIG.MAX_BUY_PER_TRANSACTION or 100
	local cappedCount = math.min(math.floor(count), maxBuy)
	if cappedCount <= 0 then return 0, 0 end
	
	-- Get buy price (raw market rate, no welfare floor)
	local unitPrice = getBuyPrice(player, itemId)
	if unitPrice <= 0 then return 0, 0 end
	
	-- Verify and deduct cash
	local DataService = rawget(Services, "DataService")
	if not DataService then return 0, 0 end
	
	-- Check if player can afford at least 1 item
	local playerMoney = DataService.GetMoney(player)
	if playerMoney < unitPrice then return 0, 0 end
	
	-- Adjust count based on what player can actually afford
	local affordableCount = math.min(cappedCount, math.floor(playerMoney / unitPrice))
	if affordableCount <= 0 then return 0, 0 end
	
	local totalCost = affordableCount * unitPrice
	
	-- Deduct the full amount first
	local deducted = DataService.DeductMoney(player, totalCost)
	if not deducted then return 0, 0 end
	
	-- Add items to storage silo (may be less than requested if storage is full)
	local ISM = rawget(Services, "ItemStorageManager")
	if not ISM then
		-- Refund if ISM not available
		DataService.AddMoney(player, totalCost)
		return 0, 0
	end
	
	local actualAdded = ISM.AddToStorage(player, itemId, affordableCount)
	
	-- Handle partial storage: refund excess cash
	if actualAdded < affordableCount then
		local refund = (affordableCount - actualAdded) * unitPrice
		DataService.AddMoney(player, refund)
		totalCost = actualAdded * unitPrice
	end
	
	if actualAdded <= 0 then
		-- Nothing was stored — full refund already happened above
		return 0, 0
	end
	
	-- Adjust AMM pool: items leave pool, cash enters pool
	adjustAMMPool(itemId, -(actualAdded * 0.9), totalCost)
	
	-- Apply local shock: buying spikes local price
	applyLocalShock(itemId, actualAdded, true)
	
	-- Notify client
	ItemBoughtEvent:FireClient(player, itemId, actualAdded, totalCost)
	
	return actualAdded, totalCost
end

--[[
	SellCartContents: Sells a cart's inventory for the player.
	Adjusts AMM pool: items enter pool, cash leaves pool.
]]
function MarketManager.SellCartContents(player, cartInventory)
	if not cartInventory then return 0, 0 end
	local sold, earned = 0, 0
	
	for itemId, count in pairs(cartInventory) do
		if count > 0 then
			local price = getPlayerSellPrice(player, itemId) -- Welfare-aware sell price
			local total = count * price
			
			sold += count
			earned += total
			
			-- Adjust AMM pool: items enter pool, cash leaves pool
			adjustAMMPool(itemId, count, -(total * 0.9))
		end
	end
	
	if earned > 0 then
		local ls = player:FindFirstChild("leaderstats")
		local m = ls and ls:FindFirstChild("Money")
		if m then m.Value += earned end
		
		-- Fire a single aggregate event for the cart instead of per-item spam
		CartSoldEvent:FireClient(player, earned, cartInventory)
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
		local buyRate = 1.0
		if sector and SM then 
			marketRate = SM.GetSectorRate(sector) or 1.0 
			bailoutRate = SM.GetBailoutRate(sector) or 1.0
			buyRate = SM.GetItemRate(id) or 1.0
		end
		local effectiveRate = (endgame == true) and marketRate or bailoutRate
		local effectiveBuyRate = (endgame == true) and buyRate or math.max(buyRate, bailoutRate)
		p[id] = {
			basePrice = bp,
			currentPrice = math.floor(bp * effectiveRate),  -- Sell price (welfare-aware)
			marketPrice = math.floor(bp * marketRate),
			bailoutPrice = math.floor(bp * bailoutRate),
			buyPrice = math.max(1, math.floor(bp * effectiveBuyRate)), -- Buy price (welfare-aware)
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
MarketManager.GetPlayerItemPrice = getPlayerSellPrice
MarketManager.GetBuyPrice = getBuyPrice
MarketManager.GetMarketRate = getMarketRate
MarketManager.IsEndgame = isEndgame

--[[
	ExecuteShortfallBuy: Registers virtual item imports into the AMM.
	Called by ShopManager when auto-buying missing items for a unit purchase.
	
	IMPORTANT: Only the RAW cost enters the AMM pool. The 10% convenience tax
	is burned (deleted from economy) by the caller and must NOT be passed here.
	
	@param shortfallPerItem {[itemId]: {missing: number, rawCost: number}}
]]
function MarketManager.ExecuteShortfallBuy(shortfallPerItem)
	if not shortfallPerItem then return end
	
	for itemId, data in pairs(shortfallPerItem) do
		if data.missing and data.missing > 0 and data.rawCost and data.rawCost > 0 then
			-- Items leave pool (bought), raw cash enters pool
			adjustAMMPool(itemId, -(data.missing * 0.9), data.rawCost)
			
			-- Spike local prices as if a massive buy order happened
			applyLocalShock(itemId, data.missing, true)
		end
	end
end

--[[
	BuyToCart: Buys items from the AMM and places them in the player's cart.
	Cart must be at_market state.
	
	@param player Player
	@param itemId string
	@param count number
	@return (boughtCount, totalCost)
]]
function MarketManager.BuyToCart(player, itemId, count)
	if type(itemId) ~= "string" or type(count) ~= "number" then return 0, 0 end
	if count <= 0 then return 0, 0 end
	
	local itemInfo = ItemConfig.Items[itemId]
	if not itemInfo then
		warn(player.Name .. " attempted to buy unknown item to cart: " .. tostring(itemId))
		return 0, 0
	end
	
	-- Cart must be at market
	local CM = rawget(Services, "CartManager")
	if not CM then return 0, 0 end
	
	local cartData = CM.GetCartState(player)
	if not cartData or cartData.State ~= "at_market" then
		warn(player.Name .. " attempted BuyToCart but cart is not at market")
		return 0, 0
	end
	
	-- Slippage protection
	local maxBuy = MarketConfig.CONFIG.MAX_BUY_PER_TRANSACTION or 100
	local cappedCount = math.min(math.floor(count), maxBuy)
	if cappedCount <= 0 then return 0, 0 end
	
	-- Check cart space
	local spaceRemaining = CM.GetCartSpaceRemaining(player)
	cappedCount = math.min(cappedCount, spaceRemaining)
	if cappedCount <= 0 then return 0, 0 end
	
	-- Get buy price (raw market rate, no welfare floor)
	local unitPrice = getBuyPrice(player, itemId)
	if unitPrice <= 0 then return 0, 0 end
	
	-- Verify and deduct cash
	local DataService = rawget(Services, "DataService")
	if not DataService then return 0, 0 end
	
	local playerMoney = DataService.GetMoney(player)
	if playerMoney < unitPrice then return 0, 0 end
	
	local affordableCount = math.min(cappedCount, math.floor(playerMoney / unitPrice))
	if affordableCount <= 0 then return 0, 0 end
	
	local totalCost = affordableCount * unitPrice
	
	local deducted = DataService.DeductMoney(player, totalCost)
	if not deducted then return 0, 0 end
	
	-- Load items into cart
	local actualLoaded = CM.LoadItemAtMarket(player, itemId, affordableCount)
	
	-- Handle partial: refund excess
	if actualLoaded < affordableCount then
		local refund = (affordableCount - actualLoaded) * unitPrice
		DataService.AddMoney(player, refund)
		totalCost = actualLoaded * unitPrice
	end
	
	if actualLoaded <= 0 then return 0, 0 end
	
	-- Adjust AMM pool: items leave pool, cash enters pool
	adjustAMMPool(itemId, -(actualLoaded * 0.9), totalCost)
	applyLocalShock(itemId, actualLoaded, true)
	
	-- Notify client
	ItemBoughtEvent:FireClient(player, itemId, actualLoaded, totalCost)
	
	return actualLoaded, totalCost
end

--[[
	SellFromCart: Sells items from the player's cart inventory.
	Cart must be at_market state. Uses welfare-aware sell price.
	
	@param player Player
	@param itemId string
	@param count number
	@return (soldCount, totalEarned)
]]
function MarketManager.SellFromCart(player, itemId, count)
	if type(itemId) ~= "string" or type(count) ~= "number" then return 0, 0 end
	if count <= 0 then return 0, 0 end
	
	local CM = rawget(Services, "CartManager")
	if not CM then return 0, 0 end
	
	local cartData = CM.GetCartState(player)
	if not cartData or cartData.State ~= "at_market" then
		warn(player.Name .. " attempted SellFromCart but cart is not at market")
		return 0, 0
	end
	
	-- Check how many are in cart
	local inCart = cartData.Inventory[itemId] or 0
	if inCart <= 0 then return 0, 0 end
	
	local toSell = math.min(count, inCart)
	local price = getPlayerSellPrice(player, itemId)
	local total = toSell * price
	
	-- Remove from cart
	local removed = CM.RemoveFromCartInventory(player, itemId, toSell)
	if removed <= 0 then return 0, 0 end
	
	-- Award money
	local DataService = rawget(Services, "DataService")
	if DataService then
		DataService.AddMoney(player, total)
	end
	
	-- Adjust AMM pool: items enter pool, cash leaves pool
	adjustAMMPool(itemId, removed, -(total * 0.9))
	applyLocalShock(itemId, removed, false)
	
	-- Notify client
	ItemSoldEvent:FireClient(player, itemId, removed, total)
	
	return removed, total
end

return MarketManager
