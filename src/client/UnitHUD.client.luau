--[[
	UnitHUD LocalScript
	
	Displays progress bars above brainrot units using BillboardGuis.
	Animates income cycles and shows floating "+$X" text on completion.
	
	Uses CollectionService to detect "ActiveBrainrot" tagged units.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Player reference
local Player = Players.LocalPlayer

-- Wait for ShopConfig (located in ReplicatedStorage.Shared per Rojo config)
local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopConfig"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- Wait for RarityConfig to get colors
local RarityConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RarityConfig"))

-- Configuration
local HUD_CONFIG = {
	-- Billboard settings (bigger to fit all info)
	BILLBOARD_SIZE = UDim2.new(0, 140, 0, 65),
	MAX_DISTANCE = 100,
	
	-- Card styling (dark theme)
	CARD_BACKGROUND = Color3.fromRGB(25, 25, 35),
	CARD_STROKE_COLOR = Color3.fromRGB(80, 80, 100),
	CARD_STROKE_THICKNESS = 1,
	CORNER_RADIUS = 8,
	
	-- Progress bar
	BAR_HEIGHT = 6,
	BAR_BACKGROUND_COLOR = Color3.fromRGB(40, 40, 50),
	BAR_FILL_COLOR = Color3.fromRGB(100, 220, 100),
	BAR_COMPLETE_COLOR = Color3.fromRGB(255, 215, 0),
	
	-- Text
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	SUBTEXT_COLOR = Color3.fromRGB(180, 180, 200),
	
	-- Floating text
	FLOAT_DISTANCE = 40,
	FLOAT_DURATION = 1.2,
	FLOAT_TEXT_COLOR = Color3.fromRGB(100, 200, 255),
	
	-- Item tier emojis
	TIER_EMOJI = {"⚪", "🟡", "🟠", "💎", "💠"},
}

-- Tag
local BRAINROT_TAG = "ActiveBrainrot"

-- Track active HUDs
local ActiveHUDs: {[Instance]: {billboard: BillboardGui, startTime: number}} = {}

--------------------------------------------------------------------------------
-- HUD CREATION
--------------------------------------------------------------------------------

--[[
	Calculates the height offset needed to position HUD above model's top.
	Uses bounding box calculation similar to GridManager grounding approach.
]]
local function calculateHUDOffset(brainrot: Instance): Vector3
	local HUD_PADDING = 4 -- Extra studs above the model's top
	
	if brainrot:IsA("Model") then
		local success, boundsCF, boundsSize = pcall(function()
			return brainrot:GetBoundingBox()
		end)
		
		if success and boundsSize then
			-- Get model's pivot position and bounds center
			local pivotPos = brainrot:GetPivot().Position
			local boundsCenter = boundsCF.Position
			
			-- Model's top Y in world space
			local modelTopY = boundsCenter.Y + (boundsSize.Y / 2)
			
			-- How far above the pivot is the top of the model
			local pivotToTop = modelTopY - pivotPos.Y
			
			-- HUD should be at top + padding
			local offsetY = pivotToTop + HUD_PADDING
			
			return Vector3.new(0, offsetY, 0)
		end
	end
	
	-- Fallback for non-models or if bounding box fails
	return Vector3.new(0, 4.5, 0)
end

--[[
	Creates a unified BillboardGui with stats and progress bar for a brainrot unit.
]]
local function createProgressHUD(brainrot: Instance): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "UnitHUD"
	billboard.Size = HUD_CONFIG.BILLBOARD_SIZE
	billboard.StudsOffset = calculateHUDOffset(brainrot) -- Dynamic offset based on model height
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = HUD_CONFIG.MAX_DISTANCE
	billboard.LightInfluence = 0
	
	-- Find adornee (the model's primary part or first part)
	if brainrot:IsA("Model") then
		billboard.Adornee = brainrot.PrimaryPart or brainrot:FindFirstChildWhichIsA("BasePart")
	elseif brainrot:IsA("BasePart") then
		billboard.Adornee = brainrot
	end
	
	-- Main card container with dark background
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = HUD_CONFIG.CARD_BACKGROUND
	card.BackgroundTransparency = 0.15
	card.BorderSizePixel = 0
	card.Parent = billboard
	
	-- Card rounded corners
	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, HUD_CONFIG.CORNER_RADIUS)
	cardCorner.Parent = card
	
	-- Card stroke
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = HUD_CONFIG.CARD_STROKE_COLOR
	cardStroke.Thickness = HUD_CONFIG.CARD_STROKE_THICKNESS
	cardStroke.Transparency = 0.3
	cardStroke.Parent = card
	
	-- Padding inside card
	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingLeft = UDim.new(0, 6)
	cardPadding.PaddingRight = UDim.new(0, 6)
	cardPadding.PaddingTop = UDim.new(0, 4)
	cardPadding.PaddingBottom = UDim.new(0, 6)
	cardPadding.Parent = card
	
	-- Content container (transparent, for layout)
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = card
	
	-- Stats row (Level | Tier)
	local statsLabel = Instance.new("TextLabel")
	statsLabel.Name = "StatsLabel"
	statsLabel.Size = UDim2.new(1, 0, 0, 14)
	statsLabel.Position = UDim2.new(0, 0, 0, 0)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Text = "Lvl 1 | Tier 1"
	statsLabel.TextColor3 = HUD_CONFIG.TEXT_COLOR
	statsLabel.TextSize = 12
	statsLabel.Font = Enum.Font.GothamBold
	statsLabel.TextXAlignment = Enum.TextXAlignment.Center
	statsLabel.Parent = container
	
	-- Rarity label
	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Name = "RarityLabel"
	rarityLabel.Size = UDim2.new(1, 0, 0, 12)
	rarityLabel.Position = UDim2.new(0, 0, 0, 14)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = "Normal"
	rarityLabel.TextColor3 = HUD_CONFIG.SUBTEXT_COLOR
	rarityLabel.TextSize = 10
	rarityLabel.Font = Enum.Font.Gotham
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Center
	rarityLabel.Parent = container

	-- Production label (What it makes)
	local prodLabel = Instance.new("TextLabel")
	prodLabel.Name = "ProductionLabel"
	prodLabel.Size = UDim2.new(1, 0, 0, 12)
	prodLabel.Position = UDim2.new(0, 0, 0, 26)
	prodLabel.BackgroundTransparency = 1
	prodLabel.Text = "Produces: Item"
	prodLabel.TextColor3 = HUD_CONFIG.FLOAT_TEXT_COLOR
	prodLabel.TextSize = 10
	prodLabel.Font = Enum.Font.GothamBold
	prodLabel.TextXAlignment = Enum.TextXAlignment.Center
	prodLabel.Parent = container
	
	-- Progress bar background (at bottom of card)
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBackground"
	barBg.Size = UDim2.new(1, 0, 0, HUD_CONFIG.BAR_HEIGHT)
	barBg.Position = UDim2.new(0, 0, 1, -HUD_CONFIG.BAR_HEIGHT)
	barBg.BackgroundColor3 = HUD_CONFIG.BAR_BACKGROUND_COLOR
	barBg.BorderSizePixel = 0
	barBg.Parent = container
	
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 3)
	bgCorner.Parent = barBg
	
	-- Progress bar fill
	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0) -- Starts at 0
	barFill.BackgroundColor3 = HUD_CONFIG.BAR_FILL_COLOR
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = barFill
	
	-- Parent to brainrot
	billboard.Parent = brainrot
	
	return billboard
end

--[[
	Creates a floating item text that rises and fades.
]]
local function createFloatingText(billboard: BillboardGui, itemId: string)
	-- Navigate through new Card hierarchy
	local card = billboard:FindFirstChild("Card")
	if not card then return end
	local container = card:FindFirstChild("Container")
	if not container then return end
	
	-- Get item info for display
	local itemInfo = ItemConfig.Items[itemId]
	local tier = itemInfo and itemInfo.tier or 1
	local emoji = HUD_CONFIG.TIER_EMOJI[tier] or "⚪"
	
	local floatText = Instance.new("TextLabel")
	floatText.Name = "FloatText"
	floatText.Size = UDim2.new(1, 0, 0, 20)
	floatText.Position = UDim2.new(0, 0, 0.5, -10)
	floatText.BackgroundTransparency = 1
	floatText.Text = emoji .. " +1"
	floatText.TextColor3 = HUD_CONFIG.FLOAT_TEXT_COLOR
	floatText.TextSize = 16
	floatText.Font = Enum.Font.GothamBold
	floatText.TextStrokeTransparency = 0
	floatText.TextStrokeColor3 = Color3.new(0, 0, 0)
	floatText.Parent = container
	
	-- Animate rising and fading
	local riseTween = TweenService:Create(floatText, TweenInfo.new(HUD_CONFIG.FLOAT_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, -0.5, 0),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	
	riseTween:Play()
	riseTween.Completed:Connect(function()
		floatText:Destroy()
	end)
	
	-- Scale pop animation
	local originalSize = floatText.TextSize
	floatText.TextSize = originalSize * 1.5
	TweenService:Create(floatText, TweenInfo.new(0.2, Enum.EasingStyle.Elastic), {
		TextSize = originalSize
	}):Play()
end

--[[
	Pulses the progress bar when complete.
]]
local function pulseComplete(barFill: Frame)
	barFill.BackgroundColor3 = HUD_CONFIG.BAR_COMPLETE_COLOR
	
	TweenService:Create(barFill, TweenInfo.new(0.3), {
		BackgroundColor3 = HUD_CONFIG.BAR_FILL_COLOR
	}):Play()
end

--------------------------------------------------------------------------------
-- HUD LOGIC
--------------------------------------------------------------------------------

--[[
	Gets the cycle time for a brainrot from its attributes or ShopConfig.
]]
local function getCycleTime(brainrot: Instance): number
	-- First try attribute (set by server)
	local cycleTime = brainrot:GetAttribute("IncomeInterval")
	if cycleTime then
		return cycleTime
	end
	
	-- Fall back to ShopConfig based on name
	local unitType = brainrot:GetAttribute("UnitType")
	if unitType then
		local config = ShopConfig.GetConfig(unitType)
		if config then
			return config.CycleTime
		end
	end
	
	-- Default fallback
	return 3
end

--[[
	Gets the item produced by a brainrot based on its model type.
]]
--[[
	Gets the item produced by a brainrot based on its model type.
	Returns { icon: string, name: string, id: string }
]]
local function getProducedItemInfo(brainrot: Instance)
	local unitType = brainrot:GetAttribute("UnitType")
	if unitType then
		local mapping = ItemConfig.BrainrotItems[unitType]
		if mapping then
			local itemId = mapping.tier1 -- Always show tier 1 as baseline
			local item = ItemConfig.Items[itemId]
			if item then
				return {
					icon = item.icon or "📦",
					name = item.displayName or "Item",
					id = itemId
				}
			end
		end
	end
	return { icon = "📦", name = "Item", id = "" }
end

--[[
	Checks if this brainrot belongs to the local player.
]]
local function isOwnedByPlayer(brainrot: Instance): boolean
	local ownerId = brainrot:GetAttribute("OwnerId")
	return ownerId == Player.UserId
end

--[[
	Updates HUD labels from brainrot attributes.
]]
local function updateHUDLabels(brainrot: Instance, billboard: BillboardGui)
	local card = billboard:FindFirstChild("Card")
	if not card then return end
	local container = card:FindFirstChild("Container")
	if not container then return end
	
	local level = brainrot:GetAttribute("Level") or 1
	local tier = brainrot:GetAttribute("ItemTier") or 1
	local rarity = brainrot:GetAttribute("Rarity") or "Normal"
	
	-- Update stats label
	local statsLabel = container:FindFirstChild("StatsLabel")
	if statsLabel then
		statsLabel.Text = string.format("Lvl %d | Tier %d", level, tier)
	end
	
	-- Update rarity label with color
	local rarityLabel = container:FindFirstChild("RarityLabel")
	if rarityLabel then
		rarityLabel.Text = rarity
		rarityLabel.TextColor3 = RarityConfig.GetColor(rarity)
	end

	-- Update production label
	local prodLabel = container:FindFirstChild("ProductionLabel")
	if prodLabel then
		local info = getProducedItemInfo(brainrot)
		prodLabel.Text = string.format("Produces %s %s", info.icon, info.name)
	end
end

--[[
	Sets up a unified HUD for a brainrot.
]]
local function setupBrainrotHUD(brainrot: Instance)
	-- Only show HUD for player's own units
	if not isOwnedByPlayer(brainrot) then
		return
	end
	
	-- Skip if already has HUD
	if ActiveHUDs[brainrot] then
		return
	end
	
	-- Remove any server-created StatsDisplay to avoid duplicates
	local head = brainrot:FindFirstChild("Head") or (brainrot :: Model).PrimaryPart
	if head then
		local oldDisplay = head:FindFirstChild("StatsDisplay")
		if oldDisplay then
			oldDisplay:Destroy()
		end
	end
	
	local billboard = createProgressHUD(brainrot)
	
	-- Initial info
	local info = getProducedItemInfo(brainrot)
	
	ActiveHUDs[brainrot] = {
		billboard = billboard,
		startTime = os.clock(), -- Fallback
		cycleTime = getCycleTime(brainrot),
		producedItem = info.id,
		lastCycle = 0,
		lastProdTS = brainrot:GetAttribute("LastProductionTime") or 0,
	}
	
	-- Update stats/rarity labels from attributes
	updateHUDLabels(brainrot, billboard)
	
	-- Listen for attribute changes to keep HUD in sync
	brainrot.AttributeChanged:Connect(function(attributeName)
		if attributeName == "Level" or attributeName == "ItemTier" or attributeName == "Rarity" then
			updateHUDLabels(brainrot, billboard)
		end
		if attributeName == "IncomeInterval" then
			local hudData = ActiveHUDs[brainrot]
			if hudData then
				hudData.cycleTime = getCycleTime(brainrot)
			end
		end
		if attributeName == "LastProductionTime" then
			local hudData = ActiveHUDs[brainrot]
			if hudData then
				hudData.startTime = brainrot:GetAttribute("LastProductionTime")
			end
		end
	end)
end

--[[
	Removes HUD when brainrot is destroyed.
]]
local function cleanupBrainrotHUD(brainrot: Instance)
	local hudData = ActiveHUDs[brainrot]
	if hudData then
		if hudData.billboard then
			hudData.billboard:Destroy()
		end
		ActiveHUDs[brainrot] = nil
	end
end

--[[
	Updates all active progress bars.
]]
local function updateProgressBars()
	local currentTime = os.clock()
	
	for brainrot, hudData in ActiveHUDs do
		-- Check if brainrot still exists
		if not brainrot or not brainrot.Parent then
			cleanupBrainrotHUD(brainrot)
			continue
		end
		
		local billboard = hudData.billboard
		if not billboard or not billboard.Parent then
			continue
		end
		
		local card = billboard:FindFirstChild("Card")
		if not card then continue end
		local container = card:FindFirstChild("Container")
		if not container then continue end
		
		local barBg = container:FindFirstChild("BarBackground")
		if not barBg then continue end
		
		local barFill = barBg:FindFirstChild("BarFill")
		if not barFill then continue end
		
		-- Calculate progress
		local cycleTime = hudData.cycleTime
		-- Use server-synced LastProductionTime if available
		local lastProd = brainrot:GetAttribute("LastProductionTime") or hudData.startTime
		local elapsed = currentTime - lastProd
		
		local progress = math.clamp(elapsed / cycleTime, 0, 1)
		
		-- Update bar width
		barFill.Size = UDim2.new(progress, 0, 1, 0)
		
		-- Logic for effects is handled by the attribute change for perfectly sync'd pulse?
		-- No, we stick to the local tracking for the pulse/float text but triggered by the reset.
		if progress >= 1 then
			-- Wait for server to update LastProductionTime to reset.
			-- Or if we haven't seen an update in cycleTime * 1.5, we assume it's stuck/offline.
		end
		
		-- Pulse and floating text on reset (detected by a decrease in progress)
		if lastProd ~= hudData.lastProdTS then
			hudData.lastProdTS = lastProd
			pulseComplete(barFill)
			createFloatingText(billboard, hudData.producedItem)
		end
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("UnitHUD: Initializing...")
	
	-- Setup existing brainrots
	for _, brainrot in CollectionService:GetTagged(BRAINROT_TAG) do
		task.spawn(setupBrainrotHUD, brainrot)
	end
	
	-- Listen for new brainrots
	CollectionService:GetInstanceAddedSignal(BRAINROT_TAG):Connect(setupBrainrotHUD)
	
	-- Listen for removed brainrots
	CollectionService:GetInstanceRemovedSignal(BRAINROT_TAG):Connect(cleanupBrainrotHUD)
	
	-- Update progress bars every frame
	RunService.RenderStepped:Connect(updateProgressBars)
	
	print("UnitHUD: Ready!")
end

-- Start
initialize()
