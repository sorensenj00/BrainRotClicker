--[[
	MarketTerminalUI Client Script
	
	Handles the market terminal interface for selling items.
	
	Features:
	- Shows backpack contents
	- Displays current prices with market multiplier
	- Sell individual items or all at once
	- Price updates in real-time
	
	Opens via ProximityPrompt on Market building or M key.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Get player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Wait for remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")

-- Stock market for rate display
local stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket")

-- Market events
local ItemSoldEvent = RemoteEvents:WaitForChild("ItemSold")
local SellItemFunction = RemoteFunctions:WaitForChild("SellItem")
local SellAllFunction = RemoteFunctions:WaitForChild("SellAll")
local GetMarketPricesFunction = RemoteFunctions:WaitForChild("GetMarketPrices")

-- Backpack events
local BackpackUpdatedEvent = RemoteEvents:WaitForChild("BackpackUpdated")
local GetBackpackFunction = RemoteEvents:WaitForChild("GetBackpack")

-- Wait for ItemConfig
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

-- UI Colors
local COLORS = {
	background = Color3.fromRGB(10, 10, 20),
	panel = Color3.fromRGB(20, 25, 35),
	accent = Color3.fromRGB(255, 200, 50),  -- Gold for market
	accentDark = Color3.fromRGB(200, 150, 30),
	text = Color3.fromRGB(255, 255, 255),
	textMuted = Color3.fromRGB(150, 150, 170),
	success = Color3.fromRGB(100, 255, 150),
	profit = Color3.fromRGB(50, 255, 100),
	loss = Color3.fromRGB(255, 80, 80),
	itemBg = Color3.fromRGB(30, 35, 50),
}

-- State
local isOpen = false
local currentBackpack = {}
local backpackTotal = 0
local marketRate = 1.0
local prices = {}

-- UI References
local screenGui = nil
local mainFrame = nil

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createScreenGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MarketTerminalUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = PlayerGui
	return gui
end

local function createMainFrame(parent)
	local frame = Instance.new("Frame")
	frame.Name = "MainFrame"
	frame.Size = UDim2.new(0, 550, 0, 450)
	frame.Position = UDim2.new(0.5, -275, 0.5, -225)
	frame.BackgroundColor3 = COLORS.background
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = frame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.accent
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = frame
	
	return frame
end

local function createHeader(parent)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundColor3 = COLORS.panel
	header.BackgroundTransparency = 0.3
	header.BorderSizePixel = 0
	header.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = header
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.5, 0, 0, 30)
	title.Position = UDim2.new(0, 20, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "🏪 MARKET TERMINAL"
	title.TextColor3 = COLORS.accent
	title.TextSize = 20
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	
	-- Market rate display
	local rateLabel = Instance.new("TextLabel")
	rateLabel.Name = "RateLabel"
	rateLabel.Size = UDim2.new(0.5, -30, 0, 25)
	rateLabel.Position = UDim2.new(0, 20, 0, 35)
	rateLabel.BackgroundTransparency = 1
	rateLabel.Text = "📈 Market Rate: 1.00x"
	rateLabel.TextColor3 = COLORS.success
	rateLabel.TextSize = 14
	rateLabel.Font = Enum.Font.GothamBold
	rateLabel.TextXAlignment = Enum.TextXAlignment.Left
	rateLabel.Parent = header
	
	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -50, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
	closeBtn.BackgroundTransparency = 0.7
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = COLORS.text
	closeBtn.TextSize = 18
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = header
	
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn
	
	closeBtn.MouseButton1Click:Connect(function()
		closeUI()
	end)
	
	return header
end

local function createItemsPanel(parent)
	local panel = Instance.new("Frame")
	panel.Name = "ItemsPanel"
	panel.Size = UDim2.new(1, -20, 1, -130)
	panel.Position = UDim2.new(0, 10, 0, 70)
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.5
	panel.BorderSizePixel = 0
	panel.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	
	-- Header row
	local headerRow = Instance.new("Frame")
	headerRow.Name = "HeaderRow"
	headerRow.Size = UDim2.new(1, -20, 0, 30)
	headerRow.Position = UDim2.new(0, 10, 0, 10)
	headerRow.BackgroundTransparency = 1
	headerRow.Parent = panel
	
	local itemHeader = Instance.new("TextLabel")
	itemHeader.Size = UDim2.new(0.35, 0, 1, 0)
	itemHeader.BackgroundTransparency = 1
	itemHeader.Text = "ITEM"
	itemHeader.TextColor3 = COLORS.textMuted
	itemHeader.TextSize = 12
	itemHeader.Font = Enum.Font.GothamBold
	itemHeader.TextXAlignment = Enum.TextXAlignment.Left
	itemHeader.Parent = headerRow
	
	local qtyHeader = Instance.new("TextLabel")
	qtyHeader.Size = UDim2.new(0.15, 0, 1, 0)
	qtyHeader.Position = UDim2.new(0.35, 0, 0, 0)
	qtyHeader.BackgroundTransparency = 1
	qtyHeader.Text = "QTY"
	qtyHeader.TextColor3 = COLORS.textMuted
	qtyHeader.TextSize = 12
	qtyHeader.Font = Enum.Font.GothamBold
	qtyHeader.Parent = headerRow
	
	local priceHeader = Instance.new("TextLabel")
	priceHeader.Size = UDim2.new(0.2, 0, 1, 0)
	priceHeader.Position = UDim2.new(0.5, 0, 0, 0)
	priceHeader.BackgroundTransparency = 1
	priceHeader.Text = "PRICE"
	priceHeader.TextColor3 = COLORS.textMuted
	priceHeader.TextSize = 12
	priceHeader.Font = Enum.Font.GothamBold
	priceHeader.Parent = headerRow
	
	local totalHeader = Instance.new("TextLabel")
	totalHeader.Size = UDim2.new(0.15, 0, 1, 0)
	totalHeader.Position = UDim2.new(0.7, 0, 0, 0)
	totalHeader.BackgroundTransparency = 1
	totalHeader.Text = "TOTAL"
	totalHeader.TextColor3 = COLORS.textMuted
	totalHeader.TextSize = 12
	totalHeader.Font = Enum.Font.GothamBold
	totalHeader.Parent = headerRow
	
	-- Scroll frame for items
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemList"
	scrollFrame.Size = UDim2.new(1, -20, 1, -50)
	scrollFrame.Position = UDim2.new(0, 10, 0, 45)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLORS.accent
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = panel
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = scrollFrame
	
	return panel
end

local function createBottomBar(parent)
	local bar = Instance.new("Frame")
	bar.Name = "BottomBar"
	bar.Size = UDim2.new(1, -20, 0, 50)
	bar.Position = UDim2.new(0, 10, 1, -55)
	bar.BackgroundColor3 = COLORS.panel
	bar.BackgroundTransparency = 0.3
	bar.BorderSizePixel = 0
	bar.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bar
	
	-- Total value display
	local totalLabel = Instance.new("TextLabel")
	totalLabel.Name = "TotalValue"
	totalLabel.Size = UDim2.new(0.5, -10, 1, 0)
	totalLabel.Position = UDim2.new(0, 15, 0, 0)
	totalLabel.BackgroundTransparency = 1
	totalLabel.Text = "💰 Total Value: $0"
	totalLabel.TextColor3 = COLORS.profit
	totalLabel.TextSize = 18
	totalLabel.Font = Enum.Font.GothamBold
	totalLabel.TextXAlignment = Enum.TextXAlignment.Left
	totalLabel.Parent = bar
	
	-- Sell All button
	local sellAllBtn = Instance.new("TextButton")
	sellAllBtn.Name = "SellAllButton"
	sellAllBtn.Size = UDim2.new(0, 180, 0, 40)
	sellAllBtn.Position = UDim2.new(1, -190, 0.5, -20)
	sellAllBtn.BackgroundColor3 = COLORS.accent
	sellAllBtn.Text = "💰 SELL ALL"
	sellAllBtn.TextColor3 = COLORS.background
	sellAllBtn.TextSize = 16
	sellAllBtn.Font = Enum.Font.GothamBold
	sellAllBtn.Parent = bar
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = sellAllBtn
	
	sellAllBtn.MouseButton1Click:Connect(function()
		local sold, earned = SellAllFunction:InvokeServer()
		if earned > 0 then
			-- Flash the button green
			sellAllBtn.BackgroundColor3 = COLORS.profit
			task.wait(0.3)
			sellAllBtn.BackgroundColor3 = COLORS.accent
		end
	end)
	
	-- Hover effect
	sellAllBtn.MouseEnter:Connect(function()
		TweenService:Create(sellAllBtn, TweenInfo.new(0.2), {BackgroundColor3 = COLORS.accentDark}):Play()
	end)
	
	sellAllBtn.MouseLeave:Connect(function()
		TweenService:Create(sellAllBtn, TweenInfo.new(0.2), {BackgroundColor3 = COLORS.accent}):Play()
	end)
	
	return bar
end

local function createItemRow(parent, itemId, count, price)
	local tierEmoji = {"⚪", "🟡", "🟠", "💎"}
	local itemInfo = ItemConfig.Items[itemId] or {}
	local emoji = tierEmoji[itemInfo.tier or 1] or "⚪"
	local totalValue = count * price
	
	local row = Instance.new("Frame")
	row.Name = "Item_" .. itemId
	row.Size = UDim2.new(1, 0, 0, 36)
	row.BackgroundColor3 = COLORS.itemBg
	row.BackgroundTransparency = 0.4
	row.BorderSizePixel = 0
	row.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = row
	
	-- Item name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.35, 0, 1, 0)
	nameLabel.Position = UDim2.new(0, 10, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = emoji .. " " .. itemId
	nameLabel.TextColor3 = COLORS.text
	nameLabel.TextSize = 13
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = row
	
	-- Quantity
	local qtyLabel = Instance.new("TextLabel")
	qtyLabel.Size = UDim2.new(0.12, 0, 1, 0)
	qtyLabel.Position = UDim2.new(0.35, 0, 0, 0)
	qtyLabel.BackgroundTransparency = 1
	qtyLabel.Text = "x" .. count
	qtyLabel.TextColor3 = COLORS.textMuted
	qtyLabel.TextSize = 13
	qtyLabel.Font = Enum.Font.GothamBold
	qtyLabel.Parent = row
	
	-- Price per item
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Size = UDim2.new(0.18, 0, 1, 0)
	priceLabel.Position = UDim2.new(0.47, 0, 0, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = "$" .. price
	priceLabel.TextColor3 = marketRate >= 1.5 and COLORS.profit or (marketRate <= 0.7 and COLORS.loss or COLORS.text)
	priceLabel.TextSize = 13
	priceLabel.Font = Enum.Font.Gotham
	priceLabel.Parent = row
	
	-- Total value
	local totalLabel = Instance.new("TextLabel")
	totalLabel.Size = UDim2.new(0.15, 0, 1, 0)
	totalLabel.Position = UDim2.new(0.65, 0, 0, 0)
	totalLabel.BackgroundTransparency = 1
	totalLabel.Text = "$" .. totalValue
	totalLabel.TextColor3 = COLORS.profit
	totalLabel.TextSize = 13
	totalLabel.Font = Enum.Font.GothamBold
	totalLabel.Parent = row
	
	-- Sell button
	local sellBtn = Instance.new("TextButton")
	sellBtn.Name = "SellButton"
	sellBtn.Size = UDim2.new(0, 55, 0, 26)
	sellBtn.Position = UDim2.new(1, -65, 0.5, -13)
	sellBtn.BackgroundColor3 = COLORS.accent
	sellBtn.Text = "SELL"
	sellBtn.TextColor3 = COLORS.background
	sellBtn.TextSize = 11
	sellBtn.Font = Enum.Font.GothamBold
	sellBtn.Parent = row
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 5)
	btnCorner.Parent = sellBtn
	
	sellBtn.MouseButton1Click:Connect(function()
		SellItemFunction:InvokeServer(itemId, count)
	end)
	
	return row
end

--------------------------------------------------------------------------------
-- UI UPDATE
--------------------------------------------------------------------------------

local function calculateTotalValue()
	local total = 0
	for itemId, count in pairs(currentBackpack) do
		if count > 0 then
			local itemInfo = ItemConfig.Items[itemId]
			if itemInfo then
				local price = math.floor((itemInfo.basePrice or 1) * marketRate)
				total = total + (price * count)
			end
		end
	end
	return total
end

local function updateUI()
	if not mainFrame then return end
	
	-- Update market rate display
	local header = mainFrame:FindFirstChild("Header")
	if header then
		local rateLabel = header:FindFirstChild("RateLabel")
		if rateLabel then
			local rateColor = marketRate >= 1.5 and COLORS.profit or (marketRate <= 0.7 and COLORS.loss or COLORS.success)
			rateLabel.Text = string.format("📈 Market Rate: %.2fx", marketRate)
			rateLabel.TextColor3 = rateColor
		end
	end
	
	-- Update item list
	local itemsPanel = mainFrame:FindFirstChild("ItemsPanel")
	if itemsPanel then
		local scrollFrame = itemsPanel:FindFirstChild("ItemList")
		if scrollFrame then
			-- Clear existing
			for _, child in scrollFrame:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			
			-- Add items
			for itemId, count in pairs(currentBackpack) do
				if count > 0 then
					local itemInfo = ItemConfig.Items[itemId]
					if itemInfo then
						local price = math.floor((itemInfo.basePrice or 1) * marketRate)
						createItemRow(scrollFrame, itemId, count, price)
					end
				end
			end
		end
	end
	
	-- Update total value
	local bottomBar = mainFrame:FindFirstChild("BottomBar")
	if bottomBar then
		local totalLabel = bottomBar:FindFirstChild("TotalValue")
		if totalLabel then
			local total = calculateTotalValue()
			totalLabel.Text = string.format("💰 Total Value: $%d", total)
		end
	end
end

--------------------------------------------------------------------------------
-- OPEN/CLOSE
--------------------------------------------------------------------------------

local function openUI()
	if isOpen then return end
	isOpen = true
	
	-- Fetch latest data
	local backpackItems, backpackTot, _ = GetBackpackFunction:InvokeServer()
	currentBackpack = backpackItems or {}
	backpackTotal = backpackTot or 0
	
	-- Get market rate
	marketRate = stockMarketFolder:GetAttribute("CurrentRate") or 1.0
	
	-- Update UI
	updateUI()
	
	-- Show with animation
	mainFrame.Visible = true
	mainFrame.Size = UDim2.new(0, 550, 0, 0)
	TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Size = UDim2.new(0, 550, 0, 450)
	}):Play()
end

function closeUI()
	if not isOpen then return end
	isOpen = false
	
	TweenService:Create(mainFrame, TweenInfo.new(0.2), {
		Size = UDim2.new(0, 550, 0, 0)
	}):Play()
	
	task.wait(0.2)
	mainFrame.Visible = false
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

BackpackUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
	currentBackpack = items or {}
	backpackTotal = total or 0
	
	if isOpen then
		updateUI()
	end
end)

ItemSoldEvent.OnClientEvent:Connect(function(itemId, count, earned)
	-- Refresh backpack after sale
	local backpackItems, backpackTot, _ = GetBackpackFunction:InvokeServer()
	currentBackpack = backpackItems or {}
	backpackTotal = backpackTot or 0
	
	if isOpen then
		updateUI()
	end
end)

-- Market rate updates
stockMarketFolder:GetAttributeChangedSignal("CurrentRate"):Connect(function()
	marketRate = stockMarketFolder:GetAttribute("CurrentRate") or 1.0
	if isOpen then
		updateUI()
	end
end)

-- Keyboard toggle (M key)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	
	if input.KeyCode == Enum.KeyCode.M then
		if isOpen then
			closeUI()
		else
			openUI()
		end
	end
end)

-- ProximityPrompt connection
local function setupMarketPrompt()
	-- Wait for market building
	task.spawn(function()
		local mainIsland = workspace:WaitForChild("MainIsland", 30)
		if mainIsland then
			local marketBuilding = mainIsland:WaitForChild("MarketBuilding", 30)
			if marketBuilding then
				local prompt = marketBuilding:FindFirstChild("MarketPrompt")
				if prompt then
					prompt.Triggered:Connect(function()
						openUI()
					end)
					print("MarketTerminalUI: Connected to Market prompt")
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	screenGui = createScreenGui()
	mainFrame = createMainFrame(screenGui)
	createHeader(mainFrame)
	createItemsPanel(mainFrame)
	createBottomBar(mainFrame)
	
	setupMarketPrompt()
	
	print("✓ MarketTerminalUI initialized - Press M to open, or use Market building")
end

initialize()
