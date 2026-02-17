local TileConfig = {}

--------------------------------------------------------------------------------
-- TILE DEFINITIONS
--------------------------------------------------------------------------------

TileConfig.Tiles = {
	-- ═══════════════════════════════════════════════════════════════════════
	-- THEMED TILES (50% speed boost to units with matching name keywords)
	-- ═══════════════════════════════════════════════════════════════════════
	
	Lava = {
		Id = "Lava",
		Name = "Molten Floor",
		Description = "Explosive and Crocodile units work 50% faster here.",
		Icon = "🌋",
		BoostKeywords = {"Bombard", "Boom", "Croc", "Nuke", "Atomic"},
		SpeedMult = 1.5,
		LuckMult = 1.0,
		Color = Color3.fromRGB(255, 100, 50),
		TextureId = "",
		ParticleEffect = "Fire",
		UnlockCost = 5000,
		UnlockTier = 1,
	},
	
	Ice = {
		Id = "Ice",
		Name = "Frozen Ground",
		Description = "Cold and Winter units work 50% faster here.",
		Icon = "❄️",
		BoostKeywords = {"Brr", "Ice", "Penguin", "Frosty", "Camelo", "Blueberry"},
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
		Description = "Musical and Talented units work 50% faster here.",
		Icon = "🎭",
		BoostKeywords = {"Trala", "Dance", "Music", "Horse", "Messi", "Piano", "Sahur", "Symphony"},
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
		Description = "Godly and Mythical units work 50% faster here.",
		Icon = "👑",
		BoostKeywords = {"God", "Odin", "Mythic", "King", "Royal", "Elite", "Master"},
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
		Description = "Food and Noob units work 50% faster here.",
		Icon = "🚽",
		BoostKeywords = {"Pizza", "Noob", "Toast", "Pot", "Chef", "Coffee", "Cap", "Signora"},
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
		Description = "Animal and Tropical units work 50% faster here.",
		Icon = "🐱",
		BoostKeywords = {"Ban", "Animal", "Guffo", "Berry", "Fruit", "Mew", "Cat", "Neon", "Nyan", "Panda", "Giraffe", "Elephant"},
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
		BoostKeywords = nil,  -- nil = all units
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
		BoostKeywords = nil,
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
		BoostKeywords = nil,
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
function TileConfig.GetTile(tileId: string)
	return TileConfig.Tiles[tileId]
end

--[[
	Calculates the speed multiplier for a unit on a tile.
	@param tileId string - The tile ID
	@param unitType string - The unit's model name/type
	@return number - Speed multiplier (higher = faster production)
]]
function TileConfig.GetSpeedBonus(tileId: string, unitType: string)
	local tile = TileConfig.Tiles[tileId]
	if not tile then return 1.0 end
	
	-- Universal tiles apply to all units
	if tile.BoostKeywords == nil then
		return tile.SpeedMult
	end
	
	-- Check if unit matches any keywords
	if unitType then
		for _, keyword in ipairs(tile.BoostKeywords) do
			if string.find(string.lower(unitType), string.lower(keyword)) then
				return tile.SpeedMult
			end
		end
	end
	
	-- No bonus for non-matching units
	return 1.0
end

--[[
	Calculates the luck multiplier for a unit on a tile.
	@param tileId string - The tile ID
	@param unitType string - The unit's model name (ignored, but for parity)
	@return number - Luck multiplier (higher = more artifact drops)
]]
function TileConfig.GetLuckBonus(tileId: string, unitType: string?)
	local tile = TileConfig.Tiles[tileId]
	if not tile then return 1.0 end
	
	-- Luck bonus applies regardless of unit type
	return tile.LuckMult
end

--[[
	Gets all bonuses for a unit on a tile.
	@param tileId string - The tile ID
	@param unitType string - The unit's model name
	@return table - {SpeedMult, LuckMult}
]]
function TileConfig.GetBonus(tileId: string, unitType: string)
	return {
		SpeedMult = TileConfig.GetSpeedBonus(tileId, unitType),
		LuckMult = TileConfig.GetLuckBonus(tileId, unitType),
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

