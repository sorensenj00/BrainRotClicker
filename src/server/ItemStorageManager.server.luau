--[[
	ItemStorageManager Server Script
	
	Manages item-based storage for the Sell a Brainrot system.
	
	Features:
	- Item storage on player plots (replaces money storage)
	- Backpack system for transporting items
	- Storage capacity limits and upgrades
	- Take/deposit operations
	
	Storage format: { [itemId] = count }
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Constants
local CONFIG = {
	DEFAULT_STORAGE_CAPACITY = 2000,
	BACKPACK_CAPACITY = 200,
	
	-- Storage upgrade costs
	STORAGE_UPGRADES = {
		{capacity = 2000, cost = 0},       -- Base
		{capacity = 10000, cost = 15000},  -- Upgrade 1
		{capacity = 50000, cost = 75000},  -- Upgrade 2
		{capacity = math.huge, cost = 0},  -- Prestige (unlimited)
	},
}

-- Player data storage
local PlayerStorage = {} -- { [Player] = { items = {}, capacity = number } }
local PlayerBackpack = {} -- { [Player] = { items = {}, capacity = number } }

-- Remote events for client communication
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not RemoteEvents then
	RemoteEvents = Instance.new("Folder")
	RemoteEvents.Name = "RemoteEvents"
	RemoteEvents.Parent = ReplicatedStorage
end

-- Create remote events for item storage
local StorageUpdatedEvent = RemoteEvents:FindFirstChild("StorageUpdated") or Instance.new("RemoteEvent")
StorageUpdatedEvent.Name = "StorageUpdated"
StorageUpdatedEvent.Parent = RemoteEvents

local BackpackUpdatedEvent = RemoteEvents:FindFirstChild("BackpackUpdated") or Instance.new("RemoteEvent")
BackpackUpdatedEvent.Name = "BackpackUpdated"
BackpackUpdatedEvent.Parent = RemoteEvents

-- Create remote functions for client queries
local GetStorageFunction = RemoteEvents:FindFirstChild("GetStorage") or Instance.new("RemoteFunction")
GetStorageFunction.Name = "GetStorage"
GetStorageFunction.Parent = RemoteEvents

local GetBackpackFunction = RemoteEvents:FindFirstChild("GetBackpack") or Instance.new("RemoteFunction")
GetBackpackFunction.Name = "GetBackpack"
GetBackpackFunction.Parent = RemoteEvents

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Calculates total item count in a storage table.
	@param items table - The items dictionary
	@return number - Total count of all items
]]
local function getTotalItemCount(items)
	local total = 0
	for _, count in pairs(items) do
		total = total + count
	end
	return total
end

--[[
	Initializes storage for a player.
	@param player Player - The player to initialize
	@param savedData table? - Optional saved data to restore
]]
local function initializePlayer(player, savedData)
	local capacity = CONFIG.DEFAULT_STORAGE_CAPACITY
	local items = {}
	local backpackItems = {}
	
	if savedData then
		items = savedData.itemStorage or {}
		backpackItems = savedData.backpack or {}
		capacity = savedData.storageCapacity or CONFIG.DEFAULT_STORAGE_CAPACITY
	end
	
	PlayerStorage[player] = {
		items = items,
		capacity = capacity,
	}
	
	PlayerBackpack[player] = {
		items = backpackItems,
		capacity = CONFIG.BACKPACK_CAPACITY,
	}
	
	print(string.format("✓ ItemStorageManager: Initialized for %s (Storage: %d items, Backpack: %d items)", 
		player.Name, getTotalItemCount(items), getTotalItemCount(backpackItems)))
end

--[[
	Cleans up storage for a player.
	@param player Player - The player to clean up
]]
local function cleanupPlayer(player)
	PlayerStorage[player] = nil
	PlayerBackpack[player] = nil
end

--------------------------------------------------------------------------------
-- STORAGE OPERATIONS
--------------------------------------------------------------------------------

--[[
	Adds items to a player's storage.
	@param player Player - The player
	@param itemId string - The item ID to add
	@param count number - How many to add
	@return number - How many were actually added (may be less if at capacity)
]]
local function addToStorage(player, itemId, count)
	local storage = PlayerStorage[player]
	if not storage then return 0 end
	
	local currentTotal = getTotalItemCount(storage.items)
	local spaceAvailable = storage.capacity - currentTotal
	local actualAdd = math.min(count, spaceAvailable)
	
	if actualAdd <= 0 then
		-- Storage is full
		return 0
	end
	
	storage.items[itemId] = (storage.items[itemId] or 0) + actualAdd
	
	-- Notify client
	StorageUpdatedEvent:FireClient(player, storage.items, currentTotal + actualAdd, storage.capacity)
	
	return actualAdd
end

--[[
	Removes items from a player's storage.
	@param player Player - The player
	@param itemId string - The item ID to remove
	@param count number - How many to remove
	@return number - How many were actually removed
]]
local function removeFromStorage(player, itemId, count)
	local storage = PlayerStorage[player]
	if not storage then return 0 end
	
	local currentCount = storage.items[itemId] or 0
	local actualRemove = math.min(count, currentCount)
	
	if actualRemove <= 0 then return 0 end
	
	storage.items[itemId] = currentCount - actualRemove
	if storage.items[itemId] <= 0 then
		storage.items[itemId] = nil
	end
	
	-- Notify client
	local newTotal = getTotalItemCount(storage.items)
	StorageUpdatedEvent:FireClient(player, storage.items, newTotal, storage.capacity)
	
	return actualRemove
end

--[[
	Gets the contents of a player's storage.
	@param player Player - The player
	@return table - Items dictionary { [itemId] = count }
]]
local function getStorageContents(player)
	local storage = PlayerStorage[player]
	if not storage then return {} end
	return storage.items
end

--[[
	Gets the storage capacity for a player.
	@param player Player - The player
	@return number - Current storage capacity
]]
local function getStorageCapacity(player)
	local storage = PlayerStorage[player]
	if not storage then return CONFIG.DEFAULT_STORAGE_CAPACITY end
	return storage.capacity
end

--[[
	Sets the storage capacity for a player (for upgrades).
	@param player Player - The player
	@param capacity number - New capacity
]]
local function setStorageCapacity(player, capacity)
	local storage = PlayerStorage[player]
	if not storage then return end
	storage.capacity = capacity
	
	-- Notify client
	local currentTotal = getTotalItemCount(storage.items)
	StorageUpdatedEvent:FireClient(player, storage.items, currentTotal, capacity)
end

--[[
	Checks if storage is full.
	@param player Player - The player
	@return boolean - True if storage is at capacity
]]
local function isStorageFull(player)
	local storage = PlayerStorage[player]
	if not storage then return true end
	return getTotalItemCount(storage.items) >= storage.capacity
end

--------------------------------------------------------------------------------
-- BACKPACK OPERATIONS
--------------------------------------------------------------------------------

--[[
	Adds items to a player's backpack.
	@param player Player - The player
	@param itemId string - The item ID to add
	@param count number - How many to add
	@return number - How many were actually added
]]
local function addToBackpack(player, itemId, count)
	local backpack = PlayerBackpack[player]
	if not backpack then return 0 end
	
	local currentTotal = getTotalItemCount(backpack.items)
	local spaceAvailable = backpack.capacity - currentTotal
	local actualAdd = math.min(count, spaceAvailable)
	
	if actualAdd <= 0 then return 0 end
	
	backpack.items[itemId] = (backpack.items[itemId] or 0) + actualAdd
	
	-- Notify client
	BackpackUpdatedEvent:FireClient(player, backpack.items, currentTotal + actualAdd, backpack.capacity)
	
	return actualAdd
end

--[[
	Removes items from a player's backpack.
	@param player Player - The player
	@param itemId string - The item ID to remove
	@param count number - How many to remove
	@return number - How many were actually removed
]]
local function removeFromBackpack(player, itemId, count)
	local backpack = PlayerBackpack[player]
	if not backpack then return 0 end
	
	local currentCount = backpack.items[itemId] or 0
	local actualRemove = math.min(count, currentCount)
	
	if actualRemove <= 0 then return 0 end
	
	backpack.items[itemId] = currentCount - actualRemove
	if backpack.items[itemId] <= 0 then
		backpack.items[itemId] = nil
	end
	
	-- Notify client
	local newTotal = getTotalItemCount(backpack.items)
	BackpackUpdatedEvent:FireClient(player, backpack.items, newTotal, backpack.capacity)
	
	return actualRemove
end

--[[
	Gets the contents of a player's backpack.
	@param player Player - The player
	@return table - Items dictionary { [itemId] = count }
]]
local function getBackpackContents(player)
	local backpack = PlayerBackpack[player]
	if not backpack then return {} end
	return backpack.items
end

--[[
	Gets the backpack capacity for a player.
	@param player Player - The player
	@return number - Backpack capacity
]]
local function getBackpackCapacity(player)
	local backpack = PlayerBackpack[player]
	if not backpack then return CONFIG.BACKPACK_CAPACITY end
	return backpack.capacity
end

--[[
	Sets the backpack capacity for a player (used by TransportManager for vehicle capacities).
	@param player Player - The player
	@param capacity number - New capacity
]]
local function setBackpackCapacity(player, capacity)
	local backpack = PlayerBackpack[player]
	if not backpack then return end
	backpack.capacity = capacity
	
	-- Notify client
	local currentTotal = getTotalItemCount(backpack.items)
	BackpackUpdatedEvent:FireClient(player, backpack.items, currentTotal, capacity)
end

--[[
	Checks if backpack is full.
	@param player Player - The player
	@return boolean - True if backpack is at capacity
]]
local function isBackpackFull(player)
	local backpack = PlayerBackpack[player]
	if not backpack then return true end
	return getTotalItemCount(backpack.items) >= backpack.capacity
end

--------------------------------------------------------------------------------
-- TRANSFER OPERATIONS
--------------------------------------------------------------------------------

--[[
	Transfers items from storage to backpack.
	@param player Player - The player
	@param itemId string - The item ID to transfer
	@param count number - How many to transfer
	@return number - How many were actually transferred
]]
local function takeFromStorage(player, itemId, count)
	local storage = PlayerStorage[player]
	local backpack = PlayerBackpack[player]
	if not storage or not backpack then return 0 end
	
	-- Check how many are available in storage
	local availableInStorage = storage.items[itemId] or 0
	if availableInStorage <= 0 then return 0 end
	
	-- Check how much space is in backpack
	local backpackTotal = getTotalItemCount(backpack.items)
	local backpackSpace = backpack.capacity - backpackTotal
	if backpackSpace <= 0 then return 0 end
	
	-- Calculate actual transfer amount
	local actualTransfer = math.min(count, availableInStorage, backpackSpace)
	
	-- Perform transfer
	removeFromStorage(player, itemId, actualTransfer)
	addToBackpack(player, itemId, actualTransfer)
	
	return actualTransfer
end

--[[
	Transfers all valuable items from storage to backpack ("Take Max").
	Prioritizes higher-value items.
	@param player Player - The player
	@return number - Total items transferred
]]
local function takeMaxFromStorage(player)
	local storage = PlayerStorage[player]
	local backpack = PlayerBackpack[player]
	if not storage or not backpack then return 0 end
	
	-- Get ItemConfig for price sorting
	local ItemConfig
	pcall(function()
		ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
	end)
	
	-- Sort items by value (highest first)
	local sortedItems = {}
	for itemId, count in pairs(storage.items) do
		local price = 1  -- Default price
		if ItemConfig and ItemConfig.Items[itemId] then
			price = ItemConfig.Items[itemId].basePrice or 1
		end
		table.insert(sortedItems, {itemId = itemId, count = count, price = price})
	end
	table.sort(sortedItems, function(a, b) return a.price > b.price end)
	
	-- Fill backpack with highest value items
	local totalTransferred = 0
	local backpackSpace = backpack.capacity - getTotalItemCount(backpack.items)
	
	for _, itemData in ipairs(sortedItems) do
		if backpackSpace <= 0 then break end
		
		local toTransfer = math.min(itemData.count, backpackSpace)
		if toTransfer > 0 then
			removeFromStorage(player, itemData.itemId, toTransfer)
			addToBackpack(player, itemData.itemId, toTransfer)
			totalTransferred = totalTransferred + toTransfer
			backpackSpace = backpackSpace - toTransfer
		end
	end
	
	return totalTransferred
end

--[[
	Deposits items from backpack back to storage.
	@param player Player - The player
	@param itemId string - The item ID to deposit
	@param count number - How many to deposit
	@return number - How many were actually deposited
]]
local function depositToStorage(player, itemId, count)
	local backpack = PlayerBackpack[player]
	local storage = PlayerStorage[player]
	if not backpack or not storage then return 0 end
	
	-- Check how many are in backpack
	local availableInBackpack = backpack.items[itemId] or 0
	if availableInBackpack <= 0 then return 0 end
	
	-- Check storage space
	local storageTotal = getTotalItemCount(storage.items)
	local storageSpace = storage.capacity - storageTotal
	if storageSpace <= 0 then return 0 end
	
	-- Calculate actual transfer
	local actualTransfer = math.min(count, availableInBackpack, storageSpace)
	
	-- Perform transfer
	removeFromBackpack(player, itemId, actualTransfer)
	addToStorage(player, itemId, actualTransfer)
	
	return actualTransfer
end

--------------------------------------------------------------------------------
-- REMOTE FUNCTION HANDLERS
--------------------------------------------------------------------------------

GetStorageFunction.OnServerInvoke = function(player)
	local storage = PlayerStorage[player]
	if not storage then return {}, 0, CONFIG.DEFAULT_STORAGE_CAPACITY end
	return storage.items, getTotalItemCount(storage.items), storage.capacity
end

GetBackpackFunction.OnServerInvoke = function(player)
	local backpack = PlayerBackpack[player]
	if not backpack then return {}, 0, CONFIG.BACKPACK_CAPACITY end
	return backpack.items, getTotalItemCount(backpack.items), backpack.capacity
end

--------------------------------------------------------------------------------
-- PLAYER EVENTS
--------------------------------------------------------------------------------

-- Wait for DataManager to load player data
local function onPlayerAdded(player)
	-- Wait a bit for DataManager to load data
	task.wait(1.5)
	
	-- Check if DataManager has cached data
	local savedData = nil
	if _G.DataManager and _G.DataManager.GetCachedData then
		savedData = _G.DataManager.GetCachedData(player)
	end
	
	initializePlayer(player, savedData)
end

local function onPlayerRemoving(player)
	cleanupPlayer(player)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   ItemStorageManager - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Connect player events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	-- Handle existing players
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	
	print("✓ ItemStorageManager initialized")
	print("  • Storage capacity: " .. CONFIG.DEFAULT_STORAGE_CAPACITY)
	print("  • Backpack capacity: " .. CONFIG.BACKPACK_CAPACITY)
	print("═══════════════════════════════════════════")
end

initialize()

-- Export API for other scripts
_G.ItemStorageManager = {
	-- Storage operations
	AddToStorage = addToStorage,
	RemoveFromStorage = removeFromStorage,
	GetStorageContents = getStorageContents,
	GetStorageCapacity = getStorageCapacity,
	SetStorageCapacity = setStorageCapacity,
	IsStorageFull = isStorageFull,
	
	-- Backpack operations
	AddToBackpack = addToBackpack,
	RemoveFromBackpack = removeFromBackpack,
	GetBackpackContents = getBackpackContents,
	GetBackpackCapacity = getBackpackCapacity,
	IsBackpackFull = isBackpackFull,
	
	-- Transfer operations
	TakeFromStorage = takeFromStorage,
	TakeMaxFromStorage = takeMaxFromStorage,
	DepositToStorage = depositToStorage,
	TransferToBackpack = takeFromStorage,  -- Alias for TransportManager
	
	-- Capacity management
	SetBackpackCapacity = setBackpackCapacity,
	
	-- Utility
	GetTotalItemCount = getTotalItemCount,
}
