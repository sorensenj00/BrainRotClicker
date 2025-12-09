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

-- Configuration
local HUD_CONFIG = {
	-- Billboard settings
	BILLBOARD_SIZE = UDim2.new(0, 80, 0, 30),
	BILLBOARD_OFFSET = Vector3.new(0, 4, 0), -- Above the model
	MAX_DISTANCE = 100,
	
	-- Progress bar
	BAR_HEIGHT = 8,
	BAR_BACKGROUND_COLOR = Color3.fromRGB(40, 40, 50),
	BAR_FILL_COLOR = Color3.fromRGB(100, 220, 100),
	BAR_COMPLETE_COLOR = Color3.fromRGB(255, 215, 0),
	CORNER_RADIUS = 4,
	
	-- Floating text
	FLOAT_DISTANCE = 40,
	FLOAT_DURATION = 1.2,
	TEXT_COLOR = Color3.fromRGB(100, 200, 255),  -- Blue for items
	
	-- Item tier emojis
	TIER_EMOJI = {"⚪", "🟡", "🟠", "💎"},
}

-- Tag
local BRAINROT_TAG = "ActiveBrainrot"

-- Track active HUDs
local ActiveHUDs: {[Instance]: {billboard: BillboardGui, startTime: number}} = {}

--------------------------------------------------------------------------------
-- HUD CREATION
--------------------------------------------------------------------------------

--[[
	Creates a BillboardGui with progress bar for a brainrot unit.
]]
local function createProgressHUD(brainrot: Instance): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ProgressHUD"
	billboard.Size = HUD_CONFIG.BILLBOARD_SIZE
	billboard.StudsOffset = HUD_CONFIG.BILLBOARD_OFFSET
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = HUD_CONFIG.MAX_DISTANCE
	billboard.LightInfluence = 0
	
	-- Find adornee (the model's primary part or first part)
	if brainrot:IsA("Model") then
		billboard.Adornee = brainrot.PrimaryPart or brainrot:FindFirstChildWhichIsA("BasePart")
	elseif brainrot:IsA("BasePart") then
		billboard.Adornee = brainrot
	end
	
	-- Container frame
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.Parent = billboard
	
	-- Progress bar background
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBackground"
	barBg.Size = UDim2.new(1, 0, 0, HUD_CONFIG.BAR_HEIGHT)
	barBg.Position = UDim2.new(0, 0, 1, -HUD_CONFIG.BAR_HEIGHT - 5)
	barBg.BackgroundColor3 = HUD_CONFIG.BAR_BACKGROUND_COLOR
	barBg.BorderSizePixel = 0
	barBg.Parent = container
	
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, HUD_CONFIG.CORNER_RADIUS)
	bgCorner.Parent = barBg
	
	-- Progress bar fill
	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0) -- Starts at 0
	barFill.BackgroundColor3 = HUD_CONFIG.BAR_FILL_COLOR
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, HUD_CONFIG.CORNER_RADIUS)
	fillCorner.Parent = barFill
	
	-- Item type label (shows item name)
	local incomeLabel = Instance.new("TextLabel")
	incomeLabel.Name = "ItemLabel"
	incomeLabel.Size = UDim2.new(1, 0, 0, 16)
	incomeLabel.Position = UDim2.new(0, 0, 0, 0)
	incomeLabel.BackgroundTransparency = 1
	incomeLabel.Text = ""
	incomeLabel.TextColor3 = HUD_CONFIG.TEXT_COLOR
	incomeLabel.TextSize = 12
	incomeLabel.Font = Enum.Font.GothamBold
	incomeLabel.TextStrokeTransparency = 0.5
	incomeLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	incomeLabel.Parent = container
	
	-- Parent to brainrot
	billboard.Parent = brainrot
	
	return billboard
end

--[[
	Creates a floating item text that rises and fades.
]]
local function createFloatingText(billboard: BillboardGui, itemId: string)
	local container = billboard:FindFirstChild("Container")
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
	floatText.TextColor3 = HUD_CONFIG.TEXT_COLOR
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
	Gets the item produced by a brainrot based on its category.
]]
local function getProducedItem(brainrot: Instance): string
	local unitType = brainrot:GetAttribute("UnitType")
	if unitType then
		local category = ItemConfig.BrainrotToCategory[unitType]
		if category and ItemConfig.BrainrotItems[category] then
			-- Return tier 1 item for display
			return ItemConfig.BrainrotItems[category].tier1 or "Item"
		end
	end
	return "Item"
end

--[[
	Checks if this brainrot belongs to the local player.
]]
local function isOwnedByPlayer(brainrot: Instance): boolean
	local ownerId = brainrot:GetAttribute("OwnerId")
	return ownerId == Player.UserId
end

--[[
	Sets up a progress HUD for a brainrot.
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
	
	local billboard = createProgressHUD(brainrot)
	local cycleTime = getCycleTime(brainrot)
	local producedItem = getProducedItem(brainrot)
	
	-- Use server's spawn time if available, otherwise use current time
	local serverSpawnTime = brainrot:GetAttribute("SpawnTime")
	local startTime = serverSpawnTime or os.time()
	
	ActiveHUDs[brainrot] = {
		billboard = billboard,
		startTime = startTime,
		cycleTime = cycleTime,
		producedItem = producedItem,
		lastCycle = 0,
	}
	
	-- Update item label
	local itemLabel = billboard.Container:FindFirstChild("ItemLabel")
	if itemLabel then
		local itemInfo = ItemConfig.Items[producedItem]
		local tier = itemInfo and itemInfo.tier or 1
		local emoji = HUD_CONFIG.TIER_EMOJI[tier] or "⚪"
		itemLabel.Text = emoji .. " " .. producedItem
	end
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
		
		local container = billboard:FindFirstChild("Container")
		if not container then continue end
		
		local barBg = container:FindFirstChild("BarBackground")
		if not barBg then continue end
		
		local barFill = barBg:FindFirstChild("BarFill")
		if not barFill then continue end
		
		-- Calculate progress within current cycle
		local cycleTime = hudData.cycleTime
		local elapsed = currentTime - hudData.startTime
		local cycleProgress = (elapsed % cycleTime) / cycleTime
		local currentCycle = math.floor(elapsed / cycleTime)
		
		-- Update bar width
		barFill.Size = UDim2.new(cycleProgress, 0, 1, 0)
		
		-- Check for cycle completion
		if currentCycle > hudData.lastCycle then
			hudData.lastCycle = currentCycle
			
			-- Play completion effects
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
