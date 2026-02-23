--[[
	CartShopManager Server Module
	
	Handles the Cart Shop on the main island.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local PurchaseCartUpgradeEvent = RemoteEvents:FindFirstChild("PurchaseCartUpgrade") or Instance.new("RemoteEvent")
PurchaseCartUpgradeEvent.Name = "PurchaseCartUpgrade"
PurchaseCartUpgradeEvent.Parent = RemoteEvents

local GetCartUpgradeInfoEvent = RemoteEvents:FindFirstChild("GetCartUpgradeInfo") or Instance.new("RemoteFunction")
GetCartUpgradeInfoEvent.Name = "GetCartUpgradeInfo"
GetCartUpgradeInfoEvent.Parent = RemoteEvents

local CartShopConfig

-- State: Managed via DataService
local CartShopManager = {}
local Services = {} 

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
	
	PurchaseCartUpgradeEvent.OnServerEvent:Connect(function(player, upgradeType)
		local s, msg = CartShopManager.HandleUpgradePurchase(player, upgradeType)
		PurchaseCartUpgradeEvent:FireClient(player, s, msg)
	end)
	
	GetCartUpgradeInfoEvent.OnServerInvoke = function(player)
		return CartShopManager.GetUpgradeInfo(player)
	end
	
	print("✓ CartShopManager Initialized")
end

function CartShopManager.GetUpgradeInfo(player)
	local DataService = rawget(Services, "DataService")
	local data = { Capacity = 0, Model = 1 }
	if DataService then
		data = DataService.GetCartUpgrades(player)
	end
	
	return {
		Capacity = CartShopConfig.GetUpgradeInfo("Capacity", data.Capacity or 0),
		Model = CartShopConfig.GetUpgradeInfo("Model", data.Model or 1),
		CurrentTiers = data
	}
end

function CartShopManager.HandleUpgradePurchase(player, upgradeType)
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

return CartShopManager
