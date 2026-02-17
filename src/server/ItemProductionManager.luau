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

-- Helper for debug
local function getKeys(t)
	local keys = {}
	for k in pairs(t) do table.insert(keys, tostring(k)) end
	return keys
end

local function initPlayerCache(player)
	PlayerCache[player] = {
		UnitTypeCounts = {},
		ProductionState = {}, -- Per unit type timing
		lastStorageFullWarning = 0
	}
end

local function updatePlayerCache(player)
	if not PlayerCache[player] then initPlayerCache(player) end
	local cache = PlayerCache[player]
	
	-- Clear counts
	cache.UnitTypeCounts = {}
	
	-- Rebuild from GridManager (Source of Truth for PLACED units)
	local GridManager = rawget(Services, "GridManager")
	if not GridManager then
		warn("[DEBUG] ItemProductionManager: GridManager not found in Services!")
		return
	end
	
	if not GridManager.GetGridPositions then
		warn("[DEBUG] ItemProductionManager: GridManager.GetGridPositions is nil!")
		return
	end
	
	local gridPos = GridManager.GetGridPositions(player)
	
	-- DEBUG: Log what we got
	local slotCount = 0
	for _ in pairs(gridPos) do slotCount += 1 end
	-- if slotCount > 0 then
	-- 	print(string.format("[DEBUG] ItemProductionManager: Player %s has %d grid slots with data", player.Name, slotCount))
	-- end
	
	for slotKey, data in pairs(gridPos) do
		-- Extract unit data
		local unitType, _unitId
		if data.Unit then
			unitType = data.Unit.unitType
			_unitId = data.Unit.unitId
		elseif data.unitType then
			unitType = data.unitType -- Legacy fallback
		end
		
		if unitType then
			-- Update Unit Type Count
			cache.UnitTypeCounts[unitType] = (cache.UnitTypeCounts[unitType] or 0) + 1
			-- print(string.format("[DEBUG] ItemProductionManager: Slot %s has unit '%s' (count now: %d)", 
			-- 	tostring(slotKey), unitType, cache.UnitTypeCounts[unitType]))
		else
			-- DEBUG: Log slots without unitType
			if data.Unit then
				local unitKeys = getKeys(data.Unit)
				warn(string.format("[DEBUG] ItemProductionManager: Slot %s has Unit table but NO unitType field! Keys: %s", 
					tostring(slotKey), table.concat(unitKeys, ", ")))
			end
		end
	end
	
	-- DEBUG: Summary
	local modelCount = 0
	for _, _ in pairs(cache.UnitTypeCounts) do
		modelCount += 1
	end
	if modelCount == 0 and slotCount > 0 then
		warn("[DEBUG] ItemProductionManager: Grid has slots but NO unit types were extracted!")
	end
end

--------------------------------------------------------------------------------
-- PRODUCTION LOGIC
--------------------------------------------------------------------------------

-- Helper to find physical instances for bonus calculation
-- This avoids caching instance references which can leak or become stale
local function findUnitInstances(player, unitType)
	local units = {}
	local plot = nil
	local BrainrotManager = rawget(Services, "BrainrotManager")
	if BrainrotManager then
		plot = BrainrotManager.GetPlayerPlot(player)
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
			if uType == unitType then
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
	
	-- Tile Bonus
	local GridManager = rawget(Services, "GridManager")
	if slotIndex and GridManager and GridManager.GetTileAtSlot then
		local tileId = GridManager.GetTileAtSlot(player, slotIndex)
		if tileId and unitType then
			-- Pass unitType as "category" for legacy tile support
			local tileBonus = TileConfig.GetBonus(tileId, unitType)
			bonuses.speedMult = bonuses.speedMult * tileBonus.SpeedMult
			bonuses.luckMult = bonuses.luckMult * tileBonus.LuckMult
		end
	end
	
	-- Artifact Bonus
	local ArtifactManager = rawget(Services, "ArtifactManager")
	if unitGUID and ArtifactManager and ArtifactManager.CalculateUnitArtifactStats then
		local artifactStats = ArtifactManager.CalculateUnitArtifactStats(player, unitGUID)
		bonuses.speedMult = bonuses.speedMult * artifactStats.CycleTimeMult
		bonuses.luckMult = bonuses.luckMult + artifactStats.LuckBonus
		bonuses.tierBonus = bonuses.tierBonus + artifactStats.ItemTierBonus
	end
	
	bonuses.speedMult = math.max(bonuses.speedMult, 0.1)
	return bonuses
end

local function tryArtifactDrop(player, bonuses)
	local ArtifactManager = rawget(Services, "ArtifactManager")
	if not ArtifactManager then return end
	
	local dropChance = CONFIG.BASE_ARTIFACT_DROP_CHANCE * bonuses.luckMult
	dropChance = math.min(dropChance, CONFIG.MAX_ARTIFACT_DROP_CHANCE)
	
	if math.random() < dropChance then
		local artifact = ArtifactManager.GenerateArtifact()
		if artifact then
			ArtifactManager.AddArtifact(player, artifact)
		end
	end
end

local function produceItems(player)
	local ISM = rawget(Services, "ItemStorageManager")
	if not ISM then return end
	
	-- 1. Check Storage
	if ISM.IsStorageFull(player) then
		local cache = PlayerCache[player]
		if cache then
			local now = tick()
			if now - cache.lastStorageFullWarning > CONFIG.STORAGE_FULL_CHECK_INTERVAL then
				cache.lastStorageFullWarning = now
				StorageFullEvent:FireClient(player)
				-- DEBUG: Storage Full
				print("[DEBUG] Production paused: Storage Full")
			end
		end
		return
	end
	
	-- 2. Use Cached Counts
	local cache = PlayerCache[player]
	if not cache then return end
	
	local now = tick()
	
	-- DEBUG: Trace loop (throttle to avoid spam, e.g. every 5s)
	-- if now % 5 < 1 then
	-- 	print("[DEBUG] Running produceItems for " .. player.Name)
	-- end
	
	for unitType, ownedCount in pairs(cache.UnitTypeCounts) do
		if ownedCount > 0 then
			local productions = ItemConfig.GetProductions(unitType, ownedCount)
			
			-- Re-enable bonuses by scanning actual units
			local activeUnits = findUnitInstances(player, unitType)
			local unitBonus = { speedMult = 1, luckMult = 1, tierBonus = 0 }
			
			for _, unitModel in ipairs(activeUnits) do
				local b = calculateUnitBonuses(player, unitModel)
				unitBonus.speedMult = math.min(unitBonus.speedMult, b.speedMult)
				unitBonus.luckMult = unitBonus.luckMult + (b.luckMult - 1)
				unitBonus.tierBonus = math.max(unitBonus.tierBonus, b.tierBonus)
			end
			
			-- Production Timing
			if not cache.ProductionState[unitType] then cache.ProductionState[unitType] = {} end
			
			for _, prod in ipairs(productions) do
				local tier = (ItemConfig.Items[prod.itemId] and ItemConfig.Items[prod.itemId].tier or 1) + math.floor(unitBonus.tierBonus)
				
				local lastProd = cache.ProductionState[unitType][tier] or 0
				local adjustedRate = math.max(0.1, prod.rate * unitBonus.speedMult)
				
				if now - lastProd >= adjustedRate then
					local added = ISM.AddToStorage(player, prod.itemId, 1)
					if added > 0 then
						cache.ProductionState[unitType][tier] = now
						ItemProducedEvent:FireClient(player, prod.itemId, 1)
						
						-- Update physical units with production timestamp for HUD sync
						for _, unitModel in ipairs(activeUnits) do
							unitModel:SetAttribute("LastProductionTime", now)
							unitModel:SetAttribute("IncomeInterval", adjustedRate)
						end
						
						-- Artifact Drop Roll
						tryArtifactDrop(player, unitBonus)
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
				local success, err = pcall(produceItems, player)
				if not success then
					warn("ItemProductionManager: Error producing for " .. player.Name .. ": " .. tostring(err))
				end
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
	return PlayerCache[player] and PlayerCache[player].UnitTypeCounts or {}
end

return ItemProductionManager
