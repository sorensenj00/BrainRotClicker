--[[
	ItemTypes.luau
	Shared type definitions for the unified inventory system.
]]

export type ItemType = "Unit" | "Artifact"

export type Item = {
	UUID: string,
	Type: ItemType,
	Id: string, -- The internal ID (e.g. "Skibidi_Toilet", "Ruby_Amulet")
	Name: string,
	Rarity: string,
	Icon: string, -- TextureId or Emoji
	
	-- State
	IsEquipped: boolean, -- For artifacts
	IsPlaced: boolean, -- For units
	
	-- Specific Data
	Data: {
		-- Unit specific
		Level: number?, 
		Equipment: {[string]: string}?, -- map of slot->artifactUUID
		
		-- Artifact specific
		Stats: {[string]: number}?, -- calculated stats
		EquippedTo: string?, -- UUID of unit equipping this
	}
}

return {}
