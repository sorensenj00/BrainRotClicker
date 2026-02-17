--[[
    ItemConfig - Shared Configuration for Producible Items
    67+ Unique Brainrot Production Lines
]]

local ItemConfig = {}

-- Typografi definitioner
export type ItemDefinition = {
    id: string,
    displayName: string,
    icon: string,
    tier: number,
    basePrice: number,
    volatility: number,
}

--------------------------------------------------------------------------------
-- PRODUCTION SETTINGS
--------------------------------------------------------------------------------

ItemConfig.ProductionRates = {
    tier1 = 2,    -- Common
    tier2 = 10,   -- Uncommon
    tier3 = 45,   -- Rare
    tier4 = 180,  -- Legendary
}

ItemConfig.MilestoneThresholds = {
    tier1 = 1,
    tier2 = 10,
    tier3 = 50,
    tier4 = 100,
}

--------------------------------------------------------------------------------
-- ITEM DEFINITIONS (The massive list of 4 tiers per model)
--------------------------------------------------------------------------------

ItemConfig.Items = {
    -- Avocadini Guffo
    Guac1 = { id = "Guac1", displayName = "Brown Pit", icon = "🥑", tier = 1, basePrice = 5, volatility = 0.1 },
    Guac2 = { id = "Guac2", displayName = "Sliced Avocado", icon = "🥑", tier = 2, basePrice = 25, volatility = 0.2 },
    Guac3 = { id = "Guac3", displayName = "Fresh Guacamole", icon = "🥣", tier = 3, basePrice = 150, volatility = 0.5 },
    Guac4 = { id = "Guac4", displayName = "Golden Avocado", icon = "✨", tier = 4, basePrice = 1000, volatility = 0.8 },

    -- Ballerina_Cappuccina
    Cap1 = { id = "Cap1", displayName = "Empty Cup", icon = "☕", tier = 1, basePrice = 6, volatility = 0.1 },
    Cap2 = { id = "Cap2", displayName = "Cold Latte", icon = "☕", tier = 2, basePrice = 30, volatility = 0.2 },
    Cap3 = { id = "Cap3", displayName = "Foamy Cappuccino", icon = "☕", tier = 3, basePrice = 180, volatility = 0.5 },
    Cap4 = { id = "Cap4", displayName = "Elite Espresso", icon = "👑", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Bananita_Dolphinita
    BanDolph1 = { id = "BanDolph1", displayName = "Banana Peel", icon = "🍌", tier = 1, basePrice = 4, volatility = 0.1 },
    BanDolph2 = { id = "BanDolph2", displayName = "Frozen Banana", icon = "❄️", tier = 2, basePrice = 22, volatility = 0.2 },
    BanDolph3 = { id = "BanDolph3", displayName = "Banana Split", icon = "🍨", tier = 3, basePrice = 140, volatility = 0.5 },
    BanDolph4 = { id = "BanDolph4", displayName = "Dolphin Figurine", icon = "🐬", tier = 4, basePrice = 950, volatility = 0.8 },

    -- Brainrot God Lucky Block
    GodLuck1 = { id = "GodLuck1", displayName = "Lucky Shard", icon = "🍀", tier = 1, basePrice = 50, volatility = 0.2 },
    GodLuck2 = { id = "GodLuck2", displayName = "Mystery Cube", icon = "📦", tier = 2, basePrice = 250, volatility = 0.4 },
    GodLuck3 = { id = "GodLuck3", displayName = "Jackpot Token", icon = "🎰", tier = 3, basePrice = 1200, volatility = 0.7 },
    GodLuck4 = { id = "GodLuck4", displayName = "Godly Artifact", icon = "🔱", tier = 4, basePrice = 8000, volatility = 1.0 },

    -- Nuclearo Dinossauro
    NukeDino1 = { id = "NukeDino1", displayName = "Radioactive Bone", icon = "🦴", tier = 1, basePrice = 40, volatility = 0.2 },
    NukeDino2 = { id = "NukeDino2", displayName = "Uranium Egg", icon = "🥚", tier = 2, basePrice = 200, volatility = 0.4 },
    NukeDino3 = { id = "NukeDino3", displayName = "Plasma Core", icon = "☢️", tier = 3, basePrice = 1000, volatility = 0.8 },
    NukeDino4 = { id = "NukeDino4", displayName = "Atomic Tyrant Eye", icon = "👁️", tier = 4, basePrice = 6500, volatility = 1.0 },

    -- Statutino Libertino
    Lib1 = { id = "Lib1", displayName = "Copper Plate", icon = "🧱", tier = 1, basePrice = 8, volatility = 0.1 },
    Lib2 = { id = "Lib2", displayName = "Rusty Torch", icon = "🔦", tier = 2, basePrice = 45, volatility = 0.2 },
    Lib3 = { id = "Lib3", displayName = "Liberty Crown", icon = "🗽", tier = 3, basePrice = 250, volatility = 0.5 },
    Lib4 = { id = "Lib4", displayName = "Golden Freedom Statue", icon = "⚖️", tier = 4, basePrice = 1800, volatility = 0.8 },

    -- Sammyni_Spyderini
    Spy1 = { id = "Spy1", displayName = "Sticky Web", icon = "🕸️", tier = 1, basePrice = 5, volatility = 0.1 },
    Spy2 = { id = "Spy2", displayName = "Spider Leg", icon = "🕷️", tier = 2, basePrice = 28, volatility = 0.2 },
    Spy3 = { id = "Spy3", displayName = "Venom Sack", icon = "🧪", tier = 3, basePrice = 160, volatility = 0.5 },
    Spy4 = { id = "Spy4", displayName = "Widow's Gem", icon = "💎", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Chimpanzini_Bananini
    ChimpBan1 = { id = "ChimpBan1", displayName = "Discarded Skin", icon = "🍌", tier = 1, basePrice = 4, volatility = 0.1 },
    ChimpBan2 = { id = "ChimpBan2", displayName = "Bunch of Bananas", icon = "🍌", tier = 2, basePrice = 20, volatility = 0.2 },
    ChimpBan3 = { id = "ChimpBan3", displayName = "Monkey Wrench", icon = "🔧", tier = 3, basePrice = 130, volatility = 0.5 },
    ChimpBan4 = { id = "ChimpBan4", displayName = "King of the Jungle Crown", icon = "👑", tier = 4, basePrice = 900, volatility = 0.8 },
    
    -- Ballerino Lololo
    Dance1 = { id = "Dance1", displayName = "Sweaty Headband", icon = "💦", tier = 1, basePrice = 5, volatility = 0.1 },
    Dance2 = { id = "Dance2", displayName = "Worn Dance Shoes", icon = "👟", tier = 2, basePrice = 30, volatility = 0.2 },
    Dance3 = { id = "Dance3", displayName = "Silver Trophy", icon = "🥈", tier = 3, basePrice = 160, volatility = 0.5 },
    Dance4 = { id = "Dance4", displayName = "Golden Disco Ball", icon = "🪩", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Bambini_Crostini
    Toast1 = { id = "Toast1", displayName = "Bread Crust", icon = "🍞", tier = 1, basePrice = 4, volatility = 0.1 },
    Toast2 = { id = "Toast2", displayName = "Toasted Slice", icon = "🍞", tier = 2, basePrice = 25, volatility = 0.2 },
    Toast3 = { id = "Toast3", displayName = "Buttered Jam Toast", icon = "🍓", tier = 3, basePrice = 140, volatility = 0.5 },
    Toast4 = { id = "Toast4", displayName = "The Golden Loaf", icon = "🥖", tier = 4, basePrice = 900, volatility = 0.8 },

    -- Bandito_Bobritto
    Taco1 = { id = "Taco1", displayName = "Corn Shell", icon = "🌮", tier = 1, basePrice = 6, volatility = 0.1 },
    Taco2 = { id = "Taco2", displayName = "Spicy Burrito", icon = "🌯", tier = 2, basePrice = 35, volatility = 0.2 },
    Taco3 = { id = "Taco3", displayName = "Bandit Mask", icon = "🎭", tier = 3, basePrice = 180, volatility = 0.5 },
    Taco4 = { id = "Taco4", displayName = "Diamond Jalapeño", icon = "💎", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Blueberrinni_Octopusini
    BerryOcto1 = { id = "BerryOcto1", displayName = "Blue Ink Shard", icon = "🖋️", tier = 1, basePrice = 7, volatility = 0.1 },
    BerryOcto2 = { id = "BerryOcto2", displayName = "Frozen Blueberry", icon = "🫐", tier = 2, basePrice = 40, volatility = 0.2 },
    BerryOcto3 = { id = "BerryOcto3", displayName = "Suction Cup", icon = "🐙", tier = 3, basePrice = 210, volatility = 0.5 },
    BerryOcto4 = { id = "BerryOcto4", displayName = "Kraken Berry", icon = "🔱", tier = 4, basePrice = 1500, volatility = 0.8 },

    -- Bombardiro_Crocodilo
    CrocBomb1 = { id = "CrocBomb1", displayName = "Croc Tooth", icon = "🦷", tier = 1, basePrice = 8, volatility = 0.1 },
    CrocBomb2 = { id = "CrocBomb2", displayName = "Scaly Grenade", icon = "💣", tier = 2, basePrice = 45, volatility = 0.2 },
    CrocBomb3 = { id = "CrocBomb3", displayName = "Swamp Missile", icon = "🚀", tier = 3, basePrice = 220, volatility = 0.5 },
    CrocBomb4 = { id = "CrocBomb4", displayName = "Apex Detonator", icon = "🐊", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Bombombini_Gusini
    Goose1 = { id = "Goose1", displayName = "Loose Feather", icon = "🪶", tier = 1, basePrice = 4, volatility = 0.1 },
    Goose2 = { id = "Goose2", displayName = "Egg Bomb", icon = "🥚", tier = 2, basePrice = 25, volatility = 0.2 },
    Goose3 = { id = "Goose3", displayName = "Tactical Honk", icon = "📢", tier = 3, basePrice = 150, volatility = 0.5 },
    Goose4 = { id = "Goose4", displayName = "Golden Goose Egg", icon = "✨", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Boneca_Ambalabu
    Doll1 = { id = "Doll1", displayName = "Loose Thread", icon = "🧵", tier = 1, basePrice = 5, volatility = 0.1 },
    Doll2 = { id = "Doll2", displayName = "Porcelain Arm", icon = "🦴", tier = 2, basePrice = 30, volatility = 0.2 },
    Doll3 = { id = "Doll3", displayName = "Voodoo Pin", icon = "📍", tier = 3, basePrice = 170, volatility = 0.5 },
    Doll4 = { id = "Doll4", displayName = "Cursed Relic", icon = "🏺", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Brr_Brr_Patapim
    Brr1 = { id = "Brr1", displayName = "Ice Shaver", icon = "🍧", tier = 1, basePrice = 5, volatility = 0.1 },
    Brr2 = { id = "Brr2", displayName = "Frosty Mug", icon = "🍺", tier = 2, basePrice = 30, volatility = 0.2 },
    Brr3 = { id = "Brr3", displayName = "Blizzard Core", icon = "🌀", tier = 3, basePrice = 180, volatility = 0.5 },
    Brr4 = { id = "Brr4", displayName = "Zero Degree Orb", icon = "❄️", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Brri_Brri_Bicus_Dicus_Bombicus
    Bicus1 = { id = "Bicus1", displayName = "Magic Spark", icon = "✨", tier = 1, basePrice = 10, volatility = 0.2 },
    Bicus2 = { id = "Bicus2", displayName = "Ancient Scroll", icon = "📜", tier = 2, basePrice = 55, volatility = 0.3 },
    Bicus3 = { id = "Bicus3", displayName = "Wizard Staff", icon = "🪄", tier = 3, basePrice = 280, volatility = 0.5 },
    Bicus4 = { id = "Bicus4", displayName = "The Forbidden Spell", icon = "📖", tier = 4, basePrice = 2000, volatility = 0.9 },

    -- Burbaloni_Loliloli
    Bubble1 = { id = "Bubble1", displayName = "Soap Water", icon = "🧼", tier = 1, basePrice = 4, volatility = 0.1 },
    Bubble2 = { id = "Bubble2", displayName = "Pink Bubble", icon = "🫧", tier = 2, basePrice = 22, volatility = 0.2 },
    Bubble3 = { id = "Bubble3", displayName = "Giant Bubble Wand", icon = "🪄", tier = 3, basePrice = 130, volatility = 0.5 },
    Bubble4 = { id = "Bubble4", displayName = "The Eternal Bubble", icon = "🔮", tier = 4, basePrice = 900, volatility = 0.8 },

    -- Cacto Hipopotamo
    Cact1 = { id = "Cact1", displayName = "Cactus Needle", icon = "🌵", tier = 1, basePrice = 5, volatility = 0.1 },
    Cact2 = { id = "Cact2", displayName = "Desert Sand", icon = "🏜️", tier = 2, basePrice = 30, volatility = 0.2 },
    Cact3 = { id = "Cact3", displayName = "Hippo Tusk", icon = "🦷", tier = 3, basePrice = 160, volatility = 0.5 },
    Cact4 = { id = "Cact4", displayName = "Blooming Oasis", icon = "🌺", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Cappuccino_Assassino
    KillerCoffee1 = { id = "KillerCoffee1", displayName = "Coffee Bean", icon = "🫘", tier = 1, basePrice = 6, volatility = 0.1 },
    KillerCoffee2 = { id = "KillerCoffee2", displayName = "Spilled Milk", icon = "🥛", tier = 2, basePrice = 35, volatility = 0.2 },
    KillerCoffee3 = { id = "KillerCoffee3", displayName = "Dagger Spoon", icon = "🥄", tier = 3, basePrice = 190, volatility = 0.5 },
    KillerCoffee4 = { id = "KillerCoffee4", displayName = "The Poisoned Brew", icon = "☕", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Cavallo_Virtuoso
    Horse1 = { id = "Horse1", displayName = "Old Horseshoe", icon = "🧲", tier = 1, basePrice = 5, volatility = 0.1 },
    Horse2 = { id = "Horse2", displayName = "Violin Bow", icon = "🎻", tier = 2, basePrice = 35, volatility = 0.2 },
    Horse3 = { id = "Horse3", displayName = "Music Stand", icon = "🎼", tier = 3, basePrice = 170, volatility = 0.5 },
    Horse4 = { id = "Horse4", displayName = "Grand Stallion Piano", icon = "🎹", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Chef_Crabracadabra
    Crab1 = { id = "Crab1", displayName = "Crab Shell", icon = "🦀", tier = 1, basePrice = 6, volatility = 0.1 },
    Crab2 = { id = "Crab2", displayName = "Sharp Cleaver", icon = "🔪", tier = 2, basePrice = 40, volatility = 0.2 },
    Crab3 = { id = "Crab3", displayName = "Magic Spatula", icon = "🪄", tier = 3, basePrice = 200, volatility = 0.5 },
    Crab4 = { id = "Crab4", displayName = "The Master Recipe", icon = "📜", tier = 4, basePrice = 1500, volatility = 0.8 },

    -- Chicleteira Bicicleteira
    Bike1 = { id = "Bike1", displayName = "Bike Valve", icon = "🚲", tier = 1, basePrice = 5, volatility = 0.1 },
    Bike2 = { id = "Bike2", displayName = "Gum Wrapper", icon = "🍬", tier = 2, basePrice = 28, volatility = 0.2 },
    Bike3 = { id = "Bike3", displayName = "Rusty Chain", icon = "⛓️", tier = 3, basePrice = 150, volatility = 0.5 },
    Bike4 = { id = "Bike4", displayName = "Diamond Gear", icon = "⚙️", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Chimpanzini Spiderini
    ChimpSpy1 = { id = "ChimpSpy1", displayName = "Sticky Web", icon = "🕸️", tier = 1, basePrice = 7, volatility = 0.1 },
    ChimpSpy2 = { id = "ChimpSpy2", displayName = "Banana Peel Trap", icon = "🍌", tier = 2, basePrice = 40, volatility = 0.2 },
    ChimpSpy3 = { id = "ChimpSpy3", displayName = "8-Legged Suit", icon = "🕷️", tier = 3, basePrice = 220, volatility = 0.5 },
    ChimpSpy4 = { id = "ChimpSpy4", displayName = "Arachnid King", icon = "👑", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Cocofanto_Elefanto
    Elephant1 = { id = "Elephant1", displayName = "Peanut Shell", icon = "🥜", tier = 1, basePrice = 5, volatility = 0.1 },
    Elephant2 = { id = "Elephant2", displayName = "Ivory Scrap", icon = "🦴", tier = 2, basePrice = 30, volatility = 0.2 },
    Elephant3 = { id = "Elephant3", displayName = "Water Trunk", icon = "🚿", tier = 3, basePrice = 170, volatility = 0.5 },
    Elephant4 = { id = "Elephant4", displayName = "Ancient Mammoth Tusk", icon = "🐘", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Espresso Signora
    Signora1 = { id = "Signora1", displayName = "Sugar Packet", icon = "🧂", tier = 1, basePrice = 6, volatility = 0.1 },
    Signora2 = { id = "Signora2", displayName = "Milk Frother", icon = "🥛", tier = 2, basePrice = 35, volatility = 0.2 },
    Signora3 = { id = "Signora3", displayName = "Fancy Saucer", icon = "🍽️", tier = 3, basePrice = 190, volatility = 0.5 },
    Signora4 = { id = "Signora4", displayName = "The Queen's Roast", icon = "☕", tier = 4, basePrice = 1450, volatility = 0.8 },

    -- Fluri_flura
    Fluri1 = { id = "Fluri1", displayName = "Petal Shard", icon = "🌸", tier = 1, basePrice = 4, volatility = 0.1 },
    Fluri2 = { id = "Fluri2", displayName = "Flower Pot", icon = "🪴", tier = 2, basePrice = 25, volatility = 0.2 },
    Fluri3 = { id = "Fluri3", displayName = "Magic Nectar", icon = "🧪", tier = 3, basePrice = 140, volatility = 0.5 },
    Fluri4 = { id = "Fluri4", displayName = "Eternal Bloom", icon = "🌻", tier = 4, basePrice = 1000, volatility = 0.8 },

    -- Frigo_Camelo
    Camel1 = { id = "Camel1", displayName = "Desert Pebble", icon = "🪨", tier = 1, basePrice = 5, volatility = 0.1 },
    Camel2 = { id = "Camel2", displayName = "Water Canteen", icon = "🥤", tier = 2, basePrice = 32, volatility = 0.2 },
    Camel3 = { id = "Camel3", displayName = "Refrigerator Hump", icon = "🧊", tier = 3, basePrice = 180, volatility = 0.5 },
    Camel4 = { id = "Camel4", displayName = "Mirage Core", icon = "🏜️", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Gangster_Footera
    Gang1 = { id = "Gang1", displayName = "Lace Scrap", icon = "🧵", tier = 1, basePrice = 7, volatility = 0.1 },
    Gang2 = { id = "Gang2", displayName = "Gold Chain", icon = "⛓️", tier = 2, basePrice = 45, volatility = 0.3 },
    Gang3 = { id = "Gang3", displayName = "Sneaker Box", icon = "📦", tier = 3, basePrice = 220, volatility = 0.5 },
    Gang4 = { id = "Gang4", displayName = "The Godfather's Boot", icon = "👟", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Garama_and_Madundung
    Garama1 = { id = "Garama1", displayName = "Dusty Rock", icon = "🪨", tier = 1, basePrice = 6, volatility = 0.1 },
    Garama2 = { id = "Garama2", displayName = "Old Staff", icon = "🦯", tier = 2, basePrice = 38, volatility = 0.2 },
    Garama3 = { id = "Garama3", displayName = "Tribal Mask", icon = "👺", tier = 3, basePrice = 200, volatility = 0.5 },
    Garama4 = { id = "Garama4", displayName = "Ancient Totem", icon = "🗿", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Gattatino Neonino
    Neon1 = { id = "Neon1", displayName = "Flickering Bulb", icon = "💡", tier = 1, basePrice = 8, volatility = 0.1 },
    Neon2 = { id = "Neon2", displayName = "Glowing Wire", icon = "🔌", tier = 2, basePrice = 50, volatility = 0.2 },
    Neon3 = { id = "Neon3", displayName = "Neon Collar", icon = "🎀", tier = 3, basePrice = 240, volatility = 0.5 },
    Neon4 = { id = "Neon4", displayName = "Cyber Cat Core", icon = "⚡", tier = 4, basePrice = 1800, volatility = 0.8 },

    -- Gattatino_Nyanino
    Nyan1 = { id = "Nyan1", displayName = "Crumbly Cookie", icon = "🍪", tier = 1, basePrice = 5, volatility = 0.1 },
    Nyan2 = { id = "Nyan2", displayName = "Rainbow Dust", icon = "🌈", tier = 2, basePrice = 35, volatility = 0.2 },
    Nyan3 = { id = "Nyan3", displayName = "Space Jam", icon = "🍯", tier = 3, basePrice = 180, volatility = 0.5 },
    Nyan4 = { id = "Nyan4", displayName = "Cosmic Pop-Tart", icon = "🌌", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Girafa_Celestre
    Giraffe1 = { id = "Giraffe1", displayName = "Long Grass", icon = "🌱", tier = 1, basePrice = 5, volatility = 0.1 },
    Giraffe2 = { id = "Giraffe2", displayName = "Spotty Scarf", icon = "🧣", tier = 2, basePrice = 30, volatility = 0.2 },
    Giraffe3 = { id = "Giraffe3", displayName = "Star Telescope", icon = "🔭", tier = 3, basePrice = 170, volatility = 0.5 },
    Giraffe4 = { id = "Giraffe4", displayName = "Cloud Tower", icon = "☁️", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Glorbo_Fruttodrillo
    Glorbo1 = { id = "Glorbo1", displayName = "Fruit Pit", icon = "🍑", tier = 1, basePrice = 6, volatility = 0.1 },
    Glorbo2 = { id = "Glorbo2", displayName = "Dragon Scale", icon = "🛡️", tier = 2, basePrice = 40, volatility = 0.2 },
    Glorbo3 = { id = "Glorbo3", displayName = "Juicy Claw", icon = "🐾", tier = 3, basePrice = 210, volatility = 0.5 },
    Glorbo4 = { id = "Glorbo4", displayName = "Tropical Emperor", icon = "👑", tier = 4, basePrice = 1550, volatility = 0.8 },

    -- Gorillo Watermelondrillo
    Melon1 = { id = "Melon1", displayName = "Melon Seed", icon = "🌱", tier = 1, basePrice = 5, volatility = 0.1 },
    Melon2 = { id = "Melon2", displayName = "Green Rind", icon = "🍉", tier = 2, basePrice = 35, volatility = 0.2 },
    Melon3 = { id = "Melon3", displayName = "Gorilla Fist", icon = "👊", tier = 3, basePrice = 190, volatility = 0.5 },
    Melon4 = { id = "Melon4", displayName = "The Giant Watermelon", icon = "🍉", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Graipuss_Medussi
    Grai1 = { id = "Grai1", displayName = "Tentacle Scrap", icon = "🐙", tier = 1, basePrice = 6, volatility = 0.1 },
    Grai2 = { id = "Grai2", displayName = "Frozen Grape", icon = "🍇", tier = 2, basePrice = 38, volatility = 0.2 },
    Grai3 = { id = "Grai3", displayName = "Stone Eye", icon = "👁️", tier = 3, basePrice = 200, volatility = 0.5 },
    Grai4 = { id = "Grai4", displayName = "Medusa's Jellyfish", icon = "🐍", tier = 4, basePrice = 1500, volatility = 0.8 },

    -- La_Grande_Combinasion
    Combo1 = { id = "Combo1", displayName = "Small Cog", icon = "⚙️", tier = 1, basePrice = 8, volatility = 0.1 },
    Combo2 = { id = "Combo2", displayName = "Mixed Battery", icon = "🔋", tier = 2, basePrice = 50, volatility = 0.2 },
    Combo3 = { id = "Combo3", displayName = "Mechanical Heart", icon = "❤️", tier = 3, basePrice = 250, volatility = 0.5 },
    Combo4 = { id = "Combo4", displayName = "The Ultimate Engine", icon = "🚀", tier = 4, basePrice = 2000, volatility = 0.8 },

    -- La_Vacca_Saturno_Saturnita
    Cow1 = { id = "Cow1", displayName = "Milk Pail", icon = "🪣", tier = 1, basePrice = 5, volatility = 0.1 },
    Cow2 = { id = "Cow2", displayName = "Space Hay", icon = "🌾", tier = 2, basePrice = 32, volatility = 0.2 },
    Cow3 = { id = "Cow3", displayName = "Saturn's Ring", icon = "🪐", tier = 3, basePrice = 190, volatility = 0.5 },
    Cow4 = { id = "Cow4", displayName = "The Galactic Bovine", icon = "🐮", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Las Tralaleritas
    Trala1 = { id = "Trala1", displayName = "Sheet Music", icon = "📄", tier = 1, basePrice = 4, volatility = 0.1 },
    Trala2 = { id = "Trala2", displayName = "Silver Bell", icon = "🔔", tier = 2, basePrice = 28, volatility = 0.2 },
    Trala3 = { id = "Trala3", displayName = "Rhythm Sticks", icon = "🥁", tier = 3, basePrice = 150, volatility = 0.5 },
    Trala4 = { id = "Trala4", displayName = "The Golden Choir", icon = "🎶", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Las Vaquitas Saturnitas
    Vaqu1 = { id = "Vaqu1", displayName = "Mini Moon", icon = "🌑", tier = 1, basePrice = 6, volatility = 0.1 },
    Vaqu2 = { id = "Vaqu2", displayName = "Asteroid Cheese", icon = "🧀", tier = 2, basePrice = 38, volatility = 0.2 },
    Vaqu3 = { id = "Vaqu3", displayName = "Cosmic Bell", icon = "🔔", tier = 3, basePrice = 210, volatility = 0.5 },
    Vaqu4 = { id = "Vaqu4", displayName = "Star-Dust Udder", icon = "🌌", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Lionel_Cactuseli
    Messi1 = { id = "Messi1", displayName = "Football Scraps", icon = "⚽", tier = 1, basePrice = 7, volatility = 0.1 },
    Messi2 = { id = "Messi2", displayName = "Spiky Ball", icon = "🌵", tier = 2, basePrice = 45, volatility = 0.2 },
    Messi3 = { id = "Messi3", displayName = "Golden Boot", icon = "👟", tier = 3, basePrice = 250, volatility = 0.5 },
    Messi4 = { id = "Messi4", displayName = "World Cup Cactus", icon = "🏆", tier = 4, basePrice = 2000, volatility = 0.8 },

    -- Lirilì_Larilà
    Liri1 = { id = "Liri1", displayName = "Note Shard", icon = "🎵", tier = 1, basePrice = 5, volatility = 0.1 },
    Liri2 = { id = "Liri2", displayName = "Humming Box", icon = "📻", tier = 2, basePrice = 32, volatility = 0.2 },
    Liri3 = { id = "Liri3", displayName = "Echo Crystal", icon = "💎", tier = 3, basePrice = 180, volatility = 0.5 },
    Liri4 = { id = "Liri4", displayName = "Grand Symphony", icon = "🎻", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Los Crocodillitos
    SmallCroc1 = { id = "SmallCroc1", displayName = "Egg Shell", icon = "🥚", tier = 1, basePrice = 5, volatility = 0.1 },
    SmallCroc2 = { id = "SmallCroc2", displayName = "Baby Scale", icon = "🛡️", tier = 2, basePrice = 30, volatility = 0.2 },
    SmallCroc3 = { id = "SmallCroc3", displayName = "Swamp Toy", icon = "🧸", tier = 3, basePrice = 160, volatility = 0.5 },
    SmallCroc4 = { id = "SmallCroc4", displayName = "King of the Pond", icon = "👑", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Los_Tralaleritos
    Traler1 = { id = "Traler1", displayName = "Toy Flute", icon = "🪈", tier = 1, basePrice = 4, volatility = 0.1 },
    Traler2 = { id = "Traler2", displayName = "Small Drum", icon = "🥁", tier = 2, basePrice = 28, volatility = 0.2 },
    Traler3 = { id = "Traler3", displayName = "Music Box", icon = "📻", tier = 3, basePrice = 150, volatility = 0.5 },
    Traler4 = { id = "Traler4", displayName = "The Masterpiece", icon = "🎨", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Mat_teo
    Matteo1 = { id = "Matteo1", displayName = "Ink Pen", icon = "🖋️", tier = 1, basePrice = 6, volatility = 0.1 },
    Matteo2 = { id = "Matteo2", displayName = "Smart Glasses", icon = "👓", tier = 2, basePrice = 40, volatility = 0.2 },
    Matteo3 = { id = "Matteo3", displayName = "Strategy Board", icon = "📋", tier = 3, basePrice = 210, volatility = 0.5 },
    Matteo4 = { id = "Matteo4", displayName = "The Final Answer", icon = "🧠", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Mythic Lucky Block
    MythLuck1 = { id = "MythLuck1", displayName = "Silver Shard", icon = "✨", tier = 1, basePrice = 25, volatility = 0.3 },
    MythLuck2 = { id = "MythLuck2", displayName = "Purple Box", icon = "📦", tier = 2, basePrice = 120, volatility = 0.4 },
    MythLuck3 = { id = "MythLuck3", displayName = "Rare Key", icon = "🔑", tier = 3, basePrice = 600, volatility = 0.6 },
    MythLuck4 = { id = "MythLuck4", displayName = "Mythical Prize", icon = "💎", tier = 4, basePrice = 4000, volatility = 0.9 },

    -- Odin_Din_Din_Dun
    Odin1 = { id = "Odin1", displayName = "Ancient Nail", icon = "🔨", tier = 1, basePrice = 10, volatility = 0.2 },
    Odin2 = { id = "Odin2", displayName = "Viking Shield", icon = "🛡️", tier = 2, basePrice = 60, volatility = 0.3 },
    Odin3 = { id = "Odin3", displayName = "Mjolnir Fragment", icon = "⚡", tier = 3, basePrice = 350, volatility = 0.6 },
    Odin4 = { id = "Odin4", displayName = "The All-Father's Eye", icon = "👁️", tier = 4, basePrice = 2500, volatility = 0.9 },

    -- Orangutini_Ananassini
    Orang1 = { id = "Orang1", displayName = "Pineapple Top", icon = "🍍", tier = 1, basePrice = 5, volatility = 0.1 },
    Orang2 = { id = "Orang2", displayName = "Orange Peel", icon = "🍊", tier = 2, basePrice = 30, volatility = 0.2 },
    Orang3 = { id = "Orang3", displayName = "Jungle Juice", icon = "🍹", tier = 3, basePrice = 170, volatility = 0.5 },
    Orang4 = { id = "Orang4", displayName = "The Tropical King", icon = "🦍", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Orcalero Orcala
    Orca1 = { id = "Orca1", displayName = "Sea Shell", icon = "🐚", tier = 1, basePrice = 6, volatility = 0.1 },
    Orca2 = { id = "Orca2", displayName = "Whale Fin", icon = "🐋", tier = 2, basePrice = 40, volatility = 0.2 },
    Orca3 = { id = "Orca3", displayName = "Tidal Wave", icon = "🌊", tier = 3, basePrice = 220, volatility = 0.5 },
    Orca4 = { id = "Orca4", displayName = "The Deep Sea Pearl", icon = "⚪", tier = 4, basePrice = 1700, volatility = 0.8 },

    -- Pandaccini Bananini
    Panda1 = { id = "Panda1", displayName = "Bamboo Leaf", icon = "🍃", tier = 1, basePrice = 5, volatility = 0.1 },
    Panda2 = { id = "Panda2", displayName = "Banana Bread", icon = "🍞", tier = 2, basePrice = 35, volatility = 0.2 },
    Panda3 = { id = "Panda3", displayName = "Panda Paw", icon = "🐾", tier = 3, basePrice = 180, volatility = 0.5 },
    Panda4 = { id = "Panda4", displayName = "Zen Master's Banana", icon = "🧘", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Perochello_Lemonchello
    Lemon1 = { id = "Lemon1", displayName = "Lemon Slice", icon = "🍋", tier = 1, basePrice = 4, volatility = 0.1 },
    Lemon2 = { id = "Lemon2", displayName = "Yellow Squeeze", icon = "🥤", tier = 2, basePrice = 25, volatility = 0.2 },
    Lemon3 = { id = "Lemon3", displayName = "Zesty Spritz", icon = "🍸", tier = 3, basePrice = 140, volatility = 0.5 },
    Lemon4 = { id = "Lemon4", displayName = "The Golden Lemon", icon = "🍋", tier = 4, basePrice = 1000, volatility = 0.8 },

    -- Piccione Macchina
    Pigeon1 = { id = "Pigeon1", displayName = "Bird Seed", icon = "🌾", tier = 1, basePrice = 5, volatility = 0.1 },
    Pigeon2 = { id = "Pigeon2", displayName = "Iron Wing", icon = "⚙️", tier = 2, basePrice = 35, volatility = 0.2 },
    Pigeon3 = { id = "Pigeon3", displayName = "Pigeon Message", icon = "📜", tier = 3, basePrice = 190, volatility = 0.5 },
    Pigeon4 = { id = "Pigeon4", displayName = "The Cyber Dove", icon = "🕊️", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Pipi_Kiwi
    Kiwi1 = { id = "Kiwi1", displayName = "Kiwi Skin", icon = "🥝", tier = 1, basePrice = 5, volatility = 0.1 },
    Kiwi2 = { id = "Kiwi2", displayName = "Fuzzy Feather", icon = "🪶", tier = 2, basePrice = 30, volatility = 0.2 },
    Kiwi3 = { id = "Kiwi3", displayName = "Kiwi Egg", icon = "🥚", tier = 3, basePrice = 170, volatility = 0.5 },
    Kiwi4 = { id = "Kiwi4", displayName = "The Emerald Bird", icon = "🐦", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Pot Hotspot
    Pot1 = { id = "Pot1", displayName = "Clay Chunk", icon = "🧱", tier = 1, basePrice = 5, volatility = 0.1 },
    Pot2 = { id = "Pot2", displayName = "Stone Pot", icon = "🏺", tier = 2, basePrice = 35, volatility = 0.2 },
    Pot3 = { id = "Pot3", displayName = "Boiling Water", icon = "♨️", tier = 3, basePrice = 180, volatility = 0.5 },
    Pot4 = { id = "Pot4", displayName = "The Iron Cauldron", icon = "🥘", tier = 4, basePrice = 1350, volatility = 0.8 },

    -- Rhino_Toasterino
    ToastRhino1 = { id = "ToastRhino1", displayName = "Crumbs", icon = "🍞", tier = 1, basePrice = 6, volatility = 0.1 },
    ToastRhino2 = { id = "ToastRhino2", displayName = "Burnt Toast", icon = "🍞", tier = 2, basePrice = 35, volatility = 0.2 },
    ToastRhino3 = { id = "ToastRhino3", displayName = "Electric Horn", icon = "🦏", tier = 3, basePrice = 200, volatility = 0.5 },
    ToastRhino4 = { id = "ToastRhino4", displayName = "The Steel Rhino", icon = "🛡️", tier = 4, basePrice = 1500, volatility = 0.8 },

    -- Salamino Penguino
    Penguin1 = { id = "Penguin1", displayName = "Small Fish", icon = "🐟", tier = 1, basePrice = 5, volatility = 0.1 },
    Penguin2 = { id = "Penguin2", displayName = "Ice Pebble", icon = "🧊", tier = 2, basePrice = 32, volatility = 0.2 },
    Penguin3 = { id = "Penguin3", displayName = "Tuxedo Bow", icon = "🎀", tier = 3, basePrice = 180, volatility = 0.5 },
    Penguin4 = { id = "Penguin4", displayName = "King of the Arctic", icon = "👑", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Secret Lucky Block
    SecLuck1 = { id = "SecLuck1", displayName = "Dusty Box", icon = "📦", tier = 1, basePrice = 20, volatility = 0.3 },
    SecLuck2 = { id = "SecLuck2", displayName = "Hidden Note", icon = "📜", tier = 2, basePrice = 100, volatility = 0.4 },
    SecLuck3 = { id = "SecLuck3", displayName = "Encrypted Key", icon = "🔑", tier = 3, basePrice = 500, volatility = 0.6 },
    SecLuck4 = { id = "SecLuck4", displayName = "Classified Prize", icon = "📁", tier = 4, basePrice = 3500, volatility = 1.0 },

    -- Noobini_Pizzanini
    PizzaCrust = { id = "PizzaCrust", displayName = "Burnt Pizza Crust", icon = "🍕", tier = 1, basePrice = 5, volatility = 0.1 },
    ColdPizza = { id = "ColdPizza", displayName = "Cold Pizza Slice", icon = "🍕", tier = 2, basePrice = 30, volatility = 0.2 },
    DeepDish = { id = "DeepDish", displayName = "Deep Dish Pizza", icon = "🥧", tier = 3, basePrice = 160, volatility = 0.5 },
    PartyPizza = { id = "PartyPizza", displayName = "Ultimate Party Pizza", icon = "🎉", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Spioniro Golubiro
    Spion1 = { id = "Spion1", displayName = "Mini Camera", icon = "📷", tier = 1, basePrice = 7, volatility = 0.1 },
    Spion2 = { id = "Spion2", displayName = "Stealth Cloak", icon = "👤", tier = 2, basePrice = 45, volatility = 0.3 },
    Spion3 = { id = "Spion3", displayName = "Binoculars", icon = "🔭", tier = 3, basePrice = 230, volatility = 0.5 },
    Spion4 = { id = "Spion4", displayName = "The Master Spy", icon = "🕴️", tier = 4, basePrice = 1700, volatility = 0.8 },

    -- Strawberrelli Flamingelli
    Flam1 = { id = "Flam1", displayName = "Pink Feather", icon = "🪶", tier = 1, basePrice = 5, volatility = 0.1 },
    Flam2 = { id = "Flam2", displayName = "Sweet Berry", icon = "🍓", tier = 2, basePrice = 30, volatility = 0.2 },
    Flam3 = { id = "Flam3", displayName = "Flamingo Stand", icon = "🦩", tier = 3, basePrice = 170, volatility = 0.5 },
    Flam4 = { id = "Flam4", displayName = "The Tropical Queen", icon = "👑", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Svinina_Bombardino
    PigBomb1 = { id = "PigBomb1", displayName = "Pig Tail", icon = "🐖", tier = 1, basePrice = 6, volatility = 0.1 },
    PigBomb2 = { id = "PigBomb2", displayName = "Ham Casing", icon = "🍖", tier = 2, basePrice = 35, volatility = 0.2 },
    PigBomb3 = { id = "PigBomb3", displayName = "Bacon Bomb", icon = "🥓", tier = 3, basePrice = 200, volatility = 0.5 },
    PigBomb4 = { id = "PigBomb4", displayName = "The Atomic Porker", icon = "🐷", tier = 4, basePrice = 1500, volatility = 0.8 },

    -- Ta_Ta_Ta_Ta_Sahur
    Sahur1 = { id = "Sahur1", displayName = "Iron Scraps", icon = "⛓️", tier = 1, basePrice = 8, volatility = 0.1 },
    Sahur2 = { id = "Sahur2", displayName = "Brass Trumpet", icon = "🎺", tier = 2, basePrice = 45, volatility = 0.2 },
    Sahur3 = { id = "Sahur3", displayName = "Marching Drum", icon = "🥁", tier = 3, basePrice = 220, volatility = 0.5 },
    Sahur4 = { id = "Sahur4", displayName = "The Grand Parade", icon = "🎪", tier = 4, basePrice = 1700, volatility = 0.8 },

    -- Talpa_Di_Fero
    Mole1 = { id = "Mole1", displayName = "Dirt Clump", icon = "🪨", tier = 1, basePrice = 5, volatility = 0.1 },
    Mole2 = { id = "Mole2", displayName = "Iron Claw", icon = "🐾", tier = 2, basePrice = 35, volatility = 0.2 },
    Mole3 = { id = "Mole3", displayName = "Tunneler", icon = "🚇", tier = 3, basePrice = 190, volatility = 0.5 },
    Mole4 = { id = "Mole4", displayName = "The Steel Driller", icon = "🚜", tier = 4, basePrice = 1450, volatility = 0.8 },

    -- Tigrilini Watermelini
    TigMelon1 = { id = "TigMelon1", displayName = "Tiger Stripe", icon = "🦓", tier = 1, basePrice = 6, volatility = 0.1 },
    TigMelon2 = { id = "TigMelon2", displayName = "Melon Slice", icon = "🍉", tier = 2, basePrice = 40, volatility = 0.2 },
    TigMelon3 = { id = "TigMelon3", displayName = "Roaring Fruit", icon = "🦁", tier = 3, basePrice = 230, volatility = 0.5 },
    TigMelon4 = { id = "TigMelon4", displayName = "The Jungle Melon", icon = "👑", tier = 4, basePrice = 1800, volatility = 0.8 },

    -- Tigroligre Frutonni
    Ligre1 = { id = "Ligre1", displayName = "Claw Scrap", icon = "🐾", tier = 1, basePrice = 7, volatility = 0.1 },
    Ligre2 = { id = "Ligre2", displayName = "Juicy Hide", icon = "🧥", tier = 2, basePrice = 45, volatility = 0.2 },
    Ligre3 = { id = "Ligre3", displayName = "Fruit Armor", icon = "🛡️", tier = 3, basePrice = 250, volatility = 0.5 },
    Ligre4 = { id = "Ligre4", displayName = "The Hybrid King", icon = "🦁", tier = 4, basePrice = 1900, volatility = 0.8 },

    -- Tim_Cheese
    Cheese1 = { id = "Cheese1", displayName = "Yellow Crumb", icon = "🧀", tier = 1, basePrice = 4, volatility = 0.1 },
    Cheese2 = { id = "Cheese2", displayName = "Wedge of Swiss", icon = "🧀", tier = 2, basePrice = 25, volatility = 0.2 },
    Cheese3 = { id = "Cheese3", displayName = "Melting Fondue", icon = "🫕", tier = 3, basePrice = 140, volatility = 0.5 },
    Cheese4 = { id = "Cheese4", displayName = "The Golden Wheel", icon = "🌕", tier = 4, basePrice = 1000, volatility = 0.8 },

    -- Torrtuginni Dragonfrutini
    Dragon1 = { id = "Dragon1", displayName = "Pink Scale", icon = "🛡️", tier = 1, basePrice = 7, volatility = 0.1 },
    Dragon2 = { id = "Dragon2", displayName = "Dragon Fruit", icon = "🌵", tier = 2, basePrice = 45, volatility = 0.2 },
    Dragon3 = { id = "Dragon3", displayName = "Turtle Shell", icon = "🐢", tier = 3, basePrice = 240, volatility = 0.5 },
    Dragon4 = { id = "Dragon4", displayName = "The Mythic Dragon", icon = "🐲", tier = 4, basePrice = 1900, volatility = 0.8 },

    -- Tralalero_Tralala
    Tra1 = { id = "Tra1", displayName = "Single Note", icon = "🎵", tier = 1, basePrice = 4, volatility = 0.1 },
    Tra2 = { id = "Tra2", displayName = "Music Sheet", icon = "📄", tier = 2, basePrice = 25, volatility = 0.2 },
    Tra3 = { id = "Tra3", displayName = "Microphone", icon = "🎤", tier = 3, basePrice = 150, volatility = 0.5 },
    Tra4 = { id = "Tra4", displayName = "Grand Piano", icon = "🎹", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Trenostruzzo_Turbo_3000
    Train1 = { id = "Train1", displayName = "Iron Bolt", icon = "🔩", tier = 1, basePrice = 10, volatility = 0.1 },
    Train2 = { id = "Train2", displayName = "Coal Lump", icon = "🪨", tier = 2, basePrice = 55, volatility = 0.2 },
    Train3 = { id = "Train3", displayName = "Turbo Engine", icon = "⚙️", tier = 3, basePrice = 300, volatility = 0.5 },
    Train4 = { id = "Train4", displayName = "The Bullet Ostrich", icon = "🚄", tier = 4, basePrice = 2200, volatility = 0.8 },

    -- Tric_Trac_Baraboom
    Boom1 = { id = "Boom1", displayName = "Fused Wire", icon = "🧵", tier = 1, basePrice = 6, volatility = 0.1 },
    Boom2 = { id = "Boom2", displayName = "Gunpowder", icon = "🧂", tier = 2, basePrice = 40, volatility = 0.3 },
    Boom3 = { id = "Boom3", displayName = "Heavy Crate", icon = "📦", tier = 3, basePrice = 220, volatility = 0.5 },
    Boom4 = { id = "Boom4", displayName = "The Grand Finale", icon = "🎆", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Trippi_Troppi
    Trip1 = { id = "Trip1", displayName = "Old Shoe", icon = "👟", tier = 1, basePrice = 5, volatility = 0.1 },
    Trip2 = { id = "Trip2", displayName = "Energy Bar", icon = "🍫", tier = 2, basePrice = 30, volatility = 0.2 },
    Trip3 = { id = "Trip3", displayName = "Hiking Staff", icon = "🦯", tier = 3, basePrice = 180, volatility = 0.5 },
    Trip4 = { id = "Trip4", displayName = "World Traveler", icon = "🌍", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Trulimero_Trulicina
    Truli1 = { id = "Truli1", displayName = "Small Shard", icon = "💎", tier = 1, basePrice = 5, volatility = 0.1 },
    Truli2 = { id = "Truli2", displayName = "Glow Stone", icon = "🪨", tier = 2, basePrice = 35, volatility = 0.2 },
    Truli3 = { id = "Truli3", displayName = "Magic Charm", icon = "🧿", tier = 3, basePrice = 190, volatility = 0.5 },
    Truli4 = { id = "Truli4", displayName = "The Divine Spark", icon = "✨", tier = 4, basePrice = 1450, volatility = 0.8 },

    -- Tung_Tung_Tung_Sahur
    Tung1 = { id = "Tung1", displayName = "Steel Plate", icon = "🧱", tier = 1, basePrice = 8, volatility = 0.1 },
    Tung2 = { id = "Tung2", displayName = "Heavy Hammer", icon = "🔨", tier = 2, basePrice = 50, volatility = 0.2 },
    Tung3 = { id = "Tung3", displayName = "Drum Kit", icon = "🥁", tier = 3, basePrice = 260, volatility = 0.5 },
    Tung4 = { id = "Tung4", displayName = "The Sahur Master", icon = "👑", tier = 4, basePrice = 2000, volatility = 0.8 },

    -- Unclito_Samito
    Sam1 = { id = "Sam1", displayName = "Red Stripe", icon = "🧣", tier = 1, basePrice = 6, volatility = 0.1 },
    Sam2 = { id = "Sam2", displayName = "Blue Star", icon = "⭐", tier = 2, basePrice = 40, volatility = 0.2 },
    Sam3 = { id = "Sam3", displayName = "Top Hat", icon = "🎩", tier = 3, basePrice = 220, volatility = 0.5 },
    Sam4 = { id = "Sam4", displayName = "The Patriot's Pride", icon = "🇺🇸", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Zibra Zubra Zibralini
    Zebra1 = { id = "Zebra1", displayName = "Black Stripe", icon = "🦓", tier = 1, basePrice = 5, volatility = 0.1 },
    Zebra2 = { id = "Zebra2", displayName = "White Stripe", icon = "⚪", tier = 2, basePrice = 30, volatility = 0.2 },
    Zebra3 = { id = "Zebra3", displayName = "Savannah Grass", icon = "🌾", tier = 3, basePrice = 170, volatility = 0.5 },
    Zebra4 = { id = "Zebra4", displayName = "The Prism Zebra", icon = "🌈", tier = 4, basePrice = 1300, volatility = 0.8 },
}

--------------------------------------------------------------------------------
-- BRAINROT → ITEM MAPPING (Hver model har sin egen række)
--------------------------------------------------------------------------------

ItemConfig.BrainrotItems = {
    ["Avocadini Guffo"] = { tier1 = "Guac1", tier2 = "Guac2", tier3 = "Guac3", tier4 = "Guac4" },
    ["Ballerina_Cappuccina"] = { tier1 = "Cap1", tier2 = "Cap2", tier3 = "Cap3", tier4 = "Cap4" },
    ["Ballerino Lololo"] = { tier1 = "Dance1", tier2 = "Dance2", tier3 = "Dance3", tier4 = "Dance4" },
    ["Bambini_Crostini"] = { tier1 = "Toast1", tier2 = "Toast2", tier3 = "Toast3", tier4 = "Toast4" },
    ["Bananita_Dolphinita"] = { tier1 = "BanDolph1", tier2 = "BanDolph2", tier3 = "BanDolph3", tier4 = "BanDolph4" },
    ["Bandito_Bobritto"] = { tier1 = "Taco1", tier2 = "Taco2", tier3 = "Taco3", tier4 = "Taco4" },
    ["Blueberrinni_Octopusini"] = { tier1 = "BerryOcto1", tier2 = "BerryOcto2", tier3 = "BerryOcto3", tier4 = "BerryOcto4" },
    ["Bombardiro_Crocodilo"] = { tier1 = "CrocBomb1", tier2 = "CrocBomb2", tier3 = "CrocBomb3", tier4 = "CrocBomb4" },
    ["Bombombini_Gusini"] = { tier1 = "Goose1", tier2 = "Goose2", tier3 = "Goose3", tier4 = "Goose4" },
    ["Boneca_Ambalabu"] = { tier1 = "Doll1", tier2 = "Doll2", tier3 = "Doll3", tier4 = "Doll4" },
    ["Brainrot God Lucky Block"] = { tier1 = "GodLuck1", tier2 = "GodLuck2", tier3 = "GodLuck3", tier4 = "GodLuck4" },
    ["Brr_Brr_Patapim"] = { tier1 = "Brr1", tier2 = "Brr2", tier3 = "Brr3", tier4 = "Brr4" },
    ["Brri_Brri_Bicus_Dicus_Bombicus"] = { tier1 = "Bicus1", tier2 = "Bicus2", tier3 = "Bicus3", tier4 = "Bicus4" },
    ["Burbaloni_Loliloli"] = { tier1 = "Bubble1", tier2 = "Bubble2", tier3 = "Bubble3", tier4 = "Bubble4" },
    ["Cacto Hipopotamo"] = { tier1 = "Cact1", tier2 = "Cact2", tier3 = "Cact3", tier4 = "Cact4" },
    ["Cappuccino_Assassino"] = { tier1 = "KillerCoffee1", tier2 = "KillerCoffee2", tier3 = "KillerCoffee3", tier4 = "KillerCoffee4" },
    ["Cavallo_Virtuoso"] = { tier1 = "Horse1", tier2 = "Horse2", tier3 = "Horse3", tier4 = "Horse4" },
    ["Chef_Crabracadabra"] = { tier1 = "Crab1", tier2 = "Crab2", tier3 = "Crab3", tier4 = "Crab4" },
    ["Chicleteira Bicicleteira"] = { tier1 = "Bike1", tier2 = "Bike2", tier3 = "Bike3", tier4 = "Bike4" },
    ["Chimpanzini Spiderini"] = { tier1 = "ChimpSpy1", tier2 = "ChimpSpy2", tier3 = "ChimpSpy3", tier4 = "ChimpSpy4" },
    ["Chimpanzini_Bananini"] = { tier1 = "ChimpBan1", tier2 = "ChimpBan2", tier3 = "ChimpBan3", tier4 = "ChimpBan4" },
    ["Cocofanto_Elefanto"] = { tier1 = "Elephant1", tier2 = "Elephant2", tier3 = "Elephant3", tier4 = "Elephant4" },
    ["Espresso Signora"] = { tier1 = "Signora1", tier2 = "Signora2", tier3 = "Signora3", tier4 = "Signora4" },
    ["Fluri_flura"] = { tier1 = "Fluri1", tier2 = "Fluri2", tier3 = "Fluri3", tier4 = "Fluri4" },
    ["Frigo_Camelo"] = { tier1 = "Camel1", tier2 = "Camel2", tier3 = "Camel3", tier4 = "Camel4" },
    ["Gangster_Footera"] = { tier1 = "Gang1", tier2 = "Gang2", tier3 = "Gang3", tier4 = "Gang4" },
    ["Garama_and_Madundung"] = { tier1 = "Garama1", tier2 = "Garama2", tier3 = "Garama3", tier4 = "Garama4" },
    ["Gattatino Neonino"] = { tier1 = "Neon1", tier2 = "Neon2", tier3 = "Neon3", tier4 = "Neon4" },
    ["Gattatino_Nyanino"] = { tier1 = "Nyan1", tier2 = "Nyan2", tier3 = "Nyan3", tier4 = "Nyan4" },
    ["Girafa_Celestre"] = { tier1 = "Giraffe1", tier2 = "Giraffe2", tier3 = "Giraffe3", tier4 = "Giraffe4" },
    ["Glorbo_Fruttodrillo"] = { tier1 = "Glorbo1", tier2 = "Glorbo2", tier3 = "Glorbo3", tier4 = "Glorbo4" },
    ["Gorillo Watermelondrillo"] = { tier1 = "Melon1", tier2 = "Melon2", tier3 = "Melon3", tier4 = "Melon4" },
    ["Graipuss_Medussi"] = { tier1 = "Grai1", tier2 = "Grai2", tier3 = "Grai3", tier4 = "Grai4" },
    ["La_Grande_Combinasion"] = { tier1 = "Combo1", tier2 = "Combo2", tier3 = "Combo3", tier4 = "Combo4" },
    ["La_Vacca_Saturno_Saturnita"] = { tier1 = "Cow1", tier2 = "Cow2", tier3 = "Cow3", tier4 = "Cow4" },
    ["Las Tralaleritas"] = { tier1 = "Trala1", tier2 = "Trala2", tier3 = "Trala3", tier4 = "Trala4" },
    ["Las Vaquitas Saturnitas"] = { tier1 = "Vaqu1", tier2 = "Vaqu2", tier3 = "Vaqu3", tier4 = "Vaqu4" },
    ["Lionel_Cactuseli"] = { tier1 = "Messi1", tier2 = "Messi2", tier3 = "Messi3", tier4 = "Messi4" },
    ["Lirilì_Larilà"] = { tier1 = "Liri1", tier2 = "Liri2", tier3 = "Liri3", tier4 = "Liri4" },
    ["Los Crocodillitos"] = { tier1 = "SmallCroc1", tier2 = "SmallCroc2", tier3 = "SmallCroc3", tier4 = "SmallCroc4" },
    ["Los_Tralaleritos"] = { tier1 = "Traler1", tier2 = "Traler2", tier3 = "Traler3", tier4 = "Traler4" },
    ["Mat_teo"] = { tier1 = "Matteo1", tier2 = "Matteo2", tier3 = "Matteo3", tier4 = "Matteo4" },
    ["Mythic Lucky Block"] = { tier1 = "MythLuck1", tier2 = "MythLuck2", tier3 = "MythLuck3", tier4 = "MythLuck4" },
    ["Noobini_Pizzanini"] = { tier1 = "PizzaCrust", tier2 = "ColdPizza", tier3 = "DeepDish", tier4 = "PartyPizza" },
    ["Nuclearo Dinossauro"] = { tier1 = "NukeDino1", tier2 = "NukeDino2", tier3 = "NukeDino3", tier4 = "NukeDino4" },
    ["Odin_Din_Din_Dun"] = { tier1 = "Odin1", tier2 = "Odin2", tier3 = "Odin3", tier4 = "Odin4" },
    ["Orangutini_Ananassini"] = { tier1 = "Orang1", tier2 = "Orang2", tier3 = "Orang3", tier4 = "Orang4" },
    ["Orcalero Orcala"] = { tier1 = "Orca1", tier2 = "Orca2", tier3 = "Orca3", tier4 = "Orca4" },
    ["Pandaccini Bananini"] = { tier1 = "Panda1", tier2 = "Panda2", tier3 = "Panda3", tier4 = "Panda4" },
    ["Perochello_Lemonchello"] = { tier1 = "Lemon1", tier2 = "Lemon2", tier3 = "Lemon3", tier4 = "Lemon4" },
    ["Piccione Macchina"] = { tier1 = "Pigeon1", tier2 = "Pigeon2", tier3 = "Pigeon3", tier4 = "Pigeon4" },
    ["Pipi_Kiwi"] = { tier1 = "Kiwi1", tier2 = "Kiwi2", tier3 = "Kiwi3", tier4 = "Kiwi4" },
    ["Pot Hotspot"] = { tier1 = "Pot1", tier2 = "Pot2", tier3 = "Pot3", tier4 = "Pot4" },
    ["Rhino_Toasterino"] = { tier1 = "ToastRhino1", tier2 = "ToastRhino2", tier3 = "ToastRhino3", tier4 = "ToastRhino4" },
    ["Salamino Penguino"] = { tier1 = "Penguin1", tier2 = "Penguin2", tier3 = "Penguin3", tier4 = "Penguin4" },
    ["Sammyni_Spyderini"] = { tier1 = "Spy1", tier2 = "Spy2", tier3 = "Spy3", tier4 = "Spy4" },
    ["Secret Lucky Block"] = { tier1 = "SecLuck1", tier2 = "SecLuck2", tier3 = "SecLuck3", tier4 = "SecLuck4" },
    ["Spioniro Golubiro"] = { tier1 = "Spion1", tier2 = "Spion2", tier3 = "Spion3", tier4 = "Spion4" },
    ["Statutino Libertino"] = { tier1 = "Lib1", tier2 = "Lib2", tier3 = "Lib3", tier4 = "Lib4" },
    ["Strawberrelli Flamingelli"] = { tier1 = "Flam1", tier2 = "Flam2", tier3 = "Flam3", tier4 = "Flam4" },
    ["Svinina_Bombardino"] = { tier1 = "PigBomb1", tier2 = "PigBomb2", tier3 = "PigBomb3", tier4 = "PigBomb4" },
    ["Ta_Ta_Ta_Ta_Sahur"] = { tier1 = "Sahur1", tier2 = "Sahur2", tier3 = "Sahur3", tier4 = "Sahur4" },
    ["Talpa_Di_Fero"] = { tier1 = "Mole1", tier2 = "Mole2", tier3 = "Mole3", tier4 = "Mole4" },
    ["Tigrilini Watermelini"] = { tier1 = "TigMelon1", tier2 = "TigMelon2", tier3 = "TigMelon3", tier4 = "TigMelon4" },
    ["Tigroligre Frutonni"] = { tier1 = "Ligre1", tier2 = "Ligre2", tier3 = "Ligre3", tier4 = "Ligre4" },
    ["Tim_Cheese"] = { tier1 = "Cheese1", tier2 = "Cheese2", tier3 = "Cheese3", tier4 = "Cheese4" },
    ["Torrtuginni Dragonfrutini"] = { tier1 = "Dragon1", tier2 = "Dragon2", tier3 = "Dragon3", tier4 = "Dragon4" },
    ["Tralalero_Tralala"] = { tier1 = "Tra1", tier2 = "Tra2", tier3 = "Tra3", tier4 = "Tra4" },
    ["Trenostruzzo_Turbo_3000"] = { tier1 = "Train1", tier2 = "Train2", tier3 = "Train3", tier4 = "Train4" },
    ["Tric_Trac_Baraboom"] = { tier1 = "Boom1", tier2 = "Boom2", tier3 = "Boom3", tier4 = "Boom4" },
    ["Trippi_Troppi"] = { tier1 = "Trip1", tier2 = "Trip2", tier3 = "Trip3", tier4 = "Trip4" },
    ["Trulimero_Trulicina"] = { tier1 = "Truli1", tier2 = "Truli2", tier3 = "Truli3", tier4 = "Truli4" },
    ["Tung_Tung_Tung_Sahur"] = { tier1 = "Tung1", tier2 = "Tung2", tier3 = "Tung3", tier4 = "Tung4" },
    ["Unclito_Samito"] = { tier1 = "Sam1", tier2 = "Sam2", tier3 = "Sam3", tier4 = "Sam4" },
    ["Zibra Zubra Zibralini"] = { tier1 = "Zebra1", tier2 = "Zebra2", tier3 = "Zebra3", tier4 = "Zebra4" },
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

function ItemConfig.GetItem(itemId: string): ItemDefinition?
    return ItemConfig.Items[itemId]
end

function ItemConfig.GetProductions(modelName: string, ownedCount: number): {{itemId: string, rate: number}}
    -- Finder rækken baseret på præcis modelnavn
    local mapping = ItemConfig.BrainrotItems[modelName]
    if not mapping then return {} end
    
    local productions = {}
    local thresholds = ItemConfig.MilestoneThresholds
    local rates = ItemConfig.ProductionRates
    
    if ownedCount >= thresholds.tier1 then table.insert(productions, {itemId = mapping.tier1, rate = rates.tier1}) end
    if ownedCount >= thresholds.tier2 then table.insert(productions, {itemId = mapping.tier2, rate = rates.tier2}) end
    if ownedCount >= thresholds.tier3 then table.insert(productions, {itemId = mapping.tier3, rate = rates.tier3}) end
    if ownedCount >= thresholds.tier4 then table.insert(productions, {itemId = mapping.tier4, rate = rates.tier4}) end
    
    return productions
end

--[[
    Determines the stock market Sector for a brainrot based on its name.
    Replaces the old hardcoded Category system.
]]
function ItemConfig.GetSector(modelName: string): string
    local name = string.lower(modelName)
    
    local SECTORS = {
        Food = {"avocado", "pizza", "burrito", "coffee", "cheese", "cap", "signora", "lemon", "toast", "crostini", "guac", "berry", "crab", "glorbo", "melon", "fruit", "pineapple", "strawber"},
        Animals = {"chimp", "panda", "giraffe", "croc", "pig", "zebra", "orca", "whale", "dolphin", "octopus", "goose", "horse", "kiwi", "lion", "tiger", "penguin", "flamingo", "mole", "spider", "spyder"},
        Entertainment = {"dance", "music", "trala", "sahur", "symphony", "virtuoso", "bell", "choir", "rhythm", "drum", "trumpet", "marching", "parade", "lololo", "larila"},
        Mystic = {"god", "odin", "mythic", "lucky", "relic", "artifact", "ancient", "dragon", "kraken", "forbidden", "spell", "magic", "secret", "divine", "bicus", "truli", "bubble"},
        Tech = {"neon", "cyber", "machine", "hybrid", "combined", "drone", "turbo", "bullet", "engine", "battery", "neon", "cyber", "volt", "light", "circuit", "train", "combo", "mat_teo"},
        Action = {"bombard", "assassin", "gangster", "bandit", "crocbomb", "boom", "nuke", "atomic", "spy", "stealth", "binoculars", "camera", "spion", "detonator", "missile", "grenade", "trip", "matteo"},
    }
    
    for sector, keywords in pairs(SECTORS) do
        for _, keyword in ipairs(keywords) do
            if string.find(name, keyword) then
                return sector
            end
        end
    end
    
    return "Neutral" -- Fallback
end

return ItemConfig