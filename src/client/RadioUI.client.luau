local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIUtils = require(Shared:WaitForChild("Utils"):WaitForChild("UIUtils"))
local RadioStations = require(Shared:WaitForChild("RadioStations"))
local RadioController = require(script.Parent:WaitForChild("Controllers"):WaitForChild("RadioController"))

local addCorner = UIUtils.addCorner
local addStroke = UIUtils.addStroke

local COLORS = {
	panel = Color3.fromRGB(16, 16, 24),
	panelAlt = Color3.fromRGB(24, 24, 34),
	stroke = Color3.fromRGB(90, 90, 120),
	text = Color3.fromRGB(245, 245, 255),
	textDim = Color3.fromRGB(165, 165, 190),
	accent = Color3.fromRGB(220, 90, 180),
	accentHover = Color3.fromRGB(240, 120, 200),
	green = Color3.fromRGB(80, 200, 120),
	red = Color3.fromRGB(230, 90, 90),
}

local screenGui: ScreenGui? = nil
local panel: Frame? = nil
local currentStationLabel: TextLabel? = nil
local statusLabel: TextLabel? = nil
local stationList: Frame? = nil
local isOpen = false
local stationButtons = {}

local function getOrCreateToggleEvent(): BindableEvent
	local existing = ReplicatedStorage:FindFirstChild("RadioToggleEvent")
	if existing and existing:IsA("BindableEvent") then
		return existing
	end

	local toggleEvent = Instance.new("BindableEvent")
	toggleEvent.Name = "RadioToggleEvent"
	toggleEvent.Parent = ReplicatedStorage
	return toggleEvent
end

local function createButton(parent: Instance, text: string, size: UDim2, color: Color3)
	local button = Instance.new("TextButton")
	button.Size = size
	button.BackgroundColor3 = color
	button.Text = text
	button.TextColor3 = COLORS.text
	button.TextSize = 15
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = false
	button.Parent = parent
	addCorner(button, UDim.new(0, 10))
	addStroke(button, COLORS.stroke, 1)
	return button
end

local function refreshStationList()
	if not stationList then
		return
	end

	for _, child in ipairs(stationList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(stationButtons)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = stationList

	local state = RadioController.GetState()
	for index, station in ipairs(RadioStations.GetAll()) do
		local button = createButton(stationList, station.displayName, UDim2.new(1, 0, 0, 34), COLORS.panelAlt)
		button.LayoutOrder = index
		button.TextXAlignment = Enum.TextXAlignment.Left
		button.Text = "  " .. station.displayName
		button.MouseButton1Click:Connect(function()
			RadioController.PlayStation(index)
		end)
		stationButtons[index] = button

		if state.stationIndex == index and not state.isOff then
			button.BackgroundColor3 = COLORS.accent
		end
	end
end

local function updatePanelState(state)
	if currentStationLabel then
		local station = state.station
		if state.isOff then
			currentStationLabel.Text = "Current Station: Off"
		elseif station then
			currentStationLabel.Text = "Current Station: " .. station.displayName
		else
			currentStationLabel.Text = "Current Station: None"
		end
	end

	if statusLabel then
		statusLabel.Text = state.statusMessage or "Radio Ready"
	end

	for index, button in pairs(stationButtons) do
		if state.stationIndex == index and not state.isOff then
			button.BackgroundColor3 = COLORS.accent
		else
			button.BackgroundColor3 = COLORS.panelAlt
		end
	end
end

local function showPanel()
	if not panel or not screenGui or isOpen then
		return
	end

	isOpen = true
	screenGui.Enabled = true
	panel.Visible = true
	panel.Position = UDim2.new(0.5, -180, 1, -180)
	TweenService:Create(panel, TweenInfo.new(0.18), {
		Position = UDim2.new(0.5, -180, 1, -210),
	}):Play()
end

local function hidePanel()
	if not panel or not screenGui or not isOpen then
		return
	end

	isOpen = false
	local tween = TweenService:Create(panel, TweenInfo.new(0.18), {
		Position = UDim2.new(0.5, -180, 1, -180),
	})
	tween:Play()
	tween.Completed:Once(function()
		if not isOpen and screenGui and panel then
			panel.Visible = false
			screenGui.Enabled = false
		end
	end)
end

local function togglePanel()
	if isOpen then
		hidePanel()
	else
		showPanel()
	end
end

local function buildUI()
	if screenGui then
		screenGui:Destroy()
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RadioUI"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 25
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromOffset(360, 280)
	panel.Position = UDim2.new(0.5, -180, 1, -210)
	panel.BackgroundColor3 = COLORS.panel
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui
	addCorner(panel, UDim.new(0, 16))
	addStroke(panel, COLORS.stroke, 1.5)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.panelAlt),
		ColorSequenceKeypoint.new(1, COLORS.panel),
	})
	gradient.Rotation = 90
	gradient.Parent = panel

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -24, 0, 24)
	titleLabel.Position = UDim2.fromOffset(12, 12)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Live Radio"
	titleLabel.TextColor3 = COLORS.text
	titleLabel.TextSize = 20
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = panel

	currentStationLabel = Instance.new("TextLabel")
	currentStationLabel.Size = UDim2.new(1, -24, 0, 18)
	currentStationLabel.Position = UDim2.fromOffset(12, 42)
	currentStationLabel.BackgroundTransparency = 1
	currentStationLabel.Text = "Current Station: Off"
	currentStationLabel.TextColor3 = COLORS.text
	currentStationLabel.TextSize = 14
	currentStationLabel.Font = Enum.Font.GothamBold
	currentStationLabel.TextXAlignment = Enum.TextXAlignment.Left
	currentStationLabel.Parent = panel

	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -24, 0, 16)
	statusLabel.Position = UDim2.fromOffset(12, 62)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Replace station SoundIds in RadioStations.luau"
	statusLabel.TextColor3 = COLORS.textDim
	statusLabel.TextSize = 12
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = panel

	local controls = Instance.new("Frame")
	controls.Size = UDim2.new(1, -24, 0, 42)
	controls.Position = UDim2.fromOffset(12, 88)
	controls.BackgroundTransparency = 1
	controls.Parent = panel

	local controlsLayout = Instance.new("UIListLayout")
	controlsLayout.FillDirection = Enum.FillDirection.Horizontal
	controlsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	controlsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	controlsLayout.Padding = UDim.new(0, 10)
	controlsLayout.Parent = controls

	local previousButton = createButton(controls, "Previous", UDim2.fromOffset(100, 38), COLORS.panelAlt)
	local offButton = createButton(controls, "Off", UDim2.fromOffset(60, 38), COLORS.red)
	local nextButton = createButton(controls, "Next", UDim2.fromOffset(100, 38), COLORS.green)

	local listLabel = Instance.new("TextLabel")
	listLabel.Size = UDim2.new(1, -24, 0, 16)
	listLabel.Position = UDim2.fromOffset(12, 140)
	listLabel.BackgroundTransparency = 1
	listLabel.Text = "Stations"
	listLabel.TextColor3 = COLORS.textDim
	listLabel.TextSize = 12
	listLabel.Font = Enum.Font.GothamBold
	listLabel.TextXAlignment = Enum.TextXAlignment.Left
	listLabel.Parent = panel

	stationList = Instance.new("Frame")
	stationList.Name = "StationList"
	stationList.Size = UDim2.new(1, -24, 1, -168)
	stationList.Position = UDim2.fromOffset(12, 160)
	stationList.BackgroundTransparency = 1
	stationList.Parent = panel

	refreshStationList()
	updatePanelState(RadioController.GetState())

	previousButton.MouseButton1Click:Connect(function()
		RadioController.PreviousStation()
	end)
	nextButton.MouseButton1Click:Connect(function()
		RadioController.NextStation()
	end)
	offButton.MouseButton1Click:Connect(function()
		RadioController.SetOff()
	end)

	RadioController.Changed:Connect(updatePanelState)

	screenGui.Parent = PlayerGui
end

buildUI()
getOrCreateToggleEvent().Event:Connect(togglePanel)
