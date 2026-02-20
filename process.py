import re

filepath = "c:/Users/Soren/Desktop/BrainrotClicker/BrainRotClicker/src/shared/ItemConfig.luau"

with open(filepath, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Replace ProductionRates with ProductionSettings
content = content.replace("""ItemConfig.ProductionRates = {
    tier1 = 2,    -- Common
    tier2 = 10,   -- Uncommon
    tier3 = 45,   -- Rare
    tier4 = 180,  -- Legendary
}""", """ItemConfig.ProductionSettings = {
    tier1 = { rate = 2, volatility = 0.05 },
    tier2 = { rate = 10, volatility = 0.15 },
    tier3 = { rate = 45, volatility = 0.40 },
    tier4 = { rate = 180, volatility = 0.80 },
}""")

# 2. Add Short IDs to Items
item_blocks = re.findall(r'(\w+)\s*=\s*\{([^}]+)\}', content)
short_id_counter = 1
id_to_short = {}
short_to_id = {}

def process_items(match):
    global short_id_counter
    obj_str = match.group(0)
    if "displayName" in obj_str and "shortId" not in obj_str:
        # insert shortId right after id
        new_obj = re.sub(r'id\s*=\s*"([^"]+)",', f'id = "\\1", shortId = {short_id_counter},', obj_str)
        short_id_counter += 1
        return new_obj
    return obj_str

new_content = []
lines = content.split('\n')
in_items = False
for line in lines:
    if "ItemConfig.Items = {" in line:
        in_items = True
        new_content.append(line)
        continue
    
    if in_items and "}" in line and " displayName " not in line and " id " not in line and line.strip() == "}":
        in_items = False
        new_content.append(line)
        # Add the ShortId maps at the end of the Items definition
        new_content.append("")
        new_content.append("ItemConfig.ID_TO_SHORT = {}")
        new_content.append("ItemConfig.SHORT_TO_ID = {}")
        new_content.append("for _, item in pairs(ItemConfig.Items) do")
        new_content.append("    if item.shortId then")
        new_content.append("        ItemConfig.ID_TO_SHORT[item.id] = item.shortId")
        new_content.append("        ItemConfig.SHORT_TO_ID[item.shortId] = item.id")
        new_content.append("    end")
        new_content.append("end")
        continue

    if in_items and "displayName" in line:
        match = re.search(r'(\w+)\s*=\s*\{(.+?)\}', line)
        if match:
            item_id_match = re.search(r'id\s*=\s*"([^"]+)"', line)
            if item_id_match:
                item_id = item_id_match.group(1)
                
                # Update volatility based on tier
                tier_match = re.search(r'tier\s*=\s*(\d)', line)
                if tier_match:
                    tier = int(tier_match.group(1))
                    vol = {1: 0.05, 2: 0.15, 3: 0.40, 4: 0.80}.get(tier, 0.1)
                    line = re.sub(r'volatility\s*=\s*[\d\.]+', f'volatility = {vol}', line)

                new_line = re.sub(r'id\s*=\s*"([^"]+)",', f'id = "\\1", shortId = {short_id_counter},', line)
                short_id_counter += 1
                new_content.append(new_line)
            else:
                new_content.append(line)
        else:
            new_content.append(line)
    else:
        new_content.append(line)

content = '\n'.join(new_content)

# 3. Add consumes to specific Crafter units in ItemConfig.BrainrotItems
crafter_replacements = {
    '["Chef_Crabracadabra"] = { tier1 = "Crab1", tier2 = "Crab2", tier3 = "Crab3", tier4 = "Crab4" }': '["Chef_Crabracadabra"] = { tier1 = "Crab1", tier2 = "Crab2", tier3 = "Crab3", tier4 = "Crab4", consumes1 = { Guac1 = 1, Toast1 = 1 }, consumes2 = { Guac2 = 1, Toast2 = 1 }, consumes3 = { Guac3 = 1, Toast3 = 1 }, consumes4 = { Guac4 = 1, Toast4 = 1 } }',
    '["La_Grande_Combinasion"] = { tier1 = "Combo1", tier2 = "Combo2", tier3 = "Combo3", tier4 = "Combo4" }': '["La_Grande_Combinasion"] = { tier1 = "Combo1", tier2 = "Combo2", tier3 = "Combo3", tier4 = "Combo4", consumes1 = { Bike1 = 1, Neon1 = 1 }, consumes2 = { Bike2 = 1, Neon2 = 1 }, consumes3 = { Bike3 = 1, Neon3 = 1 }, consumes4 = { Bike4 = 1, Neon4 = 1 } }',
}

for old, new in crafter_replacements.items():
    content = content.replace(old, new)


# 4. Update the GetProductions / GetModeProduction and BrainrotModes for the new settings and consumes
content = content.replace("""    ItemConfig.BrainrotModes[modelName] = {
        { itemId = tiers.tier1, unlockLevel = ItemConfig.MilestoneThresholds.tier1, rate = ItemConfig.ProductionRates.tier1 },
        { itemId = tiers.tier2, unlockLevel = ItemConfig.MilestoneThresholds.tier2, rate = ItemConfig.ProductionRates.tier2 },
        { itemId = tiers.tier3, unlockLevel = ItemConfig.MilestoneThresholds.tier3, rate = ItemConfig.ProductionRates.tier3 },
        { itemId = tiers.tier4, unlockLevel = ItemConfig.MilestoneThresholds.tier4, rate = ItemConfig.ProductionRates.tier4 },
    }""", """    ItemConfig.BrainrotModes[modelName] = {
        { itemId = tiers.tier1, unlockLevel = ItemConfig.MilestoneThresholds.tier1, rate = ItemConfig.ProductionSettings.tier1.rate, consumes = tiers.consumes1 },
        { itemId = tiers.tier2, unlockLevel = ItemConfig.MilestoneThresholds.tier2, rate = ItemConfig.ProductionSettings.tier2.rate, consumes = tiers.consumes2 },
        { itemId = tiers.tier3, unlockLevel = ItemConfig.MilestoneThresholds.tier3, rate = ItemConfig.ProductionSettings.tier3.rate, consumes = tiers.consumes3 },
        { itemId = tiers.tier4, unlockLevel = ItemConfig.MilestoneThresholds.tier4, rate = ItemConfig.ProductionSettings.tier4.rate, consumes = tiers.consumes4 },
    }""")

content = content.replace("""    if ownedCount >= thresholds.tier1 then table.insert(productions, {itemId = mapping.tier1, rate = rates.tier1}) end
    if ownedCount >= thresholds.tier2 then table.insert(productions, {itemId = mapping.tier2, rate = rates.tier2}) end
    if ownedCount >= thresholds.tier3 then table.insert(productions, {itemId = mapping.tier3, rate = rates.tier3}) end
    if ownedCount >= thresholds.tier4 then table.insert(productions, {itemId = mapping.tier4, rate = rates.tier4}) end""",
"""    if ownedCount >= thresholds.tier1 then table.insert(productions, {itemId = mapping.tier1, rate = ItemConfig.ProductionSettings.tier1.rate, consumes = mapping.consumes1}) end
    if ownedCount >= thresholds.tier2 then table.insert(productions, {itemId = mapping.tier2, rate = ItemConfig.ProductionSettings.tier2.rate, consumes = mapping.consumes2}) end
    if ownedCount >= thresholds.tier3 then table.insert(productions, {itemId = mapping.tier3, rate = ItemConfig.ProductionSettings.tier3.rate, consumes = mapping.consumes3}) end
    if ownedCount >= thresholds.tier4 then table.insert(productions, {itemId = mapping.tier4, rate = ItemConfig.ProductionSettings.tier4.rate, consumes = mapping.consumes4}) end""")

content = content.replace("""    return { itemId = mode.itemId, rate = adjustedRate }""", """    return { itemId = mode.itemId, rate = adjustedRate, consumes = mode.consumes }""")

content = content.replace("""        table.insert(result, {
            modeIndex = i,
            itemId = mode.itemId,
            unlockLevel = mode.unlockLevel,
            isUnlocked = isUnlocked,
            rate = adjustedRate,
        })""", """        table.insert(result, {
            modeIndex = i,
            itemId = mode.itemId,
            unlockLevel = mode.unlockLevel,
            isUnlocked = isUnlocked,
            rate = adjustedRate,
            consumes = mode.consumes,
        })""")

content = content.replace("""        isUnlocked = isUnlocked,
        rate = adjustedRate,
    }""", """        isUnlocked = isUnlocked,
        rate = adjustedRate,
        consumes = mode.consumes,
    }""")


with open(filepath, "w", encoding="utf-8") as f:
    f.write(content)

print(f"Successfully processed {filepath}")

