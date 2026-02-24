--[[
	HFTTerminal Client Script (v4.0)
	
	High-Frequency Trading Terminal — 2-column Bloomberg-style interface.
	Replaces old 3-column layout. Keybind: M
	
	Layout:
	  Left (40%)   — PORTFOLIO (Storage Holdings, Cash, Portfolio Value)
	  Right (60%)  — INSPECTOR & TRADING (Item detail, Local/Global prices,
	                 Arbitrage alerts, BUY/SELL with quantity multipliers)
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")

local StorageUpdatedEvent = RemoteEvents:WaitForChild("StorageUpdated")
local CartUpdateEvent = RemoteEvents:WaitForChild("CartUpdate")
local GetStorageFunction = RemoteFunctions:WaitForChild("GetStorage")
local GetMarketPricesFunction = RemoteFunctions:WaitForChild("GetMarketPrices")
local GetCartInfoFunction = RemoteFunctions:WaitForChild("GetCartInfo")
local BuyToCartFunction = RemoteFunctions:WaitForChild("BuyToCart")
local SellFromCartFunction = RemoteFunctions:WaitForChild("SellFromCart")

local stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local MarketConfig = require(Shared:WaitForChild("MarketConfig"))
local SparklineRenderer = require(Shared:WaitForChild("SparklineRenderer"))

--------------------------------------------------------------------------------
-- THEME
--------------------------------------------------------------------------------

local C = {
	bg         = Color3.fromRGB(10, 10, 14),
	panel      = Color3.fromRGB(18, 18, 24),
	panelLight = Color3.fromRGB(26, 26, 34),
	card       = Color3.fromRGB(22, 22, 30),
	border     = Color3.fromRGB(45, 45, 58),
	amber      = Color3.fromRGB(255, 182, 39),
	amberDim   = Color3.fromRGB(180, 130, 30),
	green      = Color3.fromRGB(0, 255, 136),
	greenDim   = Color3.fromRGB(0, 180, 100),
	greenBg    = Color3.fromRGB(15, 50, 35),
	red        = Color3.fromRGB(255, 51, 51),
	redDim     = Color3.fromRGB(180, 40, 40),
	redBg      = Color3.fromRGB(50, 15, 15),
	cyan       = Color3.fromRGB(0, 200, 255),
	white      = Color3.fromRGB(230, 230, 235),
	muted      = Color3.fromRGB(100, 100, 118),
	dimBg      = Color3.fromRGB(30, 30, 40),
	arbFlash   = Color3.fromRGB(255, 215, 0), -- Gold for arbitrage alert
}

local FONT_MONO = Enum.Font.RobotoMono
local FONT_BOLD = Enum.Font.GothamBold
local FONT_REG  = Enum.Font.Gotham
local CORNER_R  = UDim.new(0, 5)
local PAD       = 10

local MAX_BUY = MarketConfig.CONFIG.MAX_BUY_PER_TRANSACTION or 100
local ARB_THRESHOLD = MarketConfig.CONFIG.ARBITRAGE_ALERT_THRESHOLD or 0.15

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local isOpen = false
local currentStorage = {}       -- {[itemId] = count} (storage silo, for reference)
local storageUsage = 0
local storageCapacity = 0
local cartInventory = {}        -- {[itemId] = count} (what's in the cart)
local cartState = "idle"        -- idle, rolling_to_market, at_market, rolling_to_plot
local cartCapacity = 200
local cartItemCount = 0
local globalItemRates = {}      -- {[itemId] = globalRate}
local localItemRates = {}       -- {[itemId] = localRate}
local sectorRates = {}          -- {[sector] = rate}
local itemHistories = {}        -- {[itemId] = {number}}
local sectorHistories = {}      -- {[sector] = {number}}
local inspectedItem = nil       -- Currently selected item for trading
local selectedQty = 1           -- Current quantity multiplier

-- UI refs
local screenGui, mainFrame
local leftScroll, _rightPanel
local stoCapFill, stoCapText
local cartStatusBanner

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function addCorner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or CORNER_R
	c.Parent = inst
	return c
end

local function addStroke(inst, color, thick)
	local s = Instance.new("UIStroke")
	s.Color = color or C.border
	s.Thickness = thick or 1
	s.Transparency = 0.3
	s.Parent = inst
	return s
end

local function makeLabel(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = props.Color or C.white
	l.Font = props.Font or FONT_REG
	l.TextSize = props.Size or 14
	l.TextXAlignment = props.XAlign or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = props.Text or ""
	l.Name = props.Name or "Label"
	if props.UDim2Size then l.Size = props.UDim2Size end
	if props.Position then l.Position = props.Position end
	l.Parent = parent
	return l
end

local function formatMoney(n)
	if n >= 1e9 then return string.format("$%.2fB", n / 1e9) end
	if n >= 1e6 then return string.format("$%.1fM", n / 1e6) end
	if n >= 1000 then return string.format("$%.1fK", n / 1000) end
	return string.format("$%d", n)
end

local function getItemSector(itemId)
	for modelName, mapping in pairs(ItemConfig.BrainrotItems) do
		if mapping.tier1 == itemId or mapping.tier2 == itemId
			or mapping.tier3 == itemId or mapping.tier4 == itemId then
			return ItemConfig.GetSector(modelName)
		end
	end
	return "Neutral"
end

local function getLocalRate(itemId)
	return localItemRates[itemId] or globalItemRates[itemId] or 1.0
end

local function getGlobalRate(itemId)
	return globalItemRates[itemId] or 1.0
end

local function getLocalPrice(itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	return math.max(1, math.floor((info.basePrice or 1) * getLocalRate(itemId)))
end

local function getGlobalPrice(itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	return math.max(1, math.floor((info.basePrice or 1) * getGlobalRate(itemId)))
end

local function isArbOpportunity(itemId)
	local local_ = getLocalRate(itemId)
	local global = getGlobalRate(itemId)
	if global == 0 then return false end
	local deviation = math.abs(local_ - global) / global
	return deviation > ARB_THRESHOLD
end

local function getPlayerMoney()
	local ls = Player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	return m and m.Value or 0
end

-- Data parsing
local function parseSectorRates()
	local raw = stockMarketFolder:GetAttribute("SectorRates")
	if not raw then return end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and decoded then
		for sector, rate in pairs(decoded) do sectorRates[sector] = rate end
	end
end

local function parseGlobalItemRates()
	local raw = stockMarketFolder:GetAttribute("ItemRates")
	if not raw then return end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and decoded then
		for itemId, rate in pairs(decoded) do
			globalItemRates[itemId] = rate
			-- Build history
			if not itemHistories[itemId] then
				itemHistories[itemId] = {}
				for _=1, 20 do table.insert(itemHistories[itemId], rate) end
			end
			table.insert(itemHistories[itemId], rate)
			if #itemHistories[itemId] > 30 then
				table.remove(itemHistories[itemId], 1)
			end
		end
	end
end

local function parseLocalItemRates()
	local raw = stockMarketFolder:GetAttribute("LocalItemRates")
	if not raw then return end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and decoded then
		for itemId, rate in pairs(decoded) do
			localItemRates[itemId] = rate
		end
	end
end

local function parseSectorHistories()
	local raw = stockMarketFolder:GetAttribute("SectorHistories")
	if not raw then return end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or not decoded then return end
	for sector, histStr in pairs(decoded) do
		if type(histStr) == "string" then
			local nums = {}
			for val in string.gmatch(histStr, "([^,]+)") do
				table.insert(nums, tonumber(val) or 1.0)
			end
			sectorHistories[sector] = nums
		end
	end
end

local function decodeItems(encoded)
	if type(encoded) ~= "table" then return encoded end
	local success, IC = pcall(function() return require(Shared:WaitForChild("ItemConfig")) end)
	if not success or not IC or not IC.SHORT_TO_ID then return encoded end
	local decoded = {}
	for k, count in pairs(encoded) do
		local shortId = tonumber(k)
		if shortId and IC.SHORT_TO_ID[shortId] then
			decoded[IC.SHORT_TO_ID[shortId]] = count
		else
			decoded[k] = count
		end
	end
	return decoded
end

--------------------------------------------------------------------------------
-- MAIN CONTAINER
--------------------------------------------------------------------------------

local function createContainer()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HFTTerminal"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10
	screenGui.Parent = PlayerGui

	mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(1, -60, 1, -100)
	mainFrame.Position = UDim2.new(0, 30, 0, 55)
	mainFrame.BackgroundColor3 = C.bg
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui
	addCorner(mainFrame, UDim.new(0, 8))
	addStroke(mainFrame, C.border, 2)

	-- Top bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 38)
	topBar.BackgroundColor3 = C.panel
	topBar.BorderSizePixel = 0
	topBar.Parent = mainFrame
	addCorner(topBar, UDim.new(0, 8))

	makeLabel(topBar, {
		Name = "Title", Text = "⚡ HFT TERMINAL v4.0",
		Color = C.amber, Font = FONT_BOLD, Size = 15,
		UDim2Size = UDim2.new(0, 300, 1, 0),
		Position = UDim2.new(0, 14, 0, 0),
	})

	local statusLabel = makeLabel(topBar, {
		Name = "Status", Text = "● MARKET LIVE",
		Color = C.green, Font = FONT_MONO, Size = 12,
		UDim2Size = UDim2.new(0, 200, 1, 0),
		Position = UDim2.new(0.5, -100, 0, 0),
		XAlign = Enum.TextXAlignment.Center,
	})

	makeLabel(topBar, {
		Name = "RateName", Text = "",
		Color = C.muted, Font = FONT_MONO, Size = 11,
		UDim2Size = UDim2.new(0, 200, 1, 0),
		Position = UDim2.new(1, -260, 0, 0),
		XAlign = Enum.TextXAlignment.Right,
	})

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Size = UDim2.new(0, 32, 0, 26)
	closeBtn.Position = UDim2.new(1, -42, 0, 6)
	closeBtn.BackgroundColor3 = C.red
	closeBtn.BackgroundTransparency = 0.4
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = C.white
	closeBtn.TextSize = 14
	closeBtn.Font = FONT_BOLD
	closeBtn.Parent = topBar
	addCorner(closeBtn)

	-- Content area
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -PAD*2, 1, -38 - PAD)
	content.Position = UDim2.new(0, PAD, 0, 38 + PAD/2)
	content.BackgroundTransparency = 1
	content.Parent = mainFrame

	return content, closeBtn, statusLabel
end

--------------------------------------------------------------------------------
-- LEFT COLUMN — PORTFOLIO
--------------------------------------------------------------------------------

local portfolioLiquidLabel, portfolioAssetsLabel

local function createLeftColumn(parent)
	local col = Instance.new("Frame")
	col.Name = "LeftColumn"
	col.Size = UDim2.new(0.38, -6, 1, 0)
	col.Position = UDim2.new(0, 0, 0, 0)
	col.BackgroundColor3 = C.panel
	col.BorderSizePixel = 0
	col.Parent = parent
	addCorner(col)
	addStroke(col)

	-- Header
	makeLabel(col, {
		Name = "Header", Text = "🛒 CART INVENTORY",
		Color = C.amber, Font = FONT_BOLD, Size = 14,
		UDim2Size = UDim2.new(1, -12, 0, 28),
		Position = UDim2.new(0, 8, 0, 6),
	})

	-- Cash + Portfolio value bar
	local statsBar = Instance.new("Frame")
	statsBar.Name = "StatsBar"
	statsBar.Size = UDim2.new(1, -16, 0, 48)
	statsBar.Position = UDim2.new(0, 8, 0, 34)
	statsBar.BackgroundColor3 = C.bg
	statsBar.BorderSizePixel = 0
	statsBar.Parent = col
	addCorner(statsBar, UDim.new(0, 4))

	makeLabel(statsBar, { Name = "LblCash", Text = "LIQUID CASH", Color = C.muted, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(0.5, 0, 0, 13), Position = UDim2.new(0, 8, 0, 5) })
	portfolioLiquidLabel = makeLabel(statsBar, { Name = "ValCash", Text = "$0", Color = C.green, Font = FONT_MONO, Size = 15,
		UDim2Size = UDim2.new(0.5, 0, 0, 22), Position = UDim2.new(0, 8, 0, 20) })

	makeLabel(statsBar, { Name = "LblPortfolio", Text = "PORTFOLIO VALUE", Color = C.muted, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(0.5, -8, 0, 13), Position = UDim2.new(0.5, 0, 0, 5), XAlign = Enum.TextXAlignment.Right })
	portfolioAssetsLabel = makeLabel(statsBar, { Name = "ValPortfolio", Text = "$0", Color = C.amber, Font = FONT_MONO, Size = 15,
		UDim2Size = UDim2.new(0.5, -8, 0, 22), Position = UDim2.new(0.5, 0, 0, 20), XAlign = Enum.TextXAlignment.Right })

	-- Capacity bar (now shows CART capacity)
	makeLabel(col, { Name = "CapLabel", Text = "CART CAPACITY", Color = C.muted, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(1, -16, 0, 12), Position = UDim2.new(0, 8, 0, 88) })

	local capFrame = Instance.new("Frame")
	capFrame.Name = "CapBar"
	capFrame.Size = UDim2.new(1, -16, 0, 14)
	capFrame.Position = UDim2.new(0, 8, 0, 102)
	capFrame.BackgroundColor3 = C.dimBg
	capFrame.BorderSizePixel = 0
	capFrame.Parent = col
	addCorner(capFrame, UDim.new(0, 4))

	local capFill = Instance.new("Frame")
	capFill.Name = "Fill"
	capFill.Size = UDim2.new(0, 0, 1, 0)
	capFill.BackgroundColor3 = C.amber
	capFill.BorderSizePixel = 0
	capFill.Parent = capFrame
	addCorner(capFill, UDim.new(0, 4))

	stoCapText = makeLabel(capFrame, { Name = "Text", Text = "0/0", Color = C.white, Font = FONT_MONO, Size = 9,
		UDim2Size = UDim2.new(1, 0, 1, 0), XAlign = Enum.TextXAlignment.Center })
	stoCapFill = capFill

	-- Cart status banner
	cartStatusBanner = Instance.new("Frame")
	cartStatusBanner.Name = "CartStatusBanner"
	cartStatusBanner.Size = UDim2.new(1, -8, 0, 24)
	cartStatusBanner.Position = UDim2.new(0, 4, 0, 122)
	cartStatusBanner.BackgroundColor3 = C.dimBg
	cartStatusBanner.BorderSizePixel = 0
	cartStatusBanner.Parent = col
	addCorner(cartStatusBanner, UDim.new(0, 4))

	local bannerText = makeLabel(cartStatusBanner, {
		Name = "BannerText", Text = "🔴 CART AT PLOT",
		Color = C.muted, Font = FONT_MONO, Size = 10,
		UDim2Size = UDim2.new(1, 0, 1, 0),
		XAlign = Enum.TextXAlignment.Center,
	})
	bannerText.TextXAlignment = Enum.TextXAlignment.Center

	-- Scrolling cart item list
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "AssetList"
	scroll.Size = UDim2.new(1, -8, 1, -154)
	scroll.Position = UDim2.new(0, 4, 0, 150)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = C.amber
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.BorderSizePixel = 0
	scroll.Parent = col

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.Parent = scroll

	leftScroll = scroll
	return col
end

--------------------------------------------------------------------------------
-- ASSET ROW (Left Column)
--------------------------------------------------------------------------------

local function createAssetRow(parent, itemId, count)
	local itemInfo = ItemConfig.Items[itemId] or {}
	local rate = getLocalRate(itemId)
	local _trending = rate >= 1.0
	local isArb = isArbOpportunity(itemId)

	local row = Instance.new("TextButton")
	row.Name = "Asset_" .. itemId
	row.Size = UDim2.new(1, -4, 0, 30)
	row.BackgroundColor3 = isArb and Color3.fromRGB(40, 35, 15) or C.dimBg
	row.BackgroundTransparency = 0.2
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = false
	row.Parent = parent
	addCorner(row, UDim.new(0, 4))

	-- Icon
	makeLabel(row, { Name = "Icon", Text = itemInfo.icon or "?", Font = FONT_REG, Size = 12,
		UDim2Size = UDim2.new(0, 18, 1, 0), Position = UDim2.new(0, 5, 0, 0) })

	-- Name
	makeLabel(row, { Name = "Name", Text = itemInfo.displayName or itemId, Color = C.white, Font = FONT_REG, Size = 10,
		UDim2Size = UDim2.new(1, -130, 1, 0), Position = UDim2.new(0, 24, 0, 0) })

	-- Qty
	makeLabel(row, { Name = "Qty", Text = "×" .. count, Color = C.amber, Font = FONT_MONO, Size = 10,
		UDim2Size = UDim2.new(0, 35, 1, 0), Position = UDim2.new(1, -100, 0, 0), XAlign = Enum.TextXAlignment.Right })

	-- Price
	makeLabel(row, { Name = "Price", Text = formatMoney(getLocalPrice(itemId)), Color = C.muted, Font = FONT_MONO, Size = 10,
		UDim2Size = UDim2.new(0, 60, 1, 0), Position = UDim2.new(1, -60, 0, 0), XAlign = Enum.TextXAlignment.Right })

	-- Arb indicator
	if isArb then
		makeLabel(row, { Name = "ArbDot", Text = "⚡", Font = FONT_REG, Size = 10,
			Color = C.arbFlash, UDim2Size = UDim2.new(0, 14, 1, 0), Position = UDim2.new(1, -4, 0, 0) })
	end

	row.MouseButton1Click:Connect(function()
		inspectedItem = itemId
		updateInspector()
	end)

	row.MouseEnter:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.12), {BackgroundTransparency = 0}):Play()
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.12), {BackgroundTransparency = 0.2}):Play()
	end)

	return row
end

--------------------------------------------------------------------------------
-- RIGHT COLUMN — INSPECTOR & TRADING
--------------------------------------------------------------------------------

local inspectorFrame
local itemSparkline = nil

local function createRightColumn(parent)
	local col = Instance.new("Frame")
	col.Name = "RightColumn"
	col.Size = UDim2.new(0.62, -6, 1, 0)
	col.Position = UDim2.new(0.38, 6, 0, 0)
	col.BackgroundColor3 = C.panel
	col.BorderSizePixel = 0
	col.Parent = parent
	addCorner(col)
	addStroke(col)

	-- Header
	makeLabel(col, {
		Name = "Header", Text = "🎯 TRADING INSPECTOR",
		Color = C.amber, Font = FONT_BOLD, Size = 14,
		UDim2Size = UDim2.new(1, -12, 0, 28),
		Position = UDim2.new(0, 8, 0, 6),
	})

	-- Inspector content area
	local inspector = Instance.new("Frame")
	inspector.Name = "Inspector"
	inspector.Size = UDim2.new(1, -16, 1, -42)
	inspector.Position = UDim2.new(0, 8, 0, 38)
	inspector.BackgroundTransparency = 1
	inspector.Parent = col

	-- Placeholder text (shown when no item selected)
	makeLabel(inspector, {
		Name = "Placeholder", Text = "← Select an item from your portfolio to inspect",
		Color = C.muted, Font = FONT_REG, Size = 14,
		UDim2Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0.4, 0),
		XAlign = Enum.TextXAlignment.Center,
	})

	-- Item title
	makeLabel(inspector, { Name = "ItemName", Text = "", Color = C.white, Font = FONT_BOLD, Size = 22,
		UDim2Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 0) })

	-- LOCAL PRICE (big)
	makeLabel(inspector, { Name = "LblLocalPrice", Text = "LOCAL PRICE", Color = C.muted, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(0.5, 0, 0, 12), Position = UDim2.new(0, 0, 0, 34) })
	makeLabel(inspector, { Name = "LocalPrice", Text = "$0", Color = C.amber, Font = FONT_MONO, Size = 36,
		UDim2Size = UDim2.new(0.5, 0, 0, 42), Position = UDim2.new(0, 0, 0, 48) })

	-- GLOBAL PRICE (smaller, next to local)
	makeLabel(inspector, { Name = "LblGlobalPrice", Text = "GLOBAL PRICE", Color = C.muted, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(0.3, 0, 0, 12), Position = UDim2.new(0.5, 10, 0, 34) })
	makeLabel(inspector, { Name = "GlobalPrice", Text = "$0", Color = C.cyan, Font = FONT_MONO, Size = 20,
		UDim2Size = UDim2.new(0.3, 0, 0, 24), Position = UDim2.new(0.5, 10, 0, 50) })

	-- Sector + Rate info
	makeLabel(inspector, { Name = "SectorInfo", Text = "", Color = C.muted, Font = FONT_MONO, Size = 11,
		UDim2Size = UDim2.new(0.5, 0, 0, 16), Position = UDim2.new(0.5, 10, 0, 76) })

	-- ARBITRAGE ALERT
	local arbAlert = makeLabel(inspector, {
		Name = "ArbAlert", Text = "⚡ ARBITRAGE OPPORTUNITY ⚡",
		Color = C.arbFlash, Font = FONT_BOLD, Size = 14,
		UDim2Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 96),
		XAlign = Enum.TextXAlignment.Center,
	})
	arbAlert.Visible = false

	-- Sparkline
	local graphFrame = Instance.new("Frame")
	graphFrame.Name = "GraphFrame"
	graphFrame.Size = UDim2.new(1, 0, 0, 100)
	graphFrame.Position = UDim2.new(0, 0, 0, 122)
	graphFrame.BackgroundColor3 = C.bg
	graphFrame.BackgroundTransparency = 0.5
	graphFrame.BorderSizePixel = 0
	graphFrame.Parent = inspector
	addCorner(graphFrame, UDim.new(0, 4))

	task.spawn(function()
		local spark = SparklineRenderer.new(graphFrame, Vector2.new(512, 120))
		if spark and not spark.disabled then
			itemSparkline = spark
		end
	end)

	-- Position info
	makeLabel(inspector, { Name = "LblPosition", Text = "YOUR POSITION", Color = C.amberDim, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 228) })
	makeLabel(inspector, { Name = "PosText", Text = "", Color = C.white, Font = FONT_MONO, Size = 12,
		UDim2Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 242) })

	-- ========== TRADING SECTION ==========
	local tradingFrame = Instance.new("Frame")
	tradingFrame.Name = "TradingFrame"
	tradingFrame.Size = UDim2.new(1, 0, 0, 180)
	tradingFrame.Position = UDim2.new(0, 0, 1, -188)
	tradingFrame.BackgroundTransparency = 1
	tradingFrame.Parent = inspector

	-- Quantity selector
	makeLabel(tradingFrame, { Name = "LblQty", Text = "QUANTITY", Color = C.muted, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 0) })

	local qtyRow = Instance.new("Frame")
	qtyRow.Name = "QtyRow"
	qtyRow.Size = UDim2.new(1, 0, 0, 34)
	qtyRow.Position = UDim2.new(0, 0, 0, 14)
	qtyRow.BackgroundTransparency = 1
	qtyRow.Parent = tradingFrame

	local qtyButtons = {}
	local qtyValues = {1, 10, 50, -1} -- -1 = MAX
	local qtyLabels = {"×1", "×10", "×50", "MAX"}

	for i, val in ipairs(qtyValues) do
		local btn = Instance.new("TextButton")
		btn.Name = "Qty_" .. qtyLabels[i]
		btn.Size = UDim2.new(0.24, -4, 1, 0)
		btn.Position = UDim2.new((i-1) * 0.25, 2, 0, 0)
		btn.BackgroundColor3 = (val == 1) and C.amber or C.dimBg
		btn.Text = qtyLabels[i]
		btn.TextColor3 = (val == 1) and C.bg or C.white
		btn.TextSize = 13
		btn.Font = FONT_BOLD
		btn.AutoButtonColor = false
		btn.Parent = qtyRow
		addCorner(btn, UDim.new(0, 4))

		btn.MouseButton1Click:Connect(function()
			selectedQty = val
			for j, ob in ipairs(qtyButtons) do
				ob.BackgroundColor3 = (qtyValues[j] == val) and C.amber or C.dimBg
				ob.TextColor3 = (qtyValues[j] == val) and C.bg or C.white
			end
			updateInspector()
		end)

		table.insert(qtyButtons, btn)
	end

	-- BUY section
	local buyFrame = Instance.new("Frame")
	buyFrame.Name = "BuyFrame"
	buyFrame.Size = UDim2.new(0.48, 0, 0, 110)
	buyFrame.Position = UDim2.new(0, 0, 0, 54)
	buyFrame.BackgroundColor3 = C.greenBg
	buyFrame.BorderSizePixel = 0
	buyFrame.Parent = tradingFrame
	addCorner(buyFrame)
	addStroke(buyFrame, C.greenDim)

	makeLabel(buyFrame, { Name = "LblBuy", Text = "BUY", Color = C.green, Font = FONT_BOLD, Size = 11,
		UDim2Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 8, 0, 4) })
	makeLabel(buyFrame, { Name = "BuyQty", Text = "0 items", Color = C.white, Font = FONT_MONO, Size = 12,
		UDim2Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 8, 0, 22) })
	makeLabel(buyFrame, { Name = "BuyCost", Text = "Cost: $0", Color = C.muted, Font = FONT_MONO, Size = 11,
		UDim2Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 8, 0, 40) })

	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "BuyBtn"
	buyBtn.Size = UDim2.new(1, -16, 0, 34)
	buyBtn.Position = UDim2.new(0, 8, 1, -42)
	buyBtn.BackgroundColor3 = C.green
	buyBtn.Text = "⬆ BUY"
	buyBtn.TextColor3 = C.bg
	buyBtn.TextSize = 14
	buyBtn.Font = FONT_BOLD
	buyBtn.AutoButtonColor = true
	buyBtn.Parent = buyFrame
	addCorner(buyBtn, UDim.new(0, 4))

	-- SELL section
	local sellFrame = Instance.new("Frame")
	sellFrame.Name = "SellFrame"
	sellFrame.Size = UDim2.new(0.48, 0, 0, 110)
	sellFrame.Position = UDim2.new(0.52, 0, 0, 54)
	sellFrame.BackgroundColor3 = C.redBg
	sellFrame.BorderSizePixel = 0
	sellFrame.Parent = tradingFrame
	addCorner(sellFrame)
	addStroke(sellFrame, C.redDim)

	makeLabel(sellFrame, { Name = "LblSell", Text = "SELL", Color = C.red, Font = FONT_BOLD, Size = 11,
		UDim2Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 8, 0, 4) })
	makeLabel(sellFrame, { Name = "SellQty", Text = "0 items", Color = C.white, Font = FONT_MONO, Size = 12,
		UDim2Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 8, 0, 22) })
	makeLabel(sellFrame, { Name = "SellEarn", Text = "Earn: $0", Color = C.muted, Font = FONT_MONO, Size = 11,
		UDim2Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 8, 0, 40) })

	local sellBtn = Instance.new("TextButton")
	sellBtn.Name = "SellBtn"
	sellBtn.Size = UDim2.new(1, -16, 0, 34)
	sellBtn.Position = UDim2.new(0, 8, 1, -42)
	sellBtn.BackgroundColor3 = C.red
	sellBtn.Text = "⬇ SELL"
	sellBtn.TextColor3 = C.white
	sellBtn.TextSize = 14
	sellBtn.Font = FONT_BOLD
	sellBtn.AutoButtonColor = true
	sellBtn.Parent = sellFrame
	addCorner(sellBtn, UDim.new(0, 4))

	-- Wire BUY button (cart-based)
	buyBtn.MouseButton1Click:Connect(function()
		if not inspectedItem then return end
		if cartState ~= "at_market" then return end
		local qty = getActualBuyQty()
		if qty <= 0 then return end
		buyBtn.Text = "..."
		local bought, _cost = BuyToCartFunction:InvokeServer(inspectedItem, qty)
		buyBtn.Text = "⬆ BUY"
		if bought and bought > 0 then
			task.spawn(fetchData)
			task.wait(0.1)
			updateInspector()
			updateLeftColumn()
		end
	end)

	-- Wire SELL button (cart-based)
	sellBtn.MouseButton1Click:Connect(function()
		if not inspectedItem then return end
		if cartState ~= "at_market" then return end
		local qty = getActualSellQty()
		if qty <= 0 then return end
		sellBtn.Text = "..."
		local sold, _earned = SellFromCartFunction:InvokeServer(inspectedItem, qty)
		sellBtn.Text = "⬇ SELL"
		if sold and sold > 0 then
			task.spawn(fetchData)
			task.wait(0.1)
			updateInspector()
			updateLeftColumn()
		end
	end)

	inspectorFrame = inspector
	_rightPanel = col
	return col
end

--------------------------------------------------------------------------------
-- QUANTITY CALCULATION
--------------------------------------------------------------------------------

function getActualBuyQty()
	if not inspectedItem then return 0 end
	if cartState ~= "at_market" then return 0 end
	local price = getLocalPrice(inspectedItem)
	if price <= 0 then return 0 end
	local money = getPlayerMoney()
	local cartSpace = cartCapacity - cartItemCount

	if selectedQty == -1 then
		local afford = math.floor(money / price)
		return math.min(afford, MAX_BUY, cartSpace)
	else
		local afford = math.floor(money / price)
		return math.min(selectedQty, afford, MAX_BUY, cartSpace)
	end
end

function getActualSellQty()
	if not inspectedItem then return 0 end
	if cartState ~= "at_market" then return 0 end
	local owned = cartInventory[inspectedItem] or 0
	if selectedQty == -1 then
		return owned
	else
		return math.min(selectedQty, owned)
	end
end

--------------------------------------------------------------------------------
-- INSPECTOR UPDATE
--------------------------------------------------------------------------------

function updateInspector()
	if not inspectorFrame then return end

	local placeholder = inspectorFrame:FindFirstChild("Placeholder")
	local itemName = inspectorFrame:FindFirstChild("ItemName")
	local localPriceLabel = inspectorFrame:FindFirstChild("LocalPrice")
	local globalPriceLabel = inspectorFrame:FindFirstChild("GlobalPrice")
	local sectorInfo = inspectorFrame:FindFirstChild("SectorInfo")
	local arbAlert = inspectorFrame:FindFirstChild("ArbAlert")
	local posText = inspectorFrame:FindFirstChild("PosText")
	local tradingFrame = inspectorFrame:FindFirstChild("TradingFrame")

	if not inspectedItem then
		if placeholder then placeholder.Visible = true end
		for _, child in inspectorFrame:GetChildren() do
			if child.Name ~= "Placeholder" and child:IsA("GuiObject") then
				child.Visible = false
			end
		end
		return
	end

	-- Show all inspector elements
	if placeholder then placeholder.Visible = false end
	for _, child in inspectorFrame:GetChildren() do
		if child:IsA("GuiObject") then child.Visible = true end
	end

	local itemInfo = ItemConfig.Items[inspectedItem] or {}
	local localPrice = getLocalPrice(inspectedItem)
	local globalPrice = getGlobalPrice(inspectedItem)
	local localRate = getLocalRate(inspectedItem)
	local sector = getItemSector(inspectedItem)
	local isArb = isArbOpportunity(inspectedItem)
	local owned = cartInventory[inspectedItem] or 0

	-- Item name
	if itemName then
		itemName.Text = (itemInfo.icon or "") .. " " .. (itemInfo.displayName or inspectedItem)
	end

	-- Local price (big, prominent)
	if localPriceLabel then
		localPriceLabel.Text = formatMoney(localPrice)
		localPriceLabel.TextColor3 = C.amber
	end

	-- Global price (smaller)
	if globalPriceLabel then
		globalPriceLabel.Text = formatMoney(globalPrice)
	end

	-- Sector info
	if sectorInfo then
		sectorInfo.Text = string.format("SECTOR: %s | RATE: ×%.2f", string.upper(sector), localRate)
		sectorInfo.TextColor3 = localRate >= 1.0 and C.green or C.red
	end

	-- Arbitrage alert
	if arbAlert then
		arbAlert.Visible = isArb
		if isArb then
			local deviation = ((getLocalRate(inspectedItem) / getGlobalRate(inspectedItem)) - 1) * 100
			local direction = deviation > 0 and "OVERPRICED" or "UNDERPRICED"
			arbAlert.Text = string.format("⚡ ARBITRAGE: %s by %+.1f%% ⚡", direction, deviation)
		end
	end

	-- Position
	if posText then
		local basePrice = itemInfo.basePrice or 1
		local value = owned * localPrice
		posText.Text = string.format("You own: %d  |  Value: %s  |  Base: %s",
			owned, formatMoney(value), formatMoney(basePrice))
	end

	-- Sparkline
	local history = itemHistories[inspectedItem]
	if itemSparkline and history and #history >= 2 then
		itemSparkline:Update(history, C.green, C.red)
	end

	-- Trading section
	if tradingFrame then
		local buyQty = getActualBuyQty()
		local sellQty = getActualSellQty()
		local buyCost = buyQty * localPrice
		local sellEarn = sellQty * localPrice

		local buyQtyLabel = tradingFrame:FindFirstChild("BuyFrame") and tradingFrame.BuyFrame:FindFirstChild("BuyQty")
		local buyCostLabel = tradingFrame:FindFirstChild("BuyFrame") and tradingFrame.BuyFrame:FindFirstChild("BuyCost")
		local sellQtyLabel = tradingFrame:FindFirstChild("SellFrame") and tradingFrame.SellFrame:FindFirstChild("SellQty")
		local sellEarnLabel = tradingFrame:FindFirstChild("SellFrame") and tradingFrame.SellFrame:FindFirstChild("SellEarn")

		if buyQtyLabel then buyQtyLabel.Text = buyQty .. " items" end
		if buyCostLabel then buyCostLabel.Text = "Cost: " .. formatMoney(buyCost) end
		if sellQtyLabel then sellQtyLabel.Text = sellQty .. " items" end
		if sellEarnLabel then sellEarnLabel.Text = "Earn: " .. formatMoney(sellEarn) end
	end
end

--------------------------------------------------------------------------------
-- UPDATE FUNCTIONS
--------------------------------------------------------------------------------

function updateLeftColumn()
	if not leftScroll then return end

	-- Clear
	for _, child in leftScroll:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end

	-- Populate sorted by count (from CART inventory)
	local sorted = {}
	for itemId, count in pairs(cartInventory) do
		if count > 0 then
			table.insert(sorted, {id = itemId, count = count})
		end
	end
	table.sort(sorted, function(a, b) return a.count > b.count end)

	local totalAssetValue = 0
	for _, item in ipairs(sorted) do
		createAssetRow(leftScroll, item.id, item.count)
		totalAssetValue += getLocalPrice(item.id) * item.count
	end

	-- Update cart capacity bar
	if stoCapFill then
		local ratio = math.clamp(cartItemCount / math.max(1, cartCapacity), 0, 1)
		TweenService:Create(stoCapFill, TweenInfo.new(0.3), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
		stoCapFill.BackgroundColor3 = ratio >= 1 and C.red or C.amber
	end
	if stoCapText then
		stoCapText.Text = string.format("%d/%d", cartItemCount, cartCapacity)
	end

	-- Update cart status banner
	if cartStatusBanner then
		local bt = cartStatusBanner:FindFirstChild("BannerText")
		if bt then
			if cartState == "at_market" then
				bt.Text = "🟢 CART AT MARKET — TRADING ENABLED"
				bt.TextColor3 = C.green
				cartStatusBanner.BackgroundColor3 = C.greenBg
			elseif cartState == "rolling_to_market" then
				bt.Text = "🟡 CART EN ROUTE TO MARKET..."
				bt.TextColor3 = C.amber
				cartStatusBanner.BackgroundColor3 = C.dimBg
			elseif cartState == "rolling_to_plot" then
				bt.Text = "🟡 CART RETURNING TO PLOT..."
				bt.TextColor3 = C.amber
				cartStatusBanner.BackgroundColor3 = C.dimBg
			else
				bt.Text = "🔴 CART AT PLOT — SEND TO TRADE"
				bt.TextColor3 = C.red
				cartStatusBanner.BackgroundColor3 = C.redBg
			end
		end
	end

	-- Portfolio values
	if portfolioLiquidLabel then
		portfolioLiquidLabel.Text = formatMoney(getPlayerMoney())
	end
	if portfolioAssetsLabel then
		portfolioAssetsLabel.Text = formatMoney(totalAssetValue)
	end
end

--------------------------------------------------------------------------------
-- DATA FETCHING
--------------------------------------------------------------------------------

function fetchData()
	local items, total, cap = GetStorageFunction:InvokeServer()
	currentStorage = decodeItems(items) or {}
	storageUsage = total or 0
	storageCapacity = Player:GetAttribute("StorageCapacity") or cap or 0

	-- Fetch cart state
	local cartInfo = GetCartInfoFunction:InvokeServer()
	if cartInfo then
		cartState = cartInfo.state or "idle"
		cartInventory = decodeItems(cartInfo.inventory) or {}
		cartCapacity = cartInfo.capacity or 200
		cartItemCount = 0
		for _, c in pairs(cartInventory) do cartItemCount += c end
	end

	local _prices = GetMarketPricesFunction:InvokeServer()

	parseSectorRates()
	parseGlobalItemRates()
	parseLocalItemRates()
	parseSectorHistories()
end

--------------------------------------------------------------------------------
-- OPEN / CLOSE
--------------------------------------------------------------------------------

local function openUI()
	if isOpen then return end
	isOpen = true

	task.spawn(fetchData)
	task.wait(0.1)

	updateLeftColumn()
	updateInspector()

	mainFrame.Visible = true
	mainFrame.BackgroundTransparency = 1
	TweenService:Create(mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 0,
	}):Play()
end

local function closeUI()
	if not isOpen then return end
	isOpen = false

	TweenService:Create(mainFrame, TweenInfo.new(0.12), {
		BackgroundTransparency = 1,
	}):Play()

	task.wait(0.12)
	mainFrame.Visible = false
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	local content, closeBtn, statusLabel = createContainer()
	createLeftColumn(content)
	createRightColumn(content)

	closeBtn.MouseButton1Click:Connect(closeUI)

	-- EVENT HANDLERS
	StorageUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
		items = decodeItems(items)
		currentStorage = items or {}
		storageUsage = total or 0
		storageCapacity = Player:GetAttribute("StorageCapacity") or capacity or 0
	end)

	-- Cart state updates (real-time)
	CartUpdateEvent.OnClientEvent:Connect(function(state, inventory, capacity)
		cartState = state or "idle"
		cartInventory = decodeItems(inventory) or {}
		cartCapacity = capacity or cartCapacity
		cartItemCount = 0
		for _, c in pairs(cartInventory) do cartItemCount += c end
		if isOpen then
			updateLeftColumn()
			updateInspector()
		end
	end)

	stockMarketFolder:GetAttributeChangedSignal("ItemRates"):Connect(function()
		if isOpen then
			parseGlobalItemRates()
			updateLeftColumn()
			if inspectedItem then updateInspector() end
		end
	end)

	stockMarketFolder:GetAttributeChangedSignal("LocalItemRates"):Connect(function()
		if isOpen then
			parseLocalItemRates()
			updateLeftColumn()
			if inspectedItem then updateInspector() end
		end
	end)

	stockMarketFolder:GetAttributeChangedSignal("SectorRates"):Connect(function()
		if isOpen then
			parseSectorRates()
		end
	end)

	stockMarketFolder:GetAttributeChangedSignal("RateName"):Connect(function()
		if not isOpen or not mainFrame then return end
		local topBar = mainFrame:FindFirstChild("TopBar")
		if topBar then
			local rateName = topBar:FindFirstChild("RateName")
			if rateName then rateName.Text = stockMarketFolder:GetAttribute("RateName") or "" end
		end
	end)

	-- HUD Button Toggle
	local stockToggle = ReplicatedStorage:FindFirstChild("StockToggleEvent")
	if not stockToggle then
		stockToggle = Instance.new("BindableEvent")
		stockToggle.Name = "StockToggleEvent"
		stockToggle.Parent = ReplicatedStorage
	end
	stockToggle.Event:Connect(function()
		if isOpen then closeUI() else openUI() end
	end)

	-- M key toggle
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			if input.KeyCode == Enum.KeyCode.M then
				local focus = UserInputService:GetFocusedTextBox()
				if focus then return end
			else
				return
			end
		end

		if input.KeyCode == Enum.KeyCode.M then
			if isOpen then closeUI() else openUI() end
		end
	end)

	-- ProximityPrompt (market building)
	task.spawn(function()
		while true do
			local mainIsland = workspace:FindFirstChild("MainIsland")
			if mainIsland then
				local marketBuilding = mainIsland:FindFirstChild("MarketBuilding")
				if marketBuilding then
					local prompt = marketBuilding:FindFirstChild("MarketPrompt")
					if prompt then
						prompt.Triggered:Connect(function() openUI() end)
						break
					end
				end
			end
			task.wait(1)
		end
	end)

	-- Blinking status indicator
	task.spawn(function()
		local dot = true
		while true do
			if statusLabel and isOpen then
				statusLabel.Text = dot and "● MARKET LIVE" or "○ MARKET LIVE"
				statusLabel.TextColor3 = C.green
			end
			dot = not dot
			task.wait(1)
		end
	end)

	-- Arbitrage flash animation
	task.spawn(function()
		while true do
			if isOpen and inspectorFrame then
				local arbAlert = inspectorFrame:FindFirstChild("ArbAlert")
				if arbAlert and arbAlert.Visible then
					TweenService:Create(arbAlert, TweenInfo.new(0.4), {TextTransparency = 0.5}):Play()
					task.wait(0.4)
					TweenService:Create(arbAlert, TweenInfo.new(0.4), {TextTransparency = 0}):Play()
					task.wait(0.4)
				else
					task.wait(0.5)
				end
			else
				task.wait(1)
			end
		end
	end)

	print("✓ HFT Terminal v4.0 initialized — Press M to open")
end

initialize()
