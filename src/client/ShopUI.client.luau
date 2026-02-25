--[[
	ShopUI LocalScript (Grid Refactor)
	
	Creates a Cookie Clicker style shop interface as a responsive grid of cards.
	Shows ALL 74 units — locked ones appear as black silhouettes to tease progression.
	
	Features:
	- Responsive grid panel (60% screen width, max 900px)
	- Static 3D previews (no spin — performance safe for 74 viewports)
	- Locked silhouette effect (black BaseParts, stripped textures)
	- Tier 1 item always visible on locked cards; higher tiers show "???"
	- Purchase animations, sound effects, affordability checks
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

-- Player reference
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Wait for shared modules and remotes
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local ShortfallCalc = require(Shared:WaitForChild("ShortfallCalc"))
local MarketConfig = require(Shared:WaitForChild("MarketConfig"))
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyUnitRemote = RemoteEvents:WaitForChild("BuyUnit")
local GetOwnershipRemote = RemoteEvents:WaitForChild("GetOwnership")
local OwnershipChangedEvent = RemoteEvents:WaitForChild("OwnershipChanged")
local UnlockProgressChangedEvent = RemoteEvents:WaitForChild("UnlockProgressChanged")

--------------------------------------------------------------------------------
-- UI CONFIGURATION
--------------------------------------------------------------------------------

local UI_CONFIG = {
	-- Shop Panel (responsive)
	SHOP_WIDTH_SCALE = 0.6,    -- 60% of screen width
	SHOP_MAX_WIDTH = 900,      -- Cap for large screens
	SHOP_PADDING = 12,
	
	-- Card sizing (grid cells)
	CARD_WIDTH = 160,
	CARD_HEIGHT = 260,
	GRID_PADDING = 8,
	
	-- Corner radius
	CORNER_RADIUS = 16,
	CARD_CORNER_RADIUS = 10,
	
	-- Colors
	BACKGROUND_COLOR = Color3.fromRGB(15, 15, 22),
	PANEL_COLOR = Color3.fromRGB(20, 20, 30),
	CARD_COLOR = Color3.fromRGB(30, 30, 45),
	CARD_HOVER_COLOR = Color3.fromRGB(40, 40, 60),
	CARD_DISABLED_COLOR = Color3.fromRGB(20, 20, 25),
	LOCKED_COLOR = Color3.fromRGB(15, 15, 20),
	LOCKED_OVERLAY_COLOR = Color3.fromRGB(0, 0, 0),
	ACCENT_COLOR = Color3.fromRGB(80, 230, 120),
	GOLD_COLOR = Color3.fromRGB(255, 195, 40),
	GOLD_HOVER_COLOR = Color3.fromRGB(255, 215, 80),
	TEXT_COLOR = Color3.fromRGB(250, 250, 255),
	SECONDARY_TEXT_COLOR = Color3.fromRGB(160, 160, 180),
	LOCKED_TEXT_COLOR = Color3.fromRGB(100, 100, 120),
	PRICE_COLOR = Color3.fromRGB(250, 190, 60),
	ITEM_COST_COLOR = Color3.fromRGB(255, 140, 50),
	ITEM_HAVE_COLOR = Color3.fromRGB(80, 230, 120),
	ITEM_NEED_COLOR = Color3.fromRGB(255, 70, 70),
	STROKE_COLOR = Color3.fromRGB(70, 70, 90),
	VIEWPORT_BG = Color3.fromRGB(25, 22, 35),
	
	-- Animation
	TWEEN_TIME = 0.2,
	
	-- Grid positions
	SHOP_OPEN_POSITION = UDim2.new(1, -10, 0, 10),
	SHOP_CLOSED_POSITION = UDim2.new(1, 50, 0, 10),
}

--------------------------------------------------------------------------------
-- SOUNDS
--------------------------------------------------------------------------------

local function createSound(id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	return sound
end

local ChachingSound = createSound("rbxassetid://138081500", 0.5)
local ErrorSound = createSound("rbxassetid://138090596", 0.3)

--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local OwnedCounts: {[string]: number} = {}
local ShopButtons: {[string]: Frame} = {}
local UnlockProgress: number = ShopConfig.INITIAL_UNLOCKED
local ShopGui: ScreenGui? = nil
local ScrollFrame: ScrollingFrame? = nil
local IsOnMainIsland: boolean = false

-- Inventory cache for shortfall calculation (both storage + backpack/cart)
local cachedStorageItems: {[string]: number} = {}
local cachedBackpackItems: {[string]: number} = {}
local shortfallDebounce = false

-- Client-side AMM rate reading (same as HFT Terminal)
local stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket", 10) or ReplicatedStorage
local MAX_BUY = MarketConfig.CONFIG.MAX_BUY_PER_TRANSACTION or 100

local function decodeItems(encoded)
	if not ItemConfig or not ItemConfig.SHORT_TO_ID then return encoded end
	if type(encoded) ~= "table" then return {} end
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

-- Client-local buy price (mirrors server MarketManager.getBuyPrice)
local function getClientBuyPrice(itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	local basePrice = info.basePrice or 1
	-- Read local rate from StockMarket attributes
	local localRatesJson = stockMarketFolder:GetAttribute("LocalItemRates")
	local localRate = 1.0
	if localRatesJson and type(localRatesJson) == "string" then
		local ok, rates = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), localRatesJson)
		if ok and rates[itemId] then
			localRate = rates[itemId]
		end
	elseif type(localRatesJson) == "number" then
		localRate = localRatesJson
	end
	-- Fallback to global rate
	if localRate == 1.0 then
		local globalRate = stockMarketFolder:GetAttribute("CurrentRate")
		if globalRate then localRate = globalRate end
	end
	return math.max(1, math.floor(basePrice * localRate))
end

-- Merge storage + backpack into combined inventory
local function getCombinedPlayerItems()
	local combined = {}
	for id, count in pairs(cachedStorageItems) do
		combined[id] = (combined[id] or 0) + count
	end
	for id, count in pairs(cachedBackpackItems) do
		combined[id] = (combined[id] or 0) + count
	end
	return combined
end

-- Get shortfall info for a unit (computed locally, no network)
local function getUnitShortfall(unitName)
	local itemCost = ShopConfig.GetItemCost(unitName)
	if not itemCost then return nil end
	local playerItems = getCombinedPlayerItems()
	return ShortfallCalc.Calculate(itemCost, playerItems, getClientBuyPrice, MAX_BUY)
end

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

local function formatMoney(amount: number): string
	local suffixes = {"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"}
	
	if amount < 1000 then
		return "$" .. tostring(math.floor(amount))
	end
	
	local magnitude = math.floor(math.log(amount, 1000))
	if magnitude > #suffixes then
		magnitude = #suffixes
	end
	
	local value = amount / (1000 ^ magnitude)
	
	if value < 100 and value % 1 ~= 0 then
		return string.format("$%.1f%s", value, suffixes[magnitude])
	else
		return string.format("$%.0f%s", value, suffixes[magnitude])
	end
end

--------------------------------------------------------------------------------
-- STATIC VIEWPORT PREVIEW (no spin — performance safe for 74 units)
--------------------------------------------------------------------------------

--[[
	Creates a static 3D viewport of a model. No RunService connection.
]]
local function createStaticViewport(model: Model, parent: GuiObject): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ModelPreview"
	viewport.Size = UDim2.new(1, 0, 1, 0)
	viewport.BackgroundColor3 = UI_CONFIG.VIEWPORT_BG
	viewport.BackgroundTransparency = 0.3
	viewport.BorderSizePixel = 0
	viewport.Parent = parent
	
	addCorner(viewport, 6)
	
	-- Clone model into WorldModel
	local previewModel = model:Clone()
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	previewModel.Parent = worldModel
	
	-- Camera
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	
	-- Position camera to frame the model
	local cf, size = previewModel:GetBoundingBox()
	local maxDimension = math.max(size.X, size.Y, size.Z)
	local fovRad = math.rad(50 / 2)
	local distance = (maxDimension / 2) / math.tan(fovRad) * 1.5
	
	local cameraOffset = Vector3.new(distance * 0.6, distance * 0.6, distance * 0.6)
	local targetPos = cf.Position + Vector3.new(0, size.Y * 0.1, 0)
	
	camera.CFrame = CFrame.new(cf.Position + cameraOffset, targetPos)
	camera.FieldOfView = 50
	
	return viewport
end

--[[
	Creates a silhouette version of a model: all parts black, no textures.
]]
local function createSilhouetteModel(model: Model): Model
	local clone = model:Clone()
	
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Color = Color3.new(0, 0, 0)
			desc.Material = Enum.Material.SmoothPlastic
			desc.Transparency = 0
			-- Clear MeshPart TextureID
			if desc:IsA("MeshPart") then
				desc.TextureID = ""
			end
		elseif desc:IsA("SurfaceAppearance") then
			-- PBR textures override Color entirely — must remove
			desc:Destroy()
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc:Destroy()
		elseif desc:IsA("SpecialMesh") then
			desc.TextureId = ""
		elseif desc:IsA("ParticleEmitter") or desc:IsA("Fire") or desc:IsA("Smoke") or desc:IsA("Sparkles") then
			desc:Destroy()
		end
	end
	
	return clone
end

--------------------------------------------------------------------------------
-- SHOP UI CREATION
--------------------------------------------------------------------------------

local function createShopGui(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ShopUI"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	-- Main shop panel — responsive width, starts off-screen to the right
	local shopPanel = Instance.new("Frame")
	shopPanel.Name = "ShopPanel"
	shopPanel.Size = UDim2.new(UI_CONFIG.SHOP_WIDTH_SCALE, 0, 1, -20)
	shopPanel.AnchorPoint = Vector2.new(1, 0)
	shopPanel.Position = UI_CONFIG.SHOP_CLOSED_POSITION -- Start off-screen (right)
	shopPanel.BackgroundColor3 = Color3.new(1, 1, 1)
	shopPanel.BackgroundTransparency = 0.25
	shopPanel.BorderSizePixel = 0
	shopPanel.Parent = screenGui
	addCorner(shopPanel, UI_CONFIG.CORNER_RADIUS)
	addStroke(shopPanel, UI_CONFIG.STROKE_COLOR, 1.5)
	
	-- Size constraint: cap max width on large screens
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(UI_CONFIG.SHOP_MAX_WIDTH, math.huge)
	sizeConstraint.Parent = shopPanel
	
	-- Panel gradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UI_CONFIG.PANEL_COLOR),
		ColorSequenceKeypoint.new(1, UI_CONFIG.BACKGROUND_COLOR)
	})
	gradient.Rotation = 90
	gradient.Parent = shopPanel
	
	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 50)
	titleBar.BackgroundTransparency = 1
	titleBar.BorderSizePixel = 0
	titleBar.Parent = shopPanel
	
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -40, 1, 0)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "🧠 BRAINROT SHOP"
	titleLabel.TextColor3 = UI_CONFIG.TEXT_COLOR
	titleLabel.TextSize = 20
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = titleBar
	
	-- Close button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Position = UDim2.new(1, -42, 0.5, -18)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	closeButton.Text = "✕"
	closeButton.TextColor3 = UI_CONFIG.TEXT_COLOR
	closeButton.TextSize = 18
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Parent = titleBar
	addCorner(closeButton, 8)
	
	-- Warning banner (off-island)
	local warningBanner = Instance.new("Frame")
	warningBanner.Name = "WarningBanner"
	warningBanner.Size = UDim2.new(1, 0, 0, 24)
	warningBanner.Position = UDim2.new(0, 0, 0, 50)
	warningBanner.BackgroundColor3 = Color3.fromRGB(180, 80, 30)
	warningBanner.BorderSizePixel = 0
	warningBanner.Visible = false
	warningBanner.Parent = shopPanel
	
	local warningLabel = Instance.new("TextLabel")
	warningLabel.Name = "WarningText"
	warningLabel.Size = UDim2.new(1, 0, 1, 0)
	warningLabel.BackgroundTransparency = 1
	warningLabel.Text = "⚠️ Visit Main Island to purchase"
	warningLabel.TextColor3 = Color3.fromRGB(255, 255, 200)
	warningLabel.TextSize = 12
	warningLabel.Font = Enum.Font.GothamBold
	warningLabel.Parent = warningBanner
	
	-- Scrolling frame for grid
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "ItemList"
	scrollFrame.Size = UDim2.new(1, -UI_CONFIG.SHOP_PADDING * 2, 1, -60)
	scrollFrame.Position = UDim2.new(0, UI_CONFIG.SHOP_PADDING, 0, 55)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = UI_CONFIG.ACCENT_COLOR
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0) -- AutomaticCanvasSize handles this
	scrollFrame.Parent = shopPanel
	
	-- Grid layout
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.Name = "Layout"
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.CellSize = UDim2.new(0, UI_CONFIG.CARD_WIDTH, 0, UI_CONFIG.CARD_HEIGHT)
	gridLayout.CellPadding = UDim2.new(0, UI_CONFIG.GRID_PADDING, 0, UI_CONFIG.GRID_PADDING)
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gridLayout.Parent = scrollFrame
	
	return screenGui
end

--------------------------------------------------------------------------------
-- CARD CREATION
--------------------------------------------------------------------------------

local function createShopCard(unitName: string, config: any, layoutOrder: number, isLocked: boolean): Frame
	local card = Instance.new("Frame")
	card.Name = unitName
	card.Size = UDim2.new(0, UI_CONFIG.CARD_WIDTH, 0, UI_CONFIG.CARD_HEIGHT)
	card.BackgroundColor3 = isLocked and UI_CONFIG.LOCKED_COLOR or UI_CONFIG.CARD_COLOR
	card.BorderSizePixel = 0
	card.LayoutOrder = layoutOrder
	addCorner(card, UI_CONFIG.CARD_CORNER_RADIUS)
	addStroke(card, UI_CONFIG.STROKE_COLOR, 1)
	
	-- Clickable area (only interactive if unlocked)
	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickArea"
	clickButton.Size = UDim2.new(1, 0, 1, 0)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.ZIndex = 3
	clickButton.Active = not isLocked
	clickButton.Parent = card
	
	-- ═══════════════════════════════════════════════════════════
	-- TOP: 3D Model Viewport (100px)
	-- ═══════════════════════════════════════════════════════════
	local viewportContainer = Instance.new("Frame")
	viewportContainer.Name = "IconContainer"
	viewportContainer.Size = UDim2.new(1, -12, 0, 100)
	viewportContainer.Position = UDim2.new(0, 6, 0, 6)
	viewportContainer.BackgroundColor3 = UI_CONFIG.VIEWPORT_BG
	viewportContainer.BackgroundTransparency = 0.5
	viewportContainer.BorderSizePixel = 0
	viewportContainer.Parent = card
	addCorner(viewportContainer, 6)
	
	local modelName = config.ModelName or unitName
	local modelTemplate = BrainrotsFolder:FindFirstChild(modelName)
	
	if modelTemplate then
		if isLocked then
			-- Silhouette: black model, no textures
			local silhouette = createSilhouetteModel(modelTemplate)
			createStaticViewport(silhouette, viewportContainer)
		else
			-- Normal colored model
			createStaticViewport(modelTemplate, viewportContainer)
		end
	else
		-- Fallback emoji
		local fallbackLabel = Instance.new("TextLabel")
		fallbackLabel.Name = "FallbackIcon"
		fallbackLabel.Size = UDim2.new(1, 0, 1, 0)
		fallbackLabel.BackgroundTransparency = 1
		fallbackLabel.Text = isLocked and "🔒" or "🧠"
		fallbackLabel.TextSize = 36
		fallbackLabel.Font = Enum.Font.GothamBold
		fallbackLabel.Parent = viewportContainer
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- UNIT NAME (20px)
	-- ═══════════════════════════════════════════════════════════
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "UnitName"
	nameLabel.Size = UDim2.new(1, -8, 0, 20)
	nameLabel.Position = UDim2.new(0, 4, 0, 110)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = isLocked and "???" or unitName
	nameLabel.TextColor3 = isLocked and UI_CONFIG.LOCKED_TEXT_COLOR or UI_CONFIG.TEXT_COLOR
	nameLabel.TextSize = 12
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card
	
	-- ═══════════════════════════════════════════════════════════
	-- PRODUCTION ITEMS (4 rows, ~80px total)
	-- ═══════════════════════════════════════════════════════════
	local itemsContainer = Instance.new("Frame")
	itemsContainer.Name = "ItemsContainer"
	itemsContainer.Size = UDim2.new(1, -8, 0, 72)
	itemsContainer.Position = UDim2.new(0, 4, 0, 132)
	itemsContainer.BackgroundTransparency = 1
	itemsContainer.Parent = card
	
	local brainrotItems = ItemConfig.BrainrotItems[unitName]
	local tierKeys = {"tier1", "tier2", "tier3", "tier4"}
	
	for tierIdx, tierKey in ipairs(tierKeys) do
		local tierLabel = Instance.new("TextLabel")
		tierLabel.Name = "Tier" .. tierIdx
		tierLabel.Size = UDim2.new(1, 0, 0, 16)
		tierLabel.Position = UDim2.new(0, 0, 0, (tierIdx - 1) * 18)
		tierLabel.BackgroundTransparency = 1
		tierLabel.TextSize = 10
		tierLabel.Font = Enum.Font.Gotham
		tierLabel.TextXAlignment = Enum.TextXAlignment.Left
		tierLabel.TextTruncate = Enum.TextTruncate.AtEnd
		tierLabel.Parent = itemsContainer
		
		if brainrotItems and brainrotItems[tierKey] then
			local itemId = brainrotItems[tierKey]
			local itemDef = ItemConfig.Items[itemId]
			
			if isLocked then
				-- Locked: show Tier 1 fully, tiers 2-4 as "???"
				if tierIdx == 1 and itemDef then
					tierLabel.Text = itemDef.icon .. " " .. itemDef.displayName
					tierLabel.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
				else
					tierLabel.Text = "Tier " .. tierIdx .. ": ???"
					tierLabel.TextColor3 = UI_CONFIG.LOCKED_TEXT_COLOR
				end
			else
				-- Unlocked: show full item info
				if itemDef then
					tierLabel.Text = itemDef.icon .. " " .. itemDef.displayName
					tierLabel.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
				else
					tierLabel.Text = "Tier " .. tierIdx .. ": ???"
					tierLabel.TextColor3 = UI_CONFIG.LOCKED_TEXT_COLOR
				end
			end
		else
			tierLabel.Text = "—"
			tierLabel.TextColor3 = UI_CONFIG.LOCKED_TEXT_COLOR
		end
	end
	
	-- ═══════════════════════════════════════════════════════════
	-- BOTTOM BAR: Price + Owned Badge + Buy (48px)
	-- ═══════════════════════════════════════════════════════════
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(1, -8, 0, 48)
	bottomBar.Position = UDim2.new(0, 4, 1, -52)
	bottomBar.BackgroundTransparency = 1
	bottomBar.Parent = card
	
	-- Price label
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.Size = UDim2.new(1, 0, 0, 18)
	priceLabel.Position = UDim2.new(0, 0, 0, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = isLocked and "LOCKED" or formatMoney(config.BasePrice)
	priceLabel.TextColor3 = isLocked and UI_CONFIG.LOCKED_TEXT_COLOR or UI_CONFIG.PRICE_COLOR
	priceLabel.TextSize = 14
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.TextXAlignment = Enum.TextXAlignment.Center
	priceLabel.Parent = bottomBar
	
	-- Item cost label (for units that require items)
	local itemCostLabel = Instance.new("TextLabel")
	itemCostLabel.Name = "ItemCost"
	itemCostLabel.Size = UDim2.new(1, 0, 0, 12)
	itemCostLabel.Position = UDim2.new(0, 0, 0, 17)
	itemCostLabel.BackgroundTransparency = 1
	itemCostLabel.Text = ""
	itemCostLabel.TextColor3 = UI_CONFIG.ITEM_COST_COLOR
	itemCostLabel.TextSize = 9
	itemCostLabel.Font = Enum.Font.Gotham
	itemCostLabel.TextXAlignment = Enum.TextXAlignment.Center
	itemCostLabel.TextTruncate = Enum.TextTruncate.AtEnd
	itemCostLabel.Visible = false
	itemCostLabel.Parent = bottomBar
	
	if not isLocked then
		local itemCost = ShopConfig.GetItemCost(unitName)
		if itemCost then
			local parts = {}
			for itemId, qty in pairs(itemCost) do
				table.insert(parts, qty .. "x " .. itemId)
			end
			itemCostLabel.Text = "📦 " .. table.concat(parts, " + ")
			itemCostLabel.Visible = true
		end
	end
	
	-- Bottom row: Owned badge + Buy indicator
	local ownedBadge = Instance.new("TextLabel")
	ownedBadge.Name = "OwnedBadge"
	ownedBadge.Size = UDim2.new(0, 36, 0, 18)
	ownedBadge.Position = UDim2.new(0, 0, 1, -20)
	ownedBadge.BackgroundColor3 = isLocked and UI_CONFIG.LOCKED_COLOR or UI_CONFIG.ACCENT_COLOR
	ownedBadge.Text = isLocked and "🔒" or "0"
	ownedBadge.TextColor3 = isLocked and UI_CONFIG.LOCKED_TEXT_COLOR or Color3.fromRGB(0, 0, 0)
	ownedBadge.TextSize = 11
	ownedBadge.Font = Enum.Font.GothamBold
	ownedBadge.Parent = bottomBar
	addCorner(ownedBadge, 4)
	
	local buyIndicator = Instance.new("TextLabel")
	buyIndicator.Name = "BuyIndicator"
	buyIndicator.Size = UDim2.new(0, 70, 0, 18)
	buyIndicator.Position = UDim2.new(1, -70, 1, -20)
	buyIndicator.BackgroundTransparency = 1
	buyIndicator.Text = isLocked and "" or "BUY"
	buyIndicator.TextColor3 = UI_CONFIG.ACCENT_COLOR
	buyIndicator.TextSize = 12
	buyIndicator.Font = Enum.Font.GothamBold
	buyIndicator.TextXAlignment = Enum.TextXAlignment.Right
	buyIndicator.Parent = bottomBar
	
	-- ═══════════════════════════════════════════════════════════
	-- LOCKED OVERLAY
	-- ═══════════════════════════════════════════════════════════
	if isLocked then
		local overlay = Instance.new("Frame")
		overlay.Name = "LockedOverlay"
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundColor3 = UI_CONFIG.LOCKED_OVERLAY_COLOR
		overlay.BackgroundTransparency = 0.6
		overlay.ZIndex = 2
		overlay.Parent = card
		addCorner(overlay, UI_CONFIG.CARD_CORNER_RADIUS)
	end
	
	return card
end

--------------------------------------------------------------------------------
-- UI LOGIC
--------------------------------------------------------------------------------

local function updateButtonPrice(unitName: string, newCount: number)
	local card = ShopButtons[unitName]
	if not card then return end
	
	local config = ShopConfig.GetConfig(unitName)
	if not config then return end
	
	-- Skip locked cards (no price updates needed)
	local overlay = card:FindFirstChild("LockedOverlay")
	if overlay then return end
	
	local newPrice = ShopConfig.CalculatePrice(unitName, newCount)
	
	-- Update price
	local bottomBar = card:FindFirstChild("BottomBar")
	if bottomBar then
		local priceLabel = bottomBar:FindFirstChild("Price")
		if priceLabel then
			priceLabel.Text = formatMoney(newPrice)
		end
		
		local ownedBadge = bottomBar:FindFirstChild("OwnedBadge")
		if ownedBadge then
			ownedBadge.Text = tostring(newCount)
		end
		
		-- Update buy indicator text
		local buyIndicator = bottomBar:FindFirstChild("BuyIndicator")
		if buyIndicator then
			buyIndicator.Text = newCount > 0 and "UPGRADE" or "BUY"
		end
		
		-- Update item cost with have/need display
		local itemCostLabel = bottomBar:FindFirstChild("ItemCost")
		if itemCostLabel then
			local itemCost = ShopConfig.GetItemCost(unitName)
			if itemCost then
				local playerItems = getCombinedPlayerItems()
				local parts = {}
				for itemId, qty in pairs(itemCost) do
					local have = playerItems[itemId] or 0
					local itemInfo = ItemConfig.Items[itemId]
					local icon = itemInfo and itemInfo.icon or "📦"
					table.insert(parts, string.format("%s %d/%d", icon, have, qty))
				end
				itemCostLabel.Text = table.concat(parts, "  ")
				itemCostLabel.Visible = true
			else
				itemCostLabel.Visible = false
			end
		end
	end
	
	-- Update production items display
	local itemsContainer = card:FindFirstChild("ItemsContainer")
	if itemsContainer then
		local brainrotItems = ItemConfig.BrainrotItems[unitName]
		if brainrotItems then
			for tierIdx = 1, 4 do
				local tierLabel = itemsContainer:FindFirstChild("Tier" .. tierIdx)
				if tierLabel then
					local tierKey = "tier" .. tierIdx
					local itemId = brainrotItems[tierKey]
					if itemId then
						local itemDef = ItemConfig.Items[itemId]
						if itemDef then
							tierLabel.Text = itemDef.icon .. " " .. itemDef.displayName
							tierLabel.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
						end
					end
				end
			end
		end
	end
	
	OwnedCounts[unitName] = newCount
end

local function canAfford(unitName: string): boolean
	local leaderstats = Player:FindFirstChild("leaderstats")
	if not leaderstats then return false end
	
	local money = leaderstats:FindFirstChild("Money")
	if not money then return false end
	
	local count = OwnedCounts[unitName] or 0
	local unitPrice = ShopConfig.CalculatePrice(unitName, count)
	
	-- Account for shortfall auto-buy cost
	local shortfall = getUnitShortfall(unitName)
	local totalCost = unitPrice
	if shortfall and shortfall.hasShortfall then
		totalCost = unitPrice + shortfall.totalTaxed
	end
	
	return money.Value >= totalCost
end

-- Returns: "normal" | "import" | "cant_afford"
local function getAffordabilityState(unitName: string)
	local leaderstats = Player:FindFirstChild("leaderstats")
	if not leaderstats then return "cant_afford", 0 end
	local money = leaderstats:FindFirstChild("Money")
	if not money then return "cant_afford", 0 end
	
	local count = OwnedCounts[unitName] or 0
	local unitPrice = ShopConfig.CalculatePrice(unitName, count)
	local shortfall = getUnitShortfall(unitName)
	
	if not shortfall or not shortfall.hasShortfall then
		-- No items needed or player has all items
		if money.Value >= unitPrice then
			return "normal", unitPrice
		else
			return "cant_afford", unitPrice
		end
	else
		-- Has shortfall — check if player can afford total
		local totalCost = unitPrice + shortfall.totalTaxed
		if money.Value >= totalCost then
			return "import", totalCost
		else
			return "cant_afford", totalCost
		end
	end
end

local function updateButtonAffordability()
	for unitName, card in ShopButtons do
		-- Skip locked cards
		local overlay = card:FindFirstChild("LockedOverlay")
		if overlay then continue end
		
		local state, totalCost = getAffordabilityState(unitName)
		
		local bottomBar = card:FindFirstChild("BottomBar")
		if not bottomBar then continue end
		
		local buyIndicator = bottomBar:FindFirstChild("BuyIndicator")
		local priceLabel = bottomBar:FindFirstChild("Price")
		local itemCostLabel = bottomBar:FindFirstChild("ItemCost")
		
		-- Update item cost colors (have/need)
		if itemCostLabel and itemCostLabel.Visible then
			local shortfall = getUnitShortfall(unitName)
			if shortfall and shortfall.hasShortfall then
				itemCostLabel.TextColor3 = UI_CONFIG.ITEM_NEED_COLOR
			else
				itemCostLabel.TextColor3 = UI_CONFIG.ITEM_HAVE_COLOR
			end
		end
		
		if state == "normal" then
			-- Has all items, can afford
			card.BackgroundColor3 = UI_CONFIG.CARD_COLOR
			if buyIndicator then
				local count = OwnedCounts[unitName] or 0
				buyIndicator.Text = count > 0 and "UPGRADE" or "BUY"
				buyIndicator.TextColor3 = UI_CONFIG.ACCENT_COLOR
				buyIndicator.TextTransparency = 0
			end
			if priceLabel then
				priceLabel.TextColor3 = UI_CONFIG.PRICE_COLOR
			end
		elseif state == "import" then
			-- Missing items but can auto-buy — gold button
			card.BackgroundColor3 = UI_CONFIG.CARD_COLOR
			if buyIndicator then
				buyIndicator.Text = "BUY & IMPORT"
				buyIndicator.TextColor3 = UI_CONFIG.GOLD_COLOR
				buyIndicator.TextTransparency = 0
			end
			if priceLabel then
				priceLabel.Text = formatMoney(totalCost)
				priceLabel.TextColor3 = UI_CONFIG.GOLD_COLOR
			end
		else
			-- Can't afford
			card.BackgroundColor3 = UI_CONFIG.CARD_DISABLED_COLOR
			if buyIndicator then
				buyIndicator.Text = "Need " .. formatMoney(totalCost)
				buyIndicator.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
				buyIndicator.TextTransparency = 0.5
			end
			if priceLabel then
				priceLabel.TextColor3 = UI_CONFIG.SECONDARY_TEXT_COLOR
			end
		end
	end
end

local function animatePurchase(card: Frame, success: boolean)
	if success then
		-- Success: quick scale pop
		local originalSize = card.Size
		
		local popTween = TweenService:Create(card, TweenInfo.new(0.1), {
			Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset + 6, originalSize.Y.Scale, originalSize.Y.Offset + 4)
		})
		
		local returnTween = TweenService:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Elastic), {
			Size = originalSize
		})
		
		popTween:Play()
		popTween.Completed:Connect(function()
			returnTween:Play()
		end)
		
		-- Flash green
		local originalColor = card.BackgroundColor3
		card.BackgroundColor3 = UI_CONFIG.ACCENT_COLOR
		task.delay(0.1, function()
			TweenService:Create(card, TweenInfo.new(0.2), {BackgroundColor3 = originalColor}):Play()
		end)
		
		ChachingSound:Play()
	else
		-- Failure: shake
		local originalPos = card.Position
		
		for i = 1, 3 do
			local offset = i % 2 == 0 and 5 or -5
			TweenService:Create(card, TweenInfo.new(0.05), {
				Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset + offset, originalPos.Y.Scale, originalPos.Y.Offset)
			}):Play()
			task.wait(0.05)
		end
		
		card.Position = originalPos
		ErrorSound:Play()
	end
end

local function setupCardClick(card: Frame, unitName: string)
	local clickArea = card:FindFirstChild("ClickArea")
	if not clickArea then return end
	
	local debounce = false
	
	-- Hover effects
	clickArea.MouseEnter:Connect(function()
		if canAfford(unitName) then
			TweenService:Create(card, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
				BackgroundColor3 = UI_CONFIG.CARD_HOVER_COLOR
			}):Play()
		end
	end)
	
	clickArea.MouseLeave:Connect(function()
		local targetColor = canAfford(unitName) and UI_CONFIG.CARD_COLOR or UI_CONFIG.CARD_DISABLED_COLOR
		TweenService:Create(card, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
			BackgroundColor3 = targetColor
		}):Play()
	end)
	
	-- Click to buy
	clickArea.MouseButton1Click:Connect(function()
		if debounce then return end
		debounce = true
		
		local success, message = BuyUnitRemote:InvokeServer(unitName)
		animatePurchase(card, success)
		
		if not success then
			warn("Purchase failed: " .. tostring(message))
		end
		
		task.wait(0.3)
		debounce = false
	end)
end

--[[
	Refreshes the shop UI, rendering ALL units.
	Locked units get silhouette treatment.
]]
local function refreshShopUI()
	if not ScrollFrame then return end
	
	-- Clear existing cards
	for _, child in ScrollFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	ShopButtons = {}
	
	-- Get ALL units sorted by price
	local allUnits = ShopConfig.GetAllUnitsSorted()
	
	for i, unitData in allUnits do
		local unitName = unitData.name
		local config = unitData.config
		local isLocked = not ShopConfig.IsUnitUnlocked(unitName, UnlockProgress)
		
		-- Create card
		local card = createShopCard(unitName, config, i, isLocked)
		card.Parent = ScrollFrame
		
		-- Store reference for all cards (locked & unlocked)
		ShopButtons[unitName] = card
		
		if not isLocked then
			-- Update with actual owned count
			local count = OwnedCounts[unitName] or 0
			updateButtonPrice(unitName, count)
			
			-- Setup click handler
			setupCardClick(card, unitName)
		end
	end
	
	-- Update affordability
	updateButtonAffordability()
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("ShopUI: Initializing (Grid Mode)...")
	
	ShopGui = createShopGui()
	if not ShopGui then return end
	local shopPanel = ShopGui:FindFirstChild("ShopPanel")
	ScrollFrame = shopPanel and shopPanel:FindFirstChild("ItemList")
	
	-- Get initial ownership data
	local ownershipData = GetOwnershipRemote:InvokeServer()
	
	if ownershipData and ownershipData.unlockProgress then
		UnlockProgress = ownershipData.unlockProgress
	end
	
	if ownershipData and ownershipData.units then
		for unitName, data in ownershipData.units do
			OwnedCounts[unitName] = data.count
		end
	end
	
	-- Build shop
	refreshShopUI()
	
	-- Parent GUI
	ShopGui.Parent = PlayerGui
	
	-- Listen for ownership updates
	OwnershipChangedEvent.OnClientEvent:Connect(function(unitName: string, newCount: number, newPrice: number)
		OwnedCounts[unitName] = newCount
		updateButtonPrice(unitName, newCount)
		updateButtonAffordability()
	end)
	
	-- Listen for unlock progress updates
	UnlockProgressChangedEvent.OnClientEvent:Connect(function(newProgress: number)
		print(string.format("ShopUI: Unlock progress updated to %d", newProgress))
		UnlockProgress = newProgress
		refreshShopUI()
	end)
	
	-- Update affordability when money changes (debounced)
	local leaderstats = Player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local money = leaderstats:WaitForChild("Money", 5)
		if money then
			money:GetPropertyChangedSignal("Value"):Connect(function()
				if shortfallDebounce then return end
				shortfallDebounce = true
				task.delay(0.2, function()
					shortfallDebounce = false
					updateButtonAffordability()
				end)
			end)
		end
	end
	
	-- Listen for storage updates (cache for shortfall calc)
	local StorageUpdatedEvent = RemoteEvents:FindFirstChild("StorageUpdated")
	if StorageUpdatedEvent then
		StorageUpdatedEvent.OnClientEvent:Connect(function(items, _total, _capacity)
			cachedStorageItems = decodeItems(items) or {}
			-- Debounced refresh
			if shortfallDebounce then return end
			shortfallDebounce = true
			task.delay(0.2, function()
				shortfallDebounce = false
				-- Update item cost labels and affordability
				for unitName, _count in pairs(OwnedCounts) do
					updateButtonPrice(unitName, OwnedCounts[unitName] or 0)
				end
				updateButtonAffordability()
			end)
		end)
	end
	
	-- Listen for cart/backpack updates (cache for shortfall calc)
	local CartUpdateEvent = RemoteEvents:FindFirstChild("CartUpdate")
	if CartUpdateEvent then
		CartUpdateEvent.OnClientEvent:Connect(function(_state, inventory, _capacity)
			cachedBackpackItems = decodeItems(inventory) or {}
			-- Debounced refresh
			if shortfallDebounce then return end
			shortfallDebounce = true
			task.delay(0.2, function()
				shortfallDebounce = false
				for unitName, _count in pairs(OwnedCounts) do
					updateButtonPrice(unitName, OwnedCounts[unitName] or 0)
				end
				updateButtonAffordability()
			end)
		end)
	end
	
	-- Initial storage fetch
	local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions")
	if RemoteFunctions then
		local GetStorage = RemoteFunctions:FindFirstChild("GetStorage")
		if GetStorage then
			task.spawn(function()
				local items = GetStorage:InvokeServer()
				if items then
					cachedStorageItems = decodeItems(items) or {}
				end
				updateButtonAffordability()
			end)
		end
	end
	
	print(string.format("ShopUI: Ready! (%d units unlocked, %d total)", UnlockProgress, ShopConfig.GetTotalUnits()))
end

-- Start
initialize()

--------------------------------------------------------------------------------
-- SHOP VISIBILITY (Controlled by B key, HUD button, or ProximityPrompt)
--------------------------------------------------------------------------------

local ShopVisible = false

-- Responsive open/close: use AnchorPoint(1,0) so position is right-edge aligned

local function updateWarningBanner()
	if not ShopGui then return end
	local shopPanel = ShopGui:FindFirstChild("ShopPanel")
	if not shopPanel then return end
	
	local warningBanner = shopPanel:FindFirstChild("WarningBanner")
	if warningBanner then
		warningBanner.Visible = not IsOnMainIsland
	end
end

local function openShop()
	if ShopVisible then return end
	if not ShopGui then return end
	local shopPanel = ShopGui:FindFirstChild("ShopPanel")
	if not shopPanel then return end
	
	ShopVisible = true
	ShopGui.Enabled = true
	updateWarningBanner()
	TweenService:Create(shopPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UI_CONFIG.SHOP_OPEN_POSITION
	}):Play()
	print("ShopUI: Opened")
end

local function closeShop()
	if not ShopVisible then return end
	if not ShopGui then return end
	local shopPanel = ShopGui:FindFirstChild("ShopPanel")
	if not shopPanel then return end
	
	ShopVisible = false
	local tween = TweenService:Create(shopPanel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UI_CONFIG.SHOP_CLOSED_POSITION
	})
	tween:Play()
	tween.Completed:Connect(function()
		if not ShopVisible then
			ShopGui.Enabled = false
		end
	end)
	print("ShopUI: Closed")
end

--------------------------------------------------------------------------------
-- SHOP INTERACTION
--------------------------------------------------------------------------------

local ShopInteraction = require(script.Parent:WaitForChild("ShopInteraction"))

local interaction = ShopInteraction.new({
	PromptTag = "UnitShopVisual",
	InteractionDist = 20,
	Keybind = Enum.KeyCode.E,
	OnOpen = function()
		if not ShopVisible then openShop() end
	end,
	OnClose = function()
		if ShopVisible then closeShop() end
	end,
})

-- BindableEvent listener for MoneyHUD shop button
local function setupBindableEventListener()
	task.wait(0.5)
	
	local shopToggleEvent = ReplicatedStorage:FindFirstChild("ShopToggleEvent")
	if not shopToggleEvent then
		shopToggleEvent = Instance.new("BindableEvent")
		shopToggleEvent.Name = "ShopToggleEvent"
		shopToggleEvent.Parent = ReplicatedStorage
	end
	
	shopToggleEvent.Event:Connect(function()
		interaction:Toggle()
	end)
	
	print("ShopUI: BindableEvent listener setup complete")
end

-- B key toggle (legacy)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.B then
		interaction:Toggle()
	end
end)

-- Close button setup
local function setupCloseButton()
	if not ShopGui then return end
	local shopPanel = ShopGui:FindFirstChild("ShopPanel")
	if not shopPanel then return end
	
	local titleBar = shopPanel:FindFirstChild("TitleBar")
	if not titleBar then return end
	
	local closeButton = titleBar:FindFirstChild("CloseButton")
	if closeButton then
		closeButton.MouseButton1Click:Connect(function()
			interaction:Close()
		end)
		
		closeButton.MouseEnter:Connect(function()
			TweenService:Create(closeButton, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(255, 80, 80)
			}):Play()
		end)
		
		closeButton.MouseLeave:Connect(function()
			TweenService:Create(closeButton, TweenInfo.new(0.1), {
				BackgroundColor3 = Color3.fromRGB(200, 60, 60)
			}):Play()
		end)
	end
end

task.spawn(setupCloseButton)
task.spawn(setupBindableEventListener)

local UIManager = require(script.Parent:WaitForChild("Managers"):WaitForChild("UIManager"))
UIManager.RegisterShop("MachineShop", function()
	if ShopVisible then closeShop() else openShop() end
end)
