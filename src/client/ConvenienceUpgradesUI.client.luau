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
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- Player reference
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Modules
local ConvenienceUpgradesConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ConvenienceUpgradesConfig"))

-- Remote Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseUpgradeEvent = RemoteEvents:WaitForChild("PurchaseConvenienceUpgrade")
local GetUpgradesInfoEvent = RemoteEvents:WaitForChild("GetConvenienceUpgradesInfo")

-- Configuration
local UI_CONFIG = {
	INTERACTION_DISTANCE = 20,
	TWEEN_TIME = 0.3,
	COLORS = {
		Background = Color3.fromRGB(25, 20, 35),
		Header = Color3.fromRGB(80, 50, 30),
		Card = Color3.fromRGB(40, 30, 50),
		CardOwned = Color3.fromRGB(30, 60, 40),
		CardLocked = Color3.fromRGB(50, 40, 50),
		Accent = Color3.fromRGB(255, 180, 80),
		Text = Color3.fromRGB(255, 255, 255),
		TextMuted = Color3.fromRGB(150, 150, 150),
		Green = Color3.fromRGB(100, 255, 100),
		Red = Color3.fromRGB(255, 100, 100),
	},
}

-- State
local shopOpen = false
local currentCategory = "Movement"
local ownedUpgrades: {string} = {}

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function formatPrice(price: number): string
	local suffixes = {"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}
	
	if price < 1000 then
		return tostring(math.floor(price))
	end
	
	-- Calculate the magnitude (power of 1000)
	local magnitude = math.floor(math.log(price, 1000))
	
	-- Cap at the largest suffix
	if magnitude > #suffixes then
		magnitude = #suffixes
	end
	
	local value = price / (1000 ^ magnitude)
	
	-- Format with 1 decimal place if < 100, otherwise no decimals
	if value < 100 and value % 1 ~= 0 then
		return string.format("%.1f%s", value, suffixes[magnitude])
	else
		return string.format("%.0f%s", value, suffixes[magnitude])
	end
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
	mainFrame.Size = UDim2.new(0, 550, 0, 500)
	mainFrame.Position = UDim2.new(0.5, -275, 0.5, -250)
	mainFrame.BackgroundColor3 = UI_CONFIG.COLORS.Background
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui
	
	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 16)
	mainCorner.Parent = mainFrame
	
	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = UI_CONFIG.COLORS.Accent
	mainStroke.Thickness = 2
	mainStroke.Parent = mainFrame
	
	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundColor3 = UI_CONFIG.COLORS.Header
	header.BorderSizePixel = 0
	header.Parent = mainFrame
	
	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 16)
	headerCorner.Parent = header
	
	local headerFix = Instance.new("Frame")
	headerFix.Size = UDim2.new(1, 0, 0, 16)
	headerFix.Position = UDim2.new(0, 0, 1, -16)
	headerFix.BackgroundColor3 = UI_CONFIG.COLORS.Header
	headerFix.BorderSizePixel = 0
	headerFix.Parent = header
	
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -60, 1, 0)
	titleLabel.Position = UDim2.new(0, 20, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "⚡ CONVENIENCE UPGRADES"
	titleLabel.TextColor3 = UI_CONFIG.COLORS.Accent
	titleLabel.TextSize = 24
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
	
	-- Category tabs
	local tabsFrame = Instance.new("Frame")
	tabsFrame.Name = "TabsFrame"
	tabsFrame.Size = UDim2.new(1, -40, 0, 40)
	tabsFrame.Position = UDim2.new(0, 20, 0, 70)
	tabsFrame.BackgroundTransparency = 1
	tabsFrame.Parent = mainFrame
	
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 10)
	tabsLayout.Parent = tabsFrame
	
	-- Content area (scrolling)
	local contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "ContentFrame"
	contentFrame.Size = UDim2.new(1, -40, 1, -140)
	contentFrame.Position = UDim2.new(0, 20, 0, 120)
	contentFrame.BackgroundTransparency = 1
	contentFrame.ScrollBarThickness = 6
	contentFrame.ScrollBarImageColor3 = UI_CONFIG.COLORS.Accent
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.Parent = mainFrame
	
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
local tabsFrame = mainFrame:WaitForChild("TabsFrame")
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

local function createCategoryTab(category: string, index: number)
	local icons = {
		Movement = "🏃",
		Income = "💰",
		Automation = "🤖",
	}
	
	local tab = Instance.new("TextButton")
	tab.Name = "Tab_" .. category
	tab.Size = UDim2.new(0, 120, 1, 0)
	tab.BackgroundColor3 = currentCategory == category and UI_CONFIG.COLORS.Accent or UI_CONFIG.COLORS.Card
	tab.Text = (icons[category] or "📦") .. " " .. category
	tab.TextColor3 = UI_CONFIG.COLORS.Text
	tab.TextSize = 14
	tab.Font = Enum.Font.GothamBold
	tab.Parent = tabsFrame
	
	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(0, 8)
	tabCorner.Parent = tab
	
	tab.MouseButton1Click:Connect(function()
		currentCategory = category
		refreshShop()
	end)
	
	return tab
end

local function createUpgradeCard(upgradeName: string, config)
	local owned = isOwned(upgradeName)
	local canPurchase, reason = ConvenienceUpgradesConfig.CanPurchase(upgradeName, ownedUpgrades)
	
	local cardColor = owned and UI_CONFIG.COLORS.CardOwned 
		or (canPurchase and UI_CONFIG.COLORS.Card or UI_CONFIG.COLORS.CardLocked)
	
	local card = Instance.new("Frame")
	card.Name = "Card_" .. upgradeName
	card.Size = UDim2.new(1, 0, 0, 90)
	card.BackgroundColor3 = cardColor
	card.Parent = contentFrame
	
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = card
	
	-- Icon
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(0, 50, 0, 50)
	iconLabel.Position = UDim2.new(0, 15, 0.5, -25)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = config.Icon
	iconLabel.TextSize = 36
	iconLabel.Parent = card
	
	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0, 250, 0, 25)
	nameLabel.Position = UDim2.new(0, 75, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = upgradeName
	nameLabel.TextColor3 = UI_CONFIG.COLORS.Text
	nameLabel.TextSize = 16
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = card
	
	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(0, 300, 0, 40)
	descLabel.Position = UDim2.new(0, 75, 0, 35)
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
		ownedLabel.Size = UDim2.new(0, 100, 0, 30)
		ownedLabel.Position = UDim2.new(1, -115, 0.5, -15)
		ownedLabel.BackgroundColor3 = UI_CONFIG.COLORS.Green
		ownedLabel.Text = "✓ OWNED"
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
		buyButton.Size = UDim2.new(0, 100, 0, 40)
		buyButton.Position = UDim2.new(1, -115, 0.5, -20)
		buyButton.BackgroundColor3 = canPurchase and UI_CONFIG.COLORS.Accent or UI_CONFIG.COLORS.CardLocked
		buyButton.Text = "$" .. formatPrice(config.Price)
		buyButton.TextColor3 = Color3.new(0, 0, 0)
		buyButton.TextSize = 14
		buyButton.Font = Enum.Font.GothamBold
		buyButton.Parent = card
		
		local buyCorner = Instance.new("UICorner")
		buyCorner.CornerRadius = UDim.new(0, 6)
		buyCorner.Parent = buyButton
		
		if not canPurchase and reason then
			local reasonLabel = Instance.new("TextLabel")
			reasonLabel.Size = UDim2.new(0, 100, 0, 15)
			reasonLabel.Position = UDim2.new(1, -115, 1, -20)
			reasonLabel.BackgroundTransparency = 1
			reasonLabel.Text = reason
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
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	
	-- Update tabs
	for _, child in tabsFrame:GetChildren() do
		if child:IsA("TextButton") then
			child.BackgroundColor3 = child.Name == "Tab_" .. currentCategory 
				and UI_CONFIG.COLORS.Accent or UI_CONFIG.COLORS.Card
		end
	end
	
	-- Get upgrades for current category
	local categoryUpgrades = ConvenienceUpgradesConfig.GetUpgradesByCategory(currentCategory)
	
	-- Create cards
	for _, item in categoryUpgrades do
		createUpgradeCard(item.name, item.config)
	end
	
	-- Update canvas size
	local layout = contentFrame:FindFirstChild("UIListLayout")
	if layout then
		contentFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
	end
end

local function loadUpgradesInfo()
	local info = GetUpgradesInfoEvent:InvokeServer()
	if info then
		ownedUpgrades = info.OwnedUpgrades or {}
		
		-- Create category tabs
		for _, child in tabsFrame:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		
		for i, category in info.Categories or {"Movement", "Income", "Automation"} do
			createCategoryTab(category, i)
		end
	end
end

local function openShop()
	if shopOpen then return end
	shopOpen = true
	
	loadUpgradesInfo()
	refreshShop()
	
	mainFrame.Visible = true
	mainFrame.Size = UDim2.new(0, 0, 0, 0)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	
	local tween = TweenService:Create(mainFrame, TweenInfo.new(UI_CONFIG.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 550, 0, 500),
		Position = UDim2.new(0.5, -275, 0.5, -250),
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
mainFrame.Header.CloseButton.MouseButton1Click:Connect(closeShop)

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

-- Handle H key for teleport home separately as it's not part of the standard shop interaction
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.H then
		-- Teleport home if player has the upgrade
		if _G.ConvenienceUpgrades and _G.ConvenienceUpgrades.HasTeleportHome and _G.ConvenienceUpgrades.HasTeleportHome(player) then
			-- Teleport to main island
			local mainIsland = workspace:FindFirstChild("MainIsland")
			if mainIsland then
				local spawnPoint = mainIsland:FindFirstChild("Island") or mainIsland:FindFirstChildWhichIsA("BasePart")
				if spawnPoint and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
					player.Character.HumanoidRootPart.CFrame = spawnPoint.CFrame * CFrame.new(0, 10, 0)
				end
			end
		end
	end
end)

print("✓ ConvenienceUpgradesUI initialized")
