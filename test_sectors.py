import re

items = [
    "Avocadini Guffo", "Ballerina_Cappuccina", "Ballerino Lololo", "Bambini_Crostini",
    "Bananita_Dolphinita", "Bandito_Bobritto", "Blueberrinni_Octopusini",
    "Bombardiro_Crocodilo", "Bombombini_Gusini", "Boneca_Ambalabu",
    "Brainrot God Lucky Block", "Brr_Brr_Patapim", "Brri_Brri_Bicus_Dicus_Bombicus",
    "Burbaloni_Loliloli", "Cacto Hipopotamo", "Cappuccino_Assassino",
    "Cavallo_Virtuoso", "Chef_Crabracadabra", "Chicleteira Bicicleteira",
    "Chimpanzini Spiderini", "Chimpanzini_Bananini", "Cocofanto_Elefanto",
    "Espresso Signora", "Fluri_flura", "Frigo_Camelo", "Gangster_Footera",
    "Garama_and_Madundung", "Gattatino Neonino", "Gattatino_Nyanino",
    "Girafa_Celestre", "Glorbo_Fruttodrillo", "Gorillo Watermelondrillo",
    "Graipuss_Medussi", "La_Grande_Combinasion", "La_Vacca_Saturno_Saturnita",
    "Las Tralaleritas", "Las Vaquitas Saturnitas", "Lionel_Cactuseli",
    "Lirilì_Larilà", "Los Crocodillitos", "Los_Tralaleritos", "Mat_teo",
    "Mythic Lucky Block", "Noobini_Pizzanini", "Nuclearo Dinossauro",
    "Odin_Din_Din_Dun", "Orangutini_Ananassini", "Orcalero Orcala",
    "Pandaccini Bananini", "Perochello_Lemonchello", "Piccione Macchina",
    "Pipi_Kiwi", "Pot Hotspot", "Rhino_Toasterino", "Salamino Penguino",
    "Sammyni_Spyderini", "Secret Lucky Block", "Spioniro Golubiro",
    "Statutino Libertino", "Strawberrelli Flamingelli", "Svinina_Bombardino",
    "Ta_Ta_Ta_Ta_Sahur", "Talpa_Di_Fero", "Tigrilini Watermelini",
    "Tigroligre Frutonni", "Tim_Cheese", "Torrtuginni Dragonfrutini",
    "Tralalero_Tralala", "Trenostruzzo_Turbo_3000", "Tric_Trac_Baraboom",
    "Trippi_Troppi", "Trulimero_Trulicina", "Tung_Tung_Tung_Sahur",
    "Unclito_Samito", "Zibra Zubra Zibralini"
]

sectors = {
    "Food": ["avocado", "pizza", "burrito", "coffee", "cheese", "cap", "signora", "lemon", "toast", "crostini", "guac", "berry", "crab", "glorbo", "melon", "fruit", "pineapple", "strawber", "avoca", "pot", "frut", "ananas", "orang", "cappu", "chef"],
    "Animals": ["chimp", "panda", "giraffe", "croc", "pig", "zebra", "orca", "whale", "dolphin", "octopus", "goose", "horse", "kiwi", "lion", "tiger", "penguin", "flamingo", "mole", "spider", "spyder", "gusini", "hipo", "eleph", "coco", "came", "giraf", "vacca", "vaqu", "dino", "saur", "talpa", "tigr", "ligre", "zibra", "zubra", "nyan", "gatt", "pigeon", "bird"],
    "Entertainment": ["dance", "music", "trala", "sahur", "symphony", "virtuoso", "bell", "choir", "rhythm", "drum", "trumpet", "marching", "parade", "lololo", "larila", "liri", "lari", "statu", "libert"],
    "Mystic": ["god", "odin", "mythic", "lucky", "relic", "artifact", "ancient", "dragon", "kraken", "forbidden", "spell", "magic", "secret", "divine", "bicus", "truli", "bubble", "brr", "burb", "fluri", "garama", "madun", "medus", "grai", "boneca"],
    "Tech": ["neon", "cyber", "machine", "hybrid", "combined", "drone", "turbo", "bullet", "engine", "battery", "volt", "light", "circuit", "train", "combo", "mat_teo", "biciclet", "chicl", "combina", "macchina"],
    "Action": ["bombard", "assassin", "gangster", "bandit", "crocbomb", "boom", "nuke", "atomic", "spy", "stealth", "binoculars", "camera", "spion", "detonator", "missile", "grenade", "trip", "matteo", "samito", "uncl", "nuclearo", "bomb"]
}

def get_sector(name):
    name_lower = name.lower()
    for sector, keywords in sectors.items():
        for keyword in keywords:
            if keyword in name_lower:
                return sector
    return "Neutral"

print("Categorization Results:")
for item in sorted(items):
    sector = get_sector(item)
    print(f"{item}: {sector}")

neutral_count = len([item for item in items if get_sector(item) == "Neutral"])
print(f"\nTotal Neutral Items: {neutral_count}")
