--[[
	SynergyGuideUI Client Script

	Data-driven synergy reference popup.
	Reads ItemConfig.Synergies and renders requirements -> outcome rows.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local ViewportPreview = require(Shared:WaitForChild("ViewportPreview"))
local UIUtils = require(Shared:WaitForChild("Utils"):WaitForChild("UIUtils"))

local addCorner = UIUtils.addCorner
local addStroke = UIUtils.addStroke

local gui: ScreenGui? = nil
local panel: Frame? = nil
local listFrame: ScrollingFrame? = nil

local function getBrainrotModel(unitName: string): Model?
	local direct = ReplicatedStorage:FindFirstChild("Brainrots")
	if direct then
		local m = direct:FindFirstChild(unitName)
		if m and m:IsA("Model") then return m end
	end

	local units = ReplicatedStorage:FindFirstChild("Units")
	if units then
		local m = units:FindFirstChild(unitName)
		if m and m:IsA("Model") then return m end
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local brainrots = assets:FindFirstChild("Brainrots")
		if brainrots then
			local m = brainrots:FindFirstChild(unitName)
			if m and m:IsA("Model") then return m end
		end
	end

	return nil
end

local function createUnitPreview(parent: Instance, unitName: string)
	local box = Instance.new("Frame")
	box.Size = UDim2.new(0, 92, 0, 92)
	box.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	box.BorderSizePixel = 0
	box.Parent = parent
	addCorner(box, UDim.new(0, 8))
	addStroke(box, Color3.fromRGB(70, 70, 95), 1)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -6, 0, 16)
	title.Position = UDim2.new(0, 3, 1, -18)
	title.BackgroundTransparency = 1
	title.Text = unitName
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(220, 220, 235)
	title.Font = Enum.Font.Gotham
	title.Parent = box

	local model = getBrainrotModel(unitName)
	if model then
		local viewport = ViewportPreview.CreateStatic(model, box)
		viewport.Size = UDim2.new(1, -4, 1, -22)
		viewport.Position = UDim2.new(0, 2, 0, 2)
		viewport.BackgroundTransparency = 1
	else
		local fallback = Instance.new("TextLabel")
		fallback.Size = UDim2.new(1, -6, 1, -24)
		fallback.Position = UDim2.new(0, 3, 0, 2)
		fallback.BackgroundTransparency = 1
		fallback.TextWrapped = true
		fallback.Text = "Missing model"
		fallback.TextColor3 = Color3.fromRGB(255, 140, 140)
		fallback.Font = Enum.Font.GothamBold
		fallback.TextSize = 14
		fallback.Parent = box
	end

	return box
end

local function createOutputCard(parent: Instance, synergyItem: string)
	local item = ItemConfig.Items[synergyItem]

	local box = Instance.new("Frame")
	box.Size = UDim2.new(0, 170, 0, 92)
	box.BackgroundColor3 = Color3.fromRGB(28, 24, 40)
	box.BorderSizePixel = 0
	box.Parent = parent
	addCorner(box, UDim.new(0, 8))
	addStroke(box, Color3.fromRGB(95, 80, 150), 1.2)

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(0, 30, 0, 30)
	icon.Position = UDim2.new(0, 8, 0, 8)
	icon.BackgroundTransparency = 1
	icon.Text = (item and item.icon) or "?"
	icon.TextSize = 22
	icon.Font = Enum.Font.Gotham
	icon.TextColor3 = Color3.fromRGB(240, 240, 255)
	icon.Parent = box

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -46, 0, 20)
	name.Position = UDim2.new(0, 40, 0, 10)
	name.BackgroundTransparency = 1
	name.Text = (item and item.displayName) or synergyItem
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Color3.fromRGB(240, 240, 255)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 14
	name.Parent = box

	local id = Instance.new("TextLabel")
	id.Size = UDim2.new(1, -16, 0, 16)
	id.Position = UDim2.new(0, 8, 0, 36)
	id.BackgroundTransparency = 1
	id.Text = "Item ID: " .. synergyItem
	id.TextXAlignment = Enum.TextXAlignment.Left
	id.TextColor3 = Color3.fromRGB(170, 170, 190)
	id.Font = Enum.Font.RobotoMono
	id.TextSize = 11
	id.Parent = box

	local warn = Instance.new("TextLabel")
	warn.Size = UDim2.new(1, -16, 0, 16)
	warn.Position = UDim2.new(0, 8, 0, 56)
	warn.BackgroundTransparency = 1
	warn.TextXAlignment = Enum.TextXAlignment.Left
	warn.Font = Enum.Font.GothamBold
	warn.TextSize = 11
	warn.Parent = box
	if item then
		warn.Text = "Output item"
		warn.TextColor3 = Color3.fromRGB(100, 220, 130)
	else
		warn.Text = "Missing output definition"
		warn.TextColor3 = Color3.fromRGB(255, 140, 140)
	end

	return box
end

local function createSynergyRow(parent: Instance, syn, index: number)
	local outItem = ItemConfig.Items[syn.synergyItem]
	local outName = (outItem and outItem.displayName) or syn.synergyItem

	local row = Instance.new("Frame")
	row.Name = "Row_" .. index
	row.Size = UDim2.new(1, -8, 0, 154)
	row.BackgroundColor3 = Color3.fromRGB(16, 14, 24)
	row.BorderSizePixel = 0
	row.LayoutOrder = index
	row.Parent = parent
	addCorner(row, UDim.new(0, 10))
	addStroke(row, Color3.fromRGB(60, 52, 85), 1)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -14, 0, 24)
	title.Position = UDim2.new(0, 8, 0, 6)
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = string.format("Requires %s + %s -> Produces %s", syn.unitA, syn.unitB, outName)
	title.TextColor3 = Color3.fromRGB(236, 216, 130)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Parent = row

	local visual = Instance.new("Frame")
	visual.Size = UDim2.new(1, -14, 0, 106)
	visual.Position = UDim2.new(0, 8, 0, 34)
	visual.BackgroundTransparency = 1
	visual.Parent = row

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = visual

	local unitABox = createUnitPreview(visual, syn.unitA)
	if unitABox and unitABox:IsA("GuiObject") then
		unitABox.LayoutOrder = 1
	end

	local plus = Instance.new("TextLabel")
	plus.Size = UDim2.new(0, 18, 0, 92)
	plus.BackgroundTransparency = 1
	plus.Text = "+"
	plus.TextColor3 = Color3.fromRGB(205, 205, 220)
	plus.TextSize = 20
	plus.Font = Enum.Font.GothamBold
	plus.LayoutOrder = 2
	plus.Parent = visual

	local unitBBox = createUnitPreview(visual, syn.unitB)
	if unitBBox and unitBBox:IsA("GuiObject") then
		unitBBox.LayoutOrder = 3
	end

	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.new(0, 22, 0, 92)
	arrow.BackgroundTransparency = 1
	arrow.Text = "->"
	arrow.TextColor3 = Color3.fromRGB(205, 205, 220)
	arrow.TextSize = 18
	arrow.Font = Enum.Font.GothamBold
	arrow.LayoutOrder = 4
	arrow.Parent = visual

	local outputBox = createOutputCard(visual, syn.synergyItem)
	if outputBox and outputBox:IsA("GuiObject") then
		outputBox.LayoutOrder = 5
	end
end

local function rebuildRows()
	if not listFrame then return end
	for _, child in ipairs(listFrame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end

	local synergies = ItemConfig.Synergies or {}
	if #synergies == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -8, 0, 34)
		empty.BackgroundTransparency = 1
		empty.Text = "No synergies configured."
		empty.TextColor3 = Color3.fromRGB(185, 185, 205)
		empty.Font = Enum.Font.GothamBold
		empty.TextSize = 14
		empty.Parent = listFrame
		return
	end

	for i, syn in ipairs(synergies) do
		createSynergyRow(listFrame, syn, i)
	end
end

local function createGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "SynergyGuideUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	panel = Instance.new("Frame")
	panel.Name = "MainPanel"
	panel.Size = UDim2.new(0, 920, 0, 560)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(14, 12, 22)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	addCorner(panel, UDim.new(0, 14))
	addStroke(panel, Color3.fromRGB(95, 75, 160), 2)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -90, 0, 36)
	title.Position = UDim2.new(0, 16, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "SYNERGY GUIDE"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(240, 230, 160)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 26
	title.Parent = panel

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 34, 0, 34)
	closeBtn.Position = UDim2.new(1, -44, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(235, 70, 70)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 18
	closeBtn.Parent = panel
	addCorner(closeBtn, UDim.new(0, 8))
	addStroke(closeBtn, Color3.fromRGB(120, 40, 40), 1)

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "List"
	listFrame.Size = UDim2.new(1, -24, 1, -58)
	listFrame.Position = UDim2.new(0, 12, 0, 48)
	listFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 7
	listFrame.ScrollBarImageColor3 = Color3.fromRGB(120, 96, 200)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.Parent = panel
	addCorner(listFrame, UDim.new(0, 10))
	addStroke(listFrame, Color3.fromRGB(60, 52, 85), 1)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 4)
	padding.PaddingRight = UDim.new(0, 4)
	padding.Parent = listFrame

	closeBtn.MouseButton1Click:Connect(function()
		if panel then
			panel.Visible = false
		end
	end)

	gui.Parent = PlayerGui
end

local function toggleGuide()
	if not gui or not panel then
		createGui()
	end
	if not panel then return end

	panel.Visible = not panel.Visible
	if panel.Visible then
		rebuildRows()
	end
end

local SynergyToggleEvent = ReplicatedStorage:FindFirstChild("SynergyToggleEvent")
if not SynergyToggleEvent then
	SynergyToggleEvent = Instance.new("BindableEvent")
	SynergyToggleEvent.Name = "SynergyToggleEvent"
	SynergyToggleEvent.Parent = ReplicatedStorage
end

SynergyToggleEvent.Event:Connect(toggleGuide)
