--[[
	MoneyHUD LocalScript
	
	Displays the player's current money and money per second in a simple HUD.
	Located in the top-left area of the screen.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Player reference
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Wait for shared modules and remotes
local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopConfig"))
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local GetOwnershipRemote = RemoteEvents:WaitForChild("GetOwnership")
local OwnershipChangedEvent = RemoteEvents:WaitForChild("OwnershipChanged")

--------------------------------------------------------------------------------
-- UI CONFIGURATION
--------------------------------------------------------------------------------

local UI_CONFIG = {
	-- Panel positioning and size
	PANEL_WIDTH = 220,
	PANEL_HEIGHT = 225,
	PANEL_MARGIN = 20,
	CORNER_RADIUS = 16,
	
	-- Colors
	BACKGROUND_COLOR = Color3.fromRGB(20, 20, 30),
	STROKE_COLOR = Color3.fromRGB(50, 50, 70),
	MONEY_COLOR = Color3.fromRGB(100, 255, 100),
	MPS_COLOR = Color3.fromRGB(180, 180, 180),
	LABEL_COLOR = Color3.fromRGB(120, 120, 140),
	TANK_BG_COLOR = Color3.fromRGB(40, 40, 50),
	TANK_FILL_COLOR = Color3.fromRGB(100, 200, 100),
	TANK_FULL_COLOR = Color3.fromRGB(255, 100, 100),
	
	-- Animation
	TWEEN_TIME = 0.2,
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function formatMoney(amount: number): string
	if amount >= 1000000000 then
		return string.format("$%.2fB", amount / 1000000000)
	elseif amount >= 1000000 then
		return string.format("$%.2fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("$%.1fK", amount / 1000)
	else
		return "$" .. tostring(math.floor(amount))
	end
end

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
	stroke.Transparency = 0.5
	stroke.Parent = parent
	return stroke
end

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createMoneyHUD(): ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MoneyHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	
	-- Main HUD panel
	local hudPanel = Instance.new("Frame")
	hudPanel.Name = "HUDPanel"
	hudPanel.Size = UDim2.new(0, UI_CONFIG.PANEL_WIDTH, 0, UI_CONFIG.PANEL_HEIGHT)
	hudPanel.Position = UDim2.new(1, -UI_CONFIG.PANEL_WIDTH - UI_CONFIG.PANEL_MARGIN, 0, UI_CONFIG.PANEL_MARGIN)
	hudPanel.BackgroundColor3 = UI_CONFIG.BACKGROUND_COLOR
	hudPanel.BackgroundTransparency = 0.1
	hudPanel.BorderSizePixel = 0
	hudPanel.Parent = screenGui
	addCorner(hudPanel, UI_CONFIG.CORNER_RADIUS)
	addStroke(hudPanel, UI_CONFIG.STROKE_COLOR, 2)
	
	-- Add padding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = hudPanel
	
	-- Money icon and label container
	local moneyContainer = Instance.new("Frame")
	moneyContainer.Name = "MoneyContainer"
	moneyContainer.Size = UDim2.new(1, 0, 0, 32)
	moneyContainer.Position = UDim2.new(0, 0, 0, 0)
	moneyContainer.BackgroundTransparency = 1
	moneyContainer.Parent = hudPanel
	
	-- Money icon
	local moneyIcon = Instance.new("TextLabel")
	moneyIcon.Name = "MoneyIcon"
	moneyIcon.Size = UDim2.new(0, 32, 0, 32)
	moneyIcon.Position = UDim2.new(0, 0, 0, 0)
	moneyIcon.BackgroundTransparency = 1
	moneyIcon.Text = "💰"
	moneyIcon.TextSize = 24
	moneyIcon.Font = Enum.Font.GothamBold
	moneyIcon.Parent = moneyContainer
	
	-- Money value label
	local moneyLabel = Instance.new("TextLabel")
	moneyLabel.Name = "MoneyLabel"
	moneyLabel.Size = UDim2.new(1, -40, 0, 32)
	moneyLabel.Position = UDim2.new(0, 40, 0, 0)
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.Text = "$0"
	moneyLabel.TextColor3 = UI_CONFIG.MONEY_COLOR
	moneyLabel.TextSize = 28
	moneyLabel.Font = Enum.Font.GothamBold
	moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
	moneyLabel.Parent = moneyContainer
	
	-- Money per second (placeholder)
	local mpsLabel = Instance.new("TextLabel")
	mpsLabel.Name = "MPSLabel"
	mpsLabel.Size = UDim2.new(1, 0, 0, 18)
	mpsLabel.Position = UDim2.new(0, 0, 0, 38)
	mpsLabel.BackgroundTransparency = 1
	mpsLabel.Text = "+$0/s" -- Placeholder, not implemented yet
	mpsLabel.TextColor3 = UI_CONFIG.MPS_COLOR
	mpsLabel.TextSize = 14
	mpsLabel.Font = Enum.Font.Gotham
	mpsLabel.TextXAlignment = Enum.TextXAlignment.Left
	mpsLabel.Parent = hudPanel
	
	-- Storage tank container
	local tankContainer = Instance.new("Frame")
	tankContainer.Name = "TankContainer"
	tankContainer.Size = UDim2.new(1, 0, 0, 28)
	tankContainer.Position = UDim2.new(0, 0, 0, 58)
	tankContainer.BackgroundTransparency = 1
	tankContainer.Parent = hudPanel
	
	-- Tank label
	local tankLabel = Instance.new("TextLabel")
	tankLabel.Name = "TankLabel"
	tankLabel.Size = UDim2.new(0, 50, 0, 14)
	tankLabel.Position = UDim2.new(0, 0, 0, 0)
	tankLabel.BackgroundTransparency = 1
	tankLabel.Text = "TANK:"
	tankLabel.TextColor3 = UI_CONFIG.LABEL_COLOR
	tankLabel.TextSize = 10
	tankLabel.Font = Enum.Font.GothamBold
	tankLabel.TextXAlignment = Enum.TextXAlignment.Left
	tankLabel.Parent = tankContainer
	
	-- Tank bar background
	local tankBarBg = Instance.new("Frame")
	tankBarBg.Name = "TankBarBg"
	tankBarBg.Size = UDim2.new(1, 0, 0, 14)
	tankBarBg.Position = UDim2.new(0, 0, 0, 14)
	tankBarBg.BackgroundColor3 = UI_CONFIG.TANK_BG_COLOR
	tankBarBg.BorderSizePixel = 0
	tankBarBg.Parent = tankContainer
	addCorner(tankBarBg, 4)
	
	-- Tank bar fill
	local tankBarFill = Instance.new("Frame")
	tankBarFill.Name = "TankBarFill"
	tankBarFill.Size = UDim2.new(0, 0, 1, 0) -- Start empty
	tankBarFill.Position = UDim2.new(0, 0, 0, 0)
	tankBarFill.BackgroundColor3 = UI_CONFIG.TANK_FILL_COLOR
	tankBarFill.BorderSizePixel = 0
	tankBarFill.Parent = tankBarBg
	addCorner(tankBarFill, 4)
	
	-- Tank amount text (overlay on bar)
	local tankAmountLabel = Instance.new("TextLabel")
	tankAmountLabel.Name = "TankAmount"
	tankAmountLabel.Size = UDim2.new(1, 0, 1, 0)
	tankAmountLabel.Position = UDim2.new(0, 0, 0, 0)
	tankAmountLabel.BackgroundTransparency = 1
	tankAmountLabel.Text = "0 / 500"
	tankAmountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	tankAmountLabel.TextSize = 10
	tankAmountLabel.Font = Enum.Font.GothamBold
	tankAmountLabel.ZIndex = 2
	tankAmountLabel.Parent = tankBarBg
	
	-- Shop button (cart icon) 
	local shopButton = Instance.new("TextButton")
	shopButton.Name = "ShopButton"
	shopButton.Size = UDim2.new(1, 0, 0, 28)
	shopButton.Position = UDim2.new(0, 0, 0, 95)
	shopButton.BackgroundColor3 = Color3.fromRGB(80, 60, 140)
	shopButton.BorderSizePixel = 0
	shopButton.Text = "🛒 Open Shop (B)"
	shopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	shopButton.TextSize = 12
	shopButton.Font = Enum.Font.GothamBold
	shopButton.Parent = hudPanel
	addCorner(shopButton, 6)
	
	-- Brainrots/Inventory button
	local brainrotsButton = Instance.new("TextButton")
	brainrotsButton.Name = "BrainrotsButton"
	brainrotsButton.Size = UDim2.new(1, 0, 0, 28)
	brainrotsButton.Position = UDim2.new(0, 0, 0, 128)
	brainrotsButton.BackgroundColor3 = Color3.fromRGB(140, 80, 160)
	brainrotsButton.BorderSizePixel = 0
	brainrotsButton.Text = "🧠 Brainrots (I)"
	brainrotsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	brainrotsButton.TextSize = 12
	brainrotsButton.Font = Enum.Font.GothamBold
	brainrotsButton.Parent = hudPanel
	addCorner(brainrotsButton, 6)
	
	-- Synergies button
	local synergiesButton = Instance.new("TextButton")
	synergiesButton.Name = "SynergiesButton"
	synergiesButton.Size = UDim2.new(1, 0, 0, 28)
	synergiesButton.Position = UDim2.new(0, 0, 0, 161)
	synergiesButton.BackgroundColor3 = Color3.fromRGB(200, 150, 60)
	synergiesButton.BorderSizePixel = 0
	synergiesButton.Text = "⚡ Synergies (Y)"
	synergiesButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	synergiesButton.TextSize = 12
	synergiesButton.Font = Enum.Font.GothamBold
	synergiesButton.Parent = hudPanel
	addCorner(synergiesButton, 6)
	
	return screenGui
end

--------------------------------------------------------------------------------
-- MONEY TRACKING
--------------------------------------------------------------------------------

local MoneyHUDGui: ScreenGui
local MoneyLabel: TextLabel
local MPSLabel: TextLabel
local TankBarFill: Frame
local TankAmountLabel: TextLabel

local previousMoney: number = 0
local cachedPlot: Instance? = nil

-- Track ownership for MPS calculation
local OwnedCounts: {[string]: number} = {}

--[[
	Calculates the total money per second based on all owned units.
	Formula: Sum of (BaseIncome / CycleTime) * count for each unit
]]
local function calculateMPS(): number
	local totalMPS = 0
	
	for unitName, count in OwnedCounts do
		if count > 0 then
			local config = ShopConfig.GetConfig(unitName)
			if config then
				-- Income per second for this unit type: (BaseIncome / CycleTime) * count
				local incomePerSecond = (config.BaseIncome / config.CycleTime) * count
				totalMPS = totalMPS + incomePerSecond
			end
		end
	end
	
	return totalMPS
end

--[[
	Updates the MPS display label with the calculated value.
]]
local function updateMPSDisplay()
	if not MPSLabel then return end
	
	local mps = calculateMPS()
	
	if mps >= 1000 then
		MPSLabel.Text = string.format("+$%.1fK/s", mps / 1000)
	else
		MPSLabel.Text = string.format("+$%.1f/s", mps)
	end
end

local function updateMoneyDisplay(newMoney: number)
	if not MoneyLabel then return end
	
	local formattedMoney = formatMoney(newMoney)
	MoneyLabel.Text = formattedMoney
	
	-- Animate color flash on money change
	if newMoney > previousMoney then
		-- Money gained - flash bright green
		MoneyLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
		TweenService:Create(MoneyLabel, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
			TextColor3 = UI_CONFIG.MONEY_COLOR
		}):Play()
	elseif newMoney < previousMoney then
		-- Money spent - flash red briefly
		MoneyLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
		TweenService:Create(MoneyLabel, TweenInfo.new(UI_CONFIG.TWEEN_TIME), {
			TextColor3 = UI_CONFIG.MONEY_COLOR
		}):Play()
	end
	
	previousMoney = newMoney
end

--[[
	Updates the tank bar fill and text based on current/max storage.
]]
local function updateTankDisplay(currentStorage: number, maxStorage: number)
	if not TankBarFill or not TankAmountLabel then return end
	
	local fillPercent = math.clamp(currentStorage / maxStorage, 0, 1)
	
	-- Animate the fill bar width
	TweenService:Create(TankBarFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
		Size = UDim2.new(fillPercent, 0, 1, 0)
	}):Play()
	
	-- Update text
	TankAmountLabel.Text = string.format("%d / %d", currentStorage, maxStorage)
	
	-- Change color based on fill level
	local targetColor
	if fillPercent >= 1 then
		targetColor = UI_CONFIG.TANK_FULL_COLOR
	elseif fillPercent >= 0.75 then
		-- Interpolate between fill and full color
		targetColor = UI_CONFIG.TANK_FILL_COLOR:Lerp(UI_CONFIG.TANK_FULL_COLOR, (fillPercent - 0.75) / 0.25)
	else
		targetColor = UI_CONFIG.TANK_FILL_COLOR
	end
	
	TweenService:Create(TankBarFill, TweenInfo.new(0.2), {
		BackgroundColor3 = targetColor
	}):Play()
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("MoneyHUD: Initializing...")
	
	-- Create the HUD
	MoneyHUDGui = createMoneyHUD()
	MoneyHUDGui.Parent = PlayerGui
	
	-- Get references to labels
	local hudPanel = MoneyHUDGui:FindFirstChild("HUDPanel")
	if hudPanel then
		local moneyContainer = hudPanel:FindFirstChild("MoneyContainer")
		if moneyContainer then
			MoneyLabel = moneyContainer:FindFirstChild("MoneyLabel")
		end
		MPSLabel = hudPanel:FindFirstChild("MPSLabel")
		
		-- Get tank bar references
		local tankContainer = hudPanel:FindFirstChild("TankContainer")
		if tankContainer then
			local tankBarBg = tankContainer:FindFirstChild("TankBarBg")
			if tankBarBg then
				TankBarFill = tankBarBg:FindFirstChild("TankBarFill")
				TankAmountLabel = tankBarBg:FindFirstChild("TankAmount")
			end
		end
	end
	
	-- Get initial ownership data from server for MPS calculation
	local ownershipData = GetOwnershipRemote:InvokeServer()
	if ownershipData and ownershipData.units then
		for unitName, data in ownershipData.units do
			OwnedCounts[unitName] = data.count
		end
		updateMPSDisplay()
	end
	
	-- Listen for ownership changes to update MPS
	OwnershipChangedEvent.OnClientEvent:Connect(function(unitName: string, newCount: number)
		OwnedCounts[unitName] = newCount
		updateMPSDisplay()
	end)
	
	-- Wait for leaderstats and connect to money changes
	local leaderstats = Player:WaitForChild("leaderstats", 10)
	if leaderstats then
		local money = leaderstats:WaitForChild("Money", 5)
		if money then
			-- Initial update
			previousMoney = money.Value
			updateMoneyDisplay(money.Value)
			
			-- Listen for changes
			money:GetPropertyChangedSignal("Value"):Connect(function()
				updateMoneyDisplay(money.Value)
			end)
			
			print("MoneyHUD: Connected to money value")
		else
			warn("MoneyHUD: Could not find Money value")
		end
	else
		warn("MoneyHUD: Could not find leaderstats")
	end
	
	-- Poll for plot storage changes via RunService
	local RunService = game:GetService("RunService")
	local PlotsFolder = workspace:WaitForChild("Plots", 10)
	
	if PlotsFolder then
		-- Find player's plot and poll its storage
		RunService.Heartbeat:Connect(function()
			-- Find player's plot (has OwnerId attribute matching our UserId)
			if not cachedPlot then
				for _, plot in PlotsFolder:GetChildren() do
					if plot:GetAttribute("OwnerId") == Player.UserId then
						cachedPlot = plot
						break
					end
				end
			end
			
			if cachedPlot then
				local currentStorage = cachedPlot:GetAttribute("CurrentStorage") or 0
				local maxStorage = cachedPlot:GetAttribute("MaxStorage") or 500
				updateTankDisplay(currentStorage, maxStorage)
			end
		end)
	end
	
	-- Setup shop button click
	local shopHudPanel = MoneyHUDGui:FindFirstChild("HUDPanel")
	if shopHudPanel then
		local shopButton = shopHudPanel:FindFirstChild("ShopButton")
		if shopButton then
			-- Create or get the BindableEvent for shop toggle
			local shopToggleEvent = ReplicatedStorage:FindFirstChild("ShopToggleEvent")
			if not shopToggleEvent then
				shopToggleEvent = Instance.new("BindableEvent")
				shopToggleEvent.Name = "ShopToggleEvent"
				shopToggleEvent.Parent = ReplicatedStorage
			end
			
			shopButton.MouseButton1Click:Connect(function()
				shopToggleEvent:Fire()
			end)
			
			-- Hover effects
			shopButton.MouseEnter:Connect(function()
				TweenService:Create(shopButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(100, 80, 170)
				}):Play()
			end)
			
			shopButton.MouseLeave:Connect(function()
				TweenService:Create(shopButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(80, 60, 140)
				}):Play()
			end)
		end
		
		-- Setup brainrots button click
		local brainrotsButton = shopHudPanel:FindFirstChild("BrainrotsButton")
		if brainrotsButton then
			-- Create or get the BindableEvent for inventory toggle
			local inventoryToggleEvent = ReplicatedStorage:FindFirstChild("InventoryToggleEvent")
			if not inventoryToggleEvent then
				inventoryToggleEvent = Instance.new("BindableEvent")
				inventoryToggleEvent.Name = "InventoryToggleEvent"
				inventoryToggleEvent.Parent = ReplicatedStorage
			end
			
			brainrotsButton.MouseButton1Click:Connect(function()
				inventoryToggleEvent:Fire()
			end)
			
			-- Hover effects
			brainrotsButton.MouseEnter:Connect(function()
				TweenService:Create(brainrotsButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(170, 100, 190)
				}):Play()
			end)
			
			brainrotsButton.MouseLeave:Connect(function()
				TweenService:Create(brainrotsButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(140, 80, 160)
				}):Play()
			end)
		end
		
		-- Setup synergies button click
		local synergiesButton = shopHudPanel:FindFirstChild("SynergiesButton")
		if synergiesButton then
			-- Create or get the BindableEvent for synergy toggle
			local synergyToggleEvent = ReplicatedStorage:FindFirstChild("SynergyToggleEvent")
			if not synergyToggleEvent then
				synergyToggleEvent = Instance.new("BindableEvent")
				synergyToggleEvent.Name = "SynergyToggleEvent"
				synergyToggleEvent.Parent = ReplicatedStorage
			end
			
			synergiesButton.MouseButton1Click:Connect(function()
				synergyToggleEvent:Fire()
			end)
			
			-- Hover effects
			synergiesButton.MouseEnter:Connect(function()
				TweenService:Create(synergiesButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(230, 180, 80)
				}):Play()
			end)
			
			synergiesButton.MouseLeave:Connect(function()
				TweenService:Create(synergiesButton, TweenInfo.new(0.1), {
					BackgroundColor3 = Color3.fromRGB(200, 150, 60)
				}):Play()
			end)
		end
	end
	
	print("MoneyHUD: Ready!")
end

-- Start
initialize()
