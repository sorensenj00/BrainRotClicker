--[[
	ArtifactExchangeUI Client Script
	
	Grand Exchange — 2-column interface for browsing and trading artifacts.
	
	Layout:
	  Left (30%)  — MY LISTINGS + Create Listing form
	  Right (70%) — BROWSE ALL LISTINGS with filters
	
	Opens via:
	  - Proximity Prompt (ArtifactExchangeVendor tag)
	  - ExchangeToggleEvent (from MoneyHUD button)
	  - Keybind G
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local CreateListingFunc = RemoteFunctions:WaitForChild("CreateArtifactListing")
local BuyListingFunc = RemoteFunctions:WaitForChild("BuyArtifactListing")
local CancelListingFunc = RemoteFunctions:WaitForChild("CancelArtifactListing")
local GetListingsFunc = RemoteFunctions:WaitForChild("GetArtifactListings")
local GetArtifactsFunc = RemoteFunctions:WaitForChild("GetArtifacts")
local ExchangeNotifyEvent = RemoteEvents:WaitForChild("ArtifactExchangeNotify")

-- Shared config
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactExchangeConfig = require(Shared:WaitForChild("ArtifactExchangeConfig"))

local recentlyPurchased = {}
local _ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))

-- ShopInteraction for proximity prompt
local ShopInteraction = require(script.Parent:WaitForChild("ShopInteraction"))

local C = ArtifactExchangeConfig.UI
local FONT_MONO = Enum.Font.RobotoMono
local FONT_BOLD = Enum.Font.GothamBold
local FONT_REG = Enum.Font.Gotham

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local isOpen = false
local screenGui = nil
local mainFrame = nil

local currentFilters = {
	slot = "All",
	rarity = "All",
	search = "",
	sortBy = "PriceAsc",
}

local myListingsData = {}
local marketListingsData = {}
local myArtifacts = {} -- Unequipped artifacts available to sell

-- UI references
local browseScroll = nil
local myListingsScroll = nil
local artifactDropdown = nil
local priceInput = nil
local statusLabel = nil
local selectedArtifactGUID = nil

-- Forward declarations (functions defined later, referenced before definition)
local handleCreateListing
local handleBuyListing
local handleCancelListing
local refreshAll
local refreshMyListings
local refreshBrowseListings
local populateDropdown
local createLeftColumn
local createRightColumn
local createFilterButton
local openExchange
local closeExchange

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local FormatUtils = require(Shared:WaitForChild("Utils"):WaitForChild("FormatUtils"))
local UIUtils = require(Shared:WaitForChild("Utils"):WaitForChild("UIUtils"))

local addCorner = UIUtils.addCorner
local addStroke = UIUtils.addStroke
local formatMoney = FormatUtils.formatMoney

local function getRarityColor(rarity)
	local colors = {
		Common = C.COMMON,
		Uncommon = C.UNCOMMON,
		Rare = C.RARE,
		Epic = C.EPIC,
		Legendary = C.LEGENDARY,
	}
	return colors[rarity] or C.MUTED
end

local function getAffixSummary(affixes)
	if not affixes or #affixes == 0 then return "" end
	local parts = {}
	for _, affix in ipairs(affixes) do
		local icon = affix.Icon or ""
		local stat = affix.Stat or ""
		local val = ""
		if affix.Mult then
			val = string.format("%.0f%%", (1 - affix.Mult) * 100) .. " faster"
		elseif affix.Add then
			if stat == "LuckBonus" then
				val = "+" .. string.format("%.0f%%", affix.Add * 100) .. " luck"
			elseif stat == "ItemTierBonus" then
				val = "+" .. affix.Add .. " tier"
			elseif stat == "SynergyRangeBonus" then
				val = "+" .. affix.Add .. " range"
			end
		end
		table.insert(parts, icon .. " " .. val)
	end
	return table.concat(parts, "  ")
end

local function setStatus(msg, color)
	if statusLabel then
		statusLabel.Text = msg
		statusLabel.TextColor3 = color or C.MUTED
	end
end

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createMainUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ArtifactExchangeUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 15
	screenGui.Enabled = false
	screenGui.Parent = PlayerGui

	-- Semi-transparent backdrop
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = screenGui

	-- Main frame
	mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 900, 0, 560)
	mainFrame.Position = UDim2.new(0.5, -450, 0.5, -280)
	mainFrame.BackgroundColor3 = C.BG
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	addCorner(mainFrame, UDim.new(0, 10))
	addStroke(mainFrame, C.GOLD, 2)

	-- Gradient overlay
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.BG),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 8, 14)),
	})
	grad.Rotation = 90
	grad.Parent = mainFrame

	-- Top bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 44)
	topBar.Position = UDim2.new(0, 0, 0, 0)
	topBar.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
	topBar.BorderSizePixel = 0
	topBar.Parent = mainFrame
	addCorner(topBar, UDim.new(0, 10))

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(0, 300, 1, 0)
	title.Position = UDim2.new(0, 14, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = "⚔ GRAND EXCHANGE"
	title.TextColor3 = C.GOLD
	title.TextSize = 18
	title.Font = FONT_BOLD
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = topBar

	-- Status
	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(0, 300, 1, 0)
	statusLabel.Position = UDim2.new(0.5, -150, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "● MARKET LIVE"
	statusLabel.TextColor3 = C.GREEN
	statusLabel.TextSize = 11
	statusLabel.Font = FONT_MONO
	statusLabel.Parent = topBar

	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Size = UDim2.new(0, 32, 0, 32)
	closeBtn.Position = UDim2.new(1, -42, 0, 6)
	closeBtn.BackgroundColor3 = Color3.fromRGB(60, 30, 30)
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = C.RED
	closeBtn.TextSize = 16
	closeBtn.Font = FONT_BOLD
	closeBtn.Parent = topBar
	addCorner(closeBtn, UDim.new(0, 6))

	closeBtn.MouseButton1Click:Connect(function()
		closeExchange()
	end)
	backdrop.MouseButton1Click:Connect(function()
		closeExchange()
	end)

	-- Content area
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -20, 1, -54)
	content.Position = UDim2.new(0, 10, 0, 50)
	content.BackgroundTransparency = 1
	content.Parent = mainFrame

	-- LEFT COLUMN (30%)
	createLeftColumn(content)

	-- RIGHT COLUMN (70%)
	createRightColumn(content)
end

--------------------------------------------------------------------------------
-- LEFT COLUMN: My Listings + Create Listing
--------------------------------------------------------------------------------

createLeftColumn = function(parent)
	local col = Instance.new("Frame")
	col.Name = "LeftCol"
	col.Size = UDim2.new(0.30, -5, 1, 0)
	col.Position = UDim2.new(0, 0, 0, 0)
	col.BackgroundColor3 = C.PANEL
	col.BorderSizePixel = 0
	col.Parent = parent
	addCorner(col)
	addStroke(col, C.BORDER, 1)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = col

	-- MY LISTINGS header
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 22)
	header.BackgroundTransparency = 1
	header.Text = "📋 MY LISTINGS"
	header.TextColor3 = C.GOLD
	header.TextSize = 12
	header.Font = FONT_BOLD
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = col

	-- My listings scroll
	myListingsScroll = Instance.new("ScrollingFrame")
	myListingsScroll.Name = "MyListings"
	myListingsScroll.Size = UDim2.new(1, 0, 0, 160)
	myListingsScroll.Position = UDim2.new(0, 0, 0, 26)
	myListingsScroll.BackgroundTransparency = 1
	myListingsScroll.ScrollBarThickness = 3
	myListingsScroll.ScrollBarImageColor3 = C.GOLD
	myListingsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	myListingsScroll.Parent = col

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = myListingsScroll

	-- Divider
	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, 0, 0, 1)
	div.Position = UDim2.new(0, 0, 0, 192)
	div.BackgroundColor3 = C.BORDER
	div.BackgroundTransparency = 0.5
	div.BorderSizePixel = 0
	div.Parent = col

	-- SELL SECTION header
	local sellHeader = Instance.new("TextLabel")
	sellHeader.Size = UDim2.new(1, 0, 0, 22)
	sellHeader.Position = UDim2.new(0, 0, 0, 198)
	sellHeader.BackgroundTransparency = 1
	sellHeader.Text = "💰 LIST FOR SALE"
	sellHeader.TextColor3 = C.GREEN
	sellHeader.TextSize = 12
	sellHeader.Font = FONT_BOLD
	sellHeader.TextXAlignment = Enum.TextXAlignment.Left
	sellHeader.Parent = col

	-- Artifact selector (text button acting as dropdown)
	artifactDropdown = Instance.new("TextButton")
	artifactDropdown.Name = "ArtifactSelect"
	artifactDropdown.Size = UDim2.new(1, 0, 0, 34)
	artifactDropdown.Position = UDim2.new(0, 0, 0, 224)
	artifactDropdown.BackgroundColor3 = C.CARD
	artifactDropdown.Text = "Select an artifact ▼"
	artifactDropdown.TextColor3 = C.MUTED
	artifactDropdown.TextSize = 11
	artifactDropdown.Font = FONT_REG
	artifactDropdown.TextTruncate = Enum.TextTruncate.AtEnd
	artifactDropdown.Parent = col
	addCorner(artifactDropdown)
	addStroke(artifactDropdown, C.BORDER)

	-- Dropdown menu (hidden by default)
	local dropdownMenu = Instance.new("ScrollingFrame")
	dropdownMenu.Name = "DropdownMenu"
	dropdownMenu.Size = UDim2.new(1, 0, 0, 120)
	dropdownMenu.Position = UDim2.new(0, 0, 0, 260)
	dropdownMenu.BackgroundColor3 = C.CARD
	dropdownMenu.BorderSizePixel = 0
	dropdownMenu.Visible = false
	dropdownMenu.ScrollBarThickness = 3
	dropdownMenu.CanvasSize = UDim2.new(0, 0, 0, 0)
	dropdownMenu.ZIndex = 50
	dropdownMenu.Parent = col
	addCorner(dropdownMenu)
	addStroke(dropdownMenu, C.GOLD)

	local ddLayout = Instance.new("UIListLayout")
	ddLayout.Padding = UDim.new(0, 2)
	ddLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ddLayout.Parent = dropdownMenu

	artifactDropdown.MouseButton1Click:Connect(function()
		dropdownMenu.Visible = not dropdownMenu.Visible
		if dropdownMenu.Visible then
			populateDropdown(dropdownMenu)
		end
	end)

	-- Price input
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Size = UDim2.new(0.3, 0, 0, 30)
	priceLabel.Position = UDim2.new(0, 0, 0, 264)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = "Price: $"
	priceLabel.TextColor3 = C.WHITE
	priceLabel.TextSize = 12
	priceLabel.Font = FONT_BOLD
	priceLabel.TextXAlignment = Enum.TextXAlignment.Left
	priceLabel.Parent = col

	priceInput = Instance.new("TextBox")
	priceInput.Name = "PriceInput"
	priceInput.Size = UDim2.new(0.65, 0, 0, 30)
	priceInput.Position = UDim2.new(0.3, 5, 0, 264)
	priceInput.BackgroundColor3 = C.CARD
	priceInput.Text = ""
	priceInput.PlaceholderText = "Enter price..."
	priceInput.PlaceholderColor3 = C.DIM
	priceInput.TextColor3 = C.GREEN
	priceInput.TextSize = 13
	priceInput.Font = FONT_MONO
	priceInput.ClearTextOnFocus = false
	priceInput.Parent = col
	addCorner(priceInput)
	addStroke(priceInput, C.BORDER)

	-- Net profit label
	local netProfitLabel = Instance.new("TextLabel")
	netProfitLabel.Name = "NetProfitLabel"
	netProfitLabel.Size = UDim2.new(1, 0, 0, 14)
	netProfitLabel.Position = UDim2.new(0, 0, 0, 296)
	netProfitLabel.BackgroundTransparency = 1
	netProfitLabel.Text = ""
	netProfitLabel.TextColor3 = C.GREEN
	netProfitLabel.TextSize = 10
	netProfitLabel.Font = FONT_REG
	netProfitLabel.TextXAlignment = Enum.TextXAlignment.Center
	netProfitLabel.Parent = col

	priceInput:GetPropertyChangedSignal("Text"):Connect(function()
		local val = tonumber(priceInput.Text)
		if val and val > 0 then
			local net = math.floor(val * 0.9) -- 10% tax
			netProfitLabel.Text = "You will receive: " .. formatMoney(net)
		else
			netProfitLabel.Text = ""
		end
	end)

	-- List button
	local listBtn = Instance.new("TextButton")
	listBtn.Name = "ListButton"
	listBtn.Size = UDim2.new(1, 0, 0, 36)
	listBtn.Position = UDim2.new(0, 0, 0, 312)
	listBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 60)
	listBtn.Text = "📤 LIST FOR SALE"
	listBtn.TextColor3 = C.WHITE
	listBtn.TextSize = 13
	listBtn.Font = FONT_BOLD
	listBtn.Parent = col
	addCorner(listBtn, UDim.new(0, 8))
	addStroke(listBtn, C.GREEN, 1)

	listBtn.MouseButton1Click:Connect(function()
		handleCreateListing()
	end)

	-- Info text
	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(1, 0, 0, 50)
	infoLabel.Position = UDim2.new(0, 0, 1, -56)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = "10% tax on sales\nMax 3 active listings"
	infoLabel.TextColor3 = C.DIM
	infoLabel.TextSize = 10
	infoLabel.Font = FONT_REG
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	infoLabel.Parent = col
end

--------------------------------------------------------------------------------
-- RIGHT COLUMN: Browse Listings
--------------------------------------------------------------------------------

createRightColumn = function(parent)
	local col = Instance.new("Frame")
	col.Name = "RightCol"
	col.Size = UDim2.new(0.70, -5, 1, 0)
	col.Position = UDim2.new(0.30, 5, 0, 0)
	col.BackgroundColor3 = C.PANEL
	col.BorderSizePixel = 0
	col.Parent = parent
	addCorner(col)
	addStroke(col, C.BORDER, 1)

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = col

	-- Header + filters bar
	local filterBar = Instance.new("Frame")
	filterBar.Name = "FilterBar"
	filterBar.Size = UDim2.new(1, 0, 0, 30)
	filterBar.BackgroundTransparency = 1
	filterBar.Parent = col

	local fLayout = Instance.new("UIListLayout")
	fLayout.FillDirection = Enum.FillDirection.Horizontal
	fLayout.Padding = UDim.new(0, 6)
	fLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	fLayout.SortOrder = Enum.SortOrder.LayoutOrder
	fLayout.Parent = filterBar

	-- Browse header
	local browseLabel = Instance.new("TextLabel")
	browseLabel.Size = UDim2.new(0, 140, 0, 28)
	browseLabel.BackgroundTransparency = 1
	browseLabel.Text = "🔍 BROWSE LISTINGS"
	browseLabel.TextColor3 = C.GOLD
	browseLabel.TextSize = 12
	browseLabel.Font = FONT_BOLD
	browseLabel.TextXAlignment = Enum.TextXAlignment.Left
	browseLabel.LayoutOrder = 0
	browseLabel.Parent = filterBar

	-- Slot filter
	local slotOptions = {"All", "Head", "Body", "Accessory"}
	local slotBtn = createFilterButton(filterBar, "Slot: All", 1)
	local slotIndex = 1
	slotBtn.MouseButton1Click:Connect(function()
		slotIndex = (slotIndex % #slotOptions) + 1
		currentFilters.slot = slotOptions[slotIndex]
		slotBtn.Text = "Slot: " .. slotOptions[slotIndex]
		refreshAll()
	end)

	-- Rarity filter
	local rarityOptions = {"All", "Common", "Uncommon", "Rare", "Epic", "Legendary"}
	local rarityBtn = createFilterButton(filterBar, "Rarity: All", 2)
	local rarityIndex = 1
	rarityBtn.MouseButton1Click:Connect(function()
		rarityIndex = (rarityIndex % #rarityOptions) + 1
		currentFilters.rarity = rarityOptions[rarityIndex]
		rarityBtn.Text = "Rarity: " .. rarityOptions[rarityIndex]
		if currentFilters.rarity ~= "All" then
			rarityBtn.TextColor3 = getRarityColor(currentFilters.rarity)
		else
			rarityBtn.TextColor3 = C.WHITE
		end
		refreshAll()
	end)

	-- Sort toggle
	local sortOptions = {"PriceAsc", "PriceDesc", "Newest"}
	local sortLabels = {"Price ↑", "Price ↓", "Newest"}
	local sortBtn = createFilterButton(filterBar, "Sort: Price ↑", 3)
	local sortIndex = 1
	sortBtn.MouseButton1Click:Connect(function()
		sortIndex = (sortIndex % #sortOptions) + 1
		currentFilters.sortBy = sortOptions[sortIndex]
		sortBtn.Text = "Sort: " .. sortLabels[sortIndex]
		refreshAll()
	end)

	-- Search box
	local searchBox = Instance.new("TextBox")
	searchBox.Name = "Search"
	searchBox.Size = UDim2.new(0, 120, 0, 26)
	searchBox.BackgroundColor3 = C.CARD
	searchBox.PlaceholderText = "Search..."
	searchBox.PlaceholderColor3 = C.DIM
	searchBox.Text = ""
	searchBox.TextColor3 = C.WHITE
	searchBox.TextSize = 11
	searchBox.Font = FONT_REG
	searchBox.ClearTextOnFocus = false
	searchBox.LayoutOrder = 4
	searchBox.Parent = filterBar
	addCorner(searchBox, UDim.new(0, 4))
	addStroke(searchBox, C.BORDER)

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		currentFilters.search = searchBox.Text
		refreshAll()
	end)

	-- Browse scroll
	browseScroll = Instance.new("ScrollingFrame")
	browseScroll.Name = "BrowseList"
	browseScroll.Size = UDim2.new(1, 0, 1, -40)
	browseScroll.Position = UDim2.new(0, 0, 0, 36)
	browseScroll.BackgroundTransparency = 1
	browseScroll.ScrollBarThickness = 4
	browseScroll.ScrollBarImageColor3 = C.GOLD
	browseScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	browseScroll.Parent = col

	local bLayout = Instance.new("UIListLayout")
	bLayout.Padding = UDim.new(0, 4)
	bLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bLayout.Parent = browseScroll

	-- Empty state
	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.Name = "EmptyLabel"
	emptyLabel.Size = UDim2.new(1, 0, 0, 60)
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Text = "No listings found.\nBe the first to list an artifact!"
	emptyLabel.TextColor3 = C.DIM
	emptyLabel.TextSize = 13
	emptyLabel.Font = FONT_REG
	emptyLabel.Parent = browseScroll
end

createFilterButton = function(parent, text, order)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 90, 0, 26)
	btn.BackgroundColor3 = C.CARD
	btn.Text = text
	btn.TextColor3 = C.WHITE
	btn.TextSize = 10
	btn.Font = FONT_BOLD
	btn.LayoutOrder = order
	btn.Parent = parent
	addCorner(btn, UDim.new(0, 4))
	addStroke(btn, C.BORDER)

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3 = C.CARD_HOVER }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.1), { BackgroundColor3 = C.CARD }):Play()
	end)

	return btn
end

--------------------------------------------------------------------------------
-- LISTING CARD CREATION
--------------------------------------------------------------------------------

local function createListingCard(parent, listing, isMine, order)
	local art = listing.Artifact
	if not art then return end

	local card = Instance.new("Frame")
	card.Name = "Card_" .. (listing.ListingGUID or "?")
	card.Size = UDim2.new(1, 0, 0, if isMine then 55 else 68)
	card.BackgroundColor3 = C.CARD
	card.BorderSizePixel = 0
	card.LayoutOrder = order or 0
	card.Parent = parent
	addCorner(card, UDim.new(0, 5))

	-- Rarity accent bar
	local rarBar = Instance.new("Frame")
	rarBar.Size = UDim2.new(0, 3, 1, -8)
	rarBar.Position = UDim2.new(0, 2, 0, 4)
	rarBar.BackgroundColor3 = getRarityColor(art.Rarity)
	rarBar.BorderSizePixel = 0
	rarBar.Parent = card
	addCorner(rarBar, UDim.new(0, 2))

	-- Icon
	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(0, 28, 0, 28)
	icon.Position = UDim2.new(0, 10, 0, 4)
	icon.BackgroundTransparency = 1
	icon.Text = art.BaseIcon or "📿"
	icon.TextSize = 20
	icon.Font = FONT_REG
	icon.Parent = card

	-- Name
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -140, 0, 18)
	name.Position = UDim2.new(0, 42, 0, 2)
	name.BackgroundTransparency = 1
	name.Text = art.Name or "Unknown"
	name.TextColor3 = getRarityColor(art.Rarity)
	name.TextSize = 12
	name.Font = FONT_BOLD
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = card

	-- Slot + Rarity
	local SLOT_ICONS = { Head = "🎩", Body = "👕", Accessory = "💍" }
	local slotIcon = SLOT_ICONS[art.Slot] or "📿"
	local meta = Instance.new("TextLabel")
	meta.Size = UDim2.new(1, -140, 0, 14)
	meta.Position = UDim2.new(0, 42, 0, 20)
	meta.BackgroundTransparency = 1
	meta.Text = slotIcon .. " " .. (art.Slot or "?") .. "  •  " .. (art.Rarity or "?")
	meta.TextColor3 = C.MUTED
	meta.TextSize = 10
	meta.Font = FONT_REG
	meta.TextXAlignment = Enum.TextXAlignment.Left
	meta.Parent = card

	-- Affixes
	if not isMine then
		local affixText = Instance.new("TextLabel")
		affixText.Size = UDim2.new(1, -100, 0, 14)
		affixText.Position = UDim2.new(0, 42, 0, 36)
		affixText.BackgroundTransparency = 1
		affixText.Text = getAffixSummary(art.Affixes)
		affixText.TextColor3 = C.BLUE
		affixText.TextSize = 9
		affixText.Font = FONT_REG
		affixText.TextXAlignment = Enum.TextXAlignment.Left
		affixText.TextTruncate = Enum.TextTruncate.AtEnd
		affixText.Parent = card

		-- Seller
		local seller = Instance.new("TextLabel")
		seller.Size = UDim2.new(0, 100, 0, 14)
		seller.Position = UDim2.new(0, 42, 0, 52)
		seller.BackgroundTransparency = 1
		seller.Text = "by " .. (listing.SellerName or "?")
		seller.TextColor3 = C.DIM
		seller.TextSize = 9
		seller.Font = FONT_REG
		seller.TextXAlignment = Enum.TextXAlignment.Left
		seller.Parent = card
	end

	-- Price
	local priceLabel = Instance.new("TextLabel")
	priceLabel.Size = UDim2.new(0, 70, 0, 20)
	priceLabel.Position = UDim2.new(1, -135, 0, 4)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = formatMoney(listing.Price or 0)
	priceLabel.TextColor3 = C.GREEN
	priceLabel.TextSize = 13
	priceLabel.Font = FONT_MONO
	priceLabel.TextXAlignment = Enum.TextXAlignment.Right
	priceLabel.Parent = card

	-- Action button
	if isMine then
		local cancelBtn = Instance.new("TextButton")
		cancelBtn.Size = UDim2.new(0, 55, 0, 26)
		cancelBtn.Position = UDim2.new(1, -62, 0, 4)
		cancelBtn.BackgroundColor3 = Color3.fromRGB(80, 30, 30)
		cancelBtn.Text = "Cancel"
		cancelBtn.TextColor3 = C.RED
		cancelBtn.TextSize = 10
		cancelBtn.Font = FONT_BOLD
		cancelBtn.Parent = card
		addCorner(cancelBtn, UDim.new(0, 4))

		cancelBtn.MouseButton1Click:Connect(function()
			handleCancelListing(listing.ListingGUID)
		end)
	else
		-- Don't show BUY on own listings
		if listing.SellerId ~= Player.UserId then
			local buyBtn = Instance.new("TextButton")
			buyBtn.Size = UDim2.new(0, 55, 0, 30)
			buyBtn.Position = UDim2.new(1, -62, 0, 20)
			buyBtn.BackgroundColor3 = Color3.fromRGB(30, 80, 50)
			buyBtn.Text = "BUY"
			buyBtn.TextColor3 = C.GREEN
			buyBtn.TextSize = 12
			buyBtn.Font = FONT_BOLD
			buyBtn.Parent = card
			addCorner(buyBtn, UDim.new(0, 4))
			addStroke(buyBtn, C.GREEN)

			buyBtn.MouseButton1Click:Connect(function()
				handleBuyListing(listing.ListingGUID, listing.Price, art.Name)
			end)

			buyBtn.MouseEnter:Connect(function()
				TweenService:Create(buyBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(40, 120, 65) }):Play()
			end)
			buyBtn.MouseLeave:Connect(function()
				TweenService:Create(buyBtn, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(30, 80, 50) }):Play()
			end)
		end
	end

	-- Hover effect
	card.MouseEnter:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.1), { BackgroundColor3 = C.CARD_HOVER }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(card, TweenInfo.new(0.1), { BackgroundColor3 = C.CARD }):Play()
	end)
end

--------------------------------------------------------------------------------
-- DROPDOWN (Artifact Selector)
--------------------------------------------------------------------------------

populateDropdown = function(menu)
	-- Clear old entries
	for _, child in menu:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end

	-- Fetch unequipped artifacts
	local success, result = pcall(GetArtifactsFunc.InvokeServer, GetArtifactsFunc)
	if success and result and result.unequipped then
		myArtifacts = result.unequipped
	else
		myArtifacts = {}
	end

	if #myArtifacts == 0 then
		local emptyItem = Instance.new("TextLabel")
		emptyItem.Size = UDim2.new(1, 0, 0, 28)
		emptyItem.BackgroundTransparency = 1
		emptyItem.Text = "No unequipped artifacts"
		emptyItem.TextColor3 = C.DIM
		emptyItem.TextSize = 10
		emptyItem.Font = FONT_REG
		emptyItem.ZIndex = 51
		emptyItem.Parent = menu
		return
	end

	local totalHeight = 0
	for i, artifact in ipairs(myArtifacts) do
		local item = Instance.new("TextButton")
		item.Size = UDim2.new(1, -4, 0, 28)
		item.BackgroundColor3 = C.CARD
		item.BackgroundTransparency = 0.5
		item.Text = (artifact.BaseIcon or "") .. " " .. (artifact.Name or "?") .. " [" .. (artifact.Rarity or "?") .. "]"
		item.TextColor3 = getRarityColor(artifact.Rarity)
		item.TextSize = 10
		item.Font = FONT_REG
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.TextTruncate = Enum.TextTruncate.AtEnd
		item.LayoutOrder = i
		item.ZIndex = 51
		item.Parent = menu
		addCorner(item, UDim.new(0, 3))

		item.MouseButton1Click:Connect(function()
			selectedArtifactGUID = artifact.GUID
			artifactDropdown.Text = (artifact.BaseIcon or "") .. " " .. (artifact.Name or "?")
			artifactDropdown.TextColor3 = getRarityColor(artifact.Rarity)
			menu.Visible = false
		end)

		item.MouseEnter:Connect(function()
			item.BackgroundTransparency = 0
		end)
		item.MouseLeave:Connect(function()
			item.BackgroundTransparency = 0.5
		end)

		totalHeight += 30
	end

	menu.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
end

--------------------------------------------------------------------------------
-- ACTIONS
--------------------------------------------------------------------------------

handleCreateListing = function()
	if not selectedArtifactGUID then
		setStatus("Select an artifact first!", C.RED)
		return
	end

	local priceText = priceInput.Text
	local price = tonumber(priceText)
	if not price or price <= 0 then
		setStatus("Enter a valid price!", C.RED)
		return
	end

	setStatus("Listing...", C.GOLD)

	task.spawn(function()
		local ok, result = pcall(CreateListingFunc.InvokeServer, CreateListingFunc, selectedArtifactGUID, price)
		if ok then
			if result == true then
				setStatus("Listed successfully!", C.GREEN)
				selectedArtifactGUID = nil
				artifactDropdown.Text = "Select an artifact ▼"
				artifactDropdown.TextColor3 = C.MUTED
				priceInput.Text = ""
				refreshAll()
			else
				-- result is false, second return is error message
				setStatus("Failed: check your artifacts", C.RED)
			end
		else
			setStatus("Error: " .. tostring(result), C.RED)
		end
	end)
end

handleBuyListing = function(listingGUID, price, artifactName)
	setStatus("Buying " .. (artifactName or "artifact") .. "...", C.GOLD)

	task.spawn(function()
		local ok, result = pcall(BuyListingFunc.InvokeServer, BuyListingFunc, listingGUID)
		if ok and result == true then
			setStatus("Purchased! Check your inventory.", C.GREEN)
			recentlyPurchased[listingGUID] = true
			refreshAll()
		else
			local msg = "Purchase failed"
			if type(result) == "string" then
				msg = result
			end
			setStatus(msg, C.RED)
		end
	end)
end

handleCancelListing = function(listingGUID)
	setStatus("Cancelling...", C.GOLD)

	task.spawn(function()
		local ok, result = pcall(CancelListingFunc.InvokeServer, CancelListingFunc, listingGUID)
		if ok and result == true then
			setStatus("Listing cancelled. Artifact returned.", C.GREEN)
			refreshAll()
		else
			setStatus("Cancel failed", C.RED)
		end
	end)
end

--------------------------------------------------------------------------------
-- REFRESH
--------------------------------------------------------------------------------

refreshAll = function()
	task.spawn(function()
		local ok, data = pcall(GetListingsFunc.InvokeServer, GetListingsFunc, currentFilters)
		if ok and data then
			marketListingsData = data.listings or {}
			myListingsData = data.myListings or {}
		end

		refreshMyListings()
		refreshBrowseListings()
	end)
end

refreshMyListings = function()
	if not myListingsScroll then return end

	local currentCards = {}
	for _, child in myListingsScroll:GetChildren() do
		if child:IsA("Frame") and string.sub(child.Name, 1, 5) == "Card_" then
			currentCards[child.Name] = child
		end
	end

	local emptyLabel = myListingsScroll:FindFirstChild("EmptyLabel")

	if #myListingsData == 0 then
		if not emptyLabel then
			emptyLabel = Instance.new("TextLabel")
			emptyLabel.Name = "EmptyLabel"
			emptyLabel.Size = UDim2.new(1, 0, 0, 40)
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Text = "No active listings"
			emptyLabel.TextColor3 = C.DIM
			emptyLabel.TextSize = 10
			emptyLabel.Font = FONT_REG
			emptyLabel.Parent = myListingsScroll
		end
	else
		if emptyLabel then emptyLabel:Destroy() end
	end

	for i, listing in ipairs(myListingsData) do
		local cardName = "Card_" .. (listing.ListingGUID or "?")
		local existing = currentCards[cardName]
		if existing then
			existing.LayoutOrder = i
			currentCards[cardName] = nil -- keep it
		else
			createListingCard(myListingsScroll, listing, true, i)
		end
	end

	-- Destroy leftover cards
	for _, card in pairs(currentCards) do
		card:Destroy()
	end

	-- Update canvas
	local totalHeight = #myListingsData * 59
	myListingsScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(40, totalHeight))
end

refreshBrowseListings = function()
	if not browseScroll then return end

	local currentCards = {}
	for _, child in browseScroll:GetChildren() do
		if child:IsA("Frame") and string.sub(child.Name, 1, 5) == "Card_" then
			currentCards[child.Name] = child
		end
	end

	local emptyLabel = browseScroll:FindFirstChild("EmptyLabel")

	-- Apply client-side filters (server already filtered, but double-check for cached data)
	local filtered = {}
	for _, listing in ipairs(marketListingsData) do
		local art = listing.Artifact
		if art and not recentlyPurchased[listing.ListingGUID] then
			local include = true
			if currentFilters.slot ~= "All" and art.Slot ~= currentFilters.slot then
				include = false
			end
			if currentFilters.rarity ~= "All" and art.Rarity ~= currentFilters.rarity then
				include = false
			end
			if currentFilters.search ~= "" then
				local s = string.lower(currentFilters.search)
				local n = string.lower(art.Name or "")
				if not string.find(n, s, 1, true) then
					include = false
				end
			end
			if include then
				table.insert(filtered, listing)
			end
		end
	end

	-- Sort
	if currentFilters.sortBy == "PriceDesc" then
		table.sort(filtered, function(a, b) return (a.Price or 0) > (b.Price or 0) end)
	elseif currentFilters.sortBy == "Newest" then
		table.sort(filtered, function(a, b) return (a.Timestamp or 0) > (b.Timestamp or 0) end)
	else
		table.sort(filtered, function(a, b) return (a.Price or 0) < (b.Price or 0) end)
	end

	if #filtered == 0 then
		if not emptyLabel then
			emptyLabel = Instance.new("TextLabel")
			emptyLabel.Name = "EmptyLabel"
			emptyLabel.Size = UDim2.new(1, 0, 0, 60)
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Text = "No listings found.\nBe the first to list an artifact!"
			emptyLabel.TextColor3 = C.DIM
			emptyLabel.TextSize = 13
			emptyLabel.Font = FONT_REG
			emptyLabel.Parent = browseScroll
		end
	else
		if emptyLabel then emptyLabel:Destroy() end
	end

	for i, listing in ipairs(filtered) do
		local cardName = "Card_" .. (listing.ListingGUID or "?")
		local existing = currentCards[cardName]
		if existing then
			existing.LayoutOrder = i
			currentCards[cardName] = nil -- keep it
		else
			createListingCard(browseScroll, listing, false, i)
		end
	end

	-- Destroy leftover cards
	for _, card in pairs(currentCards) do
		card:Destroy()
	end

	local totalHeight = #filtered * 72
	browseScroll.CanvasSize = UDim2.new(0, 0, 0, math.max(60, totalHeight))
end

--------------------------------------------------------------------------------
-- OPEN / CLOSE
--------------------------------------------------------------------------------

openExchange = function()
	if isOpen then return end
	isOpen = true

	if not screenGui then
		createMainUI()
	end

	screenGui.Enabled = true

	-- Animate in
	mainFrame.Position = UDim2.new(0.5, -450, 0.5, -260)
	mainFrame.Size = UDim2.new(0, 880, 0, 540)
	TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 900, 0, 560),
		Position = UDim2.new(0.5, -450, 0.5, -280),
	}):Play()

	refreshAll()
end

closeExchange = function()
	if not isOpen then return end
	isOpen = false

	if screenGui then
		TweenService:Create(mainFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Size = UDim2.new(0, 860, 0, 520),
		}):Play()
		task.delay(0.15, function()
			if screenGui then
				screenGui.Enabled = false
			end
		end)
	end
end

local function toggleExchange()
	if isOpen then closeExchange() else openExchange() end
end

--------------------------------------------------------------------------------
-- AUTO-REFRESH LOOP
--------------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(ArtifactExchangeConfig.CLIENT_REFRESH_HINT)
		if isOpen then
			refreshAll()
		end
	end
end)

--------------------------------------------------------------------------------
-- INPUT BINDINGS
--------------------------------------------------------------------------------

-- G keybind
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.G then
		toggleExchange()
	end
end)

-- ExchangeToggleEvent (from MoneyHUD bottom bar button)
local exchangeToggleEvent = ReplicatedStorage:FindFirstChild("ExchangeToggleEvent")
if not exchangeToggleEvent then
	exchangeToggleEvent = Instance.new("BindableEvent")
	exchangeToggleEvent.Name = "ExchangeToggleEvent"
	exchangeToggleEvent.Parent = ReplicatedStorage
end
exchangeToggleEvent.Event:Connect(toggleExchange)

-- AdminPanel integration
local UIManager = require(script.Parent:WaitForChild("Managers"):WaitForChild("UIManager"))
UIManager.RegisterShop("ArtifactExchange", toggleExchange)

-- Proximity Prompt (ShopInteraction pattern)
local _shopInteraction = ShopInteraction.new({
	PromptTag = ArtifactExchangeConfig.VENDOR_TAG,
	InteractionDist = 25,
	OnOpen = openExchange,
	OnClose = closeExchange,
})

-- Sale notification handler
ExchangeNotifyEvent.OnClientEvent:Connect(function(notifType, data)
	if notifType == "sold" then
		local msg = "Your " .. (data.ArtifactName or "artifact") .. " sold for " .. formatMoney(data.Revenue or 0) .. "!"
		setStatus("💰 " .. msg, C.GOLD)
	end
end)

print("✓ ArtifactExchangeUI Initialized (Keybind: G)")
