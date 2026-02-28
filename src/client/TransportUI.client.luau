--[[
	TransportUI Client Script
	
	Handles the storage loading UI for the physical Cart system.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

-- Get player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local CollectionService = game:GetService("CollectionService")

-- Wait for remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")

-- Storage events
local StorageUpdatedEvent = RemoteEvents:WaitForChild("StorageUpdated")
local CartUpdateEvent = RemoteEvents:WaitForChild("CartUpdate") -- Changed from BackpackUpdated
local GetStorageFunction = RemoteFunctions:WaitForChild("GetStorage")

-- Transport events
local LoadFromStorageFunction = RemoteFunctions:WaitForChild("LoadFromStorage")
local LoadMaxFromStorageFunction = RemoteFunctions:WaitForChild("LoadMaxFromStorage")

-- Wait for ItemConfig
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

-- UI Colors (glassmorphism theme)
local COLORS = {
	background = Color3.fromRGB(15, 15, 22),
	panel = Color3.fromRGB(20, 20, 30),
	accent = Color3.fromRGB(60, 160, 255),
	accentDark = Color3.fromRGB(40, 110, 200),
	text = Color3.fromRGB(240, 240, 255),
	textMuted = Color3.fromRGB(160, 160, 180),
	success = Color3.fromRGB(80, 230, 120),
	warning = Color3.fromRGB(250, 190, 60),
	danger = Color3.fromRGB(255, 80, 80),
	itemBg = Color3.fromRGB(25, 25, 35),
	stroke = Color3.fromRGB(70, 70, 90),
}

-- State
local isOpen = false
local currentStorage = {}
local currentCart = {} -- Changed from Backpack
local storageCapacity = 0 -- Updated via Player Attribute
local storageUsage = 0
local cartCapacity = 0 -- Updated via Player Attribute
local cartState = "idle"

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
	frame.Size = UDim2.new(0, 740, 0, 520)
	frame.Position = UDim2.new(0.5, -370, 0.5, -260)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent
	
	-- Corner rounding
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = frame
	
	-- Stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.stroke
	stroke.Thickness = 1.5
	stroke.Transparency = 0.5
	stroke.Parent = frame
	
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.background),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 10, 15))
	})
	gradient.Rotation = 90
	gradient.Parent = frame
	
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
	title.Text = "📦 STORAGE & LOADING"
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
	capacityText.Text = "0 / 0"
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

local function createCartPanel(parent)
	local panel = Instance.new("Frame")
	panel.Name = "CartPanel"
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
	title.Text = "🛒 TRANSPORT CART"
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
	capacityText.Text = "0 / 0"
	capacityText.TextColor3 = COLORS.text
	capacityText.TextSize = 12
	capacityText.Font = Enum.Font.GothamBold
	capacityText.Parent = capacityBar
	
	-- Action Button (Push/Return)
	local actionBtn = Instance.new("TextButton")
	actionBtn.Name = "ActionButton"
	actionBtn.Size = UDim2.new(1, -20, 0, 35)
	actionBtn.Position = UDim2.new(0, 10, 1, -45)
	actionBtn.BackgroundColor3 = COLORS.warning
	actionBtn.Text = "PUSH TO MARKET"
	actionBtn.TextColor3 = COLORS.background
	actionBtn.TextSize = 14
	actionBtn.Font = Enum.Font.GothamBold
	actionBtn.Visible = false
	actionBtn.Parent = panel
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = actionBtn
	
	-- Connect Event
	actionBtn.MouseButton1Click:Connect(function()
		local PushCartRemote = RemoteEvents:FindFirstChild("PushCart")
		local ReturnCartRemote = RemoteEvents:FindFirstChild("ReturnCart")
		
		if cartState == "idle" and PushCartRemote then
			PushCartRemote:FireServer()
		elseif cartState == "at_market" and ReturnCartRemote then
			ReturnCartRemote:FireServer()
		end
		-- Close UI on action?
		closeUI()
	end)
	
	-- Item list scroll
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemList"
	scrollFrame.Size = UDim2.new(1, -20, 1, -135) -- Adjusted for button
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
	loadMaxBtn.Text = "📦 LOAD TO CART"
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

local function updateCartPanel()
	if not mainFrame then return end
	
	local panel = mainFrame:FindFirstChild("CartPanel")
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
	local hasItems = false
	for itemId, count in pairs(currentCart) do
		if count > 0 then
			createItemRow(scrollFrame, itemId, count, false)
			hasItems = true
		end
	end
	
	-- Update capacity bar
	local capacityBar = panel:FindFirstChild("CapacityBar")
	if capacityBar then
		local fill = capacityBar:FindFirstChild("Fill")
		local text = capacityBar:FindFirstChild("Text")
		
		local usage = 0
		for _, c in pairs(currentCart) do usage += c end
		
		local ratio = math.clamp(usage / math.max(1, cartCapacity), 0, 1)
		
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
			text.Text = string.format("%d / %d", usage, cartCapacity)
		end
	end
	
	-- Update Action Button
	local actionBtn = panel:FindFirstChild("ActionButton")
	if actionBtn then
		if cartState == "idle" then
			actionBtn.Visible = hasItems
			actionBtn.Text = "🚶 PUSH TO MARKET"
			actionBtn.BackgroundColor3 = COLORS.success
		elseif cartState == "at_market" then
			actionBtn.Visible = true
			actionBtn.Text = "🏠 RETURN CART"
			actionBtn.BackgroundColor3 = COLORS.warning
		else
			actionBtn.Visible = false
		end
	end
	
	-- Update title with cart state
	local title = panel:FindFirstChild("Title")
	if title then
		local stateText = "IDLE"
		if cartState == "rolling_to_market" then stateText = "ROLLING..."
		elseif cartState == "at_market" then stateText = "AT MARKET" 
		elseif cartState == "rolling_to_plot" then stateText = "RETURNING..." end
		title.Text = "🛒 CART: " .. stateText
	end
end

--------------------------------------------------------------------------------
-- OPEN/CLOSE
--------------------------------------------------------------------------------

local GetVehicleInfoFunction = RemoteFunctions:WaitForChild("GetVehicleInfo")

local function decodeItems(encoded)
	if not ItemConfig or not ItemConfig.SHORT_TO_ID then return encoded end
	if type(encoded) ~= "table" then return encoded end
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

local function openUI()
	if isOpen then return end
	isOpen = true
	
	-- Fetch latest storage data
	local storageItems, storageTotal, storageCap = GetStorageFunction:InvokeServer()
	currentStorage = decodeItems(storageItems) or {}
	storageUsage = storageTotal or 0
	storageCapacity = LocalPlayer:GetAttribute("StorageCapacity") or storageCap or 0
	
	-- Fetch cart data
	local vInfo = GetVehicleInfoFunction:InvokeServer()
	if vInfo then
		currentCart = decodeItems(vInfo.inventory) or {}
		cartCapacity = LocalPlayer:GetAttribute("CartCapacity") or vInfo.capacity or 0
		local usage = 0
		for _, c in pairs(currentCart) do usage += c end
		-- cartUsage removed, dealt with locally
	end
	
	-- Update UI
	updateStoragePanel()
	updateCartPanel()
	
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
	currentStorage = decodeItems(items) or {}
	storageUsage = total or 0
	storageCapacity = LocalPlayer:GetAttribute("StorageCapacity") or capacity or 0
	
	if isOpen then
		updateStoragePanel()
	end
end)

CartUpdateEvent.OnClientEvent:Connect(function(state, inventory, capacity)
	cartState = state or "idle"
	currentCart = decodeItems(inventory) or {}
	cartCapacity = LocalPlayer:GetAttribute("CartCapacity") or capacity or 0
	
	if isOpen then
		updateCartPanel()
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

-- Toggle via HUD button
local StorageToggleEvent = ReplicatedStorage:WaitForChild("StorageToggleEvent", 5)
if StorageToggleEvent then
	StorageToggleEvent.Event:Connect(function()
		if isOpen then
			closeUI()
		else
			openUI()
		end
	end)
end

-- Cart Proximity Prompt integration
local function setupPromptListener(prompt)
	if not prompt:IsA("ProximityPrompt") then return end
	prompt.Triggered:Connect(function(playerWhoTriggered)
		if playerWhoTriggered == LocalPlayer then
			if isOpen then
				closeUI()
			else
				openUI()
			end
		end
	end)
end

CollectionService:GetInstanceAddedSignal("TransportCartPrompt"):Connect(setupPromptListener)
for _, prompt in CollectionService:GetTagged("TransportCartPrompt") do
	setupPromptListener(prompt)
end

-- Fallback for world prompts that are not tagged yet (ex: placed kiosk prompts).
ProximityPromptService.PromptTriggered:Connect(function(prompt, playerWhoTriggered)
	if playerWhoTriggered == LocalPlayer and prompt.Name == "TransportCartPrompt" then
		openUI()
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
	createCartPanel(mainFrame) -- Changed from createBackpackPanel
	createBottomBar(mainFrame)
	
	print("✓ TransportUI initialized - Press T to open")
end

initialize()
