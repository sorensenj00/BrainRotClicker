--[[
	BrainrotManager Server Script (Stacking Version)
	
	Handles:
	1. Spawning ONE unique unit per type per player.
	2. Stacking purchases to upgrade Level/Speed.
	3. Calculating item tiers based on level milestones.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local _RunService = game:GetService("RunService")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local _SynergyConfig = require(Shared:WaitForChild("SynergyConfig"))
-- local ItemConfig = require(Shared:WaitForChild("ItemConfig")) -- Uncomment if needed

-- Configuration
local CONFIG = {
	BASE_INTERVAL = 5,          -- Base seconds to produce an item
	SPEED_DECAY = 0.95,         -- Each level multiplies speed by 0.95 (5% faster per level)
	MIN_INTERVAL = 0.5,         -- Cap on how fast it can go
	
	-- Level Milestones for Item Tiers
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
-- RARITY SYSTEM
--------------------------------------------------------------------------------
local RARITY_CONFIG = {
	Normal = { chance = 0.90, multiplier = 1, color = Color3.fromRGB(255, 255, 255) },
	Spicy = { chance = 0.09, multiplier = 1.5, color = Color3.fromRGB(255, 80, 80) },
	Galaxy = { chance = 0.01, multiplier = 3.0, color = Color3.fromRGB(180, 100, 255) },
}
local RARITY_ORDER = {"Normal", "Spicy", "Galaxy"}

local function rollRarity(): string
	local roll = math.random()
	local cumulative = 0
	for _, rarityName in RARITY_ORDER do
		cumulative = cumulative + RARITY_CONFIG[rarityName].chance
		if roll <= cumulative then return rarityName end
	end
	return "Normal"
end

local function getRarityValue(rarityName)
	for i, name in ipairs(RARITY_ORDER) do
		if name == rarityName then return i end
	end
	return 1
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
			local rarityColor = RARITY_CONFIG[rarity].color
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
	Adds a brainrot to the player.
	If they already have this unit type -> Stacks (Level Up).
	If they don't -> Spawns new.
	
	Optional arguments forceRarity and forceLevel are used for data restoration.
]]
local function addBrainrotToPlayer(player: Player, unitName: string, forceRarity: string?, forceLevel: number?): Instance?
	local plot = getPlayerPlot(player)
	if not plot then
		warn("No plot found for", player.Name)
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

	-- 2. Determine Rarity (Roll or Force)
	local newRarity = forceRarity or rollRarity()

	if existingUnit then
		-------------------------------------------------------
		-- UPGRADE EXISTING UNIT
		-------------------------------------------------------
		local currentLevel = existingUnit:GetAttribute("Level") or 1
		local currentRarity = existingUnit:GetAttribute("Rarity") or "Normal"
		
		-- Update Level
		local newLevel = forceLevel or (currentLevel + 1)
		existingUnit:SetAttribute("Level", newLevel)
		
		-- Update Rarity
		if forceRarity then
			existingUnit:SetAttribute("Rarity", forceRarity)
		elseif getRarityValue(newRarity) > getRarityValue(currentRarity) then
			existingUnit:SetAttribute("Rarity", newRarity)
			print(player.Name .. " upgraded " .. unitName .. " rarity to " .. newRarity .. "!")
			-- Optional: Add visual effect for rarity upgrade here
		end

		-- Recalculate Stats
		local _rarityMult = RARITY_CONFIG[existingUnit:GetAttribute("Rarity")].multiplier
		
	else
		-------------------------------------------------------
		-- SPAWN NEW UNIT
		-------------------------------------------------------
		local template = getBrainrotTemplate(unitName)
		if not template then
			warn("Template not found:", unitName)
			return nil
		end
		
		local brainrot = template:Clone()
		brainrot.Name = unitName -- Keep name simple or unique
		
		-- Set Initial Attributes
		brainrot:SetAttribute("OwnerId", player.UserId)
		brainrot:SetAttribute("UnitType", unitName)
		brainrot:SetAttribute("Level", forceLevel or 1)
		brainrot:SetAttribute("Rarity", newRarity)
		brainrot:SetAttribute("ItemTier", 1) -- Starts at Tier 1
		
		-- Calculate Initial Speed
		local rarityMult = RARITY_CONFIG[newRarity].multiplier
		local initialInterval = CONFIG.BASE_INTERVAL / rarityMult
		brainrot:SetAttribute("IncomeInterval", initialInterval)
		
		-- Store unit hidden (Option B: player places via BuildMode)
		brainrot:SetAttribute("GridSlot", nil)
		brainrot:SetAttribute("IsStored", true)
		
		
		
		
		local plotCF = plot:GetPivot() -- Assuming Plot is a Model
		if plot.PrimaryPart then plotCF = plot.PrimaryPart.CFrame end
		
		-- Offset: Start left, move right
		local offset = Vector3.new(0, -100, 0) -- Hidden below plot until placed via BuildMode
		local spawnCF = plotCF * CFrame.new(offset)
		
		brainrot:PivotTo(spawnCF)
		
		-- Finalize
		brainrot.Parent = brainrotsContainer
		CollectionService:AddTag(brainrot, BRAINROT_TAG)
		updateVisuals(brainrot)
		
		-- Ensure anchored so it doesn't fall (especially when stored at -100 Y)
		for _, part in brainrot:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		
		print("Spawned new unit:", unitName)
		
		-- Notify Client (for UI updates)
		InventoryChangedEvent:FireClient(player)
		
		return brainrot
	end
	
	-- Notify Client (for UI updates)
	InventoryChangedEvent:FireClient(player)
	return existingUnit
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