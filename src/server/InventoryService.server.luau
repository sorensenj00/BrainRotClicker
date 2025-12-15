--[[
	InventoryService Server Script
	
	Aggregates Brainrot (Unit) and Artifact data into a unified "Item" format.
	Serves as the single source of truth for the Unified Inventory UI.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemTypes = require(Shared:WaitForChild("ItemTypes"))
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

-- Create RemoteFunction for fetching unified inventory
local GetUnifiedInventoryFunc = RemoteFunctions:FindFirstChild("GetUnifiedInventory") or Instance.new("RemoteFunction")
GetUnifiedInventoryFunc.Name = "GetUnifiedInventory"
GetUnifiedInventoryFunc.Parent = RemoteFunctions

-- Create Event for updates
local UnifiedInventoryChangedEvent = RemoteEvents:FindFirstChild("UnifiedInventoryChanged") or Instance.new("RemoteEvent")
UnifiedInventoryChangedEvent.Name = "UnifiedInventoryChanged"
UnifiedInventoryChangedEvent.Parent = RemoteEvents

--------------------------------------------------------------------------------
-- DATA AGGREGATION
--------------------------------------------------------------------------------

-- Helper to wait for BrainrotManager
local function waitForBrainrotManager()
	local attempts = 0
	while not (_G.BrainrotManager and _G.BrainrotManager.GetInventoryData) and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.BrainrotManager
end

local function getUnifiedInventory(player: Player)
	local items: {ItemTypes.Item} = {}
	
	-- Ensure BrainrotManager is ready
	local BrainrotManager = waitForBrainrotManager()
	
	-- 1. Get Units from BrainrotManager
	if BrainrotManager and BrainrotManager.GetInventoryData then
		local inventoryData = BrainrotManager.GetInventoryData(player)
		-- inventoryData: { units = { [unitName]: {level, rarity, status} } }
		
		if inventoryData and inventoryData.units then
			for unitName, data in pairs(inventoryData.units) do
				-- Only include units the player actually owns (level >= 1)
				local level = data.level or 0
				if level < 1 then
					continue
				end
				
				local config = ShopConfig.GetConfig(unitName)
				local icon = config and config.Icon or "🧠" -- Fallback icon
				
				local newItem: ItemTypes.Item = {
					UUID = unitName, -- Unit names are unique keys in the current system
					Type = "Unit",
					Id = unitName,
					Name = config and config.Name or unitName,
					Rarity = data.rarity or "Normal",
					Icon = icon,
					IsEquipped = false,
					IsPlaced = (data.status == "placed"),
					Data = {
						Level = level,
						Equipment = {}, -- TODO: Fetch actual equipment if available
						Stats = nil,
						EquippedTo = nil,
					}
				}
				table.insert(items, newItem)
			end
		end
	end
	
	-- 2. Get Artifacts from ArtifactManager
	if _G.ArtifactManager and _G.ArtifactManager.GetPlayerArtifacts then
		local artifactsData = _G.ArtifactManager.GetPlayerArtifacts(player)
		-- artifactsData: {[GUID]: artifactData}
		
		if artifactsData then
			for guid, data in pairs(artifactsData) do
				local newItem: ItemTypes.Item = {
					UUID = guid,
					Type = "Artifact",
					Id = data.BaseId or "Artifact",
					Name = data.Name,
					Rarity = data.Rarity,
					Icon = data.BaseIcon or "💎",
					IsEquipped = (data.EquippedTo ~= nil),
					IsPlaced = false,
					Data = {
						Stats = ArtifactConfig.CalculateArtifactStats(data),
						EquippedTo = data.EquippedTo,
						Level = nil,
						Equipment = nil,
					}
				}
				table.insert(items, newItem)
			end
		end
	end
	
	return items
end

--------------------------------------------------------------------------------
-- EVENT LISTENERS
--------------------------------------------------------------------------------

-- Listen to existing events to trigger unified updates
local InventoryChangedEvent = RemoteEvents:FindFirstChild("InventoryChanged")
if InventoryChangedEvent then
	-- We can't listen to RemoteEvent.OnServerEvent for server-side fires? 
	-- Actually, BrainrotManager fires Client. We need to know when it happens on Server? 
	-- BrainrotManager logic is Server -> Client.
	-- We can wrap the BrainrotManager functions if we want real-time server updates,
	-- OR we can just rely on the existing Client events and have the Client re-fetch from here.
	-- BUT the plan was "Listens to changes in both managers".
	-- Since Managers are global, we can hook into them or just let the Client request updates.
	-- For simplicity and robustness, we'll let the Client decide when to fetch, 
	-- aka the Client listens to "InventoryChanged" (Units) and "ArtifactDropped" (Artifacts)
	-- and calls "GetUnifiedInventory".
	
	-- However, to be "Unified", maybe we should emit one event?
	-- For now, let's keep it simple: Client fetches.
end

--------------------------------------------------------------------------------
-- HANDLERS
--------------------------------------------------------------------------------

GetUnifiedInventoryFunc.OnServerInvoke = function(player)
	return getUnifiedInventory(player)
end

print("✓ InventoryService Initialized")
