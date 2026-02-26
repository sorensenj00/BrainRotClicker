--[[
	World-space HFT terminal screen animator.
	Renders animated data to ScreenLeft / ScreenMiddle / ScreenRight parts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket")

local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local remoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local storageUpdatedEvent = remoteEvents:WaitForChild("StorageUpdated")
local getStorageFunction = remoteFunctions:WaitForChild("GetStorage")

local shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(shared:WaitForChild("ItemConfig"))

local UPDATE_INTERVAL = 0.25
local TAPE_INTERVAL = 0.6
local MAX_GRAPH_POINTS = 48
local MAX_TAPE_LINES = 9
local MAX_MOVERS = 6
local BOOT_DURATION = 1.5

local itemRates = {}
local localItemRates = {}
local sectorRates = {}
local storageItems = {}
local storageUsage = 0
local storageCapacity = 0

local worldViews = {}
local marketGraphHistory = {}
local tapeFeed = {}
local lastLoggedTerminalCount = -1

local function decodeJson(raw)
	if type(raw) ~= "string" or raw == "" then
		return nil
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok and type(decoded) == "table" then
		return decoded
	end
	return nil
end

local function decodeItems(raw)
	if type(raw) == "table" then
		return raw
	end
	return decodeJson(raw) or {}
end

local function getPlayerCash()
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	return (money and money.Value) or 0
end

local function getItemBasePrice(itemId)
	local itemDef = ItemConfig.Items[itemId]
	return (itemDef and itemDef.basePrice) or 1
end

local function getPortfolioValue()
	local value = 0
	for itemId, count in pairs(storageItems) do
		local rate = localItemRates[itemId] or itemRates[itemId] or 1.0
		value += math.floor(getItemBasePrice(itemId) * rate) * count
	end
	return value
end

local function formatMoney(value)
	local absValue = math.abs(value)
	if absValue >= 1e12 then
		return string.format("$%.2fT", value / 1e12)
	elseif absValue >= 1e9 then
		return string.format("$%.2fB", value / 1e9)
	elseif absValue >= 1e6 then
		return string.format("$%.2fM", value / 1e6)
	elseif absValue >= 1e3 then
		return string.format("$%.1fK", value / 1e3)
	end
	return string.format("$%d", math.floor(value))
end

local function parseMarketData()
	local decodedItemRates = decodeJson(stockMarketFolder:GetAttribute("ItemRates"))
	if decodedItemRates then
		itemRates = decodedItemRates
	end

	local decodedLocalItemRates = decodeJson(stockMarketFolder:GetAttribute("LocalItemRates"))
	if decodedLocalItemRates then
		localItemRates = decodedLocalItemRates
	end

	local decodedSectorRates = decodeJson(stockMarketFolder:GetAttribute("SectorRates"))
	if decodedSectorRates then
		sectorRates = decodedSectorRates
	end
end

local function fetchStorage()
	local ok, items, total, capacity = pcall(function()
		return getStorageFunction:InvokeServer()
	end)
	if not ok then
		return
	end
	storageItems = decodeItems(items)
	storageUsage = total or storageUsage
	storageCapacity = capacity or player:GetAttribute("StorageCapacity") or storageCapacity
end

local function createLabel(parent, name, size, position, textSize, color, font, alignX)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.TextColor3 = color
	label.TextSize = textSize
	label.Font = font
	label.TextXAlignment = alignX or Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

local function ensureSurfaceGui(screenPart)
	local gui = screenPart:FindFirstChild("HFTDisplay")
	if gui and gui:IsA("SurfaceGui") then
		return gui
	end

	gui = Instance.new("SurfaceGui")
	gui.Name = "HFTDisplay"
	gui.Adornee = screenPart
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 35
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Parent = screenPart
	return gui
end

local function clearGui(gui)
	for _, child in ipairs(gui:GetChildren()) do
		child:Destroy()
	end
end

local function createBaseRoot(gui)
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(8, 12, 18)
	root.BorderSizePixel = 0
	root.Parent = gui

	local scanline = Instance.new("Frame")
	scanline.Name = "Scanline"
	scanline.Size = UDim2.fromScale(1, 0.02)
	scanline.BackgroundColor3 = Color3.fromRGB(88, 255, 199)
	scanline.BackgroundTransparency = 0.88
	scanline.BorderSizePixel = 0
	scanline.Parent = root

	local bootOverlay = Instance.new("Frame")
	bootOverlay.Name = "BootOverlay"
	bootOverlay.Size = UDim2.fromScale(1, 1)
	bootOverlay.BackgroundColor3 = Color3.fromRGB(3, 9, 14)
	bootOverlay.BorderSizePixel = 0
	bootOverlay.Parent = root

	local bootText = Instance.new("TextLabel")
	bootText.Name = "BootText"
	bootText.Size = UDim2.fromScale(1, 1)
	bootText.BackgroundTransparency = 1
	bootText.TextColor3 = Color3.fromRGB(111, 255, 195)
	bootText.TextStrokeTransparency = 0.8
	bootText.TextSize = 24
	bootText.Font = Enum.Font.RobotoMono
	bootText.TextXAlignment = Enum.TextXAlignment.Center
	bootText.TextYAlignment = Enum.TextYAlignment.Center
	bootText.Text = "CONNECTING..."
	bootText.Parent = bootOverlay

	return root, scanline, bootOverlay, bootText
end

local function buildLeftView(screenPart)
	local gui = ensureSurfaceGui(screenPart)
	clearGui(gui)
	local root, scanline, bootOverlay, bootText = createBaseRoot(gui)

	createLabel(root, "Header", UDim2.fromScale(1, 0.09), UDim2.fromScale(0, 0), 20, Color3.fromRGB(111, 255, 195), Enum.Font.RobotoMono, Enum.TextXAlignment.Center).Text = "LIVE TAPE"

	local tapeFrame = Instance.new("Frame")
	tapeFrame.Name = "TapeFrame"
	tapeFrame.Size = UDim2.fromScale(1, 0.91)
	tapeFrame.Position = UDim2.fromScale(0, 0.09)
	tapeFrame.BackgroundTransparency = 1
	tapeFrame.Parent = root

	local tapeLines = {}
	for i = 1, MAX_TAPE_LINES do
		local line = createLabel(
			tapeFrame,
			"Line" .. i,
			UDim2.fromScale(0.96, 1 / MAX_TAPE_LINES),
			UDim2.fromScale(0.02, (i - 1) / MAX_TAPE_LINES),
			16,
			Color3.fromRGB(216, 236, 255),
			Enum.Font.RobotoMono
		)
		line.Text = "..."
		table.insert(tapeLines, line)
	end

	return {
		gui = gui,
		part = screenPart,
		scanline = scanline,
		bootOverlay = bootOverlay,
		bootText = bootText,
		tapeLines = tapeLines,
	}
end

local function buildMiddleView(screenPart)
	local gui = ensureSurfaceGui(screenPart)
	clearGui(gui)
	local root, scanline, bootOverlay, bootText = createBaseRoot(gui)

	createLabel(root, "Title", UDim2.fromScale(1, 0.10), UDim2.fromScale(0, 0), 22, Color3.fromRGB(255, 214, 102), Enum.Font.RobotoMono, Enum.TextXAlignment.Center).Text = "HFT TERMINAL // ONLINE"

	local portfolioValue = createLabel(root, "Portfolio", UDim2.fromScale(0.6, 0.08), UDim2.fromScale(0.02, 0.11), 18, Color3.fromRGB(111, 255, 195), Enum.Font.GothamBold)
	local cashValue = createLabel(root, "Cash", UDim2.fromScale(0.6, 0.07), UDim2.fromScale(0.02, 0.19), 16, Color3.fromRGB(190, 225, 255), Enum.Font.Gotham)
	local capValue = createLabel(root, "Cap", UDim2.fromScale(0.96, 0.06), UDim2.fromScale(0.02, 0.26), 14, Color3.fromRGB(255, 214, 102), Enum.Font.RobotoMono)

	local pulse = Instance.new("Frame")
	pulse.Name = "Pulse"
	pulse.Size = UDim2.fromScale(0.11, 0.19)
	pulse.Position = UDim2.fromScale(0.83, 0.11)
	pulse.BackgroundColor3 = Color3.fromRGB(111, 255, 195)
	pulse.BackgroundTransparency = 0.35
	pulse.BorderSizePixel = 0
	pulse.Parent = root
	local pulseCorner = Instance.new("UICorner")
	pulseCorner.CornerRadius = UDim.new(1, 0)
	pulseCorner.Parent = pulse

	local graphFrame = Instance.new("Frame")
	graphFrame.Name = "Graph"
	graphFrame.Size = UDim2.fromScale(0.96, 0.62)
	graphFrame.Position = UDim2.fromScale(0.02, 0.35)
	graphFrame.BackgroundColor3 = Color3.fromRGB(15, 22, 30)
	graphFrame.BorderColor3 = Color3.fromRGB(45, 62, 84)
	graphFrame.Parent = root

	local points = {}
	for i = 1, MAX_GRAPH_POINTS do
		local point = Instance.new("Frame")
		point.Name = "Point" .. i
		point.Size = UDim2.fromOffset(4, 4)
		point.AnchorPoint = Vector2.new(0.5, 0.5)
		point.BackgroundColor3 = Color3.fromRGB(111, 255, 195)
		point.BorderSizePixel = 0
		point.Parent = graphFrame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = point
		points[i] = point
	end

	return {
		gui = gui,
		part = screenPart,
		scanline = scanline,
		bootOverlay = bootOverlay,
		bootText = bootText,
		portfolioValue = portfolioValue,
		cashValue = cashValue,
		capValue = capValue,
		pulse = pulse,
		graphFrame = graphFrame,
		graphPoints = points,
	}
end

local function buildRightView(screenPart)
	local gui = ensureSurfaceGui(screenPart)
	clearGui(gui)
	local root, scanline, bootOverlay, bootText = createBaseRoot(gui)

	createLabel(root, "Header", UDim2.fromScale(1, 0.09), UDim2.fromScale(0, 0), 20, Color3.fromRGB(111, 255, 195), Enum.Font.RobotoMono, Enum.TextXAlignment.Center).Text = "MOVERS / DEPTH"

	local moversFrame = Instance.new("Frame")
	moversFrame.Name = "Movers"
	moversFrame.Size = UDim2.fromScale(1, 0.58)
	moversFrame.Position = UDim2.fromScale(0, 0.09)
	moversFrame.BackgroundTransparency = 1
	moversFrame.Parent = root

	local moverLines = {}
	for i = 1, MAX_MOVERS do
		local line = createLabel(
			moversFrame,
			"Mover" .. i,
			UDim2.fromScale(0.95, 1 / MAX_MOVERS),
			UDim2.fromScale(0.03, (i - 1) / MAX_MOVERS),
			16,
			Color3.fromRGB(216, 236, 255),
			Enum.Font.RobotoMono
		)
		line.Text = "-"
		table.insert(moverLines, line)
	end

	local depthFrame = Instance.new("Frame")
	depthFrame.Name = "Depth"
	depthFrame.Size = UDim2.fromScale(0.94, 0.29)
	depthFrame.Position = UDim2.fromScale(0.03, 0.67)
	depthFrame.BackgroundTransparency = 1
	depthFrame.Parent = root

	local buyBar = Instance.new("Frame")
	buyBar.Name = "BuyBar"
	buyBar.Size = UDim2.fromScale(0.5, 0.35)
	buyBar.Position = UDim2.fromScale(0, 0.10)
	buyBar.BackgroundColor3 = Color3.fromRGB(70, 255, 140)
	buyBar.BorderSizePixel = 0
	buyBar.Parent = depthFrame

	local sellBar = Instance.new("Frame")
	sellBar.Name = "SellBar"
	sellBar.Size = UDim2.fromScale(0.5, 0.35)
	sellBar.Position = UDim2.fromScale(0, 0.55)
	sellBar.BackgroundColor3 = Color3.fromRGB(255, 90, 96)
	sellBar.BorderSizePixel = 0
	sellBar.Parent = depthFrame

	local buyLabel = createLabel(depthFrame, "BuyLbl", UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0.00), 13, Color3.fromRGB(70, 255, 140), Enum.Font.RobotoMono)
	buyLabel.Text = "BUY PRESSURE"
	local sellLabel = createLabel(depthFrame, "SellLbl", UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0.45), 13, Color3.fromRGB(255, 90, 96), Enum.Font.RobotoMono)
	sellLabel.Text = "SELL PRESSURE"

	return {
		gui = gui,
		part = screenPart,
		scanline = scanline,
		bootOverlay = bootOverlay,
		bootText = bootText,
		moverLines = moverLines,
		buyBar = buyBar,
		sellBar = sellBar,
	}
end

local function buildTerminalView(terminalModel)
	local left = terminalModel:FindFirstChild("ScreenLeft", true)
	local middle = terminalModel:FindFirstChild("ScreenMiddle", true)
	local right = terminalModel:FindFirstChild("ScreenRight", true)
	if not (left and middle and right) then
		return nil
	end
	if not (left:IsA("BasePart") and middle:IsA("BasePart") and right:IsA("BasePart")) then
		return nil
	end

	return {
		model = terminalModel,
		left = buildLeftView(left),
		middle = buildMiddleView(middle),
		right = buildRightView(right),
		scanY = 0,
		pulseTime = 0,
		bootStart = os.clock(),
	}
end

local function getAverageSectorRate()
	local sum, count = 0, 0
	for _, rate in pairs(sectorRates) do
		sum += rate
		count += 1
	end
	if count == 0 then
		return 1.0
	end
	return sum / count
end

local function buildTickerMessages()
	local sectors = {}
	for sector, rate in pairs(sectorRates) do
		local delta = (rate - 1.0) * 100
		local sign = delta >= 0 and "+" or ""
		table.insert(sectors, string.format("%s %s%.2f%%", string.upper(sector), sign, delta))
	end
	table.sort(sectors)

	local status = getAverageSectorRate() >= 1 and "RISK-ON" or "RISK-OFF"
	local messages = {
		"HFT LINK ONLINE",
		"MODE " .. status,
		"PORT " .. formatMoney(getPortfolioValue()),
		"CASH " .. formatMoney(getPlayerCash()),
	}
	for _, msg in ipairs(sectors) do
		table.insert(messages, msg)
	end
	return messages
end

local function updateTapeFeed()
	local messages = buildTickerMessages()
	if #messages == 0 then
		return
	end
	table.insert(tapeFeed, 1, messages[math.random(1, #messages)])
	while #tapeFeed > MAX_TAPE_LINES do
		table.remove(tapeFeed)
	end
end

local function getTopMovers()
	local movers = {}
	for itemId, globalRate in pairs(itemRates) do
		local localRate = localItemRates[itemId] or globalRate
		if globalRate ~= 0 then
			local move = (localRate - globalRate) / globalRate
			table.insert(movers, { itemId = itemId, move = move })
		end
	end
	table.sort(movers, function(a, b)
		return math.abs(a.move) > math.abs(b.move)
	end)
	return movers
end

local function updateWorldViews(dt)
	local avgRate = getAverageSectorRate()
	table.insert(marketGraphHistory, avgRate)
	if #marketGraphHistory > MAX_GRAPH_POINTS then
		table.remove(marketGraphHistory, 1)
	end

	local movers = getTopMovers()
	local buyPressure = math.clamp(avgRate, 0.1, 2.0) / 2.0
	local sellPressure = 1 - buyPressure

	for model, view in pairs(worldViews) do
		if not model.Parent then
			worldViews[model] = nil
			continue
		end

		view.scanY += dt * 0.30
		if view.scanY > 1 then
			view.scanY = 0
		end
		view.left.scanline.Position = UDim2.fromScale(0, view.scanY)
		view.middle.scanline.Position = UDim2.fromScale(0, view.scanY)
		view.right.scanline.Position = UDim2.fromScale(0, view.scanY)

		local bootElapsed = os.clock() - view.bootStart
		local bootActive = bootElapsed < BOOT_DURATION
		if bootActive then
			local bootText = (bootElapsed < (BOOT_DURATION * 0.6)) and "CONNECTING..." or "MARKET LINK LIVE"
			view.left.bootOverlay.Visible = true
			view.middle.bootOverlay.Visible = true
			view.right.bootOverlay.Visible = true
			view.left.bootText.Text = bootText
			view.middle.bootText.Text = bootText
			view.right.bootText.Text = bootText
		else
			view.left.bootOverlay.Visible = false
			view.middle.bootOverlay.Visible = false
			view.right.bootOverlay.Visible = false
		end

		for i, line in ipairs(view.left.tapeLines) do
			local text = tapeFeed[i] or "..."
			line.Text = text
			local isDown = string.find(text, "%-") ~= nil
			local isUp = string.find(text, "%+") ~= nil
			line.TextColor3 = isUp and Color3.fromRGB(90, 255, 160) or (isDown and Color3.fromRGB(255, 110, 110) or Color3.fromRGB(216, 236, 255))
		end

		local portfolioValue = getPortfolioValue()
		view.middle.portfolioValue.Text = "PORTFOLIO " .. formatMoney(portfolioValue)
		view.middle.cashValue.Text = "CASH " .. formatMoney(getPlayerCash())
		view.middle.capValue.Text = string.format("STORAGE %d/%d", storageUsage, storageCapacity)

		local graphCount = #marketGraphHistory
		local minRate, maxRate = 9999, -9999
		for _, rate in ipairs(marketGraphHistory) do
			if rate < minRate then minRate = rate end
			if rate > maxRate then maxRate = rate end
		end
		if maxRate - minRate < 0.001 then
			maxRate = minRate + 0.001
		end
		for i = 1, MAX_GRAPH_POINTS do
			local point = view.middle.graphPoints[i]
			if i <= graphCount then
				local normalizedX = (i - 1) / math.max(1, MAX_GRAPH_POINTS - 1)
				local normalizedY = (marketGraphHistory[i] - minRate) / (maxRate - minRate)
				point.Visible = true
				point.Position = UDim2.fromScale(normalizedX, 1 - normalizedY)
				point.BackgroundColor3 = (marketGraphHistory[i] >= 1.0) and Color3.fromRGB(90, 255, 160) or Color3.fromRGB(255, 110, 110)
			else
				point.Visible = false
			end
		end

		view.pulseTime += dt
		local pulseAlpha = (math.sin(view.pulseTime * 4) + 1) * 0.5
		view.middle.pulse.BackgroundTransparency = 0.2 + (pulseAlpha * 0.5)

		for i, line in ipairs(view.right.moverLines) do
			local mover = movers[i]
			if mover then
				local pct = mover.move * 100
				local sign = pct >= 0 and "+" or ""
				line.Text = string.format("%s %s%.2f%%", string.upper(mover.itemId), sign, pct)
				line.TextColor3 = pct >= 0 and Color3.fromRGB(90, 255, 160) or Color3.fromRGB(255, 110, 110)
			else
				line.Text = "-"
				line.TextColor3 = Color3.fromRGB(216, 236, 255)
			end
		end

		view.right.buyBar.Size = UDim2.fromScale(buyPressure, 0.35)
		view.right.sellBar.Size = UDim2.fromScale(sellPressure, 0.35)
	end
end

local function hasTerminalScreens(container)
	return container:FindFirstChild("ScreenLeft", true) ~= nil
		and container:FindFirstChild("ScreenMiddle", true) ~= nil
		and container:FindFirstChild("ScreenRight", true) ~= nil
end

local function isTerminalContainer(instance)
	if not (instance:IsA("Model") or instance:IsA("Folder")) then
		return false
	end
	if instance.Name == "Plot_HFT_Terminal" then
		return hasTerminalScreens(instance)
	end
	return hasTerminalScreens(instance)
end

local function registerTerminal(container)
	if worldViews[container] then
		return
	end
	local built = buildTerminalView(container)
	if built then
		worldViews[container] = built
	end
end

local function getOwnPlot()
	local plotsFolder = Workspace:FindFirstChild("Plots")
	if not plotsFolder then
		return nil
	end
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if plot:GetAttribute("OwnerId") == player.UserId then
			return plot
		end
	end
	return nil
end

local function isDescendantOf(instance, ancestor)
	local cursor = instance
	while cursor do
		if cursor == ancestor then
			return true
		end
		cursor = cursor.Parent
	end
	return false
end

local function tryRegisterFromDescendant(desc)
	local ownPlot = getOwnPlot()
	if ownPlot and not isDescendantOf(desc, ownPlot) then
		return
	end
	local cursor = desc
	while cursor and cursor ~= Workspace do
		if isTerminalContainer(cursor) then
			registerTerminal(cursor)
			return
		end
		cursor = cursor.Parent
	end
end

local function scanPlots()
	local ownPlot = getOwnPlot()
	if not ownPlot then
		return
	end
	for _, inst in ipairs(ownPlot:GetDescendants()) do
		if isTerminalContainer(inst) then
			registerTerminal(inst)
		end
	end
end

Workspace.DescendantAdded:Connect(function(desc)
	tryRegisterFromDescendant(desc)
end)

stockMarketFolder:GetAttributeChangedSignal("ItemRates"):Connect(parseMarketData)
stockMarketFolder:GetAttributeChangedSignal("LocalItemRates"):Connect(parseMarketData)
stockMarketFolder:GetAttributeChangedSignal("SectorRates"):Connect(parseMarketData)

storageUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
	storageItems = decodeItems(items)
	storageUsage = total or storageUsage
	storageCapacity = capacity or player:GetAttribute("StorageCapacity") or storageCapacity
end)

parseMarketData()
fetchStorage()
updateTapeFeed()
scanPlots()

local function printTerminalCount(tag)
	local terminalCount = 0
	for _ in pairs(worldViews) do
		terminalCount += 1
	end
	if terminalCount ~= lastLoggedTerminalCount then
		lastLoggedTerminalCount = terminalCount
		print(string.format("HFTTerminalScreens: %s (%d terminal views)", tag, terminalCount))
	end
end

printTerminalCount("initialized")

task.spawn(function()
	while true do
		scanPlots()
		task.wait(3)
		fetchStorage()
		printTerminalCount("rescan")
	end
end)

task.spawn(function()
	while true do
		task.wait(TAPE_INTERVAL)
		updateTapeFeed()
	end
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < UPDATE_INTERVAL then
		return
	end
	local step = acc
	acc = 0
	updateWorldViews(step)
end)
