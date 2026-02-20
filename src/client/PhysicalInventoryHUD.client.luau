--[[
	PhysicalInventoryHUD Client Script
	
	Displays contents/capacity HUDs above physical Storage Boxes and Transport Carts.
	Uses BillboardGuis to show top 3 items and a progress bar for capacity.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

-- Remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")

local StorageUpdatedEvent = RemoteEvents:WaitForChild("StorageUpdated")
local CartUpdateEvent = RemoteEvents:WaitForChild("CartUpdate")
local GetStorageFunction = RemoteFunctions:WaitForChild("GetStorage")
local GetVehicleInfoFunction = RemoteFunctions:WaitForChild("GetVehicleInfo")

-- Configuration (Linked styling with UnitHUD)
local HUD_CONFIG = {
	BILLBOARD_SIZE = UDim2.new(0, 150, 0, 90),
	MAX_DISTANCE = 120,
	CARD_BACKGROUND = Color3.fromRGB(15, 15, 22),
	CARD_STROKE_COLOR = Color3.fromRGB(70, 70, 90),
	CORNER_RADIUS = 10,
	BAR_HEIGHT = 8,
	BAR_BACKGROUND_COLOR = Color3.fromRGB(25, 25, 35),
	BAR_FILL_STORAGE = Color3.fromRGB(60, 160, 255),
	BAR_FILL_CART = Color3.fromRGB(80, 230, 120),
	TEXT_COLOR = Color3.fromRGB(240, 240, 255),
	SUBTEXT_COLOR = Color3.fromRGB(160, 160, 180),
}

local STORAGE_TAG = "PhysicalStorageHUD"
local CART_TAG = "PhysicalCartHUD"

-- State tracking
local ActiveHUDs: {[Instance]: {billboard: BillboardGui, type: string}} = {}

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createBillboard(target: Instance, title: string, fillCol: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "InventoryHUD"
	billboard.Size = HUD_CONFIG.BILLBOARD_SIZE
	billboard.StudsOffset = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = HUD_CONFIG.MAX_DISTANCE
	billboard.LightInfluence = 0
	billboard.Adornee = target
	
	-- Main card
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	card.BackgroundTransparency = 0.25
	card.BorderSizePixel = 0
	card.Parent = billboard
	
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, HUD_CONFIG.CORNER_RADIUS)
	cardCorner.Parent = card
	
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = HUD_CONFIG.CARD_STROKE_COLOR
	cardStroke.Thickness = 1.5
	cardStroke.Transparency = 0.5
	cardStroke.Parent = card
	
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HUD_CONFIG.CARD_BACKGROUND),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 10, 15))
	})
	gradient.Rotation = 90
	gradient.Parent = card
	
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = card
	
	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0, 14)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = title
	titleLabel.TextColor3 = fillCol
	titleLabel.TextSize = 12
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = card
	
	-- Item List Container
	local list = Instance.new("Frame")
	list.Name = "ItemList"
	list.Size = UDim2.new(1, 0, 1, -34)
	list.Position = UDim2.new(0, 0, 0, 16)
	list.BackgroundTransparency = 1
	list.Parent = card
	
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	
	-- Capacity Bar
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBackground"
	barBg.Size = UDim2.new(1, 0, 0, HUD_CONFIG.BAR_HEIGHT)
	barBg.Position = UDim2.new(0, 0, 1, -HUD_CONFIG.BAR_HEIGHT)
	barBg.BackgroundColor3 = HUD_CONFIG.BAR_BACKGROUND_COLOR
	barBg.BorderSizePixel = 0
	barBg.Parent = card
	
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = fillCol
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	
	local capLabel = Instance.new("TextLabel")
	capLabel.Name = "CapLabel"
	capLabel.Size = UDim2.new(1, 0, 1, 0)
	capLabel.BackgroundTransparency = 1
	capLabel.Text = "0 / 0"
	capLabel.TextColor3 = HUD_CONFIG.TEXT_COLOR
	capLabel.TextSize = 8
	capLabel.Font = Enum.Font.GothamBold
	capLabel.Parent = barBg
	
	billboard.Parent = target
	return billboard
end

local function updateHUD(billboard: BillboardGui, inventory: {[string]: number}, current: number, max: number)
	local card = billboard:FindFirstChild("Card")
	if not card then return end
	
	-- Update Bar
	local barBg = card:FindFirstChild("BarBackground")
	if barBg then
		local fill = barBg:FindFirstChild("Fill")
		local capLabel = barBg:FindFirstChild("CapLabel")
		local ratio = math.clamp(current / math.max(1, max), 0, 1)
		
		if fill then
			TweenService:Create(fill, TweenInfo.new(0.3), {Size = UDim2.new(ratio, 0, 1, 0)}):Play()
		end
		if capLabel then
			capLabel.Text = string.format("%d / %d", current, max)
		end
	end
	
	-- Update Items (Top 3)
	local list = card:FindFirstChild("ItemList")
	if list then
		for _, child in list:GetChildren() do
			if child:IsA("TextLabel") then child:Destroy() end
		end
		
		local sortedItems = {}
		for id, count in pairs(inventory) do
			if count > 0 then
				table.insert(sortedItems, {id = id, count = count})
			end
		end
		table.sort(sortedItems, function(a, b) return a.count > b.count end)
		
		for i = 1, math.min(3, #sortedItems) do
			local data = sortedItems[i]
			local itemInfo = ItemConfig.Items[data.id]
			local icon = itemInfo and itemInfo.icon or "📦"
			
			local itemLabel = Instance.new("TextLabel")
			itemLabel.Size = UDim2.new(1, 0, 0, 12)
			itemLabel.BackgroundTransparency = 1
			itemLabel.Text = string.format("%s x%d", icon, data.count)
			itemLabel.TextColor3 = HUD_CONFIG.TEXT_COLOR
			itemLabel.TextSize = 10
			itemLabel.Font = Enum.Font.Gotham
			itemLabel.TextXAlignment = Enum.TextXAlignment.Center
			itemLabel.Parent = list
		end
		
		if #sortedItems == 0 then
			local emptyLabel = Instance.new("TextLabel")
			emptyLabel.Size = UDim2.new(1, 0, 1, 0)
			emptyLabel.BackgroundTransparency = 1
			emptyLabel.Text = "Empty"
			emptyLabel.TextColor3 = HUD_CONFIG.SUBTEXT_COLOR
			emptyLabel.TextSize = 10
			emptyLabel.Font = Enum.Font.Gotham
			emptyLabel.Parent = list
		end
	end
end

--------------------------------------------------------------------------------
-- SYNC LOGIC
--------------------------------------------------------------------------------

local function decodeItems(encoded)
	if not ItemConfig or not ItemConfig.SHORT_TO_ID then return encoded end
	if type(encoded) ~= "table" then return encoded end
	local decoded = {}
	for k, count in pairs(encoded) do
		local shortId = tonumber(k)
		if shortId and ItemConfig.SHORT_TO_ID[shortId] then
			decoded[ItemConfig.SHORT_TO_ID[shortId]] = count
		else
			decoded[k] = count
		end
	end
	return decoded
end

local function isPlayerPlot(instance: Instance)
	local plot = instance:FindFirstAncestor("Plot") or instance:FindFirstAncestorWhichIsA("Model")
	if plot and plot:GetAttribute("OwnerId") == Player.UserId then
		return true
	end
	-- Check parent name pattern Cart_Username
	if instance.Name:find("Cart_") and instance.Name:find(Player.Name) then
		return true
	end
	return false
end

local function setupStorageHUD(part: Instance)
	if not isPlayerPlot(part) then return end
	if ActiveHUDs[part] then return end
	
	local bb = createBillboard(part, "📦 PLOT STORAGE", HUD_CONFIG.BAR_FILL_STORAGE)
	ActiveHUDs[part] = {billboard = bb, type = "storage"}
	
	-- Initial sync
	task.spawn(function()
		local items, current, max = GetStorageFunction:InvokeServer()
		if ActiveHUDs[part] then
			updateHUD(bb, decodeItems(items) or {}, current or 0, Player:GetAttribute("StorageCapacity") or max or 0)
		end
	end)
end

local function setupCartHUD(model: Instance)
	if not isPlayerPlot(model) then return end
	if ActiveHUDs[model] then return end
	
	local primary = model:IsA("Model") and model.PrimaryPart or model
	local bb = createBillboard(primary, "🛒 TRANSPORT CART", HUD_CONFIG.BAR_FILL_CART)
	ActiveHUDs[model] = {billboard = bb, type = "cart"}
	
	-- Initial sync
	task.spawn(function()
		local info = GetVehicleInfoFunction:InvokeServer()
		if info and ActiveHUDs[model] then
			local decodedInventory = decodeItems(info.inventory) or {}
			local current = 0
			for _, c in pairs(decodedInventory) do current += c end
			updateHUD(bb, decodedInventory, current, Player:GetAttribute("CartCapacity") or info.capacity or 0)
		end
	end)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

StorageUpdatedEvent.OnClientEvent:Connect(function(items, current, max)
	items = decodeItems(items)
	for obj, data in pairs(ActiveHUDs) do
		if data.type == "storage" then
			updateHUD(data.billboard, items, current, Player:GetAttribute("StorageCapacity") or max or 0)
		end
	end
end)

CartUpdateEvent.OnClientEvent:Connect(function(state, inventory, max)
	inventory = decodeItems(inventory)
	for obj, data in pairs(ActiveHUDs) do
		if data.type == "cart" then
			local current = 0
			for _, c in pairs(inventory or {}) do current += c end
			updateHUD(data.billboard, inventory or {}, current, Player:GetAttribute("CartCapacity") or max or 0)
		end
	end
end)

CollectionService:GetInstanceAddedSignal(STORAGE_TAG):Connect(setupStorageHUD)
CollectionService:GetInstanceAddedSignal(CART_TAG):Connect(setupCartHUD)

for _, inst in CollectionService:GetTagged(STORAGE_TAG) do task.spawn(setupStorageHUD, inst) end
for _, inst in CollectionService:GetTagged(CART_TAG) do task.spawn(setupCartHUD, inst) end

print("✓ PhysicalInventoryHUD initialized")
