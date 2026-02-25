--[[
	IslandShopUI Client Script
	
	Handles the UI for the Island Shop where players can:
	1. View their current tier status
	2. Purchase tier unlocks
	
	Opens when player presses E near the Island Shop vendor.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Player reference
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remote Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseTierEvent = RemoteEvents:WaitForChild("PurchaseTier")
local GetTierInfoEvent = RemoteEvents:WaitForChild("GetTierInfo")

-- Configuration
local UI_CONFIG = {
	INTERACTION_DISTANCE = 20,
	TWEEN_TIME = 0.3,
}

-- State
local shopOpen = false
local _nearVendor = false

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createShopUI()
	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "IslandShopUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	-- Main container
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 400, 0, 350)
	mainFrame.Position = UDim2.new(0.5, -200, 0.5, -175)
	mainFrame.BackgroundColor3 = Color3.fromRGB(25, 15, 40)
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui
	
	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 16)
	mainCorner.Parent = mainFrame
	
	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(150, 100, 200)
	mainStroke.Thickness = 2
	mainStroke.Parent = mainFrame
	
	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundColor3 = Color3.fromRGB(60, 30, 90)
	header.BorderSizePixel = 0
	header.Parent = mainFrame
	
	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 16)
	headerCorner.Parent = header
	
	-- Fix bottom corners of header
	local headerFix = Instance.new("Frame")
	headerFix.Size = UDim2.new(1, 0, 0, 16)
	headerFix.Position = UDim2.new(0, 0, 1, -16)
	headerFix.BackgroundColor3 = Color3.fromRGB(60, 30, 90)
	headerFix.BorderSizePixel = 0
	headerFix.Parent = header
	
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -60, 1, 0)
	titleLabel.Position = UDim2.new(0, 20, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "🏝️ ISLAND SHOP"
	titleLabel.TextColor3 = Color3.fromRGB(255, 200, 255)
	titleLabel.TextSize = 28
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = header
	
	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 40, 0, 40)
	closeButton.Position = UDim2.new(1, -50, 0, 10)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	closeButton.Text = "✕"
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.TextSize = 20
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Parent = header
	
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0.5, 0)
	closeCorner.Parent = closeButton
	
	-- Content area
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -40, 1, -80)
	content.Position = UDim2.new(0, 20, 0, 70)
	content.BackgroundTransparency = 1
	content.Parent = mainFrame
	
	-- Status section
	local statusFrame = Instance.new("Frame")
	statusFrame.Name = "StatusFrame"
	statusFrame.Size = UDim2.new(1, 0, 0, 100)
	statusFrame.BackgroundColor3 = Color3.fromRGB(40, 25, 60)
	statusFrame.BorderSizePixel = 0
	statusFrame.Parent = content
	
	local statusCorner = Instance.new("UICorner")
	statusCorner.CornerRadius = UDim.new(0, 12)
	statusCorner.Parent = statusFrame
	
	local tiersLabel = Instance.new("TextLabel")
	tiersLabel.Name = "TiersLabel"
	tiersLabel.Size = UDim2.new(1, -20, 0, 30)
	tiersLabel.Position = UDim2.new(0, 10, 0, 10)
	tiersLabel.BackgroundTransparency = 1
	tiersLabel.Text = "Current Islands: 1 / 6"
	tiersLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
	tiersLabel.TextSize = 18
	tiersLabel.Font = Enum.Font.GothamBold
	tiersLabel.TextXAlignment = Enum.TextXAlignment.Left
	tiersLabel.Parent = statusFrame
	
	local modelsLabel = Instance.new("TextLabel")
	modelsLabel.Name = "ModelsLabel"
	modelsLabel.Size = UDim2.new(1, -20, 0, 25)
	modelsLabel.Position = UDim2.new(0, 10, 0, 40)
	modelsLabel.BackgroundTransparency = 1
	modelsLabel.Text = "Total Models: 0"
	modelsLabel.TextColor3 = Color3.fromRGB(180, 180, 200)
	modelsLabel.TextSize = 16
	modelsLabel.Font = Enum.Font.Gotham
	modelsLabel.TextXAlignment = Enum.TextXAlignment.Left
	modelsLabel.Parent = statusFrame
	
	local fillLabel = Instance.new("TextLabel")
	fillLabel.Name = "FillLabel"
	fillLabel.Size = UDim2.new(1, -20, 0, 25)
	fillLabel.Position = UDim2.new(0, 10, 0, 65)
	fillLabel.BackgroundTransparency = 1
	fillLabel.Text = "Models per island: 12"
	fillLabel.TextColor3 = Color3.fromRGB(150, 150, 170)
	fillLabel.TextSize = 14
	fillLabel.Font = Enum.Font.Gotham
	fillLabel.TextXAlignment = Enum.TextXAlignment.Left
	fillLabel.Parent = statusFrame
	
	-- Purchase section
	local purchaseFrame = Instance.new("Frame")
	purchaseFrame.Name = "PurchaseFrame"
	purchaseFrame.Size = UDim2.new(1, 0, 0, 120)
	purchaseFrame.Position = UDim2.new(0, 0, 0, 110)
	purchaseFrame.BackgroundColor3 = Color3.fromRGB(40, 25, 60)
	purchaseFrame.BorderSizePixel = 0
	purchaseFrame.Parent = content
	
	local purchaseCorner = Instance.new("UICorner")
	purchaseCorner.CornerRadius = UDim.new(0, 12)
	purchaseCorner.Parent = purchaseFrame
	
	local purchaseTitle = Instance.new("TextLabel")
	purchaseTitle.Name = "PurchaseTitle"
	purchaseTitle.Size = UDim2.new(1, -20, 0, 30)
	purchaseTitle.Position = UDim2.new(0, 10, 0, 10)
	purchaseTitle.BackgroundTransparency = 1
	purchaseTitle.Text = "🛒 Purchase New Island"
	purchaseTitle.TextColor3 = Color3.fromRGB(255, 220, 100)
	purchaseTitle.TextSize = 18
	purchaseTitle.Font = Enum.Font.GothamBold
	purchaseTitle.TextXAlignment = Enum.TextXAlignment.Left
	purchaseTitle.Parent = purchaseFrame
	
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "PriceLabel"
	priceLabel.Size = UDim2.new(1, -20, 0, 25)
	priceLabel.Position = UDim2.new(0, 10, 0, 40)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = "Price: $5,000"
	priceLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	priceLabel.TextSize = 16
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.Parent = purchaseFrame
	
	local purchaseButton = Instance.new("TextButton")
	purchaseButton.Name = "PurchaseButton"
	purchaseButton.Size = UDim2.new(1, -20, 0, 40)
	purchaseButton.Position = UDim2.new(0, 10, 0, 70)
	purchaseButton.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
	purchaseButton.Text = "PURCHASE ISLAND"
	purchaseButton.TextColor3 = Color3.new(1, 1, 1)
	purchaseButton.TextSize = 18
	purchaseButton.Font = Enum.Font.GothamBold
	purchaseButton.Parent = purchaseFrame
	
	local purchaseButtonCorner = Instance.new("UICorner")
	purchaseButtonCorner.CornerRadius = UDim.new(0, 8)
	purchaseButtonCorner.Parent = purchaseButton
	
	-- Message label
	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "MessageLabel"
	messageLabel.Size = UDim2.new(1, 0, 0, 30)
	messageLabel.Position = UDim2.new(0, 0, 1, -30)
	messageLabel.BackgroundTransparency = 1
	messageLabel.Text = ""
	messageLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
	messageLabel.TextSize = 14
	messageLabel.Font = Enum.Font.Gotham
	messageLabel.Parent = content
	
	screenGui.Parent = playerGui
	
	return screenGui
end

--------------------------------------------------------------------------------
-- UI LOGIC
--------------------------------------------------------------------------------

local screenGui = createShopUI()
local mainFrame = screenGui:WaitForChild("MainFrame")
local content = mainFrame:WaitForChild("Content")
local statusFrame = content:WaitForChild("StatusFrame")
local purchaseFrame = content:WaitForChild("PurchaseFrame")

local function formatMoney(amount: number): string
	local suffixes = {"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}
	
	if amount < 1000 then
		return "$" .. tostring(math.floor(amount))
	end
	
	-- Calculate the magnitude (power of 1000)
	local magnitude = math.floor(math.log(amount, 1000))
	
	-- Cap at the largest suffix
	if magnitude > #suffixes then
		magnitude = #suffixes
	end
	
	local value = amount / (1000 ^ magnitude)
	
	-- Format with 1 decimal place if < 100, otherwise no decimals
	if value < 100 and value % 1 ~= 0 then
		return string.format("$%.1f%s", value, suffixes[magnitude])
	else
		return string.format("$%.0f%s", value, suffixes[magnitude])
	end
end

local function updateShopInfo()
	local info = GetTierInfoEvent:InvokeServer()
	if not info then return end
	
	-- Update status labels
	statusFrame.TiersLabel.Text = string.format("Current Islands: %d / %d", info.CurrentTiers, info.MaxTiers)
	statusFrame.ModelsLabel.Text = string.format("Total Models: %d", info.TotalModels)
	statusFrame.FillLabel.Text = string.format("Models per island: %d", info.ModelsPerTier)
	
	-- Update purchase section
	if info.CanPurchase then
		purchaseFrame.PriceLabel.Text = string.format("Price: %s", formatMoney(info.NextTierPrice))
		purchaseFrame.PurchaseButton.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
		purchaseFrame.PurchaseButton.Text = "PURCHASE ISLAND"
	else
		purchaseFrame.PriceLabel.Text = "Max islands reached!"
		purchaseFrame.PurchaseButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		purchaseFrame.PurchaseButton.Text = "MAX ISLANDS"
	end
end

local function openShop()
	if shopOpen then return end
	shopOpen = true
	
	updateShopInfo()
	
	mainFrame.Visible = true
	mainFrame.Size = UDim2.new(0, 0, 0, 0)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	
	local tween = TweenService:Create(mainFrame, TweenInfo.new(UI_CONFIG.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 400, 0, 350),
		Position = UDim2.new(0.5, -200, 0.5, -175),
	})
	tween:Play()
end

local function closeShop()
	if not shopOpen then return end
	
	local tween = TweenService:Create(mainFrame, TweenInfo.new(UI_CONFIG.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
	})
	tween:Play()
	tween.Completed:Connect(function()
		mainFrame.Visible = false
	end)
	
	shopOpen = false
end

local function showMessage(text, color)
	local messageLabel = content:FindFirstChild("MessageLabel")
	if messageLabel then
		messageLabel.Text = text
		messageLabel.TextColor3 = color or Color3.fromRGB(255, 200, 100)
		
		task.delay(3, function()
			if messageLabel.Text == text then
				messageLabel.Text = ""
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- BUTTON HANDLERS
--------------------------------------------------------------------------------

-- Close button
mainFrame.Header.CloseButton.MouseButton1Click:Connect(closeShop)

-- Purchase button
purchaseFrame.PurchaseButton.MouseButton1Click:Connect(function()
	purchaseFrame.PurchaseButton.Text = "Purchasing..."
	purchaseFrame.PurchaseButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	
	PurchaseTierEvent:FireServer()
end)

-- Handle purchase result
PurchaseTierEvent.OnClientEvent:Connect(function(success, message)
	if success then
		showMessage(message, Color3.fromRGB(100, 255, 100))
	else
		showMessage(message, Color3.fromRGB(255, 100, 100))
	end
	
	-- Refresh info
	updateShopInfo()
end)

--------------------------------------------------------------------------------
-- SHOP INTERACTION
--------------------------------------------------------------------------------

local ShopInteraction = require(script.Parent:WaitForChild("ShopInteraction"))

local _interaction = ShopInteraction.new({
	PromptTag = "IslandShopVendor",
	InteractionDist = UI_CONFIG.INTERACTION_DISTANCE,
	Keybind = Enum.KeyCode.E,
	OnOpen = openShop,
	OnClose = closeShop,
})

local UIManager = require(script.Parent:WaitForChild("Managers"):WaitForChild("UIManager"))
UIManager.RegisterShop("IslandShop", function()
	if shopOpen then closeShop() else openShop() end
end)

print("✓ IslandShopUI initialized")
