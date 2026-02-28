--[[
	ItemStorageManager Server Module

	═══════════════════════════════════════════════════════════════════════════════
	              TRANSIENT PRODUCTION RESOURCES (SUPPLY CHAIN)
	═══════════════════════════════════════════════════════════════════════════════

	PURPOSE:
	  Manages the temporary "ProductionItems" (resources) that units produce.
	  These items sit in Storage (silos) until collected into Backpack, then
	  transported and sold by TransportManager.

	MANAGES:
	  • ProductionItems  - Resources produced by placed units (e.g., "Skibidi", "Sigma")
	  • Storage (Silos)  - Tycoon storage capacity for produced items
	  • Backpack         - Temporary carry capacity before selling

	DATA LIFECYCLE:
	  • ProductionItems are TRANSIENT - produced, stored, sold, and consumed
	  • Saved to profile for session continuity, but economically consumed
	  • Flow: Units → Storage → Backpack → Sell (via TransportManager)

	SUPPLY CHAIN INTEGRATION:
	  ← ItemProductionManager  - Adds items when units produce
	  → TransportManager       - Removes items when collected/sold
	  → MarketManager          - Determines sell prices

	═══════════════════════════════════════════════════════════════════════════════
	⚠️  DO NOT USE THIS FOR PERMANENT COLLECTION ASSETS:
	    Player-owned Units (Brainrots) and Artifacts belong in InventoryManager
	    and ArtifactManager respectively. Those are permanent collection items.
	═══════════════════════════════════════════════════════════════════════════════
]]

local _Players = game:GetService("Players") -- Reserved for future player cleanup
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataService -- Will be set from Services.DataService

-- Type Imports
local Shared = ReplicatedStorage:WaitForChild("Shared")
local _ItemTypes = require(Shared:WaitForChild("ItemTypes")) -- For type reference (see FactoryItem)

-- Strict Type Definitions for FactoryItems (transient production resources)
-- See ItemTypes.luau for full type: FactoryItem
-- This storage is for transient production items only. Do not store Units here.
export type ItemMap = {[string]: number}  -- Map of itemId -> count

-- Constants
local CONFIG = {
	DEFAULT_STORAGE_CAPACITY = 2000,
	BACKPACK_CAPACITY = 200,
}

-- Configs (loaded lazily)
local _ItemConfig -- Reserved for future item validation

-- State: Player storage holds FactoryItems (transient production resources)
-- NOT for BrainrotUnits (permanent assets) - those go in InventoryManager
local PlayerStorage: {[Player]: {items: ItemMap, capacity: number, baseCapacity: number}} = {}
local PlayerBackpack: {[Player]: {items: ItemMap, capacity: number}} = {}

-- Remotes
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local StorageUpdatedEvent = RemoteEvents:FindFirstChild("StorageUpdated") or Instance.new("RemoteEvent")
StorageUpdatedEvent.Name = "StorageUpdated"
StorageUpdatedEvent.Parent = RemoteEvents

local BackpackUpdatedEvent = RemoteEvents:FindFirstChild("BackpackUpdated") or Instance.new("RemoteEvent")
BackpackUpdatedEvent.Name = "BackpackUpdated"
BackpackUpdatedEvent.Parent = RemoteEvents

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

-- Getter for DataService (to avoid circular require)
local function getDataService()
	if not DataService then
		DataService = rawget(Services, "DataService")
	end
	return DataService
end

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

local function encodeItems(items)
	if not _ItemConfig or not _ItemConfig.ID_TO_SHORT then return items end
	local encoded = {}
	for itemId, count in pairs(items) do
		local shortId = _ItemConfig.ID_TO_SHORT[itemId]
		if shortId then
			encoded[tostring(shortId)] = count
		else
			encoded[itemId] = count
		end
	end
	return encoded
end

local function isNearOwnStorage(player)
	local character = player.Character
	if not character then return false end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return false end

	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if plot:GetAttribute("OwnerId") == player.UserId then
			local root = plot.PrimaryPart or plot:FindFirstChild("Root") or plot:FindFirstChild("MainPlatform") or plot:FindFirstChildWhichIsA("BasePart")
			if root and root:IsA("BasePart") then
				local playerPos = hrp.Position
				local plotPos = root.Position
				local dx = playerPos.X - plotPos.X
				local dz = playerPos.Z - plotPos.Z
				if dx*dx + dz*dz <= 70 * 70 then
					return true
				end
			end
		end
	end

	return false
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function ItemStorageManager.Init(services)
	print("   ItemStorageManager (Module) - Initializing")
	Services = services or {}

	-- Load Configs (reserved for item validation)
	task.spawn(function()
		local SharedFolder = ReplicatedStorage:WaitForChild("Shared")
		_ItemConfig = require(SharedFolder:WaitForChild("ItemConfig"))
	end)

	-- Register Data Handlers
	local ds = getDataService()
	if not ds then
		warn("ItemStorageManager: DataService not available during Init")
		return
	end

	ds.RegisterHandler("ItemStorage", {
		DefaultData = {},
		OnLoad = function(player, data)
			local root = ds.GetData(player)
			local baseCap = root and tonumber(root.baseStorageCapacity) or root and tonumber(root.storageCapacity) or CONFIG.DEFAULT_STORAGE_CAPACITY
			local currentCap = root and tonumber(root.storageCapacity) or CONFIG.DEFAULT_STORAGE_CAPACITY

			if not PlayerStorage[player] then
				PlayerStorage[player] = {
					items = data or {},
					capacity = currentCap,
					baseCapacity = baseCap
				}
			else
				PlayerStorage[player].items = data or {}
				PlayerStorage[player].capacity = currentCap
				PlayerStorage[player].baseCapacity = baseCap
			end

			-- Re-apply any global multipliers immediately on load
			ItemStorageManager.RefreshCapacity(player)
		end,
		OnSave = function(player, data)
			if PlayerStorage[player] then
				return PlayerStorage[player].items
			end
			return {}
		end,
		OnRelease = function(player)
			PlayerStorage[player] = nil
		end
	})

	ds.RegisterHandler("Backpack", {
		DefaultData = {},
		OnLoad = function(player, data)
			if not PlayerBackpack[player] then
				PlayerBackpack[player] = { items = {}, capacity = CONFIG.BACKPACK_CAPACITY }
			end
			PlayerBackpack[player].items = data or {}

			-- Sync attribute for UI
			player:SetAttribute("BackpackCapacity", PlayerBackpack[player].capacity)
		end,
		OnSave = function(player, data)
			if PlayerBackpack[player] then
				return PlayerBackpack[player].items
			end
			return {}
		end,
		OnRelease = function(player)
			PlayerBackpack[player] = nil
		end
	})

	-- Connect Remotes
	GetStorageFunction.OnServerInvoke = function(player)
		local s = PlayerStorage[player]
		if not s then return {}, 0, CONFIG.DEFAULT_STORAGE_CAPACITY end
		return encodeItems(s.items), getTotalItemCount(s.items), s.capacity
	end
	GetBackpackFunction.OnServerInvoke = function(player)
		local b = PlayerBackpack[player]
		if not b then return {}, 0, CONFIG.BACKPACK_CAPACITY end
		return encodeItems(b.items), getTotalItemCount(b.items), b.capacity
	end

	TakeFromStorageEvent.OnServerEvent:Connect(function(player, itemId, count)
		if type(itemId) == "table" then
			if not isNearOwnStorage(player) then return end
			for id, c in pairs(itemId) do
				if type(id) == "string" and type(c) == "number" then
					ItemStorageManager.TakeFromStorage(player, id, math.max(1, math.floor(c)))
				end
			end
		else
			if type(itemId) ~= "string" or type(count) ~= "number" then return end
			if not isNearOwnStorage(player) then return end
			ItemStorageManager.TakeFromStorage(player, itemId, math.max(1, math.floor(count)))
		end
	end)

	print("✓ ItemStorageManager Initialized")
end

--[[
	AddToStorage: Adds FactoryItems (production resources) to the player's storage silo.

	@param player Player - The player whose storage to add to
	@param itemId string - The FactoryItem ID (e.g. "ToiletPaper", "Plunger")
	@param count number - How many items to add
	@return number - The actual number of items added (may be less if storage is full)

	⚠️ WARNING: This is for FactoryItems ONLY (transient production resources).
	   Do NOT use this for BrainrotUnits (permanent collection assets).
	   BrainrotUnits should go to InventoryManager.AddUnit() instead.
]]
function ItemStorageManager.AddToStorage(player: Player, itemId: string, count: number, silent: boolean?): number
	-- GUARD: Reject if this looks like a BrainrotUnit (has level/rarity/unitId pattern)
	-- This catches accidental misuse of the wrong manager
	if type(itemId) == "table" then
		warn("ItemStorageManager.AddToStorage: Received table instead of itemId string!")
		warn("  If you're trying to add a BrainrotUnit, use InventoryManager.AddUnit() instead.")
		return 0
	end

	if type(count) ~= "number" or count <= 0 then
		warn("ItemStorageManager.AddToStorage: Invalid count:", count)
		return 0
	end

	local storage = PlayerStorage[player]
	if not storage then return 0 end

	local current = getTotalItemCount(storage.items)
	local available = storage.capacity - current
	local toAdd = math.min(count, available)

	if toAdd <= 0 then return 0 end

	storage.items[itemId] = (storage.items[itemId] or 0) + toAdd

	if not silent then
		StorageUpdatedEvent:FireClient(player, encodeItems(storage.items), current + toAdd, storage.capacity)
	end
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

	StorageUpdatedEvent:FireClient(player, encodeItems(storage.items), getTotalItemCount(storage.items), storage.capacity)
	BackpackUpdatedEvent:FireClient(player, encodeItems(backpack.items), getTotalItemCount(backpack.items), backpack.capacity)

	return amount
end

--[[
	RemoveFromStorage: Removes items directly from storage (for Cart loading).
	Does NOT add to backpack.
]]
function ItemStorageManager.RemoveFromStorage(player, itemId, count)
	local storage = PlayerStorage[player]
	if not storage then return 0 end

	local inStorage = storage.items[itemId] or 0
	local toRemove = math.min(count, inStorage)
	if toRemove <= 0 then return 0 end

	storage.items[itemId] = inStorage - toRemove
	if storage.items[itemId] <= 0 then storage.items[itemId] = nil end

	StorageUpdatedEvent:FireClient(player, encodeItems(storage.items), getTotalItemCount(storage.items), storage.capacity)
	return toRemove
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
	player:SetAttribute("BackpackCapacity", cap)
	BackpackUpdatedEvent:FireClient(player, encodeItems(PlayerBackpack[player].items), getTotalItemCount(PlayerBackpack[player].items), cap)
end

function ItemStorageManager.SetStorageCapacity(player, cap)
	if not PlayerStorage[player] then PlayerStorage[player] = { items={}, capacity=cap, baseCapacity=cap } end
	PlayerStorage[player].baseCapacity = cap

	ItemStorageManager.RefreshCapacity(player)
end

function ItemStorageManager.RefreshCapacity(player)
	local storage = PlayerStorage[player]
	if not storage then return end

	local BonusManager = rawget(Services, "BonusManager")
	local multi = 1.0
	if BonusManager and BonusManager.GetTotalStorageMultiplier then
		multi = BonusManager.GetTotalStorageMultiplier(player)
	end

	local newCap = math.floor(storage.baseCapacity * multi)
	storage.capacity = newCap

	player:SetAttribute("StorageCapacity", newCap)
	player:SetAttribute("BaseStorageCapacity", storage.baseCapacity)

	local ds = getDataService()
	if ds then
		ds.SetComponentData(player, "storageCapacity", newCap)
		ds.SetComponentData(player, "baseStorageCapacity", storage.baseCapacity)
	end

	StorageUpdatedEvent:FireClient(player, encodeItems(storage.items), getTotalItemCount(storage.items), newCap)
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

	BackpackUpdatedEvent:FireClient(player, encodeItems(backpack.items), getTotalItemCount(backpack.items), backpack.capacity)
	return toRemove
end

--[[
	AddToBackpack: Directly adds items to the player's backpack (bypassing storage).
	Used for buy-to-backpack flows where items don't need to go through the silo.

	@param player Player - The player whose backpack to add to
	@param itemId string - The item ID to add
	@param count number - How many items to add
	@return number - The actual number of items added (may be less if backpack is full)
]]
function ItemStorageManager.AddToBackpack(player: Player, itemId: string, count: number): number
	local backpack = PlayerBackpack[player]
	if not backpack then return 0 end

	if type(count) ~= "number" or count <= 0 then return 0 end

	local currentSize = getTotalItemCount(backpack.items)
	local available = backpack.capacity - currentSize
	local toAdd = math.min(math.floor(count), available)

	if toAdd <= 0 then return 0 end

	backpack.items[itemId] = (backpack.items[itemId] or 0) + toAdd

	BackpackUpdatedEvent:FireClient(player, encodeItems(backpack.items), getTotalItemCount(backpack.items), backpack.capacity)
	return toAdd
end

function ItemStorageManager.ResetPlayerStorage(player)
	if PlayerStorage[player] then
		PlayerStorage[player].items = {}
		PlayerStorage[player].capacity = CONFIG.DEFAULT_STORAGE_CAPACITY
		player:SetAttribute("StorageCapacity", CONFIG.DEFAULT_STORAGE_CAPACITY)
		StorageUpdatedEvent:FireClient(player, {}, 0, CONFIG.DEFAULT_STORAGE_CAPACITY)
	end
	if PlayerBackpack[player] then
		PlayerBackpack[player].items = {}
		PlayerBackpack[player].capacity = CONFIG.BACKPACK_CAPACITY
		player:SetAttribute("BackpackCapacity", CONFIG.BACKPACK_CAPACITY)
		BackpackUpdatedEvent:FireClient(player, {}, 0, CONFIG.BACKPACK_CAPACITY)
	end

	-- Clear DataService components
	local ds = getDataService()
	if ds then
		ds.SetComponentData(player, "ItemStorage", {})
		ds.SetComponentData(player, "Backpack", {})
	end
end

return ItemStorageManager
