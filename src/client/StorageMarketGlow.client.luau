--[[
	StorageMarketGlow Client Script
	
	Updates the Storage tank display to show the current market rate multiplier
	and adds a Highlight glow effect based on the rate.
	
	Features:
	- Shows "(1.2x)" multiplier on storage display
	- Green glow when rate >= 1.5x (good time to sell)
	- Yellow glow when rate 1.0x-1.5x (neutral)
	- Red glow when rate < 1.0x (bad time to sell)
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Configuration
local CONFIG = {
	-- Glow colors
	HIGH_RATE_COLOR = Color3.fromRGB(50, 255, 100),    -- Green (>=1.5x)
	NEUTRAL_RATE_COLOR = Color3.fromRGB(255, 215, 0), -- Yellow (1.0x-1.5x)
	LOW_RATE_COLOR = Color3.fromRGB(255, 70, 70),     -- Red (<1.0x)
	
	-- Thresholds
	HIGH_RATE_THRESHOLD = 1.5,
	NEUTRAL_RATE_THRESHOLD = 1.0,
	
	-- Glow intensity
	BASE_FILL_TRANSPARENCY = 0.7,
	BASE_OUTLINE_TRANSPARENCY = 0.3,
}

-- References
local player = Players.LocalPlayer
local stockMarketFolder: Folder? = nil
local currentHighlight: Highlight? = nil
local storagePart: BasePart? = nil
local rateLabel: TextLabel? = nil

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Gets the color based on the current market rate.
]]
local function getRateColor(rate: number): Color3
	if rate >= CONFIG.HIGH_RATE_THRESHOLD then
		return CONFIG.HIGH_RATE_COLOR
	elseif rate >= CONFIG.NEUTRAL_RATE_THRESHOLD then
		return CONFIG.NEUTRAL_RATE_COLOR
	else
		return CONFIG.LOW_RATE_COLOR
	end
end

--[[
	Finds the player's storage part by looking for their plot.
]]
local function findPlayerStorage(): BasePart?
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	
	for _, plot in plotsFolder:GetChildren() do
		local ownerId = plot:GetAttribute("OwnerId")
		if ownerId and ownerId == player.UserId then
			local storage = plot:FindFirstChild("Storage")
			if storage and storage:IsA("BasePart") then
				return storage
			end
		end
	end
	
	return nil
end

--[[
	Creates or updates the rate label on the storage BillboardGui.
]]
local function ensureRateLabel(storage: BasePart): TextLabel?
	local billboard = storage:FindFirstChild("StorageDisplay")
	if not billboard then return nil end
	
	local bgFrame = billboard:FindFirstChild("Background")
	if not bgFrame then return nil end
	
	-- Check if rate label already exists
	local existingLabel = bgFrame:FindFirstChild("RateLabel")
	if existingLabel then
		return existingLabel :: TextLabel
	end
	
	-- Create new rate label
	local label = Instance.new("TextLabel")
	label.Name = "RateLabel"
	label.Size = UDim2.new(0.4, 0, 0.3, 0)
	label.Position = UDim2.new(0.6, 0, 0.05, 0)
	label.BackgroundTransparency = 1
	label.Text = "(1.0x)"
	label.TextColor3 = CONFIG.NEUTRAL_RATE_COLOR
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = bgFrame
	
	return label
end

--[[
	Creates or updates the Highlight effect on the storage.
]]
local function ensureHighlight(storage: BasePart): Highlight?
	-- Check if highlight already exists
	local existingHighlight = storage:FindFirstChild("MarketHighlight")
	if existingHighlight and existingHighlight:IsA("Highlight") then
		return existingHighlight
	end
	
	-- Create new highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "MarketHighlight"
	highlight.FillTransparency = CONFIG.BASE_FILL_TRANSPARENCY
	highlight.OutlineTransparency = CONFIG.BASE_OUTLINE_TRANSPARENCY
	highlight.FillColor = CONFIG.NEUTRAL_RATE_COLOR
	highlight.OutlineColor = CONFIG.NEUTRAL_RATE_COLOR
	highlight.Adornee = storage
	highlight.Parent = storage
	
	return highlight
end

--[[
	Updates the storage visual based on current market rate.
]]
local function updateStorageVisual()
	if not stockMarketFolder then return end
	if not storagePart then
		-- Try to find storage again
		storagePart = findPlayerStorage()
		if not storagePart then return end
		
		-- Ensure rate label exists
		rateLabel = ensureRateLabel(storagePart)
		
		-- Ensure highlight exists
		currentHighlight = ensureHighlight(storagePart)
	end
	
	-- Get current rate
	local currentRate = stockMarketFolder:GetAttribute("CurrentRate") :: number? or 1.0
	local color = getRateColor(currentRate)
	
	-- Update rate label
	if rateLabel then
		rateLabel.Text = string.format("(%.2fx)", currentRate)
		rateLabel.TextColor3 = color
	end
	
	-- Update highlight
	if currentHighlight then
		currentHighlight.FillColor = color
		currentHighlight.OutlineColor = color
		
		-- Pulse intensity based on how far from 1.0x
		local intensity = math.abs(currentRate - 1.0)
		local fillTransparency = math.clamp(0.9 - intensity * 0.3, 0.5, 0.95)
		local outlineTransparency = math.clamp(0.5 - intensity * 0.2, 0.1, 0.7)
		
		currentHighlight.FillTransparency = fillTransparency
		currentHighlight.OutlineTransparency = outlineTransparency
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("StorageMarketGlow: Initializing...")
	
	-- Wait for StockMarket folder
	stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket", 30) :: Folder?
	if not stockMarketFolder then
		warn("StorageMarketGlow: StockMarket folder not found!")
		return
	end
	
	-- Wait a moment for plot to be assigned
	task.wait(2)
	
	-- Find player's storage
	storagePart = findPlayerStorage()
	if storagePart then
		rateLabel = ensureRateLabel(storagePart)
		currentHighlight = ensureHighlight(storagePart)
		print("StorageMarketGlow: Found storage, added rate display and glow")
	else
		print("StorageMarketGlow: No storage found yet, will check on rate updates")
	end
	
	-- Initial update
	updateStorageVisual()
	
	-- Listen for rate changes
	stockMarketFolder:GetAttributeChangedSignal("CurrentRate"):Connect(updateStorageVisual)
	
	-- Also poll periodically in case storage wasn't found initially
	task.spawn(function()
		while true do
			task.wait(2)
			if not storagePart then
				storagePart = findPlayerStorage()
				if storagePart then
					rateLabel = ensureRateLabel(storagePart)
					currentHighlight = ensureHighlight(storagePart)
					updateStorageVisual()
					print("StorageMarketGlow: Found storage on poll")
				end
			end
		end
	end)
	
	print("✓ StorageMarketGlow initialized")
end

-- Start
task.spawn(initialize)
