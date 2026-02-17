--[[
	IslandShopManager Server Module
	
	Handles the Island Shop on the main island where players can:
	1. Purchase tier unlocks early
	2. View their current tier status
]]

local Players = game:GetService("Players")
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

local function createIslandShopVendor()
	local mainIsland = workspace:WaitForChild("MainIsland", 10)
	if not mainIsland then return end
	if mainIsland:FindFirstChild("IslandShopVendor") then return end
	
	local center = Vector3.new(0, 30, 0)
	local ip = mainIsland:FindFirstChild("Island") or mainIsland:FindFirstChildWhichIsA("BasePart")
	if ip then center = ip.Position end
	
	local part = Instance.new("Part")
	part.Name = "IslandShopVendor"
	part.Size = SHOP_CONFIG.VENDOR_SIZE
	part.BrickColor = BrickColor.new("Bright violet")
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.Position = center + SHOP_CONFIG.VENDOR_POSITION_OFFSET
	
	local bb = Instance.new("BillboardGui")
	bb.Name = "ShopDisplay"
	bb.Size = UDim2.new(6,0,3,0)
	bb.StudsOffset = Vector3.new(0,6,0)
	bb.Parent = part
	
	local bg = Instance.new("Frame")
	bg.BackgroundColor3 = Color3.fromRGB(40,20,60)
	bg.BackgroundTransparency = 0.2
	bg.Size = UDim2.new(1,0,1,0)
	bg.Parent = bb
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0.1,0)
	
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1,0,0.4,0)
	t.BackgroundTransparency = 1
	t.Text = "🏝️ ISLAND SHOP"
	t.TextColor3 = Color3.fromRGB(255,200,255)
	t.TextScaled = true
	t.Parent = bg
	
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Open Island Shop"
	pp.ObjectText = "Island Shop"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = part
	
	part.Parent = mainIsland
	CollectionService:AddTag(part, "IslandShopVendor")
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function IslandShopManager.Init(services)
	print("   IslandShopManager (Module) - Initializing")
	Services = services or {}
	
	task.spawn(function()
		task.wait(2)
		createIslandShopVendor()
	end)
	
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
