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
local UIConfig = require(Shared:WaitForChild("UIConfig"))

UIConfig.PANEL_COLOR = UIConfig.PANEL_COLOR or Color3.fromRGB(35, 30, 45)
UIConfig.BACKGROUND_COLOR = UIConfig.BACKGROUND_COLOR or Color3.fromRGB(20, 15, 25)
UIConfig.STROKE_COLOR = UIConfig.STROKE_COLOR or Color3.fromRGB(80, 70, 100)
UIConfig.SOFT_STROKE_COLOR = UIConfig.SOFT_STROKE_COLOR or Color3.fromRGB(60, 50, 70)
UIConfig.TITLE_CHIP_COLOR = UIConfig.TITLE_CHIP_COLOR or Color3.fromRGB(50, 40, 65)
UIConfig.TITLE_CHIP_STROKE = UIConfig.TITLE_CHIP_STROKE or Color3.fromRGB(100, 80, 130)
UIConfig.TEXT_COLOR = UIConfig.TEXT_COLOR or Color3.fromRGB(255, 255, 255)
UIConfig.SECONDARY_TEXT_COLOR = UIConfig.SECONDARY_TEXT_COLOR or Color3.fromRGB(200, 200, 200)
UIConfig.RED_COLOR = UIConfig.RED_COLOR or Color3.fromRGB(210, 55, 65)
UIConfig.ACCENT_COLOR = UIConfig.ACCENT_COLOR or Color3.fromRGB(150, 100, 255)
UIConfig.CARD_COLOR = UIConfig.CARD_COLOR or Color3.fromRGB(45, 40, 55)
UIConfig.CARD_INNER_COLOR = UIConfig.CARD_INNER_COLOR or Color3.fromRGB(35, 30, 45)
UIConfig.CARD_MAXED_COLOR = UIConfig.CARD_MAXED_COLOR or Color3.fromRGB(60, 50, 80)
UIConfig.BUTTON_COLOR = UIConfig.BUTTON_COLOR or Color3.fromRGB(150, 100, 255)
UIConfig.BUTTON_DISABLED_COLOR = UIConfig.BUTTON_DISABLED_COLOR or Color3.fromRGB(60, 50, 70)
UIConfig.TWEEN_TIME = UIConfig.TWEEN_TIME or 0.15

local Utils = Shared:WaitForChild("Utils")
local UIUtils = require(Utils:WaitForChild("UIUtils"))
local FormatUtils = require(Utils:WaitForChild("FormatUtils"))
local ViewportPreview = require(Shared:WaitForChild("ViewportPreview"))

-- Remote Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local UpgradeCartCapacityEvent = RemoteEvents:WaitForChild("UpgradeCartCapacity")
local UpgradeCartTierEvent = RemoteEvents:WaitForChild("UpgradeCartTier")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local GetUpgradesInfoEvent = RemoteFunctions:WaitForChild("GetCartUpgradeInfo")

-- State
local shopOpen = false
local currentInfo = nil

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------


local function formatPrice(price)
	if not price then return "MAX" end
	return FormatUtils.formatPrice(price)
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
	mainFrame.BackgroundColor3 = UIConfig.PANEL_COLOR
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui
	
	UIUtils.addCorner(mainFrame, 16)
	UIUtils.addStroke(mainFrame, UIConfig.STROKE_COLOR, 1.8, 0.15)
	
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UIConfig.PANEL_COLOR),
		ColorSequenceKeypoint.new(1, UIConfig.BACKGROUND_COLOR)
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
	
	local titleChip = Instance.new("Frame")
	titleChip.Name = "TitleChip"
	titleChip.Size = UDim2.new(0, 270, 0, 44)
	titleChip.Position = UDim2.new(0, 12, 0, 8)
	titleChip.BackgroundColor3 = UIConfig.TITLE_CHIP_COLOR
	titleChip.BorderSizePixel = 0
	titleChip.Parent = header
	UIUtils.addCorner(titleChip, 9)
	UIUtils.addStroke(titleChip, UIConfig.TITLE_CHIP_STROKE, 1.2, 0.1)
	
	local title = Instance.new("TextLabel")
	title.Text = "CART UPGRADES"
	title.Size = UDim2.new(1, -16, 1, 0)
	title.Position = UDim2.new(0, 10, 0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = UIConfig.TEXT_COLOR
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 23
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = titleChip
	
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Text = "X"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -50, 0, 10)
	closeBtn.BackgroundColor3 = UIConfig.RED_COLOR
	closeBtn.TextColor3 = Color3.new(1,1,1)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 20
	closeBtn.Parent = header
	UIUtils.addCorner(closeBtn, 9)
	UIUtils.addStroke(closeBtn, Color3.fromRGB(120, 20, 30), 1.2, 0.1)
	
	-- Content
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -20, 1, -80)
	content.Position = UDim2.new(0, 10, 0, 70)
	content.BackgroundColor3 = UIConfig.CARD_INNER_COLOR
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 4
	content.ScrollBarImageColor3 = UIConfig.ACCENT_COLOR
	content.Parent = mainFrame
	UIUtils.addCorner(content, 10)
	UIUtils.addStroke(content, UIConfig.SOFT_STROKE_COLOR, 1, 0.25)
	
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		content.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
	end)
	
	screenGui.Parent = playerGui
	return screenGui, content, closeBtn
end

--------------------------------------------------------------------------------
-- CARD CREATION
--------------------------------------------------------------------------------

local function createUpgradeCard(parent, id, title, icon, data)
	local card = Instance.new("Frame")
	card.Name = id
	card.Size = UDim2.new(1, -10, 0, 140)
	card.BackgroundColor3 = UIConfig.CARD_COLOR
	card.Parent = parent
	
	UIUtils.addCorner(card, 10)
	UIUtils.addStroke(card, UIConfig.SOFT_STROKE_COLOR, 1, 0.2)
	
	-- Icon Container
	local iconContainer = Instance.new("Frame")
	iconContainer.Name = "IconContainer"
	iconContainer.Size = UDim2.new(0, 60, 0, 60)
	iconContainer.Position = UDim2.new(0, 10, 0, 10)
	iconContainer.BackgroundTransparency = 1
	iconContainer.Parent = card
	
	if data.ViewportModel then
		iconContainer.BackgroundTransparency = 0
		iconContainer.BackgroundColor3 = UIConfig.CARD_INNER_COLOR
		UIUtils.addCorner(iconContainer, 6)
		
		local targetModel = data.ViewportModel
		if data.IsSilhouette then
			ViewportPreview.CreateSilhouette(targetModel, iconContainer)
		else
			ViewportPreview.CreateStatic(targetModel, iconContainer)
		end
	else
		local iconLbl = Instance.new("TextLabel")
		iconLbl.Text = icon
		iconLbl.Size = UDim2.new(1, 0, 1, 0)
		iconLbl.BackgroundTransparency = 1
		iconLbl.TextSize = 40
		iconLbl.Parent = iconContainer
	end
	
	-- Title
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Text = title
	titleLbl.Size = UDim2.new(1, -80, 0, 25)
	titleLbl.Position = UDim2.new(0, 80, 0, 10)
	titleLbl.BackgroundTransparency = 1
	titleLbl.TextColor3 = UIConfig.TEXT_COLOR
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
	statsLbl.TextColor3 = UIConfig.SECONDARY_TEXT_COLOR
	statsLbl.Font = Enum.Font.Gotham
	statsLbl.TextSize = 14
	statsLbl.TextXAlignment = Enum.TextXAlignment.Left
	statsLbl.TextWrapped = true
	statsLbl.Parent = card
	
	if data.IsMaxed then
		statsLbl.Text = string.format("Current: %s\nMAXED OUT", tostring(data.CurrentValue))
		card.BackgroundColor3 = UIConfig.CARD_MAXED_COLOR
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
		btn.BackgroundColor3 = UIConfig.BUTTON_DISABLED_COLOR
		btn.AutoButtonColor = false
	else
		btn.Text = data.ButtonText or ("UPGRADE ($" .. formatPrice(data.Price) .. ")")
		btn.BackgroundColor3 = UIConfig.BUTTON_COLOR
		
		if data.OnClick then
			btn.MouseButton1Click:Connect(data.OnClick)
		end
	end
	
	return card
end

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local screenGui, contentFrame, closeBtn = createShopUI()
local mainFrame = screenGui.MainFrame

local function normalizeUpgradeInfo(rawInfo)
	local capacity = rawInfo.capacity
	if not capacity and rawInfo.Capacity then
		capacity = {
			level = rawInfo.CurrentTiers and rawInfo.CurrentTiers.Capacity or 0,
			current = rawInfo.Capacity.CurrentValue,
			next = rawInfo.Capacity.NextValue,
			price = rawInfo.Capacity.Price,
			canUpgrade = not rawInfo.Capacity.IsMaxed,
		}
	end

	local tier = rawInfo.tier
	if not tier and rawInfo.Model then
		local currentTier = (rawInfo.CurrentTiers and rawInfo.CurrentTiers.Model) or rawInfo.Model.CurrentValue or 1
		tier = {
			current = currentTier,
			next = rawInfo.Model.NextValue,
			max = #CartShopConfig.Carts,
			canUpgrade = not rawInfo.Model.IsMaxed,
			price = rawInfo.Model.Price,
			name = rawInfo.Model.Name,
		}
	end

	return capacity, tier
end

local function updateUI()
	if not currentInfo then return end

	for _, c in contentFrame:GetChildren() do
		if c:IsA('Frame') then c:Destroy() end
	end

	local capacityInfo, tierInfo = normalizeUpgradeInfo(currentInfo)
	if not capacityInfo or not tierInfo then
		return
	end

	local capacityCardData = {
		CurrentValue = tostring(capacityInfo.current) .. ' Capacity',
		NextValue = capacityInfo.next and (tostring(capacityInfo.next) .. ' Capacity') or 'MAX',
		Price = capacityInfo.price,
		IsMaxed = not capacityInfo.canUpgrade,
		ButtonText = 'UPGRADE CAPACITY ($' .. formatPrice(capacityInfo.price) .. ')',
		OnClick = function()
			UpgradeCartCapacityEvent:FireServer()
		end,
	}
	createUpgradeCard(contentFrame, 'Capacity', 'Upgrade Current Cart', 'C', capacityCardData).LayoutOrder = 1

	local nextTier = tierInfo.next or tierInfo.current
	local currentCapacityAtTier = CartShopConfig.GetValue('Capacity', tierInfo.current - 1)
	local nextCapacityAtTier = CartShopConfig.GetValue('Capacity', nextTier - 1)
	local nextCartModelRef = ReplicatedStorage.Models.Carts:FindFirstChild('CartTier' .. tostring(nextTier))
	local tierName = (CartShopConfig.Carts[nextTier] and CartShopConfig.Carts[nextTier].Name) or ('Tier ' .. tostring(nextTier))

	local tierCardData = {
		CurrentValue = string.format('Tier %d (%d Capacity)', tierInfo.current, currentCapacityAtTier),
		NextValue = string.format('%s (%d Capacity)', tierName, nextCapacityAtTier),
		Price = tierInfo.price,
		IsMaxed = not tierInfo.canUpgrade,
		ViewportModel = nextCartModelRef,
		IsSilhouette = false,
		ButtonText = tierInfo.canUpgrade and ('GET NEXT TIER ($' .. formatPrice(tierInfo.price) .. ')') or 'MAX TIER',
		OnClick = function()
			UpgradeCartTierEvent:FireServer()
		end,
	}
	createUpgradeCard(contentFrame, 'Model', 'Buy Next Cart Tier', 'T', tierCardData).LayoutOrder = 2

	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 450)
end

local function refreshInfo()
	currentInfo = GetUpgradesInfoEvent:InvokeServer()
	updateUI()
end

local function openShop()
	if shopOpen then return end
	shopOpen = true
	mainFrame.Visible = true

	mainFrame.Size = UDim2.new(0, 0, 0, 0)
	TweenService:Create(mainFrame, TweenInfo.new(UIConfig.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 400, 0, 550)
	}):Play()

	refreshInfo()
end

local function closeShop()
	if not shopOpen then return end

	TweenService:Create(mainFrame, TweenInfo.new(UIConfig.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0)
	}):Play()

	task.wait(UIConfig.TWEEN_TIME)
	mainFrame.Visible = false
	shopOpen = false
end

--------------------------------------------------------------------------------
-- HANDLERS
--------------------------------------------------------------------------------

local function handleUpgradeResult(success, message)
	if success then
		refreshInfo()
	else
		warn('Purchase failed: ' .. tostring(message))
	end
end

UpgradeCartCapacityEvent.OnClientEvent:Connect(handleUpgradeResult)
UpgradeCartTierEvent.OnClientEvent:Connect(handleUpgradeResult)

local _interaction = ShopInteraction.new({
	PromptTag = 'CartShopVendor',
	InteractionDist = 20,
	Keybind = Enum.KeyCode.E,
	OnOpen = openShop,
	OnClose = closeShop,
})

closeBtn.MouseButton1Click:Connect(function()
	_interaction:Close()
end)

local UIManager = require(script.Parent:WaitForChild('Managers'):WaitForChild('UIManager'))
UIManager.RegisterShop('CartShop', function()
	if shopOpen then closeShop() else openShop() end
end)

print('CartShopUI initialized')

