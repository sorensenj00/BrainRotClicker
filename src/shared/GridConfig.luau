--[[
	GridConfig Shared Module

	Centralizes grid constants and math to ensure Client/Server sync.
]]

local GridConfig = {}

-- Constants
GridConfig.TILE_SIZE = 10
GridConfig.CLUSTER_SIZE = 2 -- 2x2 per corner
GridConfig.GRID_OFFSET_Y = 5 -- Height above plot top surface

-- Colors (Shared for reference)
GridConfig.COLORS = {
	EMPTY = Color3.fromRGB(100, 100, 150),
	OCCUPIED = Color3.fromRGB(80, 200, 80),
	HOVER = Color3.fromRGB(100, 200, 255),
	SELECTED = Color3.fromRGB(255, 200, 50),
	INVALID = Color3.fromRGB(255, 80, 80),
}

-- Grid Sizes
GridConfig.SIZES = {
	starter = {rows = 4, cols = 4},
	bronze = {rows = 4, cols = 5},
	silver = {rows = 5, cols = 5},
	gold = {rows = 6, cols = 6},
}

--[[
	Calculates the local position (relative to plot center) for a slot.
	Returns x, z offsets.
]]
function GridConfig.GetSlotOffset(slotIndex, plotSizeX, plotSizeZ)
	local TILE_SPACING = GridConfig.TILE_SIZE
	local CLUSTER_SIZE = GridConfig.CLUSTER_SIZE

	-- Calculate corner offsets
	local cornerOffsetX = (plotSizeX / 2) - (CLUSTER_SIZE * TILE_SPACING / 2) - TILE_SPACING
	local cornerOffsetZ = (plotSizeZ / 2) - (CLUSTER_SIZE * TILE_SPACING / 2) - TILE_SPACING

	-- Determine corner and position
	local cornerIndex = math.floor((slotIndex - 1) / 4)
	local posInCorner = (slotIndex - 1) % 4

	local localRow = math.floor(posInCorner / 2)
	local localCol = posInCorner % 2

	-- Corner directions: TL, TR, BL, BR
	local cornerDirs = {
		{x = -1, z = -1},
		{x = 1, z = -1},
		{x = -1, z = 1},
		{x = 1, z = 1},
	}

	local dir = cornerDirs[cornerIndex + 1] or cornerDirs[1]

	-- Corner center position
	local cx = dir.x * cornerOffsetX
	local cz = dir.z * cornerOffsetZ

	-- Final offset
	local posX = cx + (localCol - 0.5) * TILE_SPACING
	local posZ = cz + (localRow - 0.5) * TILE_SPACING

	return posX, posZ
end

return GridConfig
