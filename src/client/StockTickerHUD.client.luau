--[[
	StockTickerHUD Client Script
	
	A continuously scrolling stock ticker bar at the top of the screen.
	Shows each sector's current rate multiplier with trend arrows and % change.
	Clicking a sector opens a detail popup with a mini price-history graph.
	
	Data source: ReplicatedStorage.StockMarket attributes (published by StockMarketManager)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Wait for StockMarket folder
local stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket", 30)
if not stockMarketFolder then
	warn("StockTickerHUD: StockMarket folder not found!")
	return
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
	-- Bar
	BAR_HEIGHT = 28,
	BAR_COLOR = Color3.fromRGB(12, 12, 20),
	BAR_TRANSPARENCY = 0.15,
	
	-- Scrolling
	SCROLL_SPEED = 50, -- pixels per second
	ITEM_SPACING = 30, -- px between sector entries
	SEPARATOR = "  │  ",
	
	-- Colors
	UP_COLOR = Color3.fromRGB(80, 255, 120),
	DOWN_COLOR = Color3.fromRGB(255, 80, 80),
	NEUTRAL_COLOR = Color3.fromRGB(180, 180, 200),
	TEXT_COLOR = Color3.fromRGB(220, 220, 240),
	
	-- Popup
	POPUP_WIDTH = 280,
	POPUP_HEIGHT = 220,
	POPUP_BG = Color3.fromRGB(20, 20, 35),
	POPUP_STROKE = Color3.fromRGB(60, 60, 90),
	
	-- Graph (inside popup)
	GRAPH_HEIGHT = 100,
	GRAPH_LINE_COLOR_DEFAULT = Color3.fromRGB(100, 200, 255),
	
	-- Sector icons
	SECTOR_ICONS = {
		Food = "🍕",
		Animals = "🐾",
		Entertainment = "🎭",
		Mystic = "🔮",
		Tech = "⚡",
		Action = "💥",
	},
}

local SECTOR_COLORS = {
	Food = Color3.fromRGB(227, 119, 194),
	Animals = Color3.fromRGB(44, 160, 44),
	Entertainment = Color3.fromRGB(255, 127, 14),
	Mystic = Color3.fromRGB(148, 103, 189),
	Tech = Color3.fromRGB(31, 119, 180),
	Action = Color3.fromRGB(214, 39, 40),
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local sectorOrder = {"Food", "Animals", "Entertainment", "Mystic", "Tech", "Action"}
local sectorRates: {[string]: number} = {}
local sectorHistories: {[string]: {number}} = {}
local previousRates: {[string]: number} = {} -- for % change calculation

local scrollOffset = 0
local isHovered = false
local activePopupSector: string? = nil

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StockTickerHUD"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 5
screenGui.Parent = PlayerGui

-- Top bar
local tickerBar = Instance.new("Frame")
tickerBar.Name = "TickerBar"
tickerBar.Size = UDim2.new(1, 0, 0, CONFIG.BAR_HEIGHT)
tickerBar.Position = UDim2.new(0, 0, 0, 0)
tickerBar.BackgroundColor3 = CONFIG.BAR_COLOR
tickerBar.BackgroundTransparency = CONFIG.BAR_TRANSPARENCY
tickerBar.BorderSizePixel = 0
tickerBar.ClipsDescendants = true
tickerBar.Parent = screenGui

-- Subtle bottom border
local borderLine = Instance.new("Frame")
borderLine.Name = "Border"
borderLine.Size = UDim2.new(1, 0, 0, 1)
borderLine.Position = UDim2.new(0, 0, 1, -1)
borderLine.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
borderLine.BackgroundTransparency = 0.5
borderLine.BorderSizePixel = 0
borderLine.Parent = tickerBar

-- Scrolling content frame (will be wider than the bar, shifted left over time)
local scrollFrame = Instance.new("Frame")
scrollFrame.Name = "ScrollContent"
scrollFrame.Size = UDim2.new(0, 2000, 1, 0) -- Will be resized after building labels
scrollFrame.Position = UDim2.new(0, 0, 0, 0)
scrollFrame.BackgroundTransparency = 1
scrollFrame.Parent = tickerBar

-- Detail popup (hidden by default)
local popupFrame = Instance.new("Frame")
popupFrame.Name = "DetailPopup"
popupFrame.Size = UDim2.new(0, CONFIG.POPUP_WIDTH, 0, CONFIG.POPUP_HEIGHT)
popupFrame.Position = UDim2.new(0, 100, 0, CONFIG.BAR_HEIGHT + 4)
popupFrame.BackgroundColor3 = CONFIG.POPUP_BG
popupFrame.BackgroundTransparency = 0.05
popupFrame.BorderSizePixel = 0
popupFrame.Visible = false
popupFrame.ZIndex = 10
popupFrame.Parent = screenGui

local popupCorner = Instance.new("UICorner")
popupCorner.CornerRadius = UDim.new(0, 10)
popupCorner.Parent = popupFrame

local popupStroke = Instance.new("UIStroke")
popupStroke.Color = CONFIG.POPUP_STROKE
popupStroke.Thickness = 1.5
popupStroke.Transparency = 0.3
popupStroke.Parent = popupFrame

local popupPadding = Instance.new("UIPadding")
popupPadding.PaddingLeft = UDim.new(0, 10)
popupPadding.PaddingRight = UDim.new(0, 10)
popupPadding.PaddingTop = UDim.new(0, 8)
popupPadding.PaddingBottom = UDim.new(0, 8)
popupPadding.Parent = popupFrame

-- Popup: Title
local popupTitle = Instance.new("TextLabel")
popupTitle.Name = "Title"
popupTitle.Size = UDim2.new(1, 0, 0, 20)
popupTitle.BackgroundTransparency = 1
popupTitle.Text = "📈 SECTOR"
popupTitle.TextColor3 = CONFIG.TEXT_COLOR
popupTitle.TextSize = 14
popupTitle.Font = Enum.Font.GothamBold
popupTitle.TextXAlignment = Enum.TextXAlignment.Left
popupTitle.ZIndex = 11
popupTitle.Parent = popupFrame

-- Popup: Rate
local popupRate = Instance.new("TextLabel")
popupRate.Name = "Rate"
popupRate.Size = UDim2.new(1, 0, 0, 30)
popupRate.Position = UDim2.new(0, 0, 0, 22)
popupRate.BackgroundTransparency = 1
popupRate.Text = "1.00x"
popupRate.TextColor3 = CONFIG.UP_COLOR
popupRate.TextSize = 26
popupRate.Font = Enum.Font.GothamBlack
popupRate.TextXAlignment = Enum.TextXAlignment.Left
popupRate.ZIndex = 11
popupRate.Parent = popupFrame

-- Popup: Change info
local popupChange = Instance.new("TextLabel")
popupChange.Name = "Change"
popupChange.Size = UDim2.new(1, 0, 0, 16)
popupChange.Position = UDim2.new(0, 0, 0, 54)
popupChange.BackgroundTransparency = 1
popupChange.Text = "▲ +5.0% from 5 ticks ago"
popupChange.TextColor3 = CONFIG.NEUTRAL_COLOR
popupChange.TextSize = 11
popupChange.Font = Enum.Font.Gotham
popupChange.TextXAlignment = Enum.TextXAlignment.Left
popupChange.ZIndex = 11
popupChange.Parent = popupFrame

-- Popup: Graph container
local graphContainer = Instance.new("Frame")
graphContainer.Name = "GraphContainer"
graphContainer.Size = UDim2.new(1, 0, 0, CONFIG.GRAPH_HEIGHT)
graphContainer.Position = UDim2.new(0, 0, 0, 76)
graphContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
graphContainer.BackgroundTransparency = 0.3
graphContainer.BorderSizePixel = 0
graphContainer.ZIndex = 11
graphContainer.Parent = popupFrame

local graphCorner = Instance.new("UICorner")
graphCorner.CornerRadius = UDim.new(0, 6)
graphCorner.Parent = graphContainer

-- Popup: Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.new(0, 20, 0, 20)
closeBtn.Position = UDim2.new(1, -10, 0, 0)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "✕"
closeBtn.TextColor3 = CONFIG.NEUTRAL_COLOR
closeBtn.TextSize = 14
closeBtn.Font = Enum.Font.GothamBold
closeBtn.ZIndex = 12
closeBtn.Parent = popupFrame

closeBtn.Activated:Connect(function()
	popupFrame.Visible = false
	activePopupSector = nil
end)

--------------------------------------------------------------------------------
-- DATA PARSING
--------------------------------------------------------------------------------

local function parseSectorRates()
	local json = stockMarketFolder:GetAttribute("SectorRates")
	if not json then return end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if ok and data then
		-- Save previous for % change
		for k, v in pairs(sectorRates) do
			previousRates[k] = v
		end
		sectorRates = data
	end
end

local function parseSectorHistories()
	local json = stockMarketFolder:GetAttribute("SectorHistories")
	if not json then return end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or not data then return end
	
	for sector, csv in pairs(data) do
		local history = {}
		for val in string.gmatch(csv, "[^,]+") do
			local n = tonumber(val)
			if n then table.insert(history, n) end
		end
		sectorHistories[sector] = history
	end
end

local function getPercentChange(sector: string): (number, number)
	-- Returns (percentChange, previousRate)
	local history = sectorHistories[sector]
	if not history or #history < 6 then
		return 0, sectorRates[sector] or 1.0
	end
	local current = history[#history]
	local previous = history[#history - 5] -- 5 ticks ago
	if previous == 0 then return 0, previous end
	local pct = ((current - previous) / previous) * 100
	return pct, previous
end

--------------------------------------------------------------------------------
-- TICKER LABEL BUILDING
--------------------------------------------------------------------------------

local sectorButtons: {[string]: TextButton} = {}
local totalContentWidth = 0

local function buildTickerContent()
	-- Clear old
	for _, child in scrollFrame:GetChildren() do
		child:Destroy()
	end
	sectorButtons = {}
	
	local xPos = 0
	
	for i, sector in ipairs(sectorOrder) do
		local rate = sectorRates[sector] or 1.0
		local pct, _ = getPercentChange(sector)
		local icon = CONFIG.SECTOR_ICONS[sector] or "📊"
		
		-- Determine trend
		local arrow, arrowColor
		if pct > 0.5 then
			arrow = "▲"
			arrowColor = CONFIG.UP_COLOR
		elseif pct < -0.5 then
			arrow = "▼"
			arrowColor = CONFIG.DOWN_COLOR
		else
			arrow = "—"
			arrowColor = CONFIG.NEUTRAL_COLOR
		end
		
		local text = string.format("%s %s %.2fx %s%.0f%%", icon, sector, rate, arrow, math.abs(pct))
		
		local btn = Instance.new("TextButton")
		btn.Name = "Sector_" .. sector
		btn.Size = UDim2.new(0, 0, 1, 0) -- auto-sized below
		btn.Position = UDim2.new(0, xPos, 0, 0)
		btn.BackgroundTransparency = 1
		btn.Text = text
		btn.TextColor3 = arrowColor
		btn.TextSize = 13
		btn.Font = Enum.Font.GothamMedium
		btn.AutomaticSize = Enum.AutomaticSize.X
		btn.Parent = scrollFrame
		
		-- Add padding inside button
		local btnPadding = Instance.new("UIPadding")
		btnPadding.PaddingLeft = UDim.new(0, 8)
		btnPadding.PaddingRight = UDim.new(0, 8)
		btnPadding.Parent = btn
		
		-- Click handler
		btn.Activated:Connect(function()
			if activePopupSector == sector then
				popupFrame.Visible = false
				activePopupSector = nil
			else
				showPopup(sector, btn)
			end
		end)
		
		-- Hover
		btn.MouseEnter:Connect(function()
			isHovered = true
			btn.TextColor3 = Color3.new(1, 1, 1)
		end)
		btn.MouseLeave:Connect(function()
			isHovered = false
			-- Restore color on next update
		end)
		
		sectorButtons[sector] = btn
		
		-- Measure width (estimate based on text length, will be refined by AutomaticSize)
		local estimatedWidth = #text * 8 + 16
		xPos += estimatedWidth
		
		-- Add separator (except after last)
		if i < #sectorOrder then
			local sep = Instance.new("TextLabel")
			sep.Name = "Sep_" .. i
			sep.Size = UDim2.new(0, 20, 1, 0)
			sep.Position = UDim2.new(0, xPos, 0, 0)
			sep.BackgroundTransparency = 1
			sep.Text = "│"
			sep.TextColor3 = Color3.fromRGB(60, 60, 90)
			sep.TextSize = 13
			sep.Font = Enum.Font.Gotham
			sep.Parent = scrollFrame
			xPos += 20
		end
	end
	
	totalContentWidth = xPos + 40 -- extra padding for seamless wrap
	scrollFrame.Size = UDim2.new(0, totalContentWidth * 2, 1, 0) -- double for seamless loop
	
	-- Duplicate labels for seamless scrolling
	for _, child in scrollFrame:GetChildren() do
		if child:IsA("GuiBase2d") and not child.Name:find("_dup") then
			local dup = child:Clone()
			dup.Name = child.Name .. "_dup"
			dup.Position = UDim2.new(0, child.Position.X.Offset + totalContentWidth, 0, 0)
			dup.Parent = scrollFrame
		end
	end
end

local function updateTickerLabels()
	for sector, btn in pairs(sectorButtons) do
		if btn.Name:find("_dup") then continue end
		local rate = sectorRates[sector] or 1.0
		local pct, _ = getPercentChange(sector)
		local icon = CONFIG.SECTOR_ICONS[sector] or "📊"
		
		local arrow, arrowColor
		if pct > 0.5 then
			arrow = "▲"
			arrowColor = CONFIG.UP_COLOR
		elseif pct < -0.5 then
			arrow = "▼"
			arrowColor = CONFIG.DOWN_COLOR
		else
			arrow = "—"
			arrowColor = CONFIG.NEUTRAL_COLOR
		end
		
		btn.Text = string.format("%s %s %.2fx %s%.0f%%", icon, sector, rate, arrow, math.abs(pct))
		if not isHovered then
			btn.TextColor3 = arrowColor
		end
		
		-- Update duplicate
		local dup = scrollFrame:FindFirstChild(btn.Name .. "_dup")
		if dup then
			dup.Text = btn.Text
			if not isHovered then
				dup.TextColor3 = arrowColor
			end
		end
	end
end

--------------------------------------------------------------------------------
-- POPUP / DETAIL VIEW
--------------------------------------------------------------------------------

local graphLines: {Frame} = {}

local function clearGraph()
	for _, line in graphLines do
		line:Destroy()
	end
	graphLines = {}
end

local function drawMiniGraph(sector: string)
	clearGraph()
	
	local history = sectorHistories[sector]
	if not history or #history < 2 then return end
	
	local color = SECTOR_COLORS[sector] or CONFIG.GRAPH_LINE_COLOR_DEFAULT
	
	-- Find min/max for scaling
	local minVal, maxVal = math.huge, -math.huge
	for _, v in ipairs(history) do
		minVal = math.min(minVal, v)
		maxVal = math.max(maxVal, v)
	end
	local range = maxVal - minVal
	if range < 0.01 then range = 0.1 end -- avoid division by zero
	
	-- Add some padding to the range
	minVal = minVal - range * 0.1
	maxVal = maxVal + range * 0.1
	range = maxVal - minVal
	
	local graphWidth = CONFIG.POPUP_WIDTH - 20 -- accounting for padding
	local graphHeight = CONFIG.GRAPH_HEIGHT - 10
	
	-- Draw line segments
	for i = 1, #history - 1 do
		local x1 = ((i - 1) / (#history - 1)) * graphWidth
		local y1 = (1 - (history[i] - minVal) / range) * graphHeight + 5
		local x2 = (i / (#history - 1)) * graphWidth
		local y2 = (1 - (history[i + 1] - minVal) / range) * graphHeight + 5
		
		-- Calculate line properties
		local dx = x2 - x1
		local dy = y2 - y1
		local length = math.sqrt(dx * dx + dy * dy)
		local angle = math.atan2(dy, dx)
		
		local line = Instance.new("Frame")
		line.Name = "Line_" .. i
		line.Size = UDim2.new(0, math.ceil(length), 0, 2)
		line.Position = UDim2.new(0, math.floor(x1), 0, math.floor(y1))
		line.Rotation = math.deg(angle)
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.BackgroundColor3 = color
		line.BackgroundTransparency = 0.1
		line.BorderSizePixel = 0
		line.ZIndex = 12
		line.Parent = graphContainer
		
		table.insert(graphLines, line)
	end
	
	-- Draw current dot at end
	local lastX = graphWidth
	local lastY = (1 - (history[#history] - minVal) / range) * graphHeight + 5
	
	local dot = Instance.new("Frame")
	dot.Name = "CurrentDot"
	dot.Size = UDim2.new(0, 8, 0, 8)
	dot.Position = UDim2.new(0, math.floor(lastX) - 4, 0, math.floor(lastY) - 4)
	dot.BackgroundColor3 = Color3.new(1, 1, 1)
	dot.BorderSizePixel = 0
	dot.ZIndex = 13
	dot.Parent = graphContainer
	
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	
	table.insert(graphLines, dot)
	
	-- Glow behind dot
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.Size = UDim2.new(0, 16, 0, 16)
	glow.Position = UDim2.new(0, math.floor(lastX) - 8, 0, math.floor(lastY) - 8)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = 0.6
	glow.BorderSizePixel = 0
	glow.ZIndex = 12
	glow.Parent = graphContainer
	
	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0)
	glowCorner.Parent = glow
	
	table.insert(graphLines, glow)
end

function showPopup(sector: string, btn: TextButton)
	activePopupSector = sector
	
	local rate = sectorRates[sector] or 1.0
	local pct, prevRate = getPercentChange(sector)
	local icon = CONFIG.SECTOR_ICONS[sector] or "📊"
	local color = SECTOR_COLORS[sector] or CONFIG.GRAPH_LINE_COLOR_DEFAULT
	
	-- Trend text
	local arrow, arrowColor
	if pct > 0.5 then
		arrow = "▲"
		arrowColor = CONFIG.UP_COLOR
	elseif pct < -0.5 then
		arrow = "▼"
		arrowColor = CONFIG.DOWN_COLOR
	else
		arrow = "—"
		arrowColor = CONFIG.NEUTRAL_COLOR
	end
	
	popupTitle.Text = string.format("%s %s Sector", icon, sector)
	popupTitle.TextColor3 = color
	
	popupRate.Text = string.format("%.2fx", rate)
	popupRate.TextColor3 = arrowColor
	
	popupChange.Text = string.format("%s %s%.1f%% from 5 ticks ago", arrow, pct >= 0 and "+" or "", pct)
	popupChange.TextColor3 = arrowColor
	
	popupStroke.Color = color
	
	-- Position popup near the button
	local btnPos = btn.AbsolutePosition.X
	local popupX = math.clamp(btnPos, 10, tickerBar.AbsoluteSize.X - CONFIG.POPUP_WIDTH - 10)
	popupFrame.Position = UDim2.new(0, popupX, 0, CONFIG.BAR_HEIGHT + 4)
	
	-- Draw graph
	drawMiniGraph(sector)
	
	-- Show with animation
	popupFrame.Visible = true
	popupFrame.BackgroundTransparency = 1
	TweenService:Create(popupFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.05
	}):Play()
end

--------------------------------------------------------------------------------
-- SCROLLING ANIMATION
--------------------------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	if not isHovered and totalContentWidth > 0 then
		scrollOffset += CONFIG.SCROLL_SPEED * dt
		if scrollOffset >= totalContentWidth then
			scrollOffset -= totalContentWidth
		end
		scrollFrame.Position = UDim2.new(0, -scrollOffset, 0, 0)
	end
end)

--------------------------------------------------------------------------------
-- DATA UPDATES
--------------------------------------------------------------------------------

local function onMarketUpdate()
	parseSectorRates()
	parseSectorHistories()
	updateTickerLabels()
	
	-- Refresh popup if open
	if activePopupSector and popupFrame.Visible then
		local btn = sectorButtons[activePopupSector]
		if btn then
			showPopup(activePopupSector, btn)
		end
	end
end

-- Initial load
parseSectorRates()
parseSectorHistories()
buildTickerContent()

-- Listen for updates
stockMarketFolder:GetAttributeChangedSignal("SectorRates"):Connect(onMarketUpdate)
stockMarketFolder:GetAttributeChangedSignal("SectorHistories"):Connect(onMarketUpdate)

-- Close popup when clicking outside
tickerBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		-- Don't close here — let sector buttons handle their own clicks
	end
end)

print("✓ StockTickerHUD initialized")
