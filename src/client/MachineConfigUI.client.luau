--[[
	MachineConfigUI Client Script (V3)
	
	Shows when a player interacts with a placed brainrot unit.
	Allows selecting production mode, shows RPS for each mode,
	highlights BEST mode, and displays active synergy info.
	
	Now includes Equipment tab for managing artifacts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Shared configs
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local ViewportPreview = require(Shared:WaitForChild("ViewportPreview"))

-- Remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local OpenUnitUIEvent = RemoteEvents:WaitForChild("OpenUnitUI")
local ModeChangedEvent = RemoteEvents:WaitForChild("ModeChanged")
local ArtifactDroppedEvent = RemoteEvents:WaitForChild("ArtifactDropped")
local ArtifactEquippedEvent = RemoteEvents:WaitForChild("ArtifactEquipped")

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local SetUnitModeFunction = RemoteFunctions:WaitForChild("SetUnitMode")
local GetArtifacts = RemoteFunctions:WaitForChild("GetArtifacts")
local EquipArtifact = RemoteFunctions:WaitForChild("EquipArtifact")
local UnequipArtifact = RemoteFunctions:WaitForChild("UnequipArtifact")
local UpgradeUnitFromHUDFunction = RemoteFunctions:WaitForChild("UpgradeUnitFromHUD")
local GetInventoryRemote = RemoteFunctions:FindFirstChild("GetInventory")
if not GetInventoryRemote then
	GetInventoryRemote = RemoteEvents:FindFirstChild("GetInventory")
end
if not GetInventoryRemote then
	GetInventoryRemote = RemoteFunctions:WaitForChild("GetInventory", 10)
end

-- Assets
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")

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
	ACCENT_PURPLE = Color3.fromRGB(140, 80, 255),
	ACCENT_PINK = Color3.fromRGB(255, 100, 180),
	SYNERGY = Color3.fromRGB(200, 100, 255),
	DANGER = Color3.fromRGB(255, 80, 80),
	BORDER = Color3.fromRGB(50, 55, 75),
	CLOSE_BTN = Color3.fromRGB(200, 60, 60),
	TAB_ACTIVE = Color3.fromRGB(40, 45, 60),
	TAB_INACTIVE = Color3.fromRGB(20, 22, 30),
	OVERLAY_BG = Color3.fromRGB(20, 20, 30),
}

local FONT = {
	TITLE = Font.fromEnum(Enum.Font.GothamBold),
	BODY = Font.fromEnum(Enum.Font.Gotham),
	MONO = Font.fromEnum(Enum.Font.GothamMedium),
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local currentData = nil  -- Unit data from server
local screenGui = nil
local isOpen = false
local currentTab = "Production" -- "Production" or "Equipment"
local previewInstance = nil -- ViewportPreview instance
local statsLabels = {} -- {Base = label, Multipliers = label, Total = label}

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

local function getRarityColor(rarity)
	return ArtifactConfig.RarityColors[rarity] or COLORS.TEXT_DIM
end

local function formatNumber(value)
	local numberValue = math.floor(tonumber(value) or 0)
	return tostring(numberValue):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function buildUpgradeSummary(unitType, level)
	if not unitType then
		return "Upgrade unavailable"
	end

	local price = ShopConfig.CalculatePrice(unitType, math.max(0, tonumber(level) or 0))
	local itemCost = ShopConfig.GetItemCost(unitType)
	local parts = { "$" .. formatNumber(price) }

	if itemCost then
		local itemParts = {}
		for itemId, amount in pairs(itemCost) do
			local itemDef = ItemConfig.Items[itemId]
			local icon = itemDef and itemDef.icon or ""
			table.insert(itemParts, string.format("%s%s %s", icon ~= "" and (icon .. " ") or "", tostring(amount), itemId))
		end
		table.sort(itemParts)
		table.insert(parts, table.concat(itemParts, "  |  "))
	end

	return "Next upgrade: " .. table.concat(parts, "  +  ")
end

local function isFirstSynergyActivated(): boolean
	return player:GetAttribute("FirstSynergyActivated") == true
end

local function isSynergyReferenceUnlocked(): boolean
	return player:GetAttribute("SynergyReferenceUnlocked") == true
end

local function isFirstArtifactFound(): boolean
	return player:GetAttribute("FirstArtifactFound") == true
end

local function isFirstArtifactEquipped(): boolean
	return player:GetAttribute("FirstArtifactEquipped") == true
end

local function getArtifactPriorityScore(artifact)
	if type(artifact) ~= "table" then
		return 0
	end

	local stats = ArtifactConfig.CalculateArtifactStats(artifact)
	local score = 0
	score += math.max(0, (1 - (tonumber(stats.CycleTimeMult) or 1)) * 100)
	score += math.max(0, (tonumber(stats.LuckBonus) or 0) * 120)
	score += math.max(0, (tonumber(stats.ItemTierBonus) or 0) * 75)
	score += math.max(0, (tonumber(stats.SynergyRangeBonus) or 0) * 40)

	local rarityWeights = {
		Common = 1,
		Uncommon = 2,
		Rare = 3,
		Epic = 4,
		Legendary = 5,
	}
	score += (rarityWeights[tostring(artifact.Rarity or "")] or 0) * 25
	return score
end

local function getOwnedUnitMap(): {[string]: boolean}
	local owned = {}

	for _, unit in CollectionService:GetTagged("ActiveBrainrot") do
		if unit:GetAttribute("OwnerId") == player.UserId then
			local unitType = unit:GetAttribute("UnitType")
			if type(unitType) == "string" and unitType ~= "" then
				owned[unitType] = true
			end
		end
	end

	if not GetInventoryRemote then
		return owned
	end

	local success, inventory = pcall(function()
		return GetInventoryRemote:InvokeServer()
	end)
	if not success or type(inventory) ~= "table" then
		return owned
	end

	for unitName, unitData in pairs(inventory.units or {}) do
		if type(unitName) == "string" and type(unitData) == "table" then
			local level = tonumber(unitData.level) or 0
			if level > 0 then
				owned[unitName] = true
			end
		end
	end

	return owned
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
		Color = Color3.new(1, 1, 1),
		Transparency = 0.2,
		Size = UDim2.new(0, 500, 0, 600),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Anchor = Vector2.new(0.5, 0.5),
		Corner = 18,
		Stroke = Color3.fromRGB(70, 70, 90),
		Parent = backdrop,
	})
	
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.PANEL),
		ColorSequenceKeypoint.new(1, COLORS.BG)
	})
	gradient.Rotation = 90
	gradient.Parent = panel
	
	-- Gradient top accent
	local _accentBar = createFrame({
		Name = "AccentBar",
		Color = COLORS.ACCENT,
		Size = UDim2.new(1, 0, 0, 4),
		Corner = 18,
		Parent = panel,
	})
	
	-- Header section
	local header = createFrame({
		Name = "Header",
		Color = COLORS.PANEL,
		Transparency = 1,
		Size = UDim2.new(1, -32, 0, 96),
		Position = UDim2.new(0, 16, 0, 16),
		Parent = panel,
	})
	
	local titleLabel = createLabel({
		Name = "Title",
		Text = "⚙️ Production Config",
		Font = FONT.TITLE,
		Size = 22,
		FrameSize = UDim2.new(1, -80, 0, 28),
		Parent = header,
	})
	
	local subtitleLabel = createLabel({
		Name = "Subtitle",
		Text = "Lv. 1 • Normal",
		Color = COLORS.TEXT_DIM,
		Size = 14,
		FrameSize = UDim2.new(1, -170, 0, 20),
		Position = UDim2.new(0, 0, 0, 30),
		Parent = header,
	})

	local upgradeSummaryLabel = createLabel({
		Name = "UpgradeSummary",
		Text = "Next upgrade: $0",
		Color = COLORS.ACCENT_GOLD,
		Size = 12,
		FrameSize = UDim2.new(1, -170, 0, 20),
		Position = UDim2.new(0, 0, 0, 58),
		Parent = header,
	})

	local upgradeBtn = createButton({
		Name = "UpgradeBtn",
		Text = "Upgrade",
		Color = COLORS.ACCENT_GOLD,
		TextColor = COLORS.BG,
		Font = FONT.TITLE,
		Size = 14,
		FrameSize = UDim2.new(0, 150, 0, 34),
		Position = UDim2.new(1, 0, 1, 0),
		Corner = 10,
		Parent = header,
	})
	upgradeBtn.AnchorPoint = Vector2.new(1, 1)
	
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
	
	-- Tabs Container
	local tabsContainer = createFrame({
		Name = "TabsContainer",
		Color = COLORS.BG,
		Transparency = 1,
		Size = UDim2.new(1, -32, 0, 36),
		Position = UDim2.new(0, 16, 0, 118),
		Parent = panel,
	})
	
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabsContainer
	
	local prodTab = createButton({
		Name = "ProductionTab",
		Text = "⚙️ Production",
		Color = COLORS.TAB_ACTIVE,
		Size = 14,
		FrameSize = UDim2.new(0.33, -4, 1, 0),
		Corner = 8,
		Parent = tabsContainer,
	})
	
	local equipTab = createButton({
		Name = "EquipmentTab",
		Text = "📿 Equipment",
		Color = COLORS.TAB_INACTIVE,
		Size = 14,
		FrameSize = UDim2.new(0.33, -4, 1, 0),
		Corner = 8,
		Parent = tabsContainer,
	})
	
	local synTab = createButton({
		Name = "SynergiesTab",
		Text = "🔗 Synergies",
		Color = COLORS.TAB_INACTIVE,
		Size = 14,
		FrameSize = UDim2.new(0.34, -4, 1, 0),
		Corner = 8,
		Parent = tabsContainer,
	})
	
	-- Content Area
	local contentArea = createFrame({
		Name = "ContentArea",
		Transparency = 1,
		Size = UDim2.new(1, -32, 1, -178),
		Position = UDim2.new(0, 16, 0, 164),
		Parent = panel,
	})
	
	-- 1. Modes Container (Production Tab)
	local modesContainer = createFrame({
		Name = "ModesContainer",
		Transparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = contentArea,
	})
	
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = modesContainer
	
	-- Apply button (Production Tab)
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
	
	-- 2. Equipment Container (Equipment Tab)
	local equipmentContainer = createFrame({
		Name = "EquipmentContainer",
		Transparency = 1,
		Size = UDim2.new(1, 0, 1, 30), -- Taller to use apply button space
		Parent = contentArea,
	})
	equipmentContainer.Visible = false
	
	-- Top: Preview + Slots
	local splitContainer = createFrame({
		Name = "Split",
		Transparency = 1,
		Size = UDim2.new(1, 0, 0, 200),
		Parent = equipmentContainer,
	})
	
	-- Left: Preview
	local previewFrame = createFrame({
		Name = "Preview",
		Color = COLORS.BG,
		Size = UDim2.new(0.4, -4, 1, 0),
		Corner = 8,
		Stroke = COLORS.BORDER,
		Parent = splitContainer,
	})
	
	-- Right: Slots
	local slotsFrame = createFrame({
		Name = "Slots",
		Transparency = 1,
		Size = UDim2.new(0.6, -4, 1, 0),
		Position = UDim2.new(0.4, 8, 0, 0),
		Parent = splitContainer,
	})
	
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotLayout.Padding = UDim.new(0, 6)
	slotLayout.Parent = slotsFrame
	
	-- Stats Overlay in Preview
	local statsOverlay = createFrame({
		Name = "StatsOverlay",
		Color = COLORS.OVERLAY_BG,
		Transparency = 0.2,
		Size = UDim2.new(1, -16, 0, 80),
		Position = UDim2.new(0, 8, 1, -8),
		Anchor = Vector2.new(0, 1),
		Corner = 8,
		Parent = previewFrame,
	})
	
	statsLabels.Base = createLabel({
		Name = "BaseStats",
		Text = "Base: --",
		Color = COLORS.TEXT_DIM,
		Size = 10,
		FrameSize = UDim2.new(1, -10, 0, 16),
		Position = UDim2.new(0, 5, 0, 4),
		Parent = statsOverlay,
	})
	
	statsLabels.Multipliers = createLabel({
		Name = "Multipliers",
		Text = "Artifacts: --",
		Color = COLORS.ACCENT_GOLD,
		Size = 10,
		FrameSize = UDim2.new(1, -10, 0, 32), -- Multiline
		Position = UDim2.new(0, 5, 0, 20),
		Parent = statsOverlay,
	})
	statsLabels.Multipliers.TextYAlignment = Enum.TextYAlignment.Top
	statsLabels.Multipliers.TextWrapped = true
	
	statsLabels.Total = createLabel({
		Name = "TotalStats",
		Text = "Total: --",
		Color = COLORS.ACCENT_GREEN,
		Size = 11,
		Font = FONT.TITLE,
		FrameSize = UDim2.new(1, -10, 0, 20),
		Position = UDim2.new(0, 5, 1, -24),
		Parent = statsOverlay,
	})
	
	-- Bottom: Inventory
	local invFrame = createFrame({
		Name = "Inventory",
		Color = COLORS.BG,
		Size = UDim2.new(1, 0, 1, -210),
		Position = UDim2.new(0, 0, 0, 210),
		Corner = 8,
		Stroke = COLORS.BORDER,
		Parent = equipmentContainer,
	})
	
	local _invLabel = createLabel({
		Name = "Title",
		Text = "Inventory",
		Color = COLORS.TEXT_DIM,
		Size = 12,
		FrameSize = UDim2.new(1, -16, 0, 24),
		Position = UDim2.new(0, 8, 0, 0),
		Parent = invFrame,
	})
	
	local invScroll = Instance.new("ScrollingFrame")
	invScroll.Name = "Scroll"
	invScroll.Size = UDim2.new(1, -10, 1, -30)
	invScroll.Position = UDim2.new(0, 5, 0, 25)
	invScroll.BackgroundTransparency = 1
	invScroll.BorderSizePixel = 0
	invScroll.ScrollBarThickness = 4
	invScroll.ScrollBarImageColor3 = COLORS.ACCENT
	invScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	invScroll.Parent = invFrame
	
	local invLayout = Instance.new("UIListLayout")
	invLayout.SortOrder = Enum.SortOrder.Name
	invLayout.Padding = UDim.new(0, 4)
	invLayout.Parent = invScroll
	
	-- 3. Synergies Container (Synergies Tab)
	local synergiesContainer = createFrame({
		Name = "SynergiesContainer",
		Transparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = contentArea,
	})
	synergiesContainer.Visible = false
	
	local synScroll = Instance.new("ScrollingFrame")
	synScroll.Name = "Scroll"
	synScroll.Size = UDim2.new(1, 0, 1, 0)
	synScroll.BackgroundTransparency = 1
	synScroll.BorderSizePixel = 0
	synScroll.ScrollBarThickness = 4
	synScroll.ScrollBarImageColor3 = COLORS.ACCENT
	synScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	synScroll.Parent = synergiesContainer
	
	local synLayout = Instance.new("UIListLayout")
	synLayout.SortOrder = Enum.SortOrder.LayoutOrder
	synLayout.Padding = UDim.new(0, 8)
	synLayout.Parent = synScroll
	
	return {
		gui = screenGui,
		backdrop = backdrop,
		panel = panel,
		titleLabel = titleLabel,
		subtitleLabel = subtitleLabel,
		upgradeSummaryLabel = upgradeSummaryLabel,
		upgradeBtn = upgradeBtn,
		closeBtn = closeBtn,
		prodTab = prodTab,
		equipTab = equipTab,
		synTab = synTab,
		modesContainer = modesContainer,
		equipmentContainer = equipmentContainer,
		synergiesContainer = synergiesContainer,
		synScroll = synScroll,
		synLayout = synLayout,
		applyBtn = applyBtn,
		previewFrame = previewFrame,
		slotsFrame = slotsFrame,
		invScroll = invScroll,
		invLayout = invLayout,
	}
end

--------------------------------------------------------------------------------
-- POPULATE & INTERACTION
--------------------------------------------------------------------------------

local ui = buildUI()
local selectedMode = 1
local modeCards = {}

local function refreshHeader()
	if not currentData then
		ui.titleLabel.Text = "⚙️ Production Config"
		ui.subtitleLabel.Text = "Lv. 1 • Normal"
		ui.upgradeSummaryLabel.Text = "Next upgrade: $0"
		ui.upgradeBtn.Text = "Upgrade"
		ui.upgradeBtn.Active = false
		ui.upgradeBtn.AutoButtonColor = false
		ui.upgradeBtn.BackgroundColor3 = COLORS.TEXT_DIM
		return
	end

	local currentLevel = tonumber(currentData.level) or 1
	ui.titleLabel.Text = "⚙️ " .. (currentData.unitType or "Unknown")
	ui.subtitleLabel.Text = string.format("Lv. %d • %s", currentLevel, currentData.rarity or "Normal")
	ui.upgradeSummaryLabel.Text = buildUpgradeSummary(currentData.unitType, currentLevel)
	ui.upgradeBtn.Text = string.format("Upgrade to Lv. %d", currentLevel + 1)
	ui.upgradeBtn.Active = true
	ui.upgradeBtn.AutoButtonColor = true
	ui.upgradeBtn.BackgroundColor3 = COLORS.ACCENT_GOLD
end

-- Helper to switch tabs
local function switchTab(tabName)
	currentTab = tabName
	
	ui.prodTab.BackgroundColor3 = COLORS.TAB_INACTIVE
	ui.equipTab.BackgroundColor3 = COLORS.TAB_INACTIVE
	ui.synTab.BackgroundColor3 = COLORS.TAB_INACTIVE
	ui.modesContainer.Visible = false
	ui.equipmentContainer.Visible = false
	ui.synergiesContainer.Visible = false
	ui.applyBtn.Visible = false
	
	if tabName == "Production" then
		ui.prodTab.BackgroundColor3 = COLORS.TAB_ACTIVE
		ui.modesContainer.Visible = true
		ui.applyBtn.Visible = true
	elseif tabName == "Equipment" then
		ui.equipTab.BackgroundColor3 = COLORS.TAB_ACTIVE
		ui.equipmentContainer.Visible = true
	elseif tabName == "Synergies" then
		ui.synTab.BackgroundColor3 = COLORS.TAB_ACTIVE
		ui.synergiesContainer.Visible = true
	end
end

ui.prodTab.MouseButton1Click:Connect(function() switchTab("Production") end)
ui.equipTab.MouseButton1Click:Connect(function() switchTab("Equipment") end)
ui.synTab.MouseButton1Click:Connect(function() switchTab("Synergies") end)

--------------------------------------------------------------------------------
-- PRODUCTION TAB LOGIC
--------------------------------------------------------------------------------

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
	local _basePrice = itemDef and itemDef.basePrice or 0
	
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
		
		createLabel({
			Name = "RPS",
			Text = string.format("%.1f %s / s", rps, displayName),
			Font = FONT.MONO,
			Size = 14,
			Color = COLORS.ACCENT_GREEN,
			AlignX = Enum.TextXAlignment.Right,
			FrameSize = UDim2.new(0, 160, 0, 20),
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
	-- Clear existing cards and banner
	for _, card in ipairs(modeCards) do
		card:Destroy()
	end
	modeCards = {}
	
	if ui.modesContainer:FindFirstChild("SynergyBanner") then
		ui.modesContainer.SynergyBanner:Destroy()
	end
	
	if not currentData then return end
	
	local unitType = currentData.unitType
	local level = currentData.level or 1
	local modes = ItemConfig.GetAvailableModes(unitType, level)
	
	if #modes == 0 then return end
	
	-- Synergy checking
	local activeSynergy = nil
	if currentData.gridSlot and currentData.unitType then
		local slotToUnit = {}
		for _, unit in CollectionService:GetTagged("ActiveBrainrot") do
			if unit:GetAttribute("OwnerId") == player.UserId then
				local slot = unit:GetAttribute("GridSlot")
				if slot then slotToUnit[slot] = unit end
			end
		end
		local clusterIdx = math.floor((currentData.gridSlot - 1) / 4)
		local baseSlot = clusterIdx * 4 + 1
		local clusterSlots = { baseSlot, baseSlot+1, baseSlot+2, baseSlot+3 }
		for _, neighborSlot in ipairs(clusterSlots) do
			if neighborSlot ~= currentData.gridSlot and slotToUnit[neighborSlot] then
				local nType = slotToUnit[neighborSlot]:GetAttribute("UnitType")
				if nType then
					local syn = ItemConfig.GetSynergyOverride(currentData.unitType, nType)
					if syn then activeSynergy = syn; break end
				end
			end
		end
	end

	-- Add Active Synergy Banner
	if activeSynergy then
		local synItem = ItemConfig.Items[activeSynergy.synergyItem]
		local bannerStr = string.format("✨ SYNERGY ACTIVE: Producing %s %s at %sx Speed! ✨", synItem.icon or "", synItem.displayName or "", activeSynergy.bonus)
		local banner = createFrame({
			Name = "SynergyBanner",
			Color = Color3.fromRGB(80, 40, 100), -- Deep purple
			Size = UDim2.new(1, 0, 0, 36),
			Corner = 8,
			Stroke = COLORS.SYNERGY,
			Parent = ui.modesContainer,
		})
		banner.LayoutOrder = -1 -- Keep it at the top
		
		createLabel({
			Name = "BannerText",
			Text = bannerStr,
			Font = FONT.TITLE,
			Size = 13,
			Color = Color3.fromRGB(240, 200, 255),
			AlignX = Enum.TextXAlignment.Center,
			FrameSize = UDim2.new(1, 0, 1, 0),
			Parent = banner,
		})
	end
	
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

function refreshSynergies()
	for _, c in ui.synScroll:GetChildren() do
		if c:IsA("Frame") then c:Destroy() end
	end
	
	if not currentData or not currentData.unitType then return end
	
	-- Active synergy detection
	local slotToUnit = {}
	for _, unit in CollectionService:GetTagged("ActiveBrainrot") do
		if unit:GetAttribute("OwnerId") == player.UserId then
			local slot = unit:GetAttribute("GridSlot")
			if slot then slotToUnit[slot] = unit end
		end
	end
	local clusterIdx = math.floor((currentData.gridSlot - 1) / 4)
	local baseSlot = clusterIdx * 4 + 1
	local clusterSlots = { baseSlot, baseSlot+1, baseSlot+2, baseSlot+3 }
	local activeNeighbors = {}
	for _, neighborSlot in ipairs(clusterSlots) do
		if neighborSlot ~= currentData.gridSlot and slotToUnit[neighborSlot] then
			local nType = slotToUnit[neighborSlot]:GetAttribute("UnitType")
			if nType then activeNeighbors[nType] = true end
		end
	end

	-- List all possible synergies for this unit
	local possibleSynergies = {}
	for _, syn in ipairs(ItemConfig.Synergies or {}) do
		if syn.unitA == currentData.unitType then
			table.insert(possibleSynergies, { partner = syn.unitB, data = syn })
		elseif syn.unitB == currentData.unitType then
			table.insert(possibleSynergies, { partner = syn.unitA, data = syn })
		end
	end
	
	if #possibleSynergies == 0 then
		createLabel({
			Text = "This unit has no known synergies.",
			Color = COLORS.TEXT_DIM,
			Size = 14,
			AlignX = Enum.TextXAlignment.Center,
			Parent = ui.synScroll,
		})
		return
	end

	local ownedUnits = getOwnedUnitMap()
	table.sort(possibleSynergies, function(a, b)
		local aActive = activeNeighbors[a.partner] == true
		local bActive = activeNeighbors[b.partner] == true
		if aActive ~= bActive then
			return aActive
		end

		local aOwned = ownedUnits[a.partner] == true
		local bOwned = ownedUnits[b.partner] == true
		if aOwned ~= bOwned then
			return aOwned
		end

		local aValue = (ItemConfig.Items[a.data.synergyItem] and ItemConfig.Items[a.data.synergyItem].basePrice) or 0
		local bValue = (ItemConfig.Items[b.data.synergyItem] and ItemConfig.Items[b.data.synergyItem].basePrice) or 0
		if aValue ~= bValue then
			return aValue > bValue
		end

		return tostring(a.partner) < tostring(b.partner)
	end)

	if not isFirstSynergyActivated() and not isSynergyReferenceUnlocked() then
		createLabel({
			Text = "Starter Pair",
			Font = FONT.TITLE,
			Size = 16,
			Color = COLORS.SYNERGY,
			FrameSize = UDim2.new(1, -4, 0, 24),
			Parent = ui.synScroll,
		})

		createLabel({
			Text = "Start with one hybrid combo. Place both units in the same 2x2 cluster.",
			Size = 12,
			Color = COLORS.TEXT_DIM,
			FrameSize = UDim2.new(1, -4, 0, 32),
			Parent = ui.synScroll,
		})

		local starterSyn = possibleSynergies[1]
		local outItem = ItemConfig.Items[starterSyn.data.synergyItem]
		local outName = outItem and outItem.displayName or "Unknown"
		local outIcon = outItem and outItem.icon or "Item"
		local card = createFrame({
			Name = "StarterSynCard",
			Color = activeNeighbors[starterSyn.partner] and COLORS.CARD_SELECTED or COLORS.CARD,
			Size = UDim2.new(1, -10, 0, 92),
			Position = UDim2.new(0, 5, 0, 0),
			Corner = 8,
			Stroke = activeNeighbors[starterSyn.partner] and COLORS.SYNERGY or COLORS.BORDER,
			Parent = ui.synScroll,
		})

		createLabel({
			Text = outIcon,
			Size = 32,
			AlignX = Enum.TextXAlignment.Center,
			FrameSize = UDim2.new(0, 60, 1, 0),
			Parent = card,
		})

		createLabel({
			Text = string.format("Hybrid: %s %s", outIcon, outName),
			Font = FONT.TITLE,
			Size = 14,
			Color = COLORS.TEXT,
			FrameSize = UDim2.new(1, -150, 0, 20),
			Position = UDim2.new(0, 60, 0, 10),
			Parent = card,
		})

		createLabel({
			Text = string.format("Pair with: %s", tostring(starterSyn.partner):gsub("_", " ")),
			Size = 12,
			Color = COLORS.TEXT_DIM,
			FrameSize = UDim2.new(1, -150, 0, 16),
			Position = UDim2.new(0, 60, 0, 32),
			Parent = card,
		})

		local starterStatus = "Rule: same 2x2 cluster"
		if activeNeighbors[starterSyn.partner] then
			starterStatus = "Hybrid pair active now"
		elseif ownedUnits[starterSyn.partner] == true then
			starterStatus = "You already own the partner"
		end
		createLabel({
			Text = starterStatus,
			Size = 12,
			Color = activeNeighbors[starterSyn.partner] and COLORS.SYNERGY or COLORS.ACCENT_GREEN,
			FrameSize = UDim2.new(1, -150, 0, 16),
			Position = UDim2.new(0, 60, 0, 52),
			Parent = card,
		})

		createLabel({
			Name = "StarterStatus",
			Text = activeNeighbors[starterSyn.partner] and "ACTIVE" or "TRY THIS",
			Font = FONT.TITLE,
			Size = 12,
			Color = activeNeighbors[starterSyn.partner] and COLORS.SYNERGY or COLORS.ACCENT_GOLD,
			AlignX = Enum.TextXAlignment.Right,
			FrameSize = UDim2.new(0, 84, 0, 20),
			Position = UDim2.new(1, -98, 0.5, -10),
			Parent = card,
		})

		createLabel({
			Text = "More pairings reveal after your first hybrid.",
			Size = 12,
			Color = COLORS.TEXT_LOCKED,
			FrameSize = UDim2.new(1, -4, 0, 24),
			Parent = ui.synScroll,
		})

		ui.synScroll.CanvasSize = UDim2.new(0, 0, 0, ui.synLayout.AbsoluteContentSize.Y + 10)
		return
	end
	
	for i, pSyn in ipairs(possibleSynergies) do
		local isActive = activeNeighbors[pSyn.partner] == true
		local color = isActive and COLORS.CARD_SELECTED or COLORS.CARD
		local strokeColor = isActive and COLORS.SYNERGY or COLORS.BORDER
		
		local card = createFrame({
			Name = "SynCard_" .. i,
			Color = color,
			Size = UDim2.new(1, -10, 0, 80),
			Position = UDim2.new(0, 5, 0, 0),
			Corner = 8,
			Stroke = strokeColor,
			Parent = ui.synScroll,
		})
		card.LayoutOrder = i
		
		local outItem = ItemConfig.Items[pSyn.data.synergyItem]
		local outName = outItem and outItem.displayName or "Unknown"
		local outIcon = outItem and outItem.icon or "📦"
		
		createLabel({
			Text = outIcon,
			Size = 32,
			AlignX = Enum.TextXAlignment.Center,
			FrameSize = UDim2.new(0, 60, 1, 0),
			Parent = card,
		})
		
		createLabel({
			Text = string.format("Produces: %s %s", outIcon, outName),
			Font = FONT.TITLE,
			Size = 14,
			Color = COLORS.TEXT,
			FrameSize = UDim2.new(1, -140, 0, 20),
			Position = UDim2.new(0, 60, 0, 10),
			Parent = card,
		})
		
		createLabel({
			Text = string.format("Requires: 🧩 %s", pSyn.partner),
			Size = 12,
			Color = COLORS.TEXT_DIM,
			FrameSize = UDim2.new(1, -140, 0, 16),
			Position = UDim2.new(0, 60, 0, 32),
			Parent = card,
		})
		
		createLabel({
			Text = string.format("⚡ +%.0f%% Speed", (pSyn.data.bonus - 1) * 100),
			Size = 12,
			Color = COLORS.ACCENT_GREEN,
			FrameSize = UDim2.new(1, -140, 0, 16),
			Position = UDim2.new(0, 60, 0, 52),
			Parent = card,
		})
		
		if isActive then
			createLabel({
				Name = "ActiveLabel",
				Text = "▶ ACTIVE",
				Font = FONT.TITLE,
				Size = 12,
				Color = COLORS.SYNERGY,
				AlignX = Enum.TextXAlignment.Right,
				FrameSize = UDim2.new(0, 70, 0, 20),
				Position = UDim2.new(1, -86, 0.5, -10),
				Parent = card,
			})
		else
			createLabel({
				Name = "InactiveLabel",
				Text = "INACTIVE",
				Size = 12,
				Color = COLORS.TEXT_LOCKED,
				AlignX = Enum.TextXAlignment.Right,
				FrameSize = UDim2.new(0, 70, 0, 20),
				Position = UDim2.new(1, -86, 0.5, -10),
				Parent = card,
			})
		end
	end
	
	ui.synScroll.CanvasSize = UDim2.new(0, 0, 0, ui.synLayout.AbsoluteContentSize.Y + 10)
end

--------------------------------------------------------------------------------
-- EQUIPMENT TAB LOGIC
--------------------------------------------------------------------------------

local function setupPreview(unitType)
	-- Clear old
	if previewInstance then
		previewInstance:Destroy()
		previewInstance = nil
	end
	
	-- Find model
	local modelTemplate = BrainrotsFolder:FindFirstChild(unitType)
	if not modelTemplate then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		if assets then
			local brainrots = assets:FindFirstChild("Brainrots")
			if brainrots then
				modelTemplate = brainrots:FindFirstChild(unitType)
			end
		end
	end

	if not modelTemplate then return end
	
	-- Create preview
	previewInstance = ViewportPreview.Create(modelTemplate, ui.previewFrame)
end

local function refreshEquipment()
	if not currentData then return end
	
	-- Get artifacts from server
	local success, data = pcall(function()
		return GetArtifacts:InvokeServer()
	end)
	
	if not success or not data then return end
	
	-- Clear lists
	for _, c in ui.slotsFrame:GetChildren() do
		if c:IsA("Frame") then c:Destroy() end
	end
	for _, c in ui.invScroll:GetChildren() do
		if c:IsA("Frame") then c:Destroy() end
	end

	local artifactUnlocked = player:GetAttribute("ArtifactsUnlocked") == true
	local firstArtifactFound = isFirstArtifactFound()
	local firstArtifactEquipped = isFirstArtifactEquipped()
	
	-- 1. EQUIPMENT SLOTS & STATS CALCULATION
	local equippedToUnit = {}
	local combinedStats = {
		CycleTimeMult = 1,
		LuckBonus = 0,
		ItemTierBonus = 0,
		SynergyRangeBonus = 0,
	}
	
	for guid, artifact in pairs(data.all or {}) do
		if artifact.EquippedTo == currentData.unitGUID then
			equippedToUnit[artifact.Slot] = artifact
			local stats = ArtifactConfig.CalculateArtifactStats(artifact)
			combinedStats.CycleTimeMult = combinedStats.CycleTimeMult * stats.CycleTimeMult
			combinedStats.LuckBonus = combinedStats.LuckBonus + stats.LuckBonus
			combinedStats.ItemTierBonus = combinedStats.ItemTierBonus + stats.ItemTierBonus
			combinedStats.SynergyRangeBonus = combinedStats.SynergyRangeBonus + stats.SynergyRangeBonus
		end
	end
	
	-- Update Stats Overlay
	local modeInfo = ItemConfig.GetMode(currentData.unitType, currentData.level, currentData.currentMode)
	if modeInfo then
		local baseRps = 1 / modeInfo.rate
		local itemDef = ItemConfig.Items[modeInfo.itemId]
		local displayName = itemDef and itemDef.displayName or "Item"
		
		statsLabels.Base.Text = string.format("Base: %.2f/s", baseRps)
		
		local mults = {}
		if combinedStats.CycleTimeMult < 1 then
			table.insert(mults, string.format("⚡+%.0f%% Spd", (1/combinedStats.CycleTimeMult - 1) * 100))
		end
		if combinedStats.LuckBonus > 0 then
			table.insert(mults, string.format("🍀+%.0f%% Luck", combinedStats.LuckBonus * 100))
		end
		if combinedStats.SynergyRangeBonus > 0 then
			table.insert(mults, string.format("🔗+%d Rng", combinedStats.SynergyRangeBonus))
		end
		
		if #mults > 0 then
			statsLabels.Multipliers.Text = table.concat(mults, " • ")
		else
			statsLabels.Multipliers.Text = "No artifact bonuses"
		end
		
		local finalRps = baseRps / combinedStats.CycleTimeMult
		statsLabels.Total.Text = string.format("Total: %.2f %s/s", finalRps, displayName)
	end
	
	-- Helper to format bonuses
	local function getBonusText(artifact)
		local stats = ArtifactConfig.CalculateArtifactStats(artifact)
		local parts = {}
		if stats.CycleTimeMult < 1 then
			table.insert(parts, string.format("⚡+%.0f%% Spd", (1/stats.CycleTimeMult - 1) * 100))
		end
		if stats.LuckBonus > 0 then
			table.insert(parts, string.format("🍀+%.0f%% Luck", stats.LuckBonus * 100))
		end
		if stats.SynergyRangeBonus > 0 then
			table.insert(parts, string.format("🔗+%d Rng", stats.SynergyRangeBonus))
		end
		if stats.ItemTierBonus > 0 then
			table.insert(parts, string.format("💎+%d Tier", stats.ItemTierBonus))
		end
		return table.concat(parts, " • ")
	end

	local function createEquipmentHint(titleText, bodyText, accentColor)
		local hintFrame = createFrame({
			Name = "ArtifactHint",
			Color = COLORS.BG,
			Size = UDim2.new(1, 0, 0, 58),
			Corner = 8,
			Stroke = accentColor,
			Parent = ui.slotsFrame,
		})
		hintFrame.LayoutOrder = -1

		createLabel({
			Text = titleText,
			Font = FONT.TITLE,
			Size = 12,
			Color = accentColor,
			FrameSize = UDim2.new(1, -14, 0, 18),
			Position = UDim2.new(0, 8, 0, 6),
			Parent = hintFrame,
		})

		local body = createLabel({
			Text = bodyText,
			Size = 11,
			Color = COLORS.TEXT_DIM,
			FrameSize = UDim2.new(1, -14, 0, 28),
			Position = UDim2.new(0, 8, 0, 24),
			Parent = hintFrame,
		})
		body.TextWrapped = true
		body.TextYAlignment = Enum.TextYAlignment.Top
	end

	if artifactUnlocked then
		if not firstArtifactFound then
			createEquipmentHint(
				"Relics are online",
				"Your first relic should drop soon. Keep producing, then slot it into any matching gear slot here.",
				COLORS.ACCENT_GOLD
			)
		elseif not firstArtifactEquipped then
			createEquipmentHint(
				"First relic",
				"Equip one relic on a producer. Speed, luck, tier, and synergy bonuses apply immediately.",
				COLORS.ACCENT_GOLD
			)
		end
	end

	for i, slotName in ipairs({"Head", "Body", "Accessory"}) do
		local slotFrame = createFrame({
			Name = "Slot_" .. slotName,
			Color = COLORS.CARD,
			Size = UDim2.new(1, 0, 0, 50),
			Corner = 8,
			Parent = ui.slotsFrame,
		})
		slotFrame.LayoutOrder = i
		
		local artifact = equippedToUnit[slotName]
		local iconStr = ArtifactConfig.SlotIcons[slotName]
		local nameStr = "Empty"
		local color = COLORS.TEXT_DIM
		local bonusStr = ""
		
		if artifact then
			-- Fix for blank icon: Ensure we have a valid string, otherwise fallback to slot icon
			if artifact.BaseIcon and artifact.BaseIcon ~= "" then
				iconStr = artifact.BaseIcon
			end
			nameStr = artifact.Name
			color = getRarityColor(artifact.Rarity)
			bonusStr = getBonusText(artifact)
		end
		
		createLabel({
			Name = "Icon",
			Text = iconStr,
			Size = 24,
			AlignX = Enum.TextXAlignment.Center,
			FrameSize = UDim2.new(0, 40, 1, 0),
			Parent = slotFrame,
		})
		
		createLabel({
			Name = "SlotLabel",
			Text = slotName:upper(),
			Size = 9,
			Color = COLORS.TEXT_DIM,
			FrameSize = UDim2.new(1, -60, 0, 12),
			Position = UDim2.new(0, 42, 0, 4),
			Parent = slotFrame,
		})
		
		createLabel({
			Name = "NameLabel",
			Text = nameStr,
			Size = 12,
			Color = color,
			FrameSize = UDim2.new(1, -60, 0, 16),
			Position = UDim2.new(0, 42, 0, 16),
			Parent = slotFrame,
		})
		
		if bonusStr ~= "" then
			createLabel({
				Name = "BonusLabel",
				Text = bonusStr,
				Size = 9,
				Color = COLORS.ACCENT_GREEN,
				FrameSize = UDim2.new(1, -60, 0, 12),
				Position = UDim2.new(0, 42, 0, 32),
				Parent = slotFrame,
			})
		end
		
		if artifact then
			local removeBtn = createButton({
				Name = "RemoveBtn",
				Text = "Remove",
				Color = COLORS.CLOSE_BTN,
				Size = 10,
				FrameSize = UDim2.new(0, 50, 0, 24),
				Position = UDim2.new(1, -55, 0.5, -12),
				Corner = 4,
				Parent = slotFrame,
			})
			
			removeBtn.MouseButton1Click:Connect(function()
				UnequipArtifact:InvokeServer(currentData.unitGUID, slotName)
				task.wait(0.2) -- Increased wait to ensure server sync
				refreshEquipment()
			end)
		end
	end
	
	-- 2. INVENTORY LIST
	local unequipped = data.unequipped or {}
	table.sort(unequipped, function(a, b)
		return getArtifactPriorityScore(a) > getArtifactPriorityScore(b)
	end)
	
	if #unequipped == 0 then
		createLabel({
			Text = artifactUnlocked and not firstArtifactFound
				and "Your first relic should drop soon..."
				or "No artifacts available...",
			Color = COLORS.TEXT_DIM,
			Size = 12,
			AlignX = Enum.TextXAlignment.Center,
			Parent = ui.invScroll,
		})
	else
		for index, artifact in ipairs(unequipped) do
			local itemFrame = createFrame({
				Name = "Artifact",
				Color = COLORS.CARD,
				Size = UDim2.new(1, 0, 0, 50), -- Increased height for stats
				Corner = 6,
				Parent = ui.invScroll,
			})
			
			-- Rarity bar
			local bar = Instance.new("Frame")
			bar.Size = UDim2.new(0, 4, 1, 0)
			bar.BackgroundColor3 = getRarityColor(artifact.Rarity)
			bar.BorderSizePixel = 0
			bar.Parent = itemFrame
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 2)
			c.Parent = bar
			
			createLabel({
				Text = artifact.BaseIcon or "📦",
				Size = 20,
				AlignX = Enum.TextXAlignment.Center,
				FrameSize = UDim2.new(0, 30, 1, 0),
				Position = UDim2.new(0, 8, 0, 0),
				Parent = itemFrame,
			})
			
			createLabel({
				Text = artifact.Name,
				Size = 12,
				Color = getRarityColor(artifact.Rarity),
				FrameSize = UDim2.new(1, -100, 0, 16),
				Position = UDim2.new(0, 40, 0, 6),
				Parent = itemFrame,
			})
			
			createLabel({
				Text = (ArtifactConfig.SlotIcons[artifact.Slot] or "") .. " " .. artifact.Slot,
				Size = 10,
				Color = COLORS.TEXT_DIM,
				FrameSize = UDim2.new(1, -100, 0, 14),
				Position = UDim2.new(0, 40, 0, 20),
				Parent = itemFrame,
			})
			
			local bonusStr = getBonusText(artifact)
			if bonusStr ~= "" then
				createLabel({
					Text = bonusStr,
					Size = 9,
					Color = COLORS.ACCENT_GREEN,
					FrameSize = UDim2.new(1, -100, 0, 12),
					Position = UDim2.new(0, 40, 0, 34),
					Parent = itemFrame,
				})
			end
			
			local equipBtn = createButton({
				Text = (not firstArtifactEquipped and index == 1) and "Try This" or "Equip",
				Color = (not firstArtifactEquipped and index == 1) and COLORS.ACCENT_GOLD or COLORS.ACCENT,
				Size = 10,
				FrameSize = UDim2.new(0, 50, 0, 24),
				Position = UDim2.new(1, -55, 0.5, -12),
				Corner = 4,
				Parent = itemFrame,
			})
			
			equipBtn.MouseButton1Click:Connect(function()
				EquipArtifact:InvokeServer(currentData.unitGUID, artifact.GUID, artifact.Slot)
				task.wait(0.2)
				refreshEquipment()
			end)
		end
	end
	
	ui.invScroll.CanvasSize = UDim2.new(0, 0, 0, ui.invLayout.AbsoluteContentSize.Y + 10)
end

--------------------------------------------------------------------------------
-- MAIN LOGIC
--------------------------------------------------------------------------------

local function openUI(unitData)
	currentData = unitData
	selectedMode = unitData.currentMode or 1
	
	refreshHeader()
	
	-- Setup both tabs
	refreshModeCards()
	setupPreview(unitData.unitType)
	refreshEquipment()
	refreshSynergies()
	
	-- Reset tab to Production
	switchTab("Production")
	
	-- Show
	ui.gui.Enabled = true
	isOpen = true
end

local function closeUI()
	ui.gui.Enabled = false
	isOpen = false
	currentData = nil
	refreshHeader()
	if previewInstance then
		previewInstance:Destroy()
		previewInstance = nil
	end
end

local function applyMode()
	if not currentData or not currentData.gridSlot then return end
	
	local success, err = SetUnitModeFunction:InvokeServer(currentData.gridSlot, selectedMode)
	
	if success then
		-- Update local data
		currentData.currentMode = selectedMode
		if isOpen and currentTab == "Production" then
			refreshModeCards()
		end
		
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

local function upgradeUnit()
	if not currentData or not currentData.unitType then
		return
	end

	ui.upgradeBtn.Text = "Upgrading..."
	ui.upgradeBtn.Active = false
	ui.upgradeBtn.AutoButtonColor = false

	local success, message, result = UpgradeUnitFromHUDFunction:InvokeServer(currentData.unitType)

	if success then
		currentData.level = (result and result.newLevel) or ((tonumber(currentData.level) or 1) + 1)
		refreshHeader()
		refreshModeCards()
		refreshEquipment()
		refreshSynergies()

		ui.upgradeBtn.Text = string.format("Lv. %d unlocked!", tonumber(currentData.level) or 1)
		ui.upgradeBtn.BackgroundColor3 = COLORS.ACCENT_GREEN
		task.delay(1.25, function()
			if currentData then
				refreshHeader()
			elseif ui.upgradeBtn then
				ui.upgradeBtn.Text = "Upgrade"
				ui.upgradeBtn.BackgroundColor3 = COLORS.TEXT_DIM
			end
		end)
	else
		ui.upgradeBtn.Text = "✕ " .. tostring(message)
		ui.upgradeBtn.BackgroundColor3 = COLORS.DANGER
		task.delay(2, function()
			if ui.upgradeBtn then
				refreshHeader()
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
ui.upgradeBtn.MouseButton1Click:Connect(upgradeUnit)

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

ui.invLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	ui.invScroll.CanvasSize = UDim2.new(0, 0, 0, ui.invLayout.AbsoluteContentSize.Y + 10)
end)

-- Auto refresh artifact list if changes occur
ArtifactDroppedEvent.OnClientEvent:Connect(function()
	if isOpen and currentTab == "Equipment" then
		refreshEquipment()
	end
end)
ArtifactEquippedEvent.OnClientEvent:Connect(function()
	if isOpen and currentTab == "Equipment" then
		refreshEquipment()
	end
end)

for _, attributeName in ipairs({
	"FirstSynergyActivated",
	"SynergyReferenceUnlocked",
}) do
	player:GetAttributeChangedSignal(attributeName):Connect(function()
		if not isOpen or not currentData then
			return
		end
		refreshModeCards()
		refreshSynergies()
	end)
end

for _, attributeName in ipairs({
	"ArtifactsUnlocked",
	"FirstArtifactFound",
	"FirstArtifactEquipped",
}) do
	player:GetAttributeChangedSignal(attributeName):Connect(function()
		if isOpen and currentTab == "Equipment" then
			refreshEquipment()
		end
	end)
end
