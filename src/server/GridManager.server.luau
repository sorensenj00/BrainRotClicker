--[[
	GridManager Server Script
	
	Manages grid-based brainrot placement on player plots.
	
	Features:
	- Grid sizes: 3×3 (starter), 3×4, 4×4, 5×5 (max)
	- Place, move, swap, stash operations
	- Get adjacent units for synergy detection
	- CFrame calculation for grid positions
	
	Part of Phase 2: Spatial Puzzle system.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Constants
local BRAINROT_TAG = "ActiveBrainrot"

-- Configuration
local CONFIG = {
	-- Grid tile size in studs
	TILE_SIZE = 10,
	
	-- Grid sizes available (upgradeable)
	GRID_SIZES = {
		starter = {rows = 4, cols = 4},   -- 16 slots (default)
		bronze = {rows = 4, cols = 5},    -- 20 slots
		silver = {rows = 5, cols = 5},    -- 25 slots
		gold = {rows = 6, cols = 6},      -- 36 slots
	},
	
	-- Default grid size
	DEFAULT_GRID = "starter",
	
	-- Grid offset from plot TOP surface
	GRID_OFFSET_Y = 5, -- Height above plot top surface
}

-- Remote events
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not RemoteEvents then
	RemoteEvents = Instance.new("Folder")
	RemoteEvents.Name = "RemoteEvents"
	RemoteEvents.Parent = ReplicatedStorage
end

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions")
if not RemoteFunctions then
	RemoteFunctions = Instance.new("Folder")
	RemoteFunctions.Name = "RemoteFunctions"
	RemoteFunctions.Parent = ReplicatedStorage
end

-- Create events
local GridUpdatedEvent = RemoteEvents:FindFirstChild("GridUpdated") or Instance.new("RemoteEvent")
GridUpdatedEvent.Name = "GridUpdated"
GridUpdatedEvent.Parent = RemoteEvents

local UnitPlacedEvent = RemoteEvents:FindFirstChild("UnitPlaced") or Instance.new("RemoteEvent")
UnitPlacedEvent.Name = "UnitPlaced"
UnitPlacedEvent.Parent = RemoteEvents

-- Create functions
local PlaceUnitFunction = RemoteFunctions:FindFirstChild("PlaceUnit") or Instance.new("RemoteFunction")
PlaceUnitFunction.Name = "PlaceUnit"
PlaceUnitFunction.Parent = RemoteFunctions

local MoveUnitFunction = RemoteFunctions:FindFirstChild("MoveUnit") or Instance.new("RemoteFunction")
MoveUnitFunction.Name = "MoveUnit"
MoveUnitFunction.Parent = RemoteFunctions

local SwapUnitsFunction = RemoteFunctions:FindFirstChild("SwapUnits") or Instance.new("RemoteFunction")
SwapUnitsFunction.Name = "SwapUnits"
SwapUnitsFunction.Parent = RemoteFunctions

local StashUnitFunction = RemoteFunctions:FindFirstChild("StashUnit") or Instance.new("RemoteFunction")
StashUnitFunction.Name = "StashUnit"
StashUnitFunction.Parent = RemoteFunctions

local GetGridFunction = RemoteFunctions:FindFirstChild("GetGrid") or Instance.new("RemoteFunction")
GetGridFunction.Name = "GetGrid"
GetGridFunction.Parent = RemoteFunctions

--------------------------------------------------------------------------------
-- PLAYER GRID DATA
--------------------------------------------------------------------------------

-- { [userId] = { gridSize = "starter", slots = { [slotIndex] = brainrotInstance } } }
local PlayerGrids = {}

--[[
	Gets or creates grid data for a player.
	@param player Player
	@return table - Grid data
]]
local function getPlayerGrid(player)
	if not PlayerGrids[player.UserId] then
		PlayerGrids[player.UserId] = {
			gridSize = CONFIG.DEFAULT_GRID,
			slots = {},  -- { [slotIndex] = brainrotInstance }
		}
	end
	return PlayerGrids[player.UserId]
end

--[[
	Gets the grid dimensions for a player.
	@param player Player
	@return number, number - rows, cols
]]
local function getGridDimensions(player)
	local gridData = getPlayerGrid(player)
	local sizeConfig = CONFIG.GRID_SIZES[gridData.gridSize] or CONFIG.GRID_SIZES.starter
	return sizeConfig.rows, sizeConfig.cols
end

--[[
	Gets the total number of slots for a player.
	@param player Player
	@return number
]]
local function getTotalSlots(player)
	local rows, cols = getGridDimensions(player)
	return rows * cols
end

--[[
	Converts slot index to row, col (0-indexed internally).
	@param slotIndex number - 1-indexed slot number
	@param rows number
	@param cols number
	@return number, number - row, col (0-indexed)
]]
local function slotToRowCol(slotIndex, rows, cols)
	local index = slotIndex - 1
	local row = math.floor(index / cols)
	local col = index % cols
	return row, col
end

--[[
	Converts row, col to slot index.
	@param row number - 0-indexed
	@param col number - 0-indexed
	@param cols number
	@return number - 1-indexed slot number
]]
local function rowColToSlot(row, col, cols)
	return (row * cols) + col + 1
end

--------------------------------------------------------------------------------
-- PLOT & POSITION HELPERS
--------------------------------------------------------------------------------

--[[
	Finds the player's plot in workspace.
	@param player Player
	@return Instance? - The plot model/part
]]
local function findPlayerPlot(player)
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	
	for _, plot in plotsFolder:GetChildren() do
		if plot:GetAttribute("OwnerId") == player.UserId then
			return plot
		end
	end
	
	return nil
end

--[[
	Gets the plot floor position (CENTER of the plot's main part).
	@param plot Instance
	@return Vector3?
]]
local function getPlotCenter(plot)
	-- Try to find the main floor part (check multiple possible names)
	local floor = plot:FindFirstChild("Island") 
		or plot:FindFirstChild("PlotFloor") 
		or plot:FindFirstChild("Floor")
		or plot:FindFirstChildWhichIsA("BasePart")
	
	if floor and floor:IsA("BasePart") then
		return floor.Position
	end
	
	-- If plot is a model, use bounding box center
	if plot:IsA("Model") then
		local cf, size = plot:GetBoundingBox()
		return cf.Position
	end
	
	-- If plot is a part
	if plot:IsA("BasePart") then
		return plot.Position
	end
	
	return Vector3.new(0, 5, 0)
end

--[[
	Gets the plot floor size.
	@param plot Instance
	@return Vector3
]]
local function getPlotSize(plot)
	-- Try to find the main floor part (check multiple possible names)
	local floor = plot:FindFirstChild("Island") 
		or plot:FindFirstChild("PlotFloor") 
		or plot:FindFirstChild("Floor")
		or plot:FindFirstChildWhichIsA("BasePart")
	
	if floor and floor:IsA("BasePart") then
		return floor.Size
	end
	
	if plot:IsA("BasePart") then
		return plot.Size
	end
	
	-- If plot is a model, use bounding box
	if plot:IsA("Model") then
		local cf, size = plot:GetBoundingBox()
		return size
	end
	
	return Vector3.new(50, 10, 50) -- Default (thick plot)
end

--[[
	Calculates the world position for a grid slot.
	Uses 4 corner clusters layout:
	- Corner 1 (top-left): slots 1-4
	- Corner 2 (top-right): slots 5-8
	- Corner 3 (bottom-left): slots 9-12
	- Corner 4 (bottom-right): slots 13-16
	
	@param player Player
	@param slotIndex number
	@return CFrame - The position and rotation for the slot
]]
local function getSlotCFrame(player, slotIndex)
	local plot = findPlayerPlot(player)
	if not plot then return CFrame.new(0, 10, 0) end
	
	local plotCenter = getPlotCenter(plot)
	local plotSize = getPlotSize(plot)
	
	-- Y position: top of plot (center + half height) + offset
	local posY = plotCenter.Y + (plotSize.Y / 2) + CONFIG.GRID_OFFSET_Y
	
	-- Corner cluster configuration
	local CLUSTER_SIZE = 2  -- 2x2 per corner
	local TILE_SPACING = CONFIG.TILE_SIZE
	
	-- Calculate corner offsets (distance from center to corner cluster center)
	local cornerOffsetX = (plotSize.X / 2) - (CLUSTER_SIZE * TILE_SPACING / 2) - TILE_SPACING
	local cornerOffsetZ = (plotSize.Z / 2) - (CLUSTER_SIZE * TILE_SPACING / 2) - TILE_SPACING
	
	-- Determine which corner (0-3) and position within corner (0-3)
	local cornerIndex = math.floor((slotIndex - 1) / 4)
	local posInCorner = (slotIndex - 1) % 4
	
	-- Position within 2x2 cluster
	local localRow = math.floor(posInCorner / 2)
	local localCol = posInCorner % 2
	
	-- Corner base positions (relative to plot center)
	local cornerPositions = {
		{x = -cornerOffsetX, z = -cornerOffsetZ},  -- Top-left
		{x = cornerOffsetX, z = -cornerOffsetZ},   -- Top-right
		{x = -cornerOffsetX, z = cornerOffsetZ},   -- Bottom-left
		{x = cornerOffsetX, z = cornerOffsetZ},    -- Bottom-right
	}
	
	local corner = cornerPositions[cornerIndex + 1] or cornerPositions[1]
	
	-- Calculate final position
	local posX = plotCenter.X + corner.x + (localCol - 0.5) * TILE_SPACING
	local posZ = plotCenter.Z + corner.z + (localRow - 0.5) * TILE_SPACING
	
	return CFrame.new(posX, posY, posZ)
end

--------------------------------------------------------------------------------
-- GRID OPERATIONS
--------------------------------------------------------------------------------

--[[
	Places a brainrot on a grid slot.
	@param player Player
	@param brainrot Instance - The brainrot model
	@param slotIndex number - Target slot (1-indexed)
	@return boolean, string? - Success, error message
]]
local function placeUnit(player, brainrot, slotIndex)
	local gridData = getPlayerGrid(player)
	local totalSlots = getTotalSlots(player)
	
	-- Validate slot index
	if slotIndex < 1 or slotIndex > totalSlots then
		return false, "Invalid slot index"
	end
	
	-- Check if slot is occupied
	if gridData.slots[slotIndex] then
		return false, "Slot is already occupied"
	end
	
	-- Place the brainrot
	gridData.slots[slotIndex] = brainrot
	brainrot:SetAttribute("GridSlot", slotIndex)
	
	-- Update position
	local cframe = getSlotCFrame(player, slotIndex)
	if brainrot:IsA("Model") and brainrot.PrimaryPart then
		brainrot:SetPrimaryPartCFrame(cframe)
	elseif brainrot:IsA("BasePart") then
		brainrot.CFrame = cframe
	end
	
	-- Notify clients
	GridUpdatedEvent:FireClient(player, slotIndex, brainrot.Name, "placed")
	
	return true
end

--[[
	Moves a brainrot from one slot to another.
	@param player Player
	@param fromSlot number
	@param toSlot number
	@return boolean, string?
]]
local function moveUnit(player, fromSlot, toSlot)
	local gridData = getPlayerGrid(player)
	local totalSlots = getTotalSlots(player)
	
	-- Validate slots
	if fromSlot < 1 or fromSlot > totalSlots then
		return false, "Invalid source slot"
	end
	if toSlot < 1 or toSlot > totalSlots then
		return false, "Invalid target slot"
	end
	
	-- Check if source has a unit
	local brainrot = gridData.slots[fromSlot]
	if not brainrot then
		return false, "No unit in source slot"
	end
	
	-- Check if target is free
	if gridData.slots[toSlot] then
		return false, "Target slot is occupied"
	end
	
	-- Move
	gridData.slots[fromSlot] = nil
	gridData.slots[toSlot] = brainrot
	brainrot:SetAttribute("GridSlot", toSlot)
	
	-- Update position
	local cframe = getSlotCFrame(player, toSlot)
	if brainrot:IsA("Model") and brainrot.PrimaryPart then
		brainrot:SetPrimaryPartCFrame(cframe)
	elseif brainrot:IsA("BasePart") then
		brainrot.CFrame = cframe
	end
	
	-- Notify clients
	GridUpdatedEvent:FireClient(player, toSlot, brainrot.Name, "moved")
	
	return true
end

--[[
	Swaps two brainrots between slots.
	@param player Player
	@param slot1 number
	@param slot2 number
	@return boolean, string?
]]
local function swapUnits(player, slot1, slot2)
	local gridData = getPlayerGrid(player)
	local totalSlots = getTotalSlots(player)
	
	-- Validate slots
	if slot1 < 1 or slot1 > totalSlots then
		return false, "Invalid slot 1"
	end
	if slot2 < 1 or slot2 > totalSlots then
		return false, "Invalid slot 2"
	end
	
	local brainrot1 = gridData.slots[slot1]
	local brainrot2 = gridData.slots[slot2]
	
	-- Need at least one unit to swap
	if not brainrot1 and not brainrot2 then
		return false, "No units to swap"
	end
	
	-- Swap
	gridData.slots[slot1] = brainrot2
	gridData.slots[slot2] = brainrot1
	
	-- Update positions and attributes
	if brainrot1 then
		brainrot1:SetAttribute("GridSlot", slot2)
		local cframe = getSlotCFrame(player, slot2)
		if brainrot1:IsA("Model") and brainrot1.PrimaryPart then
			brainrot1:SetPrimaryPartCFrame(cframe)
		elseif brainrot1:IsA("BasePart") then
			brainrot1.CFrame = cframe
		end
	end
	
	if brainrot2 then
		brainrot2:SetAttribute("GridSlot", slot1)
		local cframe = getSlotCFrame(player, slot1)
		if brainrot2:IsA("Model") and brainrot2.PrimaryPart then
			brainrot2:SetPrimaryPartCFrame(cframe)
		elseif brainrot2:IsA("BasePart") then
			brainrot2.CFrame = cframe
		end
	end
	
	-- Notify clients
	GridUpdatedEvent:FireClient(player, slot1, brainrot2 and brainrot2.Name or nil, "swapped")
	GridUpdatedEvent:FireClient(player, slot2, brainrot1 and brainrot1.Name or nil, "swapped")
	
	return true
end

--[[
	Removes a brainrot from the grid (stashes it).
	@param player Player
	@param slotIndex number
	@return Instance?, string? - The removed brainrot, error message
]]
local function stashUnit(player, slotIndex)
	local gridData = getPlayerGrid(player)
	local totalSlots = getTotalSlots(player)
	
	if slotIndex < 1 or slotIndex > totalSlots then
		return nil, "Invalid slot index"
	end
	
	local brainrot = gridData.slots[slotIndex]
	if not brainrot then
		return nil, "No unit in slot"
	end
	
	-- Remove from grid
	gridData.slots[slotIndex] = nil
	brainrot:SetAttribute("GridSlot", nil)
	
	-- Notify clients
	GridUpdatedEvent:FireClient(player, slotIndex, nil, "stashed")
	
	return brainrot
end

--[[
	Gets adjacent slot indices for synergy detection.
	@param player Player
	@param slotIndex number
	@return table - Array of adjacent slot indices
]]
local function getAdjacentSlots(player, slotIndex)
	local rows, cols = getGridDimensions(player)
	local row, col = slotToRowCol(slotIndex, rows, cols)
	
	local adjacents = {}
	
	-- Up
	if row > 0 then
		table.insert(adjacents, rowColToSlot(row - 1, col, cols))
	end
	-- Down
	if row < rows - 1 then
		table.insert(adjacents, rowColToSlot(row + 1, col, cols))
	end
	-- Left
	if col > 0 then
		table.insert(adjacents, rowColToSlot(row, col - 1, cols))
	end
	-- Right
	if col < cols - 1 then
		table.insert(adjacents, rowColToSlot(row, col + 1, cols))
	end
	
	return adjacents
end

--[[
	Gets the brainrots in adjacent slots.
	@param player Player
	@param slotIndex number
	@return table - Array of {slot = number, brainrot = Instance}
]]
local function getAdjacentUnits(player, slotIndex)
	local gridData = getPlayerGrid(player)
	local adjacentSlots = getAdjacentSlots(player, slotIndex)
	
	local adjacentUnits = {}
	for _, adjSlot in adjacentSlots do
		local brainrot = gridData.slots[adjSlot]
		if brainrot then
			table.insert(adjacentUnits, {slot = adjSlot, brainrot = brainrot})
		end
	end
	
	return adjacentUnits
end

--[[
	Gets the full grid state for a player.
	@param player Player
	@return table - { gridSize, rows, cols, slots = { [slotIndex] = unitType } }
]]
local function getGridState(player)
	local gridData = getPlayerGrid(player)
	local rows, cols = getGridDimensions(player)
	
	local slotsState = {}
	for slotIndex, brainrot in pairs(gridData.slots) do
		slotsState[slotIndex] = brainrot:GetAttribute("UnitType") or brainrot.Name
	end
	
	return {
		gridSize = gridData.gridSize,
		rows = rows,
		cols = cols,
		slots = slotsState,
	}
end

--[[
	Finds the first empty slot.
	@param player Player
	@return number? - First empty slot index, or nil if full
]]
local function findEmptySlot(player)
	local gridData = getPlayerGrid(player)
	local totalSlots = getTotalSlots(player)
	
	for i = 1, totalSlots do
		if not gridData.slots[i] then
			return i
		end
	end
	
	return nil
end

--[[
	Sets the grid size for a player (upgrade).
	@param player Player
	@param sizeName string - "starter", "bronze", "silver", "gold"
	@return boolean
]]
local function setGridSize(player, sizeName)
	if not CONFIG.GRID_SIZES[sizeName] then
		return false
	end
	
	local gridData = getPlayerGrid(player)
	gridData.gridSize = sizeName
	
	-- Notify client
	GridUpdatedEvent:FireClient(player, 0, sizeName, "resize")
	
	return true
end

--------------------------------------------------------------------------------
-- DATA PERSISTENCE HOOKS
--------------------------------------------------------------------------------

--[[
	Gets grid data for saving.
	@param player Player
	@return table
]]
local function getGridData(player)
	local gridData = getPlayerGrid(player)
	
	-- Convert brainrot instances to slot data
	local slotsData = {}
	for slotIndex, brainrot in pairs(gridData.slots) do
		slotsData[tostring(slotIndex)] = {
			unitType = brainrot:GetAttribute("UnitType"),
			unitId = brainrot:GetAttribute("UnitId"),
		}
	end
	
	return {
		gridSize = gridData.gridSize,
		slots = slotsData,
	}
end

--[[
	Sets grid data from saved data.
	@param player Player
	@param data table
]]
local function setGridData(player, data)
	if not data then return end
	
	local gridData = getPlayerGrid(player)
	gridData.gridSize = data.gridSize or CONFIG.DEFAULT_GRID
	
	-- Note: Cannot restore brainrot instances here - that's handled by BrainrotManager
	-- The slots will be populated when brainrots are spawned
end

--------------------------------------------------------------------------------
-- REMOTE FUNCTION HANDLERS
--------------------------------------------------------------------------------

PlaceUnitFunction.OnServerInvoke = function(player, brainrotId, slotIndex)
	-- Find the brainrot by ID attribute
	for _, brainrot in CollectionService:GetTagged(BRAINROT_TAG) do
		if brainrot:GetAttribute("UnitId") == brainrotId 
			and brainrot:GetAttribute("OwnerId") == player.UserId then
			return placeUnit(player, brainrot, slotIndex)
		end
	end
	return false, "Brainrot not found"
end

MoveUnitFunction.OnServerInvoke = function(player, fromSlot, toSlot)
	return moveUnit(player, fromSlot, toSlot)
end

SwapUnitsFunction.OnServerInvoke = function(player, slot1, slot2)
	return swapUnits(player, slot1, slot2)
end

StashUnitFunction.OnServerInvoke = function(player, slotIndex)
	local brainrot, err = stashUnit(player, slotIndex)
	if brainrot then
		-- Notify BrainrotManager to handle stashing
		if _G.BrainrotManager and _G.BrainrotManager.StashBrainrot then
			_G.BrainrotManager.StashBrainrot(player, brainrot)
		end
		return true
	end
	return false, err
end

GetGridFunction.OnServerInvoke = function(player)
	return getGridState(player)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	PlayerGrids[player.UserId] = nil
end)

print("═══════════════════════════════════════════")
print("   GridManager - Initializing")
print("═══════════════════════════════════════════")
print("✓ GridManager initialized")
print("  • Default grid: " .. CONFIG.DEFAULT_GRID .. " (" .. CONFIG.GRID_SIZES.starter.rows .. "x" .. CONFIG.GRID_SIZES.starter.cols .. ")")
print("  • Tile size: " .. CONFIG.TILE_SIZE .. " studs")
print("═══════════════════════════════════════════")

-- Export API
_G.GridManager = {
	-- Grid operations
	PlaceUnit = placeUnit,
	MoveUnit = moveUnit,
	SwapUnits = swapUnits,
	StashUnit = stashUnit,
	FindEmptySlot = findEmptySlot,
	
	-- Query functions
	GetGridDimensions = getGridDimensions,
	GetTotalSlots = getTotalSlots,
	GetSlotCFrame = getSlotCFrame,
	GetAdjacentSlots = getAdjacentSlots,
	GetAdjacentUnits = getAdjacentUnits,
	GetGridState = getGridState,
	
	-- Data persistence
	GetGridData = getGridData,
	SetGridData = setGridData,
	SetGridSize = setGridSize,
	
	-- Config access
	CONFIG = CONFIG,
}
