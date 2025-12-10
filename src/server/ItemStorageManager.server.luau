--[[
	ItemStorageManager Server Script
	
	Manages item-based storage for the Sell a Brainrot system.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Config
local CONFIG = {
	DEFAULT_STORAGE_CAPACITY = 2000,
	BACKPACK_CAPACITY = 200,
}

-- State
local PlayerStorage = {} -- { [Player] = { items = {}, capacity = number } }
local PlayerBackpack = {} -- { [Player] = { items = {}, capacity = number } }

-- Remotes
local function getRemote(name, class, parent)
	local r = parent:FindFirstChild(name) or Instance.new(class)
	r.Name = name
	r.Parent = parent
	return r
end

local RE = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder", ReplicatedStorage)
RE.Name = "RemoteEvents"
local RF = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder", ReplicatedStorage)
RF.Name = "RemoteFunctions"

local StorageUpdatedEvent = getRemote("StorageUpdated", "RemoteEvent", RE)
local BackpackUpdatedEvent = getRemote("BackpackUpdated", "RemoteEvent", RE)
local GetStorageFunction = getRemote("GetStorage", "RemoteFunction", RF)
local GetBackpackFunction = getRemote("GetBackpack", "RemoteFunction", RF)

-- Helper: Get Total
local function getTotal(items)
	local t = 0
	for _, c in pairs(items) do t += c end
	return t
end

-- Init
local function initPlayer(player, saved)
	saved = saved or {}
	PlayerStorage[player] = {
		items = saved.itemStorage or {},
		capacity = saved.storageCapacity or CONFIG.DEFAULT_STORAGE_CAPACITY
	}
	PlayerBackpack[player] = {
		items = saved.backpack or {},
		capacity = CONFIG.BACKPACK_CAPACITY
	}
end

-- Operations (Shared)
local function updateContainer(player, containerType, items, capacity, event)
	event:FireClient(player, items, getTotal(items), capacity)
end

local function add(player, isBackpack, itemId, count)
	local container = isBackpack and PlayerBackpack[player] or PlayerStorage[player]
	local event = isBackpack and BackpackUpdatedEvent or StorageUpdatedEvent
	
	if not container then return 0 end
	local space = container.capacity - getTotal(container.items)
	local amount = math.min(count, space)
	if amount <= 0 then return 0 end
	
	container.items[itemId] = (container.items[itemId] or 0) + amount
	updateContainer(player, nil, container.items, container.capacity, event)
	return amount
end

local function remove(player, isBackpack, itemId, count)
	local container = isBackpack and PlayerBackpack[player] or PlayerStorage[player]
	local event = isBackpack and BackpackUpdatedEvent or StorageUpdatedEvent
	
	if not container then return 0 end
	local current = container.items[itemId] or 0
	local amount = math.min(count, current)
	if amount <= 0 then return 0 end
	
	container.items[itemId] = current - amount
	if container.items[itemId] <= 0 then container.items[itemId] = nil end
	updateContainer(player, nil, container.items, container.capacity, event)
	return amount
end

-- Transfer
local function transfer(player, fromBackpack, itemId, count)
	local src = fromBackpack and PlayerBackpack[player] or PlayerStorage[player]
	local dst = fromBackpack and PlayerStorage[player] or PlayerBackpack[player]
	
	if not src or not dst then return 0 end
	
	local avail = src.items[itemId] or 0
	local space = dst.capacity - getTotal(dst.items)
	local amount = math.min(count, avail, space)
	
	if amount > 0 then
		remove(player, fromBackpack, itemId, amount)
		add(player, not fromBackpack, itemId, amount)
	end
	return amount
end

local function takeMax(player)
	local s = PlayerStorage[player]
	local b = PlayerBackpack[player]
	if not s or not b then return 0 end
	
	local transferred = 0
	for id, count in pairs(s.items) do
		local amt = transfer(player, false, id, count)
		transferred += amt
		if getTotal(b.items) >= b.capacity then break end
	end
	return transferred
end

-- Handlers
GetStorageFunction.OnServerInvoke = function(p)
	local s = PlayerStorage[p]
	return s and s.items or {}, s and getTotal(s.items) or 0, s and s.capacity or CONFIG.DEFAULT_STORAGE_CAPACITY
end

GetBackpackFunction.OnServerInvoke = function(p)
	local b = PlayerBackpack[p]
	return b and b.items or {}, b and getTotal(b.items) or 0, b and b.capacity or CONFIG.BACKPACK_CAPACITY
end

-- Lifecycle
Players.PlayerAdded:Connect(function(player)
	task.wait(1)
	local saved = _G.DataManager and _G.DataManager.GetCachedData(player)
	initPlayer(player, saved)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerStorage[player] = nil
	PlayerBackpack[player] = nil
end)

for _, p in Players:GetPlayers() do task.spawn(function() initPlayer(p) end) end

-- API
_G.ItemStorageManager = {
	AddToStorage = function(p, i, c) return add(p, false, i, c) end,
	RemoveFromStorage = function(p, i, c) return remove(p, false, i, c) end,
	GetStorageContents = function(p) return PlayerStorage[p] and PlayerStorage[p].items or {} end,
	GetStorageCapacity = function(p) return PlayerStorage[p] and PlayerStorage[p].capacity or CONFIG.DEFAULT_STORAGE_CAPACITY end,
	SetStorageCapacity = function(p, c)
		if PlayerStorage[p] then
			PlayerStorage[p].capacity = c
			updateContainer(p, nil, PlayerStorage[p].items, c, StorageUpdatedEvent)
		end
	end,
	IsStorageFull = function(p) return PlayerStorage[p] and getTotal(PlayerStorage[p].items) >= PlayerStorage[p].capacity end,

	AddToBackpack = function(p, i, c) return add(p, true, i, c) end,
	RemoveFromBackpack = function(p, i, c) return remove(p, true, i, c) end,
	GetBackpackContents = function(p) return PlayerBackpack[p] and PlayerBackpack[p].items or {} end,
	GetBackpackCapacity = function(p) return PlayerBackpack[p] and PlayerBackpack[p].capacity or CONFIG.BACKPACK_CAPACITY end,
	IsBackpackFull = function(p) return PlayerBackpack[p] and getTotal(PlayerBackpack[p].items) >= PlayerBackpack[p].capacity end,
	SetBackpackCapacity = function(p, c)
		if PlayerBackpack[p] then
			PlayerBackpack[p].capacity = c
			updateContainer(p, nil, PlayerBackpack[p].items, c, BackpackUpdatedEvent)
		end
	end,
	
	TakeFromStorage = function(p, i, c) return transfer(p, false, i, c) end,
	DepositToStorage = function(p, i, c) return transfer(p, true, i, c) end,
	TakeMaxFromStorage = takeMax,
	TransferToBackpack = function(p, i, c) return transfer(p, false, i, c) end,
	
	GetTotalItemCount = getTotal
}

print("✓ ItemStorageManager Initialized")
