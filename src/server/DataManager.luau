--[[
	DataManager Server Module
	
	Handles saving and loading player data.
	Now acts as a bridge/adapter to the new DataService (ProfileService).
	
	CONVERTED TO MODULE SCRIPT
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))

-- New Data Service
local DataService = require(script.Parent.DataService)

-- Module Table
local DataManager = {}

-- Dependencies (Injected via Init or _G fallback for legacy)
local BrainrotManager
local InventoryManager

-- Configuration
local CONFIG = {
	DEFAULT_MONEY = 100,      -- Starting money for new players
}

--------------------------------------------------------------------------------
-- DATA GATHERING (LEGACY)
--------------------------------------------------------------------------------

local function getDefaultData()
	return {
		-- Core economy
		money = CONFIG.DEFAULT_MONEY,
		ownedUnits = {},              -- Legacy: kept for ShopManager compatibility
		unlockProgress = 5,           -- 5 units unlocked initially
		maxStorage = 500,             -- Default max storage
		purchasedTiers = 1,           -- Number of purchased tiers
		convenienceUpgrades = {},     -- Purchased convenience upgrades
		-- Brainrot placements (position restoration)
		brainrotPlacements = {},      -- Array of placed brainrots with positions/attributes
		-- Item production system
		itemStorage = {},             -- Items in plot storage
		backpack = {},                -- Items in player's backpack
		storageCapacity = 2000,       -- Current storage capacity
		selectedVehicle = "Sneakers", -- Currently selected transport vehicle
		vehicleCapacities = {},       -- Vehicle upgrade levels
		-- RPG Mechanics: Grid
		gridPositions = {},           -- Layered grid data
		discoveredSynergies = {},     -- Discovered synergy recipes
	}
end

local function gatherPlayerData(player: Player): any
	-- Resolve Global Dependencies if not injected
	if not BrainrotManager then BrainrotManager = _G.BrainrotManager end
	
	-- Get money from leaderstats
	local money = CONFIG.DEFAULT_MONEY
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local moneyValue = leaderstats:FindFirstChild("Money")
		if moneyValue then
			money = moneyValue.Value
		end
	end
	
	-- Get owned units and unlock progress from ShopManager
	local ownedUnits = {}
	local unlockProgress = 5
	
	if _G.ShopManager then
		if _G.ShopManager.GetUnlockProgress then
			unlockProgress = _G.ShopManager.GetUnlockProgress(player)
		end
		
		local ownedFolder = player:FindFirstChild("OwnedUnits")
		if ownedFolder then
			for _, countValue in ownedFolder:GetChildren() do
				if countValue:IsA("IntValue") and countValue.Value > 0 then
					ownedUnits[countValue.Name] = countValue.Value
				end
			end
		end
	end
	
	-- Get maxStorage from player's plot
	local maxStorage = 500
	if BrainrotManager and BrainrotManager.GetPlayerPlot then
		local plot = BrainrotManager.GetPlayerPlot(player)
		if plot then
			maxStorage = plot:GetAttribute("MaxStorage") or 500
		end
	end
	
	-- Get tier data from MapSystem
	local purchasedTiers = 1
	if _G.MapSystem and _G.MapSystem.GetPlayerTierSystem then
		local tierSystem = _G.MapSystem.GetPlayerTierSystem(player)
		if tierSystem then
			purchasedTiers = #tierSystem.Tiers
		end
	end
	
	-- Get convenience upgrades
	local convenienceUpgrades = {}
	if _G.ConvenienceUpgrades and _G.ConvenienceUpgrades.GetPlayerUpgrades then
		convenienceUpgrades = _G.ConvenienceUpgrades.GetPlayerUpgrades(player)
	end
	
	-- Get brainrot placements (for position restoration)
	local brainrotPlacements = {}
	if BrainrotManager and BrainrotManager.GetPlacementData then
		brainrotPlacements = BrainrotManager.GetPlacementData(player) or {}
	end
	
	-- Get item storage data
	local itemStorage = {}
	local backpack = {}
	local storageCapacity = 2000
	local selectedVehicle = "Sneakers"
	local vehicleCapacities = {}
	local gridPositions = {}
	local discoveredSynergies = {}
	
	if _G.ItemStorageManager then
		if _G.ItemStorageManager.GetStorageContents then
			itemStorage = _G.ItemStorageManager.GetStorageContents(player) or {}
		end
		if _G.ItemStorageManager.GetBackpackContents then
			backpack = _G.ItemStorageManager.GetBackpackContents(player) or {}
		end
		if _G.ItemStorageManager.GetStorageCapacity then
			storageCapacity = _G.ItemStorageManager.GetStorageCapacity(player) or 2000
		end
	end
	
	if _G.TransportManager then
		if _G.TransportManager.GetSelectedVehicle then
			selectedVehicle = _G.TransportManager.GetSelectedVehicle(player) or "Sneakers"
		end
		if _G.TransportManager.GetVehicleCapacities then
			vehicleCapacities = _G.TransportManager.GetVehicleCapacities(player) or {}
		end
	end
	
	if _G.GridManager then
		if _G.GridManager.GetGridPositions then
			gridPositions = _G.GridManager.GetGridPositions(player) or {}
		end
	end
	
	if _G.AdjacencySynergyManager then
		if _G.AdjacencySynergyManager.GetDiscoveredSynergies then
			discoveredSynergies = _G.AdjacencySynergyManager.GetDiscoveredSynergies(player) or {}
		end
	end
	
	return {
		money = money,
		lifetimeEarnings = 0, -- Will be populated by PrestigeManager
		unlockProgress = unlockProgress,
		purchasedTiers = purchasedTiers,
		convenienceUpgrades = convenienceUpgrades,
		GridPlacements = gridPositions,
		ItemStorage = itemStorage,
		Backpack = backpack,
		storageCapacity = storageCapacity,
		selectedVehicle = selectedVehicle,
		vehicleCapacities = vehicleCapacities,
		discoveredSynergies = discoveredSynergies,
	}
end

--------------------------------------------------------------------------------
-- DATA LOADING (LEGACY)
--------------------------------------------------------------------------------

local function applyLegacyData(player: Player, data: any)
	-- Resolve Global Dependencies if not injected
	if not BrainrotManager then BrainrotManager = _G.BrainrotManager end
	if not InventoryManager then InventoryManager = _G.InventoryManager end

	if not data then
		warn("DataManager: No data to apply for " .. player.Name)
		return
	end
	
	-- Create leaderstats
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
		
		local money = Instance.new("IntValue")
		money.Name = "Money"
		money.Value = data.money or CONFIG.DEFAULT_MONEY
		money.Parent = leaderstats
	else
		local money = leaderstats:FindFirstChild("Money")
		if money then
			money.Value = data.money or CONFIG.DEFAULT_MONEY
		end
	end
	
	-- Early restore convenience upgrades
	if data.convenienceUpgrades and next(data.convenienceUpgrades) ~= nil then
		if _G.ConvenienceUpgrades and _G.ConvenienceUpgrades.SetPlayerUpgrades then
			_G.ConvenienceUpgrades.SetPlayerUpgrades(player, data.convenienceUpgrades)
		end
	end
	
	-- Wait for ShopManager to initialize (usually fast, but lets NOT wait here to avoid blocking)
	-- We assume ShopManager will read the values we set in leaderstats/Allocated values
	
	-- Spawn logic is async
	task.spawn(function()
		task.wait(1) -- Give time for other systems to load
		
		-- Restore Grid / Brainrot Placements
		local gridData = data.GridPlacements or data.gridPositions
		
		if gridData and next(gridData) ~= nil and BrainrotManager and BrainrotManager.SpawnBrainrotAtSlot then
			for slotIndexStr, slotData in pairs(gridData) do
				local slotIndex = tonumber(slotIndexStr)
				if slotIndex and slotData.Unit then
					local unitInfo = slotData.Unit
					BrainrotManager.SpawnBrainrotAtSlot(
						player, 
						unitInfo.unitType, 
						slotIndex,
						unitInfo.rarity or "Normal",
						unitInfo.level or 1,
						unitInfo.unitId
					)
				end
				if slotData.Tile and _G.GridManager and _G.GridManager.PlaceTile then
					_G.GridManager.PlaceTile(player, slotIndex, slotData.Tile)
				end
			end
		end
		
		-- NOTE: Other restorations (Prestige, Artifacts) are handled by their own managers listeners
	end)
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function DataManager.Init()
	print("   DataManager (Module) - Initializing")
	
	if not BrainrotManager then BrainrotManager = _G.BrainrotManager end
	if not InventoryManager then InventoryManager = _G.InventoryManager end
	
	-- Register with DataService
	DataService.RegisterHandler("Legacy", {
		DefaultData = getDefaultData(),
		OnLoad = applyLegacyData,
		OnSave = gatherPlayerData
	})
	
	-- Init DataService (starts loading)
	DataService.Init()
	
	print("✓ DataManager Initialized")
end

-- Legacy API Support
function DataManager.SavePlayerData(player)
	return true
end

function DataManager.LoadPlayerData(player)
	return DataService.GetData(player) or getDefaultData()
end

function DataManager.GetCachedData(player)
	return DataService.GetData(player)
end

function DataManager.ResetPlayerData(player, keepPrestigeData)
	-- Pass through to DataService logic (simplified for module)
	local currentData = DataService.GetData(player)
	if not currentData then return end
	
	local newData = getDefaultData()
	
	if keepPrestigeData then
		local startingMoney = CONFIG.DEFAULT_MONEY
		if _G.PrestigeManager and _G.PrestigeManager.GetStartingMoneyBonus then
			startingMoney = startingMoney + _G.PrestigeManager.GetStartingMoneyBonus(player)
		end
		newData.money = startingMoney
	else
		DataService.SetComponentData(player, "Prestige", nil)
	end
	
	DataService.SetComponentData(player, "Inventory", {})
	DataService.SetComponentData(player, "Artifacts", {})
	
	-- Clear legacy keys
	local componentKeys = { Inventory = true, Prestige = true, Artifacts = true }
	for k, _ in pairs(currentData) do
		if not componentKeys[k] then
			currentData[k] = nil
		end
	end
	
	for k, v in pairs(newData) do
		currentData[k] = v
	end
	
	applyLegacyData(player, currentData)
	return currentData
end

return DataManager
