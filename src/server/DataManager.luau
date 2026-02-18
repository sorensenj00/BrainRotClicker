--[[
	DataManager Server Module
	
	Handles saving and loading player data.
	Acts as a bridge/adapter to the new DataService (ProfileService).
]]

local _ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataService -- Will be set from Services.DataService

-- Module Table
local DataManager = {}
local Services = {}

-- Getter for DataService (to avoid circular require)
local function getDataService()
	if not DataService then
		DataService = rawget(Services, "DataService")
	end
	return DataService
end

-- Configuration
local CONFIG = {
	DEFAULT_MONEY = 100,
}

--------------------------------------------------------------------------------
-- DATA GATHERING (LEGACY)
--------------------------------------------------------------------------------

local function getDefaultData()
	return {
		money = CONFIG.DEFAULT_MONEY,
		ownedUnits = {},
		unlockProgress = 5,
		purchasedTiers = 1,
		convenienceUpgrades = {},
		brainrotPlacements = {},
		itemStorage = {},
		backpack = {},
		storageCapacity = 2000,
		selectedVehicle = "Sneakers",
		vehicleCapacities = {},
		gridPositions = {},
		discoveredSynergies = {},
	}
end

local function gatherPlayerData(player: Player): any
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
	
	local ShopManager = rawget(Services, "ShopManager")
	if ShopManager then
		if ShopManager.GetUnlockProgress then
			unlockProgress = ShopManager.GetUnlockProgress(player)
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
	
	-- Get tier data from MapSystem
	local purchasedTiers = 1
	local MapSystem = rawget(Services, "MapSystem")
	if MapSystem and MapSystem.GetPlayerTierSystem then
		local tierSystem = MapSystem.GetPlayerTierSystem(player)
		if tierSystem then
			purchasedTiers = #tierSystem.Tiers
		end
	end
	
	-- Get convenience upgrades
	local convenienceUpgrades = {}
	local ConvenienceUpgradesManager = rawget(Services, "ConvenienceUpgradesManager")
	if ConvenienceUpgradesManager and ConvenienceUpgradesManager.GetPlayerUpgrades then
		convenienceUpgrades = ConvenienceUpgradesManager.GetPlayerUpgrades(player)
	end
	
	-- Get item storage data
	local itemStorage = {}
	local backpack = {}
	local storageCapacity = 2000
	local selectedVehicle = "Sneakers"
	local vehicleCapacities = {}
	local gridPositions = {}
	local discoveredSynergies = {}
	
	local ItemStorageManager = rawget(Services, "ItemStorageManager")
	if ItemStorageManager then
		if ItemStorageManager.GetStorageContents then
			itemStorage = ItemStorageManager.GetStorageContents(player) or {}
		end
		if ItemStorageManager.GetBackpackContents then
			backpack = ItemStorageManager.GetBackpackContents(player) or {}
		end
		if ItemStorageManager.GetStorageCapacity then
			storageCapacity = ItemStorageManager.GetStorageCapacity(player) or 2000
		end
	end
	
	local TransportManager = rawget(Services, "TransportManager")
	if TransportManager then
		if TransportManager.GetSelectedVehicle then
			selectedVehicle = TransportManager.GetSelectedVehicle(player) or "Sneakers"
		end
		if TransportManager.GetVehicleCapacities then
			vehicleCapacities = TransportManager.GetVehicleCapacities(player) or {}
		end
	end
	
	local GridManager = rawget(Services, "GridManager")
	if GridManager then
		if GridManager.GetGridPositions then
			gridPositions = GridManager.GetGridPositions(player) or {}
		end
	end
	
	-- AdjacencySynergyManager not in core services yet, skipping or need check
	-- For simplicity, omitting optional synergy data gathering if manager is not critical
	
	return {
		money = money,
		lifetimeEarnings = 0,
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
	local ConvenienceUpgradesManager = rawget(Services, "ConvenienceUpgradesManager")
	if data.convenienceUpgrades and next(data.convenienceUpgrades) ~= nil then
		if ConvenienceUpgradesManager and ConvenienceUpgradesManager.SetPlayerUpgrades then
			ConvenienceUpgradesManager.SetPlayerUpgrades(player, data.convenienceUpgrades)
		end
	end
	
	task.spawn(function()
		task.wait(1)
		
		-- MIGRATION: Restore Inventory from Legacy ownedUnits
		local InventoryManager = rawget(Services, "InventoryManager")
		if InventoryManager then
			local currentInv = InventoryManager.GetInventory(player)
			local isEmpty = true
			for _ in pairs(currentInv) do isEmpty = false; break end
			
			if isEmpty and data.ownedUnits then
				print("DataManager: Migrating legacy inventory for " .. player.Name)
				for unitName, count in pairs(data.ownedUnits) do
					if type(count) == "number" and count > 0 then
						InventoryManager.AddUnit(player, unitName, "Normal", count)
					end
				end
			end
		end
		
		-- Restore Grid / Brainrot Placements
		local gridData = data.GridPlacements or data.gridPositions
		local BrainrotManager = rawget(Services, "BrainrotManager")
		
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
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function DataManager.Init(services)
	print("   DataManager (Module) - Initializing")
	Services = services or {}
	
	local ds = getDataService()
	if not ds then
		warn("DataManager: DataService not available during Init")
		return
	end
	
	-- Register with DataService
	ds.RegisterHandler("Legacy", {
		DefaultData = getDefaultData(),
		OnLoad = applyLegacyData,
		OnSave = gatherPlayerData
	})
	
	-- Init DataService (starts loading)
	-- ds.Init()  <-- REMOVED: ServerMain already initializes DataService.

	
	print("✓ DataManager Initialized")
end

-- Legacy API Support
function DataManager.SavePlayerData(player)
	return true
end

function DataManager.LoadPlayerData(player)
	local ds = getDataService()
	return (ds and ds.GetData(player)) or getDefaultData()
end

function DataManager.GetCachedData(player)
	local ds = getDataService()
	return ds and ds.GetData(player)
end

function DataManager.ResetPlayerData(player, keepPrestigeData)
	local ds = getDataService()
	if not ds then return end
	
	local currentData = ds.GetData(player)
	if not currentData then return end
	
	local newData = getDefaultData()
	
	if keepPrestigeData then
		local startingMoney = CONFIG.DEFAULT_MONEY
		local PrestigeManager = rawget(Services, "PrestigeManager")
		if PrestigeManager and PrestigeManager.GetStartingMoneyBonus then
			startingMoney = startingMoney + PrestigeManager.GetStartingMoneyBonus(player)
		end
		newData.money = startingMoney
	else
		ds.SetComponentData(player, "Prestige", nil)
	end
	
	ds.SetComponentData(player, "Inventory", {})
	ds.SetComponentData(player, "Artifacts", {})
	
	-- Reset Item Storage (Silos and Backpack)
	local ItemStorageManager = rawget(Services, "ItemStorageManager")
	if ItemStorageManager and ItemStorageManager.ResetPlayerStorage then
		ItemStorageManager.ResetPlayerStorage(player)
	else
		-- Fallback if manager not available
		ds.SetComponentData(player, "ItemStorage", {})
		ds.SetComponentData(player, "Backpack", {})
	end

	-- Reset Grid (Units and Tiles)
	local GridManager = rawget(Services, "GridManager")
	local BrainrotManager = rawget(Services, "BrainrotManager")
	
	if GridManager and GridManager.ClearGrid then
		GridManager.ClearGrid(player)
	else
		ds.SetComponentData(player, "GridPlacements", {})
	end
	
	if BrainrotManager and BrainrotManager.ClearAllUnits then
		BrainrotManager.ClearAllUnits(player)
	end
	
	-- Clear legacy keys (those managed by the Legacy/Root adapter)
	local componentKeys = { 
		Inventory = true, 
		Prestige = true, 
		Artifacts = true, 
		ItemStorage = true, 
		Backpack = true,
		GridPlacements = true
	}
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
