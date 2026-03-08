--[[
	SynergyGuideUI Client Script

	Stages the synergy experience so the first unlock feels like a lab,
	not a full reference manual.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local ViewportPreview = require(Shared:WaitForChild("ViewportPreview"))
local UIUtils = require(Shared:WaitForChild("Utils"):WaitForChild("UIUtils"))

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local GetInventoryRemote = RemoteFunctions:FindFirstChild("GetInventory")
if not GetInventoryRemote then
	GetInventoryRemote = RemoteEvents:FindFirstChild("GetInventory")
end
if not GetInventoryRemote then
	GetInventoryRemote = RemoteFunctions:WaitForChild("GetInventory", 10)
end

local addCorner = UIUtils.addCorner
local addStroke = UIUtils.addStroke

local gui: ScreenGui? = nil
local panel: Frame? = nil
local titleLabel: TextLabel? = nil
local subtitleLabel: TextLabel? = nil
local listFrame: ScrollingFrame? = nil

local FALLBACK_UNIT_A = "Avocadini Guffo"
local FALLBACK_UNIT_B = "Bambini_Crostini"
local STAGE_LOCKED = 0
local STAGE_TEASER = 1
local STAGE_DISCOVERED = 2
local STAGE_REFERENCE = 3
local BRAINROT_TAG = "ActiveBrainrot"

local function formatUnitName(unitName: string): string
	return tostring(unitName or ""):gsub("_", " ")
end

local function getGuideStage(): number
	return tonumber(Player:GetAttribute("SynergyGuideStage")) or 0
end

local function getBrainrotModel(unitName: string): Model?
	local direct = ReplicatedStorage:FindFirstChild("Brainrots")
	if direct then
		local model = direct:FindFirstChild(unitName)
		if model and model:IsA("Model") then
			return model
		end
	end

	local units = ReplicatedStorage:FindFirstChild("Units")
	if units then
		local model = units:FindFirstChild(unitName)
		if model and model:IsA("Model") then
			return model
		end
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local brainrots = assets:FindFirstChild("Brainrots")
		if brainrots then
			local model = brainrots:FindFirstChild(unitName)
			if model and model:IsA("Model") then
				return model
			end
		end
	end

	return nil
end

local function createSectionLabel(parent: Instance, text: string, order: number)
	local label = Instance.new("TextLabel")
	label.Name = "Section_" .. tostring(order)
	label.Size = UDim2.new(1, -8, 0, 20)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = Color3.fromRGB(236, 216, 130)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function createInfoCard(parent: Instance, heading: string, body: string, order: number)
	local card = Instance.new("Frame")
	card.Name = "Info_" .. tostring(order)
	card.Size = UDim2.new(1, -8, 0, 88)
	card.BackgroundColor3 = Color3.fromRGB(18, 16, 28)
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Parent = parent
	addCorner(card, UDim.new(0, 10))
	addStroke(card, Color3.fromRGB(68, 60, 100), 1)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = heading
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(245, 235, 165)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.Parent = card

	local bodyLabel = Instance.new("TextLabel")
	bodyLabel.Size = UDim2.new(1, -16, 1, -38)
	bodyLabel.Position = UDim2.new(0, 8, 0, 30)
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Text = body
	bodyLabel.TextWrapped = true
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.TextColor3 = Color3.fromRGB(205, 205, 220)
	bodyLabel.Font = Enum.Font.Gotham
	bodyLabel.TextSize = 12
	bodyLabel.Parent = card

	return card
end

local function createLockedTeaser(parent: Instance, titleText: string, bodyText: string, order: number)
	local card = Instance.new("Frame")
	card.Name = "Teaser_" .. tostring(order)
	card.Size = UDim2.new(1, -8, 0, 74)
	card.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Parent = parent
	addCorner(card, UDim.new(0, 10))
	addStroke(card, Color3.fromRGB(50, 50, 68), 1)

	local badge = Instance.new("TextLabel")
	badge.Size = UDim2.new(0, 54, 0, 22)
	badge.Position = UDim2.new(0, 8, 0, 8)
	badge.BackgroundColor3 = Color3.fromRGB(52, 44, 80)
	badge.Text = "LOCKED"
	badge.TextColor3 = Color3.fromRGB(225, 215, 255)
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 11
	badge.Parent = card
	addCorner(badge, UDim.new(0, 6))

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -78, 0, 20)
	title.Position = UDim2.new(0, 70, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = titleText
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(230, 230, 240)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.Parent = card

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -16, 0, 28)
	body.Position = UDim2.new(0, 8, 0, 36)
	body.BackgroundTransparency = 1
	body.Text = bodyText
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextColor3 = Color3.fromRGB(165, 165, 185)
	body.Font = Enum.Font.Gotham
	body.TextSize = 11
	body.Parent = card

	return card
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
	title.Size = UDim2.new(1, -6, 0, 18)
	title.Position = UDim2.new(0, 3, 1, -20)
	title.BackgroundTransparency = 1
	title.Text = formatUnitName(unitName)
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(220, 220, 235)
	title.Font = Enum.Font.Gotham
	title.Parent = box

	local model = getBrainrotModel(unitName)
	if model then
		local viewport = ViewportPreview.CreateStatic(model, box)
		viewport.Size = UDim2.new(1, -4, 1, -24)
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
	box.Size = UDim2.new(0, 180, 0, 92)
	box.BackgroundColor3 = Color3.fromRGB(28, 24, 40)
	box.BorderSizePixel = 0
	box.Parent = parent
	addCorner(box, UDim.new(0, 8))
	addStroke(box, Color3.fromRGB(95, 80, 150), 1.2)

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(0, 32, 0, 32)
	icon.Position = UDim2.new(0, 8, 0, 8)
	icon.BackgroundTransparency = 1
	icon.Text = (item and item.icon) or "?"
	icon.TextSize = 22
	icon.Font = Enum.Font.Gotham
	icon.TextColor3 = Color3.fromRGB(240, 240, 255)
	icon.Parent = box

	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, -48, 0, 20)
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
	id.Text = "Hybrid output"
	id.TextXAlignment = Enum.TextXAlignment.Left
	id.TextColor3 = Color3.fromRGB(170, 170, 190)
	id.Font = Enum.Font.Gotham
	id.TextSize = 11
	id.Parent = box

	local summary = Instance.new("TextLabel")
	summary.Size = UDim2.new(1, -16, 0, 16)
	summary.Position = UDim2.new(0, 8, 0, 56)
	summary.BackgroundTransparency = 1
	summary.TextXAlignment = Enum.TextXAlignment.Left
	summary.Font = Enum.Font.GothamBold
	summary.TextSize = 11
	summary.Text = "Rarer stock for better sell windows"
	summary.TextColor3 = Color3.fromRGB(100, 220, 130)
	summary.Parent = box

	return box
end

local function createHeroCard(parent: Instance, syn, order: number, headerText: string, hintText: string, ownershipText: string?)
	local outputDef = ItemConfig.Items[syn.synergyItem]
	local outputName = outputDef and (outputDef.displayName or syn.synergyItem) or syn.synergyItem

	local card = Instance.new("Frame")
	card.Name = "Hero_" .. tostring(order)
	card.Size = UDim2.new(1, -8, 0, 190)
	card.BackgroundColor3 = Color3.fromRGB(16, 14, 26)
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	card.Parent = parent
	addCorner(card, UDim.new(0, 12))
	addStroke(card, Color3.fromRGB(92, 74, 156), 1.5)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = headerText
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(246, 228, 150)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.Parent = card

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, -16, 0, 18)
	sub.Position = UDim2.new(0, 8, 0, 32)
	sub.BackgroundTransparency = 1
	sub.Text = hintText
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = Color3.fromRGB(205, 205, 220)
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 12
	sub.Parent = card

	local visual = Instance.new("Frame")
	visual.Size = UDim2.new(1, -16, 0, 96)
	visual.Position = UDim2.new(0, 8, 0, 58)
	visual.BackgroundTransparency = 1
	visual.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = visual

	local unitABox = createUnitPreview(visual, syn.unitA)
	unitABox.LayoutOrder = 1

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
	unitBBox.LayoutOrder = 3

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
	outputBox.LayoutOrder = 5

	local footer = Instance.new("TextLabel")
	footer.Size = UDim2.new(1, -16, 0, 16)
	footer.Position = UDim2.new(0, 8, 1, -26)
	footer.BackgroundTransparency = 1
	footer.Text = ownershipText or ("Result: " .. outputName)
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.TextColor3 = Color3.fromRGB(130, 225, 150)
	footer.Font = Enum.Font.GothamBold
	footer.TextSize = 11
	footer.Parent = card

	return card
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
	title.Text = string.format("Requires %s + %s -> Produces %s", formatUnitName(syn.unitA), formatUnitName(syn.unitB), outName)
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
	unitABox.LayoutOrder = 1

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
	unitBBox.LayoutOrder = 3

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
	outputBox.LayoutOrder = 5
end

local function clearRows()
	if not listFrame then
		return
	end
	for _, child in ipairs(listFrame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function getOwnedUnits(): {[string]: boolean}
	local owned = {}

	for _, unit in CollectionService:GetTagged(BRAINROT_TAG) do
		if unit:GetAttribute("OwnerId") == Player.UserId then
			local unitType = unit:GetAttribute("UnitType")
			if type(unitType) == "string" and unitType ~= "" then
				owned[unitType] = true
			end
		end
	end

	if not GetInventoryRemote then
		return owned
	end

	local success, inventory = pcall(function()
		return GetInventoryRemote:InvokeServer()
	end)
	if not success or type(inventory) ~= "table" then
		return owned
	end

	for unitName, unitData in pairs(inventory.units or {}) do
		if type(unitName) == "string" and type(unitData) == "table" then
			local level = tonumber(unitData.level) or 0
			if level > 0 then
				owned[unitName] = true
			end
		end
	end

	return owned
end

local function getActiveSynergies()
	local slotToUnit = {}
	for _, unit in CollectionService:GetTagged(BRAINROT_TAG) do
		if unit:GetAttribute("OwnerId") == Player.UserId then
			local slot = tonumber(unit:GetAttribute("GridSlot"))
			if slot then
				slotToUnit[slot] = unit
			end
		end
	end

	local results = {}
	local seen = {}

	for slotIndex, unit in pairs(slotToUnit) do
		local unitType = unit:GetAttribute("UnitType")
		if type(unitType) == "string" then
			local clusterIdx = math.floor((slotIndex - 1) / 4)
			local baseSlot = clusterIdx * 4 + 1
			for _, neighborSlot in ipairs({ baseSlot, baseSlot + 1, baseSlot + 2, baseSlot + 3 }) do
				if neighborSlot ~= slotIndex and slotToUnit[neighborSlot] then
					local neighborType = slotToUnit[neighborSlot]:GetAttribute("UnitType")
					if type(neighborType) == "string" then
						local syn = ItemConfig.GetSynergyOverride(unitType, neighborType)
						if syn and not seen[syn.synergyItem] then
							seen[syn.synergyItem] = true
							table.insert(results, syn)
						end
					end
				end
			end
		end
	end

	table.sort(results, function(a, b)
		local aValue = (ItemConfig.Items[a.synergyItem] and ItemConfig.Items[a.synergyItem].basePrice) or 0
		local bValue = (ItemConfig.Items[b.synergyItem] and ItemConfig.Items[b.synergyItem].basePrice) or 0
		if aValue ~= bValue then
			return aValue > bValue
		end
		return tostring(a.synergyItem) < tostring(b.synergyItem)
	end)

	return results
end

local function getFallbackSynergy()
	for _, syn in ipairs(ItemConfig.Synergies or {}) do
		local matchesForward = syn.unitA == FALLBACK_UNIT_A and syn.unitB == FALLBACK_UNIT_B
		local matchesReverse = syn.unitA == FALLBACK_UNIT_B and syn.unitB == FALLBACK_UNIT_A
		if matchesForward or matchesReverse then
			return syn
		end
	end
	return (ItemConfig.Synergies or {})[1]
end

local function getRecommendedSynergies(limit: number, exclude: {[string]: boolean}?)
	local ownedUnits = getOwnedUnits()
	local recommendations = {}

	for _, syn in ipairs(ItemConfig.Synergies or {}) do
		if not (exclude and exclude[syn.synergyItem]) then
			local itemDef = ItemConfig.Items[syn.synergyItem]
			local ownedA = ownedUnits[syn.unitA] == true
			local ownedB = ownedUnits[syn.unitB] == true
			local score = ((itemDef and itemDef.basePrice) or 0) / 20

			if ownedA and ownedB then
				score += 300
			elseif ownedA or ownedB then
				score += 150
			end

			table.insert(recommendations, {
				synergy = syn,
				score = score,
				ownedA = ownedA,
				ownedB = ownedB,
			})
		end
	end

	table.sort(recommendations, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return tostring(a.synergy.synergyItem) < tostring(b.synergy.synergyItem)
	end)

	local selected = {}
	local seen = {}
	for _, entry in ipairs(recommendations) do
		if not seen[entry.synergy.synergyItem] then
			seen[entry.synergy.synergyItem] = true
			table.insert(selected, entry)
			if #selected >= limit then
				break
			end
		end
	end

	if #selected == 0 then
		local fallback = getFallbackSynergy()
		if fallback then
			local ownedA = ownedUnits[fallback.unitA] == true
			local ownedB = ownedUnits[fallback.unitB] == true
			table.insert(selected, {
				synergy = fallback,
				score = 0,
				ownedA = ownedA,
				ownedB = ownedB,
			})
		end
	end

	return selected
end

local function buildOwnershipHint(entry): string
	if not entry then
		return "Build this pair in the same 2x2 cluster."
	end
	if entry.ownedA and entry.ownedB then
		return "You already own both units. Pair them in one 2x2 cluster."
	end
	if entry.ownedA then
		return "You already own " .. formatUnitName(entry.synergy.unitA) .. ". Find or buy the partner next."
	end
	if entry.ownedB then
		return "You already own " .. formatUnitName(entry.synergy.unitB) .. ". Find or buy the partner next."
	end
	return "This is a reliable starter hybrid to chase next."
end

local function rebuildContent()
	if not listFrame or not titleLabel or not subtitleLabel then
		return
	end

	clearRows()

	local stage = getGuideStage()
	local totalSynergies = #(ItemConfig.Synergies or {})
	local activeSynergies = getActiveSynergies()
	local activeLookup = {}
	for _, syn in ipairs(activeSynergies) do
		activeLookup[syn.synergyItem] = true
	end

	if stage <= STAGE_LOCKED then
		titleLabel.Text = "SYNERGY LAB"
		subtitleLabel.Text = "Pair weird units for rarer outputs once synergies unlock."
		createInfoCard(
			listFrame,
			"Hybrid outputs unlock later",
			"Keep scaling your line. Once synergies unlock, you will get one starter combo instead of a full recipe wall.",
			1
		)
		return
	end

	if stage == STAGE_TEASER then
		titleLabel.Text = "SYNERGY LAB"
		subtitleLabel.Text = "Start with one hybrid combo. Place both units in the same 2x2 cluster."

		local recommendations = getRecommendedSynergies(1)
		local starter = recommendations[1]
		if starter then
			createHeroCard(
				listFrame,
				starter.synergy,
				1,
				"Starter Combo",
				"This creates rarer stock that is worth watching in the market.",
				buildOwnershipHint(starter)
			)
		end

		createInfoCard(
			listFrame,
			"How it works",
			"Place both units in the same 2x2 cluster. One becomes the hybrid producer and the other becomes the provider. The beam means the pair is live.",
			2
		)
		createLockedTeaser(
			listFrame,
			"More pairings are still hidden",
			"Your first hybrid reveals the next layer. You do not need the full recipe book yet.",
			3
		)
		createLockedTeaser(
			listFrame,
			string.format("%d more strange pairings remain", math.max(totalSynergies - 1, 0)),
			"Discover the first one before the guide expands.",
			4
		)
		return
	end

	if stage == STAGE_DISCOVERED then
		titleLabel.Text = "DISCOVERED HYBRIDS"
		subtitleLabel.Text = "You found your first hybrid. Chase one or two more before the full reference opens."

		local heroSynergy = activeSynergies[1]
		local recommended = getRecommendedSynergies(2, activeLookup)
		if not heroSynergy and recommended[1] then
			heroSynergy = recommended[1].synergy
		end

		if heroSynergy then
			createHeroCard(
				listFrame,
				heroSynergy,
				1,
				activeLookup[heroSynergy.synergyItem] and "Hybrid Online" or "Recent Discovery",
				"Hybrid outputs give you a smarter stock mix and stronger sell targets.",
				activeLookup[heroSynergy.synergyItem] and "This hybrid is active on your line right now." or "Use this as the reference point for your next pair."
			)
		end

		createSectionLabel(listFrame, "Next Pairs to Try", 2)
		if #recommended == 0 then
			createInfoCard(
				listFrame,
				"No close follow-up pair yet",
				"Keep widening your line. New hybrids become easier to chase once you own more weird units.",
				3
			)
		else
			for index, entry in ipairs(recommended) do
				createHeroCard(
					listFrame,
					entry.synergy,
					index + 2,
					"Recommended Next",
					"Try another hybrid once you want a wider premium stock mix.",
					buildOwnershipHint(entry)
				)
			end
		end

		createLockedTeaser(
			listFrame,
			string.format("%d more pairings stay locked for now", math.max(totalSynergies - 1 - #recommended, 0)),
			"Find a few unique hybrids before the full reference opens up.",
			10
		)
		return
	end

	titleLabel.Text = "SYNERGY GUIDE"
	subtitleLabel.Text = "Browse all known pairings once you have earned the deeper reference."
	createSectionLabel(listFrame, "All Known Pairings", 1)
	for index, syn in ipairs(ItemConfig.Synergies or {}) do
		createSynergyRow(listFrame, syn, index + 1)
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

	titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -90, 0, 32)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "SYNERGY LAB"
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextColor3 = Color3.fromRGB(240, 230, 160)
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextSize = 26
	titleLabel.Parent = panel

	subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Size = UDim2.new(1, -90, 0, 18)
	subtitleLabel.Position = UDim2.new(0, 16, 0, 42)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Text = "Start with one hybrid combo."
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subtitleLabel.TextColor3 = Color3.fromRGB(185, 185, 205)
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.TextSize = 12
	subtitleLabel.Parent = panel

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
	listFrame.Size = UDim2.new(1, -24, 1, -78)
	listFrame.Position = UDim2.new(0, 12, 0, 68)
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
	if not panel then
		return
	end

	panel.Visible = not panel.Visible
	if panel.Visible then
		rebuildContent()
	end
end

local SynergyToggleEvent = ReplicatedStorage:FindFirstChild("SynergyToggleEvent")
if not SynergyToggleEvent then
	SynergyToggleEvent = Instance.new("BindableEvent")
	SynergyToggleEvent.Name = "SynergyToggleEvent"
	SynergyToggleEvent.Parent = ReplicatedStorage
end

SynergyToggleEvent.Event:Connect(toggleGuide)

for _, attributeName in ipairs({
	"SynergyGuideStage",
	"FirstSynergyActivated",
	"SynergyReferenceUnlocked",
	"SynergyUnlocked",
}) do
	Player:GetAttributeChangedSignal(attributeName):Connect(function()
		if panel and panel.Visible then
			rebuildContent()
		end
	end)
end
