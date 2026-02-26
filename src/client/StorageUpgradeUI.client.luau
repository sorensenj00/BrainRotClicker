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
local FormatUtils = require(Shared:WaitForChild("Utils"):WaitForChild("FormatUtils"))
local ShopInteraction = require(script.Parent:WaitForChild("ShopInteraction"))

-- Wait for remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local UpgradeStorageEvent = RemoteEvents:WaitForChild("UpgradeStorage")
local UpgradeStorageTierEvent = RemoteEvents:WaitForChild("UpgradeStorageTier")
local GetStorageInfoEvent = RemoteFunctions:WaitForChild("GetStorageInfo")
local StorageUpgradedEvent = RemoteEvents:WaitForChild("StorageUpgraded")

--------------------------------------------------------------------------------
-- UI CONFIGURATION
--------------------------------------------------------------------------------

local UI_CONFIG = {
	TWEEN_TIME = 0.3,
	COLORS = {
		Background = Color3.fromRGB(15, 15, 22),
		Header = Color3.fromRGB(20, 20, 30),
		Card = Color3.fromRGB(25, 25, 35),
		CardMaxed = Color3.fromRGB(20, 35, 25),
		Accent = Color3.fromRGB(250, 190, 60),
		Text = Color3.fromRGB(240, 240, 255),
		TextMuted = Color3.fromRGB(160, 160, 180),
		Green = Color3.fromRGB(80, 230, 120),
		Red = Color3.fromRGB(250, 70, 70),
		Button = Color3.fromRGB(60, 160, 80),
		ButtonDisabled = Color3.fromRGB(40, 40, 50),
		Stroke = Color3.fromRGB(70, 70, 90),
	},
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

local UpgradeSound = createSound("rbxassetid://138081500", 0.5) -- Cash register
local ErrorSound = createSound("rbxassetid://138090596", 0.3) -- Error

--------------------------------------------------------------------------------
-- LOCAL STATE
--------------------------------------------------------------------------------

local shopOpen = false
local CurrentStorageInfo = nil

--------------------------------------------------------------------------------
-- VIEWPORT HELPERS
--------------------------------------------------------------------------------

local function createStaticViewport(model: Model, parent: GuiObject): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ModelPreview"
	viewport.Size = UDim2.new(1, 0, 1, 0)
	viewport.BackgroundColor3 = UI_CONFIG.COLORS.Card
	viewport.BackgroundTransparency = 1
	viewport.BorderSizePixel = 0
	viewport.Parent = parent

	local previewModel = model:Clone()
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	previewModel.Parent = worldModel

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

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

local function createSilhouetteModel(model: Model): Model
	local clone = model:Clone()

	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Color = Color3.new(0, 0, 0)
			desc.Material = Enum.Material.Neon
			desc.Transparency = 0
			if desc:IsA("MeshPart") then
				desc.TextureID = ""
			end
		elseif desc:IsA("SurfaceAppearance") or desc:IsA("Decal") or desc:IsA("Texture") then
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
-- UI CREATION
--------------------------------------------------------------------------------

local function formatPrice(price)
	if not price then return "MAX" end
	return FormatUtils.formatPrice(price)
end

local function formatStorage(amount: number): string
	if amount >= 1000000 then
		return string.format("%.1fM", amount / 1000000)
	elseif amount >= 1000 then
		return string.format("%.1fK", amount / 1000)
	else
		return tostring(math.floor(amount))
	end
end

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function createShopUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StorageUpgradeUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 430, 0, 430)
	mainFrame.Position = UDim2.new(0.5, -215, 0.5, -215)
	mainFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	mainFrame.BackgroundTransparency = 0.2
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui

	addCorner(mainFrame, 16)

	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = UI_CONFIG.COLORS.Stroke
	uiStroke.Thickness = 1.5
	uiStroke.Transparency = 0.5
	uiStroke.Parent = mainFrame

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UI_CONFIG.COLORS.Header),
		ColorSequenceKeypoint.new(1, UI_CONFIG.COLORS.Background)
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

	local title = Instance.new("TextLabel")
	title.Text = "STORAGE SHOP"
	title.Size = UDim2.new(1, -50, 1, 0)
	title.Position = UDim2.new(0, 20, 0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = UI_CONFIG.COLORS.Accent
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Text = "✕"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -50, 0, 10)
	closeBtn.BackgroundColor3 = UI_CONFIG.COLORS.Red
	closeBtn.TextColor3 = Color3.new(1,1,1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.Parent = header
	addCorner(closeBtn, 20) -- 50% radius for circle

	-- Content
	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -20, 1, -80)
	content.Position = UDim2.new(0, 10, 0, 70)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 4
	content.Parent = mainFrame

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
	card.BackgroundColor3 = UI_CONFIG.COLORS.Card
	card.Parent = parent
	addCorner(card, 8)

	-- Icon Container (Viewport)
	local iconContainer = Instance.new("Frame")
	iconContainer.Name = "IconContainer"
	iconContainer.Size = UDim2.new(0, 60, 0, 60)
	iconContainer.Position = UDim2.new(0, 10, 0, 10)
	iconContainer.BackgroundTransparency = 0
	iconContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	iconContainer.Parent = card
	addCorner(iconContainer, 6)

	if data.ViewportModel then
		local targetModel = data.ViewportModel
		if data.IsSilhouette then
			targetModel = createSilhouetteModel(targetModel)
		end
		createStaticViewport(targetModel, iconContainer)
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
	titleLbl.TextColor3 = UI_CONFIG.COLORS.Text
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
	statsLbl.TextColor3 = UI_CONFIG.COLORS.TextMuted
	statsLbl.Font = Enum.Font.Gotham
	statsLbl.TextSize = 14
	statsLbl.TextXAlignment = Enum.TextXAlignment.Left
	statsLbl.TextWrapped = true
	statsLbl.Parent = card
	statsLbl.Text = data.StatsText or ""
	if data.IsMaxed then
		card.BackgroundColor3 = UI_CONFIG.COLORS.CardMaxed
	end

	-- Button
	local btn = Instance.new("TextButton")
	btn.Name = "BuyButton"
	btn.Size = UDim2.new(1, -20, 0, 40)
	btn.Position = UDim2.new(0, 10, 1, -50)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.Parent = card
	addCorner(btn, 6)

	local function updateAffordability()
		if data.IsMaxed then return end
		local affordable = canAfford(data.Price or 0)
		btn.BackgroundColor3 = affordable and UI_CONFIG.COLORS.Button or UI_CONFIG.COLORS.ButtonDisabled
	end

	if data.IsMaxed then
		btn.Text = "MAXED"
		btn.BackgroundColor3 = UI_CONFIG.COLORS.ButtonDisabled
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
		IsMaxed = false,
		ViewportModel = currentTierModelRef or nextTierModelRef,
		IsSilhouette = true,
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
	TweenService:Create(mainFrame, TweenInfo.new(UI_CONFIG.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 430, 0, 430)
	}):Play()

	refreshInfo()
end

local function closeShop()
	if not shopOpen then return end

	TweenService:Create(mainFrame, TweenInfo.new(UI_CONFIG.TWEEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = UDim2.new(0,0,0,0)
	}):Play()

	task.wait(UI_CONFIG.TWEEN_TIME)
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

print("✓ StorageUpgradeUI initialized")
