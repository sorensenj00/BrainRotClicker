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

local CollectionService = game:GetService("CollectionService")

-- State
local PlayerUnlockProgress = {} 

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function setupShopVendor()
	local mainIsland = workspace:WaitForChild("MainIsland", 30)
	if not mainIsland then return end
	
	local shopsFolder = mainIsland:WaitForChild("Shops", 30)
	if not shopsFolder then return end
	
	-- Look for "UnitShop" in the Shops folder
	local existingVendor = shopsFolder:WaitForChild("UnitShop", 30)
	if not existingVendor then return end
	
	if CollectionService:HasTag(existingVendor, "UnitShopVisual") then
		return
	end
	
	CollectionService:AddTag(existingVendor, "UnitShopVisual")
	
	-- Ensure it has a prompt
	local primary = existingVendor.PrimaryPart or existingVendor:FindFirstChildWhichIsA("BasePart")
	if primary and not existingVendor:FindFirstChild("ShopPrompt", true) then
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "ShopPrompt"
		pp.ActionText = "Open Shop"
		pp.ObjectText = "Brainrot Shop"
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.RequiresLineOfSight = false
		pp.MaxActivationDistance = 20
		pp.Parent = primary
	end
end


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
	local DataService = rawget(Services, "DataService")
	if DataService then return DataService.GetMoney(player) end
	return 0
end

local function deductMoney(player, amount)
	local DataService = rawget(Services, "DataService")
	if DataService then return DataService.DeductMoney(player, amount) end
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
	
	task.spawn(setupShopVendor)
	
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
	-- Distance Check FIX
	local mainIsland = workspace:FindFirstChild("MainIsland")
	local shopsFolder = mainIsland and mainIsland:FindFirstChild("Shops")
	local shopVendor = shopsFolder and shopsFolder:FindFirstChild("UnitShop")
	
	if shopVendor and player.Character then
		local hrp = player.Character:FindFirstChild("HumanoidRootPart")
		-- Use GetPivot() to safely get the center of the shop model
		if hrp and (hrp.Position - shopVendor:GetPivot().Position).Magnitude > 20 then
			return false, "Too far from shop!"
		end
	end
	
	if not ShopConfig.GetConfig(unitName) then return false, "Unknown Unit" end
	
	local progress = ShopManager.GetUnlockProgress(player)
	if not ShopConfig.IsUnitUnlocked(unitName, progress) then return false, "Locked!" end
	
	local owned = ShopManager.GetOwnedCount(player, unitName)
	local price = ShopConfig.CalculatePrice(unitName, owned)
	
	if getMoney(player) < price then return false, "Not enough cash" end
	
	-- Check item costs BEFORE deducting cash (avoid partial transactions)
	local itemCost = ShopConfig.GetItemCost(unitName)
	local ISM = rawget(Services, "ItemStorageManager")
	if itemCost then
		if not ISM then return false, "Storage System Offline" end
		local storageItems = ISM.GetStorageContents(player)
		local backpackItems = ISM.GetBackpackContents(player)
		for itemId, needed in pairs(itemCost) do
			local available = (storageItems[itemId] or 0) + (backpackItems[itemId] or 0)
			if available < needed then
				return false, "Need " .. needed .. "x " .. itemId .. " (have " .. available .. ")"
			end
		end
	end
	
	if not deductMoney(player, price) then return false, "Transaction failed" end
	
	-- Deduct items (burn them — NOT reported as sales to market)
	if itemCost and ISM then
		for itemId, needed in pairs(itemCost) do
			local remaining = needed
			-- Take from storage first, then backpack
			local fromStorage = ISM.RemoveFromStorage(player, itemId, remaining)
			remaining -= fromStorage
			if remaining > 0 then
				ISM.RemoveFromBackpack(player, itemId, remaining)
			end
		end
	end
	
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
