--[[
	StorageUI Client Script
	
	Simple storage proximity UI that shows when approaching the Storage part.
	Opens Transport UI for full storage access.
	
	Features:
	- Shows storage fill level when near Storage
	- Quick info popup
	- Press T for full Transport UI
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Get player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Wait for events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local StorageUpdatedEvent = RemoteEvents:WaitForChild("StorageUpdated")
local GetStorageFunction = RemoteEvents:WaitForChild("GetStorage")

-- Constants
local PROXIMITY_DISTANCE = 20

-- State
local currentStorage = {}
local storageUsage = 0
local storageCapacity = 2000
local isNearStorage = false

-- UI References
local screenGui = nil
local popupFrame = nil

-- Colors
local COLORS = {
	background = Color3.fromRGB(20, 25, 35),
	accent = Color3.fromRGB(100, 200, 255),
	text = Color3.fromRGB(255, 255, 255),
	success = Color3.fromRGB(100, 255, 150),
	warning = Color3.fromRGB(255, 200, 100),
	danger = Color3.fromRGB(255, 100, 100),
}

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createScreenGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "StorageProximityUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = PlayerGui
	return gui
end

local function createPopup(parent)
	local popup = Instance.new("Frame")
	popup.Name = "StoragePopup"
	popup.Size = UDim2.new(0, 220, 0, 80)
	popup.Position = UDim2.new(0.5, -110, 0, 120)
	popup.BackgroundColor3 = COLORS.background
	popup.BackgroundTransparency = 0.15
	popup.Visible = false
	popup.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = popup
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.accent
	stroke.Thickness = 2
	stroke.Transparency = 0.5
	stroke.Parent = popup
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 25)
	title.Position = UDim2.new(0, 10, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "📦 STORAGE"
	title.TextColor3 = COLORS.accent
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = popup
	
	-- Capacity bar
	local barBg = Instance.new("Frame")
	barBg.Name = "CapacityBarBg"
	barBg.Size = UDim2.new(1, -20, 0, 16)
	barBg.Position = UDim2.new(0, 10, 0, 35)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
	barBg.BorderSizePixel = 0
	barBg.Parent = popup
	
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
	barCorner.Parent = barBg
	
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(0.5, 0, 1, 0)
	barFill.BackgroundColor3 = COLORS.accent
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 6)
	fillCorner.Parent = barFill
	
	local barText = Instance.new("TextLabel")
	barText.Name = "Text"
	barText.Size = UDim2.new(1, 0, 1, 0)
	barText.BackgroundTransparency = 1
	barText.Text = "0 / 2000"
	barText.TextColor3 = COLORS.text
	barText.TextSize = 11
	barText.Font = Enum.Font.GothamBold
	barText.Parent = barBg
	
	-- Hint text
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Size = UDim2.new(1, -20, 0, 18)
	hint.Position = UDim2.new(0, 10, 0, 55)
	hint.BackgroundTransparency = 1
	hint.Text = "Press T for full inventory"
	hint.TextColor3 = Color3.fromRGB(150, 150, 170)
	hint.TextSize = 12
	hint.Font = Enum.Font.Gotham
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Parent = popup
	
	return popup
end

--------------------------------------------------------------------------------
-- UPDATE
--------------------------------------------------------------------------------

local function updatePopup()
	if not popupFrame then return end
	
	local barBg = popupFrame:FindFirstChild("CapacityBarBg")
	if barBg then
		local fill = barBg:FindFirstChild("Fill")
		local text = barBg:FindFirstChild("Text")
		
		local ratio = math.clamp(storageUsage / math.max(1, storageCapacity), 0, 1)
		
		if fill then
			TweenService:Create(fill, TweenInfo.new(0.3), {
				Size = UDim2.new(ratio, 0, 1, 0)
			}):Play()
			
			-- Color based on fullness
			local color = COLORS.accent
			if ratio >= 1 then
				color = COLORS.danger
			elseif ratio > 0.8 then
				color = COLORS.warning
			elseif ratio > 0.5 then
				color = COLORS.success
			end
			fill.BackgroundColor3 = color
		end
		
		if text then
			text.Text = string.format("%d / %d", storageUsage, storageCapacity)
		end
	end
end

local function showPopup()
	if not popupFrame then return end
	
	popupFrame.Visible = true
	popupFrame.Size = UDim2.new(0, 220, 0, 0)
	TweenService:Create(popupFrame, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
		Size = UDim2.new(0, 220, 0, 80)
	}):Play()
end

local function hidePopup()
	if not popupFrame then return end
	
	TweenService:Create(popupFrame, TweenInfo.new(0.15), {
		Size = UDim2.new(0, 220, 0, 0)
	}):Play()
	
	task.wait(0.15)
	if popupFrame then
		popupFrame.Visible = false
	end
end

--------------------------------------------------------------------------------
-- PROXIMITY CHECK
--------------------------------------------------------------------------------

local function findPlayerStorage()
	local character = LocalPlayer.Character
	if not character then return nil end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	
	-- Find Storage parts in plots
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	
	for _, plot in plotsFolder:GetChildren() do
		local ownerId = plot:GetAttribute("OwnerId")
		if ownerId == LocalPlayer.UserId then
			local storage = plot:FindFirstChild("Storage")
			if storage and storage:IsA("BasePart") then
				return storage
			end
		end
	end
	
	return nil
end

local function checkProximity()
	local character = LocalPlayer.Character
	if not character then return end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	
	local storage = findPlayerStorage()
	if not storage then return end
	
	local distance = (hrp.Position - storage.Position).Magnitude
	local wasNear = isNearStorage
	isNearStorage = distance <= PROXIMITY_DISTANCE
	
	-- Transitioned to near
	if isNearStorage and not wasNear then
		-- Fetch latest storage data
		local items, total, cap = GetStorageFunction:InvokeServer()
		currentStorage = items or {}
		storageUsage = total or 0
		storageCapacity = cap or 2000
		
		updatePopup()
		showPopup()
	-- Transitioned away
	elseif not isNearStorage and wasNear then
		hidePopup()
	end
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

StorageUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
	currentStorage = items or {}
	storageUsage = total or 0
	storageCapacity = capacity or 2000
	
	if isNearStorage then
		updatePopup()
	end
end)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	screenGui = createScreenGui()
	popupFrame = createPopup(screenGui)
	
	-- Proximity check loop
	RunService.Heartbeat:Connect(function()
		checkProximity()
	end)
	
	print("✓ StorageUI initialized")
end

-- Wait for character
if LocalPlayer.Character then
	task.spawn(initialize)
else
	LocalPlayer.CharacterAdded:Wait()
	task.spawn(initialize)
end
