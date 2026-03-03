--[[
	PremiumShopConfig

	Shared config for:
	1) Robux Developer Product packs that grant Braincells
	2) Braincell shop items spendable in-game
]]

export type BraincellPack = {
	ProductId: number,
	Name: string,
	RobuxLabel: string,
	Braincells: number,
	Icon: string,
}

export type PremiumShopItem = {
	Id: string,
	Name: string,
	Description: string,
	Price: number,
	Icon: string,
	Type: string,
	Metadata: {[string]: any}?,
}

local PremiumShopConfig = {}

-- Placeholder developer product IDs. Replace with your real IDs before release.
PremiumShopConfig.BraincellPacks = {
	[100000001] = {
		ProductId = 100000001,
		Name = "Starter Braincells",
		RobuxLabel = "50 Robux",
		Braincells = 500,
		Icon = "🧠",
	},
	[100000002] = {
		ProductId = 100000002,
		Name = "Value Braincells",
		RobuxLabel = "150 Robux",
		Braincells = 1750,
		Icon = "🧠",
	},
	[100000003] = {
		ProductId = 100000003,
		Name = "Mega Braincells",
		RobuxLabel = "400 Robux",
		Braincells = 5000,
		Icon = "🧠",
	},
}

PremiumShopConfig.ShopItems = {
	premium_crate = {
		Id = "premium_crate",
		Name = "Premium Artifact Crate",
		Description = "Guaranteed at least 1 Rare Artifact. 5% chance for Legendary.",
		Price = 300,
		Icon = "📦",
		Type = "ArtifactCrate",
		Metadata = {
			MinRarity = "Rare",
			LegendaryChance = 0.05,
		},
	},
	instant_storage_fill = {
		Id = "instant_storage_fill",
		Name = "Instant Storage Fill",
		Description = "Instantly fills your plot storage based on your current units.",
		Price = 150,
		Icon = "⚡",
		Type = "Convenience",
		Metadata = {
			FillPercent = 1.0,
		},
	},
	market_manipulator = {
		Id = "market_manipulator",
		Name = "Market Manipulator",
		Description = "Force a server-wide bull run announcement for one sector for 10 minutes.",
		Price = 500,
		Icon = "📈",
		Type = "ServerBoost",
		Metadata = {
			DurationSeconds = 600,
			DefaultSector = "Tech",
			MinMultiplier = 1.5,
			MaxMultiplier = 2.5,
		},
	},
}

function PremiumShopConfig.GetPackByProductId(productId: number): BraincellPack?
	return PremiumShopConfig.BraincellPacks[productId]
end

function PremiumShopConfig.GetShopItem(itemId: string): PremiumShopItem?
	return PremiumShopConfig.ShopItems[itemId]
end

function PremiumShopConfig.GetAllPacksSorted(): {BraincellPack}
	local packs = {}
	for _, pack in pairs(PremiumShopConfig.BraincellPacks) do
		table.insert(packs, pack)
	end
	table.sort(packs, function(a, b)
		return a.Braincells < b.Braincells
	end)
	return packs
end

function PremiumShopConfig.GetAllShopItemsSorted(): {PremiumShopItem}
	local items = {}
	for _, item in pairs(PremiumShopConfig.ShopItems) do
		table.insert(items, item)
	end
	table.sort(items, function(a, b)
		return a.Price < b.Price
	end)
	return items
end

return PremiumShopConfig
