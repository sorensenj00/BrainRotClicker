--[[
	CartShopConfig ModuleScript
	
	Configuration for Cart upgrades using a tier and level system.
]]

local CartShopConfig = {}

CartShopConfig.MaxCapacityLevel = 5

CartShopConfig.Carts = {
	{ Name = "Wooden Cart", Price = 0, Model = "CartTier1", BaseCap = 100, BaseCost = 500 },
	{ Name = "Iron Cart", Price = 50000, Model = "CartTier2", BaseCap = 1000, BaseCost = 15000 },
	{ Name = "Golden Cart", Price = 5000000, Model = "CartTier3", BaseCap = 10000, BaseCost = 1000000 },
	{ Name = "Diamond Cart", Price = 500000000, Model = "CartTier4", BaseCap = 1000000, BaseCost = 100000000 },
	{ Name = "Cosmic Cart", Price = 50000000000, Model = "CartTier5", BaseCap = 100000000, BaseCost = 10000000000 },
}

function CartShopConfig.GetUpgradeInfo(upgradeType: string, currentLevel: number, currentModelTier: number)
	currentModelTier = currentModelTier or 1
	currentLevel = currentLevel or 1
	local currentCart = CartShopConfig.Carts[currentModelTier]
	if not currentCart then return nil end

	if upgradeType == "Model" then
		local nextTier = currentModelTier + 1
		local nextCart = CartShopConfig.Carts[nextTier]
		
		return {
			CurrentValue = currentModelTier,
			NextValue = nextTier,
			Price = nextCart and nextCart.Price or nil,
			IsMaxed = nextCart == nil,
			Name = nextCart and nextCart.Name or "Maxed out"
		}
	elseif upgradeType == "Capacity" then
		local nextLevel = currentLevel + 1
		local isMaxed = currentLevel >= CartShopConfig.MaxCapacityLevel
		
		return {
			CurrentValue = currentCart.BaseCap * currentLevel,
			NextValue = if isMaxed then nil else (currentCart.BaseCap * nextLevel),
			Price = if isMaxed then nil else math.floor(currentCart.BaseCost * (2.5 ^ (currentLevel - 1))),
			IsMaxed = isMaxed
		}
	end
	return nil
end

function CartShopConfig.GetValue(upgradeType: string, level: number, modelTier: number)
	modelTier = modelTier or 1
	level = level or 1
	local cart = CartShopConfig.Carts[modelTier]
	if not cart then return 0 end
	
	if upgradeType == "Capacity" then
		level = math.clamp(level, 1, CartShopConfig.MaxCapacityLevel)
		return cart.BaseCap * level
	end
	return 0
end

return CartShopConfig
