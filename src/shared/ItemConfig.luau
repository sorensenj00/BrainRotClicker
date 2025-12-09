--[[
	ItemConfig - Shared Configuration for Producible Items
	
	Defines all items that brainrots can produce, their base prices,
	volatility profiles, and mappings to brainrot types.
	
	Located in ReplicatedStorage so both Server and Client can access it.
]]

export type ItemDefinition = {
	id: string,
	displayName: string,
	icon: string,
	tier: number,          -- 1=Common, 2=Uncommon, 3=Rare, 4=Legendary
	basePrice: number,
	volatility: number,    -- 0.1 = ±10%, 0.8 = ±80%, 1.0 = ±100%
	description: string?,
}

export type BrainrotItemMapping = {
	tier1: string,  -- Item ID for tier 1 (1+ owned)
	tier2: string,  -- Item ID for tier 2 (10+ owned)
	tier3: string,  -- Item ID for tier 3 (50+ owned)
	tier4: string,  -- Item ID for tier 4 (100+ owned)
}

export type SynergyRecipe = {
	unitA: string,       -- Brainrot category (e.g., "Skibidi")
	unitB: string,       -- Second brainrot category
	itemId: string,      -- Resulting synergy item
	rate: number,        -- Production rate in seconds
}

local ItemConfig = {}

--------------------------------------------------------------------------------
-- PRODUCTION RATES (seconds per item)
--------------------------------------------------------------------------------

ItemConfig.ProductionRates = {
	tier1 = 2,    -- Common: every 2 seconds
	tier2 = 10,   -- Uncommon: every 10 seconds
	tier3 = 45,   -- Rare: every 45 seconds
	tier4 = 180,  -- Legendary: every 3 minutes
}

-- Milestone thresholds for unlocking tiers
ItemConfig.MilestoneThresholds = {
	tier1 = 1,    -- 1+ owned
	tier2 = 10,   -- 10+ owned
	tier3 = 50,   -- 50+ owned
	tier4 = 100,  -- 100+ owned
}

--------------------------------------------------------------------------------
-- ITEM DEFINITIONS
--------------------------------------------------------------------------------

ItemConfig.Items = {
	-- ═══════════════════════════════════════════════════════════════════════
	-- SKIBIDI TOILET ITEMS
	-- ═══════════════════════════════════════════════════════════════════════
	ToiletPaper = {
		id = "ToiletPaper",
		displayName = "Toilet Paper",
		icon = "🧻",
		tier = 1,
		basePrice = 5,
		volatility = 0.1,
		description = "The essentials.",
	},
	Plunger = {
		id = "Plunger",
		displayName = "Plunger",
		icon = "🪠",
		tier = 2,
		basePrice = 25,
		volatility = 0.3,
		description = "For when things get serious.",
	},
	GoldenFlush = {
		id = "GoldenFlush",
		displayName = "Golden Flush",
		icon = "🚽",
		tier = 3,
		basePrice = 150,
		volatility = 0.8,
		description = "Luxury porcelain experience.",
	},
	PorcelainThrone = {
		id = "PorcelainThrone",
		displayName = "Porcelain Throne",
		icon = "👑",
		tier = 4,
		basePrice = 1000,
		volatility = 1.0,
		description = "Fit for royalty.",
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- BOMBARDIRO ITEMS
	-- ═══════════════════════════════════════════════════════════════════════
	Firecracker = {
		id = "Firecracker",
		displayName = "Firecracker",
		icon = "🧨",
		tier = 1,
		basePrice = 8,
		volatility = 0.1,
		description = "Pop pop!",
	},
	Grenade = {
		id = "Grenade",
		displayName = "Grenade",
		icon = "💣",
		tier = 2,
		basePrice = 50,
		volatility = 0.3,
		description = "Handle with care.",
	},
	Missile = {
		id = "Missile",
		displayName = "Missile",
		icon = "🚀",
		tier = 3,
		basePrice = 200,
		volatility = 0.8,
		description = "Going ballistic.",
	},
	Nuke = {
		id = "Nuke",
		displayName = "Nuke",
		icon = "☢️",
		tier = 4,
		basePrice = 1500,
		volatility = 1.0,
		description = "The big one.",
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- TRALALERO ITEMS
	-- ═══════════════════════════════════════════════════════════════════════
	Kazoo = {
		id = "Kazoo",
		displayName = "Kazoo",
		icon = "🎵",
		tier = 1,
		basePrice = 6,
		volatility = 0.1,
		description = "Makes any song better.",
	},
	Guitar = {
		id = "Guitar",
		displayName = "Guitar",
		icon = "🎸",
		tier = 2,
		basePrice = 40,
		volatility = 0.3,
		description = "Anyway, here's Wonderwall.",
	},
	ConcertTicket = {
		id = "ConcertTicket",
		displayName = "Concert Ticket",
		icon = "🎫",
		tier = 3,
		basePrice = 175,
		volatility = 0.8,
		description = "VIP access.",
	},
	PlatinumAlbum = {
		id = "PlatinumAlbum",
		displayName = "Platinum Album",
		icon = "💿",
		tier = 4,
		basePrice = 1200,
		volatility = 1.0,
		description = "Certified classic.",
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- BRR BRR PATAPIM ITEMS
	-- ═══════════════════════════════════════════════════════════════════════
	Snowflake = {
		id = "Snowflake",
		displayName = "Snowflake",
		icon = "❄️",
		tier = 1,
		basePrice = 4,
		volatility = 0.1,
		description = "Unique, like you.",
	},
	IceCube = {
		id = "IceCube",
		displayName = "Ice Cube",
		icon = "🧊",
		tier = 2,
		basePrice = 30,
		volatility = 0.3,
		description = "Keep it cool.",
	},
	FrozenHeart = {
		id = "FrozenHeart",
		displayName = "Frozen Heart",
		icon = "💙",
		tier = 3,
		basePrice = 125,
		volatility = 0.8,
		description = "Cold but valuable.",
	},
	EternalWinter = {
		id = "EternalWinter",
		displayName = "Eternal Winter",
		icon = "🌨️",
		tier = 4,
		basePrice = 900,
		volatility = 1.0,
		description = "Winter is coming... forever.",
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- SIGMA ITEMS
	-- ═══════════════════════════════════════════════════════════════════════
	ProteinBar = {
		id = "ProteinBar",
		displayName = "Protein Bar",
		icon = "💪",
		tier = 1,
		basePrice = 7,
		volatility = 0.1,
		description = "Gains.",
	},
	Dumbbell = {
		id = "Dumbbell",
		displayName = "Dumbbell",
		icon = "🏋️",
		tier = 2,
		basePrice = 45,
		volatility = 0.3,
		description = "No pain, no gain.",
	},
	GrindsetBook = {
		id = "GrindsetBook",
		displayName = "Grindset Book",
		icon = "📈",
		tier = 3,
		basePrice = 180,
		volatility = 0.8,
		description = "Billionaire mindset.",
	},
	MoaiStatue = {
		id = "MoaiStatue",
		displayName = "Moai Statue",
		icon = "🗿",
		tier = 4,
		basePrice = 1100,
		volatility = 1.0,
		description = "Peak performance achieved.",
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- MEWER ITEMS
	-- ═══════════════════════════════════════════════════════════════════════
	CatTreat = {
		id = "CatTreat",
		displayName = "Cat Treat",
		icon = "😺",
		tier = 1,
		basePrice = 5,
		volatility = 0.1,
		description = "Meow mix.",
	},
	CatToy = {
		id = "CatToy",
		displayName = "Cat Toy",
		icon = "🐱",
		tier = 2,
		basePrice = 35,
		volatility = 0.3,
		description = "Endless entertainment.",
	},
	DesignerCollar = {
		id = "DesignerCollar",
		displayName = "Designer Collar",
		icon = "🎀",
		tier = 3,
		basePrice = 160,
		volatility = 0.8,
		description = "Fashion forward feline.",
	},
	HypnoEyes = {
		id = "HypnoEyes",
		displayName = "Hypno Eyes",
		icon = "👁️",
		tier = 4,
		basePrice = 1000,
		volatility = 1.0,
		description = "You will obey.",
	},
	
	-- ═══════════════════════════════════════════════════════════════════════
	-- SYNERGY ITEMS
	-- ═══════════════════════════════════════════════════════════════════════
	ExplosiveToilet = {
		id = "ExplosiveToilet",
		displayName = "Explosive Toilet",
		icon = "💣🚽",
		tier = 3,
		basePrice = 500,
		volatility = 0.8,
		description = "When chaos meets porcelain.",
	},
	FrozenFlush = {
		id = "FrozenFlush",
		displayName = "Frozen Flush",
		icon = "🧊🚽",
		tier = 3,
		basePrice = 400,
		volatility = 0.8,
		description = "Cold comfort.",
	},
	GigachadStatue = {
		id = "GigachadStatue",
		displayName = "Gigachad Statue",
		icon = "🗿😺",
		tier = 3,
		basePrice = 750,
		volatility = 0.8,
		description = "Peak performance achieved.",
	},
	PowerExplosion = {
		id = "PowerExplosion",
		displayName = "Power Explosion",
		icon = "💪💥",
		tier = 3,
		basePrice = 600,
		volatility = 0.8,
		description = "Explosive gains.",
	},
	FrozenSymphony = {
		id = "FrozenSymphony",
		displayName = "Frozen Symphony",
		icon = "🎵❄️",
		tier = 3,
		basePrice = 550,
		volatility = 0.8,
		description = "Chilling melodies.",
	},
	CatConcert = {
		id = "CatConcert",
		displayName = "Cat Concert",
		icon = "🎵😺",
		tier = 3,
		basePrice = 450,
		volatility = 0.8,
		description = "Purrfect harmony.",
	},
	IceBomb = {
		id = "IceBomb",
		displayName = "Ice Bomb",
		icon = "💣❄️",
		tier = 3,
		basePrice = 700,
		volatility = 0.8,
		description = "Freeze and boom.",
	},
}

--------------------------------------------------------------------------------
-- BRAINROT → ITEM MAPPINGS
--------------------------------------------------------------------------------

-- Maps brainrot categories to their item production
-- The key should match a prefix or category that groups similar brainrots
ItemConfig.BrainrotItems = {
	-- Skibidi family (Skibidi_Toilet, Skibidi_Scientist, etc.)
	Skibidi = {
		tier1 = "ToiletPaper",
		tier2 = "Plunger",
		tier3 = "GoldenFlush",
		tier4 = "PorcelainThrone",
	},
	
	-- Bombardiro family
	Bombardiro = {
		tier1 = "Firecracker",
		tier2 = "Grenade",
		tier3 = "Missile",
		tier4 = "Nuke",
	},
	
	-- Tralalero family
	Tralalero = {
		tier1 = "Kazoo",
		tier2 = "Guitar",
		tier3 = "ConcertTicket",
		tier4 = "PlatinumAlbum",
	},
	
	-- Brr Brr Patapim family
	BrrBrr = {
		tier1 = "Snowflake",
		tier2 = "IceCube",
		tier3 = "FrozenHeart",
		tier4 = "EternalWinter",
	},
	
	-- Sigma family
	Sigma = {
		tier1 = "ProteinBar",
		tier2 = "Dumbbell",
		tier3 = "GrindsetBook",
		tier4 = "MoaiStatue",
	},
	
	-- Mewer family (cats)
	Mewer = {
		tier1 = "CatTreat",
		tier2 = "CatToy",
		tier3 = "DesignerCollar",
		tier4 = "HypnoEyes",
	},
}

-- Maps actual brainrot model names to their category
-- This allows grouping similar brainrots for milestone counting
-- All 74 brainrots from ShopConfig are mapped to 6 categories
ItemConfig.BrainrotToCategory = {
	-- ═══════════════════════════════════════════════════════════════════
	-- CATEGORY: Skibidi (Toilet/Bathroom theme)
	-- Items: ToiletPaper, Plunger, GoldenBowl, DiamondThrone
	-- ═══════════════════════════════════════════════════════════════════
	["Skibidi_Toilet"] = "Skibidi",
	["Skibidi_Scientist"] = "Skibidi",
	["Skibidi_DOP_DOP"] = "Skibidi",
	["Cappuccino_Assassino"] = "Skibidi",
	["Espresso Signora"] = "Skibidi",
	["Pot Hotspot"] = "Skibidi",
	["Rhino_Toasterino"] = "Skibidi",
	["Tim_Cheese"] = "Skibidi",
	["Noobini_Pizzanini"] = "Skibidi",
	["Piccione Macchina"] = "Skibidi",
	["Sammyni_Spyderini"] = "Skibidi",
	["Spioniro Golubiro"] = "Skibidi",
	
	-- ═══════════════════════════════════════════════════════════════════
	-- CATEGORY: Bombardiro (Explosive/Military theme)
	-- Items: Firecracker, Bomblet, NukeCore, AtomSplitter
	-- ═══════════════════════════════════════════════════════════════════
	["Bombardiro_Crocodilo"] = "Bombardiro",
	["Bombombini_Gusini"] = "Bombardiro",
	["Svinina_Bombardino"] = "Bombardiro",
	["Nuclearo Dinossauro"] = "Bombardiro",
	["Tric_Trac_Baraboom"] = "Bombardiro",
	["Trenostruzzo_Turbo_3000"] = "Bombardiro",
	["Los Crocodillitos"] = "Bombardiro",
	["Gangster_Footera"] = "Bombardiro",
	["Bandito_Bobritto"] = "Bombardiro",
	["Ta_Ta_Ta_Ta_Sahur"] = "Bombardiro",
	["Tung_Tung_Tung_Sahur"] = "Bombardiro",
	["Odin_Din_Din_Dun"] = "Bombardiro",
	
	-- ═══════════════════════════════════════════════════════════════════
	-- CATEGORY: Tralalero (Musical/Dance theme)
	-- Items: MusicNote, Microphone, GoldRecord, PlatinumAlbum
	-- ═══════════════════════════════════════════════════════════════════
	["Tralalero_Tralala"] = "Tralalero",
	["Las Tralaleritas"] = "Tralalero",
	["Los_Tralaleritos"] = "Tralalero",
	["Ballerina_Cappuccina"] = "Tralalero",
	["Ballerino Lololo"] = "Tralalero",
	["Lirilì_Larilà"] = "Tralalero",
	["Burbaloni_Loliloli"] = "Tralalero",
	["Trippi_Troppi"] = "Tralalero",
	["Fluri_flura"] = "Tralalero",
	["Chicleteira Bicicleteira"] = "Tralalero",
	["Orcalero Orcala"] = "Tralalero",
	["Trulimero_Trulicina"] = "Tralalero",
	
	-- ═══════════════════════════════════════════════════════════════════
	-- CATEGORY: BrrBrr (Cold/Winter theme)
	-- Items: Snowflake, IceCube, FrozenHeart, BlizzardCore
	-- ═══════════════════════════════════════════════════════════════════
	["Brr_Brr_Patapim"] = "BrrBrr",
	["Brri_Brri_Bicus_Dicus_Bombicus"] = "BrrBrr",
	["Frigo_Camelo"] = "BrrBrr",
	["Salamino Penguino"] = "BrrBrr",
	["Pipi_Kiwi"] = "BrrBrr",
	["Blueberrinni_Octopusini"] = "BrrBrr",
	["Graipuss_Medussi"] = "BrrBrr",
	["Perochello_Lemonchello"] = "BrrBrr",
	["Strawberrelli Flamingelli"] = "BrrBrr",
	["Tigrilini Watermelini"] = "BrrBrr",
	["Tigroligre Frutonni"] = "BrrBrr",
	["Torrtuginni Dragonfrutini"] = "BrrBrr",
	
	-- ═══════════════════════════════════════════════════════════════════
	-- CATEGORY: Sigma (Meme/Internet theme)
	-- Items: ViralPost, TrendingTag, GoldenMeme, DiamondClout
	-- ═══════════════════════════════════════════════════════════════════
	["Chimpanzini_Bananini"] = "Sigma",
	["Chimpanzini Spiderini"] = "Sigma",
	["Orangutini_Ananassini"] = "Sigma",
	["Pandaccini Bananini"] = "Sigma",
	["Gorillo Watermelondrillo"] = "Sigma",
	["Mat_teo"] = "Sigma",
	["Glorbo_Fruttodrillo"] = "Sigma",
	["Unclito_Samito"] = "Sigma",
	["Statutino Libertino"] = "Sigma",
	["Secret Lucky Block"] = "Sigma",
	["Mythic Lucky Block"] = "Sigma",
	["Brainrot God Lucky Block"] = "Sigma",
	
	-- ═══════════════════════════════════════════════════════════════════
	-- CATEGORY: Mewer (Animal/Creature theme)
	-- Items: Pawprint, FurBall, GoldenCollar, CrystalClaw
	-- ═══════════════════════════════════════════════════════════════════
	["Gattatino Neonino"] = "Mewer",
	["Gattatino_Nyanino"] = "Mewer",
	["La_Gatta_Cattini"] = "Mewer",
	["Lionel_Cactuseli"] = "Mewer",
	["Girafa_Celestre"] = "Mewer",
	["Cocofanto_Elefanto"] = "Mewer",
	["Cavallo_Virtuoso"] = "Mewer",
	["La_Vacca_Saturno_Saturnita"] = "Mewer",
	["Las Vaquitas Saturnitas"] = "Mewer",
	["Zibra Zubra Zibralini"] = "Mewer",
	["Talpa_Di_Fero"] = "Mewer",
	["La_Grande_Combinasion"] = "Mewer",
	
	-- ═══════════════════════════════════════════════════════════════════
	-- STARTER UNITS (All in Tralalero for simplicity - they're basic)
	-- ═══════════════════════════════════════════════════════════════════
	["Avocadini Guffo"] = "Tralalero",
	["Bambini_Crostini"] = "Tralalero",
	["Bananita_Dolphinita"] = "BrrBrr",
	["Boneca_Ambalabu"] = "Bombardiro",
	["Cacto Hipopotamo"] = "Mewer",
	["Chef_Crabracadabra"] = "Skibidi",
	["Garama_and_Madundung"] = "Sigma",
}

--------------------------------------------------------------------------------
-- SYNERGY RECIPES
--------------------------------------------------------------------------------

ItemConfig.SynergyRecipes = {
	{
		unitA = "Skibidi",
		unitB = "Bombardiro",
		itemId = "ExplosiveToilet",
		rate = 10,
	},
	{
		unitA = "Skibidi",
		unitB = "BrrBrr",
		itemId = "FrozenFlush",
		rate = 10,
	},
	{
		unitA = "Sigma",
		unitB = "Mewer",
		itemId = "GigachadStatue",
		rate = 10,
	},
	{
		unitA = "Sigma",
		unitB = "Bombardiro",
		itemId = "PowerExplosion",
		rate = 10,
	},
	{
		unitA = "Tralalero",
		unitB = "BrrBrr",
		itemId = "FrozenSymphony",
		rate = 10,
	},
	{
		unitA = "Tralalero",
		unitB = "Mewer",
		itemId = "CatConcert",
		rate = 10,
	},
	{
		unitA = "Bombardiro",
		unitB = "BrrBrr",
		itemId = "IceBomb",
		rate = 10,
	},
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Gets an item definition by ID.
	@param itemId string - The item ID
	@return ItemDefinition? - The item definition or nil
]]
function ItemConfig.GetItem(itemId: string): ItemDefinition?
	return ItemConfig.Items[itemId]
end

--[[
	Gets the category for a brainrot model name.
	@param brainrotName string - The brainrot model name
	@return string? - The category or nil if not mapped
]]
function ItemConfig.GetBrainrotCategory(brainrotName: string): string?
	-- Direct mapping check
	if ItemConfig.BrainrotToCategory[brainrotName] then
		return ItemConfig.BrainrotToCategory[brainrotName]
	end
	
	-- Fuzzy match by prefix
	local lowerName = string.lower(brainrotName)
	if string.find(lowerName, "skibidi") then return "Skibidi" end
	if string.find(lowerName, "bombard") or string.find(lowerName, "bomber") then return "Bombardiro" end
	if string.find(lowerName, "tralal") then return "Tralalero" end
	if string.find(lowerName, "brr") or string.find(lowerName, "patapim") then return "BrrBrr" end
	if string.find(lowerName, "sigma") or string.find(lowerName, "chad") then return "Sigma" end
	if string.find(lowerName, "cat") or string.find(lowerName, "gatta") or string.find(lowerName, "mew") then return "Mewer" end
	
	return nil
end

--[[
	Gets the items a brainrot category produces based on milestone tier.
	@param category string - The brainrot category
	@param ownedCount number - How many of this category the player owns
	@return {{itemId: string, rate: number}} - Array of item productions
]]
function ItemConfig.GetProductions(category: string, ownedCount: number): {{itemId: string, rate: number}}
	local mapping = ItemConfig.BrainrotItems[category]
	if not mapping then return {} end
	
	local productions = {}
	local thresholds = ItemConfig.MilestoneThresholds
	local rates = ItemConfig.ProductionRates
	
	if ownedCount >= thresholds.tier1 then
		table.insert(productions, {itemId = mapping.tier1, rate = rates.tier1})
	end
	if ownedCount >= thresholds.tier2 then
		table.insert(productions, {itemId = mapping.tier2, rate = rates.tier2})
	end
	if ownedCount >= thresholds.tier3 then
		table.insert(productions, {itemId = mapping.tier3, rate = rates.tier3})
	end
	if ownedCount >= thresholds.tier4 then
		table.insert(productions, {itemId = mapping.tier4, rate = rates.tier4})
	end
	
	return productions
end

--[[
	Finds a synergy recipe for two adjacent categories.
	@param categoryA string - First category
	@param categoryB string - Second category
	@return SynergyRecipe? - The synergy recipe or nil
]]
function ItemConfig.GetSynergyRecipe(categoryA: string, categoryB: string): SynergyRecipe?
	for _, recipe in ItemConfig.SynergyRecipes do
		if (recipe.unitA == categoryA and recipe.unitB == categoryB) or
		   (recipe.unitA == categoryB and recipe.unitB == categoryA) then
			return recipe
		end
	end
	return nil
end

--[[
	Gets all items sorted by tier then price.
	@return {ItemDefinition} - Sorted array of items
]]
function ItemConfig.GetAllItemsSorted(): {ItemDefinition}
	local items = {}
	for _, item in ItemConfig.Items do
		table.insert(items, item)
	end
	table.sort(items, function(a, b)
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		return a.basePrice < b.basePrice
	end)
	return items
end

return ItemConfig
