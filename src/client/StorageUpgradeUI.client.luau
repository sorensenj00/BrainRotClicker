--[[
	StorageUpgradeUI LocalScript
	
	Creates a storage upgrade shop interface triggered by StorageVendor.
	Shows current storage, upgrade cost, and new storage after upgrade.
	
	Features:
	- ProximityPrompt-triggered panel
	- Live price and storage level display
	- Animated purchase feedback
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

-- Player reference
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Wait for remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local UpgradeStorageRemote = RemoteEvents:WaitForChild("UpgradeStorage")
local GetStorageInfoRemote = RemoteEvents:WaitForChild("GetStorageInfo")
local StorageUpgradedEvent = RemoteEvents:WaitForChild("StorageUpgraded")

--------------------------------------------------------------------------------
-- UI CONFIGURATION
--------------------------------------------------------------------------------

local UI_CONFIG = {
	-- Panel dimensions
	PANEL_WIDTH = 320,
	PANEL_HEIGHT = 280,
	CORNER_RADIUS = 16,
	
	-- Colors
	BACKGROUND_COLOR = Color3.fromRGB(15, 15, 22),
	PANEL_COLOR = Color3.fromRGB(20, 20, 30),
	ACCENT_COLOR = Color3.fromRGB(250, 190, 60),
	BUTTON_COLOR = Color3.fromRGB(60, 160, 80),
	BUTTON_HOVER_COLOR = Color3.fromRGB(80, 180, 100),
	BUTTON_DISABLED_COLOR = Color3.fromRGB(40, 40, 50),
	TEXT_COLOR = Color3.fromRGB(240, 240, 255),
	SECONDARY_TEXT_COLOR = Color3.fromRGB(160, 160, 180),
	PRICE_COLOR = Color3.fromRGB(250, 190, 60),
	STROKE_COLOR = Color3.fromRGB(70, 70, 90),
	
	-- Animation
	TWEEN_TIME = 0.3,
}

--------------------------------------------------------------------------------
-- SOUNDS
--------------------------------------------------------------------------------

local function createSound(id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local UpgradeSound = createSound("rbxassetid://138081500", 0.5) -- Cash register
local ErrorSound = createSound("rbxassetid://138090596", 0.3) -- Error

--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local StorageGui: ScreenGui? = nil
local StoragePanel: Frame? = nil
local PanelVisible = false
local CurrentStorageInfo = {
	currentMax = 500,
	upgradeLevel = 0,
	nextPrice = 100,
	nextMaxStorage = 1000,
}

--------------------------------------------------------------------------------
-- UI HELPERS
--------------------------------------------------------------------------------

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
	return stroke
end

local function formatMoney(amount: number): string
	if amount >= 1000000 then
		return string.format("$%.1fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("$%.1fK", amount / 1000)
	else
		return "$" .. tostring(math.floor(amount))
	end
end

local function formatStorage(amount: number): string
	if amount >= 1000000 then
		return string.format("%.1fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("%.1fK", amount / 1000)
	else
		return tostring(amount)
	end
end

local function canAfford(): boolean
	local leaderstats = Player:FindFirstChild("leaderstats")
	if not leaderstats then return false end
	
	local money = leaderstats:FindFirstChild("Money")
	if not money then return false end
	
	return money.Value >= CurrentStorageInfo.nextPrice
end

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createStorageUpgradeGui(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StorageUpgradeUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	-- Main panel (starts hidden in center)
	local panel = Instance.new("Frame")
	panel.Name = "StoragePanel"
	panel.Size = UDim2.new(0, UI_CONFIG.PANEL_WIDTH, 0, UI_CONFIG.PANEL_HEIGHT)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui
	addCorner(panel, UI_CONFIG.CORNER_RADIUS)
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = UI_CONFIG.STROKE_COLOR
	stroke.Thickness = 1.5
	stroke.Transparency = 0.5
	stroke.Parent = panel
	
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UI_CONFIG.PANEL_COLOR),
		ColorSequenceKeypoint.new(1, UI_CONFIG.BACKGROUND_COLOR)
	})
	gradient.Rotation = 90
	gradient.Parent = panel
	
	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 50)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "📦 STORAGE UPGRADE"
	titleLabel.TextColor3 = UI_CONFIG.ACCENT_COLOR
	titleLabel.TextSize = 24
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = panel
	
	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Position = UDim2.new(1, -44, 0, 8)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 80, 80)
	closeButton.Text = "✕"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextSize = 20
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Parent = panel
	addCorner(closeButton, 8)
	
	-- Current storage display
	local currentFrame = Instance.new("Frame")
	currentFrame.Name = "CurrentFrame"
	currentFrame.Size = UDim2.new(1, -40, 0, 50)
	currentFrame.Position = UDim2.new(0, 20, 0, 55)
	currentFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
	currentFrame.Parent = panel
	addCorner(currentFrame, 10)
	
	local currentLabel = Instance.new("TextLabel")
	currentLabel.Name = "Label"
	currentLabel.Size = UDim2.new(0.5, 0, 1, 0)
	currentLabel.BackgroundTransparency = 1
	currentLabel.Text = "Current Storage:"
	currentLabel.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
	currentLabel.TextSize = 16
	currentLabel.Font = Enum.Font.Gotham
	currentLabel.TextXAlignment = Enum.TextXAlignment.Left
	currentLabel.Parent = currentFrame
	
	local currentPadding = Instance.new("UIPadding")
	currentPadding.PaddingLeft = UDim.new(0, 15)
	currentPadding.Parent = currentLabel
	
	local currentValue = Instance.new("TextLabel")
	currentValue.Name = "Value"
	currentValue.Size = UDim2.new(0.5, -15, 1, 0)
	currentValue.Position = UDim2.new(0.5, 0, 0, 0)
	currentValue.BackgroundTransparency = 1
	currentValue.Text = "500"
	currentValue.TextColor3 = UI_CONFIG.TEXT_COLOR
	currentValue.TextSize = 22
	currentValue.Font = Enum.Font.GothamBold
	currentValue.TextXAlignment = Enum.TextXAlignment.Right
	currentValue.Parent = currentFrame
	
	-- Arrow and new storage
	local upgradeFrame = Instance.new("Frame")
	upgradeFrame.Name = "UpgradeFrame"
	upgradeFrame.Size = UDim2.new(1, -40, 0, 60)
	upgradeFrame.Position = UDim2.new(0, 20, 0, 115)
	upgradeFrame.BackgroundColor3 = Color3.fromRGB(60, 80, 60)
	upgradeFrame.Parent = panel
	addCorner(upgradeFrame, 10)
	addStroke(upgradeFrame, UI_CONFIG.ACCENT_COLOR, 2)
	
	local upgradeLabel = Instance.new("TextLabel")
	upgradeLabel.Name = "Label"
	upgradeLabel.Size = UDim2.new(1, 0, 0.4, 0)
	upgradeLabel.BackgroundTransparency = 1
	upgradeLabel.Text = "Upgrade to:"
	upgradeLabel.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
	upgradeLabel.TextSize = 14
	upgradeLabel.Font = Enum.Font.Gotham
	upgradeLabel.Parent = upgradeFrame
	
	local newStorageValue = Instance.new("TextLabel")
	newStorageValue.Name = "NewValue"
	newStorageValue.Size = UDim2.new(1, 0, 0.6, 0)
	newStorageValue.Position = UDim2.new(0, 0, 0.4, 0)
	newStorageValue.BackgroundTransparency = 1
	newStorageValue.Text = "1,000 (+100%)"
	newStorageValue.TextColor3 = Color3.fromRGB(100, 255, 100)
	newStorageValue.TextSize = 24
	newStorageValue.Font = Enum.Font.GothamBold
	newStorageValue.Parent = upgradeFrame
	
	-- Price and buy button
	local buyFrame = Instance.new("Frame")
	buyFrame.Name = "BuyFrame"
	buyFrame.Size = UDim2.new(1, -40, 0, 60)
	buyFrame.Position = UDim2.new(0, 20, 0, 190)
	buyFrame.BackgroundTransparency = 1
	buyFrame.Parent = panel
	
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.Size = UDim2.new(0.5, 0, 1, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = "$100"
	priceLabel.TextColor3 = UI_CONFIG.PRICE_COLOR
	priceLabel.TextSize = 28
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.Parent = buyFrame
	
	local buyButton = Instance.new("TextButton")
	buyButton.Name = "BuyButton"
	buyButton.Size = UDim2.new(0.45, 0, 1, 0)
	buyButton.Position = UDim2.new(0.55, 0, 0, 0)
	buyButton.BackgroundColor3 = UI_CONFIG.BUTTON_COLOR
	buyButton.Text = "UPGRADE"
	buyButton.TextColor3 = Color3.fromRGB(0, 0, 0)
	buyButton.TextSize = 18
	buyButton.Font = Enum.Font.GothamBold
	buyButton.Parent = buyFrame
	addCorner(buyButton, 12)
	
	-- Level indicator
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "Level"
	levelLabel.Size = UDim2.new(1, 0, 0, 25)
	levelLabel.Position = UDim2.new(0, 0, 1, -30)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level 0"
	levelLabel.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
	levelLabel.TextSize = 14
	levelLabel.Font = Enum.Font.Gotham
	levelLabel.Parent = panel
	
	return screenGui
end

--------------------------------------------------------------------------------
-- UI LOGIC
--------------------------------------------------------------------------------

local function updateUI()
	if not StoragePanel then return end
	
	-- Update current storage
	local currentFrame = StoragePanel:FindFirstChild("CurrentFrame")
	if currentFrame then
		local valueLabel = currentFrame:FindFirstChild("Value")
		if valueLabel then
			valueLabel.Text = formatStorage(CurrentStorageInfo.currentMax)
		end
	end
	
	-- Update upgrade target
	local upgradeFrame = StoragePanel:FindFirstChild("UpgradeFrame")
	if upgradeFrame then
		local newValueLabel = upgradeFrame:FindFirstChild("NewValue")
		if newValueLabel then
			local percentIncrease = math.floor((CurrentStorageInfo.nextMaxStorage / CurrentStorageInfo.currentMax - 1) * 100)
			newValueLabel.Text = string.format("%s (+%d%%)", formatStorage(CurrentStorageInfo.nextMaxStorage), percentIncrease)
		end
	end
	
	-- Update price and button
	local buyFrame = StoragePanel:FindFirstChild("BuyFrame")
	if buyFrame then
		local priceLabel = buyFrame:FindFirstChild("Price")
		if priceLabel then
			priceLabel.Text = formatMoney(CurrentStorageInfo.nextPrice)
		end
		
		local buyButton = buyFrame:FindFirstChild("BuyButton")
		if buyButton then
			local affordable = canAfford()
			buyButton.BackgroundColor3 = affordable and UI_CONFIG.BUTTON_COLOR or UI_CONFIG.BUTTON_DISABLED_COLOR
		end
	end
	
	-- Update level
	local levelLabel = StoragePanel:FindFirstChild("Level")
	if levelLabel then
		levelLabel.Text = string.format("Level %d", CurrentStorageInfo.upgradeLevel)
	end
end

local function showPanel()
	if PanelVisible then return end
	if not StoragePanel then return end
	
	-- Get fresh data from server
	local info = GetStorageInfoRemote:InvokeServer()
	if info then
		CurrentStorageInfo = info
	end
	
	updateUI()
	
	PanelVisible = true
	StoragePanel.Visible = true
	StoragePanel.Size = UDim2.new(0, 0, 0, 0)
	
	TweenService:Create(StoragePanel, TweenInfo.new(UI_CONFIG.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, UI_CONFIG.PANEL_WIDTH, 0, UI_CONFIG.PANEL_HEIGHT)
	}):Play()
	
	print("StorageUpgradeUI: Opened")
end

local function hidePanel()
	if not PanelVisible then return end
	if not StoragePanel then return end
	
	PanelVisible = false
	
	local tween = TweenService:Create(StoragePanel, TweenInfo.new(UI_CONFIG.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0, 0, 0, 0)
	})
	
	tween:Play()
	tween.Completed:Connect(function()
		if not PanelVisible then
			StoragePanel.Visible = false
		end
	end)
	
	print("StorageUpgradeUI: Closed")
end

local function handleUpgrade()
	if not canAfford() then
		ErrorSound:Play()
		return
	end
	
	local success, message = UpgradeStorageRemote:InvokeServer()
	
	if success then
		UpgradeSound:Play()
		
		-- Visual feedback - flash the panel green
		if StoragePanel then
			local originalColor = StoragePanel.BackgroundColor3
			StoragePanel.BackgroundColor3 = Color3.fromRGB(80, 150, 80)
			task.delay(0.2, function()
				TweenService:Create(StoragePanel, TweenInfo.new(0.3), {BackgroundColor3 = originalColor}):Play()
			end)
		end
		
		print("StorageUpgradeUI: Upgrade successful!")
	else
		ErrorSound:Play()
		warn("StorageUpgradeUI: Upgrade failed - " .. tostring(message))
	end
end

--------------------------------------------------------------------------------
-- SETUP CONNECTIONS
--------------------------------------------------------------------------------

local function setupConnections()
	if not StoragePanel then return end
	
	-- Close button
	local closeButton = StoragePanel:FindFirstChild("CloseButton")
	if closeButton then
		closeButton.MouseButton1Click:Connect(hidePanel)
	end
	
	-- Buy button
	local buyFrame = StoragePanel:FindFirstChild("BuyFrame")
	if buyFrame then
		local buyButton = buyFrame:FindFirstChild("BuyButton")
		if buyButton then
			buyButton.MouseButton1Click:Connect(handleUpgrade)
			
			-- Hover effects
			buyButton.MouseEnter:Connect(function()
				if canAfford() then
					TweenService:Create(buyButton, TweenInfo.new(0.1), {
						BackgroundColor3 = UI_CONFIG.BUTTON_HOVER_COLOR
					}):Play()
				end
			end)
			
			buyButton.MouseLeave:Connect(function()
				local color = canAfford() and UI_CONFIG.BUTTON_COLOR or UI_CONFIG.BUTTON_DISABLED_COLOR
				TweenService:Create(buyButton, TweenInfo.new(0.1), {
					BackgroundColor3 = color
				}):Play()
			end)
		end
	end
	
	-- Listen for storage upgraded event
	StorageUpgradedEvent.OnClientEvent:Connect(function(newInfo)
		CurrentStorageInfo = newInfo
		updateUI()
	end)
	
	-- Update affordability when money changes
	local leaderstats = Player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local money = leaderstats:WaitForChild("Money", 5)
		if money then
			money:GetPropertyChangedSignal("Value"):Connect(updateUI)
		end
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("StorageUpgradeUI: Initializing...")
	
	-- Create the UI
	StorageGui = createStorageUpgradeGui()
	if not StorageGui then return end
	
	StoragePanel = StorageGui:FindFirstChild("StoragePanel") :: Frame?
	
	-- Setup connections
	setupConnections()
	
	-- Parent GUI
	StorageGui.Parent = PlayerGui
	
	-- Setup Shop Interaction
	local ShopInteraction = require(script.Parent:WaitForChild("ShopInteraction"))
	local interaction = ShopInteraction.new({
		PromptTag = "StorageUpgradeVendor",
		InteractionDist = 20,
		Keybind = Enum.KeyCode.E,
		OnOpen = showPanel,
		OnClose = hidePanel,
	})
	
	-- Connect Close Button to Interaction
	if StoragePanel then
		local closeButton = StoragePanel:FindFirstChild("CloseButton")
		if closeButton then
			closeButton.MouseButton1Click:Connect(function() 
				interaction:Close() 
			end)
		end
	end
	
	local adminEvent = ReplicatedStorage:WaitForChild("AdminOpenShop", 5)
	if adminEvent then
		adminEvent.Event:Connect(function(shopName)
			if shopName == "StorageUpgrades" then
				if PanelVisible then hidePanel() else showPanel() end
			end
		end)
	end
	
	print("StorageUpgradeUI: Ready!")
end

-- Start
initialize()
