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

local function createCartShopVendor()
	local mainIsland = workspace:WaitForChild("MainIsland", 10)
	if not mainIsland then return end
	if mainIsland:FindFirstChild("CartShopVendor") then return end
	
	local center = Vector3.new(0, 30, 0)
	local ip = mainIsland:FindFirstChild("Island") or mainIsland:FindFirstChildWhichIsA("BasePart")
	if ip then center = ip.Position end
	
	local part = Instance.new("Part")
	part.Name = "CartShopVendor"
	part.Size = Vector3.new(6, 8, 6)
	part.BrickColor = BrickColor.new("Bright yellow")
	part.Material = Enum.Material.Neon
	part.Anchored = true
	-- Offset from center, maybe opposite side of storage/island shop
	part.Position = center + Vector3.new(30, 10, 30) 
	
	local bb = Instance.new("BillboardGui")
	bb.Name = "ShopDisplay"
	bb.Size = UDim2.new(6,0,3,0)
	bb.StudsOffset = Vector3.new(0,6,0)
	bb.Parent = part
	
	local bg = Instance.new("Frame")
	bg.BackgroundColor3 = Color3.fromRGB(60,60,20)
	bg.BackgroundTransparency = 0.2
	bg.Size = UDim2.new(1,0,1,0)
	bg.Parent = bb
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0.1,0)
	
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1,0,0.4,0)
	t.BackgroundTransparency = 1
	t.Text = "🛒 CART SHOP"
	t.TextColor3 = Color3.fromRGB(255,255,100)
	t.TextScaled = true
	t.Parent = bg
	
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Upgrade Cart"
	pp.ObjectText = "Cart Shop"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = part
	
	part.Parent = mainIsland
	CollectionService:AddTag(part, "CartShopVendor")
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
		createCartShopVendor()
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
