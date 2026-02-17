--[[
	ShopUI LocalScript
	
	Creates a Cookie Clicker style shop interface on the right side of the screen.
	Features progressive unlocking system.
	
	Features:
	- Scrolling shop panel
	- Live price updates
	- Ownership count display
	- Locked unit preview (blacked out)
	- Purchase sound effects
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Player reference
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Wait for shared modules and remotes
local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopConfig"))
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyUnitRemote = RemoteEvents:WaitForChild("BuyUnit")
local GetOwnershipRemote = RemoteEvents:WaitForChild("GetOwnership")
local OwnershipChangedEvent = RemoteEvents:WaitForChild("OwnershipChanged")
local UnlockProgressChangedEvent = RemoteEvents:WaitForChild("UnlockProgressChanged")

--------------------------------------------------------------------------------
-- UI CONFIGURATION
--------------------------------------------------------------------------------

local UI_CONFIG = {
	-- Shop Panel
	SHOP_WIDTH = 280,
	SHOP_PADDING = 10,
	
	-- Button styling
	BUTTON_HEIGHT = 130, -- Increased to fit milestone + item cost
	BUTTON_SPACING = 8,
	CORNER_RADIUS = 12,
	
	-- Colors
	BACKGROUND_COLOR = Color3.fromRGB(25, 25, 35),
	PANEL_COLOR = Color3.fromRGB(35, 35, 50),
	BUTTON_COLOR = Color3.fromRGB(50, 50, 70),
	BUTTON_HOVER_COLOR = Color3.fromRGB(65, 65, 90),
	BUTTON_DISABLED_COLOR = Color3.fromRGB(40, 40, 50),
	LOCKED_COLOR = Color3.fromRGB(20, 20, 25),
	LOCKED_OVERLAY_COLOR = Color3.fromRGB(0, 0, 0),
	ACCENT_COLOR = Color3.fromRGB(100, 220, 100),
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	SECONDARY_TEXT_COLOR = Color3.fromRGB(180, 180, 180),
	LOCKED_TEXT_COLOR = Color3.fromRGB(100, 100, 100),
	PRICE_COLOR = Color3.fromRGB(255, 215, 0),
	ITEM_COST_COLOR = Color3.fromRGB(255, 170, 60), -- Orange for item requirements
	
	-- Animation
	TWEEN_TIME = 0.15,
}

--------------------------------------------------------------------------------
-- SOUNDS
--------------------------------------------------------------------------------

-- Create sounds
local function createSound(id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local ChachingSound = createSound("rbxassetid://138081500", 0.5) -- Cash register sound
local ErrorSound = createSound("rbxassetid://138090596", 0.3) -- Error/deny sound

--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

-- Track ownership locally for UI updates
local OwnedCounts: {[string]: number} = {}
local ShopButtons: {[string]: Frame} = {}
local UnlockProgress: number = ShopConfig.INITIAL_UNLOCKED
local ShopGui: ScreenGui? = nil
local ScrollFrame: ScrollingFrame? = nil
local IsOnMainIsland: boolean = false

--------------------------------------------------------------------------------
-- UI CREATION HELPERS
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

--------------------------------------------------------------------------------
-- SHOP UI CREATION
--------------------------------------------------------------------------------

local function createShopGui(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShopUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	-- Main shop panel (right side) - starts HIDDEN (off-screen)
	local shopPanel = Instance.new("Frame")
	shopPanel.Name = "ShopPanel"
	shopPanel.Size = UDim2.new(0, UI_CONFIG.SHOP_WIDTH, 1, -20)
	shopPanel.Position = UDim2.new(1, 10, 0, 10) -- Start off-screen
	shopPanel.BackgroundColor3 = UI_CONFIG.PANEL_COLOR
	shopPanel.BorderSizePixel = 0
	shopPanel.Parent = screenGui
	addCorner(shopPanel, UI_CONFIG.CORNER_RADIUS)
	addStroke(shopPanel, Color3.fromRGB(60, 60, 80), 2)
	
	-- Shop title
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 50)
	titleBar.BackgroundColor3 = UI_CONFIG.BACKGROUND_COLOR
	titleBar.BorderSizePixel = 0
	titleBar.Parent = shopPanel
	
	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, UI_CONFIG.CORNER_RADIUS)
	titleCorner.Parent = titleBar
	
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -40, 1, 0)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "🧠 BRAINROT SHOP"
	titleLabel.TextColor3 = UI_CONFIG.TEXT_COLOR
	titleLabel.TextSize = 20
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = titleBar
	
	-- Close button (X)
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Position = UDim2.new(1, -42, 0.5, -18)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	closeButton.Text = "✕"
	closeButton.TextColor3 = UI_CONFIG.TEXT_COLOR
	closeButton.TextSize = 18
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Parent = titleBar
	addCorner(closeButton, 8)
	
	-- Warning banner for off-island (initially hidden)
	local warningBanner = Instance.new("Frame")
	warningBanner.Name = "WarningBanner"
	warningBanner.Size = UDim2.new(1, 0, 0, 24)
	warningBanner.Position = UDim2.new(0, 0, 0, 50)
	warningBanner.BackgroundColor3 = Color3.fromRGB(180, 80, 30)
	warningBanner.BorderSizePixel = 0
	warningBanner.Visible = false
	warningBanner.Parent = shopPanel
	
	local warningLabel = Instance.new("TextLabel")
	warningLabel.Name = "WarningText"
	warningLabel.Size = UDim2.new(1, 0, 1, 0)
	warningLabel.BackgroundTransparency = 1
	warningLabel.Text = "⚠️ Visit Main Island to purchase"
	warningLabel.TextColor3 = Color3.fromRGB(255, 255, 200)
	warningLabel.TextSize = 12
	warningLabel.Font = Enum.Font.GothamBold
	warningLabel.Parent = warningBanner
	
	-- Scrolling frame for items
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemList"
	scrollFrame.Size = UDim2.new(1, -UI_CONFIG.SHOP_PADDING * 2, 1, -60)
	scrollFrame.Position = UDim2.new(0, UI_CONFIG.SHOP_PADDING, 0, 55)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = UI_CONFIG.ACCENT_COLOR
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0) -- Will be set dynamically
	scrollFrame.Parent = shopPanel
	
	-- Layout for items
	local listLayout = Instance.new("UIListLayout")
	listLayout.Name = "Layout"
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, UI_CONFIG.BUTTON_SPACING)
	listLayout.Parent = scrollFrame
	
	-- Auto-resize canvas
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
	end)
	
	return screenGui
end

local function createShopButton(unitName: string, config: any, layoutOrder: number, isLocked: boolean): Frame
	local button = Instance.new("Frame")
	button.Name = unitName
	button.Size = UDim2.new(1, 0, 0, UI_CONFIG.BUTTON_HEIGHT)
	button.BackgroundColor3 = isLocked and UI_CONFIG.LOCKED_COLOR or UI_CONFIG.BUTTON_COLOR
	button.BorderSizePixel = 0
	button.LayoutOrder = layoutOrder
	addCorner(button, 8)
	
	-- Clickable button overlay (only if not locked)
	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickArea"
	clickButton.Size = UDim2.new(1, 0, 1, 0)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.Active = not isLocked
	clickButton.Parent = button
	
	-- Left side: Icon/emoji placeholder
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(0, 50, 0, 50)
	iconLabel.Position = UDim2.new(0, 10, 0.5, -25)
	iconLabel.BackgroundColor3 = isLocked and UI_CONFIG.LOCKED_COLOR or UI_CONFIG.BACKGROUND_COLOR
	iconLabel.Text = isLocked and "🔒" or "🧠"
	iconLabel.TextSize = 28
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.Parent = button
	
	-- Unit name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "UnitName"
	nameLabel.Size = UDim2.new(1, -130, 0, 24)
	nameLabel.Position = UDim2.new(0, 70, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = isLocked and "???" or unitName
	nameLabel.TextColor3 = isLocked and UI_CONFIG.LOCKED_TEXT_COLOR or UI_CONFIG.TEXT_COLOR
	nameLabel.TextSize = 16
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = button
	
	-- Owned count badge (only for unlocked)
	local ownedBadge = Instance.new("TextLabel")
	ownedBadge.Name = "OwnedBadge"
	ownedBadge.Size = UDim2.new(0, 40, 0, 22)
	ownedBadge.Position = UDim2.new(1, -50, 0, 8)
	ownedBadge.BackgroundColor3 = isLocked and UI_CONFIG.LOCKED_COLOR or UI_CONFIG.ACCENT_COLOR
	ownedBadge.Text = isLocked and "🔒" or "0"
	ownedBadge.TextColor3 = isLocked and UI_CONFIG.LOCKED_TEXT_COLOR or Color3.fromRGB(0, 0, 0)
	ownedBadge.TextSize = 14
	ownedBadge.Font = Enum.Font.GothamBold
	ownedBadge.Parent = button
	addCorner(ownedBadge, 6)
	
	-- Income info or locked message
	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "Income"
	incomeLabel.Size = UDim2.new(1, -80, 0, 18)
	incomeLabel.Position = UDim2.new(0, 70, 0, 32)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Text = isLocked and "Purchase units to unlock!" or string.format("+$%d every %ds", config.BaseIncome, config.CycleTime)
	incomeLabel.TextColor3 = isLocked and UI_CONFIG.LOCKED_TEXT_COLOR or UI_CONFIG.SECONDARY_TEXT_COLOR
	incomeLabel.TextSize = 12
	incomeLabel.Font = Enum.Font.Gotham
	incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
	incomeLabel.Parent = button
	
	-- Milestone progress label (only for unlocked)
	local milestoneLabel = Instance.new("TextLabel")
	milestoneLabel.Name = "MilestoneProgress"
	milestoneLabel.Size = UDim2.new(1, -80, 0, 16)
	milestoneLabel.Position = UDim2.new(0, 70, 0, 50)
	milestoneLabel.BackgroundTransparency = 1
	milestoneLabel.Text = isLocked and "" or "0/10 to x2 Speed"
	milestoneLabel.TextColor3 = isLocked and UI_CONFIG.LOCKED_TEXT_COLOR or Color3.fromRGB(150, 200, 255)
	milestoneLabel.TextSize = 11
	milestoneLabel.Font = Enum.Font.GothamBold
	milestoneLabel.TextXAlignment = Enum.TextXAlignment.Left
	milestoneLabel.Parent = button
	
	-- Price display
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.Size = UDim2.new(1, -80, 0, 24)
	priceLabel.Position = UDim2.new(0, 70, 1, -48)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = isLocked and "LOCKED" or formatMoney(config.BasePrice)
	priceLabel.TextColor3 = isLocked and UI_CONFIG.LOCKED_TEXT_COLOR or UI_CONFIG.PRICE_COLOR
	priceLabel.TextSize = 18
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.Parent = button
	
	-- Item cost display (shows required items for high-tier units)
	local itemCostLabel = Instance.new("TextLabel")
	itemCostLabel.Name = "ItemCost"
	itemCostLabel.Size = UDim2.new(1, -80, 0, 16)
	itemCostLabel.Position = UDim2.new(0, 70, 1, -22)
	itemCostLabel.BackgroundTransparency = 1
	itemCostLabel.Text = ""
	itemCostLabel.TextColor3 = UI_CONFIG.ITEM_COST_COLOR
	itemCostLabel.TextSize = 11
	itemCostLabel.Font = Enum.Font.Gotham
	itemCostLabel.TextXAlignment = Enum.TextXAlignment.Left
	itemCostLabel.TextTruncate = Enum.TextTruncate.AtEnd
	itemCostLabel.Visible = false
	itemCostLabel.Parent = button
	
	-- Populate item cost text if unit has item requirements
	if not isLocked then
		local itemCost = ShopConfig.GetItemCost(unitName)
		if itemCost then
			local parts = {}
			for itemId, qty in pairs(itemCost) do
				table.insert(parts, qty .. "x " .. itemId)
			end
			itemCostLabel.Text = "📦 " .. table.concat(parts, " + ")
			itemCostLabel.Visible = true
		end
	end
	
	-- Buy indicator (only for unlocked)
	local buyIndicator = Instance.new("TextLabel")
	buyIndicator.Name = "BuyIndicator"
	buyIndicator.Size = UDim2.new(0, 80, 0, 30) -- Wider for text
	buyIndicator.Position = UDim2.new(1, -90, 1, -38)
	buyIndicator.BackgroundTransparency = 1
	local ownedCount = config.count or 0
	local buttonText = "BUY"
	if ownedCount > 0 then
		buttonText = "UPGRADE"
	end
	
	buyIndicator.Text = isLocked and "" or buttonText
	buyIndicator.TextColor3 = UI_CONFIG.ACCENT_COLOR
	buyIndicator.TextSize = 14
	buyIndicator.Font = Enum.Font.GothamBold
	buyIndicator.Parent = button
	
	-- Locked overlay effect
	if isLocked then
		local overlay = Instance.new("Frame")
		overlay.Name = "LockedOverlay"
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundColor3 = UI_CONFIG.LOCKED_OVERLAY_COLOR
		overlay.BackgroundTransparency = 0.5
		overlay.ZIndex = 2
		overlay.Parent = button
		addCorner(overlay, 8)
	end
	
	return button
end

--------------------------------------------------------------------------------
-- UI LOGIC
--------------------------------------------------------------------------------

local function updateButtonPrice(unitName: string, newCount: number)
	local button = ShopButtons[unitName]
	if not button then return end
	
	local config = ShopConfig.GetConfig(unitName)
	if not config then return end
	
	local newPrice = ShopConfig.CalculatePrice(unitName, newCount)
	
	-- Update price label
	local priceLabel = button:FindFirstChild("Price")
	if priceLabel then
		priceLabel.Text = formatMoney(newPrice)
	end
	
	-- Update owned badge
	local ownedBadge = button:FindFirstChild("OwnedBadge")
	if ownedBadge then
		ownedBadge.Text = tostring(newCount)
	end
	
	-- Update income display with milestone bonuses
	local incomeLabel = button:FindFirstChild("Income")
	if incomeLabel then
		local effectiveIncome = ShopConfig.CalculateEffectiveIncome(unitName, newCount)
		local effectiveCycleTime = ShopConfig.CalculateEffectiveCycleTime(unitName, newCount)
		incomeLabel.Text = string.format("+$%d every %.1fs", effectiveIncome, effectiveCycleTime)
	end
	
	-- Update milestone progress
	local milestoneLabel = button:FindFirstChild("MilestoneProgress")
	if milestoneLabel then
		local nextMilestone, currentProgress = ShopConfig.GetNextMilestone(newCount)
		if nextMilestone then
			local bonusType = nextMilestone.milestoneType == "speed" and "x2 Speed ⚡" or string.format("x%d Profit 💰", nextMilestone.multiplier)
			milestoneLabel.Text = string.format("%d/%d to %s", currentProgress, nextMilestone.quantity, bonusType)
			milestoneLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
		else
			milestoneLabel.Text = "✅ All milestones reached!"
			milestoneLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
		end
	end
	
	-- Update item cost display
	local itemCostLabel = button:FindFirstChild("ItemCost")
	if itemCostLabel then
		local itemCost = ShopConfig.GetItemCost(unitName)
		if itemCost then
			local parts = {}
			for itemId, qty in pairs(itemCost) do
				table.insert(parts, qty .. "x " .. itemId)
			end
			itemCostLabel.Text = "📦 " .. table.concat(parts, " + ")
			itemCostLabel.Visible = true
		else
			itemCostLabel.Visible = false
		end
	end
	
	OwnedCounts[unitName] = newCount
end

local function canAfford(unitName: string): boolean
	local leaderstats = Player:FindFirstChild("leaderstats")
	if not leaderstats then return false end
	
	local money = leaderstats:FindFirstChild("Money")
	if not money then return false end
	
	local count = OwnedCounts[unitName] or 0
	local price = ShopConfig.CalculatePrice(unitName, count)
	
	return money.Value >= price
end

local function updateButtonAffordability()
	for unitName, button in ShopButtons do
		-- Skip locked buttons (they don't have proper styling)
		local overlay = button:FindFirstChild("LockedOverlay")
		if overlay then continue end
		
		local affordable = canAfford(unitName)
		button.BackgroundColor3 = affordable and UI_CONFIG.BUTTON_COLOR or UI_CONFIG.BUTTON_DISABLED_COLOR
		
		local buyIndicator = button:FindFirstChild("BuyIndicator")
		if buyIndicator then
			buyIndicator.TextTransparency = affordable and 0 or 0.7
		end
	end
end

local function animatePurchase(button: Frame, success: boolean)
	if success then
		-- Success animation - quick scale pop
		local originalSize = button.Size
		
		local popTween = TweenService:Create(button, TweenInfo.new(0.1), {
			Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset + 6, originalSize.Y.Scale, originalSize.Y.Offset + 4)
		})
		
		local returnTween = TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Elastic), {
			Size = originalSize
		})
		
		popTween:Play()
		popTween.Completed:Connect(function()
			returnTween:Play()
		end)
		
		-- Flash green
		local originalColor = button.BackgroundColor3
		button.BackgroundColor3 = UI_CONFIG.ACCENT_COLOR
		task.delay(0.1, function()
			TweenService:Create(button, TweenInfo.new(0.2), {BackgroundColor3 = originalColor}):Play()
		end)
		
		ChachingSound:Play()
	else
		-- Shake animation for failure
		local originalPos = button.Position
		
		for i = 1, 3 do
			local offset = i % 2 == 0 and 5 or -5
			TweenService:Create(button, TweenInfo.new(0.05), {
				Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset + offset, originalPos.Y.Scale, originalPos.Y.Offset)
			}):Play()
			task.wait(0.05)
		end
		
		button.Position = originalPos
		ErrorSound:Play()
	end
end

local function setupButtonClick(button: Frame, unitName: string)
	local clickArea = button:FindFirstChild("ClickArea")
	if not clickArea then return end
	
	local debounce = false
	
	-- Hover effects
	clickArea.MouseEnter:Connect(function()
		if canAfford(unitName) then
			TweenService:Create(button, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
				BackgroundColor3 = UI_CONFIG.BUTTON_HOVER_COLOR
			}):Play()
		end
	end)
	
	clickArea.MouseLeave:Connect(function()
		local targetColor = canAfford(unitName) and UI_CONFIG.BUTTON_COLOR or UI_CONFIG.BUTTON_DISABLED_COLOR
		TweenService:Create(button, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
			BackgroundColor3 = targetColor
		}):Play()
	end)
	
	-- Click to buy
	clickArea.MouseButton1Click:Connect(function()
		if debounce then return end
		
		-- REMOVED: Main island check - players can buy from anywhere
		-- Selling still requires visiting the Market on Main Island
		
		debounce = true
		
		local success, message = BuyUnitRemote:InvokeServer(unitName)
		animatePurchase(button, success)
		
		if not success then
			warn("Purchase failed: " .. tostring(message))
		end
		
		task.wait(0.3)
		debounce = false
	end)
end

--[[
	Refreshes the shop UI to show visible units based on unlock progress.
]]
local function refreshShopUI()
	if not ScrollFrame then return end
	
	-- Clear existing buttons
	for _, child in ScrollFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	ShopButtons = {}
	
	-- Get visible units based on unlock progress
	local visibleUnits = ShopConfig.GetVisibleUnits(UnlockProgress)
	
	for i, unitData in visibleUnits do
		local unitName = unitData.name
		local config = unitData.config
		local isLocked = unitData.isLocked
		
		-- Create button
		local button = createShopButton(unitName, config, i, isLocked)
		button.Parent = ScrollFrame
		
		if not isLocked then
			ShopButtons[unitName] = button
			
			-- Update with actual owned count and price
			local count = OwnedCounts[unitName] or 0
			updateButtonPrice(unitName, count)
			
			-- Setup click handler
			setupButtonClick(button, unitName)
		end
	end
	
	-- Update affordability
	updateButtonAffordability()
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("ShopUI: Initializing...")
	
	-- Create the shop GUI
	ShopGui = createShopGui()
	if not ShopGui then return end
	local shopPanel = ShopGui:FindFirstChild("ShopPanel")
	ScrollFrame = shopPanel and shopPanel:FindFirstChild("ItemList")
	
	-- Get initial ownership data from server
	local ownershipData = GetOwnershipRemote:InvokeServer()
	
	-- Set unlock progress
	if ownershipData and ownershipData.unlockProgress then
		UnlockProgress = ownershipData.unlockProgress
	end
	
	-- Initialize owned counts
	if ownershipData and ownershipData.units then
		for unitName, data in ownershipData.units do
			OwnedCounts[unitName] = data.count
		end
	end
	
	-- Build initial shop UI
	refreshShopUI()
	
	-- Parent GUI
	ShopGui.Parent = PlayerGui
	
	-- Listen for ownership updates from server
	OwnershipChangedEvent.OnClientEvent:Connect(function(unitName: string, newCount: number, newPrice: number)
		OwnedCounts[unitName] = newCount
		updateButtonPrice(unitName, newCount)
		updateButtonAffordability()
	end)
	
	-- Listen for unlock progress updates
	UnlockProgressChangedEvent.OnClientEvent:Connect(function(newProgress: number)
		print(string.format("ShopUI: Unlock progress updated to %d", newProgress))
		UnlockProgress = newProgress
		refreshShopUI()
	end)
	
	-- Update affordability when money changes
	local leaderstats = Player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local money = leaderstats:WaitForChild("Money", 5)
		if money then
			money:GetPropertyChangedSignal("Value"):Connect(updateButtonAffordability)
			updateButtonAffordability() -- Initial update
		end
	end
	
	print(string.format("ShopUI: Ready! (%d units unlocked, %d total)", UnlockProgress, ShopConfig.GetTotalUnits()))
end

-- Start
initialize()

--------------------------------------------------------------------------------
-- SHOP VISIBILITY (Controlled by B key, HUD button, or ProximityPrompt)
--------------------------------------------------------------------------------

local ShopVisible = false
local SHOP_OPEN_POSITION = UDim2.new(1, -UI_CONFIG.SHOP_WIDTH - 10, 0, 10)
local SHOP_CLOSED_POSITION = UDim2.new(1, 10, 0, 10)

--[[
	Updates the warning banner visibility based on main island status.
]]
local function updateWarningBanner()
	if not ShopGui then return end
	local shopPanel = ShopGui:FindFirstChild("ShopPanel")
	if not shopPanel then return end
	
	local warningBanner = shopPanel:FindFirstChild("WarningBanner")
	if warningBanner then
		warningBanner.Visible = not IsOnMainIsland
	end
end

local function openShop()
	if ShopVisible then return end
	if not ShopGui then return end
	local shopPanel = ShopGui:FindFirstChild("ShopPanel")
	if not shopPanel then return end
	
	ShopVisible = true
	updateWarningBanner()
	TweenService:Create(shopPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = SHOP_OPEN_POSITION
	}):Play()
	print("ShopUI: Opened")
end

local function closeShop()
	if not ShopVisible then return end
	if not ShopGui then return end
	local shopPanel = ShopGui:FindFirstChild("ShopPanel")
	if not shopPanel then return end
	
	ShopVisible = false
	TweenService:Create(shopPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = SHOP_CLOSED_POSITION
	}):Play()
	print("ShopUI: Closed")
end

local function toggleShop()
	if ShopVisible then
		closeShop()
	else
		openShop()
	end
end

-- Setup ProximityPrompt listener for ShopVendor on Main Island
local function setupShopVendorPrompt()
	local mainIsland = workspace:WaitForChild("MainIsland", 30)
	if not mainIsland then
		warn("ShopUI: MainIsland not found")
		return
	end
	
	-- Wait for or create ShopVendor
	local shopVendor = mainIsland:FindFirstChild("ShopVendor")
	if not shopVendor then
		-- Create ShopVendor part if it doesn't exist
		shopVendor = Instance.new("Part")
		shopVendor.Name = "ShopVendor"
		shopVendor.Size = Vector3.new(6, 8, 6)
		shopVendor.BrickColor = BrickColor.new("Bright violet")
		shopVendor.Material = Enum.Material.Neon
		shopVendor.Anchored = true
		shopVendor.CanCollide = true
		-- Position on main island (adjust as needed)
		local primaryPart = mainIsland.PrimaryPart or mainIsland:FindFirstChildWhichIsA("BasePart")
		if primaryPart then
			shopVendor.Position = primaryPart.Position + Vector3.new(20, 10, 0)
		else
			-- Fallback: main island is at height 30, so position at 40
			shopVendor.Position = Vector3.new(20, 40, 0)
		end
		shopVendor.Parent = mainIsland
		
		-- Add visual label
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.new(4, 0, 2, 0)
		billboard.StudsOffset = Vector3.new(0, 6, 0)
		billboard.Parent = shopVendor
		
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = "🛒 SHOP"
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = billboard
	end
	
	-- Create or get ProximityPrompt
	local prompt = shopVendor:FindFirstChild("ShopPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.ActionText = "Open Shop"
		prompt.ObjectText = "Shop"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = shopVendor
	end
	
	-- Open shop when prompt triggered
	prompt.Triggered:Connect(function(playerWhoTriggered)
		if playerWhoTriggered == Player then
			openShop()
		end
	end)
	
	print("ShopUI: ShopVendor ProximityPrompt setup complete")
end

-- Track if player is on main island for purchase permissions
local function setupMainIslandCheck()
	local mainIsland = workspace:WaitForChild("MainIsland", 30)
	if not mainIsland then
		warn("ShopUI: MainIsland not found for proximity check")
		return
	end
	
	local primaryPart = mainIsland.PrimaryPart or mainIsland:FindFirstChildWhichIsA("BasePart")
	if not primaryPart then
		warn("ShopUI: MainIsland has no primary part")
		return
	end
	
	-- Get the island bounds (approximate based on size)
	local islandSize = primaryPart.Size
	local islandCenter = primaryPart.Position
	
	RunService.Heartbeat:Connect(function()
		local character = Player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		
		-- Check if player is within horizontal distance of main island
		local playerPos = hrp.Position
		local horizontalDist = math.sqrt(
			(playerPos.X - islandCenter.X)^2 + 
			(playerPos.Z - islandCenter.Z)^2
		)
		
		-- Consider player on main island if within reasonable radius (island half-size + margin)
		local islandRadius = math.max(islandSize.X, islandSize.Z) / 2 + 20
		local wasOnMainIsland = IsOnMainIsland
		IsOnMainIsland = horizontalDist <= islandRadius and playerPos.Y >= islandCenter.Y - 20
		
		-- Update warning banner if status changed while shop is open
		if wasOnMainIsland ~= IsOnMainIsland and ShopVisible then
			updateWarningBanner()
		end
	end)
end

-- Setup 'B' key to toggle shop
local function setupKeyboardToggle()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == Enum.KeyCode.B then
			toggleShop()
		end
	end)
	print("ShopUI: B key toggle enabled")
end

-- Setup close button on shop panel
local function setupCloseButton()
	if not ShopGui then return end
	local shopPanel = ShopGui:FindFirstChild("ShopPanel")
	if not shopPanel then return end
	
	local titleBar = shopPanel:FindFirstChild("TitleBar")
	if not titleBar then return end
	
	local closeButton = titleBar:FindFirstChild("CloseButton")
	if closeButton then
		closeButton.MouseButton1Click:Connect(function()
			closeShop()
		end)
		
		-- Hover effects
		closeButton.MouseEnter:Connect(function()
			TweenService:Create(closeButton, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(255, 80, 80)
			}):Play()
		end)
		
		closeButton.MouseLeave:Connect(function()
			TweenService:Create(closeButton, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(200, 60, 60)
			}):Play()
		end)
	end
end

-- Setup BindableEvent listener for MoneyHUD shop button
local function setupBindableEventListener()
	-- Wait a bit for MoneyHUD to potentially create the event
	task.wait(0.5)
	
	local shopToggleEvent = ReplicatedStorage:FindFirstChild("ShopToggleEvent")
	if not shopToggleEvent then
		-- Create it ourselves if MoneyHUD hasn't yet
		shopToggleEvent = Instance.new("BindableEvent")
		shopToggleEvent.Name = "ShopToggleEvent"
		shopToggleEvent.Parent = ReplicatedStorage
	end
	
	shopToggleEvent.Event:Connect(function()
		toggleShop()
	end)
	
	print("ShopUI: BindableEvent listener setup complete")
end

-- Initialize shop vendor prompt
task.spawn(setupShopVendorPrompt)
task.spawn(setupMainIslandCheck)
task.spawn(setupCloseButton)
task.spawn(setupBindableEventListener)
setupKeyboardToggle()
