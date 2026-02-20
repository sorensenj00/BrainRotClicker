import os
import re

client_dir = "c:/Users/Soren/Desktop/BrainrotClicker/BrainRotClicker/src/client"
files_to_patch = [
    "TransportUI.client.luau",
    "PhysicalInventoryHUD.client.luau",
    "NotificationManager.client.luau",
    "MoneyHUD.client.luau",
    "HFTTerminal.client.luau",
    "BackpackHUD.client.luau"
]

decoder_func = """
local function decodeItems(encoded)
	if not ItemConfig or not ItemConfig.SHORT_TO_ID then return encoded end
	if type(encoded) ~= "table" then return encoded end
	local decoded = {}
	for k, count in pairs(encoded) do
		local shortId = tonumber(k)
		if shortId and ItemConfig.SHORT_TO_ID[shortId] then
			decoded[ItemConfig.SHORT_TO_ID[shortId]] = count
		else
			decoded[k] = count
		end
	end
	return decoded
end
"""

for fname in files_to_patch:
    fpath = os.path.join(client_dir, fname)
    if not os.path.exists(fpath):
        continue
        
    with open(fpath, "r", encoding="utf-8") as f:
        content = f.read()
        
    if "decodeItems(" in content:
        continue # already patched
        
    # Insert decoder func somewhere before events. Usually after ItemConfig require.
    # Or just drop it right before OnClientEvent
    
    # Let's replace StorageUpdatedEvent.OnClientEvent stuff
    if "StorageUpdatedEvent.OnClientEvent:Connect(function(items," in content:
        content = content.replace("StorageUpdatedEvent.OnClientEvent:Connect(function(items,", decoder_func + "\nStorageUpdatedEvent.OnClientEvent:Connect(function(encodedItems,")
        content = content.replace("currentStorage = items or {}", "currentStorage = decodeItems(encodedItems) or {}")
        
        # PhysicalInventoryHUD style:
        content = content.replace("updateHUD(data.billboard, items,", "updateHUD(data.billboard, decodeItems(encodedItems),")
        
        # NotificationManager/MoneyHUD style - might not use StorageUpdated, let's look for others
    
    # For BackpackHUD:
    # StorageUpdatedEvent.OnClientEvent:Connect(function(...) might not be standard.
    # TransportUI & BackpackHUD & PhysicalInventoryHUD all have CartUpdateEvent or BackpackUpdatedEvent
    content = content.replace("BackpackUpdatedEvent.OnClientEvent:Connect(function(items", "BackpackUpdatedEvent.OnClientEvent:Connect(function(encodedItems")
    
    content = content.replace("StorageUpdatedEvent.OnClientEvent:Connect(function(items)", "StorageUpdatedEvent.OnClientEvent:Connect(function(encodedItems)")
    
    content = content.replace("currentCart = inventory or {}", "currentCart = decodeItems(inventory) or {}")
    content = content.replace("CartUpdateEvent.OnClientEvent:Connect(function(state, inventory,", "CartUpdateEvent.OnClientEvent:Connect(function(state, inventory,")

    # The manual way:
    # We will just write the changes out.
    
    with open(fpath, "w", encoding="utf-8") as f:
        f.write(content)
        
    print(f"Patched {fname}")
