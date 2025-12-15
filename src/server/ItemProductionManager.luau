--[[
	ItemProductionManager Server Module
	
	Handles item production for the Sell a Brainrot system.
	
	PERFORMANCE FIX:
	- Caches active unit counts to avoid O(N^2) loop.
	- Uses InventoryManager events to update cache.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Lazy Configs
local ItemConfig, TileConfig, ArtifactConfig

local function loadConfigs()
	if not ItemConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		ItemConfig = require(Shared:WaitForChild("ItemConfig"))
		TileConfig = require(Shared:WaitForChild("TileConfig"))
		ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))
	end
end

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local ItemProducedEvent = RemoteEvents:FindFirstChild("ItemProduced") or Instance.new("RemoteEvent")
ItemProducedEvent.Name = "ItemProduced"
ItemProducedEvent.Parent = RemoteEvents

local StorageFullEvent = RemoteEvents:FindFirstChild("StorageFull") or Instance.new("RemoteEvent")
StorageFullEvent.Name = "StorageFull"
StorageFullEvent.Parent = RemoteEvents

-- Constants
local CONFIG = {
	PRODUCTION_TICK = 1,
	STORAGE_FULL_CHECK_INTERVAL = 5,
	BASE_ARTIFACT_DROP_CHANCE = 0.001,
	MAX_ARTIFACT_DROP_CHANCE = 0.05,
}

local BRAINROT_TAG = "ActiveBrainrot"

-- Module Table
local ItemProductionManager = {}
local Services = {}

-- Cache State
local PlayerCache = {}

--------------------------------------------------------------------------------
-- CACHE MANAGEMENT
--------------------------------------------------------------------------------

local function initPlayerCache(player)
	PlayerCache[player] = {
		CategoryCounts = {},
		ProductionState = {}, -- Per category timing
		lastStorageFullWarning = 0
	}
end

local function updatePlayerCache(player)
	if not PlayerCache[player] then initPlayerCache(player) end
	local cache = PlayerCache[player]
	
	-- Clear counts
	cache.CategoryCounts = {}
	
	-- Rebuild from GridManager (Source of Truth for PLACED units)
	if Services.GridManager and Services.GridManager.GetGridPositions then
		local gridPos = Services.GridManager.GetGridPositions(player)
		for _, data in pairs(gridPos) do
			-- Extract unit data
			local unitType, unitId
			if data.Unit then
				unitType = data.Unit.unitType
				unitId = data.Unit.unitId
			elseif data.unitType then
				unitType = data.unitType -- Legacy fallback
			end
			
			if unitType then
				-- Update Category Count
				local category = ItemConfig.GetBrainrotCategory(unitType)
				if category then
					cache.CategoryCounts[category] = (cache.CategoryCounts[category] or 0) + 1
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- PRODUCTION LOGIC
--------------------------------------------------------------------------------

-- Helper to find physical instances for bonus calculation
-- This avoids caching instance references which can leak or become stale
local function findUnitInstances(player, category)
	local units = {}
	local plot = nil
	if Services.BrainrotManager then
		plot = Services.BrainrotManager.GetPlayerPlot(player)
	end

	if not plot then
		-- Try legacy find
		local plotsFolder = workspace:FindFirstChild("Plots")
		if plotsFolder then
			for _, p in plotsFolder:GetChildren() do
				if p:GetAttribute("OwnerId") == player.UserId then plot = p; break end
			end
		end
	end

	if not plot then return units end

	local brainrots = plot:FindFirstChild("Brainrots")
	if brainrots then
		for _, unit in brainrots:GetChildren() do
			local uType = unit:GetAttribute("UnitType")
			if uType and ItemConfig.GetBrainrotCategory(uType) == category then
				table.insert(units, unit)
			end
		end
	end

	return units
end


local function calculateUnitBonuses(player, brainrot)
	local bonuses = {
		speedMult = 1,
		luckMult = 1,
		tierBonus = 0,
	}
	
	if not brainrot then return bonuses end

	local slotIndex = brainrot:GetAttribute("GridSlot")
	local unitGUID = brainrot:GetAttribute("UnitId")
	local unitType = brainrot:GetAttribute("UnitType")
	local category = ItemConfig.GetBrainrotCategory(unitType)
	
	-- Tile Bonus
	if slotIndex and Services.GridManager and Services.GridManager.GetTileAtSlot then
		local tileId = Services.GridManager.GetTileAtSlot(player, slotIndex)
		if tileId and category then
			local tileBonus = TileConfig.GetBonus(tileId, category)
			bonuses.speedMult = bonuses.speedMult * tileBonus.SpeedMult
			bonuses.luckMult = bonuses.luckMult * tileBonus.LuckMult
		end
	end
	
	-- Artifact Bonus
	if unitGUID and Services.ArtifactManager and Services.ArtifactManager.CalculateUnitArtifactStats then
		local artifactStats = Services.ArtifactManager.CalculateUnitArtifactStats(player, unitGUID)
		bonuses.speedMult = bonuses.speedMult * artifactStats.CycleTimeMult
		bonuses.luckMult = bonuses.luckMult + artifactStats.LuckBonus
		bonuses.tierBonus = bonuses.tierBonus + artifactStats.ItemTierBonus
	end
	
	bonuses.speedMult = math.max(bonuses.speedMult, 0.1)
	return bonuses
end

local function tryArtifactDrop(player, bonuses)
	if not Services.ArtifactManager then return end
	
	local dropChance = CONFIG.BASE_ARTIFACT_DROP_CHANCE * bonuses.luckMult
	dropChance = math.min(dropChance, CONFIG.MAX_ARTIFACT_DROP_CHANCE)
	
	if math.random() < dropChance then
		local artifact = Services.ArtifactManager.GenerateArtifact()
		if artifact then
			Services.ArtifactManager.AddArtifact(player, artifact)
		end
	end
end

local function produceItems(player)
	local ISM = Services.ItemStorageManager
	if not ISM then return end
	
	-- 1. Check Storage
	if ISM.IsStorageFull(player) then
		local cache = PlayerCache[player]
		if cache then
			local now = tick()
			if now - cache.lastStorageFullWarning > CONFIG.STORAGE_FULL_CHECK_INTERVAL then
				cache.lastStorageFullWarning = now
				StorageFullEvent:FireClient(player)
			end
		end
		return
	end
	
	-- 2. Use Cached Counts
	local cache = PlayerCache[player]
	if not cache then return end
	
	local now = tick()
	
	for category, ownedCount in pairs(cache.CategoryCounts) do
		if ownedCount > 0 then
			local productions = ItemConfig.GetProductions(category, ownedCount)
			
			-- Re-enable bonuses by scanning actual units
			local activeUnits = findUnitInstances(player, category)
			local categoryBonus = { speedMult = 1, luckMult = 1, tierBonus = 0 }
			
			for _, unitModel in ipairs(activeUnits) do
				local b = calculateUnitBonuses(player, unitModel)
				categoryBonus.speedMult = math.min(categoryBonus.speedMult, b.speedMult)
				categoryBonus.luckMult = categoryBonus.luckMult + (b.luckMult - 1)
				categoryBonus.tierBonus = math.max(categoryBonus.tierBonus, b.tierBonus)
			end
			
			-- Production Timing
			if not cache.ProductionState[category] then cache.ProductionState[category] = {} end
			
			for _, prod in ipairs(productions) do
				local tier = (ItemConfig.Items[prod.itemId] and ItemConfig.Items[prod.itemId].tier or 1) + math.floor(categoryBonus.tierBonus)
				
				local lastProd = cache.ProductionState[category][tier] or 0
				local adjustedRate = math.max(0.1, prod.rate * categoryBonus.speedMult)
				
				if now - lastProd >= adjustedRate then
					local added = ISM.AddToStorage(player, prod.itemId, 1)
					if added > 0 then
						cache.ProductionState[category][tier] = now
						ItemProducedEvent:FireClient(player, prod.itemId, 1)
						
						-- Artifact Drop Roll
						tryArtifactDrop(player, categoryBonus)
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function ItemProductionManager.Init(services)
	print("   ItemProductionManager (Module) - Initializing")
	Services = services or {}
	
	loadConfigs()
	CONFIG.BASE_ARTIFACT_DROP_CHANCE = ArtifactConfig.BaseDropChance
	CONFIG.MAX_ARTIFACT_DROP_CHANCE = ArtifactConfig.MaxDropChance
	
	-- Polling fallback for cache update
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				updatePlayerCache(player)
			end
			task.wait(5) -- Update cache every 5s
		end
	end)
	
	-- Production Loop
	task.spawn(function()
		while true do
			task.wait(CONFIG.PRODUCTION_TICK)
			for _, player in Players:GetPlayers() do
				produceItems(player)
			end
		end
	end)
	
	Players.PlayerAdded:Connect(initPlayerCache)
	Players.PlayerRemoving:Connect(function(player) PlayerCache[player] = nil end)
	
	for _, p in Players:GetPlayers() do initPlayerCache(p) end
	
	print("✓ ItemProductionManager Initialized")
end

-- Export for compatibility
ItemProductionManager.ProduceItems = produceItems
ItemProductionManager.GetCategoryCounts = function(player)
	return PlayerCache[player] and PlayerCache[player].CategoryCounts or {}
end

return ItemProductionManager
