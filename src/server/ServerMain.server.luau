--[[
	ServerMain.server.luau
	
	The central bootstrapper for the server-side architecture.
	Ensures deterministic load order and initializes systems.
	
	Load Order:
	1. Core Services (Data, Inventory)
	2. Logic Systems (Brainrot, ItemProduction)
	3. Feature Systems (Shop, etc. - TO BE MIGRATED)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Module Storage
local loadedModules = {}

--[[
	Helper to safe require and init a module.
	Also sets a global alias for backward compatibility.
]]
local function loadModule(name, path, globalAlias)
	local success, module = pcall(require, path)
	if not success then
		warn(string.format("❌ Failed to require %s: %s", name, module))
		return nil
	end
	
	print(string.format("📦 Loaded key module: %s", name))
	loadedModules[name] = module
	
	-- Backwards Compatibility: Set Global
	if globalAlias then
		_G[globalAlias] = module
	end
	
	return module
end

--[[
	Helper to initialize a loaded module if it has an Init function.
]]
local function initModule(name)
	local module = loadedModules[name]
	if module and type(module.Init) == "function" then
		print(string.format("🚀 Initializing %s...", name))
		task.spawn(function()
			local success, err = pcall(module.Init)
			if not success then
				warn(string.format("❌ Error initializing %s: %s", name, err))
			else
				print(string.format("✓ %s Initialized", name))
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- LOADING SEQUENCE
--------------------------------------------------------------------------------

print("╔═══════════════════════════════════════════╗")
print("║           SERVER BOOTSTRAP START          ║")
print("╚═══════════════════════════════════════════╝")

-- 1. Core Data Systems
local DataManager = loadModule("DataManager", script.Parent.DataManager, "DataManager")
local InventoryManager = loadModule("InventoryManager", script.Parent.InventoryManager, "InventoryManager")

-- 2. Core Game Logic
-- MapSystem must be loaded early as it handles plots
local MapSystem = loadModule("MapSystem", script.Parent.MapSystem, "MapSystem")
local BrainrotManager = loadModule("BrainrotManager", script.Parent.BrainrotManager, "BrainrotManager")
local ItemProductionManager = loadModule("ItemProductionManager", script.Parent.ItemProductionManager, "ItemProductionManager")
local GridManager = loadModule("GridManager", script.Parent.GridManager, "GridManager")
local ItemStorageManager = loadModule("ItemStorageManager", script.Parent.ItemStorageManager, "ItemStorageManager")

-- 3. Core Features
local ShopManager = loadModule("ShopManager", script.Parent.ShopManager, "ShopManager")
local TransportManager = loadModule("TransportManager", script.Parent.TransportManager, "TransportManager")
local PrestigeManager = loadModule("PrestigeManager", script.Parent.PrestigeManager, "PrestigeManager")
local ArtifactManager = loadModule("ArtifactManager", script.Parent.ArtifactManager, "ArtifactManager")

-- 4. Extended Features
local StockMarketManager = loadModule("StockMarketManager", script.Parent.StockMarketManager, "StockMarketManager")
local StockMarketBillboards = loadModule("StockMarketBillboards", script.Parent.StockMarketBillboards, "StockMarketBillboards")
local MarketManager = loadModule("MarketManager", script.Parent.MarketManager, "MarketManager")
local StorageBoxManager = loadModule("StorageBoxManager", script.Parent.StorageBoxManager, "StorageBoxManager")
local StorageUpgradeManager = loadModule("StorageUpgradeManager", script.Parent.StorageUpgradeManager, "StorageUpgradeManager")
local ConvenienceUpgradesManager = loadModule("ConvenienceUpgradesManager", script.Parent.ConvenienceUpgradesManager, "ConvenienceUpgrades")
local BuildModeManager = loadModule("BuildModeManager", script.Parent.BuildModeManager, "BuildModeManager")
local IslandShopManager = loadModule("IslandShopManager", script.Parent.IslandShopManager, "IslandShop")
local MewingManager = loadModule("MewingManager", script.Parent.MewingManager, "MewingManager")
local UnitInteractionManager = loadModule("UnitInteractionManager", script.Parent.UnitInteractionManager, "UnitInteractionManager")
local AdminService = loadModule("AdminService", script.Parent.AdminService, "AdminService")
local InventoryService = loadModule("InventoryService", script.Parent.InventoryService, "InventoryService")

-- 5. Initialize All Systems
-- Priority 1: Data & Map
initModule("DataManager")
initModule("MapSystem")
initModule("InventoryManager")

-- Priority 2: Logic
initModule("BrainrotManager")
initModule("ItemProductionManager")
initModule("GridManager")
initModule("ItemStorageManager")

-- Priority 3: Features
initModule("ShopManager")
initModule("TransportManager")
initModule("PrestigeManager")
initModule("ArtifactManager")
initModule("InventoryService") -- Service aggregation
initModule("StockMarketManager")
initModule("StockMarketBillboards")
initModule("MarketManager")
initModule("StorageBoxManager")
initModule("StorageUpgradeManager")
initModule("ConvenienceUpgradesManager")
initModule("BuildModeManager")
initModule("IslandShopManager")
initModule("MewingManager")
initModule("UnitInteractionManager")
initModule("AdminService")

print("---------------------------------------------")
print("✓ Server Bootstrap Complete")
print("---------------------------------------------")
