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
}

local MarketManager = {}
local Services = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getItemCategory(itemId)
	for cat, map in pairs(ItemConfig.BrainrotItems) do
		if map.tier1==itemId or map.tier2==itemId or map.tier3==itemId or map.tier4==itemId then return cat end
	end
	return nil
end

local function getMarketRate(itemId)
	local SM = Services.StockMarketManager
	if itemId and SM then
		local cat = getItemCategory(itemId)
		if cat then return SM.GetCategoryRate(cat) or 1.0 end
	end
	return stockMarketFolder:GetAttribute("CurrentRate") or 1.0
end

local function getItemPrice(itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	return math.floor((info.basePrice or 1) * getMarketRate(itemId))
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
	GetMarketPricesFunction.OnServerInvoke = function(p) return MarketManager.GetAllPrices(), getMarketRate() end

	print("✓ MarketManager Initialized")
end

function MarketManager.SellItem(player, itemId, count)
	local ISM = Services.ItemStorageManager
	if not ISM then return 0, 0 end
	
	local bp = ISM.GetBackpackContents(player)
	local avail = bp[itemId] or 0
	if avail <= 0 then return 0,0 end
	
	local toSell = math.min(count or 1, avail)
	local total = toSell * getItemPrice(itemId)
	
	local removed = ISM.RemoveFromBackpack(player, itemId, toSell)
	if removed <= 0 then return 0,0 end
	
	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	if m then m.Value += total end
	
	ItemSoldEvent:FireClient(player, itemId, removed, total)
	return removed, total
end

function MarketManager.SellAll(player)
	local ISM = Services.ItemStorageManager
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

function MarketManager.GetAllPrices()
	local p = {}
	local SM = Services.StockMarketManager
	for id, info in pairs(ItemConfig.Items) do
		local bp = info.basePrice or 1
		local cat = getItemCategory(id)
		local rate = 1.0
		if cat and SM then rate = SM.GetCategoryRate(cat) or 1.0 end
		p[id] = {
			basePrice = bp,
			currentPrice = math.floor(bp * rate),
			tier = info.tier or 1,
			category = cat,
			categoryRate = rate
		}
	end
	return p
end

MarketManager.GetItemPrice = getItemPrice
MarketManager.GetMarketRate = getMarketRate

return MarketManager
