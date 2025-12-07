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
local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopConfig"))

-- Wait for BrainrotManager API (loaded via _G)
local function waitForBrainrotManager()
	local attempts = 0
	while not _G.BrainrotManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.BrainrotManager
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
	Stores how many of each unit a player owns.
	Structure: PlayerOwnedUnits[Player] = { ["Hand Gesture"] = 3, ... }
]]
local PlayerOwnedUnits: {[Player]: {[string]: number}} = {}

--[[
	Stores how many units are unlocked for each player.
	Starts at INITIAL_UNLOCKED (5).
]]
local PlayerUnlockProgress: {[Player]: number} = {}

--[[
	Initializes ownership tracking for a player.
]]
local function initializePlayerData(player: Player)
	PlayerOwnedUnits[player] = {}
	PlayerUnlockProgress[player] = ShopConfig.INITIAL_UNLOCKED
	
	-- Initialize all units to 0
	for unitName, _ in ShopConfig.Units do
		PlayerOwnedUnits[player][unitName] = 0
	end
	
	-- Create an "OwnedUnits" folder under player for easy inspection
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
	if not PlayerOwnedUnits[player] then
		return 0
	end
	return PlayerOwnedUnits[player][unitName] or 0
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
	Increments the owned count for a unit and updates the IntValue.
]]
local function incrementOwnedCount(player: Player, unitName: string)
	if not PlayerOwnedUnits[player] then
		PlayerOwnedUnits[player] = {}
	end
	
	PlayerOwnedUnits[player][unitName] = (PlayerOwnedUnits[player][unitName] or 0) + 1
	
	-- Update the IntValue for replication
	local ownedFolder = player:FindFirstChild("OwnedUnits")
	if ownedFolder then
		local countValue = ownedFolder:FindFirstChild(unitName)
		if countValue then
			countValue.Value = PlayerOwnedUnits[player][unitName]
		end
	end
end

--[[
	Cleans up player data when they leave.
]]
local function cleanupPlayerData(player: Player)
	PlayerOwnedUnits[player] = nil
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
	
	-- Spawn the brainrot unit
	local BrainrotManager = waitForBrainrotManager()
	if BrainrotManager then
		local spawnedUnit = BrainrotManager.SpawnBrainrot(player, unitConfig.ModelName)
		if not spawnedUnit then
			-- Refund if spawn failed
			local leaderstats = player:FindFirstChild("leaderstats")
			if leaderstats and leaderstats:FindFirstChild("Money") then
				leaderstats.Money.Value = leaderstats.Money.Value + currentPrice
			end
			return false, "Failed to spawn unit on plot"
		end
		
		-- Roll for rarity (RNG Traits system)
		local rolledRarity = BrainrotManager.RollRarity and BrainrotManager.RollRarity() or "Normal"
		local rarityConfig = BrainrotManager.RARITY_CONFIG and BrainrotManager.RARITY_CONFIG[rolledRarity]
		local rarityMultiplier = rarityConfig and rarityConfig.incomeMultiplier or 1
		
		-- Calculate new count BEFORE updating (for correct milestone calc)
		local newCount = ownedCount + 1
		
		-- Set income values using milestone-aware calculations, with rarity multiplier
		local effectiveIncome = ShopConfig.CalculateEffectiveIncome(unitName, newCount)
		local effectiveCycleTime = ShopConfig.CalculateEffectiveCycleTime(unitName, newCount)
		
		-- Apply rarity multiplier to income
		local finalIncome = effectiveIncome * rarityMultiplier
		
		spawnedUnit:SetAttribute("IncomeAmount", finalIncome)
		spawnedUnit:SetAttribute("IncomeInterval", effectiveCycleTime)
		spawnedUnit:SetAttribute("UnitType", unitName)
		spawnedUnit:SetAttribute("Rarity", rolledRarity)
		
		-- Check if we crossed a milestone - if so, update ALL units of this type
		local oldMilestones = ShopConfig.GetMilestonesReached(ownedCount)
		local newMilestones = ShopConfig.GetMilestonesReached(newCount)
		
		if #newMilestones > #oldMilestones then
			-- Milestone was crossed! Update all existing units of this type
			BrainrotManager.UpdateAllUnitStats(player, unitName, effectiveIncome, effectiveCycleTime)
			print(string.format("⭐ %s reached milestone for %s! (%d→%d milestones)", 
				player.Name, unitName, #oldMilestones, #newMilestones))
		end
		
		-- Add to inventory tracking WITH rarity
		if BrainrotManager.AddToInventory then
			BrainrotManager.AddToInventory(player, unitName, rolledRarity)
		end
		
		-- Log special rarity rolls
		if rolledRarity ~= "Normal" then
			local rarityDisplay = rarityConfig and rarityConfig.displayName or rolledRarity
			print(string.format("🎲 %s rolled %s %s! (%dx income)", 
				player.Name, rarityDisplay, unitName, rarityMultiplier))
		end
	else
		warn("BrainrotManager not available!")
		return false, "Server error: spawn system unavailable"
	end
	
	-- Increment owned count
	incrementOwnedCount(player, unitName)
	
	-- Increment unlock progress (unlock next unit)
	incrementUnlockProgress(player)
	
	-- Notify client of ownership change (for UI update)
	local newCount = getOwnedCount(player, unitName)
	local newPrice = ShopConfig.CalculatePrice(unitName, newCount)
	OwnershipChangedEvent:FireClient(player, unitName, newCount, newPrice)
	
	print(string.format("✓ %s bought %s (#%d) for $%d", player.Name, unitName, newCount, currentPrice))
	
	return true, "Purchase successful!"
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
	
	-- Set owned units
	if not PlayerOwnedUnits[player] then
		PlayerOwnedUnits[player] = {}
	end
	
	local ownedFolder = player:FindFirstChild("OwnedUnits")
	
	for unitName, count in ownedUnits do
		PlayerOwnedUnits[player][unitName] = count
		
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
	for unitName, count in ownedUnits do
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
}

