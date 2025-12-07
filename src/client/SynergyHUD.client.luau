--[[
	SynergyHUD LocalScript
	
	Displays synergy requirements and progress in a dedicated HUD panel.
	Shows required brainrots with current/required counts and the resulting bonuses.
	
	Features:
	- Visual display of synergy requirements
	- Progress indicators (X/Y) in corner of each requirement
	- Active/Inactive synergy state
	- Effect descriptions when synergy is active
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Player reference
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Wait for shared modules and remotes
local SynergyConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SynergyConfig"))
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local GetInventoryRemote = RemoteEvents:WaitForChild("GetInventory")
local InventoryChangedEvent = RemoteEvents:WaitForChild("InventoryChanged")

--------------------------------------------------------------------------------
-- UI CONFIGURATION
--------------------------------------------------------------------------------

local UI_CONFIG = {
	-- Panel styling
	PANEL_WIDTH = 300,
	PANEL_MARGIN = 20,
	CORNER_RADIUS = 12,
	
	-- Synergy card styling
	CARD_HEIGHT = 140,
	REQUIREMENT_SIZE = 60,
	
	-- Colors
	BACKGROUND_COLOR = Color3.fromRGB(30, 25, 45),
	PANEL_COLOR = Color3.fromRGB(45, 35, 60),
	CARD_COLOR = Color3.fromRGB(55, 45, 75),
	ACCENT_COLOR = Color3.fromRGB(255, 200, 100),
	ACTIVE_COLOR = Color3.fromRGB(100, 255, 100),
	INACTIVE_COLOR = Color3.fromRGB(150, 150, 150),
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	SECONDARY_TEXT_COLOR = Color3.fromRGB(180, 180, 180),
	REQUIREMENT_MET_COLOR = Color3.fromRGB(80, 180, 80),
	REQUIREMENT_UNMET_COLOR = Color3.fromRGB(100, 80, 120),
	
	-- Rarity colors for requirement boxes
	RARITY_COLORS = {
		Normal = Color3.fromRGB(180, 180, 180),
		Spicy = Color3.fromRGB(255, 80, 80),
		Galaxy = Color3.fromRGB(180, 100, 255),
	},
}

--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local SynergyGui: ScreenGui? = nil
local SynergyCards: {[string]: Frame} = {}
local InventoryData: {[string]: {[string]: {total: number, active: number}}} = {}
local SynergyVisible = false

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
-- SYNERGY CARD CREATION
--------------------------------------------------------------------------------

local function createRequirementBox(req: SynergyConfig.SynergyRequirement, current: number): Frame
	local isMet = current >= req.MinCount
	local rarityColor = req.Rarity and UI_CONFIG.RARITY_COLORS[req.Rarity] or UI_CONFIG.TEXT_COLOR
	
	local box = Instance.new("Frame")
	box.Name = req.UnitName
	box.Size = UDim2.new(0, UI_CONFIG.REQUIREMENT_SIZE, 0, UI_CONFIG.REQUIREMENT_SIZE + 16)
	box.BackgroundTransparency = 1
	
	-- Icon box
	local iconFrame = Instance.new("Frame")
	iconFrame.Name = "IconFrame"
	iconFrame.Size = UDim2.new(0, UI_CONFIG.REQUIREMENT_SIZE, 0, UI_CONFIG.REQUIREMENT_SIZE)
	iconFrame.BackgroundColor3 = isMet and UI_CONFIG.REQUIREMENT_MET_COLOR or UI_CONFIG.REQUIREMENT_UNMET_COLOR
	iconFrame.Parent = box
	addCorner(iconFrame, 8)
	addStroke(iconFrame, rarityColor, req.Rarity and 2 or 1)
	
	-- Brainrot icon
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(1, 0, 1, -20)
	iconLabel.Position = UDim2.new(0, 0, 0, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = "🧠"
	iconLabel.TextSize = 28
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextColor3 = rarityColor
	iconLabel.Parent = iconFrame
	
	-- Count badge (bottom right corner)
	local countBadge = Instance.new("Frame")
	countBadge.Name = "CountBadge"
	countBadge.Size = UDim2.new(0, 36, 0, 18)
	countBadge.Position = UDim2.new(1, -38, 1, -20)
	countBadge.BackgroundColor3 = isMet and UI_CONFIG.ACTIVE_COLOR or UI_CONFIG.BACKGROUND_COLOR
	countBadge.Parent = iconFrame
	addCorner(countBadge, 4)
	
	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(1, 0, 1, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Text = string.format("%d/%d", current, req.MinCount)
	countLabel.TextColor3 = UI_CONFIG.TEXT_COLOR
	countLabel.TextSize = 10
	countLabel.Font = Enum.Font.GothamBold
	countLabel.Parent = countBadge
	
	-- Unit name label below
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "UnitName"
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.Position = UDim2.new(0, 0, 1, -14)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = req.UnitName:sub(1, 10) .. (req.UnitName:len() > 10 and "..." or "")
	nameLabel.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
	nameLabel.TextSize = 8
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = box
	
	-- Rarity label if applicable
	if req.Rarity then
		local rarityLabel = Instance.new("TextLabel")
		rarityLabel.Name = "Rarity"
		rarityLabel.Size = UDim2.new(1, 0, 0, 12)
		rarityLabel.Position = UDim2.new(0, 0, 0, 2)
		rarityLabel.BackgroundTransparency = 1
		rarityLabel.Text = req.Rarity
		rarityLabel.TextColor3 = rarityColor
		rarityLabel.TextSize = 9
		rarityLabel.Font = Enum.Font.GothamBold
		rarityLabel.Parent = iconFrame
	end
	
	return box
end

local function createSynergyCard(synergy: SynergyConfig.SynergyDefinition): Frame
	local card = Instance.new("Frame")
	card.Name = synergy.Id
	card.Size = UDim2.new(1, 0, 0, UI_CONFIG.CARD_HEIGHT)
	card.BackgroundColor3 = UI_CONFIG.CARD_COLOR
	card.BorderSizePixel = 0
	addCorner(card, 10)
	
	-- Header with icon and name
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 30)
	header.BackgroundTransparency = 1
	header.Parent = card
	
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(0, 30, 1, 0)
	iconLabel.Position = UDim2.new(0, 8, 0, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = synergy.Icon
	iconLabel.TextSize = 20
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.Parent = header
	
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, -100, 1, 0)
	nameLabel.Position = UDim2.new(0, 40, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = synergy.Name
	nameLabel.TextColor3 = UI_CONFIG.ACCENT_COLOR
	nameLabel.TextSize = 14
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = header
	
	-- Status badge
	local statusBadge = Instance.new("Frame")
	statusBadge.Name = "StatusBadge"
	statusBadge.Size = UDim2.new(0, 60, 0, 20)
	statusBadge.Position = UDim2.new(1, -68, 0.5, -10)
	statusBadge.BackgroundColor3 = UI_CONFIG.INACTIVE_COLOR
	statusBadge.Parent = header
	addCorner(statusBadge, 4)
	
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "StatusText"
	statusLabel.Size = UDim2.new(1, 0, 1, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "LOCKED"
	statusLabel.TextColor3 = UI_CONFIG.TEXT_COLOR
	statusLabel.TextSize = 10
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Parent = statusBadge
	
	-- Requirements container
	local reqContainer = Instance.new("Frame")
	reqContainer.Name = "Requirements"
	reqContainer.Size = UDim2.new(1, -16, 0, UI_CONFIG.REQUIREMENT_SIZE + 20)
	reqContainer.Position = UDim2.new(0, 8, 0, 32)
	reqContainer.BackgroundTransparency = 1
	reqContainer.Parent = card
	
	local reqLayout = Instance.new("UIListLayout")
	reqLayout.FillDirection = Enum.FillDirection.Horizontal
	reqLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	reqLayout.Padding = UDim.new(0, 20)
	reqLayout.Parent = reqContainer
	
	-- Add "+" sign between requirements
	for i, req in synergy.Requirements do
		if i > 1 then
			local plusLabel = Instance.new("TextLabel")
			plusLabel.Name = "Plus" .. i
			plusLabel.Size = UDim2.new(0, 20, 0, UI_CONFIG.REQUIREMENT_SIZE)
			plusLabel.BackgroundTransparency = 1
			plusLabel.Text = "+"
			plusLabel.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
			plusLabel.TextSize = 24
			plusLabel.Font = Enum.Font.GothamBold
			plusLabel.LayoutOrder = (i - 1) * 2
			plusLabel.Parent = reqContainer
		end
		
		local reqBox = createRequirementBox(req, 0)
		reqBox.LayoutOrder = i * 2
		reqBox.Parent = reqContainer
	end
	
	-- Effect description
	local effectLabel = Instance.new("TextLabel")
	effectLabel.Name = "Effect"
	effectLabel.Size = UDim2.new(1, -16, 0, 28)
	effectLabel.Position = UDim2.new(0, 8, 1, -32)
	effectLabel.BackgroundColor3 = UI_CONFIG.BACKGROUND_COLOR
	effectLabel.Text = "▶ " .. synergy.Description
	effectLabel.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
	effectLabel.TextSize = 11
	effectLabel.Font = Enum.Font.GothamMedium
	effectLabel.Parent = card
	addCorner(effectLabel, 4)
	
	return card
end

--------------------------------------------------------------------------------
-- UPDATE LOGIC
--------------------------------------------------------------------------------

local function updateSynergyCard(synergyId: string)
	local card = SynergyCards[synergyId]
	if not card then return end
	
	local synergy = SynergyConfig.GetSynergy(synergyId)
	if not synergy then return end
	
	local isActive, progress = SynergyConfig.CheckSynergyProgress(synergyId, InventoryData)
	
	-- Update status badge
	local header = card:FindFirstChild("Header")
	if header then
		local statusBadge = header:FindFirstChild("StatusBadge")
		if statusBadge then
			statusBadge.BackgroundColor3 = isActive and UI_CONFIG.ACTIVE_COLOR or UI_CONFIG.INACTIVE_COLOR
			local statusText = statusBadge:FindFirstChild("StatusText")
			if statusText then
				statusText.Text = isActive and "ACTIVE" or "LOCKED"
			end
		end
	end
	
	-- Update requirement boxes
	local reqContainer = card:FindFirstChild("Requirements")
	if reqContainer then
		for _, req in synergy.Requirements do
			local key = req.UnitName .. (req.Rarity and ("_" .. req.Rarity) or "")
			local progData = progress[key]
			local current = progData and progData.current or 0
			local isMet = current >= req.MinCount
			
			-- Find the requirement box
			for _, child in reqContainer:GetChildren() do
				if child.Name == req.UnitName then
					local iconFrame = child:FindFirstChild("IconFrame")
					if iconFrame then
						-- Update background color
						iconFrame.BackgroundColor3 = isMet and UI_CONFIG.REQUIREMENT_MET_COLOR or UI_CONFIG.REQUIREMENT_UNMET_COLOR
						
						-- Update count badge
						local countBadge = iconFrame:FindFirstChild("CountBadge")
						if countBadge then
							countBadge.BackgroundColor3 = isMet and UI_CONFIG.ACTIVE_COLOR or UI_CONFIG.BACKGROUND_COLOR
							local countLabel = countBadge:FindFirstChild("Count")
							if countLabel then
								countLabel.Text = string.format("%d/%d", current, req.MinCount)
							end
						end
					end
					break
				end
			end
		end
	end
	
	-- Update effect label style
	local effectLabel = card:FindFirstChild("Effect")
	if effectLabel then
		effectLabel.TextColor3 = isActive and UI_CONFIG.ACTIVE_COLOR or UI_CONFIG.SECONDARY_TEXT_COLOR
	end
	
	-- Add glow effect when active
	local existingStroke = card:FindFirstChildOfClass("UIStroke")
	if existingStroke then
		existingStroke:Destroy()
	end
	if isActive then
		addStroke(card, UI_CONFIG.ACTIVE_COLOR, 2)
	end
end

local function updateAllSynergies()
	for synergyId, _ in SynergyCards do
		updateSynergyCard(synergyId)
	end
end

--------------------------------------------------------------------------------
-- SYNERGY HUD CREATION
--------------------------------------------------------------------------------

local function createSynergyHUD(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SynergyHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	-- Main panel (bottom left)
	local panel = Instance.new("Frame")
	panel.Name = "SynergyPanel"
	panel.Size = UDim2.new(0, UI_CONFIG.PANEL_WIDTH, 0, 0) -- Height auto-calculated
	panel.Position = UDim2.new(0, UI_CONFIG.PANEL_MARGIN, 1, -UI_CONFIG.PANEL_MARGIN)
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.BackgroundColor3 = UI_CONFIG.PANEL_COLOR
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui
	addCorner(panel, UI_CONFIG.CORNER_RADIUS)
	addStroke(panel, UI_CONFIG.ACCENT_COLOR, 2)
	
	-- Title
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 36)
	titleBar.BackgroundColor3 = UI_CONFIG.BACKGROUND_COLOR
	titleBar.BorderSizePixel = 0
	titleBar.Parent = panel
	addCorner(titleBar, UI_CONFIG.CORNER_RADIUS)
	
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -50, 1, 0)
	titleLabel.Position = UDim2.new(0, 12, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "⚡ SYNERGIES"
	titleLabel.TextColor3 = UI_CONFIG.ACCENT_COLOR
	titleLabel.TextSize = 16
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleBar
	
	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 28, 0, 28)
	closeButton.Position = UDim2.new(1, -34, 0.5, -14)
	closeButton.BackgroundColor3 = Color3.fromRGB(180, 80, 80)
	closeButton.Text = "✕"
	closeButton.TextColor3 = UI_CONFIG.TEXT_COLOR
	closeButton.TextSize = 14
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Parent = titleBar
	addCorner(closeButton, 6)
	
	-- Content container
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -16, 1, -44)
	content.Position = UDim2.new(0, 8, 0, 40)
	content.BackgroundTransparency = 1
	content.Parent = panel
	
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = content
	
	-- Create synergy cards
	local synergies = SynergyConfig.GetAllSynergies()
	for i, synergy in synergies do
		local card = createSynergyCard(synergy)
		card.LayoutOrder = i
		card.Parent = content
		SynergyCards[synergy.Id] = card
	end
	
	-- Calculate panel height
	local totalHeight = 44 + 8 -- Title + padding
	for _, synergy in synergies do
		totalHeight = totalHeight + UI_CONFIG.CARD_HEIGHT + 8
	end
	panel.Size = UDim2.new(0, UI_CONFIG.PANEL_WIDTH, 0, totalHeight)
	
	return screenGui
end

--------------------------------------------------------------------------------
-- VISIBILITY CONTROL
--------------------------------------------------------------------------------

local function openSynergyHUD()
	if SynergyVisible then return end
	if not SynergyGui then return end
	local panel = SynergyGui:FindFirstChild("SynergyPanel")
	if not panel then return end
	
	SynergyVisible = true
	
	-- Refresh inventory data
	local inventoryResult = GetInventoryRemote:InvokeServer()
	if inventoryResult and inventoryResult.units then
		InventoryData = inventoryResult.units
		updateAllSynergies()
	end
	
	panel.Visible = true
	panel.Position = UDim2.new(0, -UI_CONFIG.PANEL_WIDTH, 1, -UI_CONFIG.PANEL_MARGIN)
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, UI_CONFIG.PANEL_MARGIN, 1, -UI_CONFIG.PANEL_MARGIN)
	}):Play()
end

local function closeSynergyHUD()
	if not SynergyVisible then return end
	if not SynergyGui then return end
	local panel = SynergyGui:FindFirstChild("SynergyPanel")
	if not panel then return end
	
	SynergyVisible = false
	
	local tween = TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, -UI_CONFIG.PANEL_WIDTH, 1, -UI_CONFIG.PANEL_MARGIN)
	})
	tween:Play()
	tween.Completed:Connect(function()
		if not SynergyVisible then
			panel.Visible = false
		end
	end)
end

local function toggleSynergyHUD()
	if SynergyVisible then
		closeSynergyHUD()
	else
		openSynergyHUD()
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("SynergyHUD: Initializing...")
	
	-- Create the HUD
	SynergyGui = createSynergyHUD()
	if not SynergyGui then return end
	SynergyGui.Parent = PlayerGui
	
	-- Setup close button
	local panel = SynergyGui:FindFirstChild("SynergyPanel")
	if panel then
		local titleBar = panel:FindFirstChild("TitleBar")
		if titleBar then
			local closeButton = titleBar:FindFirstChild("CloseButton")
			if closeButton then
				closeButton.MouseButton1Click:Connect(closeSynergyHUD)
				
				closeButton.MouseEnter:Connect(function()
					TweenService:Create(closeButton, TweenInfo.new(0.1), {
						BackgroundColor3 = Color3.fromRGB(220, 100, 100)
					}):Play()
				end)
				
				closeButton.MouseLeave:Connect(function()
					TweenService:Create(closeButton, TweenInfo.new(0.1), {
						BackgroundColor3 = Color3.fromRGB(180, 80, 80)
					}):Play()
				end)
			end
		end
	end
	
	-- Listen for inventory changes to update synergy progress
	InventoryChangedEvent.OnClientEvent:Connect(function(unitName: string, rarityData)
		if not InventoryData[unitName] then
			InventoryData[unitName] = {}
		end
		
		for rarity, data in rarityData do
			InventoryData[unitName][rarity] = {
				total = data.total,
				active = data.active,
			}
		end
		
		if SynergyVisible then
			updateAllSynergies()
		end
	end)
	
	-- Setup 'Y' key toggle
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == Enum.KeyCode.Y then
			toggleSynergyHUD()
		end
	end)
	
	-- Setup BindableEvent listener
	task.wait(0.5)
	
	local synergyToggleEvent = ReplicatedStorage:FindFirstChild("SynergyToggleEvent")
	if not synergyToggleEvent then
		synergyToggleEvent = Instance.new("BindableEvent")
		synergyToggleEvent.Name = "SynergyToggleEvent"
		synergyToggleEvent.Parent = ReplicatedStorage
	end
	
	synergyToggleEvent.Event:Connect(toggleSynergyHUD)
	
	print("SynergyHUD: Ready! Press 'Y' to toggle.")
end

-- Start
initialize()
