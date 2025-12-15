--[[
	InventoryManager Server Module
	
	The Single Source of Truth for player unit inventory state.
	
	CONVERTED TO MODULE SCRIPT
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RarityConfig = require(Shared:WaitForChild("RarityConfig"))

-- DataService for persistence
local DataService = require(script.Parent.DataService)

-- Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local InventoryChangedEvent = RemoteEvents:FindFirstChild("InventoryChanged") or Instance.new("RemoteEvent")
InventoryChangedEvent.Name = "InventoryChanged"
InventoryChangedEvent.Parent = RemoteEvents

-- Component key for DataService
local COMPONENT_KEY = "Inventory"

--------------------------------------------------------------------------------
-- MODULE DEFINITION
--------------------------------------------------------------------------------

local InventoryManager = {}

-- Signal for server-side listeners (BrainrotManager)
local UnitChangedSignal = Instance.new("BindableEvent")
InventoryManager.UnitChanged = UnitChangedSignal.Event

-- Internal helper
local function getInventoryData(player: Player): {[string]: any}?
	local data = DataService.GetComponentData(player, COMPONENT_KEY)
	if data then
		return data
	end
	
	-- Initialize if not exists and profile is loaded
	if DataService.IsLoaded(player) then
		DataService.SetComponentData(player, COMPONENT_KEY, {})
		return DataService.GetComponentData(player, COMPONENT_KEY)
	end
	
	return nil
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function InventoryManager.Init()
	print("   InventoryManager (Module) - Initializing")
	
	-- Register with DataService
	DataService.RegisterHandler(COMPONENT_KEY, {
		DefaultData = {},
		OnLoad = function(player: Player, data: any)
			local unitCount = 0
			if data and type(data) == "table" then
				for _ in pairs(data) do unitCount += 1 end
			end
			print(string.format("InventoryManager: Loaded %d units for %s", unitCount, player.Name))
			
			task.defer(function()
				UnitChangedSignal:Fire(player, nil, nil)
			end)
		end,
		OnSave = function(player: Player, data: any)
			return data
		end
	})
	
	-- Backwards compatibility hooks
	Players.PlayerAdded:Connect(InventoryManager.InitPlayer)
	
	print("✓ InventoryManager Initialized")
end

function InventoryManager.InitPlayer(player: Player)
	-- No-op: DataService handles initialization
end

function InventoryManager.SetInventory(player: Player, data: {[string]: any})
	DataService.SetComponentData(player, COMPONENT_KEY, data or {})
	UnitChangedSignal:Fire(player, nil, nil)
end

function InventoryManager.GetInventory(player: Player): {[string]: any}
	return getInventoryData(player) or {}
end

function InventoryManager.GetUnit(player: Player, unitName: string): {level: number, rarity: string}?
	local inventory = getInventoryData(player)
	return inventory and inventory[unitName]
end

function InventoryManager.GetUnitLevel(player: Player, unitName: string): number
	local unitData = InventoryManager.GetUnit(player, unitName)
	return unitData and unitData.level or 0
end

function InventoryManager.AddUnit(player: Player, unitName: string, rarity: string?, level: number?): {level: number, rarity: string}?
	local inventory = getInventoryData(player)
	if not inventory then
		-- Use pcall/warn instead of error to not crash bootstrapper if early
		warn("InventoryManager: Profile not loaded for " .. player.Name)
		return nil
	end

	local currentData = inventory[unitName]

	local newLevel = level
	local newRarity = rarity or "Normal"

	if currentData then
		if not newLevel then
			newLevel = currentData.level + 1
		end
		
		if rarity then
			local currentRank = RarityConfig.GetRarityValue(currentData.rarity)
			local newRank = RarityConfig.GetRarityValue(rarity)

			if newRank > currentRank then
				newRarity = rarity
			else
				newRarity = currentData.rarity
			end
		else
			newRarity = currentData.rarity
		end
	else
		if not newLevel then
			newLevel = 1
		end
	end

	local newData = {
		level = newLevel,
		rarity = newRarity,
		unitId = currentData and currentData.unitId or HttpService:GenerateGUID(false)
	}

	inventory[unitName] = newData

	UnitChangedSignal:Fire(player, unitName, newData)
	InventoryChangedEvent:FireClient(player, unitName, newData)

	return newData
end

return InventoryManager
