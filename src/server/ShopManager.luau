--[[
	ShopManager Server Module

	Handles all purchase logic for the shop system.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Lazy Configs
local ShopConfig
local RarityConfig

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShortfallCalc = require(Shared:WaitForChild("ShortfallCalc"))
local MarketConfig = require(Shared:WaitForChild("MarketConfig"))

local function getConfigs()
	if not ShopConfig then
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

-- Admin bypass (mirrors AdminService)
local ADMIN_USER_IDS = { [1340966465] = true }
local IS_STUDIO = RunService:IsStudio()
local function isAdmin(player)
	if IS_STUDIO then return true end
	if ADMIN_USER_IDS[player.UserId] then return true end
	if player.UserId == game.CreatorId then return true end
	return false
end

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
	-- Distance Check (bypassed for admins / Studio)
	if not isAdmin(player) then
		local mainIsland = workspace:FindFirstChild("MainIsland")
		local shopsFolder = mainIsland and mainIsland:FindFirstChild("Shops")
		local shopVendor = shopsFolder and shopsFolder:FindFirstChild("UnitShop")

		if shopVendor and player.Character then
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp.Position - shopVendor:GetPivot().Position).Magnitude > 20 then
				return false, "Too far from shop!"
			end
		end
	end

	if not ShopConfig.GetConfig(unitName) then return false, "Unknown Unit" end

	local progress = ShopManager.GetUnlockProgress(player)
	if not ShopConfig.IsUnitUnlocked(unitName, progress) then return false, "Locked!" end

	local owned = ShopManager.GetOwnedCount(player, unitName)
	local unitPrice = ShopConfig.CalculatePrice(unitName, owned)

	-- Gather item costs and player inventory
	local itemCost = ShopConfig.GetItemCost(unitName)
	local ISM = rawget(Services, "ItemStorageManager")
	local MarketMgr = rawget(Services, "MarketManager")
	local InvMgr = rawget(Services, "InventoryManager")
	local shortfall = nil
	local totalCost = unitPrice

	if not InvMgr then return false, "Inventory System Offline" end

	if itemCost then
		if not ISM then return false, "Storage System Offline" end

		-- Merge storage + backpack into one "have" table
		local storageItems = ISM.GetStorageContents(player)
		local backpackItems = ISM.GetBackpackContents(player)
		local playerItems = {}
		for itemId, _ in pairs(itemCost) do
			playerItems[itemId] = (storageItems[itemId] or 0) + (backpackItems[itemId] or 0)
		end

		-- Calculate shortfall cost with slippage
		local maxBuy = MarketConfig.CONFIG.MAX_BUY_PER_TRANSACTION or 100
		local getBuyPriceFn = (MarketMgr and MarketMgr.GetBuyPrice) or function() return 0 end
		shortfall = ShortfallCalc.Calculate(itemCost, playerItems, getBuyPriceFn, maxBuy)

		if shortfall.hasShortfall then
			if not MarketMgr then return false, "Market System Offline" end
			totalCost = unitPrice + shortfall.totalTaxed
		end
	end

	-- Check total affordability
	local playerMoney = getMoney(player)
	if playerMoney < totalCost then
		if shortfall and shortfall.hasShortfall then
			-- Explicit error for price fluctuation / shortfall
			local needed = math.ceil(totalCost)
			local _have = math.floor(playerMoney)
			return false, string.format("Market price fluctuated! You need $%s (Unit $%s + Import $%s)",
				tostring(needed), tostring(unitPrice), tostring(shortfall.totalTaxed))
		else
			return false, "Not enough cash"
		end
	end

	-- === EXECUTE TRANSACTION ===
	if not deductMoney(player, totalCost) then return false, "Transaction failed" end

	-- Consume physical items (burn from storage/backpack)
	if itemCost and ISM then
		for itemId, needed in pairs(itemCost) do
			-- Only consume what the player physically has (not the virtual imports)
			local physicalHave = shortfall and shortfall.perItem[itemId]
				and math.min(needed, shortfall.perItem[itemId].have) or needed
			if physicalHave > 0 then
				local remaining = physicalHave
				local fromStorage = ISM.RemoveFromStorage(player, itemId, remaining)
				remaining -= fromStorage
				if remaining > 0 then
					ISM.RemoveFromBackpack(player, itemId, remaining)
				end
			end
		end
	end

	-- Register virtual imports in AMM (raw cost only — tax was burned above)
	if shortfall and shortfall.hasShortfall and MarketMgr then
		MarketMgr.ExecuteShortfallBuy(shortfall.perItem)
	end

	local newData = InvMgr.AddUnit(player, unitName)
	if not newData then
		local DataService = rawget(Services, "DataService")
		if DataService then
			DataService.AddMoney(player, totalCost)
		end
		return false, "Failed to grant unit (refunded)"
	end
	local newLevel = newData.level

	updateLegacyOwnedCount(player, unitName, newLevel)

	-- Update client
	local newPrice = ShopConfig.CalculatePrice(unitName, newLevel)
	OwnershipChangedEvent:FireClient(player, unitName, newLevel, newPrice)

	-- Increment Unlock ONLY when buying a NEW unit type for the first time
	local total = ShopConfig.GetTotalUnits()
	if owned == 0 and progress < total then
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
