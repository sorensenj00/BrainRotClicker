--[[
	ItemStorageManager Server Module
	
	Manages item-based storage for the Sell a Brainrot system.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataService = require(script.Parent.DataService)

-- Constants
local CONFIG = {
	DEFAULT_STORAGE_CAPACITY = 2000,
	BACKPACK_CAPACITY = 200,
}

-- Configs
local ItemConfig

-- State
local PlayerStorage = {} 
local PlayerBackpack = {}

-- Remotes
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local StorageUpdatedEvent = RemoteEvents:FindFirstChild("StorageUpdated") or Instance.new("RemoteEvent")
StorageUpdatedEvent.Name = "StorageUpdated"
StorageUpdatedEvent.Parent = ReplicatedStorage

local BackpackUpdatedEvent = RemoteEvents:FindFirstChild("BackpackUpdated") or Instance.new("RemoteEvent")
BackpackUpdatedEvent.Name = "BackpackUpdated"
BackpackUpdatedEvent.Parent = ReplicatedStorage

local GetStorageFunction = RemoteFunctions:FindFirstChild("GetStorage") or Instance.new("RemoteFunction")
GetStorageFunction.Name = "GetStorage"
GetStorageFunction.Parent = RemoteFunctions

local GetBackpackFunction = RemoteFunctions:FindFirstChild("GetBackpack") or Instance.new("RemoteFunction")
GetBackpackFunction.Name = "GetBackpack"
GetBackpackFunction.Parent = RemoteFunctions

local TakeFromStorageEvent = RemoteEvents:FindFirstChild("TakeFromStorage") or Instance.new("RemoteEvent")
TakeFromStorageEvent.Name = "TakeFromStorage"
TakeFromStorageEvent.Parent = RemoteEvents

-- Module
local ItemStorageManager = {}
local Services = {}

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

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function ItemStorageManager.Init(services)
	print("   ItemStorageManager (Module) - Initializing")
	Services = services or {}
	
	-- Load Configs
	task.spawn(function()
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		ItemConfig = require(Shared:WaitForChild("ItemConfig"))
	end)
	
	-- Register Data Handlers
	DataService.RegisterHandler("ItemStorage", {
		DefaultData = {},
		OnLoad = function(player, data)
			if not PlayerStorage[player] then
				PlayerStorage[player] = { items = {}, capacity = CONFIG.DEFAULT_STORAGE_CAPACITY }
			end
			PlayerStorage[player].items = data or {}
			
			local root = DataService.GetData(player)
			if root and root.storageCapacity then
				PlayerStorage[player].capacity = root.storageCapacity
			end
		end,
		OnSave = function(player, data)
			if PlayerStorage[player] then
				return PlayerStorage[player].items
			end
			return {}
		end
	})
	
	DataService.RegisterHandler("Backpack", {
		DefaultData = {},
		OnLoad = function(player, data)
			if not PlayerBackpack[player] then
				PlayerBackpack[player] = { items = {}, capacity = CONFIG.BACKPACK_CAPACITY }
			end
			PlayerBackpack[player].items = data or {}
		end,
		OnSave = function(player, data)
			if PlayerBackpack[player] then
				return PlayerBackpack[player].items
			end
			return {}
		end
	})
	
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
	StorageUpdatedEvent:FireClient(player, storage.items, current + toAdd, storage.capacity)
	return toAdd
end

function ItemStorageManager.IsStorageFull(player)
	local storage = PlayerStorage[player]
	if not storage then return true end
	return getTotalItemCount(storage.items) >= storage.capacity
end

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
	
	StorageUpdatedEvent:FireClient(player, storage.items, getTotalItemCount(storage.items), storage.capacity)
	BackpackUpdatedEvent:FireClient(player, backpack.items, getTotalItemCount(backpack.items), backpack.capacity)
	
	return amount
end

-- Compatibility Exports
function ItemStorageManager.GetBackpackContents(player)
	return PlayerBackpack[player] and PlayerBackpack[player].items or {}
end

function ItemStorageManager.GetStorageContents(player)
	return PlayerStorage[player] and PlayerStorage[player].items or {}
end

function ItemStorageManager.GetStorageCapacity(player)
	return PlayerStorage[player] and PlayerStorage[player].capacity or CONFIG.DEFAULT_STORAGE_CAPACITY
end

function ItemStorageManager.SetBackpackCapacity(player, cap)
	if not PlayerBackpack[player] then PlayerBackpack[player] = { items={}, capacity=cap} end
	PlayerBackpack[player].capacity = cap
	BackpackUpdatedEvent:FireClient(player, PlayerBackpack[player].items, getTotalItemCount(PlayerBackpack[player].items), cap)
end

function ItemStorageManager.SetStorageCapacity(player, cap)
	if not PlayerStorage[player] then PlayerStorage[player] = { items={}, capacity=cap} end
	PlayerStorage[player].capacity = cap

	-- Update DataService root if needed (legacy capacity storage)
	DataService.SetComponentData(player, "storageCapacity", cap)

	StorageUpdatedEvent:FireClient(player, PlayerStorage[player].items, getTotalItemCount(PlayerStorage[player].items), cap)
end

function ItemStorageManager.TransferToBackpack(player, itemId, count)
	-- Alias for TakeFromStorage used by TransportManager
	return ItemStorageManager.TakeFromStorage(player, itemId, count)
end

function ItemStorageManager.RemoveFromBackpack(player, itemId, count)
	local backpack = PlayerBackpack[player]
	if not backpack then return 0 end

	local avail = backpack.items[itemId] or 0
	local toRemove = math.min(count, avail)
	if toRemove <= 0 then return 0 end

	backpack.items[itemId] = avail - toRemove
	if backpack.items[itemId] <= 0 then backpack.items[itemId] = nil end

	BackpackUpdatedEvent:FireClient(player, backpack.items, getTotalItemCount(backpack.items), backpack.capacity)
	return toRemove
end

return ItemStorageManager
