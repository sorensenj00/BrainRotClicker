--[[
	StockMarketUI Client Script
	
	DISABLED: Stock market is now displayed on billboards instead of HUD.
	See: StockMarketGraph.client.luau and StockMarketBillboards.server.luau
]]

-- Disabled - billboards now handle stock market display
return

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

-- Player
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Configuration
local CONFIG = {
	COLORS = {
		CRASH = Color3.fromRGB(255, 80, 80),
		NORMAL = Color3.fromRGB(255, 255, 255),
		STONKS = Color3.fromRGB(80, 255, 80),
		["HYPER INFLATION"] = Color3.fromRGB(255, 215, 0),
	},
	SOUNDS = {
		CRASH = "rbxassetid://15656647153",
		HYPER = "rbxassetid://1837756993",
	},
	UPDATE_INTERVAL = 30,
}

-- Wait for StockMarket folder
local stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket", 30)
if not stockMarketFolder then
	warn("StockMarketUI: StockMarket folder not found!")
	return
end

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StockMarketUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Main container (top-right corner, below the leaderboard area)
local container = Instance.new("Frame")
container.Name = "StockMarketContainer"
container.Size = UDim2.new(0, 200, 0, 100)
container.Position = UDim2.new(1, -220, 0, 120) -- Top right, below leaderboard
container.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
container.BackgroundTransparency = 0.2
container.BorderSizePixel = 0
container.Parent = screenGui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 12)
containerCorner.Parent = container

local containerStroke = Instance.new("UIStroke")
containerStroke.Thickness = 2
containerStroke.Color = Color3.fromRGB(60, 60, 80)
containerStroke.Parent = container

-- Header
local header = Instance.new("TextLabel")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 24)
header.Position = UDim2.new(0, 0, 0, 4)
header.BackgroundTransparency = 1
header.Text = "📈 STOCK MARKET"
header.TextColor3 = Color3.fromRGB(200, 200, 220)
header.TextSize = 14
header.Font = Enum.Font.GothamBold
header.Parent = container

-- Rate Display
local rateLabel = Instance.new("TextLabel")
rateLabel.Name = "RateLabel"
rateLabel.Size = UDim2.new(1, 0, 0, 40)
rateLabel.Position = UDim2.new(0, 0, 0, 28)
rateLabel.BackgroundTransparency = 1
rateLabel.Text = "1.0x"
rateLabel.TextColor3 = CONFIG.COLORS.NORMAL
rateLabel.TextSize = 36
rateLabel.Font = Enum.Font.GothamBlack
rateLabel.Parent = container

-- Rate Name
local rateNameLabel = Instance.new("TextLabel")
rateNameLabel.Name = "RateNameLabel"
rateNameLabel.Size = UDim2.new(1, 0, 0, 18)
rateNameLabel.Position = UDim2.new(0, 0, 0, 68)
rateNameLabel.BackgroundTransparency = 1
rateNameLabel.Text = "NORMAL"
rateNameLabel.TextColor3 = Color3.fromRGB(150, 150, 170)
rateNameLabel.TextSize = 12
rateNameLabel.Font = Enum.Font.GothamMedium
rateNameLabel.Parent = container

-- Timer (bottom)
local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "TimerLabel"
timerLabel.Size = UDim2.new(1, 0, 0, 16)
timerLabel.Position = UDim2.new(0, 0, 1, -18)
timerLabel.BackgroundTransparency = 1
timerLabel.Text = "Next: 30s"
timerLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
timerLabel.TextSize = 11
timerLabel.Font = Enum.Font.Gotham
timerLabel.Parent = container

--------------------------------------------------------------------------------
-- SOUND SETUP
--------------------------------------------------------------------------------

local crashSound = Instance.new("Sound")
crashSound.SoundId = CONFIG.SOUNDS.CRASH
crashSound.Volume = 0.7
crashSound.Parent = SoundService

local hyperSound = Instance.new("Sound")
hyperSound.SoundId = CONFIG.SOUNDS.HYPER
hyperSound.Volume = 0.8
hyperSound.Parent = SoundService

--------------------------------------------------------------------------------
-- UPDATE LOGIC
--------------------------------------------------------------------------------

local lastRateName = "NORMAL"

local function updateDisplay()
	local currentRate = stockMarketFolder:GetAttribute("CurrentRate") or 1.0
	local rateName = stockMarketFolder:GetAttribute("RateName") or "NORMAL"
	
	-- Update text
	rateLabel.Text = string.format("%.1fx", currentRate)
	rateNameLabel.Text = rateName
	
	-- Update colors
	local color = CONFIG.COLORS[rateName] or CONFIG.COLORS.NORMAL
	rateLabel.TextColor3 = color
	containerStroke.Color = color
	
	-- Play sounds on rate change
	if rateName ~= lastRateName then
		if rateName == "CRASH" then
			crashSound:Play()
		elseif rateName == "HYPER INFLATION" then
			hyperSound:Play()
		end
		
		-- Animate the rate label
		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		rateLabel.TextSize = 24
		local tween = TweenService:Create(rateLabel, tweenInfo, {TextSize = 36})
		tween:Play()
		
		lastRateName = rateName
	end
end

local function updateTimer()
	local nextUpdate = stockMarketFolder:GetAttribute("NextUpdate") or 0
	local now = os.time()
	local remaining = math.max(0, nextUpdate - now)
	timerLabel.Text = string.format("Next: %ds", remaining)
end

-- Initial update
updateDisplay()

-- Listen for rate changes
stockMarketFolder:GetAttributeChangedSignal("CurrentRate"):Connect(updateDisplay)
stockMarketFolder:GetAttributeChangedSignal("RateName"):Connect(updateDisplay)

-- Timer update loop
RunService.Heartbeat:Connect(function()
	updateTimer()
end)

print("✓ StockMarketUI initialized")
