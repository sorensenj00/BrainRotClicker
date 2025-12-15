--[[
	BrainrotManager Server Module (Stacking Version)
	
	Handles:
	1. Spawning ONE unique unit per type per player.
	2. Stacking purchases to upgrade Level/Speed.
	3. Caching units for performance (Fixes O(N) lookup).
	
	CONVERTED TO MODULE SCRIPT + PERFORMANCE FIX
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local RarityConfig = require(Shared:WaitForChild("RarityConfig"))

-- Configuration
local CONFIG = {
	TIER_MILESTONES = {
		[10] = 2,
		[25] = 3,
		[50] = 4,
		[100] = 5,
	}
}

local BRAINROT_TAG = "ActiveBrainrot"

-- References
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")
local PlotsFolder = workspace:WaitForChild("Plots")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

-- Events
local InventoryChangedEvent = RemoteEvents:FindFirstChild("InventoryChanged") or Instance.new("RemoteEvent")
local BuyBrainrotRemote = RemoteEvents:FindFirstChild("BuyBrainrot") or Instance.new("RemoteEvent")
local GetInventoryRemote = RemoteEvents:FindFirstChild("GetInventory") or Instance.new("RemoteFunction")

-- Module Table
local BrainrotManager = {}

-- Dependencies
local InventoryManager
local GridManager

--------------------------------------------------------------------------------
-- CACHE STATE (PERFORMANCE FIX)
--------------------------------------------------------------------------------

-- Lookup: Player -> UnitType -> Instance
-- Allows O(1) retrieval instead of iterating workspace
local UnitCache = {} 

local function cacheUnit(player, unitType, instance)
	if not UnitCache[player] then UnitCache[player] = {} end
	UnitCache[player][unitType] = instance
end

local function getCachedUnit(player, unitType)
	if not UnitCache[player] then return nil end
	return UnitCache[player][unitType]
end

local function clearCache(player)
	UnitCache[player] = nil
end

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function getPlayerPlot(player: Player): Instance?
	for _, plot in PlotsFolder:GetChildren() do
		local ownerId = plot:GetAttribute("OwnerId")
		if ownerId and ownerId == player.UserId then return plot end
	end
	return nil
end

local function _calculateItemTier(level: number): number
	local currentTier = 1
	local milestones = {10, 25, 50, 100} 
	for _, reqLevel in ipairs(milestones) do
		if level >= reqLevel then
			currentTier = CONFIG.TIER_MILESTONES[reqLevel]
		end
	end
	return currentTier
end

local function updateVisuals(brainrot: Model)
	-- Client handles HUD via attributes
end

local function getBrainrotTemplate(unitName: string): Model?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder then
		local brainrotsSubfolder = assetsFolder:FindFirstChild("Brainrots")
		if brainrotsSubfolder then
			local model = brainrotsSubfolder:FindFirstChild(unitName)
			if model then return model end
		end
	end
	
	local unitsFolder = ReplicatedStorage:FindFirstChild("Units")
	if unitsFolder then
		local model = unitsFolder:FindFirstChild(unitName)
		if model then return model end
	end
	
	if BrainrotsFolder then
		local model = BrainrotsFolder:FindFirstChild(unitName)
		if model then return model end
	end
	
	return nil
end

--------------------------------------------------------------------------------
-- CORE LOGIC
--------------------------------------------------------------------------------

local function recalculateStats(unit: Instance)
	local unitName = unit:GetAttribute("UnitType")
	local level = unit:GetAttribute("Level") or 1
	local rarity = unit:GetAttribute("Rarity") or "Normal"

	if not unitName then return end

	local effectiveIncome = ShopConfig.CalculateEffectiveIncome(unitName, level)
	local effectiveCycleTime = ShopConfig.CalculateEffectiveCycleTime(unitName, level)
	local rarityMult = RarityConfig.GetMultiplier(rarity)

	local finalIncome = math.floor(effectiveIncome * rarityMult)
	local finalInterval = math.max(0.1, effectiveCycleTime / rarityMult)

	unit:SetAttribute("IncomeAmount", finalIncome)
	unit:SetAttribute("IncomeInterval", finalInterval)
	unit:SetAttribute("ItemTier", _calculateItemTier(level))

	updateVisuals(unit :: Model)
end

--[[
	Spawns or updates the physical model based on authoritative data.
	Uses Cache for O(1) lookup.
]]
local function spawnOrUpdateUnit(player: Player, unitName: string, data: any): Instance?
	local plot = getPlayerPlot(player)
	if not plot then return nil end

	local brainrotsContainer = plot:FindFirstChild("Brainrots") or Instance.new("Folder", plot)
	brainrotsContainer.Name = "Brainrots"

	-- PERFORMANCE FIX: Use Cache
	local existingUnit = getCachedUnit(player, unitName)
	
	-- Fallback check if cache missed but object exists (re-sync)
	if not existingUnit then
		for _, child in brainrotsContainer:GetChildren() do
			if child:GetAttribute("UnitType") == unitName then
				existingUnit = child
				cacheUnit(player, unitName, child) -- Restore cache
				break
			end
		end
	end

	if existingUnit then
		-- Update existing
		local level = data.level or data.Level or 1
		local rarity = data.rarity or data.Rarity or "Normal"
		
		existingUnit:SetAttribute("Level", level)
		existingUnit:SetAttribute("Rarity", rarity)
		
		recalculateStats(existingUnit)
		return existingUnit
	else
		-- Spawn new
		local template = getBrainrotTemplate(unitName)
		if not template then return nil end
		
		local brainrot = template:Clone()
		brainrot.Name = unitName
		
		brainrot:SetAttribute("OwnerId", player.UserId)
		brainrot:SetAttribute("UnitType", unitName)
		
		local savedUnitId = data.unitId or data.UnitId or HttpService:GenerateGUID(false)
		brainrot:SetAttribute("UnitId", savedUnitId)
		
		local level = data.level or data.Level or 1
		local rarity = data.rarity or data.Rarity or "Normal"
		
		brainrot:SetAttribute("Level", level)
		brainrot:SetAttribute("Rarity", rarity)
		brainrot:SetAttribute("GridSlot", nil)
		brainrot:SetAttribute("IsStored", true)
		
		local plotCF = plot:GetPivot()
		if plot.PrimaryPart then plotCF = plot.PrimaryPart.CFrame end
		local spawnCF = plotCF * CFrame.new(0, -100, 0) -- Hidden underground
		brainrot:PivotTo(spawnCF)
		
		brainrot.Parent = brainrotsContainer
		CollectionService:AddTag(brainrot, BRAINROT_TAG)
		
		recalculateStats(brainrot)
		
		-- Ensure anchored
		for _, part in brainrot:GetDescendants() do
			if part:IsA("BasePart") then part.Anchored = true end
		end
		
		-- Update Cache
		cacheUnit(player, unitName, brainrot)
		
		return brainrot
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function BrainrotManager.Init()
	print("   BrainrotManager (Module) - Initializing")
	
	if not InventoryManager then InventoryManager = _G.InventoryManager end
	
	-- Connect to Inventory
	if InventoryManager and InventoryManager.UnitChanged then
		InventoryManager.UnitChanged:Connect(function(player, unitName, newData)
			if not unitName then
				-- Full reload
				BrainrotManager.UpdateAllUnitStats(player)
			else
				-- Single update
				spawnOrUpdateUnit(player, unitName, newData)
			end
		end)
	else
		-- Wait/Retry logic handled by ServerMain order, 
		-- but we can warn if strictly missing.
	end
	
	-- Player Setup
	Players.PlayerRemoving:Connect(function(player)
		clearCache(player)
	end)
	
	print("✓ BrainrotManager Initialized")
end

function BrainrotManager.AddUnit(player: Player, unitName: string, forceRarity: string?, forceLevel: number?): Instance?
	if not InventoryManager then InventoryManager = _G.InventoryManager end
	
	if InventoryManager then
		local newData = InventoryManager.AddUnit(player, unitName, forceRarity, forceLevel)
		if newData then
			return spawnOrUpdateUnit(player, unitName, newData)
		end
	end
	return nil
end

function BrainrotManager.StashBrainrot(player: Player, brainrot: Model)
	brainrot:SetAttribute("IsStored", true)
	brainrot:SetAttribute("GridSlot", nil)
	
	local currentCF = brainrot:GetPivot()
	brainrot:PivotTo(CFrame.new(currentCF.Position.X, -100, currentCF.Position.Z))
	
	InventoryChangedEvent:FireClient(player)
end

function BrainrotManager.GetPlacementData(player: Player)
	if not GridManager then GridManager = _G.GridManager end
	local placements = {}
	
	if GridManager and GridManager.GetGridPositions then
		local gridPos = GridManager.GetGridPositions(player)
		for slot, data in pairs(gridPos) do
			if data.Unit then
				local entry = {}
				entry.slotIndex = tonumber(slot)
				
				local unitData = data.Unit
				entry.unitType = unitData.unitType
				entry.rarity = unitData.rarity
				entry.level = unitData.level
				
				table.insert(placements, entry)
			elseif data.unitType then
				local entry = table.clone(data)
				entry.slotIndex = tonumber(slot)
				table.insert(placements, entry)
			end
		end
	end
	return placements
end

function BrainrotManager.SpawnFromPlacement(player: Player, data: any)
	if not GridManager then GridManager = _G.GridManager end
	
	local unitType = data.unitType or (data.Unit and data.Unit.unitType)
	local rarity = data.rarity or (data.Unit and data.Unit.rarity)
	local level = data.level or (data.Unit and data.Unit.level)
	
	if not unitType then return nil end
	
	local unit = BrainrotManager.AddUnit(player, unitType, rarity, level)
	if unit and GridManager and GridManager.PlaceUnit then
		GridManager.PlaceUnit(player, unit, data.slotIndex)
	end
	return unit
end

function BrainrotManager.SetInventoryData(player: Player, inventoryData: any)
	for unitName, rarityData in pairs(inventoryData) do
		for rarity, counts in pairs(rarityData) do
			if counts.total > 0 then
				BrainrotManager.AddUnit(player, unitName, rarity, counts.total)
			end
		end
	end
end

function BrainrotManager.UpdateAllUnitStats(player: Player)
	local plot = getPlayerPlot(player)
	if not plot then return end

	local brainrotsContainer = plot:FindFirstChild("Brainrots")
	if brainrotsContainer then
		for _, child in brainrotsContainer:GetChildren() do
			recalculateStats(child)
			-- Ensure cache is synced
			local uType = child:GetAttribute("UnitType")
			if uType then cacheUnit(player, uType, child) end
		end
	end
end

function BrainrotManager.GetPlayerPlot(player)
	return getPlayerPlot(player)
end

-- Spawn directly at slot (legacy wrapper)
function BrainrotManager.SpawnBrainrotAtSlot(player, unitName, slotIndex, rarity, level, unitId)
	if not GridManager then GridManager = _G.GridManager end
	
	task.spawn(function()
		local attempts = 0
		while not GridManager and attempts < 20 do
			attempts += 1
			GridManager = _G.GridManager
			task.wait(0.1)
		end
		
		if GridManager then
			local unit = spawnOrUpdateUnit(player, unitName, {
				level = level or 1,
				rarity = rarity or "Normal",
				unitId = unitId
			})
			
			if unit then
				GridManager.PlaceUnit(player, unit, slotIndex)
			end
		end
	end)
end

-- Compatibility Exports
BrainrotManager.SpawnBrainrot = BrainrotManager.AddUnit
BrainrotManager.RARITY_CONFIG = RarityConfig.CONFIG

--------------------------------------------------------------------------------
-- REMOTE HANDLERS
--------------------------------------------------------------------------------

BuyBrainrotRemote.OnServerEvent:Connect(function(player, unitName)
	-- TODO: Check money logic here
	BrainrotManager.AddUnit(player, unitName)
end)

GetInventoryRemote.OnServerInvoke = function(player)
	-- Reconstruct inventory view for client
	if not InventoryManager then InventoryManager = _G.InventoryManager end
	if not GridManager then GridManager = _G.GridManager end
	
	local inventory = { units = {} }
	
	if InventoryManager then
		local invData = InventoryManager.GetInventory(player)
		for unitName, unitData in pairs(invData) do
			local isPlaced = false
			-- Check if placed
			local unit = getCachedUnit(player, unitName)
			if unit and unit:GetAttribute("GridSlot") then
				isPlaced = true
			end
			
			inventory.units[unitName] = {
				level = unitData.level or 1,
				rarity = unitData.rarity or "Normal",
				status = isPlaced and "placed" or "stored"
			}
		end
	end
	
	return inventory
end

return BrainrotManager
