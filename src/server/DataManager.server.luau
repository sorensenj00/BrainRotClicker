--[[
	DataManager Server Script
	
	Handles saving and loading player data using DataStoreService.
	
	Saves:
	- Money (from leaderstats)
	- Owned unit counts (from ShopManager)
	- Unlock progress (from ShopManager)
	
	Data is saved on:
	- Player leaving
	- Auto-save every 5 minutes
	- Game shutdown (BindToClose)
]]

-- Services
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for shared modules
local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopConfig"))

-- DataStore
local PlayerDataStore = DataStoreService:GetDataStore("BrainRotClickerData_v1")

-- Configuration
local CONFIG = {
	AUTO_SAVE_INTERVAL = 300, -- 5 minutes
	DEFAULT_MONEY = 100,      -- Starting money for new players
	RETRY_ATTEMPTS = 3,
	RETRY_DELAY = 1,
}

-- Cached player data (to avoid reading twice)
local PlayerDataCache: {[Player]: {money: number, ownedUnits: {[string]: number}, unlockProgress: number, maxStorage: number}} = {}

-- Track if data has been loaded
local DataLoaded: {[Player]: boolean} = {}

-- Wait for BrainrotManager API (loaded via _G)
local function waitForBrainrotManager()
	local attempts = 0
	while not _G.BrainrotManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.BrainrotManager
end

--------------------------------------------------------------------------------
-- DATA STRUCTURE
--------------------------------------------------------------------------------

--[[
	Default data structure for new players
]]
local function getDefaultData()
	return {
		money = CONFIG.DEFAULT_MONEY,
		ownedUnits = {},
		unlockProgress = 5, -- 5 units unlocked initially (matches ShopConfig.INITIAL_UNLOCKED)
		maxStorage = 500,   -- Default max storage (legacy)
		purchasedTiers = 1, -- Number of purchased tiers (starts at 1)
		convenienceUpgrades = {}, -- Purchased convenience upgrades
		-- Prestige system data (never reset on prestige)
		lifetimeEarnings = 0,     -- Total money ever earned
		totalMeatballs = 0,       -- Lifetime accumulated meatballs
		spentMeatballs = 0,       -- Meatballs spent in shop
		prestigeCount = 0,        -- Number of times prestiged
		meatballUpgrades = {},    -- Purchased permanent upgrades
		-- Brainrot persistence data
		brainrotInventory = {},   -- Full inventory with rarities: {[unitName]: {[rarity]: {total, active}}}
		brainrotPlacements = {},  -- Array of placed brainrots with positions/attributes
		-- Item production system data (Sell a Brainrot)
		itemStorage = {},         -- Items in plot storage: {[itemId]: count}
		backpack = {},            -- Items in player's backpack: {[itemId]: count}
		storageCapacity = 2000,   -- Current storage capacity (upgradeable)
		selectedVehicle = "Sneakers", -- Currently selected transport vehicle
		vehicleCapacities = {},   -- Vehicle upgrade levels: {[vehicleId]: capacity}
		gridPositions = {},       -- Brainrot grid positions: {[slotIndex]: brainrotId}
		discoveredSynergies = {}, -- Discovered synergy recipes: {[synergyId]: true}
	}
end

--------------------------------------------------------------------------------
-- SAVE / LOAD FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Loads player data from DataStore.
	Includes maxStorage for storage upgrade persistence.
	Returns the data or default data if not found.
]]
local function loadPlayerData(player: Player): {money: number, ownedUnits: {[string]: number}, unlockProgress: number}
	local userId = player.UserId
	local key = "Player_" .. userId
	
	local success, result
	for attempt = 1, CONFIG.RETRY_ATTEMPTS do
		success, result = pcall(function()
			return PlayerDataStore:GetAsync(key)
		end)
		
		if success then
			break
		else
			warn(string.format("DataManager: Load attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
			if attempt < CONFIG.RETRY_ATTEMPTS then
				task.wait(CONFIG.RETRY_DELAY)
			end
		end
	end
	
	if success and result then
		-- Ensure maxStorage exists (for older saves)
		if not result.maxStorage then
			result.maxStorage = 500
		end
		-- Ensure convenienceUpgrades exists (for older saves)
		if not result.convenienceUpgrades then
			result.convenienceUpgrades = {}
		end
		-- Ensure prestige data exists (for older saves)
		if not result.lifetimeEarnings then
			result.lifetimeEarnings = 0
		end
		if not result.totalMeatballs then
			result.totalMeatballs = 0
		end
		if not result.spentMeatballs then
			result.spentMeatballs = 0
		end
		if not result.prestigeCount then
			result.prestigeCount = 0
		end
		if not result.meatballUpgrades then
			result.meatballUpgrades = {}
		end
		-- Ensure tier and brainrot persistence data exists (for older saves)
		if not result.purchasedTiers then
			result.purchasedTiers = 1
		end
		if not result.brainrotInventory then
			result.brainrotInventory = {}
		end
		if not result.brainrotPlacements then
			result.brainrotPlacements = {}
		end
		-- Ensure item system data exists (for older saves)
		if not result.itemStorage then
			result.itemStorage = {}
		end
		if not result.backpack then
			result.backpack = {}
		end
		if not result.storageCapacity then
			result.storageCapacity = 2000
		end
		if not result.selectedVehicle then
			result.selectedVehicle = "Sneakers"
		end
		if not result.vehicleCapacities then
			result.vehicleCapacities = {}
		end
		if not result.gridPositions then
			result.gridPositions = {}
		end
		if not result.discoveredSynergies then
			result.discoveredSynergies = {}
		end
		print(string.format("✓ Loaded data for %s: $%d, %d units unlocked, %d max storage, %d meatballs, %d tiers", 
			player.Name, result.money or 0, result.unlockProgress or 5, result.maxStorage, result.totalMeatballs, result.purchasedTiers))
		return result
	else
		print(string.format("✓ No saved data for %s, using defaults", player.Name))
		return getDefaultData()
	end
end

--[[
	Saves player data to DataStore.
]]
local function savePlayerData(player: Player): boolean
	local userId = player.UserId
	local key = "Player_" .. userId
	
	-- Get current data from game state
	local data = gatherPlayerData(player)
	if not data then
		warn("DataManager: No data to save for " .. player.Name)
		return false
	end
	
	local success, result
	for attempt = 1, CONFIG.RETRY_ATTEMPTS do
		success, result = pcall(function()
			PlayerDataStore:SetAsync(key, data)
		end)
		
		if success then
			break
		else
			warn(string.format("DataManager: Save attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
			if attempt < CONFIG.RETRY_ATTEMPTS then
				task.wait(CONFIG.RETRY_DELAY)
			end
		end
	end
	
	if success then
		print(string.format("✓ Saved data for %s: $%d, %d units unlocked, %d max storage", player.Name, data.money, data.unlockProgress, data.maxStorage or 500))
		return true
	else
		warn(string.format("✗ Failed to save data for %s after %d attempts", player.Name, CONFIG.RETRY_ATTEMPTS))
		return false
	end
end

--[[
	Gathers current player data from game state.
	Now includes maxStorage from the player's plot.
]]
function gatherPlayerData(player: Player): {money: number, ownedUnits: {[string]: number}, unlockProgress: number}?
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
		-- Get unlock progress
		if _G.ShopManager.GetUnlockProgress then
			unlockProgress = _G.ShopManager.GetUnlockProgress(player)
		end
		
		-- Get owned counts
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
	local maxStorage = 500 -- default
	local BrainrotManager = _G.BrainrotManager
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
	
	-- Get prestige data
	local lifetimeEarnings = 0
	local totalMeatballs = 0
	local spentMeatballs = 0
	local prestigeCount = 0
	local meatballUpgrades = {}
	if _G.PrestigeManager and _G.PrestigeManager.GetPlayerData then
		local prestigeData = _G.PrestigeManager.GetPlayerData(player)
		if prestigeData then
			lifetimeEarnings = prestigeData.lifetimeEarnings or 0
			totalMeatballs = prestigeData.totalMeatballs or 0
			spentMeatballs = prestigeData.spentMeatballs or 0
			prestigeCount = prestigeData.prestigeCount or 0
			meatballUpgrades = prestigeData.meatballUpgrades or {}
		end
	end
	
	-- Get brainrot inventory (with rarities)
	local brainrotInventory = {}
	if BrainrotManager and BrainrotManager.GetInventoryData then
		brainrotInventory = BrainrotManager.GetInventoryData(player) or {}
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
		ownedUnits = ownedUnits,
		unlockProgress = unlockProgress,
		maxStorage = maxStorage,
		purchasedTiers = purchasedTiers,
		convenienceUpgrades = convenienceUpgrades,
		lifetimeEarnings = lifetimeEarnings,
		totalMeatballs = totalMeatballs,
		spentMeatballs = spentMeatballs,
		prestigeCount = prestigeCount,
		meatballUpgrades = meatballUpgrades,
		brainrotInventory = brainrotInventory,
		brainrotPlacements = brainrotPlacements,
		-- Item system data
		itemStorage = itemStorage,
		backpack = backpack,
		storageCapacity = storageCapacity,
		selectedVehicle = selectedVehicle,
		vehicleCapacities = vehicleCapacities,
		gridPositions = gridPositions,
		discoveredSynergies = discoveredSynergies,
	}
end

--------------------------------------------------------------------------------
-- PLAYER EVENTS
--------------------------------------------------------------------------------

--[[
	Called when a player joins. Loads their data and applies it.
]]
local function onPlayerAdded(player: Player)
	-- Load saved data
	local data = loadPlayerData(player)
	PlayerDataCache[player] = data
	
	-- Wait for leaderstats to be created by BrainrotManager
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local money = leaderstats:WaitForChild("Money", 5)
		if money then
			-- Apply saved money
			money.Value = data.money
			print(string.format("✓ Applied saved money for %s: $%d", player.Name, data.money))
		end
	end
	
	-- Restore convenience upgrades EARLY (before ConvenienceUpgradesManager initializes)
	-- This prevents the race condition where ConvenienceUpgradesManager sets empty upgrades
	if data.convenienceUpgrades and next(data.convenienceUpgrades) ~= nil then
		if _G.ConvenienceUpgrades and _G.ConvenienceUpgrades.SetPlayerUpgrades then
			_G.ConvenienceUpgrades.SetPlayerUpgrades(player, data.convenienceUpgrades)
			local upgradeCount = 0
			for _ in pairs(data.convenienceUpgrades) do
				upgradeCount += 1
			end
			print(string.format("✓ Early restored %d convenience upgrades for %s", upgradeCount, player.Name))
		end
	end
	
	-- Wait for ShopManager to initialize the player's data
	task.wait(1)
	
	-- Apply owned units
	if _G.ShopManager and _G.ShopManager.SetPlayerData then
		_G.ShopManager.SetPlayerData(player, data.ownedUnits, data.unlockProgress)
	else
		-- Fallback: Set the values directly
		local ownedFolder = player:FindFirstChild("OwnedUnits")
		if ownedFolder then
			for unitName, count in data.ownedUnits do
				local countValue = ownedFolder:FindFirstChild(unitName)
				if countValue then
					countValue.Value = count
				end
			end
		end
		
		local unlockValue = player:FindFirstChild("UnlockProgress")
		if unlockValue then
			unlockValue.Value = data.unlockProgress
		end
	end
	
	-- Spawn owned brainrot models on the player's plot
	task.spawn(function()
		-- Wait for BrainrotManager to be ready
		local BrainrotManager = waitForBrainrotManager()
		if not BrainrotManager then
			warn("DataManager: BrainrotManager not available, cannot spawn owned brainrots")
			return
		end
		
		-- Wait for player's plot to be assigned (max 10 seconds)
		local plot = nil
		for attempt = 1, 100 do
			plot = BrainrotManager.GetPlayerPlot(player)
			if plot then break end
			task.wait(0.1)
		end
		
		if not plot then
			warn(string.format("DataManager: No plot found for %s, cannot spawn brainrots", player.Name))
			return
		end
		
		-- Restore maxStorage on the plot FIRST
		if data.maxStorage and data.maxStorage > 500 then
			plot:SetAttribute("MaxStorage", data.maxStorage)
			-- Update visual
			local currentStorage = plot:GetAttribute("CurrentStorage") or 0
			if BrainrotManager.UpdateStorageVisual then
				BrainrotManager.UpdateStorageVisual(plot, currentStorage, data.maxStorage)
			end
			print(string.format("✓ Restored max storage to %d for %s", data.maxStorage, player.Name))
		end
		
		-- Restore purchased tiers BEFORE spawning brainrots
		if data.purchasedTiers and data.purchasedTiers > 1 then
			if _G.MapSystem and _G.MapSystem.RestoreTiers then
				print(string.format("Calling RestoreTiers for %s with %d tiers", player.Name, data.purchasedTiers))
				_G.MapSystem.RestoreTiers(player, data.purchasedTiers)
			else
				warn(string.format("Cannot restore tiers for %s: MapSystem not available (MapSystem=%s)", 
					player.Name, tostring(_G.MapSystem)))
			end
		end
		
		-- Small delay to ensure tiers are spawned
		task.wait(0.5)
		
		-- Restore brainrot inventory (with rarities) - this sets up the inventory tracking
		if data.brainrotInventory and next(data.brainrotInventory) ~= nil then
			if BrainrotManager.SetInventoryData then
				-- Reset active counts to 0 since we'll spawn them from placements
				local inventoryWithZeroActive = {}
				for unitName, rarityData in pairs(data.brainrotInventory) do
					inventoryWithZeroActive[unitName] = {}
					for rarity, counts in pairs(rarityData) do
						inventoryWithZeroActive[unitName][rarity] = {
							total = counts.total,
							active = 0  -- Will be updated as we spawn
						}
					end
				end
				BrainrotManager.SetInventoryData(player, inventoryWithZeroActive)
			end
		end
		
		-- Spawn brainrots from saved placements (preserves rarities and attributes)
		local spawnedCount = 0
		if data.brainrotPlacements and #data.brainrotPlacements > 0 then
			for _, placementData in ipairs(data.brainrotPlacements) do
				if BrainrotManager.SpawnFromPlacement then
					local spawnedUnit = BrainrotManager.SpawnFromPlacement(player, placementData)
					if spawnedUnit then
						spawnedCount += 1
						-- Update inventory active count
						local inventory = BrainrotManager.GetInventoryData and BrainrotManager.GetInventoryData(player)
						if inventory and inventory[placementData.unitType] and inventory[placementData.unitType][placementData.rarity] then
							inventory[placementData.unitType][placementData.rarity].active += 1
						end
					end
				end
			end
			if spawnedCount > 0 then
				print(string.format("✓ Restored %d brainrots from saved placements for %s", spawnedCount, player.Name))
			end
		elseif data.ownedUnits then
			-- Fallback: Spawn from ownedUnits if no placement data (old save format)
			for unitName, count in data.ownedUnits do
				if count >= 1 then
					local unitConfig = ShopConfig.GetConfig(unitName)
					if unitConfig then
						local spawnedUnit = BrainrotManager.SpawnBrainrot(player, unitConfig.ModelName)
						if spawnedUnit then
							-- Use milestone-aware income/cycle calculations
							local effectiveIncome = ShopConfig.CalculateEffectiveIncome(unitName, count)
							local effectiveCycleTime = ShopConfig.CalculateEffectiveCycleTime(unitName, count)
							
							spawnedUnit:SetAttribute("IncomeAmount", effectiveIncome)
							spawnedUnit:SetAttribute("IncomeInterval", effectiveCycleTime)
							spawnedUnit:SetAttribute("UnitType", unitName)
							spawnedCount += 1
						end
					end
				end
			end
			if spawnedCount > 0 then
				print(string.format("✓ Spawned %d owned brainrot models for %s (legacy format)", spawnedCount, player.Name))
			end
		end
		
		-- Restore convenience upgrades (fallback if early restoration didn't work)
		-- Check if upgrades were already restored early (before task.spawn)
		local existingUpgrades = _G.ConvenienceUpgrades and _G.ConvenienceUpgrades.GetPlayerUpgrades and _G.ConvenienceUpgrades.GetPlayerUpgrades(player)
		local alreadyRestored = existingUpgrades and next(existingUpgrades) ~= nil
		
		if not alreadyRestored and data.convenienceUpgrades and next(data.convenienceUpgrades) ~= nil then
			if _G.ConvenienceUpgrades and _G.ConvenienceUpgrades.SetPlayerUpgrades then
				_G.ConvenienceUpgrades.SetPlayerUpgrades(player, data.convenienceUpgrades)
				-- Count upgrades safely
				local upgradeCount = 0
				for _ in pairs(data.convenienceUpgrades) do
					upgradeCount += 1
				end
				print(string.format("✓ Late restored %d convenience upgrades for %s", upgradeCount, player.Name))
			end
		end
		
		-- Restore prestige data
		if _G.PrestigeManager and _G.PrestigeManager.InitializePlayerData then
			_G.PrestigeManager.InitializePlayerData(player, {
				lifetimeEarnings = data.lifetimeEarnings or 0,
				totalMeatballs = data.totalMeatballs or 0,
				spentMeatballs = data.spentMeatballs or 0,
				prestigeCount = data.prestigeCount or 0,
				meatballUpgrades = data.meatballUpgrades or {},
			})
			if data.totalMeatballs and data.totalMeatballs > 0 then
				print(string.format("✓ Restored prestige data for %s: %d meatballs, %d prestiges", player.Name, data.totalMeatballs, data.prestigeCount or 0))
			end
		end
	end)
	
	DataLoaded[player] = true
end

--[[
	Called when a player leaves. Saves their data.
]]
local function onPlayerRemoving(player: Player)
	if DataLoaded[player] then
		savePlayerData(player)
	end
	
	-- Cleanup
	PlayerDataCache[player] = nil
	DataLoaded[player] = nil
end

--------------------------------------------------------------------------------
-- AUTO-SAVE
--------------------------------------------------------------------------------

local function autoSaveAllPlayers()
	for _, player in Players:GetPlayers() do
		if DataLoaded[player] then
			task.spawn(savePlayerData, player)
		end
	end
end

-- Auto-save loop
task.spawn(function()
	while true do
		task.wait(CONFIG.AUTO_SAVE_INTERVAL)
		print("DataManager: Running auto-save...")
		autoSaveAllPlayers()
	end
end)

--------------------------------------------------------------------------------
-- GAME SHUTDOWN
--------------------------------------------------------------------------------

-- Save all players when game is closing
game:BindToClose(function()
	print("DataManager: Game closing, saving all player data...")
	
	-- In Studio, BindToClose only has limited time
	if RunService:IsStudio() then
		-- Quick save for Studio testing
		for _, player in Players:GetPlayers() do
			if DataLoaded[player] then
				savePlayerData(player)
			end
		end
	else
		-- Production: spawn all saves concurrently
		local saveTasks = {}
		for _, player in Players:GetPlayers() do
			if DataLoaded[player] then
				table.insert(saveTasks, task.spawn(savePlayerData, player))
			end
		end
		
		-- Wait for all saves to complete (max 30 seconds)
		task.wait(5)
	end
	
	print("DataManager: Shutdown save complete")
end)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   DataManager - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Connect player events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	-- Handle existing players (in case script loads late)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	
	print("✓ DataManager initialized")
	print("  • Auto-save interval: " .. CONFIG.AUTO_SAVE_INTERVAL .. "s")
	print("═══════════════════════════════════════════")
end

initialize()

-- Export API
_G.DataManager = {
	SavePlayerData = savePlayerData,
	LoadPlayerData = loadPlayerData,
	GetCachedData = function(player) return PlayerDataCache[player] end,
	ResetPlayerData = function(player, keepPrestigeData)
		local currentData = PlayerDataCache[player]
		if not currentData then return end
		
		-- Default reset values
		local newData = getDefaultData()
		
		if keepPrestigeData then
			-- Preserve prestige data
			newData.lifetimeEarnings = currentData.lifetimeEarnings
			newData.totalMeatballs = currentData.totalMeatballs
			newData.spentMeatballs = currentData.spentMeatballs
			newData.prestigeCount = currentData.prestigeCount
			newData.meatballUpgrades = currentData.meatballUpgrades
			
			-- Apply "Quick Start" bonuses if any
			local startingMoney = CONFIG.DEFAULT_MONEY
			if _G.PrestigeManager and _G.PrestigeManager.GetStartingMoneyBonus then
				startingMoney = startingMoney + _G.PrestigeManager.GetStartingMoneyBonus(player)
			end
			newData.money = startingMoney
		end
		
		-- Update cache
		PlayerDataCache[player] = newData
		
		-- Save immediately
		savePlayerData(player)
		
		return newData
	end,
}
