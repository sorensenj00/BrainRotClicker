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
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local _ItemTypes = require(Shared:WaitForChild("ItemTypes"))
local _ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))
local _ShopConfig = require(Shared:WaitForChild("ShopConfig"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local GetUnifiedInventoryFunc = RemoteFunctions:WaitForChild("GetUnifiedInventory")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

-- Storage remotes
local GetStorageFunction = RemoteFunctions:WaitForChild("GetStorage")
local StorageUpdatedEvent = RemoteEvents:WaitForChild("StorageUpdated")
local TakeFromStorageEvent = RemoteEvents:FindFirstChild("TakeFromStorage") or Instance.new("RemoteEvent")
TakeFromStorageEvent.Name = "TakeFromStorage"
TakeFromStorageEvent.Parent = RemoteEvents

-- Folders for 3D preview
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")

local UI_CONFIG = {
	PANEL_WIDTH = 500,
	PANEL_HEIGHT = 600,
	SLOT_SIZE = 70, -- Larger slots for better visibility
	GRID_PADDING = 6,
	CORNER_RADIUS = 16,
	
	COLOR_BG = Color3.fromRGB(25, 25, 35),
	COLOR_PANEL = Color3.fromRGB(35, 35, 45),
	COLOR_SLOT = Color3.fromRGB(45, 45, 55),
	COLOR_ACCENT = Color3.fromRGB(100, 150, 255),
	COLOR_TEXT = Color3.fromRGB(240, 240, 240),
	COLOR_TEXT_DIM = Color3.fromRGB(150, 150, 160),
	
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
local CurrentFilter = "All" -- "All", "Unit", "Artifact", "Storage"

-- Storage state
local CurrentStorageItems = {} -- {[itemId] = count}
local StorageUsage = 0

-- Hover tooltip state
local CurrentHoverTooltip = nil
local HoverDelayThread = nil
local StorageCapacity = 0 -- Updated via Player Attribute

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function getRarityColor(rarity)
	return UI_CONFIG.RARITY_COLORS[rarity] or UI_CONFIG.RARITY_COLORS.Normal
end

--[[
	Checks if player is standing on their own island.
	Used to enable/disable taking items from storage.
]]
local function isOnOwnIsland()
	local character = Player.Character
	if not character then return false end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	
	local playerPos = hrp.Position
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return false end
	
	for _, plot in plotsFolder:GetChildren() do
		local ownerId = plot:GetAttribute("OwnerId")
		if ownerId == Player.UserId then
			-- Find the floor part
			local floor = plot:FindFirstChild("Island")
				or plot:FindFirstChild("PlotFloor")
				or plot:FindFirstChild("Floor")
				or plot:FindFirstChildWhichIsA("BasePart")
			
			if floor then
				local floorPos = floor.Position
				local floorSize = floor.Size
				
				-- Check if player is within plot bounds (XZ)
				local dx = math.abs(playerPos.X - floorPos.X)
				local dz = math.abs(playerPos.Z - floorPos.Z)
				
				if dx <= floorSize.X / 2 + 10 and dz <= floorSize.Z / 2 + 10 then
					return true
				end
			end
		end
	end
	
	return false
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
-- HOVER TOOLTIP
--------------------------------------------------------------------------------

local function clearHoverTooltip()
	if HoverDelayThread then
		-- pcall because thread may have already completed
		pcall(function()
			task.cancel(HoverDelayThread)
		end)
		HoverDelayThread = nil
	end
	
	if CurrentHoverTooltip then
		-- Fade out smoothly
		local tooltip = CurrentHoverTooltip
		CurrentHoverTooltip = nil
		
		local fadeOut = TweenService:Create(tooltip, TweenInfo.new(UI_CONFIG.TOOLTIP_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
			GroupTransparency = 1
		})
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if tooltip and tooltip.Parent then
				tooltip:Destroy()
			end
		end)
	end
end

local function spawn3DPreviewForTooltip(viewport, unitName)
	viewport:ClearAllChildren()
	
	local template = getBrainrotTemplate(unitName)
	if not template then return end
	
	local model = template:Clone()
	model.Parent = viewport
	
	-- Setup Camera
	local cam = Instance.new("Camera")
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	
	local success, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not success then return end
	
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dist = maxDim * 2.5 -- Further back for better framing
	
	-- Calculate center of model (vertically centered)
	local modelCenter = cf.Position
	
	-- Rotate model with camera positioned at eye level
	local rotation = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not model.Parent then 
			connection:Disconnect()
			return 
		end
		rotation = rotation + dt * 0.5
		local rotCFrame = CFrame.Angles(0, rotation, 0)
		-- Camera positioned at model's vertical center, slightly elevated
		local camHeight = size.Y * 0.3
		local newPos = modelCenter + (rotCFrame * Vector3.new(0, camHeight, dist))
		cam.CFrame = CFrame.new(newPos, modelCenter)
	end)
end

local function createHoverTooltip(item, slotPosition)
	clearHoverTooltip()
	
	-- Guard: need a valid GUI parent
	local guiParent = BackpackGui or PlayerGui:FindFirstChild("BackpackHUD")
	if not guiParent then
		warn("BackpackHUD: No GUI parent for hover tooltip")
		return
	end
	
	local tooltip = Instance.new("CanvasGroup")
	tooltip.Name = "HoverTooltip"
	tooltip.Size = UDim2.new(0, 220, 0, 280)
	tooltip.BackgroundColor3 = UI_CONFIG.COLOR_BG
	tooltip.BorderSizePixel = 0
	tooltip.GroupTransparency = 1 -- Start invisible for fade-in
	tooltip.ZIndex = 200
	
	-- Position tooltip to the right of cursor, with screen boundary check
	local screenSize = guiParent.AbsoluteSize
	local tooltipX = slotPosition.X + 80 -- Offset to the right of the slot
	local tooltipY = slotPosition.Y
	
	-- Keep tooltip on screen
	if tooltipX + 220 > screenSize.X then
		tooltipX = slotPosition.X - 230 -- Show on left if no room on right
	end
	if tooltipY + 280 > screenSize.Y then
		tooltipY = screenSize.Y - 290
	end
	if tooltipY < 10 then
		tooltipY = 10
	end
	
	tooltip.Position = UDim2.new(0, tooltipX, 0, tooltipY)
	tooltip.Parent = guiParent
	
	addCorner(tooltip, 12)
	addStroke(tooltip, getRarityColor(item.Rarity), 2)
	
	-- Content padding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = tooltip
	
	local content = Instance.new("Frame")
	content.Size = UDim2.new(1, 0, 1, 0)
	content.BackgroundTransparency = 1
	content.Parent = tooltip
	
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = content
	
	-- Header with rarity glow
	local header = Instance.new("TextLabel")
	header.Text = item.Rarity .. "  " .. item.Name
	header.TextColor3 = getRarityColor(item.Rarity)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 14
	header.TextTruncate = Enum.TextTruncate.AtEnd
	header.Size = UDim2.new(1, 0, 0, 20)
	header.BackgroundTransparency = 1
	header.LayoutOrder = 1
	header.Parent = content
	
	-- Preview area
	local previewFrame = Instance.new("Frame")
	previewFrame.Size = UDim2.new(0, 140, 0, 140)
	previewFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	previewFrame.LayoutOrder = 2
	previewFrame.Parent = content
	addCorner(previewFrame, 8)
	
	if item.Type == "Unit" then
		local vp = Instance.new("ViewportFrame")
		vp.Size = UDim2.new(1, 0, 1, 0)
		vp.BackgroundTransparency = 1
		vp.Parent = previewFrame
		spawn3DPreviewForTooltip(vp, item.UUID)
	else
		-- Fallback icon logic if item.Icon is missing
		local displayIcon = item.Icon
		if not displayIcon or displayIcon == "" then
			-- Try to look up based on base ID/Name if possible, or use generic
			displayIcon = "⚔️" -- Generic artifact icon
		end
		
		local iconLabel = Instance.new("TextLabel")
		iconLabel.Text = displayIcon
		iconLabel.Size = UDim2.new(1, 0, 1, 0)
		iconLabel.BackgroundTransparency = 1
		iconLabel.TextSize = 60
		iconLabel.Parent = previewFrame
	end
	
	-- Slot/Status line
	local statusLabel = Instance.new("TextLabel")
	if item.Type == "Unit" then
		statusLabel.Text = item.IsPlaced and "Slot: Placed" or "Slot: Inventory"
	else
		statusLabel.Text = "Slot: " .. (item.Data.EquippedTo and "Equipped" or "Inventory")
	end
	statusLabel.TextColor3 = UI_CONFIG.COLOR_TEXT_DIM
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 11
	statusLabel.Size = UDim2.new(1, 0, 0, 16)
	statusLabel.BackgroundTransparency = 1
	statusLabel.LayoutOrder = 3
	statusLabel.Parent = content
	
	-- Stats section
	local statsFrame = Instance.new("Frame")
	statsFrame.Size = UDim2.new(1, 0, 0, 60)
	statsFrame.BackgroundTransparency = 1
	statsFrame.LayoutOrder = 4
	statsFrame.Parent = content
	
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.Padding = UDim.new(0, 3)
	statsLayout.Parent = statsFrame
	
	local function addStat(text, color)
		local l = Instance.new("TextLabel")
		l.Text = text
		l.TextColor3 = color or UI_CONFIG.COLOR_TEXT
		l.TextSize = 12
		l.Font = Enum.Font.Gotham
		l.Size = UDim2.new(1, 0, 0, 14)
		l.BackgroundTransparency = 1
		l.Parent = statsFrame
	end
	
	if item.Type == "Unit" then
		addStat("⭐ Level: " .. (item.Data.Level or 1), Color3.fromRGB(255, 220, 100))
	else
		local stats = item.Data.Stats or {}
		if stats.CycleTimeMult and stats.CycleTimeMult ~= 1 then
			local p = math.round((1 - stats.CycleTimeMult) * 100)
			addStat("⚡ Cycle Time: -" .. p .. "%", Color3.fromRGB(255, 255, 100))
		end
		if stats.ItemTierBonus and stats.ItemTierBonus > 0 then
			addStat("⭐ Tier: +" .. stats.ItemTierBonus, Color3.fromRGB(255, 200, 100))
		end
		if stats.LuckBonus and stats.LuckBonus > 0 then
			addStat("🍀 Luck: +" .. stats.LuckBonus, Color3.fromRGB(100, 255, 100))
		end
	end
	
	CurrentHoverTooltip = tooltip
	
	-- Smooth fade in
	local fadeIn = TweenService:Create(tooltip, TweenInfo.new(UI_CONFIG.TOOLTIP_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 0
	})
	fadeIn:Play()
end

local function scheduleHoverTooltip(item, slot)
	clearHoverTooltip()
	
	HoverDelayThread = task.delay(UI_CONFIG.HOVER_DELAY, function()
		if slot and slot.Parent then
			local slotPos = slot.AbsolutePosition
			createHoverTooltip(item, slotPos)
		end
		HoverDelayThread = nil
	end)
end

--------------------------------------------------------------------------------
-- DETAIL POPUP
--------------------------------------------------------------------------------

local function spawn3DPreview(viewport, unitName)
	viewport:ClearAllChildren()
	
	local template = getBrainrotTemplate(unitName)
	if not template then return end
	
	local model = template:Clone()
	model.Parent = viewport
	
	-- Setup Camera
	local cam = Instance.new("Camera")
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	
	local cf, size = model:GetBoundingBox()
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dist = maxDim * 2
	
	-- Rotate model
	local rotation = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not model.Parent then 
			connection:Disconnect()
			return 
		end
		rotation = rotation + dt * 0.5
		local rotCFrame = CFrame.Angles(0, rotation, 0)
		local newPos = cf.Position + (rotCFrame * Vector3.new(0, maxDim*0.2, dist))
		cam.CFrame = CFrame.new(newPos, cf.Position)
	end)
end

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
	addStroke(popup, getRarityColor(item.Rarity), 2)
	
	-- Close Button (Top Right)
	local close = Instance.new("TextButton")
	close.Text = "✕"
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
	header.Text = item.Name
	header.TextColor3 = getRarityColor(item.Rarity)
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
		local vp = Instance.new("ViewportFrame")
		vp.Size = UDim2.new(1, 0, 1, 0)
		vp.BackgroundTransparency = 1
		vp.Parent = previewFrame
		spawn3DPreview(vp, item.UUID) -- UUID is unitName for units
		
	elseif item.Type == "Artifact" then
		-- Icon Image
		local icon = Instance.new("TextLabel") -- Using TextLabel for emoji icons?
		-- If Icon is an asset ID, use ImageLabel. If emoji, use TextLabel.
		-- Artifact system uses generic Image/Emoji.
		
		-- FALLBACK LOGIC
		local displayIcon = item.Icon
		if not displayIcon or displayIcon == "" then
			displayIcon = "⚔️" -- Generic fallback
		end
		
		icon.Text = displayIcon
		icon.Size = UDim2.new(1,0,1,0)
		icon.BackgroundTransparency = 1
		icon.TextSize = 100
		icon.Parent = previewFrame
	end
	
	-- 3. Stats / Info
	local infoFrame = Instance.new("Frame")
	infoFrame.Size = UDim2.new(1, 0, 0, 100)
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
		addLine("Slot: " .. (item.Data.EquippedTo and "Equipped" or "Inventory"), UI_CONFIG.COLOR_TEXT_DIM)
		
		local stats = item.Data.Stats or {}
		if stats.CycleTimeMult and stats.CycleTimeMult ~= 1 then
			local p = math.round((1 - stats.CycleTimeMult) * 100)
			addLine("⚡ Cycle Time: -" .. p .. "%", Color3.fromRGB(255,255,100))
		end
		if stats.LuckBonus and stats.LuckBonus > 0 then
			addLine("🍀 Luck: +" .. stats.LuckBonus, Color3.fromRGB(100,255,100))
		end
		if stats.ItemTierBonus and stats.ItemTierBonus > 0 then
			addLine("⭐ Tier: +" .. stats.ItemTierBonus, Color3.fromRGB(255,100,255))
		end
	end
end

--------------------------------------------------------------------------------
-- GRID UI
--------------------------------------------------------------------------------

local IsRefreshing = false -- Debounce flag to prevent duplicate renders

local function refreshGrid()
	-- Debounce to prevent duplicate renders from rapid event firing
	if IsRefreshing then return end
	IsRefreshing = true
	task.defer(function() IsRefreshing = false end)
	
	if not BackpackGui then
		IsRefreshing = false
		return
	end
	local mainPanel = BackpackGui:FindFirstChild("MainPanel")
	if not mainPanel then
		IsRefreshing = false
		return
	end
	local grid = mainPanel:FindFirstChild("Grid")
	if not grid then
		IsRefreshing = false
		return
	end
	
	-- Clean ALL children (including layouts) to prevent duplicates
	for _, c in pairs(grid:GetChildren()) do
		c:Destroy()
	end
	
local function decodeItems(encoded)
	if type(encoded) ~= "table" then return encoded end
	local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
	local success, IC = pcall(function() return require(Shared:WaitForChild("ItemConfig")) end)
	if not success or not IC or not IC.SHORT_TO_ID then return encoded end
	local decoded = {}
	for k, count in pairs(encoded) do
		local shortId = tonumber(k)
		if shortId and IC.SHORT_TO_ID[shortId] then
			decoded[IC.SHORT_TO_ID[shortId]] = count
		else
			decoded[k] = count
		end
	end
	return decoded
end

	-- If Storage tab, show storage items instead
	if CurrentFilter == "Storage" then
		-- Fetch storage data from server
		local success, items, total, capacity = pcall(function()
			return GetStorageFunction:InvokeServer()
		end)
		
		if not success or not items then
			items = {}
			total = 0
			capacity = 2000
		end
		
		CurrentStorageItems = decodeItems(items)
		StorageUsage = total or 0
		StorageCapacity = Player:GetAttribute("StorageCapacity") or capacity or 0
		
		local onIsland = isOnOwnIsland()
		
		-- Storage header showing total
		local header = Instance.new("Frame")
		header.Name = "StorageHeader"
		header.Size = UDim2.new(1, 0, 0, 44)
		header.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		header.BackgroundTransparency = 0.3
		header.LayoutOrder = 0
		header.Parent = grid
		addCorner(header, 8)
		
		local headerText = Instance.new("TextLabel")
		headerText.Text = string.format("📦 %d / %d", StorageUsage, StorageCapacity)
		headerText.Size = UDim2.new(0, 100, 1, 0)
		headerText.Position = UDim2.new(0, 8, 0, 0)
		headerText.BackgroundTransparency = 1
		headerText.TextColor3 = UI_CONFIG.COLOR_TEXT
		headerText.TextSize = 13
		headerText.Font = Enum.Font.GothamBold
		headerText.TextXAlignment = Enum.TextXAlignment.Left
		headerText.Parent = header
		
		-- Take All button (center)
		local takeAllBtn = Instance.new("TextButton")
		takeAllBtn.Name = "TakeAllButton"
		takeAllBtn.Text = onIsland and "📥 Take All" or "🔒"
		takeAllBtn.Size = UDim2.new(0, 80, 0, 28)
		takeAllBtn.Position = UDim2.new(0.5, -40, 0.5, -14)
		takeAllBtn.BackgroundColor3 = onIsland and Color3.fromRGB(80, 160, 80) or Color3.fromRGB(60, 60, 60)
		takeAllBtn.TextColor3 = Color3.new(1, 1, 1)
		takeAllBtn.TextSize = 11
		takeAllBtn.Font = Enum.Font.GothamBold
		takeAllBtn.AutoButtonColor = onIsland
		takeAllBtn.Parent = header
		addCorner(takeAllBtn, 6)
		
		if onIsland then
			takeAllBtn.MouseButton1Click:Connect(function()
				-- Take all items from storage
				for itemId, count in pairs(CurrentStorageItems) do
					if count > 0 then
						TakeFromStorageEvent:FireServer(itemId, count)
					end
				end
				-- Refresh after short delay
				task.wait(0.3)
				refreshGrid()
			end)
			
			-- Hover effect
			takeAllBtn.MouseEnter:Connect(function()
				TweenService:Create(takeAllBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(100, 200, 100)}):Play()
			end)
			takeAllBtn.MouseLeave:Connect(function()
				TweenService:Create(takeAllBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(80, 160, 80)}):Play()
			end)
		end
		
		-- Island status indicator (right side)
		local statusLabel = Instance.new("TextLabel")
		statusLabel.Text = onIsland and "✓ On Island" or "⚠ Go to island"
		statusLabel.Size = UDim2.new(0, 90, 1, 0)
		statusLabel.Position = UDim2.new(1, -95, 0, 0)
		statusLabel.BackgroundTransparency = 1
		statusLabel.TextColor3 = onIsland and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 150, 100)
		statusLabel.TextSize = 10
		statusLabel.Font = Enum.Font.Gotham
		statusLabel.TextXAlignment = Enum.TextXAlignment.Right
		statusLabel.Parent = header
		
		-- Create storage item slots
		local itemIndex = 1
		for itemId, count in pairs(CurrentStorageItems) do
			if count > 0 then
				local itemInfo = ItemConfig.Items[itemId]
				local icon = itemInfo and itemInfo.icon or "📦"
				local displayName = itemInfo and itemInfo.displayName or itemId
				
				local slot = Instance.new("Frame")
				slot.Name = "StorageSlot_" .. itemIndex
				slot.Size = UDim2.new(1, 0, 0, 55)
				slot.BackgroundColor3 = UI_CONFIG.COLOR_SLOT
				slot.LayoutOrder = itemIndex
				slot.Parent = grid
				addCorner(slot, 8)
				addStroke(slot, UI_CONFIG.COLOR_ACCENT, 1)
				
				-- Icon
				local iconLabel = Instance.new("TextLabel")
				iconLabel.Text = icon
				iconLabel.Size = UDim2.new(0, 40, 0, 40)
				iconLabel.Position = UDim2.new(0, 5, 0.5, -20)
				iconLabel.BackgroundTransparency = 1
				iconLabel.TextSize = 28
				iconLabel.Parent = slot
				
				-- Name + Count
				local nameLabel = Instance.new("TextLabel")
				nameLabel.Text = displayName
				nameLabel.Size = UDim2.new(0.45, 0, 0, 20)
				nameLabel.Position = UDim2.new(0, 50, 0, 8)
				nameLabel.BackgroundTransparency = 1
				nameLabel.TextColor3 = UI_CONFIG.COLOR_TEXT
				nameLabel.TextSize = 13
				nameLabel.Font = Enum.Font.GothamBold
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.Parent = slot
				
				local countLabel = Instance.new("TextLabel")
				countLabel.Text = "x" .. count
				countLabel.Size = UDim2.new(0.45, 0, 0, 18)
				countLabel.Position = UDim2.new(0, 50, 0, 28)
				countLabel.BackgroundTransparency = 1
				countLabel.TextColor3 = UI_CONFIG.COLOR_TEXT_DIM
				countLabel.TextSize = 12
				countLabel.Font = Enum.Font.Gotham
				countLabel.TextXAlignment = Enum.TextXAlignment.Left
				countLabel.Parent = slot
				
				-- Take button
				local takeBtn = Instance.new("TextButton")
				takeBtn.Name = "TakeButton"
				takeBtn.Text = onIsland and "Take" or "🔒"
				takeBtn.Size = UDim2.new(0, 60, 0, 32)
				takeBtn.Position = UDim2.new(1, -70, 0.5, -16)
				takeBtn.BackgroundColor3 = onIsland and Color3.fromRGB(80, 160, 80) or Color3.fromRGB(80, 80, 80)
				takeBtn.TextColor3 = Color3.new(1, 1, 1)
				takeBtn.TextSize = 12
				takeBtn.Font = Enum.Font.GothamBold
				takeBtn.AutoButtonColor = onIsland
				takeBtn.Parent = slot
				addCorner(takeBtn, 6)
				
				if onIsland then
					takeBtn.MouseButton1Click:Connect(function()
						-- Request take from server (take 1 at a time for now)
						TakeFromStorageEvent:FireServer(itemId, 1)
						-- Refresh after a short delay
						task.wait(0.2)
						refreshGrid()
					end)
					
					-- Hover effect
					takeBtn.MouseEnter:Connect(function()
						TweenService:Create(takeBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(100, 200, 100)}):Play()
					end)
					takeBtn.MouseLeave:Connect(function()
						TweenService:Create(takeBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(80, 160, 80)}):Play()
					end)
				end
				
				itemIndex = itemIndex + 1
			end
		end
		
		-- If no items
		if itemIndex == 1 then
			local emptyLabel = Instance.new("TextLabel")
			emptyLabel.Text = "Storage is empty"
			emptyLabel.Size = UDim2.new(1, 0, 0, 50)
			emptyLabel.LayoutOrder = 1
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.TextColor3 = UI_CONFIG.COLOR_TEXT_DIM
			emptyLabel.TextSize = 14
			emptyLabel.Font = Enum.Font.Gotham
			emptyLabel.Parent = grid
		end
		
		-- Change to list layout for Storage
		local existingLayout = grid:FindFirstChildOfClass("UIGridLayout")
		if existingLayout then existingLayout:Destroy() end
		
		local listLayout = grid:FindFirstChildOfClass("UIListLayout")
		if not listLayout then
			listLayout = Instance.new("UIListLayout")
			listLayout.SortOrder = Enum.SortOrder.LayoutOrder
			listLayout.Padding = UDim.new(0, 8)
			listLayout.Parent = grid
		end
		
		return
	end
	
	-- Standard grid layout for non-storage items
	local existingList = grid:FindFirstChildOfClass("UIListLayout")
	if existingList then existingList:Destroy() end
	
	local existingGrid = grid:FindFirstChildOfClass("UIGridLayout")
	if not existingGrid then
		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = UDim2.new(0, UI_CONFIG.SLOT_SIZE, 0, UI_CONFIG.SLOT_SIZE)
		gridLayout.CellPadding = UDim2.new(0, UI_CONFIG.GRID_PADDING, 0, UI_CONFIG.GRID_PADDING)
		gridLayout.Parent = grid
	end
	
	-- Filter Items
	local displayItems = {}
	for _, item in ipairs(CurrentItems) do
		if CurrentFilter == "All" or item.Type == CurrentFilter then
			table.insert(displayItems, item)
		end
	end
	
	-- Create Slots
	for i, item in ipairs(displayItems) do
		local slot = Instance.new("ImageButton")
		slot.Name = "Slot_" .. i
		slot.BackgroundColor3 = UI_CONFIG.COLOR_SLOT
		slot.AutoButtonColor = false
		slot.Parent = grid
		addCorner(slot, 8)
		addStroke(slot, getRarityColor(item.Rarity), 1.5)
		
		-- Icon
		local icon = Instance.new("TextLabel")
		
		-- robust fallback for icon
		local displayIcon = item.Icon
		if not displayIcon or displayIcon == "" then
			displayIcon = "❓"
			if item.Type == "Artifact" then
				displayIcon = "⚔️"
			elseif item.Type == "Unit" then
				displayIcon = "👤"
			end
		end
		
		icon.Text = displayIcon
		icon.Size = UDim2.new(1,0,1,0)
		icon.BackgroundTransparency = 1
		icon.TextSize = 24
		icon.Parent = slot
		
		-- Level badge (for Units)
		if item.Type == "Unit" and item.Data and item.Data.Level then
			local levelBadge = Instance.new("Frame")
			levelBadge.Name = "LevelBadge"
			levelBadge.Size = UDim2.new(0, 22, 0, 16)
			levelBadge.Position = UDim2.new(0, 2, 1, -18)
			levelBadge.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
			levelBadge.BorderSizePixel = 0
			levelBadge.Parent = slot
			addCorner(levelBadge, 4)
			addStroke(levelBadge, Color3.fromRGB(255, 200, 100), 1)
			
			local levelLabel = Instance.new("TextLabel")
			levelLabel.Text = "Lv" .. item.Data.Level
			levelLabel.Size = UDim2.new(1, 0, 1, 0)
			levelLabel.BackgroundTransparency = 1
			levelLabel.TextSize = 10
			levelLabel.Font = Enum.Font.GothamBold
			levelLabel.TextColor3 = Color3.fromRGB(255, 220, 100)
			levelLabel.Parent = levelBadge
		end
		
		-- Placed/Equipped indicator
		if item.IsPlaced or item.IsEquipped then
			local ind = Instance.new("Frame")
			ind.Size = UDim2.new(0, 14, 0, 14)
			ind.Position = UDim2.new(1, -16, 0, 2)
			ind.BackgroundColor3 = item.IsPlaced and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(100, 180, 255)
			ind.BorderSizePixel = 0
			ind.Parent = slot
			addCorner(ind, 7)
			
			local sLabel = Instance.new("TextLabel")
			sLabel.Text = item.IsPlaced and "✓" or "E"
			sLabel.Size = UDim2.new(1,0,1,0)
			sLabel.BackgroundTransparency = 1
			sLabel.TextSize = 9
			sLabel.Font = Enum.Font.GothamBold
			sLabel.TextColor3 = Color3.new(0,0,0)
			sLabel.Parent = ind
		end
		
		-- Click to open detail
		slot.MouseButton1Click:Connect(function()
			clearHoverTooltip()
			openDetailPopup(item)
		end)
		
		-- Hover effect with smooth scale and tooltip
		slot.MouseEnter:Connect(function()
			-- Smooth background color change
			TweenService:Create(slot, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = Color3.fromRGB(65, 65, 80)
			}):Play()
			
			-- Get the stroke and make it brighter
			local stroke = slot:FindFirstChildOfClass("UIStroke")
			if stroke then
				local originalColor = getRarityColor(item.Rarity)
				local brighterColor = Color3.new(
					math.min(originalColor.R * 1.3, 1),
					math.min(originalColor.G * 1.3, 1),
					math.min(originalColor.B * 1.3, 1)
				)
				TweenService:Create(stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
					Color = brighterColor,
					Thickness = 2.5
				}):Play()
			end
			
			-- Schedule hover tooltip
			scheduleHoverTooltip(item, slot)
		end)
		
		slot.MouseLeave:Connect(function()
			-- Smooth background color reset
			TweenService:Create(slot, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = UI_CONFIG.COLOR_SLOT
			}):Play()
			
			-- Reset stroke
			local stroke = slot:FindFirstChildOfClass("UIStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
					Color = getRarityColor(item.Rarity),
					Thickness = 1.5
				}):Play()
			end
			
			-- Clear hover tooltip
			clearHoverTooltip()
		end)
	end
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
	panel.Visible = false
	panel.Parent = screen
	addCorner(panel, UI_CONFIG.CORNER_RADIUS)
	addStroke(panel, Color3.fromRGB(60,60,80), 2)
	
	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 50)
	header.BackgroundTransparency = 1
	header.Parent = panel
	
	local title = Instance.new("TextLabel")
	title.Text = "🎒 BACKPACK"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.TextColor3 = UI_CONFIG.COLOR_TEXT
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.new(0, 20, 0, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.BackgroundTransparency = 1
	title.Parent = header
	
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = "✕"
	closeBtn.TextSize = 24
	closeBtn.TextColor3 = Color3.fromRGB(200, 80, 80)
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.Position = UDim2.new(1, -50, 0, 5)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = header
	closeBtn.MouseButton1Click:Connect(function()
		BackpackVisible = false
		panel.Visible = false
		local popup = screen:FindFirstChild("DetailPopup")
		if popup then popup:Destroy() end
	end)
	
	-- Filter Tabs
	local tabsFrame = Instance.new("Frame")
	tabsFrame.Size = UDim2.new(1, -40, 0, 36)
	tabsFrame.Position = UDim2.new(0, 20, 0, 50)
	tabsFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	tabsFrame.Parent = panel
	addCorner(tabsFrame, 8)
	
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Parent = tabsFrame
	
	local function createTab(name, filter)
		local t = Instance.new("TextButton")
		t.Text = name
		t.Size = UDim2.new(0.25, 0, 1, 0)
		t.BackgroundTransparency = 1
		t.TextColor3 = UI_CONFIG.COLOR_TEXT
		t.TextSize = 11
		t.Font = Enum.Font.GothamBold
		t.Parent = tabsFrame
		
		t.MouseButton1Click:Connect(function()
			CurrentFilter = filter
			-- Visual update for tabs could go here
			refreshGrid()
		end)
	end
	
	createTab("ALL", "All")
	createTab("UNITS", "Unit")
	createTab("ARTIFACTS", "Artifact")
	createTab("STORAGE", "Storage")
	
	-- Grid Scroll
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Grid"
	scroll.Size = UDim2.new(1, -40, 1, -110)
	scroll.Position = UDim2.new(0, 20, 0, 100)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 6
	scroll.Parent = panel
	
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, UI_CONFIG.SLOT_SIZE, 0, UI_CONFIG.SLOT_SIZE)
	gridLayout.CellPadding = UDim2.new(0, UI_CONFIG.GRID_PADDING, 0, UI_CONFIG.GRID_PADDING)
	gridLayout.Parent = scroll
	
	return screen
end

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local function loadInventory()
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
	
	if BackpackVisible then
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

-- Listen for updates from Server-side InventoryService? 
-- The plan said "InventoryChanged" (Units) and "ArtifactDropped" (Artifacts).
-- Let's listen to those and re-fetch if Backpack is open.

local function onUpdate()
	if BackpackVisible then
		loadInventory()
	end
end

local InventoryChanged = RemoteEvents:FindFirstChild("InventoryChanged")
if InventoryChanged then InventoryChanged.OnClientEvent:Connect(onUpdate) end

local ArtifactDropped = RemoteEvents:FindFirstChild("ArtifactDropped")
if ArtifactDropped then ArtifactDropped.OnClientEvent:Connect(onUpdate) end

-- Listen for storage updates to refresh when in Storage tab
StorageUpdatedEvent.OnClientEvent:Connect(function()
	if BackpackVisible and CurrentFilter == "Storage" then
		refreshGrid()
	end
end)

-- Auto-refresh timer for Storage tab (every 2 seconds)
task.spawn(function()
	while true do
		task.wait(2)
		if BackpackVisible and CurrentFilter == "Storage" then
			refreshGrid()
		end
	end
end)
