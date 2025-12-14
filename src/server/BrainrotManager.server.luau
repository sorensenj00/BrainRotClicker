--[[
	BrainrotManager Server Script (Stacking Version)
	
	Handles:
	1. Spawning ONE unique unit per type per player.
	2. Stacking purchases to upgrade Level/Speed.
	3. Calculating item tiers based on level milestones.
	4. Calculating effective income/stats based on ShopConfig + RarityConfig.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local _RunService = game:GetService("RunService")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local _SynergyConfig = require(Shared:WaitForChild("SynergyConfig"))
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local RarityConfig = require(Shared:WaitForChild("RarityConfig"))

-- Configuration
local CONFIG = {
	-- Tier milestones are handled in recalculateStats via logic,
	-- but we keep the mapping here for reference or if used elsewhere.
	TIER_MILESTONES = {
		[10] = 2, -- At Level 10, produce Tier 2 items
		[25] = 3, -- At Level 25, produce Tier 3 items
		[50] = 4, -- At Level 50, produce Tier 4 items
		[100] = 5, -- At Level 100, produce Tier 5 items
	}
}

-- Tags
local BRAINROT_TAG = "ActiveBrainrot"

-- References
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")
local PlotsFolder = workspace:WaitForChild("Plots")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

-- Events
local InventoryChangedEvent = RemoteEvents:FindFirstChild("InventoryChanged") or Instance.new("RemoteEvent")
InventoryChangedEvent.Name = "InventoryChanged"
InventoryChangedEvent.Parent = RemoteEvents

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

-- Determine Item Tier based on Level
local function _calculateItemTier(level: number): number
	local currentTier = 1
	-- Check milestones. If level >= milestone, set tier.
	-- We iterate in order to ensure we get the highest applicable tier.
	local milestones = {10, 25, 50, 100} 
	for _, reqLevel in ipairs(milestones) do
		if level >= reqLevel then
			currentTier = CONFIG.TIER_MILESTONES[reqLevel]
		end
	end
	return currentTier
end

-- Update the visual stats overhead (BillboardGui)
local function updateVisuals(brainrot: Model)
	local level = brainrot:GetAttribute("Level") or 1
	local tier = brainrot:GetAttribute("ItemTier") or 1
	local rarity = brainrot:GetAttribute("Rarity") or "Normal"
	
	-- Look for a BillboardGui named "StatsDisplay" inside the model
	local head = brainrot:FindFirstChild("Head") or brainrot.PrimaryPart
	if head then
		local gui = head:FindFirstChild("StatsDisplay")
		if not gui then
			-- Create GUI if missing
			gui = Instance.new("BillboardGui")
			gui.Name = "StatsDisplay"
			gui.Size = UDim2.new(4,0, 2,0)
			gui.StudsOffset = Vector3.new(0, 3, 0)
			gui.Parent = head
			
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1,0,1,0)
			label.BackgroundTransparency = 1
			label.TextScaled = true
			label.Font = Enum.Font.FredokaOne
			label.Parent = gui
		end
		
		local label = gui:FindFirstChild("TextLabel")
		if label then
			local rarityColor = RarityConfig.GetColor(rarity)
			label.TextColor3 = rarityColor
			label.Text = string.format("Lvl %d | Tier %d\n%s", level, tier, rarity)
		end
	end
end

--------------------------------------------------------------------------------
-- CORE LOGIC
--------------------------------------------------------------------------------

--[[
	Finds the brainrot model template from various locations.
]]
local function getBrainrotTemplate(unitName: string): Model?
	-- 1. Check Assets/Brainrots (Preferred location for visuals)
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder then
		local brainrotsSubfolder = assetsFolder:FindFirstChild("Brainrots")
		if brainrotsSubfolder then
			local model = brainrotsSubfolder:FindFirstChild(unitName)
			if model then return model end
		end
	end
	
	-- 2. Check Units folder
	local unitsFolder = ReplicatedStorage:FindFirstChild("Units")
	if unitsFolder then
		local model = unitsFolder:FindFirstChild(unitName)
		if model then return model end
	end
	
	-- 3. Check main Brainrots folder (Fallback)
	if BrainrotsFolder then
		local model = BrainrotsFolder:FindFirstChild(unitName)
		if model then return model end
	end
	
	return nil
end

--[[
	Recalculates stats (Income, Interval, Tier) and applies them to the unit.
]]
local function recalculateStats(unit: Instance)
	local unitName = unit:GetAttribute("UnitType")
	local level = unit:GetAttribute("Level") or 1
	local rarity = unit:GetAttribute("Rarity") or "Normal"

	if not unitName then return end

	-- 1. Base Stats from ShopConfig (Milestones included)
	local effectiveIncome = ShopConfig.CalculateEffectiveIncome(unitName, level)
	local effectiveCycleTime = ShopConfig.CalculateEffectiveCycleTime(unitName, level)

	-- 2. Rarity Multipliers
	local rarityMult = RarityConfig.GetMultiplier(rarity)

	-- 3. Final Calculation
	-- Income is multiplied by rarity
	local finalIncome = math.floor(effectiveIncome * rarityMult)
	
	-- Interval (Speed) is DIVIDED by rarity multiplier (higher rarity = faster)
	-- Note: CalculateEffectiveCycleTime already includes speed milestones
	local finalInterval = math.max(0.1, effectiveCycleTime / rarityMult)

	-- 4. Apply Attributes
	unit:SetAttribute("IncomeAmount", finalIncome)
	unit:SetAttribute("IncomeInterval", finalInterval)
	unit:SetAttribute("ItemTier", _calculateItemTier(level))

	-- Update Visuals
	updateVisuals(unit)
end

--[[
	Internal: Spawns or updates the physical model based on authoritative data.
]]
local function spawnOrUpdateUnit(player: Player, unitName: string, data: {Level: number, Rarity: string}): Instance?
	local plot = getPlayerPlot(player)
	if not plot then
		-- Plot might not be ready on join, retry loop handled elsewhere?
		-- For now just warn.
		return nil
	end

	local brainrotsContainer = plot:FindFirstChild("Brainrots") or Instance.new("Folder", plot)
	brainrotsContainer.Name = "Brainrots"

	-- 1. Check if unit already exists
	local existingUnit = nil
	for _, child in brainrotsContainer:GetChildren() do
		if child:GetAttribute("UnitType") == unitName then
			existingUnit = child
			break
		end
	end

	if existingUnit then
		-- Update attributes from data
		existingUnit:SetAttribute("Level", data.Level)
		existingUnit:SetAttribute("Rarity", data.Rarity)
		
		-- Recalculate Stats
		recalculateStats(existingUnit)
		return existingUnit
	else
		-- Spawn new
		local template = getBrainrotTemplate(unitName)
		if not template then
			warn("Template not found:", unitName)
			return nil
		end
		
		local brainrot = template:Clone()
		brainrot.Name = unitName
		
		-- Set Attributes
		brainrot:SetAttribute("OwnerId", player.UserId)
		brainrot:SetAttribute("UnitType", unitName)
		brainrot:SetAttribute("Level", data.Level)
		brainrot:SetAttribute("Rarity", data.Rarity)
		
		-- Store unit hidden (Option B: player places via BuildMode)
		brainrot:SetAttribute("GridSlot", nil)
		brainrot:SetAttribute("IsStored", true)
		
		local plotCF = plot:GetPivot() -- Assuming Plot is a Model
		if plot.PrimaryPart then plotCF = plot.PrimaryPart.CFrame end
		
		-- Offset: Start left, move right
		local offset = Vector3.new(0, -100, 0)
		local spawnCF = plotCF * CFrame.new(offset)
		
		brainrot:PivotTo(spawnCF)
		
		-- Finalize
		brainrot.Parent = brainrotsContainer
		CollectionService:AddTag(brainrot, BRAINROT_TAG)
		
		-- Recalculate Stats (Initial Setup)
		recalculateStats(brainrot)

		-- Ensure anchored
		for _, part in brainrot:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		
		print("Spawned new unit (View):", unitName)
		return brainrot
	end
end

--[[
	Public API: Adds a brainrot to the player.
	NOW DELEGATES TO INVENTORY MANAGER.
	
	@return Instance? - Returns the unit if immediate spawn, but mostly relies on event.
]]
local function addBrainrotToPlayer(player: Player, unitName: string, forceRarity: string?, forceLevel: number?): Instance?
	-- Legacy/Shop compatibility:
	-- If called, we update the Data Model.
	-- The Data Model will fire an event, which calls spawnOrUpdateUnit.

	if _G.InventoryManager then
		local newData = _G.InventoryManager.AddUnit(player, unitName, forceRarity, forceLevel)
		-- We can return the unit if we find it, but it might take a frame to spawn via event?
		-- For now, we can manually call spawnOrUpdateUnit to ensure immediate return for ShopManager logic
		-- (ShopManager expects a return value to verify success, though we removed stat logic from it).

		return spawnOrUpdateUnit(player, unitName, newData)
	else
		warn("BrainrotManager: InventoryManager not found!")
		return nil
	end
end

--[[
	Stash a brainrot (called by GridManager).
]]
local function stashBrainrot(player: Player, brainrot: Instance)
	-- Just notify client to update inventory UI
	InventoryChangedEvent:FireClient(player)
end

--[[
	Get placement data for saving.
]]
local function getPlacementData(player: Player)
	local placements = {}
	if _G.GridManager and _G.GridManager.GetGridPositions then
		local gridPos = _G.GridManager.GetGridPositions(player)
		for slot, data in pairs(gridPos) do
			if data.Unit then
				-- Handle layered data structure: {Unit={...}, Tile=...}
				local entry = {}
				entry.slotIndex = tonumber(slot)
				
				local unitData = data.Unit
				entry.unitType = unitData.unitType
				entry.rarity = unitData.rarity
				entry.level = unitData.level
				-- entry.unitId = unitData.unitId
				
				table.insert(placements, entry)
			elseif data.unitType then
				-- Handle legacy flat structure (fallback)
				local entry = table.clone(data)
				entry.slotIndex = tonumber(slot)
				table.insert(placements, entry)
			end
		end
	end
	return placements
end

--[[
	Spawn a unit from placement data (loading).
]]
local function spawnFromPlacement(player: Player, data: any)
	-- data: {unitType, rarity, level, slotIndex}
	if not data then return nil end
	
	-- Extract data (handle both flat and nested structures)
	local unitType = data.unitType
	local rarity = data.rarity
	local level = data.level
	
	if not unitType and data.Unit then
		unitType = data.Unit.unitType
		rarity = data.Unit.rarity
		level = data.Unit.level
	end

	if not unitType then
		warn("BrainrotManager: Invalid placement data for player " .. player.Name)
		return nil
	end
	
	local unit = addBrainrotToPlayer(player, unitType, rarity, level)
	if unit and _G.GridManager and _G.GridManager.PlaceUnit then
		_G.GridManager.PlaceUnit(player, unit, data.slotIndex)
	end
	return unit
end

--[[
	Set inventory data (Legacy support / Loading).
]]
local function setInventoryData(player: Player, inventoryData: any)
	-- inventoryData: {[unitName]: {[rarity]: {total, active}}}
	-- Convert legacy multi-unit counts to single unit levels
	for unitName, rarityData in pairs(inventoryData) do
		for rarity, counts in pairs(rarityData) do
			if counts.total > 0 then
				-- Use 'total' as the level for the new system
				addBrainrotToPlayer(player, unitName, rarity, counts.total)
			end
		end
	end
end

--[[
	Force update all unit stats (call this if ShopConfig changes or for migration).
]]
local function updateAllUnitStats(player: Player)
	local plot = getPlayerPlot(player)
	if not plot then return end

	local brainrotsContainer = plot:FindFirstChild("Brainrots")
	if brainrotsContainer then
		for _, child in brainrotsContainer:GetChildren() do
			recalculateStats(child)
		end
	end
end

--------------------------------------------------------------------------------
-- REMOTE HANDLERS
--------------------------------------------------------------------------------

-- Connect this to your UI "Buy" button
local BuyBrainrotRemote = RemoteEvents:FindFirstChild("BuyBrainrot") or Instance.new("RemoteEvent")
BuyBrainrotRemote.Name = "BuyBrainrot"
BuyBrainrotRemote.Parent = RemoteEvents

BuyBrainrotRemote.OnServerEvent:Connect(function(player, unitName)
	-- TODO: Add Money Check here!
	-- local cost = ItemConfig.GetCost(unitName, currentLevel)
	-- if player.Money >= cost then ...
	
	addBrainrotToPlayer(player, unitName)
end)

local GetInventoryRemote = RemoteEvents:FindFirstChild("GetInventory") or Instance.new("RemoteFunction")
GetInventoryRemote.Name = "GetInventory"
GetInventoryRemote.Parent = RemoteEvents

-- Initialization
-- Get Inventory Data (New Structure)
local function getInventoryData(player: Player)
	local inventory = {
		units = {}
	}
	
	-- 1. Get Owned Units (Levels) from ShopManager
	local ownedUnits = {}
	if _G.ShopManager and _G.ShopManager.GetPlayerOwnership then
		local data = _G.ShopManager.GetPlayerOwnership(player)
		if data and data.units then
			for unitName, unitData in pairs(data.units) do
				ownedUnits[unitName] = {
					level = unitData.count, -- count is level now
					rarity = "Normal" -- Default, will update from actual instance if exists
				}
			end
		end
	end
	
	-- 2. Check Placed Status from GridManager
	local placedUnits = {}
	if _G.GridManager and _G.GridManager.GetGridPositions then
		local gridPositions = _G.GridManager.GetGridPositions(player)
		for _, posData in pairs(gridPositions) do
			-- Handle layered grid structure {Unit = {...}, Tile = ...}
			if posData.Unit and posData.Unit.unitType then
				placedUnits[posData.Unit.unitType] = true
			elseif posData.unitType then
				-- Fallback for old format (just in case)
				placedUnits[posData.unitType] = true
			end
		end
	end
	
	-- 3. Check Rarity from actual instances (Brainrots folder)
	local plot = getPlayerPlot(player)
	if plot then
		local brainrotsContainer = plot:FindFirstChild("Brainrots")
		if brainrotsContainer then
			for _, child in brainrotsContainer:GetChildren() do
				local unitName = child:GetAttribute("UnitType")
				if unitName and ownedUnits[unitName] then
					ownedUnits[unitName].rarity = child:GetAttribute("Rarity") or "Normal"
				end
			end
		end
	end
	
	-- 4. Construct Final Inventory
	for unitName, data in pairs(ownedUnits) do
		inventory.units[unitName] = {
			level = data.level,
			rarity = data.rarity,
			status = placedUnits[unitName] and "placed" or "stored"
		}
	end
	
	return inventory
end

GetInventoryRemote.OnServerInvoke = function(player)
	return getInventoryData(player)
end

local function onPlayerRemoving(player)
	-- Cleanup is handled automatically if Brainrots are parented to Plot, 
	-- but if parented elsewhere, destroy them here.
end

Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Wait for InventoryManager and connect listener
task.spawn(function()
	local attempts = 0
	while not _G.InventoryManager and attempts < 100 do
		attempts += 1
		task.wait(0.1)
	end

	if _G.InventoryManager then
		_G.InventoryManager.UnitChanged:Connect(function(player, unitName, newData)
			if not unitName then
				-- Full reload (e.g. from DataManager)
				updateAllUnitStats(player)
				-- Also need to spawn missing units?
				-- For data restore, we iterate inventory.
				local inventory = _G.InventoryManager.GetInventory(player)
				for name, data in pairs(inventory) do
					spawnOrUpdateUnit(player, name, data)
				end
			else
				-- Single unit update
				spawnOrUpdateUnit(player, unitName, newData)
			end
		end)
		print("✓ BrainrotManager connected to InventoryManager")
	else
		warn("BrainrotManager: Could not connect to InventoryManager!")
	end
end)

print("✓ BrainrotManager (Stacking) Initialized")

-- Export API
_G.BrainrotManager = {
	AddUnit = addBrainrotToPlayer,
	SpawnBrainrot = addBrainrotToPlayer, -- Alias for compatibility
	StashBrainrot = stashBrainrot,
	GetPlacementData = getPlacementData,
	SpawnFromPlacement = spawnFromPlacement,
	SetInventoryData = setInventoryData,
	GetPlayerPlot = getPlayerPlot, -- Exposed for DataManager
	UpdateAllUnitStats = updateAllUnitStats,
	RARITY_CONFIG = RarityConfig.CONFIG, -- Export config for compatibility
	
	GetUnitLevel = function(player, unitName)
		local plot = getPlayerPlot(player)
		if not plot then return 0 end
		
		local brainrotsContainer = plot:FindFirstChild("Brainrots")
		if not brainrotsContainer then return 0 end
		
		for _, child in brainrotsContainer:GetChildren() do
			if child:GetAttribute("UnitType") == unitName then
				return child:GetAttribute("Level") or 1
			end
		end
		return 0
	end,
	
	GetInventoryData = function(player)
		return getInventoryData(player).units -- Return just the units table for DataManager compatibility
	end,
}
