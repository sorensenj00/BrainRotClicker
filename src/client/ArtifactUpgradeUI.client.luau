--[[
	ArtifactUpgradeUI Client Script

	Standalone UI for 5-to-1 artifact upgrades at the Tun vendor in MarketShop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))
local ArtifactUpgradeConfig = require(Shared:WaitForChild("ArtifactUpgradeConfig"))
local ShopInteraction = require(script.Parent:WaitForChild("ShopInteraction"))
local UIManager = require(script.Parent:WaitForChild("Managers"):WaitForChild("UIManager"))

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local GetArtifactUpgradeState = RemoteFunctions:WaitForChild("GetArtifactUpgradeState")
local CombineArtifacts = RemoteFunctions:WaitForChild("CombineArtifacts")

local UI = {
	ScreenGui = nil,
	Main = nil,
	CloseButton = nil,
	Status = nil,
	RewardToast = nil,
	RewardToastScale = nil,
	Rows = {},
}

local isOpen = false
local interactionRef = nil

local function getRarityColor(rarity)
	return ArtifactConfig.RarityColors[rarity] or Color3.fromRGB(200, 200, 200)
end

local function setStatus(text, color)
	if not UI.Status then
		return
	end
	UI.Status.Text = text or ""
	UI.Status.TextColor3 = color or Color3.fromRGB(210, 210, 220)
end

local function getRarityIcon(rarity)
	local icons = {
		Common = "◻",
		Uncommon = "✦",
		Rare = "◆",
		Epic = "⬟",
		Legendary = "★",
	}
	return icons[rarity] or "◆"
end

local function showRewardToast(artifactName, rarity)
	local toast = UI.RewardToast
	if not toast then
		return
	end
	local toastScale = UI.RewardToastScale

	local rarityColor = getRarityColor(rarity)
	local rarityIcon = getRarityIcon(rarity)
	toast.Text = string.format("%s New %s: %s", rarityIcon, tostring(rarity or "Artifact"), tostring(artifactName or "Unknown"))
	toast.TextColor3 = rarityColor
	toast.BackgroundTransparency = 1
	toast.Visible = true
	if toastScale then
		toastScale.Scale = 0.9
	end

	local fadeIn = TweenService:Create(toast, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.15,
	})
	fadeIn:Play()
	if toastScale then
		local popUp = TweenService:Create(toastScale, TweenInfo.new(0.11, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1.06,
		})
		popUp:Play()
		popUp.Completed:Connect(function()
			if toastScale.Parent then
				TweenService:Create(toastScale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
			end
		end)
	end

	task.spawn(function()
		task.wait(1.8)
		if not toast.Parent then
			return
		end
		local fadeOut = TweenService:Create(toast, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		})
		fadeOut:Play()
		fadeOut.Completed:Wait()
		if toast.Parent then
			toast.Visible = false
		end
	end)
end

local function createRow(parent, rarity)
	local row = Instance.new("Frame")
	row.Name = rarity .. "Row"
	row.Size = UDim2.new(1, -16, 0, 50)
	row.BackgroundColor3 = Color3.fromRGB(30, 30, 44)
	row.BorderSizePixel = 0
	row.Parent = parent

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	local rowStroke = Instance.new("UIStroke")
	rowStroke.Color = Color3.fromRGB(60, 60, 88)
	rowStroke.Thickness = 1
	rowStroke.Transparency = 0.35
	rowStroke.Parent = row

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "Rarity"
	rarityLabel.Size = UDim2.new(0, 130, 1, 0)
	rarityLabel.Position = UDim2.fromOffset(12, 0)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Font = Enum.Font.GothamBold
	rarityLabel.TextSize = 16
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	rarityLabel.TextColor3 = getRarityColor(rarity)
	rarityLabel.Text = rarity
	rarityLabel.Parent = row

	local countLabel = Instance.new("TextLabel")
	countLabel.Name = "Count"
	countLabel.Size = UDim2.new(0, 140, 1, 0)
	countLabel.Position = UDim2.fromOffset(145, 0)
	countLabel.BackgroundTransparency = 1
	countLabel.Font = Enum.Font.Gotham
	countLabel.TextSize = 14
	countLabel.TextXAlignment = Enum.TextXAlignment.Left
	countLabel.TextColor3 = Color3.fromRGB(215, 215, 230)
	countLabel.Text = "0 / " .. tostring(ArtifactUpgradeConfig.REQUIRED_COUNT)
	countLabel.Parent = row

	local upgradeBtn = Instance.new("TextButton")
	upgradeBtn.Name = "UpgradeButton"
	upgradeBtn.Size = UDim2.fromOffset(128, 32)
	upgradeBtn.Position = UDim2.new(1, -140, 0.5, -16)
	upgradeBtn.BackgroundColor3 = Color3.fromRGB(72, 114, 255)
	upgradeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	upgradeBtn.Font = Enum.Font.GothamBold
	upgradeBtn.TextSize = 14
	upgradeBtn.Text = "Upgrade"
	upgradeBtn.AutoButtonColor = true
	upgradeBtn.Parent = row

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = upgradeBtn

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = Color3.fromRGB(35, 55, 120)
	btnStroke.Thickness = 1
	btnStroke.Transparency = 0.2
	btnStroke.Parent = upgradeBtn

	return {
		Row = row,
		Count = countLabel,
		Button = upgradeBtn,
		Rarity = rarity,
	}
end

local function createUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ArtifactUpgradeUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.Size = UDim2.fromOffset(540, 420)
	main.Position = UDim2.new(0.5, -270, 0.5, -210)
	main.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
	main.BorderSizePixel = 0
	main.Visible = false
	main.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 12)
	mainCorner.Parent = main

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(60, 60, 88)
	mainStroke.Thickness = 1.4
	mainStroke.Transparency = 0.15
	mainStroke.Parent = main

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -96, 0, 54)
	title.Position = UDim2.fromOffset(16, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.TextColor3 = Color3.fromRGB(245, 245, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "Artifact Upgrade"
	title.Parent = main

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -32, 0, 20)
	subtitle.Position = UDim2.fromOffset(16, 52)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 13
	subtitle.TextColor3 = Color3.fromRGB(170, 170, 190)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = string.format("Combine %d artifacts of a rarity into 1 of the next rarity.", ArtifactUpgradeConfig.REQUIRED_COUNT)
	subtitle.Parent = main

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(34, 34)
	closeBtn.Position = UDim2.new(1, -44, 0, 12)
	closeBtn.BackgroundColor3 = Color3.fromRGB(185, 64, 72)
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.Text = "X"
	closeBtn.Parent = main

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 8)
	closeCorner.Parent = closeBtn

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -24, 1, -126)
	content.Position = UDim2.fromOffset(12, 78)
	content.BackgroundColor3 = Color3.fromRGB(24, 24, 36)
	content.BorderSizePixel = 0
	content.Parent = main

	local contentCorner = Instance.new("UICorner")
	contentCorner.CornerRadius = UDim.new(0, 10)
	contentCorner.Parent = content

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 8)
	contentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = content

	local contentPadding = Instance.new("UIPadding")
	contentPadding.PaddingTop = UDim.new(0, 10)
	contentPadding.PaddingLeft = UDim.new(0, 8)
	contentPadding.PaddingRight = UDim.new(0, 8)
	contentPadding.Parent = content

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(1, -24, 0, 24)
	status.Position = UDim2.fromOffset(12, 386)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.Gotham
	status.TextSize = 13
	status.TextColor3 = Color3.fromRGB(210, 210, 220)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = ""
	status.Parent = main

	local rewardToast = Instance.new("TextLabel")
	rewardToast.Name = "RewardToast"
	rewardToast.Size = UDim2.fromOffset(340, 28)
	rewardToast.Position = UDim2.fromOffset(12, 354)
	rewardToast.BackgroundColor3 = Color3.fromRGB(26, 34, 58)
	rewardToast.BackgroundTransparency = 1
	rewardToast.Font = Enum.Font.GothamBold
	rewardToast.TextSize = 14
	rewardToast.TextXAlignment = Enum.TextXAlignment.Left
	rewardToast.TextColor3 = Color3.fromRGB(220, 220, 240)
	rewardToast.Text = ""
	rewardToast.Visible = false
	rewardToast.Parent = main

	local toastCorner = Instance.new("UICorner")
	toastCorner.CornerRadius = UDim.new(0, 8)
	toastCorner.Parent = rewardToast

	local toastStroke = Instance.new("UIStroke")
	toastStroke.Color = Color3.fromRGB(60, 86, 140)
	toastStroke.Thickness = 1
	toastStroke.Transparency = 0.25
	toastStroke.Parent = rewardToast

	local toastScale = Instance.new("UIScale")
	toastScale.Scale = 1
	toastScale.Parent = rewardToast

	UI.ScreenGui = screenGui
	UI.Main = main
	UI.CloseButton = closeBtn
	UI.Status = status
	UI.RewardToast = rewardToast
	UI.RewardToastScale = toastScale

	for _, rarity in ipairs(ArtifactUpgradeConfig.RARITY_ORDER) do
		UI.Rows[rarity] = createRow(content, rarity)
	end
end

local function setRowEnabled(rowData, enabled, buttonText)
	if enabled then
		rowData.Button.BackgroundColor3 = Color3.fromRGB(72, 114, 255)
		rowData.Button.TextColor3 = Color3.fromRGB(255, 255, 255)
		rowData.Button.AutoButtonColor = true
		rowData.Button.Active = true
		rowData.Button.Text = buttonText or "Upgrade"
	else
		rowData.Button.BackgroundColor3 = Color3.fromRGB(70, 70, 85)
		rowData.Button.TextColor3 = Color3.fromRGB(185, 185, 195)
		rowData.Button.AutoButtonColor = false
		rowData.Button.Active = false
		rowData.Button.Text = buttonText or "Unavailable"
	end
end

local function refreshState()
	local ok, state = pcall(function()
		return GetArtifactUpgradeState:InvokeServer()
	end)

	if not ok or type(state) ~= "table" then
		setStatus("Could not fetch upgrade state.", Color3.fromRGB(245, 100, 100))
		return
	end

	local requiredCount = state.requiredCount or ArtifactUpgradeConfig.REQUIRED_COUNT
	local upgrades = state.upgrades or {}

	for _, rarity in ipairs(ArtifactUpgradeConfig.RARITY_ORDER) do
		local rowData = UI.Rows[rarity]
		local upgradeInfo = upgrades[rarity] or {}
		local count = upgradeInfo.count or 0

		rowData.Count.Text = tostring(count) .. " / " .. tostring(requiredCount)

		if not upgradeInfo.canUpgrade then
			setRowEnabled(rowData, false, "Max Tier")
		elseif count >= requiredCount then
			local nextRarity = upgradeInfo.nextRarity or "Next"
			setRowEnabled(rowData, true, "Upgrade -> " .. nextRarity)
		else
			setRowEnabled(rowData, false, "Need " .. tostring(requiredCount))
		end
	end
end

local function openUI()
	if isOpen then
		return
	end
	isOpen = true

	UI.Main.Visible = true
	UI.Main.Size = UDim2.fromOffset(420, 320)
	TweenService:Create(UI.Main, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(540, 420),
	}):Play()

	setStatus("Select a rarity to upgrade.", Color3.fromRGB(205, 205, 220))
	refreshState()
end

local function closeUI()
	if not isOpen then
		return
	end
	isOpen = false

	local tween = TweenService:Create(UI.Main, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(420, 320),
	})
	tween:Play()
	tween.Completed:Wait()

	UI.Main.Visible = false
end

createUI()

for _, rarity in ipairs(ArtifactUpgradeConfig.RARITY_ORDER) do
	local rowData = UI.Rows[rarity]
	rowData.Button.MouseButton1Click:Connect(function()
		local ok, resultA, resultB = pcall(function()
			return CombineArtifacts:InvokeServer(rarity)
		end)

		if not ok then
			setStatus("Upgrade request failed.", Color3.fromRGB(245, 100, 100))
			return
		end

		local success = resultA
		local payload = resultB
		if not success then
			setStatus(tostring(payload or "Upgrade failed."), Color3.fromRGB(245, 100, 100))
			refreshState()
			return
		end

		local artifactName = payload and payload.newArtifact and payload.newArtifact.Name or "Artifact"
		local newRarity = payload and payload.newRarity or "Next"
		setStatus("Success: " .. artifactName .. " (" .. newRarity .. ")", getRarityColor(newRarity))
		showRewardToast(artifactName, newRarity)
		refreshState()
	end)
end

interactionRef = ShopInteraction.new({
	PromptTag = ArtifactUpgradeConfig.VENDOR_TAG,
	InteractionDist = ArtifactUpgradeConfig.VENDOR_DISTANCE,
	OnOpen = openUI,
	OnClose = closeUI,
})

UI.CloseButton.MouseButton1Click:Connect(function()
	if interactionRef then
		interactionRef:Close()
	else
		closeUI()
	end
end)

UIManager.RegisterShop("ArtifactUpgrade", function()
	if isOpen then
		if interactionRef then
			interactionRef:Close()
		else
			closeUI()
		end
	else
		if interactionRef then
			interactionRef:Open()
		else
			openUI()
		end
	end
end)

print("ArtifactUpgradeUI initialized")
