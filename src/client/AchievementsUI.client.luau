--[[
	AchievementsUI

	Simple achievements window with progress and claim actions.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")

local AchievementUpdatedEvent = RemoteEvents:WaitForChild("AchievementUpdated")
local GetAchievementsSnapshotFunction = RemoteFunctions:WaitForChild("GetAchievementsSnapshot")
local ClaimAchievementRewardFunction = RemoteFunctions:WaitForChild("ClaimAchievementReward")

local UIManager = require(script.Parent:WaitForChild("Managers"):WaitForChild("UIManager"))

local isOpen = false
local screenGui = nil
local mainFrame = nil
local listFrame = nil
local statusLabel = nil

local latestSnapshot = {
	Definitions = {},
	State = {
		Progress = {},
		Unlocked = {},
		Claimed = {},
	},
}

local function formatMoney(amount)
	return "$" .. tostring(math.floor(amount or 0))
end

local function formatRewardList(def)
	local rewards = def.Rewards or {}
	if #rewards == 0 then
		return "No reward"
	end
	local parts = {}
	for _, reward in ipairs(rewards) do
		if reward.Type == "money" then
			table.insert(parts, formatMoney(reward.Amount or 0))
		elseif reward.Type == "braincells" then
			table.insert(parts, string.format("%d Braincells", math.floor(reward.Amount or 0)))
		elseif reward.Type == "title" then
			table.insert(parts, "Title: " .. tostring(reward.Value or ""))
		elseif reward.Type == "artifact" then
			table.insert(parts, tostring(reward.Value or "Artifact"))
		elseif reward.Type == "permanent_buff" then
			table.insert(parts, tostring(reward.Value or "Permanent buff"))
		end
	end
	return table.concat(parts, " + ")
end

local function hasClaimableCoreReward(def)
	local rewards = def.Rewards or {}
	for _, reward in ipairs(rewards) do
		if reward.AdvancedPending ~= true then
			return true
		end
	end
	return false
end

local function sortDefinitions(definitions)
	table.sort(definitions, function(a, b)
		local orderA = a.Order or 9999
		local orderB = b.Order or 9999
		if orderA ~= orderB then
			return orderA < orderB
		end
		return tostring(a.Title) < tostring(b.Title)
	end)
end

local function clearList()
	if not listFrame then
		return
	end
	for _, child in ipairs(listFrame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function buildStatusText(def, stateData)
	local id = def.Id
	local progress = math.floor((stateData.Progress and stateData.Progress[id]) or 0)
	local target = math.max(1, math.floor(def.TargetValue or 1))
	local unlocked = stateData.Unlocked and stateData.Unlocked[id]
	local claimed = stateData.Claimed and stateData.Claimed[id]
	local ratio = math.clamp(progress / target, 0, 1)

	local status = "Locked"
	if claimed then
		status = "Claimed"
	elseif unlocked then
		status = "Unlocked"
	end

	return progress, target, ratio, status, unlocked, claimed
end

local function claimAchievement(achievementId)
	local success, ok, message = pcall(function()
		return ClaimAchievementRewardFunction:InvokeServer(achievementId)
	end)

	if not success then
		if statusLabel then
			statusLabel.Text = "Claim failed: server error"
		end
		return
	end

	if ok then
		if statusLabel then
			statusLabel.Text = "Reward claimed!"
		end
	else
		if statusLabel then
			statusLabel.Text = "Claim failed: " .. tostring(message or "unknown")
		end
	end
end

local function rebuildList()
	if not listFrame then return end
	clearList()

	local definitions = {}
	for _, def in ipairs(latestSnapshot.Definitions or {}) do
		table.insert(definitions, def)
	end
	sortDefinitions(definitions)

	if #definitions == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -12, 0, 36)
		empty.BackgroundTransparency = 1
		empty.Text = "No achievements configured yet."
		empty.TextColor3 = Color3.fromRGB(185, 185, 205)
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 14
		empty.Parent = listFrame
		return
	end

	for i, def in ipairs(definitions) do
		local progress, target, ratio, status, unlocked, claimed = buildStatusText(def, latestSnapshot.State or {})

		local card = Instance.new("Frame")
		card.Name = "Achievement_" .. tostring(def.Id)
		card.Size = UDim2.new(1, -12, 0, 110)
		card.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.Parent = listFrame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = card

		local stroke = Instance.new("UIStroke")
		stroke.Color = claimed and Color3.fromRGB(80, 220, 120) or (unlocked and Color3.fromRGB(245, 195, 75) or Color3.fromRGB(90, 90, 120))
		stroke.Transparency = 0.2
		stroke.Parent = card

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -16, 0, 20)
		title.Position = UDim2.fromOffset(8, 6)
		title.BackgroundTransparency = 1
		title.Text = tostring(def.Title or def.Id)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = Color3.fromRGB(235, 235, 245)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 14
		title.Parent = card

		local description = Instance.new("TextLabel")
		description.Size = UDim2.new(1, -16, 0, 18)
		description.Position = UDim2.fromOffset(8, 28)
		description.BackgroundTransparency = 1
		description.Text = tostring(def.Description or "")
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.TextColor3 = Color3.fromRGB(170, 170, 190)
		description.Font = Enum.Font.Gotham
		description.TextSize = 12
		description.Parent = card

		local progressLabel = Instance.new("TextLabel")
		progressLabel.Size = UDim2.new(1, -140, 0, 16)
		progressLabel.Position = UDim2.fromOffset(8, 50)
		progressLabel.BackgroundTransparency = 1
		progressLabel.Text = string.format("%d / %d", progress, target)
		progressLabel.TextXAlignment = Enum.TextXAlignment.Left
		progressLabel.TextColor3 = Color3.fromRGB(205, 205, 220)
		progressLabel.Font = Enum.Font.GothamBold
		progressLabel.TextSize = 12
		progressLabel.Parent = card

		local statusText = Instance.new("TextLabel")
		statusText.Size = UDim2.fromOffset(120, 16)
		statusText.Position = UDim2.new(1, -128, 0, 50)
		statusText.BackgroundTransparency = 1
		statusText.Text = status
		statusText.TextXAlignment = Enum.TextXAlignment.Right
		statusText.TextColor3 = claimed and Color3.fromRGB(100, 230, 130) or (unlocked and Color3.fromRGB(255, 210, 90) or Color3.fromRGB(170, 170, 190))
		statusText.Font = Enum.Font.GothamBold
		statusText.TextSize = 11
		statusText.Parent = card

		local barBg = Instance.new("Frame")
		barBg.Size = UDim2.new(1, -16, 0, 10)
		barBg.Position = UDim2.fromOffset(8, 70)
		barBg.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
		barBg.BorderSizePixel = 0
		barBg.Parent = card
		local barBgCorner = Instance.new("UICorner")
		barBgCorner.CornerRadius = UDim.new(0, 6)
		barBgCorner.Parent = barBg

		local barFill = Instance.new("Frame")
		barFill.Size = UDim2.fromScale(ratio, 1)
		barFill.BackgroundColor3 = claimed and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(80, 155, 255)
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 6)
		fillCorner.Parent = barFill

		local rewardText = Instance.new("TextLabel")
		rewardText.Size = UDim2.new(0.6, -8, 0, 20)
		rewardText.Position = UDim2.fromOffset(8, 86)
		rewardText.BackgroundTransparency = 1
		rewardText.Text = "Reward: " .. formatRewardList(def)
		rewardText.TextXAlignment = Enum.TextXAlignment.Left
		rewardText.TextColor3 = Color3.fromRGB(100, 230, 130)
		rewardText.Font = Enum.Font.GothamBold
		rewardText.TextSize = 11
		rewardText.TextTruncate = Enum.TextTruncate.AtEnd
		rewardText.Parent = card

		local claimButton = Instance.new("TextButton")
		claimButton.Size = UDim2.fromOffset(96, 22)
		claimButton.Position = UDim2.new(1, -104, 0, 84)
		claimButton.TextSize = 11
		claimButton.Font = Enum.Font.GothamBold
		claimButton.BorderSizePixel = 0
		claimButton.Parent = card
		local claimCorner = Instance.new("UICorner")
		claimCorner.CornerRadius = UDim.new(0, 6)
		claimCorner.Parent = claimButton

		if claimed then
			claimButton.Text = "Claimed"
			claimButton.BackgroundColor3 = Color3.fromRGB(55, 95, 60)
			claimButton.TextColor3 = Color3.fromRGB(180, 240, 190)
			claimButton.AutoButtonColor = false
			claimButton.Active = false
		elseif unlocked then
			if hasClaimableCoreReward(def) then
				claimButton.Text = "Claim"
				claimButton.BackgroundColor3 = Color3.fromRGB(60, 145, 85)
				claimButton.TextColor3 = Color3.new(1, 1, 1)
				claimButton.AutoButtonColor = true
				claimButton.MouseButton1Click:Connect(function()
					claimAchievement(def.Id)
				end)
			else
				claimButton.Text = "Phase 3"
				claimButton.BackgroundColor3 = Color3.fromRGB(80, 70, 100)
				claimButton.TextColor3 = Color3.fromRGB(210, 200, 240)
				claimButton.AutoButtonColor = false
				claimButton.Active = false
			end
		else
			claimButton.Text = "Locked"
			claimButton.BackgroundColor3 = Color3.fromRGB(65, 65, 85)
			claimButton.TextColor3 = Color3.fromRGB(165, 165, 185)
			claimButton.AutoButtonColor = false
			claimButton.Active = false
		end
	end
end

local function createUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AchievementsUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 18
	screenGui.Enabled = false
	screenGui.Parent = PlayerGui

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = screenGui

	mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromOffset(640, 520)
	mainFrame.Position = UDim2.new(0.5, -320, 0.5, -260)
	mainFrame.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui

	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 10)
	frameCorner.Parent = mainFrame

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Color3.fromRGB(110, 110, 150)
	frameStroke.Transparency = 0.2
	frameStroke.Parent = mainFrame

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 42)
	header.BackgroundColor3 = Color3.fromRGB(22, 22, 34)
	header.BorderSizePixel = 0
	header.Parent = mainFrame
	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 10)
	headerCorner.Parent = header

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.fromOffset(12, 0)
	title.BackgroundTransparency = 1
	title.Text = "ACHIEVEMENTS"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(245, 220, 120)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 20
	title.Parent = header

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.fromOffset(30, 30)
	closeButton.Position = UDim2.new(1, -38, 0, 6)
	closeButton.BackgroundColor3 = Color3.fromRGB(70, 35, 35)
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(255, 150, 150)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 16
	closeButton.Parent = header
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeButton

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "List"
	listFrame.Size = UDim2.new(1, -20, 1, -96)
	listFrame.Position = UDim2.fromOffset(10, 50)
	listFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 6
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.Parent = mainFrame
	local listCorner = Instance.new("UICorner")
	listCorner.CornerRadius = UDim.new(0, 8)
	listCorner.Parent = listFrame

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = listFrame

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 6)
	listPadding.PaddingBottom = UDim.new(0, 6)
	listPadding.PaddingLeft = UDim.new(0, 6)
	listPadding.PaddingRight = UDim.new(0, 6)
	listPadding.Parent = listFrame

	statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -20, 0, 20)
	statusLabel.Position = UDim2.new(0, 10, 1, -30)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = ""
	statusLabel.TextColor3 = Color3.fromRGB(175, 175, 195)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 12
	statusLabel.Parent = mainFrame

	closeButton.MouseButton1Click:Connect(function()
		isOpen = false
		screenGui.Enabled = false
	end)

	backdrop.MouseButton1Click:Connect(function()
		isOpen = false
		screenGui.Enabled = false
	end)
end

local function refreshSnapshot()
	local ok, data = pcall(function()
		return GetAchievementsSnapshotFunction:InvokeServer()
	end)
	if ok and type(data) == "table" then
		latestSnapshot = data
		rebuildList()
	end
end

local function openUI()
	if not screenGui then
		createUI()
	end
	isOpen = true
	screenGui.Enabled = true

	mainFrame.Size = UDim2.fromOffset(620, 500)
	TweenService:Create(mainFrame, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(640, 520),
	}):Play()

	refreshSnapshot()
end

local function toggleUI()
	if isOpen then
		isOpen = false
		if screenGui then
			screenGui.Enabled = false
		end
	else
		openUI()
	end
end

local achievementsToggleEvent = ReplicatedStorage:FindFirstChild("AchievementsToggleEvent")
if not achievementsToggleEvent then
	achievementsToggleEvent = Instance.new("BindableEvent")
	achievementsToggleEvent.Name = "AchievementsToggleEvent"
	achievementsToggleEvent.Parent = ReplicatedStorage
end

achievementsToggleEvent.Event:Connect(toggleUI)
UIManager.RegisterShop("Achievements", toggleUI)

AchievementUpdatedEvent.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	latestSnapshot = snapshot
	if isOpen then
		rebuildList()
	end
end)

