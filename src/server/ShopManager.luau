--[[
	ShopManager Server Module
	
	Handles all purchase logic for the shop system.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Lazy Configs
local ShopConfig
local RarityConfig

local function getConfigs()
	if not ShopConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		ShopConfig = require(Shared:WaitForChild("ShopConfig"))
		RarityConfig = require(Shared:WaitForChild("RarityConfig"))
	end
	return ShopConfig, RarityConfig
end

-- Remotes
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local BuyUnitRemote = RemoteEvents:FindFirstChild("BuyUnit") or Instance.new("RemoteFunction")
BuyUnitRemote.Name = "BuyUnit"
BuyUnitRemote.Parent = RemoteEvents

local OwnershipChangedEvent = RemoteEvents:FindFirstChild("OwnershipChanged") or Instance.new("RemoteEvent")
OwnershipChangedEvent.Name = "OwnershipChanged"
OwnershipChangedEvent.Parent = RemoteEvents

local UnlockProgressChangedEvent = RemoteEvents:FindFirstChild("UnlockProgressChanged") or Instance.new("RemoteEvent")
UnlockProgressChangedEvent.Name = "UnlockProgressChanged"
UnlockProgressChangedEvent.Parent = RemoteEvents

local GetOwnershipRemote = RemoteEvents:FindFirstChild("GetOwnership") or Instance.new("RemoteFunction")
GetOwnershipRemote.Name = "GetOwnership"
GetOwnershipRemote.Parent = RemoteEvents

-- Module
local ShopManager = {}
local Services = {}

-- State
local PlayerUnlockProgress = {} 

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function initializePlayerData(player)
	PlayerUnlockProgress[player] = ShopConfig.INITIAL_UNLOCKED
	
	-- Visual folder (Legacy)
	local ownedFolder = Instance.new("Folder")
	ownedFolder.Name = "OwnedUnits"
	ownedFolder.Parent = player
	
	for unitName, _ in pairs(ShopConfig.Units) do
		local c = Instance.new("IntValue")
		c.Name = unitName
		c.Value = 0
		c.Parent = ownedFolder
	end
	
	local unlockValue = Instance.new("IntValue")
	unlockValue.Name = "UnlockProgress"
	unlockValue.Value = ShopConfig.INITIAL_UNLOCKED
	unlockValue.Parent = player
end

local function cleanupPlayerData(player)
	PlayerUnlockProgress[player] = nil
end

local function getMoney(player)
	local ls = player:FindFirstChild("leaderstats")
	return ls and ls:FindFirstChild("Money") and ls.Money.Value or 0
end

local function deductMoney(player, amount)
	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	if m and m.Value >= amount then
		m.Value -= amount
		return true
	end
	return false
end

local function updateLegacyOwnedCount(player, unitName, count)
	local f = player:FindFirstChild("OwnedUnits")
	if f then
		local c = f:FindFirstChild(unitName)
		if c then c.Value = count end
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API & CORE LOGIC
--------------------------------------------------------------------------------

function ShopManager.Init(services)
	print("   ShopManager (Module) - Initializing")
	Services = services or {}
	
	Players.PlayerAdded:Connect(initializePlayerData)
	Players.PlayerRemoving:Connect(cleanupPlayerData)
	
	-- Preload Configs
	getConfigs()
	
	for _, p in Players:GetPlayers() do initializePlayerData(p) end

	BuyUnitRemote.OnServerInvoke = ShopManager.HandleBuyUnit
	GetOwnershipRemote.OnServerInvoke = ShopManager.GetPlayerOwnership
	
	print("✓ ShopManager Initialized")
end

function ShopManager.GetOwnedCount(player, unitName)
	local InvMgr = rawget(Services, "InventoryManager")
	if InvMgr then return InvMgr.GetUnitLevel(player, unitName) end
	return 0
end

function ShopManager.GetUnlockProgress(player)
	return PlayerUnlockProgress[player] or ShopConfig.INITIAL_UNLOCKED
end

function ShopManager.HandleBuyUnit(player, unitName)
	-- Distance Check
	local mainIsland = workspace:FindFirstChild("MainIsland")
	local shopVendor = mainIsland and mainIsland:FindFirstChild("ShopVendor")
	if shopVendor and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - shopVendor.Position).Magnitude > 20 then
			return false, "Too far from shop!"
		end
	end
	
	if not ShopConfig.GetConfig(unitName) then return false, "Unknown Unit" end
	
	local progress = ShopManager.GetUnlockProgress(player)
	if not ShopConfig.IsUnitUnlocked(unitName, progress) then return false, "Locked!" end
	
	local owned = ShopManager.GetOwnedCount(player, unitName)
	local price = ShopConfig.CalculatePrice(unitName, owned)
	
	if getMoney(player) < price then return false, "Not enough cash" end
	if not deductMoney(player, price) then return false, "Transaction failed" end
	
	local InvMgr = rawget(Services, "InventoryManager")
	if not InvMgr then return false, "Inventory System Offline" end
	
	local rarity = RarityConfig.RollRarity()
	local newData = InvMgr.AddUnit(player, unitName, rarity)
	local newLevel = newData.level
	
	updateLegacyOwnedCount(player, unitName, newLevel)
	
	-- Update client
	local newPrice = ShopConfig.CalculatePrice(unitName, newLevel)
	OwnershipChangedEvent:FireClient(player, unitName, newLevel, newPrice)
	
	-- Increment Unlock
	local total = ShopConfig.GetTotalUnits()
	if progress < total then
		PlayerUnlockProgress[player] = progress + 1
		local uv = player:FindFirstChild("UnlockProgress")
		if uv then uv.Value = PlayerUnlockProgress[player] end
		UnlockProgressChangedEvent:FireClient(player, PlayerUnlockProgress[player])
	end
	
	return true, "Purchased!"
end

function ShopManager.GetPlayerOwnership(player)
	local data = { units = {}, unlockProgress = ShopManager.GetUnlockProgress(player) }
	for unitName, _ in pairs(ShopConfig.Units) do
		local count = ShopManager.GetOwnedCount(player, unitName)
		data.units[unitName] = { 
			count = count, 
			price = ShopConfig.CalculatePrice(unitName, count) 
		}
	end
	return data
end

function ShopManager.SetPlayerData(player, ownedUnits, unlockProgress)
	PlayerUnlockProgress[player] = unlockProgress
	
	local uv = player:FindFirstChild("UnlockProgress")
	if uv then uv.Value = unlockProgress end
	
	-- Restore legacy folder visuals
	local f = player:FindFirstChild("OwnedUnits")
	if f then
		for name, count in pairs(ownedUnits) do
			local c = f:FindFirstChild(name)
			if c then c.Value = count end
		end
	end
	
	UnlockProgressChangedEvent:FireClient(player, unlockProgress)
	
	-- Batch notify ownership
	for unitName, count in pairs(ownedUnits) do
		local price = ShopConfig.CalculatePrice(unitName, count)
		OwnershipChangedEvent:FireClient(player, unitName, count, price)
	end
end

-- Compatibility Export
ShopManager.ResetPlayerData = function(player)
	PlayerUnlockProgress[player] = ShopConfig.INITIAL_UNLOCKED
	local uv = player:FindFirstChild("UnlockProgress")
	if uv then uv.Value = ShopConfig.INITIAL_UNLOCKED end
	local f = player:FindFirstChild("OwnedUnits")
	if f then
		for _, v in pairs(f:GetChildren()) do v.Value = 0 end
	end
	UnlockProgressChangedEvent:FireClient(player, ShopConfig.INITIAL_UNLOCKED)
end

return ShopManager
