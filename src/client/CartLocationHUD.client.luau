--[[
	CartLocationHUD Client Script
	
	Compact HUD in the bottom-left corner showing:
	  • A horizontal track from Market ←→ Your Plot
	  • A cart icon that slides along the track based on state
	  • Cart storage capacity bar
	  • Recall / Send buttons
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")

local CartUpdateEvent = RemoteEvents:WaitForChild("CartUpdate")
local PushCartRemote = RemoteEvents:WaitForChild("PushCart")
local ReturnCartRemote = RemoteEvents:WaitForChild("ReturnCart")
local GetVehicleInfoFunction = RemoteFunctions:WaitForChild("GetVehicleInfo")

-- Shared
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

--------------------------------------------------------------------------------
-- THEME
--------------------------------------------------------------------------------

local C = {
	bg          = Color3.fromRGB(12, 12, 18),
	panel       = Color3.fromRGB(20, 20, 28),
	track       = Color3.fromRGB(35, 35, 48),
	trackLine   = Color3.fromRGB(55, 55, 72),
	border      = Color3.fromRGB(50, 50, 65),
	amber       = Color3.fromRGB(255, 182, 39),
	amberDim    = Color3.fromRGB(180, 130, 30),
	green       = Color3.fromRGB(0, 230, 120),
	greenDim    = Color3.fromRGB(0, 160, 90),
	greenBg     = Color3.fromRGB(12, 40, 28),
	red         = Color3.fromRGB(255, 65, 65),
	redDim      = Color3.fromRGB(180, 45, 45),
	redBg       = Color3.fromRGB(40, 12, 12),
	cyan        = Color3.fromRGB(0, 200, 255),
	white       = Color3.fromRGB(230, 230, 235),
	muted       = Color3.fromRGB(110, 110, 128),
	dimBg       = Color3.fromRGB(28, 28, 38),
	cartIcon    = Color3.fromRGB(255, 200, 60),
	marketDot   = Color3.fromRGB(0, 200, 255),
	plotDot     = Color3.fromRGB(80, 230, 120),
}

local FONT_BOLD = Enum.Font.GothamBold
local FONT_MONO = Enum.Font.RobotoMono
local FONT_REG  = Enum.Font.Gotham

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local cartState = "idle"       -- Current cart state
local cartInventory = {}       -- {[itemId] = count}
local cartCapacity = 200       -- Current cart capacity
local cartItemCount = 0        -- Total items in cart

local cartIconFrame
local trackFrame
local capBarFill, capBarText
local recallBtn, sendBtn
local storageBtn, marketBtn
local statusLabel

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function addCorner(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 5)
	c.Parent = inst
	return c
end

local function addStroke(inst, color, thick)
	local s = Instance.new("UIStroke")
	s.Color = color or C.border
	s.Thickness = thick or 1
	s.Transparency = 0.3
	s.Parent = inst
	return s
end

local function decodeItems(encoded)
	if type(encoded) ~= "table" then return encoded end
	if not ItemConfig or not ItemConfig.SHORT_TO_ID then return encoded end
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

-- Returns 0..1 position along the track (0 = Market, 1 = Plot)
local function getCartTrackPosition(): number
	if cartState == "idle" then
		return 1.0 -- At plot
	elseif cartState == "at_market" or cartState == "selling" then
		return 0.0 -- At market
	elseif cartState == "rolling_to_market" then
		return 1.0 -- Started from plot
	elseif cartState == "rolling_to_plot" then
		return 0.0 -- Started from market
	end
	return 1.0 -- Default: at plot
end

local function getStatusText(): string
	if cartState == "idle" then return "AT PLOT" end
	if cartState == "at_market" or cartState == "selling" then return "AT MARKET" end
	if cartState == "rolling_to_market" then return "→ TO MARKET" end
	if cartState == "rolling_to_plot" then return "← RETURNING" end
	return "UNKNOWN"
end

local function getStatusColor(): Color3
	if cartState == "idle" then return C.plotDot end
	if cartState == "at_market" or cartState == "selling" then return C.marketDot end
	if cartState == "rolling_to_market" or cartState == "rolling_to_plot" then return C.amber end
	return C.muted
end

--------------------------------------------------------------------------------
-- BUILD UI
--------------------------------------------------------------------------------

local function buildHUD()
	local moneyHUD = PlayerGui:WaitForChild("MoneyHUD", 10)
	if not moneyHUD then
		warn("CartLocationHUD: Could not find MoneyHUD")
		return nil
	end
	
	local hudPanel = moneyHUD:WaitForChild("HUDPanel", 10)
	if not hudPanel then
		warn("CartLocationHUD: Could not find HUDPanel")
		return nil
	end

	-- Main container — appended to bottom of MoneyHUD
	local main = Instance.new("Frame")
	main.Name = "CartHUD"
	main.Size = UDim2.new(1, 0, 0, 100)
	main.Position = UDim2.new(0, 0, 1, -110)
	main.BackgroundTransparency = 1
	main.BorderSizePixel = 0
	main.Parent = hudPanel

	-- ═══ TOP: Track area ═══

	-- Labels: Market (left) and Plot (right)
	local marketLabel = Instance.new("TextLabel")
	marketLabel.Name = "MarketLabel"
	marketLabel.Size = UDim2.new(0, 60, 0, 14)
	marketLabel.Position = UDim2.new(0, 0, 0, 0)
	marketLabel.BackgroundTransparency = 1
	marketLabel.Text = "MARKET"
	marketLabel.TextColor3 = C.marketDot
	marketLabel.TextSize = 9
	marketLabel.Font = FONT_BOLD
	marketLabel.TextXAlignment = Enum.TextXAlignment.Left
	marketLabel.Parent = main

	local plotLabel = Instance.new("TextLabel")
	plotLabel.Name = "PlotLabel"
	plotLabel.Size = UDim2.new(0, 60, 0, 14)
	plotLabel.Position = UDim2.new(1, -60, 0, 0)
	plotLabel.BackgroundTransparency = 1
	plotLabel.Text = "YOUR PLOT"
	plotLabel.TextColor3 = C.plotDot
	plotLabel.TextSize = 9
	plotLabel.Font = FONT_BOLD
	plotLabel.TextXAlignment = Enum.TextXAlignment.Right
	plotLabel.Parent = main

	-- Status label (center-ish)
	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -120, 0, 14)
	statusLabel.Position = UDim2.new(0, 60, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "AT PLOT"
	statusLabel.TextColor3 = C.plotDot
	statusLabel.TextSize = 9
	statusLabel.Font = FONT_MONO
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.Parent = main

	-- Track line
	trackFrame = Instance.new("Frame")
	trackFrame.Name = "Track"
	trackFrame.Size = UDim2.new(1, 0, 0, 16)
	trackFrame.Position = UDim2.new(0, 0, 0, 18)
	trackFrame.BackgroundTransparency = 1
	trackFrame.Parent = main

	-- Track background line
	local trackLine = Instance.new("Frame")
	trackLine.Name = "TrackLine"
	trackLine.Size = UDim2.new(1, -16, 0, 3)
	trackLine.Position = UDim2.new(0, 8, 0.5, -1)
	trackLine.BackgroundColor3 = C.trackLine
	trackLine.BorderSizePixel = 0
	trackLine.Parent = trackFrame
	addCorner(trackLine, UDim.new(0, 2))

	-- Market dot (left end of track)
	local marketDot = Instance.new("Frame")
	marketDot.Name = "MarketDot"
	marketDot.Size = UDim2.new(0, 8, 0, 8)
	marketDot.Position = UDim2.new(0, 4, 0.5, -4)
	marketDot.BackgroundColor3 = C.marketDot
	marketDot.BorderSizePixel = 0
	marketDot.Parent = trackFrame
	addCorner(marketDot, UDim.new(1, 0))

	-- Plot dot (right end of track)
	local plotDot = Instance.new("Frame")
	plotDot.Name = "PlotDot"
	plotDot.Size = UDim2.new(0, 8, 0, 8)
	plotDot.Position = UDim2.new(1, -12, 0.5, -4)
	plotDot.BackgroundColor3 = C.plotDot
	plotDot.BorderSizePixel = 0
	plotDot.Parent = trackFrame
	addCorner(plotDot, UDim.new(1, 0))

	-- Cart icon (moves along track)
	cartIconFrame = Instance.new("Frame")
	cartIconFrame.Name = "CartIcon"
	cartIconFrame.Size = UDim2.new(0, 22, 0, 16)
	cartIconFrame.Position = UDim2.new(1, -22, 0, 0) -- Default: at plot
	cartIconFrame.BackgroundColor3 = C.panel
	cartIconFrame.BorderSizePixel = 0
	cartIconFrame.Parent = trackFrame
	addCorner(cartIconFrame, UDim.new(0, 4))
	addStroke(cartIconFrame, C.cartIcon, 1.5)

	local cartEmoji = Instance.new("TextLabel")
	cartEmoji.Name = "Emoji"
	cartEmoji.Size = UDim2.new(1, 0, 1, 0)
	cartEmoji.BackgroundTransparency = 1
	cartEmoji.Text = "🛒"
	cartEmoji.TextSize = 11
	cartEmoji.Font = FONT_REG
	cartEmoji.Parent = cartIconFrame

	-- ═══ MIDDLE: Capacity bar ═══

	local capBarBg = Instance.new("Frame")
	capBarBg.Name = "CapBarBg"
	capBarBg.Size = UDim2.new(1, 0, 0, 14)
	capBarBg.Position = UDim2.new(0, 0, 0, 40)
	capBarBg.BackgroundColor3 = C.dimBg
	capBarBg.BorderSizePixel = 0
	capBarBg.Parent = main
	addCorner(capBarBg, UDim.new(0, 4))

	capBarFill = Instance.new("Frame")
	capBarFill.Name = "Fill"
	capBarFill.Size = UDim2.new(0, 0, 1, 0)
	capBarFill.BackgroundColor3 = C.amber
	capBarFill.BorderSizePixel = 0
	capBarFill.Parent = capBarBg
	addCorner(capBarFill, UDim.new(0, 4))

	capBarText = Instance.new("TextLabel")
	capBarText.Name = "CapText"
	capBarText.Size = UDim2.new(1, 0, 1, 0)
	capBarText.BackgroundTransparency = 1
	capBarText.Text = "0 / 200"
	capBarText.TextColor3 = C.white
	capBarText.TextSize = 9
	capBarText.Font = FONT_MONO
	capBarText.ZIndex = 2
	capBarText.Parent = capBarBg

	-- ═══ BOTTOM: Recall & Send buttons ═══

	local buttonRowTop = Instance.new("Frame")
	buttonRowTop.Name = "ButtonRowTop"
	buttonRowTop.Size = UDim2.new(1, 0, 0, 24)
	buttonRowTop.Position = UDim2.new(0, 0, 0, 60)
	buttonRowTop.BackgroundTransparency = 1
	buttonRowTop.Parent = main

	-- Recall button (top-left)
	recallBtn = Instance.new("TextButton")
	recallBtn.Name = "RecallBtn"
	recallBtn.Size = UDim2.new(0.47, 0, 1, 0)
	recallBtn.Position = UDim2.new(0, 0, 0, 0)
	recallBtn.BackgroundColor3 = C.redBg
	recallBtn.Text = "◀ RECALL"
	recallBtn.TextColor3 = C.red
	recallBtn.TextSize = 10
	recallBtn.Font = FONT_BOLD
	recallBtn.AutoButtonColor = false
	recallBtn.Parent = buttonRowTop
	addCorner(recallBtn, UDim.new(0, 4))
	addStroke(recallBtn, C.redDim, 1)

	-- Send button (top-right)
	sendBtn = Instance.new("TextButton")
	sendBtn.Name = "SendBtn"
	sendBtn.Size = UDim2.new(0.47, 0, 1, 0)
	sendBtn.Position = UDim2.new(0.53, 0, 0, 0)
	sendBtn.BackgroundColor3 = C.greenBg
	sendBtn.Text = "SEND ▶"
	sendBtn.TextColor3 = C.green
	sendBtn.TextSize = 10
	sendBtn.Font = FONT_BOLD
	sendBtn.AutoButtonColor = false
	sendBtn.Parent = buttonRowTop
	addCorner(sendBtn, UDim.new(0, 4))
	addStroke(sendBtn, C.greenDim, 1)

	-- ═══ BOTTOM: Storage & Market buttons ═══
	local buttonRowBottom = Instance.new("Frame")
	buttonRowBottom.Name = "ButtonRowBottom"
	buttonRowBottom.Size = UDim2.new(1, 0, 0, 24)
	buttonRowBottom.Position = UDim2.new(0, 0, 0, 88)
	buttonRowBottom.BackgroundTransparency = 1
	buttonRowBottom.Parent = main

	-- Market button (bottom-left)
	marketBtn = Instance.new("TextButton")
	marketBtn.Name = "MarketBtn"
	marketBtn.Size = UDim2.new(0.47, 0, 1, 0)
	marketBtn.Position = UDim2.new(0, 0, 0, 0)
	marketBtn.BackgroundColor3 = C.dimBg
	marketBtn.Text = "🏛️ MARKET"
	marketBtn.TextColor3 = C.marketDot
	marketBtn.TextSize = 10
	marketBtn.Font = FONT_BOLD
	marketBtn.AutoButtonColor = false
	marketBtn.Parent = buttonRowBottom
	addCorner(marketBtn, UDim.new(0, 4))
	addStroke(marketBtn, C.marketDot, 1)
	
	-- Storage button (bottom-right)
	storageBtn = Instance.new("TextButton")
	storageBtn.Name = "StorageBtn"
	storageBtn.Size = UDim2.new(0.47, 0, 1, 0)
	storageBtn.Position = UDim2.new(0.53, 0, 0, 0)
	storageBtn.BackgroundColor3 = C.dimBg
	storageBtn.Text = "📦 MANAGE"
	storageBtn.TextColor3 = C.amber
	storageBtn.TextSize = 10
	storageBtn.Font = FONT_BOLD
	storageBtn.AutoButtonColor = false
	storageBtn.Parent = buttonRowBottom
	addCorner(storageBtn, UDim.new(0, 4))
	addStroke(storageBtn, C.amberDim, 1)

	return main
end

--------------------------------------------------------------------------------
-- UPDATE UI
--------------------------------------------------------------------------------

local function updateCartIcon()
	if not cartIconFrame or not trackFrame then return end

	local pos = getCartTrackPosition()
	-- Map 0..1 to track X position (with padding for dots)
	-- Track usable area: from 8px to (width - 30px)
	-- Using scale: 0 = left (market), 1 = right (plot)
	local targetX = UDim2.new(pos, -11, 0, 0) -- Center the 22px icon

	TweenService:Create(cartIconFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = targetX,
	}):Play()

	-- Update icon stroke color based on state
	local stroke = cartIconFrame:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke.Color = getStatusColor()
	end
end

local function updateStatus()
	if not statusLabel then return end
	statusLabel.Text = getStatusText()
	statusLabel.TextColor3 = getStatusColor()
end

local function updateCapacityBar()
	if not capBarFill or not capBarText then return end

	local ratio = math.clamp(cartItemCount / math.max(1, cartCapacity), 0, 1)
	TweenService:Create(capBarFill, TweenInfo.new(0.3), {
		Size = UDim2.new(ratio, 0, 1, 0),
	}):Play()

	-- Color: amber when normal, red when full
	capBarFill.BackgroundColor3 = ratio >= 1 and C.red or C.amber
	capBarText.Text = string.format("%d / %d", cartItemCount, cartCapacity)
end

local function updateButtons()
	if not recallBtn or not sendBtn or not storageBtn or not marketBtn then return end

	-- Send and Storage: only available when cart is idle (at plot) 
	local isAtPlot = (cartState == "idle")
	
	sendBtn.BackgroundColor3 = isAtPlot and C.greenBg or C.dimBg
	sendBtn.TextColor3 = isAtPlot and C.green or C.muted
	sendBtn.Active = isAtPlot
	
	storageBtn.BackgroundColor3 = isAtPlot and Color3.fromRGB(40, 30, 10) or C.dimBg
	storageBtn.TextColor3 = isAtPlot and C.amber or C.muted
	storageBtn.Active = isAtPlot

	-- Recall and Market: only available when cart is at_market
	local isAtMarket = (cartState == "at_market")
	
	recallBtn.BackgroundColor3 = isAtMarket and C.redBg or C.dimBg
	recallBtn.TextColor3 = isAtMarket and C.red or C.muted
	recallBtn.Active = isAtMarket
	
	marketBtn.BackgroundColor3 = isAtMarket and Color3.fromRGB(10, 30, 40) or C.dimBg
	marketBtn.TextColor3 = isAtMarket and C.marketDot or C.muted
	marketBtn.Active = isAtMarket
end

local function updateAll()
	updateCartIcon()
	updateStatus()
	updateCapacityBar()
	updateButtons()
end

--------------------------------------------------------------------------------
-- ROLLING ANIMATION
--------------------------------------------------------------------------------

-- Smoothly animate cart icon when rolling
local rollingConnection = nil

local function startRollingAnimation()
	if rollingConnection then rollingConnection:Disconnect() end

	local startTime = tick()
	local startPos = (cartState == "rolling_to_market") and 1.0 or 0.0
	local endPos = (cartState == "rolling_to_market") and 0.0 or 1.0

	-- Estimate travel duration from cart model attributes
	local cartModel = nil
	for _, obj in workspace:GetChildren() do
		if obj.Name == "Cart_" .. Player.Name then
			cartModel = obj
			break
		end
	end

	local duration = 8 -- Default fallback
	if cartModel then
		local d = cartModel:GetAttribute("CartDuration")
		if d and d > 0 then duration = d end
	end

	rollingConnection = game:GetService("RunService").Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.clamp(elapsed / duration, 0, 1)
		local pos = startPos + (endPos - startPos) * alpha

		-- Directly set position for smooth animation
		local targetX = UDim2.new(pos, -11, 0, 0)
		cartIconFrame.Position = targetX

		if alpha >= 1 then
			if rollingConnection then
				rollingConnection:Disconnect()
				rollingConnection = nil
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- INITIALIZE
--------------------------------------------------------------------------------

local function initialize()
	buildHUD()

	-- Initial data fetch
	task.spawn(function()
		local info = GetVehicleInfoFunction:InvokeServer()
		if info then
			cartInventory = decodeItems(info.inventory) or {}
			cartCapacity = Player:GetAttribute("CartCapacity") or info.capacity or 200
			cartItemCount = 0
			for _, c in pairs(cartInventory) do cartItemCount += c end
		end
		updateAll()
	end)

	-- Listen for cart updates
	CartUpdateEvent.OnClientEvent:Connect(function(state, inventory, capacity)
		local prevState = cartState
		cartState = state or "idle"
		cartInventory = decodeItems(inventory) or {}
		cartCapacity = capacity or cartCapacity

		cartItemCount = 0
		for _, c in pairs(cartInventory) do cartItemCount += c end

		-- Start rolling animation if state just changed to rolling
		if (cartState == "rolling_to_market" or cartState == "rolling_to_plot")
			and prevState ~= cartState then
			startRollingAnimation()
		else
			updateCartIcon()
		end

		updateStatus()
		updateCapacityBar()
		updateButtons()
	end)

	-- Also track via model attributes for initial state
	task.spawn(function()
		while true do
			local cartModel = nil
			for _, obj in workspace:GetChildren() do
				if obj.Name == "Cart_" .. Player.Name then
					cartModel = obj
					break
				end
			end
			if cartModel then
				local modelState = cartModel:GetAttribute("CartState")
				if modelState and modelState ~= cartState then
					-- Don't override from server event, just use for init
					if cartState == "idle" and modelState ~= "idle" then
						cartState = modelState
						updateAll()
					end
				end
				break -- Found cart, stop polling
			end
			task.wait(1)
		end
	end)

	-- ═══ ACTIONS ═══
	
	marketBtn.MouseButton1Click:Connect(function()
		if cartState ~= "at_market" then return end
		local exchangeEvent = ReplicatedStorage:FindFirstChild("StockToggleEvent")
		if exchangeEvent then exchangeEvent:Fire() end
	end)

	storageBtn.MouseButton1Click:Connect(function()
		if cartState ~= "idle" then return end
		local storageEvent = ReplicatedStorage:FindFirstChild("StorageToggleEvent")
		if storageEvent then storageEvent:Fire() end
	end)

	sendBtn.MouseButton1Click:Connect(function()
		if cartState ~= "idle" then return end
		sendBtn.Text = "..."
		PushCartRemote:FireServer()
		task.wait(0.3)
		sendBtn.Text = "SEND ▶"
	end)

	recallBtn.MouseButton1Click:Connect(function()
		if cartState ~= "at_market" then return end
		recallBtn.Text = "..."
		ReturnCartRemote:FireServer()
		task.wait(0.3)
		recallBtn.Text = "◀ RECALL"
	end)

	-- Hover effects
	for _, btn in {sendBtn, recallBtn, marketBtn, storageBtn} do
		btn.MouseEnter:Connect(function()
			if btn.TextColor3 ~= C.muted then -- Only if active
				TweenService:Create(btn, TweenInfo.new(0.12), {
					BackgroundTransparency = 0,
				}):Play()
			end
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.12), {
				BackgroundTransparency = 0,
			}):Play()
		end)
	end

	print("✓ CartLocationHUD initialized")
end

initialize()
