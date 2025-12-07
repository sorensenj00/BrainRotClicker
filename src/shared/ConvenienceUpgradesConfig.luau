--[[
	ConvenienceUpgradesConfig ModuleScript
	
	Defines all purchasable convenience upgrades for the Island Shop.
	Located in ReplicatedStorage so both Server and Client can access it.
	
	Categories:
	- Movement: Walkspeed, jump, bridge speed boosts
	- Income: Global income multipliers
	- Automation: Auto-collector bots, faster cycles
	- Premium: High-tier quality of life upgrades
]]

export type UpgradeConfig = {
	Price: number,
	Description: string,
	Category: string,
	EffectType: string,
	EffectValue: number,
	Icon: string,
	Prerequisite: string?, -- Must own this upgrade first
}

-- All convenience upgrades
local Upgrades: {[string]: UpgradeConfig} = {
	-- ═══════════════════════════════════════════
	-- TIER 1: Movement & Speed ($1,000 - $10,000)
	-- ═══════════════════════════════════════════
	
	["Speed Treadmill Bridge"] = {
		Price = 1000,
		Description = "Bridges boost your speed 2x! Zoom between islands.",
		Category = "Movement",
		EffectType = "BridgeSpeed",
		EffectValue = 2, -- 2x speed on bridges
		Icon = "🏃",
	},
	
	["Walkspeed Boost I"] = {
		Price = 2500,
		Description = "Permanent +25% walkspeed everywhere.",
		Category = "Movement",
		EffectType = "Walkspeed",
		EffectValue = 0.25, -- +25%
		Icon = "👟",
	},
	
	["Jump Boost"] = {
		Price = 5000,
		Description = "Permanent +50% jump height. Leap tall buildings!",
		Category = "Movement",
		EffectType = "JumpPower",
		EffectValue = 0.50, -- +50%
		Icon = "🦘",
	},
	
	["Walkspeed Boost II"] = {
		Price = 10000,
		Description = "Additional +25% walkspeed. Stacks with Boost I!",
		Category = "Movement",
		EffectType = "Walkspeed",
		EffectValue = 0.25, -- +25% more
		Icon = "⚡",
		Prerequisite = "Walkspeed Boost I",
	},
	
	-- ═══════════════════════════════════════════
	-- TIER 2: Income Boosters ($50,000 - $500,000)
	-- ═══════════════════════════════════════════
	
	["Global Income +10%"] = {
		Price = 50000,
		Description = "All brainrots produce +10% more income!",
		Category = "Income",
		EffectType = "IncomeMultiplier",
		EffectValue = 0.10, -- +10%
		Icon = "💵",
	},
	
	["Auto-Collector Bot I"] = {
		Price = 100000,
		Description = "A cute bot collects from brainrots to storage for you!",
		Category = "Automation",
		EffectType = "AutoCollector",
		EffectValue = 1, -- 1 bot
		Icon = "🤖",
	},
	
	["Global Income +25%"] = {
		Price = 250000,
		Description = "Even more productivity! +25% income (stacks).",
		Category = "Income",
		EffectType = "IncomeMultiplier",
		EffectValue = 0.25, -- +25%
		Icon = "💰",
		Prerequisite = "Global Income +10%",
	},
	
	["Faster Cycles I"] = {
		Price = 500000,
		Description = "All brainrots work 15% faster!",
		Category = "Automation",
		EffectType = "CycleReduction",
		EffectValue = 0.15, -- -15% cycle time
		Icon = "⏱️",
	},
	
	-- ═══════════════════════════════════════════
	-- TIER 3: Automation ($1M - $10M)
	-- ═══════════════════════════════════════════
	
	["Auto-Collector Bot II"] = {
		Price = 1000000,
		Description = "A second bot joins the collection crew!",
		Category = "Automation",
		EffectType = "AutoCollector",
		EffectValue = 1, -- +1 more bot
		Icon = "🤖",
		Prerequisite = "Auto-Collector Bot I",
	},
	
	["Faster Cycles II"] = {
		Price = 2500000,
		Description = "Lightning speed! Additional -15% cycle time.",
		Category = "Automation",
		EffectType = "CycleReduction",
		EffectValue = 0.15, -- -15% more
		Icon = "⚡",
		Prerequisite = "Faster Cycles I",
	},
	
	["Lucky Bonus Chance"] = {
		Price = 5000000,
		Description = "10% chance for 2x payout on each cycle!",
		Category = "Income",
		EffectType = "LuckyChance",
		EffectValue = 0.10, -- 10% chance
		Icon = "🍀",
	},
	
	["Instant Teleport Home"] = {
		Price = 10000000,
		Description = "Press H to teleport to your main island anytime!",
		Category = "Movement",
		EffectType = "TeleportHome",
		EffectValue = 1, -- enabled
		Icon = "🏠",
	},
	
	-- ═══════════════════════════════════════════
	-- TIER 4: Premium Upgrades ($50M+)
	-- ═══════════════════════════════════════════
	
	["Global Income +50%"] = {
		Price = 50000000,
		Description = "Massive profits! +50% income from all brainrots.",
		Category = "Income",
		EffectType = "IncomeMultiplier",
		EffectValue = 0.50, -- +50%
		Icon = "💎",
		Prerequisite = "Global Income +25%",
	},
	
	["Critical Bonus Chance"] = {
		Price = 100000000,
		Description = "5% chance for JACKPOT 5x income payout!",
		Category = "Income",
		EffectType = "CriticalChance",
		EffectValue = 0.05, -- 5% chance
		Icon = "🎰",
		Prerequisite = "Lucky Bonus Chance",
	},
	
	["Golden Speed Bridges"] = {
		Price = 250000000,
		Description = "Bridges boost speed 3x and shine golden!",
		Category = "Movement",
		EffectType = "BridgeSpeed",
		EffectValue = 3, -- 3x speed (replaces 2x)
		Icon = "✨",
		Prerequisite = "Speed Treadmill Bridge",
	},
}

-- Cache for sorted upgrades
local SortedUpgradesCache: {{name: string, config: UpgradeConfig}}? = nil

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Gets the config for a specific upgrade.
	
	@param upgradeName string - The name of the upgrade
	@return UpgradeConfig? - The config, or nil if not found
]]
local function GetConfig(upgradeName: string): UpgradeConfig?
	return Upgrades[upgradeName]
end

--[[
	Returns all upgrades sorted by price (ascending).
	Cached for performance.
	
	@return table - Array of {name, config} pairs sorted by Price
]]
local function GetAllUpgradesSorted(): {{name: string, config: UpgradeConfig}}
	if SortedUpgradesCache then
		return SortedUpgradesCache
	end
	
	local sorted = {}
	
	for name, config in Upgrades do
		table.insert(sorted, {name = name, config = config})
	end
	
	table.sort(sorted, function(a, b)
		return a.config.Price < b.config.Price
	end)
	
	SortedUpgradesCache = sorted
	return sorted
end

--[[
	Gets all upgrades in a specific category.
	
	@param category string - The category name
	@return table - Array of {name, config} pairs in that category
]]
local function GetUpgradesByCategory(category: string): {{name: string, config: UpgradeConfig}}
	local result = {}
	
	for name, config in Upgrades do
		if config.Category == category then
			table.insert(result, {name = name, config = config})
		end
	end
	
	table.sort(result, function(a, b)
		return a.config.Price < b.config.Price
	end)
	
	return result
end

--[[
	Gets all unique categories.
	
	@return {string} - Array of category names
]]
local function GetCategories(): {string}
	local categories = {}
	local seen = {}
	
	for _, config in Upgrades do
		if not seen[config.Category] then
			seen[config.Category] = true
			table.insert(categories, config.Category)
		end
	end
	
	-- Sort in logical order
	local order = {Movement = 1, Income = 2, Automation = 3, Premium = 4}
	table.sort(categories, function(a, b)
		return (order[a] or 99) < (order[b] or 99)
	end)
	
	return categories
end

--[[
	Checks if a player can purchase an upgrade (meets prerequisites).
	
	@param upgradeName string - The upgrade to check
	@param ownedUpgrades {string} - List of upgrades the player owns
	@return boolean, string? - Can purchase, and reason if not
]]
local function CanPurchase(upgradeName: string, ownedUpgrades: {string}): (boolean, string?)
	local config = Upgrades[upgradeName]
	if not config then
		return false, "Upgrade not found"
	end
	
	-- Check if already owned
	for _, owned in ownedUpgrades do
		if owned == upgradeName then
			return false, "Already owned"
		end
	end
	
	-- Check prerequisite
	if config.Prerequisite then
		local hasPrereq = false
		for _, owned in ownedUpgrades do
			if owned == config.Prerequisite then
				hasPrereq = true
				break
			end
		end
		if not hasPrereq then
			return false, "Requires: " .. config.Prerequisite
		end
	end
	
	return true, nil
end

--------------------------------------------------------------------------------
-- MODULE EXPORT
--------------------------------------------------------------------------------

return {
	Upgrades = Upgrades,
	GetConfig = GetConfig,
	GetAllUpgradesSorted = GetAllUpgradesSorted,
	GetUpgradesByCategory = GetUpgradesByCategory,
	GetCategories = GetCategories,
	CanPurchase = CanPurchase,
}
