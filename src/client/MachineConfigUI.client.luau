--[[
	MachineConfigUI Client Script (V3)
	
	Shows when a player interacts with a placed brainrot unit.
	Allows selecting production mode, shows RPS for each mode,
	highlights BEST mode, and displays active synergy info.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Shared configs
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

-- Remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenUnitUIEvent = RemoteEvents:WaitForChild("OpenUnitUI")
local ModeChangedEvent = RemoteEvents:WaitForChild("ModeChanged")

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local SetUnitModeFunction = RemoteFunctions:WaitForChild("SetUnitMode")

--------------------------------------------------------------------------------
-- STYLE CONSTANTS
--------------------------------------------------------------------------------

local COLORS = {
	BG = Color3.fromRGB(15, 15, 25),
	PANEL = Color3.fromRGB(25, 28, 40),
	CARD = Color3.fromRGB(35, 40, 55),
	CARD_HOVER = Color3.fromRGB(45, 52, 72),
	CARD_SELECTED = Color3.fromRGB(50, 70, 120),
	CARD_LOCKED = Color3.fromRGB(25, 25, 35),
	TEXT = Color3.fromRGB(225, 230, 240),
	TEXT_DIM = Color3.fromRGB(140, 150, 170),
	TEXT_LOCKED = Color3.fromRGB(80, 85, 100),
	ACCENT = Color3.fromRGB(80, 140, 255),
	ACCENT_GREEN = Color3.fromRGB(60, 200, 120),
	ACCENT_GOLD = Color3.fromRGB(255, 200, 60),
	SYNERGY = Color3.fromRGB(200, 100, 255),
	DANGER = Color3.fromRGB(255, 80, 80),
	BORDER = Color3.fromRGB(50, 55, 75),
	CLOSE_BTN = Color3.fromRGB(200, 60, 60),
}

local FONT = {
	TITLE = Font.new("rbxassetid://12187365364", Enum.FontWeight.Bold),
	BODY = Font.new("rbxassetid://12187365364", Enum.FontWeight.Regular),
	MONO = Font.new("rbxassetid://12187365364", Enum.FontWeight.Medium),
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local currentData = nil  -- Unit data from server
local screenGui = nil
local isOpen = false

--------------------------------------------------------------------------------
-- UI BUILDER HELPERS
--------------------------------------------------------------------------------

local function createFrame(props)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = props.Color or COLORS.PANEL
	f.BackgroundTransparency = props.Transparency or 0
	f.BorderSizePixel = 0
	f.Size = props.Size or UDim2.new(1, 0, 1, 0)
	f.Position = props.Position or UDim2.new(0, 0, 0, 0)
	f.AnchorPoint = props.Anchor or Vector2.new(0, 0)
	f.Name = props.Name or "Frame"
	if props.Corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, props.Corner)
		c.Parent = f
	end
	if props.Stroke then
		local s = Instance.new("UIStroke")
		s.Color = props.Stroke
		s.Thickness = 1
		s.Parent = f
	end
	f.Parent = props.Parent
	return f
end

local function createLabel(props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = props.Text or ""
	l.TextColor3 = props.Color or COLORS.TEXT
	l.FontFace = props.Font or FONT.BODY
	l.TextSize = props.Size or 16
	l.TextXAlignment = props.AlignX or Enum.TextXAlignment.Left
	l.TextYAlignment = props.AlignY or Enum.TextYAlignment.Center
	l.Size = props.FrameSize or UDim2.new(1, 0, 0, 24)
	l.Position = props.Position or UDim2.new(0, 0, 0, 0)
	l.Name = props.Name or "Label"
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = props.Parent
	return l
end

local function createButton(props)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = props.Color or COLORS.ACCENT
	b.BorderSizePixel = 0
	b.Text = props.Text or "Button"
	b.TextColor3 = props.TextColor or COLORS.TEXT
	b.FontFace = props.Font or FONT.BODY
	b.TextSize = props.Size or 16
	b.Size = props.FrameSize or UDim2.new(1, 0, 0, 40)
	b.Position = props.Position or UDim2.new(0, 0, 0, 0)
	b.AutoButtonColor = true
	b.Name = props.Name or "Button"
	if props.Corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, props.Corner)
		c.Parent = b
	end
	b.Parent = props.Parent
	return b
end

--------------------------------------------------------------------------------
-- MAIN UI CONSTRUCTION
--------------------------------------------------------------------------------

local function buildUI()
	if screenGui then screenGui:Destroy() end
	
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MachineConfigUI"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 20
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui
	
	-- Semi-transparent backdrop
	local backdrop = createFrame({
		Name = "Backdrop",
		Color = COLORS.BG,
		Transparency = 0.35,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = screenGui,
	})
	
	-- Center panel
	local panel = createFrame({
		Name = "Panel",
		Color = COLORS.PANEL,
		Size = UDim2.new(0, 480, 0, 580),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Anchor = Vector2.new(0.5, 0.5),
		Corner = 16,
		Stroke = COLORS.BORDER,
		Parent = backdrop,
	})
	
	-- Gradient top accent
	local accentBar = createFrame({
		Name = "AccentBar",
		Color = COLORS.ACCENT,
		Size = UDim2.new(1, 0, 0, 4),
		Corner = 16,
		Parent = panel,
	})
	
	-- Header section
	local header = createFrame({
		Name = "Header",
		Color = COLORS.PANEL,
		Transparency = 1,
		Size = UDim2.new(1, -32, 0, 70),
		Position = UDim2.new(0, 16, 0, 16),
		Parent = panel,
	})
	
	local titleLabel = createLabel({
		Name = "Title",
		Text = "⚙️ Production Config",
		Font = FONT.TITLE,
		Size = 22,
		FrameSize = UDim2.new(1, -40, 0, 28),
		Parent = header,
	})
	
	local subtitleLabel = createLabel({
		Name = "Subtitle",
		Text = "Lv. 1 • Normal",
		Color = COLORS.TEXT_DIM,
		Size = 14,
		FrameSize = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, 30),
		Parent = header,
	})
	
	local synergyBanner = createFrame({
		Name = "SynergyBanner",
		Color = COLORS.SYNERGY,
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.new(0, 0, 0, 54),
		Corner = 6,
		Parent = header,
	})
	synergyBanner.BackgroundTransparency = 0.8
	
	local synergyLabel = createLabel({
		Name = "SynergyText",
		Text = "✨ Synergy Active: Avocado Toast (+50%)",
		Color = COLORS.SYNERGY,
		Size = 13,
		AlignX = Enum.TextXAlignment.Center,
		FrameSize = UDim2.new(1, 0, 1, 0),
		Parent = synergyBanner,
	})
	synergyBanner.Visible = false  -- Hidden by default
	
	-- Close button
	local closeBtn = createButton({
		Name = "CloseBtn",
		Text = "✕",
		Color = COLORS.CLOSE_BTN,
		TextColor = COLORS.TEXT,
		Font = FONT.TITLE,
		Size = 18,
		FrameSize = UDim2.new(0, 32, 0, 32),
		Position = UDim2.new(1, -8, 0, 8),
		Corner = 8,
		Parent = panel,
	})
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	
	-- Mode cards container
	local modesContainer = createFrame({
		Name = "ModesContainer",
		Transparency = 1,
		Size = UDim2.new(1, -32, 1, -160),
		Position = UDim2.new(0, 16, 0, 100),
		Parent = panel,
	})
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = modesContainer
	
	-- Apply button at bottom
	local applyBtn = createButton({
		Name = "ApplyBtn",
		Text = "✓ Apply Mode",
		Color = COLORS.ACCENT,
		TextColor = COLORS.TEXT,
		Font = FONT.TITLE,
		Size = 16,
		FrameSize = UDim2.new(1, -32, 0, 44),
		Position = UDim2.new(0, 16, 1, -56),
		Corner = 10,
		Parent = panel,
	})
	
	return {
		gui = screenGui,
		backdrop = backdrop,
		panel = panel,
		titleLabel = titleLabel,
		subtitleLabel = subtitleLabel,
		synergyBanner = synergyBanner,
		synergyLabel = synergyLabel,
		closeBtn = closeBtn,
		modesContainer = modesContainer,
		applyBtn = applyBtn,
	}
end

--------------------------------------------------------------------------------
-- POPULATE & INTERACTION
--------------------------------------------------------------------------------

local ui = buildUI()
local selectedMode = 1
local modeCards = {}

local function createModeCard(modeInfo, index, isCurrent, isBest)
	local isUnlocked = modeInfo.isUnlocked
	local cardColor = isCurrent and COLORS.CARD_SELECTED or (isUnlocked and COLORS.CARD or COLORS.CARD_LOCKED)
	
	local card = createFrame({
		Name = "ModeCard_" .. index,
		Color = cardColor,
		Size = UDim2.new(1, 0, 0, 90),
		Corner = 10,
		Stroke = isCurrent and COLORS.ACCENT or COLORS.BORDER,
		Parent = ui.modesContainer,
	})
	card.LayoutOrder = index
	
	-- Item icon
	local itemDef = ItemConfig.Items[modeInfo.itemId]
	local icon = itemDef and itemDef.icon or "❓"
	local displayName = itemDef and itemDef.displayName or modeInfo.itemId
	local basePrice = itemDef and itemDef.basePrice or 0
	
	createLabel({
		Name = "Icon",
		Text = icon,
		Size = 32,
		AlignX = Enum.TextXAlignment.Center,
		FrameSize = UDim2.new(0, 50, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		Parent = card,
	})
	
	-- Item name + tier label
	local tierNames = { "Common", "Uncommon", "Rare", "Legendary" }
	local tierColors = {
		COLORS.TEXT_DIM,
		Color3.fromRGB(100, 200, 100),
		Color3.fromRGB(100, 150, 255),
		COLORS.ACCENT_GOLD,
	}
	
	createLabel({
		Name = "ItemName",
		Text = displayName,
		Font = FONT.TITLE,
		Size = 16,
		Color = isUnlocked and COLORS.TEXT or COLORS.TEXT_LOCKED,
		FrameSize = UDim2.new(1, -140, 0, 22),
		Position = UDim2.new(0, 66, 0, 12),
		Parent = card,
	})
	
	createLabel({
		Name = "TierLabel",
		Text = (tierNames[index] or "T" .. index) .. " • Mode " .. index,
		Size = 12,
		Color = isUnlocked and (tierColors[index] or COLORS.TEXT_DIM) or COLORS.TEXT_LOCKED,
		FrameSize = UDim2.new(1, -140, 0, 16),
		Position = UDim2.new(0, 66, 0, 36),
		Parent = card,
	})
	
	-- RPS or Lock info
	if isUnlocked then
		local rps = 1 / modeInfo.rate
		local revenue = rps * basePrice
		
		createLabel({
			Name = "RPS",
			Text = string.format("%.1f/s • $%.0f/s", rps, revenue),
			Font = FONT.MONO,
			Size = 14,
			Color = COLORS.ACCENT_GREEN,
			AlignX = Enum.TextXAlignment.Right,
			FrameSize = UDim2.new(0, 110, 0, 20),
			Position = UDim2.new(1, -16, 0, 14),
			Parent = card,
		})
		card:FindFirstChild("RPS").AnchorPoint = Vector2.new(1, 0)
		
		-- BEST badge
		if isBest then
			local bestBadge = createFrame({
				Name = "BestBadge",
				Color = COLORS.ACCENT_GREEN,
				Size = UDim2.new(0, 46, 0, 18),
				Position = UDim2.new(1, -16, 0, 40),
				Corner = 4,
				Parent = card,
			})
			bestBadge.AnchorPoint = Vector2.new(1, 0)
			
			createLabel({
				Name = "BestText",
				Text = "BEST",
				Font = FONT.TITLE,
				Size = 11,
				Color = COLORS.BG,
				AlignX = Enum.TextXAlignment.Center,
				FrameSize = UDim2.new(1, 0, 1, 0),
				Parent = bestBadge,
			})
		end
		
		-- Current indicator
		if isCurrent then
			createLabel({
				Name = "CurrentLabel",
				Text = "▶ ACTIVE",
				Font = FONT.TITLE,
				Size = 11,
				Color = COLORS.ACCENT,
				FrameSize = UDim2.new(1, -140, 0, 16),
				Position = UDim2.new(0, 66, 0, 58),
				Parent = card,
			})
		end
	else
		createLabel({
			Name = "LockInfo",
			Text = "🔒 Unlock at Lv. " .. modeInfo.unlockLevel,
			Size = 13,
			Color = COLORS.TEXT_LOCKED,
			AlignX = Enum.TextXAlignment.Right,
			FrameSize = UDim2.new(0, 140, 0, 20),
			Position = UDim2.new(1, -16, 0, 14),
			Parent = card,
		})
		card:FindFirstChild("LockInfo").AnchorPoint = Vector2.new(1, 0)
	end
	
	-- Click to select (only if unlocked)
	if isUnlocked then
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 1, 0)
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.Name = "Hitbox"
		btn.Parent = card
		
		btn.MouseButton1Click:Connect(function()
			selectedMode = index
			refreshModeCards()
		end)
		
		btn.MouseEnter:Connect(function()
			if selectedMode ~= index then
				card.BackgroundColor3 = COLORS.CARD_HOVER
			end
		end)
		
		btn.MouseLeave:Connect(function()
			if selectedMode ~= index then
				card.BackgroundColor3 = COLORS.CARD
			else
				card.BackgroundColor3 = COLORS.CARD_SELECTED
			end
		end)
	end
	
	return card
end

function refreshModeCards()
	-- Clear existing cards
	for _, card in ipairs(modeCards) do
		card:Destroy()
	end
	modeCards = {}
	
	if not currentData then return end
	
	local unitType = currentData.unitType
	local level = currentData.level or 1
	local modes = ItemConfig.GetAvailableModes(unitType, level)
	
	if #modes == 0 then return end
	
	-- Find best RPS mode
	local bestIdx = 1
	local bestRevenue = 0
	for _, mode in ipairs(modes) do
		if mode.isUnlocked then
			local itemDef = ItemConfig.Items[mode.itemId]
			local basePrice = itemDef and itemDef.basePrice or 0
			local revenue = (1 / mode.rate) * basePrice
			if revenue > bestRevenue then
				bestRevenue = revenue
				bestIdx = mode.modeIndex
			end
		end
	end
	
	for _, mode in ipairs(modes) do
		local isCurrent = (mode.modeIndex == selectedMode)
		local isBest = (mode.modeIndex == bestIdx and mode.isUnlocked)
		local card = createModeCard(mode, mode.modeIndex, isCurrent, isBest)
		table.insert(modeCards, card)
	end
end

local function openUI(unitData)
	currentData = unitData
	selectedMode = unitData.currentMode or 1
	
	-- Update header
	ui.titleLabel.Text = "⚙️ " .. (unitData.unitType or "Unknown")
	ui.subtitleLabel.Text = string.format("Lv. %d • %s", unitData.level or 1, unitData.rarity or "Normal")
	
	-- Check synergy (client-side preview)
	-- For now hide synergy banner — server handles actual synergy logic
	ui.synergyBanner.Visible = false
	
	-- Populate mode cards
	refreshModeCards()
	
	-- Show
	ui.gui.Enabled = true
	isOpen = true
end

local function closeUI()
	ui.gui.Enabled = false
	isOpen = false
	currentData = nil
end

local function applyMode()
	if not currentData or not currentData.gridSlot then return end
	
	local success, err = SetUnitModeFunction:InvokeServer(currentData.gridSlot, selectedMode)
	
	if success then
		-- Update local data
		currentData.currentMode = selectedMode
		refreshModeCards()
		
		-- Brief flash to confirm
		ui.applyBtn.Text = "✓ Applied!"
		ui.applyBtn.BackgroundColor3 = COLORS.ACCENT_GREEN
		task.delay(1, function()
			if ui.applyBtn then
				ui.applyBtn.Text = "✓ Apply Mode"
				ui.applyBtn.BackgroundColor3 = COLORS.ACCENT
			end
		end)
	else
		ui.applyBtn.Text = "✕ " .. tostring(err)
		ui.applyBtn.BackgroundColor3 = COLORS.DANGER
		task.delay(2, function()
			if ui.applyBtn then
				ui.applyBtn.Text = "✓ Apply Mode"
				ui.applyBtn.BackgroundColor3 = COLORS.ACCENT
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- CONNECTIONS
--------------------------------------------------------------------------------

ui.closeBtn.MouseButton1Click:Connect(closeUI)
ui.backdrop.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		-- Only close if clicking backdrop (not panel)
		if input.Position then
			closeUI()
		end
	end
end)
ui.applyBtn.MouseButton1Click:Connect(applyMode)

OpenUnitUIEvent.OnClientEvent:Connect(function(unitData)
	if isOpen then
		closeUI()
	end
	openUI(unitData)
end)

-- Listen for server-side mode changes (e.g. from other sources)
ModeChangedEvent.OnClientEvent:Connect(function(slotIndex, modeIndex, itemId)
	if currentData and currentData.gridSlot == slotIndex then
		currentData.currentMode = modeIndex
		selectedMode = modeIndex
		refreshModeCards()
	end
end)
