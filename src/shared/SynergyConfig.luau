--[[
	SynergyConfig - Shared Configuration for Brainrot Synergies
	
	Defines synergy combinations that provide bonuses when requirements are met.
	
	Synergy Types:
	- Global: Affects all brainrots or player stats
	- Local: Only affects the specific brainrots involved in the synergy
	
	Requirements can specify:
	- Unit type (required)
	- Minimum count (required)
	- Specific rarity (optional - nil means any rarity counts)
]]

export type SynergyRequirement = {
	UnitName: string,           -- The brainrot type required
	MinCount: number,           -- Minimum number needed
	Rarity: string?,            -- Optional: specific rarity required (nil = any)
}

export type SynergyEffect = {
	Type: "IncomeMultiplier" | "CycleReduction" | "GlobalIncomeBoost",
	Target: "All" | "Specific",  -- All brainrots or specific units
	TargetUnits: {string}?,      -- If Target is "Specific", which units are affected
	Value: number,               -- Multiplier or percentage value
}

export type SynergyDefinition = {
	Id: string,                  -- Unique identifier
	Name: string,                -- Display name
	Description: string,         -- What the synergy does
	Icon: string,                -- Emoji icon for display
	Requirements: {SynergyRequirement}, -- What's needed to unlock
	Effects: {SynergyEffect},    -- What bonuses are applied
}

local SynergyConfig = {}

--------------------------------------------------------------------------------
-- SYNERGY DEFINITIONS
--------------------------------------------------------------------------------

SynergyConfig.Synergies = {
	--[[
		Example Synergy: Italian Brainrot Alliance
		Requires 10 Avocadini Guffo + 100 Brr_Brr_Patapim
		Result: Brr_Brr_Patapim gains 100% income multiplier
	]]
	ItalianAlliance = {
		Id = "ItalianAlliance",
		Name = "Italian Brainrot Alliance",
		Description = "Brr Brr Patapim gains +100% income!",
		Icon = "🇮🇹",
		Requirements = {
			{
				UnitName = "Avocadini Guffo",
				MinCount = 10,
				Rarity = nil, -- Any rarity counts
			},
			{
				UnitName = "Brr_Brr_Patapim",
				MinCount = 100,
				Rarity = nil,
			},
		},
		Effects = {
			{
				Type = "IncomeMultiplier",
				Target = "Specific",
				TargetUnits = {"Brr_Brr_Patapim"},
				Value = 2.0, -- 2x = +100% income
			},
		},
	},
	
	--[[
		Example Synergy: Spicy Collection
		Requires 5 Spicy rarity of any brainrot type
		Result: All brainrots gain +25% income
	]]
	-- SpicyCollection = {
	-- 	Id = "SpicyCollection",
	-- 	Name = "Spicy Collection",
	-- 	Description = "All brainrots gain +25% income!",
	-- 	Icon = "🌶️",
	-- 	Requirements = {
	-- 		{
	-- 			UnitName = "*", -- Wildcard: any unit type
	-- 			MinCount = 5,
	-- 			Rarity = "Spicy",
	-- 		},
	-- 	},
	-- 	Effects = {
	-- 		{
	-- 			Type = "IncomeMultiplier",
	-- 			Target = "All",
	-- 			TargetUnits = nil,
	-- 			Value = 1.25, -- 1.25x = +25% income
	-- 		},
	-- 	},
	-- },
}

-- Ordered list for display
SynergyConfig.SynergyOrder = {"ItalianAlliance"}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Gets a synergy definition by ID.
	@param synergyId string - The synergy ID
	@return SynergyDefinition? - The synergy definition or nil
]]
function SynergyConfig.GetSynergy(synergyId: string): SynergyDefinition?
	return SynergyConfig.Synergies[synergyId]
end

--[[
	Gets all synergy definitions in display order.
	@return {SynergyDefinition} - Array of synergy definitions
]]
function SynergyConfig.GetAllSynergies(): {SynergyDefinition}
	local synergies = {}
	for _, synergyId in SynergyConfig.SynergyOrder do
		local synergy = SynergyConfig.Synergies[synergyId]
		if synergy then
			table.insert(synergies, synergy)
		end
	end
	return synergies
end

--[[
	Checks if a player meets the requirements for a synergy.
	@param synergyId string - The synergy ID to check
	@param inventoryData table - Player's inventory {[unitName]: {[rarity]: {total, active}}}
	@return boolean, {[string]: {current: number, required: number}} - Met status and progress
]]
function SynergyConfig.CheckSynergyProgress(
	synergyId: string, 
	inventoryData: {[string]: {[string]: {total: number, active: number}}}
): (boolean, {[string]: {current: number, required: number}})
	local synergy = SynergyConfig.Synergies[synergyId]
	if not synergy then
		return false, {}
	end
	
	local progress = {}
	local allMet = true
	
	for _, req in synergy.Requirements do
		local current = 0
		local key = req.UnitName .. (req.Rarity and ("_" .. req.Rarity) or "")
		
		if req.UnitName == "*" then
			-- Wildcard: count all units of this rarity
			for _, unitRarities in inventoryData do
				if req.Rarity then
					local rarityData = unitRarities[req.Rarity]
					if rarityData then
						current = current + rarityData.total
					end
				else
					for _, rarityData in unitRarities do
						current = current + rarityData.total
					end
				end
			end
		else
			-- Specific unit
			local unitData = inventoryData[req.UnitName]
			if unitData then
				if req.Rarity then
					local rarityData = unitData[req.Rarity]
					if rarityData then
						current = rarityData.total
					end
				else
					-- Sum all rarities
					for _, rarityData in unitData do
						current = current + rarityData.total
					end
				end
			end
		end
		
		progress[key] = {
			current = current,
			required = req.MinCount,
			unitName = req.UnitName,
			rarity = req.Rarity,
		}
		
		if current < req.MinCount then
			allMet = false
		end
	end
	
	return allMet, progress
end

return SynergyConfig
