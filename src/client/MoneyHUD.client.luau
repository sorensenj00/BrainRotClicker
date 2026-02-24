--[[
	MoneyHUD LocalScript (Reworked)
	
	Right-side HUD:
	  • Money + MPS display
	  • Storage bar
	  • "Your Top Holdings" from storage items
	  • "View Full Portfolio" button
	  • Bottom-center action bar with 6 quick-access buttons
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

-- Player reference
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Wait for shared modules and remotes
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local GetOwnershipRemote = RemoteEvents:WaitForChild("GetOwnership")
local OwnershipChangedEvent = RemoteEvents:WaitForChild("OwnershipChanged")
local StorageUpdatedEvent = RemoteEvents:FindFirstChild("StorageUpdated")
local GetStorageFunction = RemoteFunctions:WaitForChild("GetStorage")

-- Brainrots folder for preview
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")

-- Stock Market folder (for sector rates)
local StockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket")

--------------------------------------------------------------------------------
-- UI CONFIGURATION
--------------------------------------------------------------------------------

local UI_CONFIG = {
	-- Panel positioning and size
	PANEL_WIDTH = 250,
	PANEL_HEIGHT = 420,
	PANEL_MARGIN = 24,
	CORNER_RADIUS = 18,
	
	-- Holdings
	MAX_HOLDINGS_ROWS = 5,
	ROW_HEIGHT = 26,
	
	-- Colors
	BACKGROUND_COLOR = Color3.fromRGB(15, 15, 22),
	STROKE_COLOR = Color3.fromRGB(70, 70, 90),
	MONEY_COLOR = Color3.fromRGB(80, 230, 120),
	MPS_COLOR = Color3.fromRGB(160, 160, 180),
	LABEL_COLOR = Color3.fromRGB(130, 130, 150),
	ITEMS_BG_COLOR = Color3.fromRGB(25, 25, 35),
	ITEMS_FILL_COLOR = Color3.fromRGB(60, 160, 255),
	ITEMS_FULL_COLOR = Color3.fromRGB(255, 80, 80),
	
	-- Holdings colors
	HOLDINGS_TITLE_COLOR = Color3.fromRGB(220, 220, 240),
	HOLDINGS_NAME_COLOR = Color3.fromRGB(240, 240, 255),
	HOLDINGS_COUNT_COLOR = Color3.fromRGB(150, 150, 170),
	HOLDINGS_VALUE_COLOR = Color3.fromRGB(80, 230, 120),
	ARROW_UP_COLOR = Color3.fromRGB(60, 200, 100),
	ARROW_DOWN_COLOR = Color3.fromRGB(250, 70, 70),
	
	-- Animation
	TWEEN_TIME = 0.3,
	
	-- Theme
	THEME_BG = Color3.fromRGB(18, 18, 28),
	THEME_STROKE = Color3.fromRGB(90, 90, 120),
	THEME_ACCENT_PURPLE = Color3.fromRGB(120, 80, 220),
	THEME_ACCENT_PINK = Color3.fromRGB(220, 90, 180),
	THEME_ACCENT_GOLD = Color3.fromRGB(250, 190, 60),
	THEME_ACCENT_BLUE = Color3.fromRGB(60, 150, 255),
	THEME_TEXT_PRIMARY = Color3.fromRGB(255, 255, 255),
	THEME_TEXT_SECONDARY = Color3.fromRGB(170, 170, 190),
	
	-- Bottom bar
	BOTTOM_BAR_BTN_SIZE = 48,
	BOTTOM_BAR_PADDING = 12,
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function formatMoney(amount: number): string
	if amount >= 1000000000 then
		return string.format("$%.2fB", amount / 1000000000)
	elseif amount >= 1000000 then
		return string.format("$%.2fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("$%.1fK", amount / 1000)
	else
		return "$" .. tostring(math.floor(amount))
	end
end

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = 0.5
	stroke.Parent = parent
	return stroke
end

-- Get current sector rates from StockMarket folder
local function getSectorRates(): {[string]: number}
	local rates = {}
	if not StockMarketFolder then
		StockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket")
	end
	if StockMarketFolder then
		local ratesStr = StockMarketFolder:GetAttribute("SectorRates")
		if ratesStr then
			local ok, parsed = pcall(function() return HttpService:JSONDecode(ratesStr) end)
			if ok and parsed then
				rates = parsed
			end
		end
	end
	return rates
end

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local StorageItems: {[string]: number} = {} -- Current storage item map
local IsBuildOpen = false
local IsShopOpen = false

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createMoneyHUD(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MoneyHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	----------------------------------------------------------------------
	-- RIGHT PANEL (Money, Storage, Holdings)
	----------------------------------------------------------------------
	local hudPanel = Instance.new("Frame")
	hudPanel.Name = "HUDPanel"
	hudPanel.Size = UDim2.new(0, UI_CONFIG.PANEL_WIDTH, 0, UI_CONFIG.PANEL_HEIGHT)
	hudPanel.Position = UDim2.new(1, -UI_CONFIG.PANEL_WIDTH - UI_CONFIG.PANEL_MARGIN, 0, 60)
	hudPanel.BackgroundColor3 = Color3.new(1, 1, 1) -- Set to white to let gradient color it
	hudPanel.BackgroundTransparency = 0.2
	hudPanel.BorderSizePixel = 0
	hudPanel.Parent = screenGui
	addCorner(hudPanel, UI_CONFIG.CORNER_RADIUS)
	addStroke(hudPanel, UI_CONFIG.THEME_STROKE, 1.5)
	
	local hudGradient = Instance.new("UIGradient")
	hudGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UI_CONFIG.THEME_BG),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 10, 15))
	})
	hudGradient.Rotation = 90
	hudGradient.Parent = hudPanel
	
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.Parent = hudPanel
	
	-- Money icon and label container
	local moneyContainer = Instance.new("Frame")
	moneyContainer.Name = "MoneyContainer"
	moneyContainer.Size = UDim2.new(1, 0, 0, 32)
	moneyContainer.Position = UDim2.new(0, 0, 0, 0)
	moneyContainer.BackgroundTransparency = 1
	moneyContainer.Parent = hudPanel
	
	local moneyIcon = Instance.new("TextLabel")
	moneyIcon.Name = "MoneyIcon"
	moneyIcon.Size = UDim2.new(0, 32, 0, 32)
	moneyIcon.Position = UDim2.new(0, 0, 0, 0)
	moneyIcon.BackgroundTransparency = 1
	moneyIcon.Text = "💰"
	moneyIcon.TextSize = 24
	moneyIcon.Font = Enum.Font.GothamBold
	moneyIcon.Parent = moneyContainer
	
	local moneyLabel = Instance.new("TextLabel")
	moneyLabel.Name = "MoneyLabel"
	moneyLabel.Size = UDim2.new(1, -40, 0, 32)
	moneyLabel.Position = UDim2.new(0, 40, 0, 0)
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.Text = "$0"
	moneyLabel.TextColor3 = UI_CONFIG.MONEY_COLOR
	moneyLabel.TextSize = 28
	moneyLabel.Font = Enum.Font.GothamBold
	moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
	moneyLabel.Parent = moneyContainer
	
	-- Money per second
	local mpsLabel = Instance.new("TextLabel")
	mpsLabel.Name = "MPSLabel"
	mpsLabel.Size = UDim2.new(1, 0, 0, 18)
	mpsLabel.Position = UDim2.new(0, 40, 0, 32)
	mpsLabel.BackgroundTransparency = 1
	mpsLabel.Text = "+$0/s"
	mpsLabel.TextColor3 = UI_CONFIG.MPS_COLOR
	mpsLabel.TextSize = 14
	mpsLabel.Font = Enum.Font.Gotham
	mpsLabel.TextXAlignment = Enum.TextXAlignment.Left
	mpsLabel.Parent = hudPanel
	
	-- Storage Section
	local storageContainer = Instance.new("Frame")
	storageContainer.Name = "ItemsContainer"
	storageContainer.Size = UDim2.new(1, -20, 0, 50)
	storageContainer.Position = UDim2.new(0, 15, 0, 60)
	storageContainer.BackgroundTransparency = 1
	storageContainer.Parent = hudPanel
	
	local storageTitle = Instance.new("TextLabel")
	storageTitle.Name = "ItemsAmount"
	storageTitle.Size = UDim2.new(1, 0, 0, 20)
	storageTitle.BackgroundTransparency = 1
	storageTitle.Text = "📦 ITEMS: 0 / 0"
	storageTitle.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
	storageTitle.TextSize = 12
	storageTitle.Font = Enum.Font.GothamBold
	storageTitle.TextXAlignment = Enum.TextXAlignment.Left
	storageTitle.Parent = storageContainer
	
	local itemsBarBg = Instance.new("Frame")
	itemsBarBg.Name = "ItemsBarBg"
	itemsBarBg.Size = UDim2.new(1, 0, 0, 12)
	itemsBarBg.Position = UDim2.new(0, 0, 0, 25)
	itemsBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	itemsBarBg.BorderSizePixel = 0
	itemsBarBg.Parent = storageContainer
	addCorner(itemsBarBg, 4)
	
	local itemsBarFill = Instance.new("Frame")
	itemsBarFill.Name = "ItemsBarFill"
	itemsBarFill.Size = UDim2.new(0, 0, 1, 0)
	itemsBarFill.BackgroundColor3 = UI_CONFIG.THEME_ACCENT_BLUE
	itemsBarFill.BorderSizePixel = 0
	itemsBarFill.Parent = itemsBarBg
	addCorner(itemsBarFill, 4)
	
	----------------------------------------------------------------------
	-- YOUR TOP HOLDINGS SECTION
	----------------------------------------------------------------------
	local holdingsY = 105
	
	-- Thin divider
	local div = Instance.new("Frame")
	div.Name = "HoldingsDivider"
	div.Size = UDim2.new(1, -10, 0, 1)
	div.Position = UDim2.new(0, 5, 0, holdingsY)
	div.BackgroundColor3 = UI_CONFIG.THEME_STROKE
	div.BackgroundTransparency = 0.4
	div.BorderSizePixel = 0
	div.Parent = hudPanel
	
	holdingsY += 8
	
	local holdingsTitle = Instance.new("TextLabel")
	holdingsTitle.Name = "HoldingsTitle"
	holdingsTitle.Size = UDim2.new(1, 0, 0, 16)
	holdingsTitle.Position = UDim2.new(0, 0, 0, holdingsY)
	holdingsTitle.BackgroundTransparency = 1
	holdingsTitle.Text = "Your Top Holdings"
	holdingsTitle.TextColor3 = UI_CONFIG.HOLDINGS_TITLE_COLOR
	holdingsTitle.TextSize = 13
	holdingsTitle.Font = Enum.Font.GothamBold
	holdingsTitle.TextXAlignment = Enum.TextXAlignment.Left
	holdingsTitle.Parent = hudPanel
	
	holdingsY += 20
	
	-- Holdings list container
	local holdingsList = Instance.new("Frame")
	holdingsList.Name = "HoldingsList"
	holdingsList.Size = UDim2.new(1, 0, 0, UI_CONFIG.MAX_HOLDINGS_ROWS * UI_CONFIG.ROW_HEIGHT)
	holdingsList.Position = UDim2.new(0, 0, 0, holdingsY)
	holdingsList.BackgroundTransparency = 1
	holdingsList.ClipsDescendants = true
	holdingsList.Parent = hudPanel
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 2)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = holdingsList
	
	holdingsY += UI_CONFIG.MAX_HOLDINGS_ROWS * UI_CONFIG.ROW_HEIGHT + 10
	
	-- Empty state label
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(1, 0, 1, 0)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "No items in storage"
	emptyLabel.TextColor3 = UI_CONFIG.LABEL_COLOR
	emptyLabel.TextSize = 11
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.Visible = true
	emptyLabel.Parent = holdingsList
	
	-- View Full Portfolio button
	local portfolioBtn = Instance.new("TextButton")
	portfolioBtn.Name = "PortfolioButton"
	portfolioBtn.Size = UDim2.new(1, 0, 0, 30)
	portfolioBtn.Position = UDim2.new(0, 0, 0, holdingsY)
	portfolioBtn.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
	portfolioBtn.Text = "📋 View Full Portfolio"
	portfolioBtn.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
	portfolioBtn.TextSize = 12
	portfolioBtn.Font = Enum.Font.GothamBold
	portfolioBtn.BorderSizePixel = 0
	portfolioBtn.Parent = hudPanel
	addCorner(portfolioBtn, 8)
	addStroke(portfolioBtn, UI_CONFIG.THEME_STROKE, 1)
	
	----------------------------------------------------------------------
	-- BOTTOM CENTER ACTION BAR (7 buttons in a row)
	----------------------------------------------------------------------
	local btnSize = UI_CONFIG.BOTTOM_BAR_BTN_SIZE
	local btnPad = UI_CONFIG.BOTTOM_BAR_PADDING
	local totalBarWidth = 7 * btnSize + 6 * btnPad + 24 -- + side padding for 7 buttons
	
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(0, totalBarWidth, 0, btnSize + 20)
	bottomBar.Position = UDim2.new(0.5, -totalBarWidth / 2, 1, -(btnSize + 30))
	bottomBar.BackgroundColor3 = Color3.new(1, 1, 1)
	bottomBar.BackgroundTransparency = 0.25
	bottomBar.BorderSizePixel = 0
	bottomBar.Parent = screenGui
	addCorner(bottomBar, UI_CONFIG.CORNER_RADIUS)
	addStroke(bottomBar, UI_CONFIG.THEME_STROKE, 1.5)
	
	local barGradient = Instance.new("UIGradient")
	barGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UI_CONFIG.THEME_BG),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 15, 20))
	})
	barGradient.Rotation = 90
	barGradient.Parent = bottomBar
	
	local barPadding = Instance.new("UIPadding")
	barPadding.PaddingLeft = UDim.new(0, 12)
	barPadding.PaddingRight = UDim.new(0, 12)
	barPadding.PaddingTop = UDim.new(0, 10)
	barPadding.PaddingBottom = UDim.new(0, 10)
	barPadding.Parent = bottomBar
	
	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	barLayout.Padding = UDim.new(0, btnPad)
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Parent = bottomBar
	
	local function createBarButton(name, textIcon, color, order)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Size = UDim2.new(0, btnSize, 0, btnSize)
		btn.BackgroundColor3 = color
		btn.LayoutOrder = order
		btn.Text = textIcon
		btn.TextSize = 20
		btn.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
		btn.Font = Enum.Font.GothamBold
		btn.Parent = bottomBar
		addCorner(btn, 10)
		addStroke(btn, UI_CONFIG.THEME_STROKE, 1.5)
		return btn
	end
	
	-- 0. Build (Hammer) - Order 0 to be first? Or last? User said "a button down in the hotbar". 
	-- Let's put it first or last. First is accessible.
	createBarButton("BuildButton", "🔨", Color3.fromRGB(255, 140, 0), 0)
	
	-- 1. Shop
	createBarButton("ShopButton", "🛒", UI_CONFIG.THEME_ACCENT_PURPLE, 1)
	
	-- 2. Brainrots (with 3D preview + badge)
	local brainrotsBtn = createBarButton("BrainrotsButton", "", UI_CONFIG.THEME_ACCENT_PINK, 2)
	
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, -6, 1, -6)
	viewport.Position = UDim2.new(0, 3, 0, 3)
	viewport.BackgroundTransparency = 1
	viewport.Parent = brainrotsBtn
	
	local countBadge = Instance.new("TextLabel")
	countBadge.Name = "CountBadge"
	countBadge.Size = UDim2.new(0, 20, 0, 16)
	countBadge.Position = UDim2.new(1, -18, 1, -14)
	countBadge.BackgroundColor3 = Color3.fromRGB(60, 180, 100)
	countBadge.Text = "0"
	countBadge.TextColor3 = Color3.new(1, 1, 1)
	countBadge.TextSize = 11
	countBadge.Font = Enum.Font.GothamBold
	countBadge.ZIndex = 10
	countBadge.Parent = brainrotsBtn
	addCorner(countBadge, 8)
	
	task.spawn(function()
		local allModels = {}
		if BrainrotsFolder then
			for _, m in BrainrotsFolder:GetChildren() do
				if m:IsA("Model") then table.insert(allModels, m) end
			end
		end
		if #allModels > 0 then
			local randomModel = allModels[math.random(1, #allModels)]:Clone()
			randomModel.Parent = viewport
			local cam = Instance.new("Camera")
			cam.Parent = viewport
			viewport.CurrentCamera = cam
			local cf, size = randomModel:GetBoundingBox()
			local maxDim = math.max(size.X, size.Y, size.Z)
			local dist = maxDim * 1.5
			cam.CFrame = CFrame.new(cf.Position + Vector3.new(dist, dist*0.5, dist), cf.Position)
		end
	end)
	
	-- 4. Backpack
	createBarButton("BackpackButton", "🎒", UI_CONFIG.THEME_ACCENT_BLUE, 4)
	-- 5. Storage
	createBarButton("StorageButton", "📦", Color3.fromRGB(255, 100, 50), 5)
	-- 6. Stock Market
	createBarButton("StockButton", "📈", Color3.fromRGB(80, 200, 100), 6)
	
	return screenGui
end

--------------------------------------------------------------------------------
-- MONEY TRACKING
--------------------------------------------------------------------------------

local MoneyHUDGui: ScreenGui
local MoneyLabel: TextLabel
local MPSLabel: TextLabel
local ItemsBarFill: Frame
local ItemsAmountLabel: TextLabel

local previousMoney: number = 0
local OwnedCounts: {[string]: number} = {}

local function calculateMPS(): number
	local totalMPS = 0
	for unitName, count in OwnedCounts do
		if count > 0 then
			local config = ShopConfig.GetConfig(unitName)
			if config then
				local incomePerSecond = (config.BaseIncome / config.CycleTime) * count
				totalMPS = totalMPS + incomePerSecond
			end
		end
	end
	return totalMPS
end

local function updateMPSDisplay()
	if not MPSLabel then return end
	local mps = calculateMPS()
	if mps >= 1000 then
		MPSLabel.Text = string.format("+$%.1fK/s", mps / 1000)
	else
		MPSLabel.Text = string.format("+$%.1f/s", mps)
	end
end

local function updateBrainrotCount()
	if not MoneyHUDGui then return end
	
	local bottomBar = MoneyHUDGui:FindFirstChild("BottomBar")
	if not bottomBar then return end
	
	local brainrotsBtn = bottomBar:FindFirstChild("BrainrotsButton")
	if not brainrotsBtn then return end
	
	local badge = brainrotsBtn:FindFirstChild("CountBadge")
	if not badge then return end
	
	local totalCount = 0
	for _, count in OwnedCounts do
		totalCount = totalCount + count
	end
	
	badge.Text = tostring(totalCount)
	if totalCount > 0 then
		badge.BackgroundColor3 = Color3.fromRGB(60, 180, 100)
	else
		badge.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	end
end

local function updateMoneyDisplay(newMoney: number)
	if not MoneyLabel then return end
	
	local formattedMoney = formatMoney(newMoney)
	MoneyLabel.Text = formattedMoney
	
	if newMoney > previousMoney then
		MoneyLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
		MoneyLabel.Size = UDim2.new(1, -30, 0, 38)
		
		TweenService:Create(MoneyLabel, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			TextColor3 = UI_CONFIG.MONEY_COLOR,
			Size = UDim2.new(1, -40, 0, 32)
		}):Play()
	elseif newMoney < previousMoney then
		MoneyLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		TweenService:Create(MoneyLabel, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
			TextColor3 = Color3.fromRGB(200, 200, 200)
		}):Play()
		task.delay(0.2, function()
			if MoneyLabel then
				TweenService:Create(MoneyLabel, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
					TextColor3 = UI_CONFIG.MONEY_COLOR
				}):Play()
			end
		end)
	end
	
	previousMoney = newMoney
end

local function updateItemsDisplay(currentItems: number, maxItems: number)
	if not ItemsBarFill or not ItemsAmountLabel then return end
	
	local fillPercent = math.clamp(currentItems / math.max(1, maxItems), 0, 1)
	
	TweenService:Create(ItemsBarFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(fillPercent, 0, 1, 0)
	}):Play()
	
	ItemsAmountLabel.Text = string.format("📦 ITEMS: %d / %d", currentItems, maxItems)
	
	local targetColor
	if fillPercent >= 1 then
		targetColor = UI_CONFIG.ITEMS_FULL_COLOR
	elseif fillPercent >= 0.75 then
		targetColor = UI_CONFIG.ITEMS_FILL_COLOR:Lerp(UI_CONFIG.ITEMS_FULL_COLOR, (fillPercent - 0.75) / 0.25)
	else
		targetColor = UI_CONFIG.ITEMS_FILL_COLOR
	end
	
	TweenService:Create(ItemsBarFill, TweenInfo.new(0.2), {
		BackgroundColor3 = targetColor
	}):Play()
end

--------------------------------------------------------------------------------
-- HOLDINGS DISPLAY
--------------------------------------------------------------------------------

local function updateHoldingsDisplay()
	if not MoneyHUDGui then return end
	
	local hudPanel = MoneyHUDGui:FindFirstChild("HUDPanel")
	if not hudPanel then return end
	local holdingsList = hudPanel:FindFirstChild("HoldingsList")
	if not holdingsList then return end
	
	-- Clear old rows (keep EmptyLabel)
	for _, child in holdingsList:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end
	
	local emptyLabel = holdingsList:FindFirstChild("EmptyLabel")
	
	-- Get sector rates
	local sectorRates = getSectorRates()
	
	-- Build sorted list by total value
	local sortedItems = {}
	for itemId, count in pairs(StorageItems) do
		if count > 0 then
			local itemDef = ItemConfig.Items[itemId]
			if itemDef then
				local sector = ItemConfig.GetSector(itemId) -- item-level lookup
				local rate = sectorRates[sector] or 1.0
				local totalValue = count * itemDef.basePrice * rate
				table.insert(sortedItems, {
					id = itemId,
					count = count,
					icon = itemDef.icon or "📦",
					name = itemDef.displayName or itemId,
					value = totalValue,
					rate = rate,
				})
			end
		end
	end
	
	table.sort(sortedItems, function(a, b) return a.value > b.value end)
	
	if emptyLabel then
		emptyLabel.Visible = #sortedItems == 0
	end
	
	for i = 1, math.min(UI_CONFIG.MAX_HOLDINGS_ROWS, #sortedItems) do
		local data = sortedItems[i]
		
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.Size = UDim2.new(1, 0, 0, UI_CONFIG.ROW_HEIGHT)
		row.BackgroundTransparency = 1
		row.LayoutOrder = i
		row.Parent = holdingsList
		
		-- Icon
		local iconLabel = Instance.new("TextLabel")
		iconLabel.Size = UDim2.new(0, 18, 1, 0)
		iconLabel.Position = UDim2.new(0, 0, 0, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = data.icon
		iconLabel.TextSize = 12
		iconLabel.Font = Enum.Font.Gotham
		iconLabel.Parent = row
		
		-- Name (truncated)
		local displayName = data.name
		if #displayName > 10 then
			displayName = string.sub(displayName, 1, 9) .. "…"
		end
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0, 60, 1, 0)
		nameLabel.Position = UDim2.new(0, 20, 0, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = displayName
		nameLabel.TextColor3 = UI_CONFIG.HOLDINGS_NAME_COLOR
		nameLabel.TextSize = 10
		nameLabel.Font = Enum.Font.Gotham
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.Parent = row
		
		-- Count
		local countLabel = Instance.new("TextLabel")
		countLabel.Size = UDim2.new(0, 30, 1, 0)
		countLabel.Position = UDim2.new(0, 82, 0, 0)
		countLabel.BackgroundTransparency = 1
		countLabel.Text = "x" .. tostring(data.count)
		countLabel.TextColor3 = UI_CONFIG.HOLDINGS_COUNT_COLOR
		countLabel.TextSize = 10
		countLabel.Font = Enum.Font.Gotham
		countLabel.TextXAlignment = Enum.TextXAlignment.Right
		countLabel.Parent = row
		
		-- Value
		local valueLabel = Instance.new("TextLabel")
		valueLabel.Size = UDim2.new(0, 50, 1, 0)
		valueLabel.Position = UDim2.new(0, 115, 0, 0)
		valueLabel.BackgroundTransparency = 1
		valueLabel.Text = formatMoney(data.value)
		valueLabel.TextColor3 = UI_CONFIG.HOLDINGS_VALUE_COLOR
		valueLabel.TextSize = 10
		valueLabel.Font = Enum.Font.GothamBold
		valueLabel.TextXAlignment = Enum.TextXAlignment.Right
		valueLabel.Parent = row
		
		-- Arrow (▲ if rate >= 1, ▼ if < 1)
		local arrowLabel = Instance.new("TextLabel")
		arrowLabel.Size = UDim2.new(0, 14, 1, 0)
		arrowLabel.Position = UDim2.new(0, 168, 0, 0)
		arrowLabel.BackgroundTransparency = 1
		if data.rate >= 1.0 then
			arrowLabel.Text = "▲"
			arrowLabel.TextColor3 = UI_CONFIG.ARROW_UP_COLOR
		else
			arrowLabel.Text = "▼"
			arrowLabel.TextColor3 = UI_CONFIG.ARROW_DOWN_COLOR
		end
		arrowLabel.TextSize = 10
		arrowLabel.Font = Enum.Font.GothamBold
		arrowLabel.Parent = row
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("MoneyHUD: Initializing...")
	
	MoneyHUDGui = createMoneyHUD()
	MoneyHUDGui.Parent = PlayerGui
	
	-- Get references
	local hudPanel = MoneyHUDGui:FindFirstChild("HUDPanel")
	if hudPanel then
		local moneyContainer = hudPanel:FindFirstChild("MoneyContainer")
		if moneyContainer then
			MoneyLabel = moneyContainer:FindFirstChild("MoneyLabel")
		end
		MPSLabel = hudPanel:FindFirstChild("MPSLabel")
		
		local itemsContainer = hudPanel:FindFirstChild("ItemsContainer")
		if itemsContainer then
			ItemsAmountLabel = itemsContainer:FindFirstChild("ItemsAmount")
			local itemsBarBg = itemsContainer:FindFirstChild("ItemsBarBg")
			if itemsBarBg then
				ItemsBarFill = itemsBarBg:FindFirstChild("ItemsBarFill")
			end
		end
	end
	
	----------------------------------------------------------------------
	-- BUTTON CONNECTIONS (Bottom Bar)
	----------------------------------------------------------------------
	local bottomBar = MoneyHUDGui:FindFirstChild("BottomBar")
	if bottomBar then
		local function setupBtn(btnName, eventName, filterArg, baseColor, hoverColor)
			local btn = bottomBar:FindFirstChild(btnName)
			if not btn then return end
			
			local toggleEvent = ReplicatedStorage:FindFirstChild(eventName)
			if not toggleEvent then
				toggleEvent = Instance.new("BindableEvent")
				toggleEvent.Name = eventName
				toggleEvent.Parent = ReplicatedStorage
			end
			
			btn.MouseButton1Click:Connect(function()
				if filterArg then
					toggleEvent:Fire(filterArg)
				else
					toggleEvent:Fire()
				end
			end)
			
			btn.MouseEnter:Connect(function()
				TweenService:Create(btn, TweenInfo.new(0.1), {
					BackgroundColor3 = hoverColor,
					Size = UDim2.new(0, UI_CONFIG.BOTTOM_BAR_BTN_SIZE + 6, 0, UI_CONFIG.BOTTOM_BAR_BTN_SIZE + 6)
				}):Play()
			end)
			btn.MouseLeave:Connect(function()
				TweenService:Create(btn, TweenInfo.new(0.1), {
					BackgroundColor3 = baseColor,
					Size = UDim2.new(0, UI_CONFIG.BOTTOM_BAR_BTN_SIZE, 0, UI_CONFIG.BOTTOM_BAR_BTN_SIZE)
				}):Play()
			end)
		end
		
		setupBtn("BuildButton", "BuildModeToggleEvent", nil,
			Color3.fromRGB(255, 140, 0), Color3.fromRGB(255, 180, 50))
		
		local buildBtn = bottomBar:FindFirstChild("BuildButton")
		if buildBtn then
			local buildToggle = ReplicatedStorage:FindFirstChild("BuildModeToggleEvent")
			buildToggle.Event:Connect(function()
				IsBuildOpen = not IsBuildOpen
				TweenService:Create(buildBtn, TweenInfo.new(0.2), {
					BackgroundColor3 = IsBuildOpen and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(255, 140, 0)
				}):Play()
			end)
		end

		setupBtn("ShopButton", "ShopToggleEvent", nil,
			UI_CONFIG.THEME_ACCENT_PURPLE, Color3.fromRGB(100, 80, 170))
		
		local shopBtn = bottomBar:FindFirstChild("ShopButton")
		if shopBtn then
			local shopToggle = ReplicatedStorage:FindFirstChild("ShopToggleEvent")
			shopToggle.Event:Connect(function()
				IsShopOpen = not IsShopOpen
				TweenService:Create(shopBtn, TweenInfo.new(0.2), {
					BackgroundColor3 = IsShopOpen and Color3.fromRGB(150, 100, 255) or UI_CONFIG.THEME_ACCENT_PURPLE
				}):Play()
			end)
		end
		setupBtn("BrainrotsButton", "BackpackToggleEvent", "Unit",
			UI_CONFIG.THEME_ACCENT_PINK, Color3.fromRGB(170, 100, 190))
		setupBtn("StorageButton", "StorageToggleEvent", nil,
			Color3.fromRGB(255, 100, 50), Color3.fromRGB(255, 140, 100))
		setupBtn("StockButton", "StockToggleEvent", nil,
			Color3.fromRGB(80, 200, 100), Color3.fromRGB(100, 230, 130))
	end
	
	-- Portfolio button
	local portfolioBtn = hudPanel and hudPanel:FindFirstChild("PortfolioButton")
	if portfolioBtn then
		local backpackToggle = ReplicatedStorage:FindFirstChild("BackpackToggleEvent")
		if not backpackToggle then
			backpackToggle = Instance.new("BindableEvent")
			backpackToggle.Name = "BackpackToggleEvent"
			backpackToggle.Parent = ReplicatedStorage
		end
		
		portfolioBtn.MouseButton1Click:Connect(function()
			backpackToggle:Fire()
		end)
		
		portfolioBtn.MouseEnter:Connect(function()
			TweenService:Create(portfolioBtn, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(55, 60, 80)
			}):Play()
		end)
		portfolioBtn.MouseLeave:Connect(function()
			TweenService:Create(portfolioBtn, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(40, 45, 60)
			}):Play()
		end)
	end
	
	----------------------------------------------------------------------
	-- OWNERSHIP / MPS (unchanged logic)
	----------------------------------------------------------------------
	local ownershipData = GetOwnershipRemote:InvokeServer()
	if ownershipData and ownershipData.units then
		for unitName, data in ownershipData.units do
			OwnedCounts[unitName] = data.count
		end
		updateMPSDisplay()
		updateBrainrotCount()
	end
	
	OwnershipChangedEvent.OnClientEvent:Connect(function(unitName: string, newCount: number)
		OwnedCounts[unitName] = newCount
		updateMPSDisplay()
		updateBrainrotCount()
	end)
	
	----------------------------------------------------------------------
	-- MONEY TRACKING
	----------------------------------------------------------------------
	local leaderstats = Player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local money = leaderstats:WaitForChild("Money", 5)
		if money then
			previousMoney = money.Value
			updateMoneyDisplay(money.Value)
			money:GetPropertyChangedSignal("Value"):Connect(function()
				updateMoneyDisplay(money.Value)
			end)
			print("MoneyHUD: Connected to money value")
		else
			warn("MoneyHUD: Could not find Money value")
		end
	else
		warn("MoneyHUD: Could not find leaderstats")
	end
	
	----------------------------------------------------------------------
	-- STORAGE + HOLDINGS
	----------------------------------------------------------------------
	local function decodeItems(encoded)
		if not ItemConfig or not ItemConfig.SHORT_TO_ID then return encoded end
		if type(encoded) ~= "table" then return encoded end
		local decoded = {}
		for k, count in pairs(encoded) do
			local shortId = tonumber(k)
			if shortId and ItemConfig.SHORT_TO_ID[shortId] then
				decoded[ItemConfig.SHORT_TO_ID[shortId]] = count
			else
				decoded[k] = count
			end
		end
		return decoded
	end

	local function refreshFromAttribute()
		local items, total, cap = GetStorageFunction:InvokeServer()
		StorageItems = decodeItems(items) or {}
		updateItemsDisplay(total or 0, Player:GetAttribute("StorageCapacity") or cap or 0)
		updateHoldingsDisplay()
	end
	
	if StorageUpdatedEvent then
		StorageUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
			items = decodeItems(items)
			StorageItems = items or {}
			updateItemsDisplay(total or 0, Player:GetAttribute("StorageCapacity") or capacity or 0)
			updateHoldingsDisplay()
		end)
	end
	
	Player:GetAttributeChangedSignal("StorageCapacity"):Connect(function()
		local cur = 0
		if ItemsAmountLabel then
			local txt = ItemsAmountLabel.Text
			local val = txt:match("ITEMS: (%d+)")
			cur = tonumber(val) or 0
		end
		updateItemsDisplay(cur, Player:GetAttribute("StorageCapacity") or 0)
	end)
	
	-- Listen for stock market rate changes to refresh holdings values
	if not StockMarketFolder then
		StockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket")
	end
	if StockMarketFolder then
		StockMarketFolder:GetAttributeChangedSignal("SectorRates"):Connect(function()
			updateHoldingsDisplay()
		end)
	end
	
	-- Initial fetch
	task.spawn(refreshFromAttribute)
	
	print("MoneyHUD: Ready!")
end

-- Start
initialize()
