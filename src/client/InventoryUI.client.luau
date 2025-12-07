--[[
	InventoryUI LocalScript
	
	Displays the player's brainrot inventory with RNG rarity tabs.
	Allows placing inactive brainrots and removing active ones.
	
	Features:
	- Tabbed interface by rarity (Normal, Spicy, Galaxy)
	- Stacked display per unit type within each rarity
	- Place/Remove buttons per stack
	- Real-time updates
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Player reference
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Wait for remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local GetInventoryRemote = RemoteEvents:WaitForChild("GetInventory")
local PlaceBrainrotRemote = RemoteEvents:WaitForChild("PlaceBrainrot")
local RemoveBrainrotRemote = RemoteEvents:WaitForChild("RemoveBrainrot")
local InventoryChangedEvent = RemoteEvents:WaitForChild("InventoryChanged")

--------------------------------------------------------------------------------
-- UI CONFIGURATION
--------------------------------------------------------------------------------

local UI_CONFIG = {
	-- Panel styling
	PANEL_WIDTH = 340,
	PANEL_PADDING = 12,
	TAB_HEIGHT = 36,
	
	-- Item styling
	ITEM_HEIGHT = 65,
	ITEM_SPACING = 6,
	CORNER_RADIUS = 10,
	
	-- Colors
	BACKGROUND_COLOR = Color3.fromRGB(25, 20, 35),
	PANEL_COLOR = Color3.fromRGB(40, 30, 55),
	ITEM_COLOR = Color3.fromRGB(55, 45, 75),
	ACCENT_COLOR = Color3.fromRGB(180, 100, 220),
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	SECONDARY_TEXT_COLOR = Color3.fromRGB(180, 180, 180),
	ACTIVE_COLOR = Color3.fromRGB(100, 220, 100),
	INACTIVE_COLOR = Color3.fromRGB(220, 180, 100),
	PLACE_BUTTON_COLOR = Color3.fromRGB(80, 180, 80),
	REMOVE_BUTTON_COLOR = Color3.fromRGB(180, 80, 80),
	DISABLED_COLOR = Color3.fromRGB(80, 70, 90),
	
	-- Rarity colors
	RARITY_COLORS = {
		Normal = Color3.fromRGB(180, 180, 180),
		Spicy = Color3.fromRGB(255, 80, 80),
		Galaxy = Color3.fromRGB(180, 100, 255),
	},
	
	-- Rarity tab colors (darker for background)
	RARITY_TAB_COLORS = {
		Normal = Color3.fromRGB(80, 80, 90),
		Spicy = Color3.fromRGB(120, 50, 50),
		Galaxy = Color3.fromRGB(90, 50, 130),
	},
	
	-- Animation
	TWEEN_TIME = 0.2,
}

-- Rarity display names
local RARITY_DISPLAY = {
	Normal = "Normal",
	Spicy = "🌶️ Spicy",
	Galaxy = "🌌 Galaxy",
}

local RARITY_ORDER = {"Normal", "Spicy", "Galaxy"}

--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

-- Track inventory locally for UI updates
-- Structure: {[unitName]: {[rarity]: {total: number, active: number}}}
local InventoryData: {[string]: {[string]: {total: number, active: number}}} = {}
local InventoryItems: {[string]: {[string]: Frame}} = {} -- [rarity][unitName]
local InventoryGui: ScreenGui? = nil
local TabButtons: {[string]: TextButton} = {}
local TabContents: {[string]: ScrollingFrame} = {}
local CurrentTab = "Normal"
local InventoryVisible = false

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

--------------------------------------------------------------------------------
-- TAB SWITCHING
--------------------------------------------------------------------------------

local function switchTab(rarity: string)
	CurrentTab = rarity
	
	-- Update tab button appearance
	for tabRarity, button in TabButtons do
		if tabRarity == rarity then
			button.BackgroundColor3 = UI_CONFIG.RARITY_COLORS[tabRarity]
			button.BackgroundTransparency = 0
		else
			button.BackgroundColor3 = UI_CONFIG.RARITY_TAB_COLORS[tabRarity]
			button.BackgroundTransparency = 0.3
		end
	end
	
	-- Show/hide tab contents
	for tabRarity, scrollFrame in TabContents do
		scrollFrame.Visible = (tabRarity == rarity)
	end
end

--------------------------------------------------------------------------------
-- INVENTORY UI CREATION
--------------------------------------------------------------------------------

local function createInventoryGui(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InventoryUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	-- Main inventory panel (left side) - starts HIDDEN (off-screen)
	local inventoryPanel = Instance.new("Frame")
	inventoryPanel.Name = "InventoryPanel"
	inventoryPanel.Size = UDim2.new(0, UI_CONFIG.PANEL_WIDTH, 0.85, 0)
	inventoryPanel.Position = UDim2.new(0, -UI_CONFIG.PANEL_WIDTH - 10, 0.075, 0)
	inventoryPanel.BackgroundColor3 = UI_CONFIG.PANEL_COLOR
	inventoryPanel.BorderSizePixel = 0
	inventoryPanel.Parent = screenGui
	addCorner(inventoryPanel, UI_CONFIG.CORNER_RADIUS)
	addStroke(inventoryPanel, UI_CONFIG.ACCENT_COLOR, 2)
	
	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 44)
	titleBar.BackgroundColor3 = UI_CONFIG.BACKGROUND_COLOR
	titleBar.BorderSizePixel = 0
	titleBar.Parent = inventoryPanel
	addCorner(titleBar, UI_CONFIG.CORNER_RADIUS)
	
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -50, 1, 0)
	titleLabel.Position = UDim2.new(0, 12, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "🧠 BRAINROT INVENTORY"
	titleLabel.TextColor3 = UI_CONFIG.ACCENT_COLOR
	titleLabel.TextSize = 18
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleBar
	
	-- Close button (X)
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 32, 0, 32)
	closeButton.Position = UDim2.new(1, -38, 0.5, -16)
	closeButton.BackgroundColor3 = UI_CONFIG.REMOVE_BUTTON_COLOR
	closeButton.Text = "✕"
	closeButton.TextColor3 = UI_CONFIG.TEXT_COLOR
	closeButton.TextSize = 16
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Parent = titleBar
	addCorner(closeButton, 6)
	
	-- Tab bar container
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, 0, 0, UI_CONFIG.TAB_HEIGHT)
	tabBar.Position = UDim2.new(0, 0, 0, 44)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = inventoryPanel
	
	-- Create tabs for each rarity
	local tabWidth = 1 / #RARITY_ORDER
	for i, rarity in RARITY_ORDER do
		local tabButton = Instance.new("TextButton")
		tabButton.Name = rarity .. "Tab"
		tabButton.Size = UDim2.new(tabWidth, -2, 1, -4)
		tabButton.Position = UDim2.new((i - 1) * tabWidth, 1, 0, 2)
		tabButton.BackgroundColor3 = UI_CONFIG.RARITY_TAB_COLORS[rarity]
		tabButton.BackgroundTransparency = rarity == "Normal" and 0 or 0.3
		tabButton.Text = RARITY_DISPLAY[rarity]
		tabButton.TextColor3 = UI_CONFIG.TEXT_COLOR
		tabButton.TextSize = 12
		tabButton.Font = Enum.Font.GothamBold
		tabButton.Parent = tabBar
		addCorner(tabButton, 6)
		
		TabButtons[rarity] = tabButton
		
		-- Tab click handler
		tabButton.MouseButton1Click:Connect(function()
			switchTab(rarity)
		end)
		
		-- Create scroll frame for this tab
		local scrollFrame = Instance.new("ScrollingFrame")
		scrollFrame.Name = rarity .. "Content"
		scrollFrame.Size = UDim2.new(1, -UI_CONFIG.PANEL_PADDING * 2, 1, -44 - UI_CONFIG.TAB_HEIGHT - 10)
		scrollFrame.Position = UDim2.new(0, UI_CONFIG.PANEL_PADDING, 0, 44 + UI_CONFIG.TAB_HEIGHT + 5)
		scrollFrame.BackgroundTransparency = 1
		scrollFrame.BorderSizePixel = 0
		scrollFrame.ScrollBarThickness = 5
		scrollFrame.ScrollBarImageColor3 = UI_CONFIG.RARITY_COLORS[rarity]
		scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
		scrollFrame.Visible = (rarity == "Normal")
		scrollFrame.Parent = inventoryPanel
		
		TabContents[rarity] = scrollFrame
		InventoryItems[rarity] = {}
		
		-- Layout for items
		local listLayout = Instance.new("UIListLayout")
		listLayout.Name = "Layout"
		listLayout.SortOrder = Enum.SortOrder.Name
		listLayout.Padding = UDim.new(0, UI_CONFIG.ITEM_SPACING)
		listLayout.Parent = scrollFrame
		
		-- Auto-resize canvas
		listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
		end)
		
		-- Empty state message
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Name = "EmptyLabel"
		emptyLabel.Size = UDim2.new(1, 0, 0, 50)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Text = "No " .. rarity .. " brainrots yet..."
		emptyLabel.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
		emptyLabel.TextSize = 14
		emptyLabel.Font = Enum.Font.GothamMedium
		emptyLabel.Parent = scrollFrame
	end
	
	-- Set Normal tab as initially active
	if TabButtons["Normal"] then
		TabButtons["Normal"].BackgroundColor3 = UI_CONFIG.RARITY_COLORS["Normal"]
		TabButtons["Normal"].BackgroundTransparency = 0
	end
	
	return screenGui
end

local function createInventoryItem(unitName: string, rarity: string, total: number, active: number): Frame
	local inactive = total - active
	local rarityColor = UI_CONFIG.RARITY_COLORS[rarity] or UI_CONFIG.TEXT_COLOR
	
	local item = Instance.new("Frame")
	item.Name = unitName
	item.Size = UDim2.new(1, 0, 0, UI_CONFIG.ITEM_HEIGHT)
	item.BackgroundColor3 = UI_CONFIG.ITEM_COLOR
	item.BorderSizePixel = 0
	addCorner(item, 8)
	addStroke(item, rarityColor, 1)
	
	-- Icon with rarity color
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(0, 36, 0, 36)
	iconLabel.Position = UDim2.new(0, 8, 0.5, -18)
	iconLabel.BackgroundColor3 = UI_CONFIG.BACKGROUND_COLOR
	iconLabel.Text = "🧠"
	iconLabel.TextSize = 20
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextColor3 = rarityColor
	iconLabel.Parent = item
	addCorner(iconLabel, 6)
	
	-- Unit name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "UnitName"
	nameLabel.Size = UDim2.new(1, -150, 0, 20)
	nameLabel.Position = UDim2.new(0, 50, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = unitName
	nameLabel.TextColor3 = rarityColor
	nameLabel.TextSize = 13
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = item
	
	-- Status label (X/Y Active)
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(0, 90, 0, 16)
	statusLabel.Position = UDim2.new(0, 50, 0, 26)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = string.format("%d/%d Active", active, total)
	statusLabel.TextColor3 = active > 0 and UI_CONFIG.ACTIVE_COLOR or UI_CONFIG.SECONDARY_TEXT_COLOR
	statusLabel.TextSize = 11
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = item
	
	-- Inactive count label
	local inactiveLabel = Instance.new("TextLabel")
	inactiveLabel.Name = "Inactive"
	inactiveLabel.Size = UDim2.new(0, 80, 0, 16)
	inactiveLabel.Position = UDim2.new(0, 50, 0, 42)
	inactiveLabel.BackgroundTransparency = 1
	inactiveLabel.Text = inactive > 0 and string.format("%d stored", inactive) or "All placed"
	inactiveLabel.TextColor3 = inactive > 0 and UI_CONFIG.INACTIVE_COLOR or UI_CONFIG.SECONDARY_TEXT_COLOR
	inactiveLabel.TextSize = 10
	inactiveLabel.Font = Enum.Font.Gotham
	inactiveLabel.TextXAlignment = Enum.TextXAlignment.Left
	inactiveLabel.Parent = item
	
	-- Button container
	local buttonContainer = Instance.new("Frame")
	buttonContainer.Name = "Buttons"
	buttonContainer.Size = UDim2.new(0, 80, 0, 46)
	buttonContainer.Position = UDim2.new(1, -88, 0.5, -23)
	buttonContainer.BackgroundTransparency = 1
	buttonContainer.Parent = item
	
	-- Place button
	local placeButton = Instance.new("TextButton")
	placeButton.Name = "PlaceButton"
	placeButton.Size = UDim2.new(1, 0, 0, 20)
	placeButton.Position = UDim2.new(0, 0, 0, 0)
	placeButton.BackgroundColor3 = inactive > 0 and UI_CONFIG.PLACE_BUTTON_COLOR or UI_CONFIG.DISABLED_COLOR
	placeButton.Text = "➕ Place"
	placeButton.TextColor3 = UI_CONFIG.TEXT_COLOR
	placeButton.TextSize = 10
	placeButton.Font = Enum.Font.GothamBold
	placeButton.Active = inactive > 0
	placeButton.Parent = buttonContainer
	addCorner(placeButton, 4)
	
	-- Remove button
	local removeButton = Instance.new("TextButton")
	removeButton.Name = "RemoveButton"
	removeButton.Size = UDim2.new(1, 0, 0, 20)
	removeButton.Position = UDim2.new(0, 0, 0, 24)
	removeButton.BackgroundColor3 = active > 0 and UI_CONFIG.REMOVE_BUTTON_COLOR or UI_CONFIG.DISABLED_COLOR
	removeButton.Text = "➖ Remove"
	removeButton.TextColor3 = UI_CONFIG.TEXT_COLOR
	removeButton.TextSize = 10
	removeButton.Font = Enum.Font.GothamBold
	removeButton.Active = active > 0
	removeButton.Parent = buttonContainer
	addCorner(removeButton, 4)
	
	return item
end

--------------------------------------------------------------------------------
-- UI LOGIC
--------------------------------------------------------------------------------

local function updateItemDisplay(item: Frame, total: number, active: number)
	local inactive = total - active
	
	-- Update status
	local statusLabel = item:FindFirstChild("Status")
	if statusLabel then
		statusLabel.Text = string.format("%d/%d Active", active, total)
		statusLabel.TextColor3 = active > 0 and UI_CONFIG.ACTIVE_COLOR or UI_CONFIG.SECONDARY_TEXT_COLOR
	end
	
	-- Update inactive label
	local inactiveLabel = item:FindFirstChild("Inactive")
	if inactiveLabel then
		inactiveLabel.Text = inactive > 0 and string.format("%d stored", inactive) or "All placed"
		inactiveLabel.TextColor3 = inactive > 0 and UI_CONFIG.INACTIVE_COLOR or UI_CONFIG.SECONDARY_TEXT_COLOR
	end
	
	-- Update buttons
	local buttonContainer = item:FindFirstChild("Buttons")
	if buttonContainer then
		local placeButton = buttonContainer:FindFirstChild("PlaceButton")
		if placeButton then
			placeButton.Active = inactive > 0
			placeButton.BackgroundColor3 = inactive > 0 and UI_CONFIG.PLACE_BUTTON_COLOR or UI_CONFIG.DISABLED_COLOR
		end
		
		local removeButton = buttonContainer:FindFirstChild("RemoveButton")
		if removeButton then
			removeButton.Active = active > 0
			removeButton.BackgroundColor3 = active > 0 and UI_CONFIG.REMOVE_BUTTON_COLOR or UI_CONFIG.DISABLED_COLOR
		end
	end
end

local function setupItemButtons(item: Frame, unitName: string, rarity: string)
	local buttonContainer = item:FindFirstChild("Buttons")
	if not buttonContainer then return end
	
	local placeButton = buttonContainer:FindFirstChild("PlaceButton")
	local removeButton = buttonContainer:FindFirstChild("RemoveButton")
	local debounce = false
	
	if placeButton then
		placeButton.MouseButton1Click:Connect(function()
			if debounce or not placeButton.Active then return end
			debounce = true
			
			local success, message = PlaceBrainrotRemote:InvokeServer(unitName, rarity)
			if not success then
				warn("Place failed: " .. tostring(message))
			end
			
			task.wait(0.2)
			debounce = false
		end)
		
		-- Hover effects
		placeButton.MouseEnter:Connect(function()
			if placeButton.Active then
				TweenService:Create(placeButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(100, 200, 100)
				}):Play()
			end
		end)
		
		placeButton.MouseLeave:Connect(function()
			local invData = InventoryData[unitName] and InventoryData[unitName][rarity]
			local inactive = invData and (invData.total - invData.active) or 0
			TweenService:Create(placeButton, TweenInfo.new(0.1), {
				BackgroundColor3 = inactive > 0 and UI_CONFIG.PLACE_BUTTON_COLOR or UI_CONFIG.DISABLED_COLOR
			}):Play()
		end)
	end
	
	if removeButton then
		removeButton.MouseButton1Click:Connect(function()
			if debounce or not removeButton.Active then return end
			debounce = true
			
			local success, message = RemoveBrainrotRemote:InvokeServer(unitName, rarity)
			if not success then
				warn("Remove failed: " .. tostring(message))
			end
			
			task.wait(0.2)
			debounce = false
		end)
		
		-- Hover effects
		removeButton.MouseEnter:Connect(function()
			if removeButton.Active then
				TweenService:Create(removeButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(200, 100, 100)
				}):Play()
			end
		end)
		
		removeButton.MouseLeave:Connect(function()
			local invData = InventoryData[unitName] and InventoryData[unitName][rarity]
			local active = invData and invData.active or 0
			TweenService:Create(removeButton, TweenInfo.new(0.1), {
				BackgroundColor3 = active > 0 and UI_CONFIG.REMOVE_BUTTON_COLOR or UI_CONFIG.DISABLED_COLOR
			}):Play()
		end)
	end
end

local function refreshInventoryUI()
	-- Process each rarity tab
	for _, rarity in RARITY_ORDER do
		local scrollFrame = TabContents[rarity]
		if not scrollFrame then continue end
		
		local hasItems = false
		
		-- Check all unit types
		for unitName, unitRarities in InventoryData do
			local data = unitRarities[rarity]
			
			if data and data.total > 0 then
				hasItems = true
				
				if not InventoryItems[rarity][unitName] then
					-- Create new item
					local item = createInventoryItem(unitName, rarity, data.total, data.active)
					item.Parent = scrollFrame
					InventoryItems[rarity][unitName] = item
					setupItemButtons(item, unitName, rarity)
				else
					-- Update existing
					updateItemDisplay(InventoryItems[rarity][unitName], data.total, data.active)
				end
			else
				-- Remove item if total is 0
				if InventoryItems[rarity][unitName] then
					InventoryItems[rarity][unitName]:Destroy()
					InventoryItems[rarity][unitName] = nil
				end
			end
		end
		
		-- Show/hide empty label
		local emptyLabel = scrollFrame:FindFirstChild("EmptyLabel")
		if emptyLabel then
			emptyLabel.Visible = not hasItems
		end
	end
end

--------------------------------------------------------------------------------
-- VISIBILITY CONTROL
--------------------------------------------------------------------------------

local PANEL_OPEN_POSITION = UDim2.new(0, 10, 0.075, 0)
local PANEL_CLOSED_POSITION = UDim2.new(0, -UI_CONFIG.PANEL_WIDTH - 10, 0.075, 0)

local function openInventory()
	if InventoryVisible then return end
	if not InventoryGui then return end
	local panel = InventoryGui:FindFirstChild("InventoryPanel")
	if not panel then return end
	
	InventoryVisible = true
	
	-- Refresh data from server
	local inventoryResult = GetInventoryRemote:InvokeServer()
	if inventoryResult and inventoryResult.units then
		for unitName, unitRarities in inventoryResult.units do
			if not InventoryData[unitName] then
				InventoryData[unitName] = {}
			end
			for rarity, data in unitRarities do
				InventoryData[unitName][rarity] = {
					total = data.total,
					active = data.active,
				}
			end
		end
		refreshInventoryUI()
	end
	
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = PANEL_OPEN_POSITION
	}):Play()
end

local function closeInventory()
	if not InventoryVisible then return end
	if not InventoryGui then return end
	local panel = InventoryGui:FindFirstChild("InventoryPanel")
	if not panel then return end
	
	InventoryVisible = false
	
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = PANEL_CLOSED_POSITION
	}):Play()
end

local function toggleInventory()
	if InventoryVisible then
		closeInventory()
	else
		openInventory()
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("InventoryUI: Initializing with RNG rarity tabs...")
	
	-- Create the inventory GUI
	InventoryGui = createInventoryGui()
	if not InventoryGui then return end
	
	-- Parent GUI
	InventoryGui.Parent = PlayerGui
	
	-- Listen for inventory updates from server
	InventoryChangedEvent.OnClientEvent:Connect(function(unitName: string, rarityData: {[string]: {total: number, active: number}})
		if not InventoryData[unitName] then
			InventoryData[unitName] = {}
		end
		
		-- Update all rarities for this unit
		for rarity, data in rarityData do
			InventoryData[unitName][rarity] = {
				total = data.total,
				active = data.active,
			}
		end
		
		if InventoryVisible then
			refreshInventoryUI()
		end
	end)
	
	-- Setup close button
	local panel = InventoryGui:FindFirstChild("InventoryPanel")
	if panel then
		local titleBar = panel:FindFirstChild("TitleBar")
		if titleBar then
			local closeButton = titleBar:FindFirstChild("CloseButton")
			if closeButton then
				closeButton.MouseButton1Click:Connect(closeInventory)
				
				-- Hover effects
				closeButton.MouseEnter:Connect(function()
					TweenService:Create(closeButton, TweenInfo.new(0.1), {
						BackgroundColor3 = Color3.fromRGB(220, 100, 100)
					}):Play()
				end)
				
				closeButton.MouseLeave:Connect(function()
					TweenService:Create(closeButton, TweenInfo.new(0.1), {
						BackgroundColor3 = UI_CONFIG.REMOVE_BUTTON_COLOR
					}):Play()
				end)
			end
		end
	end
	
	-- Setup 'I' key toggle
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == Enum.KeyCode.I then
			toggleInventory()
		end
	end)
	
	-- Setup BindableEvent listener for MoneyHUD button
	task.wait(0.5)
	
	local inventoryToggleEvent = ReplicatedStorage:FindFirstChild("InventoryToggleEvent")
	if not inventoryToggleEvent then
		inventoryToggleEvent = Instance.new("BindableEvent")
		inventoryToggleEvent.Name = "InventoryToggleEvent"
		inventoryToggleEvent.Parent = ReplicatedStorage
	end
	
	inventoryToggleEvent.Event:Connect(toggleInventory)
	
	print("InventoryUI: Ready! Press 'I' to toggle. Rarity tabs: Normal, Spicy, Galaxy")
end

-- Start
initialize()
