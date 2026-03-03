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

-- Shared Modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared:WaitForChild("UIConfig"))

local Utils = Shared:WaitForChild("Utils")
local UIUtils = require(Utils:WaitForChild("UIUtils"))
local FormatUtils = require(Utils:WaitForChild("FormatUtils"))

-- Defense for missing UIConfig keys
UIConfig.PANEL_COLOR = UIConfig.PANEL_COLOR or Color3.fromRGB(35, 30, 45)
UIConfig.BACKGROUND_COLOR = UIConfig.BACKGROUND_COLOR or Color3.fromRGB(20, 15, 25)
UIConfig.ACCENT_COLOR = UIConfig.ACCENT_COLOR or Color3.fromRGB(150, 100, 255)
UIConfig.TITLE_CHIP_COLOR = UIConfig.TITLE_CHIP_COLOR or Color3.fromRGB(50, 40, 65)
UIConfig.TITLE_CHIP_STROKE = UIConfig.TITLE_CHIP_STROKE or Color3.fromRGB(100, 80, 130)
UIConfig.TEXT_COLOR = UIConfig.TEXT_COLOR or Color3.fromRGB(255, 255, 255)
UIConfig.SECONDARY_TEXT_COLOR = UIConfig.SECONDARY_TEXT_COLOR or Color3.fromRGB(200, 200, 200)
UIConfig.GREEN_COLOR = UIConfig.GREEN_COLOR or Color3.fromRGB(100, 200, 100)
UIConfig.INFO_BLUE_COLOR = UIConfig.INFO_BLUE_COLOR or Color3.fromRGB(60, 120, 200)
UIConfig.BUTTON_DISABLED_COLOR = UIConfig.BUTTON_DISABLED_COLOR or Color3.fromRGB(60, 50, 70)
UIConfig.TWEEN_TIME = UIConfig.TWEEN_TIME or 0.3

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
	mainFrame.Size = UDim2.new(0, 430, 0, 360)
	mainFrame.Position = UDim2.new(0.5, -215, 0.5, -180)
	mainFrame.BackgroundColor3 = UIConfig.PANEL_COLOR
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui
	UIUtils.addCorner(mainFrame, 16)
	UIUtils.addStroke(mainFrame, UIConfig.ACCENT_COLOR, 1.8, 0)

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UIConfig.PANEL_COLOR),
		ColorSequenceKeypoint.new(1, UIConfig.BACKGROUND_COLOR),
	})
	panelGradient.Rotation = 90
	panelGradient.Parent = mainFrame
	
	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1
	header.Parent = mainFrame

	local titleChip = Instance.new("Frame")
	titleChip.Name = "TitleChip"
	titleChip.Size = UDim2.new(0, 250, 0, 44)
	titleChip.Position = UDim2.new(0, 12, 0, 8)
	titleChip.BackgroundColor3 = UIConfig.TITLE_CHIP_COLOR
	titleChip.BorderSizePixel = 0
	titleChip.Parent = header
	UIUtils.addCorner(titleChip, 9)
	UIUtils.addStroke(titleChip, UIConfig.TITLE_CHIP_STROKE, 1.2, 0.1)
	
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -16, 1, 0)
	titleLabel.Position = UDim2.new(0, 10, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "ISLAND SHOP"
	titleLabel.TextColor3 = UIConfig.TEXT_COLOR
	titleLabel.TextSize = 24
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleChip
	
	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 40, 0, 40)
	closeButton.Position = UDim2.new(1, -50, 0, 10)
	closeButton.BackgroundColor3 = UIConfig.RED_COLOR
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.TextSize = 20
	closeButton.Font = Enum.Font.GothamBlack
	closeButton.Parent = header
	UIUtils.addCorner(closeButton, 9)
	UIUtils.addStroke(closeButton, Color3.fromRGB(120, 20, 30), 1.2, 0.1)
	
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
	statusFrame.Size = UDim2.new(1, 0, 0, 108)
	statusFrame.BackgroundColor3 = UIConfig.CARD_COLOR
	statusFrame.BorderSizePixel = 0
	statusFrame.Parent = content
	UIUtils.addCorner(statusFrame, 12)
	UIUtils.addStroke(statusFrame, UIConfig.CARD_COLORStrokeSoft, 1, 0.2)
	
	local tiersLabel = Instance.new("TextLabel")
	tiersLabel.Name = "TiersLabel"
	tiersLabel.Size = UDim2.new(1, -20, 0, 30)
	tiersLabel.Position = UDim2.new(0, 10, 0, 10)
	tiersLabel.BackgroundTransparency = 1
	tiersLabel.Text = "Unlocked Slots: 4 / 96"
	tiersLabel.TextColor3 = UIConfig.TEXT_COLOR
	tiersLabel.TextSize = 18
	tiersLabel.Font = Enum.Font.GothamBold
	tiersLabel.TextXAlignment = Enum.TextXAlignment.Left
	tiersLabel.Parent = statusFrame
	
	local modelsLabel = Instance.new("TextLabel")
	modelsLabel.Name = "ModelsLabel"
	modelsLabel.Size = UDim2.new(1, -20, 0, 25)
	modelsLabel.Position = UDim2.new(0, 10, 0, 42)
	modelsLabel.BackgroundTransparency = 1
	modelsLabel.Text = "Next Upgrade: Expand Grid +4 Slots"
	modelsLabel.TextColor3 = UIConfig.SECONDARY_TEXT_COLOR
	modelsLabel.TextSize = 15
	modelsLabel.Font = Enum.Font.Gotham
	modelsLabel.TextXAlignment = Enum.TextXAlignment.Left
	modelsLabel.Parent = statusFrame
	
	local fillLabel = Instance.new("TextLabel")
	fillLabel.Name = "FillLabel"
	fillLabel.Size = UDim2.new(1, -20, 0, 25)
	fillLabel.Position = UDim2.new(0, 10, 0, 70)
	fillLabel.BackgroundTransparency = 1
	fillLabel.Text = "Progression: +4 slots per purchase"
	fillLabel.TextColor3 = UIConfig.SECONDARY_TEXT_COLOR
	fillLabel.TextSize = 13
	fillLabel.Font = Enum.Font.Gotham
	fillLabel.TextXAlignment = Enum.TextXAlignment.Left
	fillLabel.Parent = statusFrame
	
	-- Purchase section
	local purchaseFrame = Instance.new("Frame")
	purchaseFrame.Name = "PurchaseFrame"
	purchaseFrame.Size = UDim2.new(1, 0, 0, 128)
	purchaseFrame.Position = UDim2.new(0, 0, 0, 118)
	purchaseFrame.BackgroundColor3 = UIConfig.CARD_COLOR
	purchaseFrame.BorderSizePixel = 0
	purchaseFrame.Parent = content
	UIUtils.addCorner(purchaseFrame, 12)
	UIUtils.addStroke(purchaseFrame, UIConfig.CARD_COLORStrokeSoft, 1, 0.2)
	
	local purchaseTitle = Instance.new("TextLabel")
	purchaseTitle.Name = "PurchaseTitle"
	purchaseTitle.Size = UDim2.new(1, -20, 0, 30)
	purchaseTitle.Position = UDim2.new(0, 10, 0, 10)
	purchaseTitle.BackgroundTransparency = 1
	purchaseTitle.Text = "Expand Grid (+4 Slots)"
	purchaseTitle.TextColor3 = UIConfig.TEXT_COLOR
	purchaseTitle.TextSize = 18
	purchaseTitle.Font = Enum.Font.GothamBold
	purchaseTitle.TextXAlignment = Enum.TextXAlignment.Left
	purchaseTitle.Parent = purchaseFrame
	
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "PriceLabel"
	priceLabel.Size = UDim2.new(1, -20, 0, 25)
	priceLabel.Position = UDim2.new(0, 10, 0, 42)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = "Price: $5,000"
	priceLabel.TextColor3 = UIConfig.GREEN_COLOR
	priceLabel.TextSize = 16
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.Parent = purchaseFrame
	
	local purchaseButton = Instance.new("TextButton")
	purchaseButton.Name = "PurchaseButton"
	purchaseButton.Size = UDim2.new(1, -20, 0, 40)
	purchaseButton.Position = UDim2.new(0, 10, 0, 76)
	purchaseButton.BackgroundColor3 = UIConfig.INFO_BLUE_COLOR
	purchaseButton.Text = "EXPAND GRID (+4 SLOTS)"
	purchaseButton.TextColor3 = Color3.new(1, 1, 1)
	purchaseButton.TextSize = 17
	purchaseButton.Font = Enum.Font.GothamBold
	purchaseButton.Parent = purchaseFrame
	UIUtils.addCorner(purchaseButton, 8)
	
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



local function updateShopInfo()
	local info = GetTierInfoEvent:InvokeServer()
	if not info then return end

	local currentSlots = tonumber(info.CurrentSlots) or 4
	local maxSlots = tonumber(info.MaxSlots) or 96
	local nextPrice = tonumber(info.NextPrice) or 0
	local nextUpgradeType = info.NextUpgradeType or "ExpandGrid"

	-- Update status labels
	statusFrame.TiersLabel.Text = string.format("Unlocked Slots: %d / %d", currentSlots, maxSlots)
	statusFrame.ModelsLabel.Text = string.format("Next Upgrade: %s", nextUpgradeType == "NewIsland" and "New Island +4 Slots" or "Expand Grid +4 Slots")
	statusFrame.FillLabel.Text = "Progression: +4 slots per purchase"

	-- Update purchase section
	if info.CanPurchase then
		purchaseFrame.PriceLabel.Text = string.format("Price: %s", FormatUtils.formatMoney(nextPrice))
		if nextUpgradeType == "NewIsland" then
			purchaseFrame.PurchaseButton.BackgroundColor3 = UIConfig.GREEN_COLOR
			purchaseFrame.PurchaseButton.Text = "PURCHASE NEW ISLAND"
			purchaseFrame.PurchaseTitle.Text = "Purchase New Island"
		else
			purchaseFrame.PurchaseButton.BackgroundColor3 = UIConfig.INFO_BLUE_COLOR
			purchaseFrame.PurchaseButton.Text = "EXPAND GRID (+4 SLOTS)"
			purchaseFrame.PurchaseTitle.Text = "Expand Grid (+4 Slots)"
		end
	else
		purchaseFrame.PriceLabel.Text = "Max slots reached!"
		purchaseFrame.PurchaseButton.BackgroundColor3 = UIConfig.BUTTON_DISABLED_COLOR
		purchaseFrame.PurchaseButton.Text = "MAX SLOTS"
		purchaseFrame.PurchaseTitle.Text = "Progression Complete"
	end
end

local function openShop()
	if shopOpen then return end
	shopOpen = true
	
	updateShopInfo()
	
	mainFrame.Visible = true
	mainFrame.Size = UDim2.new(0, 0, 0, 0)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	
	local tween = TweenService:Create(mainFrame, TweenInfo.new(UIConfig.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 430, 0, 360),
		Position = UDim2.new(0.5, -215, 0.5, -180),
	})
	tween:Play()
end

local function closeShop()
	if not shopOpen then return end
	
	local tween = TweenService:Create(mainFrame, TweenInfo.new(UIConfig.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
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
	purchaseFrame.PurchaseButton.BackgroundColor3 = UIConfig.BUTTON_DISABLED_COLOR
	
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
	InteractionDist = 20,
	Keybind = Enum.KeyCode.E,
	OnOpen = openShop,
	OnClose = closeShop,
})

local UIManager = require(script.Parent:WaitForChild("Managers"):WaitForChild("UIManager"))
UIManager.RegisterShop("IslandShop", function()
	if shopOpen then closeShop() else openShop() end
end)

print("IslandShopUI initialized")


