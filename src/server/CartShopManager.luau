--[[
	CartShopManager Server Module
	
	Handles the Cart Shop on the main island.
]]

local _Players = game:GetService("Players")
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

local CartShopManager = {}
local Services = {}

-- State: [Player] = { CapacityVideo = 0, Speed = 0 }
-- This should ideally be persisted via DataService, but for now we'll stick to session state 
-- or hook into DataService if available.
-- For this task I will add it to DataManager/DataService integration later, 
-- but I'll store it here in memory and try to sync with CartManager.
local PlayerCartUpgrades = {} 

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
	local primary = vendor.PrimaryPart or vendor:FindFirstChildWhichIsA("BasePart")
	if primary and not vendor:FindFirstChild("ShopPrompt", true) then
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "ShopPrompt"
		pp.ActionText = "Upgrade Cart"
		pp.ObjectText = "Cart Shop"
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.Parent = primary
	end
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

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function CartShopManager.Init(services)
	print("   CartShopManager (Module) - Initializing")
	Services = services or {}
	
	-- Load Config
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	CartShopConfig = require(Shared:WaitForChild("CartShopConfig"))
	
	local DataService = rawget(Services, "DataService")
	if DataService then
		DataService.RegisterHandler("CartUpgrades", {
			DefaultData = { Capacity = 0, Speed = 0 },
			OnLoad = function(player, data)
				PlayerCartUpgrades[player] = data or { Capacity = 0, Speed = 0 }
				-- Apply to CartManager
				local CartManager = rawget(Services, "CartManager")
				if CartManager then
					CartManager.ApplyUpgrades(player, PlayerCartUpgrades[player])
				end
			end,
			OnSave = function(player)
				return PlayerCartUpgrades[player] or { Capacity = 0, Speed = 0 }
			end
		})
	end
	
	task.spawn(function()
		task.wait(2)
		setupCartShopVendor()
	end)
	
	PurchaseCartUpgradeEvent.OnServerEvent:Connect(function(player, upgradeType)
		local s, _m = CartShopManager.HandleUpgradePurchase(player, upgradeType)
		-- We could fire back a notification or update event here
		if s then
			-- Refresh info
			-- This is handled by client re-requesting or a specific update event
		end
	end)
	
	GetCartUpgradeInfoEvent.OnServerInvoke = function(player)
		return CartShopManager.GetUpgradeInfo(player)
	end
	
	print("✓ CartShopManager Initialized")
end

function CartShopManager.GetUpgradeInfo(player)
	local data = PlayerCartUpgrades[player] or { Capacity = 0, Speed = 0 }
	return {
		Capacity = CartShopConfig.GetUpgradeInfo("Capacity", data.Capacity),
		Speed = CartShopConfig.GetUpgradeInfo("Speed", data.Speed),
		CurrentTiers = data
	}
end

function CartShopManager.HandleUpgradePurchase(player, upgradeType)
	if not PlayerCartUpgrades[player] then PlayerCartUpgrades[player] = { Capacity = 0, Speed = 0 } end
	
	local currentTier = PlayerCartUpgrades[player][upgradeType]
	if currentTier == nil then return false, "Invalid Upgrade Type" end
	
	local info = CartShopConfig.GetUpgradeInfo(upgradeType, currentTier)
	if not info or info.IsMaxed then return false, "Maxed Out" end
	
	if getMoney(player) < info.Price then return false, "Not enough money" end
	
	if deductMoney(player, info.Price) then
		PlayerCartUpgrades[player][upgradeType] = currentTier + 1
		
		-- Apply changes immediately
		local CartManager = rawget(Services, "CartManager")
		if CartManager then
			CartManager.ApplyUpgrades(player, PlayerCartUpgrades[player])
		end
		
		return true, "Upgrade Purchased!"
	end
	
	return false, "Transaction Failed"
end

return CartShopManager
