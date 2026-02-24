--[[
	ArtifactExchangeConfig - Shared Configuration for the Grand Exchange

	Cross-server order book market for unique artifacts.
	Located in ReplicatedStorage so both Server and Client can access it.
]]

local ArtifactExchangeConfig = {}

--------------------------------------------------------------------------------
-- MARKET RULES
--------------------------------------------------------------------------------

ArtifactExchangeConfig.LISTING_TAX = 0.10          -- 10% tax burned on successful sale
ArtifactExchangeConfig.MAX_ACTIVE_LISTINGS = 3     -- Max listings per player
ArtifactExchangeConfig.MIN_PRICE = 100             -- Minimum listing price
ArtifactExchangeConfig.MAX_PRICE = 1000000000      -- Maximum listing price ($1B)
ArtifactExchangeConfig.LISTING_TTL = 3888000       -- MemoryStore TTL: 45 days (max)

--------------------------------------------------------------------------------
-- SERVER CACHE
--------------------------------------------------------------------------------

ArtifactExchangeConfig.CACHE_POLL_INTERVAL = 10    -- Seconds between MemoryStore reads
ArtifactExchangeConfig.MAX_CACHED_LISTINGS = 200   -- Max listings to cache per poll
ArtifactExchangeConfig.CLIENT_REFRESH_HINT = 5     -- Suggested client UI refresh interval

--------------------------------------------------------------------------------
-- VENDOR (Temp Shop)
--------------------------------------------------------------------------------

ArtifactExchangeConfig.VENDOR_TAG = "ArtifactExchangeVendor"
ArtifactExchangeConfig.VENDOR_POSITION = Vector3.new(10, 32, -55) -- Near existing market
ArtifactExchangeConfig.VENDOR_SIZE = Vector3.new(6, 8, 6)
ArtifactExchangeConfig.VENDOR_COLOR = Color3.fromRGB(180, 140, 60) -- Gold tint

--------------------------------------------------------------------------------
-- UI THEME (Premium dark theme matching HFT Terminal)
--------------------------------------------------------------------------------

ArtifactExchangeConfig.UI = {
	-- Core colors
	BG = Color3.fromRGB(12, 12, 20),
	PANEL = Color3.fromRGB(18, 18, 28),
	CARD = Color3.fromRGB(25, 25, 38),
	CARD_HOVER = Color3.fromRGB(32, 32, 48),
	BORDER = Color3.fromRGB(50, 50, 70),
	
	-- Text
	WHITE = Color3.fromRGB(240, 240, 255),
	MUTED = Color3.fromRGB(130, 130, 155),
	DIM = Color3.fromRGB(80, 80, 100),
	
	-- Accents
	GOLD = Color3.fromRGB(250, 190, 60),
	GREEN = Color3.fromRGB(80, 230, 120),
	RED = Color3.fromRGB(250, 80, 80),
	BLUE = Color3.fromRGB(60, 150, 255),
	PURPLE = Color3.fromRGB(120, 80, 220),
	
	-- Rarity
	COMMON = Color3.fromRGB(180, 180, 180),
	UNCOMMON = Color3.fromRGB(100, 200, 100),
	RARE = Color3.fromRGB(100, 150, 255),
	EPIC = Color3.fromRGB(180, 100, 255),
	LEGENDARY = Color3.fromRGB(255, 180, 50),
}

return ArtifactExchangeConfig
