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

ItemConfig.ProductionSettings = {
    tier1 = { rate = 2, volatility = 0.05 },
    tier2 = { rate = 10, volatility = 0.15 },
    tier3 = { rate = 45, volatility = 0.40 },
    tier4 = { rate = 180, volatility = 0.80 },
}

ItemConfig.MilestoneThresholds = {
    tier1 = 1,
    tier2 = 10,
    tier3 = 50,
    tier4 = 100,
}

-- V3: Selective Mode speed scaling (+2% per level)
ItemConfig.SpeedExponent = 1.02

--------------------------------------------------------------------------------
-- ITEM DEFINITIONS (The massive list of 4 tiers per model)
--------------------------------------------------------------------------------

ItemConfig.Items = {
    -- Avocadini Guffo
    Guac1 = { id = "Guac1", shortId = 1, displayName = "Brown Pit", icon = "🥑", tier = 1, basePrice = 5, volatility = 0.05 },
    Guac2 = { id = "Guac2", shortId = 2, displayName = "Sliced Avocado", icon = "🥑", tier = 2, basePrice = 25, volatility = 0.15 },
    Guac3 = { id = "Guac3", shortId = 3, displayName = "Fresh Guacamole", icon = "🥣", tier = 3, basePrice = 150, volatility = 0.4 },
    Guac4 = { id = "Guac4", shortId = 4, displayName = "Golden Avocado", icon = "✨", tier = 4, basePrice = 1000, volatility = 0.8 },

    -- Ballerina_Cappuccina
    Cap1 = { id = "Cap1", shortId = 5, displayName = "Empty Cup", icon = "☕", tier = 1, basePrice = 6, volatility = 0.05 },
    Cap2 = { id = "Cap2", shortId = 6, displayName = "Cold Latte", icon = "☕", tier = 2, basePrice = 30, volatility = 0.15 },
    Cap3 = { id = "Cap3", shortId = 7, displayName = "Foamy Cappuccino", icon = "☕", tier = 3, basePrice = 180, volatility = 0.4 },
    Cap4 = { id = "Cap4", shortId = 8, displayName = "Elite Espresso", icon = "👑", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Bananita_Dolphinita
    BanDolph1 = { id = "BanDolph1", shortId = 9, displayName = "Banana Peel", icon = "🍌", tier = 1, basePrice = 4, volatility = 0.05 },
    BanDolph2 = { id = "BanDolph2", shortId = 10, displayName = "Frozen Banana", icon = "❄️", tier = 2, basePrice = 22, volatility = 0.15 },
    BanDolph3 = { id = "BanDolph3", shortId = 11, displayName = "Banana Split", icon = "🍨", tier = 3, basePrice = 140, volatility = 0.4 },
    BanDolph4 = { id = "BanDolph4", shortId = 12, displayName = "Dolphin Figurine", icon = "🐬", tier = 4, basePrice = 950, volatility = 0.8 },

    -- Brainrot God Lucky Block
    GodLuck1 = { id = "GodLuck1", shortId = 13, displayName = "Lucky Shard", icon = "🍀", tier = 1, basePrice = 50, volatility = 0.05 },
    GodLuck2 = { id = "GodLuck2", shortId = 14, displayName = "Mystery Cube", icon = "📦", tier = 2, basePrice = 250, volatility = 0.15 },
    GodLuck3 = { id = "GodLuck3", shortId = 15, displayName = "Jackpot Token", icon = "🎰", tier = 3, basePrice = 1200, volatility = 0.4 },
    GodLuck4 = { id = "GodLuck4", shortId = 16, displayName = "Godly Artifact", icon = "🔱", tier = 4, basePrice = 8000, volatility = 0.8 },

    -- Nuclearo Dinossauro
    NukeDino1 = { id = "NukeDino1", shortId = 17, displayName = "Radioactive Bone", icon = "🦴", tier = 1, basePrice = 40, volatility = 0.05 },
    NukeDino2 = { id = "NukeDino2", shortId = 18, displayName = "Uranium Egg", icon = "🥚", tier = 2, basePrice = 200, volatility = 0.15 },
    NukeDino3 = { id = "NukeDino3", shortId = 19, displayName = "Plasma Core", icon = "☢️", tier = 3, basePrice = 1000, volatility = 0.4 },
    NukeDino4 = { id = "NukeDino4", shortId = 20, displayName = "Atomic Tyrant Eye", icon = "👁️", tier = 4, basePrice = 6500, volatility = 0.8 },

    -- Statutino Libertino
    Lib1 = { id = "Lib1", shortId = 21, displayName = "Copper Plate", icon = "🧱", tier = 1, basePrice = 8, volatility = 0.05 },
    Lib2 = { id = "Lib2", shortId = 22, displayName = "Rusty Torch", icon = "🔦", tier = 2, basePrice = 45, volatility = 0.15 },
    Lib3 = { id = "Lib3", shortId = 23, displayName = "Liberty Crown", icon = "🗽", tier = 3, basePrice = 250, volatility = 0.4 },
    Lib4 = { id = "Lib4", shortId = 24, displayName = "Golden Freedom Statue", icon = "⚖️", tier = 4, basePrice = 1800, volatility = 0.8 },

    -- Sammyni_Spyderini
    Spy1 = { id = "Spy1", shortId = 25, displayName = "Sticky Web", icon = "🕸️", tier = 1, basePrice = 5, volatility = 0.05 },
    Spy2 = { id = "Spy2", shortId = 26, displayName = "Spider Leg", icon = "🕷️", tier = 2, basePrice = 28, volatility = 0.15 },
    Spy3 = { id = "Spy3", shortId = 27, displayName = "Venom Sack", icon = "🧪", tier = 3, basePrice = 160, volatility = 0.4 },
    Spy4 = { id = "Spy4", shortId = 28, displayName = "Widow's Gem", icon = "💎", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Chimpanzini_Bananini
    ChimpBan1 = { id = "ChimpBan1", shortId = 29, displayName = "Discarded Skin", icon = "🍌", tier = 1, basePrice = 4, volatility = 0.05 },
    ChimpBan2 = { id = "ChimpBan2", shortId = 30, displayName = "Bunch of Bananas", icon = "🍌", tier = 2, basePrice = 20, volatility = 0.15 },
    ChimpBan3 = { id = "ChimpBan3", shortId = 31, displayName = "Monkey Wrench", icon = "🔧", tier = 3, basePrice = 130, volatility = 0.4 },
    ChimpBan4 = { id = "ChimpBan4", shortId = 32, displayName = "King of the Jungle Crown", icon = "👑", tier = 4, basePrice = 900, volatility = 0.8 },
    
    -- Ballerino Lololo
    Dance1 = { id = "Dance1", shortId = 33, displayName = "Sweaty Headband", icon = "💦", tier = 1, basePrice = 5, volatility = 0.05 },
    Dance2 = { id = "Dance2", shortId = 34, displayName = "Worn Dance Shoes", icon = "👟", tier = 2, basePrice = 30, volatility = 0.15 },
    Dance3 = { id = "Dance3", shortId = 35, displayName = "Silver Trophy", icon = "🥈", tier = 3, basePrice = 160, volatility = 0.4 },
    Dance4 = { id = "Dance4", shortId = 36, displayName = "Golden Disco Ball", icon = "🪩", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Bambini_Crostini
    Toast1 = { id = "Toast1", shortId = 37, displayName = "Bread Crust", icon = "🍞", tier = 1, basePrice = 4, volatility = 0.05 },
    Toast2 = { id = "Toast2", shortId = 38, displayName = "Toasted Slice", icon = "🍞", tier = 2, basePrice = 25, volatility = 0.15 },
    Toast3 = { id = "Toast3", shortId = 39, displayName = "Buttered Jam Toast", icon = "🍓", tier = 3, basePrice = 140, volatility = 0.4 },
    Toast4 = { id = "Toast4", shortId = 40, displayName = "The Golden Loaf", icon = "🥖", tier = 4, basePrice = 900, volatility = 0.8 },

    -- Bandito_Bobritto
    Taco1 = { id = "Taco1", shortId = 41, displayName = "Corn Shell", icon = "🌮", tier = 1, basePrice = 6, volatility = 0.05 },
    Taco2 = { id = "Taco2", shortId = 42, displayName = "Spicy Burrito", icon = "🌯", tier = 2, basePrice = 35, volatility = 0.15 },
    Taco3 = { id = "Taco3", shortId = 43, displayName = "Bandit Mask", icon = "🎭", tier = 3, basePrice = 180, volatility = 0.4 },
    Taco4 = { id = "Taco4", shortId = 44, displayName = "Diamond Jalapeño", icon = "💎", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Blueberrinni_Octopusini
    BerryOcto1 = { id = "BerryOcto1", shortId = 45, displayName = "Blue Ink Shard", icon = "🖋️", tier = 1, basePrice = 7, volatility = 0.05 },
    BerryOcto2 = { id = "BerryOcto2", shortId = 46, displayName = "Frozen Blueberry", icon = "🫐", tier = 2, basePrice = 40, volatility = 0.15 },
    BerryOcto3 = { id = "BerryOcto3", shortId = 47, displayName = "Suction Cup", icon = "🐙", tier = 3, basePrice = 210, volatility = 0.4 },
    BerryOcto4 = { id = "BerryOcto4", shortId = 48, displayName = "Kraken Berry", icon = "🔱", tier = 4, basePrice = 1500, volatility = 0.8 },

    -- Bombardiro_Crocodilo
    CrocBomb1 = { id = "CrocBomb1", shortId = 49, displayName = "Croc Tooth", icon = "🦷", tier = 1, basePrice = 8, volatility = 0.05 },
    CrocBomb2 = { id = "CrocBomb2", shortId = 50, displayName = "Scaly Grenade", icon = "💣", tier = 2, basePrice = 45, volatility = 0.15 },
    CrocBomb3 = { id = "CrocBomb3", shortId = 51, displayName = "Swamp Missile", icon = "🚀", tier = 3, basePrice = 220, volatility = 0.4 },
    CrocBomb4 = { id = "CrocBomb4", shortId = 52, displayName = "Apex Detonator", icon = "🐊", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Bombombini_Gusini
    Goose1 = { id = "Goose1", shortId = 53, displayName = "Loose Feather", icon = "🪶", tier = 1, basePrice = 4, volatility = 0.05 },
    Goose2 = { id = "Goose2", shortId = 54, displayName = "Egg Bomb", icon = "🥚", tier = 2, basePrice = 25, volatility = 0.15 },
    Goose3 = { id = "Goose3", shortId = 55, displayName = "Tactical Honk", icon = "📢", tier = 3, basePrice = 150, volatility = 0.4 },
    Goose4 = { id = "Goose4", shortId = 56, displayName = "Golden Goose Egg", icon = "✨", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Boneca_Ambalabu
    Doll1 = { id = "Doll1", shortId = 57, displayName = "Loose Thread", icon = "🧵", tier = 1, basePrice = 5, volatility = 0.05 },
    Doll2 = { id = "Doll2", shortId = 58, displayName = "Porcelain Arm", icon = "🦴", tier = 2, basePrice = 30, volatility = 0.15 },
    Doll3 = { id = "Doll3", shortId = 59, displayName = "Voodoo Pin", icon = "📍", tier = 3, basePrice = 170, volatility = 0.4 },
    Doll4 = { id = "Doll4", shortId = 60, displayName = "Cursed Relic", icon = "🏺", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Brr_Brr_Patapim
    Brr1 = { id = "Brr1", shortId = 61, displayName = "Ice Shaver", icon = "🍧", tier = 1, basePrice = 5, volatility = 0.05 },
    Brr2 = { id = "Brr2", shortId = 62, displayName = "Frosty Mug", icon = "🍺", tier = 2, basePrice = 30, volatility = 0.15 },
    Brr3 = { id = "Brr3", shortId = 63, displayName = "Blizzard Core", icon = "🌀", tier = 3, basePrice = 180, volatility = 0.4 },
    Brr4 = { id = "Brr4", shortId = 64, displayName = "Zero Degree Orb", icon = "❄️", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Brri_Brri_Bicus_Dicus_Bombicus
    Bicus1 = { id = "Bicus1", shortId = 65, displayName = "Magic Spark", icon = "✨", tier = 1, basePrice = 10, volatility = 0.05 },
    Bicus2 = { id = "Bicus2", shortId = 66, displayName = "Ancient Scroll", icon = "📜", tier = 2, basePrice = 55, volatility = 0.15 },
    Bicus3 = { id = "Bicus3", shortId = 67, displayName = "Wizard Staff", icon = "🪄", tier = 3, basePrice = 280, volatility = 0.4 },
    Bicus4 = { id = "Bicus4", shortId = 68, displayName = "The Forbidden Spell", icon = "📖", tier = 4, basePrice = 2000, volatility = 0.8 },

    -- Burbaloni_Loliloli
    Bubble1 = { id = "Bubble1", shortId = 69, displayName = "Soap Water", icon = "🧼", tier = 1, basePrice = 4, volatility = 0.05 },
    Bubble2 = { id = "Bubble2", shortId = 70, displayName = "Pink Bubble", icon = "🫧", tier = 2, basePrice = 22, volatility = 0.15 },
    Bubble3 = { id = "Bubble3", shortId = 71, displayName = "Giant Bubble Wand", icon = "🪄", tier = 3, basePrice = 130, volatility = 0.4 },
    Bubble4 = { id = "Bubble4", shortId = 72, displayName = "The Eternal Bubble", icon = "🔮", tier = 4, basePrice = 900, volatility = 0.8 },

    -- Cacto Hipopotamo
    Cact1 = { id = "Cact1", shortId = 73, displayName = "Cactus Needle", icon = "🌵", tier = 1, basePrice = 5, volatility = 0.05 },
    Cact2 = { id = "Cact2", shortId = 74, displayName = "Desert Sand", icon = "🏜️", tier = 2, basePrice = 30, volatility = 0.15 },
    Cact3 = { id = "Cact3", shortId = 75, displayName = "Hippo Tusk", icon = "🦷", tier = 3, basePrice = 160, volatility = 0.4 },
    Cact4 = { id = "Cact4", shortId = 76, displayName = "Blooming Oasis", icon = "🌺", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Cappuccino_Assassino
    KillerCoffee1 = { id = "KillerCoffee1", shortId = 77, displayName = "Coffee Bean", icon = "🫘", tier = 1, basePrice = 6, volatility = 0.05 },
    KillerCoffee2 = { id = "KillerCoffee2", shortId = 78, displayName = "Spilled Milk", icon = "🥛", tier = 2, basePrice = 35, volatility = 0.15 },
    KillerCoffee3 = { id = "KillerCoffee3", shortId = 79, displayName = "Dagger Spoon", icon = "🥄", tier = 3, basePrice = 190, volatility = 0.4 },
    KillerCoffee4 = { id = "KillerCoffee4", shortId = 80, displayName = "The Poisoned Brew", icon = "☕", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Cavallo_Virtuoso
    Horse1 = { id = "Horse1", shortId = 81, displayName = "Old Horseshoe", icon = "🧲", tier = 1, basePrice = 5, volatility = 0.05 },
    Horse2 = { id = "Horse2", shortId = 82, displayName = "Violin Bow", icon = "🎻", tier = 2, basePrice = 35, volatility = 0.15 },
    Horse3 = { id = "Horse3", shortId = 83, displayName = "Music Stand", icon = "🎼", tier = 3, basePrice = 170, volatility = 0.4 },
    Horse4 = { id = "Horse4", shortId = 84, displayName = "Grand Stallion Piano", icon = "🎹", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Chef_Crabracadabra
    Crab1 = { id = "Crab1", shortId = 85, displayName = "Crab Shell", icon = "🦀", tier = 1, basePrice = 6, volatility = 0.05 },
    Crab2 = { id = "Crab2", shortId = 86, displayName = "Sharp Cleaver", icon = "🔪", tier = 2, basePrice = 40, volatility = 0.15 },
    Crab3 = { id = "Crab3", shortId = 87, displayName = "Magic Spatula", icon = "🪄", tier = 3, basePrice = 200, volatility = 0.4 },
    Crab4 = { id = "Crab4", shortId = 88, displayName = "The Master Recipe", icon = "📜", tier = 4, basePrice = 1500, volatility = 0.8 },

    -- Chicleteira Bicicleteira
    Bike1 = { id = "Bike1", shortId = 89, displayName = "Bike Valve", icon = "🚲", tier = 1, basePrice = 5, volatility = 0.05 },
    Bike2 = { id = "Bike2", shortId = 90, displayName = "Gum Wrapper", icon = "🍬", tier = 2, basePrice = 28, volatility = 0.15 },
    Bike3 = { id = "Bike3", shortId = 91, displayName = "Rusty Chain", icon = "⛓️", tier = 3, basePrice = 150, volatility = 0.4 },
    Bike4 = { id = "Bike4", shortId = 92, displayName = "Diamond Gear", icon = "⚙️", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Chimpanzini Spiderini
    ChimpSpy1 = { id = "ChimpSpy1", shortId = 93, displayName = "Sticky Web", icon = "🕸️", tier = 1, basePrice = 7, volatility = 0.05 },
    ChimpSpy2 = { id = "ChimpSpy2", shortId = 94, displayName = "Banana Peel Trap", icon = "🍌", tier = 2, basePrice = 40, volatility = 0.15 },
    ChimpSpy3 = { id = "ChimpSpy3", shortId = 95, displayName = "8-Legged Suit", icon = "🕷️", tier = 3, basePrice = 220, volatility = 0.4 },
    ChimpSpy4 = { id = "ChimpSpy4", shortId = 96, displayName = "Arachnid King", icon = "👑", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Cocofanto_Elefanto
    Elephant1 = { id = "Elephant1", shortId = 97, displayName = "Peanut Shell", icon = "🥜", tier = 1, basePrice = 5, volatility = 0.05 },
    Elephant2 = { id = "Elephant2", shortId = 98, displayName = "Ivory Scrap", icon = "🦴", tier = 2, basePrice = 30, volatility = 0.15 },
    Elephant3 = { id = "Elephant3", shortId = 99, displayName = "Water Trunk", icon = "🚿", tier = 3, basePrice = 170, volatility = 0.4 },
    Elephant4 = { id = "Elephant4", shortId = 100, displayName = "Ancient Mammoth Tusk", icon = "🐘", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Espresso Signora
    Signora1 = { id = "Signora1", shortId = 101, displayName = "Sugar Packet", icon = "🧂", tier = 1, basePrice = 6, volatility = 0.05 },
    Signora2 = { id = "Signora2", shortId = 102, displayName = "Milk Frother", icon = "🥛", tier = 2, basePrice = 35, volatility = 0.15 },
    Signora3 = { id = "Signora3", shortId = 103, displayName = "Fancy Saucer", icon = "🍽️", tier = 3, basePrice = 190, volatility = 0.4 },
    Signora4 = { id = "Signora4", shortId = 104, displayName = "The Queen's Roast", icon = "☕", tier = 4, basePrice = 1450, volatility = 0.8 },

    -- Fluri_flura
    Fluri1 = { id = "Fluri1", shortId = 105, displayName = "Petal Shard", icon = "🌸", tier = 1, basePrice = 4, volatility = 0.05 },
    Fluri2 = { id = "Fluri2", shortId = 106, displayName = "Flower Pot", icon = "🪴", tier = 2, basePrice = 25, volatility = 0.15 },
    Fluri3 = { id = "Fluri3", shortId = 107, displayName = "Magic Nectar", icon = "🧪", tier = 3, basePrice = 140, volatility = 0.4 },
    Fluri4 = { id = "Fluri4", shortId = 108, displayName = "Eternal Bloom", icon = "🌻", tier = 4, basePrice = 1000, volatility = 0.8 },

    -- Frigo_Camelo
    Camel1 = { id = "Camel1", shortId = 109, displayName = "Desert Pebble", icon = "🪨", tier = 1, basePrice = 5, volatility = 0.05 },
    Camel2 = { id = "Camel2", shortId = 110, displayName = "Water Canteen", icon = "🥤", tier = 2, basePrice = 32, volatility = 0.15 },
    Camel3 = { id = "Camel3", shortId = 111, displayName = "Refrigerator Hump", icon = "🧊", tier = 3, basePrice = 180, volatility = 0.4 },
    Camel4 = { id = "Camel4", shortId = 112, displayName = "Mirage Core", icon = "🏜️", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Gangster_Footera
    Gang1 = { id = "Gang1", shortId = 113, displayName = "Lace Scrap", icon = "🧵", tier = 1, basePrice = 7, volatility = 0.05 },
    Gang2 = { id = "Gang2", shortId = 114, displayName = "Gold Chain", icon = "⛓️", tier = 2, basePrice = 45, volatility = 0.15 },
    Gang3 = { id = "Gang3", shortId = 115, displayName = "Sneaker Box", icon = "📦", tier = 3, basePrice = 220, volatility = 0.4 },
    Gang4 = { id = "Gang4", shortId = 116, displayName = "The Godfather's Boot", icon = "👟", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Garama_and_Madundung
    Garama1 = { id = "Garama1", shortId = 117, displayName = "Dusty Rock", icon = "🪨", tier = 1, basePrice = 6, volatility = 0.05 },
    Garama2 = { id = "Garama2", shortId = 118, displayName = "Old Staff", icon = "🦯", tier = 2, basePrice = 38, volatility = 0.15 },
    Garama3 = { id = "Garama3", shortId = 119, displayName = "Tribal Mask", icon = "👺", tier = 3, basePrice = 200, volatility = 0.4 },
    Garama4 = { id = "Garama4", shortId = 120, displayName = "Ancient Totem", icon = "🗿", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Gattatino Neonino
    Neon1 = { id = "Neon1", shortId = 121, displayName = "Flickering Bulb", icon = "💡", tier = 1, basePrice = 8, volatility = 0.05 },
    Neon2 = { id = "Neon2", shortId = 122, displayName = "Glowing Wire", icon = "🔌", tier = 2, basePrice = 50, volatility = 0.15 },
    Neon3 = { id = "Neon3", shortId = 123, displayName = "Neon Collar", icon = "🎀", tier = 3, basePrice = 240, volatility = 0.4 },
    Neon4 = { id = "Neon4", shortId = 124, displayName = "Cyber Cat Core", icon = "⚡", tier = 4, basePrice = 1800, volatility = 0.8 },

    -- Gattatino_Nyanino
    Nyan1 = { id = "Nyan1", shortId = 125, displayName = "Crumbly Cookie", icon = "🍪", tier = 1, basePrice = 5, volatility = 0.05 },
    Nyan2 = { id = "Nyan2", shortId = 126, displayName = "Rainbow Dust", icon = "🌈", tier = 2, basePrice = 35, volatility = 0.15 },
    Nyan3 = { id = "Nyan3", shortId = 127, displayName = "Space Jam", icon = "🍯", tier = 3, basePrice = 180, volatility = 0.4 },
    Nyan4 = { id = "Nyan4", shortId = 128, displayName = "Cosmic Pop-Tart", icon = "🌌", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Girafa_Celestre
    Giraffe1 = { id = "Giraffe1", shortId = 129, displayName = "Long Grass", icon = "🌱", tier = 1, basePrice = 5, volatility = 0.05 },
    Giraffe2 = { id = "Giraffe2", shortId = 130, displayName = "Spotty Scarf", icon = "🧣", tier = 2, basePrice = 30, volatility = 0.15 },
    Giraffe3 = { id = "Giraffe3", shortId = 131, displayName = "Star Telescope", icon = "🔭", tier = 3, basePrice = 170, volatility = 0.4 },
    Giraffe4 = { id = "Giraffe4", shortId = 132, displayName = "Cloud Tower", icon = "☁️", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Glorbo_Fruttodrillo
    Glorbo1 = { id = "Glorbo1", shortId = 133, displayName = "Fruit Pit", icon = "🍑", tier = 1, basePrice = 6, volatility = 0.05 },
    Glorbo2 = { id = "Glorbo2", shortId = 134, displayName = "Dragon Scale", icon = "🛡️", tier = 2, basePrice = 40, volatility = 0.15 },
    Glorbo3 = { id = "Glorbo3", shortId = 135, displayName = "Juicy Claw", icon = "🐾", tier = 3, basePrice = 210, volatility = 0.4 },
    Glorbo4 = { id = "Glorbo4", shortId = 136, displayName = "Tropical Emperor", icon = "👑", tier = 4, basePrice = 1550, volatility = 0.8 },

    -- Gorillo Watermelondrillo
    Melon1 = { id = "Melon1", shortId = 137, displayName = "Melon Seed", icon = "🌱", tier = 1, basePrice = 5, volatility = 0.05 },
    Melon2 = { id = "Melon2", shortId = 138, displayName = "Green Rind", icon = "🍉", tier = 2, basePrice = 35, volatility = 0.15 },
    Melon3 = { id = "Melon3", shortId = 139, displayName = "Gorilla Fist", icon = "👊", tier = 3, basePrice = 190, volatility = 0.4 },
    Melon4 = { id = "Melon4", shortId = 140, displayName = "The Giant Watermelon", icon = "🍉", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Graipuss_Medussi
    Grai1 = { id = "Grai1", shortId = 141, displayName = "Tentacle Scrap", icon = "🐙", tier = 1, basePrice = 6, volatility = 0.05 },
    Grai2 = { id = "Grai2", shortId = 142, displayName = "Frozen Grape", icon = "🍇", tier = 2, basePrice = 38, volatility = 0.15 },
    Grai3 = { id = "Grai3", shortId = 143, displayName = "Stone Eye", icon = "👁️", tier = 3, basePrice = 200, volatility = 0.4 },
    Grai4 = { id = "Grai4", shortId = 144, displayName = "Medusa's Jellyfish", icon = "🐍", tier = 4, basePrice = 1500, volatility = 0.8 },

    -- La_Grande_Combinasion
    Combo1 = { id = "Combo1", shortId = 145, displayName = "Small Cog", icon = "⚙️", tier = 1, basePrice = 8, volatility = 0.05 },
    Combo2 = { id = "Combo2", shortId = 146, displayName = "Mixed Battery", icon = "🔋", tier = 2, basePrice = 50, volatility = 0.15 },
    Combo3 = { id = "Combo3", shortId = 147, displayName = "Mechanical Heart", icon = "❤️", tier = 3, basePrice = 250, volatility = 0.4 },
    Combo4 = { id = "Combo4", shortId = 148, displayName = "The Ultimate Engine", icon = "🚀", tier = 4, basePrice = 2000, volatility = 0.8 },

    -- La_Vacca_Saturno_Saturnita
    Cow1 = { id = "Cow1", shortId = 149, displayName = "Milk Pail", icon = "🪣", tier = 1, basePrice = 5, volatility = 0.05 },
    Cow2 = { id = "Cow2", shortId = 150, displayName = "Space Hay", icon = "🌾", tier = 2, basePrice = 32, volatility = 0.15 },
    Cow3 = { id = "Cow3", shortId = 151, displayName = "Saturn's Ring", icon = "🪐", tier = 3, basePrice = 190, volatility = 0.4 },
    Cow4 = { id = "Cow4", shortId = 152, displayName = "The Galactic Bovine", icon = "🐮", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Las Tralaleritas
    Trala1 = { id = "Trala1", shortId = 153, displayName = "Sheet Music", icon = "📄", tier = 1, basePrice = 4, volatility = 0.05 },
    Trala2 = { id = "Trala2", shortId = 154, displayName = "Silver Bell", icon = "🔔", tier = 2, basePrice = 28, volatility = 0.15 },
    Trala3 = { id = "Trala3", shortId = 155, displayName = "Rhythm Sticks", icon = "🥁", tier = 3, basePrice = 150, volatility = 0.4 },
    Trala4 = { id = "Trala4", shortId = 156, displayName = "The Golden Choir", icon = "🎶", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Las Vaquitas Saturnitas
    Vaqu1 = { id = "Vaqu1", shortId = 157, displayName = "Mini Moon", icon = "🌑", tier = 1, basePrice = 6, volatility = 0.05 },
    Vaqu2 = { id = "Vaqu2", shortId = 158, displayName = "Asteroid Cheese", icon = "🧀", tier = 2, basePrice = 38, volatility = 0.15 },
    Vaqu3 = { id = "Vaqu3", shortId = 159, displayName = "Cosmic Bell", icon = "🔔", tier = 3, basePrice = 210, volatility = 0.4 },
    Vaqu4 = { id = "Vaqu4", shortId = 160, displayName = "Star-Dust Udder", icon = "🌌", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Lionel_Cactuseli
    Messi1 = { id = "Messi1", shortId = 161, displayName = "Football Scraps", icon = "⚽", tier = 1, basePrice = 7, volatility = 0.05 },
    Messi2 = { id = "Messi2", shortId = 162, displayName = "Spiky Ball", icon = "🌵", tier = 2, basePrice = 45, volatility = 0.15 },
    Messi3 = { id = "Messi3", shortId = 163, displayName = "Golden Boot", icon = "👟", tier = 3, basePrice = 250, volatility = 0.4 },
    Messi4 = { id = "Messi4", shortId = 164, displayName = "World Cup Cactus", icon = "🏆", tier = 4, basePrice = 2000, volatility = 0.8 },

    -- Lirilì_Larilà
    Liri1 = { id = "Liri1", shortId = 165, displayName = "Note Shard", icon = "🎵", tier = 1, basePrice = 5, volatility = 0.05 },
    Liri2 = { id = "Liri2", shortId = 166, displayName = "Humming Box", icon = "📻", tier = 2, basePrice = 32, volatility = 0.15 },
    Liri3 = { id = "Liri3", shortId = 167, displayName = "Echo Crystal", icon = "💎", tier = 3, basePrice = 180, volatility = 0.4 },
    Liri4 = { id = "Liri4", shortId = 168, displayName = "Grand Symphony", icon = "🎻", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Los Crocodillitos
    SmallCroc1 = { id = "SmallCroc1", shortId = 169, displayName = "Egg Shell", icon = "🥚", tier = 1, basePrice = 5, volatility = 0.05 },
    SmallCroc2 = { id = "SmallCroc2", shortId = 170, displayName = "Baby Scale", icon = "🛡️", tier = 2, basePrice = 30, volatility = 0.15 },
    SmallCroc3 = { id = "SmallCroc3", shortId = 171, displayName = "Swamp Toy", icon = "🧸", tier = 3, basePrice = 160, volatility = 0.4 },
    SmallCroc4 = { id = "SmallCroc4", shortId = 172, displayName = "King of the Pond", icon = "👑", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Los_Tralaleritos
    Traler1 = { id = "Traler1", shortId = 173, displayName = "Toy Flute", icon = "🪈", tier = 1, basePrice = 4, volatility = 0.05 },
    Traler2 = { id = "Traler2", shortId = 174, displayName = "Small Drum", icon = "🥁", tier = 2, basePrice = 28, volatility = 0.15 },
    Traler3 = { id = "Traler3", shortId = 175, displayName = "Music Box", icon = "📻", tier = 3, basePrice = 150, volatility = 0.4 },
    Traler4 = { id = "Traler4", shortId = 176, displayName = "The Masterpiece", icon = "🎨", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Mat_teo
    Matteo1 = { id = "Matteo1", shortId = 177, displayName = "Ink Pen", icon = "🖋️", tier = 1, basePrice = 6, volatility = 0.05 },
    Matteo2 = { id = "Matteo2", shortId = 178, displayName = "Smart Glasses", icon = "👓", tier = 2, basePrice = 40, volatility = 0.15 },
    Matteo3 = { id = "Matteo3", shortId = 179, displayName = "Strategy Board", icon = "📋", tier = 3, basePrice = 210, volatility = 0.4 },
    Matteo4 = { id = "Matteo4", shortId = 180, displayName = "The Final Answer", icon = "🧠", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Mythic Lucky Block
    MythLuck1 = { id = "MythLuck1", shortId = 181, displayName = "Silver Shard", icon = "✨", tier = 1, basePrice = 25, volatility = 0.05 },
    MythLuck2 = { id = "MythLuck2", shortId = 182, displayName = "Purple Box", icon = "📦", tier = 2, basePrice = 120, volatility = 0.15 },
    MythLuck3 = { id = "MythLuck3", shortId = 183, displayName = "Rare Key", icon = "🔑", tier = 3, basePrice = 600, volatility = 0.4 },
    MythLuck4 = { id = "MythLuck4", shortId = 184, displayName = "Mythical Prize", icon = "💎", tier = 4, basePrice = 4000, volatility = 0.8 },

    -- Odin_Din_Din_Dun
    Odin1 = { id = "Odin1", shortId = 185, displayName = "Ancient Nail", icon = "🔨", tier = 1, basePrice = 10, volatility = 0.05 },
    Odin2 = { id = "Odin2", shortId = 186, displayName = "Viking Shield", icon = "🛡️", tier = 2, basePrice = 60, volatility = 0.15 },
    Odin3 = { id = "Odin3", shortId = 187, displayName = "Mjolnir Fragment", icon = "⚡", tier = 3, basePrice = 350, volatility = 0.4 },
    Odin4 = { id = "Odin4", shortId = 188, displayName = "The All-Father's Eye", icon = "👁️", tier = 4, basePrice = 2500, volatility = 0.8 },

    -- Orangutini_Ananassini
    Orang1 = { id = "Orang1", shortId = 189, displayName = "Pineapple Top", icon = "🍍", tier = 1, basePrice = 5, volatility = 0.05 },
    Orang2 = { id = "Orang2", shortId = 190, displayName = "Orange Peel", icon = "🍊", tier = 2, basePrice = 30, volatility = 0.15 },
    Orang3 = { id = "Orang3", shortId = 191, displayName = "Jungle Juice", icon = "🍹", tier = 3, basePrice = 170, volatility = 0.4 },
    Orang4 = { id = "Orang4", shortId = 192, displayName = "The Tropical King", icon = "🦍", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Orcalero Orcala
    Orca1 = { id = "Orca1", shortId = 193, displayName = "Sea Shell", icon = "🐚", tier = 1, basePrice = 6, volatility = 0.05 },
    Orca2 = { id = "Orca2", shortId = 194, displayName = "Whale Fin", icon = "🐋", tier = 2, basePrice = 40, volatility = 0.15 },
    Orca3 = { id = "Orca3", shortId = 195, displayName = "Tidal Wave", icon = "🌊", tier = 3, basePrice = 220, volatility = 0.4 },
    Orca4 = { id = "Orca4", shortId = 196, displayName = "The Deep Sea Pearl", icon = "⚪", tier = 4, basePrice = 1700, volatility = 0.8 },

    -- Pandaccini Bananini
    Panda1 = { id = "Panda1", shortId = 197, displayName = "Bamboo Leaf", icon = "🍃", tier = 1, basePrice = 5, volatility = 0.05 },
    Panda2 = { id = "Panda2", shortId = 198, displayName = "Banana Bread", icon = "🍞", tier = 2, basePrice = 35, volatility = 0.15 },
    Panda3 = { id = "Panda3", shortId = 199, displayName = "Panda Paw", icon = "🐾", tier = 3, basePrice = 180, volatility = 0.4 },
    Panda4 = { id = "Panda4", shortId = 200, displayName = "Zen Master's Banana", icon = "🧘", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Perochello_Lemonchello
    Lemon1 = { id = "Lemon1", shortId = 201, displayName = "Lemon Slice", icon = "🍋", tier = 1, basePrice = 4, volatility = 0.05 },
    Lemon2 = { id = "Lemon2", shortId = 202, displayName = "Yellow Squeeze", icon = "🥤", tier = 2, basePrice = 25, volatility = 0.15 },
    Lemon3 = { id = "Lemon3", shortId = 203, displayName = "Zesty Spritz", icon = "🍸", tier = 3, basePrice = 140, volatility = 0.4 },
    Lemon4 = { id = "Lemon4", shortId = 204, displayName = "The Golden Lemon", icon = "🍋", tier = 4, basePrice = 1000, volatility = 0.8 },

    -- Piccione Macchina
    Pigeon1 = { id = "Pigeon1", shortId = 205, displayName = "Bird Seed", icon = "🌾", tier = 1, basePrice = 5, volatility = 0.05 },
    Pigeon2 = { id = "Pigeon2", shortId = 206, displayName = "Iron Wing", icon = "⚙️", tier = 2, basePrice = 35, volatility = 0.15 },
    Pigeon3 = { id = "Pigeon3", shortId = 207, displayName = "Pigeon Message", icon = "📜", tier = 3, basePrice = 190, volatility = 0.4 },
    Pigeon4 = { id = "Pigeon4", shortId = 208, displayName = "The Cyber Dove", icon = "🕊️", tier = 4, basePrice = 1400, volatility = 0.8 },

    -- Pipi_Kiwi
    Kiwi1 = { id = "Kiwi1", shortId = 209, displayName = "Kiwi Skin", icon = "🥝", tier = 1, basePrice = 5, volatility = 0.05 },
    Kiwi2 = { id = "Kiwi2", shortId = 210, displayName = "Fuzzy Feather", icon = "🪶", tier = 2, basePrice = 30, volatility = 0.15 },
    Kiwi3 = { id = "Kiwi3", shortId = 211, displayName = "Kiwi Egg", icon = "🥚", tier = 3, basePrice = 170, volatility = 0.4 },
    Kiwi4 = { id = "Kiwi4", shortId = 212, displayName = "The Emerald Bird", icon = "🐦", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Pot Hotspot
    Pot1 = { id = "Pot1", shortId = 213, displayName = "Clay Chunk", icon = "🧱", tier = 1, basePrice = 5, volatility = 0.05 },
    Pot2 = { id = "Pot2", shortId = 214, displayName = "Stone Pot", icon = "🏺", tier = 2, basePrice = 35, volatility = 0.15 },
    Pot3 = { id = "Pot3", shortId = 215, displayName = "Boiling Water", icon = "♨️", tier = 3, basePrice = 180, volatility = 0.4 },
    Pot4 = { id = "Pot4", shortId = 216, displayName = "The Iron Cauldron", icon = "🥘", tier = 4, basePrice = 1350, volatility = 0.8 },

    -- Rhino_Toasterino
    ToastRhino1 = { id = "ToastRhino1", shortId = 217, displayName = "Crumbs", icon = "🍞", tier = 1, basePrice = 6, volatility = 0.05 },
    ToastRhino2 = { id = "ToastRhino2", shortId = 218, displayName = "Burnt Toast", icon = "🍞", tier = 2, basePrice = 35, volatility = 0.15 },
    ToastRhino3 = { id = "ToastRhino3", shortId = 219, displayName = "Electric Horn", icon = "🦏", tier = 3, basePrice = 200, volatility = 0.4 },
    ToastRhino4 = { id = "ToastRhino4", shortId = 220, displayName = "The Steel Rhino", icon = "🛡️", tier = 4, basePrice = 1500, volatility = 0.8 },

    -- Salamino Penguino
    Penguin1 = { id = "Penguin1", shortId = 221, displayName = "Small Fish", icon = "🐟", tier = 1, basePrice = 5, volatility = 0.05 },
    Penguin2 = { id = "Penguin2", shortId = 222, displayName = "Ice Pebble", icon = "🧊", tier = 2, basePrice = 32, volatility = 0.15 },
    Penguin3 = { id = "Penguin3", shortId = 223, displayName = "Tuxedo Bow", icon = "🎀", tier = 3, basePrice = 180, volatility = 0.4 },
    Penguin4 = { id = "Penguin4", shortId = 224, displayName = "King of the Arctic", icon = "👑", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Secret Lucky Block
    SecLuck1 = { id = "SecLuck1", shortId = 225, displayName = "Dusty Box", icon = "📦", tier = 1, basePrice = 20, volatility = 0.05 },
    SecLuck2 = { id = "SecLuck2", shortId = 226, displayName = "Hidden Note", icon = "📜", tier = 2, basePrice = 100, volatility = 0.15 },
    SecLuck3 = { id = "SecLuck3", shortId = 227, displayName = "Encrypted Key", icon = "🔑", tier = 3, basePrice = 500, volatility = 0.4 },
    SecLuck4 = { id = "SecLuck4", shortId = 228, displayName = "Classified Prize", icon = "📁", tier = 4, basePrice = 3500, volatility = 0.8 },

    -- Noobini_Pizzanini
    PizzaCrust = { id = "PizzaCrust", shortId = 229, displayName = "Burnt Pizza Crust", icon = "🍕", tier = 1, basePrice = 5, volatility = 0.05 },
    ColdPizza = { id = "ColdPizza", shortId = 230, displayName = "Cold Pizza Slice", icon = "🍕", tier = 2, basePrice = 30, volatility = 0.15 },
    DeepDish = { id = "DeepDish", shortId = 231, displayName = "Deep Dish Pizza", icon = "🥧", tier = 3, basePrice = 160, volatility = 0.4 },
    PartyPizza = { id = "PartyPizza", shortId = 232, displayName = "Ultimate Party Pizza", icon = "🎉", tier = 4, basePrice = 1200, volatility = 0.8 },

    -- Spioniro Golubiro
    Spion1 = { id = "Spion1", shortId = 233, displayName = "Mini Camera", icon = "📷", tier = 1, basePrice = 7, volatility = 0.05 },
    Spion2 = { id = "Spion2", shortId = 234, displayName = "Stealth Cloak", icon = "👤", tier = 2, basePrice = 45, volatility = 0.15 },
    Spion3 = { id = "Spion3", shortId = 235, displayName = "Binoculars", icon = "🔭", tier = 3, basePrice = 230, volatility = 0.4 },
    Spion4 = { id = "Spion4", shortId = 236, displayName = "The Master Spy", icon = "🕴️", tier = 4, basePrice = 1700, volatility = 0.8 },

    -- Strawberrelli Flamingelli
    Flam1 = { id = "Flam1", shortId = 237, displayName = "Pink Feather", icon = "🪶", tier = 1, basePrice = 5, volatility = 0.05 },
    Flam2 = { id = "Flam2", shortId = 238, displayName = "Sweet Berry", icon = "🍓", tier = 2, basePrice = 30, volatility = 0.15 },
    Flam3 = { id = "Flam3", shortId = 239, displayName = "Flamingo Stand", icon = "🦩", tier = 3, basePrice = 170, volatility = 0.4 },
    Flam4 = { id = "Flam4", shortId = 240, displayName = "The Tropical Queen", icon = "👑", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Svinina_Bombardino
    PigBomb1 = { id = "PigBomb1", shortId = 241, displayName = "Pig Tail", icon = "🐖", tier = 1, basePrice = 6, volatility = 0.05 },
    PigBomb2 = { id = "PigBomb2", shortId = 242, displayName = "Ham Casing", icon = "🍖", tier = 2, basePrice = 35, volatility = 0.15 },
    PigBomb3 = { id = "PigBomb3", shortId = 243, displayName = "Bacon Bomb", icon = "🥓", tier = 3, basePrice = 200, volatility = 0.4 },
    PigBomb4 = { id = "PigBomb4", shortId = 244, displayName = "The Atomic Porker", icon = "🐷", tier = 4, basePrice = 1500, volatility = 0.8 },

    -- Ta_Ta_Ta_Ta_Sahur
    Sahur1 = { id = "Sahur1", shortId = 245, displayName = "Iron Scraps", icon = "⛓️", tier = 1, basePrice = 8, volatility = 0.05 },
    Sahur2 = { id = "Sahur2", shortId = 246, displayName = "Brass Trumpet", icon = "🎺", tier = 2, basePrice = 45, volatility = 0.15 },
    Sahur3 = { id = "Sahur3", shortId = 247, displayName = "Marching Drum", icon = "🥁", tier = 3, basePrice = 220, volatility = 0.4 },
    Sahur4 = { id = "Sahur4", shortId = 248, displayName = "The Grand Parade", icon = "🎪", tier = 4, basePrice = 1700, volatility = 0.8 },

    -- Talpa_Di_Fero
    Mole1 = { id = "Mole1", shortId = 249, displayName = "Dirt Clump", icon = "🪨", tier = 1, basePrice = 5, volatility = 0.05 },
    Mole2 = { id = "Mole2", shortId = 250, displayName = "Iron Claw", icon = "🐾", tier = 2, basePrice = 35, volatility = 0.15 },
    Mole3 = { id = "Mole3", shortId = 251, displayName = "Tunneler", icon = "🚇", tier = 3, basePrice = 190, volatility = 0.4 },
    Mole4 = { id = "Mole4", shortId = 252, displayName = "The Steel Driller", icon = "🚜", tier = 4, basePrice = 1450, volatility = 0.8 },

    -- Tigrilini Watermelini
    TigMelon1 = { id = "TigMelon1", shortId = 253, displayName = "Tiger Stripe", icon = "🦓", tier = 1, basePrice = 6, volatility = 0.05 },
    TigMelon2 = { id = "TigMelon2", shortId = 254, displayName = "Melon Slice", icon = "🍉", tier = 2, basePrice = 40, volatility = 0.15 },
    TigMelon3 = { id = "TigMelon3", shortId = 255, displayName = "Roaring Fruit", icon = "🦁", tier = 3, basePrice = 230, volatility = 0.4 },
    TigMelon4 = { id = "TigMelon4", shortId = 256, displayName = "The Jungle Melon", icon = "👑", tier = 4, basePrice = 1800, volatility = 0.8 },

    -- Tigroligre Frutonni
    Ligre1 = { id = "Ligre1", shortId = 257, displayName = "Claw Scrap", icon = "🐾", tier = 1, basePrice = 7, volatility = 0.05 },
    Ligre2 = { id = "Ligre2", shortId = 258, displayName = "Juicy Hide", icon = "🧥", tier = 2, basePrice = 45, volatility = 0.15 },
    Ligre3 = { id = "Ligre3", shortId = 259, displayName = "Fruit Armor", icon = "🛡️", tier = 3, basePrice = 250, volatility = 0.4 },
    Ligre4 = { id = "Ligre4", shortId = 260, displayName = "The Hybrid King", icon = "🦁", tier = 4, basePrice = 1900, volatility = 0.8 },

    -- Tim_Cheese
    Cheese1 = { id = "Cheese1", shortId = 261, displayName = "Yellow Crumb", icon = "🧀", tier = 1, basePrice = 4, volatility = 0.05 },
    Cheese2 = { id = "Cheese2", shortId = 262, displayName = "Wedge of Swiss", icon = "🧀", tier = 2, basePrice = 25, volatility = 0.15 },
    Cheese3 = { id = "Cheese3", shortId = 263, displayName = "Melting Fondue", icon = "🫕", tier = 3, basePrice = 140, volatility = 0.4 },
    Cheese4 = { id = "Cheese4", shortId = 264, displayName = "The Golden Wheel", icon = "🌕", tier = 4, basePrice = 1000, volatility = 0.8 },

    -- Torrtuginni Dragonfrutini
    Dragon1 = { id = "Dragon1", shortId = 265, displayName = "Pink Scale", icon = "🛡️", tier = 1, basePrice = 7, volatility = 0.05 },
    Dragon2 = { id = "Dragon2", shortId = 266, displayName = "Dragon Fruit", icon = "🌵", tier = 2, basePrice = 45, volatility = 0.15 },
    Dragon3 = { id = "Dragon3", shortId = 267, displayName = "Turtle Shell", icon = "🐢", tier = 3, basePrice = 240, volatility = 0.4 },
    Dragon4 = { id = "Dragon4", shortId = 268, displayName = "The Mythic Dragon", icon = "🐲", tier = 4, basePrice = 1900, volatility = 0.8 },

    -- Tralalero_Tralala
    Tra1 = { id = "Tra1", shortId = 269, displayName = "Single Note", icon = "🎵", tier = 1, basePrice = 4, volatility = 0.05 },
    Tra2 = { id = "Tra2", shortId = 270, displayName = "Music Sheet", icon = "📄", tier = 2, basePrice = 25, volatility = 0.15 },
    Tra3 = { id = "Tra3", shortId = 271, displayName = "Microphone", icon = "🎤", tier = 3, basePrice = 150, volatility = 0.4 },
    Tra4 = { id = "Tra4", shortId = 272, displayName = "Grand Piano", icon = "🎹", tier = 4, basePrice = 1100, volatility = 0.8 },

    -- Trenostruzzo_Turbo_3000
    Train1 = { id = "Train1", shortId = 273, displayName = "Iron Bolt", icon = "🔩", tier = 1, basePrice = 10, volatility = 0.05 },
    Train2 = { id = "Train2", shortId = 274, displayName = "Coal Lump", icon = "🪨", tier = 2, basePrice = 55, volatility = 0.15 },
    Train3 = { id = "Train3", shortId = 275, displayName = "Turbo Engine", icon = "⚙️", tier = 3, basePrice = 300, volatility = 0.4 },
    Train4 = { id = "Train4", shortId = 276, displayName = "The Bullet Ostrich", icon = "🚄", tier = 4, basePrice = 2200, volatility = 0.8 },

    -- Tric_Trac_Baraboom
    Boom1 = { id = "Boom1", shortId = 277, displayName = "Fused Wire", icon = "🧵", tier = 1, basePrice = 6, volatility = 0.05 },
    Boom2 = { id = "Boom2", shortId = 278, displayName = "Gunpowder", icon = "🧂", tier = 2, basePrice = 40, volatility = 0.15 },
    Boom3 = { id = "Boom3", shortId = 279, displayName = "Heavy Crate", icon = "📦", tier = 3, basePrice = 220, volatility = 0.4 },
    Boom4 = { id = "Boom4", shortId = 280, displayName = "The Grand Finale", icon = "🎆", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Trippi_Troppi
    Trip1 = { id = "Trip1", shortId = 281, displayName = "Old Shoe", icon = "👟", tier = 1, basePrice = 5, volatility = 0.05 },
    Trip2 = { id = "Trip2", shortId = 282, displayName = "Energy Bar", icon = "🍫", tier = 2, basePrice = 30, volatility = 0.15 },
    Trip3 = { id = "Trip3", shortId = 283, displayName = "Hiking Staff", icon = "🦯", tier = 3, basePrice = 180, volatility = 0.4 },
    Trip4 = { id = "Trip4", shortId = 284, displayName = "World Traveler", icon = "🌍", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- Trulimero_Trulicina
    Truli1 = { id = "Truli1", shortId = 285, displayName = "Small Shard", icon = "💎", tier = 1, basePrice = 5, volatility = 0.05 },
    Truli2 = { id = "Truli2", shortId = 286, displayName = "Glow Stone", icon = "🪨", tier = 2, basePrice = 35, volatility = 0.15 },
    Truli3 = { id = "Truli3", shortId = 287, displayName = "Magic Charm", icon = "🧿", tier = 3, basePrice = 190, volatility = 0.4 },
    Truli4 = { id = "Truli4", shortId = 288, displayName = "The Divine Spark", icon = "✨", tier = 4, basePrice = 1450, volatility = 0.8 },

    -- Tung_Tung_Tung_Sahur
    Tung1 = { id = "Tung1", shortId = 289, displayName = "Steel Plate", icon = "🧱", tier = 1, basePrice = 8, volatility = 0.05 },
    Tung2 = { id = "Tung2", shortId = 290, displayName = "Heavy Hammer", icon = "🔨", tier = 2, basePrice = 50, volatility = 0.15 },
    Tung3 = { id = "Tung3", shortId = 291, displayName = "Drum Kit", icon = "🥁", tier = 3, basePrice = 260, volatility = 0.4 },
    Tung4 = { id = "Tung4", shortId = 292, displayName = "The Sahur Master", icon = "👑", tier = 4, basePrice = 2000, volatility = 0.8 },

    -- Unclito_Samito
    Sam1 = { id = "Sam1", shortId = 293, displayName = "Red Stripe", icon = "🧣", tier = 1, basePrice = 6, volatility = 0.05 },
    Sam2 = { id = "Sam2", shortId = 294, displayName = "Blue Star", icon = "⭐", tier = 2, basePrice = 40, volatility = 0.15 },
    Sam3 = { id = "Sam3", shortId = 295, displayName = "Top Hat", icon = "🎩", tier = 3, basePrice = 220, volatility = 0.4 },
    Sam4 = { id = "Sam4", shortId = 296, displayName = "The Patriot's Pride", icon = "🇺🇸", tier = 4, basePrice = 1600, volatility = 0.8 },

    -- Zibra Zubra Zibralini
    Zebra1 = { id = "Zebra1", shortId = 297, displayName = "Black Stripe", icon = "🦓", tier = 1, basePrice = 5, volatility = 0.05 },
    Zebra2 = { id = "Zebra2", shortId = 298, displayName = "White Stripe", icon = "⚪", tier = 2, basePrice = 30, volatility = 0.15 },
    Zebra3 = { id = "Zebra3", shortId = 299, displayName = "Savannah Grass", icon = "🌾", tier = 3, basePrice = 170, volatility = 0.4 },
    Zebra4 = { id = "Zebra4", shortId = 300, displayName = "The Prism Zebra", icon = "🌈", tier = 4, basePrice = 1300, volatility = 0.8 },

    -- V3: Synergy composite items (produced when specific pairs are in the same cluster)
    AvocadoToast = { id = "AvocadoToast", shortId = 301, displayName = "Avocado Toast", icon = "🥑🍞", tier = 3, basePrice = 320, volatility = 0.4 },
    PizzaCoffee = { id = "PizzaCoffee", shortId = 302, displayName = "Pizza Latte", icon = "🍕☕", tier = 3, basePrice = 280, volatility = 0.4 },
    NukeCroc = { id = "NukeCroc", shortId = 303, displayName = "Nuclear Crocodile", icon = "☢️🐊", tier = 4, basePrice = 2500, volatility = 0.8 },
    BananaSplit = { id = "BananaSplit", shortId = 304, displayName = "Banana Split Deluxe", icon = "🍌🍨", tier = 3, basePrice = 300, volatility = 0.4 },
    GrandChoir = { id = "GrandChoir", shortId = 305, displayName = "Grand Tralala Choir", icon = "🎵🎶", tier = 4, basePrice = 1800, volatility = 0.8 },
    DiscoSymphony = { id = "DiscoSymphony", shortId = 306, displayName = "Disco Symphony", icon = "🪩🎻", tier = 3, basePrice = 340, volatility = 0.4 },
    LemonFondue = { id = "LemonFondue", shortId = 307, displayName = "Lemon Fondue", icon = "🍋🫕", tier = 3, basePrice = 330, volatility = 0.4 },
    ArcticKiwiShake = { id = "ArcticKiwiShake", shortId = 308, displayName = "Arctic Kiwi Shake", icon = "🥝🧊", tier = 3, basePrice = 360, volatility = 0.4 },
    CourierGumCycle = { id = "CourierGumCycle", shortId = 309, displayName = "Courier Gum Cycle", icon = "🚲🕊️", tier = 3, basePrice = 380, volatility = 0.4 },
    EspressoIntel = { id = "EspressoIntel", shortId = 310, displayName = "Espresso Intel", icon = "☕🕶️", tier = 4, basePrice = 1200, volatility = 0.8 },
    NeonRailCore = { id = "NeonRailCore", shortId = 311, displayName = "Neon Rail Core", icon = "⚡🚄", tier = 4, basePrice = 1500, volatility = 0.8 },
    MoltenTunnelToast = { id = "MoltenTunnelToast", shortId = 312, displayName = "Molten Tunnel Toast", icon = "🌋🍞", tier = 4, basePrice = 1250, volatility = 0.8 },
    RuneSparkRelic = { id = "RuneSparkRelic", shortId = 313, displayName = "Rune Spark Relic", icon = "🪨✨", tier = 4, basePrice = 1700, volatility = 0.8 },
    SahurMegaMarch = { id = "SahurMegaMarch", shortId = 314, displayName = "Sahur Mega March", icon = "🥁🎺", tier = 4, basePrice = 2300, volatility = 0.8 },
    BaconHonkWarhead = { id = "BaconHonkWarhead", shortId = 315, displayName = "Bacon Honk Warhead", icon = "🥓💣", tier = 4, basePrice = 2500, volatility = 0.8 },
    QuantumDinoReactor = { id = "QuantumDinoReactor", shortId = 316, displayName = "Quantum Dino Reactor", icon = "☢️⚛️", tier = 4, basePrice = 2900, volatility = 0.8 },
    JackpotSingularity = { id = "JackpotSingularity", shortId = 317, displayName = "Jackpot Singularity", icon = "🎰🌀", tier = 4, basePrice = 3200, volatility = 0.8 },
}

ItemConfig.ID_TO_SHORT = {}
ItemConfig.SHORT_TO_ID = {}
for _, item in pairs(ItemConfig.Items) do
    if item.shortId then
        ItemConfig.ID_TO_SHORT[item.id] = item.shortId
        ItemConfig.SHORT_TO_ID[item.shortId] = item.id
    end
end

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
    ["Chef_Crabracadabra"] = { tier1 = "Crab1", tier2 = "Crab2", tier3 = "Crab3", tier4 = "Crab4", consumes1 = { Guac1 = 1, Toast1 = 1 }, consumes2 = { Guac2 = 1, Toast2 = 1 }, consumes3 = { Guac3 = 1, Toast3 = 1 }, consumes4 = { Guac4 = 1, Toast4 = 1 } },
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
    ["La_Grande_Combinasion"] = { tier1 = "Combo1", tier2 = "Combo2", tier3 = "Combo3", tier4 = "Combo4", consumes1 = { Bike1 = 1, Neon1 = 1 }, consumes2 = { Bike2 = 1, Neon2 = 1 }, consumes3 = { Bike3 = 1, Neon3 = 1 }, consumes4 = { Bike4 = 1, Neon4 = 1 } },
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
-- V3: AUTO-GENERATED MODES TABLE (from BrainrotItems)
-- Each model gets 4 selectable modes with level-based unlock thresholds
--------------------------------------------------------------------------------

ItemConfig.BrainrotModes = {}
for modelName, tiers in pairs(ItemConfig.BrainrotItems) do
    ItemConfig.BrainrotModes[modelName] = {
        { itemId = tiers.tier1, unlockLevel = ItemConfig.MilestoneThresholds.tier1, rate = ItemConfig.ProductionSettings.tier1.rate, consumes = tiers.consumes1 },
        { itemId = tiers.tier2, unlockLevel = ItemConfig.MilestoneThresholds.tier2, rate = ItemConfig.ProductionSettings.tier2.rate, consumes = tiers.consumes2 },
        { itemId = tiers.tier3, unlockLevel = ItemConfig.MilestoneThresholds.tier3, rate = ItemConfig.ProductionSettings.tier3.rate, consumes = tiers.consumes3 },
        { itemId = tiers.tier4, unlockLevel = ItemConfig.MilestoneThresholds.tier4, rate = ItemConfig.ProductionSettings.tier4.rate, consumes = tiers.consumes4 },
    }
end

--------------------------------------------------------------------------------
-- V3: SYNERGY DEFINITIONS
-- Pairs of unit types that produce special composite items when in the same cluster
--------------------------------------------------------------------------------

ItemConfig.Synergies = {
    { unitA = "Avocadini Guffo",       unitB = "Bambini_Crostini",       synergyItem = "AvocadoToast", bonus = 1.5 },
    { unitA = "Ballerina_Cappuccina",   unitB = "Noobini_Pizzanini",     synergyItem = "PizzaCoffee",  bonus = 1.3 },
    { unitA = "Bombardiro_Crocodilo",   unitB = "Nuclearo Dinossauro",   synergyItem = "NukeCroc",     bonus = 2.0 },
    { unitA = "Chimpanzini_Bananini",   unitB = "Bananita_Dolphinita",   synergyItem = "BananaSplit",  bonus = 1.4 },
    { unitA = "Tralalero_Tralala",      unitB = "Las Tralaleritas",      synergyItem = "GrandChoir",   bonus = 1.6 },
    { unitA = "Ballerino Lololo",       unitB = "Lirilì_Larilà",         synergyItem = "DiscoSymphony", bonus = 1.3 },
    { unitA = "Perochello_Lemonchello", unitB = "Tim_Cheese",            synergyItem = "LemonFondue", bonus = 1.28 },
    { unitA = "Pipi_Kiwi",              unitB = "Salamino Penguino",     synergyItem = "ArcticKiwiShake", bonus = 1.32 },
    { unitA = "Chicleteira Bicicleteira", unitB = "Piccione Macchina",   synergyItem = "CourierGumCycle", bonus = 1.35 },
    { unitA = "Cappuccino_Assassino",   unitB = "Spioniro Golubiro",     synergyItem = "EspressoIntel", bonus = 1.5 },
    { unitA = "Gattatino Neonino",      unitB = "Trenostruzzo_Turbo_3000", synergyItem = "NeonRailCore", bonus = 1.55 },
    { unitA = "Talpa_Di_Fero",          unitB = "Rhino_Toasterino",      synergyItem = "MoltenTunnelToast", bonus = 1.45 },
    { unitA = "Trulimero_Trulicina",    unitB = "Odin_Din_Din_Dun",      synergyItem = "RuneSparkRelic", bonus = 1.6 },
    { unitA = "Tung_Tung_Tung_Sahur",   unitB = "Ta_Ta_Ta_Ta_Sahur",     synergyItem = "SahurMegaMarch", bonus = 1.75 },
    { unitA = "Bombombini_Gusini",      unitB = "Svinina_Bombardino",    synergyItem = "BaconHonkWarhead", bonus = 1.8 },
    { unitA = "La_Grande_Combinasion",  unitB = "Nuclearo Dinossauro",   synergyItem = "QuantumDinoReactor", bonus = 1.9 },
    { unitA = "Brainrot God Lucky Block", unitB = "Mythic Lucky Block",  synergyItem = "JackpotSingularity", bonus = 1.85 },
}

-- Pre-build lookup for O(1) synergy checks
ItemConfig._SynergyLookup = {}
for _, syn in ipairs(ItemConfig.Synergies) do
    if not ItemConfig._SynergyLookup[syn.unitA] then ItemConfig._SynergyLookup[syn.unitA] = {} end
    if not ItemConfig._SynergyLookup[syn.unitB] then ItemConfig._SynergyLookup[syn.unitB] = {} end
    ItemConfig._SynergyLookup[syn.unitA][syn.unitB] = syn
    ItemConfig._SynergyLookup[syn.unitB][syn.unitA] = syn
end

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

function ItemConfig.GetItem(itemId: string): ItemDefinition?
    return ItemConfig.Items[itemId]
end

function ItemConfig.GetProductions(modelName: string, ownedCount: number): {{itemId: string, rate: number, consumes: {[string]: number}?}}
    -- Finder rækken baseret på præcis modelnavn
    local mapping = ItemConfig.BrainrotItems[modelName]
    if not mapping then return {} end
    
    local productions = {}
    local thresholds = ItemConfig.MilestoneThresholds
    
    if ownedCount >= thresholds.tier1 then table.insert(productions, {itemId = mapping.tier1, rate = ItemConfig.ProductionSettings.tier1.rate, consumes = mapping.consumes1}) end
    if ownedCount >= thresholds.tier2 then table.insert(productions, {itemId = mapping.tier2, rate = ItemConfig.ProductionSettings.tier2.rate, consumes = mapping.consumes2}) end
    if ownedCount >= thresholds.tier3 then table.insert(productions, {itemId = mapping.tier3, rate = ItemConfig.ProductionSettings.tier3.rate, consumes = mapping.consumes3}) end
    if ownedCount >= thresholds.tier4 then table.insert(productions, {itemId = mapping.tier4, rate = ItemConfig.ProductionSettings.tier4.rate, consumes = mapping.consumes4}) end
    
    return productions
end

--[[
    V3: Get production info for a single selected mode.
    Returns { itemId, rate } adjusted by level-based speed scaling.
]]
function ItemConfig.GetModeProduction(modelName: string, modeIndex: number, level: number): {itemId: string, rate: number, consumes: {[string]: number}?}?
    local modes = ItemConfig.BrainrotModes[modelName]
    if not modes then return nil end
    
    local mode = modes[math.clamp(modeIndex, 1, #modes)]
    if not mode then return nil end
    
    level = tonumber(level) or 1
    
    -- Speed scales with level: rate / (SpeedExponent ^ (level - 1))
    local speedMult = ItemConfig.SpeedExponent ^ (level - 1)
    local adjustedRate = mode.rate / speedMult
    adjustedRate = math.max(adjustedRate, 0.1) -- Floor at 0.1s
    
    return { itemId = mode.itemId, rate = adjustedRate, consumes = mode.consumes }
end

--[[
    V3: Check if two unit types form a synergy pair.
    Returns synergy config { unitA, unitB, synergyItem, bonus } or nil.
]]
function ItemConfig.GetSynergyOverride(unitTypeA: string, unitTypeB: string)
    local lookup = ItemConfig._SynergyLookup[unitTypeA]
    if not lookup then return nil end
    return lookup[unitTypeB]
end

--[[
    V3: Get all modes available to a unit at a given level.
    Returns array of { modeIndex, itemId, unlockLevel, isUnlocked, rate }.
]]
function ItemConfig.GetAvailableModes(modelName: string, level: number): {{modeIndex: number, itemId: string, unlockLevel: number, isUnlocked: boolean, rate: number, consumes: {[string]: number}?}}
    local modes = ItemConfig.BrainrotModes[modelName]
    if not modes then return {} end
    
    local result = {}
    for i, mode in ipairs(modes) do
        local isUnlocked = level >= mode.unlockLevel
        local speedMult = ItemConfig.SpeedExponent ^ (level - 1)
        local adjustedRate = mode.rate / speedMult
        adjustedRate = math.max(adjustedRate, 0.1)
        
        table.insert(result, {
            modeIndex = i,
            itemId = mode.itemId,
            unlockLevel = mode.unlockLevel,
            isUnlocked = isUnlocked,
            rate = adjustedRate,
            consumes = mode.consumes,
        })
    end
    return result
end

--[[
    V3: Get full info for a specific mode.
    Used by UI to get details for the currently active mode.
]]
function ItemConfig.GetMode(modelName: string, level: number, modeIndex: number)
    local modes = ItemConfig.BrainrotModes[modelName]
    if not modes then return nil end
    
    -- Default to mode 1 if index is invalid or nil
    modeIndex = modeIndex or 1
    local mode = modes[math.clamp(modeIndex, 1, #modes)]
    if not mode then return nil end
    
    local isUnlocked = level >= mode.unlockLevel
    local speedMult = ItemConfig.SpeedExponent ^ (level - 1)
    local adjustedRate = mode.rate / speedMult
    adjustedRate = math.max(adjustedRate, 0.1)
    
    return {
        modeIndex = modeIndex,
        itemId = mode.itemId,
        unlockLevel = mode.unlockLevel,
        isUnlocked = isUnlocked,
        rate = adjustedRate,
        consumes = mode.consumes,
    }
end

--[[
    Determines the stock market Sector for a brainrot based on its name.
    Replaces the old hardcoded Category system.
]]
function ItemConfig.GetSector(modelName: string): string
    local name = string.lower(modelName)
    
    local SECTORS = {
        Food = {"avocado", "pizza", "burrito", "coffee", "cheese", "cap", "signora", "lemon", "toast", "crostini", "guac", "berry", "crab", "glorbo", "melon", "fruit", "pineapple", "strawber", "avoca", "pot", "frut", "ananas", "orang", "cappu", "chef"},
        Animals = {"chimp", "panda", "giraffe", "croc", "pig", "zebra", "orca", "whale", "dolphin", "octopus", "goose", "horse", "kiwi", "lion", "tiger", "penguin", "flamingo", "mole", "spider", "spyder", "gusini", "hipo", "eleph", "coco", "came", "giraf", "vacca", "vaqu", "dino", "saur", "talpa", "tigr", "ligre", "zibra", "zubra", "nyan", "gatt", "pigeon", "bird"},
        Entertainment = {"dance", "music", "trala", "sahur", "symphony", "virtuoso", "bell", "choir", "rhythm", "drum", "trumpet", "marching", "parade", "lololo", "larila", "liri", "lari", "statu", "libert"},
        Mystic = {"god", "odin", "mythic", "lucky", "relic", "artifact", "ancient", "dragon", "kraken", "forbidden", "spell", "magic", "secret", "divine", "bicus", "truli", "bubble", "brr", "burb", "fluri", "garama", "madun", "medus", "grai", "boneca"},
        Tech = {"neon", "cyber", "machine", "hybrid", "combined", "drone", "turbo", "bullet", "engine", "battery", "volt", "light", "circuit", "train", "combo", "mat_teo", "biciclet", "chicl", "combina", "macchina"},
        Action = {"bombard", "assassin", "gangster", "bandit", "crocbomb", "boom", "nuke", "atomic", "spy", "stealth", "binoculars", "camera", "spion", "detonator", "missile", "grenade", "trip", "matteo", "samito", "uncl", "nuclearo", "bomb"},
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

ItemConfig._ItemSectorLookup = nil

local function buildItemSectorLookup()
    if ItemConfig._ItemSectorLookup then
        return
    end

    local lookup = {}

    -- Authoritative mapping: modelName -> sector, then all mapped tier items inherit it.
    for modelName, mapping in pairs(ItemConfig.BrainrotItems) do
        local sector = ItemConfig.GetSector(modelName)
        if mapping.tier1 then lookup[mapping.tier1] = sector end
        if mapping.tier2 then lookup[mapping.tier2] = sector end
        if mapping.tier3 then lookup[mapping.tier3] = sector end
        if mapping.tier4 then lookup[mapping.tier4] = sector end
    end

    -- Safety fallback for items not present in BrainrotItems (e.g. composites/future additions).
    for itemId, itemDef in pairs(ItemConfig.Items) do
        if not lookup[itemId] then
            lookup[itemId] = ItemConfig.GetSector(itemDef.displayName or itemId)
        end
    end

    ItemConfig._ItemSectorLookup = lookup
end

function ItemConfig.GetSectorByItemId(itemId: string): string
    if not itemId then return "Neutral" end
    buildItemSectorLookup()
    return (ItemConfig._ItemSectorLookup and ItemConfig._ItemSectorLookup[itemId]) or "Neutral"
end

return ItemConfig