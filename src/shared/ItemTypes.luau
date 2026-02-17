--[[
	ItemTypes.luau
	
	═══════════════════════════════════════════════════════════════════════════════
	                     TYPE DEFINITIONS FOR TWO RESOURCE SYSTEMS
	═══════════════════════════════════════════════════════════════════════════════
	
	This file defines types for BOTH resource systems in the game:
	
	┌─────────────────────────────────────────────────────────────────────────────┐
	│  PERMANENT ASSETS (Collection)                                              │
	│  ─────────────────────────────────                                          │
	│  • BrainrotUnit  - Brainrot characters the player OWNS (InventoryManager)   │
	│  • Artifact      - Equipment items the player OWNS (ArtifactManager)        │
	│  These PERSIST forever, are saved to profile, and never get consumed.       │
	├─────────────────────────────────────────────────────────────────────────────┤
	│  TRANSIENT RESOURCES (Factory/Production)                                   │
	│  ─────────────────────────────────────────                                  │
	│  • FactoryItem   - Resources produced by units (ItemStorageManager)         │
	│  These are TEMPORARY, get sold for money, and are consumed.                 │
	│  Flow: ItemProductionManager → ItemStorageManager → TransportManager → Sold │
	└─────────────────────────────────────────────────────────────────────────────┘
]]

--------------------------------------------------------------------------------
-- PERMANENT ASSETS: Units & Artifacts (stored in InventoryManager/ArtifactManager)
--------------------------------------------------------------------------------

-- Category discriminator for collection items
export type CollectionItemType = "Unit" | "Artifact"

--[[
	BrainrotUnit: A permanent character the player owns.
	
	Stored in: InventoryManager
	Lifetime: PERMANENT - saved to profile, never consumed
	
	Examples: "Skibidi_Toilet", "Bombardiro_Crocodilo", "Sigma"
]]
export type BrainrotUnit = {
	UUID: string,               -- Unique identifier for this specific unit instance
	Type: "Unit",               -- Always "Unit" for BrainrotUnits
	Id: string,                 -- Model name (e.g. "Skibidi_Toilet")
	Name: string,               -- Display name (e.g. "Skibidi Toilet")
	Rarity: string,             -- "Normal", "Rare", "Legendary", etc.
	Icon: string,               -- TextureId or Emoji for UI display
	
	-- State
	IsPlaced: boolean,          -- true if placed on grid, false if in inventory
	
	-- Unit-specific data
	Data: {
		Level: number,                      -- Current level (1+)
		Equipment: {[string]: string}?,     -- Map of slot → artifactUUID
	}
}

--[[
	Artifact: A permanent equipment item the player owns.
	
	Stored in: ArtifactManager
	Lifetime: PERMANENT - saved to profile, never consumed
	
	Examples: "Ruby_Amulet", "Speed_Boots", "Power_Ring"
]]
export type Artifact = {
	UUID: string,               -- Unique identifier for this artifact instance
	Type: "Artifact",           -- Always "Artifact" for Artifacts
	Id: string,                 -- Artifact type ID (e.g. "Ruby_Amulet")
	Name: string,               -- Display name
	Rarity: string,             -- Rarity tier
	Icon: string,               -- TextureId or Emoji
	
	-- State
	IsEquipped: boolean,        -- true if equipped to a unit
	
	-- Artifact-specific data
	Data: {
		Stats: {[string]: number}?,  -- Calculated stats (damage, speed, etc.)
		EquippedTo: string?,         -- UUID of the unit this is equipped to
	}
}

--------------------------------------------------------------------------------
-- TRANSIENT RESOURCES: Factory Production (stored in ItemStorageManager)
--------------------------------------------------------------------------------

--[[
	FactoryItem: A transient resource produced by units.
	
	Stored in: ItemStorageManager (silos/backpack)
	Lifetime: TEMPORARY - produced, stored, sold, consumed
	
	Flow: Unit produces → Storage (silo) → Backpack → Sell at Market
	
	Examples: "ToiletPaper", "Plunger", "Firecracker", "ProteinBar"
	
	NOTE: For the full item DEFINITION (basePrice, volatility, tier, etc.),
	      see ItemConfig.luau → ItemDefinition. This type is for runtime stacks.
]]
export type FactoryItem = {
	itemId: string,             -- References ItemConfig.Items[itemId]
	count: number,              -- Stack count in storage/backpack
}

--------------------------------------------------------------------------------
-- LEGACY ALIASES (for backwards compatibility, prefer specific types above)
--------------------------------------------------------------------------------

-- CollectionItem: Union type for any permanent asset (Unit OR Artifact)
-- @deprecated Prefer using BrainrotUnit or Artifact directly for strict typing
export type CollectionItem = {
	UUID: string,
	Type: CollectionItemType,
	Id: string,
	Name: string,
	Rarity: string,
	Icon: string,
	
	-- State (one will be relevant depending on Type)
	IsEquipped: boolean,  -- For artifacts
	IsPlaced: boolean,    -- For units
	
	-- Combined data (fields optional based on Type)
	Data: {
		-- Unit specific
		Level: number?, 
		Equipment: {[string]: string}?,
		
		-- Artifact specific
		Stats: {[string]: number}?,
		EquippedTo: string?,
	}
}

-- Legacy alias
export type ItemType = CollectionItemType

return {}
