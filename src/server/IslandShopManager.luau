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
	BASE_TIER_PRICE = 5000,
	PRICE_MULTIPLIER = 2,
	VENDOR_SIZE = Vector3.new(6, 8, 6),
	VENDOR_POSITION_OFFSET = Vector3.new(-30, 10, 30),
}

local IslandShopManager = {}
local Services = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getTierPrice(tierNumber)
	if tierNumber <= 1 then return 0 end
	return SHOP_CONFIG.BASE_TIER_PRICE * (SHOP_CONFIG.PRICE_MULTIPLIER ^ (tierNumber - 2))
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
	local primary = vendor.PrimaryPart or vendor:FindFirstChildWhichIsA("BasePart")
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
	local ts = MapSystem.GetPlayerTierSystem(player)
	if not ts then return false, "No plot assigned" end
	
	local currentCount = #ts.Tiers
	local nextNum = currentCount + 1
	local CONF = MapSystem.TIER_CONFIG
	if nextNum > CONF.MAX_TIERS then return false, "Max islands reached" end
	
	local price = getTierPrice(nextNum)
	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	if not m or m.Value < price then return false, "Not enough money" end
	
	local parentTier
	for i = currentCount, 1, -1 do
		local t = ts.Tiers[i]
		if (3 - #t.UsedSides) > 0 then parentTier = t; break end
	end
	if not parentTier then return false, "No space for new island" end
	
	m.Value -= price
	local newTier = MapSystem.SpawnTierPlot(player, parentTier)
	if not newTier then
		m.Value += price
		return false, "Spawn failed"
	end
	
	return true, "Purchased Island " .. nextNum
end

function IslandShopManager.GetTierInfo(player)
	local MapSystem = rawget(Services, "MapSystem")
	if not MapSystem then return nil end
	local ts = MapSystem.GetPlayerTierSystem(player)
	if not ts then return nil end
	local cnt = #ts.Tiers
	local Conf = MapSystem.TIER_CONFIG
	return {
		CurrentTiers = cnt,
		MaxTiers = Conf.MAX_TIERS,
		NextTierPrice = getTierPrice(cnt + 1),
		CanPurchase = (cnt + 1) <= Conf.MAX_TIERS,
		TotalModels = ts.TotalModels,
		ModelsPerTier = Conf.MODELS_PER_TIER
	}
end

IslandShopManager.GetTierPrice = getTierPrice
IslandShopManager.SHOP_CONFIG = SHOP_CONFIG

return IslandShopManager
