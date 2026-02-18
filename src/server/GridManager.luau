--[[
	GridManager Server Module
	
	Manages grid-based brainrot placement on player plots.
]]

-- Services
local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _CollectionService = game:GetService("CollectionService")

-- Shared configs
-- Shared configs (Lazy Loaded)
local ItemConfig

local function getItemConfig()
	if not ItemConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		ItemConfig = require(Shared:WaitForChild("ItemConfig"))
	end
	return ItemConfig
end

-- DataService (Lazy Loaded via Services)
local DataService -- Will be set from Services.DataService

-- Constants
local _BRAINROT_TAG = "Brainrot"
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
	TILE_THICKNESS = 1,
}

-- Remote Objects
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

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

local SetUnitModeFunction = RemoteFunctions:FindFirstChild("SetUnitMode") or Instance.new("RemoteFunction")
SetUnitModeFunction.Name = "SetUnitMode"
SetUnitModeFunction.Parent = RemoteFunctions

local ModeChangedEvent = RemoteEvents:FindFirstChild("ModeChanged") or Instance.new("RemoteEvent")
ModeChangedEvent.Name = "ModeChanged"
ModeChangedEvent.Parent = RemoteEvents

-- Module Table
local GridManager = {}
local Services = {}

-- Getter for DataService (to avoid circular require)
local function getDataService()
	if not DataService then
		DataService = rawget(Services, "DataService")
	end
	return DataService
end

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
		}
	end
	return PlayerGrids[player.UserId]
end

local function getSlotData(gridData, slotIndex)
	if not gridData.slots[slotIndex] then
		gridData.slots[slotIndex] = { Unit = nil, CurrentMode = 1 }
	end
	-- Migration: ensure CurrentMode exists for legacy data
	if gridData.slots[slotIndex].CurrentMode == nil then
		gridData.slots[slotIndex].CurrentMode = 1
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

local function _getFloorTopY(player)
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

local function repositionUnitOnTile(player, brainrot, slotIndex)
	if not brainrot then 
		print("[DEBUG] repositionUnitOnTile: brainrot is nil!")
		return 
	end
	local baseCFrame = getSlotCFrame(player, slotIndex)
	print(string.format("[DEBUG] repositionUnitOnTile: Moving %s to slot %d at Y=%.1f", 
		brainrot.Name, slotIndex, baseCFrame.Position.Y))
	brainrot:PivotTo(baseCFrame)
end

local function syncToProfile(player)
	local ds = getDataService()
	if ds and ds.IsLoaded(player) then
		local gridData = getPlayerGrid(player)
		local positions = {}
		for idx, slotInfo in pairs(gridData.slots) do
			if slotInfo.Unit then
				local entry = { Unit = nil, CurrentMode = slotInfo.CurrentMode or 1 }
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
				positions[tostring(idx)] = entry
			end
		end
		ds.SetComponentData(player, "GridPlacements", positions)
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function GridManager.Init(services)
	print("   GridManager (Module) - Initializing")
	Services = services or {}
	
	-- Register Data Handler
	local ds = getDataService()
	if not ds then
		warn("GridManager: DataService not available during Init")
		return
	end
	
	ds.RegisterHandler("GridPlacements", {
		DefaultData = {},
		OnLoad = function(player, data)
			-- Restore Grid
			if not data then
				local PlayerLifecycleManager = rawget(Services, "PlayerLifecycleManager")
				if PlayerLifecycleManager then
					PlayerLifecycleManager.SetGridRestored(player)
				end
				return
			end
			
			task.spawn(function()
				local BrainrotManager = rawget(Services, "BrainrotManager")
				local MapSystem = rawget(Services, "MapSystem")
				
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
					end
				end
				
				if not plot then
					warn("GridManager: Could not find plot for " .. player.Name .. " - Grid restoration failed")
					return
				end
				
				-- Proceed with restoration
				local gridData = getPlayerGrid(player)
				for slotIndexStr, slotData in pairs(data) do
					local slotIndex = tonumber(slotIndexStr)
					if slotIndex then
						-- Restore CurrentMode (default to 1 for migration)
						local slot = getSlotData(gridData, slotIndex)
						slot.CurrentMode = slotData.CurrentMode or 1
						
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
				
				local PlayerLifecycleManager = rawget(Services, "PlayerLifecycleManager")
				if PlayerLifecycleManager then
					PlayerLifecycleManager.SetGridRestored(player)
				end
			end)
		end,
		OnSave = function(player, data)
			-- Return current state to ensure it's saved correctly
			return GridManager.GetGridPositions(player)
		end
	})
	
	-- Connect Remotes
	PlaceUnitFunction.OnServerInvoke = GridManager.PlaceUnitFromInventory
	MoveUnitFunction.OnServerInvoke = GridManager.MoveUnit
	SwapUnitsFunction.OnServerInvoke = GridManager.SwapUnits
	StashUnitFunction.OnServerInvoke = GridManager.StashUnit
	SetUnitModeFunction.OnServerInvoke = GridManager.SetUnitMode
	
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
			if v.Unit then
				serialized.slots[k] = {
					UnitName = v.Unit.Name
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
	-- Polymorphic Argument Handling
	local slotIndex
	if type(arg2) == "number" then
		slotIndex = arg2
	elseif type(arg3) == "number" then
		slotIndex = arg3
	else
		print("[DEBUG] PlaceUnitFromInventory: Invalid arguments", unitName, arg2, arg3)
		return false, "Invalid arguments"
	end

	print(string.format("[DEBUG] PlaceUnitFromInventory: %s -> slot %d", unitName, slotIndex))

	-- Logic wrapper for Remote
	local BrainrotManager = rawget(Services, "BrainrotManager")
	local InventoryManager = rawget(Services, "InventoryManager")
	
	if not BrainrotManager or not InventoryManager then return false, "Server not ready" end
	
	-- 1. Ownership Check
	local unitData = InventoryManager.GetUnit(player, unitName)
	if not unitData then
		print("[DEBUG] PlaceUnitFromInventory: Unit not owned -", unitName)
		return false, "Unit not owned"
	end
	print(string.format("[DEBUG] PlaceUnitFromInventory: Ownership verified (level=%d)", unitData.level or 0))
	
	-- 2. Find Physical Unit
	local plot = findPlayerPlot(player)
	if not plot then return false, "No plot" end
	
	local brainrots = plot:FindFirstChild("Brainrots")
	local unit
	if brainrots then
		for _, child in brainrots:GetChildren() do
			if child:GetAttribute("UnitType") == unitName then
				unit = child
				print(string.format("[DEBUG] PlaceUnitFromInventory: Found existing model at Y=%.1f", child:GetPivot().Position.Y))
				break
			end
		end
	end
	
	-- 3. Recovery if unit missing physically but owned
	if not unit then
		-- Force Spawn using SpawnForGrid (avoids duplicate AddUnit call)
		print("[DEBUG] PlaceUnitFromInventory: No model found, spawning new visual...")
		
		-- Construct data from inventory
		local spawnData = {
			level = unitData.level or 1,
			rarity = unitData.rarity or "Normal",
			unitId = unitData.unitId -- Vital to keep same ID
		}
		
		unit = BrainrotManager.SpawnForGrid(player, unitName, spawnData)
		if unit then
			print(string.format("[DEBUG] PlaceUnitFromInventory: Spawned new model at Y=%.1f", unit:GetPivot().Position.Y))
		else
			print("[DEBUG] PlaceUnitFromInventory: Spawn failed!")
		end
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
	
	local BrainrotManager = rawget(Services, "BrainrotManager")
	if BrainrotManager then
		BrainrotManager.StashBrainrot(player, brainrot)
	end
	
	syncToProfile(player)
	return true
end

function GridManager.GetGridPositions(player)
	-- Returns grid format for other managers (V3: includes CurrentMode)
	local gridData = getPlayerGrid(player)
	local export = {}
	for k, v in pairs(gridData.slots) do
		if v.Unit then
			export[tostring(k)] = {
				Unit = {
					unitType = v.Unit:GetAttribute("UnitType"),
					rarity = v.Unit:GetAttribute("Rarity"),
					level = v.Unit:GetAttribute("Level"),
					unitId = v.Unit:GetAttribute("UnitId")
				},
				CurrentMode = v.CurrentMode or 1,
			}
		end
	end
	return export
end

function GridManager.GetClusterSlots(slotIndex)
	local clusterIdx = math.floor((slotIndex - 1) / 4)
	local baseSlot = clusterIdx * 4 + 1
	return { baseSlot, baseSlot + 1, baseSlot + 2, baseSlot + 3 }
end

function GridManager.SetUnitMode(player, slotIndex, modeIndex)
	if type(slotIndex) ~= "number" or type(modeIndex) ~= "number" then
		return false, "Invalid arguments"
	end
	
	local gridData = getPlayerGrid(player)
	local slot = getSlotData(gridData, slotIndex)
	
	if not slot.Unit then return false, "No unit in slot" end
	
	local unitType = slot.Unit:GetAttribute("UnitType")
	if not unitType then return false, "Invalid unit" end
	
	-- Validate mode exists and is unlocked
	local ic = getItemConfig()
	local modes = ic.BrainrotModes[unitType]
	if not modes then return false, "No modes for this unit" end
	
	if modeIndex < 1 or modeIndex > #modes then return false, "Invalid mode index" end
	
	local targetMode = modes[modeIndex]
	local unitLevel = slot.Unit:GetAttribute("Level") or 1
	if unitLevel < targetMode.unlockLevel then
		return false, string.format("Requires level %d (current: %d)", targetMode.unlockLevel, unitLevel)
	end
	
	-- Apply mode
	slot.CurrentMode = modeIndex
	slot.Unit:SetAttribute("CurrentMode", modeIndex)
	
	-- Notify client for UI updates (overhead icon, etc.)
	ModeChangedEvent:FireClient(player, slotIndex, modeIndex, targetMode.itemId)
	
	syncToProfile(player)
	return true
end

function GridManager.ClearGrid(player)
	local gridData = PlayerGrids[player.UserId]
	if not gridData then return end
	
	gridData.slots = {}
	
	-- Ensure the grid is cleared in DataService
	syncToProfile(player)
	
	-- Notify client
	GridUpdatedEvent:FireClient(player, 0, "", "cleared")
end

return GridManager
