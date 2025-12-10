--[[
	DataManager Server Script
	Handles saving and loading player data using DataStoreService.
]]

-- Services
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- DataStore
local PlayerDataStore = DataStoreService:GetDataStore("BrainRotClickerData_v1")

-- Configuration
local CONFIG = {
	AUTO_SAVE_INTERVAL = 300,
	DEFAULT_MONEY = 100,
	RETRY_ATTEMPTS = 3,
}

-- State
local PlayerDataCache = {}
local DataLoaded = {}

-- Helper: Get Default Data
local function getDefaultData()
	return {
		money = CONFIG.DEFAULT_MONEY,
		ownedUnits = {},
		unlockProgress = 5,
		maxStorage = 500,
		purchasedTiers = 1,
		convenienceUpgrades = {},
		-- Prestige
		lifetimeEarnings = 0,
		totalMeatballs = 0,
		spentMeatballs = 0,
		prestigeCount = 0,
		meatballUpgrades = {},
		-- Brainrot
		brainrotInventory = {},
		brainrotPlacements = {},
		-- Items
		itemStorage = {},
		backpack = {},
		storageCapacity = 2000,
		selectedVehicle = "Sneakers",
		vehicleCapacities = {},
		gridPositions = {},
		discoveredSynergies = {},
	}
end

-- Helper: Gather Data
local function gatherPlayerData(player)
	local data = getDefaultData() -- Start with defaults to ensure structure
	
	-- Money
	local ls = player:FindFirstChild("leaderstats")
	if ls and ls:FindFirstChild("Money") then data.money = ls.Money.Value end
	
	-- Shop
	if _G.ShopManager then
		if _G.ShopManager.GetUnlockProgress then data.unlockProgress = _G.ShopManager.GetUnlockProgress(player) end
		local owned = player:FindFirstChild("OwnedUnits")
		if owned then
			for _, v in owned:GetChildren() do if v.Value > 0 then data.ownedUnits[v.Name] = v.Value end end
		end
	end
	
	-- Max Storage
	if _G.BrainrotManager and _G.BrainrotManager.GetPlayerPlot then
		local plot = _G.BrainrotManager.GetPlayerPlot(player)
		if plot then data.maxStorage = plot:GetAttribute("MaxStorage") or 500 end
	end
	
	-- Tiers
	if _G.MapSystem and _G.MapSystem.GetPlayerTierSystem then
		local ts = _G.MapSystem.GetPlayerTierSystem(player)
		if ts then data.purchasedTiers = #ts.Tiers end
	end
	
	-- Upgrades
	if _G.ConvenienceUpgrades and _G.ConvenienceUpgrades.GetPlayerUpgrades then
		data.convenienceUpgrades = _G.ConvenienceUpgrades.GetPlayerUpgrades(player)
	end
	
	-- Prestige
	if _G.PrestigeManager and _G.PrestigeManager.GetPlayerData then
		local pd = _G.PrestigeManager.GetPlayerData(player)
		if pd then
			data.lifetimeEarnings = pd.lifetimeEarnings
			data.totalMeatballs = pd.totalMeatballs
			data.spentMeatballs = pd.spentMeatballs
			data.prestigeCount = pd.prestigeCount
			data.meatballUpgrades = pd.meatballUpgrades
		end
	end
	
	-- Brainrot
	if _G.BrainrotManager then
		if _G.BrainrotManager.GetInventoryData then data.brainrotInventory = _G.BrainrotManager.GetInventoryData(player) end
		if _G.BrainrotManager.GetPlacementData then data.brainrotPlacements = _G.BrainrotManager.GetPlacementData(player) end
	end
	
	-- Item Storage
	if _G.ItemStorageManager then
		if _G.ItemStorageManager.GetStorageContents then data.itemStorage = _G.ItemStorageManager.GetStorageContents(player) end
		if _G.ItemStorageManager.GetBackpackContents then data.backpack = _G.ItemStorageManager.GetBackpackContents(player) end
		if _G.ItemStorageManager.GetStorageCapacity then data.storageCapacity = _G.ItemStorageManager.GetStorageCapacity(player) end
	end
	
	-- Transport
	if _G.TransportManager then
		if _G.TransportManager.GetSelectedVehicle then data.selectedVehicle = _G.TransportManager.GetSelectedVehicle(player) end
		if _G.TransportManager.GetVehicleCapacities then data.vehicleCapacities = _G.TransportManager.GetVehicleCapacities(player) end
	end
	
	-- Grid
	if _G.GridManager and _G.GridManager.GetGridPositions then
		data.gridPositions = _G.GridManager.GetGridPositions(player)
	end
	
	-- Synergies
	if _G.AdjacencySynergyManager and _G.AdjacencySynergyManager.GetDiscoveredSynergies then
		data.discoveredSynergies = _G.AdjacencySynergyManager.GetDiscoveredSynergies(player)
	end
	
	return data
end

-- Save/Load
local function savePlayerData(player)
	local userId = player.UserId
	local data = gatherPlayerData(player)
	local success, err

	for i = 1, CONFIG.RETRY_ATTEMPTS do
		success, err = pcall(function() PlayerDataStore:SetAsync("Player_"..userId, data) end)
		if success then break end
		task.wait(1)
	end

	if not success then warn("Failed to save data for "..player.Name..": "..tostring(err)) end
	return success
end

local function loadPlayerData(player)
	local userId = player.UserId
	local success, data
	
	for i = 1, CONFIG.RETRY_ATTEMPTS do
		success, data = pcall(function() return PlayerDataStore:GetAsync("Player_"..userId) end)
		if success then break end
		task.wait(1)
	end
	
	if success and data then
		-- Backwards compatibility filling
		local default = getDefaultData()
		for k, v in pairs(default) do
			if data[k] == nil then data[k] = v end
		end
		return data
	end
	return getDefaultData()
end

-- Events
local function onPlayerAdded(player)
	local data = loadPlayerData(player)
	PlayerDataCache[player] = data
	
	-- Apply Money
	local ls = player:WaitForChild("leaderstats", 10)
	if ls and ls:WaitForChild("Money", 5) then ls.Money.Value = data.money end
	
	-- Restore Upgrades
	if _G.ConvenienceUpgrades and _G.ConvenienceUpgrades.SetPlayerUpgrades then
		_G.ConvenienceUpgrades.SetPlayerUpgrades(player, data.convenienceUpgrades)
	end
	
	-- Restore Shop Data
	task.spawn(function()
		task.wait(1) -- Wait for managers
		if _G.ShopManager and _G.ShopManager.SetPlayerData then
			_G.ShopManager.SetPlayerData(player, data.ownedUnits, data.unlockProgress)
		end
		
		-- Restore Tiers
		if data.purchasedTiers > 1 and _G.MapSystem and _G.MapSystem.RestoreTiers then
			_G.MapSystem.RestoreTiers(player, data.purchasedTiers)
		end
		
		-- Restore Brainrot Inventory
		if _G.BrainrotManager and _G.BrainrotManager.SetInventoryData then
			local inv = {}
			for u, rData in pairs(data.brainrotInventory) do
				inv[u] = {}
				for r, counts in pairs(rData) do inv[u][r] = {total = counts.total, active = 0} end
			end
			_G.BrainrotManager.SetInventoryData(player, inv)
		end
		
		-- Restore Placements
		task.wait(0.5)
		if data.brainrotPlacements and #data.brainrotPlacements > 0 and _G.BrainrotManager and _G.BrainrotManager.SpawnFromPlacement then
			for _, pData in ipairs(data.brainrotPlacements) do
				local unit = _G.BrainrotManager.SpawnFromPlacement(player, pData)
				if unit and _G.BrainrotManager.GetInventoryData then
					-- Update active count manually if SpawnFromPlacement doesn't (it seems it doesn't in original)
					local inv = _G.BrainrotManager.GetInventoryData(player)
					if inv[pData.unitType] and inv[pData.unitType][pData.rarity] then
						inv[pData.unitType][pData.rarity].active += 1
					end
				end
			end
		end
		
		-- Restore Prestige
		if _G.PrestigeManager and _G.PrestigeManager.InitializePlayerData then
			_G.PrestigeManager.InitializePlayerData(player, data)
		end
	end)
	
	DataLoaded[player] = true
end

local function onPlayerRemoving(player)
	if DataLoaded[player] then savePlayerData(player) end
	PlayerDataCache[player] = nil
	DataLoaded[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, p in Players:GetPlayers() do task.spawn(onPlayerAdded, p) end

-- Auto Save
task.spawn(function()
	while true do
		task.wait(CONFIG.AUTO_SAVE_INTERVAL)
		for _, p in Players:GetPlayers() do if DataLoaded[p] then task.spawn(savePlayerData, p) end end
	end
end)

game:BindToClose(function()
	for _, p in Players:GetPlayers() do if DataLoaded[p] then task.spawn(savePlayerData, p) end end
	if not RunService:IsStudio() then task.wait(5) end
end)

_G.DataManager = {
	SavePlayerData = savePlayerData,
	LoadPlayerData = loadPlayerData,
	GetCachedData = function(p) return PlayerDataCache[p] end,
	ResetPlayerData = function(p, keepPrestige)
		local old = PlayerDataCache[p]
		local new = getDefaultData()
		if keepPrestige and old then
			new.lifetimeEarnings = old.lifetimeEarnings
			new.totalMeatballs = old.totalMeatballs
			new.spentMeatballs = old.spentMeatballs
			new.prestigeCount = old.prestigeCount
			new.meatballUpgrades = old.meatballUpgrades
			if _G.PrestigeManager and _G.PrestigeManager.GetStartingMoneyBonus then
				new.money += _G.PrestigeManager.GetStartingMoneyBonus(p)
			end
		end
		PlayerDataCache[p] = new
		savePlayerData(p)
		return new
	end
}

print("✓ DataManager Initialized")
