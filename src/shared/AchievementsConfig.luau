--!strict

local AchievementsConfig = {}

export type GoalType =
	"units_purchased"
	| "first_brainrot_placed"
	| "first_market_sale"
	| "grid_slots_unlocked"
	| "islands_purchased"
	| "items_produced_total"
	| "storage_tier_level"
	| "storage_full_exact"
	| "first_cart_sale"
	| "cart_fully_loaded"
	| "cart_distance_traveled"
	| "cart_tier_unlocked"
	| "load_max_used"
	| "cash_balance_reached"
	| "cart_sold_hyper_inflation"
	| "sold_during_crash"
	| "local_market_crash_20"
	| "profitable_arbitrage"
	| "diversified_storage_sectors"
	| "synergy_activated"
	| "synergy_unique_active"
	| "artifact_drop"
	| "unit_fully_equipped"
	| "legendary_artifact_drop"
	| "artifact_listed"
	| "mewing_locked_in"
	| "mewing_gigachad"
	| "mega_project_contributor"
	| "flash_order_finisher"
	| "braincells_spent_total"
	| "premium_crates_opened"
	| "market_manipulator_used"

export type Reward = {
	Type: "money" | "braincells" | "title" | "artifact" | "permanent_buff",
	Amount: number?,
	Value: string?,
	AdvancedPending: boolean?,
}

export type AchievementDefinition = {
	Id: string,
	Title: string,
	Description: string,
	Category: string,
	Order: number,
	GoalType: GoalType,
	TargetValue: number,
	Rewards: {Reward},
	AutoClaim: boolean?,
	OnboardingOrder: number?,
}

AchievementsConfig.List = {
	{
		Id = "onboarding_buy_first_unit",
		Title = "Buy Your First Unit",
		Description = "Pick up your first Brainrot.",
		Category = "Onboarding",
		Order = 1,
		OnboardingOrder = 1,
		GoalType = "units_purchased",
		TargetValue = 1,
		AutoClaim = true,
		Rewards = {
			{
				Type = "money",
				Amount = 100,
			},
		},
	},
	{
		Id = "onboarding_place_first_unit",
		Title = "Place Your First Unit",
		Description = "Drop your first Brainrot onto the grid.",
		Category = "Onboarding",
		Order = 2,
		OnboardingOrder = 2,
		GoalType = "first_brainrot_placed",
		TargetValue = 1,
		AutoClaim = true,
		Rewards = {
			{
				Type = "money",
				Amount = 150,
			},
		},
	},
	{
		Id = "onboarding_first_batch",
		Title = "Produce Your First Batch",
		Description = "Let your setup produce 20 items.",
		Category = "Onboarding",
		Order = 3,
		OnboardingOrder = 3,
		GoalType = "items_produced_total",
		TargetValue = 20,
		AutoClaim = true,
		Rewards = {
			{
				Type = "money",
				Amount = 200,
			},
		},
	},
	{
		Id = "onboarding_first_sale",
		Title = "Cash Out Once",
		Description = "Sell your stored stock once.",
		Category = "Onboarding",
		Order = 4,
		OnboardingOrder = 4,
		GoalType = "first_market_sale",
		TargetValue = 1,
		AutoClaim = true,
		Rewards = {
			{
				Type = "money",
				Amount = 250,
			},
		},
	},
	{
		Id = "onboarding_reinvest",
		Title = "Reinvest Profits",
		Description = "Buy a second unit to grow your setup.",
		Category = "Onboarding",
		Order = 5,
		OnboardingOrder = 5,
		GoalType = "units_purchased",
		TargetValue = 2,
		AutoClaim = true,
		Rewards = {
			{
				Type = "money",
				Amount = 300,
			},
		},
	},
	{
		Id = "midgame_targeted_seller",
		Title = "Target 3 Terminal Sales",
		Description = "Use the market terminal to make 3 targeted cart sales.",
		Category = "Midgame",
		Order = 6,
		GoalType = "first_cart_sale",
		TargetValue = 3,
		AutoClaim = true,
		Rewards = {
			{
				Type = "money",
				Amount = 1500,
			},
		},
	},
	{
		Id = "midgame_expand_line",
		Title = "Run 4 Producers",
		Description = "Own 4 total producers to widen your cash-out windows.",
		Category = "Midgame",
		Order = 7,
		GoalType = "units_purchased",
		TargetValue = 4,
		AutoClaim = true,
		Rewards = {
			{
				Type = "money",
				Amount = 2000,
			},
		},
	},
	{
		Id = "midgame_full_cart",
		Title = "Ship a Full Cart",
		Description = "Fill the cart completely before pushing it to market.",
		Category = "Midgame",
		Order = 8,
		GoalType = "cart_fully_loaded",
		TargetValue = 1,
		AutoClaim = true,
		Rewards = {
			{
				Type = "money",
				Amount = 2500,
			},
		},
	},
	{
		Id = "midgame_first_synergy",
		Title = "Trigger Your First Synergy",
		Description = "Pair the right weird units and create your first synergy output.",
		Category = "Midgame",
		Order = 9,
		GoalType = "synergy_activated",
		TargetValue = 1,
		AutoClaim = true,
		Rewards = {
			{
				Type = "money",
				Amount = 3500,
			},
		},
	},
	{
		Id = "midgame_cart_tier_two",
		Title = "Upgrade Cart to Tier 2",
		Description = "Boost throughput so your next cash-outs land harder.",
		Category = "Midgame",
		Order = 10,
		GoalType = "cart_tier_unlocked",
		TargetValue = 2,
		AutoClaim = true,
		Rewards = {
			{
				Type = "money",
				Amount = 5000,
			},
		},
	},
	{
		Id = "midgame_first_contract",
		Title = "Finish a Flash Order",
		Description = "Close out your first contract finisher for a premium payout.",
		Category = "Midgame",
		Order = 11,
		GoalType = "flash_order_finisher",
		TargetValue = 1,
		AutoClaim = true,
		Rewards = {
			{
				Type = "money",
				Amount = 7500,
			},
		},
	},
	{
		Id = "first_steps",
		Title = "First Steps",
		Description = "Place your first Brainrot on the grid.",
		Category = "Production",
		Order = 1,
		GoalType = "first_brainrot_placed",
		TargetValue = 1,
		Rewards = {
			{
				Type = "money",
				Amount = 500,
			},
		},
	},
	{
		Id = "grid_expansion",
		Title = "Grid Expansion",
		Description = "Unlock all 16 slots on your first grid.",
		Category = "Production",
		Order = 2,
		GoalType = "grid_slots_unlocked",
		TargetValue = 16,
		Rewards = {
			{
				Type = "braincells",
				Amount = 50,
			},
		},
	},
	{
		Id = "island_hopper",
		Title = "Island Hopper",
		Description = "Buy your first extra island.",
		Category = "Production",
		Order = 3,
		GoalType = "islands_purchased",
		TargetValue = 1,
		Rewards = {
			{
				Type = "braincells",
				Amount = 100,
			},
		},
	},
	{
		Id = "mass_production",
		Title = "Mass Production",
		Description = "Produce 10,000 total items.",
		Category = "Production",
		Order = 4,
		GoalType = "items_produced_total",
		TargetValue = 10000,
		Rewards = {
			{
				Type = "money",
				Amount = 50000,
			},
		},
	},
	{
		Id = "industrial_empire",
		Title = "Industrial Empire",
		Description = "Produce 1,000,000 total items.",
		Category = "Production",
		Order = 5,
		GoalType = "items_produced_total",
		TargetValue = 1000000,
		Rewards = {
			{
				Type = "braincells",
				Amount = 250,
			},
			{
				Type = "title",
				Value = "Factory Owner",
				AdvancedPending = true,
			},
		},
	},
	{
		Id = "max_capacity",
		Title = "Max Capacity",
		Description = "Upgrade Plot Storage to Level 5.",
		Category = "Production",
		Order = 6,
		GoalType = "storage_tier_level",
		TargetValue = 5,
		Rewards = {
			{
				Type = "artifact",
				Value = "Uncommon",
				AdvancedPending = true,
			},
		},
	},
	{
		Id = "hoarder",
		Title = "Hoarder",
		Description = "Fill Storage to exactly 100% capacity.",
		Category = "Production",
		Order = 7,
		GoalType = "storage_full_exact",
		TargetValue = 1,
		Rewards = {
			{
				Type = "braincells",
				Amount = 75,
			},
		},
	},
	{
		Id = "first_delivery",
		Title = "First Delivery",
		Description = "Sell items from your cart for the first time.",
		Category = "Logistics",
		Order = 8,
		GoalType = "first_cart_sale",
		TargetValue = 1,
		Rewards = {
			{
				Type = "money",
				Amount = 1000,
			},
		},
	},
	{
		Id = "heavy_load",
		Title = "Heavy Load",
		Description = "Fill your cart to 100% before pushing it.",
		Category = "Logistics",
		Order = 9,
		GoalType = "cart_fully_loaded",
		TargetValue = 1,
		Rewards = {
			{
				Type = "braincells",
				Amount = 50,
			},
		},
	},
	{
		Id = "marathon_runner",
		Title = "Marathon Runner",
		Description = "Travel 50,000 studs with your cart.",
		Category = "Logistics",
		Order = 10,
		GoalType = "cart_distance_traveled",
		TargetValue = 50000,
		Rewards = {
			{
				Type = "permanent_buff",
				Value = "Walkspeed5Pct",
				AdvancedPending = true,
			},
		},
	},
	{
		Id = "cart_pimp",
		Title = "Cart Pimp",
		Description = "Upgrade your cart to Tier 2.",
		Category = "Logistics",
		Order = 11,
		GoalType = "cart_tier_unlocked",
		TargetValue = 2,
		Rewards = {
			{
				Type = "artifact",
				Value = "Rare",
				AdvancedPending = true,
			},
		},
	},
	{
		Id = "cosmic_transporter",
		Title = "Cosmic Transporter",
		Description = "Unlock cart Tier 5.",
		Category = "Logistics",
		Order = 12,
		GoalType = "cart_tier_unlocked",
		TargetValue = 5,
		Rewards = {
			{
				Type = "artifact",
				Value = "Legendary",
				AdvancedPending = true,
			},
		},
	},
	{
		Id = "logistics_expert",
		Title = "Logistics Expert",
		Description = "Use Load Max To Cart 50 times.",
		Category = "Logistics",
		Order = 13,
		GoalType = "load_max_used",
		TargetValue = 50,
		Rewards = {
			{
				Type = "braincells",
				Amount = 100,
			},
		},
	},
	{
		Id = "first_million",
		Title = "First Million",
		Description = "Reach $1,000,000 cash.",
		Category = "Economy",
		Order = 14,
		GoalType = "cash_balance_reached",
		TargetValue = 1000000,
		Rewards = {
			{
				Type = "braincells",
				Amount = 150,
			},
		},
	},
	{
		Id = "billionaire_club",
		Title = "Billionaire Club",
		Description = "Reach $1,000,000,000 cash.",
		Category = "Economy",
		Order = 15,
		GoalType = "cash_balance_reached",
		TargetValue = 1000000000,
		Rewards = {
			{
				Type = "braincells",
				Amount = 500,
			},
			{
				Type = "title",
				Value = "Billionaire",
				AdvancedPending = true,
			},
		},
	},
	{
		Id = "stonks",
		Title = "STONKS!",
		Description = "Sell a full cart during Hyper Inflation (>2.5x).",
		Category = "Economy",
		Order = 16,
		GoalType = "cart_sold_hyper_inflation",
		TargetValue = 1,
		Rewards = {
			{
				Type = "braincells",
				Amount = 200,
			},
		},
	},
	{
		Id = "diamond_hands",
		Title = "Diamond Hands",
		Description = "Sell an item during market crash (<0.5x).",
		Category = "Economy",
		Order = 17,
		GoalType = "sold_during_crash",
		TargetValue = 1,
		Rewards = {
			{
				Type = "braincells",
				Amount = 50,
			},
		},
	},
	{
		Id = "market_manipulator",
		Title = "Market Manipulator",
		Description = "Crash a local item market by 20% with one trade.",
		Category = "Economy",
		Order = 18,
		GoalType = "local_market_crash_20",
		TargetValue = 1,
		Rewards = {
			{
				Type = "title",
				Value = "The Whale",
				AdvancedPending = true,
			},
			{
				Type = "artifact",
				Value = "Epic",
				AdvancedPending = true,
			},
		},
	},
	{
		Id = "arbitrage_god",
		Title = "Arbitrage God",
		Description = "Complete a profitable arbitrage buy.",
		Category = "Economy",
		Order = 19,
		GoalType = "profitable_arbitrage",
		TargetValue = 1,
		Rewards = {
			{
				Type = "braincells",
				Amount = 150,
			},
		},
	},
	{
		Id = "diversified",
		Title = "Diversified",
		Description = "Hold 500+ items from all sectors in storage.",
		Category = "Economy",
		Order = 20,
		GoalType = "diversified_storage_sectors",
		TargetValue = 1,
		Rewards = {
			{
				Type = "money",
				Amount = 250000,
			},
		},
	},
	{
		Id = "matchmaker",
		Title = "Matchmaker",
		Description = "Activate your first synergy.",
		Category = "Artifacts",
		Order = 21,
		GoalType = "synergy_activated",
		TargetValue = 1,
		Rewards = {
			{
				Type = "braincells",
				Amount = 100,
			},
		},
	},
	{
		Id = "synergy_master",
		Title = "Synergy Master",
		Description = "Have 4 unique active synergies at once.",
		Category = "Artifacts",
		Order = 22,
		GoalType = "synergy_unique_active",
		TargetValue = 4,
		Rewards = {
			{
				Type = "artifact",
				Value = "Epic",
				AdvancedPending = true,
			},
		},
	},
	{
		Id = "loot_goblin",
		Title = "Loot Goblin",
		Description = "Get your first artifact drop.",
		Category = "Artifacts",
		Order = 23,
		GoalType = "artifact_drop",
		TargetValue = 1,
		Rewards = {
			{
				Type = "braincells",
				Amount = 50,
			},
		},
	},
	{
		Id = "fully_equipped",
		Title = "Fully Equipped",
		Description = "Equip one unit with all 3 artifact slots.",
		Category = "Artifacts",
		Order = 24,
		GoalType = "unit_fully_equipped",
		TargetValue = 1,
		Rewards = {
			{
				Type = "money",
				Amount = 100000,
			},
		},
	},
	{
		Id = "rng_sus",
		Title = "RNG Sus",
		Description = "Find a Legendary artifact drop.",
		Category = "Artifacts",
		Order = 25,
		GoalType = "legendary_artifact_drop",
		TargetValue = 1,
		Rewards = {
			{
				Type = "braincells",
				Amount = 300,
			},
			{
				Type = "title",
				Value = "RNG God",
				AdvancedPending = true,
			},
		},
	},
	{
		Id = "grand_exchange",
		Title = "Grand Exchange",
		Description = "List your first artifact on the market.",
		Category = "Artifacts",
		Order = 26,
		GoalType = "artifact_listed",
		TargetValue = 1,
		Rewards = {
			{
				Type = "braincells",
				Amount = 50,
			},
		},
	},
	{
		Id = "mewing_apprentice",
		Title = "Mewing Apprentice",
		Description = "Reach Locked In mewing tier (5 min).",
		Category = "Social",
		Order = 27,
		GoalType = "mewing_locked_in",
		TargetValue = 1,
		Rewards = {
			{
				Type = "money",
				Amount = 5000,
			},
		},
	},
	{
		Id = "gigachad",
		Title = "GigaChad",
		Description = "Reach GigaChad mewing tier (10 min).",
		Category = "Social",
		Order = 28,
		GoalType = "mewing_gigachad",
		TargetValue = 1,
		Rewards = {
			{
				Type = "permanent_buff",
				Value = "GlobalIncome2Pct",
				AdvancedPending = true,
			},
		},
	},
	{
		Id = "team_player",
		Title = "Team Player",
		Description = "Meet contribution threshold in a Mega Project.",
		Category = "Social",
		Order = 29,
		GoalType = "mega_project_contributor",
		TargetValue = 1,
		Rewards = {
			{
				Type = "artifact",
				Value = "Rare",
				AdvancedPending = true,
			},
		},
	},
	{
		Id = "bounty_hunter",
		Title = "Bounty Hunter",
		Description = "Be the finisher on a Flash Order contract.",
		Category = "Social",
		Order = 30,
		GoalType = "flash_order_finisher",
		TargetValue = 1,
		Rewards = {
			{
				Type = "braincells",
				Amount = 250,
			},
		},
	},
	{
		Id = "braincell_burner",
		Title = "Braincell Burner",
		Description = "Spend 1,000 Braincells in the Premium Shop.",
		Category = "Premium",
		Order = 31,
		GoalType = "braincells_spent_total",
		TargetValue = 1000,
		Rewards = {
			{
				Type = "money",
				Amount = 250000,
			},
		},
	},
	{
		Id = "crate_enjoyer",
		Title = "Crate Enjoyer",
		Description = "Open 10 Premium Artifact Crates.",
		Category = "Premium",
		Order = 32,
		GoalType = "premium_crates_opened",
		TargetValue = 10,
		Rewards = {
			{
				Type = "braincells",
				Amount = 100,
			},
		},
	},
	{
		Id = "pump_it",
		Title = "Pump It",
		Description = "Use Market Manipulator once.",
		Category = "Premium",
		Order = 33,
		GoalType = "market_manipulator_used",
		TargetValue = 1,
		Rewards = {
			{
				Type = "title",
				Value = "Market Whale",
				AdvancedPending = true,
			},
		},
	},
} :: {AchievementDefinition}

function AchievementsConfig.GetDefinitions(): {AchievementDefinition}
	return AchievementsConfig.List
end

return AchievementsConfig
