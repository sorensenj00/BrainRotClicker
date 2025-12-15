--[[
	StorageUI Client Script
	
	Simple storage button and keybind to open Transport UI.
	
	Features:
	- Press T to open storage
	- Button in corner of screen
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Get player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Wait for events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local StorageUpdatedEvent = RemoteEvents:WaitForChild("StorageUpdated")
local GetStorageFunction = RemoteEvents:WaitForChild("GetStorage")

-- State
local storageUsage = 0
local storageCapacity = 2000

-- UI References
local screenGui = nil
local storageButton = nil

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
	gui.Name = "StorageButtonUI"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = PlayerGui
	return gui
end

local function createStorageButton(parent)
	local button = Instance.new("TextButton")
	button.Name = "StorageButton"
	button.Size = UDim2.new(0, 60, 0, 60)
	button.Position = UDim2.new(0, 20, 0.5, -30)
	button.BackgroundColor3 = COLORS.background
	button.BackgroundTransparency = 0.15
	button.Text = ""
	button.AutoButtonColor = false
	button.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = button
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.accent
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = button
	
	-- Icon
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(1, 0, 0, 30)
	icon.Position = UDim2.new(0, 0, 0, 5)
	icon.BackgroundTransparency = 1
	icon.Text = "📦"
	icon.TextSize = 24
	icon.Font = Enum.Font.GothamBold
	icon.Parent = button
	
	-- Capacity bar background
	local barBg = Instance.new("Frame")
	barBg.Name = "CapacityBarBg"
	barBg.Size = UDim2.new(0.8, 0, 0, 6)
	barBg.Position = UDim2.new(0.1, 0, 1, -18)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
	barBg.BorderSizePixel = 0
	barBg.Parent = button
	
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 3)
	barCorner.Parent = barBg
	
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = COLORS.accent
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = barFill
	
	-- Keybind hint
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Size = UDim2.new(1, 0, 0, 12)
	hint.Position = UDim2.new(0, 0, 1, -10)
	hint.BackgroundTransparency = 1
	hint.Text = "[T]"
	hint.TextColor3 = Color3.fromRGB(150, 150, 170)
	hint.TextSize = 10
	hint.Font = Enum.Font.GothamBold
	hint.Parent = button
	
	-- Hover effects
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15), {
			BackgroundTransparency = 0
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15), {
			Transparency = 0
		}):Play()
	end)
	
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15), {
			BackgroundTransparency = 0.15
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15), {
			Transparency = 0.3
		}):Play()
	end)
	
	return button
end

--------------------------------------------------------------------------------
-- UPDATE
--------------------------------------------------------------------------------

local function updateStorageBar()
	if not storageButton then return end
	
	local barBg = storageButton:FindFirstChild("CapacityBarBg")
	if not barBg then return end
	
	local fill = barBg:FindFirstChild("Fill")
	if not fill then return end
	
	-- Safely calculate ratio
	local usage = tonumber(storageUsage) or 0
	local capacity = tonumber(storageCapacity) or 2000
	if capacity <= 0 then capacity = 2000 end
	
	local ratio = math.clamp(usage / capacity, 0, 1)
	
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

--------------------------------------------------------------------------------
-- OPEN STORAGE (Transport UI)
--------------------------------------------------------------------------------

local function openStorage()
	-- Find and toggle Transport UI
	local transportGui = PlayerGui:FindFirstChild("TransportUI")
	if transportGui then
		local mainFrame = transportGui:FindFirstChild("MainFrame")
		if mainFrame then
			mainFrame.Visible = not mainFrame.Visible
			return
		end
	end
	
	-- Try to find BackpackHUD and switch to Storage tab
	local backpackGui = PlayerGui:FindFirstChild("BackpackHUD")
	if backpackGui then
		local mainFrame = backpackGui:FindFirstChild("MainFrame")
		if mainFrame then
			mainFrame.Visible = true
			-- Try to click Storage tab if it exists
			local tabContainer = mainFrame:FindFirstChild("TabContainer")
			if tabContainer then
				local storageTab = tabContainer:FindFirstChild("StorageTab")
				if storageTab then
					-- Simulate click by firing any click handlers
					-- The actual tab switching is handled by BackpackHUD
				end
			end
		end
	end
	
	print("📦 Storage opened via keybind/button")
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

-- Storage data update
StorageUpdatedEvent.OnClientEvent:Connect(function(total, capacity)
	-- Handle both table and separate value formats
	if type(total) == "table" then
		storageUsage = total.total or total.usage or 0
		storageCapacity = total.capacity or total.cap or 2000
	else
		storageUsage = total or 0
		storageCapacity = capacity or 2000
	end
	
	updateStorageBar()
end)

-- T keybind
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	if input.KeyCode == Enum.KeyCode.T then
		openStorage()
	end
end)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	screenGui = createScreenGui()
	storageButton = createStorageButton(screenGui)
	
	-- Button click handler
	storageButton.MouseButton1Click:Connect(openStorage)
	
	-- Fetch initial storage data
	task.spawn(function()
		local result = GetStorageFunction:InvokeServer()
		if type(result) == "table" then
			storageUsage = result.total or result.usage or 0
			storageCapacity = result.capacity or result.cap or 2000
		elseif type(result) == "number" then
			storageUsage = result
		end
		updateStorageBar()
	end)
	
	print("✓ StorageUI initialized (Press T or click button to open)")
end

-- Wait for character
if LocalPlayer.Character then
	task.spawn(initialize)
else
	LocalPlayer.CharacterAdded:Wait()
	task.spawn(initialize)
end
