--[[
	TileConfig - Shared Configuration for Grid Tiles
	
	Defines flooring types and their synergy bonuses.
	Tiles can be placed on the grid, and Units placed on top receive bonuses.
	
	Located in ReplicatedStorage so both Server and Client can access it.
]]

local TileConfig = {}

--------------------------------------------------------------------------------
-- TILE DEFINITIONS
--------------------------------------------------------------------------------

TileConfig.Tiles = {
	-- ═══════════════════════════════════════════════════════════════════════
	-- CATEGORY-SPECIFIC TILES (50% speed boost to matching units)
	-- ═══════════════════════════════════════════════════════════════════════
	
	Lava = {
		Id = "Lava",
		Name = "Molten Floor",
		Description = "Bombardiro units work 50% faster here.",
		Icon = "🌋",
		BonusCategory = "Bombardiro",
		SpeedMult = 1.5,
		LuckMult = 1.0,
		Color = Color3.fromRGB(255, 100, 50),
		TextureId = "",  -- Optional: can be rbxassetid://
		ParticleEffect = "Fire",
		UnlockCost = 5000,
		UnlockTier = 1,
	},
	
	Ice = {
		Id = "Ice",
		Name = "Frozen Ground",
		Description = "BrrBrr units work 50% faster here.",
		Icon = "❄️",
		BonusCategory = "BrrBrr",
		SpeedMult = 1.5,
		LuckMult = 1.0,
		Color = Color3.fromRGB(150, 220, 255),
		TextureId = "",
		ParticleEffect = "Snow",
		UnlockCost = 5000,
		UnlockTier = 1,
	},
	
	Stage = {
		Id = "Stage",
		Name = "Performance Stage",
		Description = "Tralalero units work 50% faster here.",
		Icon = "🎭",
		BonusCategory = "Tralalero",
		SpeedMult = 1.5,
		LuckMult = 1.0,
		Color = Color3.fromRGB(200, 150, 100),
		TextureId = "",
		ParticleEffect = "Confetti",
		UnlockCost = 5000,
		UnlockTier = 1,
	},
	
	Throne = {
		Id = "Throne",
		Name = "Throne Platform",
		Description = "Sigma units work 50% faster here.",
		Icon = "👑",
		BonusCategory = "Sigma",
		SpeedMult = 1.5,
		LuckMult = 1.0,
		Color = Color3.fromRGB(100, 50, 150),
		TextureId = "",
		ParticleEffect = "Crown",
		UnlockCost = 5000,
		UnlockTier = 1,
	},
	
	Toilet = {
		Id = "Toilet",
		Name = "Bathroom Floor",
		Description = "Skibidi units work 50% faster here.",
		Icon = "🚽",
		BonusCategory = "Skibidi",
		SpeedMult = 1.5,
		LuckMult = 1.0,
		Color = Color3.fromRGB(200, 200, 220),
		TextureId = "",
		ParticleEffect = "Bubbles",
		UnlockCost = 5000,
		UnlockTier = 1,
	},
	
	Cozy = {
		Id = "Cozy",
		Name = "Cozy Carpet",
		Description = "Mewer units work 50% faster here.",
		Icon = "🐱",
		BonusCategory = "Mewer",
		SpeedMult = 1.5,
		LuckMult = 1.0,
		Color = Color3.fromRGB(255, 180, 200),
		TextureId = "",
		ParticleEffect = "Hearts",
		UnlockCost = 5000,
		UnlockTier = 1,
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- UNIVERSAL TILES (Smaller bonuses to all units)
	-- ═══════════════════════════════════════════════════════════════════════
	
	Grass = {
		Id = "Grass",
		Name = "Grass Patch",
		Description = "All units work 10% faster here.",
		Icon = "🌱",
		BonusCategory = nil,  -- nil = all categories
		SpeedMult = 1.1,
		LuckMult = 1.0,
		Color = Color3.fromRGB(100, 180, 80),
		TextureId = "",
		ParticleEffect = nil,
		UnlockCost = 1000,
		UnlockTier = 1,
	},
	
	Gold = {
		Id = "Gold",
		Name = "Golden Platform",
		Description = "25% higher artifact drop chance here.",
		Icon = "💰",
		BonusCategory = nil,
		SpeedMult = 1.0,
		LuckMult = 1.25,
		Color = Color3.fromRGB(255, 215, 0),
		TextureId = "",
		ParticleEffect = "Sparkle",
		UnlockCost = 10000,
		UnlockTier = 2,
	},
	
	Diamond = {
		Id = "Diamond",
		Name = "Diamond Floor",
		Description = "20% faster + 20% higher artifact chance.",
		Icon = "💎",
		BonusCategory = nil,
		SpeedMult = 1.2,
		LuckMult = 1.2,
		Color = Color3.fromRGB(180, 230, 255),
		TextureId = "",
		ParticleEffect = "Diamond",
		UnlockCost = 50000,
		UnlockTier = 3,
	},
}

-- Tile visual properties
TileConfig.TileHeight = 0.5  -- Studs thick
TileConfig.TileSize = 9.5   -- Slightly smaller than grid slot for visual gap

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Gets a tile definition by ID.
	@param tileId string - The tile ID
	@return table? - The tile definition or nil
]]
function TileConfig.GetTile(tileId)
	return TileConfig.Tiles[tileId]
end

--[[
	Calculates the speed multiplier for a unit on a tile.
	@param tileId string - The tile ID
	@param unitCategory string - The unit's category (from ItemConfig)
	@return number - Speed multiplier (higher = faster production)
]]
function TileConfig.GetSpeedBonus(tileId, unitCategory)
	local tile = TileConfig.Tiles[tileId]
	if not tile then return 1.0 end
	
	-- Universal tiles apply to all
	if tile.BonusCategory == nil then
		return tile.SpeedMult
	end
	
	-- Category-specific tiles only apply to matching units
	if tile.BonusCategory == unitCategory then
		return tile.SpeedMult
	end
	
	-- No bonus for non-matching category
	return 1.0
end

--[[
	Calculates the luck multiplier for a unit on a tile.
	@param tileId string - The tile ID
	@param unitCategory string - The unit's category
	@return number - Luck multiplier (higher = more artifact drops)
]]
function TileConfig.GetLuckBonus(tileId, unitCategory)
	local tile = TileConfig.Tiles[tileId]
	if not tile then return 1.0 end
	
	-- Luck bonus applies regardless of category
	return tile.LuckMult
end

--[[
	Gets all bonuses for a unit on a tile.
	@param tileId string - The tile ID
	@param unitCategory string - The unit's category
	@return table - {SpeedMult, LuckMult}
]]
function TileConfig.GetBonus(tileId, unitCategory)
	return {
		SpeedMult = TileConfig.GetSpeedBonus(tileId, unitCategory),
		LuckMult = TileConfig.GetLuckBonus(tileId, unitCategory),
	}
end

--[[
	Gets all tiles available at a given tier.
	@param tier number - The player's tier level
	@return table - Array of tile definitions
]]
function TileConfig.GetUnlockedTiles(tier)
	local unlocked = {}
	for id, tile in pairs(TileConfig.Tiles) do
		if tile.UnlockTier <= tier then
			table.insert(unlocked, tile)
		end
	end
	return unlocked
end

--[[
	Gets all tile IDs as an array for UI iteration.
	@return table - Array of tile IDs
]]
function TileConfig.GetAllTileIds()
	local ids = {}
	for id, _ in pairs(TileConfig.Tiles) do
		table.insert(ids, id)
	end
	table.sort(ids)  -- Alphabetical for consistent ordering
	return ids
end

return TileConfig
