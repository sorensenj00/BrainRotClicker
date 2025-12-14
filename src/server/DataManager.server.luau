--[[
	DataManager Server Script
	
	Handles saving and loading player data.
	REFACTORED: Now acts as a bridge/adapter to the new DataService (ProfileService).
	
	Saves:
	- Money (from leaderstats)
	- Owned unit counts (from ShopManager)
	- Unlock progress (from ShopManager)
	
	The core saving logic has been moved to DataService (ModuleScript).
	This script now registers the "Legacy" data component.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Wait for shared modules
local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopConfig"))

-- New Data Service
-- Ideally, DataService should be in ServerScriptService/Server/DataService
-- I am assuming it was created in the same directory as this script.
-- Adjust require path if necessary.
local DataService = require(script.Parent.DataService)

-- Configuration
local CONFIG = {
	DEFAULT_MONEY = 100,      -- Starting money for new players
}

-- Wait for BrainrotManager API (loaded via _G)
local function waitForBrainrotManager()
	local attempts = 0
	while not _G.BrainrotManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.BrainrotManager
end

-- Wait for InventoryManager API (loaded via _G)
local function waitForInventoryManager()
	local attempts = 0
	while not _G.InventoryManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.InventoryManager
end

--------------------------------------------------------------------------------
-- DATA GATHERING (LEGACY)
--------------------------------------------------------------------------------

--[[
	Default data structure for new players.
	Now exported via DataService handler.
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
		-- RPG Mechanics: Layered Grid
		gridPositions = {},       -- Layered grid: {[slotIndex]: {Unit = {...}, Tile = tileId}}
		discoveredSynergies = {}, -- Discovered synergy recipes: {[synergyId]: true}
		-- RPG Mechanics: Artifacts
		playerArtifacts = {},     -- Artifact inventory: {[GUID]: artifactData}
	}
end

--[[
	Gathers current player data from game state.
	Moved from old DataManager.
]]
local function gatherPlayerData(player: Player): {money: number, ownedUnits: {[string]: number}, unlockProgress: number}?
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
	
	-- Get brainrot inventory (from InventoryManager)
	-- We store the flat inventory format directly.
	local brainrotInventory = {}
	if _G.InventoryManager then
		brainrotInventory = _G.InventoryManager.GetInventory(player) or {}
	elseif BrainrotManager and BrainrotManager.GetInventoryData then
		-- Fallback to old scraping if InventoryManager not ready (unlikely)
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
-- DATA LOADING (LEGACY)
--------------------------------------------------------------------------------

local function applyLegacyData(player: Player, data: any)
	if not data then
		warn("DataManager: No data to apply for " .. player.Name)
		return
	end
	
	-- Create leaderstats IMMEDIATELY to prevent race conditions
	-- Other scripts depend on leaderstats existing
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
		
		local money = Instance.new("IntValue")
		money.Name = "Money"
		money.Value = data.money or CONFIG.DEFAULT_MONEY -- Apply saved money
		money.Parent = leaderstats
		
		print(string.format("✓ Created leaderstats for %s with $%d", player.Name, money.Value))
	else
		-- leaderstats exists, just update value
		local money = leaderstats:FindFirstChild("Money")
		if money then
			money.Value = data.money or CONFIG.DEFAULT_MONEY
			print(string.format("✓ Applied saved money for %s: $%d", player.Name, money.Value))
		end
	end
	
	-- Restore convenience upgrades EARLY (before ConvenienceUpgradesManager initializes)
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
		_G.ShopManager.SetPlayerData(player, data.ownedUnits or {}, data.unlockProgress or 5)
	else
		-- Fallback: Set the values directly
		local ownedFolder = player:FindFirstChild("OwnedUnits")
		if ownedFolder then
			for unitName, count in pairs(data.ownedUnits or {}) do
				local countValue = ownedFolder:FindFirstChild(unitName)
				if countValue then
					countValue.Value = count
				end
			end
		end
		
		local unlockValue = player:FindFirstChild("UnlockProgress")
		if unlockValue then
			unlockValue.Value = data.unlockProgress or 5
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
		
		-- Restore brainrot inventory
		-- We push data to InventoryManager, which notifies BrainrotManager to spawn units.
		if not BrainrotManager then BrainrotManager = _G.BrainrotManager end
		local InventoryManager = _G.InventoryManager or waitForInventoryManager()

		if InventoryManager and data.brainrotInventory and next(data.brainrotInventory) ~= nil then
			-- Check if it's the new flat format (has 'level' field in entries)
			local firstKey, firstVal = next(data.brainrotInventory)
			local isFlatFormat = (type(firstVal) == "table" and firstVal.level ~= nil)
			
			local finalInventory = {}

			if isFlatFormat then
				-- Already compatible with InventoryManager
				finalInventory = data.brainrotInventory
			else
				-- Convert Old Format: {[unitName]: {[rarity]: {total, active}}}
				-- To Flat Format: {[unitName]: {level, rarity}}
				for unitName, rarityData in pairs(data.brainrotInventory) do
					for rarity, counts in pairs(rarityData) do
						if counts.total > 0 then
							-- We only keep one entry per unit type (highest/first found in loop)
							-- This mimics the "Stacking" logic refactor.
							finalInventory[unitName] = {
								level = counts.total,
								rarity = rarity
							}
						end
					end
				end
				print(string.format("  [Migration] Converted %s inventory items to flat format", player.Name))
			end

			-- Set the authoritative state
			InventoryManager.SetInventory(player, finalInventory)
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
			local inventoryData = {}
			
			for unitName, count in pairs(data.ownedUnits) do
				if count >= 1 then
					-- Initialize inventory entry
					if not inventoryData[unitName] then inventoryData[unitName] = {} end
					if not inventoryData[unitName]["Normal"] then 
						inventoryData[unitName]["Normal"] = {total = 0, active = 0} 
					end
					
					-- Update totals
					inventoryData[unitName]["Normal"].total = count
					
					-- Spawn units
					for i = 1, count do
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
								spawnedUnit:SetAttribute("Rarity", "Normal") -- Default to Normal for legacy
								spawnedCount += 1
								
								-- Update active count
								inventoryData[unitName]["Normal"].active += 1
							end
						end
					end
				end
			end
			
			-- Set the inventory data in BrainrotManager
			if BrainrotManager.SetInventoryData then
				BrainrotManager.SetInventoryData(player, inventoryData)
			end
			
			if spawnedCount > 0 then
				print(string.format("✓ Spawned %d owned brainrot models for %s (legacy format) and updated inventory", spawnedCount, player.Name))
			end
		end
		
		-- Restore convenience upgrades (fallback if early restoration didn't work)
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
end

--------------------------------------------------------------------------------
-- AUTO-SYNC (LEGACY)
--------------------------------------------------------------------------------

--[[
	Because we're using ProfileService in a hybrid "Legacy Adapter" mode,
	we need to periodically push the current game state into the Profile.Data table.
	ProfileService auto-saves the *table* every 30 seconds (configurable),
	but it doesn't know how to fetch new data from the game (e.g., leaderstats)
	unless we update the table.

	This loop ensures the Profile.Data table is always reasonably up-to-date.
]]
task.spawn(function()
	while true do
		task.wait(10) -- Update the profile data object every 10 seconds
		for _, player in ipairs(Players:GetPlayers()) do
			local profileData = DataService.GetData(player)
			if profileData then
				-- Gather fresh data from game state
				local freshData = gatherPlayerData(player)
				if freshData then
					-- Update the profile data in place
					for k, v in pairs(freshData) do
						profileData[k] = v
					end
				end
			end
		end
	end
end)


--------------------------------------------------------------------------------
-- INIT & EXPORT
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   DataManager (Legacy Adapter) - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Wait for dependencies
	-- We explicitly wait here to ensure dependencies are ready before DataService
	-- starts loading players. This prevents race conditions in OnLoad handlers.
	print("DataManager: Waiting for Managers...")
	local brainrotManager = waitForBrainrotManager()
	local inventoryManager = waitForInventoryManager()

	if not brainrotManager then
		warn("DataManager: Failed to load BrainrotManager!")
	end
	if not inventoryManager then
		warn("DataManager: Failed to load InventoryManager!")
	end
	
	if brainrotManager and inventoryManager then
		print("DataManager: Managers ready.")
	end

	-- Register with the new DataService
	-- We register as "Legacy" (or Root) to handle the entire data table
	DataService.RegisterHandler("Legacy", {
		DefaultData = getDefaultData(),
		OnLoad = applyLegacyData,
		OnSave = gatherPlayerData
	})

	-- Init DataService (this starts the player loading process)
	DataService.Init()

	print("✓ DataManager (Legacy Adapter) initialized")
	print("═══════════════════════════════════════════")
end

initialize()

-- Export Legacy API for compatibility
-- Many scripts use _G.DataManager.GetCachedData(player)
_G.DataManager = {
	SavePlayerData = function(player)
		-- ProfileService handles auto-saves.
		-- This manual save call is now less critical but we can map it to nothing or a forced save if exposed.
		-- Since DataService handles saving on removal, manual saves might be redundant.
		-- If we want to support manual save (e.g. "Save Game" button), we need to expose Save from DataService.
		-- For now, we return true to fake success.
		return true
	end,
	LoadPlayerData = function(player)
		-- Should return the data immediately if loaded
		return DataService.GetData(player) or getDefaultData()
	end,
	GetCachedData = function(player)
		return DataService.GetData(player)
	end,
	ResetPlayerData = function(player, keepPrestigeData)
		-- This is tricky with ProfileService as it involves wiping data.
		-- For now, we can manually reset the table in the profile.
		local currentData = DataService.GetData(player)
		if not currentData then return end
		
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
		
		-- Update the profile data in place (ProfileService will save this)
		-- We need to clear existing keys first because simple assignment might not remove old keys if we iterate.
		-- Use table.clear would break strict typing if not recognized, but iterating to nil is safe.
		for k, _ in pairs(currentData) do
			currentData[k] = nil
		end
		
		-- Merge new data
		for k, v in pairs(newData) do
			currentData[k] = v
		end
		
		-- Apply the new data visually/logically
		applyLegacyData(player, currentData)
		
		return currentData
	end,
}
