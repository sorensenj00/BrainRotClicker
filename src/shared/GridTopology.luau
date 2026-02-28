--[[
	GridTopology Shared Module

	Centralizes grid math, slot positioning, and clustering logic.
	Used by both Server (GridManager) and Client (BuildModeUI) for consistent placement.
]]

local GridTopology = {}

GridTopology.CONSTANTS = {
	TILE_SIZE = 10,
	GRID_OFFSET_Y = 0,
	CLUSTER_SIZE = 2,
	-- Offsets for corner clusters relative to plot center
	-- These depend on plot size, calculated dynamically
}

--[[
	Calculates the CFrame for a specific slot index on a plot.

	@param plotCFrame CFrame - The center CFrame of the plot (usually the floor/island)
	@param plotSize Vector3 - The size of the plot (usually the floor/island size)
	@param slotIndex number - The index of the slot (1-based)
	@param tileHeight number - (Optional) Additional height offset for tiles
	@return CFrame - The world CFrame for the slot
]]
function GridTopology.GetSlotCFrame(plotCFrame: CFrame, plotSize: Vector3, slotIndex: number, tileHeight: number?)
	tileHeight = tileHeight or 0
	local localSlotIndex = ((slotIndex - 1) % 16) + 1

	local plotCenter = plotCFrame.Position
	local posY = plotCenter.Y + (plotSize.Y / 2) + GridTopology.CONSTANTS.GRID_OFFSET_Y + tileHeight

	local TILE_SPACING = GridTopology.CONSTANTS.TILE_SIZE

	-- Push the clusters further towards the edges of the plot
	local centerDistance = (plotSize.X / 2) * 0.55 -- Push out to 55% of the radius
	
	-- 4 Clusters of 4 slots each (standard 16 slot layout)
	local cornerIndex = math.floor((localSlotIndex - 1) / 4)
	local posInCorner = (localSlotIndex - 1) % 4
	
	-- Diamond pattern offsets instead of 2x2 square
	local diamondOffsets = {
		[0] = {x = 0, z = -1}, -- Top
		[1] = {x = -1, z = 0}, -- Left
		[2] = {x = 1, z = 0},  -- Right
		[3] = {x = 0, z = 1},  -- Bottom
	}
	
	local localOffset = diamondOffsets[posInCorner] or {x = 0, z = 0}

	local cornerPositions = {
		{x = -centerDistance, z = -centerDistance},  -- Top-Left
		{x = centerDistance, z = -centerDistance},   -- Top-Right
		{x = -centerDistance, z = centerDistance},   -- Bottom-Left
		{x = centerDistance, z = centerDistance},    -- Bottom-Right
	}

	-- Fallback to first corner if index is out of bounds (should happen only if grid expands)
	local corner = cornerPositions[cornerIndex + 1] or cornerPositions[1]

	local posX = plotCenter.X + corner.x + (localOffset.x * TILE_SPACING)
	local posZ = plotCenter.Z + corner.z + (localOffset.z * TILE_SPACING)

	local unitPos = Vector3.new(posX, posY, posZ)

	-- Look towards center of plot
	local lookDirection = (plotCenter - unitPos) * Vector3.new(1, 0, 1)
	if lookDirection.Magnitude == 0 then
		lookDirection = Vector3.new(0, 0, -1)
	end

	return CFrame.lookAt(unitPos, unitPos + lookDirection)
end

--[[
	Returns the list of slot indices that belong to the same cluster as the given slot.
	Useful for synergy checks.

	@param slotIndex number
	@return {number} - List of 4 slot indices
]]
function GridTopology.GetClusterSlots(slotIndex: number)
	local clusterIdx = math.floor((slotIndex - 1) / 4)
	local baseSlot = clusterIdx * 4 + 1
	return { baseSlot, baseSlot + 1, baseSlot + 2, baseSlot + 3 }
end

return GridTopology
