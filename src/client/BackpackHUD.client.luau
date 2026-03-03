--[[
	BackpackHUD LocalScript
	
	Unified Inventory UI ("Backpack").
	Displays Units and Artifacts in a grid.
	Features rich interaction with 3D previews and stats.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local _UserInputService = game:GetService("UserInputService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local _ItemTypes = require(Shared:WaitForChild("ItemTypes"))
local ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))
local _ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local ViewportPreview = require(Shared:WaitForChild("ViewportPreview"))
local ClientPlotService = require(script.Parent:WaitForChild("ClientPlotService"))

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

-- Remotes with Timeouts to prevent Infinite Yields
local GetUnifiedInventoryFunc = RemoteFunctions:WaitForChild("GetUnifiedInventory", 10)
if not GetUnifiedInventoryFunc then warn("BackpackHUD: GetUnifiedInventory not found!") end

-- Storage remotes
local GetStorageFunction = RemoteFunctions:WaitForChild("GetStorage", 10)
local StorageUpdatedEvent = RemoteEvents:WaitForChild("StorageUpdated", 10)
local InventoryChangedEvent = RemoteEvents:WaitForChild("InventoryChanged", 10)
local ItemProducedEvent = RemoteEvents:WaitForChild("ItemProduced", 10)

-- Folders for 3D preview
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")

local UI_CONFIG = {
	PANEL_WIDTH = 760,
	PANEL_HEIGHT = 560,
	SLOT_SIZE = 128,
	SLOT_HEIGHT = 138,
	GRID_PADDING = 10,
	CORNER_RADIUS = 16,
	
	COLOR_BG = Color3.fromRGB(12, 12, 20),
	COLOR_PANEL = Color3.fromRGB(26, 26, 42),
	COLOR_SLOT = Color3.fromRGB(31, 31, 52),
	COLOR_SLOT_INNER = Color3.fromRGB(18, 18, 34),
	COLOR_ACCENT = Color3.fromRGB(140, 80, 255),
	COLOR_TEXT = Color3.fromRGB(240, 240, 240),
	COLOR_TEXT_DIM = Color3.fromRGB(160, 160, 180),
	COLOR_TAB_ACTIVE = Color3.fromRGB(235, 190, 52),
	COLOR_TAB_IDLE = Color3.fromRGB(41, 41, 60),
	COLOR_SEARCH_BG = Color3.fromRGB(23, 23, 36),
	COLOR_CLOSE = Color3.fromRGB(210, 55, 65),
	
	RARITY_COLORS = {
		Normal = Color3.fromRGB(180, 180, 180),
		Spicy = Color3.fromRGB(255, 80, 80),
		Galaxy = Color3.fromRGB(180, 100, 255),
	},
	
	-- Hover tooltip settings
	HOVER_DELAY = 0.3, -- Seconds before tooltip appears
	TOOLTIP_FADE_TIME = 0.2, -- Fade in/out duration
}

local BackpackGui
local BackpackVisible = false
local CurrentItems = {}
local CurrentFilter = "Unit" -- "Unit", "Storage", "Artifact"
local CurrentSearchQuery = ""

-- Storage state
local CurrentStorageItems = {} -- {[itemId] = count}
local StorageUsage = 0

local StorageCapacity = 0 -- Updated via Player Attribute

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local UIUtils = require(Shared:WaitForChild("Utils"):WaitForChild("UIUtils"))

local addCorner = UIUtils.addCorner
local addStroke = UIUtils.addStroke
local decodeItems = UIUtils.decodeItems

local function getRarityColor(rarity)
	if ArtifactConfig.RarityColors and ArtifactConfig.RarityColors[rarity] then
		return ArtifactConfig.RarityColors[rarity]
	end
	return UI_CONFIG.RARITY_COLORS[rarity] or UI_CONFIG.RARITY_COLORS.Normal
end

local function matchesSearch(text: string): boolean
	if CurrentSearchQuery == "" then
		return true
	end
	local haystack = string.lower(tostring(text or ""))
	local needle = string.lower(CurrentSearchQuery)
	return string.find(haystack, needle, 1, true) ~= nil
end

local function getArtifactStats(artifactData)
	if not artifactData then
		return {
			CycleTimeMult = 1,
			LuckBonus = 0,
			ItemTierBonus = 0,
			SynergyRangeBonus = 0,
		}
	end

	if artifactData.Stats then
		return artifactData.Stats
	end

	return ArtifactConfig.CalculateArtifactStats(artifactData)
end

local function addArtifactStatLines(addLineFn, stats)
	if not stats then return end

	if stats.CycleTimeMult and stats.CycleTimeMult < 1 then
		local pct = math.floor((1 - stats.CycleTimeMult) * 100)
		addLineFn("Cycle Time: -" .. pct .. "%", Color3.fromRGB(255, 255, 100))
	end
	if stats.LuckBonus and stats.LuckBonus > 0 then
		addLineFn("Luck: +" .. math.floor(stats.LuckBonus * 100) .. "%", Color3.fromRGB(100, 255, 100))
	end
	if stats.ItemTierBonus and stats.ItemTierBonus > 0 then
		addLineFn("Tier Bonus: +" .. stats.ItemTierBonus, Color3.fromRGB(255, 210, 120))
	end
	if stats.SynergyRangeBonus and stats.SynergyRangeBonus > 0 then
		addLineFn("Synergy Range: +" .. stats.SynergyRangeBonus, Color3.fromRGB(120, 220, 255))
	end
end
--[[
	Checks if player is standing on their own island.
	Used to enable/disable taking items from storage.
]]
local function isOnOwnIsland()
	return ClientPlotService.IsOnMyIsland()
end

--[[
	Finds the brainrot visual template.
]]
local function getBrainrotTemplate(unitName)
	-- Try to find in various locations
	local t = BrainrotsFolder:FindFirstChild(unitName)
	if t then return t end
	
	-- Check ReplicatedStorage.Assets.Brainrots if exists
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets and assets:FindFirstChild("Brainrots") then
		t = assets.Brainrots:FindFirstChild(unitName)
		if t then return t end
	end
	
	return nil
end

--------------------------------------------------------------------------------
-- DETAIL POPUP
--------------------------------------------------------------------------------



local function openDetailPopup(item)
	-- Remove existing popup
	local oldPopup = BackpackGui:FindFirstChild("DetailPopup")
	if oldPopup then oldPopup:Destroy() end
	
	local popup = Instance.new("Frame")
	popup.Name = "DetailPopup"
	popup.Size = UDim2.new(0, 300, 0, 400)
	-- Center related to screen? Or panel? let's center on screen for now
	popup.Position = UDim2.new(0.5, 0, 0.5, 0)
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.BackgroundColor3 = UI_CONFIG.COLOR_BG
	popup.BorderSizePixel = 0
	popup.ZIndex = 100
	popup.Parent = BackpackGui
	
	addCorner(popup, 16)
	addStroke(popup, (item.Type == "Artifact" and getRarityColor(item.Rarity) or UI_CONFIG.COLOR_ACCENT), 2)
	
	-- Close Button (Top Right)
	local close = Instance.new("TextButton")
	close.Text = "X"
	close.Size = UDim2.new(0, 30, 0, 30)
	close.Position = UDim2.new(1, -35, 0, 5)
	close.BackgroundTransparency = 1
	close.TextColor3 = UI_CONFIG.COLOR_TEXT_DIM
	close.TextSize = 20
	close.Parent = popup
	close.MouseButton1Click:Connect(function() popup:Destroy() end)
	
	-- Content Layout
	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, -20, 1, -20)
	content.Position = UDim2.new(0, 10, 0, 10)
	content.BackgroundTransparency = 1
	content.Parent = popup
	
	local uiList = Instance.new("UIListLayout")
	uiList.SortOrder = Enum.SortOrder.LayoutOrder
	uiList.Padding = UDim.new(0, 10)
	uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	uiList.Parent = content
	
	-- 1. Header (Name & Rarity)
	local header = Instance.new("TextLabel")
	local rarityPrefix = item.Type == "Artifact" and ((item.Rarity or "Common") .. " ") or ""
	header.Text = rarityPrefix .. item.Name
	header.TextColor3 = item.Type == "Artifact" and getRarityColor(item.Rarity) or UI_CONFIG.COLOR_TEXT
	header.Font = Enum.Font.GothamBold
	header.TextSize = 18
	header.Size = UDim2.new(1, 0, 0, 24)
	header.BackgroundTransparency = 1
	header.LayoutOrder = 1
	header.Parent = content
	
	-- 2. Preview Area
	local previewFrame = Instance.new("Frame")
	previewFrame.Size = UDim2.new(0, 200, 0, 200)
	previewFrame.BackgroundColor3 = Color3.fromRGB(20,20,25)
	previewFrame.LayoutOrder = 2
	previewFrame.Parent = content
	addCorner(previewFrame, 8)
	
	if item.Type == "Unit" then
		-- 3D Viewport
		local template = getBrainrotTemplate(item.UUID) -- UUID is unitName for units
		if template then
			local preview = ViewportPreview.Create(template, previewFrame)
			preview.viewport.BackgroundTransparency = 1
		end
		
	elseif item.Type == "Artifact" then
		-- Icon Image
		local icon = Instance.new("TextLabel") -- Using TextLabel for emoji icons?
		-- If Icon is an asset ID, use ImageLabel. If emoji, use TextLabel.
		-- Artifact system uses generic Image/Emoji.
		
		-- FALLBACK LOGIC
		local displayIcon = item.Icon
		if not displayIcon or displayIcon == "" then
			displayIcon = "[Artifact]"
		end
		
		icon.Text = displayIcon
		icon.Size = UDim2.new(1,0,1,0)
		icon.BackgroundTransparency = 1
		icon.TextSize = 100
		icon.Parent = previewFrame
	end
	
	-- 3. Stats / Info
	local infoFrame = Instance.new("Frame")
	infoFrame.Size = UDim2.new(1, 0, 0, 160)
	infoFrame.BackgroundTransparency = 1
	infoFrame.LayoutOrder = 3
	infoFrame.Parent = content
	
	local infoList = Instance.new("UIListLayout")
	infoList.Padding = UDim.new(0, 4)
	infoList.Parent = infoFrame
	
	local function addLine(text, color)
		local l = Instance.new("TextLabel")
		l.Text = text
		l.TextColor3 = color or UI_CONFIG.COLOR_TEXT
		l.TextSize = 14
		l.Font = Enum.Font.Gotham
		l.Size = UDim2.new(1, 0, 0, 18)
		l.BackgroundTransparency = 1
		l.Parent = infoFrame
	end
	
	if item.Type == "Unit" then
		addLine("Level: " .. (item.Data.Level or 1), UI_CONFIG.COLOR_TEXT)
		addLine("Status: " .. (item.IsPlaced and "Placed (On Grid)" or "Stored"), 
			item.IsPlaced and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 200, 100))
			
		-- TODO: Show slots?
	else -- Artifact
		local slotIcon = ArtifactConfig.SlotIcons[item.Data.Slot] or "[Slot]"
		addLine(string.format("Slot: %s %s", slotIcon, item.Data.Slot or "Unknown"), UI_CONFIG.COLOR_TEXT)
		addLine("Status: " .. (item.Data.EquippedTo and "Equipped" or "In Inventory"), UI_CONFIG.COLOR_TEXT_DIM)
		addLine("Rarity: " .. tostring(item.Rarity or "Common"), getRarityColor(item.Rarity))

		local stats = getArtifactStats(item.Data)
		addArtifactStatLines(addLine, stats)

		local affixes = item.Data.Affixes or {}
		if #affixes > 0 then
			addLine("Affixes:", Color3.fromRGB(190, 190, 220))
			for _, affix in ipairs(affixes) do
				local icon = affix.Icon or "-"
				addLine(string.format("%s %s", icon, affix.Name or "Unknown"), UI_CONFIG.COLOR_TEXT_DIM)
			end
		else
			addLine("No affixes", UI_CONFIG.COLOR_TEXT_DIM)
		end
	end
end

--------------------------------------------------------------------------------
-- GRID UI
--------------------------------------------------------------------------------

local IsRefreshing = false -- Debounce flag to prevent duplicate renders

local function refreshGrid()
	if IsRefreshing then return end
	IsRefreshing = true

	-- Cleanup IsRefreshing at the very end
	local function finish()
		IsRefreshing = false
	end

	if not BackpackGui then return finish() end
	local mainPanel = BackpackGui:FindFirstChild("MainPanel")
	if not mainPanel then return finish() end
	local grid = mainPanel:FindFirstChild("Grid")
	if not grid then return finish() end
	local infoLabel = mainPanel:FindFirstChild("InfoLabel")
	local searchBox = mainPanel:FindFirstChild("SearchBox")
	if searchBox and searchBox:IsA("TextBox") then
		CurrentSearchQuery = string.gsub(searchBox.Text or "", "^%s*(.-)%s*$", "%1")
	end

	-- Thoroughly clear grid leaving ONLY the GridLayout
	for _, child in grid:GetChildren() do
		if not child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end

	local function createEmptyState(text)
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -10, 0, 40)
		empty.BackgroundTransparency = 1
		empty.Text = text
		empty.TextColor3 = UI_CONFIG.COLOR_TEXT_DIM
		empty.TextSize = 16
		empty.Font = Enum.Font.Gotham
		empty.Parent = grid
	end

	if CurrentFilter == "Storage" then
		local success, items, total, capacity = pcall(function()
			return GetStorageFunction:InvokeServer()
		end)
		if not success or not items then
			items, total, capacity = {}, 0, 2000
		end

		CurrentStorageItems = decodeItems(items)
		StorageUsage = total or 0
		StorageCapacity = Player:GetAttribute("StorageCapacity") or capacity or 0

		local onIsland = isOnOwnIsland()
		if infoLabel then
			infoLabel.Text = string.format("Items in storage: %d / %d%s", StorageUsage, StorageCapacity, onIsland and "" or "  (Go to your island to transfer)")
		end

		local display = {}
		for itemId, count in pairs(CurrentStorageItems) do
			if count > 0 then
				local def = ItemConfig.Items[itemId]
				-- Strict Item Tab Filter: Only show items defined in ItemConfig
				if not def then continue end 
				
				local name = def.displayName or itemId
				if matchesSearch(name) or matchesSearch(itemId) then
					table.insert(display, {
						itemId = itemId,
						name = name,
						icon = def.icon or "[Item]",
						count = count,
					})
				end
			end
		end
		table.sort(display, function(a, b)
			if a.count == b.count then return a.name < b.name end
			return a.count > b.count
		end)

		if #display == 0 then
			createEmptyState("No matching storage items")
		end

		for i, entry in ipairs(display) do
			local card = Instance.new("Frame")
			card.Name = "StorageCard_" .. i
			card.BackgroundColor3 = UI_CONFIG.COLOR_SLOT
			card.LayoutOrder = i
			card.Parent = grid
			addCorner(card, 10)
			addStroke(card, Color3.fromRGB(80, 130, 255), 1.5)

			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, -12, 0, 18)
			title.Position = UDim2.new(0, 6, 0, 6)
			title.BackgroundTransparency = 1
			title.Text = entry.name
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.TextColor3 = UI_CONFIG.COLOR_TEXT
			title.TextSize = 11
			title.Font = Enum.Font.GothamBold
			title.Parent = card

			local iconFrame = Instance.new("Frame")
			iconFrame.Size = UDim2.new(1, -14, 0, 70)
			iconFrame.Position = UDim2.new(0, 7, 0, 28)
			iconFrame.BackgroundColor3 = UI_CONFIG.COLOR_SLOT_INNER
			iconFrame.BorderSizePixel = 0
			iconFrame.Parent = card
			addCorner(iconFrame, 8)

			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(1, 0, 1, 0)
			icon.BackgroundTransparency = 1
			icon.Text = entry.icon
			icon.TextSize = 40
			icon.Parent = iconFrame

			local count = Instance.new("TextLabel")
			count.Size = UDim2.new(1, -12, 0, 14)
			count.Position = UDim2.new(0, 6, 0, 102)
			count.BackgroundTransparency = 1
			count.Text = "x" .. tostring(entry.count)
			count.TextColor3 = UI_CONFIG.COLOR_TEXT_DIM
			count.TextSize = 11
			count.Font = Enum.Font.GothamBold
			count.TextXAlignment = Enum.TextXAlignment.Left
			count.Parent = card

			-- Action button removed per user request: items are now moved via Carts/Transport
		end
	elseif CurrentFilter == "Unit" then
		-- UNIT TAB
		if infoLabel then
			infoLabel.Text = "Your Brainrot collection"
		end

		local display = {}
		for _, item in ipairs(CurrentItems) do
			if item.Type == "Unit" then
				if matchesSearch(item.Name) then
					table.insert(display, item)
				end
			end
		end

		if #display == 0 then
			createEmptyState("No matching units")
		end

		for i, item in ipairs(display) do
			local card = Instance.new("ImageButton")
			card.Name = "UnitCard_" .. i
			card.BackgroundColor3 = UI_CONFIG.COLOR_SLOT
			card.AutoButtonColor = false
			card.LayoutOrder = i
			card.Parent = grid
			addCorner(card, 10)
			addStroke(card, UI_CONFIG.COLOR_ACCENT, 1.7)

			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, -12, 0, 18)
			title.Position = UDim2.new(0, 6, 0, 6)
			title.BackgroundTransparency = 1
			title.Text = item.Name
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.TextColor3 = UI_CONFIG.COLOR_TEXT
			title.TextSize = 11
			title.Font = Enum.Font.GothamBold
			title.Parent = card

			local iconFrame = Instance.new("Frame")
			iconFrame.Size = UDim2.new(1, -14, 0, 70)
			iconFrame.Position = UDim2.new(0, 7, 0, 28)
			iconFrame.BackgroundColor3 = UI_CONFIG.COLOR_SLOT_INNER
			iconFrame.BorderSizePixel = 0
			iconFrame.Parent = card
			addCorner(iconFrame, 8)

			-- 3D Viewport would be better, but for grid, we'll try a static preview
			task.spawn(function()
				local template = getBrainrotTemplate(item.Name)
				if template then
					local preview = ViewportPreview.CreateStatic(template, iconFrame)
					preview.viewport.BackgroundTransparency = 1
				end
			end)

			local levelLine = Instance.new("TextLabel")
			levelLine.Size = UDim2.new(1, -12, 0, 14)
			levelLine.Position = UDim2.new(0, 6, 0, 102)
			levelLine.BackgroundTransparency = 1
			levelLine.Text = "Level " .. (item.Data and item.Data.Level or 1)
			levelLine.TextColor3 = UI_CONFIG.COLOR_TEXT_DIM
			levelLine.TextSize = 10
			levelLine.Font = Enum.Font.Gotham
			levelLine.TextXAlignment = Enum.TextXAlignment.Left
			levelLine.Parent = card

			local statusLine = Instance.new("TextLabel")
			statusLine.Size = UDim2.new(1, -12, 0, 14)
			statusLine.Position = UDim2.new(0, 6, 0, 118)
			statusLine.BackgroundTransparency = 1
			statusLine.Text = item.IsPlaced and "PLACED" or "STORED"
			statusLine.TextColor3 = item.IsPlaced and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 200, 100)
			statusLine.TextSize = 10
			statusLine.Font = Enum.Font.GothamBold
			statusLine.TextXAlignment = Enum.TextXAlignment.Left
			statusLine.Parent = card

			card.MouseButton1Click:Connect(function()
				openDetailPopup(item)
			end)
		end
	else
		-- ARTIFACT TAB
		if infoLabel then
			infoLabel.Text = "Artifacts collected"
		end

		local display = {}
		for _, item in ipairs(CurrentItems) do
			-- Strict Artifact Tab Filter: Only show artifact type
			if item.Type == "Artifact" then
				local slotName = (item.Data and item.Data.Slot) or ""
				if matchesSearch(item.Name) or matchesSearch(item.Rarity or "") or matchesSearch(slotName) then
					table.insert(display, item)
				end
			end
		end

		if #display == 0 then
			createEmptyState("No matching artifacts")
		end

		for i, item in ipairs(display) do
			local card = Instance.new("ImageButton")
			card.Name = "ArtifactCard_" .. i
			card.BackgroundColor3 = UI_CONFIG.COLOR_SLOT
			card.AutoButtonColor = false
			card.LayoutOrder = i
			card.Parent = grid
			addCorner(card, 10)
			addStroke(card, getRarityColor(item.Rarity), 1.7)

			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, -12, 0, 18)
			title.Position = UDim2.new(0, 6, 0, 6)
			title.BackgroundTransparency = 1
			title.Text = item.Name
			title.TextTruncate = Enum.TextTruncate.AtEnd
			title.TextColor3 = UI_CONFIG.COLOR_TEXT
			title.TextSize = 11
			title.Font = Enum.Font.GothamBold
			title.Parent = card

			local iconFrame = Instance.new("Frame")
			iconFrame.Size = UDim2.new(1, -14, 0, 70)
			iconFrame.Position = UDim2.new(0, 7, 0, 28)
			iconFrame.BackgroundColor3 = UI_CONFIG.COLOR_SLOT_INNER
			iconFrame.BorderSizePixel = 0
			iconFrame.Parent = card
			addCorner(iconFrame, 8)

			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(1, 0, 1, 0)
			icon.BackgroundTransparency = 1
			icon.Text = (item.Icon and item.Icon ~= "") and item.Icon or "[Artifact]"
			icon.TextSize = 36
			icon.Parent = iconFrame

			local slotLine = Instance.new("TextLabel")
			slotLine.Size = UDim2.new(1, -12, 0, 14)
			slotLine.Position = UDim2.new(0, 6, 0, 102)
			slotLine.BackgroundTransparency = 1
			slotLine.Text = string.format("%s %s", ArtifactConfig.SlotIcons[(item.Data and item.Data.Slot) or ""] or "[Slot]", (item.Data and item.Data.Slot) or "Unknown")
			slotLine.TextColor3 = UI_CONFIG.COLOR_TEXT_DIM
			slotLine.TextSize = 10
			slotLine.Font = Enum.Font.Gotham
			slotLine.TextXAlignment = Enum.TextXAlignment.Left
			slotLine.Parent = card

			local statText = "No bonus"
			local stats = getArtifactStats(item.Data)
			if stats.CycleTimeMult and stats.CycleTimeMult < 1 then
				statText = "Cycle: -" .. math.floor((1 - stats.CycleTimeMult) * 100) .. "%"
			elseif stats.LuckBonus and stats.LuckBonus > 0 then
				statText = "Luck: +" .. math.floor(stats.LuckBonus * 100) .. "%"
			elseif stats.ItemTierBonus and stats.ItemTierBonus > 0 then
				statText = "Tier: +" .. stats.ItemTierBonus
			elseif stats.SynergyRangeBonus and stats.SynergyRangeBonus > 0 then
				statText = "Range: +" .. stats.SynergyRangeBonus
			end

			local statLine = Instance.new("TextLabel")
			statLine.Size = UDim2.new(1, -12, 0, 14)
			statLine.Position = UDim2.new(0, 6, 0, 118)
			statLine.BackgroundTransparency = 1
			statLine.Text = statText
			statLine.TextColor3 = Color3.fromRGB(175, 215, 255)
			statLine.TextSize = 10
			statLine.Font = Enum.Font.Gotham
			statLine.TextXAlignment = Enum.TextXAlignment.Left
			statLine.Parent = card

			if item.Data and item.Data.EquippedTo then
				local equipped = Instance.new("TextLabel")
				equipped.Size = UDim2.new(0, 30, 0, 14)
				equipped.Position = UDim2.new(1, -34, 0, 6)
				equipped.BackgroundColor3 = Color3.fromRGB(90, 150, 255)
				equipped.Text = "EQ"
				equipped.TextSize = 9
				equipped.TextColor3 = Color3.new(1, 1, 1)
				equipped.Font = Enum.Font.GothamBold
				equipped.Parent = card
				addCorner(equipped, 6)
			end

			card.MouseButton1Click:Connect(function()
				openDetailPopup(item)
			end)

			card.MouseEnter:Connect(function()
				TweenService:Create(card, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(40, 40, 62)}):Play()
			end)
			card.MouseLeave:Connect(function()
				TweenService:Create(card, TweenInfo.new(0.12), {BackgroundColor3 = UI_CONFIG.COLOR_SLOT}):Play()
			end)
		end
	end

	grid.CanvasSize = UDim2.new(0, 0, 0, math.max(0, grid:FindFirstChild("GridLayout").AbsoluteContentSize.Y + 10))
	return finish()
end

--------------------------------------------------------------------------------
-- MAIN GUI
--------------------------------------------------------------------------------

local function createBackpackHUD()
	local screen = Instance.new("ScreenGui")
	screen.Name = "BackpackHUD"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = Instance.new("Frame")
	panel.Name = "MainPanel"
	panel.Size = UDim2.new(0, UI_CONFIG.PANEL_WIDTH, 0, UI_CONFIG.PANEL_HEIGHT)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = UI_CONFIG.COLOR_PANEL
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	addCorner(panel, UI_CONFIG.CORNER_RADIUS)
	addStroke(panel, UI_CONFIG.COLOR_ACCENT, 2)

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 20, 34)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 12, 20)),
	})
	panelGradient.Rotation = 90
	panelGradient.Parent = panel

	local titleChip = Instance.new("Frame")
	titleChip.Name = "TitleChip"
	titleChip.Size = UDim2.new(0, 340, 0, 52)
	titleChip.Position = UDim2.new(0, 16, 0, 12)
	titleChip.BackgroundColor3 = Color3.fromRGB(98, 26, 184)
	titleChip.BorderSizePixel = 0
	titleChip.Parent = panel
	addCorner(titleChip, 10)
	addStroke(titleChip, Color3.fromRGB(175, 120, 255), 1.4)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -16, 1, 0)
	title.Position = UDim2.new(0, 10, 0, 0)
	title.Text = "INVENTORY"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextSize = 34
	title.Font = Enum.Font.GothamBlack
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = titleChip

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 46, 0, 46)
	closeBtn.Position = UDim2.new(1, -60, 0, 16)
	closeBtn.BackgroundColor3 = UI_CONFIG.COLOR_CLOSE
	closeBtn.Text = "X"
	closeBtn.TextSize = 22
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBlack
	closeBtn.Parent = panel
	addCorner(closeBtn, 10)
	addStroke(closeBtn, Color3.fromRGB(120, 20, 30), 1.2)
	closeBtn.MouseButton1Click:Connect(function()
		BackpackVisible = false
		panel.Visible = false
		local popup = screen:FindFirstChild("DetailPopup")
		if popup then popup:Destroy() end
	end)

	local search = Instance.new("TextBox")
	search.Name = "SearchBox"
	search.Size = UDim2.new(0, 360, 0, 34)
	search.Position = UDim2.new(0, 16, 0, 76)
	search.BackgroundColor3 = UI_CONFIG.COLOR_SEARCH_BG
	search.BorderSizePixel = 0
	search.PlaceholderText = "Search..."
	search.Text = ""
	search.ClearTextOnFocus = false
	search.TextColor3 = UI_CONFIG.COLOR_TEXT
	search.PlaceholderColor3 = UI_CONFIG.COLOR_TEXT_DIM
	search.TextSize = 16
	search.Font = Enum.Font.Gotham
	search.TextXAlignment = Enum.TextXAlignment.Left
	search.Parent = panel
	addCorner(search, 8)
	addStroke(search, Color3.fromRGB(65, 65, 95), 1)

	local tabsFrame = Instance.new("Frame")
	tabsFrame.Name = "Tabs"
	tabsFrame.Size = UDim2.new(0, 400, 0, 34)
	tabsFrame.Position = UDim2.new(1, -416, 0, 76)
	tabsFrame.BackgroundTransparency = 1
	tabsFrame.Parent = panel

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 10)
	tabLayout.Parent = tabsFrame

	local function makeTab(name, filter, order)
		local btn = Instance.new("TextButton")
		btn.Name = "Tab_" .. filter
		btn.Size = UDim2.new(0, 145, 1, 0)
		btn.LayoutOrder = order
		btn.Text = name
		btn.TextSize = 14
		btn.Font = Enum.Font.GothamBold
		btn.TextColor3 = Color3.fromRGB(235, 235, 245)
		btn.BackgroundColor3 = UI_CONFIG.COLOR_TAB_IDLE
		btn.BorderSizePixel = 0
		btn.Parent = tabsFrame
		addCorner(btn, 8)

		local function updateTabs()
			for _, tab in tabsFrame:GetChildren() do
				if tab:IsA("TextButton") then
					local isThis = (tab.Name == "Tab_" .. CurrentFilter)
					tab.BackgroundColor3 = isThis and UI_CONFIG.COLOR_TAB_ACTIVE or UI_CONFIG.COLOR_TAB_IDLE
					tab.TextColor3 = isThis and Color3.fromRGB(25, 25, 30) or Color3.fromRGB(235, 235, 245)
				end
			end
		end

		btn.MouseButton1Click:Connect(function()
			CurrentFilter = filter
			updateTabs()
			refreshGrid()
		end)
		return btn
	end

	local unitsTab = makeTab("UNITS", "Unit", 1)
	local _itemsTab = makeTab("ITEMS", "Storage", 2)
	local _artifactTab = makeTab("ARTIFACTS", "Artifact", 3)

	unitsTab.BackgroundColor3 = UI_CONFIG.COLOR_TAB_ACTIVE
	unitsTab.TextColor3 = Color3.fromRGB(25, 25, 30)

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Name = "InfoLabel"
	infoLabel.Size = UDim2.new(1, -32, 0, 18)
	infoLabel.Position = UDim2.new(0, 16, 0, 118)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = ""
	infoLabel.TextColor3 = UI_CONFIG.COLOR_TEXT_DIM
	infoLabel.TextSize = 12
	infoLabel.Font = Enum.Font.Gotham
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.Size = UDim2.new(1, -32, 1, -162)
	scroll.Position = UDim2.new(0, 16, 0, 142)
	scroll.BackgroundColor3 = Color3.fromRGB(11, 11, 20)
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = UI_CONFIG.COLOR_ACCENT
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = panel
	addCorner(scroll, 10)
	addStroke(scroll, Color3.fromRGB(70, 55, 120), 1)

	-- Persistent layout
	local layout = Instance.new("UIGridLayout")
	layout.Name = "GridLayout"
	layout.CellSize = UDim2.new(0, UI_CONFIG.SLOT_SIZE, 0, UI_CONFIG.SLOT_HEIGHT)
	layout.CellPadding = UDim2.new(0, UI_CONFIG.GRID_PADDING, 0, UI_CONFIG.GRID_PADDING)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	search:GetPropertyChangedSignal("Text"):Connect(function()
		if BackpackVisible then
			refreshGrid()
		end
	end)

	return screen
end

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local function loadInventory()
	if not GetUnifiedInventoryFunc then
		warn("BackpackHUD: Cannot load inventory - GetUnifiedInventory function missing!")
		return
	end
	local items = GetUnifiedInventoryFunc:InvokeServer()
	if items then
		CurrentItems = items
		refreshGrid()
	end
end

local function toggleBackpack(filterOverride)
	BackpackVisible = not BackpackVisible
	-- If opening with a specific filter, ensure it's visible and set filter
	if filterOverride and typeof(filterOverride) == "string" then
		CurrentFilter = filterOverride
		BackpackVisible = true -- Force open if filter provided
	end

	if not BackpackGui then
		BackpackGui = createBackpackHUD()
		BackpackGui.Parent = PlayerGui
	end
	
	local panel = BackpackGui:FindFirstChild("MainPanel")
	panel.Visible = BackpackVisible

	if not BackpackVisible then
		local popup = BackpackGui:FindFirstChild("DetailPopup")
		if popup then popup:Destroy() end
		return
	end
	
	if BackpackVisible then
		for _, tab in panel:FindFirstChild("Tabs"):GetChildren() do
			if tab:IsA("TextButton") then
				local filter = string.gsub(tab.Name, "Tab_", "")
				local isThis = (filter == CurrentFilter)
				tab.BackgroundColor3 = isThis and UI_CONFIG.COLOR_TAB_ACTIVE or UI_CONFIG.COLOR_TAB_IDLE
				tab.TextColor3 = isThis and Color3.fromRGB(25, 25, 30) or Color3.fromRGB(235, 235, 245)
			end
		end
		loadInventory()
	end
end

-- Events
local BackpackToggleEvent = ReplicatedStorage:FindFirstChild("BackpackToggleEvent")
if not BackpackToggleEvent then
	BackpackToggleEvent = Instance.new("BindableEvent")
	BackpackToggleEvent.Name = "BackpackToggleEvent"
	BackpackToggleEvent.Parent = ReplicatedStorage
end
BackpackToggleEvent.Event:Connect(toggleBackpack)

-- Listen for updates from Server-side InventoryService
local function onUpdate()
	if BackpackVisible then
		loadInventory()
	end
end

if InventoryChangedEvent then InventoryChangedEvent.OnClientEvent:Connect(onUpdate) end

local ArtifactDropped = RemoteEvents:FindFirstChild("ArtifactDropped")
if ArtifactDropped then ArtifactDropped.OnClientEvent:Connect(onUpdate) end
local ArtifactEquipped = RemoteEvents:FindFirstChild("ArtifactEquipped")
if ArtifactEquipped then ArtifactEquipped.OnClientEvent:Connect(onUpdate) end

-- Listen for storage updates
if StorageUpdatedEvent then
	StorageUpdatedEvent.OnClientEvent:Connect(function()
		if BackpackVisible and CurrentFilter == "Storage" then
			refreshGrid()
		end
	end)
end

-- Consume ItemProduced event to drain the queue warning
if ItemProducedEvent then
	ItemProducedEvent.OnClientEvent:Connect(function(_producedItems)
		-- For now, just drain the queue to avoid exhaustion warnings
	end)
end

print("✓ [BackpackHUD] Client script fully loaded and ready")


