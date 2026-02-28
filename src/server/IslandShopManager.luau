--[[
	IslandShopManager Server Module
	
	Handles the Island Shop on the main island where players can:
	1. Purchase tier unlocks early
	2. View their current tier status
]]

local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local PurchaseTierEvent = RemoteEvents:FindFirstChild("PurchaseTier") or Instance.new("RemoteEvent")
PurchaseTierEvent.Name = "PurchaseTier"
PurchaseTierEvent.Parent = RemoteEvents

local GetTierInfoEvent = RemoteEvents:FindFirstChild("GetTierInfo") or Instance.new("RemoteFunction")
GetTierInfoEvent.Name = "GetTierInfo"
GetTierInfoEvent.Parent = RemoteEvents

local SHOP_CONFIG = {
	BASE_TIER_PRICE = 50000,
	PRICE_MULTIPLIER = 4,
	VENDOR_SIZE = Vector3.new(6, 8, 6),
	VENDOR_POSITION_OFFSET = Vector3.new(-30, 10, 30),
}

local IslandShopManager = {}
local Services = {}
local DataService

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getDataService()
	if not DataService then
		DataService = rawget(Services, "DataService")
	end
	return DataService
end

local function getTierConfig()
	local PlotManager = rawget(Services, "PlotManager")
	return PlotManager and PlotManager.TIER_CONFIG or nil
end

local function getMaxSlots()
	local conf = getTierConfig()
	if not conf then
		return 96
	end
	return conf.MAX_TIERS * conf.MODELS_PER_TIER
end

local function getCurrentSlots(player)
	local ds = getDataService()
	local defaultSlots = 4
	if not ds or not ds.GetData then
		return defaultSlots
	end

	local data = ds.GetData(player)
	local rawSlots = data and tonumber(data.unlockedGridSlots) or defaultSlots
	return math.max(defaultSlots, math.floor(rawSlots))
end

local function getNextUpgradeType(currentSlots)
	if currentSlots % 16 == 0 then
		return "NewIsland"
	end
	return "ExpandGrid"
end

local function getNextPrice(currentSlots)
	return math.floor(5000 * (2 ^ (currentSlots / 4)))
end

local function findParentTierWithSpace(tierSystem)
	for i = #tierSystem.Tiers, 1, -1 do
		local tierData = tierSystem.Tiers[i]
		if tierData and (3 - #tierData.UsedSides) > 0 then
			return tierData
		end
	end
	return nil
end

local function deductMoney(player, amount)
	local ds = getDataService()
	if ds and ds.DeductMoney then
		return ds.DeductMoney(player, amount)
	end

	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	if not m or m.Value < amount then
		return false
	end
	m.Value -= amount
	return true
end

local function refundMoney(player, amount)
	local ds = getDataService()
	if ds and ds.AddMoney then
		ds.AddMoney(player, amount)
		return
	end

	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	if m then
		m.Value += amount
	end
end

local function setupIslandShopVendor()
	local mainIsland = workspace:WaitForChild("MainIsland", 10)
	if not mainIsland then return end
	
	local shopsFolder = mainIsland:WaitForChild("Shops", 10)
	if not shopsFolder then return end
	
	local vendor = shopsFolder:WaitForChild("IslandShop", 10)
	if not vendor then return end
	
	CollectionService:AddTag(vendor, "IslandShopVendor")
	
	-- Ensure prompt exists
	local primary = vendor:FindFirstChild("Meshes/tung tung", true) or vendor.PrimaryPart or vendor:FindFirstChildWhichIsA("BasePart", true)
	if primary and not vendor:FindFirstChild("ShopPrompt", true) then
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "ShopPrompt"
		pp.ActionText = "Open Island Shop"
		pp.ObjectText = "Island Shop"
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.RequiresLineOfSight = false
		pp.MaxActivationDistance = 20
		pp.Parent = primary
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function IslandShopManager.Init(services)
	print("   IslandShopManager (Module) - Initializing")
	Services = services or {}
	
	task.spawn(setupIslandShopVendor)
	
	PurchaseTierEvent.OnServerEvent:Connect(function(player)
		local s, m = IslandShopManager.HandleTierPurchase(player)
		PurchaseTierEvent:FireClient(player, s, m)
	end)
	
	GetTierInfoEvent.OnServerInvoke = function(player)
		return IslandShopManager.GetTierInfo(player)
	end
	
	print("✓ IslandShopManager Initialized")
end

function IslandShopManager.HandleTierPurchase(player)
	local MapSystem = rawget(Services, "MapSystem")
	if not MapSystem then return false, "Shop system not ready" end

	local maxSlots = getMaxSlots()
	local currentSlots = getCurrentSlots(player)
	if currentSlots >= maxSlots then
		return false, "Max slots reached"
	end

	local nextPrice = getNextPrice(currentSlots)
	local nextUpgradeType = getNextUpgradeType(currentSlots)

	if not deductMoney(player, nextPrice) then
		return false, "Not enough money"
	end

	if nextUpgradeType == "NewIsland" then
		local tierSystem = MapSystem.GetPlayerTierSystem(player)
		if not tierSystem then
			refundMoney(player, nextPrice)
			return false, "No plot assigned"
		end

		local parentTier = findParentTierWithSpace(tierSystem)
		if not parentTier then
			refundMoney(player, nextPrice)
			return false, "No space for new island"
		end

		local newTier = MapSystem.SpawnTierPlot(player, parentTier)
		if not newTier then
			refundMoney(player, nextPrice)
			return false, "Spawn failed"
		end
	end

	local ds = getDataService()
	if not ds or not ds.GetData then
		refundMoney(player, nextPrice)
		return false, "Data service unavailable"
	end

	local data = ds.GetData(player)
	if not data then
		refundMoney(player, nextPrice)
		return false, "Data not loaded"
	end

	data.unlockedGridSlots = math.min(maxSlots, currentSlots + 4)

	return true, "Grid Expanded!"
end

function IslandShopManager.GetTierInfo(player)
	local MapSystem = rawget(Services, "MapSystem")
	local maxSlots = getMaxSlots()
	local currentSlots = getCurrentSlots(player)
	local canPurchase = currentSlots < maxSlots
	local nextUpgradeType = getNextUpgradeType(currentSlots)
	local nextPrice = getNextPrice(currentSlots)

	local currentTiers = 1
	if MapSystem and MapSystem.GetPlayerTierSystem then
		local ts = MapSystem.GetPlayerTierSystem(player)
		if ts and ts.Tiers then
			currentTiers = #ts.Tiers
		end
	end

	return {
		CurrentSlots = currentSlots,
		MaxSlots = maxSlots,
		NextUpgradeType = nextUpgradeType,
		NextPrice = nextPrice,
		CanPurchase = canPurchase,

		-- Backward-compatible fields for any legacy UI readers
		CurrentTiers = currentTiers,
		MaxTiers = (getTierConfig() and getTierConfig().MAX_TIERS) or 6,
		NextTierPrice = nextPrice,
		TotalModels = 0,
		ModelsPerTier = (getTierConfig() and getTierConfig().MODELS_PER_TIER) or 16,
	}
end

IslandShopManager.GetTierPrice = getNextPrice
IslandShopManager.SHOP_CONFIG = SHOP_CONFIG

return IslandShopManager
