--[[
	BuildModeUI Client Script
	
	"Architect Overlay" interface for placing and arranging brainrots.
	
	Features:
	- Press TAB to enter/exit Build Mode
	- Isometric camera view of plot
	- Grid visualization
	- KINEMATIC DRAG AND DROP (TFT Style)
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Shared Configs
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TileConfig = require(Shared:WaitForChild("TileConfig"))
local ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))

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

-- Tile remotes
local PlaceTileRemote = RemoteFunctions:WaitForChild("PlaceTile")
local RemoveTileRemote = RemoteFunctions:WaitForChild("RemoveTile")

-- State
local currentTab = "Units" -- "Units" or "Tiles"
local tileList = {} -- To be populated from TileConfig

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
	
	-- Drag Physics (TFT Feel)
	DRAG_HEIGHT = 4.0,       -- How high it hovers when dragging
	DRAG_SMOOTHNESS = 20.0,  -- Position Lerp speed (Higher = Snappier, Lower = Heavier)
	TILT_STRENGTH = 0.3,     -- How much it tilts when moving
	TILT_RETURN_SPEED = 10.0,-- How fast it straightens up
	MAX_TILT_ANGLE = 25,     -- Max degrees of tilt
	
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
	INVENTORY_WIDTH = 220,
	
	-- Rarity colors
	RARITY_COLORS = {
		Normal = Color3.fromRGB(180, 180, 180),
		Spicy = Color3.fromRGB(255, 80, 80),
		Galaxy = Color3.fromRGB(180, 100, 255),
	},
	
	-- Modern Dark Theme (MoneyHUD Style)
	THEME_BG = Color3.fromRGB(20, 20, 30),
	THEME_STROKE = Color3.fromRGB(50, 50, 70),
	THEME_ACCENT_PURPLE = Color3.fromRGB(80, 60, 140),
	THEME_ACCENT_PINK = Color3.fromRGB(140, 80, 160),
	THEME_ACCENT_GOLD = Color3.fromRGB(200, 150, 60),
	THEME_ACCENT_BLUE = Color3.fromRGB(80, 160, 200),
	THEME_ACCENT_GREEN = Color3.fromRGB(100, 255, 100), -- For valid
	THEME_TEXT_PRIMARY = Color3.fromRGB(255, 255, 255),
	THEME_TEXT_SECONDARY = Color3.fromRGB(180, 180, 180),
	THEME_PANEL_RADIUS = 16,
	THEME_BUTTON_RADIUS = 6,
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
local gridFloorHeight = 0 -- Detected automatically

-- Drag-drop state
local draggedUnit = nil  -- {name: string, rarity: string}
local inventoryPanel = nil
local inventoryData = {}  -- {[unitName]: {[rarity]: {total, active}}}

-- Placement ghost state
local placementGhost = nil  -- The ghost model in workspace
local ghostPulseTween = nil  -- Current pulse tween
local isGhostValid = false  -- Is ghost in a valid position
local dragConnection = nil  -- Mouse move connection during drag
local ghostCenterOffset = Vector3.new() -- Offset from pivot to bounding box center

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
local startTileDrag
local completeDrop

-- Helper for rounded stroke panels (MoneyHUD style)
local function _stylePanel(frame, radius)
	frame.BackgroundColor3 = CONFIG.THEME_BG
	frame.BackgroundTransparency = 0.1 -- Slight transparency like MoneyHUD
	frame.BorderSizePixel = 0
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or CONFIG.THEME_PANEL_RADIUS)
	corner.Parent = frame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = CONFIG.THEME_STROKE
	stroke.Thickness = 2
	stroke.Parent = frame
	return frame
end

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
	gridFloorHeight = gridY -- Store for physics raycasting
	
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
		
		-- Handle new layered slot format: {unitType = string?, tileId = string?}
		local slotData = gridState.slots[slotIndex]
		local unitName = nil
		
		if type(slotData) == "table" then
			unitName = slotData.unitType
		elseif type(slotData) == "string" then
			unitName = slotData
		end
		
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

--[[
	Creates the build mode UI overlay with Roblox STUD theme.
]]
local function createBuildModeUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuildModeUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 100
	
	-- Top bar (transparent container)
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 50)
	topBar.Position = UDim2.new(0, 0, 0, 0)
	topBar.BackgroundTransparency = 1
	topBar.BorderSizePixel = 0
	topBar.Parent = screenGui
	
	-- BUILD MODE title badge
	local titleContainer = Instance.new("Frame")
	titleContainer.Name = "TitleContainer"
	titleContainer.Size = UDim2.new(0, 160, 0, 32)
	titleContainer.Position = UDim2.new(0, 140, 0.5, -16)
	titleContainer.BackgroundColor3 = CONFIG.THEME_ACCENT_PINK
	titleContainer.BorderSizePixel = 0
	titleContainer.Parent = topBar
	
	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, CONFIG.THEME_BUTTON_RADIUS)
	titleCorner.Parent = titleContainer
	
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 1, 0)
	title.Position = UDim2.new(0, 0, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "🏗️ BUILD MODE"
	title.TextColor3 = CONFIG.THEME_TEXT_PRIMARY
	title.TextSize = 14
	title.Font = Enum.Font.GothamBold
	title.Parent = titleContainer
	
	-- Instructions
	local instructions = Instance.new("TextLabel")
	instructions.Name = "Instructions"
	instructions.Size = UDim2.new(0, 400, 1, 0)
	instructions.Position = UDim2.new(0.5, -200, 0, 0)
	instructions.BackgroundTransparency = 1
	instructions.Text = "Click to select • Drag to move"
	instructions.TextColor3 = CONFIG.THEME_TEXT_SECONDARY
	instructions.TextSize = 14
	instructions.Font = Enum.Font.GothamBold
	instructions.Parent = topBar
	
	-- Exit button (Matching theme style)
	local exitButton = Instance.new("TextButton")
	exitButton.Name = "ExitButton"
	exitButton.Size = UDim2.new(0, 90, 0, 36)
	exitButton.Position = UDim2.new(1, -105, 0.5, -18)
	exitButton.BackgroundColor3 = CONFIG.THEME_ACCENT_PURPLE -- Matching theme button color
	exitButton.Text = "EXIT"
	exitButton.TextColor3 = CONFIG.THEME_TEXT_PRIMARY
	exitButton.TextSize = 14
	exitButton.Font = Enum.Font.GothamBold
	exitButton.Parent = topBar
	
	local exitCorner = Instance.new("UICorner")
	exitCorner.CornerRadius = UDim.new(0, CONFIG.THEME_BUTTON_RADIUS)
	exitCorner.Parent = exitButton
	
	-- Hover effect
	exitButton.MouseEnter:Connect(function()
		TweenService:Create(exitButton, TweenInfo.new(0.1), {
			BackgroundColor3 = CONFIG.THEME_ACCENT_PURPLE:Lerp(Color3.new(1,1,1), 0.1)
		}):Play()
	end)
	
	exitButton.MouseLeave:Connect(function()
		TweenService:Create(exitButton, TweenInfo.new(0.1), {
			BackgroundColor3 = CONFIG.THEME_ACCENT_PURPLE
		}):Play()
	end)
	
	-- Status bar at bottom (transparent container)
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(1, 0, 0, 36)
	bottomBar.Position = UDim2.new(0, 0, 1, -36)
	bottomBar.BackgroundTransparency = 1
	bottomBar.BorderSizePixel = 0
	bottomBar.Parent = screenGui
	
	-- Status text
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -40, 1, 0)
	statusLabel.Position = UDim2.new(0, 20, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Editing Plot - Click tile or drag from inventory"
	statusLabel.TextColor3 = CONFIG.THEME_TEXT_PRIMARY
	statusLabel.TextSize = 14
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = bottomBar
	

	
	return screenGui
end



--------------------------------------------------------------------------------
-- INVENTORY PANEL (for Build Mode)
--------------------------------------------------------------------------------

local RARITY_ORDER = {"Normal", "Spicy", "Galaxy"}
local inventoryItems = {}  -- UI item frames

--[[
	Creates the inventory panel for Build Mode with Tabs.
]]
local function createInventoryPanel(parent)
	local panel = Instance.new("Frame")
	panel.Name = "InventoryPanel"
	panel.Size = UDim2.new(0, CONFIG.INVENTORY_WIDTH, 1, -110)
	panel.Position = UDim2.new(0, 10, 0, 60)
	_stylePanel(panel)
	panel.Parent = parent
	
	-- Tab Container
	local tabContainer = Instance.new("Frame")
	tabContainer.Name = "TabContainer"
	tabContainer.Size = UDim2.new(1, -20, 0, 36)
	tabContainer.Position = UDim2.new(0, 10, 0, 10)
	tabContainer.BackgroundTransparency = 1
	tabContainer.Parent = panel
	
	-- Units Tab Button
	local unitsBtn = Instance.new("TextButton")
	unitsBtn.Name = "UnitsButton"
	unitsBtn.Size = UDim2.new(0.5, -5, 1, 0)
	unitsBtn.Position = UDim2.new(0, 0, 0, 0)
	unitsBtn.BackgroundColor3 = currentTab == "Units" and CONFIG.THEME_ACCENT_PURPLE or Color3.fromRGB(40,40,50)
	unitsBtn.Text = "🧠 UNITS"
	unitsBtn.TextColor3 = CONFIG.THEME_TEXT_PRIMARY
	unitsBtn.TextSize = 12
	unitsBtn.Font = Enum.Font.GothamBold
	unitsBtn.Parent = tabContainer
	
	local uCorner = Instance.new("UICorner")
	uCorner.CornerRadius = UDim.new(0, 6)
	uCorner.Parent = unitsBtn
	
	-- Tiles Tab Button
	local tilesBtn = Instance.new("TextButton")
	tilesBtn.Name = "TilesButton"
	tilesBtn.Size = UDim2.new(0.5, -5, 1, 0)
	tilesBtn.Position = UDim2.new(0.5, 5, 0, 0)
	tilesBtn.BackgroundColor3 = currentTab == "Tiles" and CONFIG.THEME_ACCENT_PINK or Color3.fromRGB(40,40,50)
	tilesBtn.Text = "🧱 TILES"
	tilesBtn.TextColor3 = CONFIG.THEME_TEXT_PRIMARY
	tilesBtn.TextSize = 12
	tilesBtn.Font = Enum.Font.GothamBold
	tilesBtn.Parent = tabContainer
	
	local tCorner = Instance.new("UICorner")
	tCorner.CornerRadius = UDim.new(0, 6)
	tCorner.Parent = tilesBtn
	
	-- Tab Logic
	unitsBtn.MouseButton1Click:Connect(function()
		currentTab = "Units"
		unitsBtn.BackgroundColor3 = CONFIG.THEME_ACCENT_PURPLE
		tilesBtn.BackgroundColor3 = Color3.fromRGB(40,40,50)
		refreshInventoryPanel()
	end)
	
	tilesBtn.MouseButton1Click:Connect(function()
		currentTab = "Tiles"
		tilesBtn.BackgroundColor3 = CONFIG.THEME_ACCENT_PINK
		unitsBtn.BackgroundColor3 = Color3.fromRGB(40,40,50)
		refreshInventoryPanel()
	end)

	-- Scrolling frame for items
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemsList"
	scrollFrame.Size = UDim2.new(1, -20, 1, -60)
	scrollFrame.Position = UDim2.new(0, 10, 0, 55)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = CONFIG.THEME_ACCENT_PURPLE
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.Parent = panel
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder -- Changed to manual order
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = scrollFrame
	
	-- Auto-resize canvas
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
	end)
	
	inventoryPanel = panel
	return panel;
end

--[[
	Populates the inventory panel with stored units.
	Called when entering build mode and after placing/removing units.
]]
--[[
	Gets the brainrot model from ReplicatedStorage.
]]
local function getBrainrotModel(unitName: string): Model?
	-- Check main Brainrots folder first
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
	Populates the inventory panel with stored units.
	Called when entering build mode and after placing/removing units.
]]
refreshInventoryPanel = function()
	if not inventoryPanel then return end
	
	local scrollFrame = inventoryPanel:FindFirstChild("ItemsList")
	if not scrollFrame then return end
	
	-- Clear old entries (destroy everything except UIListLayout)
	for _, child in scrollFrame:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	inventoryItems = {}
	
	-- Clean up old previews
	for _, previewFrame in pairs(inventoryPreviews) do
		if previewFrame and previewFrame.Parent then
			previewFrame:Destroy()
		end
	end
	inventoryPreviews = {}
	
	-- Fetch inventory from server
	local success, inventory = pcall(function()
		return GetInventoryRemote:InvokeServer()
	end)
	
	if not success then return end
	
	if currentTab == "Units" then
		if not inventory or not inventory.units then return end
		
		-- Create an entry for each unit that is STORED (not placed)
		for unitName, unitData in pairs(inventory.units) do
			if unitData.status == "stored" and (unitData.level or 0) > 0 then

			local rarityColor = CONFIG.RARITY_COLORS[unitData.rarity] or CONFIG.THEME_TEXT_SECONDARY
			
			-- Card container (Modern Style)
			local itemFrame = Instance.new("Frame")
			itemFrame.Name = "Item_" .. unitName
			itemFrame.Size = UDim2.new(1, 0, 0, 90) -- Slightly taller for new layout
			itemFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50) -- Dark inner panel
			itemFrame.BorderSizePixel = 0
			itemFrame.Parent = scrollFrame
			
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, CONFIG.THEME_BUTTON_RADIUS)
			corner.Parent = itemFrame
			
			-- Viewport (Preview)
			local viewport = Instance.new("ViewportFrame")
			viewport.Name = "Preview"
			viewport.Size = UDim2.new(0, 70, 0, 70)
			viewport.Position = UDim2.new(0, 10, 0, 10)
			viewport.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
			viewport.BorderSizePixel = 0
			viewport.Parent = itemFrame
			
			local viewCorner = Instance.new("UICorner")
			viewCorner.CornerRadius = UDim.new(0, CONFIG.THEME_BUTTON_RADIUS)
			viewCorner.Parent = viewport
			
			-- Info Group
			local infoGroup = Instance.new("Frame")
			infoGroup.Name = "Info"
			infoGroup.Size = UDim2.new(1, -90, 1, 0)
			infoGroup.Position = UDim2.new(0, 90, 0, 0)
			infoGroup.BackgroundTransparency = 1
			infoGroup.Parent = itemFrame
			
			-- Unit Name
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "Name"
			nameLabel.Size = UDim2.new(1, 0, 0, 20)
			nameLabel.Position = UDim2.new(0, 0, 0, 10)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = unitName
			nameLabel.TextColor3 = CONFIG.THEME_TEXT_PRIMARY
			nameLabel.TextSize = 14
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = infoGroup
			
			-- Level / Rarity
			local rarityLabel = Instance.new("TextLabel")
			rarityLabel.Name = "Rarity"
			rarityLabel.Size = UDim2.new(1, 0, 0, 16)
			rarityLabel.Position = UDim2.new(0, 0, 0, 30)
			rarityLabel.BackgroundTransparency = 1
			rarityLabel.Text = string.format("Lvl %d • %s", unitData.level or 1, unitData.rarity or "Normal")
			rarityLabel.TextColor3 = rarityColor
			rarityLabel.TextSize = 11
			rarityLabel.Font = Enum.Font.Gotham
			rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
			rarityLabel.Parent = infoGroup
			
			-- HP Label
			local hpLabel = Instance.new("TextLabel")
			hpLabel.Name = "HP"
			hpLabel.Size = UDim2.new(1, 0, 0, 16)
			hpLabel.Position = UDim2.new(0, 0, 0, 46)
			hpLabel.BackgroundTransparency = 1
			hpLabel.Text = "❤️ " .. tostring((unitData.level or 1) * 10 + 25) -- Example HP calculation
			hpLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
			hpLabel.TextSize = 11
			hpLabel.Font = Enum.Font.GothamBold
			hpLabel.TextXAlignment = Enum.TextXAlignment.Left
			hpLabel.Parent = infoGroup
			
			-- Full-card drag overlay (click anywhere to drag)
			local dragOverlay = Instance.new("TextButton")
			dragOverlay.Name = "DragOverlay"
			dragOverlay.Size = UDim2.new(1, 0, 1, 0)
			dragOverlay.Position = UDim2.new(0, 0, 0, 0)
			dragOverlay.BackgroundTransparency = 1
			dragOverlay.Text = ""
			dragOverlay.ZIndex = 10 -- Ensure it's on top
			dragOverlay.Parent = itemFrame
			
			-- Hover effect for entire card
			dragOverlay.MouseEnter:Connect(function()
				TweenService:Create(itemFrame, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(55, 55, 70)
				}):Play()
			end)
			dragOverlay.MouseLeave:Connect(function()
				TweenService:Create(itemFrame, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(40, 40, 50)
				}):Play()
			end)
			
			-- Drag trigger on mouse down anywhere on the card
			dragOverlay.MouseButton1Down:Connect(function()
				startDrag(unitName, unitData.rarity or "Normal")
			end)
			
			-- Try to add model preview
			local template = getBrainrotModel(unitName)
			if template then
				local previewModel = template:Clone()
				previewModel.Parent = viewport
				
				local previewCamera = Instance.new("Camera")
				previewCamera.Parent = viewport
				viewport.CurrentCamera = previewCamera
				
				-- Calculate bounding box to properly frame the model
				local cf, size = previewModel:GetBoundingBox()
				local maxDim = math.max(size.X, size.Y, size.Z)
				local distance = maxDim * 1.0  -- Zoomed in closer
				
				-- Isolate visual center
				local center = cf.Position
				if previewModel.PrimaryPart then
					center = previewModel.PrimaryPart.Position
				end
				
				previewCamera.CFrame = CFrame.new(center + Vector3.new(distance, distance*0.5, distance), center)
				
				inventoryItems[unitName] = itemFrame
			end
		end
	end
	
	end
	
	if currentTab == "Tiles" then
		-- Render Tiles List
		local tileIds = TileConfig.GetAllTileIds()
		
		for _, tileId in ipairs(tileIds) do
			local tileData = TileConfig.Tiles[tileId]
			if not tileData then continue end
			
			-- Card container
			local itemFrame = Instance.new("Frame")
			itemFrame.Name = "Tile_" .. tileId
			itemFrame.Size = UDim2.new(1, 0, 0, 80)
			itemFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
			itemFrame.BorderSizePixel = 0
			itemFrame.Parent = scrollFrame
			
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, CONFIG.THEME_BUTTON_RADIUS)
			corner.Parent = itemFrame
			
			-- Color strip
			local colorStrip = Instance.new("Frame")
			colorStrip.Name = "ColorStrip"
			colorStrip.Size = UDim2.new(0, 50, 1, -20)
			colorStrip.Position = UDim2.new(0, 10, 0, 10)
			colorStrip.BackgroundColor3 = tileData.Color or Color3.fromRGB(150,150,150)
			colorStrip.BorderSizePixel = 0
			colorStrip.Parent = itemFrame
			
			local stripCorner = Instance.new("UICorner")
			stripCorner.CornerRadius = UDim.new(0, 8)
			stripCorner.Parent = colorStrip
			
			-- Info
			local infoGroup = Instance.new("Frame")
			infoGroup.Name = "Info"
			infoGroup.Size = UDim2.new(1, -70, 1, 0)
			infoGroup.Position = UDim2.new(0, 70, 0, 0)
			infoGroup.BackgroundTransparency = 1
			infoGroup.Parent = itemFrame
			
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "Name"
			nameLabel.Size = UDim2.new(1, 0, 0, 20)
			nameLabel.Position = UDim2.new(0, 0, 0, 15)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = tileData.Name
			nameLabel.TextColor3 = CONFIG.THEME_TEXT_PRIMARY
			nameLabel.TextSize = 14
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.Parent = infoGroup
			
			local descLabel = Instance.new("TextLabel")
			descLabel.Name = "Desc"
			descLabel.Size = UDim2.new(1, 0, 0, 30)
			descLabel.Position = UDim2.new(0, 0, 0, 35)
			descLabel.BackgroundTransparency = 1
			descLabel.Text = tileData.Description
			descLabel.TextColor3 = CONFIG.THEME_TEXT_SECONDARY
			descLabel.TextSize = 11
			descLabel.Font = Enum.Font.Gotham
			descLabel.TextXAlignment = Enum.TextXAlignment.Left
			descLabel.TextWrapped = true
			descLabel.Parent = infoGroup
			
			-- Drag Button (Transparent overlay)
			local dragBtn = Instance.new("TextButton")
			dragBtn.Name = "DragButton"
			dragBtn.Size = UDim2.new(1, 0, 1, 0)
			dragBtn.BackgroundTransparency = 1
			dragBtn.Text = ""
			dragBtn.Parent = itemFrame
			
			dragBtn.MouseButton1Down:Connect(function()
				startTileDrag(tileId)
			end)
		end
	end
end

-- Ghost colors

local GHOST_VALID_COLOR = Color3.fromRGB(100, 255, 100)

local GHOST_INVALID_COLOR = Color3.fromRGB(255, 80, 80)



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
]]
--[[
	Creates a ghost preview using the MeshPart-only approach.
]]
--[[
	Creates a ghost preview using the MeshPart-only approach.
]]
local function createPlacementGhost(nameOrId: string, isTile: boolean?): Model?
	local ghost
	
	if isTile then
		-- Create Tile Ghost
		local tileData = TileConfig.GetTile(nameOrId)
		if not tileData then return nil end
		
		ghost = Instance.new("Model")
		local part = Instance.new("Part")
		part.Name = "TileGhost"
		part.Size = Vector3.new(CONFIG.TILE_SIZE - 0.5, CONFIG.TILE_HEIGHT, CONFIG.TILE_SIZE - 0.5)
		part.Transparency = 0.3
		part.Color = tileData.Color or GHOST_VALID_COLOR
		part.Material = Enum.Material.ForceField
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = false
		part.Parent = ghost
		ghost.PrimaryPart = part
		
		-- Add slight glow
		local highlight = Instance.new("SurfaceLight")
		highlight.Color = tileData.Color or GHOST_VALID_COLOR
		highlight.Brightness = 0.5
		highlight.Face = Enum.NormalId.Top
		highlight.Parent = part
		
		ghost.Name = "PlacementGhost_Tile"
		ghost.Parent = workspace
		placementGhost = ghost
		isGhostValid = true
		ghostCenterOffset = Vector3.new()
		return ghost
	end

	local originalModel = getBrainrotModel(nameOrId)

	-- 1. Create the Clone
	if originalModel then
		ghost = originalModel:Clone()
		-- Calculate bounding box center offset from pivot
		-- This ensures the ghost is centered on the model's visual center
		local cf, _size = originalModel:GetBoundingBox()
		local pivotPos = originalModel:GetPivot().Position
		local boundingBoxCenter = cf.Position
		ghostCenterOffset = pivotPos - boundingBoxCenter
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
		ghostCenterOffset = Vector3.new()
		return ghost
	end

	ghost.Name = "PlacementGhost"

	-- 2. Clean up logic (Destroy specific types AND specific names)
	local descendants = ghost:GetDescendants()
	for _, item in descendants do
		-- Check if the item still exists (it might have been a child of a previously destroyed item)
		if not item.Parent then continue end

		-- A. Remove unwanted classes (Scripts, UI, Sounds, Humanoids)
		if item:IsA("Humanoid") 
			or item:IsA("LuaSourceContainer") 
			or item:IsA("Sound") 
			or item:IsA("Light") 
			or item:IsA("ParticleEmitter") 
			or item:IsA("Trail")
			or item:IsA("Beam")
			or item:IsA("BillboardGui")
			or item:IsA("SurfaceGui")
		then
			item:Destroy()
			continue
		end

		-- B. Remove unwanted specific Parts (The "Weird Box" fix)
		if item.Name == "FakeRootPart" 
			or item.Name == "RootPart" 
			or item.Name == "HumanoidRootPart" 
			or item.Name == "Hitbox" 
			or item.Name == "VfxInstance"
            or item.Name == "AnimationController" -- Also usually junk in ghosts
		then
			item:Destroy()
			continue
		end
		
		-- C. Apply Ghost Visuals to what remains
		if item:IsA("BasePart") then
			if item:IsA("MeshPart") then
				-- MeshPart = actual visual geometry, apply ghost effect
				item.CanCollide = false
				item.CastShadow = false
				item.Anchored = true
				item.Transparency = 0.3
				item.Color = GHOST_VALID_COLOR
				item.Material = Enum.Material.ForceField
			else
				-- Regular Parts/Unions = remaining structure - keep invisible
				-- (If any survived the delete list above)
				item.CanCollide = false
				item.CastShadow = false
				item.Anchored = true
				item.Transparency = 1
			end
		elseif item:IsA("Decal") or item:IsA("Texture") then
			item:Destroy() -- Clean up textures too for a cleaner ghost look
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
	local direction = 1
	
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

--------------------------------------------------------------------------------
-- DRAG AND DROP SYSTEM
--------------------------------------------------------------------------------

--[[
	Calculates the mouse position on the 3D plane at grid height.
	Allows dragging freely between tiles.
]]
local function getMousePlanePosition()
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	
	-- Create a mathematical plane at the grid height (y = gridFloorHeight)
	-- Plane equation: (P - P0) dot Normal = 0
	-- Ray: P = Origin + Direction * t
	-- (Origin + Dir*t - P0) dot Normal = 0
	-- t = (P0 - Origin) dot Normal / (Dir dot Normal)
	
	local normal = Vector3.new(0, 1, 0)
	local p0 = Vector3.new(0, gridFloorHeight, 0)
	
	local denominator = ray.Direction:Dot(normal)
	
	if math.abs(denominator) > 0.001 then -- Prevent division by zero
		local t = (p0 - ray.Origin):Dot(normal) / denominator
		if t > 0 then
			return ray.Origin + ray.Direction * t
		end
	end
	
	return nil
end

--[[
	Starts a drag operation from inventory.
]]
startDrag = function(unitName: string, rarity: string)
	print("DEBUG: startDrag called for", unitName)
	if isDragging then return end
	
	isDragging = true
	draggedUnit = {type = "unit", name = unitName, rarity = rarity}
	
	-- Determine Start Position
	local mousePos = getMousePlanePosition()
	local startPos = mousePos or Vector3.new(0, gridFloorHeight, 0)
	
	-- Physics State Variables
	local currentPos = startPos
	local currentVelocity = Vector3.new()
	local currentTilt = CFrame.new()
	
	-- Create ghost
	local ghost = createPlacementGhost(unitName)
	if ghost then
		print("DEBUG: Ghost created successfully")
		-- Apply offset so visual center is at the target position
		ghost:PivotTo(CFrame.new(startPos + Vector3.new(0, CONFIG.DRAG_HEIGHT, 0) + ghostCenterOffset))
		startGhostPulse()
	else
		warn("DEBUG: Ghost creation FAILED for " .. unitName)
	end
	
	updateStatus("🎯 Release over an empty tile to place " .. unitName)
	
	-- KINEMATIC DRAG LOOP
	dragConnection = RunService.RenderStepped:Connect(function(dt)
		if not isDragging then return end
		
		-- 1. Determine Target Position (Mouse on Floor Plane)
		local rawMousePos = getMousePlanePosition()
		if not rawMousePos then return end
		
		local targetPos = rawMousePos + Vector3.new(0, CONFIG.DRAG_HEIGHT, 0)
		
		-- 2. Smooth Position (Lag Effect)
		-- Simple Lerp is often smoother than Spring for Mouse Drag in Roblox due to update rates
		local lerpAlpha = math.clamp(dt * CONFIG.DRAG_SMOOTHNESS, 0, 1)
		local newPos = currentPos:Lerp(targetPos, lerpAlpha)
		
		-- Calculate velocity for tilt
		local velocity = (newPos - currentPos) / dt
		currentPos = newPos
		
		-- 3. Calculate Tilt (Procedural Animation)
		-- Tilt axis is perpendicular to velocity and up vector
		local tiltAxis = velocity:Cross(Vector3.yAxis)
		local speed = velocity.Magnitude
		
		-- Calculate target tilt rotation
		local targetTiltRot = CFrame.new()
		if speed > 0.1 and tiltAxis.Magnitude > 0.01 then
			-- Calculate angle based on speed (clamped)
			local tiltAngle = math.rad(math.clamp(speed * CONFIG.TILT_STRENGTH, -CONFIG.MAX_TILT_ANGLE, CONFIG.MAX_TILT_ANGLE))
			
			-- We invert the angle so it "drags" behind
			targetTiltRot = CFrame.fromAxisAngle(tiltAxis.Unit, -tiltAngle)
		end
		
		-- Smoothly interpolate tilt
		currentTilt = currentTilt:Lerp(targetTiltRot, dt * CONFIG.TILT_RETURN_SPEED)
		
		-- 4. Apply to Ghost
		if placementGhost then
			-- Apply offset so visual center follows cursor
			placementGhost:PivotTo(CFrame.new(currentPos + ghostCenterOffset) * currentTilt)
		end
		
		-- 5. Grid Interaction (Highlighting)
		local slot = getSlotUnderMouse()
		
		if slot then
			local tile = gridTiles[slot]
			local isOccupied = tile and tile:GetAttribute("IsOccupied")
			
			if isOccupied then
				if placementGhost then setGhostInvalid() end
				if tile then highlightTile(slot, CONFIG.INVALID_COLOR) end
				isGhostValid = false
			else
				if placementGhost and not isGhostValid then startGhostPulse() end
				if tile then highlightTile(slot, CONFIG.HOVER_COLOR) end
				isGhostValid = true
			end
		else
			-- Check if hovering over inventory panel (valid cancel target)
			local mouse = LocalPlayer:GetMouse()
			if inventoryPanel then
				local panelPos = inventoryPanel.AbsolutePosition
				local panelSize = inventoryPanel.AbsoluteSize
				if mouse.X >= panelPos.X and mouse.X <= panelPos.X + panelSize.X and
				   mouse.Y >= panelPos.Y and mouse.Y <= panelPos.Y + panelSize.Y then
					if placementGhost and not isGhostValid then startGhostPulse() end
					isGhostValid = true
				else
					if placementGhost then setGhostInvalid() end
					isGhostValid = false
				end
			else
				if placementGhost then setGhostInvalid() end
				isGhostValid = false
			end
		end
	end)
end

--[[
	Starts a drag operation from inventory for a TILE.
]]
startTileDrag = function(tileId: string)
	if isDragging then return end
	
	isDragging = true
	draggedUnit = {type = "tile", id = tileId}
	
	-- Determine Start Position
	local mousePos = getMousePlanePosition()
	local startPos = mousePos or Vector3.new(0, gridFloorHeight, 0)
	
	-- Physics State Variables
	local currentPos = startPos
	
	-- Create ghost (pass true for isTile)
	local ghost = createPlacementGhost(tileId, true)
	if ghost then
		-- Apply offset so visual center is at the target position
		ghost:PivotTo(CFrame.new(startPos + Vector3.new(0, CONFIG.DRAG_HEIGHT, 0) + ghostCenterOffset))
		startGhostPulse()
	end
	
	updateStatus("🎯 Tile Mode: Release over a slot to place " .. tileId)
	
	-- KINEMATIC DRAG LOOP (Tiles - simplified, no tilt needed for flat tiles usually)
	dragConnection = RunService.RenderStepped:Connect(function(dt)
		if not isDragging then return end
		
		-- 1. Determine Target Position (Mouse on Floor Plane)
		local rawMousePos = getMousePlanePosition()
		if not rawMousePos then return end
		
		local targetPos = rawMousePos + Vector3.new(0, CONFIG.DRAG_HEIGHT, 0)
		
		-- 2. Smooth Position
		local lerpAlpha = math.clamp(dt * CONFIG.DRAG_SMOOTHNESS, 0, 1)
		local newPos = currentPos:Lerp(targetPos, lerpAlpha)
		currentPos = newPos
		
		-- 4. Apply to Ghost
		if placementGhost then
			placementGhost:PivotTo(CFrame.new(currentPos + ghostCenterOffset))
		end
		
		-- 5. Grid Interaction (Highlighting)
		local slot = getSlotUnderMouse()
		
		if slot then
			-- For tiles, we check if the slot already has THIS tile? Or just highlight valid
			if placementGhost and not isGhostValid then startGhostPulse() end
			highlightTile(slot, CONFIG.HOVER_COLOR)
			isGhostValid = true
		else
			if placementGhost then setGhostInvalid() end
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
		-- Handle different drag types
		if draggedUnit.type == "tile" then
			-- Place Tile
			local success, msg = PlaceTileRemote:InvokeServer(draggedUnit.id, slot)
			
			if success then
				updateStatus("✓ Placed " .. (draggedUnit.id or "tile") .. " at slot " .. slot)
				task.defer(renderBuildGrid)
			else
				updateStatus("✗ " .. (msg or "Tile placement failed"))
			end
			
		elseif draggedUnit.type == "unit" or draggedUnit.type == nil then -- Default to unit
			-- Check if slot is empty (units can't overlap)
			local tile = gridTiles[slot]
			local isOccupied = tile and tile:GetAttribute("IsOccupied")
			
			if not isOccupied then
				-- Place the unit!
				local success, msg = PlaceBrainrotRemote:InvokeServer(draggedUnit.name, draggedUnit.rarity, slot)
				
				if success then
					updateStatus("✓ Placed " .. (draggedUnit.name or "unit") .. " at slot " .. slot)
					task.defer(renderBuildGrid)
					task.defer(refreshInventoryPanel)
				else
					updateStatus("✗ " .. (msg or "Place failed"))
				end
			else
				updateStatus("✗ Slot is occupied")
			end
		end
	else
		-- Check if dropped on inventory panel (cancel gracefully - unit stays in storage)
		local mouse = LocalPlayer:GetMouse()
		if inventoryPanel then
			local panelPos = inventoryPanel.AbsolutePosition
			local panelSize = inventoryPanel.AbsoluteSize
			if mouse.X >= panelPos.X and mouse.X <= panelPos.X + panelSize.X and
			   mouse.Y >= panelPos.Y and mouse.Y <= panelPos.Y + panelSize.Y then
				updateStatus("✓ Drag cancelled - unit stays in inventory")
			else
				updateStatus("✗ Invalid drop location")
			end
		else
			updateStatus("✗ Invalid drop location")
		end
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
			if descendant:IsA("BasePart") then
				descendant.Transparency = 1
			end
			continue
		end
		
		if descendant:IsA("MeshPart") then
			descendant.Transparency = enabled and 0 or 1
		elseif descendant:IsA("Part") or descendant:IsA("UnionOperation") then
			descendant.Transparency = 1
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = enabled and 0 or 1
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = enabled
		elseif descendant:IsA("LayerCollector") then
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
		type = "unit",
		name = brainrotModel:GetAttribute("UnitType") or brainrotModel.Name,
		rarity = brainrotModel:GetAttribute("Rarity") or "Normal",
		fromSlot = slotIndex,
		isFromWorld = true,
		originalModel = brainrotModel
	}
	
	updateStatus("🎯 Drag to new slot or inventory panel to store")
	
	-- Setup Physics State
	-- Start exactly where the unit currently is
	local startPos
	if brainrotModel.PrimaryPart then
		startPos = brainrotModel.PrimaryPart.Position
	else
		startPos = brainrotModel:GetPivot().Position
	end
	
	local currentPos = startPos
	local currentTilt = CFrame.new()
	
	-- Create placement ghost
	createPlacementGhost(draggedUnit.name)
	if placementGhost then
		-- Apply offset so visual center is at the start position
		placementGhost:PivotTo(CFrame.new(startPos + ghostCenterOffset))
	end
	
	-- Hide the original model while dragging
	if brainrotModel then
		setVisualsEnabled(brainrotModel, false)
	end
	
	-- Highlight the source slot
	if gridTiles[slotIndex] then
		highlightTile(slotIndex, CONFIG.SELECTED_COLOR)
	end
	
	-- KINEMATIC DRAG LOOP (World)
	dragConnection = RunService.RenderStepped:Connect(function(dt)
		if not isDragging then return end
		
		-- 1. Determine Target (Mouse on Floor Plane)
		local rawMousePos = getMousePlanePosition()
		if not rawMousePos then return end
		
		local targetPos = rawMousePos + Vector3.new(0, CONFIG.DRAG_HEIGHT, 0)
		
		-- 2. Smooth Position
		local lerpAlpha = math.clamp(dt * CONFIG.DRAG_SMOOTHNESS, 0, 1)
		local newPos = currentPos:Lerp(targetPos, lerpAlpha)
		
		local velocity = (newPos - currentPos) / dt
		currentPos = newPos
		
		-- 3. Calculate Tilt
		local tiltAxis = velocity:Cross(Vector3.yAxis)
		local speed = velocity.Magnitude
		
		local targetTiltRot = CFrame.new()
		if speed > 0.1 and tiltAxis.Magnitude > 0.01 then
			local tiltAngle = math.rad(math.clamp(speed * CONFIG.TILT_STRENGTH, -CONFIG.MAX_TILT_ANGLE, CONFIG.MAX_TILT_ANGLE))
			targetTiltRot = CFrame.fromAxisAngle(tiltAxis.Unit, -tiltAngle)
		end
		
		currentTilt = currentTilt:Lerp(targetTiltRot, dt * CONFIG.TILT_RETURN_SPEED)
		
		-- 4. Apply
		if placementGhost then
			-- Apply offset so visual center follows cursor
			placementGhost:PivotTo(CFrame.new(currentPos + ghostCenterOffset) * currentTilt)
		end
		
		-- 5. Logic Checks
		local slot = getSlotUnderMouse()
		
		if slot then
			local tile = gridTiles[slot]
			local isOccupied = tile and tile:GetAttribute("IsOccupied")
			
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
			-- Check inventory hover
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
			local success, msg = RemoveBrainrotRemote:InvokeServer(sourceSlot)
			if success then
				updateStatus("✓ Stored " .. draggedUnit.name .. " in inventory")
				task.defer(renderBuildGrid)
				task.defer(refreshInventoryPanel)
			else
				updateStatus("✗ " .. (msg or "Store failed"))
			end
			
			isDragging = false
			draggedUnit = nil
			if dragConnection then
				dragConnection:Disconnect()
				dragConnection = nil
			end
			destroyPlacementGhost()
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
	
	ExitBuildMode:InvokeServer()
	
	isInBuildMode = false
	
	if currentHoverConnection then
		currentHoverConnection:Disconnect()
		currentHoverConnection = nil
	end
	
	destroyBuildGrid()
	
	inventoryPanel = nil
	inventoryItems = {}
	
	if buildModeGui then
		buildModeGui:Destroy()
		buildModeGui = nil
	end
	
	tweenToPlayerView()
	
	selectedSlot = nil
	hoveredSlot = nil
	
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.Tab then
		toggleBuildMode()
	elseif input.KeyCode == Enum.KeyCode.Escape and isInBuildMode then
		exitBuildModeLocal()
	end
end)

-- Mouse click handling
local mouse = LocalPlayer:GetMouse()
mouse.Button1Down:Connect(function()
	if not isInBuildMode then return end
	if isDragging then return end
	
	local brainrot, slotIndex = getBrainrotUnderMouse()
	if brainrot and slotIndex then
		startDragFromWorld(brainrot, slotIndex)
		return
	end
	
	handleClick()
end)

-- Mouse release
mouse.Button1Up:Connect(function()
	if not isInBuildMode or not isDragging then return end
	
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
		task.defer(renderBuildGrid)
	end
end)

--------------------------------------------------------------------------------
-- LISTEN FOR INVENTORY CHANGES (when brainrots are purchased)
--------------------------------------------------------------------------------

InventoryChangedEvent.OnClientEvent:Connect(function()
	if isInBuildMode then
		task.defer(refreshInventoryPanel)
	end
end)

-- Listen for InventoryToggleEvent (from HUD)
local InventoryToggleEvent = ReplicatedStorage:FindFirstChild("InventoryToggleEvent")
if not InventoryToggleEvent then
	InventoryToggleEvent = Instance.new("BindableEvent")
	InventoryToggleEvent.Name = "InventoryToggleEvent"
	InventoryToggleEvent.Parent = ReplicatedStorage
end
InventoryToggleEvent.Event:Connect(toggleBuildMode)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

print("✓ BuildModeUI initialized - Press TAB to toggle Build Mode")

_G.BuildModeUI = {
	Toggle = toggleBuildMode,
	Enter = enterBuildModeLocal,
	Exit = exitBuildModeLocal,
	IsActive = function() return isInBuildMode end,
}

