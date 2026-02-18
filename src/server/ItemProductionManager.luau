--[[
	ItemProductionManager Server Module (V3)
	
	Handles item production for the Sell a Brainrot system.
	
	V3 CHANGES:
	- Per-slot production (not per-unit-type)
	- Single mode selection per unit (exclusive production)
	- Cluster synergy overrides when specific pairs share a 2x2 corner
	- Speed scales smoothly with level via SpeedExponent
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Lazy Configs
local ItemConfig, ArtifactConfig

local function loadConfigs()
	if not ItemConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		ItemConfig = require(Shared:WaitForChild("ItemConfig"))
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
	}
end

--------------------------------------------------------------------------------
-- PRODUCTION HELPERS
--------------------------------------------------------------------------------

-- Find the physical brainrot model for a given slot
local function findUnitInSlot(player, slotIndex)
	local plot = nil
	local MapSystem = rawget(Services, "MapSystem")
	if MapSystem and MapSystem.GetPlayerPlot then
		plot = MapSystem.GetPlayerPlot(player)
	end

	if not plot then
		local BrainrotManager = rawget(Services, "BrainrotManager")
		if BrainrotManager then
			plot = BrainrotManager.GetPlayerPlot(player)
		end
	end

	if not plot then
		local plotsFolder = workspace:FindFirstChild("Plots")
		if plotsFolder then
			for _, p in plotsFolder:GetChildren() do
				if p:GetAttribute("OwnerId") == player.UserId then plot = p; break end
			end
		end
	end

	if not plot then return nil end

	local brainrots = plot:FindFirstChild("Brainrots")
	if brainrots then
		for _, unit in brainrots:GetChildren() do
			if unit:GetAttribute("GridSlot") == slotIndex then
				return unit
			end
		end
	end
	return nil
end

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
	
	-- 2. Get grid state
	local GridManager = rawget(Services, "GridManager")
	if not GridManager then return end
	
	local gridPositions = GridManager.GetGridPositions(player)
	if not gridPositions then return end
	
	local cache = PlayerCache[player]
	if not cache then return end
	
	local now = tick()
	
	-- 3. Iterate each occupied slot
	for slotKey, slotData in pairs(gridPositions) do
		if slotData.Unit then
			local slotIndex = tonumber(slotKey)
			if not slotIndex then continue end
			
			local unitType = slotData.Unit.unitType
			local level = slotData.Unit.level or 1
			local currentMode = slotData.CurrentMode or 1
			
			if not unitType then continue end
			
			-- Determine what to produce
			local outputItemId, outputRate
			
			-- Check synergy override first
			local synergy = checkClusterSynergy(gridPositions, slotIndex, unitType)
			
			if synergy then
				-- Synergy active: produce composite item with bonus rate
				local baseProd = ItemConfig.GetModeProduction(unitType, currentMode, level)
				if baseProd then
					outputItemId = synergy.synergyItem
					outputRate = baseProd.rate / synergy.bonus -- Faster with synergy bonus
				end
			else
				-- Normal: produce selected mode item
				local prod = ItemConfig.GetModeProduction(unitType, currentMode, level)
				if prod then
					outputItemId = prod.itemId
					outputRate = prod.rate
				end
			end
			
			if not outputItemId or not outputRate then continue end
			
			-- Apply tile/artifact bonuses
			local unitModel = findUnitInSlot(player, slotIndex)
			local bonuses = calculateUnitBonuses(player, unitModel)
			local adjustedRate = math.max(0.1, outputRate * bonuses.speedMult)
			
			-- Production timing (keyed by slot)
			if not cache.SlotProduction[slotIndex] then
				cache.SlotProduction[slotIndex] = { lastProd = 0 }
			end
			
			local slotState = cache.SlotProduction[slotIndex]
			
			if now - slotState.lastProd >= adjustedRate then
				local added = ISM.AddToStorage(player, outputItemId, 1)
				if added > 0 then
					slotState.lastProd = now
					ItemProducedEvent:FireClient(player, outputItemId, 1)
					
					-- Update physical unit with production timestamp
					if unitModel then
						unitModel:SetAttribute("LastProductionTime", now)
						unitModel:SetAttribute("IncomeInterval", adjustedRate)
						unitModel:SetAttribute("CurrentProducing", outputItemId)
					end
					
					-- Artifact Drop Roll
					tryArtifactDrop(player, bonuses)
				end
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
	
	loadConfigs()
	CONFIG.BASE_ARTIFACT_DROP_CHANCE = ArtifactConfig.BaseDropChance
	CONFIG.MAX_ARTIFACT_DROP_CHANCE = ArtifactConfig.MaxDropChance
	
	-- Production Loop (no longer needs cache polling — reads grid directly)
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

return ItemProductionManager
