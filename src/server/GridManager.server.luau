--[[
	GridManager Server Script
	
	Manages grid-based brainrot placement on player plots.
	
	Features:
	- Grid sizes: 3×3 (starter), 3×4, 4×4, 5×5 (max)
	- LAYERED SLOTS: Each slot can have a Tile (flooring) AND a Unit on top
	- Place, move, swap, stash operations
	- Get adjacent units for synergy detection
	- CFrame calculation for grid positions (with tile height offset)
	
	Part of Phase 2: Spatial Puzzle system.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Shared configs
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TileConfig = require(Shared:WaitForChild("TileConfig"))

-- Constants
local BRAINROT_TAG = "ActiveBrainrot"
local _TILE_TAG = "GridTile"  -- Prefixed with _ as reserved for future use

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
	GRID_OFFSET_Y = 0, -- Units will be grounded via bounding box calculation
	
	-- Tile thickness for Y offset when unit is on tile
	TILE_THICKNESS = TileConfig.TileHeight,
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

-- BuildModeUI expects these as RemoteFunctions in RemoteEvents folder  
local PlaceBrainrotFunction = RemoteEvents:FindFirstChild("PlaceBrainrot") or Instance.new("RemoteFunction")
PlaceBrainrotFunction.Name = "PlaceBrainrot"
PlaceBrainrotFunction.Parent = RemoteEvents

local RemoveBrainrotFunction = RemoteEvents:FindFirstChild("RemoveBrainrot") or Instance.new("RemoteFunction")
RemoveBrainrotFunction.Name = "RemoveBrainrot"
RemoveBrainrotFunction.Parent = RemoteEvents

-- Tile RemoteFunction
local PlaceTileFunction = RemoteFunctions:FindFirstChild("PlaceTile") or Instance.new("RemoteFunction")
PlaceTileFunction.Name = "PlaceTile"
PlaceTileFunction.Parent = RemoteFunctions

local RemoveTileFunction = RemoteFunctions:FindFirstChild("RemoveTile") or Instance.new("RemoteFunction")
RemoveTileFunction.Name = "RemoveTile"
RemoveTileFunction.Parent = RemoteFunctions

--------------------------------------------------------------------------------
-- PLAYER GRID DATA
--------------------------------------------------------------------------------

--[[
	LAYERED SLOT STRUCTURE:
	{ [userId] = { 
		gridSize = "starter", 
		slots = { 
			[slotIndex] = { 
				Unit = brainrotInstance?,  -- The unit on this slot
				Tile = "TileId"?           -- The tile ID placed here
			} 
		}
		tileInstances = { [slotIndex] = TilePart }  -- Physical tile parts
	}}
]]
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
			slots = {},  -- { [slotIndex] = { Unit = Instance?, Tile = string? } }
			tileInstances = {},  -- { [slotIndex] = TilePart }
		}
	end
	return PlayerGrids[player.UserId]
end

--[[
	Gets or creates a slot data entry.
	@param gridData table
	@param slotIndex number
	@return table - The slot data { Unit, Tile }
]]
local function getSlotData(gridData, slotIndex)
	if not gridData.slots[slotIndex] then
		gridData.slots[slotIndex] = { Unit = nil, Tile = nil }
	end
	return gridData.slots[slotIndex]
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
	Gets the tile ID at a slot.
	@param player Player
	@param slotIndex number
	@return string? - The tile ID or nil
]]
local function getTileAtSlot(player, slotIndex)
	local gridData = getPlayerGrid(player)
	local slot = gridData.slots[slotIndex]
	if slot then
		return slot.Tile
	end
	return nil
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
	
	-- Add tile height if present
	local tileId = getTileAtSlot(player, slotIndex)
	if tileId then
		posY = posY + TileConfig.TileHeight
	end
	
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
	
	-- Calculate rotation to face plot center
	local unitPos = Vector3.new(posX, posY, posZ)
	local lookDirection = (plotCenter - unitPos) * Vector3.new(1, 0, 1) -- Flatten Y
	
	-- Face center
	local rotation = CFrame.lookAt(unitPos, unitPos + lookDirection)
	
	return rotation
end

--[[
	Gets the floor surface Y position for a player's plot.
	@param player Player
	@return number - The Y position of the floor's top surface
]]
local function getFloorTopY(player)
	local plot = findPlayerPlot(player)
	if not plot then return 10 end
	
	local floor = plot:FindFirstChild("Island") 
		or plot:FindFirstChild("PlotFloor") 
		or plot:FindFirstChild("Floor")
		or plot:FindFirstChildWhichIsA("BasePart")
	
	if floor and floor:IsA("BasePart") then
		-- Top of floor = center Y + half height
		return floor.Position.Y + (floor.Size.Y / 2)
	end
	
	return 10 -- Fallback
end

--[[
	Calculates a grounded CFrame for a model.
	Positions the model so its bottom sits exactly on the floor surface.
	
	@param baseCFrame CFrame - The base slot CFrame (X, Z position and rotation)
	@param model Model - The brainrot model to ground
	@param floorTopY number - The Y position of the floor's top surface
	@return CFrame - Adjusted CFrame with correct Y position
]]
local function getGroundedCFrame(baseCFrame, model, floorTopY)
	if not model or not model:IsA("Model") then
		return baseCFrame
	end
	
	-- Get model's bounding box to determine its height
	local success, boundsCF, boundsSize = pcall(function()
		return model:GetBoundingBox()
	end)
	
	if not success or not boundsSize then
		-- Fallback: just use floor top + a small offset
		local fallbackPos = Vector3.new(baseCFrame.Position.X, floorTopY + 3, baseCFrame.Position.Z)
		return CFrame.new(fallbackPos) * (baseCFrame - baseCFrame.Position)
	end
	
	-- Calculate how far the pivot is from the model's bottom
	local pivotPos = model:GetPivot().Position
	local boundsCenter = boundsCF.Position
	local modelBottomY = boundsCenter.Y - (boundsSize.Y / 2)
	local pivotToBottom = pivotPos.Y - modelBottomY  -- How far below pivot is the bottom
	
	-- Position: floor surface + distance from bottom to pivot
	local groundedY = floorTopY + pivotToBottom
	
	-- Create grounded CFrame with rotation from base
	local groundedPos = Vector3.new(baseCFrame.Position.X, groundedY, baseCFrame.Position.Z)
	return CFrame.new(groundedPos) * (baseCFrame - baseCFrame.Position)
end

--------------------------------------------------------------------------------
-- GRID OPERATIONS
--------------------------------------------------------------------------------



--[[
	Creates the visual tile part for a slot.
	@param player Player
	@param slotIndex number
	@param tileId string
	@return BasePart? - The created tile part
]]
local function createTileVisual(player, slotIndex, tileId)
	local tileData = TileConfig.GetTile(tileId)
	if not tileData then return nil end
	
	local plot = findPlayerPlot(player)
	if not plot then return nil end
	
	-- Get the position for this slot
	local baseCFrame = getSlotCFrame(player, slotIndex)
	local floorTopY = getFloorTopY(player)
	
	-- Create the tile part
	local tilePart = Instance.new("Part")
	tilePart.Name = "GridTile_" .. slotIndex
	tilePart.Size = Vector3.new(TileConfig.TileSize, TileConfig.TileHeight, TileConfig.TileSize)
	tilePart.Anchored = true
	tilePart.CanCollide = false
	tilePart.Material = Enum.Material.SmoothPlastic
	tilePart.Color = tileData.Color
	tilePart.Transparency = 0.2
	
	-- Position tile on floor
	local tileY = floorTopY + (TileConfig.TileHeight / 2)
	tilePart.Position = Vector3.new(baseCFrame.Position.X, tileY, baseCFrame.Position.Z)
	
	-- Add subtle glow effect
	local highlight = Instance.new("SurfaceLight")
	highlight.Color = tileData.Color
	highlight.Brightness = 0.3
	highlight.Range = 4
	highlight.Face = Enum.NormalId.Top
	highlight.Parent = tilePart
	
	-- Store tile ID as attribute
	tilePart:SetAttribute("TileId", tileId)
	tilePart:SetAttribute("SlotIndex", slotIndex)
	
	-- Parent to a Tiles folder in the plot
	local tilesFolder = plot:FindFirstChild("GridTiles") or Instance.new("Folder", plot)
	tilesFolder.Name = "GridTiles"
	tilePart.Parent = tilesFolder
	
	return tilePart
end

--[[
	Repositions a unit to account for tile height.
	@param player Player
	@param brainrot Model
	@param slotIndex number
]]
local function repositionUnitOnTile(player, brainrot, slotIndex)
	local gridData = getPlayerGrid(player)
	local slot = gridData.slots[slotIndex]
	if not brainrot then return end
	
	local baseCFrame = getSlotCFrame(player, slotIndex)
	local floorTopY = getFloorTopY(player)
	
	-- If there's a tile, raise the floor level
	if slot and slot.Tile then
		floorTopY = floorTopY + CONFIG.TILE_THICKNESS
	end
	
	local groundedCFrame = getGroundedCFrame(baseCFrame, brainrot, floorTopY)
	
	if brainrot:IsA("Model") then
		brainrot:PivotTo(groundedCFrame)
	elseif brainrot:IsA("BasePart") then
		brainrot.CFrame = groundedCFrame
	end
end

--[[
	Places a tile on a grid slot.
	@param player Player
	@param tileId string - The tile type ID
	@param slotIndex number - Target slot (1-indexed)
	@return boolean, string? - Success, error message
]]
local function placeTile(player, tileId, slotIndex)
	local gridData = getPlayerGrid(player)
	local totalSlots = getTotalSlots(player)
	
	-- Validate tile exists
	if not TileConfig.GetTile(tileId) then
		return false, "Invalid tile type"
	end
	
	-- Validate slot index
	if slotIndex < 1 or slotIndex > totalSlots then
		return false, "Invalid slot index"
	end
	
	-- Get or create slot data
	local slot = getSlotData(gridData, slotIndex)
	
	-- Remove existing tile visual if any
	if gridData.tileInstances[slotIndex] then
		gridData.tileInstances[slotIndex]:Destroy()
		gridData.tileInstances[slotIndex] = nil
	end
	
	-- Place the new tile
	slot.Tile = tileId
	
	-- Create visual
	local tileVisual = createTileVisual(player, slotIndex, tileId)
	if tileVisual then
		gridData.tileInstances[slotIndex] = tileVisual
	end
	
	-- Reposition any unit on this slot to be on top of tile
	if slot.Unit then
		repositionUnitOnTile(player, slot.Unit, slotIndex)
	end
	
	-- Notify clients
	GridUpdatedEvent:FireClient(player, slotIndex, tileId, "tile_placed")
	
	return true
end

--[[
	Removes a tile from a grid slot.
	@param player Player
	@param slotIndex number
	@return boolean, string? - Success, error message
]]
local function removeTile(player, slotIndex)
	local gridData = getPlayerGrid(player)
	local totalSlots = getTotalSlots(player)
	
	if slotIndex < 1 or slotIndex > totalSlots then
		return false, "Invalid slot index"
	end
	
	local slot = gridData.slots[slotIndex]
	if not slot or not slot.Tile then
		return false, "No tile in slot"
	end
	
	-- Remove tile visual
	if gridData.tileInstances[slotIndex] then
		gridData.tileInstances[slotIndex]:Destroy()
		gridData.tileInstances[slotIndex] = nil
	end
	
	-- Clear tile data
	slot.Tile = nil
	
	-- Reposition any unit to ground level
	if slot.Unit then
		repositionUnitOnTile(player, slot.Unit, slotIndex)
	end
	
	-- Notify clients
	GridUpdatedEvent:FireClient(player, slotIndex, nil, "tile_removed")
	
	return true
end

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
	
	-- Get slot data
	local slot = getSlotData(gridData, slotIndex)
	
	-- Check if slot already has a unit
	if slot.Unit then
		return false, "Slot is already occupied"
	end
	
	-- Check if this unit type is already placed elsewhere on the grid
	local unitType = brainrot:GetAttribute("UnitType") or brainrot.Name
	for _, slotData in pairs(gridData.slots) do
		if slotData.Unit then
			local otherType = slotData.Unit:GetAttribute("UnitType") or slotData.Unit.Name
			if otherType == unitType then
				return false, "You can only place one of each unit type!"
			end
		end
	end
	
	-- Place the brainrot
	slot.Unit = brainrot
	brainrot:SetAttribute("GridSlot", slotIndex)
	brainrot:SetAttribute("IsStored", false)
	
	-- Position unit (accounting for tile height)
	repositionUnitOnTile(player, brainrot, slotIndex)
	
	-- Anchor all parts
	for _, part in brainrot:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
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
	local fromSlotData = gridData.slots[fromSlot]
	if not fromSlotData or not fromSlotData.Unit then
		return false, "No unit in source slot"
	end
	
	-- Check if target slot unit is free
	local toSlotData = getSlotData(gridData, toSlot)
	if toSlotData.Unit then
		return false, "Target slot is occupied"
	end
	
	-- Move unit
	local brainrot = fromSlotData.Unit
	fromSlotData.Unit = nil
	toSlotData.Unit = brainrot
	brainrot:SetAttribute("GridSlot", toSlot)
	
	-- Reposition to new slot
	repositionUnitOnTile(player, brainrot, toSlot)
	
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
	
	local slot1Data = getSlotData(gridData, slot1)
	local slot2Data = getSlotData(gridData, slot2)
	
	local brainrot1 = slot1Data.Unit
	local brainrot2 = slot2Data.Unit
	
	-- Need at least one unit to swap
	if not brainrot1 and not brainrot2 then
		return false, "No units to swap"
	end
	
	-- Swap units
	slot1Data.Unit = brainrot2
	slot2Data.Unit = brainrot1
	
	-- Update positions
	if brainrot1 then
		brainrot1:SetAttribute("GridSlot", slot2)
		repositionUnitOnTile(player, brainrot1, slot2)
	end
	
	if brainrot2 then
		brainrot2:SetAttribute("GridSlot", slot1)
		repositionUnitOnTile(player, brainrot2, slot1)
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
	
	local slot = gridData.slots[slotIndex]
	if not slot or not slot.Unit then
		return nil, "No unit in slot"
	end
	
	local brainrot = slot.Unit
	slot.Unit = nil
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
		local slot = gridData.slots[adjSlot]
		if slot and slot.Unit then
			table.insert(adjacentUnits, {slot = adjSlot, brainrot = slot.Unit})
		end
	end
	
	return adjacentUnits
end

--[[
	Gets the full grid state for a player.
	@param player Player
	@return table - { gridSize, rows, cols, slots = { [slotIndex] = {unitType, tileId} } }
]]
local function getGridState(player)
	local gridData = getPlayerGrid(player)
	local rows, cols = getGridDimensions(player)
	
	local slotsState = {}
	for slotIndex, slot in pairs(gridData.slots) do
		slotsState[slotIndex] = {
			unitType = slot.Unit and (slot.Unit:GetAttribute("UnitType") or slot.Unit.Name) or nil,
			tileId = slot.Tile,
		}
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
		local slot = gridData.slots[i]
		if not slot or not slot.Unit then
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
	
	-- Convert slot data for saving
	local slotsData = {}
	for slotIndex, slot in pairs(gridData.slots) do
		local slotSave = {}
		if slot.Unit then
			slotSave.unitType = slot.Unit:GetAttribute("UnitType")
			slotSave.unitId = slot.Unit:GetAttribute("UnitId")
		end
		if slot.Tile then
			slotSave.tileId = slot.Tile
		end
		if slotSave.unitType or slotSave.tileId then
			slotsData[tostring(slotIndex)] = slotSave
		end
	end
	
	return {
		gridSize = gridData.gridSize,
		slots = slotsData,
	}
end

--[[
	Gets grid positions for DataManager persistence.
	Returns a table mapping slot indices to layered slot info.
	@param player Player
	@return table {[slotIndex]: {Unit = {unitType, rarity, ...}, Tile = tileId}}
]]
local function getGridPositions(player)
	local gridData = getPlayerGrid(player)
	local positions = {}
	
	for slotIndex, slotData in pairs(gridData.slots) do
		local entry = { Unit = nil, Tile = slotData.Tile }
		
	if slotData.Unit then
			local brainrot = slotData.Unit
			-- Only save primitive values that can be serialized to DataStore
			local unitType = brainrot:GetAttribute("UnitType")
			local rarity = brainrot:GetAttribute("Rarity")
			local level = brainrot:GetAttribute("Level")
			local unitId = brainrot:GetAttribute("UnitId")
			
			-- Only create entry if we have valid unit data
			if unitType and typeof(unitType) == "string" then
				entry.Unit = {
					unitType = unitType,
					rarity = (typeof(rarity) == "string") and rarity or "Normal",
					level = (typeof(level) == "number") and level or 1,
					unitId = (typeof(unitId) == "string") and unitId or nil,
					-- NOTE: equippedArtifacts removed - can contain non-serializable Instance data
				}
			end
		end
		
		-- Only save slots that have content
		if entry.Unit or entry.Tile then
			positions[tostring(slotIndex)] = entry
		end
	end
	
	return positions
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

-- Handler for placing a tile on grid
PlaceTileFunction.OnServerInvoke = function(player, tileId, slotIndex)
	-- TODO: Validate player has unlocked this tile type
	return placeTile(player, tileId, slotIndex)
end

-- Handler for removing a tile from grid
RemoveTileFunction.OnServerInvoke = function(player, slotIndex)
	return removeTile(player, slotIndex)
end

-- Handler for placing a brainrot from inventory/stash onto grid
PlaceBrainrotFunction.OnServerInvoke = function(player, unitName, rarity, slotIndex)
	-- First, find or spawn the brainrot
	local brainrot = nil
	
	-- Look for existing brainrot in player's Brainrots folder that matches type
	local plot = findPlayerPlot(player)
	if plot then
		local brainrotsContainer = plot:FindFirstChild("Brainrots")
		if brainrotsContainer then
			for _, unit in brainrotsContainer:GetChildren() do
				local unitType = unit:GetAttribute("UnitType")
				if unitType == unitName then
					brainrot = unit
					break
				end
			end
		end
	end
	
	-- If brainrot doesn't exist, spawn it using BrainrotManager
	if not brainrot then
		if _G.BrainrotManager and _G.BrainrotManager.AddUnit then
			brainrot = _G.BrainrotManager.AddUnit(player, unitName, rarity)
		end
	end
	
	if not brainrot then
		return false, "Could not find or create brainrot"
	end
	
	-- Now place on grid
	return placeUnit(player, brainrot, slotIndex)
end

-- Handler for removing/stashing a brainrot from grid
RemoveBrainrotFunction.OnServerInvoke = function(player, slotIndex)
	local brainrot, err = stashUnit(player, slotIndex)
	if brainrot then
		if _G.BrainrotManager and _G.BrainrotManager.StashBrainrot then
			_G.BrainrotManager.StashBrainrot(player, brainrot)
		end
		return true
	end
	return false, err
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	-- IMPORTANT: Delay cleanup to ensure DataService.OnSave has time to gather placement data first.
	-- DataService also listens to PlayerRemoving, and event handler order is not guaranteed.
	-- The 2-second delay ensures gatherPlayerData() can read PlayerGrids before it's cleared.
	task.delay(2, function()
		PlayerGrids[player.UserId] = nil
	end)
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
	
	-- Tile operations
	PlaceTile = placeTile,
	RemoveTile = removeTile,
	GetTileAtSlot = getTileAtSlot,
	
	-- Query functions
	GetGridDimensions = getGridDimensions,
	GetTotalSlots = getTotalSlots,
	GetSlotCFrame = getSlotCFrame,
	GetAdjacentSlots = getAdjacentSlots,
	GetAdjacentUnits = getAdjacentUnits,
	GetGridState = getGridState,
	
	-- Data persistence
	GetGridData = getGridData,
	GetGridPositions = getGridPositions,
	SetGridData = setGridData,
	SetGridSize = setGridSize,
	
	-- Config access
	CONFIG = CONFIG,
}
