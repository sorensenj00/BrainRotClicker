--[[
	BackpackHUD LocalScript
	
	Displays the player's artifact inventory (storage) in an 8x8 grid.
	Features:
	- Grid view of unequipped artifacts
	- Tooltip with artifact stats on hover
	- Toggle visibility via button
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local GetArtifactsFunction = RemoteFunctions:WaitForChild("GetArtifacts")

local UI_CONFIG = {
	PANEL_SIZE = 400,
	SLOT_SIZE = 40,
	GRID_PADDING = 8,
	CORNER_RADIUS = 12,
	
	BG_COLOR = Color3.fromRGB(30,30,40),
	SLOT_BG = Color3.fromRGB(40,40,50),
	ACCENT = Color3.fromRGB(100, 150, 255),
	TEXT_COLOR = Color3.fromRGB(255,255,255),
}

local BackpackGui
local BackpackVisible = false
local ArtifactsCache = {}

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
	stroke.Parent = parent
	return stroke
end

local function createTooltip(artifact)
	local tooltip = Instance.new("Frame")
	tooltip.Name = "Tooltip"
	tooltip.BackgroundColor3 = Color3.fromRGB(20,20,30)
	tooltip.BorderSizePixel = 0
	tooltip.Size = UDim2.new(0, 200, 0, 0) -- Auto height
	tooltip.ClipsDescendants = true
	tooltip.ZIndex = 10
	addCorner(tooltip, 8)
	addStroke(tooltip, artifact.Color or Color3.new(1,1,1), 1)
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.Parent = tooltip
	
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = tooltip
	
	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Text = artifact.Name
	nameLabel.TextColor3 = artifact.Color or Color3.new(1,1,1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.TextWrap = true
	nameLabel.Parent = tooltip
	
	-- Stats
	local stats = ArtifactConfig.CalculateArtifactStats(artifact)
	
	local function addStatLine(text)
		local label = Instance.new("TextLabel")
		label.Text = text
		label.TextColor3 = UI_CONFIG.TEXT_COLOR
		label.Font = Enum.Font.Gotham
		label.TextSize = 12
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 16)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = tooltip
	end
	
	if stats.CycleTimeMult ~= 1 then
		local percent = math.round((1 - stats.CycleTimeMult) * 100)
		addStatLine(string.format("⚡ Cycle Time: -%d%%", percent))
	end
	if stats.LuckBonus > 0 then
		addStatLine(string.format("🍀 Luck: +%.1f", stats.LuckBonus))
	end
	if stats.ItemTierBonus > 0 then
		addStatLine(string.format("⭐ Tier: +%.1f", stats.ItemTierBonus))
	end
	if stats.SynergyRangeBonus > 0 then
		addStatLine(string.format("🔗 Range: +%d", stats.SynergyRangeBonus))
	end
	
	-- Adjust height
	local contentHeight = 0
	for _, child in ipairs(tooltip:GetChildren()) do
		if child:IsA("GuiObject") then
			contentHeight = contentHeight + child.Size.Y.Offset + 4
		end
	end
	tooltip.Size = UDim2.new(0, 200, 0, contentHeight + 16)
	
	return tooltip
end

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createBackpackHUD()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BackpackHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	local panel = Instance.new("Frame")
	panel.Name = "MainPanel"
	panel.Size = UDim2.new(0, UI_CONFIG.PANEL_SIZE, 0, UI_CONFIG.PANEL_SIZE + 50)
	panel.Position = UDim2.new(0.5, -UI_CONFIG.PANEL_SIZE/2, 0.5, -UI_CONFIG.PANEL_SIZE/2)
	panel.BackgroundColor3 = UI_CONFIG.BG_COLOR
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui
	addCorner(panel, UI_CONFIG.CORNER_RADIUS)
	addStroke(panel, Color3.fromRGB(60,60,80), 2)
	
	-- Header
	local header = Instance.new("TextLabel")
	header.Text = "🎒 BACKPACK STORAGE"
	header.Font = Enum.Font.GothamBold
	header.TextSize = 18
	header.TextColor3 = UI_CONFIG.TEXT_COLOR
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 40)
	header.Parent = panel
	
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = "✕"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.BackgroundTransparency = 1
	closeBtn.TextSize = 18
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -40, 0, 0)
	closeBtn.Parent = panel
	
	closeBtn.MouseButton1Click:Connect(function()
		BackpackVisible = false
		panel.Visible = false
	end)
	
	-- Grid Container
	local gridFrame = Instance.new("ScrollingFrame")
	gridFrame.Name = "Grid"
	gridFrame.BackgroundTransparency = 1
	gridFrame.Size = UDim2.new(1, -20, 1, -60)
	gridFrame.Position = UDim2.new(0, 10, 0, 50)
	gridFrame.ScrollBarThickness = 6
	gridFrame.Parent = panel
	
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 43, 0, 43) -- Fits approx 8 in 400px width minus padding
	gridLayout.CellPadding = UDim2.new(0, 5, 0, 5)
	gridLayout.Parent = gridFrame
	
	return screenGui
end

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local function refreshGrid()
	if not BackpackGui then return end
	local grid = BackpackGui:FindFirstChild("MainPanel"):FindFirstChild("Grid")
	if not grid then return end
	
	-- Clear existing
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	
	-- Fetch data
	local artifactsData = GetArtifactsFunction:InvokeServer()
	local artifacts = artifactsData.unequipped or {}
	
	-- Populate grid (64 slots minimum to look like 8x8)
	for i = 1, 64 do
		local artifact = artifacts[i]
		
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. i
		slot.BackgroundColor3 = UI_CONFIG.SLOT_BG
		slot.Parent = grid
		addCorner(slot, 6)
		
		if artifact then
			local icon = Instance.new("TextLabel")
			icon.Text = artifact.BaseIcon or "💎"
			icon.Size = UDim2.new(1,0,1,0)
			icon.BackgroundTransparency = 1
			icon.TextSize = 24
			icon.Parent = slot
			
			-- Rarity Border
			if artifact.Color then
				addStroke(slot, artifact.Color, 2)
			end
			
			-- Tooltip logic
			slot.MouseEnter:Connect(function()
				local t = createTooltip(artifact)
				t.Parent = BackpackGui.MainPanel
				-- Position near mouse
				local mouse = Player:GetMouse()
				local x = mouse.X - BackpackGui.MainPanel.AbsolutePosition.X + 15
				local y = mouse.Y - BackpackGui.MainPanel.AbsolutePosition.Y + 15
				t.Position = UDim2.new(0, x, 0, y)
				t.Name = "ActiveTooltip"
			end)
			
			slot.MouseLeave:Connect(function()
				local t = BackpackGui.MainPanel:FindFirstChild("ActiveTooltip")
				if t then t:Destroy() end
			end)
		end
	end
end

local function toggleBackpack()
	BackpackVisible = not BackpackVisible
	if not BackpackGui then
		BackpackGui = createBackpackHUD()
		BackpackGui.Parent = PlayerGui
	end
	
	local panel = BackpackGui:FindFirstChild("MainPanel")
	panel.Visible = BackpackVisible
	
	if BackpackVisible then
		refreshGrid()
	end
end

-- Init
local BackpackToggleEvent = ReplicatedStorage:FindFirstChild("BackpackToggleEvent")
if not BackpackToggleEvent then
	BackpackToggleEvent = Instance.new("BindableEvent")
	BackpackToggleEvent.Name = "BackpackToggleEvent"
	BackpackToggleEvent.Parent = ReplicatedStorage
end
BackpackToggleEvent.Event:Connect(toggleBackpack)
