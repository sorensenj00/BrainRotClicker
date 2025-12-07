local PrestigeConfig = {}

-- Meatball calculation constants
PrestigeConfig.MEATBALL_DIVISOR = 1_000_000       -- Lifetime earnings divisor
PrestigeConfig.MEATBALL_MULTIPLIER = 150          -- Square root multiplier
PrestigeConfig.MEATBALL_BONUS_RATE = 0.02         -- +2% income per meatball
PrestigeConfig.MINIMUM_PRESTIGE_GAIN = 10         -- Must gain at least 10 meatballs

-- Meatball Shop items with progressive unlock
PrestigeConfig.SHOP_ITEMS = {
    -- Tier 1: Unlocked at 0 lifetime meatballs
    { 
        Id = "GoldenBoost1",
        Name = "Golden Boost I", 
        Price = 50, 
        Effect = "IncomeMultiplier", 
        Value = 0.10, 
        UnlockAt = 0,
        Description = "Increases all income by 10%"
    },
    { 
        Id = "QuickStart1",
        Name = "Quick Start I", 
        Price = 100, 
        Effect = "StartingMoney", 
        Value = 500, 
        UnlockAt = 0,
        Description = "Start with +$500 after prestige"
    },
    
    -- Tier 2: Unlocked at 500 lifetime meatballs
    { 
        Id = "GoldenBoost2",
        Name = "Golden Boost II", 
        Price = 200, 
        Effect = "IncomeMultiplier", 
        Value = 0.25, 
        UnlockAt = 500,
        Description = "Increases all income by another 25%"
    },
    { 
        Id = "UnitBooster1",
        Name = "Unit Booster: Tier 1", 
        Price = 300, 
        Effect = "UnitBoost", 
        Value = { Tier = 1, Multiplier = 5 }, 
        UnlockAt = 500,
        Description = "Tier 1 units earn 5x income"
    },
    
    -- Tier 3: Unlocked at 2000 lifetime meatballs
    { 
        Id = "GoldenBoost3",
        Name = "Golden Boost III", 
        Price = 500, 
        Effect = "IncomeMultiplier", 
        Value = 0.50, 
        UnlockAt = 2000,
        Description = "Increases all income by another 50%"
    },
    { 
        Id = "QuickStart2",
        Name = "Quick Start II", 
        Price = 400, 
        Effect = "StartingMoney", 
        Value = 2500, 
        UnlockAt = 2000,
        Description = "Start with +$2500 after prestige"
    },
}

-- Helper to get item by ID
function PrestigeConfig.GetItem(itemId)
    for _, item in ipairs(PrestigeConfig.SHOP_ITEMS) do
        if item.Id == itemId then
            return item
        end
    end
    return nil
end

return PrestigeConfig
