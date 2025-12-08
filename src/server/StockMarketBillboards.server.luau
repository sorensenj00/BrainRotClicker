--[[
	StockMarketBillboards Server Script
	
	Creates 4 giant floating billboards above the Main Island
	that display the stock market graph.
	
	Billboard positions: North, South, East, West - all facing the center
]]

-- Services
local Workspace = game:GetService("Workspace")

-- Configuration
local BILLBOARD_CONFIG = {
	SIZE = Vector3.new(80, 60, 2),     -- 80 wide, 60 tall, 2 thick
	HEIGHT_OFFSET = 120,                -- Height above MainIsland
	DISTANCE_FROM_CENTER = 150,         -- Distance from island center
	
	-- Colors
	FRAME_COLOR = Color3.fromRGB(30, 30, 40),
	SCREEN_COLOR = Color3.fromRGB(15, 15, 25),
}

-- Billboard positions relative to center (X, Z offsets and Y rotation)
local BILLBOARD_POSITIONS = {
	{ name = "North", offset = Vector3.new(0, 0, -BILLBOARD_CONFIG.DISTANCE_FROM_CENTER), rotation = 0 },
	{ name = "South", offset = Vector3.new(0, 0, BILLBOARD_CONFIG.DISTANCE_FROM_CENTER), rotation = 180 },
	{ name = "East", offset = Vector3.new(BILLBOARD_CONFIG.DISTANCE_FROM_CENTER, 0, 0), rotation = -90 },
	{ name = "West", offset = Vector3.new(-BILLBOARD_CONFIG.DISTANCE_FROM_CENTER, 0, 0), rotation = 90 },
}

--[[
	Creates a single billboard at the specified position.
]]
local function createBillboard(positionData: {name: string, offset: Vector3, rotation: number}, centerPosition: Vector3)
	-- Create the billboard model
	local billboardModel = Instance.new("Model")
	billboardModel.Name = "StockMarketBillboard_" .. positionData.name
	
	-- Create the main screen part
	local screenPart = Instance.new("Part")
	screenPart.Name = "Screen"
	screenPart.Size = BILLBOARD_CONFIG.SIZE
	screenPart.Anchored = true
	screenPart.CanCollide = false
	screenPart.Material = Enum.Material.Neon
	screenPart.Color = BILLBOARD_CONFIG.SCREEN_COLOR
	screenPart.CastShadow = false
	
	-- Position and rotate to face center
	local position = centerPosition + positionData.offset + Vector3.new(0, BILLBOARD_CONFIG.HEIGHT_OFFSET, 0)
	screenPart.CFrame = CFrame.new(position) * CFrame.Angles(0, math.rad(positionData.rotation), 0)
	screenPart.Parent = billboardModel
	
	-- Create frame/border around the screen
	local frameThickness = 2
	local frameColor = BILLBOARD_CONFIG.FRAME_COLOR
	
	-- Top frame
	local topFrame = Instance.new("Part")
	topFrame.Name = "TopFrame"
	topFrame.Size = Vector3.new(BILLBOARD_CONFIG.SIZE.X + frameThickness * 2, frameThickness, BILLBOARD_CONFIG.SIZE.Z)
	topFrame.Anchored = true
	topFrame.CanCollide = false
	topFrame.Material = Enum.Material.Metal
	topFrame.Color = frameColor
	topFrame.CFrame = screenPart.CFrame * CFrame.new(0, BILLBOARD_CONFIG.SIZE.Y / 2 + frameThickness / 2, 0)
	topFrame.Parent = billboardModel
	
	-- Bottom frame
	local bottomFrame = Instance.new("Part")
	bottomFrame.Name = "BottomFrame"
	bottomFrame.Size = Vector3.new(BILLBOARD_CONFIG.SIZE.X + frameThickness * 2, frameThickness, BILLBOARD_CONFIG.SIZE.Z)
	bottomFrame.Anchored = true
	bottomFrame.CanCollide = false
	bottomFrame.Material = Enum.Material.Metal
	bottomFrame.Color = frameColor
	bottomFrame.CFrame = screenPart.CFrame * CFrame.new(0, -BILLBOARD_CONFIG.SIZE.Y / 2 - frameThickness / 2, 0)
	bottomFrame.Parent = billboardModel
	
	-- Left frame
	local leftFrame = Instance.new("Part")
	leftFrame.Name = "LeftFrame"
	leftFrame.Size = Vector3.new(frameThickness, BILLBOARD_CONFIG.SIZE.Y, BILLBOARD_CONFIG.SIZE.Z)
	leftFrame.Anchored = true
	leftFrame.CanCollide = false
	leftFrame.Material = Enum.Material.Metal
	leftFrame.Color = frameColor
	leftFrame.CFrame = screenPart.CFrame * CFrame.new(-BILLBOARD_CONFIG.SIZE.X / 2 - frameThickness / 2, 0, 0)
	leftFrame.Parent = billboardModel
	
	-- Right frame
	local rightFrame = Instance.new("Part")
	rightFrame.Name = "RightFrame"
	rightFrame.Size = Vector3.new(frameThickness, BILLBOARD_CONFIG.SIZE.Y, BILLBOARD_CONFIG.SIZE.Z)
	rightFrame.Anchored = true
	rightFrame.CanCollide = false
	rightFrame.Material = Enum.Material.Metal
	rightFrame.Color = frameColor
	rightFrame.CFrame = screenPart.CFrame * CFrame.new(BILLBOARD_CONFIG.SIZE.X / 2 + frameThickness / 2, 0, 0)
	rightFrame.Parent = billboardModel
	
	-- Create SurfaceGui on the front face
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "StockMarketDisplay"
	surfaceGui.Face = Enum.NormalId.Front
	surfaceGui.CanvasSize = Vector2.new(1600, 1200) -- High resolution for detail
	surfaceGui.LightInfluence = 0
	surfaceGui.Brightness = 1
	surfaceGui.Parent = screenPart
	
	-- Create main container frame
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundColor3 = BILLBOARD_CONFIG.SCREEN_COLOR
	container.BorderSizePixel = 0
	container.Parent = surfaceGui
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.12, 0)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "📈 SAUCE MARKET"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.Parent = container
	
	-- Current rate display
	local rateDisplay = Instance.new("TextLabel")
	rateDisplay.Name = "RateDisplay"
	rateDisplay.Size = UDim2.new(0.4, 0, 0.15, 0)
	rateDisplay.Position = UDim2.new(0.05, 0, 0.12, 0)
	rateDisplay.BackgroundTransparency = 1
	rateDisplay.Text = "1.00x"
	rateDisplay.TextColor3 = Color3.fromRGB(100, 255, 100)
	rateDisplay.TextScaled = true
	rateDisplay.Font = Enum.Font.GothamBold
	rateDisplay.TextXAlignment = Enum.TextXAlignment.Left
	rateDisplay.Parent = container
	
	-- Rate name display
	local rateName = Instance.new("TextLabel")
	rateName.Name = "RateName"
	rateName.Size = UDim2.new(0.5, 0, 0.08, 0)
	rateName.Position = UDim2.new(0.45, 0, 0.16, 0)
	rateName.BackgroundTransparency = 1
	rateName.Text = "NORMAL"
	rateName.TextColor3 = Color3.fromRGB(180, 180, 180)
	rateName.TextScaled = true
	rateName.Font = Enum.Font.Gotham
	rateName.TextXAlignment = Enum.TextXAlignment.Right
	rateName.Parent = container
	
	-- Graph container
	local graphContainer = Instance.new("Frame")
	graphContainer.Name = "GraphContainer"
	graphContainer.Size = UDim2.new(0.9, 0, 0.6, 0)
	graphContainer.Position = UDim2.new(0.05, 0, 0.3, 0)
	graphContainer.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	graphContainer.BorderSizePixel = 0
	graphContainer.Parent = container
	
	local graphCorner = Instance.new("UICorner")
	graphCorner.CornerRadius = UDim.new(0, 10)
	graphCorner.Parent = graphContainer
	
	-- 1.0x baseline marker
	local baselineFrame = Instance.new("Frame")
	baselineFrame.Name = "Baseline"
	baselineFrame.Size = UDim2.new(1, 0, 0, 2)
	baselineFrame.Position = UDim2.new(0, 0, 0.4, 0) -- 1.0 is at 40% from top (since range is 0.5-3.0)
	baselineFrame.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	baselineFrame.BackgroundTransparency = 0.5
	baselineFrame.BorderSizePixel = 0
	baselineFrame.Parent = graphContainer
	
	-- Baseline label
	local baselineLabel = Instance.new("TextLabel")
	baselineLabel.Name = "BaselineLabel"
	baselineLabel.Size = UDim2.new(0.08, 0, 0.08, 0)
	baselineLabel.Position = UDim2.new(0.92, 0, 0.36, 0)
	baselineLabel.BackgroundTransparency = 1
	baselineLabel.Text = "1.0x"
	baselineLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	baselineLabel.TextScaled = true
	baselineLabel.Font = Enum.Font.Gotham
	baselineLabel.Parent = graphContainer
	
	-- Graph lines container (will be populated by client)
	local graphLines = Instance.new("Frame")
	graphLines.Name = "GraphLines"
	graphLines.Size = UDim2.new(1, 0, 1, 0)
	graphLines.BackgroundTransparency = 1
	graphLines.Parent = graphContainer
	
	-- Timer display
	local timerDisplay = Instance.new("TextLabel")
	timerDisplay.Name = "TimerDisplay"
	timerDisplay.Size = UDim2.new(1, 0, 0.08, 0)
	timerDisplay.Position = UDim2.new(0, 0, 0.92, 0)
	timerDisplay.BackgroundTransparency = 1
	timerDisplay.Text = "Next update in: 10s"
	timerDisplay.TextColor3 = Color3.fromRGB(150, 150, 150)
	timerDisplay.TextScaled = true
	timerDisplay.Font = Enum.Font.Gotham
	timerDisplay.Parent = container
	
	billboardModel.Parent = Workspace
	
	print(string.format("✓ Created %s billboard at position (%d, %d, %d)", 
		positionData.name, position.X, position.Y, position.Z))
	
	return billboardModel
end

--[[
	Initializes all 4 billboards above the Main Island.
]]
local function initialize()
	print("═══════════════════════════════════════════")
	print("   StockMarketBillboards - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Wait for main island
	task.wait(2)
	
	local mainIsland = Workspace:WaitForChild("MainIsland", 10)
	local centerPosition = Vector3.new(0, 30, 0) -- Default main island center
	
	if mainIsland then
		local islandPart = mainIsland:FindFirstChild("Island") or mainIsland:FindFirstChildWhichIsA("BasePart")
		if islandPart then
			centerPosition = Vector3.new(islandPart.Position.X, 30, islandPart.Position.Z)
		end
	end
	
	-- Create billboards folder
	local billboardsFolder = Instance.new("Folder")
	billboardsFolder.Name = "StockMarketBillboards"
	billboardsFolder.Parent = Workspace
	
	-- Create all 4 billboards
	for _, posData in ipairs(BILLBOARD_POSITIONS) do
		local billboard = createBillboard(posData, centerPosition)
		billboard.Parent = billboardsFolder
	end
	
	print("✓ StockMarketBillboards initialized (4 billboards created)")
	print("═══════════════════════════════════════════")
end

-- Start initialization
task.spawn(initialize)
