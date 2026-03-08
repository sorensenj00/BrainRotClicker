local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ClientPlotService = require(script.Parent:WaitForChild("ClientPlotService"))

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local GetAchievementsSnapshotFunction = RemoteFunctions:WaitForChild("GetAchievementsSnapshot")
local AchievementUpdatedEvent = RemoteEvents:WaitForChild("AchievementUpdated")

local LatestAchievementSnapshot = {
	Definitions = {},
	State = {
		Progress = {},
		Unlocked = {},
		Claimed = {},
	},
}

local GUIDE_COLORS = {
	Panel = Color3.fromRGB(14, 28, 54),
	PanelBorder = Color3.fromRGB(74, 220, 255),
	Accent = Color3.fromRGB(255, 215, 92),
	TextPrimary = Color3.fromRGB(255, 255, 255),
	TextSecondary = Color3.fromRGB(205, 225, 255),
	WorldMarker = Color3.fromRGB(84, 245, 255),
	ButtonMarker = Color3.fromRGB(255, 220, 92),
}

local GuideGui = Instance.new("ScreenGui")
GuideGui.Name = "OnboardingGuide"
GuideGui.ResetOnSpawn = false
GuideGui.DisplayOrder = 210
GuideGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GuideGui.Parent = PlayerGui

local Banner = Instance.new("Frame")
Banner.Name = "Banner"
Banner.Size = UDim2.new(0, 420, 0, 96)
Banner.AnchorPoint = Vector2.new(0.5, 0)
Banner.Position = UDim2.new(0.5, 0, 0, 18)
Banner.BackgroundColor3 = GUIDE_COLORS.Panel
Banner.BackgroundTransparency = 0.1
Banner.BorderSizePixel = 0
Banner.Parent = GuideGui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 14)
bannerCorner.Parent = Banner

local bannerStroke = Instance.new("UIStroke")
bannerStroke.Color = GUIDE_COLORS.PanelBorder
bannerStroke.Thickness = 2
bannerStroke.Transparency = 0.15
bannerStroke.Parent = Banner

local bannerPadding = Instance.new("UIPadding")
bannerPadding.PaddingLeft = UDim.new(0, 14)
bannerPadding.PaddingRight = UDim.new(0, 14)
bannerPadding.PaddingTop = UDim.new(0, 10)
bannerPadding.PaddingBottom = UDim.new(0, 10)
bannerPadding.Parent = Banner

local bannerHeader = Instance.new("TextLabel")
bannerHeader.Name = "Header"
bannerHeader.Size = UDim2.new(1, 0, 0, 16)
bannerHeader.BackgroundTransparency = 1
bannerHeader.Text = "NEXT STEP"
bannerHeader.TextColor3 = GUIDE_COLORS.Accent
bannerHeader.TextSize = 11
bannerHeader.Font = Enum.Font.GothamBold
bannerHeader.TextXAlignment = Enum.TextXAlignment.Left
bannerHeader.Parent = Banner

local bannerTitle = Instance.new("TextLabel")
bannerTitle.Name = "Title"
bannerTitle.Size = UDim2.new(1, 0, 0, 28)
bannerTitle.Position = UDim2.new(0, 0, 0, 18)
bannerTitle.BackgroundTransparency = 1
bannerTitle.Text = "Buy Your First Unit"
bannerTitle.TextColor3 = GUIDE_COLORS.TextPrimary
bannerTitle.TextSize = 22
bannerTitle.Font = Enum.Font.GothamBold
bannerTitle.TextWrapped = true
bannerTitle.TextXAlignment = Enum.TextXAlignment.Left
bannerTitle.Parent = Banner

local bannerBody = Instance.new("TextLabel")
bannerBody.Name = "Body"
bannerBody.Size = UDim2.new(1, 0, 0, 18)
bannerBody.Position = UDim2.new(0, 0, 0, 50)
bannerBody.BackgroundTransparency = 1
bannerBody.Text = "Go to the Brainrot Shop on the main island."
bannerBody.TextColor3 = GUIDE_COLORS.TextSecondary
bannerBody.TextSize = 13
bannerBody.Font = Enum.Font.GothamMedium
bannerBody.TextWrapped = true
bannerBody.TextXAlignment = Enum.TextXAlignment.Left
bannerBody.Parent = Banner

local bannerHint = Instance.new("TextLabel")
bannerHint.Name = "Hint"
bannerHint.Size = UDim2.new(1, 0, 0, 16)
bannerHint.Position = UDim2.new(0, 0, 0, 69)
bannerHint.BackgroundTransparency = 1
bannerHint.Text = "Follow the marker."
bannerHint.TextColor3 = GUIDE_COLORS.Accent
bannerHint.TextSize = 12
bannerHint.Font = Enum.Font.GothamBold
bannerHint.TextWrapped = true
bannerHint.TextXAlignment = Enum.TextXAlignment.Left
bannerHint.Parent = Banner

local EdgeArrow = Instance.new("TextLabel")
EdgeArrow.Name = "EdgeArrow"
EdgeArrow.Size = UDim2.new(0, 54, 0, 54)
EdgeArrow.AnchorPoint = Vector2.new(0.5, 0.5)
EdgeArrow.BackgroundTransparency = 0.12
EdgeArrow.BackgroundColor3 = GUIDE_COLORS.Panel
EdgeArrow.Text = "^"
EdgeArrow.TextColor3 = GUIDE_COLORS.Accent
EdgeArrow.TextSize = 28
EdgeArrow.Font = Enum.Font.GothamBold
EdgeArrow.Visible = false
EdgeArrow.ZIndex = 12
EdgeArrow.Parent = GuideGui

local edgeCorner = Instance.new("UICorner")
edgeCorner.CornerRadius = UDim.new(1, 0)
edgeCorner.Parent = EdgeArrow

local edgeStroke = Instance.new("UIStroke")
edgeStroke.Color = GUIDE_COLORS.PanelBorder
edgeStroke.Thickness = 2
edgeStroke.Transparency = 0.18
edgeStroke.Parent = EdgeArrow

local EdgeLabel = Instance.new("TextLabel")
EdgeLabel.Name = "EdgeLabel"
EdgeLabel.Size = UDim2.new(0, 190, 0, 22)
EdgeLabel.AnchorPoint = Vector2.new(0.5, 0)
EdgeLabel.BackgroundTransparency = 1
EdgeLabel.Text = ""
EdgeLabel.TextColor3 = GUIDE_COLORS.TextPrimary
EdgeLabel.TextSize = 13
EdgeLabel.Font = Enum.Font.GothamBold
EdgeLabel.Visible = false
EdgeLabel.ZIndex = 12
EdgeLabel.Parent = GuideGui

local ButtonPointer = Instance.new("Frame")
ButtonPointer.Name = "ButtonPointer"
ButtonPointer.Size = UDim2.new(0, 110, 0, 52)
ButtonPointer.BackgroundTransparency = 1
ButtonPointer.Visible = false
ButtonPointer.ZIndex = 14
ButtonPointer.Parent = GuideGui

local ButtonArrow = Instance.new("TextLabel")
ButtonArrow.Name = "Arrow"
ButtonArrow.Size = UDim2.new(1, 0, 0, 18)
ButtonArrow.BackgroundTransparency = 1
ButtonArrow.Text = "v"
ButtonArrow.TextColor3 = GUIDE_COLORS.Accent
ButtonArrow.TextSize = 18
ButtonArrow.Font = Enum.Font.GothamBold
ButtonArrow.Parent = ButtonPointer

local ButtonCallout = Instance.new("TextLabel")
ButtonCallout.Name = "Callout"
ButtonCallout.Size = UDim2.new(1, 0, 0, 22)
ButtonCallout.Position = UDim2.new(0, 0, 0, 18)
ButtonCallout.BackgroundColor3 = GUIDE_COLORS.Panel
ButtonCallout.BackgroundTransparency = 0.08
ButtonCallout.Text = "TAP BUILD"
ButtonCallout.TextColor3 = GUIDE_COLORS.TextPrimary
ButtonCallout.TextSize = 12
ButtonCallout.Font = Enum.Font.GothamBold
ButtonCallout.Parent = ButtonPointer

local buttonCalloutCorner = Instance.new("UICorner")
buttonCalloutCorner.CornerRadius = UDim.new(0, 10)
buttonCalloutCorner.Parent = ButtonCallout

local buttonCalloutStroke = Instance.new("UIStroke")
buttonCalloutStroke.Color = GUIDE_COLORS.ButtonMarker
buttonCalloutStroke.Thickness = 2
buttonCalloutStroke.Parent = ButtonCallout

local ButtonRing = Instance.new("Frame")
ButtonRing.Name = "ButtonRing"
ButtonRing.AnchorPoint = Vector2.new(0.5, 0.5)
ButtonRing.Size = UDim2.new(0, 132, 0, 56)
ButtonRing.BackgroundTransparency = 1
ButtonRing.Visible = false
ButtonRing.ZIndex = 13
ButtonRing.Parent = GuideGui

local buttonRingStroke = Instance.new("UIStroke")
buttonRingStroke.Color = GUIDE_COLORS.ButtonMarker
buttonRingStroke.Thickness = 3
buttonRingStroke.Transparency = 0.15
buttonRingStroke.Parent = ButtonRing

local buttonRingCorner = Instance.new("UICorner")
buttonRingCorner.CornerRadius = UDim.new(1, 0)
buttonRingCorner.Parent = ButtonRing

local WorldBillboard = Instance.new("BillboardGui")
WorldBillboard.Name = "WorldMarker"
WorldBillboard.Size = UDim2.new(0, 156, 0, 70)
WorldBillboard.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
WorldBillboard.AlwaysOnTop = true
WorldBillboard.Enabled = false
WorldBillboard.Parent = PlayerGui

local worldBadge = Instance.new("Frame")
worldBadge.Name = "Badge"
worldBadge.Size = UDim2.new(1, 0, 1, 0)
worldBadge.BackgroundColor3 = GUIDE_COLORS.Panel
worldBadge.BackgroundTransparency = 0.1
worldBadge.BorderSizePixel = 0
worldBadge.Parent = WorldBillboard

local worldBadgeCorner = Instance.new("UICorner")
worldBadgeCorner.CornerRadius = UDim.new(0, 12)
worldBadgeCorner.Parent = worldBadge

local worldBadgeStroke = Instance.new("UIStroke")
worldBadgeStroke.Color = GUIDE_COLORS.WorldMarker
worldBadgeStroke.Thickness = 2
worldBadgeStroke.Transparency = 0.08
worldBadgeStroke.Parent = worldBadge

local worldArrow = Instance.new("TextLabel")
worldArrow.Name = "Arrow"
worldArrow.Size = UDim2.new(1, 0, 0, 24)
worldArrow.BackgroundTransparency = 1
worldArrow.Text = "GO"
worldArrow.TextColor3 = GUIDE_COLORS.Accent
worldArrow.TextSize = 18
worldArrow.Font = Enum.Font.GothamBold
worldArrow.Parent = worldBadge

local worldTitle = Instance.new("TextLabel")
worldTitle.Name = "Title"
worldTitle.Size = UDim2.new(1, -10, 0, 20)
worldTitle.Position = UDim2.new(0, 5, 0, 24)
worldTitle.BackgroundTransparency = 1
worldTitle.Text = "Brainrot Shop"
worldTitle.TextColor3 = GUIDE_COLORS.TextPrimary
worldTitle.TextSize = 14
worldTitle.Font = Enum.Font.GothamBold
worldTitle.TextWrapped = true
worldTitle.Parent = worldBadge

local worldBody = Instance.new("TextLabel")
worldBody.Name = "Body"
worldBody.Size = UDim2.new(1, -10, 0, 18)
worldBody.Position = UDim2.new(0, 5, 0, 46)
worldBody.BackgroundTransparency = 1
worldBody.Text = "Go here"
worldBody.TextColor3 = GUIDE_COLORS.TextSecondary
worldBody.TextSize = 11
worldBody.Font = Enum.Font.GothamMedium
worldBody.TextWrapped = true
worldBody.Parent = worldBadge

local WorldHighlight = Instance.new("Highlight")
WorldHighlight.Name = "OnboardingHighlight"
WorldHighlight.Enabled = false
WorldHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
WorldHighlight.FillColor = GUIDE_COLORS.WorldMarker
WorldHighlight.FillTransparency = 0.78
WorldHighlight.OutlineColor = GUIDE_COLORS.Accent
WorldHighlight.OutlineTransparency = 0.05
WorldHighlight.Parent = Workspace

type GuideTarget = {
	kind: "world" | "button",
	buttonName: string?,
	buttonCallout: string?,
	worldPart: BasePart?,
	highlightAdornee: Instance?,
	worldLabel: string?,
	worldBody: string?,
	title: string,
	description: string,
	hint: string,
}

local FALLBACK_ONBOARDING_TEXT = {
	[1] = {
		Title = "Buy Your First Unit",
		Description = "Pick up your first Brainrot.",
	},
	[2] = {
		Title = "Place Your First Unit",
		Description = "Drop your first Brainrot onto the grid.",
	},
	[3] = {
		Title = "Produce Your First Batch",
		Description = "Let your setup produce 20 items.",
	},
	[4] = {
		Title = "Cash Out Once",
		Description = "Sell your stored stock once.",
	},
	[5] = {
		Title = "Reinvest Profits",
		Description = "Buy a second unit to grow your setup.",
	},
}

local currentGuideTarget: GuideTarget? = nil
local currentButtonTarget: GuiObject? = nil
local timeAccumulator = 0
local lastGuideStateKey = ""

local function getObjectiveDefinitionForStage(stage: number)
	local order = math.clamp(stage + 1, 1, 5)
	for _, definition in ipairs(LatestAchievementSnapshot.Definitions or {}) do
		if tonumber(definition.OnboardingOrder) == order then
			return definition
		end
	end
	return FALLBACK_ONBOARDING_TEXT[order]
end

local function getBasePart(instance: Instance?): BasePart?
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart
			or instance:FindFirstChild("Root")
			or instance:FindFirstChild("MainPlatform")
			or instance:FindFirstChildWhichIsA("BasePart", true)
	end
	if instance:IsA("ProximityPrompt") then
		local parent = instance.Parent
		if parent and parent:IsA("Attachment") then
			parent = parent.Parent
		end
		if parent and parent:IsA("BasePart") then
			return parent
		end
		if instance.Adornee and instance.Adornee:IsA("BasePart") then
			return instance.Adornee
		end
	end
	return nil
end

local function isBuildModeOpen(): boolean
	return PlayerGui:FindFirstChild("BuildModeUI") ~= nil
end

local function findMoneyHUDButton(buttonName: string): GuiObject?
	local moneyHud = PlayerGui:FindFirstChild("MoneyHUD")
	if not moneyHud then
		return nil
	end
	local bottomBar = moneyHud:FindFirstChild("BottomBar")
	if not bottomBar then
		return nil
	end
	local buttonsFrame = bottomBar:FindFirstChild("ButtonsFrame")
	if not buttonsFrame then
		return nil
	end
	local button = buttonsFrame:FindFirstChild(buttonName)
	if button and button:IsA("GuiObject") and button.Visible then
		return button
	end
	return nil
end

local function getUnitShopTarget()
	local mainIsland = Workspace:FindFirstChild("MainIsland")
	if not mainIsland then
		return nil, nil
	end
	local shops = mainIsland:FindFirstChild("Shops")
	local unitShop = shops and shops:FindFirstChild("UnitShop")
	if unitShop then
		local prompt = unitShop:FindFirstChild("ShopPrompt", true)
		local part = getBasePart(prompt or unitShop)
		return part, unitShop
	end
	return getBasePart(mainIsland), mainIsland
end

local function getPlayerPlotTarget()
	local plot = ClientPlotService.GetMyPlot()
	if not plot then
		return nil, nil
	end
	local part = getBasePart(plot:FindFirstChild("MainPlatform") or plot:FindFirstChild("Root") or plot)
	return part, plot
end

local function getFirstOwnedUnitTarget()
	local bestUnit = nil
	local bestSlot = math.huge
	for _, unit in ipairs(CollectionService:GetTagged("ActiveBrainrot")) do
		if unit:GetAttribute("OwnerId") == Player.UserId then
			local slot = tonumber(unit:GetAttribute("GridSlot")) or math.huge
			if slot < bestSlot then
				bestSlot = slot
				bestUnit = unit
			end
		end
	end
	if not bestUnit then
		return nil, nil
	end
	return getBasePart(bestUnit), bestUnit
end

local function getCurrentGuideTarget(): GuideTarget?
	if Player:GetAttribute("TutorialComplete") == true then
		return nil
	end

	local stage = tonumber(Player:GetAttribute("OnboardingStage")) or 0
	local objective = getObjectiveDefinitionForStage(stage)
	local title = objective and objective.Title or "Next Step"
	local description = objective and objective.Description or "Follow the guide."

	if stage <= 0 then
		local part, highlightAdornee = getUnitShopTarget()
		return {
			kind = "world",
			worldPart = part,
			highlightAdornee = highlightAdornee,
			worldLabel = "Brainrot Shop",
			worldBody = "Buy your first unit here.",
			title = title,
			description = "Go to the Brainrot Shop on the main island.",
			hint = description,
		}
	elseif stage == 1 then
		if not isBuildModeOpen() then
			return {
				kind = "button",
				buttonName = "BuildButton",
				buttonCallout = "TAP BUILD",
				title = title,
				description = "Open Build so you can place your first unit.",
				hint = "Then place it on your plot.",
			}
		end

		local part, highlightAdornee = getPlayerPlotTarget()
		return {
			kind = "world",
			worldPart = part,
			highlightAdornee = highlightAdornee,
			worldLabel = "Your Plot",
			worldBody = "Place your first unit here.",
			title = title,
			description = "Place your first unit on your plot.",
			hint = "Drop it anywhere inside the build area.",
		}
	elseif stage == 2 then
		local part, highlightAdornee = getFirstOwnedUnitTarget()
		if not part then
			part, highlightAdornee = getPlayerPlotTarget()
		end
		return {
			kind = "world",
			worldPart = part,
			highlightAdornee = highlightAdornee,
			worldLabel = "Your Producer",
			worldBody = "Let it make 20 items.",
			title = title,
			description = "Let your first producer build up stock.",
			hint = description,
		}
	elseif stage == 3 then
		return {
			kind = "button",
			buttonName = "StockButton",
			buttonCallout = "TAP SELL",
			title = title,
			description = "Cash out your first stock when you are ready.",
			hint = "Use Sell once to lock in the payout.",
		}
	else
		local part, highlightAdornee = getUnitShopTarget()
		return {
			kind = "world",
			worldPart = part,
			highlightAdornee = highlightAdornee,
			worldLabel = "Brainrot Shop",
			worldBody = "Buy one more unit.",
			title = title,
			description = "Reinvest at the Brainrot Shop.",
			hint = description,
		}
	end
end

local function hideWorldTarget()
	WorldBillboard.Enabled = false
	WorldBillboard.Adornee = nil
	WorldHighlight.Enabled = false
	WorldHighlight.Adornee = nil
	EdgeArrow.Visible = false
	EdgeLabel.Visible = false
end

local function hideButtonTarget()
	ButtonPointer.Visible = false
	ButtonRing.Visible = false
	currentButtonTarget = nil
end

local function applyGuideTarget(target: GuideTarget?)
	currentGuideTarget = target
	if not target then
		Banner.Visible = false
		hideWorldTarget()
		hideButtonTarget()
		return
	end

	Banner.Visible = true
	bannerTitle.Text = target.title
	bannerBody.Text = target.description
	bannerHint.Text = target.hint

	hideWorldTarget()
	hideButtonTarget()

	if target.kind == "world" then
		if target.worldPart then
			WorldBillboard.Enabled = true
			WorldBillboard.Adornee = target.worldPart
			worldTitle.Text = target.worldLabel or "Go Here"
			worldBody.Text = target.worldBody or ""
		end
		if target.highlightAdornee then
			WorldHighlight.Adornee = target.highlightAdornee
			WorldHighlight.Enabled = true
		end
	elseif target.kind == "button" and target.buttonName then
		currentButtonTarget = findMoneyHUDButton(target.buttonName)
		ButtonCallout.Text = target.buttonCallout or "TAP HERE"
		ButtonPointer.Visible = currentButtonTarget ~= nil
		ButtonRing.Visible = currentButtonTarget ~= nil
	end

	local stage = tonumber(Player:GetAttribute("OnboardingStage")) or 0
	local targetKey = string.format("%s:%s:%s", stage, target.kind, target.buttonName or (target.worldLabel or ""))
	if targetKey ~= lastGuideStateKey then
		lastGuideStateKey = targetKey
	end
end

local function refreshGuideTarget()
	applyGuideTarget(getCurrentGuideTarget())
end

local function updateWorldTargetVisuals(now: number)
	if not currentGuideTarget or currentGuideTarget.kind ~= "world" or not currentGuideTarget.worldPart then
		EdgeArrow.Visible = false
		EdgeLabel.Visible = false
		return
	end

	WorldBillboard.StudsOffsetWorldSpace = Vector3.new(0, 8 + (math.sin(now * 3) * 0.35), 0)
	WorldHighlight.FillTransparency = 0.7 + (math.sin(now * 3) * 0.06)

	local camera = Workspace.CurrentCamera
	if not camera then
		EdgeArrow.Visible = false
		EdgeLabel.Visible = false
		return
	end

	local viewportSize = camera.ViewportSize
	local worldPos = currentGuideTarget.worldPart.Position + Vector3.new(0, 6, 0)
	local screenPos, onScreen = camera:WorldToViewportPoint(worldPos)
	local inFront = screenPos.Z > 0
	local margin = 72

	if onScreen
		and inFront
		and screenPos.X >= margin
		and screenPos.X <= viewportSize.X - margin
		and screenPos.Y >= margin
		and screenPos.Y <= viewportSize.Y - margin
	then
		EdgeArrow.Visible = false
		EdgeLabel.Visible = false
		return
	end

	local center = Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.5)
	local direction = Vector2.new(screenPos.X - center.X, screenPos.Y - center.Y)
	if not inFront then
		direction = -direction
	end
	if direction.Magnitude < 0.001 then
		direction = Vector2.new(0, -1)
	end
	direction = direction.Unit

	local scaleX = (center.X - margin) / math.max(math.abs(direction.X), 0.001)
	local scaleY = (center.Y - margin) / math.max(math.abs(direction.Y), 0.001)
	local edgePos = center + direction * math.min(scaleX, scaleY)

	EdgeArrow.Visible = true
	EdgeArrow.Position = UDim2.fromOffset(edgePos.X, edgePos.Y)
	EdgeArrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
	EdgeArrow.TextTransparency = 0.05 + (0.15 * (0.5 + 0.5 * math.sin(now * 4)))

	EdgeLabel.Visible = true
	EdgeLabel.Position = UDim2.fromOffset(edgePos.X, edgePos.Y + 34)
	EdgeLabel.Text = currentGuideTarget.worldLabel or "Go Here"
end

local function updateButtonTargetVisuals(now: number)
	if not currentGuideTarget or currentGuideTarget.kind ~= "button" or not currentGuideTarget.buttonName then
		ButtonPointer.Visible = false
		ButtonRing.Visible = false
		return
	end

	currentButtonTarget = findMoneyHUDButton(currentGuideTarget.buttonName)
	if not currentButtonTarget then
		ButtonPointer.Visible = false
		ButtonRing.Visible = false
		return
	end

	local absolutePosition = currentButtonTarget.AbsolutePosition
	local absoluteSize = currentButtonTarget.AbsoluteSize
	local centerX = absolutePosition.X + (absoluteSize.X * 0.5)
	local topY = absolutePosition.Y - 44
	local pulse = 0.5 + 0.5 * math.sin(now * 5)

	ButtonPointer.Visible = true
	ButtonRing.Visible = true

	ButtonPointer.Position = UDim2.fromOffset(centerX - 55, topY)
	ButtonRing.Position = UDim2.fromOffset(centerX, absolutePosition.Y + (absoluteSize.Y * 0.5))
	ButtonRing.Size = UDim2.fromOffset(absoluteSize.X + 14, absoluteSize.Y + 12)
	buttonRingStroke.Transparency = 0.08 + (0.35 * pulse)
	buttonRingStroke.Thickness = 2.5 + pulse
	ButtonArrow.TextTransparency = 0.1 + (0.25 * pulse)
end

local function renderGuide(dt: number)
	timeAccumulator += dt
	if timeAccumulator >= 0.25 then
		timeAccumulator = 0
		refreshGuideTarget()
	end

	local now = tick()
	updateWorldTargetVisuals(now)
	updateButtonTargetVisuals(now)
end

local ok, snapshot = pcall(function()
	return GetAchievementsSnapshotFunction:InvokeServer()
end)
if ok and type(snapshot) == "table" then
	LatestAchievementSnapshot = snapshot
end

AchievementUpdatedEvent.OnClientEvent:Connect(function(snapshotData)
	if type(snapshotData) == "table" then
		LatestAchievementSnapshot = snapshotData
		refreshGuideTarget()
	end
end)

for _, attributeName in ipairs({
	"OnboardingStage",
	"TutorialComplete",
}) do
	Player:GetAttributeChangedSignal(attributeName):Connect(function()
		refreshGuideTarget()
	end)
end

PlayerGui.ChildAdded:Connect(function()
	task.defer(refreshGuideTarget)
end)

PlayerGui.ChildRemoved:Connect(function()
	task.defer(refreshGuideTarget)
end)

refreshGuideTarget()

RunService.RenderStepped:Connect(renderGuide)
