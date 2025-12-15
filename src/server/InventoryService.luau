--[[
	InventoryService Server Module
	
	Aggregates Brainrot (Unit) and Artifact data into a unified "Item" format.
	Serves as the single source of truth for the Unified Inventory UI.
	
	CONVERTED TO MODULE SCRIPT
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

local GetUnifiedInventoryFunc = RemoteFunctions:FindFirstChild("GetUnifiedInventory") or Instance.new("RemoteFunction")
GetUnifiedInventoryFunc.Name = "GetUnifiedInventory"
GetUnifiedInventoryFunc.Parent = RemoteFunctions

local UnifiedInventoryChangedEvent = RemoteEvents:FindFirstChild("UnifiedInventoryChanged") or Instance.new("RemoteEvent")
UnifiedInventoryChangedEvent.Name = "UnifiedInventoryChanged"
UnifiedInventoryChangedEvent.Parent = RemoteEvents

local InventoryService = {}

--------------------------------------------------------------------------------
-- DATA AGGREGATION
--------------------------------------------------------------------------------

local function waitForBrainrotManager()
	local attempts = 0
	while not (_G.BrainrotManager and _G.BrainrotManager.GetInventoryData) and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.BrainrotManager
end

local function getUnifiedInventory(player)
	local items = {}
	local BrainrotManager = waitForBrainrotManager()
	
	-- 1. Units
	if BrainrotManager and BrainrotManager.GetInventoryData then
		local inventoryData = BrainrotManager.GetInventoryData(player)
		if inventoryData and inventoryData.units then
			for unitName, data in pairs(inventoryData.units) do
				local level = data.level or 0
				if level < 1 then continue end
				
				local config = ShopConfig.GetConfig(unitName)
				local icon = config and config.Icon or "🧠"
				
				local newItem = {
					UUID = unitName,
					Type = "Unit",
					Id = unitName,
					Name = config and config.Name or unitName,
					Rarity = data.rarity or "Normal",
					Icon = icon,
					IsEquipped = false,
					IsPlaced = (data.status == "placed"),
					Data = {
						Level = level,
						Equipment = {},
						Stats = nil,
						EquippedTo = nil,
					}
				}
				table.insert(items, newItem)
			end
		end
	end
	
	-- 2. Artifacts
	if _G.ArtifactManager and _G.ArtifactManager.GetPlayerArtifacts then
		local artifactsData = _G.ArtifactManager.GetPlayerArtifacts(player)
		if artifactsData then
			for guid, data in pairs(artifactsData) do
				local newItem = {
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
-- API
--------------------------------------------------------------------------------

function InventoryService.Init()
	print("   InventoryService (Module) - Initializing")
	
	GetUnifiedInventoryFunc.OnServerInvoke = function(player)
		return getUnifiedInventory(player)
	end
	
	print("✓ InventoryService Initialized")
end

return InventoryService
