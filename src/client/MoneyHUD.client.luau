--[[
	MoneyHUD LocalScript (Reworked)
	
	Right-side HUD:
	  • Money + MPS display
	  • Storage bar
	  • "Your Top Holdings" from storage items
	  • "View Full Portfolio" button
	  • Bottom-center action bar with quick-access buttons
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

-- Player reference
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Wait for shared modules and remotes
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

local Utils = Shared:WaitForChild("Utils")
local UIUtils = require(Utils:WaitForChild("UIUtils"))
local FormatUtils = require(Utils:WaitForChild("FormatUtils"))
local CartController = require(script.Parent:WaitForChild("Controllers"):WaitForChild("CartController"))
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local GetOwnershipRemote = RemoteEvents:WaitForChild("GetOwnership")
local OwnershipChangedEvent = RemoteEvents:WaitForChild("OwnershipChanged")
local StorageUpdatedEvent = RemoteEvents:FindFirstChild("StorageUpdated")
local AchievementUpdatedEvent = RemoteEvents:WaitForChild("AchievementUpdated")
local GetStorageFunction = RemoteFunctions:WaitForChild("GetStorage")
local GetAchievementsSnapshotFunction = RemoteFunctions:WaitForChild("GetAchievementsSnapshot")
local SellAllFunction = RemoteFunctions:WaitForChild("SellAll")

-- Brainrots folder for preview
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")

-- Stock Market folder (for sector rates)
local StockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket")

--------------------------------------------------------------------------------
-- UI CONFIGURATION
--------------------------------------------------------------------------------

local UI_CONFIG = {
	-- Panel positioning and size
	PANEL_WIDTH = 250,
	PANEL_HEIGHT = 440,
	PANEL_MARGIN = 24,
	CORNER_RADIUS = 12,

	-- Holdings
	MAX_HOLDINGS_ROWS = 5,
	ROW_HEIGHT = 30,

	-- Colors
	BACKGROUND_COLOR = Color3.fromRGB(24, 76, 137), -- Deep blue gradient start
	BACKGROUND_TRANSPARENCY = 0.05,
	BACKGROUND_GRADIENT_END = Color3.fromRGB(132, 34, 114), -- Purple/Pink gradient end
	STROKE_COLOR = Color3.fromRGB(0, 255, 255),
	STROKE_TRANSPARENCY = 0.2,
	MONEY_COLOR = Color3.fromRGB(80, 230, 120),
	MPS_COLOR = Color3.fromRGB(160, 160, 180),
	LABEL_COLOR = Color3.fromRGB(220, 220, 240),
	ITEMS_BG_COLOR = Color3.fromRGB(25, 25, 35),
	ITEMS_FILL_COLOR = Color3.fromRGB(60, 160, 255),
	ITEMS_FULL_COLOR = Color3.fromRGB(255, 80, 80),

	-- Holdings colors
	HOLDINGS_TITLE_COLOR = Color3.fromRGB(255, 255, 255),
	HOLDINGS_NAME_COLOR = Color3.fromRGB(240, 240, 255),
	HOLDINGS_COUNT_COLOR = Color3.fromRGB(200, 200, 220),
	HOLDINGS_VALUE_COLOR = Color3.fromRGB(120, 240, 150),
	ARROW_UP_COLOR = Color3.fromRGB(60, 200, 100),
	ARROW_DOWN_COLOR = Color3.fromRGB(250, 70, 70),

	-- Animation
	TWEEN_TIME = 0.3,

	-- Theme
	THEME_BG = Color3.fromRGB(255, 255, 255),
	THEME_STROKE = Color3.fromRGB(255, 255, 255),
	THEME_ACCENT_PURPLE = Color3.fromRGB(120, 80, 220),
	THEME_ACCENT_PINK = Color3.fromRGB(220, 90, 180),
	THEME_ACCENT_GOLD = Color3.fromRGB(250, 190, 60),
	THEME_ACCENT_BLUE = Color3.fromRGB(60, 150, 255),
	THEME_TEXT_PRIMARY = Color3.fromRGB(255, 255, 255),
	THEME_TEXT_SECONDARY = Color3.fromRGB(220, 220, 240),

	-- Bottom bar
	BOTTOM_BAR_BREAKPOINT = 700,
	BOTTOM_BAR_WIDE_BUTTON_WIDTH = 90,
	BOTTOM_BAR_WIDE_BUTTON_HEIGHT = 40,
	BOTTOM_BAR_WIDE_SPACING = 10,
	BOTTOM_BAR_WIDE_PADDING_X = 12,
	BOTTOM_BAR_WIDE_PADDING_Y = 10,
	BOTTOM_BAR_WIDE_BOTTOM_MARGIN = 24,
	BOTTOM_BAR_MOBILE_BUTTON_WIDTH = 88,
	BOTTOM_BAR_MOBILE_BUTTON_HEIGHT = 46,
	BOTTOM_BAR_MOBILE_SPACING = 8,
	BOTTOM_BAR_MOBILE_PADDING = 10,
	BOTTOM_BAR_MOBILE_BOTTOM_MARGIN = 34,
	BOTTOM_BAR_BUTTON_BG = Color3.fromRGB(15, 20, 35),
	BOTTOM_BAR_BUTTON_BG_HOVER = Color3.fromRGB(25, 35, 55),
	BOTTOM_BAR_BUTTON_TRANSPARENCY = 0.2,
	BOTTOM_BAR_CHIP_BG = Color3.fromRGB(20, 25, 45),
}

local BOTTOM_BAR_ACTIONS = {
	{
		name = "BuildButton",
		iconLetter = "B",
		label = "Build",
		accentColor = Color3.fromRGB(125, 249, 255), -- Pastel/Electric Blue
		hoverColor = Color3.fromRGB(160, 255, 255),
		eventName = "BuildModeToggleEvent",
		filterArg = nil,
		layoutOrder = 1,
		mobileLayoutOrder = 1,
	},
	{
		name = "BackpackButton",
		iconLetter = "I",
		label = "Items",
		accentColor = Color3.fromRGB(200, 150, 255), -- Pastel Purple
		hoverColor = Color3.fromRGB(220, 180, 255),
		eventName = "BackpackToggleEvent",
		filterArg = "Storage",
		layoutOrder = 2,
		mobileLayoutOrder = 2,
	},
	{
		name = "StockButton",
		iconLetter = "S",
		label = "Sell",
		accentColor = Color3.fromRGB(152, 255, 152), -- Pastel Mint
		hoverColor = Color3.fromRGB(180, 255, 180),
		eventName = "StockToggleEvent",
		filterArg = nil,
		layoutOrder = 3,
		mobileLayoutOrder = 3,
	},
	{
		name = "SynergyButton",
		iconLetter = "Y",
		label = "Synergy",
		accentColor = Color3.fromRGB(255, 180, 200), -- Pastel Pink
		hoverColor = Color3.fromRGB(255, 200, 220),
		eventName = "SynergyToggleEvent",
		filterArg = nil,
		layoutOrder = 4,
		mobileLayoutOrder = 5,
	},
	{
		name = "AchievementsButton",
		iconLetter = "A",
		label = "Goals",
		accentColor = Color3.fromRGB(255, 220, 120), -- Pastel Gold/Yellow
		hoverColor = Color3.fromRGB(255, 235, 150),
		eventName = "AchievementsToggleEvent",
		filterArg = nil,
		layoutOrder = 5,
		mobileLayoutOrder = 6,
	},
}

local BOTTOM_BAR_ACTIONS_BY_NAME = {}
for _, action in ipairs(BOTTOM_BAR_ACTIONS) do
	BOTTOM_BAR_ACTIONS_BY_NAME[action.name] = action
end

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------



-- Get current sector rates from StockMarket folder
local function getSectorRates(): { [string]: number }
	local rates = {}
	if not StockMarketFolder then
		StockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket")
	end
	if StockMarketFolder then
		local ratesStr = StockMarketFolder:GetAttribute("SectorRates")
		if ratesStr then
			local ok, parsed = pcall(function()
				return HttpService:JSONDecode(ratesStr)
			end)
			if ok and parsed then
				rates = parsed
			end
		end
	end
	return rates
end

local function getLocalItemRates(): { [string]: number }
	local rates = {}
	if not StockMarketFolder then
		StockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket")
	end
	if StockMarketFolder then
		local ratesStr = StockMarketFolder:GetAttribute("LocalItemRates")
		if ratesStr then
			local ok, parsed = pcall(function()
				return HttpService:JSONDecode(ratesStr)
			end)
			if ok and parsed then
				rates = parsed
			end
		end
	end
	return rates
end

local function formatUnitShortName(unitName: string): string
	local formatted = tostring(unitName or ""):gsub("_", " ")
	if #formatted > 16 then
		return string.sub(formatted, 1, 15) .. "."
	end
	return formatted
end

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local StorageItems: { [string]: number } = {} -- Current storage item map
local IsBuildOpen = false
local IsShopOpen = false
local MoneyHUDGui: ScreenGui
local BottomBarButtons: { [string]: TextButton } = {}
local BottomBarViewportConnection: RBXScriptConnection? = nil
local BottomBarCameraConnection: RBXScriptConnection? = nil
local LatestAchievementSnapshot = {
	Definitions = {},
	State = {
		Progress = {},
		Unlocked = {},
		Claimed = {},
	},
}

local function ensureToggleEvent(eventName: string): BindableEvent
	local existing = ReplicatedStorage:FindFirstChild(eventName)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end

	local toggleEvent = Instance.new("BindableEvent")
	toggleEvent.Name = eventName
	toggleEvent.Parent = ReplicatedStorage
	return toggleEvent
end

local function isTutorialComplete(): boolean
	return Player:GetAttribute("TutorialComplete") == true
end

local function isTerminalIntroComplete(): boolean
	return Player:GetAttribute("TerminalIntroComplete") == true
end

local function isFirstSynergyActivated(): boolean
	return Player:GetAttribute("FirstSynergyActivated") == true
end

local function isFirstArtifactFound(): boolean
	return Player:GetAttribute("FirstArtifactFound") == true
end

local function isFirstArtifactEquipped(): boolean
	return Player:GetAttribute("FirstArtifactEquipped") == true
end

local function getVisibleBottomBarActions()
	local actions = {
		BOTTOM_BAR_ACTIONS_BY_NAME.BuildButton,
	}

	if Player:GetAttribute("ManualLogisticsUnlocked") == true then
		table.insert(actions, BOTTOM_BAR_ACTIONS_BY_NAME.BackpackButton)
	end

	table.insert(actions, BOTTOM_BAR_ACTIONS_BY_NAME.StockButton)

	if Player:GetAttribute("SynergyUnlocked") == true then
		table.insert(actions, BOTTOM_BAR_ACTIONS_BY_NAME.SynergyButton)
	end

	table.insert(actions, BOTTOM_BAR_ACTIONS_BY_NAME.AchievementsButton)
	return actions
end

local function isBottomBarActionVisible(actionName: string): boolean
	for _, action in ipairs(getVisibleBottomBarActions()) do
		if action and action.name == actionName then
			return true
		end
	end
	return false
end

local function getButtonPresentation(config)
	local label = config.label
	local iconLetter = config.iconLetter

	if config.name == "StockButton" then
		if Player:GetAttribute("DetailedMarketUnlocked") == true then
			label = "Market"
			iconLetter = "M"
		else
			label = "Sell"
			iconLetter = "$"
		end
	elseif config.name == "AchievementsButton" then
		label = "Goals"
		iconLetter = "A"
	end

	return label, iconLetter
end

local function getBottomBarMetrics(viewportWidth: number)
	local visibleCount = math.max(#getVisibleBottomBarActions(), 1)
	local isMobile = viewportWidth < UI_CONFIG.BOTTOM_BAR_BREAKPOINT
	if isMobile then
		local buttonWidth = UI_CONFIG.BOTTOM_BAR_MOBILE_BUTTON_WIDTH
		local buttonHeight = UI_CONFIG.BOTTOM_BAR_MOBILE_BUTTON_HEIGHT
		local spacing = UI_CONFIG.BOTTOM_BAR_MOBILE_SPACING
		local padding = UI_CONFIG.BOTTOM_BAR_MOBILE_PADDING
		local columns = math.min(3, visibleCount)
		local rows = math.max(1, math.ceil(visibleCount / 3))
		local barWidth = (buttonWidth * columns) + (spacing * math.max(0, columns - 1)) + (padding * 2)
		local barHeight = (buttonHeight * rows) + (spacing * math.max(0, rows - 1)) + (padding * 2)
		return {
			isMobile = true,
			buttonWidth = buttonWidth,
			buttonHeight = buttonHeight,
			spacing = spacing,
			paddingX = padding,
			paddingY = padding,
			barWidth = barWidth,
			barHeight = barHeight,
			bottomMargin = UI_CONFIG.BOTTOM_BAR_MOBILE_BOTTOM_MARGIN,
		}
	end

	local buttonWidth = UI_CONFIG.BOTTOM_BAR_WIDE_BUTTON_WIDTH
	local buttonHeight = UI_CONFIG.BOTTOM_BAR_WIDE_BUTTON_HEIGHT
	local spacing = UI_CONFIG.BOTTOM_BAR_WIDE_SPACING
	local paddingX = UI_CONFIG.BOTTOM_BAR_WIDE_PADDING_X
	local paddingY = UI_CONFIG.BOTTOM_BAR_WIDE_PADDING_Y
	local barWidth = (buttonWidth * visibleCount) + (spacing * math.max(0, visibleCount - 1)) + (paddingX * 2)
	local barHeight = buttonHeight + (paddingY * 2)
	return {
		isMobile = false,
		buttonWidth = buttonWidth,
		buttonHeight = buttonHeight,
		spacing = spacing,
		paddingX = paddingX,
		paddingY = paddingY,
		barWidth = barWidth,
		barHeight = barHeight,
		bottomMargin = UI_CONFIG.BOTTOM_BAR_WIDE_BOTTOM_MARGIN,
	}
end

local function getBottomBarViewportWidth(): number
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize.X
	end
	return UI_CONFIG.BOTTOM_BAR_BREAKPOINT
end

local function tweenBarButtonVisual(btn: TextButton, config, forceInstant: boolean?)
	local iconChip = btn:FindFirstChild("IconChip")
	local iconLabel = iconChip and iconChip:FindFirstChild("IconLabel")
	local textLabel = btn:FindFirstChild("TextLabel")
	local stroke = btn:FindFirstChildWhichIsA("UIStroke")
	if not iconChip or not iconLabel or not textLabel or not stroke then
		return
	end

	local isHovered = btn:GetAttribute("Hovered") == true
	local isPressed = btn:GetAttribute("Pressed") == true
	local isActive = config.name == "BuildButton" and IsBuildOpen

	local backgroundColor = UI_CONFIG.BOTTOM_BAR_BUTTON_BG
	local chipColor = UI_CONFIG.BOTTOM_BAR_CHIP_BG:Lerp(config.accentColor, 0.18)
	local textColor = config.accentColor
	local iconColor = config.accentColor
	local strokeColor = config.accentColor
	local strokeTransparency = 0.25

	if isActive then
		backgroundColor = UI_CONFIG.BOTTOM_BAR_BUTTON_BG:Lerp(config.accentColor, 0.28)
		chipColor = UI_CONFIG.BOTTOM_BAR_CHIP_BG:Lerp(config.hoverColor, 0.38)
		textColor = config.hoverColor
		iconColor = config.hoverColor
		strokeColor = config.hoverColor
		strokeTransparency = 0.02
	elseif isPressed then
		backgroundColor = UI_CONFIG.BOTTOM_BAR_BUTTON_BG:Lerp(config.accentColor, 0.24)
		chipColor = UI_CONFIG.BOTTOM_BAR_CHIP_BG:Lerp(config.hoverColor, 0.28)
		textColor = config.hoverColor
		iconColor = config.hoverColor
		strokeTransparency = 0.08
	elseif isHovered then
		backgroundColor = UI_CONFIG.BOTTOM_BAR_BUTTON_BG_HOVER:Lerp(config.accentColor, 0.16)
		chipColor = UI_CONFIG.BOTTOM_BAR_CHIP_BG:Lerp(config.hoverColor, 0.24)
		textColor = config.hoverColor
		iconColor = config.hoverColor
		strokeTransparency = 0.1
	end

	if forceInstant then
		btn.BackgroundColor3 = backgroundColor
		btn.BackgroundTransparency = UI_CONFIG.BOTTOM_BAR_BUTTON_TRANSPARENCY
		iconChip.BackgroundColor3 = chipColor
		iconChip.BackgroundTransparency = UI_CONFIG.BOTTOM_BAR_BUTTON_TRANSPARENCY
		iconLabel.TextColor3 = iconColor
		textLabel.TextColor3 = textColor
		stroke.Color = strokeColor
		stroke.Transparency = strokeTransparency
		return
	end

	local tweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(btn, tweenInfo, {
		BackgroundColor3 = backgroundColor,
		BackgroundTransparency = UI_CONFIG.BOTTOM_BAR_BUTTON_TRANSPARENCY,
	}):Play()
	TweenService:Create(iconChip, tweenInfo, {
		BackgroundColor3 = chipColor,
		BackgroundTransparency = UI_CONFIG.BOTTOM_BAR_BUTTON_TRANSPARENCY,
	}):Play()
	TweenService:Create(iconLabel, tweenInfo, { TextColor3 = iconColor }):Play()
	TweenService:Create(textLabel, tweenInfo, { TextColor3 = textColor }):Play()
	TweenService:Create(stroke, tweenInfo, {
		Color = strokeColor,
		Transparency = strokeTransparency,
	}):Play()
end

local function refreshBottomBarButtonVisuals(forceInstant: boolean?)
	for name, btn in pairs(BottomBarButtons) do
		local config = BOTTOM_BAR_ACTIONS_BY_NAME[name]
		if config then
			tweenBarButtonVisual(btn, config, forceInstant)
		end
	end
end

local function updateBottomBarLayout()
	if not MoneyHUDGui then
		return
	end

	local bottomBar = MoneyHUDGui:FindFirstChild("BottomBar")
	local buttonsFrame = bottomBar and bottomBar:FindFirstChild("ButtonsFrame")
	local padding = bottomBar and bottomBar:FindFirstChild("Padding")
	if not bottomBar or not buttonsFrame or not padding then
		return
	end

	local metrics = getBottomBarMetrics(getBottomBarViewportWidth())

	bottomBar.Size = UDim2.fromOffset(metrics.barWidth, metrics.barHeight)
	bottomBar.Position = UDim2.new(0.5, -math.floor(metrics.barWidth / 2), 1, -(metrics.barHeight + metrics.bottomMargin))

	padding.PaddingLeft = UDim.new(0, metrics.paddingX)
	padding.PaddingRight = UDim.new(0, metrics.paddingX)
	padding.PaddingTop = UDim.new(0, metrics.paddingY)
	padding.PaddingBottom = UDim.new(0, metrics.paddingY)

	for _, child in ipairs(buttonsFrame:GetChildren()) do
		if child:IsA("UIListLayout") or child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end

	local visibleActions = getVisibleBottomBarActions()
	if metrics.isMobile then
		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.fromOffset(metrics.buttonWidth, metrics.buttonHeight)
		gridLayout.CellPadding = UDim2.fromOffset(metrics.spacing, metrics.spacing)
		gridLayout.FillDirection = Enum.FillDirection.Horizontal
		gridLayout.FillDirectionMaxCells = math.min(3, math.max(1, #visibleActions))
		gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		gridLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = buttonsFrame
	else
		local listLayout = Instance.new("UIListLayout")
		listLayout.FillDirection = Enum.FillDirection.Horizontal
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		listLayout.Padding = UDim.new(0, metrics.spacing)
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Parent = buttonsFrame
	end

	for _, config in ipairs(BOTTOM_BAR_ACTIONS) do
		local btn = BottomBarButtons[config.name]
		if btn then
			btn.Visible = isBottomBarActionVisible(config.name)
			btn.Size = UDim2.fromOffset(metrics.buttonWidth, metrics.buttonHeight)
			local layoutOrder = 100
			for index, action in ipairs(visibleActions) do
				if action and action.name == config.name then
					layoutOrder = index
					break
				end
			end
			btn.LayoutOrder = layoutOrder

			local iconChip = btn:FindFirstChild("IconChip")
			local iconLabel = iconChip and iconChip:FindFirstChild("IconLabel")
			local textLabel = btn:FindFirstChild("TextLabel")
			if iconChip and textLabel then
				local iconSize = metrics.isMobile and 22 or 18
				local iconOffset = metrics.isMobile and 8 or 7
				local textOffset = metrics.isMobile and 34 or 30
				local textInset = metrics.isMobile and 40 or 36
				iconChip.Size = UDim2.fromOffset(iconSize, iconSize)
				iconChip.Position = UDim2.new(0, iconOffset, 0.5, -math.floor(iconSize / 2))

				textLabel.Position = UDim2.new(0, textOffset, 0, 0)
				textLabel.Size = UDim2.new(1, -textInset, 1, 0)
				textLabel.TextSize = 11
			end

			local label, iconLetter = getButtonPresentation(config)
			if textLabel then
				textLabel.Text = label
			end
			if iconLabel then
				iconLabel.Text = iconLetter
			end
		end
	end
end

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createMoneyHUD(): ScreenGui
	table.clear(BottomBarButtons)

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MoneyHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	----------------------------------------------------------------------
	-- RIGHT PANEL (Money, Storage, Holdings)
	----------------------------------------------------------------------
	local hudPanel = Instance.new("Frame")
	hudPanel.Name = "HUDPanel"
	hudPanel.Size = UDim2.new(0, UI_CONFIG.PANEL_WIDTH, 0, UI_CONFIG.PANEL_HEIGHT)
	hudPanel.Position = UDim2.new(1, -UI_CONFIG.PANEL_WIDTH - UI_CONFIG.PANEL_MARGIN, 0, 60)
	hudPanel.BackgroundColor3 = Color3.new(1, 1, 1) -- Set white to let Gradient work correctly
	hudPanel.BackgroundTransparency = UI_CONFIG.BACKGROUND_TRANSPARENCY
	hudPanel.BorderSizePixel = 0
	hudPanel.Parent = screenGui
	UIUtils.addCorner(hudPanel, UI_CONFIG.CORNER_RADIUS)
	
	-- UIGradient for the deep blue/purple mix
	local bgGradient = Instance.new("UIGradient")
	bgGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UI_CONFIG.BACKGROUND_COLOR),
		ColorSequenceKeypoint.new(1, UI_CONFIG.BACKGROUND_GRADIENT_END)
	})
	bgGradient.Rotation = 90
	bgGradient.Parent = hudPanel
	
	UIUtils.addStroke(hudPanel, UI_CONFIG.STROKE_COLOR, 1.5, UI_CONFIG.STROKE_TRANSPARENCY)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 16)
	padding.Parent = hudPanel

	-- Money and premium currency container
	local moneyContainer = Instance.new("Frame")
	moneyContainer.Name = "MoneyContainer"
	moneyContainer.Size = UDim2.new(1, 0, 0, 58)
	moneyContainer.Position = UDim2.new(0, 0, 0, 0)
	moneyContainer.BackgroundTransparency = 1
	moneyContainer.Parent = hudPanel

	local moneyIcon = Instance.new("TextLabel")
	moneyIcon.Name = "MoneyIcon"
	moneyIcon.Size = UDim2.new(0, 32, 0, 32)
	moneyIcon.Position = UDim2.new(0, 0, 0, 0)
	moneyIcon.BackgroundTransparency = 1
	moneyIcon.Text = "💰"
	moneyIcon.TextSize = 24
	moneyIcon.Font = Enum.Font.GothamBold
	moneyIcon.Parent = moneyContainer

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

	local braincellsLabel = Instance.new("TextLabel")
	braincellsLabel.Name = "BraincellsLabel"
	braincellsLabel.Size = UDim2.new(1, -40, 0, 20)
	braincellsLabel.Position = UDim2.new(0, 40, 0, 34)
	braincellsLabel.BackgroundTransparency = 1
	braincellsLabel.Text = "🧠 0"
	braincellsLabel.TextColor3 = Color3.fromRGB(145, 200, 255)
	braincellsLabel.TextSize = 15
	braincellsLabel.Font = Enum.Font.GothamBold
	braincellsLabel.TextXAlignment = Enum.TextXAlignment.Left
	braincellsLabel.Parent = moneyContainer

	local moneyDeltaLabel = Instance.new("TextLabel")
	moneyDeltaLabel.Name = "MoneyDeltaLabel"
	moneyDeltaLabel.Size = UDim2.new(0, 110, 0, 18)
	moneyDeltaLabel.Position = UDim2.new(1, -110, 0, 6)
	moneyDeltaLabel.BackgroundTransparency = 1
	moneyDeltaLabel.Text = ""
	moneyDeltaLabel.TextTransparency = 1
	moneyDeltaLabel.TextColor3 = UI_CONFIG.MONEY_COLOR
	moneyDeltaLabel.TextSize = 13
	moneyDeltaLabel.Font = Enum.Font.GothamBold
	moneyDeltaLabel.TextXAlignment = Enum.TextXAlignment.Right
	moneyDeltaLabel.Parent = moneyContainer

	-- Storage Section
	local storageContainer = Instance.new("Frame")
	storageContainer.Name = "ItemsContainer"
	storageContainer.Size = UDim2.new(1, -20, 0, 108)
	storageContainer.Position = UDim2.new(0, 15, 0, 86)
	storageContainer.BackgroundTransparency = 1
	storageContainer.Parent = hudPanel

	local storageTitle = Instance.new("TextLabel")
	storageTitle.Name = "ItemsAmount"
	storageTitle.Size = UDim2.new(1, 0, 0, 20)
	storageTitle.BackgroundTransparency = 1
	storageTitle.Text = "📦 ITEMS IN STORAGE: 0 / 0"
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
	UIUtils.addCorner(itemsBarBg, 4)

	local itemsBarFill = Instance.new("Frame")
	itemsBarFill.Name = "ItemsBarFill"
	itemsBarFill.Size = UDim2.new(0, 0, 1, 0)
	itemsBarFill.BackgroundColor3 = UI_CONFIG.THEME_ACCENT_BLUE
	itemsBarFill.BorderSizePixel = 0
	itemsBarFill.Parent = itemsBarBg
	UIUtils.addCorner(itemsBarFill, 4)

	local marketStatus = Instance.new("TextLabel")
	marketStatus.Name = "MarketStatus"
	marketStatus.Size = UDim2.new(1, 0, 0, 18)
	marketStatus.Position = UDim2.new(0, 0, 0, 44)
	marketStatus.BackgroundTransparency = 1
	marketStatus.Text = "Market steady."
	marketStatus.TextColor3 = UI_CONFIG.THEME_TEXT_SECONDARY
	marketStatus.TextSize = 11
	marketStatus.Font = Enum.Font.GothamBold
	marketStatus.TextXAlignment = Enum.TextXAlignment.Left
	marketStatus.Parent = storageContainer

	local marketOpportunity = Instance.new("TextLabel")
	marketOpportunity.Name = "MarketOpportunity"
	marketOpportunity.Size = UDim2.new(1, 0, 0, 16)
	marketOpportunity.Position = UDim2.new(0, 0, 0, 60)
	marketOpportunity.BackgroundTransparency = 1
	marketOpportunity.Text = "Build stock to catch the next spike."
	marketOpportunity.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
	marketOpportunity.TextSize = 10
	marketOpportunity.Font = Enum.Font.Gotham
	marketOpportunity.TextXAlignment = Enum.TextXAlignment.Left
	marketOpportunity.Parent = storageContainer

	local nextGoal = Instance.new("TextLabel")
	nextGoal.Name = "NextGoal"
	nextGoal.Size = UDim2.new(1, 0, 0, 16)
	nextGoal.Position = UDim2.new(0, 0, 0, 76)
	nextGoal.BackgroundTransparency = 1
	nextGoal.Text = "Keep scaling to reveal your next power spike."
	nextGoal.TextColor3 = UI_CONFIG.THEME_ACCENT_BLUE
	nextGoal.TextSize = 10
	nextGoal.Font = Enum.Font.GothamBold
	nextGoal.TextXAlignment = Enum.TextXAlignment.Left
	nextGoal.Parent = storageContainer

	local nextUnlock = Instance.new("TextLabel")
	nextUnlock.Name = "NextUnlock"
	nextUnlock.Size = UDim2.new(1, 0, 0, 16)
	nextUnlock.Position = UDim2.new(0, 0, 0, 92)
	nextUnlock.BackgroundTransparency = 1
	nextUnlock.Text = "Finish onboarding to reveal the next unlock."
	nextUnlock.TextColor3 = UI_CONFIG.THEME_ACCENT_GOLD
	nextUnlock.TextSize = 10
	nextUnlock.Font = Enum.Font.GothamBold
	nextUnlock.TextXAlignment = Enum.TextXAlignment.Left
	nextUnlock.Parent = storageContainer

	----------------------------------------------------------------------
	-- YOUR TOP HOLDINGS SECTION
	----------------------------------------------------------------------
	local holdingsY = 192

	-- Thin divider
	local div = Instance.new("Frame")
	div.Name = "HoldingsDivider"
	div.Size = UDim2.new(1, -10, 0, 1)
	div.Position = UDim2.new(0, 5, 0, holdingsY)
	div.BackgroundColor3 = UI_CONFIG.THEME_STROKE
	div.BackgroundTransparency = 0.4
	div.BorderSizePixel = 0
	div.Parent = hudPanel

	holdingsY += 8

	local titleContainer = Instance.new("Frame")
	titleContainer.Name = "TitleContainer"
	titleContainer.Size = UDim2.new(1, 0, 0, 16)
	titleContainer.Position = UDim2.new(0, 0, 0, holdingsY)
	titleContainer.BackgroundTransparency = 1
	titleContainer.Parent = hudPanel

	local holdingsTitle = Instance.new("TextLabel")
	holdingsTitle.Name = "HoldingsTitle"
	holdingsTitle.Size = UDim2.new(1, -20, 1, 0)
	holdingsTitle.Position = UDim2.new(0, 0, 0, 0)
	holdingsTitle.BackgroundTransparency = 1
	holdingsTitle.Text = "Your Top Holdings"
	holdingsTitle.TextColor3 = UI_CONFIG.HOLDINGS_TITLE_COLOR
	holdingsTitle.TextSize = 13
	holdingsTitle.Font = Enum.Font.GothamBold
	holdingsTitle.TextXAlignment = Enum.TextXAlignment.Left
	holdingsTitle.Parent = titleContainer

	local collapseButton = Instance.new("TextButton")
	collapseButton.Name = "CollapseButton"
	collapseButton.Size = UDim2.new(0, 16, 0, 16)
	collapseButton.Position = UDim2.new(1, -16, 0, 0)
	collapseButton.BackgroundTransparency = 1
	collapseButton.Text = "▼"
	collapseButton.TextColor3 = UI_CONFIG.THEME_TEXT_SECONDARY
	collapseButton.TextSize = 12
	collapseButton.Font = Enum.Font.GothamBold
	collapseButton.Parent = titleContainer

	holdingsY += 20

	-- Holdings list container
	local holdingsList = Instance.new("ScrollingFrame")
	holdingsList.Name = "HoldingsList"
	holdingsList.Size = UDim2.new(1, 0, 0, UI_CONFIG.MAX_HOLDINGS_ROWS * UI_CONFIG.ROW_HEIGHT + 25)
	holdingsList.Position = UDim2.new(0, 0, 0, holdingsY)
	holdingsList.BackgroundTransparency = 1
	holdingsList.BorderSizePixel = 0
	holdingsList.ScrollBarThickness = 4
	holdingsList.ScrollBarImageColor3 = UI_CONFIG.THEME_TEXT_SECONDARY
	holdingsList.CanvasSize = UDim2.new(0, 0, 0, 0)
	holdingsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	holdingsList.ClipsDescendants = true
	holdingsList.Parent = hudPanel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8) -- Matches reference spacing
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = holdingsList

	holdingsY += UI_CONFIG.MAX_HOLDINGS_ROWS * UI_CONFIG.ROW_HEIGHT + 25

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(1, 0, 1, 0)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "No items in storage"
	emptyLabel.TextColor3 = UI_CONFIG.LABEL_COLOR
	emptyLabel.TextSize = 11
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.Visible = true
	emptyLabel.Parent = holdingsList

	collapseButton.MouseButton1Click:Connect(function()
		local isVisible = holdingsList.Visible
		holdingsList.Visible = not isVisible
		collapseButton.Text = isVisible and "▶" or "▼"
		emptyLabel.Visible = not isVisible and emptyLabel.Text ~= ""
	end)

	----------------------------------------------------------------------
	-- BOTTOM CENTER ACTION BAR
	----------------------------------------------------------------------
	local initialMetrics = getBottomBarMetrics(getBottomBarViewportWidth())

	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.fromOffset(initialMetrics.barWidth, initialMetrics.barHeight)
	bottomBar.Position = UDim2.new(
		0.5,
		-math.floor(initialMetrics.barWidth / 2),
		1,
		-(initialMetrics.barHeight + initialMetrics.bottomMargin)
	)
	bottomBar.BackgroundColor3 = UI_CONFIG.BACKGROUND_COLOR
	bottomBar.BackgroundTransparency = UI_CONFIG.BACKGROUND_TRANSPARENCY
	bottomBar.BorderSizePixel = 0
	bottomBar.Parent = screenGui
	UIUtils.addCorner(bottomBar, UI_CONFIG.CORNER_RADIUS)
	UIUtils.addStroke(bottomBar, UI_CONFIG.STROKE_COLOR, 2.5, UI_CONFIG.STROKE_TRANSPARENCY)

	local barPadding = Instance.new("UIPadding")
	barPadding.Name = "Padding"
	barPadding.PaddingLeft = UDim.new(0, initialMetrics.paddingX)
	barPadding.PaddingRight = UDim.new(0, initialMetrics.paddingX)
	barPadding.PaddingTop = UDim.new(0, initialMetrics.paddingY)
	barPadding.PaddingBottom = UDim.new(0, initialMetrics.paddingY)
	barPadding.Parent = bottomBar

	local buttonsFrame = Instance.new("Frame")
	buttonsFrame.Name = "ButtonsFrame"
	buttonsFrame.Size = UDim2.new(1, 0, 1, 0)
	buttonsFrame.BackgroundTransparency = 1
	buttonsFrame.Parent = bottomBar

	local function createBarButton(config)
		local label, iconLetter = getButtonPresentation(config)

		local btn = Instance.new("TextButton")
		btn.Name = config.name
		btn.Size = UDim2.fromOffset(initialMetrics.buttonWidth, initialMetrics.buttonHeight)
		btn.BackgroundColor3 = Color3.new(1, 1, 1) -- Set to white for UIGradient
		btn.BackgroundTransparency = UI_CONFIG.BOTTOM_BAR_BUTTON_TRANSPARENCY
		btn.LayoutOrder = config.layoutOrder
		btn.Text = ""
		btn.AutoButtonColor = false
		btn.BorderSizePixel = 0
		btn.Parent = buttonsFrame
		
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = btn
		
		local btnGradient = Instance.new("UIGradient")
		btnGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, config.accentColor),
			ColorSequenceKeypoint.new(1, UI_CONFIG.BOTTOM_BAR_BUTTON_BG)
		})
		btnGradient.Rotation = 90
		btnGradient.Parent = btn
		
		UIUtils.addStroke(btn, config.accentColor, 2, 0)

		local iconChip = Instance.new("Frame")
		iconChip.Name = "IconChip"
		iconChip.Size = UDim2.fromOffset(20, 20)
		iconChip.Position = UDim2.new(0, 6, 0.5, -10)
		iconChip.BackgroundColor3 = UI_CONFIG.BOTTOM_BAR_CHIP_BG:Lerp(config.accentColor, 0.18)
		iconChip.BorderSizePixel = 0
		iconChip.Parent = btn
		
		local chipCorner = Instance.new("UICorner")
		chipCorner.CornerRadius = UDim.new(1, 0)
		chipCorner.Parent = iconChip

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Name = "IconLabel"
		iconLabel.Size = UDim2.new(1, 0, 1, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = iconLetter
		iconLabel.TextSize = 11
		iconLabel.TextColor3 = config.accentColor
		iconLabel.Font = Enum.Font.GothamBold
		iconLabel.Parent = iconChip

		local textLabel = Instance.new("TextLabel")
		textLabel.Name = "TextLabel"
		textLabel.Size = UDim2.new(1, -32, 1, 0)
		textLabel.Position = UDim2.new(0, 28, 0, 0)
		textLabel.BackgroundTransparency = 1
		textLabel.Text = label
		textLabel.TextSize = 11
		textLabel.TextColor3 = config.accentColor
		textLabel.Font = Enum.Font.GothamBold
		textLabel.TextXAlignment = Enum.TextXAlignment.Left
		textLabel.Parent = btn

		BottomBarButtons[config.name] = btn
		return btn
	end

	for _, config in ipairs(BOTTOM_BAR_ACTIONS) do
		createBarButton(config)
	end

	return screenGui
end

--------------------------------------------------------------------------------
-- MONEY TRACKING
--------------------------------------------------------------------------------

local MoneyLabel: TextLabel
local MoneyDeltaLabel: TextLabel
local BraincellsLabel: TextLabel
local ItemsBarFill: Frame
local ItemsAmountLabel: TextLabel
local MarketStatusLabel: TextLabel
local MarketOpportunityLabel: TextLabel
local NextGoalLabel: TextLabel
local NextUnlockLabel: TextLabel

local previousMoney: number = 0
local OwnedCounts: { [string]: number } = {}

local rateCache = {}
local lastRateUpdate = 0

local function getOwnedUnitSet(): { [string]: boolean }
	local owned = {}

	for unitName, count in pairs(OwnedCounts) do
		if tonumber(count) and count > 0 then
			owned[unitName] = true
		end
	end

	for _, unit in CollectionService:GetTagged("ActiveBrainrot") do
		if unit:GetAttribute("OwnerId") == Player.UserId then
			local unitType = unit:GetAttribute("UnitType")
			if type(unitType) == "string" and unitType ~= "" then
				owned[unitType] = true
			end
		end
	end

	return owned
end

local function getFallbackSynergyConfig()
	for _, syn in ipairs(ItemConfig.Synergies or {}) do
		local forward = syn.unitA == "Avocadini Guffo" and syn.unitB == "Bambini_Crostini"
		local reverse = syn.unitA == "Bambini_Crostini" and syn.unitB == "Avocadini Guffo"
		if forward or reverse then
			return syn
		end
	end
	return (ItemConfig.Synergies or {})[1]
end

local function getRecommendedSynergyPair()
	if Player:GetAttribute("SynergyUnlocked") ~= true then
		return nil
	end

	local ownedUnits = getOwnedUnitSet()
	local bestSyn = nil
	local bestScore = -math.huge

	for _, syn in ipairs(ItemConfig.Synergies or {}) do
		local itemDef = ItemConfig.Items[syn.synergyItem]
		local ownedA = ownedUnits[syn.unitA] == true
		local ownedB = ownedUnits[syn.unitB] == true
		local score = ((itemDef and itemDef.basePrice) or 0) / 20

		if ownedA and ownedB then
			score += 300
		elseif ownedA or ownedB then
			score += 150
		end

		if score > bestScore then
			bestScore = score
			bestSyn = syn
		end
	end

	return bestSyn or getFallbackSynergyConfig()
end

local function updateRateCache()
	if os.clock() - lastRateUpdate < 1 then
		return
	end
	lastRateUpdate = os.clock()

	table.clear(rateCache)
	for _, unit in CollectionService:GetTagged("ActiveBrainrot") do
		if unit:GetAttribute("OwnerId") == Player.UserId then
			local producingId = unit:GetAttribute("CurrentProducing")

			if not producingId then
				local unitType = unit:GetAttribute("UnitType")
				local currentMode = unit:GetAttribute("CurrentMode") or 1
				if
					unitType
					and ItemConfig.BrainrotModes
					and ItemConfig.BrainrotModes[unitType]
					and ItemConfig.BrainrotModes[unitType][currentMode]
				then
					producingId = ItemConfig.BrainrotModes[unitType][currentMode].itemId
				end
			end

			if producingId then
				local interval = unit:GetAttribute("IncomeInterval")
				local rate = 0
				if interval and interval > 0 then
					rate = 1 / interval
				else
					local unitType = unit:GetAttribute("UnitType")
					local config = unitType and ShopConfig.GetConfig(unitType)
					if config and config.CycleTime and config.CycleTime > 0 then
						rate = 1 / config.CycleTime
					end
				end
				rateCache[producingId] = (rateCache[producingId] or 0) + rate
			end
		end
	end
end

local function calculateItemRate(itemId: string): number
	return rateCache[itemId] or 0
end

local function updateMPSDisplay()
	-- Removed globally
end

local function updateBrainrotCount()
	if not MoneyHUDGui then
		return
	end

	local bottomBar = MoneyHUDGui:FindFirstChild("BottomBar")
	if not bottomBar then
		return
	end

	local brainrotsBtn = bottomBar:FindFirstChild("BrainrotsButton")
	if not brainrotsBtn then
		return
	end

	local badge = brainrotsBtn:FindFirstChild("CountBadge")
	if not badge then
		return
	end

	local totalCount = 0
	for _, count in OwnedCounts do
		totalCount = totalCount + count
	end

	badge.Text = tostring(totalCount)
	if totalCount > 0 then
		badge.BackgroundColor3 = Color3.fromRGB(60, 180, 100)
	else
		badge.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	end
end

local function updateMoneyDisplay(newMoney: number)
	if not MoneyLabel then
		return
	end

	local delta = newMoney - previousMoney
	local formattedMoney = FormatUtils.formatMoney(newMoney)
	MoneyLabel.Text = formattedMoney

	if delta > 0 then
		MoneyLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
		MoneyLabel.Size = UDim2.new(1, -30, 0, 38)

		TweenService:Create(MoneyLabel, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			TextColor3 = UI_CONFIG.MONEY_COLOR,
			Size = UDim2.new(1, -40, 0, 32),
		}):Play()
	elseif delta < 0 then
		MoneyLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		TweenService:Create(MoneyLabel, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
			TextColor3 = Color3.fromRGB(200, 200, 200),
		}):Play()
		task.delay(0.2, function()
			if MoneyLabel then
				TweenService:Create(MoneyLabel, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
					TextColor3 = UI_CONFIG.MONEY_COLOR,
				}):Play()
			end
		end)
	end

	if MoneyDeltaLabel and delta ~= 0 then
		MoneyDeltaLabel.Text = string.format("%s%s", delta > 0 and "+" or "-", FormatUtils.formatMoney(math.abs(delta)))
		MoneyDeltaLabel.TextColor3 = delta > 0 and UI_CONFIG.MONEY_COLOR or UI_CONFIG.ARROW_DOWN_COLOR
		MoneyDeltaLabel.TextTransparency = 0
		MoneyDeltaLabel.Position = UDim2.new(1, -110, 0, 6)
		TweenService:Create(MoneyDeltaLabel, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
			Position = UDim2.new(1, -110, 0, delta > 0 and -2 or 12),
		}):Play()
	end

	previousMoney = newMoney
end

local function updateBraincellsDisplay(newBraincells: number)
	if not BraincellsLabel then
		return
	end
	BraincellsLabel.Text = string.format("🧠 %s", FormatUtils.formatMoney(newBraincells))
end

local function updateItemsDisplay(currentItems: number, maxItems: number)
	if not ItemsBarFill or not ItemsAmountLabel then
		return
	end

	local fillPercent = math.clamp(currentItems / math.max(1, maxItems), 0, 1)

	TweenService:Create(ItemsBarFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(fillPercent, 0, 1, 0),
	}):Play()

	ItemsAmountLabel.Text = string.format("📦 ITEMS IN STORAGE: %d / %d", currentItems, maxItems)

	local targetColor
	if fillPercent >= 1 then
		targetColor = UI_CONFIG.ITEMS_FULL_COLOR
	elseif fillPercent >= 0.75 then
		targetColor = UI_CONFIG.ITEMS_FILL_COLOR:Lerp(UI_CONFIG.ITEMS_FULL_COLOR, (fillPercent - 0.75) / 0.25)
	else
		targetColor = UI_CONFIG.ITEMS_FILL_COLOR
	end

	TweenService:Create(ItemsBarFill, TweenInfo.new(0.2), {
		BackgroundColor3 = targetColor,
	}):Play()
end

local function getBestStoredOpportunity()
	local localRates = getLocalItemRates()
	local bestOpportunity = nil

	for itemId, count in pairs(StorageItems) do
		if count > 0 then
			local itemDef = ItemConfig.Items[itemId]
			if itemDef then
				local localRate = tonumber(localRates[itemId]) or 1.0
				local estimatedValue = count * (itemDef.basePrice or 1) * localRate
				if (not bestOpportunity) or estimatedValue > bestOpportunity.estimatedValue then
					bestOpportunity = {
						itemId = itemId,
						count = count,
						rate = localRate,
						estimatedValue = estimatedValue,
						displayName = itemDef.displayName or itemId,
					}
				end
			end
		end
	end

	return bestOpportunity
end

local function getBestHybridOpportunity()
	local localRates = getLocalItemRates()
	local synergyOutputs = {}
	for _, syn in ipairs(ItemConfig.Synergies or {}) do
		synergyOutputs[syn.synergyItem] = true
	end

	local bestOpportunity = nil
	for itemId, count in pairs(StorageItems) do
		if count > 0 and synergyOutputs[itemId] then
			local itemDef = ItemConfig.Items[itemId]
			if itemDef then
				local localRate = tonumber(localRates[itemId]) or 1.0
				local estimatedValue = count * (itemDef.basePrice or 1) * localRate
				if (not bestOpportunity) or estimatedValue > bestOpportunity.estimatedValue then
					bestOpportunity = {
						itemId = itemId,
						count = count,
						rate = localRate,
						estimatedValue = estimatedValue,
						displayName = itemDef.displayName or itemId,
					}
				end
			end
		end
	end

	return bestOpportunity
end

local function updateMarketStatusDisplay()
	if not MarketStatusLabel then
		return
	end

	local currentRate = StockMarketFolder and StockMarketFolder:GetAttribute("CurrentRate") or 1.0
	local bestOpportunity = getBestStoredOpportunity()
	local bestHybridOpportunity = getBestHybridOpportunity()
	local recommendedSynergy = getRecommendedSynergyPair()
	if currentRate >= 1.25 then
		MarketStatusLabel.Text = "Market hot. Sell now."
		MarketStatusLabel.TextColor3 = UI_CONFIG.ARROW_UP_COLOR
	elseif currentRate <= 0.85 then
		MarketStatusLabel.Text = "Market weak. Wait if you can."
		MarketStatusLabel.TextColor3 = UI_CONFIG.ARROW_DOWN_COLOR
	else
		MarketStatusLabel.Text = "Market steady."
		MarketStatusLabel.TextColor3 = UI_CONFIG.THEME_TEXT_SECONDARY
	end

	if not MarketOpportunityLabel then
		return
	end

	if Player:GetAttribute("MarketIntelUnlocked") ~= true then
		if isTutorialComplete() then
			MarketOpportunityLabel.Text = "Market intel will reveal your best sell window soon."
		else
			MarketOpportunityLabel.Text = "Finish your first goals to start reading the market."
		end
		MarketOpportunityLabel.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
		return
	end

	if not bestOpportunity then
		if Player:GetAttribute("DetailedMarketUnlocked") == true and not isTerminalIntroComplete() then
			if CartController.State == "rolling_to_market" then
				MarketOpportunityLabel.Text = "Cart en route. Open Market when it arrives."
			elseif CartController.State == "idle" and CartController.ItemCount > 0 then
				MarketOpportunityLabel.Text = "Cart loaded. Send it to market for your first targeted sell."
			else
				MarketOpportunityLabel.Text = "Market terminal ready. Build stock, then target the best stack first."
			end
		elseif Player:GetAttribute("DetailedMarketUnlocked") == true and Player:GetAttribute("SynergyUnlocked") ~= true then
			if CartController.State == "rolling_to_market" then
				MarketOpportunityLabel.Text = "Cart en route. Sell the strongest stack first when it lands."
			elseif CartController.State == "idle" and CartController.ItemCount > 0 then
				MarketOpportunityLabel.Text = "Cart loaded. Send it out and cash the strongest stack first."
			else
				MarketOpportunityLabel.Text = "Terminal ready. Build stock, then target your best seller."
			end
		else
			MarketOpportunityLabel.Text = Player:GetAttribute("DetailedMarketUnlocked") == true
				and "Terminal ready. Build stock for a targeted sell."
				or "Build stock to catch the next hot market."
		end
		MarketOpportunityLabel.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
		return
	end

	if Player:GetAttribute("DetailedMarketUnlocked") == true and not isTerminalIntroComplete() then
		if CartController.State == "rolling_to_market" then
			MarketOpportunityLabel.Text = "Cart en route. Open Market when it arrives."
		elseif CartController.State == "idle" and CartController.ItemCount > 0 then
			MarketOpportunityLabel.Text = "Cart loaded. Send it to market for your first targeted sell."
		else
			MarketOpportunityLabel.Text = "Market terminal ready. Load, send, and sell your best stock."
		end
		MarketOpportunityLabel.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
		return
	end

	if Player:GetAttribute("SynergyUnlocked") == true and not isFirstSynergyActivated() then
		if recommendedSynergy then
			MarketOpportunityLabel.Text = string.format(
				"Hybrid stock starts with %s + %s.",
				formatUnitShortName(recommendedSynergy.unitA),
				formatUnitShortName(recommendedSynergy.unitB)
			)
		else
			MarketOpportunityLabel.Text = "Hybrid outputs create rarer stock. Pair two weird units in one cluster."
		end
		MarketOpportunityLabel.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
		return
	end

	if Player:GetAttribute("SynergyUnlocked") == true and bestHybridOpportunity then
		MarketOpportunityLabel.Text = string.format(
			"Hybrid stock online: %s x%d at %.2fx",
			bestHybridOpportunity.displayName,
			bestHybridOpportunity.count,
			bestHybridOpportunity.rate
		)
		MarketOpportunityLabel.TextColor3 = UI_CONFIG.THEME_ACCENT_BLUE
		return
	end

	if Player:GetAttribute("ArtifactsUnlocked") == true and not isFirstArtifactFound() then
		MarketOpportunityLabel.Text = "Relics are online. Keep producing and your first one should drop soon."
		MarketOpportunityLabel.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
		return
	end

	if Player:GetAttribute("ArtifactsUnlocked") == true and not isFirstArtifactEquipped() then
		MarketOpportunityLabel.Text = "First relic found. Open a producer and equip it for a real boost."
		MarketOpportunityLabel.TextColor3 = UI_CONFIG.THEME_ACCENT_BLUE
		return
	end

	if Player:GetAttribute("DetailedMarketUnlocked") == true and Player:GetAttribute("SynergyUnlocked") ~= true then
		if CartController.State == "rolling_to_market" then
			MarketOpportunityLabel.Text = "Cart en route. Sell the strongest stack first when it lands."
		elseif CartController.State == "idle" and CartController.ItemCount > 0 then
			MarketOpportunityLabel.Text = "Cart loaded. Send it out and cash the strongest stack first."
		else
			MarketOpportunityLabel.Text = string.format(
				"Best target: %s x%d at %.2fx",
				bestOpportunity.displayName,
				bestOpportunity.count,
				bestOpportunity.rate
			)
		end
		MarketOpportunityLabel.TextColor3 = UI_CONFIG.THEME_TEXT_PRIMARY
		return
	end

	if Player:GetAttribute("DetailedMarketUnlocked") == true then
		MarketOpportunityLabel.Text = string.format(
			"Move first: %s x%d at %.2fx",
			bestOpportunity.displayName,
			bestOpportunity.count,
			bestOpportunity.rate
		)
	elseif bestOpportunity.rate >= 1.15 then
		MarketOpportunityLabel.Text = string.format(
			"Best sell now: %s x%d at %.2fx",
			bestOpportunity.displayName,
			bestOpportunity.count,
			bestOpportunity.rate
		)
	elseif bestOpportunity.rate <= 0.9 then
		MarketOpportunityLabel.Text = string.format(
			"Hold if you can: %s is weak at %.2fx",
			bestOpportunity.displayName,
			bestOpportunity.rate
		)
	else
		MarketOpportunityLabel.Text = string.format(
			"Top stock: %s x%d at %.2fx",
			bestOpportunity.displayName,
			bestOpportunity.count,
			bestOpportunity.rate
		)
	end
	MarketOpportunityLabel.TextColor3 = bestOpportunity.rate >= 1.0
		and UI_CONFIG.THEME_TEXT_PRIMARY
		or UI_CONFIG.HOLDINGS_COUNT_COLOR
end

local function updateNextGoalDisplay()
	if not NextGoalLabel then
		return
	end

	if not isTutorialComplete() then
		NextGoalLabel.Text = "Onboarding is setting your next move."
		NextGoalLabel.TextColor3 = UI_CONFIG.THEME_ACCENT_BLUE
		return
	end

	if Player:GetAttribute("DetailedMarketUnlocked") == true and not isTerminalIntroComplete() then
		NextGoalLabel.Text = "Next goal: make your first targeted terminal sale."
		NextGoalLabel.TextColor3 = UI_CONFIG.THEME_ACCENT_BLUE
		return
	end

	if Player:GetAttribute("SynergyUnlocked") == true and not isFirstSynergyActivated() then
		NextGoalLabel.Text = "Next goal: make your first hybrid output."
		NextGoalLabel.TextColor3 = UI_CONFIG.THEME_ACCENT_BLUE
		return
	end

	if Player:GetAttribute("ArtifactsUnlocked") == true and not isFirstArtifactFound() then
		NextGoalLabel.Text = "Next goal: find your first relic."
		NextGoalLabel.TextColor3 = UI_CONFIG.THEME_ACCENT_BLUE
		return
	end

	if Player:GetAttribute("ArtifactsUnlocked") == true and not isFirstArtifactEquipped() then
		NextGoalLabel.Text = "Next goal: equip your first relic on a producer."
		NextGoalLabel.TextColor3 = UI_CONFIG.THEME_ACCENT_BLUE
		return
	end

	local goalName = tostring(Player:GetAttribute("NextGoalName") or "")
	local goalTarget = tonumber(Player:GetAttribute("NextGoalTarget")) or 0
	local goalProgress = tonumber(Player:GetAttribute("NextGoalProgress")) or 0
	if goalName ~= "" and goalTarget > 0 then
		NextGoalLabel.Text = string.format(
			"Next goal: %s %d/%d",
			goalName,
			math.min(math.floor(goalProgress), math.floor(goalTarget)),
			math.floor(goalTarget)
		)
		NextGoalLabel.TextColor3 = UI_CONFIG.THEME_ACCENT_BLUE
		return
	end

	local fallbackDescription = tostring(Player:GetAttribute("NextUnlockDescription") or "")
	if fallbackDescription ~= "" then
		NextGoalLabel.Text = fallbackDescription
		NextGoalLabel.TextColor3 = UI_CONFIG.THEME_TEXT_SECONDARY
		return
	end

	NextGoalLabel.Text = "Keep scaling to reveal your next power spike."
	NextGoalLabel.TextColor3 = UI_CONFIG.THEME_TEXT_SECONDARY
end

local function updateNextUnlockDisplay()
	if not NextUnlockLabel then
		return
	end

	if not isTutorialComplete() then
		NextUnlockLabel.Text = "Finish onboarding to reveal your first market unlock."
		NextUnlockLabel.TextColor3 = UI_CONFIG.THEME_ACCENT_GOLD
		return
	end

	if Player:GetAttribute("DetailedMarketUnlocked") == true and not isTerminalIntroComplete() then
		NextUnlockLabel.Text = "Next goal: make your first targeted terminal sale."
		NextUnlockLabel.TextColor3 = UI_CONFIG.THEME_ACCENT_GOLD
		return
	end

	local unlockName = tostring(Player:GetAttribute("NextUnlockName") or "")
	local unlockTarget = tonumber(Player:GetAttribute("NextUnlockTarget")) or 0
	local unlockProgress = tonumber(Player:GetAttribute("NextUnlockProgress")) or 0

	if unlockName == "" or unlockTarget <= 0 then
		NextUnlockLabel.Text = "All core systems unlocked."
		NextUnlockLabel.TextColor3 = UI_CONFIG.ARROW_UP_COLOR
		return
	end

	NextUnlockLabel.Text = string.format(
		"Next unlock: %s %s / %s",
		unlockName,
		FormatUtils.formatMoney(unlockProgress),
		FormatUtils.formatMoney(unlockTarget)
	)
	NextUnlockLabel.TextColor3 = UI_CONFIG.THEME_ACCENT_GOLD
end

--------------------------------------------------------------------------------
-- HOLDINGS DISPLAY
--------------------------------------------------------------------------------

local function updateHoldingsDisplay()
	if not MoneyHUDGui then
		return
	end

	local hudPanel = MoneyHUDGui:FindFirstChild("HUDPanel")
	if not hudPanel then
		return
	end
	local titleContainer = hudPanel:FindFirstChild("TitleContainer")
	local holdingsTitle = titleContainer and titleContainer:FindFirstChild("HoldingsTitle") or hudPanel:FindFirstChild("HoldingsTitle")
	local holdingsList = hudPanel:FindFirstChild("HoldingsList")
	if not holdingsList then
		return
	end

	-- Hide old rows instead of destroying (Object Pooling)
	for _, child in holdingsList:GetChildren() do
		if child:IsA("Frame") and string.sub(child.Name, 1, 3) == "Row" then
			child.Visible = false
		end
	end

	local emptyLabel = holdingsList:FindFirstChild("EmptyLabel")


	if not isTutorialComplete() then
		if holdingsTitle then
			holdingsTitle.Text = "Objectives"
		end

		local definitions = {}
		for _, def in ipairs(LatestAchievementSnapshot.Definitions or {}) do
			if def.OnboardingOrder then
				table.insert(definitions, def)
			end
		end
		table.sort(definitions, function(a, b)
			return (a.OnboardingOrder or 999) < (b.OnboardingOrder or 999)
		end)

		if emptyLabel then
			emptyLabel.Text = "No objectives configured"
			emptyLabel.Visible = #definitions == 0
		end

		for i = 1, math.min(UI_CONFIG.MAX_HOLDINGS_ROWS, #definitions) do
			local def = definitions[i]
			local progressMap = (LatestAchievementSnapshot.State and LatestAchievementSnapshot.State.Progress) or {}
			local progress = math.floor(progressMap[def.Id] or 0)
			local target = math.max(1, math.floor(def.TargetValue or 1))
			local completed = progress >= target

			local row = holdingsList:FindFirstChild("Row" .. i)
			if not row then
				row = Instance.new("Frame")
				row.Name = "Row" .. i
				row.Size = UDim2.new(1, 0, 0, 44) 
				row.BackgroundTransparency = 0.85
				row.BorderSizePixel = 0
				row.LayoutOrder = i
				row.Parent = holdingsList
				UIUtils.addCorner(row, 8)
				UIUtils.addStroke(row, UI_CONFIG.THEME_ACCENT_BLUE, 1, 0)

				local iconChip = Instance.new("Frame")
				iconChip.Name = "IconChip"
				iconChip.Size = UDim2.new(0, 36, 0, 36)
				iconChip.Position = UDim2.new(0, 4, 0, 4)
				iconChip.BackgroundColor3 = UI_CONFIG.THEME_ACCENT_BLUE -- Default, overridden below
				iconChip.BackgroundTransparency = 0
				iconChip.BorderSizePixel = 0
				iconChip.Parent = row
				UIUtils.addCorner(iconChip, 6)

				local iconLabel = Instance.new("TextLabel")
				iconLabel.Name = "Icon"
				iconLabel.Size = UDim2.new(1, 0, 1, 0)
				iconLabel.Position = UDim2.new(0, 0, 0, 0)
				iconLabel.BackgroundTransparency = 1
				iconLabel.TextSize = 20
				iconLabel.Font = Enum.Font.GothamBold
				iconLabel.Parent = iconChip

				local nameLabel = Instance.new("TextLabel")
				nameLabel.Name = "ItemName"
				nameLabel.Size = UDim2.new(1, -120, 0, 16)
				nameLabel.Position = UDim2.new(0, 48, 0, 4)
				nameLabel.BackgroundTransparency = 1
				nameLabel.TextColor3 = Color3.new(1, 1, 1)
				nameLabel.TextSize = 13
				nameLabel.Font = Enum.Font.GothamMedium
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
				nameLabel.Parent = row

				local countLabel = Instance.new("TextLabel")
				countLabel.Name = "Count"
				countLabel.Size = UDim2.new(0, 30, 0, 14)
				countLabel.Position = UDim2.new(0, 48, 0, 22)
				countLabel.BackgroundTransparency = 1
				countLabel.TextColor3 = UI_CONFIG.THEME_TEXT_SECONDARY
				countLabel.TextSize = 10
				countLabel.Font = Enum.Font.Gotham
				countLabel.TextXAlignment = Enum.TextXAlignment.Left
				countLabel.Parent = row

				local progressBarBg = Instance.new("Frame")
				progressBarBg.Name = "ProgressBarBg"
				progressBarBg.Size = UDim2.new(1, -86, 0, 4)
				progressBarBg.Position = UDim2.new(0, 80, 0, 28)
				progressBarBg.BackgroundColor3 = Color3.fromRGB(30, 35, 50)
				progressBarBg.BorderSizePixel = 0
				progressBarBg.Parent = row
				UIUtils.addCorner(progressBarBg, 2)

				local progressBarFill = Instance.new("Frame")
				progressBarFill.Name = "ProgressBarFill"
				progressBarFill.Size = UDim2.new(0, 0, 1, 0)
				progressBarFill.BackgroundColor3 = UI_CONFIG.THEME_ACCENT_BLUE
				progressBarFill.BorderSizePixel = 0
				progressBarFill.Parent = progressBarBg
				UIUtils.addCorner(progressBarFill, 2)

				local statusLabel = Instance.new("TextLabel")
				statusLabel.Name = "Status"
				statusLabel.Size = UDim2.new(0, 70, 0, 12)
				statusLabel.Position = UDim2.new(1, -76, 0, 6)
				statusLabel.BackgroundTransparency = 1
				statusLabel.TextColor3 = UI_CONFIG.THEME_TEXT_SECONDARY
				statusLabel.TextSize = 9
				statusLabel.Font = Enum.Font.GothamMedium
				statusLabel.TextXAlignment = Enum.TextXAlignment.Right
				statusLabel.TextTransparency = 0
				statusLabel.Parent = row

				local arrowLabel = Instance.new("TextLabel")
				arrowLabel.Name = "Arrow"
				arrowLabel.Size = UDim2.new(0, 1, 1, 0)
				arrowLabel.Position = UDim2.new(1, -1, 0, 0)
				arrowLabel.BackgroundTransparency = 1
				arrowLabel.Visible = false
				arrowLabel.Parent = row
			end

			row.Visible = true
			row.LayoutOrder = i

			local iconChip = row:FindFirstChild("IconChip")
			local iconLabel = iconChip and iconChip:FindFirstChild("Icon")
			local nameLabel = row:FindFirstChild("ItemName")
			local countLabel = row:FindFirstChild("Count")
			local progressBarBg = row:FindFirstChild("ProgressBarBg")
			local progressBarFill = progressBarBg and progressBarBg:FindFirstChild("ProgressBarFill")
			local statusLabel = row:FindFirstChild("Status")
			local arrowLabel = row:FindFirstChild("Arrow")

			-- Map objective index to a specific color/icon
			local colors = {
				UI_CONFIG.STROKE_COLOR, -- Cyan
				UI_CONFIG.THEME_ACCENT_PINK,
				UI_CONFIG.THEME_ACCENT_GOLD,
				UI_CONFIG.THEME_ACCENT_PURPLE,
				UI_CONFIG.MONEY_COLOR
			}
			local icons = {"📦", "🔨", "⚙️", "💰", "📈"}
			local color = colors[((i - 1) % #colors) + 1]
			local iconText = icons[((i - 1) % #icons) + 1]

			if iconChip then
				iconChip.BackgroundColor3 = color
			end
			
			if row then
				row.BackgroundColor3 = color
				local stroke = row:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = color
				end
			end

			if iconLabel then
				iconLabel.Text = iconText
				iconLabel.TextColor3 = Color3.new(1, 1, 1) -- White icon
			end
			if nameLabel then
				nameLabel.Text = tostring(def.Title or def.Id)
				-- Text is white based on initialization, leaving it white.
			end
			if countLabel then
				countLabel.Text = string.format("%d/%d", progress, target)
			end
			if progressBarBg then
				progressBarBg.Visible = true
				if progressBarFill then
					local fillPct = math.clamp(progress / target, 0, 1)
					local fillTween = TweenService:Create(progressBarFill, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
						Size = UDim2.new(fillPct, 0, 1, 0),
						BackgroundColor3 = color
					})
					fillTween:Play()
				end
			end
			if statusLabel then
				statusLabel.Text = completed and "DONE" or "IN PROGRESS"
				statusLabel.TextColor3 = completed and UI_CONFIG.ARROW_UP_COLOR or color
			end
		end

		return
	end

	if holdingsTitle then
		holdingsTitle.Text = "Your Top Holdings"
	end
	if emptyLabel then
		emptyLabel.Text = "No items in storage"
	end

	-- Get sector rates
	local sectorRates = getSectorRates()

	updateRateCache()

	-- Build sorted list by total value
	local sortedItems = {}
	for itemId, count in pairs(StorageItems) do
		if count > 0 then
			local itemDef = ItemConfig.Items[itemId]
			if itemDef then
				local sector = ItemConfig.GetSectorByItemId(itemId)
				local rate = sectorRates[sector] or 1.0
				local totalValue = count * itemDef.basePrice * rate
				local itemRate = calculateItemRate(itemId)
				table.insert(sortedItems, {
					id = itemId,
					count = count,
					icon = itemDef.icon or "📦",
					name = itemDef.displayName or itemId,
					value = totalValue,
					itemRate = itemRate,
					rate = rate,
				})
			end
		end
	end

	table.sort(sortedItems, function(a, b)
		return a.value > b.value
	end)

	if emptyLabel then
		emptyLabel.Visible = #sortedItems == 0
	end

	for i = 1, math.min(UI_CONFIG.MAX_HOLDINGS_ROWS, #sortedItems) do
		local data = sortedItems[i]

		local row = holdingsList:FindFirstChild("Row" .. i)
		if not row then
			row = Instance.new("Frame")
			row.Name = "Row" .. i
			row.Size = UDim2.new(1, 0, 0, UI_CONFIG.ROW_HEIGHT)
			row.BackgroundTransparency = 1
			row.LayoutOrder = i
			row.Parent = holdingsList

			-- Icon
			local iconLabel = Instance.new("TextLabel")
			iconLabel.Name = "Icon"
			iconLabel.Size = UDim2.new(0, 18, 1, 0)
			iconLabel.Position = UDim2.new(0, 0, 0, 0)
			iconLabel.BackgroundTransparency = 1
			iconLabel.TextSize = 12
			iconLabel.Font = Enum.Font.Gotham
			iconLabel.Parent = row

			-- Name (truncated)
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Name = "ItemName"
			nameLabel.Size = UDim2.new(0, 60, 1, 0)
			nameLabel.Position = UDim2.new(0, 20, 0, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.TextColor3 = UI_CONFIG.HOLDINGS_NAME_COLOR
			nameLabel.TextSize = 10
			nameLabel.Font = Enum.Font.Gotham
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.Parent = row

			-- Count
			local countLabel = Instance.new("TextLabel")
			countLabel.Name = "Count"
			countLabel.Size = UDim2.new(0, 30, 1, 0)
			countLabel.Position = UDim2.new(0, 82, 0, 0)
			countLabel.BackgroundTransparency = 1
			countLabel.TextColor3 = UI_CONFIG.HOLDINGS_COUNT_COLOR
			countLabel.TextSize = 10
			countLabel.Font = Enum.Font.Gotham
			countLabel.TextXAlignment = Enum.TextXAlignment.Right
			countLabel.Parent = row

			-- Item Rate (replaces total value)
			local valueLabel = Instance.new("TextLabel")
			valueLabel.Name = "Value"
			valueLabel.Size = UDim2.new(0, 50, 1, 0)
			valueLabel.Position = UDim2.new(0, 115, 0, 0)
			valueLabel.BackgroundTransparency = 1
			valueLabel.TextColor3 = UI_CONFIG.HOLDINGS_VALUE_COLOR
			valueLabel.TextSize = 10
			valueLabel.Font = Enum.Font.GothamBold
			valueLabel.TextXAlignment = Enum.TextXAlignment.Right
			valueLabel.Parent = row

			-- Arrow (▲ if rate >= 1, ▼ if < 1)
			local arrowLabel = Instance.new("TextLabel")
			arrowLabel.Name = "Arrow"
			arrowLabel.Size = UDim2.new(0, 14, 1, 0)
			arrowLabel.Position = UDim2.new(0, 168, 0, 0)
			arrowLabel.BackgroundTransparency = 1
			arrowLabel.TextSize = 10
			arrowLabel.Font = Enum.Font.GothamBold
			arrowLabel.Parent = row
		end

		row.Visible = true

		-- Update layout order just in case it got mixed up somehow
		row.LayoutOrder = i

		local iconLabel = row:FindFirstChild("Icon")
		if iconLabel then
			iconLabel.Text = data.icon
		end

		local nameLabel = row:FindFirstChild("ItemName")
		if nameLabel then
			local displayName = data.name
			if #displayName > 10 then
				displayName = string.sub(displayName, 1, 9) .. "…"
			end
			nameLabel.Text = displayName
		end

		local countLabel = row:FindFirstChild("Count")
		if countLabel then
			countLabel.Text = "x" .. tostring(data.count)
		end

		local valueLabel = row:FindFirstChild("Value")
		if valueLabel then
			valueLabel.Text = string.format("+%.1f/s", data.itemRate)
		end

		local arrowLabel = row:FindFirstChild("Arrow")
		if arrowLabel then
			arrowLabel.Visible = true
			if data.rate >= 1.0 then
				arrowLabel.Text = "▲"
				arrowLabel.TextColor3 = UI_CONFIG.ARROW_UP_COLOR
			else
				arrowLabel.Text = "▼"
				arrowLabel.TextColor3 = UI_CONFIG.ARROW_DOWN_COLOR
			end
		end
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("MoneyHUD: Initializing...")

	MoneyHUDGui = createMoneyHUD()
	MoneyHUDGui.Parent = PlayerGui

	-- Get references
	local hudPanel = MoneyHUDGui:FindFirstChild("HUDPanel")
	if hudPanel then
		local moneyContainer = hudPanel:FindFirstChild("MoneyContainer")
		if moneyContainer then
			MoneyLabel = moneyContainer:FindFirstChild("MoneyLabel")
			MoneyDeltaLabel = moneyContainer:FindFirstChild("MoneyDeltaLabel")
			BraincellsLabel = moneyContainer:FindFirstChild("BraincellsLabel")
		end

		local itemsContainer = hudPanel:FindFirstChild("ItemsContainer")
		if itemsContainer then
			ItemsAmountLabel = itemsContainer:FindFirstChild("ItemsAmount")
			MarketStatusLabel = itemsContainer:FindFirstChild("MarketStatus")
			MarketOpportunityLabel = itemsContainer:FindFirstChild("MarketOpportunity")
			NextGoalLabel = itemsContainer:FindFirstChild("NextGoal")
			NextUnlockLabel = itemsContainer:FindFirstChild("NextUnlock")
			local itemsBarBg = itemsContainer:FindFirstChild("ItemsBarBg")
			if itemsBarBg then
				ItemsBarFill = itemsBarBg:FindFirstChild("ItemsBarFill")
			end
		end
	end

	local function refreshHudState()
		updateBottomBarLayout()
		refreshBottomBarButtonVisuals(true)
		updateMarketStatusDisplay()
		updateNextGoalDisplay()
		updateNextUnlockDisplay()
		updateHoldingsDisplay()
	end

	----------------------------------------------------------------------
	-- BUTTON CONNECTIONS (Bottom Bar)
	----------------------------------------------------------------------
	local bottomBar = MoneyHUDGui:FindFirstChild("BottomBar")
	if bottomBar then
		local function setupBtn(config)
			local buttonsFrame = bottomBar:FindFirstChild("ButtonsFrame")
			local btn = BottomBarButtons[config.name] or (buttonsFrame and buttonsFrame:FindFirstChild(config.name))
			if not btn then
				return
			end

			local toggleEvent = ensureToggleEvent(config.eventName)
			btn:SetAttribute("Hovered", false)
			btn:SetAttribute("Pressed", false)

			btn.MouseButton1Click:Connect(function()
				if config.name == "StockButton" and Player:GetAttribute("DetailedMarketUnlocked") ~= true then
					pcall(function()
						SellAllFunction:InvokeServer()
					end)
					return
				end

				if config.filterArg then
					toggleEvent:Fire(config.filterArg)
				else
					toggleEvent:Fire()
				end
			end)

			btn.MouseEnter:Connect(function()
				btn:SetAttribute("Hovered", true)
				tweenBarButtonVisual(btn, config)
			end)
			btn.MouseButton1Down:Connect(function()
				btn:SetAttribute("Pressed", true)
				tweenBarButtonVisual(btn, config)
			end)
			btn.MouseButton1Up:Connect(function()
				btn:SetAttribute("Pressed", false)
				tweenBarButtonVisual(btn, config)
			end)
			btn.MouseLeave:Connect(function()
				btn:SetAttribute("Hovered", false)
				btn:SetAttribute("Pressed", false)
				tweenBarButtonVisual(btn, config)
			end)

			tweenBarButtonVisual(btn, config, true)
		end

		for _, config in ipairs(BOTTOM_BAR_ACTIONS) do
			setupBtn(config)
		end

		local buildToggle = ensureToggleEvent("BuildModeToggleEvent")
		local buildBtn = BottomBarButtons["BuildButton"]
		if buildBtn then
			buildToggle.Event:Connect(function()
				IsBuildOpen = not IsBuildOpen
				refreshBottomBarButtonVisuals()
			end)
		end

		local function attachViewportListener(camera)
			if BottomBarViewportConnection then
				BottomBarViewportConnection:Disconnect()
				BottomBarViewportConnection = nil
			end

			if camera then
				BottomBarViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
					updateBottomBarLayout()
				end)
			end

			updateBottomBarLayout()
		end

		if BottomBarCameraConnection then
			BottomBarCameraConnection:Disconnect()
			BottomBarCameraConnection = nil
		end

		BottomBarCameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			attachViewportListener(workspace.CurrentCamera)
		end)

		attachViewportListener(workspace.CurrentCamera)
		refreshHudState()
	end

	----------------------------------------------------------------------
	-- OWNERSHIP / MPS (unchanged logic)
	----------------------------------------------------------------------
	local ownershipData = GetOwnershipRemote:InvokeServer()
	if ownershipData and ownershipData.units then
		for unitName, data in ownershipData.units do
			OwnedCounts[unitName] = data.count
		end
		updateMPSDisplay()
		updateBrainrotCount()
	end

	OwnershipChangedEvent.OnClientEvent:Connect(function(unitName: string, newCount: number)
		OwnedCounts[unitName] = newCount
		updateMPSDisplay()
		updateBrainrotCount()
		updateMarketStatusDisplay()
		updateNextGoalDisplay()
		updateHoldingsDisplay()
	end)

	----------------------------------------------------------------------
	-- MONEY TRACKING
	----------------------------------------------------------------------
	local leaderstats = Player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local money = leaderstats:WaitForChild("Money", 5)
		if money then
			previousMoney = money.Value
			updateMoneyDisplay(money.Value)
			money:GetPropertyChangedSignal("Value"):Connect(function()
				updateMoneyDisplay(money.Value)
			end)
			print("MoneyHUD: Connected to money value")
		else
			warn("MoneyHUD: Could not find Money value")
		end

		local braincells = leaderstats:FindFirstChild("Braincells")
		if braincells then
			updateBraincellsDisplay(braincells.Value)
			braincells:GetPropertyChangedSignal("Value"):Connect(function()
				updateBraincellsDisplay(braincells.Value)
			end)
		else
			warn("MoneyHUD: Could not find Braincells value")
		end
	else
		warn("MoneyHUD: Could not find leaderstats")
	end

	----------------------------------------------------------------------
	-- STORAGE + HOLDINGS
	----------------------------------------------------------------------
	local function decodeItems(encoded)
		if not ItemConfig or not ItemConfig.SHORT_TO_ID then
			return encoded
		end
		if type(encoded) ~= "table" then
			return encoded
		end
		local decoded = {}
		for k, count in pairs(encoded) do
			local shortId = tonumber(k)
			if shortId and ItemConfig.SHORT_TO_ID[shortId] then
				decoded[ItemConfig.SHORT_TO_ID[shortId]] = count
			else
				decoded[k] = count
			end
		end
		return decoded
	end

	local function refreshFromAttribute()
		local items, total, cap = GetStorageFunction:InvokeServer()
		StorageItems = decodeItems(items) or {}
		updateItemsDisplay(total or 0, Player:GetAttribute("StorageCapacity") or cap or 0)
		updateMarketStatusDisplay()
		updateHoldingsDisplay()
	end

	if StorageUpdatedEvent then
		StorageUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
			items = decodeItems(items)
			StorageItems = items or {}
			updateItemsDisplay(total or 0, Player:GetAttribute("StorageCapacity") or capacity or 0)
			updateMarketStatusDisplay()
			updateHoldingsDisplay()
		end)
	end

	CartController.OnChanged(function()
		updateMarketStatusDisplay()
	end)

	Player:GetAttributeChangedSignal("StorageCapacity"):Connect(function()
		local cur = 0
		if ItemsAmountLabel then
			local txt = ItemsAmountLabel.Text
			local val = txt:match("ITEMS IN STORAGE: (%d+)")
			cur = tonumber(val) or 0
		end
		updateItemsDisplay(cur, Player:GetAttribute("StorageCapacity") or 0)
	end)

	-- Listen for stock market rate changes to refresh holdings values
	if not StockMarketFolder then
		StockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket")
	end
	if StockMarketFolder then
		StockMarketFolder:GetAttributeChangedSignal("SectorRates"):Connect(function()
			updateHoldingsDisplay()
		end)
		StockMarketFolder:GetAttributeChangedSignal("LocalItemRates"):Connect(function()
			updateMarketStatusDisplay()
			updateHoldingsDisplay()
		end)
		StockMarketFolder:GetAttributeChangedSignal("CurrentRate"):Connect(function()
			updateMarketStatusDisplay()
		end)
	end

	local ok, snapshot = pcall(function()
		return GetAchievementsSnapshotFunction:InvokeServer()
	end)
	if ok and type(snapshot) == "table" then
		LatestAchievementSnapshot = snapshot
	end
	updateMarketStatusDisplay()
	updateNextGoalDisplay()
	updateNextUnlockDisplay()
	updateHoldingsDisplay()

	AchievementUpdatedEvent.OnClientEvent:Connect(function(snapshotData)
		if type(snapshotData) ~= "table" then
			return
		end
		LatestAchievementSnapshot = snapshotData
		updateHoldingsDisplay()
	end)

	for _, attrName in ipairs({
		"TutorialComplete",
		"MarketIntelUnlocked",
		"DetailedMarketUnlocked",
		"TerminalIntroComplete",
		"ManualLogisticsUnlocked",
		"SynergyUnlocked",
		"FirstSynergyActivated",
		"ArtifactsUnlocked",
		"FirstArtifactFound",
		"FirstArtifactEquipped",
		"NextGoalName",
		"NextGoalProgress",
		"NextGoalTarget",
		"NextUnlockName",
		"NextUnlockDescription",
		"NextUnlockProgress",
		"NextUnlockTarget",
	}) do
		Player:GetAttributeChangedSignal(attrName):Connect(function()
			refreshHudState()
		end)
	end

	-- Watch ActiveBrainrot units to update cache instantly on mode change
	local updatePending = false
	local function requestHoldingsUpdate()
		if updatePending then
			return
		end
		updatePending = true
		task.delay(0.1, function()
			updatePending = false
			lastRateUpdate = 0
			updateMarketStatusDisplay()
			updateNextGoalDisplay()
			updateHoldingsDisplay()
		end)
	end

	local unitConnections = {}
	local function onUnitAdded(unit)
		if unitConnections[unit] then
			return
		end
		unitConnections[unit] = {
			unit:GetAttributeChangedSignal("CurrentProducing"):Connect(requestHoldingsUpdate),
			unit:GetAttributeChangedSignal("CurrentMode"):Connect(requestHoldingsUpdate),
			unit:GetAttributeChangedSignal("IncomeInterval"):Connect(requestHoldingsUpdate),
			unit:GetAttributeChangedSignal("OwnerId"):Connect(requestHoldingsUpdate),
		}
	end

	local function onUnitRemoved(unit)
		if unitConnections[unit] then
			for _, conn in unitConnections[unit] do
				conn:Disconnect()
			end
			unitConnections[unit] = nil
		end
		requestHoldingsUpdate()
	end

	for _, unit in CollectionService:GetTagged("ActiveBrainrot") do
		onUnitAdded(unit)
	end
	CollectionService:GetInstanceAddedSignal("ActiveBrainrot"):Connect(onUnitAdded)
	CollectionService:GetInstanceRemovedSignal("ActiveBrainrot"):Connect(onUnitRemoved)

	-- Initial fetch
	task.spawn(refreshFromAttribute)

	print("MoneyHUD: Ready!")
end

-- Start
initialize()
