--[[
	InventoryManager Server Script

	The Single Source of Truth for player unit inventory state.
	
	REFACTORED: Now uses DataService component-based persistence.
	Inventory data is stored directly in Profile.Data.Inventory.

	Responsibilities:
	- Store which units a player owns, their levels, and rarities.
	- Handle data persistence via DataService (ProfileService).
	- Notify other systems (BrainrotManager, ShopManager) of changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
-- PUBLIC API
--------------------------------------------------------------------------------

local InventoryManager = {}

-- Signal for server-side listeners (BrainrotManager)
local UnitChangedSignal = Instance.new("BindableEvent")
InventoryManager.UnitChanged = UnitChangedSignal.Event

--[[
	Gets the inventory table reference from Profile.Data.
	This is the authoritative source of truth.
]]
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

--[[
	Initialize inventory for a player.
	Called when player joins (before DataService loads).
]]
function InventoryManager.InitPlayer(player: Player)
	-- No-op: DataService will initialize the data when profile loads
	-- We keep this for backwards compatibility
end

--[[
	Cleans up player data.
	Called when player leaves (after DataService saves).
]]
function InventoryManager.CleanupPlayer(player: Player)
	-- No-op: DataService handles cleanup
	-- We keep this for backwards compatibility
end

--[[
	Sets the entire inventory for a player (used by Data Loading).
	Expected Data Format: { [UnitName]: { level: number, rarity: string } }
]]
function InventoryManager.SetInventory(player: Player, data: {[string]: any})
	DataService.SetComponentData(player, COMPONENT_KEY, data or {})
	-- Notify listeners of full reload (pass nil unitName)
	UnitChangedSignal:Fire(player, nil, nil)
end

--[[
	Gets the entire inventory for a player.
]]
function InventoryManager.GetInventory(player: Player): {[string]: any}
	return getInventoryData(player) or {}
end

--[[
	Gets the data for a specific unit.
]]
function InventoryManager.GetUnit(player: Player, unitName: string): {level: number, rarity: string}?
	local inventory = getInventoryData(player)
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
function InventoryManager.AddUnit(player: Player, unitName: string, rarity: string?, level: number?): {level: number, rarity: string}?
	local inventory = getInventoryData(player)
	if not inventory then
		warn("InventoryManager: Profile not loaded for " .. player.Name)
		return nil
	end

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

	-- Update directly in Profile.Data.Inventory (auto-saved by ProfileService)
	inventory[unitName] = newData

	-- Notify Server Listeners (BrainrotManager will spawn/update model)
	UnitChangedSignal:Fire(player, unitName, newData)

	-- Notify Client (UI)
	InventoryChangedEvent:FireClient(player, unitName, newData)

	return newData
end

--------------------------------------------------------------------------------
-- DATA SERVICE HANDLER
--------------------------------------------------------------------------------

-- Register with DataService for automatic persistence
DataService.RegisterHandler(COMPONENT_KEY, {
	DefaultData = {},
	
	OnLoad = function(player: Player, data: any)
		-- Data is already in Profile.Data.Inventory
		-- Just fire the change signal to notify BrainrotManager
		print(string.format("InventoryManager: Loaded %d units for %s", 
			data and #(function() local c=0; for _ in pairs(data) do c+=1 end; return c end)() or 0,
			player.Name))
		
		-- Fire reload signal so BrainrotManager can spawn units
		task.defer(function()
			UnitChangedSignal:Fire(player, nil, nil)
		end)
	end,
	
	OnSave = function(player: Player, data: any)
		-- Data is already kept up-to-date in Profile.Data.Inventory
		-- No additional work needed
		return data
	end
})

--------------------------------------------------------------------------------
-- INIT & EXPORT
--------------------------------------------------------------------------------

-- Backwards compatibility: Still connect to player events
-- (though DataService handles the actual lifecycle)
Players.PlayerAdded:Connect(InventoryManager.InitPlayer)
Players.PlayerRemoving:Connect(InventoryManager.CleanupPlayer)

-- Handle existing players
for _, player in Players:GetPlayers() do
	InventoryManager.InitPlayer(player)
end

_G.InventoryManager = InventoryManager

return InventoryManager
