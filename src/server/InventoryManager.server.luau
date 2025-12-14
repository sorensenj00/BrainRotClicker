--[[
	InventoryManager Server Script

	The Single Source of Truth for player unit inventory state.

	Responsibilities:
	- Store which units a player owns, their levels, and rarities.
	- Handle data persistence via DataService.
	- Notify other systems (BrainrotManager, ShopManager) of changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RarityConfig = require(Shared:WaitForChild("RarityConfig"))

-- Data Service
local DataService = require(script.Parent.DataService)

-- Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local InventoryChangedEvent = RemoteEvents:FindFirstChild("InventoryChanged") or Instance.new("RemoteEvent")
InventoryChangedEvent.Name = "InventoryChanged"
InventoryChangedEvent.Parent = RemoteEvents

-- Internal State
-- Structure: { [Player]: { [UnitName]: { level: number, rarity: string } } }
local PlayerInventory = {}

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

local InventoryManager = {}

-- Signal for server-side listeners (BrainrotManager)
local UnitChangedSignal = Instance.new("BindableEvent")
InventoryManager.UnitChanged = UnitChangedSignal.Event

--[[
	Sets the entire inventory for a player (used by Data Loading).
	Expected Data Format: { [UnitName]: { level: number, rarity: string } }
]]
function InventoryManager.SetInventory(player: Player, data: {[string]: any})
	PlayerInventory[player] = data or {}
	-- Notify listeners of full reload (pass nil unitName)
	UnitChangedSignal:Fire(player, nil, nil)
end

--------------------------------------------------------------------------------
-- DATA HANDLERS (ProfileService)
--------------------------------------------------------------------------------

local function onLoad(player: Player, data: any)
	InventoryManager.SetInventory(player, data)
	print("InventoryManager: Loaded data for " .. player.Name)
end

local function onSave(player: Player)
	return PlayerInventory[player] or {}
end

-- Register with DataService
DataService.RegisterHandler("Inventory", {
	DefaultData = {},
	OnLoad = onLoad,
	OnSave = onSave
})

--[[
	Gets the entire inventory for a player.
]]
function InventoryManager.GetInventory(player: Player)
	return PlayerInventory[player] or {}
end

--[[
	Gets the data for a specific unit.
]]
function InventoryManager.GetUnit(player: Player, unitName: string)
	local inventory = PlayerInventory[player]
	return inventory and inventory[unitName]
end

--[[
	Gets the level (count) of a unit. Returns 0 if not owned.
]]
function InventoryManager.GetUnitLevel(player: Player, unitName: string): number
	local unitData = InventoryManager.GetUnit(player, unitName)
	return unitData and unitData.level or 0
end

--[[
	Adds or updates a unit in the inventory.
	If the unit exists, it upgrades the level.
	It also handles Rarity upgrades (keeps the best rarity).

	@param player Player
	@param unitName string
	@param rarity string (Optional, default "Normal")
	@param level number (Optional, default +1)
	@return {level: number, rarity: string} - The updated unit data
]]
function InventoryManager.AddUnit(player: Player, unitName: string, rarity: string?, level: number?)
	if not PlayerInventory[player] then
		PlayerInventory[player] = {}
	end

	local inventory = PlayerInventory[player]
	local currentData = inventory[unitName]

	local newLevel = level
	local newRarity = rarity or "Normal"

	if currentData then
		-- Upgrade existing
		if not newLevel then
			newLevel = currentData.level + 1
		end

		-- Logic: Always upgrade level. Only upgrade rarity if better.
		if rarity then
			local currentRank = RarityConfig.GetRarityValue(currentData.rarity)
			local newRank = RarityConfig.GetRarityValue(rarity)

			if newRank > currentRank then
				newRarity = rarity
			else
				newRarity = currentData.rarity -- Keep existing better rarity
			end
		else
			newRarity = currentData.rarity -- Keep existing if not specified
		end

	else
		-- New Unit
		if not newLevel then
			newLevel = 1
		end
	end

	local newData = {
		level = newLevel,
		rarity = newRarity
	}

	inventory[unitName] = newData

	-- Notify Server Listeners (BrainrotManager will spawn/update model)
	UnitChangedSignal:Fire(player, unitName, newData)

	-- Notify Client (UI)
	InventoryChangedEvent:FireClient(player, unitName, newData)

	return newData
end

--------------------------------------------------------------------------------
-- INIT & EXPORT
--------------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	PlayerInventory[player] = nil
end)

_G.InventoryManager = InventoryManager

return InventoryManager
