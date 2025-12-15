--[[
	TransportUI Client Script
	
	Handles the transport/vehicle selection UI for carrying items to market.
	
	Features:
	- Storage view with item list
	- Vehicle selection
	- "Load" and "Load Max" buttons
	- Backpack capacity display
	
	Opens when approaching the Storage on player plot.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Get player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Wait for remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")

-- Storage events
local StorageUpdatedEvent = RemoteEvents:WaitForChild("StorageUpdated")
local BackpackUpdatedEvent = RemoteEvents:WaitForChild("BackpackUpdated")
local GetStorageFunction = RemoteEvents:WaitForChild("GetStorage")
local GetBackpackFunction = RemoteEvents:WaitForChild("GetBackpack")

-- Transport events
local VehicleUpdatedEvent = RemoteEvents:WaitForChild("VehicleUpdated")
local LoadFromStorageFunction = RemoteFunctions:WaitForChild("LoadFromStorage")
local LoadMaxFromStorageFunction = RemoteFunctions:WaitForChild("LoadMaxFromStorage")
local GetVehicleInfoFunction = RemoteFunctions:WaitForChild("GetVehicleInfo")

-- Wait for ItemConfig
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

-- UI Colors (glassmorphism theme)
local COLORS = {
	background = Color3.fromRGB(15, 15, 25),
	panel = Color3.fromRGB(25, 25, 40),
	accent = Color3.fromRGB(100, 200, 255),
	accentDark = Color3.fromRGB(60, 140, 200),
	text = Color3.fromRGB(255, 255, 255),
	textMuted = Color3.fromRGB(150, 150, 170),
	success = Color3.fromRGB(100, 255, 150),
	warning = Color3.fromRGB(255, 200, 100),
	danger = Color3.fromRGB(255, 100, 100),
	itemBg = Color3.fromRGB(35, 35, 55),
}

-- State
local isOpen = false
local currentStorage = {}
local currentBackpack = {}
local storageCapacity = 2000
local storageUsage = 0
local backpackCapacity = 100
local backpackUsage = 0
local selectedVehicle = "Sneakers"

-- UI References
local screenGui = nil
local mainFrame = nil

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createScreenGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TransportUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = PlayerGui
	return gui
end

local function createMainFrame(parent)
	local frame = Instance.new("Frame")
	frame.Name = "MainFrame"
	frame.Size = UDim2.new(0, 700, 0, 500)
	frame.Position = UDim2.new(0.5, -350, 0.5, -250)
	frame.BackgroundColor3 = COLORS.background
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent
	
	-- Corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = frame
	
	-- Stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.accent
	stroke.Thickness = 2
	stroke.Transparency = 0.5
	stroke.Parent = frame
	
	return frame
end

local function createHeader(parent)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 50)
	header.BackgroundColor3 = COLORS.panel
	header.BackgroundTransparency = 0.3
	header.BorderSizePixel = 0
	header.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = header
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.new(0, 20, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "📦 STORAGE & TRANSPORT"
	title.TextColor3 = COLORS.text
	title.TextSize = 22
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header
	
	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -45, 0, 5)
	closeBtn.BackgroundColor3 = COLORS.danger
	closeBtn.BackgroundTransparency = 0.7
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = COLORS.text
	closeBtn.TextSize = 18
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = header
	
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn
	
	closeBtn.MouseButton1Click:Connect(function()
		closeUI()
	end)
	
	return header
end

local function createStoragePanel(parent)
	local panel = Instance.new("Frame")
	panel.Name = "StoragePanel"
	panel.Size = UDim2.new(0.5, -15, 1, -120)
	panel.Position = UDim2.new(0, 10, 0, 60)
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.5
	panel.BorderSizePixel = 0
	panel.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	
	-- Panel title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 30)
	title.Position = UDim2.new(0, 10, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "🏭 PLOT STORAGE"
	title.TextColor3 = COLORS.accent
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel
	
	-- Capacity bar
	local capacityBar = Instance.new("Frame")
	capacityBar.Name = "CapacityBar"
	capacityBar.Size = UDim2.new(1, -20, 0, 20)
	capacityBar.Position = UDim2.new(0, 10, 0, 45)
	capacityBar.BackgroundColor3 = COLORS.itemBg
	capacityBar.BorderSizePixel = 0
	capacityBar.Parent = panel
	
	local capCorner = Instance.new("UICorner")
	capCorner.CornerRadius = UDim.new(0, 6)
	capCorner.Parent = capacityBar
	
	local capacityFill = Instance.new("Frame")
	capacityFill.Name = "Fill"
	capacityFill.Size = UDim2.new(0, 0, 1, 0)
	capacityFill.BackgroundColor3 = COLORS.accent
	capacityFill.BorderSizePixel = 0
	capacityFill.Parent = capacityBar
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = capacityFill
	
	local capacityText = Instance.new("TextLabel")
	capacityText.Name = "Text"
	capacityText.Size = UDim2.new(1, 0, 1, 0)
	capacityText.BackgroundTransparency = 1
	capacityText.Text = "0 / 2000"
	capacityText.TextColor3 = COLORS.text
	capacityText.TextSize = 12
	capacityText.Font = Enum.Font.GothamBold
	capacityText.Parent = capacityBar
	
	-- Item list scroll
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemList"
	scrollFrame.Size = UDim2.new(1, -20, 1, -80)
	scrollFrame.Position = UDim2.new(0, 10, 0, 75)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLORS.accent
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = panel
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 5)
	listLayout.Parent = scrollFrame
	
	return panel
end

local function createBackpackPanel(parent)
	local panel = Instance.new("Frame")
	panel.Name = "BackpackPanel"
	panel.Size = UDim2.new(0.5, -15, 1, -120)
	panel.Position = UDim2.new(0.5, 5, 0, 60)
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.5
	panel.BorderSizePixel = 0
	panel.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	
	-- Panel title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 30)
	title.Position = UDim2.new(0, 10, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "🛵 TRANSPORT MODE"
	title.TextColor3 = COLORS.success
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel
	
	-- Capacity bar
	local capacityBar = Instance.new("Frame")
	capacityBar.Name = "CapacityBar"
	capacityBar.Size = UDim2.new(1, -20, 0, 20)
	capacityBar.Position = UDim2.new(0, 10, 0, 45)
	capacityBar.BackgroundColor3 = COLORS.itemBg
	capacityBar.BorderSizePixel = 0
	capacityBar.Parent = panel
	
	local capCorner = Instance.new("UICorner")
	capCorner.CornerRadius = UDim.new(0, 6)
	capCorner.Parent = capacityBar
	
	local capacityFill = Instance.new("Frame")
	capacityFill.Name = "Fill"
	capacityFill.Size = UDim2.new(0, 0, 1, 0)
	capacityFill.BackgroundColor3 = COLORS.success
	capacityFill.BorderSizePixel = 0
	capacityFill.Parent = capacityBar
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = capacityFill
	
	local capacityText = Instance.new("TextLabel")
	capacityText.Name = "Text"
	capacityText.Size = UDim2.new(1, 0, 1, 0)
	capacityText.BackgroundTransparency = 1
	capacityText.Text = "0 / 100"
	capacityText.TextColor3 = COLORS.text
	capacityText.TextSize = 12
	capacityText.Font = Enum.Font.GothamBold
	capacityText.Parent = capacityBar
	
	-- Item list scroll
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemList"
	scrollFrame.Size = UDim2.new(1, -20, 1, -80)
	scrollFrame.Position = UDim2.new(0, 10, 0, 75)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = COLORS.success
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = panel
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 5)
	listLayout.Parent = scrollFrame
	
	return panel
end

local function createBottomBar(parent)
	local bar = Instance.new("Frame")
	bar.Name = "BottomBar"
	bar.Size = UDim2.new(1, -20, 0, 50)
	bar.Position = UDim2.new(0, 10, 1, -55)
	bar.BackgroundColor3 = COLORS.panel
	bar.BackgroundTransparency = 0.5
	bar.BorderSizePixel = 0
	bar.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bar
	
	-- Load Max button
	local loadMaxBtn = Instance.new("TextButton")
	loadMaxBtn.Name = "LoadMaxButton"
	loadMaxBtn.Size = UDim2.new(0, 200, 0, 40)
	loadMaxBtn.Position = UDim2.new(0.5, -100, 0.5, -20)
	loadMaxBtn.BackgroundColor3 = COLORS.accent
	loadMaxBtn.Text = "📦 LOAD MAX"
	loadMaxBtn.TextColor3 = COLORS.text
	loadMaxBtn.TextSize = 16
	loadMaxBtn.Font = Enum.Font.GothamBold
	loadMaxBtn.Parent = bar
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = loadMaxBtn
	
	loadMaxBtn.MouseButton1Click:Connect(function()
		LoadMaxFromStorageFunction:InvokeServer()
	end)
	
	-- Hover effect
	loadMaxBtn.MouseEnter:Connect(function()
		TweenService:Create(loadMaxBtn, TweenInfo.new(0.2), {BackgroundColor3 = COLORS.accentDark}):Play()
	end)
	
	loadMaxBtn.MouseLeave:Connect(function()
		TweenService:Create(loadMaxBtn, TweenInfo.new(0.2), {BackgroundColor3 = COLORS.accent}):Play()
	end)
	
	return bar
end

local function createItemRow(parent, itemId, count, isStorage)
	local itemInfo = ItemConfig.Items[itemId] or {}
	local tierEmoji = {"⚪", "🟡", "🟠", "💎"}
	local emoji = tierEmoji[itemInfo.tier or 1] or "⚪"
	
	local row = Instance.new("Frame")
	row.Name = "Item_" .. itemId
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3 = COLORS.itemBg
	row.BackgroundTransparency = 0.3
	row.BorderSizePixel = 0
	row.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = row
	
	-- Item name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(0.5, -10, 1, 0)
	nameLabel.Position = UDim2.new(0, 10, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = emoji .. " " .. itemId
	nameLabel.TextColor3 = COLORS.text
	nameLabel.TextSize = 14
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = row
	
	-- Count
	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(0, 60, 1, 0)
	countLabel.Position = UDim2.new(0.5, 0, 0, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = "x" .. count
	countLabel.TextColor3 = COLORS.textMuted
	countLabel.TextSize = 14
	countLabel.Font = Enum.Font.GothamBold
	countLabel.Parent = row
	
	-- Load button (only for storage items)
	if isStorage then
		local loadBtn = Instance.new("TextButton")
		loadBtn.Name = "LoadButton"
		loadBtn.Size = UDim2.new(0, 60, 0, 28)
		loadBtn.Position = UDim2.new(1, -70, 0.5, -14)
		loadBtn.BackgroundColor3 = COLORS.accent
		loadBtn.Text = "LOAD"
		loadBtn.TextColor3 = COLORS.text
		loadBtn.TextSize = 12
		loadBtn.Font = Enum.Font.GothamBold
		loadBtn.Parent = row
		
		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 6)
		btnCorner.Parent = loadBtn
		
		loadBtn.MouseButton1Click:Connect(function()
			LoadFromStorageFunction:InvokeServer(itemId, 10) -- Load 10 at a time
		end)
	end
	
	return row
end

--------------------------------------------------------------------------------
-- UI UPDATE
--------------------------------------------------------------------------------

local function updateStoragePanel()
	if not mainFrame then return end
	
	local panel = mainFrame:FindFirstChild("StoragePanel")
	if not panel then return end
	
	local scrollFrame = panel:FindFirstChild("ItemList")
	if not scrollFrame then return end
	
	-- Clear existing items
	for _, child in scrollFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	
	-- Add items
	for itemId, count in pairs(currentStorage) do
		if count > 0 then
			createItemRow(scrollFrame, itemId, count, true)
		end
	end
	
	-- Update capacity bar
	local capacityBar = panel:FindFirstChild("CapacityBar")
	if capacityBar then
		local fill = capacityBar:FindFirstChild("Fill")
		local text = capacityBar:FindFirstChild("Text")
		
		local ratio = math.clamp(storageUsage / math.max(1, storageCapacity), 0, 1)
		
		if fill then
			TweenService:Create(fill, TweenInfo.new(0.3), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
			
			-- Color based on fullness
			local color = COLORS.accent
			if ratio > 0.9 then
				color = COLORS.danger
			elseif ratio > 0.7 then
				color = COLORS.warning
			end
			fill.BackgroundColor3 = color
		end
		
		if text then
			text.Text = string.format("%d / %d", storageUsage, storageCapacity)
		end
	end
end

local function updateBackpackPanel()
	if not mainFrame then return end
	
	local panel = mainFrame:FindFirstChild("BackpackPanel")
	if not panel then return end
	
	local scrollFrame = panel:FindFirstChild("ItemList")
	if not scrollFrame then return end
	
	-- Clear existing items
	for _, child in scrollFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	
	-- Add items
	for itemId, count in pairs(currentBackpack) do
		if count > 0 then
			createItemRow(scrollFrame, itemId, count, false)
		end
	end
	
	-- Update capacity bar
	local capacityBar = panel:FindFirstChild("CapacityBar")
	if capacityBar then
		local fill = capacityBar:FindFirstChild("Fill")
		local text = capacityBar:FindFirstChild("Text")
		
		local ratio = math.clamp(backpackUsage / math.max(1, backpackCapacity), 0, 1)
		
		if fill then
			TweenService:Create(fill, TweenInfo.new(0.3), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
			
			-- Color based on fullness
			local color = COLORS.success
			if ratio > 0.9 then
				color = COLORS.danger
			elseif ratio > 0.7 then
				color = COLORS.warning
			end
			fill.BackgroundColor3 = color
		end
		
		if text then
			text.Text = string.format("%d / %d", backpackUsage, backpackCapacity)
		end
	end
	
	-- Update title with vehicle name
	local title = panel:FindFirstChild("Title")
	if title then
		title.Text = "🛵 TRANSPORT: " .. string.upper(selectedVehicle)
	end
end

--------------------------------------------------------------------------------
-- OPEN/CLOSE
--------------------------------------------------------------------------------

local function openUI()
	if isOpen then return end
	isOpen = true
	
	-- Fetch latest data
	local storageItems, storageTotal, storageCap = GetStorageFunction:InvokeServer()
	currentStorage = storageItems or {}
	storageUsage = storageTotal or 0
	storageCapacity = storageCap or 2000
	
	local backpackItems, backpackTotal, backpackCap = GetBackpackFunction:InvokeServer()
	currentBackpack = backpackItems or {}
	backpackUsage = backpackTotal or 0
	backpackCapacity = backpackCap or 100
	
	-- Fetch vehicle info
	local vehicleInfo = GetVehicleInfoFunction:InvokeServer()
	if vehicleInfo then
		selectedVehicle = vehicleInfo.selectedVehicle or "Sneakers"
		backpackCapacity = vehicleInfo.capacity or backpackCapacity
	end
	
	-- Update UI
	updateStoragePanel()
	updateBackpackPanel()
	
	-- Show with animation
	mainFrame.Visible = true
	mainFrame.Size = UDim2.new(0, 700, 0, 0)
	TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Size = UDim2.new(0, 700, 0, 500)
	}):Play()
end

function closeUI()
	if not isOpen then return end
	isOpen = false
	
	TweenService:Create(mainFrame, TweenInfo.new(0.2), {
		Size = UDim2.new(0, 700, 0, 0)
	}):Play()
	
	task.wait(0.2)
	mainFrame.Visible = false
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

StorageUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
	currentStorage = items or {}
	storageUsage = total or 0
	storageCapacity = capacity or 2000
	
	if isOpen then
		updateStoragePanel()
	end
end)

BackpackUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
	currentBackpack = items or {}
	backpackUsage = total or 0
	backpackCapacity = capacity or 100
	
	if isOpen then
		updateBackpackPanel()
	end
end)

VehicleUpdatedEvent.OnClientEvent:Connect(function(vehicleId, newCapacity)
	selectedVehicle = vehicleId or selectedVehicle
	backpackCapacity = newCapacity or 100
	if isOpen then
		updateBackpackPanel()
	end
end)

-- Keyboard toggle (T key)
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	
	if input.KeyCode == Enum.KeyCode.T then
		if isOpen then
			closeUI()
		else
			openUI()
		end
	end
end)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	-- Create UI
	screenGui = createScreenGui()
	mainFrame = createMainFrame(screenGui)
	createHeader(mainFrame)
	createStoragePanel(mainFrame)
	createBackpackPanel(mainFrame)
	createBottomBar(mainFrame)
	
	print("✓ TransportUI initialized - Press T to open")
end

initialize()
