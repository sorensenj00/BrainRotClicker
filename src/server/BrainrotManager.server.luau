--[[
	BrainrotManager Server Script
	
	Handles:
	1. Leaderstats creation for players
	2. Spawning Brainrot units on player plots
	3. Income generation loop for active brainrots (stores to Plot storage)
	4. Storage part creation with visual display
	
	The client LocalScript should listen for "ActiveBrainrot" tagged objects
	using CollectionService to handle visual progress bars.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- Wait for shared modules
local SynergyConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SynergyConfig"))

-- Configuration
local CONFIG = {
	INCOME_INTERVAL = 3,        -- Seconds between income ticks
	INCOME_AMOUNT = 10,         -- Money earned per brainrot per tick
	SPAWN_OFFSET_RANGE = 15,    -- Random spawn offset range
	SPAWN_HEIGHT = 10,          -- Height above plot surface
	STARTING_MONEY = 1000,      -- Starting money for new players
	DEFAULT_MAX_STORAGE = 500,  -- Default max storage capacity
}

-- Tags
local BRAINROT_TAG = "ActiveBrainrot"

-- References
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")
local PlotsFolder = workspace:WaitForChild("Plots")

-- Remote Events for client communication
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

-- Create SpawnBrainrot remote event (for client to request spawns)
local SpawnBrainrotEvent = RemoteEvents:FindFirstChild("SpawnBrainrot") or Instance.new("RemoteEvent")
SpawnBrainrotEvent.Name = "SpawnBrainrot"
SpawnBrainrotEvent.Parent = RemoteEvents

-- Create inventory management remote events
local GetInventoryRemote = RemoteEvents:FindFirstChild("GetInventory") or Instance.new("RemoteFunction")
GetInventoryRemote.Name = "GetInventory"
GetInventoryRemote.Parent = RemoteEvents

local PlaceBrainrotRemote = RemoteEvents:FindFirstChild("PlaceBrainrot") or Instance.new("RemoteFunction")
PlaceBrainrotRemote.Name = "PlaceBrainrot"
PlaceBrainrotRemote.Parent = RemoteEvents

local RemoveBrainrotRemote = RemoteEvents:FindFirstChild("RemoveBrainrot") or Instance.new("RemoteFunction")
RemoveBrainrotRemote.Name = "RemoveBrainrot"
RemoveBrainrotRemote.Parent = RemoteEvents

local InventoryChangedEvent = RemoteEvents:FindFirstChild("InventoryChanged") or Instance.new("RemoteEvent")
InventoryChangedEvent.Name = "InventoryChanged"
InventoryChangedEvent.Parent = RemoteEvents

--------------------------------------------------------------------------------
-- RARITY SYSTEM (RNG Traits)
--------------------------------------------------------------------------------

--[[
	Rarity configuration inspired by Sols RNG.
	Each purchase rolls for a rarity that affects income multiplier and visual style.
]]
local RARITY_CONFIG = {
	Normal = {
		chance = 0.90,       -- 90% drop rate
		incomeMultiplier = 1, -- Base income
		color = Color3.fromRGB(255, 255, 255), -- White
		displayName = "Normal",
	},
	Spicy = {
		chance = 0.09,       -- 9% drop rate
		incomeMultiplier = 2, -- 2x income
		color = Color3.fromRGB(255, 80, 80),   -- Red
		displayName = "🌶️ Spicy",
	},
	Galaxy = {
		chance = 0.01,       -- 1% drop rate
		incomeMultiplier = 10, -- 10x income
		color = Color3.fromRGB(180, 100, 255), -- Purple/Shiny
		displayName = "🌌 Galaxy",
	},
}

-- Ordered list for iteration
local RARITY_ORDER = {"Normal", "Spicy", "Galaxy"}

--[[
	Rolls for a rarity based on configured drop rates.
	@return string - The rolled rarity name
]]
local function rollRarity(): string
	local roll = math.random()
	local cumulative = 0
	
	for _, rarityName in RARITY_ORDER do
		cumulative = cumulative + RARITY_CONFIG[rarityName].chance
		if roll <= cumulative then
			return rarityName
		end
	end
	
	return "Normal" -- Fallback
end

--------------------------------------------------------------------------------
-- INVENTORY TRACKING
--------------------------------------------------------------------------------

--[[
	PlayerInventory tracks brainrots per unit type AND rarity.
	Structure: {[Player]: {[unitName]: {[rarity]: {total: number, active: number}}}}
	
	Example:
	{
		["Avocadini Guffo"] = {
			Normal = {total = 5, active = 3},
			Spicy = {total = 1, active = 1},
			Galaxy = {total = 0, active = 0},
		}
	}
]]
local PlayerInventory: {[Player]: {[string]: {[string]: {total: number, active: number}}}} = {}

--------------------------------------------------------------------------------
-- LEADERSTATS
--------------------------------------------------------------------------------

--[[
	Creates leaderstats folder with Money value for a player.
	
	@param player Player - The player to create leaderstats for
]]
local function setupLeaderstats(player: Player)
	-- Check if leaderstats already exists (avoid duplicates)
	if player:FindFirstChild("leaderstats") then
		return
	end
	
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player
	
	local money = Instance.new("IntValue")
	money.Name = "Money"
	money.Value = CONFIG.STARTING_MONEY
	money.Parent = leaderstats
	
	print(string.format("✓ Created leaderstats for %s", player.Name))
end

--------------------------------------------------------------------------------
-- PLOT UTILITIES
--------------------------------------------------------------------------------

--[[
	Finds the plot model owned by a specific player.
	
	@param player Player - The player to find the plot for
	@return Model? - The plot model, or nil if not found
]]
local function getPlayerPlot(player: Player): Instance?
	for _, plot in PlotsFolder:GetChildren() do
		if plot:IsA("Model") or plot:IsA("Folder") then
			local ownerId = plot:GetAttribute("OwnerId")
			if ownerId and ownerId == player.UserId then
				return plot
			end
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- STORAGE SYSTEM
--------------------------------------------------------------------------------

--[[
	Creates a Storage part on the player's plot with BillboardGui and Smoke effect.
	Called when a plot is assigned to a player.
	
	@param plot Instance - The plot to add storage to
	@param plotCFrame CFrame - The plot's CFrame for positioning
]]
local function createStoragePart(plot: Instance, plotCFrame: CFrame)
	-- Check if Storage already exists
	if plot:FindFirstChild("Storage") then
		return plot:FindFirstChild("Storage")
	end
	
	-- Create the Storage part
	local storagePart = Instance.new("Part")
	storagePart.Name = "Storage"
	storagePart.Size = Vector3.new(6, 4, 6)
	storagePart.BrickColor = BrickColor.new("Dark stone grey")
	storagePart.Material = Enum.Material.DiamondPlate
	storagePart.Anchored = true
	storagePart.CanCollide = true
	-- Position near the front of the plot
	storagePart.CFrame = plotCFrame * CFrame.new(25, 10, 0)
	storagePart.Parent = plot
	
	-- Create BillboardGui for display
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "StorageDisplay"
	billboardGui.Size = UDim2.new(4, 0, 2, 0)
	billboardGui.StudsOffset = Vector3.new(0, 4, 0)
	billboardGui.AlwaysOnTop = false
	billboardGui.Parent = storagePart
	
	-- Background frame
	local bgFrame = Instance.new("Frame")
	bgFrame.Name = "Background"
	bgFrame.Size = UDim2.new(1, 0, 1, 0)
	bgFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	bgFrame.BackgroundTransparency = 0.3
	bgFrame.Parent = billboardGui
	
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0.1, 0)
	uiCorner.Parent = bgFrame
	
	-- Title label
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.4, 0)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "💰 STORAGE"
	titleLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = bgFrame
	
	-- Amount label
	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "Amount"
	amountLabel.Size = UDim2.new(1, 0, 0.5, 0)
	amountLabel.Position = UDim2.new(0, 0, 0.4, 0)
	amountLabel.BackgroundTransparency = 1
	amountLabel.Text = "$0 / $500"
	amountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	amountLabel.TextScaled = true
	amountLabel.Font = Enum.Font.GothamBold
	amountLabel.Parent = bgFrame
	
	-- Create Smoke particle (disabled by default)
	local smoke = Instance.new("Smoke")
	smoke.Name = "OverflowSmoke"
	smoke.Color = Color3.fromRGB(100, 100, 100)
	smoke.Opacity = 0.3
	smoke.RiseVelocity = 3
	smoke.Size = 2
	smoke.Enabled = false
	smoke.Parent = storagePart
	
	-- Initialize storage attributes on plot
	if not plot:GetAttribute("CurrentStorage") then
		plot:SetAttribute("CurrentStorage", 0)
	end
	if not plot:GetAttribute("MaxStorage") then
		plot:SetAttribute("MaxStorage", CONFIG.DEFAULT_MAX_STORAGE)
	end
	
	print(string.format("✓ Created Storage part for plot"))
	return storagePart
end

--[[
	Updates the Storage visual display and overflow effect.
	
	@param plot Instance - The plot containing the Storage
	@param currentStorage number - Current stored amount
	@param maxStorage number - Maximum storage capacity
]]
local function updateStorageVisual(plot: Instance, currentStorage: number, maxStorage: number)
	local storagePart = plot:FindFirstChild("Storage")
	if not storagePart then return end
	
	-- Update display text
	local billboardGui = storagePart:FindFirstChild("StorageDisplay")
	if billboardGui then
		local bgFrame = billboardGui:FindFirstChild("Background")
		if bgFrame then
			local amountLabel = bgFrame:FindFirstChild("Amount")
			if amountLabel then
				amountLabel.Text = string.format("$%d / $%d", currentStorage, maxStorage)
				-- Change color based on fill level
				if currentStorage >= maxStorage then
					amountLabel.TextColor3 = Color3.fromRGB(255, 100, 100) -- Red when full
				elseif currentStorage >= maxStorage * 0.75 then
					amountLabel.TextColor3 = Color3.fromRGB(255, 200, 100) -- Orange when 75%+
				else
					amountLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- White normally
				end
			end
		end
	end
	
	-- Toggle smoke effect when full
	local smoke = storagePart:FindFirstChild("OverflowSmoke")
	if smoke then
		smoke.Enabled = (currentStorage >= maxStorage)
	end
end

-- Grid configuration for 2 rows of 6 models on each side of the plot
local GRID_CONFIG = {
	MODELS_PER_ROW = 6,     -- 6 models per side
	SPACING = 8,            -- Distance between each brainrot along the row
	SIDE_OFFSET = 15,       -- Distance from center line to each row (Z axis)
	START_OFFSET_X = -20,   -- Starting X offset from plot center
}

-- Track next grid index per plot
local PlotGridIndex: {[Instance]: number} = {}

--[[
	Gets the next available grid position for a plot.
	Arranges models in 2 lines of 6 on opposite sides of the plot.
	Models face inward toward the center line.
	
	@param plot Instance - The plot to get a grid position for
	@param plotCFrame CFrame - The center CFrame of the plot
	@return CFrame - The grid spawn CFrame (includes rotation facing inward)
]]
local function getGridSpawnCFrame(plot: Instance, plotCFrame: CFrame): CFrame
	-- Get current grid index for this plot (or start at 0)
	local gridIndex = PlotGridIndex[plot] or 0
	
	-- Determine which side (0 = front row, 1 = back row) and position in row
	local side = math.floor(gridIndex / GRID_CONFIG.MODELS_PER_ROW) -- 0 or 1
	local positionInRow = gridIndex % GRID_CONFIG.MODELS_PER_ROW    -- 0-5
	
	-- Calculate X offset (position along the row)
	local offsetX = GRID_CONFIG.START_OFFSET_X + (positionInRow * GRID_CONFIG.SPACING)
	
	-- Calculate Z offset (which side of the center line)
	-- Side 0 = negative Z (front), Side 1 = positive Z (back)
	local offsetZ = (side == 0) and -GRID_CONFIG.SIDE_OFFSET or GRID_CONFIG.SIDE_OFFSET
	
	-- Calculate rotation to face inward toward center line
	-- Front row (side 0) faces +Z direction (toward center)
	-- Back row (side 1) faces -Z direction (toward center)
	local rotationY = (side == 0) and 0 or math.pi  -- 0° or 180°
	
	local offset = Vector3.new(offsetX, CONFIG.SPAWN_HEIGHT, offsetZ)
	
	-- Increment grid index for next spawn
	PlotGridIndex[plot] = gridIndex + 1
	
	-- Return CFrame with position and rotation facing inward
	return plotCFrame * CFrame.new(offset) * CFrame.Angles(0, rotationY, 0)
end

--------------------------------------------------------------------------------
-- BRAINROT SPAWNING
--------------------------------------------------------------------------------

--[[
	Spawns a Brainrot unit on the player's current tier plot.
	Automatically triggers new tier spawn when current tier is full.
	
	@param player Player - The player who is spawning the brainrot
	@param brainrotName string? - Optional specific brainrot name (defaults to "Avocadini Guffo")
	@return Model? - The spawned brainrot model, or nil if failed
]]
local function spawnBrainrot(player: Player, brainrotName: string?): Model?
	local nameToSpawn = brainrotName or "Avocadini Guffo"
	
	-- Wait for MapSystem to be available
	if not _G.MapSystem then
		task.wait(1)
		if not _G.MapSystem then
			warn("MapSystem not available for tier spawning")
			return nil
		end
	end
	
	local TIER_CONFIG = _G.MapSystem.TIER_CONFIG
	local tierSystem = _G.MapSystem.GetPlayerTierSystem(player)
	
	if not tierSystem then
		warn(string.format("No tier system for %s - using fallback", player.Name))
		-- Fallback to base plot
		local plot = getPlayerPlot(player)
		if not plot then
			warn(string.format("Cannot spawn brainrot: No plot found for %s", player.Name))
			return nil
		end
	end
	
	-- Get current tier data
	local currentTierData = tierSystem.Tiers[tierSystem.CurrentTier]
	if not currentTierData then
		warn("No current tier data for " .. player.Name)
		return nil
	end
	
	-- Check if current tier is full (12 models = 6 columns * 2 rows)
	local MODELS_PER_TIER = TIER_CONFIG.MODELS_PER_TIER or 12
	if currentTierData.GridIndex >= MODELS_PER_TIER then
		print(string.format("Tier %d is full for %s, spawning new tier...", tierSystem.CurrentTier, player.Name))
		
		-- Try to spawn a new tier
		local newTierData = _G.MapSystem.SpawnTierPlot(player, currentTierData)
		if newTierData then
			tierSystem.CurrentTier = newTierData.TierIndex
			currentTierData = newTierData
		else
			warn("Could not spawn new tier for " .. player.Name .. ", tier is full")
			return nil
		end
	end
	
	-- Get the brainrot template
	local brainrotTemplate = BrainrotsFolder:FindFirstChild(nameToSpawn)
	if not brainrotTemplate then
		warn(string.format("Brainrot template '%s' not found in ReplicatedStorage.Brainrots", nameToSpawn))
		return nil
	end
	
	-- Get plot CFrame from current tier
	local plot = currentTierData.Model
	local plotCFrame: CFrame
	if plot:IsA("Model") and plot.PrimaryPart then
		plotCFrame = plot.PrimaryPart.CFrame
	elseif plot:IsA("Model") then
		plotCFrame = plot:GetPivot()
	else
		local primaryPart = plot:FindFirstChild("Island") or plot:FindFirstChildWhichIsA("BasePart")
		if primaryPart then
			plotCFrame = primaryPart.CFrame
		else
			warn(string.format("Cannot determine plot center for %s tier %d", player.Name, tierSystem.CurrentTier))
			return nil
		end
	end
	
	-- Calculate grid spawn position using tier's grid index (2 rows of 6 facing inward)
	local gridIndex = currentTierData.GridIndex
	local side = math.floor(gridIndex / GRID_CONFIG.MODELS_PER_ROW) -- 0 or 1
	local positionInRow = gridIndex % GRID_CONFIG.MODELS_PER_ROW    -- 0-5
	
	-- Calculate X offset (position along the row)
	local offsetX = GRID_CONFIG.START_OFFSET_X + (positionInRow * GRID_CONFIG.SPACING)
	
	-- Calculate Z offset (which side of the center line)
	local offsetZ = (side == 0) and -GRID_CONFIG.SIDE_OFFSET or GRID_CONFIG.SIDE_OFFSET
	
	-- Calculate rotation to face inward toward center line
	local rotationY = (side == 0) and 0 or math.pi  -- 0° or 180°
	
	local offset = Vector3.new(offsetX, CONFIG.SPAWN_HEIGHT, offsetZ)
	local spawnCFrame = plotCFrame * CFrame.new(offset) * CFrame.Angles(0, rotationY, 0)
	
	-- Increment grid index for this tier
	currentTierData.GridIndex = gridIndex + 1
	tierSystem.TotalModels = tierSystem.TotalModels + 1
	
	-- Clone the brainrot
	local brainrot = brainrotTemplate:Clone()
	brainrot.Name = nameToSpawn .. "_" .. tostring(player.UserId) .. "_" .. tostring(os.time())
	
	-- Position the brainrot
	if brainrot:IsA("Model") then
		if brainrot.PrimaryPart then
			brainrot:SetPrimaryPartCFrame(spawnCFrame)
		else
			brainrot:PivotTo(spawnCFrame)
		end
	elseif brainrot:IsA("BasePart") then
		brainrot.CFrame = spawnCFrame
	end
	
	-- Anchor all parts to prevent falling through the map
	for _, part in brainrot:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	
	-- Set ownership attribute (for income loop)
	brainrot:SetAttribute("OwnerId", player.UserId)
	brainrot:SetAttribute("TierIndex", tierSystem.CurrentTier)
	brainrot:SetAttribute("UnitType", nameToSpawn)
	brainrot:SetAttribute("SynergyType", nil) -- Placeholder for future synergy system
	
	-- Set spawn time (for client progress bar sync)
	brainrot:SetAttribute("SpawnTime", os.time())
	brainrot:SetAttribute("IncomeInterval", CONFIG.INCOME_INTERVAL)
	brainrot:SetAttribute("IncomeAmount", CONFIG.INCOME_AMOUNT)
	
	-- Tag for income system and client detection
	CollectionService:AddTag(brainrot, BRAINROT_TAG)
	
	-- Parent to the current tier's plot (or a subfolder)
	local brainrotsContainer = plot:FindFirstChild("Brainrots")
	if not brainrotsContainer then
		brainrotsContainer = Instance.new("Folder")
		brainrotsContainer.Name = "Brainrots"
		brainrotsContainer.Parent = plot
	end
	brainrot.Parent = brainrotsContainer
	
	-- Debug logging
	local descendantCount = #brainrot:GetDescendants()
	local position = spawnCFrame.Position
	print(string.format("✓ Spawned %s for %s on Tier %d (model %d/%d)", 
		nameToSpawn, player.Name, tierSystem.CurrentTier, 
		currentTierData.GridIndex, MODELS_PER_TIER))
	print(string.format("  DEBUG: Parent = %s, Descendants = %d, Position = (%d, %d, %d)", 
		brainrotsContainer:GetFullName(), 
		descendantCount,
		math.floor(position.X), math.floor(position.Y), math.floor(position.Z)))
	
	return brainrot
end

--------------------------------------------------------------------------------
-- INCOME SYSTEM
--------------------------------------------------------------------------------

-- Track last income time per brainrot to avoid drift
local lastIncomeTick: {[Instance]: number} = {}

--[[
	Processes income for all active brainrots.
	Called every frame, but only awards income based on each brainrot's attributes.
	Income is stored in the Plot's CurrentStorage attribute instead of leaderstats.
	
	Applies Convenience Upgrade effects:
	- Income Multiplier: Increases base income
	- Cycle Reduction: Makes brainrots produce faster
	- Lucky Chance: 10% chance for 2x payout
	- Critical Chance: 5% chance for 5x payout
]]
local function processIncome()
	local currentTime = os.clock()
	
	for _, brainrot in CollectionService:GetTagged(BRAINROT_TAG) do
		-- Get this brainrot's specific income settings
		local baseIncomeInterval = brainrot:GetAttribute("IncomeInterval") or CONFIG.INCOME_INTERVAL
		local baseIncomeAmount = brainrot:GetAttribute("IncomeAmount") or CONFIG.INCOME_AMOUNT
		
		-- Initialize tracking if needed
		if not lastIncomeTick[brainrot] then
			lastIncomeTick[brainrot] = currentTime
		end
		
		-- Get the owner for upgrade bonuses
		local ownerId = brainrot:GetAttribute("OwnerId")
		local player = ownerId and Players:GetPlayerByUserId(ownerId)
		
		-- Apply cycle reduction from convenience upgrades
		local cycleReduction = player and player:GetAttribute("CycleReduction") or 0
		local incomeInterval = baseIncomeInterval * (1 - cycleReduction)
		
		-- Check if enough time has passed for THIS brainrot
		local elapsed = currentTime - lastIncomeTick[brainrot]
		if elapsed >= incomeInterval then
			if player then
				-- Get the player's plot and add to storage (not leaderstats)
				local plot = getPlayerPlot(player)
				if plot then
					local currentStorage = plot:GetAttribute("CurrentStorage") or 0
					local maxStorage = plot:GetAttribute("MaxStorage") or CONFIG.DEFAULT_MAX_STORAGE
					
					-- Apply income multiplier from convenience upgrades
					local convenienceMultiplier = player:GetAttribute("IncomeMultiplier") or 1
					
					-- Apply meatball multipliers from prestige system
					local meatballMultiplier = 1
					if _G.PrestigeManager and _G.PrestigeManager.GetTotalIncomeMultiplier then
						meatballMultiplier = _G.PrestigeManager.GetTotalIncomeMultiplier(player)
					end
					
					-- Apply synergy multiplier (set by updateSynergies)
					local synergyMultiplier = brainrot:GetAttribute("SynergyMultiplier") or 1
					
					-- Apply Mewing AFK bonus
					local mewingMultiplier = player:GetAttribute("MewingMultiplier") or 1
					
					local finalIncome = baseIncomeAmount * convenienceMultiplier * meatballMultiplier * synergyMultiplier * mewingMultiplier
					
					-- Check for Lucky Bonus (2x) and Critical Bonus (5x)
					local luckyChance = player:GetAttribute("LuckyChance") or 0
					local criticalChance = player:GetAttribute("CriticalChance") or 0
					local roll = math.random()
					
					if roll < criticalChance then
						-- Critical hit! 5x payout
						finalIncome = finalIncome * 5
					elseif roll < criticalChance + luckyChance then
						-- Lucky bonus! 2x payout
						finalIncome = finalIncome * 2
					end
					
					local incomeToAdd = math.floor(finalIncome)
					
					-- Calculate new storage (capped at max)
					local newStorage = math.min(currentStorage + incomeToAdd, maxStorage)
					plot:SetAttribute("CurrentStorage", newStorage)
					
					-- Track lifetime earnings for prestige system
					if _G.PrestigeManager and _G.PrestigeManager.AddLifetimeEarnings then
						-- Only track actual income added (not overflow)
						local actualAdded = newStorage - currentStorage
						if actualAdded > 0 then
							_G.PrestigeManager.AddLifetimeEarnings(player, actualAdded)
						end
					end
					
					-- Update visual display
					updateStorageVisual(plot, newStorage, maxStorage)
				end
			end
			
			-- Reset timer
			lastIncomeTick[brainrot] = currentTime
		end
	end
end

-- Clean up tracking when brainrots are removed
local function onBrainrotRemoved(brainrot: Instance)
	lastIncomeTick[brainrot] = nil
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

--[[
	Handles player joining the game.
]]
local function onPlayerAdded(player: Player)
	setupLeaderstats(player)
end

--[[
	Handles player leaving the game.
	Cleans up their brainrots.
]]
local function onPlayerRemoving(player: Player)
	-- Destroy all brainrots owned by this player
	for _, brainrot in CollectionService:GetTagged(BRAINROT_TAG) do
		local ownerId = brainrot:GetAttribute("OwnerId")
		if ownerId and ownerId == player.UserId then
			-- Clean up income tracking first
			lastIncomeTick[brainrot] = nil
			-- Destroy the brainrot
			brainrot:Destroy()
		end
	end
	
	print(string.format("✓ Cleaned up brainrots for %s", player.Name))
end

--[[
	Handles remote event from client requesting to spawn a brainrot.
	You can add validation here (e.g., check if player has enough money to buy).
]]
local function onSpawnBrainrotRequested(player: Player, brainrotName: string?)
	-- Optional: Add cost validation here
	-- local cost = getBrainrotCost(brainrotName)
	-- if not hasMoney(player, cost) then return end
	-- deductMoney(player, cost)
	
	spawnBrainrot(player, brainrotName)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   BrainrotManager - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Connect player events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	-- Handle players already in game
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	
	-- Connect remote event for client-requested spawns
	SpawnBrainrotEvent.OnServerEvent:Connect(onSpawnBrainrotRequested)
	
	-- Connect brainrot removal cleanup
	CollectionService:GetInstanceRemovedSignal(BRAINROT_TAG):Connect(onBrainrotRemoved)
	
	-- Start income loop using Heartbeat for smooth timing
	RunService.Heartbeat:Connect(processIncome)
	
	print("✓ BrainrotManager initialized")
	print("═══════════════════════════════════════════")
end

-- Start the system
initialize()

--------------------------------------------------------------------------------
-- INVENTORY MANAGEMENT
--------------------------------------------------------------------------------

--[[
	Initializes inventory tracking for a player.
	Called when player joins.
	
	@param player Player - The player to initialize inventory for
]]
local function initializePlayerInventory(player: Player)
	if PlayerInventory[player] then return end
	PlayerInventory[player] = {}
	print(string.format("✓ Initialized inventory for %s", player.Name))
end

--[[
	Gets the full inventory data for a player, organized by unitName then rarity.
	
	@param player Player - The player to get inventory for
	@return table - Inventory data with {unitName: {rarity: {total, active}}}
]]
local function getInventoryData(player: Player): {[string]: {[string]: {total: number, active: number}}}
	return PlayerInventory[player] or {}
end

--[[
	Updates synergy effects for a player based on current inventory.
	Calculates multipliers and applies them to active brainrots.
	
	@param player Player - The player to update synergies for
]]
local function updateSynergies(player: Player)
	local inventory = PlayerInventory[player]
	if not inventory then return end
	
	-- 1. Calculate active effects
	local unitMultipliers: {[string]: number} = {} -- unitName -> multiplier
	local globalMultiplier = 1
	
	for _, synergy in SynergyConfig.GetAllSynergies() do
		local isMet, _ = SynergyConfig.CheckSynergyProgress(synergy.Id, inventory)
		
		if isMet then
			for _, effect in synergy.Effects do
				if effect.Type == "IncomeMultiplier" then
					if effect.Target == "All" then
						globalMultiplier = globalMultiplier * effect.Value
					elseif effect.Target == "Specific" and effect.TargetUnits then
						for _, unitName in effect.TargetUnits do
							unitMultipliers[unitName] = (unitMultipliers[unitName] or 1) * effect.Value
						end
					end
				elseif effect.Type == "GlobalIncomeBoost" then
					globalMultiplier = globalMultiplier * effect.Value
				end
				-- TODO: Handle CycleReduction if needed
			end
		end
	end
	
	-- 2. Apply to active brainrots
	local updateCount = 0
	for _, brainrot in CollectionService:GetTagged(BRAINROT_TAG) do
		if brainrot:GetAttribute("OwnerId") == player.UserId then
			local unitName = brainrot:GetAttribute("UnitType")
			
			-- Calculate total synergy multiplier for this unit
			local specificMult = unitMultipliers[unitName] or 1
			local totalMult = globalMultiplier * specificMult
			
			-- Only update if changed
			local currentMult = brainrot:GetAttribute("SynergyMultiplier") or 1
			if math.abs(currentMult - totalMult) > 0.001 then
				brainrot:SetAttribute("SynergyMultiplier", totalMult)
				updateCount = updateCount + 1
			end
		end
	end
	
	if updateCount > 0 then
		print(string.format("⚡ Updated synergies for %s (%d units affected)", player.Name, updateCount))
	end
end

--[[
	Adds a brainrot to a player's inventory when purchased.
	Automatically rolls for rarity and sets it as active (placed).
	
	@param player Player - The player who owns the brainrot
	@param unitName string - The unit type name
	@param rarity string? - Optional specific rarity (if not provided, rolls for one)
	@return string - The rarity that was rolled/assigned
]]
local function addToInventory(player: Player, unitName: string, rarity: string?): string
	if not PlayerInventory[player] then
		initializePlayerInventory(player)
	end
	
	-- Roll for rarity if not specified
	local actualRarity = rarity or rollRarity()
	
	-- Initialize unit entry if needed
	if not PlayerInventory[player][unitName] then
		PlayerInventory[player][unitName] = {}
	end
	
	-- Initialize rarity entry if needed
	if not PlayerInventory[player][unitName][actualRarity] then
		PlayerInventory[player][unitName][actualRarity] = {
			total = 0,
			active = 0,
		}
	end
	
	local invData = PlayerInventory[player][unitName][actualRarity]
	invData.total = invData.total + 1
	invData.active = invData.active + 1
	
	-- Notify client of inventory change (send full inventory for this unit)
	InventoryChangedEvent:FireClient(player, unitName, PlayerInventory[player][unitName])
	
	-- Update synergies (purchase might unlock requirements)
	updateSynergies(player)
	
	-- Log roll result
	if actualRarity ~= "Normal" then
		print(string.format("🎲 %s rolled %s %s!", player.Name, RARITY_CONFIG[actualRarity].displayName, unitName))
	end
	
	return actualRarity
end

--[[
	Places an inactive brainrot from inventory onto the plot.
	
	@param player Player - The player placing the brainrot
	@param unitName string - The unit type to place
	@param rarity string - The rarity to place
	@return boolean, string? - Success and error message
]]
local function placeBrainrotFromInventory(player: Player, unitName: string, rarity: string): (boolean, string?)
	local inventory = PlayerInventory[player]
	if not inventory or not inventory[unitName] or not inventory[unitName][rarity] then
		return false, "Unit not in inventory"
	end
	
	local invData = inventory[unitName][rarity]
	local inactive = invData.total - invData.active
	
	if inactive <= 0 then
		return false, "No inactive brainrots of this rarity to place"
	end
	
	-- Spawn a new brainrot on the plot with the specified rarity
	local brainrot = spawnBrainrot(player, unitName)
	if not brainrot then
		return false, "Failed to spawn brainrot"
	end
	
	-- Set rarity attribute on the brainrot
	brainrot:SetAttribute("Rarity", rarity)
	
	-- Apply rarity income multiplier
	local baseIncome = brainrot:GetAttribute("IncomeAmount") or CONFIG.INCOME_AMOUNT
	local rarityConfig = RARITY_CONFIG[rarity]
	if rarityConfig then
		brainrot:SetAttribute("IncomeAmount", baseIncome * rarityConfig.incomeMultiplier)
	end
	
	-- Update inventory counts
	invData.active = invData.active + 1
	
	-- Notify client
	InventoryChangedEvent:FireClient(player, unitName, PlayerInventory[player][unitName])
	
	-- Update synergies (newly placed unit needs synergy attributes)
	updateSynergies(player)
	
	print(string.format("✓ %s placed %s %s from inventory (%d/%d active)", 
		player.Name, rarity, unitName, invData.active, invData.total))
	
	return true, nil
end

--[[
	Removes an active brainrot from the plot to inventory (makes inactive).
	
	@param player Player - The player removing the brainrot
	@param unitName string - The unit type to remove
	@param rarity string - The rarity to remove
	@return boolean, string? - Success and error message
]]
local function removeBrainrotToInventory(player: Player, unitName: string, rarity: string): (boolean, string?)
	local inventory = PlayerInventory[player]
	if not inventory or not inventory[unitName] or not inventory[unitName][rarity] then
		return false, "Unit not in inventory"
	end
	
	local invData = inventory[unitName][rarity]
	
	if invData.active <= 0 then
		return false, "No active brainrots of this rarity to remove"
	end
	
	-- Find and destroy one active brainrot of this type and rarity
	local foundBrainrot = nil
	for _, brainrot in CollectionService:GetTagged(BRAINROT_TAG) do
		local ownerId = brainrot:GetAttribute("OwnerId")
		local brainrotType = brainrot:GetAttribute("UnitType")
		local brainrotRarity = brainrot:GetAttribute("Rarity") or "Normal"
		
		if ownerId == player.UserId and brainrotType == unitName and brainrotRarity == rarity then
			foundBrainrot = brainrot
			break
		end
	end
	
	if not foundBrainrot then
		return false, "Could not find brainrot to remove"
	end
	
	-- Destroy the brainrot model
	foundBrainrot:Destroy()
	
	-- Update inventory counts
	invData.active = invData.active - 1
	
	-- Notify client
	InventoryChangedEvent:FireClient(player, unitName, PlayerInventory[player][unitName])
	
	-- Update synergies (removal shouldn't affect requirements as they are based on total, but good to keep consistent)
	updateSynergies(player)
	
	print(string.format("✓ %s removed %s %s to inventory (%d/%d active)", 
		player.Name, rarity, unitName, invData.active, invData.total))
	
	return true, nil
end

--[[
	Clears inventory for a player when they leave.
	
	@param player Player - The player to clear inventory for
]]
local function clearPlayerInventory(player: Player)
	PlayerInventory[player] = nil
end

-- Connect inventory remote functions
GetInventoryRemote.OnServerInvoke = function(player: Player)
	return {
		units = getInventoryData(player),
		rarityConfig = RARITY_CONFIG,
		rarityOrder = RARITY_ORDER,
	}
end

PlaceBrainrotRemote.OnServerInvoke = function(player: Player, unitName: string, rarity: string)
	return placeBrainrotFromInventory(player, unitName, rarity)
end

RemoveBrainrotRemote.OnServerInvoke = function(player: Player, unitName: string, rarity: string)
	return removeBrainrotToInventory(player, unitName, rarity)
end

-- Clean up inventory when player leaves
Players.PlayerRemoving:Connect(clearPlayerInventory)

--------------------------------------------------------------------------------
-- MODULE API (for other server scripts)
--------------------------------------------------------------------------------

--[[
	Updates all brainrots of a specific unit type for a player.
	Called when a milestone is crossed to apply new income/cycle values.
	
	@param player Player - The player who owns the units
	@param unitType string - The unit type name (e.g., "Avocadini Guffo")
	@param newIncome number - The new effective income amount
	@param newCycleTime number - The new effective cycle time
]]
local function updateAllUnitStats(player: Player, unitType: string, newIncome: number, newCycleTime: number)
	local updateCount = 0
	
	for _, brainrot in CollectionService:GetTagged(BRAINROT_TAG) do
		local ownerId = brainrot:GetAttribute("OwnerId")
		local brainrotType = brainrot:GetAttribute("UnitType")
		
		if ownerId == player.UserId and brainrotType == unitType then
			brainrot:SetAttribute("IncomeAmount", newIncome)
			brainrot:SetAttribute("IncomeInterval", newCycleTime)
			updateCount += 1
		end
	end
	
	if updateCount > 0 then
		print(string.format("✓ Updated %d %s units for %s (Income: $%d, Cycle: %.1fs)", 
			updateCount, unitType, player.Name, newIncome, newCycleTime))
	end
end

-- Export functions for other scripts via _G (or use ModuleScript pattern)
_G.BrainrotManager = {
	SpawnBrainrot = spawnBrainrot,
	GetPlayerPlot = getPlayerPlot,
	CreateStoragePart = createStoragePart,
	UpdateStorageVisual = updateStorageVisual,
	UpdateAllUnitStats = updateAllUnitStats,
	-- Inventory management
	AddToInventory = addToInventory,
	GetInventoryData = getInventoryData,
	PlaceBrainrotFromInventory = placeBrainrotFromInventory,
	RemoveBrainrotToInventory = removeBrainrotToInventory,
	-- Rarity system
	RollRarity = rollRarity,
	RARITY_CONFIG = RARITY_CONFIG,
	RARITY_ORDER = RARITY_ORDER,
	CONFIG = CONFIG,
}
