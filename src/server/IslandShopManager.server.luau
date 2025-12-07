--[[
	IslandShopManager Server Script
	
	Handles the Island Shop on the main island where players can:
	1. Purchase tier unlocks early (before filling 12 models)
	2. View their current tier status
	
	Pricing: 5000 * (2 ^ (tierNumber - 1))
	Tier 2: $5,000 | Tier 3: $10,000 | Tier 4: $20,000 | etc.
]]

-- Services
local _Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Configuration
local SHOP_CONFIG = {
	BASE_TIER_PRICE = 5000,      -- Base price for tier 2
	PRICE_MULTIPLIER = 2,        -- Price doubles per tier
	VENDOR_SIZE = Vector3.new(6, 8, 6),
	VENDOR_POSITION_OFFSET = Vector3.new(-30, 10, 30), -- Offset from main island center
}

-- Remote Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local PurchaseTierEvent = RemoteEvents:FindFirstChild("PurchaseTier") or Instance.new("RemoteEvent")
PurchaseTierEvent.Name = "PurchaseTier"
PurchaseTierEvent.Parent = RemoteEvents

local GetTierInfoEvent = RemoteEvents:FindFirstChild("GetTierInfo") or Instance.new("RemoteFunction")
GetTierInfoEvent.Name = "GetTierInfo"
GetTierInfoEvent.Parent = RemoteEvents

--------------------------------------------------------------------------------
-- PRICING FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Calculates the price for purchasing a specific tier.
	
	@param tierNumber number - The tier number to purchase (2+)
	@return number - The price for that tier
]]
local function getTierPrice(tierNumber: number): number
	if tierNumber <= 1 then
		return 0 -- Tier 1 is free (starting tier)
	end
	
	-- Formula: 5000 * (2 ^ (tierNumber - 2))
	-- Tier 2: 5000, Tier 3: 10000, Tier 4: 20000, etc.
	return SHOP_CONFIG.BASE_TIER_PRICE * (SHOP_CONFIG.PRICE_MULTIPLIER ^ (tierNumber - 2))
end

--------------------------------------------------------------------------------
-- VENDOR CREATION
--------------------------------------------------------------------------------

--[[
	Creates the Island Shop vendor part on the main island.
]]
local function createIslandShopVendor()
	-- Wait for main island to exist
	local mainIsland = workspace:WaitForChild("MainIsland", 10)
	if not mainIsland then
		warn("MainIsland not found, cannot create Island Shop vendor")
		return nil
	end
	
	-- Check if vendor already exists
	if mainIsland:FindFirstChild("IslandShopVendor") then
		return mainIsland:FindFirstChild("IslandShopVendor")
	end
	
	-- Get main island position
	local mainIslandPos = Vector3.new(0, 30, 0) -- Default main island height
	local islandPart = mainIsland:FindFirstChild("Island") or mainIsland:FindFirstChildWhichIsA("BasePart")
	if islandPart then
		mainIslandPos = islandPart.Position
	end
	
	-- Create the vendor part
	local vendorPart = Instance.new("Part")
	vendorPart.Name = "IslandShopVendor"
	vendorPart.Size = SHOP_CONFIG.VENDOR_SIZE
	vendorPart.BrickColor = BrickColor.new("Bright violet")
	vendorPart.Material = Enum.Material.Neon
	vendorPart.Anchored = true
	vendorPart.CanCollide = true
	vendorPart.Position = mainIslandPos + SHOP_CONFIG.VENDOR_POSITION_OFFSET
	
	-- Create BillboardGui for display
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "ShopDisplay"
	billboardGui.Size = UDim2.new(6, 0, 3, 0)
	billboardGui.StudsOffset = Vector3.new(0, 6, 0)
	billboardGui.AlwaysOnTop = false
	billboardGui.Parent = vendorPart
	
	-- Background frame
	local bgFrame = Instance.new("Frame")
	bgFrame.Name = "Background"
	bgFrame.Size = UDim2.new(1, 0, 1, 0)
	bgFrame.BackgroundColor3 = Color3.fromRGB(40, 20, 60)
	bgFrame.BackgroundTransparency = 0.2
	bgFrame.Parent = billboardGui
	
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0.1, 0)
	uiCorner.Parent = bgFrame
	
	-- Title label
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.4, 0)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "🏝️ ISLAND SHOP"
	titleLabel.TextColor3 = Color3.fromRGB(255, 200, 255)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = bgFrame
	
	-- Subtitle label
	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.Size = UDim2.new(1, 0, 0.3, 0)
	subtitleLabel.Position = UDim2.new(0, 0, 0.4, 0)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Text = "Buy Tier Unlocks"
	subtitleLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
	subtitleLabel.TextScaled = true
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.Parent = bgFrame
	
	-- Instruction label
	local instructLabel = Instance.new("TextLabel")
	instructLabel.Name = "Instruction"
	instructLabel.Size = UDim2.new(1, 0, 0.25, 0)
	instructLabel.Position = UDim2.new(0, 0, 0.7, 0)
	instructLabel.BackgroundTransparency = 1
	instructLabel.Text = "Press E to open"
	instructLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	instructLabel.TextScaled = true
	instructLabel.Font = Enum.Font.Gotham
	instructLabel.Parent = bgFrame
	
	-- Tag for proximity detection
	CollectionService:AddTag(vendorPart, "IslandShopVendor")
	
	-- Create ProximityPrompt for interaction
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "IslandShopPrompt"
	prompt.ActionText = "Open Island Shop"
	prompt.ObjectText = "Island Shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = vendorPart
	
	vendorPart.Parent = mainIsland
	
	print("✓ Created Island Shop vendor on Main Island")
	return vendorPart
end

--------------------------------------------------------------------------------
-- PURCHASE HANDLING
--------------------------------------------------------------------------------

--[[
	Handles a player's request to purchase a new tier.
	
	@param player Player - The player attempting to purchase
	@return boolean, string - Success status and message
]]
local function handleTierPurchase(player: Player): (boolean, string)
	-- Wait for MapSystem to be available
	if not _G.MapSystem then
		return false, "Shop system not ready"
	end
	
	local tierSystem = _G.MapSystem.GetPlayerTierSystem(player)
	if not tierSystem then
		return false, "You don't have a plot assigned"
	end
	
	local currentTierCount = #tierSystem.Tiers
	local nextTierNumber = currentTierCount + 1
	
	-- Check max tiers
	local TIER_CONFIG = _G.MapSystem.TIER_CONFIG
	if nextTierNumber > TIER_CONFIG.MAX_TIERS then
		return false, "You've reached the maximum number of tiers!"
	end
	
	-- Get price
	local price = getTierPrice(nextTierNumber)
	
	-- Check if player has enough money
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return false, "Could not find your money"
	end
	
	local money = leaderstats:FindFirstChild("Money")
	if not money then
		return false, "Could not find your money"
	end
	
	if money.Value < price then
		return false, string.format("Not enough money! Need $%d, have $%d", price, money.Value)
	end
	
	-- Find the tier with available sides to spawn from
	-- Prefer the most recent tier, but fall back to earlier tiers if needed
	local parentTier = nil
	for i = currentTierCount, 1, -1 do
		local tier = tierSystem.Tiers[i]
		local availableSides = 3 - #tier.UsedSides -- 3 sides available (excluding blocked)
		if availableSides > 0 then
			parentTier = tier
			break
		end
	end
	
	if not parentTier then
		return false, "No available space for a new tier"
	end
	
	-- Deduct money
	money.Value = money.Value - price
	
	-- Spawn the new tier
	local newTierData = _G.MapSystem.SpawnTierPlot(player, parentTier)
	if not newTierData then
		-- Refund if spawn failed
		money.Value = money.Value + price
		return false, "Failed to create new tier"
	end
	
	return true, string.format("Purchased Tier %d for $%d!", nextTierNumber, price)
end

--------------------------------------------------------------------------------
-- REMOTE EVENT HANDLERS
--------------------------------------------------------------------------------

PurchaseTierEvent.OnServerEvent:Connect(function(player)
	local success, message = handleTierPurchase(player)
	
	-- Send result back to client
	PurchaseTierEvent:FireClient(player, success, message)
end)

GetTierInfoEvent.OnServerInvoke = function(player)
	if not _G.MapSystem then
		return nil
	end
	
	local tierSystem = _G.MapSystem.GetPlayerTierSystem(player)
	if not tierSystem then
		return nil
	end
	
	local currentTierCount = #tierSystem.Tiers
	local nextTierNumber = currentTierCount + 1
	local TIER_CONFIG = _G.MapSystem.TIER_CONFIG
	
	return {
		CurrentTiers = currentTierCount,
		MaxTiers = TIER_CONFIG.MAX_TIERS,
		NextTierPrice = getTierPrice(nextTierNumber),
		CanPurchase = nextTierNumber <= TIER_CONFIG.MAX_TIERS,
		TotalModels = tierSystem.TotalModels,
		ModelsPerTier = TIER_CONFIG.MODELS_PER_TIER,
	}
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   IslandShopManager - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Wait a bit for MapSystem to initialize
	task.wait(2)
	
	-- Create the vendor on main island
	createIslandShopVendor()
	
	print("✓ IslandShopManager initialized")
	print("═══════════════════════════════════════════")
end

-- Start initialization
task.spawn(initialize)

-- Export API
_G.IslandShop = {
	GetTierPrice = getTierPrice,
	SHOP_CONFIG = SHOP_CONFIG,
}
