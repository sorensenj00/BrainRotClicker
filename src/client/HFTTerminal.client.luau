--[[
	HFTTerminal Client Script (v4.0)
	
	High-Frequency Trading Terminal - 2-column Bloomberg-style interface.
	Replaces old 3-column layout. Keybind: M
	
	Layout:
	  Left (40%)   - PORTFOLIO (Storage Holdings, Cash, Portfolio Value)
	  Right (60%)  - INSPECTOR & TRADING (Item detail, Local/Global prices,
	                 Arbitrage alerts, BUY/SELL with quantity multipliers)
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")

local StorageUpdatedEvent = RemoteEvents:WaitForChild("StorageUpdated")
local PushCartRemote = RemoteEvents:WaitForChild("PushCart")
local ReturnCartRemote = RemoteEvents:WaitForChild("ReturnCart")
local GetStorageFunction = RemoteFunctions:WaitForChild("GetStorage")
local LoadMaxFromStorageFunction = RemoteFunctions:WaitForChild("LoadMaxFromStorage")
local GetMarketPricesFunction = RemoteFunctions:WaitForChild("GetMarketPrices")
local BuyToCartFunction = RemoteFunctions:WaitForChild("BuyToCart")
local SellFromCartFunction = RemoteFunctions:WaitForChild("SellFromCart")
local GetActiveContractsFunction = RemoteFunctions:WaitForChild("GetActiveContracts")
local DeliverToContractFunction = RemoteFunctions:WaitForChild("DeliverToContract")
local ContractEvent = RemoteEvents:WaitForChild("ContractEvent")

local stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket")

-- Shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local MarketConfig = require(Shared:WaitForChild("MarketConfig"))
local ContractConfig = require(Shared:WaitForChild("ContractConfig"))
local SparklineRenderer = require(Shared:WaitForChild("SparklineRenderer"))
local CartController = require(script.Parent:WaitForChild("Controllers"):WaitForChild("CartController"))

--------------------------------------------------------------------------------
-- THEME
--------------------------------------------------------------------------------

local C = {
	bg = Color3.fromRGB(15, 10, 20),
	panel = Color3.fromRGB(25, 20, 35),
	card = Color3.fromRGB(35, 30, 50),
	header = Color3.fromRGB(110, 40, 180),
	border = Color3.fromRGB(50, 40, 70),
	green = Color3.fromRGB(30, 215, 95),
	red = Color3.fromRGB(245, 50, 50),
	gold = Color3.fromRGB(255, 190, 50),
}

local FONT_MONO = Enum.Font.RobotoMono
local FONT_BOLD = Enum.Font.GothamBold
local FONT_REG  = Enum.Font.Gotham
local PAD       = 10

local C_WHITE = Color3.fromRGB(240, 240, 245)
local C_MUTED = Color3.fromRGB(145, 145, 168)
local C_DIM_BG = Color3.fromRGB(22, 18, 30)
local C_CYAN = Color3.fromRGB(80, 190, 255)
local C_ARB_FLASH = Color3.fromRGB(255, 210, 120)
local C_OWNED_BG = Color3.fromRGB(15, 35, 20)
local C_SEARCH_PLACEHOLDER = Color3.fromRGB(170, 160, 195)

local MAX_BUY = MarketConfig.CONFIG.MAX_BUY_PER_TRANSACTION or 100
local ARB_THRESHOLD = MarketConfig.CONFIG.ARBITRAGE_ALERT_THRESHOLD or 0.15

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local isOpen = false
local currentStorage = {}       -- {[itemId] = count} (storage silo, for reference)
local storageUsage = 0
local storageCapacity = 0
local cartInventory = {}        -- {[itemId] = count} (what's in the cart)
local cartState = "idle"        -- idle, rolling_to_market, at_market, rolling_to_plot
local cartCapacity = 200
local cartItemCount = 0
local globalItemRates = {}      -- {[itemId] = globalRate}
local localItemRates = {}       -- {[itemId] = localRate}
local sectorRates = {}          -- {[sector] = rate}
local itemHistories = {}        -- {[itemId] = {number}}
local sectorHistories = {}      -- {[sector] = {number}}
local inspectedItem = nil       -- Currently selected item for trading
local selectedQty = 1           -- Current quantity multiplier
local assetSearchQuery = ""
local assetSearchBox
local activeTab = "TRADING"
local contractsById = {}        -- {[instanceId] = ActiveContract-like payload}
local selectedContractId = nil
local contractDeliverMode = "MAX" -- "MAX" | "X10"
local contractRowPool = {}      -- {[number] = TextButton}
local rowDefaultColors = {}     -- {[rowName] = Color3}
local rowFlashDebounce = {}     -- {[rowName] = boolean}
local prevLocalPrices = {}      -- {[itemId] = number}
local hasShownIntroToast = false
local hasAutoFocusedRecommendedItemThisOpen = false

-- UI refs
local screenGui, mainFrame
local leftScroll, _rightPanel
local stoCapFill, stoCapText
local cartStatusBanner
local inspectorFrame
local tabTradingBtn, tabContractsBtn
local contractsPanel, contractsList, contractsDetail
local refreshContractsList
local topBarTitleLabel, topBarStatusLabel, topBarRateNameLabel
local leftHeaderLabel, inspectorHeaderLabel
local isDetailedMarketUnlocked
local areContractsUnlocked
local refreshUnlockState
local isTerminalIntroComplete
local isGuidedTerminalMode
local isSellFocusedTerminalMode
local syncGuidedRecommendation
local updateTopBarChrome

local function getContractTemplate(templateId)
	for _, t in ipairs(ContractConfig.FlashOrderTemplates) do
		if t.Id == templateId then return t end
	end
	for _, t in ipairs(ContractConfig.MegaProjectTemplates) do
		if t.Id == templateId then return t end
	end
	return nil
end

local function formatDuration(secondsLeft: number): string
	local s = math.max(0, math.floor(secondsLeft))
	local m = math.floor(s / 60)
	local sec = s % 60
	return string.format("%02d:%02d", m, sec)
end

local function setTab(tabName: string)
	activeTab = tabName
	if tabTradingBtn then
		local isTrading = tabName == "TRADING"
		tabTradingBtn.BackgroundColor3 = isTrading and C.gold or C.card
		tabTradingBtn.TextColor3 = isTrading and C.bg or C_WHITE
	end
	if tabContractsBtn then
		local isContracts = tabName == "CONTRACTS"
		tabContractsBtn.BackgroundColor3 = isContracts and C.gold or C.card
		tabContractsBtn.TextColor3 = isContracts and C.bg or C_WHITE
	end
	if inspectorFrame then
		inspectorFrame.Visible = tabName == "TRADING"
	end
	if contractsPanel then
		contractsPanel.Visible = tabName == "CONTRACTS" and areContractsUnlocked() and not isGuidedTerminalMode()
	end
end

isDetailedMarketUnlocked = function(): boolean
	return Player:GetAttribute("DetailedMarketUnlocked") == true
end

areContractsUnlocked = function(): boolean
	return Player:GetAttribute("ContractsUnlocked") == true
end

refreshUnlockState = function()
	if tabContractsBtn then
		tabContractsBtn.Visible = areContractsUnlocked() and not isGuidedTerminalMode()
	end
	if (not areContractsUnlocked() or isGuidedTerminalMode()) and activeTab == "CONTRACTS" then
		setTab("TRADING")
	end
	if contractsPanel then
		contractsPanel.Visible = areContractsUnlocked() and not isGuidedTerminalMode() and activeTab == "CONTRACTS"
	end
end

local function getContractItemDisplay(itemId: string): (string, string)
	local info = ItemConfig.Items[itemId]
	if not info then
		return "?", itemId
	end
	return info.icon or "?", info.displayName or itemId
end

local function updateContractsDetail()
	if not contractsDetail or not contractsDetail.Title then return end
	local contract = selectedContractId and contractsById[selectedContractId] or nil
	local deliverBtn = contractsDetail.DeliverBtn
	local modeX10 = contractsDetail.ModeX10
	local modeMax = contractsDetail.ModeMax
	if not contract then
		contractsDetail.Title.Text = "No contract selected"
		contractsDetail.Body.Text = "Select a contract from the list."
		if deliverBtn then
			deliverBtn.Text = "DELIVER"
			deliverBtn.Active = false
			deliverBtn.AutoButtonColor = false
			deliverBtn.BackgroundColor3 = Color3.fromRGB(95, 50, 55)
		end
		return
	end

	if modeX10 and modeX10:IsA("TextButton") then
		local active = contractDeliverMode == "X10"
		modeX10.BackgroundColor3 = active and C.gold or C.card
		modeX10.TextColor3 = active and C.bg or C_WHITE
	end
	if modeMax and modeMax:IsA("TextButton") then
		local active = contractDeliverMode == "MAX"
		modeMax.BackgroundColor3 = active and C.gold or C.card
		modeMax.TextColor3 = active and C.bg or C_WHITE
	end

	local icon, itemName = getContractItemDisplay(contract.TargetItemId)
	local nowTs = os.time()
	local timeLeft = math.max(0, (contract.EndTime or nowTs) - nowTs)
	local progress = 0
	if (contract.RequiredAmount or 0) > 0 then
		progress = (contract.CurrentAmount or 0) / contract.RequiredAmount
	end
	local multiplierText = contract.Type == "FlashOrder"
		and string.format("Multiplier: x%.2f", contract.Multiplier or 1)
		or "Multiplier: None (Co-op)"
	local pct = progress * 100
	local lines = {
		string.format("%s %s", icon, itemName),
		string.format("%s", multiplierText),
		string.format("Time Left: %s", formatDuration(timeLeft)),
		string.format("Progress: %d / %d (%.1f%%)", contract.CurrentAmount or 0, contract.RequiredAmount or 0, pct),
	}
	if contract.Type == "MegaProject" then
		local myContribution = 0
		if contract.Contributions then
			myContribution = contract.Contributions[Player.UserId] or 0
		end
		local myPct = ((contract.RequiredAmount or 1) > 0) and ((myContribution / contract.RequiredAmount) * 100) or 0
		local minPct = 2.0
		local template = getContractTemplate(contract.TemplateId)
		if template and template.MinContributionPct then
			minPct = template.MinContributionPct * 100
		end
		local missing = math.max(0, minPct - myPct)
		table.insert(lines, string.format("Dit bidrag: %.2f%% - Du mangler %.2f%%", myPct, missing))
	end

	contractsDetail.Title.Text = contract.Name or "Contract"
	contractsDetail.Body.Text = table.concat(lines, "\n")

	local canDeliver = cartState == "at_market"
	local inCart = tonumber(cartInventory[contract.TargetItemId]) or 0
	local amountText = contractDeliverMode == "X10" and "x10" or "MAX"
	if deliverBtn then
		deliverBtn.Active = canDeliver
		deliverBtn.AutoButtonColor = canDeliver
		deliverBtn.BackgroundColor3 = canDeliver and C.green or Color3.fromRGB(95, 50, 55)
		deliverBtn.TextColor3 = canDeliver and Color3.new(0, 0, 0) or C_WHITE
		deliverBtn.Text = canDeliver
			and string.format("DELIVER %s (IN CART: %d)", amountText, inCart)
			or "CART NOT AT MARKET"
	end
end

local function deliverSelectedContract(maxAmount: number?)
	if cartState ~= "at_market" then return end
	if not selectedContractId then return end
	local response = DeliverToContractFunction:InvokeServer(selectedContractId, maxAmount)
	if type(response) == "table" and response.Success then
		local contract = contractsById[selectedContractId]
		if contract then
			local delivered = tonumber(response.AmountDelivered) or 0
			contract.CurrentAmount = (contract.CurrentAmount or 0) + delivered
			contract.Contributions = contract.Contributions or {}
			contract.Contributions[Player.UserId] = (contract.Contributions[Player.UserId] or 0) + delivered
			if contract.CurrentAmount >= (contract.RequiredAmount or 0) then
				contractsById[selectedContractId] = nil
				selectedContractId = nil
			end
		end
		refreshContractsList()
	end
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local FormatUtils = require(Shared:WaitForChild("Utils"):WaitForChild("FormatUtils"))
local UIUtils = require(Shared:WaitForChild("Utils"):WaitForChild("UIUtils"))

local addCorner = UIUtils.addCorner
local addStroke = UIUtils.addStroke
local formatMoney = FormatUtils.formatMoney
local decodeItems = UIUtils.decodeItems

isTerminalIntroComplete = function(): boolean
	return Player:GetAttribute("TerminalIntroComplete") == true
end

isSellFocusedTerminalMode = function(): boolean
	return isDetailedMarketUnlocked() and Player:GetAttribute("SynergyUnlocked") ~= true
end

isGuidedTerminalMode = function(): boolean
	return isSellFocusedTerminalMode() and not isTerminalIntroComplete()
end

local function notifyToast(message: string, typeKey: string?, duration: number?)
	local notificationManager = _G.NotificationManager
	if notificationManager and notificationManager.ShowToast then
		notificationManager.ShowToast(message, typeKey or "info", duration or 4)
	end
end

local function notifyBanner(message: string, color: Color3?, duration: number?)
	local notificationManager = _G.NotificationManager
	if notificationManager and notificationManager.ShowBanner then
		notificationManager.ShowBanner(message, color or C.gold, duration or 4.5)
	end
end

local function makeLabel(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = props.Color or C_WHITE
	l.Font = props.Font or FONT_REG
	l.TextSize = props.Size or 14
	l.TextXAlignment = props.XAlign or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = props.Text or ""
	l.Name = props.Name or "Label"
	if props.UDim2Size then l.Size = props.UDim2Size end
	if props.Position then l.Position = props.Position end
	l.Parent = parent
	return l
end

refreshContractsList = function()
	if not contractsList then return end

	local entries = {}
	for id, contract in pairs(contractsById) do
		table.insert(entries, { id = id, contract = contract })
	end
	table.sort(entries, function(a, b)
		return (a.contract.EndTime or 0) < (b.contract.EndTime or 0)
	end)

	local function getOrCreateContractRow(index: number): TextButton
		local row = contractRowPool[index]
		if row then
			return row
		end

		row = Instance.new("TextButton")
		row.Name = "ContractRow_" .. index
		row.Size = UDim2.new(1, -6, 0, 58)
		row.BorderSizePixel = 0
		row.Text = ""
		row.AutoButtonColor = false
		row.Parent = contractsList
		addCorner(row, UDim.new(0, 8))
		addStroke(row, C.border, 1)

		local idValue = Instance.new("StringValue")
		idValue.Name = "InstanceId"
		idValue.Parent = row

		makeLabel(row, {
			Name = "Name",
			Text = "",
			Color = C_WHITE,
			Font = FONT_BOLD,
			Size = 12,
			UDim2Size = UDim2.new(1, -8, 0, 18),
			Position = UDim2.new(0, 8, 0, 3),
		})
		makeLabel(row, {
			Name = "Meta",
			Text = "",
			Color = C_MUTED,
			Font = FONT_MONO,
			Size = 10,
			UDim2Size = UDim2.new(1, -8, 0, 14),
			Position = UDim2.new(0, 8, 0, 24),
		})

		local barBg = Instance.new("Frame")
		barBg.Name = "ProgressBg"
		barBg.Size = UDim2.new(1, -14, 0, 10)
		barBg.Position = UDim2.new(0, 7, 1, -13)
		barBg.BackgroundColor3 = C_DIM_BG
		barBg.BorderSizePixel = 0
		barBg.Parent = row
		addCorner(barBg, UDim.new(0, 3))

		local barFill = Instance.new("Frame")
		barFill.Name = "ProgressFill"
		barFill.Size = UDim2.new(0, 0, 1, 0)
		barFill.BackgroundColor3 = C.green
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg
		addCorner(barFill, UDim.new(0, 3))

		row.MouseButton1Click:Connect(function()
			local idObj = row:FindFirstChild("InstanceId")
			if not idObj or not idObj:IsA("StringValue") then return end
			if idObj.Value == "" then return end
			selectedContractId = idObj.Value
			refreshContractsList()
			updateContractsDetail()
		end)

		contractRowPool[index] = row
		return row
	end

	for i, entry in ipairs(entries) do
		local contract = entry.contract
		local btn = getOrCreateContractRow(i)
		btn.Position = UDim2.new(0, 3, 0, (i - 1) * 62)
		btn.BackgroundColor3 = (selectedContractId == entry.id) and Color3.fromRGB(50, 42, 65) or C.card
		btn.Visible = true

		local icon, itemName = getContractItemDisplay(contract.TargetItemId)
		local timeLeft = math.max(0, (contract.EndTime or os.time()) - os.time())
		local multiplierText = (contract.Type == "FlashOrder") and string.format("x%.1f", contract.Multiplier or 1) or "CO-OP"
		local progressText = string.format("%d / %d", contract.CurrentAmount or 0, contract.RequiredAmount or 0)
		local idValue = btn:FindFirstChild("InstanceId")
		if idValue and idValue:IsA("StringValue") then
			idValue.Value = entry.id
		end
		local nameLabel = btn:FindFirstChild("Name")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = string.format("%s %s  [%s]", icon, contract.Name or itemName, multiplierText)
		end
		local metaLabel = btn:FindFirstChild("Meta")
		if metaLabel and metaLabel:IsA("TextLabel") then
			metaLabel.Text = string.format("Time: %s   Progress: %s", formatDuration(timeLeft), progressText)
		end

		local ratio = 0
		if (contract.RequiredAmount or 0) > 0 then
			ratio = math.clamp((contract.CurrentAmount or 0) / contract.RequiredAmount, 0, 1)
		end
		local barBg = btn:FindFirstChild("ProgressBg")
		if barBg and barBg:IsA("Frame") then
			local barFill = barBg:FindFirstChild("ProgressFill")
			if barFill and barFill:IsA("Frame") then
				barFill.Size = UDim2.new(ratio, 0, 1, 0)
			end
		end
	end

	for i = #entries + 1, #contractRowPool do
		local row = contractRowPool[i]
		if row then
			row.Visible = false
		end
	end

	contractsList.CanvasSize = UDim2.new(0, 0, 0, #entries * 62)
	if not selectedContractId and entries[1] then
		selectedContractId = entries[1].id
	end
	updateContractsDetail()
end

local function fetchContracts()
	local ok, data = pcall(function()
		return GetActiveContractsFunction:InvokeServer()
	end)
	if not ok or type(data) ~= "table" then
		contractsById = {}
		selectedContractId = nil
		refreshContractsList()
		return
	end
	contractsById = data
	if selectedContractId and not contractsById[selectedContractId] then
		selectedContractId = nil
	end
	refreshContractsList()
end

local function matchesAssetSearch(itemId: string, displayName: string): boolean
	if assetSearchQuery == "" then return true end
	local needle = string.lower(assetSearchQuery)
	local byName = string.find(string.lower(displayName), needle, 1, true) ~= nil
	local byId = string.find(string.lower(itemId), needle, 1, true) ~= nil
	return byName or byId
end

local function applyRowVisualState(row, isOwned, isSelected)
	local stroke = row:FindFirstChild("OwnedStroke")
	local baseColor = isOwned and C_OWNED_BG or C.card
	if isSelected then
		baseColor = isOwned and Color3.fromRGB(20, 50, 30) or Color3.fromRGB(50, 42, 65)
	end
	rowDefaultColors[row.Name] = baseColor
	row.BackgroundColor3 = baseColor
	if stroke and stroke:IsA("UIStroke") then
		if isOwned then
			stroke.Enabled = true
			stroke.Color = C.green
			stroke.Transparency = 0
		else
			stroke.Enabled = false
			stroke.Transparency = 1
		end
	end
end

local function flashRow(row: TextButton, wentUp: boolean)
	if rowFlashDebounce[row.Name] then return end
	rowFlashDebounce[row.Name] = true

	local flashColor = wentUp and Color3.fromRGB(36, 90, 56) or Color3.fromRGB(95, 35, 40)
	local baseColor = rowDefaultColors[row.Name] or row.BackgroundColor3
	TweenService:Create(row, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {BackgroundColor3 = flashColor}):Play()
	task.delay(0.12, function()
		TweenService:Create(row, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {BackgroundColor3 = baseColor}):Play()
		task.delay(0.2, function()
			rowFlashDebounce[row.Name] = nil
		end)
	end)
end



local function getItemSector(itemId)
	for modelName, mapping in pairs(ItemConfig.BrainrotItems) do
		if mapping.tier1 == itemId or mapping.tier2 == itemId
			or mapping.tier3 == itemId or mapping.tier4 == itemId then
			return ItemConfig.GetSector(modelName)
		end
	end
	return "Neutral"
end

local function getLocalRate(itemId)
	return localItemRates[itemId] or globalItemRates[itemId] or 1.0
end

local function getGlobalRate(itemId)
	return globalItemRates[itemId] or 1.0
end

local function getLocalPrice(itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	return math.max(1, math.floor((info.basePrice or 1) * getLocalRate(itemId)))
end

local function getGlobalPrice(itemId)
	local info = ItemConfig.Items[itemId]
	if not info then return 0 end
	return math.max(1, math.floor((info.basePrice or 1) * getGlobalRate(itemId)))
end

local function isArbOpportunity(itemId)
	local local_ = getLocalRate(itemId)
	local global = getGlobalRate(itemId)
	if global == 0 then return false end
	local deviation = math.abs(local_ - global) / global
	return deviation > ARB_THRESHOLD
end

local function getPlayerMoney()
	local ls = Player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	return m and m.Value or 0
end

local function getTotalOwned(itemId: string): number
	return (currentStorage[itemId] or 0) + (cartInventory[itemId] or 0)
end

local function getGuidedPriorityCount(itemId: string): (number, string)
	local cartCount = cartInventory[itemId] or 0
	local storageCount = currentStorage[itemId] or 0

	if cartState == "at_market" and cartCount > 0 then
		return cartCount, "cart"
	end
	if storageCount > 0 then
		return storageCount, "storage"
	end
	if cartCount > 0 then
		return cartCount, "cart"
	end

	return 0, "none"
end

local function getGuidedOfferCopy(rate: number): (string, Color3)
	if rate >= 1.15 then
		return "Strong local offer. Cash out this stack now.", C.green
	elseif rate <= 0.9 then
		return "Weak offer. Hold this stack if you can.", C.red
	end
	return "Decent offer. Sell if you want faster reinvestment.", C.gold
end

local function getGuidedRecommendedItem()
	local bestEntry = nil

	for itemId, _ in pairs(ItemConfig.Items) do
		local count, source = getGuidedPriorityCount(itemId)
		if count > 0 then
			local localPrice = getLocalPrice(itemId)
			local totalValue = localPrice * count
			local info = ItemConfig.Items[itemId] or {}
			local candidate = {
				id = itemId,
				count = count,
				source = source,
				totalValue = totalValue,
				localPrice = localPrice,
				rate = getLocalRate(itemId),
				displayName = info.displayName or itemId,
				icon = info.icon or "?",
			}
			if not bestEntry
				or candidate.totalValue > bestEntry.totalValue
				or (candidate.totalValue == bestEntry.totalValue and candidate.displayName < bestEntry.displayName) then
				bestEntry = candidate
			end
		end
	end

	return bestEntry
end

syncGuidedRecommendation = function(forceSelection: boolean?)
	if not isGuidedTerminalMode() then
		return
	end

	local recommended = getGuidedRecommendedItem()
	if not recommended then
		if forceSelection then
			inspectedItem = nil
		end
		return
	end

	local currentCount = inspectedItem and select(1, getGuidedPriorityCount(inspectedItem)) or 0
	local shouldReplace = forceSelection == true
		or not inspectedItem
		or currentCount <= 0
		or (cartState == "at_market" and (cartInventory[inspectedItem] or 0) <= 0)

	if shouldReplace then
		inspectedItem = recommended.id
		hasAutoFocusedRecommendedItemThisOpen = true
	end
end

local function getGuidedStatusText(): string
	if cartState == "rolling_to_market" then
		return "Cart arriving at market"
	end
	if cartState == "at_market" and cartItemCount > 0 then
		return "Best sell ready"
	end
	if cartState == "idle" and cartItemCount > 0 then
		return "Send cart to market"
	end
	if storageUsage > 0 then
		return "Load stock to cart"
	end
	return "Ready to target your best stock"
end

updateTopBarChrome = function(blinkOn: boolean?)
	local guidedMode = isGuidedTerminalMode()
	local sellFocusedMode = isSellFocusedTerminalMode()
	if topBarTitleLabel then
		topBarTitleLabel.Text = sellFocusedMode and "MARKET TERMINAL" or "HFT TERMINAL v4.0"
	end
	if topBarRateNameLabel then
		topBarRateNameLabel.Visible = not sellFocusedMode
		if not sellFocusedMode then
			topBarRateNameLabel.Text = stockMarketFolder:GetAttribute("RateName") or ""
		else
			topBarRateNameLabel.Text = ""
		end
	end
	if topBarStatusLabel then
		if guidedMode then
			topBarStatusLabel.Text = getGuidedStatusText()
			topBarStatusLabel.TextColor3 = C_WHITE
		elseif sellFocusedMode then
			local dot = blinkOn == false and utf8.char(0x25CB) or utf8.char(0x25CF)
			topBarStatusLabel.Text = dot .. " SELL WINDOWS LIVE"
			topBarStatusLabel.TextColor3 = C.gold
		else
			local dot = blinkOn == false and utf8.char(0x25CB) or utf8.char(0x25CF)
			topBarStatusLabel.Text = dot .. " MARKET LIVE"
			topBarStatusLabel.TextColor3 = C.green
		end
	end
	if leftHeaderLabel then
		leftHeaderLabel.Text = sellFocusedMode and "YOUR STOCK" or "ORDER BOOK"
	end
	if inspectorHeaderLabel then
		if guidedMode then
			inspectorHeaderLabel.Text = "BEST SELL"
		elseif sellFocusedMode then
			inspectorHeaderLabel.Text = "SELL DESK"
		else
			inspectorHeaderLabel.Text = "TRADING INSPECTOR"
		end
	end
end

-- Data parsing
local function parseSectorRates()
	local raw = stockMarketFolder:GetAttribute("SectorRates")
	if not raw then return end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and decoded then
		for sector, rate in pairs(decoded) do sectorRates[sector] = rate end
	end
end

local function parseGlobalItemRates()
	local raw = stockMarketFolder:GetAttribute("ItemRates")
	if not raw then return end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and decoded then
		for itemId, rate in pairs(decoded) do
			globalItemRates[itemId] = rate
			-- Build history
			if not itemHistories[itemId] then
				itemHistories[itemId] = {}
				for _=1, 20 do table.insert(itemHistories[itemId], rate) end
			end
			table.insert(itemHistories[itemId], rate)
			if #itemHistories[itemId] > 30 then
				table.remove(itemHistories[itemId], 1)
			end
		end
	end
end

local function parseLocalItemRates()
	local raw = stockMarketFolder:GetAttribute("LocalItemRates")
	if not raw then return end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and decoded then
		for itemId, rate in pairs(decoded) do
			localItemRates[itemId] = rate
		end
	end
end

local function parseSectorHistories()
	local raw = stockMarketFolder:GetAttribute("SectorHistories")
	if not raw then return end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or not decoded then return end
	for sector, histStr in pairs(decoded) do
		if type(histStr) == "string" then
			local nums = {}
			for val in string.gmatch(histStr, "([^,]+)") do
				table.insert(nums, tonumber(val) or 1.0)
			end
			sectorHistories[sector] = nums
		end
	end
end



--------------------------------------------------------------------------------
-- MAIN CONTAINER
--------------------------------------------------------------------------------

local function createContainer()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HFTTerminal"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10
	screenGui.Parent = PlayerGui

	mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(1, -60, 1, -100)
	mainFrame.Position = UDim2.new(0, 30, 0, 55)
	mainFrame.BackgroundColor3 = C.bg
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui
	addCorner(mainFrame, UDim.new(0, 12))
	addStroke(mainFrame, C.header, 2)

	-- Top bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 38)
	topBar.BackgroundColor3 = C.header
	topBar.BorderSizePixel = 0
	topBar.Parent = mainFrame
	addCorner(topBar, UDim.new(0, 10))

	topBarTitleLabel = makeLabel(topBar, {
		Name = "Title", Text = "HFT TERMINAL v4.0",
		Color = C_WHITE, Font = FONT_BOLD, Size = 15,
		UDim2Size = UDim2.new(0, 300, 1, 0),
		Position = UDim2.new(0, 14, 0, 0),
	})

	local statusLabel = makeLabel(topBar, {
		Name = "Status", Text = utf8.char(0x25CF) .. " MARKET LIVE",
		Color = C_WHITE, Font = FONT_MONO, Size = 12,
		UDim2Size = UDim2.new(0, 200, 1, 0),
		Position = UDim2.new(0.5, -100, 0, 0),
		XAlign = Enum.TextXAlignment.Center,
	})
	topBarStatusLabel = statusLabel

	topBarRateNameLabel = makeLabel(topBar, {
		Name = "RateName", Text = "",
		Color = C_WHITE, Font = FONT_MONO, Size = 11,
		UDim2Size = UDim2.new(0, 200, 1, 0),
		Position = UDim2.new(1, -260, 0, 0),
		XAlign = Enum.TextXAlignment.Right,
	})

	tabTradingBtn = Instance.new("TextButton")
	tabTradingBtn.Name = "TabTrading"
	tabTradingBtn.Size = UDim2.new(0, 90, 0, 26)
	tabTradingBtn.Position = UDim2.new(0, 250, 0, 6)
	tabTradingBtn.BackgroundColor3 = C.gold
	tabTradingBtn.Text = "TRADING"
	tabTradingBtn.TextColor3 = C.bg
	tabTradingBtn.TextSize = 11
	tabTradingBtn.Font = FONT_BOLD
	tabTradingBtn.AutoButtonColor = false
	tabTradingBtn.Parent = topBar
	addCorner(tabTradingBtn, UDim.new(0, 6))

	tabContractsBtn = Instance.new("TextButton")
	tabContractsBtn.Name = "TabContracts"
	tabContractsBtn.Size = UDim2.new(0, 100, 0, 26)
	tabContractsBtn.Position = UDim2.new(0, 346, 0, 6)
	tabContractsBtn.BackgroundColor3 = C.card
	tabContractsBtn.Text = "CONTRACTS"
	tabContractsBtn.TextColor3 = C_WHITE
	tabContractsBtn.TextSize = 11
	tabContractsBtn.Font = FONT_BOLD
	tabContractsBtn.AutoButtonColor = false
	tabContractsBtn.Parent = topBar
	addCorner(tabContractsBtn, UDim.new(0, 6))

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -44, 0, 1)
	closeBtn.BackgroundColor3 = C.red
	closeBtn.BackgroundTransparency = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextSize = 18
	closeBtn.Font = FONT_BOLD
	closeBtn.Parent = topBar
	addCorner(closeBtn, UDim.new(0, 8))

	-- Content area
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -PAD*2, 1, -38 - PAD)
	content.Position = UDim2.new(0, PAD, 0, 38 + PAD/2)
	content.BackgroundTransparency = 1
	content.Parent = mainFrame

	return content, closeBtn, statusLabel
end

--------------------------------------------------------------------------------
-- LEFT COLUMN - PORTFOLIO
--------------------------------------------------------------------------------

local portfolioLiquidLabel, portfolioAssetsLabel

local function createLeftColumn(parent)
	local col = Instance.new("Frame")
	col.Name = "LeftColumn"
	col.Size = UDim2.new(0.38, -6, 1, 0)
	col.Position = UDim2.new(0, 0, 0, 0)
	col.BackgroundColor3 = C.panel
	col.BorderSizePixel = 0
	col.Parent = parent
	addCorner(col, UDim.new(0, 10))
	addStroke(col, C.border, 1.5)

	-- Header
	leftHeaderLabel = makeLabel(col, {
		Name = "Header", Text = "ORDER BOOK",
		Color = C.gold, Font = FONT_BOLD, Size = 14,
		UDim2Size = UDim2.new(1, -12, 0, 28),
		Position = UDim2.new(0, 8, 0, 6),
	})

	-- Cash + Portfolio value bar
	local statsBar = Instance.new("Frame")
	statsBar.Name = "StatsBar"
	statsBar.Size = UDim2.new(1, -16, 0, 48)
	statsBar.Position = UDim2.new(0, 8, 0, 34)
	statsBar.BackgroundColor3 = C_DIM_BG
	statsBar.BorderSizePixel = 0
	statsBar.Parent = col
	addCorner(statsBar, UDim.new(0, 4))
	addStroke(statsBar, C.border, 1)

	makeLabel(statsBar, { Name = "LblCash", Text = "LIQUID CASH", Color = C_MUTED, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(0.5, 0, 0, 13), Position = UDim2.new(0, 8, 0, 5) })
	portfolioLiquidLabel = makeLabel(statsBar, { Name = "ValCash", Text = "$0", Color = C.green, Font = FONT_MONO, Size = 15,
		UDim2Size = UDim2.new(0.5, 0, 0, 22), Position = UDim2.new(0, 8, 0, 20) })

	makeLabel(statsBar, { Name = "LblPortfolio", Text = "PORTFOLIO VALUE", Color = C_MUTED, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(0.5, -8, 0, 13), Position = UDim2.new(0.5, 0, 0, 5), XAlign = Enum.TextXAlignment.Right })
	portfolioAssetsLabel = makeLabel(statsBar, { Name = "ValPortfolio", Text = "$0", Color = C.gold, Font = FONT_MONO, Size = 15,
		UDim2Size = UDim2.new(0.5, -8, 0, 22), Position = UDim2.new(0.5, 0, 0, 20), XAlign = Enum.TextXAlignment.Right })

	-- Capacity bar (now shows CART capacity)
	makeLabel(col, { Name = "CapLabel", Text = "CART CAPACITY", Color = C_MUTED, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(1, -16, 0, 12), Position = UDim2.new(0, 8, 0, 88) })

	local capFrame = Instance.new("Frame")
	capFrame.Name = "CapBar"
	capFrame.Size = UDim2.new(1, -16, 0, 14)
	capFrame.Position = UDim2.new(0, 8, 0, 102)
	capFrame.BackgroundColor3 = C_DIM_BG
	capFrame.BorderSizePixel = 0
	capFrame.Parent = col
	addCorner(capFrame, UDim.new(0, 4))

	local capFill = Instance.new("Frame")
	capFill.Name = "Fill"
	capFill.Size = UDim2.new(0, 0, 1, 0)
	capFill.BackgroundColor3 = C.gold
	capFill.BorderSizePixel = 0
	capFill.Parent = capFrame
	addCorner(capFill, UDim.new(0, 4))

	stoCapText = makeLabel(capFrame, { Name = "Text", Text = "0/0", Color = C_WHITE, Font = FONT_MONO, Size = 9,
		UDim2Size = UDim2.new(1, 0, 1, 0), XAlign = Enum.TextXAlignment.Center })
	stoCapFill = capFill

	-- Cart status banner
	cartStatusBanner = Instance.new("Frame")
	cartStatusBanner.Name = "CartStatusBanner"
	cartStatusBanner.Size = UDim2.new(1, -8, 0, 24)
	cartStatusBanner.Position = UDim2.new(0, 4, 0, 122)
	cartStatusBanner.BackgroundColor3 = C_DIM_BG
	cartStatusBanner.BorderSizePixel = 0
	cartStatusBanner.Parent = col
	addCorner(cartStatusBanner, UDim.new(0, 4))

	local bannerText = makeLabel(cartStatusBanner, {
		Name = "BannerText", Text = "CART AT PLOT",
		Color = C_MUTED, Font = FONT_MONO, Size = 10,
		UDim2Size = UDim2.new(1, 0, 1, 0),
		XAlign = Enum.TextXAlignment.Center,
	})
	bannerText.TextXAlignment = Enum.TextXAlignment.Center

	assetSearchBox = Instance.new("TextBox")
	assetSearchBox.Name = "SearchBar"
	assetSearchBox.Size = UDim2.new(1, -8, 0, 30)
	assetSearchBox.Position = UDim2.new(0, 4, 0, 150)
	assetSearchBox.BackgroundColor3 = C.card
	assetSearchBox.BorderSizePixel = 0
	assetSearchBox.ClearTextOnFocus = false
	assetSearchBox.PlaceholderText = utf8.char(0x1F50D) .. " Search assets..."
	assetSearchBox.PlaceholderColor3 = C_SEARCH_PLACEHOLDER
	assetSearchBox.Text = ""
	assetSearchBox.TextColor3 = C_WHITE
	assetSearchBox.TextSize = 14
	assetSearchBox.Font = FONT_REG
	assetSearchBox.Parent = col
	addCorner(assetSearchBox, UDim.new(0, 8))
	addStroke(assetSearchBox, C.border, 1)

	assetSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
		assetSearchQuery = string.lower(string.gsub(assetSearchBox.Text or "", "^%s*(.-)%s*$", "%1"))
		updateLeftColumn()
	end)

	-- Scrolling cart item list
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "AssetList"
	scroll.Size = UDim2.new(1, -8, 1, -188)
	scroll.Position = UDim2.new(0, 4, 0, 184)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 3
	scroll.ScrollBarImageColor3 = C.gold
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.BorderSizePixel = 0
	scroll.Parent = col

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = scroll

	leftScroll = scroll
	return col
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- ASSET ROW (Left Column)
--------------------------------------------------------------------------------

local function getOrCreateAssetRow(parent, index)
	local rowName = "AssetRow_" .. index
	local row = parent:FindFirstChild(rowName)
	if row then return row end

	row = Instance.new("TextButton")
	row.Name = rowName
	row.Size = UDim2.new(1, -4, 0, 30)
	row.BackgroundTransparency = 0
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = false
	row.LayoutOrder = index
	row.Parent = parent
	addCorner(row, UDim.new(0, 8))

	local ownedStroke = Instance.new("UIStroke")
	ownedStroke.Name = "OwnedStroke"
	ownedStroke.Enabled = false
	ownedStroke.Color = C.green
	ownedStroke.Thickness = 1.2
	ownedStroke.Transparency = 1
	ownedStroke.Parent = row

	-- Icon
	makeLabel(row, { Name = "Icon", Text = "?", Font = FONT_REG, Size = 12,
		UDim2Size = UDim2.new(0, 18, 1, 0), Position = UDim2.new(0, 5, 0, 0) })

	-- Name
	makeLabel(row, { Name = "ItemName", Text = "Item", Color = C_WHITE, Font = FONT_REG, Size = 10,
		UDim2Size = UDim2.new(1, -130, 1, 0), Position = UDim2.new(0, 24, 0, 0) })

	-- Qty
	makeLabel(row, { Name = "Qty", Text = "x0", Color = C.gold, Font = FONT_MONO, Size = 10,
		UDim2Size = UDim2.new(0, 35, 1, 0), Position = UDim2.new(1, -100, 0, 0), XAlign = Enum.TextXAlignment.Right })

	-- Price
	makeLabel(row, { Name = "Price", Text = "$0", Color = C_MUTED, Font = FONT_MONO, Size = 10,
		UDim2Size = UDim2.new(0, 60, 1, 0), Position = UDim2.new(1, -60, 0, 0), XAlign = Enum.TextXAlignment.Right })

	-- Arb indicator
	local arbDot = makeLabel(row, { Name = "ArbDot", Text = "!", Font = FONT_REG, Size = 10,
		Color = C_ARB_FLASH, UDim2Size = UDim2.new(0, 14, 1, 0), Position = UDim2.new(1, -4, 0, 0) })
	arbDot.Visible = false

	local idValue = Instance.new("StringValue")
	idValue.Name = "ItemId"
	idValue.Parent = row

	row.MouseButton1Click:Connect(function()
		local id = row:FindFirstChild("ItemId")
		if id and id.Value ~= "" then
			inspectedItem = id.Value
			updateInspector()
			updateLeftColumn()
		end
	end)

	row.MouseEnter:Connect(function()
		local base = rowDefaultColors[row.Name] or row.BackgroundColor3
		local hover = base:Lerp(Color3.new(1, 1, 1), 0.06)
		TweenService:Create(row, TweenInfo.new(0.12), {BackgroundColor3 = hover}):Play()
	end)
	row.MouseLeave:Connect(function()
		local base = rowDefaultColors[row.Name] or row.BackgroundColor3
		TweenService:Create(row, TweenInfo.new(0.12), {BackgroundColor3 = base}):Play()
	end)

	return row
end

local function createOrUpdateSectionLabel(parent: ScrollingFrame, labelName: string, text: string, layoutOrder: number, color: Color3?)
	local section = parent:FindFirstChild(labelName)
	if not section then
		section = Instance.new("TextLabel")
		section.Name = labelName
		section.Size = UDim2.new(1, -4, 0, 20)
		section.BackgroundTransparency = 1
		section.TextColor3 = color or C.gold
		section.TextSize = 11
		section.Font = FONT_BOLD
		section.TextXAlignment = Enum.TextXAlignment.Left
		section.Parent = parent
	end
	section.LayoutOrder = layoutOrder
	section.Text = text
	section.TextColor3 = color or C.gold
	section.Visible = true
	return section
end

local function updateAssetRow(row, itemId, count, cartCount, storageCount)
	local itemInfo = ItemConfig.Items[itemId] or {}
	local isArb = isArbOpportunity(itemId)
	local isOwned = count > 0
	local isSelected = inspectedItem == itemId

	local idValue = row:FindFirstChild("ItemId")
	if idValue then idValue.Value = itemId end

	applyRowVisualState(row, isOwned, isSelected)
	row.Visible = true

	local icon = row:FindFirstChild("Icon")
	if icon then icon.Text = itemInfo.icon or "?" end

	local name = row:FindFirstChild("ItemName")
	if name then name.Text = itemInfo.displayName or itemId end

	local qty = row:FindFirstChild("Qty")
	if qty then
		if count > 0 then
			qty.Text = string.format("x%d", count)
			qty.TextColor3 = C.green
		else
			qty.Text = "x0"
			qty.TextColor3 = C.gold
		end
	end

	local price = row:FindFirstChild("Price")
	if price then price.Text = formatMoney(getLocalPrice(itemId)) end

	local arbDot = row:FindFirstChild("ArbDot")
	if arbDot then arbDot.Visible = isArb end

	row:SetAttribute("CartCount", cartCount or 0)
	row:SetAttribute("StorageCount", storageCount or 0)
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- RIGHT COLUMN - INSPECTOR & TRADING
--------------------------------------------------------------------------------

local itemSparkline = nil

local function wireHoverGrow(btn: TextButton, baseSize: UDim2, basePos: UDim2, growPx: number)
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
			Size = UDim2.new(baseSize.X.Scale, baseSize.X.Offset + growPx, baseSize.Y.Scale, baseSize.Y.Offset + growPx),
			Position = UDim2.new(basePos.X.Scale, basePos.X.Offset - math.floor(growPx / 2), basePos.Y.Scale, basePos.Y.Offset - math.floor(growPx / 2)),
		}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
			Size = baseSize,
			Position = basePos,
		}):Play()
	end)
end

local function createRightColumn(parent)
	local col = Instance.new("Frame")
	col.Name = "RightColumn"
	col.Size = UDim2.new(0.62, -6, 1, 0)
	col.Position = UDim2.new(0.38, 6, 0, 0)
	col.BackgroundColor3 = C.panel
	col.BorderSizePixel = 0
	col.Parent = parent
	addCorner(col, UDim.new(0, 10))
	addStroke(col, C.border, 1.5)

	-- Header
	inspectorHeaderLabel = makeLabel(col, {
		Name = "Header", Text = "TRADING INSPECTOR",
		Color = C.gold, Font = FONT_BOLD, Size = 14,
		UDim2Size = UDim2.new(1, -12, 0, 28),
		Position = UDim2.new(0, 8, 0, 6),
	})

	-- Inspector content area
	local inspector = Instance.new("Frame")
	inspector.Name = "Inspector"
	inspector.Size = UDim2.new(1, -16, 1, -42)
	inspector.Position = UDim2.new(0, 8, 0, 38)
	inspector.BackgroundTransparency = 1
	inspector.Parent = col

	local watermark = makeLabel(inspector, {
		Name = "Watermark", Text = utf8.char(0x1F4C8),
		Color = C_WHITE, Font = FONT_BOLD, Size = 150,
		UDim2Size = UDim2.new(1, 0, 1, 0),
		XAlign = Enum.TextXAlignment.Center,
	})
	watermark.ZIndex = 1
	watermark.TextTransparency = 0.9
	watermark.TextYAlignment = Enum.TextYAlignment.Center

	-- Placeholder text (shown when no item selected)
	local placeholder = makeLabel(inspector, {
		Name = "Placeholder", Text = "Select an item from your order book",
		Color = C_MUTED, Font = FONT_BOLD, Size = 14,
		UDim2Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0.4, 0),
		XAlign = Enum.TextXAlignment.Center,
	})
	placeholder.ZIndex = 2

	-- Item title
	local itemName = makeLabel(inspector, { Name = "ItemName", Text = "", Color = C_WHITE, Font = FONT_BOLD, Size = 22,
		UDim2Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 0) })
	itemName.ZIndex = 2

	-- LOCAL PRICE (big)
	makeLabel(inspector, { Name = "LblLocalPrice", Text = "LOCAL PRICE", Color = C_MUTED, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(0.5, 0, 0, 12), Position = UDim2.new(0, 0, 0, 34) })
	makeLabel(inspector, { Name = "LocalPrice", Text = "$0", Color = C.gold, Font = FONT_MONO, Size = 36,
		UDim2Size = UDim2.new(0.5, 0, 0, 42), Position = UDim2.new(0, 0, 0, 48) })

	-- GLOBAL PRICE (smaller, next to local)
	makeLabel(inspector, { Name = "LblGlobalPrice", Text = "GLOBAL PRICE", Color = C_MUTED, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(0.3, 0, 0, 12), Position = UDim2.new(0.5, 10, 0, 34) })
	makeLabel(inspector, { Name = "GlobalPrice", Text = "$0", Color = C_CYAN, Font = FONT_MONO, Size = 20,
		UDim2Size = UDim2.new(0.3, 0, 0, 24), Position = UDim2.new(0.5, 10, 0, 50) })

	makeLabel(inspector, { Name = "SectorInfo", Text = "", Color = C_MUTED, Font = FONT_MONO, Size = 11,
		UDim2Size = UDim2.new(0.5, 0, 0, 16), Position = UDim2.new(0.5, 10, 0, 76) })

	local spreadPill = Instance.new("Frame")
	spreadPill.Name = "SpreadPill"
	spreadPill.Size = UDim2.new(0, 170, 0, 24)
	spreadPill.Position = UDim2.new(1, -170, 0, 96)
	spreadPill.BackgroundColor3 = C.card
	spreadPill.BorderSizePixel = 0
	spreadPill.Parent = inspector
	addCorner(spreadPill, UDim.new(1, 0))

	makeLabel(spreadPill, {
		Name = "SpreadLabel", Text = "Spread 0.0%",
		Color = C_WHITE, Font = FONT_MONO, Size = 12,
		UDim2Size = UDim2.new(1, 0, 1, 0),
		XAlign = Enum.TextXAlignment.Center,
	})

	-- ARBITRAGE ALERT
	local arbAlert = makeLabel(inspector, {
		Name = "ArbAlert", Text = "ARBITRAGE OPPORTUNITY",
		Color = C_ARB_FLASH, Font = FONT_BOLD, Size = 14,
		UDim2Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 96),
		XAlign = Enum.TextXAlignment.Center,
	})
	arbAlert.Visible = false

	-- Sparkline monitor
	local graphContainer = Instance.new("Frame")
	graphContainer.Name = "GraphContainer"
	graphContainer.Size = UDim2.new(1, 0, 0, 100)
	graphContainer.Position = UDim2.new(0, 0, 0, 122)
	graphContainer.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
	graphContainer.BorderSizePixel = 0
	graphContainer.Parent = inspector
	addCorner(graphContainer, UDim.new(0, 8))
	addStroke(graphContainer, C.border, 1)

	for i = 1, 3 do
		local gridLine = Instance.new("Frame")
		gridLine.Name = "GridLine_" .. i
		gridLine.Size = UDim2.new(1, -12, 0, 1)
		gridLine.Position = UDim2.new(0, 6, i / 4, 0)
		gridLine.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
		gridLine.BackgroundTransparency = 0.8
		gridLine.BorderSizePixel = 0
		gridLine.ZIndex = 1
		gridLine.Parent = graphContainer
	end

	local graphFrame = Instance.new("Frame")
	graphFrame.Name = "GraphFrame"
	graphFrame.Size = UDim2.new(1, -8, 1, -8)
	graphFrame.Position = UDim2.new(0, 4, 0, 4)
	graphFrame.BackgroundTransparency = 1
	graphFrame.BorderSizePixel = 0
	graphFrame.ZIndex = 2
	graphFrame.Parent = graphContainer

	task.spawn(function()
		local spark = SparklineRenderer.new(graphFrame, Vector2.new(512, 120))
		if spark and not spark.disabled then
			itemSparkline = spark
		end
	end)

	-- Position info
	makeLabel(inspector, { Name = "LblPosition", Text = "YOUR POSITION", Color = C.gold, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 228) })
	makeLabel(inspector, { Name = "PosText", Text = "", Color = C_WHITE, Font = FONT_MONO, Size = 12,
		UDim2Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 242) })

	-- ========== TRADING SECTION ==========
	local tradingFrame = Instance.new("Frame")
	tradingFrame.Name = "TradingFrame"
	tradingFrame.Size = UDim2.new(1, 0, 0, 180)
	tradingFrame.Position = UDim2.new(0, 0, 1, -188)
	tradingFrame.BackgroundTransparency = 1
	tradingFrame.Parent = inspector

	makeLabel(tradingFrame, { Name = "TradeState", Text = "CART NOT AT MARKET - TRADING DISABLED", Color = C.red, Font = FONT_BOLD, Size = 10,
		UDim2Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 0), XAlign = Enum.TextXAlignment.Left })
	makeLabel(tradingFrame, { Name = "CartItemQty", Text = "In cart: 0", Color = C_MUTED, Font = FONT_MONO, Size = 10,
		UDim2Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 12), XAlign = Enum.TextXAlignment.Left })

	makeLabel(tradingFrame, { Name = "LblQty", Text = "QUANTITY", Color = C_MUTED, Font = FONT_BOLD, Size = 9,
		UDim2Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 24) })

	local qtyRow = Instance.new("Frame")
	qtyRow.Name = "QtyRow"
	qtyRow.Size = UDim2.new(1, 0, 0, 34)
	qtyRow.Position = UDim2.new(0, 0, 0, 38)
	qtyRow.BackgroundTransparency = 1
	qtyRow.Parent = tradingFrame

	local qtyButtons = {}
	local qtyValues = {1, 10, -1} -- -1 = MAX
	local qtyLabels = {"x1", "x10", "MAX"}

	for i, val in ipairs(qtyValues) do
		local btn = Instance.new("TextButton")
		btn.Name = "Qty_" .. qtyLabels[i]
		btn.Size = UDim2.new(1 / #qtyValues, -4, 1, 0)
		btn.Position = UDim2.new((i-1) / #qtyValues, 2, 0, 0)
		btn.BackgroundColor3 = (val == 1) and C.gold or C.card
		btn.Text = qtyLabels[i]
		btn.TextColor3 = (val == 1) and C.bg or C_WHITE
		btn.TextSize = 13
		btn.Font = FONT_MONO
		btn.AutoButtonColor = false
		btn.Parent = qtyRow
		addCorner(btn, UDim.new(0, 8))
		addStroke(btn, C.border, 1)

		btn.MouseButton1Click:Connect(function()
			selectedQty = val
			for j, ob in ipairs(qtyButtons) do
				ob.BackgroundColor3 = (qtyValues[j] == val) and C.gold or C.card
				ob.TextColor3 = (qtyValues[j] == val) and C.bg or C_WHITE
			end
			updateInspector()
		end)

		table.insert(qtyButtons, btn)
	end

	local guidedHint = makeLabel(tradingFrame, {
		Name = "GuidedHint",
		Text = "",
		Color = C_MUTED,
		Font = FONT_REG,
		Size = 11,
		UDim2Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.new(0, 0, 0, 34),
	})
	guidedHint.Visible = false
	guidedHint.TextWrapped = true

	local guidedActionBtn = Instance.new("TextButton")
	guidedActionBtn.Name = "GuidedActionBtn"
	guidedActionBtn.Size = UDim2.new(1, 0, 0, 42)
	guidedActionBtn.Position = UDim2.new(0, 0, 0, 68)
	guidedActionBtn.BackgroundColor3 = C.gold
	guidedActionBtn.Text = "LOAD STOCK TO CART"
	guidedActionBtn.TextColor3 = C.bg
	guidedActionBtn.TextSize = 14
	guidedActionBtn.Font = FONT_BOLD
	guidedActionBtn.AutoButtonColor = false
	guidedActionBtn.Visible = false
	guidedActionBtn.Parent = tradingFrame
	addCorner(guidedActionBtn, UDim.new(0, 8))
	addStroke(guidedActionBtn, C.border, 1)
	wireHoverGrow(guidedActionBtn, guidedActionBtn.Size, guidedActionBtn.Position, 2)

	guidedActionBtn.MouseButton1Click:Connect(function()
		if not isGuidedTerminalMode() then
			return
		end

		local guidedActionState = tostring(guidedActionBtn:GetAttribute("ActionState") or "none")

		if guidedActionState == "load" then
			LoadMaxFromStorageFunction:InvokeServer()
			task.spawn(fetchData)
			task.wait(0.1)
			syncGuidedRecommendation(true)
			updateInspector()
			updateLeftColumn()
		elseif guidedActionState == "push" then
			PushCartRemote:FireServer()
		elseif guidedActionState == "return" then
			ReturnCartRemote:FireServer()
		elseif guidedActionState == "sell" and inspectedItem then
			local qty = cartInventory[inspectedItem] or 0
			if qty <= 0 then
				return
			end
			guidedActionBtn.Text = "..."
			local sold, _earned = SellFromCartFunction:InvokeServer(inspectedItem, qty)
			if sold and sold > 0 then
				notifyBanner("TARGETED SELL COMPLETE", C.gold, 4.5)
				notifyToast("You sold with control, not a blind dump.", "success", 4)
				notifyToast("You cashed out your best stack first. The terminal gives you more control than quick-sell.", "info", 4.5)
				task.spawn(fetchData)
				task.wait(0.1)
				syncGuidedRecommendation(true)
				updateInspector()
				updateLeftColumn()
			end
			guidedActionBtn.Text = "SELL RECOMMENDED"
		end
	end)

	-- BUY section
	local buyFrame = Instance.new("Frame")
	buyFrame.Name = "BuyFrame"
	buyFrame.Size = UDim2.new(0.48, 0, 0, 110)
	buyFrame.Position = UDim2.new(0, 0, 0, 78)
	buyFrame.BackgroundColor3 = C.card
	buyFrame.BorderSizePixel = 0
	buyFrame.Parent = tradingFrame
	addCorner(buyFrame, UDim.new(0, 8))
	addStroke(buyFrame, C.border, 1)

	makeLabel(buyFrame, { Name = "LblBuy", Text = "BUY", Color = C.green, Font = FONT_BOLD, Size = 11,
		UDim2Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 8, 0, 4) })
	makeLabel(buyFrame, { Name = "BuyQty", Text = "0 items", Color = C_WHITE, Font = FONT_MONO, Size = 12,
		UDim2Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 8, 0, 22) })
	makeLabel(buyFrame, { Name = "BuyCost", Text = "Cost: $0", Color = C_MUTED, Font = FONT_MONO, Size = 11,
		UDim2Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 8, 0, 40) })

	local buyBtn = Instance.new("TextButton")
	buyBtn.Name = "BuyBtn"
	buyBtn.Size = UDim2.new(1, -16, 0, 34)
	buyBtn.Position = UDim2.new(0, 8, 1, -42)
	buyBtn.BackgroundColor3 = C.green
	buyBtn.Text = "BUY"
	buyBtn.TextColor3 = Color3.new(0, 0, 0)
	buyBtn.TextSize = 14
	buyBtn.Font = FONT_BOLD
	buyBtn.AutoButtonColor = false
	buyBtn.Parent = buyFrame
	addCorner(buyBtn, UDim.new(0, 8))
	wireHoverGrow(buyBtn, buyBtn.Size, buyBtn.Position, 2)

	-- SELL section
	local sellFrame = Instance.new("Frame")
	sellFrame.Name = "SellFrame"
	sellFrame.Size = UDim2.new(0.48, 0, 0, 110)
	sellFrame.Position = UDim2.new(0.52, 0, 0, 78)
	sellFrame.BackgroundColor3 = C.card
	sellFrame.BorderSizePixel = 0
	sellFrame.Parent = tradingFrame
	addCorner(sellFrame, UDim.new(0, 8))
	addStroke(sellFrame, C.border, 1)

	makeLabel(sellFrame, { Name = "LblSell", Text = "SELL", Color = C.red, Font = FONT_BOLD, Size = 11,
		UDim2Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 8, 0, 4) })
	makeLabel(sellFrame, { Name = "SellQty", Text = "0 items", Color = C_WHITE, Font = FONT_MONO, Size = 12,
		UDim2Size = UDim2.new(1, -16, 0, 16), Position = UDim2.new(0, 8, 0, 22) })
	makeLabel(sellFrame, { Name = "SellEarn", Text = "Earn: $0", Color = C_MUTED, Font = FONT_MONO, Size = 11,
		UDim2Size = UDim2.new(1, -16, 0, 14), Position = UDim2.new(0, 8, 0, 40) })

	local sellBtn = Instance.new("TextButton")
	sellBtn.Name = "SellBtn"
	sellBtn.Size = UDim2.new(1, -16, 0, 34)
	sellBtn.Position = UDim2.new(0, 8, 1, -42)
	sellBtn.BackgroundColor3 = C.red
	sellBtn.Text = "SELL"
	sellBtn.TextColor3 = C_WHITE
	sellBtn.TextSize = 14
	sellBtn.Font = FONT_BOLD
	sellBtn.AutoButtonColor = false
	sellBtn.Parent = sellFrame
	addCorner(sellBtn, UDim.new(0, 8))
	wireHoverGrow(sellBtn, sellBtn.Size, sellBtn.Position, 2)

	-- Wire BUY button (cart-based)
	buyBtn.MouseButton1Click:Connect(function()
		if not inspectedItem then return end
		if cartState ~= "at_market" then return end
		local qty = getActualBuyQty()
		if qty <= 0 then return end
		buyBtn.Text = "..."
		local bought, _cost = BuyToCartFunction:InvokeServer(inspectedItem, qty)
		buyBtn.Text = "BUY"
		if bought and bought > 0 then
			task.spawn(fetchData)
			task.wait(0.1)
			updateInspector()
			updateLeftColumn()
		end
	end)

	-- Wire SELL button (cart-based)
	sellBtn.MouseButton1Click:Connect(function()
		if not inspectedItem then return end
		if cartState ~= "at_market" then return end
		local qty = getActualSellQty()
		if qty <= 0 then return end
		sellBtn.Text = "..."
		local sold, _earned = SellFromCartFunction:InvokeServer(inspectedItem, qty)
		sellBtn.Text = "SELL"
		if sold and sold > 0 then
			task.spawn(fetchData)
			task.wait(0.1)
			updateInspector()
			updateLeftColumn()
		end
	end)

	local contractsRoot = Instance.new("Frame")
	contractsRoot.Name = "ContractsPanel"
	contractsRoot.Size = UDim2.new(1, -16, 1, -42)
	contractsRoot.Position = UDim2.new(0, 8, 0, 38)
	contractsRoot.BackgroundTransparency = 1
	contractsRoot.Visible = false
	contractsRoot.Parent = col
	contractsPanel = contractsRoot

	local contractsHeader = makeLabel(contractsRoot, {
		Name = "Header",
		Text = "ACTIVE CONTRACTS",
		Color = C.gold,
		Font = FONT_BOLD,
		Size = 14,
		UDim2Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 0),
	})
	contractsHeader.TextXAlignment = Enum.TextXAlignment.Left

	local list = Instance.new("ScrollingFrame")
	list.Name = "ContractsList"
	list.Size = UDim2.new(1, 0, 0.52, -8)
	list.Position = UDim2.new(0, 0, 0, 24)
	list.BackgroundColor3 = C.panel
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = C.gold
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = contractsRoot
	addCorner(list, UDim.new(0, 8))
	addStroke(list, C.border, 1)
	contractsList = list

	local detail = Instance.new("Frame")
	detail.Name = "ContractsDetail"
	detail.Size = UDim2.new(1, 0, 0.48, -20)
	detail.Position = UDim2.new(0, 0, 0.52, 4)
	detail.BackgroundColor3 = C.card
	detail.BorderSizePixel = 0
	detail.Parent = contractsRoot
	addCorner(detail, UDim.new(0, 8))
	addStroke(detail, C.border, 1)

	local detailTitle = makeLabel(detail, {
		Name = "Title",
		Text = "No contract selected",
		Color = C_WHITE,
		Font = FONT_BOLD,
		Size = 14,
		UDim2Size = UDim2.new(1, -10, 0, 22),
		Position = UDim2.new(0, 8, 0, 6),
	})
	detailTitle.TextXAlignment = Enum.TextXAlignment.Left

	local detailBody = makeLabel(detail, {
		Name = "Body",
		Text = "Select a contract from the list.",
		Color = C_MUTED,
		Font = FONT_MONO,
		Size = 11,
		UDim2Size = UDim2.new(1, -10, 1, -66),
		Position = UDim2.new(0, 8, 0, 30),
	})
	detailBody.TextWrapped = true
	detailBody.TextYAlignment = Enum.TextYAlignment.Top

	local modeRow = Instance.new("Frame")
	modeRow.Name = "DeliverModeRow"
	modeRow.Size = UDim2.new(1, -16, 0, 26)
	modeRow.Position = UDim2.new(0, 8, 1, -74)
	modeRow.BackgroundTransparency = 1
	modeRow.Parent = detail

	local modeX10 = Instance.new("TextButton")
	modeX10.Name = "ModeX10"
	modeX10.Size = UDim2.new(0.48, 0, 1, 0)
	modeX10.Position = UDim2.new(0, 0, 0, 0)
	modeX10.BackgroundColor3 = C.card
	modeX10.Text = "DELIVER x10"
	modeX10.TextColor3 = C_WHITE
	modeX10.TextSize = 11
	modeX10.Font = FONT_BOLD
	modeX10.AutoButtonColor = false
	modeX10.Parent = modeRow
	addCorner(modeX10, UDim.new(0, 6))
	addStroke(modeX10, C.border, 1)

	local modeMax = Instance.new("TextButton")
	modeMax.Name = "ModeMax"
	modeMax.Size = UDim2.new(0.48, 0, 1, 0)
	modeMax.Position = UDim2.new(0.52, 0, 0, 0)
	modeMax.BackgroundColor3 = C.gold
	modeMax.Text = "DELIVER MAX"
	modeMax.TextColor3 = C.bg
	modeMax.TextSize = 11
	modeMax.Font = FONT_BOLD
	modeMax.AutoButtonColor = false
	modeMax.Parent = modeRow
	addCorner(modeMax, UDim.new(0, 6))
	addStroke(modeMax, C.border, 1)

	local deliverBtn = Instance.new("TextButton")
	deliverBtn.Name = "DeliverBtn"
	deliverBtn.Size = UDim2.new(1, -16, 0, 34)
	deliverBtn.Position = UDim2.new(0, 8, 1, -42)
	deliverBtn.BackgroundColor3 = Color3.fromRGB(95, 50, 55)
	deliverBtn.Text = "DELIVER"
	deliverBtn.TextColor3 = C_WHITE
	deliverBtn.TextSize = 14
	deliverBtn.Font = FONT_BOLD
	deliverBtn.Active = false
	deliverBtn.AutoButtonColor = false
	deliverBtn.Parent = detail
	addCorner(deliverBtn, UDim.new(0, 8))

	modeX10.MouseButton1Click:Connect(function()
		contractDeliverMode = "X10"
		updateContractsDetail()
	end)

	modeMax.MouseButton1Click:Connect(function()
		contractDeliverMode = "MAX"
		updateContractsDetail()
	end)

	deliverBtn.MouseButton1Click:Connect(function()
		if contractDeliverMode == "X10" then
			deliverSelectedContract(10)
		else
			deliverSelectedContract(nil)
		end
	end)

	contractsDetail = {
		Title = detailTitle,
		Body = detailBody,
		ModeX10 = modeX10,
		ModeMax = modeMax,
		DeliverBtn = deliverBtn,
	}

	inspectorFrame = inspector
	_rightPanel = col
	return col
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- QUANTITY CALCULATION
--------------------------------------------------------------------------------

function getActualBuyQty()
	if not inspectedItem then return 0 end
	if cartState ~= "at_market" then return 0 end
	local price = getLocalPrice(inspectedItem)
	if price <= 0 then return 0 end
	local money = getPlayerMoney()
	local cartSpace = cartCapacity - cartItemCount

	if selectedQty == -1 then
		local afford = math.floor(money / price)
		return math.min(afford, MAX_BUY, cartSpace)
	else
		local afford = math.floor(money / price)
		return math.min(selectedQty, afford, MAX_BUY, cartSpace)
	end
end

function getActualSellQty()
	if not inspectedItem then return 0 end
	if cartState ~= "at_market" then return 0 end
	local owned = cartInventory[inspectedItem] or 0
	if selectedQty == -1 then
		return owned
	else
		return math.min(selectedQty, owned)
	end
end

--------------------------------------------------------------------------------
-- INSPECTOR UPDATE
--------------------------------------------------------------------------------

function updateInspector()
	if not inspectorFrame then return end
	updateTopBarChrome(true)

	local placeholder = inspectorFrame:FindFirstChild("Placeholder")
	local watermark = inspectorFrame:FindFirstChild("Watermark")
	local itemName = inspectorFrame:FindFirstChild("ItemName")
	local localPriceHeader = inspectorFrame:FindFirstChild("LblLocalPrice")
	local localPriceLabel = inspectorFrame:FindFirstChild("LocalPrice")
	local globalPriceHeader = inspectorFrame:FindFirstChild("LblGlobalPrice")
	local globalPriceLabel = inspectorFrame:FindFirstChild("GlobalPrice")
	local sectorInfo = inspectorFrame:FindFirstChild("SectorInfo")
	local arbAlert = inspectorFrame:FindFirstChild("ArbAlert")
	local spreadPill = inspectorFrame:FindFirstChild("SpreadPill")
	local graphContainer = inspectorFrame:FindFirstChild("GraphContainer")
	local positionHeader = inspectorFrame:FindFirstChild("LblPosition")
	local posText = inspectorFrame:FindFirstChild("PosText")
	local tradingFrame = inspectorFrame:FindFirstChild("TradingFrame")
	local guidedMode = isGuidedTerminalMode()
	local sellFocusedMode = isSellFocusedTerminalMode()

	if not inspectedItem then
		if guidedMode and placeholder then
			if storageUsage > 0 or cartItemCount > 0 then
				placeholder.Text = "Pick the highlighted stack and follow the next step below."
			else
				placeholder.Text = "Build stock, then use the terminal to target your best stack first."
			end
		elseif sellFocusedMode and placeholder then
			placeholder.Text = "Pick an owned stack and cash out the best sell window first."
		elseif placeholder then
			placeholder.Text = "Select an item from your order book"
		end
		if placeholder then placeholder.Visible = true end
		if watermark then watermark.Visible = true end
		for _, child in inspectorFrame:GetChildren() do
			if child.Name ~= "Placeholder" and child.Name ~= "Watermark" and child:IsA("GuiObject") then
				child.Visible = false
			end
		end
		return
	end

	-- Show all inspector elements
	if placeholder then placeholder.Visible = false end
	if watermark then watermark.Visible = false end
	for _, child in inspectorFrame:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Placeholder" and child.Name ~= "Watermark" then
			child.Visible = true
		end
	end

	local itemInfo = ItemConfig.Items[inspectedItem] or {}
	local localPrice = getLocalPrice(inspectedItem)
	local globalPrice = getGlobalPrice(inspectedItem)
	local localRate = getLocalRate(inspectedItem)
	local globalRate = getGlobalRate(inspectedItem)
	local sector = getItemSector(inspectedItem)
	local isArb = isArbOpportunity(inspectedItem)
	local ownedInCart = cartInventory[inspectedItem] or 0
	local ownedInStorage = currentStorage[inspectedItem] or 0
	local guidedCount, guidedSource = getGuidedPriorityCount(inspectedItem)
	local offerCopy, offerColor = getGuidedOfferCopy(localRate)

	-- Item name
	if itemName then
		itemName.Text = (itemInfo.icon or "") .. " " .. (itemInfo.displayName or inspectedItem)
	end

	if guidedMode then
		if localPriceHeader then
			localPriceHeader.Text = "ESTIMATED CASH-OUT"
		end
		if localPriceLabel then
			localPriceLabel.Text = formatMoney(localPrice * guidedCount)
			localPriceLabel.TextColor3 = C.gold
			localPriceLabel.Font = FONT_MONO
		end
		if globalPriceHeader then
			globalPriceHeader.Text = "OFFER STRENGTH"
		end
		if globalPriceLabel then
			globalPriceLabel.Text = localRate >= 1.15 and "Strong offer"
				or (localRate <= 0.9 and "Weak offer" or "Decent offer")
			globalPriceLabel.TextColor3 = offerColor
			globalPriceLabel.Font = FONT_BOLD
			globalPriceLabel.TextSize = 18
			globalPriceLabel.TextWrapped = false
		end
		if sectorInfo then
			local ownedText = guidedSource == "cart" and "in cart"
				or (guidedSource == "storage" and "in storage" or "owned")
			sectorInfo.Size = UDim2.new(1, 0, 0, 34)
			sectorInfo.Position = UDim2.new(0, 0, 0, 84)
			sectorInfo.Text = string.format("You own x%d %s. %s", guidedCount, ownedText, offerCopy)
			sectorInfo.TextColor3 = C_WHITE
			sectorInfo.Font = FONT_REG
			sectorInfo.TextWrapped = true
		end
		if spreadPill then
			spreadPill.Visible = false
		end
		if arbAlert then
			arbAlert.Visible = false
		end
		if graphContainer then
			graphContainer.Visible = false
		end
		if positionHeader then
			positionHeader.Visible = false
		end
		if posText then
			posText.Visible = false
		end
	elseif sellFocusedMode then
		if localPriceHeader then
			localPriceHeader.Text = "SELL PRICE"
		end
		if localPriceLabel then
			localPriceLabel.Text = formatMoney(localPrice)
			localPriceLabel.TextColor3 = C.gold
			localPriceLabel.Font = FONT_MONO
			localPriceLabel.TextSize = 36
		end
		if globalPriceHeader then
			globalPriceHeader.Text = "OFFER"
		end
		if globalPriceLabel then
			globalPriceLabel.Text = localRate >= 1.15 and "Strong offer"
				or (localRate <= 0.9 and "Weak offer" or "Decent offer")
			globalPriceLabel.TextColor3 = offerColor
			globalPriceLabel.Font = FONT_BOLD
			globalPriceLabel.TextSize = 20
			globalPriceLabel.TextWrapped = false
		end
		if sectorInfo then
			sectorInfo.Size = UDim2.new(1, 0, 0, 34)
			sectorInfo.Position = UDim2.new(0, 0, 0, 84)
			sectorInfo.Text = string.format(
				"Cart x%d | Storage x%d | Total cash-out %s",
				ownedInCart,
				ownedInStorage,
				formatMoney((ownedInCart + ownedInStorage) * localPrice)
			)
			sectorInfo.TextColor3 = C_WHITE
			sectorInfo.Font = FONT_REG
			sectorInfo.TextWrapped = true
		end
		if spreadPill then
			spreadPill.Visible = false
		end
		if arbAlert then
			arbAlert.Visible = false
		end
		if graphContainer then
			graphContainer.Visible = false
		end
		if positionHeader then
			positionHeader.Visible = true
		end
		if posText then
			posText.Visible = true
			posText.Text = string.format(
				"Best timing matters more than breadth here. Sell stacks first, buy-side tools unlock later."
			)
			posText.Font = FONT_REG
		end
	else
		if localPriceHeader then
			localPriceHeader.Text = "LOCAL PRICE"
		end
		if localPriceLabel then
			localPriceLabel.Text = formatMoney(localPrice)
			localPriceLabel.TextColor3 = C.gold
			localPriceLabel.Font = FONT_MONO
			localPriceLabel.TextSize = 36
		end
		if globalPriceHeader then
			globalPriceHeader.Text = "GLOBAL PRICE"
		end
		if globalPriceLabel then
			globalPriceLabel.Text = formatMoney(globalPrice)
			globalPriceLabel.TextColor3 = C_CYAN
			globalPriceLabel.Font = FONT_MONO
			globalPriceLabel.TextSize = 20
			globalPriceLabel.TextWrapped = false
		end
		if sectorInfo then
			sectorInfo.Size = UDim2.new(0.5, 0, 0, 16)
			sectorInfo.Position = UDim2.new(0.5, 10, 0, 76)
			sectorInfo.Text = string.format("SECTOR: %s | RATE: x%.2f", string.upper(sector), localRate)
			sectorInfo.TextColor3 = localRate >= 1.0 and C.green or C.red
			sectorInfo.Font = FONT_MONO
			sectorInfo.TextWrapped = false
		end

		if spreadPill and spreadPill:IsA("Frame") then
			spreadPill.Visible = true
			local spreadLabel = spreadPill:FindFirstChild("SpreadLabel")
			local spreadPct = 0
			if globalRate ~= 0 then
				spreadPct = ((localRate / globalRate) - 1) * 100
			end
			if spreadPct > 0 then
				spreadPill.BackgroundColor3 = C.red
				if spreadLabel and spreadLabel:IsA("TextLabel") then
					spreadLabel.TextColor3 = C_WHITE
				end
			elseif spreadPct < 0 then
				spreadPill.BackgroundColor3 = C.green
				if spreadLabel and spreadLabel:IsA("TextLabel") then
					spreadLabel.TextColor3 = Color3.new(0, 0, 0)
				end
			else
				spreadPill.BackgroundColor3 = C.card
				if spreadLabel and spreadLabel:IsA("TextLabel") then
					spreadLabel.TextColor3 = C_WHITE
				end
			end
			if spreadLabel and spreadLabel:IsA("TextLabel") then
				spreadLabel.Text = string.format("Spread %+.2f%%", spreadPct)
				spreadLabel.Font = FONT_MONO
			end
		end

		if arbAlert then
			arbAlert.Visible = isArb
			if isArb then
				local deviation = ((getLocalRate(inspectedItem) / getGlobalRate(inspectedItem)) - 1) * 100
				local direction = deviation > 0 and "OVERPRICED" or "UNDERPRICED"
				arbAlert.Text = string.format("ARBITRAGE: %s by %+.1f%%", direction, deviation)
			end
		end

		if positionHeader then
			positionHeader.Visible = true
		end
		if posText then
			local basePrice = itemInfo.basePrice or 1
			local totalOwned = ownedInCart + ownedInStorage
			local value = totalOwned * localPrice
			posText.Visible = true
			posText.Text = string.format("Cart: %d  |  Storage: %d  |  Value: %s  |  Base: %s",
				ownedInCart, ownedInStorage, formatMoney(value), formatMoney(basePrice))
			posText.Font = FONT_MONO
		end

		if graphContainer then
			graphContainer.Visible = true
		end

		local history = itemHistories[inspectedItem]
		if itemSparkline and history and #history >= 2 then
			itemSparkline:Update(history, C.green, C.red)
		end
	end

	if tradingFrame then
		local isAtMarket = (cartState == "at_market")
		local inCart = ownedInCart
		local buyQty = isAtMarket and getActualBuyQty() or 0
		local sellQty = isAtMarket and getActualSellQty() or 0
		local buyCost = buyQty * localPrice
		local sellEarn = sellQty * localPrice

		local tradeStateLabel = tradingFrame:FindFirstChild("TradeState")
		local cartItemQtyLabel = tradingFrame:FindFirstChild("CartItemQty")
		local qtyLabel = tradingFrame:FindFirstChild("LblQty")
		local qtyRow = tradingFrame:FindFirstChild("QtyRow")
		local guidedHint = tradingFrame:FindFirstChild("GuidedHint")
		local guidedActionBtn = tradingFrame:FindFirstChild("GuidedActionBtn")
		local buyFrame = tradingFrame:FindFirstChild("BuyFrame")
		local buyQtyLabel = buyFrame and buyFrame:FindFirstChild("BuyQty")
		local buyCostLabel = buyFrame and buyFrame:FindFirstChild("BuyCost")
		local buyBtn = buyFrame and buyFrame:FindFirstChild("BuyBtn")
		local sellFrame = tradingFrame:FindFirstChild("SellFrame")
		local sellQtyLabel = sellFrame and sellFrame:FindFirstChild("SellQty")
		local sellEarnLabel = sellFrame and sellFrame:FindFirstChild("SellEarn")
		local sellBtn = sellFrame and sellFrame:FindFirstChild("SellBtn")

		if guidedMode then
			local actionState = "none"
			local actionText = "BUILD STOCK FIRST"
			local actionHint = "Build stock to get a recommendation."
			local actionColor = Color3.fromRGB(95, 50, 55)
			local actionEnabled = false

			if cartState == "rolling_to_market" then
				actionState = "wait"
				actionText = "CART EN ROUTE..."
				actionHint = "Wait for the cart to arrive, then cash out the highlighted winner."
			elseif cartState == "rolling_to_plot" then
				actionState = "wait"
				actionText = "RETURNING TO PLOT..."
				actionHint = "Wait for the cart to return so you can load more stock."
			elseif cartState == "at_market" and (cartInventory[inspectedItem] or 0) > 0 then
				actionState = "sell"
				actionText = "SELL RECOMMENDED"
				actionHint = "Cash out the highlighted winner first."
				actionColor = C.red
				actionEnabled = true
			elseif cartState == "at_market" then
				actionState = "return"
				actionText = "RETURN CART"
				actionHint = "No sellable stock left in cart. Return for another load."
				actionColor = C.gold
				actionEnabled = true
			elseif cartState == "idle" and cartItemCount > 0 then
				actionState = "push"
				actionText = "SEND CART TO MARKET"
				actionHint = "Your best stack is packed. Send the cart to market to trade it."
				actionColor = C.gold
				actionEnabled = true
			elseif storageUsage > 0 then
				actionState = "load"
				actionText = "LOAD STOCK TO CART"
				actionHint = "Load your storage into the cart so the terminal can trade it."
				actionColor = C.gold
				actionEnabled = true
			end

			if tradeStateLabel and tradeStateLabel:IsA("TextLabel") then
				tradeStateLabel.Text = string.upper(getGuidedStatusText())
				tradeStateLabel.TextColor3 = actionEnabled and C.gold or C_MUTED
			end
			if cartItemQtyLabel and cartItemQtyLabel:IsA("TextLabel") then
				cartItemQtyLabel.Text = string.format("Best stack: %s x%d", itemInfo.displayName or inspectedItem, guidedCount)
				cartItemQtyLabel.TextColor3 = C_WHITE
			end
			if qtyLabel then qtyLabel.Visible = false end
			if qtyRow then qtyRow.Visible = false end
			if buyFrame then buyFrame.Visible = false end
			if sellFrame then sellFrame.Visible = false end
			if guidedHint then
				guidedHint.Visible = true
				guidedHint.Text = actionHint
			end
			if guidedActionBtn and guidedActionBtn:IsA("TextButton") then
				guidedActionBtn.Visible = true
				guidedActionBtn:SetAttribute("ActionState", actionState)
				guidedActionBtn.Active = actionEnabled
				guidedActionBtn.AutoButtonColor = actionEnabled
				guidedActionBtn.BackgroundColor3 = actionEnabled and actionColor or Color3.fromRGB(70, 55, 75)
				guidedActionBtn.TextColor3 = actionState == "sell" and C_WHITE or C.bg
				if not actionEnabled then
					guidedActionBtn.TextColor3 = C_WHITE
				end
				guidedActionBtn.Text = actionText
			end
		elseif sellFocusedMode then
			if tradeStateLabel and tradeStateLabel:IsA("TextLabel") then
				if isAtMarket then
					tradeStateLabel.Text = "CART AT MARKET - READY TO SELL"
					tradeStateLabel.TextColor3 = C.green
				elseif cartState == "rolling_to_market" then
					tradeStateLabel.Text = "CART EN ROUTE TO MARKET..."
					tradeStateLabel.TextColor3 = C.gold
				else
					tradeStateLabel.Text = "SEND CART TO MARKET TO SELL"
					tradeStateLabel.TextColor3 = C.red
				end
			end

			if cartItemQtyLabel and cartItemQtyLabel:IsA("TextLabel") then
				cartItemQtyLabel.Text = string.format("Ready in cart: %d", inCart)
				cartItemQtyLabel.TextColor3 = C_MUTED
			end

			if qtyLabel then qtyLabel.Visible = true end
			if qtyRow then qtyRow.Visible = true end
			if buyFrame then buyFrame.Visible = false end
			if sellFrame then sellFrame.Visible = true end
			if guidedHint then
				guidedHint.Visible = true
				guidedHint.Text = "Cash out winners first. Buy-side tools unlock after synergies."
			end
			if guidedActionBtn then guidedActionBtn.Visible = false end

			if sellQtyLabel then sellQtyLabel.Text = sellQty .. " items" end
			if sellEarnLabel then sellEarnLabel.Text = "Earn: " .. formatMoney(sellEarn) end

			local canSell = isAtMarket and sellQty > 0
			if sellBtn and sellBtn:IsA("TextButton") then
				sellBtn.Active = canSell
				sellBtn.AutoButtonColor = canSell
				sellBtn.BackgroundColor3 = canSell and C.red or Color3.fromRGB(95, 50, 55)
				sellBtn.Text = canSell and "SELL" or "SELL (UNAVAILABLE)"
				sellBtn.TextColor3 = C_WHITE
			end
		else
			if tradeStateLabel and tradeStateLabel:IsA("TextLabel") then
				if isAtMarket then
					tradeStateLabel.Text = "CART AT MARKET - TRADING ENABLED"
					tradeStateLabel.TextColor3 = C.green
				else
					tradeStateLabel.Text = "CART NOT AT MARKET - TRADING DISABLED"
					tradeStateLabel.TextColor3 = C.red
				end
			end

			if cartItemQtyLabel and cartItemQtyLabel:IsA("TextLabel") then
				cartItemQtyLabel.Text = string.format("In cart: %d", inCart)
				cartItemQtyLabel.TextColor3 = C_MUTED
			end

			if qtyLabel then qtyLabel.Visible = true end
			if qtyRow then qtyRow.Visible = true end
			if buyFrame then buyFrame.Visible = true end
			if sellFrame then sellFrame.Visible = true end
			if guidedHint then guidedHint.Visible = false end
			if guidedActionBtn then guidedActionBtn.Visible = false end

			if buyQtyLabel then buyQtyLabel.Text = buyQty .. " items" end
			if buyCostLabel then buyCostLabel.Text = "Cost: " .. formatMoney(buyCost) end
			if sellQtyLabel then sellQtyLabel.Text = sellQty .. " items" end
			if sellEarnLabel then sellEarnLabel.Text = "Earn: " .. formatMoney(sellEarn) end

			local canBuy = isAtMarket and buyQty > 0
			local canSell = isAtMarket and sellQty > 0

			if buyBtn and buyBtn:IsA("TextButton") then
				buyBtn.Active = canBuy
				buyBtn.AutoButtonColor = canBuy
				buyBtn.BackgroundColor3 = canBuy and C.green or Color3.fromRGB(60, 90, 65)
				buyBtn.Text = canBuy and "BUY" or "BUY (UNAVAILABLE)"
				buyBtn.TextColor3 = canBuy and Color3.new(0, 0, 0) or C_WHITE
			end

			if sellBtn and sellBtn:IsA("TextButton") then
				sellBtn.Active = canSell
				sellBtn.AutoButtonColor = canSell
				sellBtn.BackgroundColor3 = canSell and C.red or Color3.fromRGB(95, 50, 55)
				sellBtn.Text = canSell and "SELL" or "SELL (UNAVAILABLE)"
				sellBtn.TextColor3 = C_WHITE
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- UPDATE FUNCTIONS
--------------------------------------------------------------------------------

function updateLeftColumn()
	if not leftScroll then return end
	updateTopBarChrome(true)

	-- Hide all existing (Object Pooling)
	for _, child in leftScroll:GetChildren() do
		local isAssetRow = child:IsA("TextButton") and string.match(child.Name, "^AssetRow_")
		local isSectionLabel = child:IsA("TextLabel")
			and (child.Name == "SectionMarket" or child.Name == "SectionOwned" or child.Name == "SectionAll" or child.Name == "SectionEmpty")
		if isAssetRow or isSectionLabel then
			child.Visible = false
		end
	end

	local guidedMode = isGuidedTerminalMode()
	local sellFocusedMode = isSellFocusedTerminalMode()
	if assetSearchBox then
		assetSearchBox.Visible = not sellFocusedMode
	end
	if leftScroll then
		if sellFocusedMode then
			leftScroll.Position = UDim2.new(0, 4, 0, 150)
			leftScroll.Size = UDim2.new(1, -8, 1, -154)
		else
			leftScroll.Position = UDim2.new(0, 4, 0, 184)
			leftScroll.Size = UDim2.new(1, -8, 1, -188)
		end
	end

	if guidedMode then
		local entries = {}
		for itemId, _ in pairs(ItemConfig.Items) do
			local count, source = getGuidedPriorityCount(itemId)
			if count > 0 then
				local displayName = ((ItemConfig.Items[itemId] or {}).displayName) or itemId
				table.insert(entries, {
					id = itemId,
					displayName = displayName,
					cartCount = cartInventory[itemId] or 0,
					storageCount = currentStorage[itemId] or 0,
					ownedCount = getTotalOwned(itemId),
					count = count,
					source = source,
					value = count * getLocalPrice(itemId),
				})
			end
		end

		table.sort(entries, function(a, b)
			if a.value == b.value then
				if a.displayName == b.displayName then
					return a.id < b.id
				end
				return a.displayName < b.displayName
			end
			return a.value > b.value
		end)

		local totalAssetValue = 0
		local rowPoolIndex = 0
		local layoutOrder = 0

		if #entries > 0 then
			layoutOrder += 1
			createOrUpdateSectionLabel(leftScroll, "SectionOwned", "BEST STOCK", layoutOrder, C.gold)
		else
			layoutOrder += 1
			createOrUpdateSectionLabel(leftScroll, "SectionEmpty", "BUILD STOCK TO GET A RECOMMENDATION", layoutOrder, C.gold)
		end

		for _, item in ipairs(entries) do
			rowPoolIndex += 1
			layoutOrder += 1
			local row = getOrCreateAssetRow(leftScroll, rowPoolIndex)
			row.LayoutOrder = layoutOrder
			updateAssetRow(row, item.id, item.count, item.cartCount, item.storageCount)

			local currentPrice = getLocalPrice(item.id)
			local previousPrice = prevLocalPrices[item.id]
			if previousPrice and previousPrice ~= currentPrice then
				flashRow(row, currentPrice > previousPrice)
			end
			prevLocalPrices[item.id] = currentPrice
			totalAssetValue += currentPrice * item.ownedCount
		end

		if stoCapFill then
			local ratio = math.clamp(cartItemCount / math.max(1, cartCapacity), 0, 1)
			TweenService:Create(stoCapFill, TweenInfo.new(0.3), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
			stoCapFill.BackgroundColor3 = ratio >= 1 and C.red or C.gold
		end
		if stoCapText then
			stoCapText.Text = string.format("%d/%d", cartItemCount, cartCapacity)
		end

		if cartStatusBanner then
			local bt = cartStatusBanner:FindFirstChild("BannerText")
			if bt and bt:IsA("TextLabel") then
				if cartState == "at_market" then
					bt.Text = "CART AT MARKET - READY TO SELL"
					bt.TextColor3 = C.green
					cartStatusBanner.BackgroundColor3 = Color3.fromRGB(20, 55, 30)
				elseif cartState == "rolling_to_market" then
					bt.Text = "CART EN ROUTE TO MARKET..."
					bt.TextColor3 = C.gold
					cartStatusBanner.BackgroundColor3 = C_DIM_BG
				elseif cartState == "rolling_to_plot" then
					bt.Text = "CART RETURNING TO PLOT..."
					bt.TextColor3 = C.gold
					cartStatusBanner.BackgroundColor3 = C_DIM_BG
				elseif cartItemCount > 0 then
					bt.Text = "CART LOADED - SEND TO MARKET"
					bt.TextColor3 = C.gold
					cartStatusBanner.BackgroundColor3 = Color3.fromRGB(55, 45, 20)
				else
					bt.Text = "LOAD STOCK TO CART TO TRADE"
					bt.TextColor3 = C.red
					cartStatusBanner.BackgroundColor3 = Color3.fromRGB(55, 20, 25)
				end
			end
		end

		if portfolioLiquidLabel then
			portfolioLiquidLabel.Text = formatMoney(getPlayerMoney())
		end
		if portfolioAssetsLabel then
			portfolioAssetsLabel.Text = formatMoney(totalAssetValue)
		end

		syncGuidedRecommendation(not hasAutoFocusedRecommendedItemThisOpen)
		return
	end

	if sellFocusedMode then
		local market = {}
		local owned = {}
		local totalAssetValue = 0
		local rowPoolIndex = 0
		local layoutOrder = 0

		for itemId, _ in pairs(ItemConfig.Items) do
			local cartCount = cartInventory[itemId] or 0
			local storageCount = currentStorage[itemId] or 0
			local ownedCount = cartCount + storageCount
			if ownedCount > 0 then
				local displayName = ((ItemConfig.Items[itemId] or {}).displayName) or itemId
				local entry = {
					id = itemId,
					displayName = displayName,
					cartCount = cartCount,
					storageCount = storageCount,
					ownedCount = ownedCount,
					value = ownedCount * getLocalPrice(itemId),
				}
				if cartCount > 0 and cartState == "at_market" then
					table.insert(market, entry)
				else
					table.insert(owned, entry)
				end
			end
		end

		table.sort(market, function(a, b)
			if a.value == b.value then
				return a.displayName < b.displayName
			end
			return a.value > b.value
		end)
		table.sort(owned, function(a, b)
			if a.value == b.value then
				return a.displayName < b.displayName
			end
			return a.value > b.value
		end)

		if #market > 0 then
			layoutOrder += 1
			createOrUpdateSectionLabel(leftScroll, "SectionMarket", string.format("READY TO SELL (%d)", #market), layoutOrder, C.green)
		end

		for _, item in ipairs(market) do
			rowPoolIndex += 1
			layoutOrder += 1
			local row = getOrCreateAssetRow(leftScroll, rowPoolIndex)
			row.LayoutOrder = layoutOrder
			updateAssetRow(row, item.id, item.cartCount, item.cartCount, item.storageCount)
			totalAssetValue += getLocalPrice(item.id) * item.ownedCount
		end

		if #owned > 0 then
			layoutOrder += 1
			createOrUpdateSectionLabel(leftScroll, "SectionOwned", string.format("YOUR STOCK (%d)", #owned), layoutOrder, C.gold)
		elseif #market == 0 then
			layoutOrder += 1
			createOrUpdateSectionLabel(leftScroll, "SectionEmpty", "BUILD STOCK TO PICK YOUR NEXT CASH-OUT", layoutOrder, C.gold)
		end

		for _, item in ipairs(owned) do
			rowPoolIndex += 1
			layoutOrder += 1
			local row = getOrCreateAssetRow(leftScroll, rowPoolIndex)
			row.LayoutOrder = layoutOrder
			updateAssetRow(row, item.id, item.ownedCount, item.cartCount, item.storageCount)
			totalAssetValue += getLocalPrice(item.id) * item.ownedCount
		end

		if stoCapFill then
			local ratio = math.clamp(cartItemCount / math.max(1, cartCapacity), 0, 1)
			TweenService:Create(stoCapFill, TweenInfo.new(0.3), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
			stoCapFill.BackgroundColor3 = ratio >= 1 and C.red or C.gold
		end
		if stoCapText then
			stoCapText.Text = string.format("%d/%d", cartItemCount, cartCapacity)
		end

		if cartStatusBanner then
			local bt = cartStatusBanner:FindFirstChild("BannerText")
			if bt and bt:IsA("TextLabel") then
				if cartState == "at_market" then
					bt.Text = "CART AT MARKET - PICK A WINNER"
					bt.TextColor3 = C.green
					cartStatusBanner.BackgroundColor3 = Color3.fromRGB(20, 55, 30)
				elseif cartState == "rolling_to_market" then
					bt.Text = "CART EN ROUTE TO MARKET..."
					bt.TextColor3 = C.gold
					cartStatusBanner.BackgroundColor3 = C_DIM_BG
				elseif cartState == "rolling_to_plot" then
					bt.Text = "CART RETURNING TO PLOT..."
					bt.TextColor3 = C.gold
					cartStatusBanner.BackgroundColor3 = C_DIM_BG
				elseif cartItemCount > 0 then
					bt.Text = "CART LOADED - SEND IT OUT"
					bt.TextColor3 = C.gold
					cartStatusBanner.BackgroundColor3 = Color3.fromRGB(55, 45, 20)
				else
					bt.Text = "BUILD STOCK TO PLAN THE NEXT SELL"
					bt.TextColor3 = C.red
					cartStatusBanner.BackgroundColor3 = Color3.fromRGB(55, 20, 25)
				end
			end
		end

		if portfolioLiquidLabel then
			portfolioLiquidLabel.Text = formatMoney(getPlayerMoney())
		end
		if portfolioAssetsLabel then
			portfolioAssetsLabel.Text = formatMoney(totalAssetValue)
		end

		if not inspectedItem and #market > 0 then
			inspectedItem = market[1].id
		elseif not inspectedItem and #owned > 0 then
			inspectedItem = owned[1].id
		end

		return
	end

	local market = {}
	local owned = {}
	local unowned = {}

	-- Build from union of market-known + cart + storage so all owned items are represented.
	local allItemIds = {}
	for itemId, _ in pairs(globalItemRates) do
		allItemIds[itemId] = true
	end
	for itemId, _ in pairs(cartInventory) do
		allItemIds[itemId] = true
	end
	for itemId, _ in pairs(currentStorage) do
		allItemIds[itemId] = true
	end

	for itemId, _ in pairs(allItemIds) do
		local cartCount = cartInventory[itemId] or 0
		local storageCount = currentStorage[itemId] or 0
		local ownedCount = cartCount + storageCount
		local displayName = ((ItemConfig.Items[itemId] or {}).displayName) or itemId
		if matchesAssetSearch(itemId, displayName) then
			local entry = {
				id = itemId,
				displayName = displayName,
				cartCount = cartCount,
				storageCount = storageCount,
				ownedCount = ownedCount,
			}
			if cartCount > 0 and cartState == "at_market" then
				table.insert(market, entry)
			elseif ownedCount > 0 then
				table.insert(owned, entry)
			else
				table.insert(unowned, entry)
			end
		end
	end

	local function alphaSort(a, b)
		if a.displayName == b.displayName then
			return a.id < b.id
		end
		return a.displayName < b.displayName
	end

	table.sort(market, alphaSort)
	table.sort(owned, alphaSort)
	table.sort(unowned, alphaSort)

	local totalAssetValue = 0
	local rowPoolIndex = 0
	local layoutOrder = 0

	if #market > 0 then
		layoutOrder += 1
		createOrUpdateSectionLabel(leftScroll, "SectionMarket", string.format("AT MARKET (%d)", #market), layoutOrder, C.green)
	end

	for _, item in ipairs(market) do
		rowPoolIndex += 1
		layoutOrder += 1
		local row = getOrCreateAssetRow(leftScroll, rowPoolIndex)
		row.LayoutOrder = layoutOrder
		-- Market section shows exactly what can be sold right now (cart quantity).
		updateAssetRow(row, item.id, item.cartCount, item.cartCount, item.storageCount)

		local currentPrice = getLocalPrice(item.id)
		local previousPrice = prevLocalPrices[item.id]
		if previousPrice and previousPrice ~= currentPrice then
			flashRow(row, currentPrice > previousPrice)
		end
		prevLocalPrices[item.id] = currentPrice

		totalAssetValue += currentPrice * item.ownedCount
	end

	if #owned > 0 then
		layoutOrder += 1
		createOrUpdateSectionLabel(leftScroll, "SectionOwned", string.format("OWNED (%d)", #owned), layoutOrder)
	end

	for _, item in ipairs(owned) do
		rowPoolIndex += 1
		layoutOrder += 1
		local row = getOrCreateAssetRow(leftScroll, rowPoolIndex)
		row.LayoutOrder = layoutOrder
		updateAssetRow(row, item.id, item.ownedCount, item.cartCount, item.storageCount)

		local currentPrice = getLocalPrice(item.id)
		local previousPrice = prevLocalPrices[item.id]
		if previousPrice and previousPrice ~= currentPrice then
			flashRow(row, currentPrice > previousPrice)
		end
		prevLocalPrices[item.id] = currentPrice

		totalAssetValue += currentPrice * item.ownedCount
	end

	if #unowned > 0 then
		layoutOrder += 1
		createOrUpdateSectionLabel(leftScroll, "SectionAll", "ALL ITEMS", layoutOrder)
	end

	for _, item in ipairs(unowned) do
		rowPoolIndex += 1
		layoutOrder += 1
		local row = getOrCreateAssetRow(leftScroll, rowPoolIndex)
		row.LayoutOrder = layoutOrder
		updateAssetRow(row, item.id, 0, item.cartCount, item.storageCount)

		local currentPrice = getLocalPrice(item.id)
		local previousPrice = prevLocalPrices[item.id]
		if previousPrice and previousPrice ~= currentPrice then
			flashRow(row, currentPrice > previousPrice)
		end
		prevLocalPrices[item.id] = currentPrice
	end

	if #market == 0 and #owned == 0 and #unowned == 0 then
		layoutOrder += 1
		createOrUpdateSectionLabel(leftScroll, "SectionEmpty", "NO ITEMS MATCH SEARCH", layoutOrder)
	end

	if stoCapFill then
		local ratio = math.clamp(cartItemCount / math.max(1, cartCapacity), 0, 1)
		TweenService:Create(stoCapFill, TweenInfo.new(0.3), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
		stoCapFill.BackgroundColor3 = ratio >= 1 and C.red or C.gold
	end
	if stoCapText then
		stoCapText.Text = string.format("%d/%d", cartItemCount, cartCapacity)
	end

	if cartStatusBanner then
		local bt = cartStatusBanner:FindFirstChild("BannerText")
		if bt and bt:IsA("TextLabel") then
			if cartState == "at_market" then
				bt.Text = "CART AT MARKET - TRADING ENABLED"
				bt.TextColor3 = C.green
				cartStatusBanner.BackgroundColor3 = Color3.fromRGB(20, 55, 30)
			elseif cartState == "rolling_to_market" then
				bt.Text = "CART EN ROUTE TO MARKET..."
				bt.TextColor3 = C.gold
				cartStatusBanner.BackgroundColor3 = C_DIM_BG
			elseif cartState == "rolling_to_plot" then
				bt.Text = "CART RETURNING TO PLOT..."
				bt.TextColor3 = C.gold
				cartStatusBanner.BackgroundColor3 = C_DIM_BG
			else
				bt.Text = "CART AT PLOT - SEND TO TRADE"
				bt.TextColor3 = C.red
				cartStatusBanner.BackgroundColor3 = Color3.fromRGB(55, 20, 25)
			end
		end
	end

	if portfolioLiquidLabel then
		portfolioLiquidLabel.Text = formatMoney(getPlayerMoney())
	end
	if portfolioAssetsLabel then
		portfolioAssetsLabel.Text = formatMoney(totalAssetValue)
	end
end

--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- DATA FETCHING
--------------------------------------------------------------------------------

function fetchData()
	local items, total, cap = GetStorageFunction:InvokeServer()
	currentStorage = decodeItems(items) or {}
	storageUsage = total or 0
	storageCapacity = Player:GetAttribute("StorageCapacity") or cap or 0


	local _prices = GetMarketPricesFunction:InvokeServer()

	parseSectorRates()
	parseGlobalItemRates()
	parseLocalItemRates()
	parseSectorHistories()
end

--------------------------------------------------------------------------------
-- OPEN / CLOSE
--------------------------------------------------------------------------------

local function openUI()
	if not isDetailedMarketUnlocked() then return end
	if isOpen then return end
	isOpen = true
	hasAutoFocusedRecommendedItemThisOpen = false

	task.spawn(fetchData)
	if areContractsUnlocked() then
		task.spawn(fetchContracts)
	end
	task.wait(0.1)

	if isSellFocusedTerminalMode() then
		activeTab = "TRADING"
	end
	if isGuidedTerminalMode() then
		syncGuidedRecommendation(true)
	end

	refreshUnlockState()
	updateLeftColumn()
	updateInspector()
	refreshContractsList()
	setTab(activeTab)
	updateTopBarChrome(true)

	mainFrame.Visible = true
	mainFrame.BackgroundTransparency = 1
	TweenService:Create(mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 0,
	}):Play()

	if isGuidedTerminalMode() and not hasShownIntroToast then
		hasShownIntroToast = true
		notifyToast("Load stock, send your cart, then cash out the best stack first.", "info", 4.5)
	end
end

local function closeUI()
	if not isOpen then return end
	isOpen = false

	TweenService:Create(mainFrame, TweenInfo.new(0.12), {
		BackgroundTransparency = 1,
	}):Play()

	task.wait(0.12)
	mainFrame.Visible = false
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	local content, closeBtn, statusLabel = createContainer()
	createLeftColumn(content)
	createRightColumn(content)
	setTab("TRADING")
	refreshUnlockState()

	closeBtn.MouseButton1Click:Connect(closeUI)
	if tabTradingBtn then
		tabTradingBtn.MouseButton1Click:Connect(function()
			setTab("TRADING")
		end)
	end
	if tabContractsBtn then
		tabContractsBtn.MouseButton1Click:Connect(function()
			if not areContractsUnlocked() then
				return
			end
			setTab("CONTRACTS")
			refreshContractsList()
		end)
	end

	-- EVENT HANDLERS
	StorageUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
		-- Some server emitters may send partial deltas; always pull a full snapshot.
		local ok, freshItems, freshTotal, freshCap = pcall(function()
			return GetStorageFunction:InvokeServer()
		end)
		if ok then
			currentStorage = decodeItems(freshItems) or {}
			storageUsage = freshTotal or 0
			storageCapacity = Player:GetAttribute("StorageCapacity") or freshCap or 0
		else
			items = decodeItems(items)
			currentStorage = items or {}
			storageUsage = total or 0
			storageCapacity = Player:GetAttribute("StorageCapacity") or capacity or 0
		end
		if isOpen then
			syncGuidedRecommendation(false)
			updateLeftColumn()
			if inspectedItem then updateInspector() end
		end
	end)

	-- Cart state updates (real-time)
	CartController.OnChanged(function(state, inventory, capacity, count)
		cartState = state
		cartInventory = inventory
		cartCapacity = capacity
		cartItemCount = count
		if isOpen then
			syncGuidedRecommendation(state == "at_market")
			updateLeftColumn()
			if inspectedItem then updateInspector() end
		end
	end)

	stockMarketFolder:GetAttributeChangedSignal("ItemRates"):Connect(function()
		if isOpen then
			parseGlobalItemRates()
			syncGuidedRecommendation(false)
			updateLeftColumn()
			if inspectedItem then updateInspector() end
		end
	end)

	stockMarketFolder:GetAttributeChangedSignal("LocalItemRates"):Connect(function()
		if isOpen then
			parseLocalItemRates()
			syncGuidedRecommendation(false)
			updateLeftColumn()
			if inspectedItem then updateInspector() end
		end
	end)

	stockMarketFolder:GetAttributeChangedSignal("SectorRates"):Connect(function()
		if isOpen then
			parseSectorRates()
		end
	end)

	stockMarketFolder:GetAttributeChangedSignal("RateName"):Connect(function()
		if not isOpen or not mainFrame then return end
		updateTopBarChrome(true)
	end)

	ContractEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		local action = payload.Action
		if action == "Spawned" and payload.Contract and payload.Contract.InstanceId then
			contractsById[payload.Contract.InstanceId] = payload.Contract
		elseif action == "Updated" and payload.InstanceId then
			local contract = contractsById[payload.InstanceId]
			if contract and payload.NewCurrentAmount then
				contract.CurrentAmount = payload.NewCurrentAmount
			end
		elseif (action == "Completed" or action == "Expired") then
			local id = payload.InstanceId or (payload.Contract and payload.Contract.InstanceId)
			if id then
				contractsById[id] = nil
				if selectedContractId == id then
					selectedContractId = nil
				end
			end
		end

		if isOpen and activeTab == "CONTRACTS" then
			refreshContractsList()
		end
	end)

	-- HUD Button Toggle
	local stockToggle = ReplicatedStorage:FindFirstChild("StockToggleEvent")
	if not stockToggle then
		stockToggle = Instance.new("BindableEvent")
		stockToggle.Name = "StockToggleEvent"
		stockToggle.Parent = ReplicatedStorage
	end
	stockToggle.Event:Connect(function()
		if not isDetailedMarketUnlocked() then
			return
		end
		if isOpen then closeUI() else openUI() end
	end)

	-- ProximityPrompt (market building & player plot terminals)
	local ProximityPromptService = game:GetService("ProximityPromptService")
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player == Player then
			if prompt.Name == "MarketPrompt" or prompt.Name == "HFTTerminalPrompt" then
				if not isDetailedMarketUnlocked() then
					return
				end
				openUI()
			end
		end
	end)

	Player:GetAttributeChangedSignal("DetailedMarketUnlocked"):Connect(function()
		if not isDetailedMarketUnlocked() and isOpen then
			closeUI()
		end
	end)
	Player:GetAttributeChangedSignal("TerminalIntroComplete"):Connect(function()
		refreshUnlockState()
		if isOpen then
			updateTopBarChrome(true)
			updateLeftColumn()
			if inspectedItem then
				updateInspector()
			end
		end
	end)
	Player:GetAttributeChangedSignal("ContractsUnlocked"):Connect(function()
		refreshUnlockState()
	end)
	Player:GetAttributeChangedSignal("SynergyUnlocked"):Connect(function()
		refreshUnlockState()
		if isOpen then
			updateTopBarChrome(true)
			updateLeftColumn()
			if inspectedItem then
				updateInspector()
			end
		end
	end)
	
	-- Blinking status indicator
	task.spawn(function()
		local dot = true
		while true do
			if isOpen then
				updateTopBarChrome(dot)
			end
			if isOpen and activeTab == "CONTRACTS" then
				refreshContractsList()
			end
			dot = not dot
			task.wait(1)
		end
	end)

	-- Arbitrage flash animation
	task.spawn(function()
		while true do
			if isOpen and inspectorFrame then
				local arbAlert = inspectorFrame:FindFirstChild("ArbAlert")
				if arbAlert and arbAlert.Visible then
					TweenService:Create(arbAlert, TweenInfo.new(0.4), {TextTransparency = 0.5}):Play()
					task.wait(0.4)
					TweenService:Create(arbAlert, TweenInfo.new(0.4), {TextTransparency = 0}):Play()
					task.wait(0.4)
				else
					task.wait(0.5)
				end
			else
				task.wait(1)
			end
		end
	end)

	print("HFT Terminal v4.0 initialized - Press M to open")
end

initialize()
