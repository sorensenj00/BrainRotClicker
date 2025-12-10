--[[
	BuildModeUI Client Script
	
	"Architect Overlay" interface for placing and arranging brainrots.
	
	Features:
	- Press TAB to enter/exit Build Mode
	- Isometric camera view of plot
	- Grid visualization with drag-and-drop
	- Ghost preview when dragging units
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Wait for remotes
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local EnterBuildMode = RemoteFunctions:WaitForChild("EnterBuildMode")
local ExitBuildMode = RemoteFunctions:WaitForChild("ExitBuildMode")
local GetGrid = RemoteFunctions:WaitForChild("GetGrid")
local MoveUnit = RemoteFunctions:WaitForChild("MoveUnit")
local SwapUnits = RemoteFunctions:WaitForChild("SwapUnits")

-- Inventory remotes (RemoteFunctions but parented to RemoteEvents folder)
local GetInventoryRemote = RemoteEvents:WaitForChild("GetInventory")
local PlaceBrainrotRemote = RemoteEvents:WaitForChild("PlaceBrainrot")
local RemoveBrainrotRemote = RemoteEvents:WaitForChild("RemoveBrainrot")

-- Events
local InventoryChangedEvent = RemoteEvents:WaitForChild("InventoryChanged")
local _BuildModeChangedEvent = RemoteEvents:WaitForChild("BuildModeChanged")
local GridUpdatedEvent = RemoteEvents:WaitForChild("GridUpdated")

-- Configuration
local CONFIG = {
	-- Camera
	CAMERA_HEIGHT = 60,
	CAMERA_ANGLE = 45, -- degrees from horizontal
	CAMERA_TWEEN_TIME = 0.5,
	
	-- Grid
	TILE_SIZE = 10,
	TILE_HEIGHT = 0.1,
	
	-- Colors (more subtle)
	EMPTY_COLOR = Color3.fromRGB(100, 100, 150),
	OCCUPIED_COLOR = Color3.fromRGB(80, 200, 80),
	HOVER_COLOR = Color3.fromRGB(100, 200, 255),
	SELECTED_COLOR = Color3.fromRGB(255, 200, 50),
	INVALID_COLOR = Color3.fromRGB(255, 80, 80),
	SYNERGY_COLOR = Color3.fromRGB(200, 100, 255),
	
	-- UI
	TOOLBAR_HEIGHT = 80,
	BUTTON_SIZE = 60,
	INVENTORY_WIDTH = 280,
	
	-- Rarity colors
	RARITY_COLORS = {
		Normal = Color3.fromRGB(180, 180, 180),
		Spicy = Color3.fromRGB(255, 80, 80),
		Galaxy = Color3.fromRGB(180, 100, 255),
	},
}

-- State
local isInBuildMode = false
local savedCameraCFrame = nil
local gridTiles = {}
local gridContainer = nil
local buildModeGui = nil
local selectedSlot = nil
local hoveredSlot = nil
local isDragging = false
local currentHoverConnection = nil

-- Drag-drop state
local draggedUnit = nil  -- {name: string, rarity: string}
local inventoryPanel = nil
local inventoryData = {}  -- {[unitName]: {[rarity]: {total, active}}}

-- Placement ghost state
local placementGhost = nil  -- The ghost model in workspace
local ghostPulseTween = nil  -- Current pulse tween
local isGhostValid = false  -- Is ghost in a valid position
local dragConnection = nil  -- Mouse move connection during drag

-- Modules
local ViewportPreview = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ViewportPreview"))

-- Model folder for 3D previews
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")

-- Track inventory previews for cleanup
local inventoryPreviews = {}
-- Forward declarations
local exitBuildModeLocal
local refreshInventoryPanel
local getSlotUnderMouse
local renderBuildGrid
local startDrag
local completeDrop

-- Camera reference
local camera = workspace.CurrentCamera

--------------------------------------------------------------------------------
-- GRID VISUALIZATION
--------------------------------------------------------------------------------

--[[
	Finds all plots owned by the player.
]]
local function findAllPlayerPlots()
	local plots = {}
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return plots end
	
	for _, plot in plotsFolder:GetChildren() do
		if plot:GetAttribute("OwnerId") == LocalPlayer.UserId then
			table.insert(plots, plot)
		end
	end
	
	return plots
end

--[[
	Finds the island/plot the player is currently standing on.
	Uses raycast detection from player position.
]]
local function findCurrentIsland()
	local character = LocalPlayer.Character
	if not character then return nil end
	
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then return nil end
	
	local playerPos = humanoidRootPart.Position
	
	-- Get all player's plots
	local playerPlots = findAllPlayerPlots()
	if #playerPlots == 0 then return nil end
	
	-- Find which plot the player is standing on
	local closestPlot = nil
	local closestDistance = math.huge
	
	for _, plot in playerPlots do
		local floor = plot:FindFirstChild("Island") 
			or plot:FindFirstChild("PlotFloor") 
			or plot:FindFirstChild("Floor")
			or plot:FindFirstChildWhichIsA("BasePart")
		
		if floor then
			local floorPos = floor.Position
			local floorSize = floor.Size
			
			-- Check if player is within the plot bounds (XZ)
			local dx = math.abs(playerPos.X - floorPos.X)
			local dz = math.abs(playerPos.Z - floorPos.Z)
			
			if dx <= floorSize.X / 2 + 10 and dz <= floorSize.Z / 2 + 10 then
				-- Player is on or near this plot
				local distance = (playerPos - floorPos).Magnitude
				if distance < closestDistance then
					closestDistance = distance
					closestPlot = plot
				end
			end
		end
	end
	
	-- If not standing on any, return first plot as fallback
	if not closestPlot and #playerPlots > 0 then
		closestPlot = playerPlots[1]
	end
	
	return closestPlot
end

--[[
	Finds the player's plot (for backwards compatibility - returns current island).
]]
local function findPlayerPlot()
	return findCurrentIsland()
end

--[[
	Gets plot top surface position.
]]
local function getPlotTopCenter(plot)
	-- Try to find the main floor part (check multiple possible names)
	local floor = plot:FindFirstChild("Island") 
		or plot:FindFirstChild("PlotFloor") 
		or plot:FindFirstChild("Floor")
		or plot:FindFirstChildWhichIsA("BasePart")
	
	if floor and floor:IsA("BasePart") then
		return Vector3.new(floor.Position.X, floor.Position.Y + floor.Size.Y/2, floor.Position.Z)
	end
	
	if plot:IsA("Model") then
		local cf, size = plot:GetBoundingBox()
		return Vector3.new(cf.Position.X, cf.Position.Y + size.Y/2, cf.Position.Z)
	end
	
	if plot:IsA("BasePart") then
		return Vector3.new(plot.Position.X, plot.Position.Y + plot.Size.Y/2, plot.Position.Z)
	end
	
	return Vector3.new(0, 10, 0)
end

--[[
	Creates a grid tile part (invisible, outline-only for selection).
]]
local function createGridTile(slotIndex, position, isOccupied, unitName)
	local tile = Instance.new("Part")
	tile.Name = "BuildTile_" .. slotIndex
	tile.Size = Vector3.new(CONFIG.TILE_SIZE - 0.5, CONFIG.TILE_HEIGHT, CONFIG.TILE_SIZE - 0.5)
	tile.Position = position
	tile.Anchored = true
	tile.CanCollide = false
	tile.Transparency = 1  -- Fully invisible
	tile:SetAttribute("SlotIndex", slotIndex)
	tile:SetAttribute("IsOccupied", isOccupied)
	tile:SetAttribute("UnitName", unitName)
	
	-- Add border/outline effect (this is all we show)
	local selectionBox = Instance.new("SelectionBox")
	selectionBox.Name = "Outline"
	selectionBox.Adornee = tile
	selectionBox.Color3 = isOccupied and CONFIG.OCCUPIED_COLOR or CONFIG.EMPTY_COLOR
	selectionBox.LineThickness = 0.03
	selectionBox.Transparency = 0.3
	selectionBox.Parent = tile
	
	-- Slot number label (small, only for empty slots)
	if not isOccupied then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "SlotLabel"
		billboard.Size = UDim2.new(1, 0, 0.5, 0)
		billboard.StudsOffset = Vector3.new(0, 0.5, 0)
		billboard.AlwaysOnTop = false
		billboard.Parent = tile
		
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = tostring(slotIndex)
		label.TextColor3 = Color3.fromRGB(150, 150, 150)
		label.TextScaled = true
		label.Font = Enum.Font.Gotham
		label.TextStrokeTransparency = 0.5
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.Parent = billboard
	end
	
	return tile
end

--[[
	Renders the build mode grid using 4 corner clusters.
]]
renderBuildGrid = function()
	-- Get grid state from server (for tracking occupancy)
	local gridState = GetGrid:InvokeServer()
	if not gridState then return end
	
	local plot = findPlayerPlot()
	if not plot then return end
	
	-- Get plot info
	local floor = plot:FindFirstChild("Island") 
		or plot:FindFirstChild("PlotFloor") 
		or plot:FindFirstChild("Floor")
		or plot:FindFirstChildWhichIsA("BasePart")
	
	if not floor then return end
	
	local plotCenter = floor.Position
	local plotSize = floor.Size
	local plotTop = Vector3.new(plotCenter.X, plotCenter.Y + plotSize.Y/2, plotCenter.Z)
	local gridY = plotTop.Y + 0.5
	
	-- Clear any old grid container
	if gridContainer then
		gridContainer:Destroy()
	end
	
	gridContainer = Instance.new("Folder")
	gridContainer.Name = "BuildModeGrid"
	gridContainer.Parent = workspace
	
	-- Clear old tiles
	gridTiles = {}
	
	-- Corner cluster configuration (matches server)
	local CLUSTER_SIZE = 2  -- 2x2 per corner
	local TILE_SPACING = CONFIG.TILE_SIZE
	
	-- Calculate corner offsets (distance from center to corner cluster center)
	local cornerOffsetX = (plotSize.X / 2) - (CLUSTER_SIZE * TILE_SPACING / 2) - TILE_SPACING
	local cornerOffsetZ = (plotSize.Z / 2) - (CLUSTER_SIZE * TILE_SPACING / 2) - TILE_SPACING
	
	-- Corner base positions (relative to plot center)
	local cornerPositions = {
		{x = -cornerOffsetX, z = -cornerOffsetZ},  -- Top-left (slots 1-4)
		{x = cornerOffsetX, z = -cornerOffsetZ},   -- Top-right (slots 5-8)
		{x = -cornerOffsetX, z = cornerOffsetZ},   -- Bottom-left (slots 9-12)
		{x = cornerOffsetX, z = cornerOffsetZ},    -- Bottom-right (slots 13-16)
	}
	
	-- Create 16 tiles (4 corners x 4 slots each)
	for slotIndex = 1, 16 do
		local cornerIndex = math.floor((slotIndex - 1) / 4)
		local posInCorner = (slotIndex - 1) % 4
		
		local localRow = math.floor(posInCorner / 2)
		local localCol = posInCorner % 2
		
		local corner = cornerPositions[cornerIndex + 1]
		
		local posX = plotCenter.X + corner.x + (localCol - 0.5) * TILE_SPACING
		local posZ = plotCenter.Z + corner.z + (localRow - 0.5) * TILE_SPACING
		
		local unitName = gridState.slots[slotIndex]
		local isOccupied = unitName ~= nil
		local tile = createGridTile(slotIndex, Vector3.new(posX, gridY, posZ), isOccupied, unitName)
		tile.Parent = gridContainer
		
		gridTiles[slotIndex] = tile
	end
	
	print("BuildModeUI: Rendered 16 grid tiles (4 corners x 4 slots)")
	return plotTop
end

--[[
	Destroys the build grid.
]]
local function destroyBuildGrid()
	if gridContainer then
		gridContainer:Destroy()
		gridContainer = nil
		gridTiles = {}
	end
end

--[[
	Highlights a tile.
]]
local function highlightTile(slotIndex, color)
	local tile = gridTiles[slotIndex]
	if not tile then return end
	
	TweenService:Create(tile, TweenInfo.new(0.1), {
		Color = color,
		Transparency = 0.3
	}):Play()
	
	local outline = tile:FindFirstChild("Outline")
	if outline then
		outline.Color3 = color
		outline.Transparency = 0
	end
end

--[[
	Unhighlights a tile.
]]
local function unhighlightTile(slotIndex)
	local tile = gridTiles[slotIndex]
	if not tile then return end
	
	local isOccupied = tile:GetAttribute("IsOccupied")
	TweenService:Create(tile, TweenInfo.new(0.1), {
		Color = isOccupied and CONFIG.OCCUPIED_COLOR or CONFIG.EMPTY_COLOR,
		Transparency = 0.85
	}):Play()
	
	local outline = tile:FindFirstChild("Outline")
	if outline then
		outline.Color3 = Color3.fromRGB(200, 200, 200)
		outline.Transparency = 0.5
	end
end

--------------------------------------------------------------------------------
-- CAMERA CONTROLS
--------------------------------------------------------------------------------

--[[
	Tweens camera to isometric build view.
]]
local function tweenToIsometricView(plotCenter)
	savedCameraCFrame = camera.CFrame
	
	-- Calculate isometric camera position
	local angleRad = math.rad(CONFIG.CAMERA_ANGLE)
	local distance = CONFIG.CAMERA_HEIGHT / math.sin(angleRad)
	
	-- Position camera above and slightly back
	local cameraPos = plotCenter + Vector3.new(0, CONFIG.CAMERA_HEIGHT, distance * math.cos(angleRad))
	local targetCFrame = CFrame.new(cameraPos, plotCenter)
	
	-- Switch to scriptable camera
	camera.CameraType = Enum.CameraType.Scriptable
	
	-- Tween to position
	local tween = TweenService:Create(camera, TweenInfo.new(CONFIG.CAMERA_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = targetCFrame
	})
	tween:Play()
	
	print("BuildModeUI: Camera tweened to isometric view")
end

--[[
	Tweens camera back to player view.
]]
local function tweenToPlayerView()
	if not savedCameraCFrame then return end
	
	-- Tween back
	local tween = TweenService:Create(camera, TweenInfo.new(CONFIG.CAMERA_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = savedCameraCFrame
	})
	tween:Play()
	
	tween.Completed:Connect(function()
		camera.CameraType = Enum.CameraType.Custom
		savedCameraCFrame = nil
	end)
	
	print("BuildModeUI: Camera returned to player view")
end

--------------------------------------------------------------------------------
-- BUILD MODE UI
--------------------------------------------------------------------------------

--[[
	Creates the build mode UI overlay.
]]
local function createBuildModeUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuildModeUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 100
	
	-- Top bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 50)
	topBar.Position = UDim2.new(0, 0, 0, 0)
	topBar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	topBar.BorderSizePixel = 0
	topBar.Parent = screenGui
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0.5, 0, 1, 0)
	title.Position = UDim2.new(0, 20, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "🏗️ BUILD MODE"
	title.TextColor3 = Color3.fromRGB(255, 200, 50)
	title.TextSize = 24
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = topBar
	
	-- Instructions
	local instructions = Instance.new("TextLabel")
	instructions.Name = "Instructions"
	instructions.Size = UDim2.new(0.5, -20, 1, 0)
	instructions.Position = UDim2.new(0.5, 0, 0, 0)
	instructions.BackgroundTransparency = 1
	instructions.Text = "Click to select • Drag to move • G or ESC to exit"
	instructions.TextColor3 = Color3.fromRGB(180, 180, 180)
	instructions.TextSize = 14
	instructions.Font = Enum.Font.Gotham
	instructions.TextXAlignment = Enum.TextXAlignment.Right
	instructions.Parent = topBar
	
	-- Exit button
	local exitButton = Instance.new("TextButton")
	exitButton.Name = "ExitButton"
	exitButton.Size = UDim2.new(0, 100, 0, 36)
	exitButton.Position = UDim2.new(1, -120, 0.5, -18)
	exitButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	exitButton.Text = "✕ EXIT"
	exitButton.TextColor3 = Color3.new(1, 1, 1)
	exitButton.TextSize = 14
	exitButton.Font = Enum.Font.GothamBold
	exitButton.Parent = topBar
	
	local exitCorner = Instance.new("UICorner")
	exitCorner.CornerRadius = UDim.new(0, 8)
	exitCorner.Parent = exitButton
	
	-- Status bar at bottom
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(1, 0, 0, 40)
	bottomBar.Position = UDim2.new(0, 0, 1, -40)
	bottomBar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	bottomBar.BorderSizePixel = 0
	bottomBar.Parent = screenGui
	
	-- Status text
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -40, 1, 0)
	statusLabel.Position = UDim2.new(0, 20, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Select a tile to begin"
	statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	statusLabel.TextSize = 14
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = bottomBar
	
	return screenGui
end

--[[
	Updates the status text.
]]
local function updateStatus(text)
	if not buildModeGui then return end
	local bottomBar = buildModeGui:FindFirstChild("BottomBar")
	if bottomBar then
		local status = bottomBar:FindFirstChild("Status")
		if status then
			status.Text = text
		end
	end
end

--------------------------------------------------------------------------------
-- INVENTORY PANEL (for Build Mode)
--------------------------------------------------------------------------------

local RARITY_ORDER = {"Normal", "Spicy", "Galaxy"}
local inventoryItems = {}  -- UI item frames

--[[
	Creates an inventory item card for drag-and-drop.
]]
local function createInventoryCard(unitName, rarity, storedCount)
	local rarityColor = CONFIG.RARITY_COLORS[rarity] or Color3.fromRGB(180, 180, 180)
	
	local card = Instance.new("Frame")
	card.Name = unitName .. "_" .. rarity
	card.Size = UDim2.new(1, -10, 0, 50)
	card.BackgroundColor3 = Color3.fromRGB(50, 45, 65)
	card.BorderSizePixel = 0
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = card
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = rarityColor
	stroke.Thickness = 1
	stroke.Parent = card
	
	-- Icon
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 36, 0, 36)
	icon.Position = UDim2.new(0, 6, 0.5, -18)
	icon.BackgroundColor3 = Color3.fromRGB(35, 30, 45)
	icon.Text = "🧠"
	icon.TextSize = 18
	icon.TextColor3 = rarityColor
	icon.Parent = card
	
	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 4)
	iconCorner.Parent = icon
	
	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "UnitName"
	nameLabel.Size = UDim2.new(1, -100, 0, 20)
	nameLabel.Position = UDim2.new(0, 48, 0, 5)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = unitName
	nameLabel.TextColor3 = rarityColor
	nameLabel.TextSize = 12
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card
	
	-- Count
	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(0, 50, 0, 16)
	countLabel.Position = UDim2.new(0, 48, 0, 28)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = storedCount .. " stored"
	countLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	countLabel.TextSize = 10
	countLabel.Font = Enum.Font.Gotham
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.Parent = card
	
	-- Place button
	local placeBtn = Instance.new("TextButton")
	placeBtn.Name = "PlaceButton"
	placeBtn.Size = UDim2.new(0, 50, 0, 30)
	placeBtn.Position = UDim2.new(1, -60, 0.5, -15)
	placeBtn.BackgroundColor3 = storedCount > 0 and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(60, 60, 70)
	placeBtn.Text = "Place"
	placeBtn.TextColor3 = Color3.new(1, 1, 1)
	placeBtn.TextSize = 10
	placeBtn.Font = Enum.Font.GothamBold
	placeBtn.Active = storedCount > 0
	placeBtn.Parent = card
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = placeBtn
	
	-- Store metadata
	card:SetAttribute("UnitName", unitName)
	card:SetAttribute("Rarity", rarity)
	card:SetAttribute("StoredCount", storedCount)
	
	return card
end

--[[
	Creates the inventory panel for Build Mode.
]]
local function createInventoryPanel(parent)
	local panel = Instance.new("Frame")
	panel.Name = "InventoryPanel"
	panel.Size = UDim2.new(0, CONFIG.INVENTORY_WIDTH, 1, -100)
	panel.Position = UDim2.new(0, 10, 0, 55)
	panel.BackgroundColor3 = Color3.fromRGB(35, 30, 50)
	panel.BorderSizePixel = 0
	panel.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 80, 150)
	stroke.Thickness = 2
	stroke.Parent = panel
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 30)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "🧠 INVENTORY"
	title.TextColor3 = Color3.fromRGB(180, 140, 220)
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel
	
	-- Scrolling frame for items
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemsList"
	scrollFrame.Size = UDim2.new(1, -20, 1, -50)
	scrollFrame.Position = UDim2.new(0, 10, 0, 45)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 80, 150)
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent = panel
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.Name
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = scrollFrame
	
	-- Auto-resize canvas
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
	end)
	
	inventoryPanel = panel
	return panel
end

--[[
	Refreshes inventory panel with current data.
]]
refreshInventoryPanel = function()
	if not inventoryPanel then 
		return 
	end
	
	local scrollFrame = inventoryPanel:FindFirstChild("ItemsList")
	if not scrollFrame then 
		return 
	end
	
	-- Cleanup old 3D previews
	for _, preview in ipairs(inventoryPreviews) do
		if preview.Destroy then
			preview:Destroy()
		end
	end
	inventoryPreviews = {}
	
	-- Clear old items (keep TextLabels for empty message)
	for _, child in scrollFrame:GetChildren() do
		if child:IsA("Frame") or (child:IsA("TextLabel") and child.Name == "EmptyLabel") then
			child:Destroy()
		end
	end
	inventoryItems = {}
	
	-- Get inventory from server
	print("BuildModeUI: Invoking GetInventoryRemote")
	local result = GetInventoryRemote:InvokeServer()
	print("BuildModeUI: Got inventory result:", result)
	if not result or not result.units then 
		print("BuildModeUI: No inventory data!")
		return 
	end
	
	inventoryData = result.units
	print("BuildModeUI: inventoryData:", inventoryData)
	
	local cardCount = 0
	
	-- Create cards for each unit (show ALL - both stored and placed)
	for unitName, rarityData in pairs(inventoryData) do
		for _, rarity in RARITY_ORDER do
			local data = rarityData[rarity]
			if data and data.total > 0 then
				local storedCount = data.total - data.active
				local activeCount = data.active
				local rarityColor = CONFIG.RARITY_COLORS[rarity] or Color3.fromRGB(180, 180, 180)
				
				-- Create card
				local card = Instance.new("Frame")
				card.Name = unitName .. "_" .. rarity
				card.Size = UDim2.new(1, -10, 0, 60)
				card.BackgroundColor3 = Color3.fromRGB(50, 45, 65)
				card.BorderSizePixel = 0
				
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 6)
				corner.Parent = card
				
				local stroke = Instance.new("UIStroke")
				stroke.Color = rarityColor
				stroke.Thickness = 1
				stroke.Parent = card
				
				-- Icon container (Draggable)
				local iconFrame = Instance.new("Frame")
				iconFrame.Name = "IconFrame"
				iconFrame.Size = UDim2.new(0, 44, 0, 44)
				iconFrame.Position = UDim2.new(0, 4, 0.5, -22)
				iconFrame.BackgroundColor3 = Color3.fromRGB(35, 30, 45)
				iconFrame.Parent = card
				
				local iconCorner = Instance.new("UICorner")
				iconCorner.CornerRadius = UDim.new(0, 6)
				iconCorner.Parent = iconFrame
				
				-- Try to create 3D preview, fallback to emoji
				local brainrotTemplate = BrainrotsFolder:FindFirstChild(unitName)
				if brainrotTemplate then
					local preview = ViewportPreview.Create(brainrotTemplate, iconFrame)
					-- Store for cleanup
					if not inventoryPreviews then
						inventoryPreviews = {}
					end
					table.insert(inventoryPreviews, preview)
				else
					-- Fallback emoji
					local emoji = Instance.new("TextLabel")
					emoji.Size = UDim2.new(1, 0, 1, 0)
					emoji.BackgroundTransparency = 1
					emoji.Text = "🧠"
					emoji.TextSize = 22
					emoji.TextColor3 = rarityColor
					emoji.Parent = iconFrame
				end
				
				-- Invisible drag button overlay
				local dragButton = Instance.new("TextButton")
				dragButton.Name = "DragButton"
				dragButton.Size = UDim2.new(1, 0, 1, 0)
				dragButton.BackgroundTransparency = 1
				dragButton.Text = ""
				dragButton.Parent = iconFrame
				
				-- Connect drag to button
				dragButton.MouseButton1Down:Connect(function()
					if storedCount > 0 then
						startDrag(unitName, rarity)
					end
				end)
				
				-- Name
				local nameLabel = Instance.new("TextLabel")
				nameLabel.Name = "UnitName"
				nameLabel.Size = UDim2.new(1, -115, 0, 18)
				nameLabel.Position = UDim2.new(0, 48, 0, 5)
				nameLabel.BackgroundTransparency = 1
				nameLabel.Text = unitName
				nameLabel.TextColor3 = rarityColor
				nameLabel.TextSize = 11
				nameLabel.Font = Enum.Font.GothamBold
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
				nameLabel.Parent = card
				
				-- Status labels
				local statusLabel = Instance.new("TextLabel")
				statusLabel.Name = "Status"
				statusLabel.Size = UDim2.new(1, -115, 0, 14)
				statusLabel.Position = UDim2.new(0, 48, 0, 24)
				statusLabel.BackgroundTransparency = 1
				statusLabel.Text = activeCount .. " placed • " .. storedCount .. " stored"
				statusLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
				statusLabel.TextSize = 10
				statusLabel.Font = Enum.Font.Gotham
				statusLabel.TextXAlignment = Enum.TextXAlignment.Left
				statusLabel.Parent = card
				
				-- Button container
				local btnContainer = Instance.new("Frame")
				btnContainer.Name = "Buttons"
				btnContainer.Size = UDim2.new(0, 55, 0, 48)
				btnContainer.Position = UDim2.new(1, -62, 0.5, -24)
				btnContainer.BackgroundTransparency = 1
				btnContainer.Parent = card
				
				-- Place button
				local placeBtn = Instance.new("TextButton")
				placeBtn.Name = "PlaceButton"
				placeBtn.Size = UDim2.new(1, 0, 0, 22)
				placeBtn.Position = UDim2.new(0, 0, 0, 0)
				placeBtn.BackgroundColor3 = storedCount > 0 and Color3.fromRGB(80, 180, 80) or Color3.fromRGB(60, 60, 70)
				placeBtn.Text = "Place"
				placeBtn.TextColor3 = Color3.new(1, 1, 1)
				placeBtn.TextSize = 10
				placeBtn.Font = Enum.Font.GothamBold
				placeBtn.Active = storedCount > 0
				placeBtn.Parent = btnContainer
				
				local placeBtnCorner = Instance.new("UICorner")
				placeBtnCorner.CornerRadius = UDim.new(0, 4)
				placeBtnCorner.Parent = placeBtn
				
				-- Remove button
				local removeBtn = Instance.new("TextButton")
				removeBtn.Name = "RemoveButton"
				removeBtn.Size = UDim2.new(1, 0, 0, 22)
				removeBtn.Position = UDim2.new(0, 0, 0, 26)
				removeBtn.BackgroundColor3 = activeCount > 0 and Color3.fromRGB(180, 80, 80) or Color3.fromRGB(60, 60, 70)
				removeBtn.Text = "Remove"
				removeBtn.TextColor3 = Color3.new(1, 1, 1)
				removeBtn.TextSize = 10
				removeBtn.Font = Enum.Font.GothamBold
				removeBtn.Active = activeCount > 0
				removeBtn.Parent = btnContainer
				
				local removeBtnCorner = Instance.new("UICorner")
				removeBtnCorner.CornerRadius = UDim.new(0, 4)
				removeBtnCorner.Parent = removeBtn
				
				card.Parent = scrollFrame
				inventoryItems[unitName .. "_" .. rarity] = card
				cardCount = cardCount + 1
				
				-- Setup place/drag button - starts drag operation
				placeBtn.MouseButton1Down:Connect(function()
					print("BuildModeUI: Place button clicked for", unitName, "storedCount:", storedCount)
					if storedCount <= 0 then 
						print("BuildModeUI: No stored units, returning")
						return 
					end
					startDrag(unitName, rarity)
				end)
				
				-- Setup remove button
				removeBtn.MouseButton1Click:Connect(function()
					if activeCount <= 0 then return end
					
					local success, msg = RemoveBrainrotRemote:InvokeServer(unitName, rarity)
					if success then
						updateStatus("✓ Removed " .. unitName .. " to inventory")
						task.defer(renderBuildGrid)
						task.defer(refreshInventoryPanel)
					else
						updateStatus("✗ " .. (msg or "Remove failed"))
					end
				end)
			end
		end
	end
	
	-- Empty message if no brainrots
	if cardCount == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Name = "EmptyLabel"
		emptyLabel.Size = UDim2.new(1, 0, 0, 50)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Text = "No brainrots yet\nBuy from shop!"
		emptyLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
		emptyLabel.TextSize = 12
		emptyLabel.Font = Enum.Font.Gotham
		emptyLabel.Parent = scrollFrame
	end
end

--------------------------------------------------------------------------------
-- PLACEMENT GHOST SYSTEM
--------------------------------------------------------------------------------

-- Ghost colors
local GHOST_VALID_COLOR = Color3.fromRGB(100, 255, 100)
local GHOST_INVALID_COLOR = Color3.fromRGB(255, 80, 80)

--[[
	Gets the brainrot model from ReplicatedStorage.
]]
local function getBrainrotModel(unitName: string): Model?
	-- Check main Brainrots folder first (same as inventory preview)
	if BrainrotsFolder then
		local model = BrainrotsFolder:FindFirstChild(unitName)
		if model then return model end
	end
	
	-- Fallback: Check Units folder
	local unitsFolder = ReplicatedStorage:FindFirstChild("Units")
	if unitsFolder then
		local model = unitsFolder:FindFirstChild(unitName)
		if model then return model end
	end
	
	-- Fallback: Check Assets/Brainrots
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder then
		local brainrotsSubfolder = assetsFolder:FindFirstChild("Brainrots")
		if brainrotsSubfolder then
			local model = brainrotsSubfolder:FindFirstChild(unitName)
			if model then return model end
		end
	end
	
	return nil
end

--[[
	Sets transparency on all parts in a model (for ghost effects).
]]
local function setModelTransparency(model: Model, transparency: number)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = transparency
		end
	end
end

--[[
	Sets color on all parts in a model (for ghost effects).
]]
local function setModelColor(model: Model, color: Color3)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Color = color
		end
	end
	
	-- Also update highlight if present
	local highlight = model:FindFirstChildWhichIsA("Highlight")
	if highlight then
		highlight.FillColor = color
		highlight.OutlineColor = color
	end
end

--[[
	Creates a ghost preview using the MeshPart-only approach.
	Only MeshParts get the ghost effect - they contain actual visual geometry.
	Regular Parts (hitboxes, root parts, etc.) are kept fully invisible.
]]
local function createPlacementGhost(unitName: string): Model?
	local originalModel = getBrainrotModel(unitName)
	local ghost

	-- 1. Create the Clone
	if originalModel then
		ghost = originalModel:Clone()
	else
		-- Fallback if model is missing
		ghost = Instance.new("Model")
		local part = Instance.new("Part")
		part.Name = "FallbackGhost"
		part.Size = Vector3.new(3, 5, 3)
		part.Transparency = 0.5
		part.Color = GHOST_VALID_COLOR
		part.Material = Enum.Material.ForceField
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = false
		part.Parent = ghost
		ghost.PrimaryPart = part
		
		ghost.Name = "PlacementGhost"
		ghost.Parent = workspace
		placementGhost = ghost
		isGhostValid = true
		return ghost
	end

	ghost.Name = "PlacementGhost"

	-- 2. Clean up non-visual instances (Scripts, Sounds, etc.)
	for _, item in ghost:GetDescendants() do
		if item:IsA("Humanoid") 
			or item:IsA("LuaSourceContainer") -- All script types
			or item:IsA("Sound") 
			or item:IsA("Light") -- All light types
			or item:IsA("ParticleEmitter") 
			or item:IsA("Trail")
			or item:IsA("Beam")
			or item:IsA("Fire")
			or item:IsA("Smoke")
			or item:IsA("Sparkles")
			or item:IsA("BillboardGui")
			or item:IsA("SurfaceGui")
		then
			item:Destroy()
		end
	end

	-- 3. Apply Ghost Visuals - ONLY to MeshParts!
	-- MeshParts contain actual visual geometry (character models, etc.)
	-- Regular Parts are typically hitboxes, root parts, or other non-visual structure
	for _, part in ghost:GetDescendants() do
		if part:IsA("MeshPart") then
			-- MeshPart = actual visual geometry, apply ghost effect
			part.CanCollide = false
			part.CastShadow = false
			part.Anchored = true
			part.Transparency = 0.5
			part.Color = GHOST_VALID_COLOR
			part.Material = Enum.Material.ForceField
			
		elseif part:IsA("Part") or part:IsA("UnionOperation") or part:IsA("BasePart") then
			-- Regular Parts = hitboxes, root parts, etc. - keep invisible
			part.CanCollide = false
			part.CastShadow = false
			part.Anchored = true
			part.Transparency = 1
			
		elseif part:IsA("Decal") or part:IsA("Texture") then
			-- Hide decals on ghosts for cleaner look
			part.Transparency = 1
		end
	end

	ghost.Parent = workspace
	placementGhost = ghost
	isGhostValid = true

	return ghost
end

--[[
	Destroys the placement ghost.
]]
local function destroyPlacementGhost()
	if ghostPulseTween then
		ghostPulseTween:Cancel()
		ghostPulseTween = nil
	end
	
	if placementGhost then
		placementGhost:Destroy()
		placementGhost = nil
	end
	
	isGhostValid = false
end

--[[
	Starts the pulsing effect on ghost (valid position).
]]
local function startGhostPulse()
	if not placementGhost then return end
	
	-- Stop existing pulse
	if ghostPulseTween then
		ghostPulseTween:Cancel()
	end
	
	-- Set valid color
	setModelColor(placementGhost, GHOST_VALID_COLOR)
	isGhostValid = true
	
	-- Create pulse loop
	local pulsing = true
	local currentTransparency = 0.3
	local direction = 1 -- 1 = fading out, -1 = fading in
	
	task.spawn(function()
		while pulsing and placementGhost and placementGhost.Parent do
			currentTransparency = currentTransparency + (direction * 0.15 * 0.016)
			
			if currentTransparency >= 0.6 then
				direction = -1
				currentTransparency = 0.6
			elseif currentTransparency <= 0.3 then
				direction = 1
				currentTransparency = 0.3
			end
			
			setModelTransparency(placementGhost, currentTransparency)
			task.wait()
		end
	end)
end

--[[
	Stops pulsing and sets ghost to invalid (solid red).
]]
local function setGhostInvalid()
	if not placementGhost then return end
	
	if ghostPulseTween then
		ghostPulseTween:Cancel()
		ghostPulseTween = nil
	end
	
	setModelColor(placementGhost, GHOST_INVALID_COLOR)
	setModelTransparency(placementGhost, 0.5)
	isGhostValid = false
end

--[[
	Moves ghost to a slot position.
]]
local function moveGhostToSlot(slotIndex: number)
	if not placementGhost then return end
	
	local tile = gridTiles[slotIndex]
	if tile then
		local pos = tile.Position + Vector3.new(0, 2, 0)
		placementGhost:PivotTo(CFrame.new(pos))
	end
end

--------------------------------------------------------------------------------
-- DRAG AND DROP SYSTEM
--------------------------------------------------------------------------------

--[[
	Starts a drag operation from inventory.
]]
startDrag = function(unitName: string, rarity: string)
	print("BuildModeUI: startDrag called for", unitName, rarity)
	if isDragging then return end
	
	print("BuildModeUI: Starting drag operation")
	isDragging = true
	draggedUnit = {name = unitName, rarity = rarity}
	
	-- Try to create ghost (may fail if model not found)
	local ghost = createPlacementGhost(unitName)
	if ghost then
		startGhostPulse()
	end
	
	updateStatus("🎯 Release over an empty tile to place " .. unitName)
	
	-- Connect mouse move to track hovered slot
	dragConnection = RunService.RenderStepped:Connect(function()
		if not isDragging then return end
		
		-- Get slot under mouse
		local slot = getSlotUnderMouse()
		
		if slot then
			-- Move ghost if exists
			if placementGhost then
				moveGhostToSlot(slot)
			end
			
			-- Check if slot is valid (empty)
			local tile = gridTiles[slot]
			local isOccupied = tile and tile:GetAttribute("IsOccupied")
			
			if isOccupied then
				-- Invalid slot
				if placementGhost then
					setGhostInvalid()
				end
				if tile then
					highlightTile(slot, CONFIG.INVALID_COLOR)
				end
				isGhostValid = false
			else
				-- Valid slot
				if placementGhost and not isGhostValid then
					startGhostPulse()
				end
				if tile then
					highlightTile(slot, CONFIG.HOVER_COLOR)
				end
				isGhostValid = true
			end
		else
			-- Not over any slot
			if placementGhost then
				setGhostInvalid()
			end
			isGhostValid = false
		end
	end)
end

--[[
	Cancels the current drag operation.
]]
local function cancelDrag()
	if not isDragging then return end
	
	isDragging = false
	draggedUnit = nil
	
	if dragConnection then
		dragConnection:Disconnect()
		dragConnection = nil
	end
	
	destroyPlacementGhost()
	updateStatus("Drag cancelled")
end

--[[
	Completes a drop operation.
]]
completeDrop = function()
	if not isDragging or not draggedUnit then 
		cancelDrag()
		return 
	end
	
	-- Get slot under mouse
	local slot = getSlotUnderMouse()
	
	if slot and isGhostValid then
		-- Check if slot is empty
		local tile = gridTiles[slot]
		local isOccupied = tile and tile:GetAttribute("IsOccupied")
		
		if not isOccupied then
			-- Place the unit!
			local success, msg = PlaceBrainrotRemote:InvokeServer(draggedUnit.name, draggedUnit.rarity, slot)
			
			if success then
				updateStatus("✓ Placed " .. draggedUnit.name .. " at slot " .. slot)
				task.defer(renderBuildGrid)
				task.defer(refreshInventoryPanel)
			else
				updateStatus("✗ " .. (msg or "Place failed"))
			end
		else
			updateStatus("✗ Slot is occupied")
		end
	else
		updateStatus("✗ Invalid drop location")
	end
	
	-- Cleanup
	isDragging = false
	draggedUnit = nil
	
	if dragConnection then
		dragConnection:Disconnect()
		dragConnection = nil
	end
	
	destroyPlacementGhost()
end

--[[
	Gets the brainrot model under the mouse cursor.
	Returns the model and its slot index if found.
]]
local function getBrainrotUnderMouse(): (Model?, number?)
	local mousePos = UserInputService:GetMouseLocation()
	
	-- Get all brainrots and check if we're clicking on any
	local brainrots = CollectionService:GetTagged("ActiveBrainrot")
	
	local closestBrainrot = nil
	local closestSlot = nil
	local closestDist = math.huge
	
	for _, brainrot in brainrots do
		local ownerId = brainrot:GetAttribute("OwnerId")
		local slotIndex = brainrot:GetAttribute("GridSlot")
		
		-- Only check brainrots owned by this player
		if ownerId ~= LocalPlayer.UserId then
			continue
		end
		
		if not slotIndex then 
			continue 
		end
		
		-- Get brainrot position
		local brainrotPos
		if brainrot:IsA("Model") then
			if brainrot.PrimaryPart then
				brainrotPos = brainrot.PrimaryPart.Position
			else
				brainrotPos = brainrot:GetPivot().Position
			end
		elseif brainrot:IsA("BasePart") then
			brainrotPos = brainrot.Position
		end
		
		if not brainrotPos then 
			continue 
		end
		
		-- Project to screen
		local screenPos, onScreen = camera:WorldToViewportPoint(brainrotPos)
		
		if not onScreen then continue end
		
		-- Check distance from mouse to brainrot's screen position
		local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
		
		-- Use a generous click radius (80 pixels)
		if screenDist < 80 and screenDist < closestDist then
			closestDist = screenDist
			closestBrainrot = brainrot
			closestSlot = slotIndex
		end
	end
	
	return closestBrainrot, closestSlot
end

--[[
	Toggles visibility of all visual elements in a model.
	Only shows MeshParts when enabling - regular Parts stay invisible.
]]
local function setVisualsEnabled(model: Model, enabled: boolean)
	for _, descendant in model:GetDescendants() do
		-- Skip parts that should ALWAYS remain hidden
		if descendant.Name == "FakeRootPart" 
			or descendant.Name == "VfxInstance" 
			or descendant.Name == "RootPart"
			or descendant.Name == "HumanoidRootPart"
			or descendant.Name == "Hitbox"
		then
			-- Ensure these stay invisible
			if descendant:IsA("BasePart") then
				descendant.Transparency = 1
			end
			continue
		end
		
		if descendant:IsA("MeshPart") then
			-- MeshParts = actual visual geometry, toggle visibility
			descendant.Transparency = enabled and 0 or 1
		elseif descendant:IsA("Part") or descendant:IsA("UnionOperation") then
			-- Regular Parts = hitboxes, structure - keep invisible always
			descendant.Transparency = 1
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = enabled and 0 or 1
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = enabled
		elseif descendant:IsA("LayerCollector") then -- SurfaceGui, BillboardGui
			descendant.Enabled = enabled
		end
	end
end

--[[
	Starts dragging an existing brainrot from the world.
]]
local function startDragFromWorld(brainrotModel: Model, slotIndex: number)
	if isDragging then return end
	
	isDragging = true
	draggedUnit = {
		name = brainrotModel:GetAttribute("UnitType") or brainrotModel.Name,
		rarity = brainrotModel:GetAttribute("Rarity") or "Normal",
		fromSlot = slotIndex,
		isFromWorld = true,
		originalModel = brainrotModel
	}
	
	updateStatus("🎯 Drag to new slot or inventory panel to store")
	
	-- Create placement ghost
	createPlacementGhost(draggedUnit.name)
	
	-- Hide the original model while dragging
	if brainrotModel then
		setVisualsEnabled(brainrotModel, false)
	end
	
	-- Highlight the source slot
	if gridTiles[slotIndex] then
		highlightTile(slotIndex, CONFIG.SELECTED_COLOR)
	end
	
	-- Connect mouse move to track hovered slot and update ghost
	dragConnection = RunService.RenderStepped:Connect(function()
		if not isDragging then return end
		
		local slot = getSlotUnderMouse()
		
		-- Update ghost position
		if placementGhost and slot then
			moveGhostToSlot(slot)
			
			local tile = gridTiles[slot]
			local isOccupied = tile and tile:GetAttribute("IsOccupied")
			
			-- Don't show as invalid if it's our own source slot
			if slot == draggedUnit.fromSlot then
				startGhostPulse()
			elseif isOccupied then
				setGhostInvalid()
				highlightTile(slot, CONFIG.INVALID_COLOR)
			else
				startGhostPulse()
				highlightTile(slot, CONFIG.HOVER_COLOR)
			end
		elseif placementGhost then
			-- Mouse not over grid - check if over inventory
			local mouse = LocalPlayer:GetMouse()
			if inventoryPanel then
				local panelPos = inventoryPanel.AbsolutePosition
				local panelSize = inventoryPanel.AbsoluteSize
				if mouse.X >= panelPos.X and mouse.X <= panelPos.X + panelSize.X and
				   mouse.Y >= panelPos.Y and mouse.Y <= panelPos.Y + panelSize.Y then
					startGhostPulse() -- Valid to drop on inventory
				else
					setGhostInvalid()
				end
			end
		end
	end)
end

--[[
	Completes a drag operation from world model.
]]
local function completeDragFromWorld()
	if not isDragging or not draggedUnit or not draggedUnit.isFromWorld then
		return
	end
	
	local targetSlot = getSlotUnderMouse()
	local sourceSlot = draggedUnit.fromSlot
	
	-- Check if dropped on inventory panel (store the unit)
	local mouse = LocalPlayer:GetMouse()
	if inventoryPanel then
		local panelPos = inventoryPanel.AbsolutePosition
		local panelSize = inventoryPanel.AbsoluteSize

		
		if mouse.X >= panelPos.X and mouse.X <= panelPos.X + panelSize.X and
		   mouse.Y >= panelPos.Y and mouse.Y <= panelPos.Y + panelSize.Y then
			-- Drop on inventory - remove from grid to storage
			print("BuildModeUI: Dropping on inventory panel - storing")
			local success, msg = RemoveBrainrotRemote:InvokeServer(draggedUnit.name, draggedUnit.rarity)
			if success then
				updateStatus("✓ Stored " .. draggedUnit.name .. " in inventory")
				task.defer(renderBuildGrid)
				task.defer(refreshInventoryPanel)
			else
				updateStatus("✗ " .. (msg or "Store failed"))
			end
			
			-- Cleanup
			isDragging = false
			draggedUnit = nil
			if dragConnection then
				dragConnection:Disconnect()
				dragConnection = nil
			end
			return
		end
	end
	
	-- Check if dropped on a valid grid slot
	if targetSlot and targetSlot ~= sourceSlot then
		local tile = gridTiles[targetSlot]
		local isOccupied = tile and tile:GetAttribute("IsOccupied")
		
		if isOccupied then
			-- Swap
			local success, err = SwapUnits:InvokeServer(sourceSlot, targetSlot)
			if success then
				updateStatus("✓ Swapped units!")
			else
				updateStatus("✗ " .. (err or "Swap failed"))
			end
		else
			-- Move to empty slot
			local success, err = MoveUnit:InvokeServer(sourceSlot, targetSlot)
			if success then
				updateStatus("✓ Moved to slot " .. targetSlot)
			else
				updateStatus("✗ " .. (err or "Move failed"))
			end
		end
		task.defer(renderBuildGrid)
	else
		updateStatus("Drag cancelled")
	end
	
	-- Restore original model visibility
	if draggedUnit and draggedUnit.originalModel and draggedUnit.originalModel.Parent then
		setVisualsEnabled(draggedUnit.originalModel, true)
	end

	-- Cleanup
	isDragging = false
	draggedUnit = nil
	if dragConnection then
		dragConnection:Disconnect()
		dragConnection = nil
	end
	
	-- Destroy ghost
	destroyPlacementGhost()
	
	-- Unhighlight source
	if gridTiles[sourceSlot] then
		unhighlightTile(sourceSlot)
	end
end

--------------------------------------------------------------------------------
-- INTERACTION
--------------------------------------------------------------------------------

--[[
	Gets the slot under the mouse cursor.
]]
getSlotUnderMouse = function()
	if not gridContainer then return nil end
	
	local mouse = LocalPlayer:GetMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = {gridContainer}
	
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
	if result and result.Instance then
		return result.Instance:GetAttribute("SlotIndex")
	end
	
	return nil
end

--[[
	Handles mouse click on grid.
]]
local function handleClick()
	local slot = getSlotUnderMouse()
	if not slot then return end
	
	local tile = gridTiles[slot]
	if not tile then return end
	
	if selectedSlot then
		-- If we have a selection, try to move/swap
		if slot ~= selectedSlot then
			local sourceOccupied = gridTiles[selectedSlot]:GetAttribute("IsOccupied")
			local targetOccupied = tile:GetAttribute("IsOccupied")
			
			if sourceOccupied then
				if targetOccupied then
					-- Swap
					local success, err = SwapUnits:InvokeServer(selectedSlot, slot)
					if success then
						updateStatus("✓ Swapped units!")
					else
						updateStatus("✗ " .. (err or "Swap failed"))
					end
				else
					-- Move
					local success, err = MoveUnit:InvokeServer(selectedSlot, slot)
					if success then
						updateStatus("✓ Moved unit!")
					else
						updateStatus("✗ " .. (err or "Move failed"))
					end
				end
				
				-- Refresh grid
				task.defer(renderBuildGrid)
			end
		end
		
		-- Deselect
		unhighlightTile(selectedSlot)
		selectedSlot = nil
	else
		-- Select this slot
		if tile:GetAttribute("IsOccupied") then
			selectedSlot = slot
			highlightTile(slot, CONFIG.SELECTED_COLOR)
			updateStatus("Selected: " .. (tile:GetAttribute("UnitName") or "Unit") .. " • Click tile to move/swap")
		else
			updateStatus("Empty slot - select an occupied tile first")
		end
	end
end

--[[
	Handles mouse hover.
]]
local function setupHoverTracking()
	if currentHoverConnection then
		currentHoverConnection:Disconnect()
	end
	
	currentHoverConnection = RunService.RenderStepped:Connect(function()
		if not isInBuildMode then return end
		
		local slot = getSlotUnderMouse()
		
		if slot ~= hoveredSlot then
			-- Unhighlight old
			if hoveredSlot and hoveredSlot ~= selectedSlot then
				unhighlightTile(hoveredSlot)
			end
			
			-- Highlight new
			if slot and slot ~= selectedSlot then
				highlightTile(slot, CONFIG.HOVER_COLOR)
			end
			
			hoveredSlot = slot
		end
	end)
end

--------------------------------------------------------------------------------
-- BUILD MODE TOGGLE
--------------------------------------------------------------------------------

--[[
	Enters build mode.
]]
local function enterBuildModeLocal()
	if isInBuildMode then return end
	
	-- Request from server
	local success, err = EnterBuildMode:InvokeServer()
	if not success then
		warn("BuildModeUI: Failed to enter - " .. tostring(err))
		return
	end
	
	isInBuildMode = true
	
	-- Get current island info
	local currentPlot = findCurrentIsland()
	local islandName = currentPlot and currentPlot.Name or "Unknown"
	
	-- Render grid and get plot center
	local plotCenter = renderBuildGrid()
	
	-- Create UI
	buildModeGui = createBuildModeUI()
	buildModeGui.Parent = PlayerGui
	
	-- Create and populate inventory panel
	createInventoryPanel(buildModeGui)
	refreshInventoryPanel()
	
	-- Update status with island name
	updateStatus("Editing: " .. islandName .. " • Click tile or Place from inventory")
	
	-- Setup exit button
	local topBar = buildModeGui:FindFirstChild("TopBar")
	if topBar then
		local exitButton = topBar:FindFirstChild("ExitButton")
		if exitButton then
			exitButton.MouseButton1Click:Connect(function()
				exitBuildModeLocal()
			end)
		end
	end
	
	-- Tween camera
	if plotCenter then
		tweenToIsometricView(plotCenter)
	end
	
	-- Setup interaction
	setupHoverTracking()
	
	-- Fire event for GridOverlay
	local buildModeToggle = ReplicatedStorage:FindFirstChild("BuildModeToggle")
	if buildModeToggle then
		buildModeToggle:Fire(true)
	end
	
	print("BuildModeUI: Entered Build Mode for " .. islandName)
end

--[[
	Exits build mode.
]]
exitBuildModeLocal = function()
	if not isInBuildMode then return end
	
	-- Request from server
	ExitBuildMode:InvokeServer()
	
	isInBuildMode = false
	
	-- Clean up
	if currentHoverConnection then
		currentHoverConnection:Disconnect()
		currentHoverConnection = nil
	end
	
	-- Destroy grid
	destroyBuildGrid()
	
	-- Clear inventory panel reference
	inventoryPanel = nil
	inventoryItems = {}
	
	-- Destroy UI
	if buildModeGui then
		buildModeGui:Destroy()
		buildModeGui = nil
	end
	
	-- Return camera
	tweenToPlayerView()
	
	-- Clear selection
	selectedSlot = nil
	hoveredSlot = nil
	
	-- Fire event for GridOverlay
	local buildModeToggle = ReplicatedStorage:FindFirstChild("BuildModeToggle")
	if buildModeToggle then
		buildModeToggle:Fire(false)
	end
	
	print("BuildModeUI: Exited Build Mode")
end

--[[
	Toggles build mode.
]]
local function toggleBuildMode()
	if isInBuildMode then
		exitBuildModeLocal()
	else
		enterBuildModeLocal()
	end
end

--------------------------------------------------------------------------------
-- INPUT HANDLING
--------------------------------------------------------------------------------

-- G or Tab key to toggle
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.Tab then
		toggleBuildMode()
	elseif input.KeyCode == Enum.KeyCode.Escape and isInBuildMode then
		exitBuildModeLocal()
	end
end)

-- Mouse click handling - try to drag brainrot models first
local mouse = LocalPlayer:GetMouse()
mouse.Button1Down:Connect(function()
	if not isInBuildMode then return end
	if isDragging then return end
	
	-- Check if clicking on a brainrot model
	local brainrot, slotIndex = getBrainrotUnderMouse()
	if brainrot and slotIndex then
		-- Start dragging this brainrot
		startDragFromWorld(brainrot, slotIndex)
		return
	end
	
	-- Otherwise, handle grid click
	handleClick()
end)

-- Mouse release for completing drag-drop
mouse.Button1Up:Connect(function()
	if not isInBuildMode or not isDragging then return end
	
	-- Check if this is a world drag or inventory drag
	if draggedUnit and draggedUnit.isFromWorld then
		completeDragFromWorld()
	else
		completeDrop()
	end
end)

--------------------------------------------------------------------------------
-- LISTEN FOR GRID UPDATES
--------------------------------------------------------------------------------

GridUpdatedEvent.OnClientEvent:Connect(function(slotIndex, unitName, action)
	if isInBuildMode then
		-- Refresh the grid when updates happen
		task.defer(renderBuildGrid)
	end
end)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

print("✓ BuildModeUI initialized - Press TAB to toggle Build Mode")

-- Export
_G.BuildModeUI = {
	Toggle = toggleBuildMode,
	Enter = enterBuildModeLocal,
	Exit = exitBuildModeLocal,
	IsActive = function() return isInBuildMode end,
}
