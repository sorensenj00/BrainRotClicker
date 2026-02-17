--[[
	InventoryManager Server Module
	
	═══════════════════════════════════════════════════════════════════════════════
	                   PERMANENT COLLECTION ASSETS ONLY
	═══════════════════════════════════════════════════════════════════════════════
	
	PURPOSE:
	  The Single Source of Truth for player-OWNED Units (Brainrots) and their
	  metadata. These are PERMANENT assets that persist across sessions and
	  are saved to the player's DataStore profile.
	
	MANAGES:
	  • CollectionUnits  - Brainrots the player owns (with level, rarity, unitId)
	  • Unit Placement   - Whether a unit is "placed" on grid or "stored"
	
	DATA LIFECYCLE:
	  • Saved to Profile via DataService ("Inventory" component)
	  • Persists across sessions
	  • Never automatically consumed or sold
	
	INTEGRATION:
	  → GridManager       - For unit placement status
	  → BrainrotManager   - Listens to UnitChanged signal
	  → ArtifactManager   - Separate manager for Artifact collection
	
	═══════════════════════════════════════════════════════════════════════════════
	⚠️  DO NOT USE THIS FOR TRANSIENT TYCOON RESOURCES:
	    Produced items (resources waiting in silos) belong in ItemStorageManager,
	    which connects to ItemProductionManager → TransportManager supply chain.
	═══════════════════════════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- Type Imports
local Shared = ReplicatedStorage:WaitForChild("Shared")
local _ItemTypes = require(Shared:WaitForChild("ItemTypes")) -- For type reference (see BrainrotUnit)

-- Strict Type Definitions for BrainrotUnits (permanent collection assets)
-- See ItemTypes.luau for full type: BrainrotUnit
export type UnitData = {
	level: number,
	rarity: string,
	unitId: string,
}

-- Lazy Config
local RarityConfig

local function getRarityConfig()
	if not RarityConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		RarityConfig = require(Shared:WaitForChild("RarityConfig"))
	end
	return RarityConfig
end

-- DataService (Lazy Loaded via Services)
local DataService -- Will be set from Services.DataService

-- Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local InventoryChangedEvent = RemoteEvents:FindFirstChild("InventoryChanged") or Instance.new("RemoteEvent")
InventoryChangedEvent.Name = "InventoryChanged"
InventoryChangedEvent.Parent = RemoteEvents

-- Component key for DataService
local COMPONENT_KEY = "Inventory"

--------------------------------------------------------------------------------
-- MODULE DEFINITION
--------------------------------------------------------------------------------

local InventoryManager = {}
local Services = {} -- Service Container

-- Getter for DataService (to avoid circular require)
local function getDataService()
	if not DataService then
		DataService = rawget(Services, "DataService")
	end
	return DataService
end

-- Signal for server-side listeners (BrainrotManager)
local UnitChangedSignal = Instance.new("BindableEvent")
InventoryManager.UnitChanged = UnitChangedSignal.Event

-- Internal helper
local function getInventoryData(player: Player): {[string]: any}?
	local ds = getDataService()
	if not ds then return nil end
	
	local data = ds.GetComponentData(player, COMPONENT_KEY)
	if data then
		return data
	end
	
	-- Initialize if not exists and profile is loaded
	if ds.IsLoaded(player) then
		ds.SetComponentData(player, COMPONENT_KEY, {})
		return ds.GetComponentData(player, COMPONENT_KEY)
	end
	
	return nil
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function InventoryManager.Init(services)
	print("   InventoryManager (Module) - Initializing")
	Services = services or {}
	
	-- Create canonical GetInventory RemoteFunction
	local GetInventoryRemote = RemoteEvents:FindFirstChild("GetInventory") or Instance.new("RemoteFunction")
	GetInventoryRemote.Name = "GetInventory"
	GetInventoryRemote.Parent = RemoteEvents
	
	-- Register with DataService
	local ds = getDataService()
	if ds then
		ds.RegisterHandler(COMPONENT_KEY, {
			DefaultData = {},
			OnLoad = function(player: Player, data: any)
				local unitCount = 0
				if data and type(data) == "table" then
					for _ in pairs(data) do unitCount += 1 end
				end
				print(string.format("InventoryManager: Loaded %d units for %s", unitCount, player.Name))
				
				task.defer(function()
					UnitChangedSignal:Fire(player, nil, nil)
				end)
			end,
			OnSave = function(player: Player, data: any)
				return data
			end
		})
	else
		warn("InventoryManager: DataService not available during Init")
	end
	
	-- Canonical GetInventory handler
	GetInventoryRemote.OnServerInvoke = function(player)
		local inventory = { units = {} }
		local invData = getInventoryData(player) or {}
		
		-- Get GridManager to check placement status
		local GridManager = rawget(Services, "GridManager")
		local gridPositions = {}
		if GridManager and GridManager.GetGridPositions then
			gridPositions = GridManager.GetGridPositions(player) or {}
		end
		
		-- Build placed units set
		local placedUnits = {}
		for _, slotData in pairs(gridPositions) do
			if slotData.Unit and slotData.Unit.unitType then
				placedUnits[slotData.Unit.unitType] = true
			end
		end
		
		-- Build response
		for unitName, unitData in pairs(invData) do
			if unitData.level and unitData.level > 0 then
				inventory.units[unitName] = {
					level = unitData.level or 1,
					rarity = unitData.rarity or "Normal",
					status = placedUnits[unitName] and "placed" or "stored"
				}
			end
		end
		
		return inventory
	end
	
	-- Create GetUnifiedInventory RemoteFunction (for BackpackHUD)
	local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
	RemoteFunctions.Name = "RemoteFunctions"
	RemoteFunctions.Parent = ReplicatedStorage
	
	local GetUnifiedInventoryRemote = RemoteFunctions:FindFirstChild("GetUnifiedInventory") or Instance.new("RemoteFunction")
	GetUnifiedInventoryRemote.Name = "GetUnifiedInventory"
	GetUnifiedInventoryRemote.Parent = RemoteFunctions
	
	-- Unified inventory handler (returns units + artifacts in format BackpackHUD expects)
	GetUnifiedInventoryRemote.OnServerInvoke = function(player)
		local items = {}
		local invData = getInventoryData(player) or {}
		
		-- Get GridManager to check placement status
		local GridManager = rawget(Services, "GridManager")
		local gridPositions = {}
		if GridManager and GridManager.GetGridPositions then
			gridPositions = GridManager.GetGridPositions(player) or {}
		end
		
		-- Build placed units set
		local placedUnits = {}
		for _, slotData in pairs(gridPositions) do
			if slotData.Unit and slotData.Unit.unitType then
				placedUnits[slotData.Unit.unitType] = true
			end
		end
		
		-- Add units to items list
		for unitName, unitData in pairs(invData) do
			if unitData.level and unitData.level > 0 then
				table.insert(items, {
					Type = "Unit",
					UUID = unitName, -- For units, UUID is the unit name
					Name = unitName,
					Rarity = unitData.rarity or "Normal",
					IsPlaced = placedUnits[unitName] or false,
					Data = {
						Level = unitData.level or 1,
						Rarity = unitData.rarity or "Normal",
					}
				})
			end
		end
		
		-- Artifacts
		local ArtifactManager = rawget(Services, "ArtifactManager")
		if ArtifactManager and ArtifactManager.GetArtifacts then
			local artifactData = ArtifactManager.GetArtifacts(player)
			-- GetArtifacts returns {all = {...}, unequipped = {...}}
			if artifactData and artifactData.all then
				for guid, artifact in pairs(artifactData.all) do
					table.insert(items, {
						Type = "Artifact",
						UUID = guid,
						Name = artifact.Name,
						Rarity = artifact.Rarity,
						Icon = artifact.BaseIcon, -- Map BaseIcon to Icon for UI
						IsPlaced = false,
						Data = artifact
					})
				end
			end
		end
		
		return items
	end
	
	-- Backwards compatibility hooks
	Players.PlayerAdded:Connect(InventoryManager.InitPlayer)
	
	print("✓ InventoryManager Initialized")
end

function InventoryManager.InitPlayer(player: Player)
	-- No-op: DataService handles initialization
end

function InventoryManager.SetInventory(player: Player, data: {[string]: any})
	DataService.SetComponentData(player, COMPONENT_KEY, data or {})
	UnitChangedSignal:Fire(player, nil, nil)
end

function InventoryManager.GetInventory(player: Player): {[string]: any}
	return getInventoryData(player) or {}
end

function InventoryManager.GetUnit(player: Player, unitName: string): UnitData?
	local inventory = getInventoryData(player)
	return inventory and inventory[unitName]
end

function InventoryManager.GetUnitLevel(player: Player, unitName: string): number
	local unitData = InventoryManager.GetUnit(player, unitName)
	return unitData and unitData.level or 0
end

--[[
	AddUnit: Adds or upgrades a BrainrotUnit in the player's permanent inventory.
	
	@param player Player - The player to add the unit to
	@param unitName string - The unit model name (e.g. "Skibidi_Toilet")
	@param rarity string? - Optional rarity override ("Normal", "Rare", etc.)
	@param level number? - Optional level override (defaults to increment)
	@return UnitData? - The new/updated unit data, or nil if failed
	
	⚠️ WARNING: This is for BrainrotUnits ONLY (permanent collection assets).
	   Do NOT use this for FactoryItems (transient production resources).
	   FactoryItems should go to ItemStorageManager.AddToStorage() instead.
]]
function InventoryManager.AddUnit(player: Player, unitName: string, rarity: string?, level: number?): UnitData?
	-- GUARD: Reject if this looks like a FactoryItem (has itemId/count pattern)
	-- This catches accidental misuse of the wrong manager
	if type(unitName) == "table" then
		warn("InventoryManager.AddUnit: Received table instead of unitName string!")
		warn("  If you're trying to add a FactoryItem, use ItemStorageManager.AddToStorage() instead.")
		return nil
	end
	
	local inventory = getInventoryData(player)
	if not inventory then
		warn("InventoryManager: Profile not loaded for " .. player.Name)
		return nil
	end

	local currentData = inventory[unitName]

	local newLevel = level
	local newRarity = rarity or "Normal"

	if currentData then
		if not newLevel then
			newLevel = currentData.level + 1
		end
		
		if rarity then
			local rc = getRarityConfig()
			local currentRank = rc.GetRarityValue(currentData.rarity)
			local newRank = rc.GetRarityValue(rarity)

			if newRank > currentRank then
				newRarity = rarity
			else
				newRarity = currentData.rarity
			end
		else
			newRarity = currentData.rarity
		end
	else
		if not newLevel then
			newLevel = 1
		end
	end

	local newData: UnitData = {
		level = newLevel,
		rarity = newRarity,
		unitId = currentData and currentData.unitId or HttpService:GenerateGUID(false)
	}

	inventory[unitName] = newData

	UnitChangedSignal:Fire(player, unitName, newData)
	InventoryChangedEvent:FireClient(player, unitName, newData)

	return newData
end

return InventoryManager
