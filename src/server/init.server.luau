--[[
	Map Generation and Plot Assignment Server Script
	
	This script handles:
	1. Spawning the central MainIsland hub
	2. Generating 8 player plots in a circular formation around the hub
	3. Creating bridges connecting each plot to the hub
	4. Assigning plots to players when they join
	5. Cleaning up plots when players leave
	
	Layout:
	- Central hub at origin (0, 0, 0)
	- 8 plots arranged in a circle at 400 stud radius
	- Each plot faces toward the center
]]

-- Services
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Configuration
local CONFIG = {
	MAX_PLAYERS = 8,
	PLOT_RADIUS = 400,        -- Distance from center to each plot
	MAIN_ISLAND_HEIGHT = 30,  -- Y position for main island (lower than plots)
	PLOT_MIN_HEIGHT = 50,     -- Minimum Y position for player plots
	PLOT_MAX_HEIGHT = 120,     -- Maximum Y position for player plots
}

-- Tier System Configuration
local TIER_CONFIG = {
	MODELS_PER_TIER = 12,      -- Number of models before tier is full
	MAX_TIERS = 6,             -- Maximum tiers per player
	-- Height variation (always positive, new tier is higher than parent)
	TIER_HEIGHT_MIN = 20,      -- Minimum Y increase per tier
	TIER_HEIGHT_MAX = 60,      -- Maximum Y increase per tier
	-- Distance variation
	TIER_DISTANCE_MIN = 80,    -- Minimum distance from parent plot
	TIER_DISTANCE_MAX = 140,   -- Maximum distance from parent plot
	-- Stair configuration
	STAIR_WIDTH = 10,          -- Width of each stair step
	STAIR_DEPTH = 4,           -- Depth of each stair step
	STAIR_HEIGHT = 3,          -- Height of each stair step
	GRID_COLUMNS = 6,          -- Models per row
	GRID_ROWS = 2,             -- Rows per tier
	-- Sides: 0=North (+Z), 1=East (+X), 2=South (-Z), 3=West (-X)
	SIDE_OFFSETS = {
		[0] = Vector3.new(0, 0, 1),   -- North
		[1] = Vector3.new(1, 0, 0),   -- East
		[2] = Vector3.new(0, 0, -1),  -- South
		[3] = Vector3.new(-1, 0, 0),  -- West
	},
}

-- Model references (will be set up in initialization)
local MainIslandTemplate: Model
local PlayerPlotTemplate: Model
local BridgeTemplate: Model

--[[
	Plot data structure:
	{
		Index: number,           -- Plot index (1-8)
		Model: Model,            -- The cloned PlayerPlot model
		Bridge: Model,           -- The cloned Bridge model
		Position: CFrame,        -- World position of the plot
		Owner: Player?,          -- Current owner (nil if unclaimed)
		ClaimPart: BasePart,     -- The touchable claim pad
	}
]]
local Plots: {[number]: {
	Index: number,
	Model: Model,
	Bridge: Model,
	Position: CFrame,
	Owner: Player?,
	ClaimPart: BasePart,
}} = {}

-- Reverse lookup: Player -> Plot Index
local PlayerToPlot: {[Player]: number} = {}

-- Folder to hold all plots in workspace
local PlotsFolder: Folder

--[[
	Tier data structure for tracking player plot expansions
]]
export type TierPlotData = {
	TierIndex: number,         -- Which tier (1 = original, 2+ = expansions)
	Model: Model,              -- The tier's plot model
	Bridge: Model?,            -- Bridge connecting to parent (nil for tier 1)
	ParentTier: TierPlotData?, -- Reference to parent tier
	BlockedSide: number,       -- Side with incoming bridge (0-3)
	UsedSides: {number},       -- Sides with outgoing bridges to child tiers
	GridIndex: number,         -- Current grid spawn index for this tier
}

export type PlayerTierSystem = {
	BasePlotIndex: number,     -- Original plot index (1-8)
	Tiers: {TierPlotData},     -- Array of all tier plots
	CurrentTier: number,       -- Index of tier currently being filled
	TotalModels: number,       -- Total models across all tiers
}

-- Track tier systems per player
local PlayerTierSystems: {[Player]: PlayerTierSystem} = {}

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Calculates the CFrame position for a plot at a given index.
	
	Math explanation:
	- We have 8 plots arranged in a circle, so each plot is 360°/8 = 45° apart
	- Starting angle is 0° (pointing along positive X axis)
	- For plot index i (0-indexed), angle = i * (2π / 8) = i * π/4
	- X position = radius * cos(angle)
	- Z position = radius * sin(angle)
	- The plot faces the center, so we rotate it by (angle + π) to face inward
	- Height is randomized between PLOT_MIN_HEIGHT and PLOT_MAX_HEIGHT
	
	@param index number - The plot index (1-8)
	@return CFrame - The world CFrame for this plot
]]
local function calculatePlotCFrame(index: number): CFrame
	-- Convert to 0-indexed for the math
	local i = index - 1
	
	-- Calculate the angle for this plot position
	-- 2π radians = 360°, divided by 8 plots = π/4 radians per plot (45°)
	local anglePerPlot = (2 * math.pi) / CONFIG.MAX_PLAYERS
	local angle = i * anglePerPlot
	
	-- Calculate X and Z positions on the circle
	-- cos(angle) gives us the X coordinate, sin(angle) gives us the Z coordinate
	local x = CONFIG.PLOT_RADIUS * math.cos(angle)
	local z = CONFIG.PLOT_RADIUS * math.sin(angle)
	
	-- Generate a random height for this plot between min and max
	local randomHeight = math.random(CONFIG.PLOT_MIN_HEIGHT, CONFIG.PLOT_MAX_HEIGHT)
	
	-- Create position vector at the calculated location with random height
	local position = Vector3.new(x, randomHeight, z)
	
	-- Calculate the rotation so the plot faces the center (0, 0, 0)
	-- We need to rotate by the angle + π (180°) to make the front face inward
	-- Using CFrame.Angles with Y rotation to spin around the vertical axis
	local rotationAngle = angle + math.pi
	local rotation = CFrame.Angles(0, -rotationAngle, 0)
	
	-- Combine position and rotation into final CFrame
	return CFrame.new(position) * rotation
end

--[[
	Calculates the CFrame and scale for a bridge connecting the hub to a plot.
	
	The bridge connects the main island (at MAIN_ISLAND_HEIGHT) to each plot
	(at their random heights). The bridge is positioned and angled to span
	the gap properly.
	
	@param plotCFrame CFrame - The CFrame of the destination plot
	@return CFrame, number - The bridge CFrame and the scale factor for length
]]
local function calculateBridgeCFrame(plotCFrame: CFrame): (CFrame, number)
	-- Get 2D direction from center to plot (on the XZ plane)
	local plotPos = plotCFrame.Position
	local direction2D = Vector3.new(plotPos.X, 0, plotPos.Z).Unit
	
	-- Bridge start point: edge of main island at main island height
	local hubRadius = 50  -- Approximate radius of hub island
	local hubEdgePos = Vector3.new(
		direction2D.X * hubRadius,
		CONFIG.MAIN_ISLAND_HEIGHT + 10, -- Slightly above island surface
		direction2D.Z * hubRadius
	)
	
	-- Bridge end point: edge of plot at plot height
	local plotRadius = 40 -- Approximate radius of plot island
	local plotEdgePos = Vector3.new(
		plotPos.X - direction2D.X * plotRadius,
		plotPos.Y + 10, -- Slightly above plot surface
		plotPos.Z - direction2D.Z * plotRadius
	)
	
	-- Midpoint between the two edge positions
	local midpoint = (hubEdgePos + plotEdgePos) / 2
	
	-- Calculate the 3D distance for the bridge length
	local distance = (plotEdgePos - hubEdgePos).Magnitude
	
	-- Create CFrame looking from hub toward plot, tilted to match height difference
	local bridgeCFrame = CFrame.new(midpoint, plotEdgePos)
	
	return bridgeCFrame, distance
end

--------------------------------------------------------------------------------
-- TIER SYSTEM FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Gets a random available side for spawning a new tier.
	Excludes the blocked side (where incoming bridge is) and used sides.
	
	@param tierData TierPlotData - The tier to get an available side from
	@return number? - Side index (0-3), or nil if no sides available
]]
local function getAvailableSide(tierData: TierPlotData): number?
	local availableSides = {}
	
	for side = 0, 3 do
		local isBlocked = (side == tierData.BlockedSide)
		local isUsed = false
		
		for _, usedSide in tierData.UsedSides do
			if usedSide == side then
				isUsed = true
				break
			end
		end
		
		if not isBlocked and not isUsed then
			table.insert(availableSides, side)
		end
	end
	
	if #availableSides == 0 then
		return nil
	end
	
	-- Return random available side
	return availableSides[math.random(1, #availableSides)]
end

--[[
	Calculates the side that connects back to the parent based on direction.
	Used to determine the blocked side for a new tier.
	
	@param parentPos Vector3 - Parent plot position
	@param childPos Vector3 - Child plot position
	@return number - The side index (0-3) facing the parent
]]
local function calculateIncomingSide(parentPos: Vector3, childPos: Vector3): number
	local direction = (parentPos - childPos)
	local absX = math.abs(direction.X)
	local absZ = math.abs(direction.Z)
	
	if absZ > absX then
		-- More Z than X: North or South
		if direction.Z > 0 then
			return 0 -- North (parent is north of child)
		else
			return 2 -- South
		end
	else
		-- More X than Z: East or West
		if direction.X > 0 then
			return 1 -- East (parent is east of child)
		else
			return 3 -- West
		end
	end
end

--[[
	Calculates bridge CFrame between two tier plots.
	
	@param fromCFrame CFrame - Source tier CFrame
	@param toCFrame CFrame - Destination tier CFrame
	@return CFrame, number - Bridge CFrame and distance
]]
local function calculateTierBridgeCFrame(fromCFrame: CFrame, toCFrame: CFrame): (CFrame, number)
	local fromPos = fromCFrame.Position
	local toPos = toCFrame.Position
	
	local plotRadius = 40 -- Approximate radius of plot island
	local direction = (toPos - fromPos).Unit
	
	local fromEdge = fromPos + direction * plotRadius
	fromEdge = Vector3.new(fromEdge.X, fromPos.Y + 10, fromEdge.Z)
	
	local toEdge = toPos - direction * plotRadius
	toEdge = Vector3.new(toEdge.X, toPos.Y + 10, toEdge.Z)
	
	local midpoint = (fromEdge + toEdge) / 2
	local distance = (toEdge - fromEdge).Magnitude
	
	local bridgeCFrame = CFrame.new(midpoint, toEdge)
	
	return bridgeCFrame, distance
end

--[[
	Spawns a new tier plot for a player.
	
	@param player Player - The player to spawn the tier for
	@param parentTier TierPlotData - The parent tier to spawn from
	@return TierPlotData? - The new tier data, or nil if failed
]]
local function spawnTierPlot(player: Player, parentTier: TierPlotData): TierPlotData?
	-- Get an available side from parent
	local side = getAvailableSide(parentTier)
	if not side then
		warn("No available sides for new tier on player " .. player.Name)
		return nil
	end
	
	local tierSystem = PlayerTierSystems[player]
	if not tierSystem then
		warn("No tier system found for player " .. player.Name)
		return nil
	end
	
	local newTierIndex = #tierSystem.Tiers + 1
	if newTierIndex > TIER_CONFIG.MAX_TIERS then
		warn("Player " .. player.Name .. " has reached max tiers")
		return nil
	end
	
	-- Calculate new tier position with randomized distance and height
	local parentCFrame = parentTier.Model:GetPivot()
	local sideOffset = TIER_CONFIG.SIDE_OFFSETS[side]
	
	-- Random height (always positive, new tier is higher)
	local heightOffset = math.random(TIER_CONFIG.TIER_HEIGHT_MIN, TIER_CONFIG.TIER_HEIGHT_MAX)
	local newHeight = parentCFrame.Position.Y + heightOffset
	
	-- Random distance
	local tierDistance = math.random(TIER_CONFIG.TIER_DISTANCE_MIN, TIER_CONFIG.TIER_DISTANCE_MAX)
	local newPosition = parentCFrame.Position + (sideOffset * tierDistance)
	newPosition = Vector3.new(newPosition.X, newHeight, newPosition.Z)
	
	-- Clone the plot template
	local newPlotModel = PlayerPlotTemplate:Clone()
	newPlotModel.Name = string.format("Plot_%d_Tier_%d", tierSystem.BasePlotIndex, newTierIndex)
	
	-- Position and rotate to face parent (similar rotation logic)
	local lookDirection = (parentCFrame.Position - newPosition)
	local rotationAngle = math.atan2(lookDirection.X, lookDirection.Z)
	local newCFrame = CFrame.new(newPosition) * CFrame.Angles(0, rotationAngle, 0)
	
	if newPlotModel.PrimaryPart then
		newPlotModel:SetPrimaryPartCFrame(newCFrame)
	else
		newPlotModel:PivotTo(newCFrame)
	end
	
	newPlotModel:SetAttribute("OwnerId", player.UserId)
	newPlotModel:SetAttribute("TierIndex", newTierIndex)
	newPlotModel.Parent = PlotsFolder
	
	-- Create STAIRS between parent and new tier (instead of flat bridge)
	local stairsModel = Instance.new("Model")
	stairsModel.Name = string.format("Stairs_%d_Tier_%d", tierSystem.BasePlotIndex, newTierIndex)
	
	-- Calculate stair parameters
	local parentEdgePos = parentCFrame.Position + (sideOffset * 40) -- Edge of parent plot
	parentEdgePos = Vector3.new(parentEdgePos.X, parentCFrame.Position.Y + 2, parentEdgePos.Z) -- +2 for slight offset above surface
	
	local childEdgePos = newPosition - (sideOffset * 40) -- Edge of child plot
	childEdgePos = Vector3.new(childEdgePos.X, newPosition.Y + 2, childEdgePos.Z) -- Same offset for child
	
	local horizontalDistance = (Vector3.new(childEdgePos.X, 0, childEdgePos.Z) - Vector3.new(parentEdgePos.X, 0, parentEdgePos.Z)).Magnitude
	local verticalDistance = childEdgePos.Y - parentEdgePos.Y
	
	print(string.format("  Stairs debug: horizontal=%.1f, vertical=%.1f", horizontalDistance, verticalDistance))
	
	-- Calculate number of steps needed
	local numSteps = math.max(1, math.floor(verticalDistance / TIER_CONFIG.STAIR_HEIGHT))
	local stepHeight = verticalDistance / numSteps
	local stepDepth = horizontalDistance / numSteps
	
	print(string.format("  Stairs debug: numSteps=%d, stepHeight=%.1f, stepDepth=%.1f", numSteps, stepHeight, stepDepth))
	
	-- Direction from parent to child (normalized XZ)
	local directionVector = Vector3.new(childEdgePos.X, 0, childEdgePos.Z) - Vector3.new(parentEdgePos.X, 0, parentEdgePos.Z)
	if directionVector.Magnitude < 0.001 then
		warn("Stairs creation: direction vector is zero, cannot create stairs!")
		stairsModel.Parent = workspace -- Still parent it even if empty
	else
		local direction = directionVector.Unit
		
		-- Create each step
		for i = 0, numSteps - 1 do
			local step = Instance.new("Part")
			step.Name = "Step_" .. i
			step.Size = Vector3.new(TIER_CONFIG.STAIR_WIDTH, math.max(0.5, stepHeight), math.max(0.5, stepDepth))
			step.BrickColor = BrickColor.new("Medium stone grey")
			step.Material = Enum.Material.Concrete
			step.Anchored = true
			step.CanCollide = true
			
			-- Position each step
			local stepX = parentEdgePos.X + direction.X * (i + 0.5) * stepDepth
			local stepZ = parentEdgePos.Z + direction.Z * (i + 0.5) * stepDepth
			local stepY = parentEdgePos.Y + (i + 0.5) * stepHeight
			step.Position = Vector3.new(stepX, stepY, stepZ)
			
			-- Rotate step to align with direction
			step.CFrame = CFrame.new(step.Position) * CFrame.Angles(0, math.atan2(direction.X, direction.Z), 0)
			
			step.Parent = stairsModel
		end
		
		print(string.format("  Created %d steps in stairs model", numSteps))
	end
	
	-- Set primary part for the stairs model
	local firstStep = stairsModel:FindFirstChild("Step_0")
	if firstStep then
		stairsModel.PrimaryPart = firstStep
	end
	
	stairsModel.Parent = workspace
	print(string.format("  Stairs model '%s' parented to workspace", stairsModel.Name))
	
	-- Mark parent side as used
	table.insert(parentTier.UsedSides, side)
	
	-- Calculate incoming side for new tier
	local incomingSide = calculateIncomingSide(parentCFrame.Position, newPosition)
	
	-- Create tier data
	local newTierData: TierPlotData = {
		TierIndex = newTierIndex,
		Model = newPlotModel,
		Bridge = stairsModel, -- Now stores the stairs model instead of bridge
		ParentTier = parentTier,
		BlockedSide = incomingSide,
		UsedSides = {},
		GridIndex = 0,
	}
	
	-- Add to player's tier system
	table.insert(tierSystem.Tiers, newTierData)
	
	print(string.format("✓ Spawned Tier %d for %s (distance: %d, height: +%d)", newTierIndex, player.Name, tierDistance, heightOffset))
	
	return newTierData
end

--[[
	Creates a claim part (touchable pad) for a plot.
	The claim part is placed on top of the plot for players to step on.
	
	@param plotModel Model - The plot model to add the claim part to
	@return BasePart - The created claim part
]]
local function createClaimPart(plotModel: Model): BasePart
	local claimPart = Instance.new("Part")
	claimPart.Name = "ClaimPart"
	claimPart.Size = Vector3.new(10, 1, 10)
	claimPart.BrickColor = BrickColor.new("Lime green")
	claimPart.Material = Enum.Material.Neon
	claimPart.Transparency = 0.3
	claimPart.Anchored = true
	claimPart.CanCollide = false -- Players can walk through it
	
	-- Position it slightly above the plot's primary part or center
	local plotPrimary = plotModel.PrimaryPart or plotModel:FindFirstChildWhichIsA("BasePart")
	if plotPrimary then
		claimPart.Position = plotPrimary.Position + Vector3.new(0, 3, 0)
	else
		claimPart.Position = plotModel:GetPivot().Position + Vector3.new(0, 3, 0)
	end
	
	claimPart.Parent = plotModel
	
	return claimPart
end

--------------------------------------------------------------------------------
-- MAP GENERATION
--------------------------------------------------------------------------------

--[[
	Initializes the templates from storage.
	Creates placeholder models if they don't exist (for testing).
]]
local function initializeTemplates()
	-- Try ServerStorage first, then ReplicatedStorage
	MainIslandTemplate = ServerStorage:FindFirstChild("MainIsland") or ReplicatedStorage:FindFirstChild("MainIsland")
	PlayerPlotTemplate = ServerStorage:FindFirstChild("PlayerPlot") or ReplicatedStorage:FindFirstChild("PlayerPlot")
	BridgeTemplate = ServerStorage:FindFirstChild("Bridge") or ReplicatedStorage:FindFirstChild("Bridge")
	
	-- Create placeholder templates if they don't exist (for testing)
	if not MainIslandTemplate then
		-- warn("MainIsland template not found! Creating placeholder...")
		local newModel = Instance.new("Model")
		newModel.Name = "MainIsland"
		
		local part = Instance.new("Part")
		part.Name = "Island"
		part.Size = Vector3.new(100, 20, 100)
		part.BrickColor = BrickColor.new("Bright green")
		part.Material = Enum.Material.Grass
		part.Anchored = true
		part.Parent = newModel -- Fixed: parent to newModel, not MainIslandTemplate
		
		newModel.PrimaryPart = part
		newModel.Parent = ServerStorage
		MainIslandTemplate = newModel
	end
	
	if not PlayerPlotTemplate then
		-- warn("PlayerPlot template not found! Creating placeholder...")
		local newModel = Instance.new("Model")
		newModel.Name = "PlayerPlot"
		
		local part = Instance.new("Part")
		part.Name = "Island"
		part.Size = Vector3.new(80, 15, 80)
		part.BrickColor = BrickColor.new("Bright green")
		part.Material = Enum.Material.Grass
		part.Anchored = true
		part.Parent = newModel -- Fixed: parent to newModel, not PlayerPlotTemplate
		
		newModel.PrimaryPart = part
		newModel.Parent = ServerStorage
		PlayerPlotTemplate = newModel
	end
	
	if not BridgeTemplate then
		-- warn("Bridge template not found! Creating placeholder...")
		local newModel = Instance.new("Model")
		newModel.Name = "Bridge"
		
		local part = Instance.new("Part")
		part.Name = "BridgePart"
		part.Size = Vector3.new(10, 2, 50) -- Will be scaled to fit
		part.BrickColor = BrickColor.new("Brown")
		part.Material = Enum.Material.Wood
		part.Anchored = true
		part.Parent = newModel -- Fixed: parent to newModel, not BridgeTemplate
		
		newModel.PrimaryPart = part
		newModel.Parent = ServerStorage
		BridgeTemplate = newModel
	end
	
	print("✓ Templates initialized")
end

--[[
	Spawns the main central hub island at the world origin.
]]
local function spawnMainIsland()
	local mainIsland = MainIslandTemplate:Clone()
	mainIsland.Name = "MainIsland"
	
	-- Position at origin, at the configured height (lower than plots)
	local hubCFrame = CFrame.new(0, CONFIG.MAIN_ISLAND_HEIGHT, 0)
	
	if mainIsland.PrimaryPart then
		mainIsland:SetPrimaryPartCFrame(hubCFrame)
	else
		mainIsland:PivotTo(hubCFrame)
	end
	
	mainIsland.Parent = workspace
	
	print("✓ Main Island spawned at origin")
	return mainIsland
end

--[[
	Generates all 8 player plots around the central hub.
	Creates plots, bridges, and claim parts for each position.
]]
local function generatePlots()
	-- Create the Plots folder in Workspace
	PlotsFolder = Instance.new("Folder")
	PlotsFolder.Name = "Plots"
	PlotsFolder.Parent = workspace
	
	for i = 1, CONFIG.MAX_PLAYERS do
		-- Calculate this plot's position and rotation
		local plotCFrame = calculatePlotCFrame(i)
		
		-- Clone and position the player plot
		local plotModel = PlayerPlotTemplate:Clone()
		plotModel.Name = "Plot_" .. i
		
		if plotModel.PrimaryPart then
			plotModel:SetPrimaryPartCFrame(plotCFrame)
		else
			plotModel:PivotTo(plotCFrame)
		end
		
		plotModel.Parent = PlotsFolder
		
		-- Calculate and create the bridge
		local bridgeCFrame, bridgeDistance = calculateBridgeCFrame(plotCFrame)
		local bridgeModel = BridgeTemplate:Clone()
		bridgeModel.Name = "Bridge_" .. i
		
		-- Scale the bridge to fit the gap
		-- bridgeDistance is already the edge-to-edge distance from calculateBridgeCFrame
		
		-- Scale the bridge parts
		for _, part in bridgeModel:GetDescendants() do
			if part:IsA("BasePart") then
				-- Scale the Z axis (length) of the bridge
				part.Size = Vector3.new(part.Size.X, part.Size.Y, bridgeDistance)
			end
		end
		
		if bridgeModel.PrimaryPart then
			bridgeModel:SetPrimaryPartCFrame(bridgeCFrame)
		else
			bridgeModel:PivotTo(bridgeCFrame)
		end
		
		bridgeModel.Parent = workspace
		
		-- Create the claim part for this plot
		local claimPart = createClaimPart(plotModel)
		
		-- Store plot data
		Plots[i] = {
			Index = i,
			Model = plotModel,
			Bridge = bridgeModel,
			Position = plotCFrame,
			Owner = nil,
			ClaimPart = claimPart,
		}
		
		-- Create placeholder parts for future features
		-- Cannon placeholder (edge of plot facing Main Island)
		local cannonPlaceholder = Instance.new("Part")
		cannonPlaceholder.Name = "Cannon_Placeholder"
		cannonPlaceholder.Size = Vector3.new(4, 4, 4)
		cannonPlaceholder.BrickColor = BrickColor.new("Medium stone grey")
		cannonPlaceholder.Material = Enum.Material.SmoothPlastic
		cannonPlaceholder.Anchored = true
		cannonPlaceholder.CanCollide = false
		cannonPlaceholder.Transparency = 0.5
		cannonPlaceholder.CFrame = plotCFrame * CFrame.new(35, 5, 0)
		cannonPlaceholder.Parent = plotModel
		
		-- Zipline placeholder on Main Island (facing this plot)
		local mainIsland = workspace:FindFirstChild("MainIsland")
		if mainIsland then
			local ziplinePlaceholder = Instance.new("Part")
			ziplinePlaceholder.Name = "Zipline_Placeholder_" .. i
			ziplinePlaceholder.Size = Vector3.new(4, 8, 4)
			ziplinePlaceholder.BrickColor = BrickColor.new("Medium stone grey")
			ziplinePlaceholder.Material = Enum.Material.SmoothPlastic
			ziplinePlaceholder.Anchored = true
			ziplinePlaceholder.CanCollide = false
			ziplinePlaceholder.Transparency = 0.5
			-- Position on edge of main island facing the plot
			local directionToPlot = (plotCFrame.Position - Vector3.new(0, CONFIG.MAIN_ISLAND_HEIGHT, 0)).Unit
			ziplinePlaceholder.Position = Vector3.new(0, CONFIG.MAIN_ISLAND_HEIGHT, 0) + directionToPlot * 45
			ziplinePlaceholder.Parent = mainIsland
		end
		
		print(string.format("✓ Plot %d generated at angle %.1f°", i, ((i-1) * 45)))
	end
	
	print("✓ All " .. CONFIG.MAX_PLAYERS .. " plots generated")
end

--------------------------------------------------------------------------------
-- PLAYER HANDLING
--------------------------------------------------------------------------------

--[[
	Finds the first available (unowned) plot.
	
	@return number? - The index of an available plot, or nil if all are taken
]]
local function findAvailablePlot(): number?
	for i, plotData in Plots do
		if plotData.Owner == nil then
			return i
		end
	end
	return nil
end

--[[
	Assigns a plot to a player.
	
	@param player Player - The player to assign a plot to
	@param plotIndex number - The index of the plot to assign
]]
local function assignPlotToPlayer(player: Player, plotIndex: number)
	local plotData = Plots[plotIndex]
	if not plotData then
		warn("Invalid plot index: " .. plotIndex)
		return
	end
	
	if plotData.Owner then
		warn("Plot " .. plotIndex .. " is already owned by " .. plotData.Owner.Name)
		return
	end
	
	-- Assign ownership
	plotData.Owner = player
	PlayerToPlot[player] = plotIndex
	
	-- Set OwnerId attribute on the plot model (for BrainrotManager lookups)
	plotData.Model:SetAttribute("OwnerId", player.UserId)
	plotData.Model:SetAttribute("TierIndex", 1)
	
	-- Update the claim part appearance to show it's claimed
	if plotData.ClaimPart then
		plotData.ClaimPart.BrickColor = BrickColor.new("Really red")
		plotData.ClaimPart.Transparency = 0.7
	end
	
	-- Create a folder for player's buildings on their plot
	local buildingsFolder = Instance.new("Folder")
	buildingsFolder.Name = "PlayerBuildings"
	buildingsFolder.Parent = plotData.Model
	
	-- Initialize tier system for this player
	-- Calculate blocked side (facing main island at origin)
	local plotPos = plotData.Position.Position
	local blockedSide = calculateIncomingSide(Vector3.new(0, 0, 0), plotPos)
	
	local initialTier: TierPlotData = {
		TierIndex = 1,
		Model = plotData.Model,
		Bridge = plotData.Bridge,
		ParentTier = nil,
		BlockedSide = blockedSide,
		UsedSides = {},
		GridIndex = 0,
	}
	
	PlayerTierSystems[player] = {
		BasePlotIndex = plotIndex,
		Tiers = {initialTier},
		CurrentTier = 1,
		TotalModels = 0,
	}
	
	print(string.format("✓ Assigned Plot %d to %s (Tier 1 initialized, blocked side: %d)", plotIndex, player.Name, blockedSide))
end

--[[
	Teleports a player's character to their assigned plot.
	
	@param player Player - The player to teleport
]]
local function teleportPlayerToPlot(player: Player)
	local plotIndex = PlayerToPlot[player]
	if not plotIndex then
		warn("Player " .. player.Name .. " has no assigned plot")
		return
	end
	
	local plotData = Plots[plotIndex]
	if not plotData then return end
	
	-- Wait for character to exist
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
	
	if humanoidRootPart then
		-- Get the actual plot model position (use PrimaryPart or pivot)
		local plotModel = plotData.Model
		local spawnPosition: Vector3
		
		if plotModel.PrimaryPart then
			-- Spawn above the PrimaryPart (the island surface)
			spawnPosition = plotModel.PrimaryPart.Position + Vector3.new(0, 10, 0)
		else
			-- Fallback to pivot position
			spawnPosition = plotModel:GetPivot().Position + Vector3.new(0, 10, 0)
		end
		
		humanoidRootPart.CFrame = CFrame.new(spawnPosition)
		
		print(string.format("✓ Teleported %s to Plot %d at position %s", player.Name, plotIndex, tostring(spawnPosition)))
	else
		warn("Could not find HumanoidRootPart for " .. player.Name)
	end
end

--[[
	Clears a player's data from their plot and resets it.
	Removes any buildings the player placed but keeps the island and bridge.
	
	@param player Player - The player whose plot to clear
]]
local function clearPlayerPlot(player: Player)
	local plotIndex = PlayerToPlot[player]
	if not plotIndex then return end
	
	local plotData = Plots[plotIndex]
	if not plotData then return end
	
	-- Clean up tier system
	local tierSystem = PlayerTierSystems[player]
	if tierSystem then
		-- Remove all tier plots except tier 1 (which is the base plot)
		for i = #tierSystem.Tiers, 2, -1 do
			local tierData = tierSystem.Tiers[i]
			if tierData.Bridge then
				tierData.Bridge:Destroy()
			end
			if tierData.Model then
				tierData.Model:Destroy()
			end
		end
		PlayerTierSystems[player] = nil
	end
	
	-- Remove player buildings
	local buildingsFolder = plotData.Model:FindFirstChild("PlayerBuildings")
	if buildingsFolder then
		buildingsFolder:Destroy()
	end
	
	-- Remove player's brainrots
	local brainrotsFolder = plotData.Model:FindFirstChild("Brainrots")
	if brainrotsFolder then
		brainrotsFolder:Destroy()
	end
	
	-- Reset claim part appearance
	if plotData.ClaimPart then
		plotData.ClaimPart.BrickColor = BrickColor.new("Lime green")
		plotData.ClaimPart.Transparency = 0.3
	end
	
	-- Clear ownership
	plotData.Owner = nil
	PlayerToPlot[player] = nil
	
	-- Clear OwnerId attribute (so BrainrotManager knows plot is free)
	plotData.Model:SetAttribute("OwnerId", nil)
	plotData.Model:SetAttribute("TierIndex", nil)
	
	print(string.format("✓ Cleared Plot %d and tiers (previously owned by %s)", plotIndex, player.Name))
end

--[[
	Handles a new player joining the game.
	Automatically assigns them to the first available plot and teleports them.
	
	@param player Player - The player who joined
]]
local function onPlayerAdded(player: Player)
	print("Player joined: " .. player.Name)
	
	-- Find an available plot
	local plotIndex = findAvailablePlot()
	
	if not plotIndex then
		warn("No available plots for " .. player.Name .. "! All " .. CONFIG.MAX_PLAYERS .. " plots are taken.")
		return
	end
	
	-- Assign the plot to this player
	assignPlotToPlayer(player, plotIndex)
	
	-- Teleport when character spawns
	local function onCharacterAdded(character)
		-- Small delay to ensure character is fully loaded
		task.wait(1)
		teleportPlayerToPlot(player)
	end
	
	-- Connect to CharacterAdded for initial spawn and respawns
	player.CharacterAdded:Connect(onCharacterAdded)
	
	-- If character already exists, teleport now
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

--[[
	Handles a player leaving the game.
	Clears their plot data and resets the plot for the next player.
	
	@param player Player - The player who left
]]
local function onPlayerRemoving(player: Player)
	print("Player leaving: " .. player.Name)
	clearPlayerPlot(player)
end

--------------------------------------------------------------------------------
-- API FUNCTIONS (for other scripts to use)
--------------------------------------------------------------------------------

--[[
	Gets the plot data for a specific player.
	
	@param player Player - The player to get plot data for
	@return table? - The plot data, or nil if player has no plot
]]
local function getPlayerPlot(player: Player)
	local plotIndex = PlayerToPlot[player]
	if plotIndex then
		return Plots[plotIndex]
	end
	return nil
end

--[[
	Gets all plots data.
	
	@return table - Dictionary of all plots
]]
local function getAllPlots()
	return Plots
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   BrainRotClicker - Map Generation")
	print("═══════════════════════════════════════════")
	print("")
	print("Config:")
	print("  • Max Players: " .. CONFIG.MAX_PLAYERS)
	print("  • Plot Radius: " .. CONFIG.PLOT_RADIUS .. " studs")
	print("  • Main Island Height: " .. CONFIG.MAIN_ISLAND_HEIGHT .. " studs")
	print("  • Plot Heights: " .. CONFIG.PLOT_MIN_HEIGHT .. "-" .. CONFIG.PLOT_MAX_HEIGHT .. " studs (random)")
	print("")
	
	-- Initialize templates from storage
	initializeTemplates()
	
	-- Spawn the central hub
	spawnMainIsland()
	
	-- Generate all player plots
	generatePlots()
	
	-- Connect player events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	-- Handle players who joined before this script ran
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	
	print("")
	print("═══════════════════════════════════════════")
	print("   ✓ Map Generation Complete!")
	print("═══════════════════════════════════════════")
end

-- Start the initialization
initialize()

-- Export API for other scripts (using _G for simplicity, or you could use a ModuleScript)
_G.MapSystem = {
	GetPlayerPlot = getPlayerPlot,
	GetAllPlots = getAllPlots,
	CONFIG = CONFIG,
	-- Tier System API
	TIER_CONFIG = TIER_CONFIG,
	GetPlayerTierSystem = function(player: Player): PlayerTierSystem?
		return PlayerTierSystems[player]
	end,
	SpawnTierPlot = spawnTierPlot,
	GetCurrentTier = function(player: Player): TierPlotData?
		local tierSystem = PlayerTierSystems[player]
		if tierSystem then
			return tierSystem.Tiers[tierSystem.CurrentTier]
		end
		return nil
	end,
	ResetPlayerPlot = function(player: Player)
		local plotIndex = PlayerToPlot[player]
		if plotIndex then
			print(string.format("🔄 Admin resetting plot %d for %s", plotIndex, player.Name))
			clearPlayerPlot(player)
			-- Small delay to ensure cleanup
			task.wait(0.1)
			assignPlotToPlayer(player, plotIndex)
			-- Teleport back
			task.delay(0.5, function() 
				teleportPlayerToPlot(player) 
			end)
		end
	end,
	-- Persistence: Restore tiers from saved data
	RestoreTiers = function(player: Player, tierCount: number)
		local tierSystem = PlayerTierSystems[player]
		if not tierSystem then
			warn("RestoreTiers: No tier system found for " .. player.Name)
			return
		end
		
		if tierCount <= 1 then
			print(string.format("RestoreTiers: Only base tier for %s, nothing to restore", player.Name))
			return -- Only base tier, nothing to restore
		end
		
		print(string.format("🔄 Restoring %d tiers for %s (current tiers: %d)", tierCount, player.Name, #tierSystem.Tiers))
		
		-- Spawn additional tiers up to tierCount
		for i = 2, tierCount do
			local currentTier = tierSystem.Tiers[#tierSystem.Tiers]
			if currentTier then
				print(string.format("  Spawning tier %d from parent tier %d...", i, currentTier.TierIndex))
				local newTier = spawnTierPlot(player, currentTier)
				if newTier then
					tierSystem.CurrentTier = newTier.TierIndex
					print(string.format("  ✓ Tier %d spawned successfully (bridge/stairs: %s)", 
						i, newTier.Bridge and newTier.Bridge.Name or "nil"))
				else
					warn(string.format("RestoreTiers: Failed to spawn tier %d for %s", i, player.Name))
					break
				end
			else
				warn(string.format("RestoreTiers: No current tier found for iteration %d", i))
			end
		end
		
		print(string.format("✓ Restored %d tiers for %s", #tierSystem.Tiers, player.Name))
	end,
}
