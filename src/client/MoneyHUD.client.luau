--[[
	MoneyHUD LocalScript
	
	Displays the player's current money and money per second in a simple HUD.
	Located in the top-left area of the screen.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Player reference
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Wait for shared modules and remotes
local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopConfig"))
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local GetOwnershipRemote = RemoteEvents:WaitForChild("GetOwnership")
local OwnershipChangedEvent = RemoteEvents:WaitForChild("OwnershipChanged")

-- Brainrots folder for preview
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")

--------------------------------------------------------------------------------
-- UI CONFIGURATION
--------------------------------------------------------------------------------

local UI_CONFIG = {
	-- Panel positioning and size
	PANEL_WIDTH = 220,
	PANEL_HEIGHT = 290,  -- Increased for new buttons
	PANEL_MARGIN = 20,
	CORNER_RADIUS = 16,
	
	-- Colors
	BACKGROUND_COLOR = Color3.fromRGB(20, 20, 30),
	STROKE_COLOR = Color3.fromRGB(50, 50, 70),
	MONEY_COLOR = Color3.fromRGB(100, 255, 100),
	MPS_COLOR = Color3.fromRGB(180, 180, 180),
	LABEL_COLOR = Color3.fromRGB(120, 120, 140),
	ITEMS_BG_COLOR = Color3.fromRGB(40, 40, 50),
	ITEMS_FILL_COLOR = Color3.fromRGB(100, 180, 255),  -- Blue for items
	ITEMS_FULL_COLOR = Color3.fromRGB(255, 100, 100),
	
	-- Animation
	TWEEN_TIME = 0.2,
	
	-- Theme (Modern Dark from BuildMode)
	THEME_BG = Color3.fromRGB(20, 20, 30),
	THEME_STROKE = Color3.fromRGB(50, 50, 70),
	THEME_ACCENT_PURPLE = Color3.fromRGB(80, 60, 140),
	THEME_ACCENT_PINK = Color3.fromRGB(140, 80, 160),
	THEME_ACCENT_GOLD = Color3.fromRGB(200, 150, 60),
	THEME_ACCENT_BLUE = Color3.fromRGB(60, 120, 200),
	THEME_TEXT_PRIMARY = Color3.fromRGB(255, 255, 255),
	THEME_TEXT_SECONDARY = Color3.fromRGB(180, 180, 180),
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function formatMoney(amount: number): string
	if amount >= 1000000000 then
		return string.format("$%.2fB", amount / 1000000000)
	elseif amount >= 1000000 then
		return string.format("$%.2fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("$%.1fK", amount / 1000)
	else
		return "$" .. tostring(math.floor(amount))
	end
end

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
	stroke.Transparency = 0.5
	stroke.Parent = parent
	return stroke
end

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createMoneyHUD(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MoneyHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	-- Main HUD panel
	local hudPanel = Instance.new("Frame")
	hudPanel.Name = "HUDPanel"
	hudPanel.Size = UDim2.new(0, UI_CONFIG.PANEL_WIDTH, 0, 260) -- Adjusted height
	hudPanel.Position = UDim2.new(1, -UI_CONFIG.PANEL_WIDTH - UI_CONFIG.PANEL_MARGIN, 0, 60) -- Lowered slightly
	hudPanel.BackgroundColor3 = UI_CONFIG.THEME_BG
	hudPanel.BackgroundTransparency = 0.1
	hudPanel.BorderSizePixel = 0
	hudPanel.Parent = screenGui
	addCorner(hudPanel, UI_CONFIG.CORNER_RADIUS)
	addStroke(hudPanel, UI_CONFIG.THEME_STROKE, 2)
	
	-- Add padding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.Parent = hudPanel
	
	-- Money icon and label container
	local moneyContainer = Instance.new("Frame")
	moneyContainer.Name = "MoneyContainer"
	moneyContainer.Size = UDim2.new(1, 0, 0, 32)
	moneyContainer.Position = UDim2.new(0, 0, 0, 0)
	moneyContainer.BackgroundTransparency = 1
	moneyContainer.Parent = hudPanel
	
	-- Money icon
	local moneyIcon = Instance.new("TextLabel")
	moneyIcon.Name = "MoneyIcon"
	moneyIcon.Size = UDim2.new(0, 32, 0, 32)
	moneyIcon.Position = UDim2.new(0, 0, 0, 0)
	moneyIcon.BackgroundTransparency = 1
	moneyIcon.Text = "💰"
	moneyIcon.TextSize = 24
	moneyIcon.Font = Enum.Font.GothamBold
	moneyIcon.Parent = moneyContainer
	
	-- Money value label
	local moneyLabel = Instance.new("TextLabel")
	moneyLabel.Name = "MoneyLabel"
	moneyLabel.Size = UDim2.new(1, -40, 0, 32)
	moneyLabel.Position = UDim2.new(0, 40, 0, 0)
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.Text = "$0"
	moneyLabel.TextColor3 = UI_CONFIG.MONEY_COLOR
	moneyLabel.TextSize = 28
	moneyLabel.Font = Enum.Font.GothamBold
	moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
	moneyLabel.Parent = moneyContainer
	
	-- Money per second
	local mpsLabel = Instance.new("TextLabel")
	mpsLabel.Name = "MPSLabel"
	mpsLabel.Size = UDim2.new(1, 0, 0, 18)
	mpsLabel.Position = UDim2.new(0, 40, 0, 32)
	mpsLabel.BackgroundTransparency = 1
	mpsLabel.Text = "+$0/s"
	mpsLabel.TextColor3 = UI_CONFIG.MPS_COLOR
	mpsLabel.TextSize = 14
	mpsLabel.Font = Enum.Font.Gotham
	mpsLabel.TextXAlignment = Enum.TextXAlignment.Left
	mpsLabel.Parent = hudPanel
	
	-- Separator
	local div = Instance.new("Frame")
	div.Name = "Divider"
	div.Size = UDim2.new(0, 2, 0, 40)
	div.Position = UDim2.new(0, 0, 0, 60)
	div.BackgroundColor3 = UI_CONFIG.THEME_ACCENT_BLUE
	div.BorderSizePixel = 0
	div.Parent = hudPanel
	addCorner(div, 2)
	
	-- Storage Section
	local storageContainer = Instance.new("Frame")
	storageContainer.Name = "ItemsContainer" -- Kept Name for script compatibility
	storageContainer.Size = UDim2.new(1, -20, 0, 50)
	storageContainer.Position = UDim2.new(0, 15, 0, 60)
	storageContainer.BackgroundTransparency = 1
	storageContainer.Parent = hudPanel
	
	local storageTitle = Instance.new("TextLabel")
	storageTitle.Name = "Title"
	storageTitle.Size = UDim2.new(1, 0, 0, 20)
	storageTitle.BackgroundTransparency = 1
	storageTitle.Text = "📦 ITEMS: 0 / 2000" -- Initial text
	storageTitle.Name = "ItemsAmount" -- Kept Name for script compatibility
	storageTitle.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
	storageTitle.TextSize = 12
	storageTitle.Font = Enum.Font.GothamBold
	storageTitle.TextXAlignment = Enum.TextXAlignment.Left
	storageTitle.Parent = storageContainer
	
	local itemsBarBg = Instance.new("Frame")
	itemsBarBg.Name = "ItemsBarBg"
	itemsBarBg.Size = UDim2.new(1, 0, 0, 12)
	itemsBarBg.Position = UDim2.new(0, 0, 0, 25)
	itemsBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	itemsBarBg.BorderSizePixel = 0
	itemsBarBg.Parent = storageContainer
	addCorner(itemsBarBg, 4)
	
	local itemsBarFill = Instance.new("Frame")
	itemsBarFill.Name = "ItemsBarFill"
	itemsBarFill.Size = UDim2.new(0, 0, 1, 0)
	itemsBarFill.BackgroundColor3 = UI_CONFIG.THEME_ACCENT_BLUE
	itemsBarFill.BorderSizePixel = 0
	itemsBarFill.Parent = itemsBarBg
	addCorner(itemsBarFill, 4)
	
	-- Action Icons Container
	local actionsFrame = Instance.new("Frame")
	actionsFrame.Name = "ActionsFrame"
	actionsFrame.Size = UDim2.new(1, 0, 0, 50)
	actionsFrame.Position = UDim2.new(0, 0, 0, 125)
	actionsFrame.BackgroundTransparency = 1
	actionsFrame.Parent = hudPanel
	
	local uiLayout = Instance.new("UIListLayout")
	uiLayout.FillDirection = Enum.FillDirection.Horizontal
	uiLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	uiLayout.SortOrder = Enum.SortOrder.LayoutOrder
	uiLayout.Padding = UDim.new(0, 15)
	uiLayout.Parent = actionsFrame
	
	-- Helper to create icon buttons
	local function createIconButton(name, textIcon, color, order)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.Size = UDim2.new(0, 48, 0, 48)
		btn.BackgroundColor3 = color
		btn.LayoutOrder = order
		btn.Text = textIcon
		btn.TextSize = 24
		btn.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
		btn.Font = Enum.Font.GothamBold
		btn.Parent = actionsFrame
		
		addCorner(btn, 12)
		addStroke(btn, UI_CONFIG.THEME_STROKE, 1.5)
		
		return btn
	end
	
	-- 1. Shop Button
	createIconButton("ShopButton", "🛒", UI_CONFIG.THEME_ACCENT_PURPLE, 1)
	
	-- 2. Brainrots Button (3D Preview)
	local brainrotsBtn = createIconButton("BrainrotsButton", "", UI_CONFIG.THEME_ACCENT_PINK, 2)
	
	-- Viewport for Brainrot
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.new(1, -6, 1, -6)
	viewport.Position = UDim2.new(0, 3, 0, 3)
	viewport.BackgroundTransparency = 1
	viewport.Parent = brainrotsBtn
	
	-- Pick random model for preview
	task.spawn(function()
		local allModels = {}
		if BrainrotsFolder then
			for _, m in BrainrotsFolder:GetChildren() do
				if m:IsA("Model") then table.insert(allModels, m) end
			end
		end
		
		if #allModels > 0 then
			local randomModel = allModels[math.random(1, #allModels)]:Clone()
			randomModel.Parent = viewport
			
			local cam = Instance.new("Camera")
			cam.Parent = viewport
			viewport.CurrentCamera = cam
			
			local cf, size = randomModel:GetBoundingBox()
			local maxDim = math.max(size.X, size.Y, size.Z)
			local dist = maxDim * 1.5
			cam.CFrame = CFrame.new(cf.Position + Vector3.new(dist, dist*0.5, dist), cf.Position)
		end
	end)
	
	-- 3. Synergies Button
	createIconButton("SynergiesButton", "📖", UI_CONFIG.THEME_ACCENT_GOLD, 3)
	
	-- 4. Backpack Button (NEW)
	createIconButton("BackpackButton", "🎒", UI_CONFIG.THEME_ACCENT_BLUE, 4)
	
	return screenGui
end

--------------------------------------------------------------------------------
-- MONEY TRACKING
--------------------------------------------------------------------------------

local MoneyHUDGui: ScreenGui
local MoneyLabel: TextLabel
local MPSLabel: TextLabel
local ItemsBarFill: Frame
local ItemsAmountLabel: TextLabel

local previousMoney: number = 0

-- Track ownership for MPS calculation
local OwnedCounts: {[string]: number} = {}

--[[
	Calculates the total money per second based on all owned units.
	Formula: Sum of (BaseIncome / CycleTime) * count for each unit
]]
local function calculateMPS(): number
	local totalMPS = 0
	
	for unitName, count in OwnedCounts do
		if count > 0 then
			local config = ShopConfig.GetConfig(unitName)
			if config then
				-- Income per second for this unit type: (BaseIncome / CycleTime) * count
				local incomePerSecond = (config.BaseIncome / config.CycleTime) * count
				totalMPS = totalMPS + incomePerSecond
			end
		end
	end
	
	return totalMPS
end

--[[
	Updates the MPS display label with the calculated value.
]]
local function updateMPSDisplay()
	if not MPSLabel then return end
	
	local mps = calculateMPS()
	
	if mps >= 1000 then
		MPSLabel.Text = string.format("+$%.1fK/s", mps / 1000)
	else
		MPSLabel.Text = string.format("+$%.1f/s", mps)
	end
end

local function updateMoneyDisplay(newMoney: number)
	if not MoneyLabel then return end
	
	local formattedMoney = formatMoney(newMoney)
	MoneyLabel.Text = formattedMoney
	
	-- Animate color flash on money change
	if newMoney > previousMoney then
		-- Money gained - flash bright green
		MoneyLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
		TweenService:Create(MoneyLabel, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
			TextColor3 = UI_CONFIG.MONEY_COLOR
		}):Play()
	elseif newMoney < previousMoney then
		-- Money spent - flash red briefly
		MoneyLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		TweenService:Create(MoneyLabel, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
			TextColor3 = UI_CONFIG.MONEY_COLOR
		}):Play()
	end
	
	previousMoney = newMoney
end

--[[
	Updates the items bar fill and text based on current item storage.
]]
local function updateItemsDisplay(currentItems: number, maxItems: number)
	if not ItemsBarFill or not ItemsAmountLabel then return end
	
	local fillPercent = math.clamp(currentItems / maxItems, 0, 1)
	
	-- Animate the fill bar width
	TweenService:Create(ItemsBarFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(fillPercent, 0, 1, 0)
	}):Play()
	
	-- Update text
	ItemsAmountLabel.Text = string.format("📦 ITEMS: %d / %d", currentItems, maxItems)
	
	-- Change color based on fill level
	local targetColor
	if fillPercent >= 1 then
		targetColor = UI_CONFIG.ITEMS_FULL_COLOR
	elseif fillPercent >= 0.75 then
		-- Interpolate between fill and full color
		targetColor = UI_CONFIG.ITEMS_FILL_COLOR:Lerp(UI_CONFIG.ITEMS_FULL_COLOR, (fillPercent - 0.75) / 0.25)
	else
		targetColor = UI_CONFIG.ITEMS_FILL_COLOR
	end
	
	TweenService:Create(ItemsBarFill, TweenInfo.new(0.2), {
		BackgroundColor3 = targetColor
	}):Play()
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("MoneyHUD: Initializing...")
	
	-- Create the HUD
	MoneyHUDGui = createMoneyHUD()
	MoneyHUDGui.Parent = PlayerGui
	
	-- Get references to labels
	local hudPanel = MoneyHUDGui:FindFirstChild("HUDPanel")
	if hudPanel then
		local moneyContainer = hudPanel:FindFirstChild("MoneyContainer")
		if moneyContainer then
			MoneyLabel = moneyContainer:FindFirstChild("MoneyLabel")
		end
		MPSLabel = hudPanel:FindFirstChild("MPSLabel")
		
		-- Get items bar references (was tank bar)
		local itemsContainer = hudPanel:FindFirstChild("ItemsContainer")
		if itemsContainer then
			ItemsAmountLabel = itemsContainer:FindFirstChild("ItemsAmount")
			local itemsBarBg = itemsContainer:FindFirstChild("ItemsBarBg")
			if itemsBarBg then
				ItemsBarFill = itemsBarBg:FindFirstChild("ItemsBarFill")
			end
		end
	end
	
	-- Get action buttons from ActionsFrame
	local actionsFrame = hudPanel and hudPanel:FindFirstChild("ActionsFrame")
	if actionsFrame then 
		local shopButton = actionsFrame:FindFirstChild("ShopButton")
		local brainrotsButton = actionsFrame:FindFirstChild("BrainrotsButton")
		local synergiesButton = actionsFrame:FindFirstChild("SynergiesButton")
		local backpackButton = actionsFrame:FindFirstChild("BackpackButton")
		
		print(string.format("MoneyHUD: Buttons found - Shop:%s, Brainrots:%s, Synergies:%s, Backpack:%s",
			tostring(shopButton~=nil), tostring(brainrotsButton~=nil), tostring(synergiesButton~=nil), tostring(backpackButton~=nil)))

		-- Setup shop button click
		if shopButton then
			-- Create or get the BindableEvent for shop toggle
			local shopToggleEvent = ReplicatedStorage:FindFirstChild("ShopToggleEvent")
			if not shopToggleEvent then
				shopToggleEvent = Instance.new("BindableEvent")
				shopToggleEvent.Name = "ShopToggleEvent"
				shopToggleEvent.Parent = ReplicatedStorage
			end
			
			shopButton.MouseButton1Click:Connect(function()
				shopToggleEvent:Fire()
			end)
			
			-- Hover effects
			shopButton.MouseEnter:Connect(function()
				TweenService:Create(shopButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(100, 80, 170),
					Size = UDim2.new(0, 56, 0, 56)
				}):Play()
			end)
			
			shopButton.MouseLeave:Connect(function()
				TweenService:Create(shopButton, TweenInfo.new(0.1), {
					BackgroundColor3 = UI_CONFIG.THEME_ACCENT_PURPLE,
					Size = UDim2.new(0, 48, 0, 48)
				}):Play()
			end)
		end
		
		-- Setup brainrots button click
		if brainrotsButton then
			-- Create or get the BindableEvent for backpack toggle (we use this now instead of InventoryToggleEvent)
			local backpackToggleEvent = ReplicatedStorage:FindFirstChild("BackpackToggleEvent")
			if not backpackToggleEvent then
				backpackToggleEvent = Instance.new("BindableEvent")
				backpackToggleEvent.Name = "BackpackToggleEvent"
				backpackToggleEvent.Parent = ReplicatedStorage
			end
			
			brainrotsButton.MouseButton1Click:Connect(function()
				-- Open Backpack filtered to Units
				backpackToggleEvent:Fire("Unit")
			end)
			
			-- Hover effects
			brainrotsButton.MouseEnter:Connect(function()
				TweenService:Create(brainrotsButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(170, 100, 190),
					Size = UDim2.new(0, 56, 0, 56)
				}):Play()
			end)
			
			brainrotsButton.MouseLeave:Connect(function()
				TweenService:Create(brainrotsButton, TweenInfo.new(0.1), {
					BackgroundColor3 = UI_CONFIG.THEME_ACCENT_PINK,
					Size = UDim2.new(0, 48, 0, 48)
				}):Play()
			end)
		end
		
		-- Setup synergies button click
		if synergiesButton then
			-- Create or get the BindableEvent for synergy toggle
			local synergyToggleEvent = ReplicatedStorage:FindFirstChild("SynergyToggleEvent")
			if not synergyToggleEvent then
				synergyToggleEvent = Instance.new("BindableEvent")
				synergyToggleEvent.Name = "SynergyToggleEvent"
				synergyToggleEvent.Parent = ReplicatedStorage
			end
			
			synergiesButton.MouseButton1Click:Connect(function()
				synergyToggleEvent:Fire()
			end)
			
			-- Hover effects
			synergiesButton.MouseEnter:Connect(function()
				TweenService:Create(synergiesButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(230, 180, 80),
					Size = UDim2.new(0, 56, 0, 56)
				}):Play()
			end)
			
			synergiesButton.MouseLeave:Connect(function()
				TweenService:Create(synergiesButton, TweenInfo.new(0.1), {
					BackgroundColor3 = UI_CONFIG.THEME_ACCENT_GOLD,
					Size = UDim2.new(0, 48, 0, 48)
				}):Play()
			end)
		end
		
		-- Setup backpack button click
		if backpackButton then
			-- Create or get the BindableEvent for backpack toggle
			local backpackToggleEvent = ReplicatedStorage:FindFirstChild("BackpackToggleEvent")
			if not backpackToggleEvent then
				backpackToggleEvent = Instance.new("BindableEvent")
				backpackToggleEvent.Name = "BackpackToggleEvent"
				backpackToggleEvent.Parent = ReplicatedStorage
			end
			
			backpackButton.MouseButton1Click:Connect(function()
				backpackToggleEvent:Fire()
			end)
			
			-- Hover effects
			backpackButton.MouseEnter:Connect(function()
				TweenService:Create(backpackButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(100, 150, 255),
					Size = UDim2.new(0, 56, 0, 56)
				}):Play()
			end)
			
			backpackButton.MouseLeave:Connect(function()
				TweenService:Create(backpackButton, TweenInfo.new(0.1), {
					BackgroundColor3 = UI_CONFIG.THEME_ACCENT_BLUE,
					Size = UDim2.new(0, 48, 0, 48)
				}):Play()
			end)
		end
	end
	
	-- Get initial ownership data from server for MPS calculation
	local ownershipData = GetOwnershipRemote:InvokeServer()
	if ownershipData and ownershipData.units then
		for unitName, data in ownershipData.units do
			OwnedCounts[unitName] = data.count
		end
		updateMPSDisplay()
	end
	
	-- Listen for ownership changes to update MPS
	OwnershipChangedEvent.OnClientEvent:Connect(function(unitName: string, newCount: number)
		OwnedCounts[unitName] = newCount
		updateMPSDisplay()
	end)
	
	-- Wait for leaderstats and connect to money changes
	local leaderstats = Player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local money = leaderstats:WaitForChild("Money", 5)
		if money then
			-- Initial update
			previousMoney = money.Value
			updateMoneyDisplay(money.Value)
			
			-- Listen for changes
			money:GetPropertyChangedSignal("Value"):Connect(function()
				updateMoneyDisplay(money.Value)
			end)
			
			print("MoneyHUD: Connected to money value")
		else
			warn("MoneyHUD: Could not find Money value")
		end
	else
		warn("MoneyHUD: Could not find leaderstats")
	end
	
	-- Listen for item storage updates (from ItemStorageManager)
	local StorageUpdatedEvent = RemoteEvents:FindFirstChild("StorageUpdated")
	if StorageUpdatedEvent then
		StorageUpdatedEvent.OnClientEvent:Connect(function(_, total, capacity)
			updateItemsDisplay(total or 0, capacity or 2000)
		end)
		-- Also fetch initial values
		local GetStorageFunction = RemoteEvents:FindFirstChild("GetStorage")
		if GetStorageFunction then
			task.spawn(function()
				local _, total, capacity = GetStorageFunction:InvokeServer()
				updateItemsDisplay(total or 0, capacity or 2000)
			end)
		end
	end

	print("MoneyHUD: Ready!")
end

-- Start
initialize()
