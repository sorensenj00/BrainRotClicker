--[[
	ConvenienceUpgradesConfig ModuleScript
	
	Defines all purchasable convenience upgrades for the Island Shop.
	Located in ReplicatedStorage so both Server and Client can access it.
	
	Categories:
	- Mobility: Walkspeed, jump, bridge speed boosts
	- Economy: Global income and payout chance upgrades
	- Automation: Collector bots and cycle speed upgrades
	- Utility: Late-game quality of life upgrades
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
-- Pricing is aligned with the current game economy curve:
-- early utility unlocks, midgame multipliers, and high-end sinks.
local Upgrades: {[string]: UpgradeConfig} = {
	-- TIER 1: Mobility Foundation ($20k - $800k)
	["Bridge Thrusters I"] = {
		Price = 20000,
		Description = "Bridge lanes grant 1.5x movement speed.",
		Category = "Mobility",
		EffectType = "BridgeSpeed",
		EffectValue = 1.5,
		Icon = "🏃",
	},

	["Runner Shoes I"] = {
		Price = 50000,
		Description = "Permanent +15% walkspeed everywhere.",
		Category = "Mobility",
		EffectType = "Walkspeed",
		EffectValue = 0.15,
		Icon = "👟",
	},

	["Jump Spring Mod"] = {
		Price = 120000,
		Description = "Permanent +30% jump height.",
		Category = "Mobility",
		EffectType = "JumpPower",
		EffectValue = 0.30,
		Icon = "🦘",
	},

	["Runner Shoes II"] = {
		Price = 300000,
		Description = "Additional +15% walkspeed. Stacks with Runner Shoes I.",
		Category = "Mobility",
		EffectType = "Walkspeed",
		EffectValue = 0.15,
		Icon = "⚡",
		Prerequisite = "Runner Shoes I",
	},

	["Bridge Thrusters II"] = {
		Price = 800000,
		Description = "Bridge lanes now grant 2x movement speed.",
		Category = "Mobility",
		EffectType = "BridgeSpeed",
		EffectValue = 2.0,
		Icon = "✨",
		Prerequisite = "Bridge Thrusters I",
	},

	-- TIER 2: Economy + Automation Core ($2M - $60M)
	["Profit Routing I"] = {
		Price = 2000000,
		Description = "All units generate +8% income.",
		Category = "Economy",
		EffectType = "IncomeMultiplier",
		EffectValue = 0.08,
		Icon = "💵",
	},

	["Cycle Overclock I"] = {
		Price = 6000000,
		Description = "All unit cycles run 8% faster.",
		Category = "Automation",
		EffectType = "CycleReduction",
		EffectValue = 0.08,
		Icon = "⏱️",
	},

	["Collector Drone I"] = {
		Price = 15000000,
		Description = "Deploys one auto-collector bot.",
		Category = "Automation",
		EffectType = "AutoCollector",
		EffectValue = 1,
		Icon = "🤖",
	},

	["Profit Routing II"] = {
		Price = 30000000,
		Description = "All units generate an additional +12% income.",
		Category = "Economy",
		EffectType = "IncomeMultiplier",
		EffectValue = 0.12,
		Icon = "💰",
		Prerequisite = "Profit Routing I",
	},

	["Cycle Overclock II"] = {
		Price = 60000000,
		Description = "All unit cycles run an additional 10% faster.",
		Category = "Automation",
		EffectType = "CycleReduction",
		EffectValue = 0.10,
		Icon = "⚙️",
		Prerequisite = "Cycle Overclock I",
	},

	-- TIER 3: Late Midgame ($150M - $2.5B)
	["Collector Drone II"] = {
		Price = 150000000,
		Description = "Deploys a second auto-collector bot.",
		Category = "Automation",
		EffectType = "AutoCollector",
		EffectValue = 1,
		Icon = "🛰️",
		Prerequisite = "Collector Drone I",
	},

	["Lucky Payout Matrix"] = {
		Price = 350000000,
		Description = "Adds +8% lucky payout chance.",
		Category = "Economy",
		EffectType = "LuckyChance",
		EffectValue = 0.08,
		Icon = "🍀",
	},

	["Profit Routing III"] = {
		Price = 800000000,
		Description = "All units generate an additional +18% income.",
		Category = "Economy",
		EffectType = "IncomeMultiplier",
		EffectValue = 0.18,
		Icon = "💎",
		Prerequisite = "Profit Routing II",
	},

	["Cycle Overclock III"] = {
		Price = 1600000000,
		Description = "All unit cycles run an additional 12% faster.",
		Category = "Automation",
		EffectType = "CycleReduction",
		EffectValue = 0.12,
		Icon = "🚀",
		Prerequisite = "Cycle Overclock II",
	},

	["Home Warp Beacon"] = {
		Price = 2500000000,
		Description = "Unlocks instant teleport back to your main island.",
		Category = "Utility",
		EffectType = "TeleportHome",
		EffectValue = 1,
		Icon = "🏠",
	},

	-- TIER 4: Endgame Sinks ($6B - $70B)
	["Collector Drone III"] = {
		Price = 6000000000,
		Description = "Deploys a third auto-collector bot.",
		Category = "Automation",
		EffectType = "AutoCollector",
		EffectValue = 1,
		Icon = "🤖",
		Prerequisite = "Collector Drone II",
	},

	["Critical Payout Matrix"] = {
		Price = 16000000000,
		Description = "Adds +4% critical payout chance.",
		Category = "Economy",
		EffectType = "CriticalChance",
		EffectValue = 0.04,
		Icon = "🎰",
		Prerequisite = "Lucky Payout Matrix",
	},

	["Bridge Thrusters III"] = {
		Price = 32000000000,
		Description = "Bridge lanes now grant 2.8x movement speed.",
		Category = "Mobility",
		EffectType = "BridgeSpeed",
		EffectValue = 2.8,
		Icon = "🌉",
		Prerequisite = "Bridge Thrusters II",
	},

	["Profit Routing IV"] = {
		Price = 70000000000,
		Description = "All units generate an additional +25% income.",
		Category = "Economy",
		EffectType = "IncomeMultiplier",
		EffectValue = 0.25,
		Icon = "🏦",
		Prerequisite = "Profit Routing III",
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
	local order = {Mobility = 1, Economy = 2, Automation = 3, Utility = 4}
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
