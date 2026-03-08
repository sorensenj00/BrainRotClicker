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
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

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

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local BuyUnitRemote = RemoteEvents:FindFirstChild("BuyUnit") or Instance.new("RemoteFunction")
BuyUnitRemote.Name = "BuyUnit"
BuyUnitRemote.Parent = RemoteEvents

local UpgradeUnitFromHUDRemote = RemoteFunctions:FindFirstChild("UpgradeUnitFromHUD") or Instance.new("RemoteFunction")
UpgradeUnitFromHUDRemote.Name = "UpgradeUnitFromHUD"
UpgradeUnitFromHUDRemote.Parent = RemoteFunctions

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
	local primary = existingVendor:FindFirstChild("Meshes/tung tung", true) or existingVendor.PrimaryPart or existingVendor:FindFirstChildWhichIsA("BasePart", true)
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

local function recordAchievements(player, goalType, amount)
	local AchievementMgr = rawget(Services, "AchievementsManager")
	if AchievementMgr and AchievementMgr.RecordProgress then
		AchievementMgr.RecordProgress(player, goalType, amount)
	end
end

local function isPlayerNearUnitShop(player)
	local mainIsland = workspace:FindFirstChild("MainIsland")
	local shopsFolder = mainIsland and mainIsland:FindFirstChild("Shops")
	local shopVendor = shopsFolder and shopsFolder:FindFirstChild("UnitShop")

	if not shopVendor or not player.Character then
		return false
	end

	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	return hrp and (hrp.Position - shopVendor:GetPivot().Position).Magnitude <= 20
end

local function getUnitOutputInfo(unitName)
	local production = ItemConfig.GetModeProduction(unitName, 1, 1)
	local itemId = production and production.itemId
	local itemDef = itemId and ItemConfig.Items[itemId]
	return {
		itemId = itemId,
		itemName = itemDef and (itemDef.displayName or itemId) or itemId,
		itemIcon = itemDef and (itemDef.icon or "") or "",
		cycleTime = production and production.rate or nil,
	}
end

local function getNewlyUnlockedUnitName(previousProgress, newProgress)
	local shopConfig = getConfigs()
	local sortedUnits = shopConfig.GetAllUnitsSorted()
	for index = previousProgress + 1, math.min(newProgress, #sortedUnits) do
		local unitData = sortedUnits[index]
		if unitData then
			return unitData.name
		end
	end
	return nil
end

local function executeUnitPurchase(player, unitName, skipDistanceCheck)
	-- Distance Check (bypassed for admins / Studio)
	if not skipDistanceCheck and not isAdmin(player) and not isPlayerNearUnitShop(player) then
		return false, "Too far from shop!"
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

		-- Only use storage items
		local playerItems = ISM.GetStorageContents(player)

		-- Calculate shortfall cost with slippage
		local maxBuy = MarketConfig.CONFIG.MAX_BUY_PER_TRANSACTION or 100
		local getBuyPriceFn = MarketMgr and MarketMgr.GetBuyPrice
		if not getBuyPriceFn then
			getBuyPriceFn = function()
				return 0
			end
		end
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
			local needed = math.ceil(totalCost)
			return false, string.format("Market price fluctuated! You need $%s (Unit $%s + Import $%s)",
				tostring(needed), tostring(unitPrice), tostring(shortfall.totalTaxed))
		else
			return false, "Not enough cash"
		end
	end

	-- Execute transaction
	if not deductMoney(player, totalCost) then return false, "Transaction failed" end

	if itemCost and ISM then
		for itemId, needed in pairs(itemCost) do
			local toConsume = shortfall and shortfall.perItem[itemId]
				and math.min(needed, shortfall.perItem[itemId].have) or needed
			if toConsume > 0 then
				ISM.RemoveFromStorage(player, itemId, toConsume)
			end
		end
	end

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
	recordAchievements(player, "units_purchased", 1)

	local newPrice = ShopConfig.CalculatePrice(unitName, newLevel)
	OwnershipChangedEvent:FireClient(player, unitName, newLevel, newPrice)

	local total = ShopConfig.GetTotalUnits()
	local updatedProgress = progress
	local newUnlockName = nil
	if owned == 0 and progress < total then
		PlayerUnlockProgress[player] = progress + 1
		updatedProgress = PlayerUnlockProgress[player]
		newUnlockName = getNewlyUnlockedUnitName(progress, updatedProgress)
		local uv = player:FindFirstChild("UnlockProgress")
		if uv then
			uv.Value = PlayerUnlockProgress[player]
		end
		UnlockProgressChangedEvent:FireClient(player, PlayerUnlockProgress[player])
	end

	local outputInfo = getUnitOutputInfo(unitName)

	return true, "Purchased!", {
		unitName = unitName,
		ownedBefore = owned,
		newLevel = newLevel,
		newPrice = newPrice,
		amountPaid = math.floor(totalCost),
		unlockProgress = updatedProgress,
		newUnlockName = newUnlockName,
		outputItemId = outputInfo.itemId,
		outputItemName = outputInfo.itemName,
		outputItemIcon = outputInfo.itemIcon,
		outputCycleTime = outputInfo.cycleTime,
	}
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

	for _, p in Players:GetPlayers() do
		initializePlayerData(p)
	end

	BuyUnitRemote.OnServerInvoke = ShopManager.HandleBuyUnit
	UpgradeUnitFromHUDRemote.OnServerInvoke = ShopManager.HandleHUDUpgrade
	GetOwnershipRemote.OnServerInvoke = ShopManager.GetPlayerOwnership

	print("✓ ShopManager Initialized")
end

function ShopManager.GetOwnedCount(player, unitName)
	local InvMgr = rawget(Services, "InventoryManager")
	if InvMgr then
		return InvMgr.GetUnitLevel(player, unitName)
	end
	return 0
end

function ShopManager.GetUnlockProgress(player)
	return PlayerUnlockProgress[player] or ShopConfig.INITIAL_UNLOCKED
end

function ShopManager.HandleBuyUnit(player, unitName)
	return executeUnitPurchase(player, unitName, false)
end

function ShopManager.HandleHUDUpgrade(player, unitName)
	return executeUnitPurchase(player, unitName, true)
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
	if uv then
		uv.Value = unlockProgress
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
	if uv then
		uv.Value = ShopConfig.INITIAL_UNLOCKED
	end

	UnlockProgressChangedEvent:FireClient(player, ShopConfig.INITIAL_UNLOCKED)
end

return ShopManager
