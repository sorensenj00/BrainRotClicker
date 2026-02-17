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


--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local sectorOrder = {"Food", "Animals", "Entertainment", "Mystic", "Tech", "Action"}
local sectorRates: {[string]: number} = {}
local sectorHistories: {[string]: {number}} = {}
local previousRates: {[string]: number} = {} -- for % change calculation

local scrollOffset = 0
local totalContentWidth = 0

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StockTickerHUD"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 5
screenGui.Parent = PlayerGui
screenGui.IgnoreGuiInset = true

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

local sectorLabels: {[string]: TextLabel} = {}

local function buildTickerContent()
	-- Clear old
	for _, child in scrollFrame:GetChildren() do
		child:Destroy()
	end
	sectorLabels = {}
	
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
		
		local label = Instance.new("TextLabel")
		label.Name = "Sector_" .. sector
		label.Size = UDim2.new(0, 0, 1, 0) -- auto-sized below
		label.Position = UDim2.new(0, xPos, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = text
		label.TextColor3 = arrowColor
		label.TextSize = 13
		label.Font = Enum.Font.GothamMedium
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Parent = scrollFrame
		
		-- Add padding inside label
		local btnPadding = Instance.new("UIPadding")
		btnPadding.PaddingLeft = UDim.new(0, 8)
		btnPadding.PaddingRight = UDim.new(0, 8)
		btnPadding.Parent = label
		
		sectorLabels[sector] = label
		
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
	for sector, label in pairs(sectorLabels) do
		if label.Name:find("_dup") then continue end
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
		
		label.Text = string.format("%s %s %.2fx %s%.0f%%", icon, sector, rate, arrow, math.abs(pct))
		label.TextColor3 = arrowColor
		
		-- Update duplicate
		local dup = scrollFrame:FindFirstChild(label.Name .. "_dup")
		if dup then
			dup.Text = label.Text
			dup.TextColor3 = arrowColor
		end
	end
end


--------------------------------------------------------------------------------
-- SCROLLING ANIMATION
--------------------------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt)
	if totalContentWidth > 0 then
		scrollOffset += CONFIG.SCROLL_SPEED * dt
		if scrollOffset >= totalContentWidth then
			scrollOffset -= totalContentWidth
		end
		scrollFrame.Position = UDim2.new(0, -scrollOffset, 0, 0)
	end
end)

--------------------------------------------------------------------------------
-- PRICING MODE INDICATOR
--------------------------------------------------------------------------------

-- Small GLOBAL/LOCAL indicator on right side of ticker bar
local modeIndicator = Instance.new("TextLabel")
modeIndicator.Name = "ModeIndicator"
modeIndicator.Size = UDim2.new(0, 80, 1, 0)
modeIndicator.Position = UDim2.new(1, -85, 0, 0)
modeIndicator.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
modeIndicator.BackgroundTransparency = 0.3
modeIndicator.Text = "📡 GLOBAL"
modeIndicator.TextColor3 = CONFIG.UP_COLOR
modeIndicator.TextSize = 10
modeIndicator.Font = Enum.Font.GothamBold
modeIndicator.ZIndex = 3
modeIndicator.Parent = tickerBar

local modeCorner = Instance.new("UICorner")
modeCorner.CornerRadius = UDim.new(0, 4)
modeCorner.Parent = modeIndicator

local function updateModeIndicator()
	local globalActive = stockMarketFolder:GetAttribute("GlobalPricingActive")
	if globalActive then
		modeIndicator.Text = "📡 GLOBAL"
		modeIndicator.TextColor3 = CONFIG.UP_COLOR
	else
		modeIndicator.Text = "💻 LOCAL"
		modeIndicator.TextColor3 = Color3.fromRGB(255, 200, 60)
	end
end

--------------------------------------------------------------------------------
-- DATA UPDATES
--------------------------------------------------------------------------------

local function onMarketUpdate()
	parseSectorRates()
	parseSectorHistories()
	updateTickerLabels()
	updateModeIndicator()
end

-- Initial load
parseSectorRates()
parseSectorHistories()
buildTickerContent()
updateModeIndicator()

-- Listen for updates
stockMarketFolder:GetAttributeChangedSignal("SectorRates"):Connect(onMarketUpdate)
stockMarketFolder:GetAttributeChangedSignal("SectorHistories"):Connect(onMarketUpdate)


print("✓ StockTickerHUD initialized")
