--[[
	DataManager Server Module
	
	Handles saving and loading player data.
	Acts as a bridge/adapter to the new DataService (ProfileService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataService = require(script.Parent.DataService)

-- Module Table
local DataManager = {}
local Services = {}

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
	
	if Services.ShopManager then
		if Services.ShopManager.GetUnlockProgress then
			unlockProgress = Services.ShopManager.GetUnlockProgress(player)
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
	if Services.MapSystem and Services.MapSystem.GetPlayerTierSystem then
		local tierSystem = Services.MapSystem.GetPlayerTierSystem(player)
		if tierSystem then
			purchasedTiers = #tierSystem.Tiers
		end
	end
	
	-- Get convenience upgrades
	local convenienceUpgrades = {}
	if Services.ConvenienceUpgradesManager and Services.ConvenienceUpgradesManager.GetPlayerUpgrades then
		convenienceUpgrades = Services.ConvenienceUpgradesManager.GetPlayerUpgrades(player)
	end
	
	-- Get item storage data
	local itemStorage = {}
	local backpack = {}
	local storageCapacity = 2000
	local selectedVehicle = "Sneakers"
	local vehicleCapacities = {}
	local gridPositions = {}
	local discoveredSynergies = {}
	
	if Services.ItemStorageManager then
		if Services.ItemStorageManager.GetStorageContents then
			itemStorage = Services.ItemStorageManager.GetStorageContents(player) or {}
		end
		if Services.ItemStorageManager.GetBackpackContents then
			backpack = Services.ItemStorageManager.GetBackpackContents(player) or {}
		end
		if Services.ItemStorageManager.GetStorageCapacity then
			storageCapacity = Services.ItemStorageManager.GetStorageCapacity(player) or 2000
		end
	end
	
	if Services.TransportManager then
		if Services.TransportManager.GetSelectedVehicle then
			selectedVehicle = Services.TransportManager.GetSelectedVehicle(player) or "Sneakers"
		end
		if Services.TransportManager.GetVehicleCapacities then
			vehicleCapacities = Services.TransportManager.GetVehicleCapacities(player) or {}
		end
	end
	
	if Services.GridManager then
		if Services.GridManager.GetGridPositions then
			gridPositions = Services.GridManager.GetGridPositions(player) or {}
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
	if data.convenienceUpgrades and next(data.convenienceUpgrades) ~= nil then
		if Services.ConvenienceUpgradesManager and Services.ConvenienceUpgradesManager.SetPlayerUpgrades then
			Services.ConvenienceUpgradesManager.SetPlayerUpgrades(player, data.convenienceUpgrades)
		end
	end
	
	task.spawn(function()
		task.wait(1)
		
		-- MIGRATION: Restore Inventory from Legacy ownedUnits
		if Services.InventoryManager then
			local currentInv = Services.InventoryManager.GetInventory(player)
			local isEmpty = true
			for _ in pairs(currentInv) do isEmpty = false; break end
			
			if isEmpty and data.ownedUnits then
				print("DataManager: Migrating legacy inventory for " .. player.Name)
				for unitName, count in pairs(data.ownedUnits) do
					if type(count) == "number" and count > 0 then
						Services.InventoryManager.AddUnit(player, unitName, "Normal", count)
					end
				end
			end
		end
		
		-- Restore Grid / Brainrot Placements
		local gridData = data.GridPlacements or data.gridPositions
		
		if gridData and next(gridData) ~= nil and Services.BrainrotManager and Services.BrainrotManager.SpawnBrainrotAtSlot then
			for slotIndexStr, slotData in pairs(gridData) do
				local slotIndex = tonumber(slotIndexStr)
				if slotIndex and slotData.Unit then
					local unitInfo = slotData.Unit
					Services.BrainrotManager.SpawnBrainrotAtSlot(
						player, 
						unitInfo.unitType, 
						slotIndex,
						unitInfo.rarity or "Normal",
						unitInfo.level or 1,
						unitInfo.unitId
					)
				end
				if slotData.Tile and Services.GridManager and Services.GridManager.PlaceTile then
					Services.GridManager.PlaceTile(player, slotIndex, slotData.Tile)
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
	local currentData = DataService.GetData(player)
	if not currentData then return end
	
	local newData = getDefaultData()
	
	if keepPrestigeData then
		local startingMoney = CONFIG.DEFAULT_MONEY
		if Services.PrestigeManager and Services.PrestigeManager.GetStartingMoneyBonus then
			startingMoney = startingMoney + Services.PrestigeManager.GetStartingMoneyBonus(player)
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
