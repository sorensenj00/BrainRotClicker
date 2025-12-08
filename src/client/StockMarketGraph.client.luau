--!strict
--[[
	StockMarketGraph Client Script
	
	Procedural Geometry Architecture using EditableImage with scanline-based rendering.
	
	Classes:
	- DataBuffer: Circular buffer for rate history
	- GraphViewport: Coordinate transformation (rate/time to pixels)
	- MeshRenderer: Scanline-based rendering for filled quads and thick lines
	
	Uses modern EditableImage API:
	- AssetService:CreateEditableImage()
	- Content.fromObject() for ImageLabel binding
	- DrawLine() and DrawCircle() for geometry
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local AssetService = game:GetService("AssetService")

-- Configuration
local CONFIG = {
	-- Canvas size (matches SurfaceGui canvas)
	CANVAS_WIDTH = 1440,
	CANVAS_HEIGHT = 720,
	PADDING = 40,
	
	-- Graph appearance
	LINE_THICKNESS = 8,
	GLOW_THICKNESS = 20,
	GLOW_OPACITY = 0.7,
	
	-- Colors
	GREEN_COLOR = Color3.fromRGB(50, 255, 100),
	RED_COLOR = Color3.fromRGB(255, 70, 70),
	YELLOW_COLOR = Color3.fromRGB(255, 215, 0),
	FILL_OPACITY = 0.75,
	
	-- Buffer
	MAX_HISTORY = 60,
}

--------------------------------------------------------------------------------
-- DataBuffer Class: Circular buffer for rate history
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
	if not historyStr or historyStr == "" then
		return
	end
	
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
	for i = 1, self.count do
		result[i] = self.buffer[i]
	end
	return result
end

function DataBuffer.GetCount(self: DataBufferImpl): number
	return self.count
end

--------------------------------------------------------------------------------
-- GraphViewport Class: Coordinate transformation
--------------------------------------------------------------------------------

export type ViewportImpl = {
	width: number,
	height: number,
	paddingX: number,
	paddingY: number,
	minRate: number,
	maxRate: number,
	pointCount: number,
}

local GraphViewport = {}
GraphViewport.__index = GraphViewport

function GraphViewport.new(width: number, height: number, paddingX: number, paddingY: number): ViewportImpl
	local self = setmetatable({}, GraphViewport) :: any
	self.width = width
	self.height = height
	self.paddingX = paddingX
	self.paddingY = paddingY
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

function GraphViewport.GetUsableWidth(self: ViewportImpl): number
	return self.width - self.paddingX * 2
end

function GraphViewport.GetUsableHeight(self: ViewportImpl): number
	return self.height - self.paddingY * 2
end

function GraphViewport.GetBottomY(self: ViewportImpl): number
	return self.height - self.paddingY
end

function GraphViewport.RateToY(self: ViewportImpl, rate: number): number
	local usableHeight = GraphViewport.GetUsableHeight(self)
	local normalized = (rate - self.minRate) / (self.maxRate - self.minRate)
	return self.paddingY + (1 - normalized) * usableHeight
end

function GraphViewport.IndexToX(self: ViewportImpl, index: number): number
	local usableWidth = GraphViewport.GetUsableWidth(self)
	local spacing = usableWidth / math.max(1, self.pointCount - 1)
	return self.paddingX + (index - 1) * spacing
end

function GraphViewport.ToPixelCoords(self: ViewportImpl, index: number, rate: number): Vector2
	return Vector2.new(
		GraphViewport.IndexToX(self, index),
		GraphViewport.RateToY(self, rate)
	)
end

--------------------------------------------------------------------------------
-- MeshRenderer Class: Scanline-based EditableImage rendering
--------------------------------------------------------------------------------

export type RendererImpl = {
	image: EditableImage?,
	viewport: ViewportImpl,
	width: number,
	height: number,
}

local MeshRenderer = {}
MeshRenderer.__index = MeshRenderer

function MeshRenderer.new(viewport: ViewportImpl, width: number, height: number): RendererImpl
	local self = setmetatable({}, MeshRenderer) :: any
	self.viewport = viewport
	self.width = width
	self.height = height
	self.image = nil
	return self :: RendererImpl
end

function MeshRenderer.Initialize(self: RendererImpl): boolean
	local success, result = pcall(function()
		return AssetService:CreateEditableImage({
			Size = Vector2.new(self.width, self.height)
		})
	end)
	
	if not success then
		warn("MeshRenderer: Failed to create EditableImage:", result)
		return false
	end
	
	self.image = result :: EditableImage
	return true
end

function MeshRenderer.Clear(self: RendererImpl)
	if not self.image then return end
	
	-- Fill with transparent black
	self.image:DrawRectangle(
		Vector2.new(0, 0),
		Vector2.new(self.width, self.height),
		Color3.new(0, 0, 0),
		1, -- Fully transparent
		Enum.ImageCombineType.Overwrite
	)
end

function MeshRenderer.GetRateColor(rate: number): Color3
	if rate >= 2.0 then
		return CONFIG.YELLOW_COLOR
	elseif rate >= 1.0 then
		return CONFIG.GREEN_COLOR
	else
		return CONFIG.RED_COLOR
	end
end

--[[
	Draws a filled quad (4-sided polygon) using multiple horizontal lines.
	This is a fallback since DrawTriangle doesn't exist in the current API.
	Vertices should be in order: p1 -> p2 -> p3 -> p4 (forming a quad)
]]
function MeshRenderer.DrawQuad(
	self: RendererImpl,
	p1: Vector2,
	p2: Vector2,
	p3: Vector2,
	p4: Vector2,
	color: Color3,
	transparency: number
)
	if not self.image then return end
	
	-- Find bounding box
	local minY = math.floor(math.min(p1.Y, p2.Y, p3.Y, p4.Y))
	local maxY = math.ceil(math.max(p1.Y, p2.Y, p3.Y, p4.Y))
	
	-- Clamp to image bounds
	minY = math.max(0, minY)
	maxY = math.min(self.height - 1, maxY)
	
	-- For each scanline, find intersections with quad edges and fill
	local edges = {
		{p1, p2},
		{p2, p3},
		{p3, p4},
		{p4, p1}
	}
	
	for y = minY, maxY do
		local intersections: {number} = {}
		
		for _, edge in edges do
			local a, b = edge[1], edge[2]
			-- Check if this edge crosses the scanline
			if (a.Y <= y and b.Y > y) or (b.Y <= y and a.Y > y) then
				-- Calculate x intersection using linear interpolation
				local t = (y - a.Y) / (b.Y - a.Y)
				local x = a.X + t * (b.X - a.X)
				table.insert(intersections, x)
			end
		end
		
		-- Sort intersections and draw between pairs
		table.sort(intersections)
		
		for i = 1, #intersections - 1, 2 do
			local x1 = math.floor(intersections[i])
			local x2 = math.ceil(intersections[i + 1])
			
			-- Clamp to image bounds
			x1 = math.max(0, x1)
			x2 = math.min(self.width - 1, x2)
			
			if x2 > x1 then
				-- Draw horizontal line segment using DrawLine
				self.image:DrawLine(
					Vector2.new(x1, y),
					Vector2.new(x2, y),
					color,
					transparency,
					Enum.ImageCombineType.AlphaBlend
				)
			end
		end
	end
end

--[[
	Calculates the perpendicular normal vector for a line segment.
	Returns a unit vector perpendicular to the line from p1 to p2.
]]
local function calculateNormal(p1: Vector2, p2: Vector2): Vector2
	local dx = p2.X - p1.X
	local dy = p2.Y - p1.Y
	local length = math.sqrt(dx * dx + dy * dy)
	
	if length < 0.001 then
		return Vector2.new(0, 1) -- Default up if points are same
	end
	
	-- Perpendicular vector (rotate 90 degrees)
	return Vector2.new(-dy / length, dx / length)
end

--[[
	Draws a thick line segment as a quad using the normal vector for thickness.
	The quad has 4 corners offset from the line by half-thickness in the normal direction.
]]
function MeshRenderer.DrawThickLine(
	self: RendererImpl,
	p1: Vector2,
	p2: Vector2,
	color: Color3,
	thickness: number,
	transparency: number
)
	if not self.image then return end
	
	local normal = calculateNormal(p1, p2)
	local halfThickness = thickness / 2
	local offset = normal * halfThickness
	
	-- Calculate 4 corners of the line quad
	-- Corner order: top-left, top-right, bottom-right, bottom-left
	local c1 = p1 + offset  -- Start top
	local c2 = p2 + offset  -- End top
	local c3 = p2 - offset  -- End bottom
	local c4 = p1 - offset  -- Start bottom
	
	MeshRenderer.DrawQuad(self, c1, c2, c3, c4, color, transparency)
end

--[[
	Draws the gradient fill under a line segment.
	Creates a quad from the line segment down to the bottom of the graph.
]]
function MeshRenderer.DrawFillSegment(
	self: RendererImpl,
	p1: Vector2,
	p2: Vector2,
	bottomY: number,
	color: Color3,
	transparency: number
)
	if not self.image then return end
	
	-- Create quad from line segment to bottom
	local bottom1 = Vector2.new(p1.X, bottomY)
	local bottom2 = Vector2.new(p2.X, bottomY)
	
	-- Draw the fill quad (line on top, bottom edge at bottomY)
	MeshRenderer.DrawQuad(self, p1, p2, bottom2, bottom1, color, transparency)
end

--[[
	Draws the complete polyline with:
	1. Gradient fill under the line
	2. Glow layer (wider, lower opacity)
	3. Main stroke layer
]]
function MeshRenderer.DrawPolyline(self: RendererImpl, points: {Vector2}, rates: {number})
	if not self.image or #points < 2 then return end
	
	local bottomY = GraphViewport.GetBottomY(self.viewport)
	
	-- Pre-calculate colors for each segment
	local colors: {Color3} = {}
	for i = 1, #points - 1 do
		local avgRate = (rates[i] + rates[i + 1]) / 2
		colors[i] = MeshRenderer.GetRateColor(avgRate)
	end
	
	-- Layer 1: Gradient fill (bottom layer)
	for i = 1, #points - 1 do
		MeshRenderer.DrawFillSegment(self, points[i], points[i + 1], bottomY, colors[i], CONFIG.FILL_OPACITY)
	end
	
	-- Layer 2: Glow (wider, more transparent)
	for i = 1, #points - 1 do
		MeshRenderer.DrawThickLine(self, points[i], points[i + 1], colors[i], CONFIG.GLOW_THICKNESS, CONFIG.GLOW_OPACITY)
	end
	
	-- Layer 3: Main stroke (sharp, opaque)
	for i = 1, #points - 1 do
		MeshRenderer.DrawThickLine(self, points[i], points[i + 1], colors[i], CONFIG.LINE_THICKNESS, 0)
	end
end

--[[
	Draws a highlighted dot at the current position.
]]
function MeshRenderer.DrawCurrentDot(self: RendererImpl, pos: Vector2, color: Color3)
	if not self.image then return end
	
	-- Draw glow circle
	self.image:DrawCircle(pos, 18, color, 0.6, Enum.ImageCombineType.AlphaBlend)
	-- Draw main circle
	self.image:DrawCircle(pos, 12, color, 0, Enum.ImageCombineType.AlphaBlend)
	-- Draw white center
	self.image:DrawCircle(pos, 5, Color3.new(1, 1, 1), 0, Enum.ImageCombineType.AlphaBlend)
end

function MeshRenderer.GetImage(self: RendererImpl): EditableImage?
	return self.image
end

--------------------------------------------------------------------------------
-- Billboard Display Management
--------------------------------------------------------------------------------

type BillboardDisplay = {
	container: Frame,
	graphImageLabel: ImageLabel?,
	rateDisplay: TextLabel?,
	rateName: TextLabel?,
	timerDisplay: TextLabel?,
	renderer: RendererImpl?,
}

local billboardDisplays: {BillboardDisplay} = {}
local dataBuffer: DataBufferImpl = DataBuffer.new(CONFIG.MAX_HISTORY)
local stockMarketFolder: Folder? = nil

--[[
	Creates an ImageLabel for the EditableImage and attaches it.
]]
local function setupImageLabel(graphLines: Frame, renderer: RendererImpl): ImageLabel?
	-- Remove any existing ImageLabel
	local existing = graphLines:FindFirstChildOfClass("ImageLabel")
	if existing then
		existing:Destroy()
	end
	
	-- Create new ImageLabel
	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "GraphImage"
	imageLabel.Size = UDim2.new(1, 0, 1, 0)
	imageLabel.BackgroundTransparency = 1
	imageLabel.ScaleType = Enum.ScaleType.Stretch
	imageLabel.Parent = graphLines
	
	-- Attach EditableImage using Content.fromObject
	local editableImage = renderer.image
	if editableImage then
		imageLabel.ImageContent = Content.fromObject(editableImage)
	end
	
	return imageLabel
end

--[[
	Finds all billboard displays and sets up EditableImage rendering.
]]
local function findBillboards()
	billboardDisplays = {}
	
	local billboardsFolder = Workspace:WaitForChild("StockMarketBillboards", 30)
	if not billboardsFolder then
		warn("StockMarketGraph: Billboards folder not found!")
		return
	end
	
	for _, billboard in billboardsFolder:GetChildren() do
		local screen = billboard:FindFirstChild("Screen")
		if not screen then continue end
		
		local surfaceGui = screen:FindFirstChild("StockMarketDisplay")
		if not surfaceGui then continue end
		
		local container = surfaceGui:FindFirstChild("Container")
		if not container then continue end
		
		local graphContainer = container:FindFirstChild("GraphContainer")
		if not graphContainer then continue end
		
		local graphLines = graphContainer:FindFirstChild("GraphLines") :: Frame?
		if not graphLines then continue end
		
		-- Create viewport and renderer
		local viewport = GraphViewport.new(CONFIG.CANVAS_WIDTH, CONFIG.CANVAS_HEIGHT, CONFIG.PADDING, CONFIG.PADDING)
		local renderer = MeshRenderer.new(viewport, CONFIG.CANVAS_WIDTH, CONFIG.CANVAS_HEIGHT)
		
		local graphImageLabel: ImageLabel? = nil
		
		if MeshRenderer.Initialize(renderer) then
			graphImageLabel = setupImageLabel(graphLines, renderer)
			print("StockMarketGraph: Initialized EditableImage for billboard")
		else
			warn("StockMarketGraph: Failed to initialize renderer for billboard")
		end
		
		local display: BillboardDisplay = {
			container = container :: Frame,
			graphImageLabel = graphImageLabel,
			rateDisplay = container:FindFirstChild("RateDisplay") :: TextLabel?,
			rateName = container:FindFirstChild("RateName") :: TextLabel?,
			timerDisplay = container:FindFirstChild("TimerDisplay") :: TextLabel?,
			renderer = renderer,
		}
		
		table.insert(billboardDisplays, display)
	end
	
	print(string.format("StockMarketGraph: Found %d billboard displays", #billboardDisplays))
end

--[[
	Gets rate color for text labels.
]]
local function getRateColor(rate: number): Color3
	if rate >= 2.0 then
		return CONFIG.YELLOW_COLOR
	elseif rate >= 1.0 then
		return CONFIG.GREEN_COLOR
	else
		return CONFIG.RED_COLOR
	end
end

--[[
	Redraws the graph on a single billboard.
]]
local function drawGraph(display: BillboardDisplay)
	local renderer = display.renderer
	if not renderer or not renderer.image then return end
	if not stockMarketFolder then return end
	
	-- Get current attributes
	local currentRate = stockMarketFolder:GetAttribute("CurrentRate") :: number? or 1.0
	local rateNameAttr = stockMarketFolder:GetAttribute("RateName") :: string? or "NORMAL"
	local minRate = stockMarketFolder:GetAttribute("MinRate") :: number? or 0.5
	local maxRate = stockMarketFolder:GetAttribute("MaxRate") :: number? or 3.0
	
	local rates = DataBuffer.GetPoints(dataBuffer)
	local pointCount = DataBuffer.GetCount(dataBuffer)
	
	if pointCount < 2 then return end
	
	-- Update viewport bounds
	GraphViewport.SetBounds(renderer.viewport, minRate, maxRate, pointCount)
	
	-- Convert rates to pixel coordinates
	local points: {Vector2} = {}
	for i = 1, pointCount do
		points[i] = GraphViewport.ToPixelCoords(renderer.viewport, i, rates[i])
	end
	
	-- Clear and redraw
	MeshRenderer.Clear(renderer)
	MeshRenderer.DrawPolyline(renderer, points, rates)
	
	-- Draw current value dot
	if #points > 0 then
		local lastPoint = points[#points]
		local lastRate = rates[#rates]
		MeshRenderer.DrawCurrentDot(renderer, lastPoint, MeshRenderer.GetRateColor(lastRate))
	end
	
	-- Update text labels
	if display.rateDisplay then
		display.rateDisplay.Text = string.format("%.2fx", currentRate)
		display.rateDisplay.TextColor3 = getRateColor(currentRate)
	end
	
	if display.rateName then
		display.rateName.Text = rateNameAttr
		display.rateName.TextColor3 = getRateColor(currentRate)
	end
end

--[[
	Updates all billboard graphs.
]]
local function updateAllGraphs()
	for _, display in billboardDisplays do
		drawGraph(display)
	end
end

--[[
	Updates the timer display on all billboards.
]]
local function updateTimer()
	if not stockMarketFolder then return end
	
	local nextUpdate = stockMarketFolder:GetAttribute("NextUpdate") :: number? or 0
	local now = os.time()
	local remaining = math.max(0, nextUpdate - now)
	
	for _, display in billboardDisplays do
		if display.timerDisplay then
			display.timerDisplay.Text = string.format("Next update: %ds", remaining)
		end
	end
end

--[[
	Handles rate history updates from the server.
]]
local function onHistoryChanged()
	if not stockMarketFolder then return end
	
	local historyStr = stockMarketFolder:GetAttribute("RateHistory") :: string?
	if historyStr then
		DataBuffer.ParseAndUpdate(dataBuffer, historyStr)
		updateAllGraphs()
	end
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local function initialize()
	print("StockMarketGraph: Initializing with EditableImage (Triangle-based)...")
	
	-- Wait for StockMarket folder
	stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket", 30) :: Folder?
	if not stockMarketFolder then
		warn("StockMarketGraph: StockMarket folder not found!")
		return
	end
	
	-- Wait for billboards to be created
	task.wait(4)
	
	-- Find and setup billboard displays
	findBillboards()
	
	if #billboardDisplays == 0 then
		warn("StockMarketGraph: No billboard displays found!")
		return
	end
	
	-- Initial parse and draw
	local historyStr = stockMarketFolder:GetAttribute("RateHistory") :: string?
	if historyStr then
		DataBuffer.ParseAndUpdate(dataBuffer, historyStr)
	end
	updateAllGraphs()
	
	-- Listen for rate history changes
	stockMarketFolder:GetAttributeChangedSignal("RateHistory"):Connect(onHistoryChanged)
	
	-- Timer update loop
	RunService.Heartbeat:Connect(updateTimer)
	
	print("✓ StockMarketGraph initialized with Triangle-based EditableImage")
end

-- Start
task.spawn(initialize)
