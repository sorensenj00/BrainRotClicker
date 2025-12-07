--[[
	ShopConfig ModuleScript
	
	Central database for all 74 purchasable brainrot units.
	Located in ReplicatedStorage so both Server and Client can access it.
	
	Features:
	- Auto-sorted by BasePrice (ascending)
	- Progressive unlock system (5 unlocked initially, +1 on each purchase)
	- Per-unit cost multipliers (higher tiers have steeper curves)
	- Milestone bonuses at 10/25/50/100/200/300/400/500 owned
	- Price Formula: CurrentPrice = BasePrice * (CostMultiplier ^ AmountOwned)
]]

export type UnitConfig = {
	BasePrice: number,
	BaseIncome: number,
	CycleTime: number,
	ModelName: string,
	Description: string?,
	CostMultiplier: number?, -- Optional: overrides default 1.15 multiplier
	ProjectileColor: Color3?, -- Optional: color of income projectile (defaults to white)
}

export type MilestoneInfo = {
	quantity: number,
	milestoneType: "speed" | "profit",
	multiplier: number,
}

-- Constants
local INITIAL_UNLOCKED = 5 -- How many units are unlocked from the start
local PRICE_MULTIPLIER = 1.15 -- Default 15% increase per owned unit

-- Milestone definitions (Adventure Capitalist-inspired)
-- Speed milestones halve cycle time, profit milestones multiply income
local MILESTONES: {MilestoneInfo} = {
	{quantity = 10, milestoneType = "speed", multiplier = 2},   -- x2 speed (1/2 cycle)
	{quantity = 25, milestoneType = "speed", multiplier = 2},   -- x4 speed total
	{quantity = 50, milestoneType = "speed", multiplier = 2},   -- x8 speed total
	{quantity = 100, milestoneType = "profit", multiplier = 3}, -- x3 profit
	{quantity = 200, milestoneType = "speed", multiplier = 2},  -- x16 speed total
	{quantity = 300, milestoneType = "profit", multiplier = 3}, -- x9 profit total
	{quantity = 400, milestoneType = "speed", multiplier = 2},  -- x32 speed total
	{quantity = 500, milestoneType = "profit", multiplier = 4}, -- x36 profit total
}

--[[
	All 74 brainrot units with balanced progression.
	Sorted by BasePrice ascending.
	Model names match exactly with ReplicatedStorage.Brainrots folder.
]]
local Units: {[string]: UnitConfig} = {
	-- Tier 1: Starter Units ($50 - $400)
	["Avocadini Guffo"] = {
		BasePrice = 50,
		BaseIncome = 5,
		CycleTime = 3,
		ModelName = "Avocadini Guffo",
		Description = "A quirky avocado owl friend.",
		ProjectileColor = Color3.fromRGB(255, 255, 255),
	},
	["Ballerina_Cappuccina"] = {
		BasePrice = 100,
		BaseIncome = 8,
		CycleTime = 3,
		ModelName = "Ballerina_Cappuccina",
		Description = "Dancing coffee ballerina.",
		ProjectileColor = Color3.fromRGB(255, 255, 255),
	},
	["Ballerino Lololo"] = {
		BasePrice = 175,
		BaseIncome = 12,
		CycleTime = 3,
		ModelName = "Ballerino Lololo",
		Description = "The dancing lololo!",
		ProjectileColor = Color3.fromRGB(255, 255, 255),
	},
	["Bambini_Crostini"] = {
		BasePrice = 275,
		BaseIncome = 18,
		CycleTime = 3,
		ModelName = "Bambini_Crostini",
		Description = "Crispy little ones.",
		ProjectileColor = Color3.fromRGB(255, 255, 255),
	},
	["Bananita_Dolphinita"] = {
		BasePrice = 400,
		BaseIncome = 25,
		CycleTime = 4,
		ModelName = "Bananita_Dolphinita",
		Description = "Banana dolphin vibes!",
		ProjectileColor = Color3.fromRGB(255, 255, 255),
	},
	
	-- Tier 2: Early Game ($2.5k - $22.5k)
	["Bandito_Bobritto"] = {
		BasePrice = 2500,
		BaseIncome = 150,
		CycleTime = 4,
		ModelName = "Bandito_Bobritto",
		Description = "The sneaky beaver bandit.",
		ProjectileColor = Color3.fromRGB(255, 255, 150),
	},
	["Blueberrinni_Octopusini"] = {
		BasePrice = 3750,
		BaseIncome = 210,
		CycleTime = 4,
		ModelName = "Blueberrinni_Octopusini",
		Description = "Berry tentacle power!",
		ProjectileColor = Color3.fromRGB(255, 255, 150),
	},
	["Bombardiro_Crocodilo"] = {
		BasePrice = 5500,
		BaseIncome = 280,
		CycleTime = 4,
		ModelName = "Bombardiro_Crocodilo",
		Description = "Explosive croc energy!",
		ProjectileColor = Color3.fromRGB(255, 255, 150),
	},
	["Bombombini_Gusini"] = {
		BasePrice = 7500,
		BaseIncome = 360,
		CycleTime = 4,
		ModelName = "Bombombini_Gusini",
		Description = "Boom boom goose!",
		ProjectileColor = Color3.fromRGB(255, 255, 150),
	},
	["Boneca_Ambalabu"] = {
		BasePrice = 10000,
		BaseIncome = 450,
		CycleTime = 4,
		ModelName = "Boneca_Ambalabu",
		Description = "Mysterious doll vibes.",
		ProjectileColor = Color3.fromRGB(255, 255, 150),
	},
	["Brr_Brr_Patapim"] = {
		BasePrice = 13500,
		BaseIncome = 580,
		CycleTime = 4,
		ModelName = "Brr_Brr_Patapim",
		Description = "Cold cash generator.",
		ProjectileColor = Color3.fromRGB(255, 255, 150),
	},
	["Brri_Brri_Bicus_Dicus_Bombicus"] = {
		BasePrice = 17500,
		BaseIncome = 720,
		CycleTime = 5,
		ModelName = "Brri_Brri_Bicus_Dicus_Bombicus",
		Description = "The ultimate combo name!",
		ProjectileColor = Color3.fromRGB(255, 255, 150),
	},
	["Burbaloni_Loliloli"] = {
		BasePrice = 22500,
		BaseIncome = 900,
		CycleTime = 5,
		ModelName = "Burbaloni_Loliloli",
		Description = "Bubbly personality.",
		ProjectileColor = Color3.fromRGB(255, 255, 150),
	},
	
	-- Tier 3: Mid Game ($150k - $3.2M)
	["Cacto Hipopotamo"] = {
		BasePrice = 150000,
		BaseIncome = 5000,
		CycleTime = 5,
		ModelName = "Cacto Hipopotamo",
		Description = "Prickly hippo power!",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	["Cappuccino_Assassino"] = {
		BasePrice = 225000,
		BaseIncome = 7200,
		CycleTime = 5,
		ModelName = "Cappuccino_Assassino",
		Description = "Deadly coffee vibes.",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	["Cavallo_Virtuoso"] = {
		BasePrice = 325000,
		BaseIncome = 10000,
		CycleTime = 5,
		ModelName = "Cavallo_Virtuoso",
		Description = "Virtuoso horse!",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	["Chef_Crabracadabra"] = {
		BasePrice = 450000,
		BaseIncome = 13500,
		CycleTime = 5,
		ModelName = "Chef_Crabracadabra",
		Description = "Magic crab chef!",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	["Chicleteira Bicicleteira"] = {
		BasePrice = 600000,
		BaseIncome = 17500,
		CycleTime = 5,
		ModelName = "Chicleteira Bicicleteira",
		Description = "Gum on wheels!",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	["Chimpanzini Spiderini"] = {
		BasePrice = 800000,
		BaseIncome = 22500,
		CycleTime = 5,
		ModelName = "Chimpanzini Spiderini",
		Description = "Spider monkey fusion!",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	["Chimpanzini_Bananini"] = {
		BasePrice = 1000000,
		BaseIncome = 27500,
		CycleTime = 6,
		ModelName = "Chimpanzini_Bananini",
		Description = "Monke banana business!",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	["Cocofanto_Elefanto"] = {
		BasePrice = 1300000,
		BaseIncome = 35000,
		CycleTime = 6,
		ModelName = "Cocofanto_Elefanto",
		Description = "Coconut elephant!",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	["Espresso Signora"] = {
		BasePrice = 1600000,
		BaseIncome = 42500,
		CycleTime = 6,
		ModelName = "Espresso Signora",
		Description = "The espresso lady!",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	["Fluri_flura"] = {
		BasePrice = 2000000,
		BaseIncome = 52000,
		CycleTime = 6,
		ModelName = "Fluri_flura",
		Description = "Flowery friend.",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	["Frigo_Camelo"] = {
		BasePrice = 2500000,
		BaseIncome = 64000,
		CycleTime = 6,
		ModelName = "Frigo_Camelo",
		Description = "Cool camel cash!",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	["Gangster_Footera"] = {
		BasePrice = 3200000,
		BaseIncome = 80000,
		CycleTime = 6,
		ModelName = "Gangster_Footera",
		Description = "Gangster football!",
		ProjectileColor = Color3.fromRGB(255, 215, 0),
	},
	
	-- Tier 4: Mid-Late Game ($15M - $2.3B) - CostMultiplier: 1.20
	["Garama_and_Madundung"] = {
		BasePrice = 15000000,
		BaseIncome = 350000,
		CycleTime = 6,
		ModelName = "Garama_and_Madundung",
		Description = "Dynamic duo!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	["Gattatino Neonino"] = {
		BasePrice = 25000000,
		BaseIncome = 550000,
		CycleTime = 6,
		ModelName = "Gattatino Neonino",
		Description = "Neon kitty glow!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	["Gattatino_Nyanino"] = {
		BasePrice = 40000000,
		BaseIncome = 850000,
		CycleTime = 6,
		ModelName = "Gattatino_Nyanino",
		Description = "Nyan cat vibes!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	["Girafa_Celestre"] = {
		BasePrice = 65000000,
		BaseIncome = 1300000,
		CycleTime = 7,
		ModelName = "Girafa_Celestre",
		Description = "Heavenly giraffe!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	["Glorbo_Fruttodrillo"] = {
		BasePrice = 100000000,
		BaseIncome = 1900000,
		CycleTime = 7,
		ModelName = "Glorbo_Fruttodrillo",
		Description = "The legendary Glorbo!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	["Gorillo Watermelondrillo"] = {
		BasePrice = 150000000,
		BaseIncome = 2800000,
		CycleTime = 7,
		ModelName = "Gorillo Watermelondrillo",
		Description = "Watermelon gorilla!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	["Graipuss_Medussi"] = {
		BasePrice = 225000000,
		BaseIncome = 4000000,
		CycleTime = 7,
		ModelName = "Graipuss_Medussi",
		Description = "Grape medusa power!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	["La_Grande_Combinasion"] = {
		BasePrice = 350000000,
		BaseIncome = 6000000,
		CycleTime = 7,
		ModelName = "La_Grande_Combinasion",
		Description = "The grand combination!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	["La_Vacca_Saturno_Saturnita"] = {
		BasePrice = 500000000,
		BaseIncome = 8500000,
		CycleTime = 7,
		ModelName = "La_Vacca_Saturno_Saturnita",
		Description = "Cosmic cow powers!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	["Las Tralaleritas"] = {
		BasePrice = 750000000,
		BaseIncome = 12000000,
		CycleTime = 7,
		ModelName = "Las Tralaleritas",
		Description = "The little tralala girls!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	["Las Vaquitas Saturnitas"] = {
		BasePrice = 1100000000,
		BaseIncome = 17000000,
		CycleTime = 8,
		ModelName = "Las Vaquitas Saturnitas",
		Description = "Little Saturn cows!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	["Lionel_Cactuseli"] = {
		BasePrice = 1600000000,
		BaseIncome = 24000000,
		CycleTime = 8,
		ModelName = "Lionel_Cactuseli",
		Description = "Cactus lion legend!",
		CostMultiplier = 1.20,
		ProjectileColor = Color3.fromRGB(255, 165, 0),
	},
	
	-- Tier 5: Late Game ($2.5B - $175B) - CostMultiplier: 1.22
	["Lirilì_Larilà"] = {
		BasePrice = 2500000000,
		BaseIncome = 35000000,
		CycleTime = 8,
		ModelName = "Lirilì_Larilà",
		Description = "Musical magic!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Los Crocodillitos"] = {
		BasePrice = 4000000000,
		BaseIncome = 55000000,
		CycleTime = 8,
		ModelName = "Los Crocodillitos",
		Description = "Little croc gang!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Los_Tralaleritos"] = {
		BasePrice = 6500000000,
		BaseIncome = 85000000,
		CycleTime = 8,
		ModelName = "Los_Tralaleritos",
		Description = "The tralala boys!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Mat_teo"] = {
		BasePrice = 10000000000,
		BaseIncome = 125000000,
		CycleTime = 8,
		ModelName = "Mat_teo",
		Description = "It's Mat Teo!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Noobini_Pizzanini"] = {
		BasePrice = 15000000000,
		BaseIncome = 180000000,
		CycleTime = 8,
		ModelName = "Noobini_Pizzanini",
		Description = "Noob pizza power!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Nuclearo Dinossauro"] = {
		BasePrice = 22500000000,
		BaseIncome = 260000000,
		CycleTime = 8,
		ModelName = "Nuclearo Dinossauro",
		Description = "Nuclear dino!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Odin_Din_Din_Dun"] = {
		BasePrice = 32500000000,
		BaseIncome = 360000000,
		CycleTime = 9,
		ModelName = "Odin_Din_Din_Dun",
		Description = "Norse god energy!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Orangutini_Ananassini"] = {
		BasePrice = 45000000000,
		BaseIncome = 480000000,
		CycleTime = 9,
		ModelName = "Orangutini_Ananassini",
		Description = "Pineapple orangutan!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Orcalero Orcala"] = {
		BasePrice = 60000000000,
		BaseIncome = 620000000,
		CycleTime = 9,
		ModelName = "Orcalero Orcala",
		Description = "Orca power!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Pandaccini Bananini"] = {
		BasePrice = 80000000000,
		BaseIncome = 800000000,
		CycleTime = 9,
		ModelName = "Pandaccini Bananini",
		Description = "Panda banana combo!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Perochello_Lemonchello"] = {
		BasePrice = 105000000000,
		BaseIncome = 1000000000,
		CycleTime = 9,
		ModelName = "Perochello_Lemonchello",
		Description = "Lemon parrot drinks!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Piccione Macchina"] = {
		BasePrice = 135000000000,
		BaseIncome = 1250000000,
		CycleTime = 9,
		ModelName = "Piccione Macchina",
		Description = "Pigeon machine!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	["Pipi_Kiwi"] = {
		BasePrice = 175000000000,
		BaseIncome = 1550000000,
		CycleTime = 9,
		ModelName = "Pipi_Kiwi",
		Description = "Kiwi bird vibes!",
		CostMultiplier = 1.22,
		ProjectileColor = Color3.fromRGB(255, 105, 180),
	},
	
	-- Tier 6: End Game ($500B - $650T) - CostMultiplier: 1.25
	["Pot Hotspot"] = {
		BasePrice = 500000000000,
		BaseIncome = 4000000000,
		CycleTime = 9,
		ModelName = "Pot Hotspot",
		Description = "Hot pot spot!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Rhino_Toasterino"] = {
		BasePrice = 850000000000,
		BaseIncome = 6500000000,
		CycleTime = 9,
		ModelName = "Rhino_Toasterino",
		Description = "Toaster rhino!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Salamino Penguino"] = {
		BasePrice = 1500000000000,
		BaseIncome = 10000000000,
		CycleTime = 9,
		ModelName = "Salamino Penguino",
		Description = "Salami penguin!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Sammyni_Spyderini"] = {
		BasePrice = 2500000000000,
		BaseIncome = 15000000000,
		CycleTime = 10,
		ModelName = "Sammyni_Spyderini",
		Description = "Sammy the spider!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Spioniro Golubiro"] = {
		BasePrice = 4000000000000,
		BaseIncome = 22000000000,
		CycleTime = 10,
		ModelName = "Spioniro Golubiro",
		Description = "Spy pigeon!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Statutino Libertino"] = {
		BasePrice = 6500000000000,
		BaseIncome = 32000000000,
		CycleTime = 10,
		ModelName = "Statutino Libertino",
		Description = "Liberty statue!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Strawberrelli Flamingelli"] = {
		BasePrice = 10000000000000,
		BaseIncome = 45000000000,
		CycleTime = 10,
		ModelName = "Strawberrelli Flamingelli",
		Description = "Strawberry flamingo!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Svinina_Bombardino"] = {
		BasePrice = 15000000000000,
		BaseIncome = 60000000000,
		CycleTime = 10,
		ModelName = "Svinina_Bombardino",
		Description = "Bomber pig!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Ta_Ta_Ta_Ta_Sahur"] = {
		BasePrice = 22500000000000,
		BaseIncome = 85000000000,
		CycleTime = 10,
		ModelName = "Ta_Ta_Ta_Ta_Sahur",
		Description = "Sahur rhythm!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Talpa_Di_Fero"] = {
		BasePrice = 35000000000000,
		BaseIncome = 120000000000,
		CycleTime = 10,
		ModelName = "Talpa_Di_Fero",
		Description = "Iron mole!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Tigrilini Watermelini"] = {
		BasePrice = 50000000000000,
		BaseIncome = 160000000000,
		CycleTime = 10,
		ModelName = "Tigrilini Watermelini",
		Description = "Watermelon tiger!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Tigroligre Frutonni"] = {
		BasePrice = 75000000000000,
		BaseIncome = 220000000000,
		CycleTime = 10,
		ModelName = "Tigroligre Frutonni",
		Description = "Fruit tiger-lion!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Tim_Cheese"] = {
		BasePrice = 110000000000000,
		BaseIncome = 300000000000,
		CycleTime = 10,
		ModelName = "Tim_Cheese",
		Description = "It's Tim Cheese!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Torrtuginni Dragonfrutini"] = {
		BasePrice = 160000000000000,
		BaseIncome = 400000000000,
		CycleTime = 10,
		ModelName = "Torrtuginni Dragonfrutini",
		Description = "Dragonfruit turtle!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Tralalero_Tralala"] = {
		BasePrice = 225000000000000,
		BaseIncome = 550000000000,
		CycleTime = 10,
		ModelName = "Tralalero_Tralala",
		Description = "The OG tralala!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Trenostruzzo_Turbo_3000"] = {
		BasePrice = 325000000000000,
		BaseIncome = 750000000000,
		CycleTime = 10,
		ModelName = "Trenostruzzo_Turbo_3000",
		Description = "Turbo train ostrich!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Tric_Trac_Baraboom"] = {
		BasePrice = 450000000000000,
		BaseIncome = 1000000000000,
		CycleTime = 10,
		ModelName = "Tric_Trac_Baraboom",
		Description = "Boom tric trac!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	["Trippi_Troppi"] = {
		BasePrice = 650000000000000,
		BaseIncome = 1400000000000,
		CycleTime = 10,
		ModelName = "Trippi_Troppi",
		Description = "Trippy toppy!",
		CostMultiplier = 1.25,
		ProjectileColor = Color3.fromRGB(255, 50, 50),
	},
	
	-- Tier 7: Legendary ($1Qa - $10Qa) - CostMultiplier: 1.30
	["Trulimero_Trulicina"] = {
		BasePrice = 1000000000000000,
		BaseIncome = 2000000000000,
		CycleTime = 10,
		ModelName = "Trulimero_Trulicina",
		Description = "Trulli power!",
		CostMultiplier = 1.30,
		ProjectileColor = Color3.fromRGB(148, 0, 211),
	},
	["Tung_Tung_Tung_Sahur"] = {
		BasePrice = 2500000000000000,
		BaseIncome = 4500000000000,
		CycleTime = 10,
		ModelName = "Tung_Tung_Tung_Sahur",
		Description = "Wake up to riches!",
		CostMultiplier = 1.30,
		ProjectileColor = Color3.fromRGB(148, 0, 211),
	},
	["Unclito_Samito"] = {
		BasePrice = 5000000000000000,
		BaseIncome = 8500000000000,
		CycleTime = 10,
		ModelName = "Unclito_Samito",
		Description = "Uncle Sam power!",
		CostMultiplier = 1.30,
		ProjectileColor = Color3.fromRGB(148, 0, 211),
	},
	["Zibra Zubra Zibralini"] = {
		BasePrice = 10000000000000000,
		BaseIncome = 16000000000000,
		CycleTime = 10,
		ModelName = "Zibra Zubra Zibralini",
		Description = "Triple zebra!",
		CostMultiplier = 1.30,
		ProjectileColor = Color3.fromRGB(148, 0, 211),
	},
	
	-- Tier 8: Lucky Blocks (Special Units) - CostMultiplier: 1.45
	["Secret Lucky Block"] = {
		BasePrice = 50000000000000000,
		BaseIncome = 75000000000000,
		CycleTime = 10,
		ModelName = "Secret Lucky Block",
		Description = "Secret lucky power!",
		CostMultiplier = 1.45,
		ProjectileColor = Color3.fromRGB(0, 255, 255),
	},
	["Mythic Lucky Block"] = {
		BasePrice = 250000000000000000,
		BaseIncome = 350000000000000,
		CycleTime = 10,
		ModelName = "Mythic Lucky Block",
		Description = "Mythic luck!",
		CostMultiplier = 1.45,
		ProjectileColor = Color3.fromRGB(0, 255, 255),
	},
	["Brainrot God Lucky Block"] = {
		BasePrice = 1000000000000000000,
		BaseIncome = 1250000000000000,
		CycleTime = 10,
		ModelName = "Brainrot God Lucky Block",
		Description = "The ultimate brainrot deity!",
		CostMultiplier = 1.45,
		ProjectileColor = Color3.fromRGB(0, 255, 255),
	},
}

-- Pre-sorted list cache
local SortedUnitsCache: {{name: string, config: UnitConfig}}? = nil

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Calculates the current price for a unit based on how many the player owns.
	
	Formula: BasePrice * (CostMultiplier ^ amountOwned)
	Uses per-unit CostMultiplier if defined, otherwise default 1.15.
	
	@param unitName string - The name of the unit
	@param amountOwned number - How many of this unit the player currently owns
	@return number - The calculated price (floored to integer)
]]
local function CalculatePrice(unitName: string, amountOwned: number): number
	local config = Units[unitName]
	if not config then
		warn("ShopConfig: Unknown unit " .. unitName)
		return 0
	end
	
	-- Use per-unit multiplier if defined, otherwise fall back to default
	local multiplier = config.CostMultiplier or PRICE_MULTIPLIER
	local price = config.BasePrice * (multiplier ^ amountOwned)
	return math.floor(price)
end

--[[
	Calculates the effective income for a unit with milestone bonuses.
	
	@param unitName string - The name of the unit
	@param amountOwned number - How many of this unit the player owns
	@return number - The effective income per cycle
]]
local function CalculateEffectiveIncome(unitName: string, amountOwned: number): number
	local config = Units[unitName]
	if not config then
		warn("ShopConfig: Unknown unit " .. unitName)
		return 0
	end
	
	local profitMultiplier = 1
	
	-- Apply all profit milestones that have been reached
	for _, milestone in MILESTONES do
		if amountOwned >= milestone.quantity and milestone.milestoneType == "profit" then
			profitMultiplier = profitMultiplier * milestone.multiplier
		end
	end
	
	return math.floor(config.BaseIncome * profitMultiplier)
end

--[[
	Calculates the effective cycle time for a unit with milestone bonuses.
	
	@param unitName string - The name of the unit
	@param amountOwned number - How many of this unit the player owns
	@return number - The effective cycle time in seconds
]]
local function CalculateEffectiveCycleTime(unitName: string, amountOwned: number): number
	local config = Units[unitName]
	if not config then
		warn("ShopConfig: Unknown unit " .. unitName)
		return 3 -- Default fallback
	end
	
	local speedMultiplier = 1
	
	-- Apply all speed milestones that have been reached
	for _, milestone in MILESTONES do
		if amountOwned >= milestone.quantity and milestone.milestoneType == "speed" then
			speedMultiplier = speedMultiplier * milestone.multiplier
		end
	end
	
	-- Speed multiplier reduces cycle time (higher speed = lower time)
	return math.max(0.1, config.CycleTime / speedMultiplier) -- Min 0.1s cycle
end

--[[
	Gets the next milestone info for a unit.
	
	@param amountOwned number - How many of this unit the player owns
	@return MilestoneInfo?, number - Next milestone and progress, or nil if all reached
]]
local function GetNextMilestone(amountOwned: number): (MilestoneInfo?, number)
	for _, milestone in MILESTONES do
		if amountOwned < milestone.quantity then
			return milestone, amountOwned
		end
	end
	
	return nil, amountOwned -- All milestones reached
end

--[[
	Gets all milestones that have been reached.
	
	@param amountOwned number - How many of this unit the player owns
	@return {MilestoneInfo} - Array of reached milestones
]]
local function GetMilestonesReached(amountOwned: number): {MilestoneInfo}
	local reached = {}
	
	for _, milestone in MILESTONES do
		if amountOwned >= milestone.quantity then
			table.insert(reached, milestone)
		end
	end
	
	return reached
end

--[[
	Gets the configuration for a specific unit.
	
	@param unitName string - The name of the unit
	@return UnitConfig? - The config table, or nil if not found
]]
local function GetConfig(unitName: string): UnitConfig?
	return Units[unitName]
end

--[[
	Returns an array of all units sorted by BasePrice (ascending).
	Cached for performance.
	
	@return table - Array of {name, config} pairs sorted by BasePrice
]]
local function GetAllUnitsSorted(): {{name: string, config: UnitConfig}}
	if SortedUnitsCache then
		return SortedUnitsCache
	end
	
	local sorted = {}
	
	for name, config in Units do
		table.insert(sorted, {name = name, config = config})
	end
	
	table.sort(sorted, function(a, b)
		return a.config.BasePrice < b.config.BasePrice
	end)
	
	SortedUnitsCache = sorted
	return sorted
end

--[[
	Returns which units should be visible based on unlock progress.
	Shows (unlockProgress) unlocked + 1 locked preview.
	
	@param unlockProgress number - How many units are unlocked (default: INITIAL_UNLOCKED)
	@return table - Array of {name, config, isLocked} for visible units
]]
local function GetVisibleUnits(unlockProgress: number?): {{name: string, config: UnitConfig, isLocked: boolean}}
	local progress = unlockProgress or INITIAL_UNLOCKED
	local allUnits = GetAllUnitsSorted()
	local visible = {}
	
	-- Show unlocked units + 1 locked preview
	local showCount = math.min(progress + 1, #allUnits)
	
	for i = 1, showCount do
		local unit = allUnits[i]
		table.insert(visible, {
			name = unit.name,
			config = unit.config,
			isLocked = i > progress,
		})
	end
	
	return visible
end

--[[
	Checks if a unit is unlocked based on unlock progress.
	
	@param unitName string - The name of the unit
	@param unlockProgress number - Current unlock progress
	@return boolean - Whether the unit is unlocked
]]
local function IsUnitUnlocked(unitName: string, unlockProgress: number?): boolean
	local progress = unlockProgress or INITIAL_UNLOCKED
	local allUnits = GetAllUnitsSorted()
	
	for i, unit in allUnits do
		if unit.name == unitName then
			return i <= progress
		end
	end
	
	return false
end

--[[
	Gets the total number of units available.
]]
local function GetTotalUnits(): number
	return #GetAllUnitsSorted()
end

-- Return module with both data and functions
return {
	Units = Units,
	CalculatePrice = CalculatePrice,
	CalculateEffectiveIncome = CalculateEffectiveIncome,
	CalculateEffectiveCycleTime = CalculateEffectiveCycleTime,
	GetNextMilestone = GetNextMilestone,
	GetMilestonesReached = GetMilestonesReached,
	GetConfig = GetConfig,
	GetAllUnitsSorted = GetAllUnitsSorted,
	GetVisibleUnits = GetVisibleUnits,
	IsUnitUnlocked = IsUnitUnlocked,
	GetTotalUnits = GetTotalUnits,
	
	-- Constants
	PRICE_MULTIPLIER = PRICE_MULTIPLIER,
	INITIAL_UNLOCKED = INITIAL_UNLOCKED,
	MILESTONES = MILESTONES,
}
