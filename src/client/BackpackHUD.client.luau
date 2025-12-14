--[[
	BackpackHUD LocalScript
	
	Unified Inventory UI ("Backpack").
	Displays Units and Artifacts in a grid.
	Features rich interaction with 3D previews and stats.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemTypes = require(Shared:WaitForChild("ItemTypes"))
local ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local GetUnifiedInventoryFunc = RemoteFunctions:WaitForChild("GetUnifiedInventory")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

-- Folders for 3D preview
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")

local UI_CONFIG = {
	PANEL_WIDTH = 500,
	PANEL_HEIGHT = 600,
	SLOT_SIZE = 50,
	GRID_PADDING = 8,
	CORNER_RADIUS = 16,
	
	COLOR_BG = Color3.fromRGB(25, 25, 35),
	COLOR_PANEL = Color3.fromRGB(35, 35, 45),
	COLOR_SLOT = Color3.fromRGB(45, 45, 55),
	COLOR_ACCENT = Color3.fromRGB(100, 150, 255),
	COLOR_TEXT = Color3.fromRGB(240, 240, 240),
	COLOR_TEXT_DIM = Color3.fromRGB(150, 150, 160),
	
	RARITY_COLORS = {
		Normal = Color3.fromRGB(180, 180, 180),
		Spicy = Color3.fromRGB(255, 80, 80),
		Galaxy = Color3.fromRGB(180, 100, 255),
	}
}

local BackpackGui
local BackpackVisible = false
local CurrentItems = {}
local CurrentFilter = "All" -- "All", "Unit", "Artifact"

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function getRarityColor(rarity)
	return UI_CONFIG.RARITY_COLORS[rarity] or UI_CONFIG.RARITY_COLORS.Normal
end

--[[
	Finds the brainrot visual template.
]]
local function getBrainrotTemplate(unitName)
	-- Try to find in various locations
	local t = BrainrotsFolder:FindFirstChild(unitName)
	if t then return t end
	
	-- Check ReplicatedStorage.Assets.Brainrots if exists
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets and assets:FindFirstChild("Brainrots") then
		t = assets.Brainrots:FindFirstChild(unitName)
		if t then return t end
	end
	
	return nil
end

--------------------------------------------------------------------------------
-- DETAIL POPUP
--------------------------------------------------------------------------------

local function spawn3DPreview(viewport, unitName)
	viewport:ClearAllChildren()
	
	local template = getBrainrotTemplate(unitName)
	if not template then return end
	
	local model = template:Clone()
	model.Parent = viewport
	
	-- Setup Camera
	local cam = Instance.new("Camera")
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	
	local cf, size = model:GetBoundingBox()
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dist = maxDim * 2
	
	-- Rotate model
	local rotation = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not model.Parent then 
			connection:Disconnect()
			return 
		end
		rotation = rotation + dt * 0.5
		local rotCFrame = CFrame.Angles(0, rotation, 0)
		local newPos = cf.Position + (rotCFrame * Vector3.new(0, maxDim*0.2, dist))
		cam.CFrame = CFrame.new(newPos, cf.Position)
	end)
end

local function openDetailPopup(item)
	-- Remove existing popup
	local oldPopup = BackpackGui:FindFirstChild("DetailPopup")
	if oldPopup then oldPopup:Destroy() end
	
	local popup = Instance.new("Frame")
	popup.Name = "DetailPopup"
	popup.Size = UDim2.new(0, 300, 0, 400)
	-- Center related to screen? Or panel? let's center on screen for now
	popup.Position = UDim2.new(0.5, 0, 0.5, 0)
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.BackgroundColor3 = UI_CONFIG.COLOR_BG
	popup.BorderSizePixel = 0
	popup.ZIndex = 100
	popup.Parent = BackpackGui
	
	addCorner(popup, 16)
	addStroke(popup, getRarityColor(item.Rarity), 2)
	
	-- Close Button (Top Right)
	local close = Instance.new("TextButton")
	close.Text = "✕"
	close.Size = UDim2.new(0, 30, 0, 30)
	close.Position = UDim2.new(1, -35, 0, 5)
	close.BackgroundTransparency = 1
	close.TextColor3 = UI_CONFIG.COLOR_TEXT_DIM
	close.TextSize = 20
	close.Parent = popup
	close.MouseButton1Click:Connect(function() popup:Destroy() end)
	
	-- Content Layout
	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, -20, 1, -20)
	content.Position = UDim2.new(0, 10, 0, 10)
	content.BackgroundTransparency = 1
	content.Parent = popup
	
	local uiList = Instance.new("UIListLayout")
	uiList.SortOrder = Enum.SortOrder.LayoutOrder
	uiList.Padding = UDim.new(0, 10)
	uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	uiList.Parent = content
	
	-- 1. Header (Name & Rarity)
	local header = Instance.new("TextLabel")
	header.Text = item.Name
	header.TextColor3 = getRarityColor(item.Rarity)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 18
	header.Size = UDim2.new(1, 0, 0, 24)
	header.BackgroundTransparency = 1
	header.LayoutOrder = 1
	header.Parent = content
	
	-- 2. Preview Area
	local previewFrame = Instance.new("Frame")
	previewFrame.Size = UDim2.new(0, 200, 0, 200)
	previewFrame.BackgroundColor3 = Color3.fromRGB(20,20,25)
	previewFrame.LayoutOrder = 2
	previewFrame.Parent = content
	addCorner(previewFrame, 8)
	
	if item.Type == "Unit" then
		-- 3D Viewport
		local vp = Instance.new("ViewportFrame")
		vp.Size = UDim2.new(1, 0, 1, 0)
		vp.BackgroundTransparency = 1
		vp.Parent = previewFrame
		spawn3DPreview(vp, item.UUID) -- UUID is unitName for units
		
	elseif item.Type == "Artifact" then
		-- Icon Image
		local icon = Instance.new("TextLabel") -- Using TextLabel for emoji icons?
		-- If Icon is an asset ID, use ImageLabel. If emoji, use TextLabel.
		-- Artifact system uses generic Image/Emoji.
		icon.Text = item.Icon
		icon.Size = UDim2.new(1,0,1,0)
		icon.BackgroundTransparency = 1
		icon.TextSize = 100
		icon.Parent = previewFrame
	end
	
	-- 3. Stats / Info
	local infoFrame = Instance.new("Frame")
	infoFrame.Size = UDim2.new(1, 0, 0, 100)
	infoFrame.BackgroundTransparency = 1
	infoFrame.LayoutOrder = 3
	infoFrame.Parent = content
	
	local infoList = Instance.new("UIListLayout")
	infoList.Padding = UDim.new(0, 4)
	infoList.Parent = infoFrame
	
	local function addLine(text, color)
		local l = Instance.new("TextLabel")
		l.Text = text
		l.TextColor3 = color or UI_CONFIG.COLOR_TEXT
		l.TextSize = 14
		l.Font = Enum.Font.Gotham
		l.Size = UDim2.new(1, 0, 0, 18)
		l.BackgroundTransparency = 1
		l.Parent = infoFrame
	end
	
	if item.Type == "Unit" then
		addLine("Level: " .. (item.Data.Level or 1), UI_CONFIG.COLOR_TEXT)
		addLine("Status: " .. (item.IsPlaced and "Placed (On Grid)" or "Stored"), 
			item.IsPlaced and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 200, 100))
			
		-- TODO: Show slots?
	else -- Artifact
		addLine("Slot: " .. (item.Data.EquippedTo and "Equipped" or "Inventory"), UI_CONFIG.COLOR_TEXT_DIM)
		
		local stats = item.Data.Stats or {}
		if stats.CycleTimeMult and stats.CycleTimeMult ~= 1 then
			local p = math.round((1 - stats.CycleTimeMult) * 100)
			addLine("⚡ Cycle Time: -" .. p .. "%", Color3.fromRGB(255,255,100))
		end
		if stats.LuckBonus and stats.LuckBonus > 0 then
			addLine("🍀 Luck: +" .. stats.LuckBonus, Color3.fromRGB(100,255,100))
		end
		if stats.ItemTierBonus and stats.ItemTierBonus > 0 then
			addLine("⭐ Tier: +" .. stats.ItemTierBonus, Color3.fromRGB(255,100,255))
		end
	end
end

--------------------------------------------------------------------------------
-- GRID UI
--------------------------------------------------------------------------------

local function refreshGrid()
	if not BackpackGui then return end
	local grid = BackpackGui:FindFirstChild("MainPanel"):FindFirstChild("Grid")
	if not grid then return end
	
	-- Clean old
	for _, c in pairs(grid:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	
	-- Filter Items
	local displayItems = {}
	for _, item in ipairs(CurrentItems) do
		if CurrentFilter == "All" or item.Type == CurrentFilter then
			table.insert(displayItems, item)
		end
	end
	
	-- Create Slots
	for i, item in ipairs(displayItems) do
		local slot = Instance.new("ImageButton")
		slot.Name = "Slot_" .. i
		slot.BackgroundColor3 = UI_CONFIG.COLOR_SLOT
		slot.AutoButtonColor = false
		slot.Parent = grid
		addCorner(slot, 8)
		addStroke(slot, getRarityColor(item.Rarity), 1.5)
		
		-- Icon
		local icon = Instance.new("TextLabel")
		icon.Text = item.Icon
		icon.Size = UDim2.new(1,0,1,0)
		icon.BackgroundTransparency = 1
		icon.TextSize = 24
		icon.Parent = slot
		
		-- Placed/Equipped indicator
		if item.IsPlaced or item.IsEquipped then
			local ind = Instance.new("Frame")
			ind.Size = UDim2.new(0, 12, 0, 12)
			ind.Position = UDim2.new(1, -12, 1, -12)
			ind.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
			ind.BorderSizePixel = 0
			ind.Parent = slot
			addCorner(ind, 6)
			
			local sLabel = Instance.new("TextLabel")
			sLabel.Text = item.IsPlaced and "P" or "E"
			sLabel.Size = UDim2.new(1,0,1,0)
			sLabel.BackgroundTransparency = 1
			sLabel.TextSize = 8
			sLabel.Font = Enum.Font.GothamBold
			sLabel.TextColor3 = Color3.new(0,0,0)
			sLabel.Parent = ind
		end
		
		-- Click to open detail
		slot.MouseButton1Click:Connect(function()
			openDetailPopup(item)
		end)
		
		-- Hover effect
		slot.MouseEnter:Connect(function()
			TweenService:Create(slot, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(60,60,70)}):Play()
		end)
		slot.MouseLeave:Connect(function()
			TweenService:Create(slot, TweenInfo.new(0.1), {BackgroundColor3 = UI_CONFIG.COLOR_SLOT}):Play()
		end)
	end
end

--------------------------------------------------------------------------------
-- MAIN GUI
--------------------------------------------------------------------------------

local function createBackpackHUD()
	local screen = Instance.new("ScreenGui")
	screen.Name = "BackpackHUD"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	local panel = Instance.new("Frame")
	panel.Name = "MainPanel"
	panel.Size = UDim2.new(0, UI_CONFIG.PANEL_WIDTH, 0, UI_CONFIG.PANEL_HEIGHT)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = UI_CONFIG.COLOR_PANEL
	panel.Visible = false
	panel.Parent = screen
	addCorner(panel, UI_CONFIG.CORNER_RADIUS)
	addStroke(panel, Color3.fromRGB(60,60,80), 2)
	
	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 50)
	header.BackgroundTransparency = 1
	header.Parent = panel
	
	local title = Instance.new("TextLabel")
	title.Text = "🎒 BACKPACK"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.TextColor3 = UI_CONFIG.COLOR_TEXT
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.new(0, 20, 0, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.BackgroundTransparency = 1
	title.Parent = header
	
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = "✕"
	closeBtn.TextSize = 24
	closeBtn.TextColor3 = Color3.fromRGB(200, 80, 80)
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -50, 0, 5)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = header
	closeBtn.MouseButton1Click:Connect(function()
		BackpackVisible = false
		panel.Visible = false
		local popup = screen:FindFirstChild("DetailPopup")
		if popup then popup:Destroy() end
	end)
	
	-- Filter Tabs
	local tabsFrame = Instance.new("Frame")
	tabsFrame.Size = UDim2.new(1, -40, 0, 36)
	tabsFrame.Position = UDim2.new(0, 20, 0, 50)
	tabsFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	tabsFrame.Parent = panel
	addCorner(tabsFrame, 8)
	
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Parent = tabsFrame
	
	local function createTab(name, filter)
		local t = Instance.new("TextButton")
		t.Text = name
		t.Size = UDim2.new(0.333, 0, 1, 0)
		t.BackgroundTransparency = 1
		t.TextColor3 = UI_CONFIG.COLOR_TEXT
		t.Font = Enum.Font.GothamBold
		t.Parent = tabsFrame
		
		t.MouseButton1Click:Connect(function()
			CurrentFilter = filter
			-- Visual update for tabs could go here
			refreshGrid()
		end)
	end
	
	createTab("ALL", "All")
	createTab("UNITS", "Unit")
	createTab("ARTIFACTS", "Artifact")
	
	-- Grid Scroll
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.Size = UDim2.new(1, -40, 1, -110)
	scroll.Position = UDim2.new(0, 20, 0, 100)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 6
	scroll.Parent = panel
	
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, UI_CONFIG.SLOT_SIZE, 0, UI_CONFIG.SLOT_SIZE)
	gridLayout.CellPadding = UDim2.new(0, UI_CONFIG.GRID_PADDING, 0, UI_CONFIG.GRID_PADDING)
	gridLayout.Parent = scroll
	
	return screen
end

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local function loadInventory()
	local items = GetUnifiedInventoryFunc:InvokeServer()
	if items then
		CurrentItems = items
		refreshGrid()
	end
end

local function toggleBackpack(filterOverride)
	BackpackVisible = not BackpackVisible
	-- If opening with a specific filter, ensure it's visible and set filter
	if filterOverride and typeof(filterOverride) == "string" then
		CurrentFilter = filterOverride
		BackpackVisible = true -- Force open if filter provided
	end

	if not BackpackGui then
		BackpackGui = createBackpackHUD()
		BackpackGui.Parent = PlayerGui
	end
	
	local panel = BackpackGui:FindFirstChild("MainPanel")
	panel.Visible = BackpackVisible
	
	if BackpackVisible then
		loadInventory()
	end
end

-- Events
local BackpackToggleEvent = ReplicatedStorage:FindFirstChild("BackpackToggleEvent")
if not BackpackToggleEvent then
	BackpackToggleEvent = Instance.new("BindableEvent")
	BackpackToggleEvent.Name = "BackpackToggleEvent"
	BackpackToggleEvent.Parent = ReplicatedStorage
end
BackpackToggleEvent.Event:Connect(toggleBackpack)

-- Listen for updates from Server-side InventoryService? 
-- The plan said "InventoryChanged" (Units) and "ArtifactDropped" (Artifacts).
-- Let's listen to those and re-fetch if Backpack is open.

local function onUpdate()
	if BackpackVisible then
		loadInventory()
	end
end

local InventoryChanged = RemoteEvents:FindFirstChild("InventoryChanged")
if InventoryChanged then InventoryChanged.OnClientEvent:Connect(onUpdate) end

local ArtifactDropped = RemoteEvents:FindFirstChild("ArtifactDropped")
if ArtifactDropped then ArtifactDropped.OnClientEvent:Connect(onUpdate) end
