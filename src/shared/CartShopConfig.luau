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
}

CartShopConfig.Carts = {
		{ Name = "Wooden Cart", Price = 0, Model = "CartTier1" },
		{ Name = "Iron Cart", Price = 5000, Model = "CartTier2" },
		{ Name = "Golden Cart", Price = 25000, Model = "CartTier3" },
		{ Name = "Diamond Cart", Price = 100000, Model = "CartTier4" },
		{ Name = "Netherite Cart", Price = 500000, Model = "CartTier5" },
	}


function CartShopConfig.GetUpgradeInfo(upgradeType: string, currentTier: number)
	if upgradeType == "Model" then
		local carts = CartShopConfig.Carts
		local nextTier = currentTier + 1
		local nextCart = carts[nextTier]
		
		return {
			CurrentValue = currentTier, -- Just the tier number for models
			NextValue = nextTier,
			Price = nextCart and nextCart.Price or nil,
			IsMaxed = nextCart == nil,
			Name = nextCart and nextCart.Name or "Maxed"
		}
	end

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
