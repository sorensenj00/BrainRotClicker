--[[
	GridManager Server Module
	
	Manages grid-based brainrot placement on player plots.
	
	CONVERTED TO MODULE SCRIPT
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Shared configs
-- Shared configs (Lazy Loaded)
local TileConfig

local function getTileConfig()
	if not TileConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		TileConfig = require(Shared:WaitForChild("TileConfig"))
	end
	return TileConfig
end

-- DataService for real-time grid persistence
local DataService = require(script.Parent.DataService)

-- Constants
local BRAINROT_TAG = "ActiveBrainrot"
local _TILE_TAG = "GridTile"
local CONFIG = {
	TILE_SIZE = 10,
	GRID_SIZES = {
		starter = {rows = 4, cols = 4},   -- 16 slots
		bronze = {rows = 4, cols = 5},    -- 20 slots
		silver = {rows = 5, cols = 5},    -- 25 slots
		gold = {rows = 6, cols = 6},      -- 36 slots
	},
	DEFAULT_GRID = "starter",
	GRID_OFFSET_Y = 0,
	TILE_THICKNESS = 1, -- Default, updated from config later if needed
}

-- Remote Objects (created if missing)
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

local GridUpdatedEvent = RemoteEvents:FindFirstChild("GridUpdated") or Instance.new("RemoteEvent")
GridUpdatedEvent.Name = "GridUpdated"
GridUpdatedEvent.Parent = RemoteEvents

local UnitPlacedEvent = RemoteEvents:FindFirstChild("UnitPlaced") or Instance.new("RemoteEvent")
UnitPlacedEvent.Name = "UnitPlaced"
UnitPlacedEvent.Parent = RemoteEvents

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

-- Admin/Debug functions referenced in legacy
local PlaceBrainrotFunction = RemoteEvents:FindFirstChild("PlaceBrainrot") or Instance.new("RemoteFunction")
PlaceBrainrotFunction.Name = "PlaceBrainrot"
PlaceBrainrotFunction.Parent = RemoteEvents

local RemoveBrainrotFunction = RemoteEvents:FindFirstChild("RemoveBrainrot") or Instance.new("RemoteFunction")
RemoveBrainrotFunction.Name = "RemoveBrainrot"
RemoveBrainrotFunction.Parent = RemoteEvents

local PlaceTileFunction = RemoteFunctions:FindFirstChild("PlaceTile") or Instance.new("RemoteFunction")
PlaceTileFunction.Name = "PlaceTile"
PlaceTileFunction.Parent = RemoteFunctions

local RemoveTileFunction = RemoteFunctions:FindFirstChild("RemoveTile") or Instance.new("RemoteFunction")
RemoveTileFunction.Name = "RemoveTile"
RemoveTileFunction.Parent = RemoteFunctions

-- Module Table
local GridManager = {}

-- Player Grid Data
local PlayerGrids = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getPlayerGrid(player)
	if not PlayerGrids[player.UserId] then
		PlayerGrids[player.UserId] = {
			gridSize = CONFIG.DEFAULT_GRID,
			slots = {},
			tileInstances = {},
		}
	end
	return PlayerGrids[player.UserId]
end

local function getSlotData(gridData, slotIndex)
	if not gridData.slots[slotIndex] then
		gridData.slots[slotIndex] = { Unit = nil, Tile = nil }
	end
	return gridData.slots[slotIndex]
end

local function getGridDimensions(player)
	local gridData = getPlayerGrid(player)
	local sizeConfig = CONFIG.GRID_SIZES[gridData.gridSize] or CONFIG.GRID_SIZES.starter
	return sizeConfig.rows, sizeConfig.cols
end

local function getTotalSlots(player)
	local rows, cols = getGridDimensions(player)
	return rows * cols
end

local function findPlayerPlot(player)
	-- Assumes plots are in Workspace.Plots and have OwnerId attribute
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	for _, plot in plotsFolder:GetChildren() do
		if plot:GetAttribute("OwnerId") == player.UserId then return plot end
	end
	return nil
end

local function getPlotCenter(plot)
	local floor = plot:FindFirstChild("Island") or plot:FindFirstChild("PlotFloor") or plot:FindFirstChild("Floor") or plot:FindFirstChildWhichIsA("BasePart")
	if floor and floor:IsA("BasePart") then return floor.Position end
	if plot:IsA("Model") then return plot:GetBoundingBox().Position end
	if plot:IsA("BasePart") then return plot.Position end
	return Vector3.new(0, 5, 0)
end

local function getPlotSize(plot)
	local floor = plot:FindFirstChild("Island") or plot:FindFirstChild("PlotFloor") or plot:FindFirstChild("Floor") or plot:FindFirstChildWhichIsA("BasePart")
	if floor and floor:IsA("BasePart") then return floor.Size end
	if plot:IsA("BasePart") then return plot.Size end
	if plot:IsA("Model") then local _, size = plot:GetBoundingBox(); return size end
	return Vector3.new(50, 10, 50)
end

local function getTileAtSlot(player, slotIndex)
	local gridData = getPlayerGrid(player)
	local slot = gridData.slots[slotIndex]
	return slot and slot.Tile
end

local function getFloorTopY(player)
	local plot = findPlayerPlot(player)
	if not plot then return 10 end
	local floor = plot:FindFirstChild("Island") or plot:FindFirstChild("PlotFloor") or plot:FindFirstChild("Floor") or plot:FindFirstChildWhichIsA("BasePart")
	if floor and floor:IsA("BasePart") then
		return floor.Position.Y + (floor.Size.Y / 2)
	end
	return 10
end

local function getSlotCFrame(player, slotIndex)
	local plot = findPlayerPlot(player)
	if not plot then return CFrame.new(0, 10, 0) end
	
	local plotCenter = getPlotCenter(plot)
	local plotSize = getPlotSize(plot)
	
	local posY = plotCenter.Y + (plotSize.Y / 2) + CONFIG.GRID_OFFSET_Y
	local tileId = getTileAtSlot(player, slotIndex)
	if tileId then 
		local tc = getTileConfig()
		posY = posY + tc.TileHeight 
	end
	
	local CLUSTER_SIZE = 2
	local TILE_SPACING = CONFIG.TILE_SIZE
	local cornerOffsetX = (plotSize.X / 2) - (CLUSTER_SIZE * TILE_SPACING / 2) - TILE_SPACING
	local cornerOffsetZ = (plotSize.Z / 2) - (CLUSTER_SIZE * TILE_SPACING / 2) - TILE_SPACING
	
	local cornerIndex = math.floor((slotIndex - 1) / 4)
	local posInCorner = (slotIndex - 1) % 4
	
	local localRow = math.floor(posInCorner / 2)
	local localCol = posInCorner % 2
	
	local cornerPositions = {
		{x = -cornerOffsetX, z = -cornerOffsetZ},
		{x = cornerOffsetX, z = -cornerOffsetZ},
		{x = -cornerOffsetX, z = cornerOffsetZ},
		{x = cornerOffsetX, z = cornerOffsetZ},
	}
	local corner = cornerPositions[cornerIndex + 1] or cornerPositions[1]
	
	local posX = plotCenter.X + corner.x + (localCol - 0.5) * TILE_SPACING
	local posZ = plotCenter.Z + corner.z + (localRow - 0.5) * TILE_SPACING
	
	local unitPos = Vector3.new(posX, posY, posZ)
	local lookDirection = (plotCenter - unitPos) * Vector3.new(1, 0, 1)
	
	if lookDirection.Magnitude == 0 then lookDirection = Vector3.new(0, 0, -1) end
	return CFrame.lookAt(unitPos, unitPos + lookDirection)
end

local function getGroundedCFrame(baseCFrame, model, floorTopY)
	if not model or not model:IsA("Model") then return baseCFrame end
	local success, _, boundsSize = pcall(function() return model:GetBoundingBox() end)
	if not success or not boundsSize then
		return CFrame.new(Vector3.new(baseCFrame.Position.X, floorTopY + 3, baseCFrame.Position.Z)) * (baseCFrame - baseCFrame.Position)
	end
	local pivotPos = model:GetPivot().Position
	local modelBottomY = pivotPos.Y - (boundsSize.Y / 2) -- Approximation if Pivot is Center
	-- Better approximation:
	local _, size = model:GetBoundingBox()
	-- If pivot is at center, bottom is pivot.y - size.y/2
	-- If pivot is at bottom, bottom is pivot.y
	-- We'll assume standard model setup (pivot at center or bottom).
	-- Let's just blindly trust the original logic's intent but simplify:
	-- The original logic used bounds center to pivot distance.
	-- We will standardly anchor at floor Y.
	
	local groundedPos = Vector3.new(baseCFrame.Position.X, floorTopY, baseCFrame.Position.Z)
	-- To make the model sit ON the floor, we need to know where its bottom is relative to its PrimaryPart/Pivot.
	-- We'll manually adjust up by half height for now as safe default if we assume pivot is center.
	-- Or just use the passed in baseCFrame Y if it was calculated correctly.
	-- The getSlotCFrame calculates Y based on plot surface.
	return baseCFrame
end

local function repositionUnitOnTile(player, brainrot, slotIndex)
	if not brainrot then return end
	local baseCFrame = getSlotCFrame(player, slotIndex)
	-- getSlotCFrame already accounts for tile height in its Y calculation!
	-- We just need to apply it.
	brainrot:PivotTo(baseCFrame)
end

local function createTileVisual(player, slotIndex, tileId)
	local tc = getTileConfig()
	local tileData = tc.GetTile(tileId)
	if not tileData then return nil end
	local plot = findPlayerPlot(player)
	if not plot then return nil end
	
	local baseCFrame = getSlotCFrame(player, slotIndex) -- Includes Tile Y offset
	-- But the tile itself needs to be BELOW that unit surface
	local floorTopY = getFloorTopY(player)
	local tileY = floorTopY + (tc.TileHeight / 2)
	
	local tilePart = Instance.new("Part")
	tilePart.Name = "GridTile_" .. slotIndex
	tilePart.Size = Vector3.new(tc.TileSize, tc.TileHeight, tc.TileSize)
	tilePart.Anchored = true
	tilePart.CanCollide = false
	tilePart.Material = Enum.Material.SmoothPlastic
	tilePart.Color = tileData.Color
	tilePart.Transparency = 0.2
	tilePart.Position = Vector3.new(baseCFrame.Position.X, tileY, baseCFrame.Position.Z)
	
	local highlight = Instance.new("SurfaceLight")
	highlight.Color = tileData.Color
	highlight.Brightness = 0.3
	highlight.Range = 4
	highlight.Face = Enum.NormalId.Top
	highlight.Parent = tilePart
	
	tilePart:SetAttribute("TileId", tileId)
	tilePart:SetAttribute("SlotIndex", slotIndex)
	
	local tilesFolder = plot:FindFirstChild("GridTiles") or Instance.new("Folder", plot)
	tilesFolder.Name = "GridTiles"
	tilePart.Parent = tilesFolder
	
	return tilePart
end

local function syncToProfile(player)
	if DataService.IsLoaded(player) then
		local gridData = getPlayerGrid(player)
		local positions = {}
		for idx, slotInfo in pairs(gridData.slots) do
			if slotInfo.Unit or slotInfo.Tile then
				local entry = { Unit = nil, Tile = slotInfo.Tile }
				if slotInfo.Unit then
					local u = slotInfo.Unit
					local uType = u:GetAttribute("UnitType")
					if uType then
						entry.Unit = {
							unitType = uType,
							rarity = u:GetAttribute("Rarity") or "Normal",
							level = u:GetAttribute("Level") or 1,
							unitId = u:GetAttribute("UnitId"),
						}
					end
				end
				positions[tostring(idx)] = entry
			end
		end
		DataService.SetComponentData(player, "GridPlacements", positions)
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function GridManager.Init()
	print("   GridManager (Module) - Initializing")
	
	-- Register Data Handler
	DataService.RegisterHandler("GridPlacements", {
		DefaultData = {},
		OnLoad = function(player, data)
			-- Restore Grid
			if not data then
				local PlayerLifecycleManager = require(script.Parent.PlayerLifecycleManager)
				PlayerLifecycleManager.SetGridRestored(player)
				return
			end
			
			task.spawn(function()
				-- Lazy load dependencies if needed
				local BrainrotManager = _G.BrainrotManager
				local MapSystem = _G.MapSystem
				
				-- WAIT FOR PLOT (Fix Race Condition)
				local plot = nil
				local attempts = 0
				while not plot and attempts < 100 do -- Wait up to 10s
					if not player.Parent then return end -- Player left
					
					if MapSystem and MapSystem.GetPlayerPlot then
						plot = MapSystem.GetPlayerPlot(player)
					end
					
					if not plot then
						task.wait(0.1)
						attempts += 1
						BrainrotManager = _G.BrainrotManager
						MapSystem = _G.MapSystem
					end
				end
				
				if not plot then
					warn("GridManager: Could not find plot for " .. player.Name .. " - Grid restoration failed")
					return
				end
				
				-- Proceed with restoration
				for slotIndexStr, slotData in pairs(data) do
					local slotIndex = tonumber(slotIndexStr)
					if slotIndex then
						-- Restore Tile
						if slotData.Tile then
							GridManager.PlaceTile(player, slotIndex, slotData.Tile)
						end
						
						-- Restore Unit
						if slotData.Unit and BrainrotManager then
							-- Reconstruct placement data for BrainrotManager
							local placementData = {
								unitType = slotData.Unit.unitType,
								rarity = slotData.Unit.rarity,
								level = slotData.Unit.level,
								unitId = slotData.Unit.unitId,
								slotIndex = slotIndex
							}
							-- Spawn physical unit and place it
							BrainrotManager.SpawnFromPlacement(player, placementData)
						end
					end
				end
				
				local PlayerLifecycleManager = require(script.Parent.PlayerLifecycleManager)
				PlayerLifecycleManager.SetGridRestored(player)
			end)
		end,
		OnSave = function(player, data)
			-- Return current state to ensure it's saved correctly
			return GridManager.GetGridPositions(player)
		end
	})
	
	-- NOTE: PlayerGrids cleanup removed to prevent race condition with DataService save
	-- DataService OnSave will read from PlayerGrids, so we must NOT clear it before save completes
	
	-- Connect Remotes
	PlaceUnitFunction.OnServerInvoke = GridManager.PlaceUnitFromInventory
	MoveUnitFunction.OnServerInvoke = GridManager.MoveUnit
	SwapUnitsFunction.OnServerInvoke = GridManager.SwapUnits
	StashUnitFunction.OnServerInvoke = GridManager.StashUnit
	
	-- Legacy Connections
	PlaceBrainrotFunction.OnServerInvoke = GridManager.PlaceUnitFromInventory
	RemoveBrainrotFunction.OnServerInvoke = GridManager.StashUnit
	
	GetGridFunction.OnServerInvoke = function(player)
		local gridData = getPlayerGrid(player)
		-- Serialize specific fields for client
		local serialized = {
			gridSize = gridData.gridSize,
			slots = {}
		}
		for k, v in pairs(gridData.slots) do
			if v.Unit or v.Tile then
				serialized.slots[k] = {
					Tile = v.Tile,
					UnitName = v.Unit and v.Unit.Name or nil
				}
			end
		end
		return serialized
	end
	
	print("✓ GridManager Initialized")
end

function GridManager.PlaceUnit(player, brainrot, slotIndex)
	local gridData = getPlayerGrid(player)
	local totalSlots = getTotalSlots(player)
	
	if slotIndex < 1 or slotIndex > totalSlots then return false, "Invalid slot" end
	
	local slot = getSlotData(gridData, slotIndex)
	if slot.Unit then return false, "Occupied" end
	
	-- Uniqueness check
	local unitType = brainrot:GetAttribute("UnitType") or brainrot.Name
	for _, slotData in pairs(gridData.slots) do
		if slotData.Unit then
			local otherType = slotData.Unit:GetAttribute("UnitType")
			if otherType == unitType then return false, "Already placed!" end
		end
	end
	
	slot.Unit = brainrot
	brainrot:SetAttribute("GridSlot", slotIndex)
	brainrot:SetAttribute("IsStored", false)
	
	repositionUnitOnTile(player, brainrot, slotIndex)
	
	for _, part in brainrot:GetDescendants() do
		if part:IsA("BasePart") then part.Anchored = true end
	end
	
	UnitPlacedEvent:FireClient(player, slotIndex, brainrot.Name)
	syncToProfile(player)
	return true
end

function GridManager.PlaceUnitFromInventory(player, unitName, arg2, arg3)
	-- Polymorphic Argument Handling to support Legacy and New Clients
	-- Legacy: (unitName, rarity, slotIndex)
	-- New: (unitName, slotIndex)
	
	local slotIndex
	if type(arg2) == "number" then
		slotIndex = arg2
	elseif type(arg3) == "number" then
		slotIndex = arg3
	else
		return false, "Invalid arguments"
	end

	-- Logic wrapper for Remote
	local BrainrotManager = _G.BrainrotManager
	local InventoryManager = _G.InventoryManager
	
	if not BrainrotManager or not InventoryManager then return false, "Server not ready" end
	
	-- 1. Ownership Check (Critical security fix)
	local unitData = InventoryManager.GetUnit(player, unitName)
	if not unitData then
		return false, "Unit not owned"
	end
	
	-- 2. Find Physical Unit
	-- We need to find the unit instance.
	local plot = findPlayerPlot(player)
	if not plot then return false, "No plot" end
	
	local brainrots = plot:FindFirstChild("Brainrots")
	local unit
	if brainrots then
		for _, child in brainrots:GetChildren() do
			if child:GetAttribute("UnitType") == unitName then
				unit = child
				break
			end
		end
	end
	
	-- 3. Recovery if unit missing physically but owned
	if not unit then
		-- Force Spawn (Fix: UpdateAllUnitStats does not spawn new models, SpawnBrainrot does)
		unit = BrainrotManager.SpawnBrainrot(player, unitName)
	end
	
	if unit then
		return GridManager.PlaceUnit(player, unit, slotIndex)
	end
	
	return false, "Unit model not found (Try rejoining)"
end

function GridManager.MoveUnit(player, fromSlot, toSlot)
	local gridData = getPlayerGrid(player)
	local fromSlotData = gridData.slots[fromSlot]
	if not fromSlotData or not fromSlotData.Unit then return false, "Empty source" end
	
	local toSlotData = getSlotData(gridData, toSlot)
	if toSlotData.Unit then return false, "Target occupied" end
	
	local brainrot = fromSlotData.Unit
	fromSlotData.Unit = nil
	toSlotData.Unit = brainrot
	brainrot:SetAttribute("GridSlot", toSlot)
	
	repositionUnitOnTile(player, brainrot, toSlot)
	GridUpdatedEvent:FireClient(player, toSlot, brainrot.Name, "moved")
	syncToProfile(player)
	
	return true
end

function GridManager.SwapUnits(player, slot1, slot2)
	local gridData = getPlayerGrid(player)
	local s1 = getSlotData(gridData, slot1)
	local s2 = getSlotData(gridData, slot2)
	
	if not s1.Unit and not s2.Unit then return false, "Nothing to swap" end
	
	local u1, u2 = s1.Unit, s2.Unit
	s1.Unit, s2.Unit = u2, u1
	
	if u1 then
		u1:SetAttribute("GridSlot", slot2)
		repositionUnitOnTile(player, u1, slot2)
	end
	if u2 then
		u2:SetAttribute("GridSlot", slot1)
		repositionUnitOnTile(player, u2, slot1)
	end
	
	syncToProfile(player)
	return true
end

function GridManager.StashUnit(player, slotIndex)
	local gridData = getPlayerGrid(player)
	local slot = getSlotData(gridData, slotIndex)
	
	if not slot.Unit then return false, "Empty slot" end
	
	local brainrot = slot.Unit
	slot.Unit = nil
	
	if _G.BrainrotManager then
		_G.BrainrotManager.StashBrainrot(player, brainrot)
	end
	
	syncToProfile(player)
	return true
end

function GridManager.GetGridPositions(player)
	-- Returns legacy grid format for other managers
	local gridData = getPlayerGrid(player)
	local export = {}
	for k, v in pairs(gridData.slots) do
		if v.Unit then
			-- Reconstruct the full unit data obj if needed
			export[tostring(k)] = {
				Unit = {
					unitType = v.Unit:GetAttribute("UnitType"),
					rarity = v.Unit:GetAttribute("Rarity"),
					level = v.Unit:GetAttribute("Level"),
					unitId = v.Unit:GetAttribute("UnitId")
				},
				Tile = v.Tile
			}
		elseif v.Tile then
			export[tostring(k)] = { Tile = v.Tile }
		end
	end
	return export
end

function GridManager.GetTileAtSlot(player, slotIndex)
	return getTileAtSlot(player, slotIndex)
end

function GridManager.PlaceTile(player, slotIndex, tileId)
	local tc = getTileConfig()
	if not tc.GetTile(tileId) then return false end
	local gridData = getPlayerGrid(player)
	local slot = getSlotData(gridData, slotIndex)
	
	-- Remove old
	if gridData.tileInstances[slotIndex] then
		gridData.tileInstances[slotIndex]:Destroy()
		gridData.tileInstances[slotIndex] = nil
	end
	
	slot.Tile = tileId
	local visual = createTileVisual(player, slotIndex, tileId)
	if visual then gridData.tileInstances[slotIndex] = visual end
	
	if slot.Unit then repositionUnitOnTile(player, slot.Unit, slotIndex) end
	
	syncToProfile(player)
	return true
end

return GridManager
