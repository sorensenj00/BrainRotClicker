--[[
	NotificationManager Client Script
	
	Handles visual notifications and alerts for the player.
	
	Features:
	- Toast notifications (bottom-right corner)
	- Full-width banners for important events
	- Market ticker for price changes
	- Storage full warnings
	
	Part of the "Sell a Brainrot" system.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Get player
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Wait for events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local StorageUpdatedEvent = RemoteEvents:WaitForChild("StorageUpdated")
local ItemSoldEvent = RemoteEvents:WaitForChild("ItemSold")
local BackpackLoadedEvent = RemoteEvents:WaitForChild("BackpackLoaded")

-- Stock market for events
local stockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket")

-- UI Colors
local COLORS = {
	toast = Color3.fromRGB(30, 35, 50),
	success = Color3.fromRGB(50, 200, 100),
	warning = Color3.fromRGB(255, 180, 50),
	error = Color3.fromRGB(255, 80, 80),
	info = Color3.fromRGB(100, 180, 255),
	gold = Color3.fromRGB(255, 200, 50),
	text = Color3.fromRGB(255, 255, 255),
	textMuted = Color3.fromRGB(180, 180, 200),
}

-- Constants
local TOAST_DURATION = 3
local TOAST_WIDTH = 280
local TOAST_HEIGHT = 60
local MAX_TOASTS = 4

-- State
local activeToasts = {}
local screenGui = nil
local toastContainer = nil
local bannerFrame = nil

--------------------------------------------------------------------------------
-- TOAST NOTIFICATIONS
--------------------------------------------------------------------------------

local function createToastContainer()
	local container = Instance.new("Frame")
	container.Name = "ToastContainer"
	container.Size = UDim2.new(0, TOAST_WIDTH + 20, 1, 0)
	container.Position = UDim2.new(1, -TOAST_WIDTH - 30, 0, 0)
	container.BackgroundTransparency = 1
	container.Parent = screenGui
	
	return container
end

local function showToast(message, toastType, duration)
	toastType = toastType or "info"
	duration = duration or TOAST_DURATION
	
	local color = COLORS[toastType] or COLORS.info
	local emoji = {
		success = "✓",
		warning = "⚠",
		error = "✕",
		info = "ℹ",
		gold = "💰",
	}
	
	-- Create toast
	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.Size = UDim2.new(0, TOAST_WIDTH, 0, TOAST_HEIGHT)
	toast.Position = UDim2.new(0, TOAST_WIDTH + 20, 1, -10 - (#activeToasts * (TOAST_HEIGHT + 10)))
	toast.BackgroundColor3 = COLORS.toast
	toast.BackgroundTransparency = 0.1
	toast.Parent = toastContainer
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = toast
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = toast
	
	-- Icon
	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(0, 40, 1, 0)
	icon.BackgroundTransparency = 1
	icon.Text = emoji[toastType] or "ℹ"
	icon.TextColor3 = color
	icon.TextSize = 22
	icon.Font = Enum.Font.GothamBold
	icon.Parent = toast
	
	-- Message
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -50, 1, 0)
	label.Position = UDim2.new(0, 40, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = message
	label.TextColor3 = COLORS.text
	label.TextSize = 14
	label.Font = Enum.Font.Gotham
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Parent = toast
	
	-- Slide in
	table.insert(activeToasts, toast)
	TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
		Position = UDim2.new(0, 0, 1, -10 - ((#activeToasts - 1) * (TOAST_HEIGHT + 10)))
	}):Play()
	
	-- Auto-remove after duration
	task.delay(duration, function()
		-- Fade out
		TweenService:Create(toast, TweenInfo.new(0.3), {
			Position = UDim2.new(0, TOAST_WIDTH + 20, toast.Position.Y.Scale, toast.Position.Y.Offset)
		}):Play()
		
		task.wait(0.3)
		
		-- Remove from list and destroy
		local index = table.find(activeToasts, toast)
		if index then
			table.remove(activeToasts, index)
		end
		toast:Destroy()
		
		-- Reposition remaining toasts
		for i, t in ipairs(activeToasts) do
			TweenService:Create(t, TweenInfo.new(0.2), {
				Position = UDim2.new(0, 0, 1, -10 - ((i - 1) * (TOAST_HEIGHT + 10)))
			}):Play()
		end
	end)
	
	-- Limit max toasts
	while #activeToasts > MAX_TOASTS do
		local oldest = table.remove(activeToasts, 1)
		if oldest then oldest:Destroy() end
	end
end

--------------------------------------------------------------------------------
-- BANNER NOTIFICATIONS
--------------------------------------------------------------------------------

local function createBannerFrame()
	local banner = Instance.new("Frame")
	banner.Name = "BannerFrame"
	banner.Size = UDim2.new(1, 0, 0, 60)
	banner.Position = UDim2.new(0, 0, 0, -60)
	banner.BackgroundColor3 = COLORS.gold
	banner.BackgroundTransparency = 0.1
	banner.Visible = false
	banner.ZIndex = 10
	banner.Parent = screenGui
	
	local label = Instance.new("TextLabel")
	label.Name = "Message"
	label.Size = UDim2.new(1, -40, 1, 0)
	label.Position = UDim2.new(0, 20, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = Color3.fromRGB(20, 20, 30)
	label.TextSize = 24
	label.Font = Enum.Font.GothamBold
	label.ZIndex = 11
	label.Parent = banner
	
	return banner
end

local function showBanner(message, color, duration)
	color = color or COLORS.gold
	duration = duration or 4
	
	bannerFrame.BackgroundColor3 = color
	bannerFrame:FindFirstChild("Message").Text = message
	bannerFrame.Visible = true
	
	-- Slide down
	bannerFrame.Position = UDim2.new(0, 0, 0, -60)
	TweenService:Create(bannerFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back), {
		Position = UDim2.new(0, 0, 0, 0)
	}):Play()
	
	-- Auto hide
	task.delay(duration, function()
		TweenService:Create(bannerFrame, TweenInfo.new(0.3), {
			Position = UDim2.new(0, 0, 0, -60)
		}):Play()
		
		task.wait(0.3)
		bannerFrame.Visible = false
	end)
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

-- Storage full warning
StorageUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
	if total >= capacity then
		showToast("Storage is FULL! Brainrots are sleeping.", "warning")
	elseif total >= capacity * 0.9 then
		showToast("Storage almost full (" .. total .. "/" .. capacity .. ")", "warning")
	end
end)

-- Item sold notification
ItemSoldEvent.OnClientEvent:Connect(function(itemId, count, earned)
	if earned > 0 then
		local msg = string.format("+$%d for %dx %s", earned, count, itemId or "items")
		showToast(msg, "gold", 2)
	end
end)

-- Backpack loaded notification
BackpackLoadedEvent.OnClientEvent:Connect(function(itemId, count)
	if count > 0 then
		local msg = itemId and string.format("Loaded %dx %s", count, itemId) or string.format("Loaded %d items", count)
		showToast(msg, "info", 2)
	end
end)

-- Market rate changes
local lastRate = 1.0
stockMarketFolder:GetAttributeChangedSignal("CurrentRate"):Connect(function()
	local newRate = stockMarketFolder:GetAttribute("CurrentRate") or 1.0
	
	if newRate >= 2.5 and lastRate < 2.5 then
		showBanner("📈 HYPER INFLATION! Sell now for 2.5x+ prices!", COLORS.success, 5)
	elseif newRate <= 0.6 and lastRate > 0.6 then
		showBanner("📉 MARKET CRASH! Prices at historic lows!", COLORS.error, 5)
	end
	
	lastRate = newRate
end)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	-- Create screen gui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NotificationUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = PlayerGui
	
	-- Create containers
	toastContainer = createToastContainer()
	bannerFrame = createBannerFrame()
	
	print("✓ NotificationManager initialized")
end

initialize()

-- Export for other scripts
_G.NotificationManager = {
	ShowToast = showToast,
	ShowBanner = showBanner,
}
