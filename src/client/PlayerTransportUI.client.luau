local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared:WaitForChild("UIConfig"))
local Utils = Shared:WaitForChild("Utils")
local UIUtils = require(Utils:WaitForChild("UIUtils"))

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local GetCatalogFunction = RemoteFunctions:WaitForChild("GetPlayerTransportCatalog")
local PurchaseFunction = RemoteFunctions:WaitForChild("PurchasePlayerTransport")
local SpawnFunction = RemoteFunctions:WaitForChild("SpawnPlayerTransport")
local DespawnFunction = RemoteFunctions:WaitForChild("DespawnPlayerTransport")
local UpdatedEvent = RemoteEvents:WaitForChild("PlayerTransportUpdated")

local state = {
	open = false,
	loading = false,
	catalog = nil,
	selectedTransportId = nil,
}

local screenGui
local panel
local listFrame
local statusLabel
local actionButton
local titleLabel
local descLabel
local priceLabel

local function formatMoney(amount)
	return "$" .. tostring(math.floor(tonumber(amount) or 0))
end

local function findTransport(transportId)
	local catalog = state.catalog
	if not catalog or type(catalog.vehicles) ~= "table" then
		return nil
	end

	for _, transport in ipairs(catalog.vehicles) do
		if transport.id == transportId then
			return transport
		end
	end
	return nil
end

local function getSelectedTransport()
	return findTransport(state.selectedTransportId)
end

local function setStatus(message, color)
	if statusLabel then
		statusLabel.Text = message or ""
		statusLabel.TextColor3 = color or UIConfig.SECONDARY_TEXT_COLOR
	end
end

local function closeUI()
	if not screenGui or not state.open then
		return
	end

	state.open = false
	local tween = TweenService:Create(panel, UIConfig.TWEEN_INFO.Close, {
		Size = UDim2.new(0, 0, 0, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
	})
	tween:Play()
	tween.Completed:Connect(function()
		if not state.open then
			screenGui.Enabled = false
		end
	end)
end

local refreshRows
local updateDetails

local function updateActionButton()
	if not actionButton then
		return
	end

	local transport = getSelectedTransport()
	if not transport then
		actionButton.Text = "SELECT A VEHICLE"
		actionButton.BackgroundColor3 = UIConfig.BUTTON_DISABLED_COLOR
		return
	end

	if state.loading then
		actionButton.Text = "WORKING..."
		actionButton.BackgroundColor3 = UIConfig.BUTTON_DISABLED_COLOR
		return
	end

	if transport.available == false then
		actionButton.Text = "UNAVAILABLE"
		actionButton.BackgroundColor3 = UIConfig.BUTTON_DISABLED_COLOR
		return
	end

	if transport.active then
		actionButton.Text = "DESPAWN"
		actionButton.BackgroundColor3 = UIConfig.RED_COLOR
		return
	end

	if transport.unlocked then
		actionButton.Text = "SPAWN"
		actionButton.BackgroundColor3 = UIConfig.GREEN_COLOR
		return
	end

	actionButton.Text = "BUY " .. formatMoney(transport.price)
	actionButton.BackgroundColor3 = UIConfig.BUTTON_COLOR
end

updateDetails = function()
	if not titleLabel or not descLabel or not priceLabel then
		return
	end

	local transport = getSelectedTransport()
	if not transport then
		titleLabel.Text = "No Vehicle Selected"
		descLabel.Text = "Select a vehicle from the kiosk list."
		priceLabel.Text = ""
		setStatus("Ready", UIConfig.SECONDARY_TEXT_COLOR)
		updateActionButton()
		return
	end

	titleLabel.Text = string.upper(transport.displayName or transport.id)
	descLabel.Text = transport.description or ""

	if transport.available == false then
		priceLabel.Text = "Model missing from ReplicatedStorage"
		priceLabel.TextColor3 = UIConfig.RED_COLOR
	elseif transport.active then
		priceLabel.Text = "Currently spawned on your pad"
		priceLabel.TextColor3 = UIConfig.GREEN_COLOR
	elseif transport.unlocked then
		priceLabel.Text = "Unlocked"
		priceLabel.TextColor3 = UIConfig.GREEN_COLOR
	else
		priceLabel.Text = "Price: " .. formatMoney(transport.price)
		priceLabel.TextColor3 = UIConfig.GOLD_COLOR
	end

	updateActionButton()
end

refreshRows = function()
	if not listFrame then
		return
	end

	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame

	local catalog = state.catalog
	if not catalog or type(catalog.vehicles) ~= "table" then
		return
	end

	for index, transport in ipairs(catalog.vehicles) do
		local button = Instance.new("TextButton")
		button.Name = transport.id
		button.Size = UDim2.new(1, 0, 0, 72)
		button.BackgroundColor3 = state.selectedTransportId == transport.id and UIConfig.CARD_HOVER_COLOR or UIConfig.CARD_COLOR
		button.BorderSizePixel = 0
		button.Text = ""
		button.AutoButtonColor = false
		button.LayoutOrder = index
		button.Parent = listFrame
		UIUtils.addCorner(button, 10)
		UIUtils.addStroke(button, UIConfig.SOFT_STROKE_COLOR, 1, 0.15)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.new(0, 12, 0, 8)
		nameLabel.Size = UDim2.new(1, -24, 0, 20)
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 16
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = UIConfig.TEXT_COLOR
		nameLabel.Text = transport.displayName
		nameLabel.Parent = button

		local stateText = "Locked"
		local stateColor = UIConfig.GOLD_COLOR
		if transport.available == false then
			stateText = "Unavailable"
			stateColor = UIConfig.RED_COLOR
		elseif transport.active then
			stateText = "Active"
			stateColor = UIConfig.GREEN_COLOR
		elseif transport.unlocked then
			stateText = "Unlocked"
			stateColor = UIConfig.INFO_BLUE_COLOR
		end

		local stateChip = Instance.new("TextLabel")
		stateChip.BackgroundColor3 = Color3.fromRGB(26, 22, 34)
		stateChip.BorderSizePixel = 0
		stateChip.Position = UDim2.new(0, 12, 0, 34)
		stateChip.Size = UDim2.new(0, 110, 0, 24)
		stateChip.Font = Enum.Font.GothamBold
		stateChip.TextSize = 12
		stateChip.TextColor3 = stateColor
		stateChip.Text = stateText
		stateChip.Parent = button
		UIUtils.addCorner(stateChip, 8)

		local priceRow = Instance.new("TextLabel")
		priceRow.BackgroundTransparency = 1
		priceRow.Position = UDim2.new(1, -152, 0, 24)
		priceRow.Size = UDim2.new(0, 140, 0, 20)
		priceRow.Font = Enum.Font.GothamMedium
		priceRow.TextSize = 14
		priceRow.TextXAlignment = Enum.TextXAlignment.Right
		priceRow.TextColor3 = UIConfig.SECONDARY_TEXT_COLOR
		if transport.available == false then
			priceRow.Text = "Missing model"
		elseif transport.unlocked then
			priceRow.Text = "Owned"
		else
			priceRow.Text = formatMoney(transport.price)
		end
		priceRow.Parent = button

		button.MouseButton1Click:Connect(function()
			state.selectedTransportId = transport.id
			updateDetails()
			refreshRows()
		end)
	end
end

local function syncCatalog(catalog)
	if type(catalog) ~= "table" or type(catalog.vehicles) ~= "table" then
		return
	end

	state.catalog = catalog

	if not state.selectedTransportId or not findTransport(state.selectedTransportId) then
		local first = catalog.vehicles[1]
		state.selectedTransportId = first and first.id or nil
	end

	refreshRows()
	updateDetails()
end

local function invokeAndSync(callback)
	if state.loading then
		return
	end

	state.loading = true
	updateActionButton()

	local ok, success, message, catalog = pcall(callback)
	state.loading = false

	if not ok then
		setStatus("Request failed", UIConfig.RED_COLOR)
		updateActionButton()
		return
	end

	if type(catalog) == "table" then
		syncCatalog(catalog)
	end

	if success then
		setStatus(message or "Done", UIConfig.GREEN_COLOR)
	else
		setStatus(message or "Failed", UIConfig.RED_COLOR)
	end

	updateActionButton()
end

local function onActionClicked()
	local transport = getSelectedTransport()
	if not transport or state.loading then
		return
	end

	if transport.available == false then
		setStatus("Transport model missing", UIConfig.RED_COLOR)
		updateActionButton()
		return
	end

	if transport.active then
		invokeAndSync(function()
			return DespawnFunction:InvokeServer()
		end)
		return
	end

	if transport.unlocked then
		invokeAndSync(function()
			return SpawnFunction:InvokeServer(transport.id)
		end)
		return
	end

	invokeAndSync(function()
		return PurchaseFunction:InvokeServer(transport.id)
	end)
end

local function createUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlayerTransportUI"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(0, 0, 0, 0)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = UIConfig.BACKGROUND_COLOR
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	UIUtils.addCorner(panel, 14)
	UIUtils.addStroke(panel, UIConfig.TITLE_CHIP_STROKE, 1, 0.15)

	local header = Instance.new("Frame")
	header.BackgroundColor3 = UIConfig.PANEL_COLOR
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, 54)
	header.Parent = panel
	UIUtils.addCorner(header, 14)

	local headerTitle = Instance.new("TextLabel")
	headerTitle.BackgroundTransparency = 1
	headerTitle.Position = UDim2.new(0, 16, 0, 0)
	headerTitle.Size = UDim2.new(1, -64, 1, 0)
	headerTitle.Font = Enum.Font.GothamBlack
	headerTitle.TextSize = 22
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.TextColor3 = UIConfig.TEXT_COLOR
	headerTitle.Text = "TRANSPORT KIOSK"
	headerTitle.Parent = header

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.new(0, 34, 0, 34)
	closeButton.Position = UDim2.new(1, -44, 0, 10)
	closeButton.BackgroundColor3 = UIConfig.RED_COLOR
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = UIConfig.TEXT_COLOR
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 16
	closeButton.Parent = header
	UIUtils.addCorner(closeButton, 8)
	closeButton.MouseButton1Click:Connect(closeUI)

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Position = UDim2.new(0, 16, 0, 70)
	listFrame.Size = UDim2.new(0, 260, 1, -128)
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.ScrollBarThickness = 6
	listFrame.BackgroundColor3 = UIConfig.PANEL_COLOR
	listFrame.BorderSizePixel = 0
	listFrame.Parent = panel
	UIUtils.addCorner(listFrame, 12)

	local detailFrame = Instance.new("Frame")
	detailFrame.Position = UDim2.new(0, 292, 0, 70)
	detailFrame.Size = UDim2.new(1, -308, 1, -128)
	detailFrame.BackgroundColor3 = UIConfig.PANEL_COLOR
	detailFrame.BorderSizePixel = 0
	detailFrame.Parent = panel
	UIUtils.addCorner(detailFrame, 12)

	titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, 18, 0, 18)
	titleLabel.Size = UDim2.new(1, -36, 0, 30)
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextSize = 24
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = UIConfig.TEXT_COLOR
	titleLabel.Parent = detailFrame

	descLabel = Instance.new("TextLabel")
	descLabel.BackgroundTransparency = 1
	descLabel.Position = UDim2.new(0, 18, 0, 58)
	descLabel.Size = UDim2.new(1, -36, 0, 86)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 16
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextColor3 = UIConfig.SECONDARY_TEXT_COLOR
	descLabel.Parent = detailFrame

	priceLabel = Instance.new("TextLabel")
	priceLabel.BackgroundTransparency = 1
	priceLabel.Position = UDim2.new(0, 18, 0, 152)
	priceLabel.Size = UDim2.new(1, -36, 0, 26)
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextSize = 18
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.Parent = detailFrame

	statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.new(0, 18, 1, -78)
	statusLabel.Size = UDim2.new(1, -36, 0, 22)
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.TextSize = 14
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextColor3 = UIConfig.SECONDARY_TEXT_COLOR
	statusLabel.Text = "Ready"
	statusLabel.Parent = detailFrame

	actionButton = Instance.new("TextButton")
	actionButton.Position = UDim2.new(0, 18, 1, -48)
	actionButton.Size = UDim2.new(1, -36, 0, 36)
	actionButton.BackgroundColor3 = UIConfig.BUTTON_COLOR
	actionButton.BorderSizePixel = 0
	actionButton.TextColor3 = UIConfig.TEXT_COLOR
	actionButton.Font = Enum.Font.GothamBold
	actionButton.TextSize = 16
	actionButton.Parent = detailFrame
	UIUtils.addCorner(actionButton, 10)
	UIUtils.addStroke(actionButton, UIConfig.TITLE_CHIP_STROKE, 1, 0.15)
	actionButton.MouseButton1Click:Connect(onActionClicked)

	if state.catalog then
		syncCatalog(state.catalog)
	else
		updateDetails()
	end
end

local function openUI()
	if not screenGui then
		createUI()
	end
	if state.open then
		return
	end

	state.open = true
	screenGui.Enabled = true
	setStatus("Loading transport catalog...", UIConfig.SECONDARY_TEXT_COLOR)

	panel.Size = UDim2.new(0, 0, 0, 0)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	TweenService:Create(panel, UIConfig.TWEEN_INFO.Open, {
		Size = UDim2.new(0, 760, 0, 470),
		Position = UDim2.new(0.5, -380, 0.5, -235),
	}):Play()

	local ok, catalog = pcall(function()
		return GetCatalogFunction:InvokeServer()
	end)
	if ok then
		syncCatalog(catalog)
		setStatus("Ready", UIConfig.SECONDARY_TEXT_COLOR)
	else
		setStatus("Failed to load catalog", UIConfig.RED_COLOR)
	end
end

UpdatedEvent.OnClientEvent:Connect(function(catalog)
	syncCatalog(catalog)
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then
		return
	end
	if prompt and prompt.Name == "PlayerTransportKioskPrompt" then
		openUI()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape and state.open then
		closeUI()
	end
end)
