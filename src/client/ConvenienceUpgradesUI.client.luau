--[[
	ConvenienceUpgradesUI Client Script
	
	Handles the UI for the Convenience Upgrades Shop where players can:
	1. Browse upgrades by category
	2. View owned vs available upgrades
	3. Purchase upgrades
	4. See upgrade effects
	
	Opens when player presses E near the Convenience Shop vendor.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Player reference
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Modules
local ConvenienceUpgradesConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ConvenienceUpgradesConfig"))

-- Remote Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseUpgradeEvent = RemoteEvents:WaitForChild("PurchaseConvenienceUpgrade")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local GetUpgradesInfoEvent = RemoteFunctions:WaitForChild("GetConvenienceUpgradesInfo")

-- Configuration
local UI_CONFIG = {
	INTERACTION_DISTANCE = 20,
	TWEEN_TIME = 0.3,
	COLORS = {
		Background = Color3.fromRGB(12, 12, 20),
		Header = Color3.fromRGB(20, 20, 34),
		Card = Color3.fromRGB(31, 31, 52),
		CardOwned = Color3.fromRGB(22, 49, 41),
		CardLocked = Color3.fromRGB(39, 34, 57),
		CardInner = Color3.fromRGB(18, 18, 34),
		Accent = Color3.fromRGB(140, 80, 255),
		TitleChip = Color3.fromRGB(98, 26, 184),
		TitleChipStroke = Color3.fromRGB(175, 120, 255),
		Text = Color3.fromRGB(240, 240, 245),
		TextMuted = Color3.fromRGB(160, 160, 180),
		Green = Color3.fromRGB(80, 230, 120),
		Red = Color3.fromRGB(210, 55, 65),
		PanelStrokeSoft = Color3.fromRGB(70, 55, 120),
	},
}

-- State
local shopOpen = false
local ownedUpgrades: {string} = {}
local currentMoney = 0

local CATEGORY_LABELS = {
	Mobility = "Mobility & Travel",
	Economy = "Income & Payouts",
	Automation = "Automation Systems",
	Utility = "Utility Unlocks",
}

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FormatUtils = require(Shared:WaitForChild("Utils"):WaitForChild("FormatUtils"))

local function formatPrice(price: number): string
	return FormatUtils.formatPrice(price)
end

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number, transparency: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function createShopUI()
	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ConvenienceUpgradesUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	-- Main container
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromOffset(550, 500)
	mainFrame.Position = UDim2.new(0.5, -275, 0.5, -250)
	mainFrame.BackgroundColor3 = UI_CONFIG.COLORS.Header
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui
	addCorner(mainFrame, 16)
	addStroke(mainFrame, UI_CONFIG.COLORS.Accent, 1.8, 0.15)

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UI_CONFIG.COLORS.Header),
		ColorSequenceKeypoint.new(1, UI_CONFIG.COLORS.Background),
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
	titleChip.Size = UDim2.fromOffset(360, 44)
	titleChip.Position = UDim2.fromOffset(12, 8)
	titleChip.BackgroundColor3 = UI_CONFIG.COLORS.TitleChip
	titleChip.BorderSizePixel = 0
	titleChip.Parent = header
	addCorner(titleChip, 9)
	addStroke(titleChip, UI_CONFIG.COLORS.TitleChipStroke, 1.2, 0.1)
	
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -16, 1, 0)
	titleLabel.Position = UDim2.fromOffset(10, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "CONVENIENCE UPGRADES"
	titleLabel.TextColor3 = UI_CONFIG.COLORS.Text
	titleLabel.TextSize = 23
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleChip
	
	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.fromOffset(40, 40)
	closeButton.Position = UDim2.new(1, -50, 0, 10)
	closeButton.BackgroundColor3 = UI_CONFIG.COLORS.Red
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.TextSize = 20
	closeButton.Font = Enum.Font.GothamBlack
	closeButton.Parent = header
	addCorner(closeButton, 9)
	addStroke(closeButton, Color3.fromRGB(120, 20, 30), 1.2, 0.1)

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -40, 0, 20)
	subtitle.Position = UDim2.fromOffset(20, 66)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Modern progression upgrades for every stage"
	subtitle.TextColor3 = UI_CONFIG.COLORS.TextMuted
	subtitle.TextSize = 13
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = mainFrame
	
	-- Content area (scrolling)
	local contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "ContentFrame"
	contentFrame.Size = UDim2.new(1, -40, 1, -130)
	contentFrame.Position = UDim2.fromOffset(20, 90)
	contentFrame.BackgroundColor3 = UI_CONFIG.COLORS.CardInner
	contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 6
	contentFrame.ScrollBarImageColor3 = UI_CONFIG.COLORS.Accent
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.Parent = mainFrame
	addCorner(contentFrame, 10)
	addStroke(contentFrame, UI_CONFIG.COLORS.PanelStrokeSoft, 1, 0.25)
	
	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 10)
	contentLayout.Parent = contentFrame
	
	-- Message label
	local messageLabel = Instance.new("TextLabel")
	messageLabel.Name = "MessageLabel"
	messageLabel.Size = UDim2.new(1, -40, 0, 30)
	messageLabel.Position = UDim2.new(0, 20, 1, -35)
	messageLabel.BackgroundTransparency = 1
	messageLabel.Text = ""
	messageLabel.TextColor3 = UI_CONFIG.COLORS.Green
	messageLabel.TextSize = 14
	messageLabel.Font = Enum.Font.GothamBold
	messageLabel.Parent = mainFrame
	
	screenGui.Parent = playerGui
	return screenGui
end

--------------------------------------------------------------------------------
-- UI COMPONENTS
--------------------------------------------------------------------------------

local screenGui = createShopUI()
local mainFrame = screenGui:WaitForChild("MainFrame")
local contentFrame = mainFrame:WaitForChild("ContentFrame")
local messageLabel = mainFrame:WaitForChild("MessageLabel")

local function isOwned(upgradeName: string): boolean
	for _, owned in ownedUpgrades do
		if owned == upgradeName then
			return true
		end
	end
	return false
end

local function createCategoryHeader(category: string)
	local header = Instance.new("TextLabel")
	header.Name = "Category_" .. category
	header.Size = UDim2.new(1, -12, 0, 28)
	header.BackgroundColor3 = UI_CONFIG.COLORS.TitleChip
	header.Text = string.upper(CATEGORY_LABELS[category] or category)
	header.TextColor3 = UI_CONFIG.COLORS.Text
	header.TextSize = 14
	header.Font = Enum.Font.GothamBold
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = contentFrame
	addCorner(header, 8)
	addStroke(header, UI_CONFIG.COLORS.TitleChipStroke, 1, 0.2)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.Parent = header

	return header
end

local function createUpgradeCard(upgradeName: string, config)
	local owned = isOwned(upgradeName)
	local canPurchaseByState, reason = ConvenienceUpgradesConfig.CanPurchase(upgradeName, ownedUpgrades)
	local canAfford = currentMoney >= config.Price
	local canPurchase = canPurchaseByState and canAfford
	
	local cardColor = owned and UI_CONFIG.COLORS.CardOwned 
		or ((canPurchaseByState and canAfford) and UI_CONFIG.COLORS.Card or UI_CONFIG.COLORS.CardLocked)
	
	local card = Instance.new("Frame")
	card.Name = "Card_" .. upgradeName
	card.Size = UDim2.new(1, 0, 0, 90)
	card.BackgroundColor3 = cardColor
	card.Parent = contentFrame
	
	addCorner(card, 10)
	addStroke(card, UI_CONFIG.COLORS.PanelStrokeSoft, 1, 0.2)
	
	-- Icon
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.fromOffset(50, 50)
	iconLabel.Position = UDim2.new(0, 15, 0.5, -25)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = config.Icon
	iconLabel.TextSize = 36
	iconLabel.Parent = card
	
	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.fromOffset(250, 25)
	nameLabel.Position = UDim2.fromOffset(75, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = upgradeName
	nameLabel.TextColor3 = UI_CONFIG.COLORS.Text
	nameLabel.TextSize = 16
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = card
	
	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.fromOffset(300, 40)
	descLabel.Position = UDim2.fromOffset(75, 35)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = config.Description
	descLabel.TextColor3 = UI_CONFIG.COLORS.TextMuted
	descLabel.TextSize = 12
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextWrapped = true
	descLabel.Parent = card
	
	-- Status/Button
	if owned then
		local ownedLabel = Instance.new("TextLabel")
		ownedLabel.Size = UDim2.fromOffset(100, 30)
		ownedLabel.Position = UDim2.new(1, -115, 0.5, -15)
		ownedLabel.BackgroundColor3 = UI_CONFIG.COLORS.Green
		ownedLabel.Text = "OWNED"
		ownedLabel.TextColor3 = Color3.new(0, 0, 0)
		ownedLabel.TextSize = 14
		ownedLabel.Font = Enum.Font.GothamBold
		ownedLabel.Parent = card
		
		local ownedCorner = Instance.new("UICorner")
		ownedCorner.CornerRadius = UDim.new(0, 6)
		ownedCorner.Parent = ownedLabel
	else
		local buyButton = Instance.new("TextButton")
		buyButton.Name = "BuyButton"
		buyButton.Size = UDim2.fromOffset(100, 40)
		buyButton.Position = UDim2.new(1, -115, 0.5, -20)
		buyButton.BackgroundColor3 = canPurchase and UI_CONFIG.COLORS.Accent or UI_CONFIG.COLORS.CardLocked
		buyButton.Text = "$" .. formatPrice(config.Price)
		buyButton.TextColor3 = Color3.new(1, 1, 1)
		buyButton.TextSize = 14
		buyButton.Font = Enum.Font.GothamBold
		buyButton.Parent = card
		
		local buyCorner = Instance.new("UICorner")
		buyCorner.CornerRadius = UDim.new(0, 6)
		buyCorner.Parent = buyButton
		
		if not canPurchase then
			local reasonLabel = Instance.new("TextLabel")
			reasonLabel.Size = UDim2.fromOffset(100, 15)
			reasonLabel.Position = UDim2.new(1, -115, 1, -20)
			reasonLabel.BackgroundTransparency = 1
			if not canPurchaseByState and reason then
				reasonLabel.Text = reason
			else
				reasonLabel.Text = "Need $" .. formatPrice(config.Price)
			end
			reasonLabel.TextColor3 = UI_CONFIG.COLORS.Red
			reasonLabel.TextSize = 10
			reasonLabel.Font = Enum.Font.Gotham
			reasonLabel.Parent = card
		end
		
		if canPurchase then
			buyButton.MouseButton1Click:Connect(function()
				buyButton.Text = "..."
				buyButton.BackgroundColor3 = UI_CONFIG.COLORS.CardLocked
				PurchaseUpgradeEvent:FireServer(upgradeName)
			end)
		end
	end
	
	return card
end

--------------------------------------------------------------------------------
-- SHOP LOGIC
--------------------------------------------------------------------------------

function refreshShop()
	-- Clear existing content
	for _, child in contentFrame:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local categories = ConvenienceUpgradesConfig.GetCategories()
	for _, category in categories do
		local categoryUpgrades = ConvenienceUpgradesConfig.GetUpgradesByCategory(category)
		if #categoryUpgrades > 0 then
			createCategoryHeader(category)
			for _, item in categoryUpgrades do
				createUpgradeCard(item.name, item.config)
			end
		end
	end
	
	-- Update canvas size
	local layout = contentFrame:FindFirstChild("UIListLayout")
	if layout then
		contentFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 10)
	end
end

local function loadUpgradesInfo()
	local info = GetUpgradesInfoEvent:InvokeServer()
	if info then
		ownedUpgrades = info.OwnedUpgrades or {}
		currentMoney = info.CurrentMoney or 0
	end
end

local function openShop()
	if shopOpen then return end
	shopOpen = true
	
	mainFrame.Visible = true
	mainFrame.Size = UDim2.new(0, 0, 0, 0)
	mainFrame.Position = UDim2.fromScale(0.5, 0.5)
	
	local tween = TweenService:Create(mainFrame, TweenInfo.new(UI_CONFIG.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(550, 500),
		Position = UDim2.new(0.5, -275, 0.5, -250),
	})
	tween:Play()
	
	task.spawn(function()
		loadUpgradesInfo()
		if shopOpen then
			refreshShop()
		end
	end)
end

local function closeShop()
	if not shopOpen then return end
	
	local tween = TweenService:Create(mainFrame, TweenInfo.new(UI_CONFIG.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	tween:Play()
	tween.Completed:Connect(function()
		mainFrame.Visible = false
	end)
	
	shopOpen = false
end

local function showMessage(text: string, color: Color3?)
	messageLabel.Text = text
	messageLabel.TextColor3 = color or UI_CONFIG.COLORS.Green
	
	task.delay(3, function()
		if messageLabel.Text == text then
			messageLabel.Text = ""
		end
	end)
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

-- Close button
-- Connected after _interaction is initialized

-- Purchase result
PurchaseUpgradeEvent.OnClientEvent:Connect(function(success, message)
	if success then
		showMessage(message, UI_CONFIG.COLORS.Green)
	else
		showMessage(message, UI_CONFIG.COLORS.Red)
	end
	
	-- Refresh the shop
	loadUpgradesInfo()
	refreshShop()
end)

--------------------------------------------------------------------------------
-- SHOP INTERACTION
--------------------------------------------------------------------------------

local ShopInteraction = require(script.Parent:WaitForChild("ShopInteraction"))

local _interaction = ShopInteraction.new({
	PromptTag = "ConvenienceShopVendor",
	InteractionDist = UI_CONFIG.INTERACTION_DISTANCE,
	Keybind = Enum.KeyCode.E,
	OnOpen = openShop,
	OnClose = closeShop,
})

mainFrame.Header.CloseButton.MouseButton1Click:Connect(function()
	if _interaction and _interaction.IsOpen then
		_interaction:Close()
	else
		closeShop()
	end
end)

local UIManager = require(script.Parent:WaitForChild("Managers"):WaitForChild("UIManager"))
UIManager.RegisterShop("ConvenienceUpgrades", function()
	if shopOpen then
		closeShop()
	else
		openShop()
	end
end)

print("ConvenienceUpgradesUI initialized")



