--[[
	CartShopManager Server Module
	
	Handles the Cart Shop on the main island.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local function getOrCreateRemote(parent, remoteName, className)
	local remote = parent:FindFirstChild(remoteName)
	if remote and not remote:IsA(className) then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new(className)
		remote.Name = remoteName
		remote.Parent = parent
	end
	return remote
end

local PurchaseCartUpgradeEvent = getOrCreateRemote(RemoteEvents, "PurchaseCartUpgrade", "RemoteEvent") -- Legacy
local UpgradeCartCapacityEvent = getOrCreateRemote(RemoteEvents, "UpgradeCartCapacity", "RemoteEvent")
local UpgradeCartTierEvent = getOrCreateRemote(RemoteEvents, "UpgradeCartTier", "RemoteEvent")
local GetCartUpgradeInfoEvent = getOrCreateRemote(RemoteFunctions, "GetCartUpgradeInfo", "RemoteFunction")

local CartShopConfig

-- State: Managed via DataService
local CartShopManager = {}
local Services = {} 
local CONFIG = {
	VENDOR_DISTANCE = 20,
}

-- Admin bypass (mirrors other managers)
local ADMIN_USER_IDS = { [1340966465] = true }
local IS_STUDIO = RunService:IsStudio()
local function isAdmin(player)
	if IS_STUDIO then return true end
	if ADMIN_USER_IDS[player.UserId] then return true end
	if player.UserId == game.CreatorId then return true end
	return false
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function setupCartShopVendor()
	local mainIsland = workspace:WaitForChild("MainIsland", 10)
	if not mainIsland then return end
	
	local shopsFolder = mainIsland:WaitForChild("Shops", 10)
	if not shopsFolder then return end
	
	local vendor = shopsFolder:WaitForChild("CartShop", 10)
	if not vendor then return end
	
	CollectionService:AddTag(vendor, "CartShopVendor")
	
	-- Ensure prompt exists
	local primary = vendor.PrimaryPart or vendor:FindFirstChildWhichIsA("BasePart", true)
	if primary and not vendor:FindFirstChild("ShopPrompt", true) then
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "ShopPrompt"
		pp.ActionText = "Upgrade Cart"
		pp.ObjectText = "Cart Shop"
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.RequiresLineOfSight = false
		pp.MaxActivationDistance = 20
		pp.Parent = primary
	end
end

local function isNearCartVendor(player)
	if isAdmin(player) then return true end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local mainIsland = workspace:FindFirstChild("MainIsland")
	local shopsFolder = mainIsland and mainIsland:FindFirstChild("Shops")
	local vendor = shopsFolder and shopsFolder:FindFirstChild("CartShop")
	local target = vendor and (vendor.PrimaryPart or vendor:FindFirstChildWhichIsA("BasePart", true))
	if not target then return true end

	return (hrp.Position - target.Position).Magnitude <= CONFIG.VENDOR_DISTANCE
end

local function buildUpgradeInfo(player)
	local DataService = rawget(Services, "DataService")
	local data = { Capacity = 0, Model = 1 }
	if DataService then
		data = DataService.GetCartUpgrades(player)
	end

	local capacityInfo = CartShopConfig.GetUpgradeInfo("Capacity", data.Capacity or 0)
	local tierInfo = CartShopConfig.GetUpgradeInfo("Model", data.Model or 1)

	local currentCapacity = CartShopConfig.GetValue("Capacity", data.Capacity or 0)
	local nextCapacity = capacityInfo and capacityInfo.NextValue or nil
	local maxTier = #CartShopConfig.Carts
	local currentTier = data.Model or 1
	local nextTier = tierInfo and tierInfo.NextValue or math.min(currentTier + 1, maxTier)
	local canTierUpgrade = tierInfo and (not tierInfo.IsMaxed) or false

	return {
		-- Legacy fields
		Capacity = capacityInfo,
		Model = tierInfo,
		CurrentTiers = data,

		-- Structured fields
		capacity = {
			level = data.Capacity or 0,
			current = currentCapacity,
			next = nextCapacity,
			price = capacityInfo and capacityInfo.Price or nil,
			canUpgrade = capacityInfo and (not capacityInfo.IsMaxed) or false,
		},
		tier = {
			current = currentTier,
			next = math.min(nextTier, maxTier),
			max = maxTier,
			canUpgrade = canTierUpgrade,
			price = tierInfo and tierInfo.Price or nil,
			name = tierInfo and tierInfo.Name or nil,
		},
	}
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function CartShopManager.Init(services)
	print("   CartShopManager (Module) - Initializing")
	Services = services or {}
	
	-- Load Config
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	CartShopConfig = require(Shared:WaitForChild("CartShopConfig"))
	
	-- Note: DataService automatically handles loading profile data.
	-- We just need to apply it when player joins or data loads.
	
	Players.PlayerAdded:Connect(function(player)
		task.wait(2) -- Wait for things to settle (e.g. Cart spawning)
		local DataService = rawget(Services, "DataService")
		if DataService then
			local upgrades = DataService.GetCartUpgrades(player)
			-- Apply to CartManager
			local CartManager = rawget(Services, "CartManager")
			if CartManager then
				CartManager.ApplyUpgrades(player, upgrades)
			end
		end
	end)
	
	task.spawn(function()
		task.wait(2)
		setupCartShopVendor()
	end)
	
	-- Legacy event support
	PurchaseCartUpgradeEvent.OnServerEvent:Connect(function(player, upgradeType)
		local s, msg
		if upgradeType == "Capacity" then
			s, msg = CartShopManager.HandleCapacityUpgrade(player)
		elseif upgradeType == "Model" then
			s, msg = CartShopManager.HandleTierUpgrade(player)
		else
			s, msg = false, "Invalid Upgrade Type"
		end
		PurchaseCartUpgradeEvent:FireClient(player, s, msg)
	end)

	UpgradeCartCapacityEvent.OnServerEvent:Connect(function(player)
		local s, msg = CartShopManager.HandleCapacityUpgrade(player)
		UpgradeCartCapacityEvent:FireClient(player, s, msg)
	end)

	UpgradeCartTierEvent.OnServerEvent:Connect(function(player)
		local s, msg = CartShopManager.HandleTierUpgrade(player)
		UpgradeCartTierEvent:FireClient(player, s, msg)
	end)
	
	GetCartUpgradeInfoEvent.OnServerInvoke = function(player)
		return CartShopManager.GetUpgradeInfo(player)
	end
	
	print("✓ CartShopManager Initialized")
end

function CartShopManager.GetUpgradeInfo(player)
	return buildUpgradeInfo(player)
end

function CartShopManager.HandleUpgradePurchase(player, upgradeType) -- Legacy entrypoint
	if upgradeType == "Capacity" then
		return CartShopManager.HandleCapacityUpgrade(player)
	elseif upgradeType == "Model" then
		return CartShopManager.HandleTierUpgrade(player)
	end
	return false, "Invalid Upgrade Type"
end

local function handleUpgradePurchase(player, upgradeType)
	if not isNearCartVendor(player) then
		return false, "Too far from vendor"
	end

	local DataService = rawget(Services, "DataService")
	if not DataService then return false, "System Offline" end
	
	local currentData = DataService.GetCartUpgrades(player)
	local currentTier = currentData[upgradeType]
	
	-- Default Model to 1 if missing
	if upgradeType == "Model" and not currentTier then currentTier = 1 end
	if currentTier == nil then return false, "Invalid Upgrade Type" end
	
	local info = CartShopConfig.GetUpgradeInfo(upgradeType, currentTier)
	if not info or info.IsMaxed then return false, "Maxed Out" end
	
	local price = info.Price
	if not price then return false, "Invalid Price" end
	
	if DataService.GetMoney(player) < price then return false, "Not enough money" end
	
	if DataService.DeductMoney(player, price) then
		-- Update Data
		currentData[upgradeType] = currentTier + 1
		DataService.SetCartUpgrades(player, currentData)
		
		-- Apply changes immediately
		local CartManager = rawget(Services, "CartManager")
		if CartManager then
			CartManager.ApplyUpgrades(player, currentData)
		end
		
		return true, "Upgrade Purchased!"
	end
	
	return false, "Transaction Failed"
end

function CartShopManager.HandleCapacityUpgrade(player)
	return handleUpgradePurchase(player, "Capacity")
end

function CartShopManager.HandleTierUpgrade(player)
	return handleUpgradePurchase(player, "Model")
end

return CartShopManager
