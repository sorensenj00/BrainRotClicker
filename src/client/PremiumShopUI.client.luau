--[[
	PremiumShopUI Client Script

	Two tabs:
	- Get Braincells (Robux product purchase)
	- Spend Braincells (server validated premium perks)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PremiumShopConfig = require(Shared:WaitForChild("PremiumShopConfig"))
local UIConfig = require(Shared:WaitForChild("UIConfig"))
local UIUtils = require(Shared:WaitForChild("Utils"):WaitForChild("UIUtils"))
local FormatUtils = require(Shared:WaitForChild("Utils"):WaitForChild("FormatUtils"))
local ShopInteraction = require(script.Parent:WaitForChild("ShopInteraction"))

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local SpendBraincellsRemote = RemoteFunctions:WaitForChild("SpendBraincells")
local GetPremiumShopStateRemote = RemoteFunctions:WaitForChild("GetPremiumShopState")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PremiumShopNoticeEvent = RemoteEvents:WaitForChild("PremiumShopNotice")
local AchievementNotifyEvent = RemoteEvents:WaitForChild("AchievementNotify")

local UI = {
	ScreenGui = nil,
	MainFrame = nil,
	ContentFrame = nil,
	FeedbackLabel = nil,
	BalanceLabel = nil,
	TabButtons = {},
}

local currentTab = "GetBraincells"
local shopOpen = false
local actionDebounce = false
local PREMIUM_ACHIEVEMENT_IDS = {
	braincell_burner = true,
	crate_enjoyer = true,
	pump_it = true,
}

local function formatBraincells(amount: number): string
	return string.format("Braincells: %s", FormatUtils.formatNumber(amount))
end

local function getBraincellsValue(): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local braincells = leaderstats and leaderstats:FindFirstChild("Braincells")
	if braincells then
		return braincells.Value
	end
	return 0
end

local function setFeedback(text: string, isError: boolean?)
	if not UI.FeedbackLabel then return end
	UI.FeedbackLabel.Text = text or ""
	UI.FeedbackLabel.TextColor3 = isError and UIConfig.RED_COLOR or UIConfig.GREEN_COLOR
	task.delay(3, function()
		if UI.FeedbackLabel and UI.FeedbackLabel.Text == text then
			UI.FeedbackLabel.Text = ""
		end
	end)
end

local function updateBalanceLabel()
	if not UI.BalanceLabel then return end
	UI.BalanceLabel.Text = formatBraincells(getBraincellsValue())
end

local function clearContent()
	if not UI.ContentFrame then return end
	for _, child in ipairs(UI.ContentFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function createCard(parent: Instance, title: string, description: string, rightInfo: string, buttonText: string, onClick: () -> ())
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, -8, 0, 100)
	card.BackgroundColor3 = UIConfig.CARD_COLOR
	card.BorderSizePixel = 0
	card.Parent = parent
	UIUtils.addCorner(card, 8)
	UIUtils.addStroke(card, UIConfig.SOFT_STROKE_COLOR, 1)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -150, 0, 24)
	titleLabel.Position = UDim2.fromOffset(10, 8)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = title
	titleLabel.TextColor3 = UIConfig.TEXT_COLOR
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 15
	titleLabel.Parent = card

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Size = UDim2.new(1, -150, 0, 44)
	descriptionLabel.Position = UDim2.fromOffset(10, 34)
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Text = description
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextColor3 = UIConfig.SECONDARY_TEXT_COLOR
	descriptionLabel.Font = Enum.Font.Gotham
	descriptionLabel.TextSize = 12
	descriptionLabel.Parent = card

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.fromOffset(130, 22)
	infoLabel.Position = UDim2.new(1, -140, 0, 10)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = rightInfo
	infoLabel.TextColor3 = UIConfig.GOLD_COLOR
	infoLabel.Font = Enum.Font.GothamBold
	infoLabel.TextSize = 12
	infoLabel.Parent = card

	local actionButton = Instance.new("TextButton")
	actionButton.Size = UDim2.fromOffset(130, 36)
	actionButton.Position = UDim2.new(1, -140, 1, -46)
	actionButton.BackgroundColor3 = UIConfig.BUTTON_COLOR
	actionButton.BorderSizePixel = 0
	actionButton.Text = buttonText
	actionButton.TextColor3 = UIConfig.TEXT_COLOR
	actionButton.Font = Enum.Font.GothamBold
	actionButton.TextSize = 13
	actionButton.Parent = card
	UIUtils.addCorner(actionButton, 6)

	actionButton.MouseButton1Click:Connect(function()
		if actionDebounce then return end
		actionDebounce = true
		onClick()
		task.delay(0.25, function()
			actionDebounce = false
		end)
	end)
end

local function renderGetBraincellsTab()
	clearContent()
	for _, pack in ipairs(PremiumShopConfig.GetAllPacksSorted()) do
		createCard(
			UI.ContentFrame,
			pack.Name,
			string.format("%s Braincells", FormatUtils.formatNumber(pack.Braincells)),
			pack.RobuxLabel,
			"Buy",
			function()
				MarketplaceService:PromptProductPurchase(player, pack.ProductId)
			end
		)
	end
end

local function renderSpendBraincellsTab()
	clearContent()
	for _, item in ipairs(PremiumShopConfig.GetAllShopItemsSorted()) do
		createCard(
			UI.ContentFrame,
			item.Name,
			item.Description,
			string.format("%s BC", FormatUtils.formatNumber(item.Price)),
			"Purchase",
			function()
				local ok, result = pcall(function()
					return SpendBraincellsRemote:InvokeServer(item.Id)
				end)
				if not ok or type(result) ~= "table" then
					setFeedback("Could not contact server", true)
					return
				end

				if result.success then
					setFeedback(result.message or "Purchased!", false)
				else
					setFeedback(result.message or "Purchase failed", true)
				end
				updateBalanceLabel()
			end
		)
	end
end

local function refreshTab()
	for tabName, button in pairs(UI.TabButtons) do
		button.BackgroundColor3 = (tabName == currentTab) and UIConfig.ACCENT_COLOR or UIConfig.CARD_COLOR
	end

	if currentTab == "GetBraincells" then
		renderGetBraincellsTab()
	else
		renderSpendBraincellsTab()
	end
end

local function createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PremiumShopUI"
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromOffset(720, 540)
	mainFrame.Position = UDim2.new(0.5, -360, 0.5, -270)
	mainFrame.BackgroundColor3 = UIConfig.PANEL_COLOR
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui
	UIUtils.addCorner(mainFrame, 14)
	UIUtils.addStroke(mainFrame, UIConfig.STROKE_COLOR, 1.5)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UIConfig.PANEL_COLOR),
		ColorSequenceKeypoint.new(1, UIConfig.BACKGROUND_COLOR),
	})
	gradient.Rotation = 90
	gradient.Parent = mainFrame

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromOffset(280, 40)
	title.Position = UDim2.fromOffset(16, 10)
	title.BackgroundTransparency = 1
	title.Text = "PREMIUM SHOP"
	title.TextColor3 = UIConfig.TEXT_COLOR
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = mainFrame

	local balanceLabel = Instance.new("TextLabel")
	balanceLabel.Size = UDim2.fromOffset(260, 28)
	balanceLabel.Position = UDim2.fromOffset(16, 44)
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.TextColor3 = UIConfig.GOLD_COLOR
	balanceLabel.Font = Enum.Font.GothamBold
	balanceLabel.TextSize = 16
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	balanceLabel.Parent = mainFrame

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(40, 40)
	closeButton.Position = UDim2.new(1, -50, 0, 10)
	closeButton.BackgroundColor3 = UIConfig.RED_COLOR
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = UIConfig.TEXT_COLOR
	closeButton.Font = Enum.Font.GothamBlack
	closeButton.TextSize = 20
	closeButton.Parent = mainFrame
	UIUtils.addCorner(closeButton, 8)

	local tabGetButton = Instance.new("TextButton")
	tabGetButton.Size = UDim2.fromOffset(180, 34)
	tabGetButton.Position = UDim2.fromOffset(16, 82)
	tabGetButton.BackgroundColor3 = UIConfig.ACCENT_COLOR
	tabGetButton.BorderSizePixel = 0
	tabGetButton.Text = "Get Braincells"
	tabGetButton.TextColor3 = UIConfig.TEXT_COLOR
	tabGetButton.Font = Enum.Font.GothamBold
	tabGetButton.TextSize = 14
	tabGetButton.Parent = mainFrame
	UIUtils.addCorner(tabGetButton, 8)

	local tabSpendButton = Instance.new("TextButton")
	tabSpendButton.Size = UDim2.fromOffset(180, 34)
	tabSpendButton.Position = UDim2.fromOffset(206, 82)
	tabSpendButton.BackgroundColor3 = UIConfig.CARD_COLOR
	tabSpendButton.BorderSizePixel = 0
	tabSpendButton.Text = "Spend Braincells"
	tabSpendButton.TextColor3 = UIConfig.TEXT_COLOR
	tabSpendButton.Font = Enum.Font.GothamBold
	tabSpendButton.TextSize = 14
	tabSpendButton.Parent = mainFrame
	UIUtils.addCorner(tabSpendButton, 8)

	local contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Size = UDim2.new(1, -24, 1, -170)
	contentFrame.Position = UDim2.fromOffset(12, 126)
	contentFrame.BackgroundColor3 = UIConfig.CARD_INNER_COLOR
	contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 6
	contentFrame.ScrollBarImageColor3 = UIConfig.ACCENT_COLOR
	contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.Parent = mainFrame
	UIUtils.addCorner(contentFrame, 10)
	UIUtils.addStroke(contentFrame, UIConfig.SOFT_STROKE_COLOR, 1)

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = contentFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = contentFrame

	local feedback = Instance.new("TextLabel")
	feedback.Size = UDim2.new(1, -24, 0, 22)
	feedback.Position = UDim2.new(0, 12, 1, -28)
	feedback.BackgroundTransparency = 1
	feedback.Text = ""
	feedback.TextColor3 = UIConfig.GREEN_COLOR
	feedback.TextXAlignment = Enum.TextXAlignment.Left
	feedback.Font = Enum.Font.GothamBold
	feedback.TextSize = 13
	feedback.Parent = mainFrame

	UI.ScreenGui = screenGui
	UI.MainFrame = mainFrame
	UI.ContentFrame = contentFrame
	UI.FeedbackLabel = feedback
	UI.BalanceLabel = balanceLabel
	UI.TabButtons = {
		GetBraincells = tabGetButton,
		SpendBraincells = tabSpendButton,
	}

	tabGetButton.MouseButton1Click:Connect(function()
		currentTab = "GetBraincells"
		refreshTab()
	end)

	tabSpendButton.MouseButton1Click:Connect(function()
		currentTab = "SpendBraincells"
		refreshTab()
	end)

	closeButton.MouseButton1Click:Connect(function()
		if not shopOpen then return end
		shopOpen = false
		local tween = TweenService:Create(mainFrame, UIConfig.TWEEN_INFO.Close, {
			Size = UDim2.new(0, 0, 0, 0),
			Position = UDim2.new(0.5, 0, 0.5, 50),
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			if not shopOpen then
				mainFrame.Visible = false
				screenGui.Enabled = false
			end
		end)
	end)
end

local function openShop()
	if shopOpen then return end
	shopOpen = true
	UI.ScreenGui.Enabled = true
	UI.MainFrame.Visible = true

	UI.MainFrame.Size = UDim2.new(0, 0, 0, 0)
	UI.MainFrame.Position = UDim2.new(0.5, 0, 0.5, 50)
	UI.MainFrame.BackgroundTransparency = 1

	local tween = TweenService:Create(UI.MainFrame, UIConfig.TWEEN_INFO.Open, {
		Size = UDim2.fromOffset(720, 540),
		Position = UDim2.new(0.5, -360, 0.5, -270),
		BackgroundTransparency = 0,
	})
	tween:Play()

	updateBalanceLabel()
	task.spawn(function()
		local ok, state = pcall(function()
			return GetPremiumShopStateRemote:InvokeServer()
		end)
		if ok and type(state) == "table" and type(state.Braincells) == "number" then
			if UI.BalanceLabel then
				UI.BalanceLabel.Text = formatBraincells(state.Braincells)
			end
		end
	end)
	refreshTab()
end

local function closeShop()
	if not shopOpen then return end
	shopOpen = false
	local tween = TweenService:Create(UI.MainFrame, UIConfig.TWEEN_INFO.Close, {
		Size = UDim2.new(0, 0, 0, 0),
		Position = UDim2.new(0.5, 0, 0.5, 50),
		BackgroundTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		if not shopOpen then
			UI.MainFrame.Visible = false
			UI.ScreenGui.Enabled = false
		end
	end)
end

createUI()
updateBalanceLabel()

PremiumShopNoticeEvent.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and type(payload.Message) == "string" then
		setFeedback(payload.Message, false)
		return
	end
	if type(payload) == "string" then
		setFeedback(payload, false)
	end
end)

AchievementNotifyEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if not PREMIUM_ACHIEVEMENT_IDS[payload.AchievementId] then
		return
	end

	local action = payload.Action
	local title = payload.Title or payload.AchievementId or "Achievement"
	if action == "Unlocked" then
		setFeedback("Premium achievement unlocked: " .. title, false)
	elseif action == "Claimed" then
		setFeedback("Premium achievement claimed: " .. title, false)
	end
end)

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 10)
	if not leaderstats then return end
	local braincells = leaderstats:WaitForChild("Braincells", 10)
	if not braincells then return end

	braincells:GetPropertyChangedSignal("Value"):Connect(function()
		updateBalanceLabel()
	end)
end)

local interaction = ShopInteraction.new({
	PromptTag = "PremiumShopVendor",
	InteractionDist = 20,
	Keybind = Enum.KeyCode.E,
	OnOpen = openShop,
	OnClose = closeShop,
})

local UIManager = require(script.Parent:WaitForChild("Managers"):WaitForChild("UIManager"))
UIManager.RegisterShop("PremiumShop", function()
	if shopOpen then
		interaction:Close()
	else
		interaction:Open()
	end
end)

print("PremiumShopUI initialized")
