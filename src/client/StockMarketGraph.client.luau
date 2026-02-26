--!strict
--[[
	StockMarketGraph Client Script (Refactored)
	
	Ultra-performant graph rendering using native UI frames ("Pill-Frame" logic).
	Replaces the heavy EditableImage scanline approach with pure GPU vectors.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local CONFIG = {
	-- Canvas size matching the GraphContainer SurfaceGui area (1440x720)
	CANVAS_WIDTH = 1440,
	CANVAS_HEIGHT = 720,
	PADDING = 40,
	
	-- Pill-Frame Graph Settings
	CORE_THICKNESS = 4,    
	GLOW_THICKNESS = 12,
	GLOW_OPACITY = 0.6,
	DOT_CORE_SIZE = 8,
	DOT_GLOW_SIZE = 24,
	
	-- Colors
	SECTOR_COLORS = {
		Food = Color3.fromRGB(227, 119, 194),
		Animals = Color3.fromRGB(44, 160, 44),
		Entertainment = Color3.fromRGB(255, 127, 14),
		Mystic = Color3.fromRGB(148, 103, 189),
		Tech = Color3.fromRGB(31, 119, 180),
		Action = Color3.fromRGB(214, 39, 40),
	},
	MAX_HISTORY = 60,
}

local SECTOR_ORDER = {"Food", "Animals", "Entertainment", "Mystic", "Tech", "Action"}

--------------------------------------------------------------------------------
-- DataBuffer Class
--------------------------------------------------------------------------------

export type DataBufferImpl = {
	buffer: {number},
	capacity: number,
	count: number,
}

local DataBuffer = {}
DataBuffer.__index = DataBuffer

function DataBuffer.new(capacity: number): DataBufferImpl
	local self = setmetatable({}, DataBuffer) :: any
	self.buffer = table.create(capacity, 1.0)
	self.capacity = capacity
	self.count = 0
	return self :: DataBufferImpl
end

function DataBuffer.ParseAndUpdate(self: DataBufferImpl, historyStr: string)
	if not historyStr or historyStr == "" then return end
	local index = 0
	for value in string.gmatch(historyStr, "[^,]+") do
		index += 1
		local num = tonumber(value)
		if num and index <= self.capacity then
			self.buffer[index] = num
		end
	end
	self.count = index
end

function DataBuffer.GetPoints(self: DataBufferImpl): {number}
	local result = {}
	for i = 1, self.count do result[i] = self.buffer[i] end
	return result
end

function DataBuffer.GetCount(self: DataBufferImpl): number
	return self.count
end

--------------------------------------------------------------------------------
-- GraphViewport Class
--------------------------------------------------------------------------------

export type ViewportImpl = {
	width: number,
	height: number,
	padding: number,
	minRate: number,
	maxRate: number,
	pointCount: number,
}

local GraphViewport = {}
GraphViewport.__index = GraphViewport

function GraphViewport.new(width: number, height: number, padding: number): ViewportImpl
	local self = setmetatable({}, GraphViewport) :: any
	self.width = width
	self.height = height
	self.padding = padding
	self.minRate = 0.5
	self.maxRate = 3.0
	self.pointCount = 60
	return self :: ViewportImpl
end

function GraphViewport.SetBounds(self: ViewportImpl, minRate: number, maxRate: number, pointCount: number)
	self.minRate = minRate
	self.maxRate = maxRate
	self.pointCount = math.max(2, pointCount)
end

function GraphViewport.ToPixelCoords(self: ViewportImpl, index: number, rate: number): Vector2
	local usableWidth = self.width - (self.padding * 2)
	local usableHeight = self.height - (self.padding * 2)
	
	local spacing = usableWidth / math.max(1, self.pointCount - 1)
	local x = self.padding + (index - 1) * spacing
	
	local normalized = (rate - self.minRate) / (self.maxRate - self.minRate)
	local y = self.padding + (1 - normalized) * usableHeight
	
	return Vector2.new(x, y)
end

--------------------------------------------------------------------------------
-- Billboard Display Management
--------------------------------------------------------------------------------

type BillboardDisplay = {
	container: Frame,
	graphLines: Frame,
	rateDisplay: TextLabel?,
	rateName: TextLabel?,
	timerDisplay: TextLabel?,
	viewport: ViewportImpl,
	-- Object Pools
	linePool: {{glow: Frame, core: Frame}},
	dotPool: {{glow: Frame, core: Frame}},
}

local billboardDisplays: {BillboardDisplay} = {}
local sectorBuffers: {[string]: DataBufferImpl} = {}
local stockMarketFolder: Folder? = nil

for _, sector in SECTOR_ORDER do
	sectorBuffers[sector] = DataBuffer.new(CONFIG.MAX_HISTORY)
end

local function findBillboards()
	billboardDisplays = {}
	local billboardsFolder = Workspace:WaitForChild("StockMarketBillboards", 30)
	if not billboardsFolder then return end
	
	for _, billboard in billboardsFolder:GetChildren() do
		local screen = billboard:FindFirstChild("Screen")
		if not screen then continue end
		
		local surfaceGui = screen:FindFirstChild("StockMarketDisplay")
		if not surfaceGui then continue end
		
		local container = surfaceGui:FindFirstChild("Container")
		local graphContainer = container and container:FindFirstChild("GraphContainer")
		local graphLines = graphContainer and graphContainer:FindFirstChild("GraphLines") :: Frame?
		
		if graphLines then
			-- Clear any legacy EditableImage objects
			for _, child in graphLines:GetChildren() do child:Destroy() end
			
			local display: BillboardDisplay = {
				container = container :: Frame,
				graphLines = graphLines,
				rateDisplay = container:FindFirstChild("RateDisplay") :: TextLabel?,
				rateName = container:FindFirstChild("RateName") :: TextLabel?,
				timerDisplay = container:FindFirstChild("TimerDisplay") :: TextLabel?,
				viewport = GraphViewport.new(CONFIG.CANVAS_WIDTH, CONFIG.CANVAS_HEIGHT, CONFIG.PADDING),
				linePool = {},
				dotPool = {},
			}
			table.insert(billboardDisplays, display)
		end
	end
end

local function getRateColor(rate: number): Color3
	if rate >= 2.0 then return Color3.fromRGB(255, 215, 0)
	elseif rate >= 1.0 then return Color3.fromRGB(100, 255, 100)
	else return Color3.fromRGB(255, 70, 70) end
end

--------------------------------------------------------------------------------
-- CORE DRAWING LOGIC (With Strict Object Pooling)
--------------------------------------------------------------------------------

local function drawGraph(display: BillboardDisplay)
	if not stockMarketFolder then return end
	
	local minRate = stockMarketFolder:GetAttribute("MinRate") :: number? or 0.5
	local maxRate = stockMarketFolder:GetAttribute("MaxRate") :: number? or 3.0
	
	local firstBuffer = sectorBuffers[SECTOR_ORDER[1]]
	local pointCount = DataBuffer.GetCount(firstBuffer)
	
	if pointCount < 2 then return end
	GraphViewport.SetBounds(display.viewport, minRate, maxRate, pointCount)
	
	local bestSector = SECTOR_ORDER[1]
	local bestRate = 0
	
	local activeLineIndex = 0
	local activeDotIndex = 0
	
	for _, sector in ipairs(SECTOR_ORDER) do
		local buffer = sectorBuffers[sector]
		local rates = DataBuffer.GetPoints(buffer)
		local count = DataBuffer.GetCount(buffer)
		
		if count >= 2 then
			local points = {}
			for j = 1, count do
				points[j] = GraphViewport.ToPixelCoords(display.viewport, j, rates[j])
			end
			
			local color = CONFIG.SECTOR_COLORS[sector] or Color3.fromRGB(200, 200, 200)
			
			-- Render Line Segments
			for i = 1, #points - 1 do
				activeLineIndex += 1
				local p1 = points[i]
				local p2 = points[i + 1]
				
				local distance = (p2 - p1).Magnitude
				local center = (p1 + p2) / 2
				local rotation = math.deg(math.atan2(p2.Y - p1.Y, p2.X - p1.X))
				
				local segment = display.linePool[activeLineIndex]
				if not segment then
					local glow = Instance.new("Frame")
					glow.BorderSizePixel = 0
					glow.AnchorPoint = Vector2.new(0.5, 0.5)
					Instance.new("UICorner", glow).CornerRadius = UDim.new(0.5, 0)
					glow.Parent = display.graphLines
					
					local core = Instance.new("Frame")
					core.BorderSizePixel = 0
					core.AnchorPoint = Vector2.new(0.5, 0.5)
					Instance.new("UICorner", core).CornerRadius = UDim.new(0.5, 0)
					core.Parent = display.graphLines
					
					segment = {glow = glow, core = core}
					display.linePool[activeLineIndex] = segment
				end
				
				-- Set Glow
				segment.glow.Visible = true
				segment.glow.BackgroundColor3 = color
				segment.glow.BackgroundTransparency = CONFIG.GLOW_OPACITY
				segment.glow.Position = UDim2.new(0, center.X, 0, center.Y)
				segment.glow.Size = UDim2.new(0, distance, 0, CONFIG.GLOW_THICKNESS)
				segment.glow.Rotation = rotation
				segment.glow.ZIndex = 1
				
				-- Set Core
				segment.core.Visible = true
				segment.core.BackgroundColor3 = color
				segment.core.BackgroundTransparency = 0
				segment.core.Position = UDim2.new(0, center.X, 0, center.Y)
				segment.core.Size = UDim2.new(0, distance, 0, CONFIG.CORE_THICKNESS)
				segment.core.Rotation = rotation
				segment.core.ZIndex = 2
			end
			
			-- Render Current Dot
			if #points > 0 then
				activeDotIndex += 1
				local lastPoint = points[#points]
				
				local dot = display.dotPool[activeDotIndex]
				if not dot then
					local glow = Instance.new("Frame")
					glow.BorderSizePixel = 0
					glow.AnchorPoint = Vector2.new(0.5, 0.5)
					Instance.new("UICorner", glow).CornerRadius = UDim.new(0.5, 0)
					glow.Parent = display.graphLines
					
					local core = Instance.new("Frame")
					core.BorderSizePixel = 0
					core.AnchorPoint = Vector2.new(0.5, 0.5)
					Instance.new("UICorner", core).CornerRadius = UDim.new(0.5, 0)
					core.Parent = display.graphLines
					
					dot = {glow = glow, core = core}
					display.dotPool[activeDotIndex] = dot
				end
				
				dot.glow.Visible = true
				dot.glow.BackgroundColor3 = color
				dot.glow.BackgroundTransparency = 0.4
				dot.glow.Position = UDim2.new(0, lastPoint.X, 0, lastPoint.Y)
				dot.glow.Size = UDim2.new(0, CONFIG.DOT_GLOW_SIZE, 0, CONFIG.DOT_GLOW_SIZE)
				dot.glow.ZIndex = 3
				
				dot.core.Visible = true
				dot.core.BackgroundColor3 = Color3.new(1, 1, 1)
				dot.core.BackgroundTransparency = 0
				dot.core.Position = UDim2.new(0, lastPoint.X, 0, lastPoint.Y)
				dot.core.Size = UDim2.new(0, CONFIG.DOT_CORE_SIZE, 0, CONFIG.DOT_CORE_SIZE)
				dot.core.ZIndex = 4
			end
			
			local currentRate = rates[count] or 1.0
			if currentRate > bestRate then
				bestRate = currentRate
				bestSector = sector
			end
		end
	end
	
	-- Hide all unused pooled objects
	for i = activeLineIndex + 1, #display.linePool do
		display.linePool[i].glow.Visible = false
		display.linePool[i].core.Visible = false
	end
	for i = activeDotIndex + 1, #display.dotPool do
		display.dotPool[i].glow.Visible = false
		display.dotPool[i].core.Visible = false
	end
	
	-- Update Labels
	if display.rateDisplay then
		display.rateDisplay.Text = string.format("BEST: %.2fx", bestRate)
		display.rateDisplay.TextColor3 = CONFIG.SECTOR_COLORS[bestSector] or getRateColor(bestRate)
	end
	if display.rateName then
		display.rateName.Text = bestSector:upper()
		display.rateName.TextColor3 = CONFIG.SECTOR_COLORS[bestSector] or getRateColor(bestRate)
	end
end

--------------------------------------------------------------------------------
-- REPLICATION HANDLING
--------------------------------------------------------------------------------

local function updateAllGraphs()
	for _, display in billboardDisplays do
		drawGraph(display)
	end
end

local function updateTimer()
	if not stockMarketFolder then return end
	local nextUpdate = stockMarketFolder:GetAttribute("NextUpdate") :: number? or 0
	local remaining = math.max(0, nextUpdate - os.time())
	
	for _, display in billboardDisplays do
		if display.timerDisplay then
			display.timerDisplay.Text = string.format("Next update in: %ds", remaining)
		end
	end
end

local function parseHistories()
	if not stockMarketFolder then return end
	local historiesJson = stockMarketFolder:GetAttribute("SectorHistories") :: string?
	if not historiesJson then return end
	
	local ok, histories = pcall(HttpService.JSONDecode, HttpService, historiesJson)
	if not ok or not histories then return end
	
	for sector, historyStr in pairs(histories) do
		local buffer = sectorBuffers[sector]
		if buffer then DataBuffer.ParseAndUpdate(buffer, historyStr) end
	end
end

local function onHistoryChanged()
	parseHistories()
	updateAllGraphs()
end

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------

local function initialize()
	stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket", 30) :: Folder?
	if not stockMarketFolder then return end
	
	task.wait(4)
	findBillboards()
	
	parseHistories()
	updateAllGraphs()
	
	stockMarketFolder:GetAttributeChangedSignal("SectorHistories"):Connect(onHistoryChanged)
	RunService.Heartbeat:Connect(updateTimer)
end

task.spawn(initialize)