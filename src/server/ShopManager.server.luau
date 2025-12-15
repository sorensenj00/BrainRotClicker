--[[
	ShopManager Server Script
	
	Handles all purchase logic for the shop system.
	Creates RemoteFunctions for clients to buy units.
	Tracks progressive unlock progress per player.
	
	Price Formula: BasePrice * (CostMultiplier ^ AmountOwned)
	Income/CycleTime: Affected by milestones at 10/25/50/100/200/300/400/500
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local RarityConfig = require(Shared:WaitForChild("RarityConfig"))

-- Wait for Managers API (loaded via _G)
local function waitForBrainrotManager()
	local attempts = 0
	while not _G.BrainrotManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.BrainrotManager
end

local function waitForInventoryManager()
	local attempts = 0
	while not _G.InventoryManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.InventoryManager
end

-- Remote setup
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

-- Create BuyUnit RemoteFunction
local BuyUnitRemote = Instance.new("RemoteFunction")
BuyUnitRemote.Name = "BuyUnit"
BuyUnitRemote.Parent = RemoteEvents

-- Create RemoteEvent for ownership updates (to sync client UI)
local OwnershipChangedEvent = Instance.new("RemoteEvent")
OwnershipChangedEvent.Name = "OwnershipChanged"
OwnershipChangedEvent.Parent = RemoteEvents

-- Create RemoteEvent for unlock progress updates
local UnlockProgressChangedEvent = Instance.new("RemoteEvent")
UnlockProgressChangedEvent.Name = "UnlockProgressChanged"
UnlockProgressChangedEvent.Parent = RemoteEvents

--------------------------------------------------------------------------------
-- PLAYER DATA
--------------------------------------------------------------------------------

--[[
	Stores how many units are unlocked for each player.
	Starts at INITIAL_UNLOCKED (5).
]]
local PlayerUnlockProgress: {[Player]: number} = {}

--[[
	Initializes ownership tracking for a player.
	NOTE: Leaderstats are created by DataManager, not here.
]]
local function initializePlayerData(player: Player)
	PlayerUnlockProgress[player] = ShopConfig.INITIAL_UNLOCKED
	
	-- Create an "OwnedUnits" folder under player for easy inspection (Legacy/Visual)
	local ownedFolder = Instance.new("Folder")
	ownedFolder.Name = "OwnedUnits"
	ownedFolder.Parent = player
	
	-- Create IntValue for each unit type
	for unitName, _ in ShopConfig.Units do
		local countValue = Instance.new("IntValue")
		countValue.Name = unitName
		countValue.Value = 0
		countValue.Parent = ownedFolder
	end
	
	-- Create IntValue for unlock progress
	local unlockValue = Instance.new("IntValue")
	unlockValue.Name = "UnlockProgress"
	unlockValue.Value = ShopConfig.INITIAL_UNLOCKED
	unlockValue.Parent = player
	
	print(string.format("✓ Initialized shop data for %s (Unlocked: %d units)", player.Name, ShopConfig.INITIAL_UNLOCKED))
end

--[[
	Gets how many of a specific unit a player owns.
]]
local function getOwnedCount(player: Player, unitName: string): number
	if _G.InventoryManager then
		return _G.InventoryManager.GetUnitLevel(player, unitName)
	end
	return 0
end

--[[
	Gets the unlock progress for a player.
]]
local function getUnlockProgress(player: Player): number
	return PlayerUnlockProgress[player] or ShopConfig.INITIAL_UNLOCKED
end

--[[
	Increments the unlock progress for a player.
	Called when they purchase any unlocked unit.
]]
local function incrementUnlockProgress(player: Player)
	local currentProgress = getUnlockProgress(player)
	local totalUnits = ShopConfig.GetTotalUnits()
	
	-- Only increment if not at max
	if currentProgress < totalUnits then
		PlayerUnlockProgress[player] = currentProgress + 1
		
		-- Update the IntValue for debugging
		local unlockValue = player:FindFirstChild("UnlockProgress")
		if unlockValue then
			unlockValue.Value = PlayerUnlockProgress[player]
		end
		
		-- Notify client of unlock progress change
		UnlockProgressChangedEvent:FireClient(player, PlayerUnlockProgress[player])
		
		print(string.format("✓ %s unlocked unit #%d", player.Name, PlayerUnlockProgress[player]))
	end
end

--[[
	Updates the IntValue for legacy replication.
	Does NOT manage state (that's InventoryManager now).
]]
local function updateLegacyOwnedCount(player: Player, unitName: string, count: number)
	local ownedFolder = player:FindFirstChild("OwnedUnits")
	if ownedFolder then
		local countValue = ownedFolder:FindFirstChild(unitName)
		if countValue then
			countValue.Value = count
		end
	end
end

--[[
	Cleans up player data when they leave.
]]
local function cleanupPlayerData(player: Player)
	PlayerUnlockProgress[player] = nil
end

--------------------------------------------------------------------------------
-- CURRENCY FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Gets the player's current money.
]]
local function getMoney(player: Player): number
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local money = leaderstats:FindFirstChild("Money")
		if money then
			return money.Value
		end
	end
	return 0
end

--[[
	Deducts money from the player.
	Returns true if successful, false if not enough money.
]]
local function deductMoney(player: Player, amount: number): boolean
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return false end
	
	local money = leaderstats:FindFirstChild("Money")
	if not money then return false end
	
	if money.Value >= amount then
		money.Value = money.Value - amount
		return true
	end
	
	return false
end

--------------------------------------------------------------------------------
-- PURCHASE LOGIC
--------------------------------------------------------------------------------

--[[
	Handles a purchase request from a client.
	
	@param player Player - The player making the purchase
	@param unitName string - The name of the unit to buy
	@return boolean, string? - Success status and optional message
]]
local function handleBuyUnit(player: Player, unitName: string): (boolean, string?)
	-- Security: Verify player is near ShopVendor on Main Island
	local mainIsland = workspace:FindFirstChild("MainIsland")
	local shopVendor = mainIsland and mainIsland:FindFirstChild("ShopVendor")
	if shopVendor then
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local distance = (hrp.Position - shopVendor.Position).Magnitude
			if distance > 20 then
				return false, "You must be at the shop to make purchases!"
			end
		end
	end
	
	-- Validate unit exists
	local unitConfig = ShopConfig.GetConfig(unitName)
	if not unitConfig then
		return false, "Unknown unit: " .. tostring(unitName)
	end
	
	-- Check if unit is unlocked for this player
	local unlockProgress = getUnlockProgress(player)
	if not ShopConfig.IsUnitUnlocked(unitName, unlockProgress) then
		return false, "This unit is locked! Purchase other units to unlock."
	end
	
	-- Calculate current price based on owned count
	local ownedCount = getOwnedCount(player, unitName)
	local currentPrice = ShopConfig.CalculatePrice(unitName, ownedCount)
	
	-- Check if player has enough money
	local playerMoney = getMoney(player)
	if playerMoney < currentPrice then
		return false, string.format("Not enough money! Need $%d, have $%d", currentPrice, playerMoney)
	end
	
	-- Deduct money
	if not deductMoney(player, currentPrice) then
		return false, "Failed to deduct money"
	end
	
	-- Spawn or Upgrade the unit via InventoryManager
	local InventoryManager = waitForInventoryManager()

	if InventoryManager then
		-- 1. Roll Rarity
		local rarity = RarityConfig.RollRarity()
		
		-- 2. Update Inventory (Authoritative State)
		-- This returns the new data {level, rarity}
		local newData = InventoryManager.AddUnit(player, unitName, rarity)
		local newLevel = newData.level
		
		-- 3. Update Legacy Visuals (IntValues)
		updateLegacyOwnedCount(player, unitName, newLevel)
		
		-- 4. Check Milestones
		local oldMilestones = ShopConfig.GetMilestonesReached(newLevel - 1)
		local newMilestones = ShopConfig.GetMilestonesReached(newLevel)
		
		if #newMilestones > #oldMilestones then
			print(string.format("⭐ %s reached milestone for %s! (%d→%d milestones)", 
				player.Name, unitName, #oldMilestones, #newMilestones))
		end
		
		-- 5. Notify client of ownership change (for UI update)
		local newPrice = ShopConfig.CalculatePrice(unitName, newLevel)
		OwnershipChangedEvent:FireClient(player, unitName, newLevel, newPrice)

		print(string.format("✓ %s upgraded %s to Level %d for $%d", player.Name, unitName, newLevel, currentPrice))
		
		-- Increment unlock progress (unlock next unit)
		incrementUnlockProgress(player)
		
		return true, "Purchase successful!"

	else
		warn("InventoryManager not available!")
		-- Refund
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats and leaderstats:FindFirstChild("Money") then
			leaderstats.Money.Value = leaderstats.Money.Value + currentPrice
		end
		return false, "Server error: inventory system unavailable"
	end
	
end

--------------------------------------------------------------------------------
-- API FOR OTHER SCRIPTS
--------------------------------------------------------------------------------

--[[
	Gets all ownership data for a player (for initial UI sync).
	Now includes unlock progress.
]]
local function getPlayerOwnership(player: Player): {units: {[string]: {count: number, price: number}}, unlockProgress: number}
	local data = {
		units = {},
		unlockProgress = getUnlockProgress(player),
	}
	
	for unitName, _ in ShopConfig.Units do
		local count = getOwnedCount(player, unitName)
		local price = ShopConfig.CalculatePrice(unitName, count)
		data.units[unitName] = {
			count = count,
			price = price,
		}
	end
	
	return data
end

-- Create RemoteFunction to get initial ownership data
local GetOwnershipRemote = Instance.new("RemoteFunction")
GetOwnershipRemote.Name = "GetOwnership"
GetOwnershipRemote.Parent = RemoteEvents

GetOwnershipRemote.OnServerInvoke = function(player: Player)
	return getPlayerOwnership(player)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   ShopManager - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Connect player events
	Players.PlayerAdded:Connect(initializePlayerData)
	Players.PlayerRemoving:Connect(cleanupPlayerData)
	
	-- Handle existing players
	for _, player in Players:GetPlayers() do
		task.spawn(initializePlayerData, player)
	end
	
	-- Connect buy remote
	BuyUnitRemote.OnServerInvoke = handleBuyUnit
	
	print(string.format("✓ ShopManager initialized (%d total units)", ShopConfig.GetTotalUnits()))
	print(string.format("  • Initial unlocked: %d units", ShopConfig.INITIAL_UNLOCKED))
	print("  • BuyUnit RemoteFunction ready")
	print("  • GetOwnership RemoteFunction ready")
	print("  • OwnershipChanged RemoteEvent ready")
	print("  • UnlockProgressChanged RemoteEvent ready")
	print("═══════════════════════════════════════════")
end

initialize()

--[[
	Sets player data from saved data (called by DataManager on load).
	
	@param player Player - The player to set data for
	@param ownedUnits table - Dictionary of {unitName: count}
	@param unlockProgress number - How many units are unlocked
]]
local function setPlayerData(player: Player, ownedUnits: {[string]: number}, unlockProgress: number)
	-- Set unlock progress
	PlayerUnlockProgress[player] = unlockProgress
	
	local unlockValue = player:FindFirstChild("UnlockProgress")
	if unlockValue then
		unlockValue.Value = unlockProgress
	end
	
	-- Set legacy owned units visuals (Actual data is in InventoryManager now)
	-- ownedUnits here comes from DataManager, which might still pass the simple count map
	-- if it constructed it from InventoryManager.
	
	local ownedFolder = player:FindFirstChild("OwnedUnits")
	
	for unitName, count in pairs(ownedUnits) do
		if ownedFolder then
			local countValue = ownedFolder:FindFirstChild(unitName)
			if countValue then
				countValue.Value = count
			end
		end
	end
	
	-- Notify client of updated unlock progress
	UnlockProgressChangedEvent:FireClient(player, unlockProgress)
	
	-- Notify client of all owned unit counts
	for unitName, count in pairs(ownedUnits) do
		local price = ShopConfig.CalculatePrice(unitName, count)
		OwnershipChangedEvent:FireClient(player, unitName, count, price)
	end
	
	print(string.format("✓ Loaded saved data for %s: %d units unlocked", player.Name, unlockProgress))
end

-- Export for other scripts
_G.ShopManager = {
	GetOwnedCount = getOwnedCount,
	GetPlayerOwnership = getPlayerOwnership,
	GetUnlockProgress = getUnlockProgress,
	SetPlayerData = setPlayerData,
	ResetPlayerData = function(player: Player)
		-- Reset unlock progress
		PlayerUnlockProgress[player] = ShopConfig.INITIAL_UNLOCKED
		
		-- Update the IntValue for unlock progress
		local unlockValue = player:FindFirstChild("UnlockProgress")
		if unlockValue then
			unlockValue.Value = ShopConfig.INITIAL_UNLOCKED
		end
		
		-- Update owned unit IntValues
		local ownedFolder = player:FindFirstChild("OwnedUnits")
		if ownedFolder then
			for unitName, _ in ShopConfig.Units do
				local countValue = ownedFolder:FindFirstChild(unitName)
				if countValue then
					countValue.Value = 0
				end
			end
		end
		
		-- Notify client
		UnlockProgressChangedEvent:FireClient(player, ShopConfig.INITIAL_UNLOCKED)
		for unitName, _ in ShopConfig.Units do
			local price = ShopConfig.CalculatePrice(unitName, 0)
			OwnershipChangedEvent:FireClient(player, unitName, 0, price)
		end
		
		print(string.format("✓ Reset shop data for %s", player.Name))
	end,
}

