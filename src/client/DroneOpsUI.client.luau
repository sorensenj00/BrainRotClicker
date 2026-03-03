--[[
	DroneOpsUI Client Script

	Shop-inspired panel for targeted drone abilities.
	Opened via ProximityPrompt named "DroneKioskPrompt".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared:WaitForChild("UIConfig"))
local DroneOpsConfig = require(Shared:WaitForChild("DroneOpsConfig"))
local Utils = Shared:WaitForChild("Utils")
local UIUtils = require(Utils:WaitForChild("UIUtils"))

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local CastAbilityFunction = RemoteFunctions:WaitForChild("DroneOpsCastAbility")
local CooldownsFunction = RemoteFunctions:WaitForChild("DroneOpsGetCooldowns")

local state = {
	open = false,
	selectedAbility = "EMP",
	selectedSector = DroneOpsConfig.SECTORS[1],
	selectedTarget = nil,
	lastScoutLines = {},
}

local screenGui
local panel
local targetList
local sectorRow
local castButton
local scoutBox
local abilityButtons = {}
local targetButtons = {}

local function showToast(message, _typeKey, _duration)
	-- NotificationManager receives authoritative server notifications.
	-- For local validation feedback we keep this lightweight fallback.
	warn("DroneOpsUI:", message)
end

local function clearChildren(frame)
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function createLabel(parent, text, size, position, font, textSize, color)
	local lbl = Instance.new("TextLabel")
	lbl.Size = size
	lbl.Position = position
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.Font = font or Enum.Font.Gotham
	lbl.TextSize = textSize or 14
	lbl.TextColor3 = color or UIConfig.TEXT_COLOR
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.Parent = parent
	return lbl
end

local function getOnlineTargets()
	local rows = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			table.insert(rows, p)
		end
	end
	table.sort(rows, function(a, b)
		return string.lower(a.Name) < string.lower(b.Name)
	end)
	return rows
end

local function abilityNeedsSector(ability)
	return ability == "EMP" or ability == "OVERCLOCK"
end

local function setSelectedAbility(ability)
	state.selectedAbility = ability
	for name, button in pairs(abilityButtons) do
		local isActive = name == ability
		button.BackgroundColor3 = isActive and UIConfig.ACCENT_COLOR or UIConfig.CARD_COLOR
		button.TextColor3 = isActive and Color3.fromRGB(10, 10, 15) or UIConfig.TEXT_COLOR
	end
	if sectorRow then
		sectorRow.Visible = abilityNeedsSector(ability)
	end
end

local function getAbilityBaseLabel(ability)
	if ability == "EMP" then return "EMP" end
	if ability == "BLOCKADE" then return "BLOCKADE" end
	if ability == "SCOUT" then return "SCOUT" end
	if ability == "OVERCLOCK" then return "OVERCLOCK" end
	return ability
end

local function refreshCooldownLabels()
	if not screenGui or not state.open then return end
	local ok, data = pcall(function()
		return CooldownsFunction:InvokeServer()
	end)
	if not ok or type(data) ~= "table" then return end

	for ability, button in pairs(abilityButtons) do
		local remaining = tonumber(data[ability]) or 0
		local base = getAbilityBaseLabel(ability)
		if remaining > 0.1 then
			button.Text = string.format("%s (%.0fs)", base, math.ceil(remaining))
		else
			button.Text = base
		end
	end
end

local function setSelectedTarget(userId)
	state.selectedTarget = userId
	for id, button in pairs(targetButtons) do
		local isActive = (id == userId)
		button.BackgroundColor3 = isActive and Color3.fromRGB(90, 160, 255) or UIConfig.CARD_COLOR
		button.TextColor3 = isActive and Color3.fromRGB(10, 10, 15) or UIConfig.TEXT_COLOR
	end
end

local function refreshTargetList()
	if not targetList then return end
	clearChildren(targetList)
	table.clear(targetButtons)

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 6)
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = targetList

	local targets = getOnlineTargets()
	if #targets == 0 then
		local empty = createLabel(
			targetList,
			"No other players online",
			UDim2.new(1, 0, 0, 20),
			UDim2.new(0, 0, 0, 0),
			Enum.Font.Gotham,
			12,
			UIConfig.SECONDARY_TEXT_COLOR
		)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		return
	end

	for _, p in ipairs(targets) do
		local btn = Instance.new("TextButton")
		btn.Name = tostring(p.UserId)
		btn.Size = UDim2.new(1, 0, 0, 28)
		btn.BackgroundColor3 = UIConfig.CARD_COLOR
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = false
		btn.Text = p.Name
		btn.TextColor3 = UIConfig.TEXT_COLOR
		btn.TextSize = 12
		btn.Font = Enum.Font.GothamBold
		btn.Parent = targetList
		UIUtils.addCorner(btn, 7)
		UIUtils.addStroke(btn, UIConfig.SOFT_STROKE_COLOR, 1, 0.25)

		btn.MouseButton1Click:Connect(function()
			setSelectedTarget(p.UserId)
		end)
		targetButtons[p.UserId] = btn
	end

	-- Keep selection valid.
	if state.selectedTarget then
		local stillOnline = false
		for _, p in ipairs(targets) do
			if p.UserId == state.selectedTarget then
				stillOnline = true
				break
			end
		end
		if stillOnline then
			setSelectedTarget(state.selectedTarget)
		else
			state.selectedTarget = nil
		end
	end

	if not state.selectedTarget and targets[1] then
		setSelectedTarget(targets[1].UserId)
	end
end

local function updateScoutBox(lines)
	state.lastScoutLines = lines or {}
	if not scoutBox then return end
	if #state.lastScoutLines == 0 then
		scoutBox.Text = "Scout output appears here."
		scoutBox.TextColor3 = UIConfig.SECONDARY_TEXT_COLOR
	else
		scoutBox.Text = table.concat(state.lastScoutLines, "\n")
		scoutBox.TextColor3 = UIConfig.TEXT_COLOR
	end
end

local function formatScoutSnapshot(snapshot)
	local storageTotal = 0
	local cartTotal = 0
	for _, count in pairs(snapshot.storage or {}) do
		storageTotal += count
	end
	for _, count in pairs(snapshot.cart or {}) do
		cartTotal += count
	end

	local lines = {
		string.format("Target: %s", snapshot.targetName or "?"),
		string.format("Storage items: %d", storageTotal),
		string.format("Cart items: %d", cartTotal),
	}
	return lines
end

local function castSelectedAbility()
	if not state.selectedTarget then
		showToast("Select a target first.", "warning", 3)
		return
	end

	local payload = {
		ability = state.selectedAbility,
		targetUserId = state.selectedTarget,
	}
	if abilityNeedsSector(state.selectedAbility) then
		payload.sector = state.selectedSector
	end

	if castButton then
		castButton.Text = "SENDING..."
		castButton.Active = false
	end

	local ok, resultA, resultB = pcall(function()
		return CastAbilityFunction:InvokeServer(payload)
	end)

	if castButton then
		castButton.Text = "SEND DRONE"
		castButton.Active = true
	end

	if not ok then
		showToast("Drone request failed. Try again.", "error", 4)
		return
	end

	local success = resultA
	local data = resultB
	if not success then
		showToast(tostring(data or "Ability failed."), "error", 4)
		return
	end

	if state.selectedAbility == "SCOUT" and type(data) == "table" then
		updateScoutBox(formatScoutSnapshot(data))
	end
	refreshCooldownLabels()
end

local function createAbilityButton(parent, ability, label, order)
	local btn = Instance.new("TextButton")
	btn.Name = ability
	btn.LayoutOrder = order
	btn.Size = UDim2.new(0, 130, 0, 34)
	btn.BackgroundColor3 = UIConfig.CARD_COLOR
	btn.BorderSizePixel = 0
	btn.AutoButtonColor = false
	btn.Text = label
	btn.TextSize = 12
	btn.Font = Enum.Font.GothamBold
	btn.TextColor3 = UIConfig.TEXT_COLOR
	btn.Parent = parent
	UIUtils.addCorner(btn, 8)
	UIUtils.addStroke(btn, UIConfig.SOFT_STROKE_COLOR, 1, 0.2)

	btn.MouseButton1Click:Connect(function()
		setSelectedAbility(ability)
	end)
	abilityButtons[ability] = btn
	return btn
end

local function createSectorSelector(parent)
	local row = Instance.new("Frame")
	row.Name = "SectorRow"
	row.Size = UDim2.new(1, 0, 0, 36)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local title = createLabel(
		row,
		"SECTOR",
		UDim2.new(0, 80, 1, 0),
		UDim2.new(0, 0, 0, 0),
		Enum.Font.GothamBold,
		12,
		UIConfig.SECONDARY_TEXT_COLOR
	)
	title.TextYAlignment = Enum.TextYAlignment.Center

	local dropdown = Instance.new("TextButton")
	dropdown.Name = "SectorDropdown"
	dropdown.Size = UDim2.new(0, 180, 0, 30)
	dropdown.Position = UDim2.new(0, 90, 0, 3)
	dropdown.BackgroundColor3 = UIConfig.CARD_COLOR
	dropdown.BorderSizePixel = 0
	dropdown.TextColor3 = UIConfig.TEXT_COLOR
	dropdown.TextSize = 12
	dropdown.Font = Enum.Font.GothamBold
	dropdown.Text = "Sector: " .. tostring(state.selectedSector)
	dropdown.Parent = row
	UIUtils.addCorner(dropdown, 8)
	UIUtils.addStroke(dropdown, UIConfig.SOFT_STROKE_COLOR, 1, 0.2)

	local idx = 1
	for i, sector in ipairs(DroneOpsConfig.SECTORS) do
		if sector == state.selectedSector then
			idx = i
			break
		end
	end

	dropdown.MouseButton1Click:Connect(function()
		idx += 1
		if idx > #DroneOpsConfig.SECTORS then
			idx = 1
		end
		state.selectedSector = DroneOpsConfig.SECTORS[idx]
		dropdown.Text = "Sector: " .. tostring(state.selectedSector)
	end)

	return row
end

local function createUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DroneOpsUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	panel = Instance.new("Frame")
	panel.Name = "MainPanel"
	panel.Size = UDim2.new(0, 520, 0, 470)
	panel.Position = UDim2.new(0.5, -260, 0.5, -235)
	panel.BackgroundColor3 = UIConfig.PANEL_COLOR
	panel.BorderSizePixel = 0
	panel.Parent = screenGui
	UIUtils.addCorner(panel, 16)
	UIUtils.addStroke(panel, UIConfig.STROKE_COLOR, 1.8, 0.12)

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, UIConfig.PANEL_COLOR),
		ColorSequenceKeypoint.new(1, UIConfig.BACKGROUND_COLOR),
	})
	grad.Rotation = 90
	grad.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 62)
	header.BackgroundTransparency = 1
	header.Parent = panel

	local chip = Instance.new("Frame")
	chip.Size = UDim2.new(0, 280, 0, 44)
	chip.Position = UDim2.new(0, 12, 0, 10)
	chip.BackgroundColor3 = UIConfig.TITLE_CHIP_COLOR
	chip.BorderSizePixel = 0
	chip.Parent = header
	UIUtils.addCorner(chip, 9)
	UIUtils.addStroke(chip, UIConfig.TITLE_CHIP_STROKE, 1.2, 0.1)

	local title = createLabel(chip, "DRONE OPS", UDim2.new(1, -16, 1, 0), UDim2.new(0, 10, 0, 0), Enum.Font.GothamBlack, 23, UIConfig.TEXT_COLOR)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -50, 0, 11)
	closeBtn.BackgroundColor3 = UIConfig.RED_COLOR
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = UIConfig.TEXT_COLOR
	closeBtn.TextSize = 18
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = header
	UIUtils.addCorner(closeBtn, 9)
	UIUtils.addStroke(closeBtn, Color3.fromRGB(120, 20, 30), 1.2, 0.1)
	closeBtn.MouseButton1Click:Connect(function()
		state.open = false
		screenGui.Enabled = false
	end)

	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, -20, 1, -80)
	content.Position = UDim2.new(0, 10, 0, 70)
	content.BackgroundColor3 = UIConfig.CARD_INNER_COLOR
	content.BorderSizePixel = 0
	content.Parent = panel
	UIUtils.addCorner(content, 10)
	UIUtils.addStroke(content, UIConfig.SOFT_STROKE_COLOR, 1, 0.25)

	local abilitiesLabel = createLabel(content, "ABILITIES", UDim2.new(1, -20, 0, 18), UDim2.new(0, 10, 0, 10), Enum.Font.GothamBold, 12, UIConfig.SECONDARY_TEXT_COLOR)
	abilitiesLabel.TextXAlignment = Enum.TextXAlignment.Left

	local abilitiesRow = Instance.new("Frame")
	abilitiesRow.Size = UDim2.new(1, -20, 0, 82)
	abilitiesRow.Position = UDim2.new(0, 10, 0, 30)
	abilitiesRow.BackgroundTransparency = 1
	abilitiesRow.Parent = content
	local abilitiesLayout = Instance.new("UIGridLayout")
	abilitiesLayout.CellSize = UDim2.new(0, 130, 0, 34)
	abilitiesLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	abilitiesLayout.FillDirectionMaxCells = 3
	abilitiesLayout.SortOrder = Enum.SortOrder.LayoutOrder
	abilitiesLayout.Parent = abilitiesRow

	createAbilityButton(abilitiesRow, "EMP", "EMP", 1)
	createAbilityButton(abilitiesRow, "BLOCKADE", "BLOCKADE", 2)
	createAbilityButton(abilitiesRow, "SCOUT", "SCOUT", 3)
	createAbilityButton(abilitiesRow, "OVERCLOCK", "OVERCLOCK", 4)

	sectorRow = createSectorSelector(content)
	sectorRow.Position = UDim2.new(0, 10, 0, 120)

	local targetsLabel = createLabel(content, "TARGET PLAYER", UDim2.new(1, -20, 0, 18), UDim2.new(0, 10, 0, 164), Enum.Font.GothamBold, 12, UIConfig.SECONDARY_TEXT_COLOR)
	targetsLabel.TextXAlignment = Enum.TextXAlignment.Left

	targetList = Instance.new("ScrollingFrame")
	targetList.Name = "TargetList"
	targetList.Size = UDim2.new(0.48, -10, 0, 185)
	targetList.Position = UDim2.new(0, 10, 0, 184)
	targetList.BackgroundColor3 = UIConfig.CARD_COLOR
	targetList.BorderSizePixel = 0
	targetList.ScrollBarThickness = 4
	targetList.ScrollBarImageColor3 = UIConfig.ACCENT_COLOR
	targetList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	targetList.CanvasSize = UDim2.new(0, 0, 0, 0)
	targetList.Parent = content
	UIUtils.addCorner(targetList, 8)
	UIUtils.addStroke(targetList, UIConfig.SOFT_STROKE_COLOR, 1, 0.2)
	local targetPadding = Instance.new("UIPadding")
	targetPadding.PaddingLeft = UDim.new(0, 8)
	targetPadding.PaddingRight = UDim.new(0, 8)
	targetPadding.PaddingTop = UDim.new(0, 8)
	targetPadding.PaddingBottom = UDim.new(0, 8)
	targetPadding.Parent = targetList

	local scoutLabel = createLabel(content, "SCOUT RESULT", UDim2.new(0.48, -10, 0, 18), UDim2.new(0.52, 0, 0, 164), Enum.Font.GothamBold, 12, UIConfig.SECONDARY_TEXT_COLOR)
	scoutLabel.TextXAlignment = Enum.TextXAlignment.Left

	local scoutFrame = Instance.new("Frame")
	scoutFrame.Size = UDim2.new(0.48, -10, 0, 185)
	scoutFrame.Position = UDim2.new(0.52, 0, 0, 184)
	scoutFrame.BackgroundColor3 = UIConfig.CARD_COLOR
	scoutFrame.BorderSizePixel = 0
	scoutFrame.Parent = content
	UIUtils.addCorner(scoutFrame, 8)
	UIUtils.addStroke(scoutFrame, UIConfig.SOFT_STROKE_COLOR, 1, 0.2)

	scoutBox = Instance.new("TextLabel")
	scoutBox.Size = UDim2.new(1, -16, 1, -16)
	scoutBox.Position = UDim2.new(0, 8, 0, 8)
	scoutBox.BackgroundTransparency = 1
	scoutBox.TextXAlignment = Enum.TextXAlignment.Left
	scoutBox.TextYAlignment = Enum.TextYAlignment.Top
	scoutBox.TextWrapped = true
	scoutBox.Font = Enum.Font.RobotoMono
	scoutBox.TextSize = 12
	scoutBox.TextColor3 = UIConfig.SECONDARY_TEXT_COLOR
	scoutBox.Text = "Scout output appears here."
	scoutBox.Parent = scoutFrame

	castButton = Instance.new("TextButton")
	castButton.Name = "CastButton"
	castButton.Size = UDim2.new(1, -20, 0, 38)
	castButton.Position = UDim2.new(0, 10, 1, -48)
	castButton.BackgroundColor3 = UIConfig.BUTTON_COLOR
	castButton.BorderSizePixel = 0
	castButton.Text = "SEND DRONE"
	castButton.TextColor3 = UIConfig.TEXT_COLOR
	castButton.TextSize = 14
	castButton.Font = Enum.Font.GothamBold
	castButton.Parent = content
	UIUtils.addCorner(castButton, 9)
	UIUtils.addStroke(castButton, UIConfig.TITLE_CHIP_STROKE, 1, 0.2)
	castButton.MouseButton1Click:Connect(castSelectedAbility)
end

local function openUI()
	if not screenGui then
		createUI()
	end
	if state.open then return end
	state.open = true
	screenGui.Enabled = true
	refreshTargetList()
	updateScoutBox(state.lastScoutLines)
	setSelectedAbility(state.selectedAbility)
	refreshCooldownLabels()

	panel.Size = UDim2.new(0, 0, 0, 0)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	TweenService:Create(panel, UIConfig.TWEEN_INFO.Open, {
		Size = UDim2.new(0, 520, 0, 470),
		Position = UDim2.new(0.5, -260, 0.5, -235),
	}):Play()
end

local function closeUI()
	if not screenGui or not state.open then return end
	state.open = false
	local tween = TweenService:Create(panel, UIConfig.TWEEN_INFO.Close, {
		Size = UDim2.new(0, 0, 0, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
	})
	tween:Play()
	tween.Completed:Connect(function()
		if not state.open then
			screenGui.Enabled = false
		end
	end)
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	if prompt and prompt.Name == "DroneKioskPrompt" then
		openUI()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Escape and state.open then
		closeUI()
	end
end)

Players.PlayerAdded:Connect(function()
	if state.open then
		task.defer(refreshTargetList)
	end
end)

Players.PlayerRemoving:Connect(function()
	if state.open then
		task.defer(refreshTargetList)
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		if state.open then
			refreshCooldownLabels()
		end
	end
end)

