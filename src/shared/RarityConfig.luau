--[[
	RarityConfig.luau

	Shared configuration for unit rarities.
	Handles rarity definitions, probabilities, and multipliers.
]]

export type RarityInfo = {
	chance: number,
	multiplier: number,
	color: Color3
}

local RARITY_CONFIG: {[string]: RarityInfo} = {
	Normal = { chance = 0.90, multiplier = 1, color = Color3.fromRGB(255, 255, 255) },
	Spicy = { chance = 0.09, multiplier = 1.5, color = Color3.fromRGB(255, 80, 80) },
	Galaxy = { chance = 0.01, multiplier = 3.0, color = Color3.fromRGB(180, 100, 255) },
}

local RARITY_ORDER = {"Normal", "Spicy", "Galaxy"}

local RarityConfig = {}

RarityConfig.CONFIG = RARITY_CONFIG
RarityConfig.ORDER = RARITY_ORDER

--[[
	Rolls a random rarity based on configured chances.
]]
function RarityConfig.RollRarity(): string
	local roll = math.random()
	local cumulative = 0
	for _, rarityName in ipairs(RARITY_ORDER) do
		local config = RARITY_CONFIG[rarityName]
		if config then
			cumulative = cumulative + config.chance
			if roll <= cumulative then return rarityName end
		end
	end
	return "Normal"
end

--[[
	Gets the numeric value/rank of a rarity (higher is better).
]]
function RarityConfig.GetRarityValue(rarityName: string): number
	for i, name in ipairs(RARITY_ORDER) do
		if name == rarityName then return i end
	end
	return 1
end

--[[
	Gets the multiplier for a given rarity.
]]
function RarityConfig.GetMultiplier(rarityName: string): number
	local config = RARITY_CONFIG[rarityName]
	return config and config.multiplier or 1
end

--[[
	Gets the color for a given rarity.
]]
function RarityConfig.GetColor(rarityName: string): Color3
	local config = RARITY_CONFIG[rarityName]
	return config and config.color or Color3.fromRGB(255, 255, 255)
end

return RarityConfig
