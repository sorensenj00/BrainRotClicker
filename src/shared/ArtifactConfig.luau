--[[
	ArtifactConfig - Shared Configuration for Procedural Artifacts
	
	Defines artifact generation rules, rarity weights, affixes, and equipment slots.
	
	Located in ReplicatedStorage so both Server and Client can access it.
]]

local ArtifactConfig = {}

--------------------------------------------------------------------------------
-- RARITY SYSTEM
--------------------------------------------------------------------------------

ArtifactConfig.RarityWeights = {
	Common = 60,      -- 60% drop chance
	Uncommon = 25,    -- 25% drop chance
	Rare = 10,        -- 10% drop chance
	Epic = 4,         -- 4% drop chance
	Legendary = 1,    -- 1% drop chance
}

ArtifactConfig.RarityColors = {
	Common = Color3.fromRGB(180, 180, 180),      -- Gray
	Uncommon = Color3.fromRGB(100, 200, 100),    -- Green
	Rare = Color3.fromRGB(100, 150, 255),        -- Blue
	Epic = Color3.fromRGB(180, 100, 255),        -- Purple
	Legendary = Color3.fromRGB(255, 180, 50),    -- Gold
}

-- Number of affixes per rarity
ArtifactConfig.AffixCountByRarity = {
	Common = 1,
	Uncommon = 1,
	Rare = 2,
	Epic = 2,
	Legendary = 3,
}

--------------------------------------------------------------------------------
-- EQUIPMENT SLOTS
--------------------------------------------------------------------------------

ArtifactConfig.EquipmentSlots = {
	"Head",
	"Body",
	"Accessory",
}

ArtifactConfig.SlotIcons = {
	Head = "👒",
	Body = "👔",
	Accessory = "📿",
}

--------------------------------------------------------------------------------
-- AFFIXES (Prefixes and Suffixes)
--------------------------------------------------------------------------------

-- Prefixes: Applied to artifact names
ArtifactConfig.Prefixes = {
	-- Speed affixes
	Glitchy = { Name = "Glitchy", Stat = "CycleTime", Mult = 0.95, Icon = "⚡" },
	Swift = { Name = "Swift", Stat = "CycleTime", Mult = 0.90, Icon = "💨" },
	Blazing = { Name = "Blazing", Stat = "CycleTime", Mult = 0.85, Icon = "🔥" },
	Hypercharged = { Name = "Hypercharged", Stat = "CycleTime", Mult = 0.80, Icon = "⚡" },
	
	-- Luck affixes
	Lucky = { Name = "Lucky", Stat = "LuckBonus", Add = 0.02, Icon = "🍀" },
	Fortunate = { Name = "Fortunate", Stat = "LuckBonus", Add = 0.05, Icon = "✨" },
	Blessed = { Name = "Blessed", Stat = "LuckBonus", Add = 0.08, Icon = "🌟" },
	
	-- Tier affixes
	Enhanced = { Name = "Enhanced", Stat = "ItemTierBonus", Add = 1, Icon = "📈" },
	Superior = { Name = "Superior", Stat = "ItemTierBonus", Add = 2, Icon = "💎" },
}

-- Suffixes: Applied to artifact names
ArtifactConfig.Suffixes = {
	-- Speed suffixes
	ofSpeed = { Name = "of Speed", Stat = "CycleTime", Mult = 0.95, Icon = "🏃" },
	ofHaste = { Name = "of Haste", Stat = "CycleTime", Mult = 0.90, Icon = "⏩" },
	ofVelocity = { Name = "of Velocity", Stat = "CycleTime", Mult = 0.85, Icon = "🚀" },
	
	-- Luck suffixes
	ofFortune = { Name = "of Fortune", Stat = "LuckBonus", Add = 0.03, Icon = "🎰" },
	ofProsperity = { Name = "of Prosperity", Stat = "LuckBonus", Add = 0.06, Icon = "💰" },
	
	-- Synergy suffixes
	ofResonance = { Name = "of Resonance", Stat = "SynergyRangeBonus", Add = 1, Icon = "🔗" },
	ofHarmony = { Name = "of Harmony", Stat = "SynergyRangeBonus", Add = 2, Icon = "🎵" },
	
	-- Tier suffixes
	ofQuality = { Name = "of Quality", Stat = "ItemTierBonus", Add = 1, Icon = "⬆️" },
	ofMastery = { Name = "of Mastery", Stat = "ItemTierBonus", Add = 2, Icon = "👑" },
}

--------------------------------------------------------------------------------
-- BASE ARTIFACTS (Visuals per slot type)
--------------------------------------------------------------------------------

ArtifactConfig.BaseArtifacts = {
	Head = {
		{ Id = "Crown", Name = "Crown", Icon = "👑" },
		{ Id = "Helmet", Name = "Helmet", Icon = "🪖" },
		{ Id = "Headband", Name = "Headband", Icon = "🎀" },
		{ Id = "Goggles", Name = "Goggles", Icon = "🥽" },
		{ Id = "TopHat", Name = "Top Hat", Icon = "🎩" },
	},
	Body = {
		{ Id = "Armor", Name = "Armor", Icon = "🛡️" },
		{ Id = "Cloak", Name = "Cloak", Icon = "🧥" },
		{ Id = "Vest", Name = "Vest", Icon = "🦺" },
		{ Id = "Robe", Name = "Robe", Icon = "🥋" },
		{ Id = "Cape", Name = "Cape", Icon = "🦸" },
	},
	Accessory = {
		{ Id = "Amulet", Name = "Amulet", Icon = "📿" },
		{ Id = "Ring", Name = "Ring", Icon = "💍" },
		{ Id = "Charm", Name = "Charm", Icon = "🔮" },
		{ Id = "Pendant", Name = "Pendant", Icon = "💎" },
		{ Id = "Bracelet", Name = "Bracelet", Icon = "⌚" },
	},
}

--------------------------------------------------------------------------------
-- DROP CHANCES
--------------------------------------------------------------------------------

ArtifactConfig.BaseDropChance = 0.01  -- 1% base chance per production cycle
ArtifactConfig.MaxDropChance = 0.25   -- 25% max after all bonuses

--------------------------------------------------------------------------------
-- STAT LIMITS (for balance)
--------------------------------------------------------------------------------

ArtifactConfig.StatLimits = {
	CycleTimeMin = 0.1,       -- Minimum cycle time in seconds (prevents instant production)
	MaxLuckBonus = 0.5,       -- Maximum luck bonus from artifacts (50%)
	MaxSynergyRange = 3,      -- Maximum extra synergy range
	MaxTierBonus = 5,         -- Maximum tier bonus
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Rolls a rarity based on weights.
	@return string - The rarity name
]]
function ArtifactConfig.RollRarity()
	local total = 0
	for _, weight in pairs(ArtifactConfig.RarityWeights) do
		total = total + weight
	end
	
	local roll = math.random() * total
	local cumulative = 0
	
	-- Roll in order from most to least common
	local rarityOrder = {"Legendary", "Epic", "Rare", "Uncommon", "Common"}
	for _, rarity in ipairs(rarityOrder) do
		cumulative = cumulative + ArtifactConfig.RarityWeights[rarity]
		if roll <= cumulative then
			return rarity
		end
	end
	
	return "Common"
end

--[[
	Gets a random prefix for artifact generation.
	@return table - The prefix data
]]
function ArtifactConfig.GetRandomPrefix()
	local prefixes = {}
	for key, data in pairs(ArtifactConfig.Prefixes) do
		table.insert(prefixes, {key = key, data = data})
	end
	return prefixes[math.random(#prefixes)]
end

--[[
	Gets a random suffix for artifact generation.
	@return table - The suffix data
]]
function ArtifactConfig.GetRandomSuffix()
	local suffixes = {}
	for key, data in pairs(ArtifactConfig.Suffixes) do
		table.insert(suffixes, {key = key, data = data})
	end
	return suffixes[math.random(#suffixes)]
end

--[[
	Gets a random base artifact for a slot.
	@param slot string - The equipment slot
	@return table - The base artifact data
]]
function ArtifactConfig.GetRandomBase(slot)
	local bases = ArtifactConfig.BaseArtifacts[slot]
	if not bases then return nil end
	return bases[math.random(#bases)]
end

--[[
	Calculates combined stats from an artifact.
	@param artifact table - The artifact data
	@return table - Combined stats {CycleTime, LuckBonus, etc.}
]]
function ArtifactConfig.CalculateArtifactStats(artifact)
	local stats = {
		CycleTimeMult = 1,
		LuckBonus = 0,
		ItemTierBonus = 0,
		SynergyRangeBonus = 0,
	}
	
	if not artifact or not artifact.Affixes then
		return stats
	end
	
	for _, affix in ipairs(artifact.Affixes) do
		if affix.Stat == "CycleTime" then
			stats.CycleTimeMult = stats.CycleTimeMult * (affix.Mult or 1)
		elseif affix.Stat == "LuckBonus" then
			stats.LuckBonus = stats.LuckBonus + (affix.Add or 0)
		elseif affix.Stat == "ItemTierBonus" then
			stats.ItemTierBonus = stats.ItemTierBonus + (affix.Add or 0)
		elseif affix.Stat == "SynergyRangeBonus" then
			stats.SynergyRangeBonus = stats.SynergyRangeBonus + (affix.Add or 0)
		end
	end
	
	return stats
end

return ArtifactConfig
