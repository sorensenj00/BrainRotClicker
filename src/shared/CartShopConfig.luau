--[[
	CartShopConfig ModuleScript
	
	Configuration for Cart upgrades (Capacity and Speed).
]]

export type UpgradeTier = {
	Price: number,
	Value: number, -- The actual capacity or speed value
}

export type UpgradeTypeConfig = {
	Name: string,
	Description: string,
	BaseValue: number,
	Tiers: {UpgradeTier}
}

local CartShopConfig = {}

CartShopConfig.Upgrades = {
	Capacity = {
		Name = "Cart Capacity",
		Description = "Increase the amount of items your cart can carry.",
		BaseValue = 200, -- Tier 0 (Default)
		Tiers = {
			{ Price = 500, Value = 400 },   -- Tier 1
			{ Price = 1500, Value = 800 },  -- Tier 2
			{ Price = 4000, Value = 1500 }, -- Tier 3
			{ Price = 10000, Value = 3000 },-- Tier 4
			{ Price = 25000, Value = 6000 },-- Tier 5
		}
	},
	Speed = {
		Name = "Cart Speed",
		Description = "Increase the speed of your cart.",
		BaseValue = 40, -- Tier 0 (Default)
		Tiers = {
			{ Price = 750, Value = 60 },    -- Tier 1
			{ Price = 2000, Value = 90 },   -- Tier 2
			{ Price = 5000, Value = 130 },  -- Tier 3
			{ Price = 12500, Value = 180 }, -- Tier 4
			{ Price = 30000, Value = 250 }, -- Tier 5
		}
	}
}

function CartShopConfig.GetUpgradeInfo(upgradeType: string, currentTier: number)
	local config = CartShopConfig.Upgrades[upgradeType]
	if not config then return nil end
	
	local nextTier = currentTier + 1
	local nextUpgrade = config.Tiers[nextTier]
	
	return {
		CurrentValue = currentTier == 0 and config.BaseValue or config.Tiers[currentTier].Value,
		NextValue = nextUpgrade and nextUpgrade.Value or nil,
		Price = nextUpgrade and nextUpgrade.Price or nil,
		IsMaxed = nextUpgrade == nil
	}
end

function CartShopConfig.GetValue(upgradeType: string, tier: number)
	local config = CartShopConfig.Upgrades[upgradeType]
	if not config then return 0 end
	if tier <= 0 then return config.BaseValue end
	
	-- Cap at max tier
	tier = math.min(tier, #config.Tiers)
	return config.Tiers[tier].Value
end

return CartShopConfig
