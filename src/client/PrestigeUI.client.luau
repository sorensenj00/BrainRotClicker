--[[
	PrestigeUI Client Script
	
	Handles the Golden Meatball Altar UI and Shop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for shared modules
local PrestigeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PrestigeConfig"))

-- Remote Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PrestigeEvent = RemoteEvents:WaitForChild("PrestigeEvent")

-- State
local currentData = {
	totalMeatballs = 0,
	spentMeatballs = 0,
	pendingMeatballs = 0,
	lifetimeEarnings = 0,
	upgrades = {}
}

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createPrestigeUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PrestigeUI"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.Parent = playerGui
	
	-- Main Frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 800, 0, 600)
	mainFrame.Position = UDim2.new(0.5, -400, 0.5, -300)
	mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, 12)
	uiCorner.Parent = mainFrame
	
	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 80)
	header.BackgroundColor3 = Color3.fromRGB(255, 215, 0) -- Gold
	header.BorderSizePixel = 0
	header.Parent = mainFrame
	
	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 12)
	headerCorner.Parent = header
	
	-- Fix bottom corners of header
	local headerCover = Instance.new("Frame")
	headerCover.Size = UDim2.new(1, 0, 0, 20)
	headerCover.Position = UDim2.new(0, 0, 1, -20)
	headerCover.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	headerCover.BorderSizePixel = 0
	headerCover.Parent = header
	
	local title = Instance.new("TextLabel")
	title.Text = "GOLDEN MEATBALL ALTAR"
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 40
	title.TextColor3 = Color3.fromRGB(100, 80, 0)
	title.Size = UDim2.new(1, 0, 1, 0)
	title.BackgroundTransparency = 1
	title.Parent = header
	
	-- Close Button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.FredokaOne
	closeBtn.TextSize = 24
	closeBtn.TextColor3 = Color3.fromRGB(100, 80, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -50, 0.5, -20)
	closeBtn.Parent = header
	
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn
	
	closeBtn.MouseButton1Click:Connect(function()
		screenGui.Enabled = false
	end)
	
	-- Content Container
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -40, 1, -140)
	content.Position = UDim2.new(0, 20, 0, 100)
	content.BackgroundTransparency = 1
	content.Parent = mainFrame
	
	-- Left Panel: Stats & Prestige
	local leftPanel = Instance.new("Frame")
	leftPanel.Name = "LeftPanel"
	leftPanel.Size = UDim2.new(0.4, -10, 1, 0)
	leftPanel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	leftPanel.Parent = content
	
	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0, 8)
	leftCorner.Parent = leftPanel
	
	-- Stats Display
	local statsList = Instance.new("UIListLayout")
	statsList.Padding = UDim.new(0, 10)
	statsList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	statsList.SortOrder = Enum.SortOrder.LayoutOrder
	statsList.Parent = leftPanel
	
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.PaddingBottom = UDim.new(0, 20)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = leftPanel
	
	-- Current Meatballs
	local currentLabel = Instance.new("TextLabel")
	currentLabel.Name = "CurrentLabel"
	currentLabel.Text = "Your Golden Meatballs"
	currentLabel.Font = Enum.Font.GothamBold
	currentLabel.TextSize = 18
	currentLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	currentLabel.Size = UDim2.new(1, 0, 0, 30)
	currentLabel.BackgroundTransparency = 1
	currentLabel.LayoutOrder = 1
	currentLabel.Parent = leftPanel
	
	local meatballCount = Instance.new("TextLabel")
	meatballCount.Name = "MeatballCount"
	meatballCount.Text = "0"
	meatballCount.Font = Enum.Font.FredokaOne
	meatballCount.TextSize = 48
	meatballCount.TextColor3 = Color3.fromRGB(255, 215, 0)
	meatballCount.Size = UDim2.new(1, 0, 0, 60)
	meatballCount.BackgroundTransparency = 1
	meatballCount.LayoutOrder = 2
	meatballCount.Parent = leftPanel
	
	-- Bonus Display
	local bonusLabel = Instance.new("TextLabel")
	bonusLabel.Name = "BonusLabel"
	bonusLabel.Text = "+0% Income Bonus"
	bonusLabel.Font = Enum.Font.GothamBold
	bonusLabel.TextSize = 20
	bonusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	bonusLabel.Size = UDim2.new(1, 0, 0, 30)
	bonusLabel.BackgroundTransparency = 1
	bonusLabel.LayoutOrder = 3
	bonusLabel.Parent = leftPanel
	
	-- Divider
	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, 0, 0, 2)
	divider.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	divider.BorderSizePixel = 0
	divider.LayoutOrder = 4
	divider.Parent = leftPanel
	
	-- Pending Section
	local pendingTitle = Instance.new("TextLabel")
	pendingTitle.Text = "Prestige Now To Gain:"
	pendingTitle.Font = Enum.Font.GothamBold
	pendingTitle.TextSize = 16
	pendingTitle.TextColor3 = Color3.fromRGB(200, 200, 200)
	pendingTitle.Size = UDim2.new(1, 0, 0, 30)
	pendingTitle.BackgroundTransparency = 1
	pendingTitle.LayoutOrder = 5
	pendingTitle.Parent = leftPanel
	
	local pendingCount = Instance.new("TextLabel")
	pendingCount.Name = "PendingCount"
	pendingCount.Text = "+0"
	pendingCount.Font = Enum.Font.FredokaOne
	pendingCount.TextSize = 36
	pendingCount.TextColor3 = Color3.fromRGB(255, 255, 255)
	pendingCount.Size = UDim2.new(1, 0, 0, 50)
	pendingCount.BackgroundTransparency = 1
	pendingCount.LayoutOrder = 6
	pendingCount.Parent = leftPanel
	
	-- Prestige Button
	local prestigeBtn = Instance.new("TextButton")
	prestigeBtn.Name = "PrestigeButton"
	prestigeBtn.Text = "PRESTIGE RESET"
	prestigeBtn.Font = Enum.Font.FredokaOne
	prestigeBtn.TextSize = 24
	prestigeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	prestigeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	prestigeBtn.Size = UDim2.new(1, 0, 0, 60)
	prestigeBtn.LayoutOrder = 7
	prestigeBtn.Parent = leftPanel
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = prestigeBtn
	
	local warningLabel = Instance.new("TextLabel")
	warningLabel.Text = "Resets Money, Units & Upgrades!"
	warningLabel.Font = Enum.Font.Gotham
	warningLabel.TextSize = 12
	warningLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	warningLabel.Size = UDim2.new(1, 0, 0, 20)
	warningLabel.BackgroundTransparency = 1
	warningLabel.LayoutOrder = 8
	warningLabel.Parent = leftPanel
	
	prestigeBtn.MouseButton1Click:Connect(function()
		if currentData.pendingMeatballs >= PrestigeConfig.MINIMUM_PRESTIGE_GAIN then
			PrestigeEvent:FireServer("Prestige")
			screenGui.Enabled = false
		end
	end)
	
	-- Right Panel: Shop
	local rightPanel = Instance.new("ScrollingFrame")
	rightPanel.Name = "ShopPanel"
	rightPanel.Size = UDim2.new(0.6, -10, 1, 0)
	rightPanel.Position = UDim2.new(0.4, 10, 0, 0)
	rightPanel.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	rightPanel.ScrollBarThickness = 6
	rightPanel.Parent = content
	
	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = UDim.new(0, 8)
	rightCorner.Parent = rightPanel
	
	local shopLayout = Instance.new("UIListLayout")
	shopLayout.Padding = UDim.new(0, 10)
	shopLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
	shopLayout.Parent = rightPanel
	
	local shopPadding = Instance.new("UIPadding")
	shopPadding.PaddingTop = UDim.new(0, 10)
	shopPadding.PaddingBottom = UDim.new(0, 10)
	shopPadding.PaddingLeft = UDim.new(0, 10)
	shopPadding.PaddingRight = UDim.new(0, 10)
	shopPadding.Parent = rightPanel
	
	return screenGui
end

local function createShopItem(parent, item, isOwned, isLocked)
	local frame = Instance.new("Frame")
	frame.Name = item.Id
	frame.Size = UDim2.new(1, 0, 0, 80)
	frame.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	frame.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame
	
	-- Name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Text = item.Name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Size = UDim2.new(0.6, 0, 0, 25)
	nameLabel.Position = UDim2.new(0, 10, 0, 5)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.BackgroundTransparency = 1
	nameLabel.Parent = frame
	
	-- Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Text = item.Description
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 12
	descLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	descLabel.Size = UDim2.new(0.6, 0, 0, 40)
	descLabel.Position = UDim2.new(0, 10, 0, 30)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextWrapped = true
	descLabel.BackgroundTransparency = 1
	descLabel.Parent = frame
	
	-- Buy Button
	local buyBtn = Instance.new("TextButton")
	buyBtn.Size = UDim2.new(0.35, 0, 0.8, 0)
	buyBtn.Position = UDim2.new(0.63, 0, 0.1, 0)
	buyBtn.Font = Enum.Font.GothamBold
	buyBtn.TextSize = 14
	buyBtn.Parent = frame
	
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = buyBtn
	
	if isOwned then
		buyBtn.Text = "OWNED"
		buyBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		buyBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
		buyBtn.AutoButtonColor = false
	elseif isLocked then
		buyBtn.Text = "LOCKED\nNeed " .. item.UnlockAt .. " Meatballs"
		buyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		buyBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
		buyBtn.AutoButtonColor = false
	else
		buyBtn.Text = "BUY\n" .. item.Price .. " Meatballs"
		buyBtn.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
		buyBtn.TextColor3 = Color3.fromRGB(50, 40, 0)
		
		buyBtn.MouseButton1Click:Connect(function()
			PrestigeEvent:FireServer("PurchaseUpgrade", item.Id)
		end)
	end
end

local function updateUI(gui)
	local leftPanel = gui.MainFrame.Content.LeftPanel
	local shopPanel = gui.MainFrame.Content.ShopPanel
	
	-- Update Stats
	leftPanel.MeatballCount.Text = tostring(currentData.totalMeatballs)
	
	-- Calculate bonus (unspent * 2%)
	local unspent = currentData.totalMeatballs - currentData.spentMeatballs
	local bonus = math.floor(unspent * PrestigeConfig.MEATBALL_BONUS_RATE * 100)
	leftPanel.BonusLabel.Text = "+" .. bonus .. "% Income Bonus"
	
	-- Update Pending
	leftPanel.PendingCount.Text = "+" .. currentData.pendingMeatballs
	
	-- Update Button
	local prestigeBtn = leftPanel.PrestigeButton
	if currentData.pendingMeatballs >= PrestigeConfig.MINIMUM_PRESTIGE_GAIN then
		prestigeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
		prestigeBtn.Text = "PRESTIGE RESET"
		prestigeBtn.AutoButtonColor = true
	else
		prestigeBtn.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
		prestigeBtn.Text = "Need " .. PrestigeConfig.MINIMUM_PRESTIGE_GAIN .. " to Prestige"
		prestigeBtn.AutoButtonColor = false
	end
	
	-- Update Shop
	-- Clear old items
	for _, child in shopPanel:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end
	
	-- Add items
	for _, item in ipairs(PrestigeConfig.SHOP_ITEMS) do
		local isOwned = false
		for _, ownedId in ipairs(currentData.upgrades) do
			if ownedId == item.Id then
				isOwned = true
				break
			end
		end
		
		local isLocked = currentData.totalMeatballs < item.UnlockAt
		
		createShopItem(shopPanel, item, isOwned, isLocked)
	end
end

--------------------------------------------------------------------------------
-- MAIN LOGIC
--------------------------------------------------------------------------------

local ui = createPrestigeUI()

PrestigeEvent.OnClientEvent:Connect(function(action, data)
	if action == "OpenMenu" then
		currentData = data
		updateUI(ui)
		ui.Enabled = true
	elseif action == "UpdateData" then
		currentData = data
		if ui.Enabled then
			updateUI(ui)
		end
	elseif action == "PrestigeCompleted" then
		-- Play cool effect?
		print("Prestige completed! Gained " .. data.gained .. " meatballs.")
	end
end)

-- HUD Integration (Optional: Add meatball counter to main HUD)
-- For now, we rely on the Altar UI.
