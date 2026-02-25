--[[
	BrainrotManager Server Module (Simplified)
	
	Handles spawning and visual updates of units.
	Acts as a listener to InventoryManager and GridManager.
]]

local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

-- Lazy Configs
local ShopConfig
local RarityConfig

local function getConfigs()
	if not ShopConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		ShopConfig = require(Shared:WaitForChild("ShopConfig"))
		RarityConfig = require(Shared:WaitForChild("RarityConfig"))
	end
	return ShopConfig, RarityConfig
end

-- Configuration
local CONFIG = {
	TIER_MILESTONES = {
		[10] = 2,
		[50] = 3,
		[100] = 4,
	}
}

local BRAINROT_TAG = "ActiveBrainrot"

-- References
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")

-- Events
local InventoryChangedEvent = RemoteEvents:FindFirstChild("InventoryChanged") or Instance.new("RemoteEvent")
InventoryChangedEvent.Name = "InventoryChanged"
InventoryChangedEvent.Parent = RemoteEvents

local BuyBrainrotRemote = RemoteEvents:FindFirstChild("BuyBrainrot") or Instance.new("RemoteEvent")
BuyBrainrotRemote.Name = "BuyBrainrot"
BuyBrainrotRemote.Parent = RemoteEvents

-- References (Lazy Loaded)
local BrainrotsFolder
local PlotsFolder

-- Module Table
local BrainrotManager = {}
local Services = {}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function getPlayerPlot(player: Player): Instance?
	if not PlotsFolder then PlotsFolder = workspace:FindFirstChild("Plots") end
	if not PlotsFolder then return nil end
	
	for _, plot in PlotsFolder:GetChildren() do
		local ownerId = plot:GetAttribute("OwnerId")
		if ownerId and ownerId == player.UserId then return plot end
	end
	return nil
end

local function _calculateItemTier(level: number): number
	local currentTier = 1
	local milestones = {10, 50, 100} 
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
	
	if not BrainrotsFolder then BrainrotsFolder = ReplicatedStorage:FindFirstChild("Brainrots") end
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

	if not unitName then return end
	
	local sc, _rc = getConfigs()
	local effectiveIncome = sc.CalculateEffectiveIncome(unitName, level)
	local effectiveCycleTime = sc.CalculateEffectiveCycleTime(unitName, level)
	local finalIncome = effectiveIncome
	local finalInterval = effectiveCycleTime

	local itemTier = _calculateItemTier(level)

	unit:SetAttribute("IncomeAmount", finalIncome)
	unit:SetAttribute("IncomeInterval", finalInterval)
	unit:SetAttribute("ItemTier", itemTier)

	-- Apply Tier-based Unit Scaling
	local scaleMultiplier = 1.0
	if itemTier == 2 then scaleMultiplier = 1.25
	elseif itemTier == 3 then scaleMultiplier = 1.5
	elseif itemTier >= 4 then scaleMultiplier = 2.0
	end
	
	if unit:IsA("Model") then
		unit:ScaleTo(scaleMultiplier)
		
		local player = _Players:GetPlayerByUserId(unit:GetAttribute("OwnerId"))
		if player then
			local GridManager = rawget(Services, "GridManager")
			if GridManager and GridManager.RegroundUnit then
				GridManager.RegroundUnit(player, unit)
			end
		end
	end

	updateVisuals(unit :: Model)
end

--[[
	Spawns or updates the physical model based on authoritative data.
]]
local function spawnOrUpdateUnit(player: Player, unitName: string, data: any): Instance?
	local plot = getPlayerPlot(player)
	if not plot then return nil end

	local brainrotsContainer = plot:FindFirstChild("Brainrots") or Instance.new("Folder", plot)
	brainrotsContainer.Name = "Brainrots"

	-- Look for existing unit in the container
	local existingUnit
	for _, child in brainrotsContainer:GetChildren() do
		if child:GetAttribute("UnitType") == unitName then
			existingUnit = child
			break
		end
	end

	if existingUnit then
		-- Update existing
		local level = data.level or data.Level or 1
		existingUnit:SetAttribute("Level", level)
		
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
		brainrot:SetAttribute("Level", level)
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
		
		return brainrot
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function BrainrotManager.Init(services)
	print("   BrainrotManager (Module) - Initializing")
	Services = services or {}
	
	-- Preload Configs
	getConfigs()
	
	local InventoryManager = rawget(Services, "InventoryManager")
	
	-- Connect to Inventory
	if InventoryManager and InventoryManager.UnitChanged then
		InventoryManager.UnitChanged:Connect(function(player, unitName, newData)
			if not unitName then
				-- Full reload
				BrainrotManager.UpdateAllUnitStats(player)
			else
				-- Single update
				-- CRITICAL CHANGE: Only update if a physical model ALREADY exists!
				-- New units bought from shop stay in inventory (virtual) until placed.
				local plot = getPlayerPlot(player)
				if plot then
					local brainrotsContainer = plot:FindFirstChild("Brainrots")
					if brainrotsContainer then
						local existing = nil
						for _, child in brainrotsContainer:GetChildren() do
							if child:GetAttribute("UnitType") == unitName then
								existing = child
								break
							end
						end
						
						if existing then
							spawnOrUpdateUnit(player, unitName, newData)
							
							-- Refresh all attributes (synergies/stats) after level up
							local IPM = rawget(Services, "ItemProductionManager")
							if IPM and IPM.RefreshUnitAttributes then
								IPM.RefreshUnitAttributes(player)
							end
						end
					end
				end
			end
		end)
	else
		warn("BrainrotManager: InventoryManager missing or UnitChanged signal not found.")
	end
	
	print("✓ BrainrotManager Initialized")
end

-- Exposed for GridManager to spawn units when placed from inventory
function BrainrotManager.SpawnForGrid(player: Player, unitName: string, data: any): Instance?
	return spawnOrUpdateUnit(player, unitName, data)
end

function BrainrotManager.AddUnit(player: Player, unitName: string, forceLevel: number?): Instance?
	-- Delegate to InventoryManager
	local InventoryManager = rawget(Services, "InventoryManager")
	
	if InventoryManager then
		local newData = InventoryManager.AddUnit(player, unitName, forceLevel)
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
	local GridManager = rawget(Services, "GridManager")
	local placements = {}
	
	if GridManager and GridManager.GetGridPositions then
		local gridPos = GridManager.GetGridPositions(player)
		for slot, data in pairs(gridPos) do
			if data.Unit then
				local entry = {}
				entry.slotIndex = tonumber(slot)
				
				local unitData = data.Unit
				entry.unitType = unitData.unitType
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
	local GridManager = rawget(Services, "GridManager")
	
	local unitType = data.unitType or (data.Unit and data.Unit.unitType)
	local level = data.level or (data.Unit and data.Unit.level)
	local unitId = data.unitId or (data.Unit and data.Unit.unitId)
	
	if not unitType then return nil end
	
	local unit = spawnOrUpdateUnit(player, unitType, {
		level = level,
		unitId = unitId
	})
	
	if unit and GridManager and GridManager.PlaceUnit then
		GridManager.PlaceUnit(player, unit, data.slotIndex)
	end
	return unit
end

function BrainrotManager.SetInventoryData(player: Player, inventoryData: any)
	for unitName, levelData in pairs(inventoryData) do
		if levelData.total > 0 then
			BrainrotManager.AddUnit(player, unitName, levelData.total)
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
		end
	end
end

function BrainrotManager.GetPlayerPlot(player)
	return getPlayerPlot(player)
end

-- Compatibility Exports
BrainrotManager.SpawnBrainrot = BrainrotManager.AddUnit
BrainrotManager.RARITY_CONFIG = nil -- RarityConfig.CONFIG

--------------------------------------------------------------------------------
-- REMOTE HANDLERS
--------------------------------------------------------------------------------

BuyBrainrotRemote.OnServerEvent:Connect(function(player, unitName)
	-- Pass to ShopManager properly in future cleanup, for now delegate to internal AddUnit
	-- Or check money here if logic was embedded
	BrainrotManager.AddUnit(player, unitName)
end)

function BrainrotManager.ClearAllUnits(player)
	local plot = getPlayerPlot(player)
	if plot then
		local brainrotsContainer = plot:FindFirstChild("Brainrots")
		if brainrotsContainer then
			brainrotsContainer:ClearAllChildren()
		end
	end
end

return BrainrotManager
