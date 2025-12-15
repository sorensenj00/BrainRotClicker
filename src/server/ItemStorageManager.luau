--[[
	ItemStorageManager Server Module
	
	Manages item-based storage for the Sell a Brainrot system.
	
	CONVERTED TO MODULE SCRIPT
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataService = require(script.Parent.DataService)

-- Constants
local CONFIG = {
	DEFAULT_STORAGE_CAPACITY = 2000,
	BACKPACK_CAPACITY = 200,
	STORAGE_UPGRADES = {
		{capacity = 2000, cost = 0},
		{capacity = 10000, cost = 15000},
		{capacity = 50000, cost = 75000},
		{capacity = math.huge, cost = 0},
	},
}

-- Configs (Dynamically loaded to avoid cyclic issues if possible, or wait)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig -- Lazy loaded

-- State
local PlayerStorage = {} 
local PlayerBackpack = {}

-- Remotes
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not RemoteEvents then
	RemoteEvents = Instance.new("Folder")
	RemoteEvents.Name = "RemoteEvents"
	RemoteEvents.Parent = ReplicatedStorage
end

local StorageUpdatedEvent = RemoteEvents:FindFirstChild("StorageUpdated") or Instance.new("RemoteEvent")
StorageUpdatedEvent.Name = "StorageUpdated"
StorageUpdatedEvent.Parent = RemoteEvents

local BackpackUpdatedEvent = RemoteEvents:FindFirstChild("BackpackUpdated") or Instance.new("RemoteEvent")
BackpackUpdatedEvent.Name = "BackpackUpdated"
BackpackUpdatedEvent.Parent = RemoteEvents

local GetStorageFunction = RemoteEvents:FindFirstChild("GetStorage") or Instance.new("RemoteFunction")
GetStorageFunction.Name = "GetStorage"
GetStorageFunction.Parent = RemoteEvents

local GetBackpackFunction = RemoteEvents:FindFirstChild("GetBackpack") or Instance.new("RemoteFunction")
GetBackpackFunction.Name = "GetBackpack"
GetBackpackFunction.Parent = RemoteEvents

local TakeFromStorageEvent = RemoteEvents:FindFirstChild("TakeFromStorage") or Instance.new("RemoteEvent")
TakeFromStorageEvent.Name = "TakeFromStorage"
TakeFromStorageEvent.Parent = RemoteEvents

-- Module
local ItemStorageManager = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getTotalItemCount(items)
	local total = 0
	if items then
		for _, count in pairs(items) do total += count end
	end
	return total
end

local function initializePlayer(player)
	local data = DataService.GetData(player)
	local items = {}
	local capacity = CONFIG.DEFAULT_STORAGE_CAPACITY
	local backpackItems = {}
	
	if data then
		items = data.ItemStorage or {}
		capacity = data.storageCapacity or CONFIG.DEFAULT_STORAGE_CAPACITY
		backpackItems = data.Backpack or {}
	end
	
	PlayerStorage[player] = { items = items, capacity = capacity }
	PlayerBackpack[player] = { items = backpackItems, capacity = CONFIG.BACKPACK_CAPACITY }
end

local function syncStorage(player)
	local storage = PlayerStorage[player]
	if not storage then return end
	local data = DataService.GetData(player)
	if data then
		data.ItemStorage = storage.items
		data.storageCapacity = storage.capacity
	end
end

local function syncBackpack(player)
	local backpack = PlayerBackpack[player]
	if not backpack then return end
	local data = DataService.GetData(player)
	if data then
		data.Backpack = backpack.items
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function ItemStorageManager.Init()
	print("   ItemStorageManager (Module) - Initializing")
	
	-- Load Configs
	task.spawn(function()
		ItemConfig = require(Shared:WaitForChild("ItemConfig"))
	end)
	
	-- Register Events
	Players.PlayerAdded:Connect(function(player)
		-- Wait for Data to be ready
		task.spawn(function()
			local attempts = 0
			while not DataService.IsLoaded(player) and attempts < 100 do
				task.wait(0.1)
				attempts += 1
			end
			initializePlayer(player)
		end)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		PlayerStorage[player] = nil
		PlayerBackpack[player] = nil
	end)
	
	-- Connect Remotes
	GetStorageFunction.OnServerInvoke = function(player)
		local s = PlayerStorage[player]
		if not s then return {}, 0, CONFIG.DEFAULT_STORAGE_CAPACITY end
		return s.items, getTotalItemCount(s.items), s.capacity
	end
	GetBackpackFunction.OnServerInvoke = function(player)
		local b = PlayerBackpack[player]
		if not b then return {}, 0, CONFIG.BACKPACK_CAPACITY end
		return b.items, getTotalItemCount(b.items), b.capacity
	end
	
	TakeFromStorageEvent.OnServerEvent:Connect(function(player, itemId, count)
		if type(itemId) ~= "string" or type(count) ~= "number" then return end
		ItemStorageManager.TakeFromStorage(player, itemId, count)
	end)
	
	-- Init existing players
	for _, p in Players:GetPlayers() do
		initializePlayer(p)
	end
	
	print("✓ ItemStorageManager Initialized")
end

function ItemStorageManager.AddToStorage(player, itemId, count)
	local storage = PlayerStorage[player]
	if not storage then return 0 end
	
	local current = getTotalItemCount(storage.items)
	local available = storage.capacity - current
	local toAdd = math.min(count, available)
	
	if toAdd <= 0 then return 0 end
	
	storage.items[itemId] = (storage.items[itemId] or 0) + toAdd
	syncStorage(player)
	StorageUpdatedEvent:FireClient(player, storage.items, current + toAdd, storage.capacity)
	return toAdd
end

function ItemStorageManager.IsStorageFull(player)
	local storage = PlayerStorage[player]
	if not storage then return true end
	return getTotalItemCount(storage.items) >= storage.capacity
end

-- Export additional functions as needed...
-- For brevity, implementing Key functions.

function ItemStorageManager.TakeFromStorage(player, itemId, count)
	local storage = PlayerStorage[player]
	local backpack = PlayerBackpack[player]
	if not storage or not backpack then return 0 end
	
	local inStorage = storage.items[itemId] or 0
	local backSize = getTotalItemCount(backpack.items)
	local backSpace = backpack.capacity - backSize
	
	local amount = math.min(count, inStorage, backSpace)
	if amount <= 0 then return 0 end
	
	storage.items[itemId] = inStorage - amount
	if storage.items[itemId] <= 0 then storage.items[itemId] = nil end
	
	backpack.items[itemId] = (backpack.items[itemId] or 0) + amount
	
	syncStorage(player)
	syncBackpack(player)
	
	StorageUpdatedEvent:FireClient(player, storage.items, getTotalItemCount(storage.items), storage.capacity)
	BackpackUpdatedEvent:FireClient(player, backpack.items, getTotalItemCount(backpack.items), backpack.capacity)
	
	return amount
end

-- Map other required API methods used by legacy systems
ItemStorageManager.GetBackpackContents = function(player)
	return PlayerBackpack[player] and PlayerBackpack[player].items or {}
end
ItemStorageManager.GetStorageContents = function(player)
	return PlayerStorage[player] and PlayerStorage[player].items or {}
end
ItemStorageManager.GetStorageCapacity = function(player)
	return PlayerStorage[player] and PlayerStorage[player].capacity or 0
end

return ItemStorageManager
