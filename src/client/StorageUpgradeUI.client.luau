--[[
	StorageUpgradeUI LocalScript

	Creates a storage upgrade shop interface triggered by StorageVendor.
	Matches the layout and silhouette style of the Cart Shop.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

-- Player reference
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopInteraction = require(script.Parent:WaitForChild("ShopInteraction"))
local UIConfig = require(Shared:WaitForChild("UIConfig"))

local Utils = Shared:WaitForChild("Utils")
local UIUtils = require(Utils:WaitForChild("UIUtils"))
local FormatUtils = require(Utils:WaitForChild("FormatUtils"))
local ViewportPreview = require(Shared:WaitForChild("ViewportPreview"))

local function formatPrice(price: number?): string
	if not price then
		return "MAX"
	end
	return FormatUtils.formatPrice(price)
end

local function formatStorage(amount: number?): string
	return FormatUtils.formatNumber(amount or 0)
end

-- Wait for remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local UpgradeStorageEvent = RemoteEvents:WaitForChild("UpgradeStorageRequest")
local UpgradeStorageTierEvent = RemoteEvents:WaitForChild("UpgradeStorageTierRequest")
local GetStorageInfoEvent = RemoteFunctions:WaitForChild("GetStorageInfo")
local StorageUpgradedEvent = RemoteEvents:WaitForChild("StorageUpgraded")

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

local UpgradeSound = createSound("rbxassetid://138081500", 0.5) -- Cash register
local ErrorSound = createSound("rbxassetid://138090596", 0.3) -- Error

--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local shopOpen = false
local CurrentStorageInfo = nil

local function createShopUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StorageUpgradeUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 430, 0, 430)
	mainFrame.Position = UDim2.new(0.5, -215, 0.5, -215)
	mainFrame.BackgroundColor3 = UIConfig.PANEL_COLOR
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui

	UIUtils.addCorner(mainFrame, 16)
	UIUtils.addStroke(mainFrame, UIConfig.STROKE_COLOR, 1.8, 0.15)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UIConfig.PANEL_COLOR),
		ColorSequenceKeypoint.new(1, UIConfig.BACKGROUND_COLOR)
	})
	gradient.Rotation = 90
	gradient.Parent = mainFrame

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundTransparency = 1
	header.BorderSizePixel = 0
	header.Parent = mainFrame

	local titleChip = Instance.new("Frame")
	titleChip.Name = "TitleChip"
	titleChip.Size = UDim2.new(0, 270, 0, 44)
	titleChip.Position = UDim2.new(0, 12, 0, 8)
	titleChip.BackgroundColor3 = UIConfig.TITLE_CHIP_COLOR
	titleChip.BorderSizePixel = 0
	titleChip.Parent = header
	UIUtils.addCorner(titleChip, 9)
	UIUtils.addStroke(titleChip, UIConfig.TITLE_CHIP_STROKE, 1.2, 0.1)

	local title = Instance.new("TextLabel")
	title.Text = "STORAGE SHOP"
	title.Size = UDim2.new(1, -16, 1, 0)
	title.Position = UDim2.new(0, 10, 0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = UIConfig.TEXT_COLOR
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 23
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = titleChip

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Text = "X"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -50, 0, 10)
	closeBtn.BackgroundColor3 = UIConfig.RED_COLOR
	closeBtn.TextColor3 = Color3.new(1,1,1)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.TextSize = 20
	closeBtn.Parent = header
	UIUtils.addCorner(closeBtn, 9)
	UIUtils.addStroke(closeBtn, Color3.fromRGB(120, 20, 30), 1.2, 0.1)

	-- Content
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -20, 1, -80)
	content.Position = UDim2.new(0, 10, 0, 70)
	content.BackgroundColor3 = UIConfig.CARD_INNER_COLOR
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 4
	content.ScrollBarImageColor3 = UIConfig.ACCENT_COLOR
	content.Parent = mainFrame
	UIUtils.addCorner(content, 10)
	UIUtils.addStroke(content, UIConfig.SOFT_STROKE_COLOR, 1, 0.25)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = content
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		content.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
	end)

	screenGui.Parent = PlayerGui
	return screenGui, content, closeBtn, mainFrame
end

local function canAfford(price)
	local leaderstats = Player:FindFirstChild("leaderstats")
	if not leaderstats then return false end
	local money = leaderstats:FindFirstChild("Money")
	if not money then return false end
	return money.Value >= price
end

--------------------------------------------------------------------------------
-- CARD CREATION
--------------------------------------------------------------------------------

local function createUpgradeCard(parent, id, title, data)
	local card = Instance.new("Frame")
	card.Name = id
	card.Size = UDim2.new(1, -10, 0, 165)
	card.BackgroundColor3 = UIConfig.CARD_COLOR
	card.Parent = parent
	UIUtils.addCorner(card, 10)
	UIUtils.addStroke(card, UIConfig.SOFT_STROKE_COLOR, 1, 0.2)

	-- Icon Container (Viewport)
	local iconContainer = Instance.new("Frame")
	iconContainer.Name = "IconContainer"
	iconContainer.Size = UDim2.new(0, 60, 0, 60)
	iconContainer.Position = UDim2.new(0, 10, 0, 10)
	iconContainer.BackgroundTransparency = 0
	iconContainer.BackgroundColor3 = UIConfig.CARD_INNER_COLOR
	iconContainer.Parent = card
	UIUtils.addCorner(iconContainer, 6)

	if data.ViewportModel then
		local targetModel = data.ViewportModel
		if data.IsSilhouette then
			ViewportPreview.CreateSilhouette(targetModel, iconContainer)
		else
			ViewportPreview.CreateStatic(targetModel, iconContainer)
		end
	else
		-- Fallback
		local iconLbl = Instance.new("TextLabel")
		iconLbl.Text = "📦"
		iconLbl.Size = UDim2.new(1, 0, 1, 0)
		iconLbl.BackgroundTransparency = 1
		iconLbl.TextSize = 40
		iconLbl.Parent = iconContainer
	end

	-- Title
	local titleLbl = Instance.new("TextLabel")
	titleLbl.Text = title
	titleLbl.Size = UDim2.new(1, -80, 0, 25)
	titleLbl.Position = UDim2.new(0, 80, 0, 10)
	titleLbl.BackgroundTransparency = 1
	titleLbl.TextColor3 = UIConfig.TEXT_COLOR
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.TextSize = 18
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = card

	-- Stats
	local statsLbl = Instance.new("TextLabel")
	statsLbl.Name = "Stats"
	statsLbl.Size = UDim2.new(1, -80, 0, 40)
	statsLbl.Position = UDim2.new(0, 80, 0, 35)
	statsLbl.BackgroundTransparency = 1
	statsLbl.TextColor3 = UIConfig.SECONDARY_TEXT_COLOR
	statsLbl.Font = Enum.Font.Gotham
	statsLbl.TextSize = 14
	statsLbl.TextXAlignment = Enum.TextXAlignment.Left
	statsLbl.TextWrapped = true
	statsLbl.Parent = card
	statsLbl.Text = data.StatsText or ""
	if data.IsMaxed then
		card.BackgroundColor3 = UIConfig.CARD_MAXED_COLOR
	end

	-- Button
	local btn = Instance.new("TextButton")
	btn.Name = "BuyButton"
	btn.Size = UDim2.new(1, -20, 0, 40)
	btn.Position = UDim2.new(0, 10, 1, -50)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.Parent = card
	UIUtils.addCorner(btn, 6)

	local function updateAffordability()
		if data.IsMaxed then return end
		local affordable = canAfford(data.Price or 0)
		btn.BackgroundColor3 = affordable and UIConfig.BUTTON_COLOR or UIConfig.BUTTON_DISABLED_COLOR
	end

	if data.IsMaxed then
		btn.Text = "MAXED"
		btn.BackgroundColor3 = UIConfig.BUTTON_DISABLED_COLOR
		btn.AutoButtonColor = false
	else
		btn.Text = data.ButtonText or ("BUY ($" .. formatPrice(data.Price) .. ")")
		updateAffordability()

		btn.MouseButton1Click:Connect(function()
			if not canAfford(data.Price or 0) then
				ErrorSound:Play()
				return
			end
			if data.OnPurchase then
				data.OnPurchase()
			end
		end)

		local leaderstats = Player:WaitForChild("leaderstats", 10)
		if leaderstats then
			local money = leaderstats:WaitForChild("Money", 5)
			if money then
				local conn
				conn = money:GetPropertyChangedSignal("Value"):Connect(function()
					if not card.Parent then
						conn:Disconnect()
						return
					end
					updateAffordability()
				end)
			end
		end
	end

	return card
end

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local StorageGui, contentFrame, closeBtn, mainFrame = createShopUI()

local function updateUI()
	if not CurrentStorageInfo then return end

	-- Clear
	for _, c in contentFrame:GetChildren() do
		if c:IsA("Frame") then c:Destroy() end
	end

	local capInfo = CurrentStorageInfo.capacity or {
		current = CurrentStorageInfo.currentMax,
		next = CurrentStorageInfo.nextMaxStorage,
		price = CurrentStorageInfo.nextPrice,
	}
	local tierInfo = CurrentStorageInfo.tier or {
		current = 1,
		next = 2,
		max = 5,
		canUpgrade = true,
		price = (CurrentStorageInfo.nextPrice or 0) * 2,
	}
	local displayMax = CurrentStorageInfo.displayMax or capInfo.current or 0

	local storageModels = ReplicatedStorage:FindFirstChild("Models") and ReplicatedStorage.Models:FindFirstChild("PlayerStorage")
	local currentTierModelRef = storageModels and storageModels:FindFirstChild("PlayerStorageTier" .. tostring(tierInfo.current or 1))
	local nextTierModelRef = storageModels and storageModels:FindFirstChild("PlayerStorageTier" .. tostring(tierInfo.next or 1))

	local capacityCardData = {
		StatsText = string.format(
			"Current Base: %s Capacity\nEffective Capacity: %s\nNext Base: %s Capacity",
			formatStorage(capInfo.current or 0),
			formatStorage(displayMax),
			formatStorage(capInfo.next or 0)
		),
		Price = capInfo.price,
		ViewportModel = currentTierModelRef or nextTierModelRef,
		IsSilhouette = false,
		ButtonText = "UPGRADE CURRENT STORAGE ($" .. formatPrice(capInfo.price) .. ")",
		OnPurchase = function()
			UpgradeStorageEvent:FireServer()
		end,
	}
	createUpgradeCard(contentFrame, "CapacityUpgrade", "Upgrade Current Storage", capacityCardData).LayoutOrder = 1

	local tierMaxed = not tierInfo.canUpgrade
	local tierStats = tierMaxed
		and string.format("Current Tier: %d/%d\nStorage visual fully upgraded", tierInfo.current or 1, tierInfo.max or 1)
		or string.format("Current Tier: %d/%d\nNext Tier: %d", tierInfo.current or 1, tierInfo.max or 1, tierInfo.next or (tierInfo.current or 1))

	local tierCardData = {
		StatsText = tierStats,
		Price = tierInfo.price,
		IsMaxed = tierMaxed,
		ViewportModel = nextTierModelRef or currentTierModelRef,
		IsSilhouette = false,
		ButtonText = tierMaxed and "MAX TIER" or ("GET NEXT TIER ($" .. formatPrice(tierInfo.price) .. ")"),
		OnPurchase = function()
			UpgradeStorageTierEvent:FireServer()
		end,
	}
	createUpgradeCard(contentFrame, "TierUpgrade", "Buy Next Tier", tierCardData).LayoutOrder = 2
end

local function refreshInfo()
	local info = GetStorageInfoEvent:InvokeServer()
	if info then
		CurrentStorageInfo = info
	end
	updateUI()
end

local function openShop()
	if shopOpen then return end
	shopOpen = true
	mainFrame.Visible = true

	mainFrame.Size = UDim2.new(0,0,0,0)
	TweenService:Create(mainFrame, TweenInfo.new(UIConfig.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 430, 0, 430)
	}):Play()

	refreshInfo()
end

local function closeShop()
	if not shopOpen then return end

	TweenService:Create(mainFrame, TweenInfo.new(UIConfig.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0,0,0,0)
	}):Play()

	task.wait(UIConfig.TWEEN_TIME)
	mainFrame.Visible = false
	shopOpen = false
end

--------------------------------------------------------------------------------
-- RUN
--------------------------------------------------------------------------------

local _interaction = ShopInteraction.new({
	PromptTag = "StorageUpgradeVendor",
	InteractionDist = 20,
	Keybind = Enum.KeyCode.E,
	OnOpen = openShop,
	OnClose = closeShop,
})

closeBtn.MouseButton1Click:Connect(function()
	_interaction:Close()
end)

UpgradeStorageEvent.OnClientEvent:Connect(function(success, message)
	if success then
		UpgradeSound:Play()
		refreshInfo()
	else
		ErrorSound:Play()
		warn("Purchase failed: " .. tostring(message))
	end
end)

UpgradeStorageTierEvent.OnClientEvent:Connect(function(success, message)
	if success then
		UpgradeSound:Play()
		refreshInfo()
	else
		ErrorSound:Play()
		warn("Tier purchase failed: " .. tostring(message))
	end
end)

StorageUpgradedEvent.OnClientEvent:Connect(function(newInfo)
	CurrentStorageInfo = newInfo
	updateUI()
end)

local UIManager = require(script.Parent:WaitForChild("Managers"):WaitForChild("UIManager"))
UIManager.RegisterShop("StorageUpgrades", function()
	if shopOpen then closeShop() else openShop() end
end)

print("StorageUpgradeUI initialized")

