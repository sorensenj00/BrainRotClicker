--[[
	CartShopUI Client Script
	
	Handles the UI for the Cart Shop where players can:
	1. Upgrade Cart Capacity
	2. Upgrade Cart Speed
	3. Buy new Cart Models
	
	Opens when player presses E near the Cart Shop vendor.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Player reference
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local CartShopConfig = require(Shared:WaitForChild("CartShopConfig"))
local ShopInteraction = require(script.Parent:WaitForChild("ShopInteraction"))

-- Remote Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseUpgradeEvent = RemoteEvents:WaitForChild("PurchaseCartUpgrade")
local GetUpgradesInfoEvent = RemoteEvents:WaitForChild("GetCartUpgradeInfo")

-- Configuration
local UI_CONFIG = {
	TWEEN_TIME = 0.3,
	COLORS = {
		Background = Color3.fromRGB(15, 15, 22),
		Header = Color3.fromRGB(20, 20, 30),
		Card = Color3.fromRGB(25, 25, 35),
		CardMaxed = Color3.fromRGB(20, 35, 25),
		Accent = Color3.fromRGB(250, 190, 60),
		Text = Color3.fromRGB(240, 240, 255),
		TextMuted = Color3.fromRGB(160, 160, 180),
		Green = Color3.fromRGB(80, 230, 120),
		Red = Color3.fromRGB(250, 70, 70),
		Button = Color3.fromRGB(60, 160, 80),
		ButtonDisabled = Color3.fromRGB(40, 40, 50),
		Stroke = Color3.fromRGB(70, 70, 90),
	},
}

-- State
local shopOpen = false
local currentInfo = nil

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function formatPrice(price: number): string
	if not price then return "MAX" end
	local suffixes = {"K", "M", "B", "T"}
	if price < 1000 then return tostring(math.floor(price)) end
	local magnitude = math.floor(math.log(price, 1000))
	if magnitude > #suffixes then magnitude = #suffixes end
	local value = price / (1000 ^ magnitude)
	return string.format("%.1f%s", value, suffixes[magnitude])
end

local function createShopUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CartShopUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	-- Main Frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 400, 0, 550)
	mainFrame.Position = UDim2.new(0.5, -200, 0.5, -275)
	mainFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	mainFrame.BackgroundTransparency = 0.2
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui
	
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 16)
	uiCorner.Parent = mainFrame
	
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = UI_CONFIG.COLORS.Stroke
	uiStroke.Thickness = 1.5
	uiStroke.Transparency = 0.5
	uiStroke.Parent = mainFrame
	
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UI_CONFIG.COLORS.Header),
		ColorSequenceKeypoint.new(1, UI_CONFIG.COLORS.Background)
	})
	gradient.Rotation = 90
	gradient.Parent = mainFrame
	
	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Parent = mainFrame
	
	local title = Instance.new("TextLabel")
	title.Text = "🛒 CART UPGRADES"
	title.Size = UDim2.new(1, -50, 1, 0)
	title.Position = UDim2.new(0, 20, 0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = UI_CONFIG.COLORS.Accent
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Text = "✕"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -50, 0, 10)
	closeBtn.BackgroundColor3 = UI_CONFIG.COLORS.Red
	closeBtn.TextColor3 = Color3.new(1,1,1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.Parent = header
	local closeCorner = Instance.new("UICorner"); closeCorner.CornerRadius = UDim.new(0.5,0); closeCorner.Parent = closeBtn
	
	-- Content
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -20, 1, -80)
	content.Position = UDim2.new(0, 10, 0, 70)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 4
	content.Parent = mainFrame
	
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content
	
	screenGui.Parent = playerGui
	return screenGui, content, closeBtn
end

--------------------------------------------------------------------------------
-- CARD CREATION
--------------------------------------------------------------------------------

local function createUpgradeCard(parent, id, title, icon, data, upgradeType)
	local card = Instance.new("Frame")
	card.Name = id
	card.Size = UDim2.new(1, -10, 0, 140)
	card.BackgroundColor3 = UI_CONFIG.COLORS.Card
	card.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card
	
	-- Icon
	local iconLbl = Instance.new("TextLabel")
	iconLbl.Text = icon
	iconLbl.Size = UDim2.new(0, 60, 0, 60)
	iconLbl.Position = UDim2.new(0, 10, 0, 10)
	iconLbl.BackgroundTransparency = 1
	iconLbl.TextSize = 40
	iconLbl.Parent = card
	
	-- Title
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Text = title
	titleLbl.Size = UDim2.new(1, -80, 0, 25)
	titleLbl.Position = UDim2.new(0, 80, 0, 10)
	titleLbl.BackgroundTransparency = 1
	titleLbl.TextColor3 = UI_CONFIG.COLORS.Text
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.TextSize = 18
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = card
	
	-- Stats
	local statsLbl = Instance.new("TextLabel")
	statsLbl.Name = "Stats"
	statsLbl.Size = UDim2.new(1, -80, 0, 40)
	statsLbl.Position = UDim2.new(0, 80, 0, 35)
	statsLbl.BackgroundTransparency = 1
	statsLbl.TextColor3 = UI_CONFIG.COLORS.TextMuted
	statsLbl.Font = Enum.Font.Gotham
	statsLbl.TextSize = 14
	statsLbl.TextXAlignment = Enum.TextXAlignment.Left
	statsLbl.TextWrapped = true
	statsLbl.Parent = card
	
	if data.IsMaxed then
		statsLbl.Text = string.format("Current: %s\nMAXED OUT", tostring(data.CurrentValue))
		card.BackgroundColor3 = UI_CONFIG.COLORS.CardMaxed
	else
		statsLbl.Text = string.format("Current: %s\nNext: %s", tostring(data.CurrentValue), tostring(data.NextValue))
	end
	
	-- Button
	local btn = Instance.new("TextButton")
	btn.Name = "BuyButton"
	btn.Size = UDim2.new(1, -20, 0, 40)
	btn.Position = UDim2.new(0, 10, 1, -50)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.Parent = card
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = btn
	
	if data.IsMaxed then
		btn.Text = "MAXED"
		btn.BackgroundColor3 = UI_CONFIG.COLORS.ButtonDisabled
		btn.AutoButtonColor = false
	else
		btn.Text = "UPGRADE ($" .. formatPrice(data.Price) .. ")"
		btn.BackgroundColor3 = UI_CONFIG.COLORS.Button
		
		btn.MouseButton1Click:Connect(function()
			PurchaseUpgradeEvent:FireServer(upgradeType)
		end)
	end
	
	return card
end

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local screenGui, contentFrame, closeBtn = createShopUI()
local mainFrame = screenGui.MainFrame

local function updateUI()
	if not currentInfo then return end
	
	-- Clear
	for _, c in contentFrame:GetChildren() do
		if c:IsA("Frame") then c:Destroy() end
	end
	
	-- 1. Capacity
	createUpgradeCard(contentFrame, "Capacity", "Cart Capacity", "📦", currentInfo.Capacity, "Capacity").LayoutOrder = 1
	
	-- 3. Model
	local modelData = currentInfo.Model
	-- For display, show current model vs next model name
	local displayData = {
		CurrentValue = CartShopConfig.Carts[modelData.CurrentValue] and CartShopConfig.Carts[modelData.CurrentValue].Name or "Unknown",
		NextValue = modelData.Name, -- GetUpgradeInfo returns next cart name in 'Name' field for models
		Price = modelData.Price,
		IsMaxed = modelData.IsMaxed
	}
	createUpgradeCard(contentFrame, "Model", "New Cart Model", "🛒", displayData, "Model").LayoutOrder = 3
	
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 450) -- Approx
end

local function refreshInfo()
	currentInfo = GetUpgradesInfoEvent:InvokeServer()
	updateUI()
end

local function openShop()
	if shopOpen then return end
	shopOpen = true
	mainFrame.Visible = true
	
	-- Animate
	mainFrame.Size = UDim2.new(0,0,0,0)
	TweenService:Create(mainFrame, TweenInfo.new(UI_CONFIG.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 400, 0, 550)
	}):Play()
	
	refreshInfo()
end

local function closeShop()
	if not shopOpen then return end
	
	TweenService:Create(mainFrame, TweenInfo.new(UI_CONFIG.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0,0,0,0)
	}):Play()
	
	task.wait(UI_CONFIG.TWEEN_TIME)
	mainFrame.Visible = false
	shopOpen = false
end

--------------------------------------------------------------------------------
-- HANDLERS
--------------------------------------------------------------------------------

PurchaseUpgradeEvent.OnClientEvent:Connect(function(success, message)
	if success then
		refreshInfo()
	else
		warn("Purchase failed: " .. tostring(message))
	end
end)

local _interaction = ShopInteraction.new({
	PromptTag = "CartShopVendor",
	InteractionDist = 20,
	Keybind = Enum.KeyCode.E,
	OnOpen = openShop,
	OnClose = closeShop,
})

closeBtn.MouseButton1Click:Connect(function()
	_interaction:Close()
end)

local adminEvent = ReplicatedStorage:WaitForChild("AdminOpenShop", 5)
if adminEvent then
	adminEvent.Event:Connect(function(shopName)
		if shopName == "CartShop" then
			if shopOpen then closeShop() else openShop() end
		end
	end)
end

print("✓ CartShopUI initialized")
