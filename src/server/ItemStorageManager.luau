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

local GetStorageFunction = RemoteFunctions:FindFirstChild("GetStorage") or Instance.new("RemoteFunction")
GetStorageFunction.Name = "GetStorage"
GetStorageFunction.Parent = RemoteFunctions

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

local function recordAchievement(player, goalType, amount)
	local achievementManager = rawget(Services, "AchievementsManager")
	if achievementManager and achievementManager.RecordProgress then
		achievementManager.RecordProgress(player, goalType, amount)
	end
end

local function setAchievementProgress(player, goalType, absoluteValue)
	local achievementManager = rawget(Services, "AchievementsManager")
	if achievementManager and achievementManager.SetProgress then
		achievementManager.SetProgress(player, goalType, absoluteValue)
	else
		recordAchievement(player, goalType, absoluteValue)
	end
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

local function _isNearOwnStorage(player)
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

local function evaluateStorageAchievements(player, storage)
	if not storage then
		return
	end

	local total = getTotalItemCount(storage.items)
	if storage.capacity > 0 and total == storage.capacity then
		recordAchievement(player, "storage_full_exact", 1)
	end

	if not _ItemConfig or not _ItemConfig.GetSectorByItemId then
		return
	end

	local sectorTotals = {}
	for itemId, count in pairs(storage.items) do
		local sector = _ItemConfig.GetSectorByItemId(itemId)
		if sector then
			sectorTotals[sector] = (sectorTotals[sector] or 0) + count
		end
	end

	local qualifyingSectors = 0
	for _, count in pairs(sectorTotals) do
		if count >= 500 then
			qualifyingSectors += 1
		end
	end
	if qualifyingSectors >= 6 then
		setAchievementProgress(player, "diversified_storage_sectors", 1)
	end
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
					totalItems = getTotalItemCount(data or {}),
					capacity = currentCap,
					baseCapacity = baseCap
				}
			else
				PlayerStorage[player].items = data or {}
				PlayerStorage[player].totalItems = getTotalItemCount(data or {})
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

	-- Connect Remotes
	GetStorageFunction.OnServerInvoke = function(player)
		local s = PlayerStorage[player]
		if not s then return {}, 0, CONFIG.DEFAULT_STORAGE_CAPACITY end
		return encodeItems(s.items), getTotalItemCount(s.items), s.capacity
	end

	print("✓ ItemStorageManager Initialized")
end

--[[
	AddToStorage: Adds FactoryItems (production resources) to the player's storage silo.

	@param player Player - The player whose storage to add to
	@param itemId string - The FactoryItem ID (e.g. "ToiletPaper", "Plunger")
	@param count number - How many items to add
	@return number - The actual number of items added (may be less if storage is full)
]]
function ItemStorageManager.AddToStorage(player: Player, itemId: string, count: number, silent: boolean?): number
	if type(count) ~= "number" or count <= 0 then
		warn("ItemStorageManager.AddToStorage: Invalid count:", count)
		return 0
	end

	local storage = PlayerStorage[player]
	if not storage then return 0 end

	local current = storage.totalItems or getTotalItemCount(storage.items)
	local available = storage.capacity - current
	local toAdd = math.min(count, available)

	if toAdd <= 0 then return 0 end

	storage.items[itemId] = (storage.items[itemId] or 0) + toAdd
	storage.totalItems = current + toAdd

	if not silent then
		StorageUpdatedEvent:FireClient(player, encodeItems(storage.items), storage.totalItems, storage.capacity)
	end
	evaluateStorageAchievements(player, storage)
	return toAdd
end

function ItemStorageManager.IsStorageFull(player)
	local storage = PlayerStorage[player]
	if not storage then return true end

	local current = storage.totalItems or getTotalItemCount(storage.items)
	return current >= storage.capacity
end

--[[
	RemoveFromStorage: Removes items directly from storage (for Cart loading or Shop purchases).
]]
function ItemStorageManager.RemoveFromStorage(player, itemId, count)
	local storage = PlayerStorage[player]
	if not storage then return 0 end

	local inStorage = storage.items[itemId] or 0
	local toRemove = math.min(count, inStorage)
	if toRemove <= 0 then return 0 end

	storage.items[itemId] = inStorage - toRemove
	if storage.items[itemId] <= 0 then storage.items[itemId] = nil end

	if storage.totalItems then
		storage.totalItems = math.max(0, storage.totalItems - toRemove)
	else
		storage.totalItems = getTotalItemCount(storage.items)
	end

	StorageUpdatedEvent:FireClient(player, encodeItems(storage.items), storage.totalItems, storage.capacity)
	evaluateStorageAchievements(player, storage)
	return toRemove
end

-- Compatibility Exports
function ItemStorageManager.GetStorageContents(player)
	return PlayerStorage[player] and PlayerStorage[player].items or {}
end

function ItemStorageManager.GetStorageCapacity(player)
	return PlayerStorage[player] and PlayerStorage[player].capacity or CONFIG.DEFAULT_STORAGE_CAPACITY
end

function ItemStorageManager.SetStorageCapacity(player, cap)
	if not PlayerStorage[player] then PlayerStorage[player] = { items={}, totalItems=0, capacity=cap, baseCapacity=cap } end
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
	evaluateStorageAchievements(player, storage)
end

function ItemStorageManager.ResetPlayerStorage(player)
	if PlayerStorage[player] then
		PlayerStorage[player].items = {}
		PlayerStorage[player].capacity = CONFIG.DEFAULT_STORAGE_CAPACITY
		player:SetAttribute("StorageCapacity", CONFIG.DEFAULT_STORAGE_CAPACITY)
		StorageUpdatedEvent:FireClient(player, {}, 0, CONFIG.DEFAULT_STORAGE_CAPACITY)
	end

	-- Clear DataService components
	local ds = getDataService()
	if ds then
		ds.SetComponentData(player, "ItemStorage", {})
		ds.SetComponentData(player, "Backpack", {}) -- Clean up any stale data
	end
end

return ItemStorageManager
