--[[
	HFTTerminal Client Script
	
	High-Frequency Trading Terminal — Bloomberg-style 3-column interface.
	Replaces old MarketTerminalUI. Keybind: M
	
	Layout:
	  Left (20%)   — ASSETS (Storage Portfolio)
	  Center (60%) — MARKET BRAIN (Sector Overview / Item Inspector)
	  Right (20%)  — CART STATUS (Logistics)
	
	No selling. Storage → Cart loading only.
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
local LoadFromStorageFunction = RemoteFunctions:WaitForChild("LoadFromStorage")
local LoadMaxFromStorageFunction = RemoteFunctions:WaitForChild("LoadMaxFromStorage")
local GetVehicleInfoFunction = RemoteFunctions:WaitForChild("GetVehicleInfo")
local GetMarketPricesFunction = RemoteFunctions:WaitForChild("GetMarketPrices")

local stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local SparklineRenderer = require(Shared:WaitForChild("SparklineRenderer"))

--------------------------------------------------------------------------------
-- THEME
--------------------------------------------------------------------------------

local C = {
	bg         = Color3.fromRGB(13, 13, 13),
	panel      = Color3.fromRGB(20, 20, 24),
	panelLight = Color3.fromRGB(28, 28, 34),
	border     = Color3.fromRGB(50, 50, 60),
	amber      = Color3.fromRGB(255, 182, 39),
	amberDim   = Color3.fromRGB(180, 130, 30),
	green      = Color3.fromRGB(0, 255, 136),
	greenDim   = Color3.fromRGB(0, 180, 100),
	red        = Color3.fromRGB(255, 51, 51),
	redDim     = Color3.fromRGB(180, 40, 40),
	white      = Color3.fromRGB(230, 230, 235),
	muted      = Color3.fromRGB(110, 110, 125),
	dimBg      = Color3.fromRGB(30, 30, 38),
}

local FONT_MONO = Enum.Font.RobotoMono
local FONT_BOLD = Enum.Font.GothamBold
local FONT_REG  = Enum.Font.Gotham
local CORNER_R  = UDim.new(0, 4)
local PAD       = 10

local SECTORS = {"Food", "Animals", "Entertainment", "Mystic", "Tech", "Action"}
local SECTOR_ICONS = {
	Food = "🍕", Animals = "🐾", Entertainment = "🎵",
	Mystic = "🔮", Tech = "⚡", Action = "💥",
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local isOpen = false
local currentStorage = {}      -- {[itemId] = count}
local storageUsage = 0
local storageCapacity = 0
local currentCart = {}          -- {[itemId] = count}
local cartCapacity = 0
local cartState = "idle"
local marketPrices = {}         -- {[itemId] = {currentPrice, sector, sectorRate, ...}}
local sectorRates = {}          -- {[sector] = rate}
local itemRates = {}            -- {[itemId] = rate}
local sectorHistories = {}      -- {[sector] = {number}}
local sectorSparklines = {}     -- {[sector] = SparklineRenderer}
local inspectedItem = nil       -- itemId currently inspected (nil = sector view)
local transferQty = 1

-- UI refs
local screenGui, mainFrame
local leftScroll, centerFrame, sectorGrid, inspectorFrame, rightScroll
local cartCapBar, cartCapText, cartValueLabel, cartStateLabel
local loadCartBtn, pushCartBtn

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

local function addPadding(inst, p)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, p)
	pad.PaddingBottom = UDim.new(0, p)
	pad.PaddingLeft = UDim.new(0, p)
	pad.PaddingRight = UDim.new(0, p)
	pad.Parent = inst
	return pad
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
	if n >= 1000000 then return string.format("$%.1fM", n / 1000000) end
	if n >= 1000 then return string.format("$%.1fK", n / 1000) end
	return string.format("$%d", n)
end

-- Map item ID → sector using BrainrotItems table
local function getItemSector(itemId)
	for modelName, mapping in pairs(ItemConfig.BrainrotItems) do
		if mapping.tier1 == itemId or mapping.tier2 == itemId
			or mapping.tier3 == itemId or mapping.tier4 == itemId then
			return ItemConfig.GetSector(modelName)
		end
	end
	-- Fallback: check server-cached data
	local pd = marketPrices[itemId]
	if pd and pd.sector then return pd.sector end
	return "Neutral"
end

-- Get live rate for an item (prefers individual item rate, falls back to sector)
local function getItemRate(itemId)
	-- If we have an individual rate, use it
	if itemRates[itemId] then return itemRates[itemId] end
	
	-- Fallback to sector rate
	local sector = getItemSector(itemId)
	return sectorRates[sector] or 1.0
end

-- Compute live market price for an item (basePrice × rate)
local function getLivePrice(itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	local rate = getItemRate(itemId)
	return math.floor((info.basePrice or 1) * rate)
end

local function getTrendForItem(itemId)
	return getItemRate(itemId)
end

local function parseSectorRates()
	local raw = stockMarketFolder:GetAttribute("SectorRates")
	if not raw then return end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and decoded then
		for sector, rate in pairs(decoded) do
			sectorRates[sector] = rate
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
	mainFrame.Size = UDim2.new(1, -40, 1, -80)
	mainFrame.Position = UDim2.new(0, 20, 0, 50)
	mainFrame.BackgroundColor3 = C.bg
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui
	addCorner(mainFrame)
	addStroke(mainFrame, C.border, 2)

	-- Top bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 36)
	topBar.BackgroundColor3 = C.panel
	topBar.BorderSizePixel = 0
	topBar.Parent = mainFrame
	addCorner(topBar)

	-- Title
	makeLabel(topBar, {
		Name = "Title", Text = "⚡ HFT TERMINAL v3.1",
		Color = C.amber, Font = FONT_BOLD, Size = 15,
		UDim2Size = UDim2.new(0, 300, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
	})

	-- Clock / market status
	local statusLabel = makeLabel(topBar, {
		Name = "Status", Text = "● MARKET LIVE",
		Color = C.green, Font = FONT_MONO, Size = 12,
		UDim2Size = UDim2.new(0, 200, 1, 0),
		Position = UDim2.new(0.5, -100, 0, 0),
		XAlign = Enum.TextXAlignment.Center,
	})

	-- Rate name
	makeLabel(topBar, {
		Name = "RateName", Text = "",
		Color = C.muted, Font = FONT_MONO, Size = 11,
		UDim2Size = UDim2.new(0, 200, 1, 0),
		Position = UDim2.new(1, -260, 0, 0),
		XAlign = Enum.TextXAlignment.Right,
	})

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Size = UDim2.new(0, 30, 0, 24)
	closeBtn.Position = UDim2.new(1, -40, 0, 6)
	closeBtn.BackgroundColor3 = C.red
	closeBtn.BackgroundTransparency = 0.5
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = C.white
	closeBtn.TextSize = 14
	closeBtn.Font = FONT_BOLD
	closeBtn.Parent = topBar
	addCorner(closeBtn)

	-- Content area (below top bar)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -PAD*2, 1, -36 - PAD)
	content.Position = UDim2.new(0, PAD, 0, 36 + PAD/2)
	content.BackgroundTransparency = 1
	content.Parent = mainFrame

	return content, closeBtn, statusLabel
end

--------------------------------------------------------------------------------
-- LEFT COLUMN — ASSETS
--------------------------------------------------------------------------------

local function createLeftColumn(parent)
	local col = Instance.new("Frame")
	col.Name = "LeftColumn"
	col.Size = UDim2.new(0.20, -5, 1, 0)
	col.Position = UDim2.new(0, 0, 0, 0)
	col.BackgroundColor3 = C.panel
	col.BorderSizePixel = 0
	col.Parent = parent
	addCorner(col)
	addStroke(col)

	-- Header
	makeLabel(col, {
		Name = "Header", Text = "📊 ASSETS",
		Color = C.amber, Font = FONT_BOLD, Size = 13,
		UDim2Size = UDim2.new(1, -10, 0, 28),
		Position = UDim2.new(0, 8, 0, 6),
	})

	-- Storage capacity mini-bar
	local capFrame = Instance.new("Frame")
	capFrame.Name = "CapBar"
	capFrame.Size = UDim2.new(1, -16, 0, 12)
	capFrame.Position = UDim2.new(0, 8, 0, 34)
	capFrame.BackgroundColor3 = C.dimBg
	capFrame.BorderSizePixel = 0
	capFrame.Parent = col
	addCorner(capFrame, UDim.new(0, 3))

	local capFill = Instance.new("Frame")
	capFill.Name = "Fill"
	capFill.Size = UDim2.new(0, 0, 1, 0)
	capFill.BackgroundColor3 = C.amber
	capFill.BorderSizePixel = 0
	capFill.Parent = capFrame
	addCorner(capFill, UDim.new(0, 3))

	local capText = makeLabel(capFrame, {
		Name = "Text", Text = "0/0",
		Color = C.white, Font = FONT_MONO, Size = 9,
		UDim2Size = UDim2.new(1, 0, 1, 0),
		XAlign = Enum.TextXAlignment.Center,
	})

	-- Scrolling item list
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "AssetList"
	scroll.Size = UDim2.new(1, -8, 1, -54)
	scroll.Position = UDim2.new(0, 4, 0, 50)
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
	return col, capFill, capText
end

--------------------------------------------------------------------------------
-- CENTER COLUMN — MARKET BRAIN
--------------------------------------------------------------------------------

local function createCenterColumn(parent)
	local col = Instance.new("Frame")
	col.Name = "CenterColumn"
	col.Size = UDim2.new(0.60, -10, 1, 0)
	col.Position = UDim2.new(0.20, 5, 0, 0)
	col.BackgroundColor3 = C.panel
	col.BorderSizePixel = 0
	col.Parent = parent
	addCorner(col)
	addStroke(col)

	-- Header
	makeLabel(col, {
		Name = "Header", Text = "🧠 MARKET BRAIN",
		Color = C.amber, Font = FONT_BOLD, Size = 13,
		UDim2Size = UDim2.new(1, -10, 0, 28),
		Position = UDim2.new(0, 8, 0, 6),
	})

	centerFrame = col

	-- === VIEW A: Sector Overview (6-grid) ===
	local gridContainer = Instance.new("Frame")
	gridContainer.Name = "SectorGrid"
	gridContainer.Size = UDim2.new(1, -16, 1, -42)
	gridContainer.Position = UDim2.new(0, 8, 0, 36)
	gridContainer.BackgroundTransparency = 1
	gridContainer.Parent = col

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.49, 0, 0.32, -4)
	grid.CellPadding = UDim2.new(0.02, 0, 0, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = gridContainer

	sectorGrid = gridContainer

	-- Create 6 sector cards
	for i, sector in ipairs(SECTORS) do
		local card = Instance.new("Frame")
		card.Name = "Sector_" .. sector
		card.BackgroundColor3 = C.panelLight
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.Parent = gridContainer
		addCorner(card)
		addStroke(card)

		local icon = SECTOR_ICONS[sector] or "📈"

		makeLabel(card, {
			Name = "SectorName", Text = icon .. " " .. string.upper(sector),
			Color = C.amber, Font = FONT_BOLD, Size = 14,
			UDim2Size = UDim2.new(1, -10, 0, 22),
			Position = UDim2.new(0, 8, 0, 8),
		})

		makeLabel(card, {
			Name = "Rate", Text = "×1.00",
			Color = C.green, Font = FONT_MONO, Size = 20,
			UDim2Size = UDim2.new(0.45, 0, 0, 24),
			Position = UDim2.new(0, 8, 0, 30),
		})

		makeLabel(card, {
			Name = "Trend", Text = "▲ +0.0%",
			Color = C.green, Font = FONT_MONO, Size = 11,
			UDim2Size = UDim2.new(0.45, 0, 0, 16),
			Position = UDim2.new(0, 8, 0, 54),
		})

		-- Sparkline graph frame (right half of card)
		local graphFrame = Instance.new("Frame")
		graphFrame.Name = "GraphFrame"
		graphFrame.Size = UDim2.new(0.50, -8, 1, -34)
		graphFrame.Position = UDim2.new(0.50, 0, 0, 28)
		graphFrame.BackgroundColor3 = C.bg
		graphFrame.BackgroundTransparency = 0.5
		graphFrame.BorderSizePixel = 0
		graphFrame.Parent = card
		addCorner(graphFrame, UDim.new(0, 3))

		-- Create sparkline renderer
		task.spawn(function()
			local spark = SparklineRenderer.new(graphFrame, Vector2.new(256, 80))
			if spark and not spark.disabled then
				sectorSparklines[sector] = spark
			end
		end)
	end

	-- === VIEW B: Item Inspector ===
	local inspector = Instance.new("Frame")
	inspector.Name = "Inspector"
	inspector.Size = UDim2.new(1, -16, 1, -42)
	inspector.Position = UDim2.new(0, 8, 0, 36)
	inspector.BackgroundTransparency = 1
	inspector.Visible = false
	inspector.Parent = col

	-- Back button
	local backBtn = Instance.new("TextButton")
	backBtn.Name = "BackBtn"
	backBtn.Size = UDim2.new(0, 80, 0, 26)
	backBtn.Position = UDim2.new(0, 0, 0, 0)
	backBtn.BackgroundColor3 = C.dimBg
	backBtn.Text = "← BACK"
	backBtn.TextColor3 = C.amber
	backBtn.TextSize = 11
	backBtn.Font = FONT_BOLD
	backBtn.Parent = inspector
	addCorner(backBtn)
	addStroke(backBtn)

	-- Item title area
	makeLabel(inspector, {
		Name = "ItemName", Text = "",
		Color = C.white, Font = FONT_BOLD, Size = 20,
		UDim2Size = UDim2.new(1, -100, 0, 28),
		Position = UDim2.new(0, 90, 0, 0),
	})

	-- Big price
	makeLabel(inspector, {
		Name = "BigPrice", Text = "$0.00",
		Color = C.amber, Font = FONT_MONO, Size = 42,
		UDim2Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.new(0, 0, 0, 40),
		XAlign = Enum.TextXAlignment.Center,
	})

	-- Sector + trend row
	makeLabel(inspector, {
		Name = "SectorInfo", Text = "SECTOR: — | TREND: —",
		Color = C.muted, Font = FONT_MONO, Size = 13,
		UDim2Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, 95),
		XAlign = Enum.TextXAlignment.Center,
	})

	-- Divider
	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, 0, 0, 1)
	div.Position = UDim2.new(0, 0, 0, 125)
	div.BackgroundColor3 = C.border
	div.BorderSizePixel = 0
	div.Parent = inspector

	-- Quantity controls
	makeLabel(inspector, {
		Name = "QtyLabel", Text = "TRANSFER QTY:",
		Color = C.muted, Font = FONT_BOLD, Size = 12,
		UDim2Size = UDim2.new(0.4, 0, 0, 24),
		Position = UDim2.new(0, 0, 0, 140),
	})

	local qtyFrame = Instance.new("Frame")
	qtyFrame.Name = "QtyControls"
	qtyFrame.Size = UDim2.new(0.6, 0, 0, 32)
	qtyFrame.Position = UDim2.new(0.2, 0, 0, 168)
	qtyFrame.BackgroundTransparency = 1
	qtyFrame.Parent = inspector

	local minusBtn = Instance.new("TextButton")
	minusBtn.Name = "Minus"
	minusBtn.Size = UDim2.new(0, 40, 1, 0)
	minusBtn.BackgroundColor3 = C.dimBg
	minusBtn.Text = "−"
	minusBtn.TextColor3 = C.amber
	minusBtn.TextSize = 18
	minusBtn.Font = FONT_BOLD
	minusBtn.Parent = qtyFrame
	addCorner(minusBtn)
	addStroke(minusBtn)

	local qtyDisplay = makeLabel(qtyFrame, {
		Name = "QtyDisplay", Text = "1",
		Color = C.amber, Font = FONT_MONO, Size = 22,
		UDim2Size = UDim2.new(1, -100, 1, 0),
		Position = UDim2.new(0, 50, 0, 0),
		XAlign = Enum.TextXAlignment.Center,
	})

	local plusBtn = Instance.new("TextButton")
	plusBtn.Name = "Plus"
	plusBtn.Size = UDim2.new(0, 40, 1, 0)
	plusBtn.Position = UDim2.new(1, -40, 0, 0)
	plusBtn.BackgroundColor3 = C.dimBg
	plusBtn.Text = "+"
	plusBtn.TextColor3 = C.amber
	plusBtn.TextSize = 18
	plusBtn.Font = FONT_BOLD
	plusBtn.Parent = qtyFrame
	addCorner(plusBtn)
	addStroke(plusBtn)

	local maxBtn = Instance.new("TextButton")
	maxBtn.Name = "MaxBtn"
	maxBtn.Size = UDim2.new(0, 50, 0, 24)
	maxBtn.Position = UDim2.new(1, -50, 0, 140)
	maxBtn.BackgroundColor3 = C.dimBg
	maxBtn.Text = "MAX"
	maxBtn.TextColor3 = C.amber
	maxBtn.TextSize = 10
	maxBtn.Font = FONT_BOLD
	maxBtn.Parent = inspector
	addCorner(maxBtn)
	addStroke(maxBtn)

	-- Load Cart button (the big action button)
	loadCartBtn = Instance.new("TextButton")
	loadCartBtn.Name = "LoadCartBtn"
	loadCartBtn.Size = UDim2.new(0.7, 0, 0, 44)
	loadCartBtn.Position = UDim2.new(0.15, 0, 1, -55)
	loadCartBtn.BackgroundColor3 = C.green
	loadCartBtn.Text = "LOAD"
	loadCartBtn.TextColor3 = C.bg
	loadCartBtn.TextSize = 20
	loadCartBtn.Font = FONT_BOLD
	loadCartBtn.Parent = inspector
	addCorner(loadCartBtn)
	addStroke(loadCartBtn, C.greenDim, 2)

	inspectorFrame = inspector
	return col, backBtn, minusBtn, plusBtn, maxBtn, qtyDisplay
end

--------------------------------------------------------------------------------
-- RIGHT COLUMN — CART STATUS
--------------------------------------------------------------------------------

local function createRightColumn(parent)
	local col = Instance.new("Frame")
	col.Name = "RightColumn"
	col.Size = UDim2.new(0.20, -5, 1, 0)
	col.Position = UDim2.new(0.80, 5, 0, 0)
	col.BackgroundColor3 = C.panel
	col.BorderSizePixel = 0
	col.Parent = parent
	addCorner(col)
	addStroke(col)

	-- Header
	cartStateLabel = makeLabel(col, {
		Name = "Header", Text = "🛒 CART: IDLE",
		Color = C.green, Font = FONT_BOLD, Size = 13,
		UDim2Size = UDim2.new(1, -10, 0, 28),
		Position = UDim2.new(0, 8, 0, 6),
	})

	-- Vertical capacity bar (visual)
	local barBg = Instance.new("Frame")
	barBg.Name = "CapBarBg"
	barBg.Size = UDim2.new(0, 30, 0.45, 0)
	barBg.Position = UDim2.new(0.5, -15, 0, 38)
	barBg.BackgroundColor3 = C.dimBg
	barBg.BorderSizePixel = 0
	barBg.Parent = col
	addCorner(barBg)
	addStroke(barBg)

	cartCapBar = Instance.new("Frame")
	cartCapBar.Name = "Fill"
	cartCapBar.Size = UDim2.new(1, 0, 0, 0)
	cartCapBar.Position = UDim2.new(0, 0, 1, 0)
	cartCapBar.AnchorPoint = Vector2.new(0, 1)
	cartCapBar.BackgroundColor3 = C.green
	cartCapBar.BorderSizePixel = 0
	cartCapBar.Parent = barBg
	addCorner(cartCapBar)

	-- Capacity text
	cartCapText = makeLabel(col, {
		Name = "CapText", Text = "0 / 0",
		Color = C.amber, Font = FONT_MONO, Size = 13,
		UDim2Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0.45, 44),
		XAlign = Enum.TextXAlignment.Center,
	})

	-- Est Value
	cartValueLabel = makeLabel(col, {
		Name = "EstValue", Text = "Est: $0",
		Color = C.muted, Font = FONT_MONO, Size = 11,
		UDim2Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 0.45, 66),
		XAlign = Enum.TextXAlignment.Center,
	})

	-- Cart items scroll
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "CartItems"
	scroll.Size = UDim2.new(1, -8, 0.35, -10)
	scroll.Position = UDim2.new(0, 4, 0.45, 86)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = C.green
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.BorderSizePixel = 0
	scroll.Parent = col

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.Parent = scroll

	rightScroll = scroll

	-- LOAD MAX button
	local loadMaxBtn = Instance.new("TextButton")
	loadMaxBtn.Name = "LoadMax"
	loadMaxBtn.Size = UDim2.new(1, -16, 0, 30)
	loadMaxBtn.Position = UDim2.new(0, 8, 1, -72)
	loadMaxBtn.BackgroundColor3 = C.amber
	loadMaxBtn.Text = "⚡ LOAD MAX"
	loadMaxBtn.TextColor3 = C.bg
	loadMaxBtn.TextSize = 12
	loadMaxBtn.Font = FONT_BOLD
	loadMaxBtn.Parent = col
	addCorner(loadMaxBtn)

	-- PUSH / RETURN button
	pushCartBtn = Instance.new("TextButton")
	pushCartBtn.Name = "PushCart"
	pushCartBtn.Size = UDim2.new(1, -16, 0, 30)
	pushCartBtn.Position = UDim2.new(0, 8, 1, -38)
	pushCartBtn.BackgroundColor3 = C.green
	pushCartBtn.Text = "🚛 PUSH TO MARKET"
	pushCartBtn.TextColor3 = C.bg
	pushCartBtn.TextSize = 12
	pushCartBtn.Font = FONT_BOLD
	pushCartBtn.Parent = col
	addCorner(pushCartBtn)

	return col, loadMaxBtn
end

--------------------------------------------------------------------------------
-- ASSET ROW (Left Column)
--------------------------------------------------------------------------------

local function createAssetRow(parent, itemId, count)
	local itemInfo = ItemConfig.Items[itemId] or {}
	local rate = getTrendForItem(itemId)
	local trending = rate >= 1.0

	local row = Instance.new("TextButton")
	row.Name = "Asset_" .. itemId
	row.Size = UDim2.new(1, -4, 0, 28)
	row.BackgroundColor3 = C.dimBg
	row.BackgroundTransparency = 0.3
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = false
	row.Parent = parent
	addCorner(row, UDim.new(0, 3))

	-- Icon
	makeLabel(row, {
		Name = "Icon", Text = itemInfo.icon or "?",
		Font = FONT_REG, Size = 12,
		UDim2Size = UDim2.new(0, 18, 1, 0),
		Position = UDim2.new(0, 4, 0, 0),
	})

	-- Name
	makeLabel(row, {
		Name = "Name", Text = itemInfo.displayName or itemId,
		Color = C.white, Font = FONT_REG, Size = 10,
		UDim2Size = UDim2.new(1, -72, 1, 0),
		Position = UDim2.new(0, 22, 0, 0),
	})

	-- Qty
	makeLabel(row, {
		Name = "Qty", Text = "x" .. count,
		Color = C.amber, Font = FONT_MONO, Size = 10,
		UDim2Size = UDim2.new(0, 30, 1, 0),
		Position = UDim2.new(1, -50, 0, 0),
		XAlign = Enum.TextXAlignment.Right,
	})

	-- Trend arrow
	makeLabel(row, {
		Name = "Trend",
		Text = trending and "▲" or "▼",
		Color = trending and C.green or C.red,
		Font = FONT_MONO, Size = 12,
		UDim2Size = UDim2.new(0, 16, 1, 0),
		Position = UDim2.new(1, -18, 0, 0),
	})

	-- Click → inspect
	row.MouseButton1Click:Connect(function()
		inspectedItem = itemId
		transferQty = 1
		showItemInspector(itemId)
	end)

	-- Hover effect
	row.MouseEnter:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.15), {BackgroundTransparency = 0}):Play()
	end)
	row.MouseLeave:Connect(function()
		TweenService:Create(row, TweenInfo.new(0.15), {BackgroundTransparency = 0.3}):Play()
	end)

	return row
end

--------------------------------------------------------------------------------
-- CART ROW (Right Column)
--------------------------------------------------------------------------------

local function createCartRow(parent, itemId, count)
	local itemInfo = ItemConfig.Items[itemId] or {}

	local row = Instance.new("Frame")
	row.Name = "Cart_" .. itemId
	row.Size = UDim2.new(1, -4, 0, 22)
	row.BackgroundColor3 = C.dimBg
	row.BackgroundTransparency = 0.5
	row.BorderSizePixel = 0
	row.Parent = parent
	addCorner(row, UDim.new(0, 3))

	makeLabel(row, {
		Text = (itemInfo.icon or "?") .. " " .. (itemInfo.displayName or itemId),
		Color = C.muted, Font = FONT_REG, Size = 9,
		UDim2Size = UDim2.new(0.7, 0, 1, 0),
		Position = UDim2.new(0, 4, 0, 0),
	})

	makeLabel(row, {
		Text = "x" .. count,
		Color = C.green, Font = FONT_MONO, Size = 10,
		UDim2Size = UDim2.new(0.28, 0, 1, 0),
		Position = UDim2.new(0.7, 0, 0, 0),
		XAlign = Enum.TextXAlignment.Right,
	})

	return row
end

--------------------------------------------------------------------------------
-- VIEW SWITCHING
--------------------------------------------------------------------------------

local function showSectorOverview()
	inspectedItem = nil
	if sectorGrid then sectorGrid.Visible = true end
	if inspectorFrame then inspectorFrame.Visible = false end
end

function showItemInspector(itemId)
	inspectedItem = itemId  -- Set this first
	
	if sectorGrid then sectorGrid.Visible = false end
	if inspectorFrame then inspectorFrame.Visible = true end

	local itemInfo = ItemConfig.Items[itemId] or {}
	local sector = getItemSector(itemId)
	local rate = getItemRate(itemId)
	local price = getLivePrice(itemId)
	local trending = rate >= 1.0

	local nameLabel = inspectorFrame:FindFirstChild("ItemName")
	if nameLabel then nameLabel.Text = (itemInfo.icon or "") .. " " .. (itemInfo.displayName or itemId) end

	local bigPrice = inspectorFrame:FindFirstChild("BigPrice")
	if bigPrice then
		bigPrice.Text = formatMoney(price)
		bigPrice.TextColor3 = C.amber
	end

	local sectorInfo = inspectorFrame:FindFirstChild("SectorInfo")
	if sectorInfo then
		sectorInfo.Text = string.format("SECTOR: %s | RATE: ×%.2f", string.upper(sector), rate)
		sectorInfo.TextColor3 = trending and C.green or C.red
	end

	-- Update load button
	if loadCartBtn then
		loadCartBtn.BackgroundColor3 = trending and C.green or C.amber
		loadCartBtn.Text = "LOAD"
		addStroke(loadCartBtn, trending and C.greenDim or C.amberDim, 2)
	end

	-- Update qty display (find it in the inspector)
	local qtyFrame = inspectorFrame:FindFirstChild("QtyControls")
	if qtyFrame then
		local qtyDisp = qtyFrame:FindFirstChild("QtyDisplay")
		if qtyDisp then qtyDisp.Text = tostring(transferQty) end
	end
end

--------------------------------------------------------------------------------
-- UPDATE FUNCTIONS
--------------------------------------------------------------------------------

local stoCapFill, stoCapText

local function updateLeftColumn()
	if not leftScroll then return end

	-- Clear
	for _, child in leftScroll:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end

	-- Populate
	local sorted = {}
	for itemId, count in pairs(currentStorage) do
		if count > 0 then
			table.insert(sorted, {id = itemId, count = count})
		end
	end
	table.sort(sorted, function(a, b) return a.count > b.count end)

	for _, item in ipairs(sorted) do
		createAssetRow(leftScroll, item.id, item.count)
	end

	-- Update capacity bar
	if stoCapFill then
		local ratio = math.clamp(storageUsage / math.max(1, storageCapacity), 0, 1)
		TweenService:Create(stoCapFill, TweenInfo.new(0.3), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
		local color = ratio > 0.9 and C.red or (ratio > 0.7 and C.amber or C.amber)
		stoCapFill.BackgroundColor3 = color
	end
	if stoCapText then
		stoCapText.Text = string.format("%d/%d", storageUsage, storageCapacity)
	end
end

local function updateRightColumn()
	if not rightScroll then return end

	-- Clear
	for _, child in rightScroll:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end

	-- Populate
	local usage = 0
	local estValue = 0
	for itemId, count in pairs(currentCart) do
		if count > 0 then
			createCartRow(rightScroll, itemId, count)
			usage += count
			local livePrice = getLivePrice(itemId)
			estValue += livePrice * count
		end
	end

	-- Capacity bar
	if cartCapBar then
		local ratio = math.clamp(usage / math.max(1, cartCapacity), 0, 1)
		TweenService:Create(cartCapBar, TweenInfo.new(0.3), {Size = UDim2.new(1, 0, ratio, 0)}):Play()
		cartCapBar.BackgroundColor3 = ratio > 0.9 and C.red or (ratio > 0.7 and C.amber or C.green)
	end
	if cartCapText then
		cartCapText.Text = string.format("%d / %d", usage, cartCapacity)
	end
	if cartValueLabel then
		cartValueLabel.Text = "Est: " .. formatMoney(estValue)
	end

	-- Cart state
	if cartStateLabel then
		local stateMap = {
			idle = {text = "🛒 CART: IDLE", color = C.green},
			rolling_to_market = {text = "🛒 CART: ROLLING...", color = C.amber},
			at_market = {text = "🛒 CART: AT MARKET", color = C.amber},
			rolling_to_plot = {text = "🛒 CART: RETURNING...", color = C.muted},
		}
		local info = stateMap[cartState] or stateMap.idle
		cartStateLabel.Text = info.text
		cartStateLabel.TextColor3 = info.color
	end

	-- Push button state
	if pushCartBtn then
		if cartState == "idle" then
			pushCartBtn.Text = "🚛 PUSH TO MARKET"
			pushCartBtn.BackgroundColor3 = C.green
			pushCartBtn.Visible = usage > 0
		elseif cartState == "at_market" then
			pushCartBtn.Text = "🏠 RETURN CART"
			pushCartBtn.BackgroundColor3 = C.amber
			pushCartBtn.Visible = true
		else
			pushCartBtn.Visible = false
		end
	end
end

local function updateSectorCards()
	parseSectorRates()
	parseSectorHistories()
	if not sectorGrid then return end

	for _, sector in ipairs(SECTORS) do
		local card = sectorGrid:FindFirstChild("Sector_" .. sector)
		if card then
			local rate = sectorRates[sector] or 1.0
			local pctChange = (rate - 1.0) * 100
			local trending = rate >= 1.0

			local rateLabel = card:FindFirstChild("Rate")
			if rateLabel then
				rateLabel.Text = string.format("×%.2f", rate)
				rateLabel.TextColor3 = trending and C.green or C.red
			end

			local trendLabel = card:FindFirstChild("Trend")
			if trendLabel then
				trendLabel.Text = string.format("%s %+.1f%%",
					trending and "▲" or "▼", pctChange)
				trendLabel.TextColor3 = trending and C.green or C.red
			end

			-- Update sparkline graph
			local spark = sectorSparklines[sector]
			local history = sectorHistories[sector]
			if spark and history and #history >= 2 then
				spark:Update(history, C.green, C.red)
			end
		end
	end
end

local function updateTopBar()
	if not mainFrame then return end
	local topBar = mainFrame:FindFirstChild("TopBar")
	if not topBar then return end

	local rateName = topBar:FindFirstChild("RateName")
	if rateName then
		local name = stockMarketFolder:GetAttribute("RateName") or ""
		rateName.Text = name
	end
end

local function refreshAll()
	updateLeftColumn()
	updateRightColumn()
	updateSectorCards()
	updateTopBar()
end

--------------------------------------------------------------------------------
-- OPEN / CLOSE
--------------------------------------------------------------------------------

local function fetchData()
	-- Storage
	local items, total, cap = GetStorageFunction:InvokeServer()
	currentStorage = items or {}
	storageUsage = total or 0
	storageCapacity = Player:GetAttribute("StorageCapacity") or cap or 0

	-- Cart
	local vInfo = GetVehicleInfoFunction:InvokeServer()
	if vInfo then
		currentCart = vInfo.inventory or {}
		cartCapacity = Player:GetAttribute("CartCapacity") or vInfo.capacity or 0
	end

	-- Market prices
	local prices = GetMarketPricesFunction:InvokeServer()
	marketPrices = prices or {}

	-- Sector rates
	parseSectorRates()
end

local function openUI()
	if isOpen then return end
	isOpen = true

	task.spawn(fetchData)
	task.wait(0.1) -- Brief wait for data

	transferQty = 1 -- Reset only on open
	showSectorOverview()
	refreshAll()

	mainFrame.Visible = true
	mainFrame.BackgroundTransparency = 1
	TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 0,
	}):Play()
end

local function closeUI()
	if not isOpen then return end
	isOpen = false

	TweenService:Create(mainFrame, TweenInfo.new(0.15), {
		BackgroundTransparency = 1,
	}):Play()

	task.wait(0.15)
	mainFrame.Visible = false
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	local content, closeBtn, statusLabel = createContainer()
	local leftCol
	leftCol, stoCapFill, stoCapText = createLeftColumn(content)
	local centerCol, backBtn, minusBtn, plusBtn, maxBtn, qtyDisplay = createCenterColumn(content)
	local rightCol, loadMaxBtn = createRightColumn(content)

	-- Close button
	closeBtn.MouseButton1Click:Connect(closeUI)

	-- Back button (inspector → sectors)
	backBtn.MouseButton1Click:Connect(showSectorOverview)

	-- Qty controls
	minusBtn.MouseButton1Click:Connect(function()
		transferQty = math.max(1, transferQty - 1)
		qtyDisplay.Text = tostring(transferQty)
	end)

	plusBtn.MouseButton1Click:Connect(function()
		if inspectedItem then
			local maxQ = currentStorage[inspectedItem] or 0
			transferQty = math.min(maxQ, transferQty + 1)
		else
			transferQty += 1
		end
		qtyDisplay.Text = tostring(transferQty)
	end)

	maxBtn.MouseButton1Click:Connect(function()
		if inspectedItem then
			transferQty = currentStorage[inspectedItem] or 1
			qtyDisplay.Text = tostring(transferQty)
		end
	end)

	-- Load Cart button (inspector)
	loadCartBtn.MouseButton1Click:Connect(function()
		if not inspectedItem then return end
		local qty = transferQty
		if qty <= 0 then return end

		loadCartBtn.Text = "⏳ LOADING..."
		local loaded = LoadFromStorageFunction:InvokeServer(inspectedItem, qty)
		if loaded and loaded > 0 then
			loadCartBtn.Text = "✓ LOADED " .. loaded
			loadCartBtn.BackgroundColor3 = C.green
			task.wait(0.5)
		else
			loadCartBtn.Text = "✗ FAILED"
			loadCartBtn.BackgroundColor3 = C.red
			task.wait(0.5)
		end
		-- Re-show
		if inspectedItem then
			showItemInspector(inspectedItem)
		end
	end)

	-- Load Max button (right col)
	loadMaxBtn.MouseButton1Click:Connect(function()
		loadMaxBtn.Text = "⏳ LOADING..."
		LoadMaxFromStorageFunction:InvokeServer()
		task.wait(0.3)
		loadMaxBtn.Text = "⚡ LOAD MAX"
	end)

	-- Push/Return cart
	pushCartBtn.MouseButton1Click:Connect(function()
		local PushCartRemote = RemoteEvents:FindFirstChild("PushCart")
		local ReturnCartRemote = RemoteEvents:FindFirstChild("ReturnCart")

		if cartState == "idle" and PushCartRemote then
			PushCartRemote:FireServer()
		elseif cartState == "at_market" and ReturnCartRemote then
			ReturnCartRemote:FireServer()
		end
	end)

	-- EVENT HANDLERS
	StorageUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
		currentStorage = items or {}
		storageUsage = total or 0
		storageCapacity = Player:GetAttribute("StorageCapacity") or capacity or 0
		if isOpen then updateLeftColumn() end
	end)

	CartUpdateEvent.OnClientEvent:Connect(function(state, inventory, capacity)
		cartState = state or "idle"
		currentCart = inventory or {}
		cartCapacity = Player:GetAttribute("CartCapacity") or capacity or 0
		if isOpen then updateRightColumn() end
	end)

	stockMarketFolder:GetAttributeChangedSignal("SectorRates"):Connect(function()
		if isOpen then
			parseSectorRates()
			updateSectorCards()
			updateRightColumn()
			-- Refresh inspector if an item is being viewed
			if inspectedItem then
				showItemInspector(inspectedItem)
			end
		end
	end)

	stockMarketFolder:GetAttributeChangedSignal("RateName"):Connect(function()
		if isOpen then updateTopBar() end
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

	print("✓ HFT Terminal initialized — Press M to open")
end

initialize()
