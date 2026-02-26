--[[
	ItemProductionManager Server Module (V3)
	
	Handles item production for the Sell a Brainrot system.
	
	V3 CHANGES:
	- Per-slot production (not per-unit-type)
	- Single mode selection per unit (exclusive production)
	- Cluster synergy overrides when specific pairs share a 2x2 corner
	- Speed scales smoothly with level via SpeedExponent
]]

local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Lazy Configs
local ItemConfig, _ArtifactConfig

local function _loadConfigs()
	if not ItemConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		ItemConfig = require(Shared:WaitForChild("ItemConfig"))
		_ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))
	end
end

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local StorageFullEvent = RemoteEvents:FindFirstChild("StorageFull") or Instance.new("RemoteEvent")
StorageFullEvent.Name = "StorageFull"
StorageFullEvent.Parent = RemoteEvents

local ItemProducedEvent = RemoteEvents:FindFirstChild("ItemProduced") or Instance.new("RemoteEvent")
ItemProducedEvent.Name = "ItemProduced"
ItemProducedEvent.Parent = RemoteEvents

local CONFIG = {
	PRODUCTION_TICK = 1,
	STORAGE_FULL_CHECK_INTERVAL = 5,
	BASE_ARTIFACT_DROP_CHANCE = 0.001,
	MAX_ARTIFACT_DROP_CHANCE = 0.05,
}

-- Module Table
local ItemProductionManager = {}
local Services = {}

-- Cache State (V3: keyed by slot index instead of unit type)
local PlayerCache = {}

--------------------------------------------------------------------------------
-- CACHE MANAGEMENT
--------------------------------------------------------------------------------

local function initPlayerCache(player)
	PlayerCache[player] = {
		SlotProduction = {},  -- [slotIndex] = { lastProd = timestamp }
		lastStorageFullWarning = 0,
		lastStorageSnapshot = nil,
		lastStorageCapacity = nil,
	}
end

local function cloneItemMap(items)
	local clone = {}
	for itemId, count in pairs(items) do
		clone[itemId] = count
	end
	return clone
end

local function areItemMapsEqual(a, b)
	if a == b then return true end
	if not a or not b then return false end
	for itemId, count in pairs(a) do
		if b[itemId] ~= count then
			return false
		end
	end
	for itemId, count in pairs(b) do
		if a[itemId] ~= count then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- PRODUCTION HELPERS
--------------------------------------------------------------------------------


local function calculateUnitBonuses(player, brainrot)
	local bonuses = {
		speedMult = 1,
		luckMult = 1,
		tierBonus = 0,
	}
	
	if not brainrot then return bonuses end

	local _slotIndex = brainrot:GetAttribute("GridSlot")
	local unitGUID = brainrot:GetAttribute("UnitId")
	local _unitType = brainrot:GetAttribute("UnitType")
	
	-- Tile Bonus (REMOVED)
	
	-- 1. Artifact Bonus (Per-Unit)
	local ArtifactManager = rawget(Services, "ArtifactManager")
	if unitGUID and ArtifactManager and ArtifactManager.CalculateUnitArtifactStats then
		local artifactStats = ArtifactManager.CalculateUnitArtifactStats(player, unitGUID)
		bonuses.speedMult = bonuses.speedMult * artifactStats.CycleTimeMult
		bonuses.luckMult = bonuses.luckMult + artifactStats.LuckBonus
		bonuses.tierBonus = bonuses.tierBonus + artifactStats.ItemTierBonus
	end

	-- 2. Global Bonus Aggregator (Prestige, Upgrades, Mewing)
	local BonusManager = rawget(Services, "BonusManager")
	if BonusManager then
		bonuses.speedMult = bonuses.speedMult * BonusManager.GetTotalSpeedMultiplier(player)
		-- Global luck is multiplier-based here for simplicity
		bonuses.luckMult = bonuses.luckMult * BonusManager.GetTotalLuckMultiplier(player)
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

-- V3: Check if this slot has a synergy partner in the same cluster
local function checkClusterSynergy(gridPositions, slotIndex, unitType)
	local GridManager = rawget(Services, "GridManager")
	if not GridManager or not GridManager.GetClusterSlots then return nil end
	
	local clusterSlots = GridManager.GetClusterSlots(slotIndex)
	
	for _, neighborSlot in ipairs(clusterSlots) do
		if neighborSlot ~= slotIndex then
			local neighborData = gridPositions[tostring(neighborSlot)]
			if neighborData and neighborData.Unit then
				local synergy = ItemConfig.GetSynergyOverride(unitType, neighborData.Unit.unitType)
				if synergy then return synergy end
			end
		end
	end
	return nil
end

local function _calculateItemTier(level: number): number
	local CONFIG_TIER_MILESTONES = { [1] = 1, [10] = 2, [50] = 3, [100] = 4 }
	local currentTier = 1
	local milestones = {1, 10, 50, 100}
	for _, reqLevel in ipairs(milestones) do
		if level >= reqLevel then
			currentTier = CONFIG_TIER_MILESTONES[reqLevel]
		end
	end
	return currentTier
end


--------------------------------------------------------------------------------
-- V3: PER-SLOT PRODUCTION LOOP
--------------------------------------------------------------------------------

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
			end
		end
		return
	end
	
	-- 2. Fetch O(1) Cache directly from GridManager
	local GridManager = rawget(Services, "GridManager")
	if not GridManager then return end
	
	local gridCache = GridManager.GetGridCache(player)
	if not gridCache then return end
	
	local cache = PlayerCache[player]
	if not cache then return end
	
	local now = tick()
	local storageItems = cloneItemMap(ISM.GetStorageContents(player) or {})
	local totalAdded = 0
	local itemsProducedThisTick = {}
	
	-- 3. Iterate each occupied slot
	for slotIndex, slotData in pairs(gridCache) do
		local unitModel = slotData.Unit
		if unitModel then
			local outputItemId = slotData.OutputItem
			local outputRate = slotData.OutputRate
			local consumes = slotData.Consumes
			
			if not outputItemId or not outputRate or outputItemId == "SYNERGY_PROVIDER" then continue end
			
			-- Apply tile/artifact bonuses
			local bonuses = calculateUnitBonuses(player, unitModel)
			local adjustedRate = math.max(0.1, outputRate * bonuses.speedMult)
			
			-- Production timing (keyed by slot)
			if not cache.SlotProduction[slotIndex] then
				cache.SlotProduction[slotIndex] = { lastProd = 0 }
			end
			
			local slotState = cache.SlotProduction[slotIndex]
			
			if now - slotState.lastProd >= adjustedRate then
				-- Check and consume crafting requirements
				local canConsume = true
				if consumes then
					for reqId, reqCount in pairs(consumes) do
						if (storageItems[reqId] or 0) < reqCount then
							canConsume = false
							break
						end
					end
					if canConsume then
						for reqId, reqCount in pairs(consumes) do
							storageItems[reqId] = (storageItems[reqId] or 0) - reqCount
							if storageItems[reqId] <= 0 then
								storageItems[reqId] = nil
							end
							ISM.RemoveFromStorage(player, reqId, reqCount)
						end
					end
				end
				
				if not canConsume then continue end

				-- SILENT ADD: Pass true to suppress immediate event firing
				local added = ISM.AddToStorage(player, outputItemId, 1, true)
				if added > 0 then
					storageItems[outputItemId] = (storageItems[outputItemId] or 0) + added
					slotState.lastProd = now
					
					-- Batch the event data
					totalAdded += 1
					itemsProducedThisTick[outputItemId] = (itemsProducedThisTick[outputItemId] or 0) + added
					
					-- Update physical unit with production timestamp
					unitModel:SetAttribute("LastProductionTime", now)
					
					-- Artifact Drop Roll
					tryArtifactDrop(player, bonuses)
				end
			end
		end
	end
	
	-- BATCH FIRE: Send exactly ONE remote event per second for all production
	if totalAdded > 0 then
		ItemProducedEvent:FireClient(player, itemsProducedThisTick)

		local currentTotal = 0
		for _, c in pairs(storageItems) do currentTotal += c end
		local capacity = ISM.GetStorageCapacity(player)
		
		local storageChanged = not areItemMapsEqual(storageItems, cache.lastStorageSnapshot)
		local capacityChanged = cache.lastStorageCapacity ~= capacity
		if storageChanged or capacityChanged then
			cache.lastStorageSnapshot = cloneItemMap(storageItems)
			cache.lastStorageCapacity = capacity
			local StorageUpdatedEvent = ReplicatedStorage:FindFirstChild("RemoteEvents") and ReplicatedStorage.RemoteEvents:FindFirstChild("StorageUpdated")
			if StorageUpdatedEvent then
				StorageUpdatedEvent:FireClient(player, storageItems, currentTotal, capacity)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function ItemProductionManager.Init(services)
	print("   ItemProductionManager (Module) - Initializing [V3: Mode-Based]")
	Services = services or {}
	
	_loadConfigs()
	CONFIG.BASE_ARTIFACT_DROP_CHANCE = _ArtifactConfig.BaseDropChance
	CONFIG.MAX_ARTIFACT_DROP_CHANCE = _ArtifactConfig.MaxDropChance
	
	-- Production Loop (no longer needs cache polling — reads grid directly)
	task.spawn(function()
		while true do
			task.wait(CONFIG.PRODUCTION_TICK)
			for _, player in _Players:GetPlayers() do
				local success, err = pcall(produceItems, player)
				if not success then
					warn("ItemProductionManager: Error producing for " .. player.Name .. ": " .. tostring(err))
				end
			end
		end
	end)
	
	_Players.PlayerAdded:Connect(initPlayerCache)
	_Players.PlayerRemoving:Connect(function(player) PlayerCache[player] = nil end)
	
	for _, p in _Players:GetPlayers() do initPlayerCache(p) end
	
	print("✓ ItemProductionManager Initialized [V3]")
end

-- Export for compatibility
ItemProductionManager.ProduceItems = produceItems
ItemProductionManager.GetCategoryCounts = function(player)
	-- Legacy compatibility: build counts from grid positions
	local GridManager = rawget(Services, "GridManager")
	if not GridManager then return {} end
	local gridPos = GridManager.GetGridPositions(player)
	local counts = {}
	for _, data in pairs(gridPos) do
		if data.Unit and data.Unit.unitType then
			counts[data.Unit.unitType] = (counts[data.Unit.unitType] or 0) + 1
		end
	end
	return counts
end

--[[
	RefreshUnitAttributes: Updates physical model attributes (HUD/Visuals) for all placed units.
	Ensures synergy, mode, and artifact bonuses are immediately reflected in the UI.
]]
function ItemProductionManager.RefreshUnitAttributes(player: Player)
	local GridManager = rawget(Services, "GridManager")
	if not GridManager then return end
	
	local gridPositions = GridManager.GetGridPositions(player)
	if not gridPositions then return end
	
	local gridCache = GridManager.GetGridCache(player)

	_loadConfigs()
	local _now = tick()
	
	for slotKey, slotData in pairs(gridPositions) do
		local slotIndex = tonumber(slotKey)
		local unitModel = nil
		if gridCache and gridCache[slotIndex] then
			unitModel = gridCache[slotIndex].Unit
		end
		if not unitModel then continue end
		
		local unitType = slotData.Unit.unitType
		local level = slotData.Unit.level or 1
		local currentMode = slotData.CurrentMode or 1
		
		local outputItemId, outputRate, consumes
		local synergy = checkClusterSynergy(gridPositions, slotIndex, unitType)
		
		if synergy then
			if unitType == synergy.unitA then
				local baseProd = ItemConfig.GetModeProduction(unitType, currentMode, level)
				if baseProd then
					outputItemId = synergy.synergyItem
					outputRate = baseProd.rate / synergy.bonus
					consumes = baseProd.consumes
				end
			elseif unitType == synergy.unitB then
				outputItemId = "SYNERGY_PROVIDER"
				outputRate = 9999
			end
		else
			local prod = ItemConfig.GetModeProduction(unitType, currentMode, level)
			if prod then
				outputItemId = prod.itemId
				outputRate = prod.rate
				consumes = prod.consumes
			end
		end

		-- Store in GridCache so produceItems() reads it instantly
		if gridCache and gridCache[slotIndex] then
			gridCache[slotIndex].OutputItem = outputItemId
			gridCache[slotIndex].OutputRate = outputRate
			gridCache[slotIndex].Consumes = consumes
		end
		
		if outputItemId and outputRate then
			local bonuses = calculateUnitBonuses(player, unitModel)
			local adjustedRate = math.max(0.1, outputRate * bonuses.speedMult)
			
			unitModel:SetAttribute("IncomeInterval", adjustedRate)
			unitModel:SetAttribute("CurrentProducing", outputItemId)
			unitModel:SetAttribute("ItemTier", _calculateItemTier(level))
			unitModel:SetAttribute("Level", level)
		end
	end
end

return ItemProductionManager
