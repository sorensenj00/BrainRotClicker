--[[
	OverheadStatusUI Client Script (V3)
	
	Adds a BillboardGui above each placed brainrot showing the currently
	produced item's icon. Updates when production mode changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

-- Shared configs
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

-- Remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local ModeChangedEvent = RemoteEvents:WaitForChild("ModeChanged")

local BRAINROT_TAG = "ActiveBrainrot"

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

local BILLBOARD_CONFIG = {
	Size = UDim2.new(0, 52, 0, 52),
	MaxDistance = 45,
	AlwaysOnTop = false,
}

local function calculateIconOffset(unitModel: Instance): Vector3
	local HUD_PADDING = 1.2 -- Placed explicitly under the main HUD (which uses 4)
	
	if unitModel:IsA("Model") then
		local success, boundsCF, boundsSize = pcall(function()
			return unitModel:GetBoundingBox()
		end)
		
		if success and boundsSize then
			local pivotPos = unitModel:GetPivot().Position
			local boundsCenter = boundsCF.Position
			local modelTopY = boundsCenter.Y + (boundsSize.Y / 2)
			local pivotToTop = modelTopY - pivotPos.Y
			local offsetY = pivotToTop + HUD_PADDING
			return Vector3.new(0, offsetY, 0)
		end
	end
	
	return Vector3.new(0, 1.5, 0)
end

local COLORS = {
	BG = Color3.fromRGB(20, 22, 35),
	BORDER = Color3.fromRGB(60, 70, 100),
	TEXT = Color3.fromRGB(255, 255, 255),
	SYNERGY_GLOW = Color3.fromRGB(180, 100, 255),
}

--------------------------------------------------------------------------------
-- OVERHEAD CREATION
--------------------------------------------------------------------------------

local activeOverheads = {} -- [unit Model] = BillboardGui

local function getItemIcon(unitModel)
	local unitType = unitModel:GetAttribute("UnitType")
	if not unitType then return "❓" end
	
	local currentMode = unitModel:GetAttribute("CurrentMode") or 1
	local modes = ItemConfig.BrainrotModes[unitType]
	if not modes or not modes[currentMode] then return "❓" end
	
	local itemId = modes[currentMode].itemId
	local itemDef = ItemConfig.Items[itemId]
	return itemDef and itemDef.icon or "📦"
end

local function createOverhead(unitModel)
	-- Only show for own units
	local ownerId = unitModel:GetAttribute("OwnerId")
	if ownerId ~= player.UserId then return end
	
	-- Find attach point
	local attachPart = unitModel.PrimaryPart
		or unitModel:FindFirstChild("HumanoidRootPart")
		or unitModel:FindFirstChild("Head")
		or unitModel:FindFirstChildWhichIsA("BasePart")
	
	if not attachPart then return end
	
	-- Remove existing
	if activeOverheads[unitModel] then
		activeOverheads[unitModel]:Destroy()
	end
	
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ProductionOverhead"
	billboard.Size = BILLBOARD_CONFIG.Size
	billboard.StudsOffset = calculateIconOffset(unitModel)
	billboard.MaxDistance = BILLBOARD_CONFIG.MaxDistance
	billboard.AlwaysOnTop = BILLBOARD_CONFIG.AlwaysOnTop
	billboard.Adornee = attachPart
	billboard.Parent = attachPart
	
	-- Background circle
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = COLORS.BG
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel = 0
	bg.Parent = billboard
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = bg
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.BORDER
	stroke.Thickness = 1.5
	stroke.Parent = bg
	
	-- Icon label
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.BackgroundTransparency = 1
	icon.Text = getItemIcon(unitModel)
	icon.TextSize = 26
	icon.TextColor3 = COLORS.TEXT
	icon.FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.Regular)
	icon.Parent = bg
	
	activeOverheads[unitModel] = billboard
	
	-- Listen for attribute changes on this unit
	unitModel:GetAttributeChangedSignal("CurrentMode"):Connect(function()
		if icon and icon.Parent then
			icon.Text = getItemIcon(unitModel)
		end
	end)
	
	unitModel:GetAttributeChangedSignal("CurrentProducing"):Connect(function()
		local producingId = unitModel:GetAttribute("CurrentProducing")
		if producingId and icon and icon.Parent then
			local itemDef = ItemConfig.Items[producingId]
			icon.Text = itemDef and itemDef.icon or "📦"
		end
	end)
end

local function removeOverhead(unitModel)
	if activeOverheads[unitModel] then
		activeOverheads[unitModel]:Destroy()
		activeOverheads[unitModel] = nil
	end
end

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------

-- Attach to existing units
for _, unit in CollectionService:GetTagged(BRAINROT_TAG) do
	task.spawn(function()
		task.wait(0.5) -- Wait for attributes to be set
		createOverhead(unit)
	end)
end

-- Listen for new units
CollectionService:GetInstanceAddedSignal(BRAINROT_TAG):Connect(function(unit)
	task.spawn(function()
		task.wait(0.5)
		createOverhead(unit)
	end)
end)

CollectionService:GetInstanceRemovedSignal(BRAINROT_TAG):Connect(function(unit)
	removeOverhead(unit)
end)

-- Listen for mode change events from server
ModeChangedEvent.OnClientEvent:Connect(function(slotIndex, modeIndex, itemId)
	-- Find the unit in this slot and update its overhead
	for unit, billboard in pairs(activeOverheads) do
		if unit:GetAttribute("GridSlot") == slotIndex then
			local bg = billboard:FindFirstChild("Background")
			if bg then
				local iconLabel = bg:FindFirstChild("Icon")
				if iconLabel then
					local itemDef = ItemConfig.Items[itemId]
					iconLabel.Text = itemDef and itemDef.icon or "📦"
				end
			end
			break
		end
	end
end)
