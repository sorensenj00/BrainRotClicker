--[[
	ServerMain.server.luau
	
	The central bootstrapper for the server-side architecture.
	Ensures deterministic load order and initializes systems with Dependency Injection.
	
	Load Order:
	1. Core Services (Data, Inventory)
	2. Logic Systems (Brainrot, ItemProduction)
	3. Feature Systems (Shop, etc.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Ensure Remote Folders Exist
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local StockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket") or Instance.new("Folder")
StockMarketFolder.Name = "StockMarket"
StockMarketFolder.Parent = ReplicatedStorage

-- Service Container (Dependency Injection)
local Services = {}

--[[
	Helper to safe require and register a module.
]]
local function registerService(name, path)
	local success, module = pcall(require, path)
	if not success then
		warn(string.format("❌ Failed to require %s: %s", name, module))
		return nil
	end
	
	print(string.format("📦 Loaded service: %s", name))
	Services[name] = module
	return module
end

--[[
	Helper to initialize a loaded service.
]]
local function initService(name)
	local module = Services[name]
	if module and type(module.Init) == "function" then
		print(string.format("🚀 Initializing %s...", name))
		local success, err = pcall(module.Init, Services)
		if not success then
			warn(string.format("❌ Error initializing %s: %s", name, err))
		else
			print(string.format("✓ %s Initialized", name))
		end
	end
end

--------------------------------------------------------------------------------
-- LOADING SEQUENCE
--------------------------------------------------------------------------------

print("╔═══════════════════════════════════════════╗")
print("║           SERVER BOOTSTRAP START          ║")
print("╚═══════════════════════════════════════════╝")

-- 1. Load All Modules (DataService and PlayerLifecycleManager first to avoid circular deps)
registerService("DataService", script.Parent.DataService)
registerService("PlayerLifecycleManager", script.Parent.PlayerLifecycleManager)
registerService("DataManager", script.Parent.DataManager)
registerService("InventoryManager", script.Parent.InventoryManager)
registerService("MapSystem", script.Parent.MapSystem)
registerService("BrainrotManager", script.Parent.BrainrotManager)
registerService("ItemProductionManager", script.Parent.ItemProductionManager)
registerService("AchievementsManager", script.Parent.AchievementsManager)
registerService("TerrainGenerator", script.Parent.TerrainGenerator)
registerService("PlotManager", script.Parent.PlotManager)
registerService("GridManager", script.Parent.GridManager)
registerService("ItemStorageManager", script.Parent.ItemStorageManager)
registerService("ShopManager", script.Parent.ShopManager)
registerService("TransportManager", script.Parent.TransportManager)
registerService("CartManager", script.Parent.CartManager)
registerService("PlayerTransportManager", script.Parent.PlayerTransportManager)
registerService("PrestigeManager", script.Parent.PrestigeManager)
registerService("ArtifactManager", script.Parent.ArtifactManager)
registerService("ArtifactUpgradeManager", script.Parent.ArtifactUpgradeManager)
registerService("ArtifactExchangeManager", script.Parent.ArtifactExchangeManager)
registerService("StockMarketManager", script.Parent.StockMarketManager)
registerService("StockMarketBillboards", script.Parent.StockMarketBillboards)
registerService("MarketManager", script.Parent.MarketManager)
registerService("ContractManager", script.Parent.ContractManager)
registerService("DroneOpsManager", script.Parent.DroneOpsManager)
registerService("NetWorthStatueManager", script.Parent.NetWorthStatueManager)
registerService("StorageBoxManager", script.Parent.StorageBoxManager)
registerService("StorageUpgradeManager", script.Parent.StorageUpgradeManager)
registerService("ConvenienceUpgradesManager", script.Parent.ConvenienceUpgradesManager)
registerService("BuildModeManager", script.Parent.BuildModeManager)
registerService("IslandShopManager", script.Parent.IslandShopManager)
registerService("MewingManager", script.Parent.MewingManager)
registerService("UnitInteractionManager", script.Parent.UnitInteractionManager)
registerService("AdminService", script.Parent.AdminService)
registerService("CartShopManager", script.Parent.CartShopManager)
registerService("PremiumShopManager", script.Parent.PremiumShopManager)

-- 2. Initialize All Systems (In Order)

-- Priority 0: Core Infrastructure (must be first)
initService("DataService")
initService("PlayerLifecycleManager")

-- Priority 1: Core Data & Map
initService("DataManager")
initService("TerrainGenerator")
initService("PlotManager")
initService("MapSystem")
initService("InventoryManager")

-- Priority 2: Core Logic
initService("BrainrotManager")
initService("ItemProductionManager")
initService("AchievementsManager")
initService("GridManager")
initService("ItemStorageManager")

-- Priority 3: Features
initService("ShopManager")
initService("TransportManager")
initService("CartManager")
initService("PlayerTransportManager")
initService("PrestigeManager")
initService("ArtifactManager")
initService("ArtifactUpgradeManager")
initService("ArtifactExchangeManager")
initService("StockMarketManager")
initService("StockMarketBillboards")
initService("MarketManager")
initService("ContractManager")
initService("DroneOpsManager")
initService("NetWorthStatueManager")
initService("StorageBoxManager")
initService("StorageUpgradeManager")
initService("ConvenienceUpgradesManager")
initService("BuildModeManager")
initService("IslandShopManager")
initService("MewingManager")
initService("UnitInteractionManager")
initService("AdminService")
initService("CartShopManager")
initService("PremiumShopManager")

print("---------------------------------------------")
print("✓ Server Bootstrap Complete")
print("---------------------------------------------")
