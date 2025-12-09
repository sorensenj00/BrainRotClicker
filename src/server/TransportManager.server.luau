--[[
	TransportManager Server Script
	
	Handles the transport system for carrying items from storage to market.
	
	Features:
	- Vehicle selection and spawning
	- Item loading from storage to backpack
	- Backpack capacity management
	- Vehicle upgrades
	
	Part of the "Sell a Brainrot" system.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

-- Constants
local CONFIG = {
	DEFAULT_VEHICLE = "Sneakers",
	VEHICLES = {
		Sneakers = {
			capacity = 100,
			price = 0,  -- Starter vehicle
			description = "Basic transport, small capacity",
		},
		Cart = {
			capacity = 500,
			price = 5000,
			description = "Wooden cart, medium capacity",
		},
		Hoverboard = {
			capacity = 2000,
			price = 50000,
			description = "Futuristic hover transport",
		},
		Truck = {
			capacity = 10000,
			price = 500000,
			description = "Massive hauler, huge capacity",
		},
	},
}

-- Player data: { [Player] = { vehicleContents = {}, selectedVehicle = "Sneakers" } }
local PlayerTransport = {}

-- Remote events and functions
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

-- Create events
local VehicleUpdated = RemoteEvents:FindFirstChild("VehicleUpdated") or Instance.new("RemoteEvent")
VehicleUpdated.Name = "VehicleUpdated"
VehicleUpdated.Parent = RemoteEvents

local BackpackLoaded = RemoteEvents:FindFirstChild("BackpackLoaded") or Instance.new("RemoteEvent")
BackpackLoaded.Name = "BackpackLoaded"
BackpackLoaded.Parent = RemoteEvents

-- Create functions
local SelectVehicle = RemoteFunctions:FindFirstChild("SelectVehicle") or Instance.new("RemoteFunction")
SelectVehicle.Name = "SelectVehicle"
SelectVehicle.Parent = RemoteFunctions

local GetVehicleInfo = RemoteFunctions:FindFirstChild("GetVehicleInfo") or Instance.new("RemoteFunction")
GetVehicleInfo.Name = "GetVehicleInfo"
GetVehicleInfo.Parent = RemoteFunctions

local LoadFromStorage = RemoteFunctions:FindFirstChild("LoadFromStorage") or Instance.new("RemoteFunction")
LoadFromStorage.Name = "LoadFromStorage"
LoadFromStorage.Parent = RemoteFunctions

local LoadMaxFromStorage = RemoteFunctions:FindFirstChild("LoadMaxFromStorage") or Instance.new("RemoteFunction")
LoadMaxFromStorage.Name = "LoadMaxFromStorage"
LoadMaxFromStorage.Parent = RemoteFunctions

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Waits for ItemStorageManager to be available.
	@return table? - The ItemStorageManager API or nil
]]
local function waitForItemStorageManager()
	local attempts = 0
	while not _G.ItemStorageManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.ItemStorageManager
end

--[[
	Gets the backpack capacity for a player based on selected vehicle.
	@param player Player - The player
	@return number - The capacity
]]
local function getBackpackCapacity(player)
	local transport = PlayerTransport[player]
	if not transport then return 100 end
	
	local vehicleId = transport.selectedVehicle or CONFIG.DEFAULT_VEHICLE
	local vehicleConfig = CONFIG.VEHICLES[vehicleId]
	return vehicleConfig and vehicleConfig.capacity or 100
end

--[[
	Gets current backpack usage for a player.
	@param player Player - The player
	@return number - Total items in backpack
]]
local function getBackpackUsage(player)
	local ItemStorageManager = _G.ItemStorageManager
	if not ItemStorageManager then return 0 end
	
	local backpack = ItemStorageManager.GetBackpackContents(player)
	local total = 0
	for _, count in pairs(backpack) do
		total = total + count
	end
	return total
end

--[[
	Gets remaining backpack space for a player.
	@param player Player - The player
	@return number - Available space
]]
local function getBackpackSpace(player)
	return getBackpackCapacity(player) - getBackpackUsage(player)
end

--[[
	Initializes transport state for a player.
	@param player Player - The player
]]
local function initializePlayer(player)
	PlayerTransport[player] = {
		selectedVehicle = CONFIG.DEFAULT_VEHICLE,
	}
	
	-- Update ItemStorageManager with new capacity
	local ItemStorageManager = _G.ItemStorageManager
	if ItemStorageManager and ItemStorageManager.SetBackpackCapacity then
		ItemStorageManager.SetBackpackCapacity(player, getBackpackCapacity(player))
	end
	
	print(string.format("✓ TransportManager: Initialized for %s (Vehicle: %s, Capacity: %d)", 
		player.Name, CONFIG.DEFAULT_VEHICLE, getBackpackCapacity(player)))
end

--[[
	Cleans up transport state for a player.
	@param player Player - The player
]]
local function cleanupPlayer(player)
	PlayerTransport[player] = nil
end

--------------------------------------------------------------------------------
-- API FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Selects a vehicle for a player.
	@param player Player - The player
	@param vehicleId string - The vehicle to select
	@return boolean - Success
]]
local function selectVehicle(player, vehicleId)
	local transport = PlayerTransport[player]
	if not transport then return false end
	
	local vehicleConfig = CONFIG.VEHICLES[vehicleId]
	if not vehicleConfig then
		warn("TransportManager: Unknown vehicle: " .. tostring(vehicleId))
		return false
	end
	
	-- Check if player owns this vehicle (TODO: add ownership tracking)
	-- For now, only Sneakers are free
	if vehicleId ~= "Sneakers" then
		-- Check if player has enough money to buy
		local leaderstats = player:FindFirstChild("leaderstats")
		local moneyValue = leaderstats and leaderstats:FindFirstChild("Money")
		
		if not moneyValue or moneyValue.Value < vehicleConfig.price then
			return false, "Not enough money"
		end
		
		-- Deduct money
		moneyValue.Value = moneyValue.Value - vehicleConfig.price
	end
	
	transport.selectedVehicle = vehicleId
	
	-- Update ItemStorageManager with new capacity
	local ItemStorageManager = _G.ItemStorageManager
	if ItemStorageManager and ItemStorageManager.SetBackpackCapacity then
		ItemStorageManager.SetBackpackCapacity(player, getBackpackCapacity(player))
	end
	
	-- Notify client
	VehicleUpdated:FireClient(player, vehicleId, getBackpackCapacity(player))
	
	print(string.format("✓ %s selected vehicle: %s (Capacity: %d)", 
		player.Name, vehicleId, getBackpackCapacity(player)))
	
	return true
end

--[[
	Loads items from storage to backpack.
	@param player Player - The player
	@param itemId string - Item to load (or nil for max smart load)
	@param count number - How many to load
	@return number - How many actually loaded
]]
local function loadFromStorage(player, itemId, count)
	local ItemStorageManager = _G.ItemStorageManager
	if not ItemStorageManager then return 0 end
	
	local availableSpace = getBackpackSpace(player)
	if availableSpace <= 0 then return 0 end
	
	-- Limit to available space
	local toLoad = math.min(count, availableSpace)
	
	-- Transfer from storage to backpack
	local loaded = ItemStorageManager.TransferToBackpack(player, itemId, toLoad)
	
	if loaded > 0 then
		BackpackLoaded:FireClient(player, itemId, loaded)
		print(string.format("✓ %s loaded %d x %s to backpack", player.Name, loaded, itemId))
	end
	
	return loaded
end

--[[
	Loads items from storage to backpack, prioritizing highest value items.
	@param player Player - The player
	@return table - { [itemId] = count } of loaded items
]]
local function loadMaxFromStorageFn(player)
	local ItemStorageManager = _G.ItemStorageManager
	if not ItemStorageManager then return {} end
	
	local loaded = {}
	local availableSpace = getBackpackSpace(player)
	
	if availableSpace <= 0 then return {} end
	
	-- Get storage contents
	local storage = ItemStorageManager.GetStorageContents(player)
	
	-- Sort items by value (highest first)
	local itemList = {}
	for itemId, count in pairs(storage) do
		local itemInfo = ItemConfig.Items[itemId]
		if itemInfo and count > 0 then
			table.insert(itemList, {
				itemId = itemId,
				count = count,
				value = itemInfo.basePrice or 1,
			})
		end
	end
	
	table.sort(itemList, function(a, b)
		return a.value > b.value
	end)
	
	-- Load highest value items first
	for _, item in ipairs(itemList) do
		if availableSpace <= 0 then break end
		
		local toLoad = math.min(item.count, availableSpace)
		local actualLoaded = ItemStorageManager.TransferToBackpack(player, item.itemId, toLoad)
		
		if actualLoaded > 0 then
			loaded[item.itemId] = actualLoaded
			availableSpace = availableSpace - actualLoaded
		end
	end
	
	-- Notify client
	local totalLoaded = 0
	for _, count in pairs(loaded) do
		totalLoaded = totalLoaded + count
	end
	
	if totalLoaded > 0 then
		BackpackLoaded:FireClient(player, nil, totalLoaded)  -- nil = mixed
		print(string.format("✓ %s loaded %d items to backpack (max)", player.Name, totalLoaded))
	end
	
	return loaded
end

--[[
	Gets vehicle information for a player.
	@param player Player - The player
	@return table - Vehicle info
]]
local function getVehicleInfoFn(player)
	local transport = PlayerTransport[player]
	if not transport then
		return {
			selectedVehicle = CONFIG.DEFAULT_VEHICLE,
			capacity = 100,
			currentLoad = 0,
			availableVehicles = CONFIG.VEHICLES,
		}
	end
	
	return {
		selectedVehicle = transport.selectedVehicle,
		capacity = getBackpackCapacity(player),
		currentLoad = getBackpackUsage(player),
		availableVehicles = CONFIG.VEHICLES,
	}
end

--[[
	Gets transport data for saving via DataManager.
	@param player Player - The player
	@return table - Transport data
]]
local function getTransportData(player)
	local transport = PlayerTransport[player]
	if not transport then
		return { selectedVehicle = CONFIG.DEFAULT_VEHICLE }
	end
	
	return {
		selectedVehicle = transport.selectedVehicle,
	}
end

--[[
	Sets transport data from DataManager load.
	@param player Player - The player
	@param data table - Transport data
]]
local function setTransportData(player, data)
	if not PlayerTransport[player] then
		PlayerTransport[player] = {}
	end
	
	PlayerTransport[player].selectedVehicle = data.selectedVehicle or CONFIG.DEFAULT_VEHICLE
	
	-- Update ItemStorageManager with capacity
	local ItemStorageManager = _G.ItemStorageManager
	if ItemStorageManager and ItemStorageManager.SetBackpackCapacity then
		ItemStorageManager.SetBackpackCapacity(player, getBackpackCapacity(player))
	end
end

--------------------------------------------------------------------------------
-- REMOTE FUNCTION HANDLERS
--------------------------------------------------------------------------------

SelectVehicle.OnServerInvoke = function(player, vehicleId)
	return selectVehicle(player, vehicleId)
end

GetVehicleInfo.OnServerInvoke = function(player)
	return getVehicleInfoFn(player)
end

LoadFromStorage.OnServerInvoke = function(player, itemId, count)
	return loadFromStorage(player, itemId, count or 1)
end

LoadMaxFromStorage.OnServerInvoke = function(player)
	return loadMaxFromStorageFn(player)
end

--------------------------------------------------------------------------------
-- PLAYER EVENTS
--------------------------------------------------------------------------------

local function onPlayerAdded(player)
	-- Wait for dependencies
	task.wait(2)
	waitForItemStorageManager()
	
	initializePlayer(player)
end

local function onPlayerRemoving(player)
	cleanupPlayer(player)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   TransportManager - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Connect player events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	-- Handle existing players
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	
	print("✓ TransportManager initialized")
	print("  • Default vehicle: " .. CONFIG.DEFAULT_VEHICLE)
	print("  • Vehicles: Sneakers, Cart, Hoverboard, Truck")
	print("═══════════════════════════════════════════")
end

initialize()

-- Export API for other scripts
_G.TransportManager = {
	SelectVehicle = selectVehicle,
	LoadFromStorage = loadFromStorage,
	LoadMaxFromStorage = loadMaxFromStorageFn,
	GetVehicleInfo = getVehicleInfoFn,
	GetBackpackCapacity = getBackpackCapacity,
	GetBackpackUsage = getBackpackUsage,
	GetBackpackSpace = getBackpackSpace,
	-- Persistence functions
	GetTransportData = getTransportData,
	SetTransportData = setTransportData,
	-- Constants
	CONFIG = CONFIG,
}
