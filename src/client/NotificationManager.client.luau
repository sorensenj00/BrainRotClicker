--[[
	NotificationManager Client Script (V2 - Premium Edition)
	
	A modern, glassmorphic notification pipeline for Brainrot Clicker.
	Features:
	- Spring-animated Toasts with duration bars
	- Sleek top-down Banners for global events
	- Modular API exposed via _G.NotificationManager
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--------------------------------------------------------------------------------
-- CONFIGURATION & THEME
--------------------------------------------------------------------------------

local THEME = {
	-- Base
	Background = Color3.fromRGB(15, 15, 22),
	BackgroundTransparency = 0.25, -- Glass effect
	Text = Color3.fromRGB(240, 240, 245),
	TextMuted = Color3.fromRGB(170, 170, 180),
	
	-- Types
	info = Color3.fromRGB(80, 160, 255),
	success = Color3.fromRGB(80, 220, 120),
	warning = Color3.fromRGB(255, 170, 50),
	error = Color3.fromRGB(255, 80, 80),
	gold = Color3.fromRGB(255, 210, 60),
	
	-- Layout
	ToastWidth = 320,
	ToastHeight = 65,
	ToastGap = 12,
	MaxToasts = 5,
	CornerRadius = 12,
}

local ICONS = {
	info = "ℹ️",
	success = "✨",
	warning = "⚠️",
	error = "❌",
	gold = "💎",
}

--------------------------------------------------------------------------------
-- STATE & UI SETUP
--------------------------------------------------------------------------------

local ActiveToasts = {}
local ScreenGui = nil
local ToastContainer = nil
local BannerContainer = nil
local ActiveBanner = nil

local function initializeUI()
	if ScreenGui then return end
	
	ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "NotificationManagerV2"
	ScreenGui.ResetOnSpawn = false
	ScreenGui.DisplayOrder = 100 -- Sit above most things
	ScreenGui.Parent = PlayerGui
	
	-- Container for top-center toasts
	ToastContainer = Instance.new("Frame")
	ToastContainer.Name = "ToastContainer"
	ToastContainer.Size = UDim2.new(0, THEME.ToastWidth, 1, 0)
	ToastContainer.Position = UDim2.new(0.5, -THEME.ToastWidth / 2, 0, 0)
	ToastContainer.BackgroundTransparency = 1
	ToastContainer.Parent = ScreenGui
	
	-- Container for top-center banners
	BannerContainer = Instance.new("Frame")
	BannerContainer.Name = "BannerContainer"
	BannerContainer.Size = UDim2.new(1, 0, 0, 100)
	BannerContainer.Position = UDim2.new(0, 0, 0, 0)
	BannerContainer.BackgroundTransparency = 1
	BannerContainer.ClipsDescendants = false
	BannerContainer.Parent = ScreenGui
end

--------------------------------------------------------------------------------
-- TOAST ENGINE
--------------------------------------------------------------------------------

local function createToastElement(message, typeKey, duration)
	local color = THEME[typeKey] or THEME.info
	local icon = ICONS[typeKey] or ICONS.info
	
	-- Main Frame
	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.Size = UDim2.new(1, 0, 0, THEME.ToastHeight)
	toast.BackgroundColor3 = THEME.Background
	toast.BackgroundTransparency = THEME.BackgroundTransparency
	toast.BorderSizePixel = 0
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, THEME.CornerRadius)
	corner.Parent = toast
	
	-- Glow/Stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 1.5
	stroke.Transparency = 0.6
	stroke.Parent = toast
	
	-- Icon Box
	local iconBox = Instance.new("Frame")
	iconBox.Size = UDim2.new(0, 50, 1, -4) -- Leaves room for the progress bar
	iconBox.Position = UDim2.new(0, 0, 0, 0)
	iconBox.BackgroundTransparency = 1
	iconBox.Parent = toast
	
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(1, 0, 1, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = icon
	iconLabel.TextSize = 24
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.Parent = iconBox
	
	-- Text Box
	local messageLabel = Instance.new("TextLabel")
	messageLabel.Size = UDim2.new(1, -60, 1, -4)
	messageLabel.Position = UDim2.new(0, 50, 0, 0)
	messageLabel.BackgroundTransparency = 1
	messageLabel.Text = message
	messageLabel.TextColor3 = THEME.Text
	messageLabel.TextSize = 14
	messageLabel.Font = Enum.Font.GothamMedium
	messageLabel.TextXAlignment = Enum.TextXAlignment.Left
	messageLabel.TextWrapped = true
	messageLabel.Parent = toast
	
	-- Duration Bar
	local barBg = Instance.new("Frame")
	barBg.Size = UDim2.new(1, 0, 0, 4)
	barBg.Position = UDim2.new(0, 0, 1, -4)
	barBg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	barBg.BackgroundTransparency = 0.5
	barBg.BorderSizePixel = 0
	barBg.Parent = toast
	
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 4)
	barCorner.Parent = barBg
	
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = color
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = barFill
	
	-- Progress Animation
	TweenService:Create(barFill, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = UDim2.new(0, 0, 1, 0)
	}):Play()
	
	return toast
end

local function updateToastPositions()
	for i, toastData in ipairs(ActiveToasts) do
		local targetY = 40 + ((i - 1) * (THEME.ToastHeight + THEME.ToastGap))
		
		TweenService:Create(toastData.frame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, 0, 0, targetY)
		}):Play()
	end
end

local function ShowToast(message: string, typeKey: string, duration: number)
	if not ScreenGui then initializeUI() end
	
	typeKey = typeKey or "info"
	duration = duration or 4
	
	local toast = createToastElement(message, typeKey, duration)
	
	-- Start position (slided up, off-screen)
	toast.Position = UDim2.new(0, 0, 0, -100 - (#ActiveToasts * (THEME.ToastHeight + THEME.ToastGap)))
	toast.Parent = ToastContainer
	
	local toastData = { frame = toast, time = tick() + duration }
	table.insert(ActiveToasts, 1, toastData) -- Insert at beginning (pushes others down)
	
	-- Enforce MAX_TOASTS
	if #ActiveToasts > THEME.MaxToasts then
		local oldest = table.remove(ActiveToasts, #ActiveToasts)
		TweenService:Create(oldest.frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0, 0, 0, -150)
		}):Play()
		task.delay(0.3, function() oldest.frame:Destroy() end)
	end
	
	updateToastPositions()
	
	-- Auto-cleanup
	task.delay(duration, function()
		local index = table.find(ActiveToasts, toastData)
		if index then
			table.remove(ActiveToasts, index)
			
			-- Slide out
			local outTween = TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(0, 0, 0, -150)
			})
			outTween:Play()
			
			outTween.Completed:Connect(function()
				toast:Destroy()
			end)
			
			updateToastPositions()
		end
	end)
end

--------------------------------------------------------------------------------
-- BANNER ENGINE
--------------------------------------------------------------------------------

local function ShowBanner(message: string, color: Color3, duration: number)
	if not ScreenGui then initializeUI() end
	
	color = color or THEME.gold
	duration = duration or 5
	
	if ActiveBanner then
		ActiveBanner:Destroy()
	end
	
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Size = UDim2.new(0, 600, 0, 70)
	banner.Position = UDim2.new(0.5, -300, 0, -80) -- Off-screen top
	banner.BackgroundColor3 = THEME.Background
	banner.BackgroundTransparency = 0.1
	banner.BorderSizePixel = 0
	banner.Parent = BannerContainer
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = banner
	
	-- Dramatic glowing stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = banner
	
	-- Left Accent Line
	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 6, 1, -20)
	accent.Position = UDim2.new(0, 10, 0, 10)
	accent.BackgroundColor3 = color
	accent.BorderSizePixel = 0
	accent.Parent = banner
	
	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(1, 0)
	accentCorner.Parent = accent
	
	-- Message
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -40, 1, 0)
	label.Position = UDim2.new(0, 30, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = message
	label.TextColor3 = THEME.Text
	label.TextSize = 22
	label.Font = Enum.Font.GothamBold
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = banner
	
	ActiveBanner = banner
	
	-- Slide In
	TweenService:Create(banner, TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -300, 0, 20)
	}):Play()
	
	-- Slide Out
	task.delay(duration, function()
		if ActiveBanner == banner then
			local outTween = TweenService:Create(banner, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.In), {
				Position = UDim2.new(0.5, -300, 0, -80)
			})
			outTween:Play()
			task.delay(0.5, function() banner:Destroy() end)
		end
	end)
end

local function formatMoneyShort(amount)
	if amount >= 1000000000 then return string.format("$%.2fB", amount / 1000000000) end
	if amount >= 1000000 then return string.format("$%.2fM", amount / 1000000) end
	if amount >= 1000 then return string.format("$%.1fK", amount / 1000) end
	return "$" .. tostring(math.floor(amount))
end

local function playScreenShake(duration, amplitude)
	local camera = workspace.CurrentCamera
	if not camera then return end

	local startTime = tick()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		if elapsed >= duration then
			if connection then connection:Disconnect() end
			return
		end

		local fade = 1 - (elapsed / duration)
		local offset = Vector3.new(
			(math.random() - 0.5) * 2 * amplitude * fade,
			(math.random() - 0.5) * 2 * amplitude * fade,
			0
		)
		camera.CFrame = camera.CFrame * CFrame.new(offset)
	end)
end

local function spawnConfetti(originPosition)
	local source = Instance.new("Part")
	source.Name = "ToTheMoonConfetti"
	source.Size = Vector3.new(1, 1, 1)
	source.Anchored = true
	source.CanCollide = false
	source.Transparency = 1
	source.Position = originPosition + Vector3.new(0, 5, 0)
	source.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(20, 35)
	emitter.Lifetime = NumberRange.new(1.5, 2.8)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 80, 80)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 60)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80, 220, 120)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 255, 255)),
	})
	emitter.Parent = source
	emitter:Emit(220)

	Debris:AddItem(source, 4)
end

local function launchRocket(originPosition)
	local rocket = Instance.new("Part")
	rocket.Name = "ToTheMoonRocket"
	rocket.Size = Vector3.new(1, 3, 1)
	rocket.Material = Enum.Material.Metal
	rocket.Color = Color3.fromRGB(235, 235, 235)
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CFrame = CFrame.new(originPosition + Vector3.new(0, 6, 0))
	rocket.Parent = workspace

	local top = Instance.new("Part")
	top.Name = "RocketTop"
	top.Shape = Enum.PartType.Ball
	top.Size = Vector3.new(1.1, 1.1, 1.1)
	top.Material = Enum.Material.Neon
	top.Color = Color3.fromRGB(255, 100, 100)
	top.Anchored = true
	top.CanCollide = false
	top.CFrame = rocket.CFrame * CFrame.new(0, 1.8, 0)
	top.Parent = workspace

	local bottomAttach = Instance.new("Attachment")
	bottomAttach.Position = Vector3.new(0, -1.5, 0)
	bottomAttach.Parent = rocket
	local topAttach = Instance.new("Attachment")
	topAttach.Position = Vector3.new(0, -3.5, 0)
	topAttach.Parent = rocket

	local trail = Instance.new("Trail")
	trail.Attachment0 = bottomAttach
	trail.Attachment1 = topAttach
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 170, 50), Color3.fromRGB(255, 70, 70))
	trail.Lifetime = 0.3
	trail.LightEmission = 1
	trail.Parent = rocket

	local upTween = TweenService:Create(rocket, TweenInfo.new(1.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		CFrame = rocket.CFrame * CFrame.new(0, 140, 0),
	})
	local topTween = TweenService:Create(top, TweenInfo.new(1.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		CFrame = top.CFrame * CFrame.new(0, 140, 0),
	})
	upTween:Play()
	topTween:Play()

	Debris:AddItem(rocket, 3)
	Debris:AddItem(top, 3)
end

--------------------------------------------------------------------------------
-- API EXPORT
--------------------------------------------------------------------------------

_G.NotificationManager = {
	ShowToast = ShowToast,
	ShowBanner = ShowBanner,
}

--------------------------------------------------------------------------------
-- LEGACY EVENT LISTENERS (Kept for compatibility, but UI is upgraded)
--------------------------------------------------------------------------------

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local StorageUpdatedEvent = RemoteEvents:WaitForChild("StorageUpdated")
local ItemSoldEvent = RemoteEvents:WaitForChild("ItemSold")
local CartSoldEvent = RemoteEvents:WaitForChild("CartSold")
local BackpackLoadedEvent = RemoteEvents:WaitForChild("BackpackLoaded")
local ArtifactDroppedEvent = RemoteEvents:WaitForChild("ArtifactDropped")
local ToTheMoonCelebrationEvent = RemoteEvents:WaitForChild("ToTheMoonCelebration")
local DroneOpsNotifyEvent = RemoteEvents:WaitForChild("DroneOpsNotify")
local ContractEventRemote = RemoteEvents:WaitForChild("ContractEvent")
local AchievementNotifyEvent = RemoteEvents:WaitForChild("AchievementNotify")
local StockMarketFolder = ReplicatedStorage:WaitForChild("StockMarket")

StorageUpdatedEvent.OnClientEvent:Connect(function(items, total, capacity)
	if total >= capacity then
		ShowToast("Storage is FULL! Units have stopped producing.", "error", 5)
	end
end)

ItemSoldEvent.OnClientEvent:Connect(function(itemId, count, earned)
	if earned > 0 then
		-- Try to get the friendly name
		local displayName = itemId
		local Shared = ReplicatedStorage:FindFirstChild("Shared")
		if Shared then
			local success, IC = pcall(function() return require(Shared:WaitForChild("ItemConfig")) end)
			if success and IC and IC.Items[itemId] then
				displayName = IC.Items[itemId].displayName or itemId
			end
		end
		
		local msg = string.format("+$%d for selling %dx %s", earned, count, displayName)
		ShowToast(msg, "gold", 2.5)
	end
end)

CartSoldEvent.OnClientEvent:Connect(function(earned, inventory)
	if earned > 0 then
		local function formatMoney(amount)
			if amount >= 1000000000 then return string.format("$%.2fB", amount / 1000000000)
			elseif amount >= 1000000 then return string.format("$%.2fM", amount / 1000000)
			elseif amount >= 1000 then return string.format("$%.1fK", amount / 1000)
			else return "$" .. tostring(math.floor(amount)) end
		end
		
		local msg = string.format("🛒 CART SOLD! +%s", formatMoney(earned))
		ShowBanner(msg, THEME.success, 5)
	end
end)

BackpackLoadedEvent.OnClientEvent:Connect(function(itemId, count)
	if count > 0 then
		local displayName = itemId
		local Shared = ReplicatedStorage:FindFirstChild("Shared")
		if Shared then
			local success, IC = pcall(function() return require(Shared:WaitForChild("ItemConfig")) end)
			if success and IC and IC.Items[itemId] then
				displayName = IC.Items[itemId].displayName or itemId
			end
		end
		local msg = itemId and string.format("Loaded %dx %s onto transport", count, displayName) or string.format("Loaded %d items onto transport", count)
		ShowToast(msg, "info", 3)
	end
end)

ArtifactDroppedEvent.OnClientEvent:Connect(function(artifact)
	if not artifact or not artifact.Name then return end

	local rarity = artifact.Rarity or "Common"
	
	if rarity == "Legendary" or rarity == "Epic" then
		-- Big banner for rare artifacts
		local msg = string.format("🏆 RARE ARTIFACT FOUND: %s!", artifact.Name)
		ShowBanner(msg, THEME.gold, 5)
	else
		-- Standard toast for normal artifacts
		local msg = string.format("Found new artifact: %s", artifact.Name)
		local typeKey = rarity == "Rare" and "gold" or "info"
		ShowToast(msg, typeKey, 4)
	end
end)

ToTheMoonCelebrationEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local sellerName = payload.sellerName or "Someone"
	local totalEarned = tonumber(payload.totalEarned) or 0
	local originPosition = payload.originPosition
	if typeof(originPosition) ~= "Vector3" then
		originPosition = Vector3.new(0, 32, 0)
	end

	local bannerMessage = string.format("TO THE MOON! %s just made bank! +%s", sellerName, formatMoneyShort(totalEarned))
	ShowBanner(bannerMessage, THEME.gold, 6)
	playScreenShake(0.6, 0.28)
	spawnConfetti(originPosition)
	launchRocket(originPosition)
end)

DroneOpsNotifyEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local message = payload.message or payload.Message
	if type(message) ~= "string" or message == "" then return end
	local typeKey = payload.type or payload.Type or "info"
	local duration = tonumber(payload.duration or payload.Duration) or 4
	ShowToast(message, typeKey, duration)
end)

ContractEventRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local action = payload.Action
	if action == "Spawned" then
		local contract = payload.Contract
		local title = (type(contract) == "table" and contract.Name) or "New Contract"
		ShowBanner("CONTRACT SPAWNED: " .. tostring(title), THEME.gold, 6)
	elseif action == "Completed" then
		local contract = payload.Contract
		local title = (type(contract) == "table" and contract.Name) or "Contract"
		ShowToast("Contract completed: " .. tostring(title), "success", 4)
	elseif action == "Expired" then
		local contract = payload.Contract
		local title = (type(contract) == "table" and contract.Name) or "Contract"
		ShowToast("Contract expired: " .. tostring(title), "warning", 4)
	end
end)

AchievementNotifyEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local action = payload.Action
	local title = tostring(payload.Title or "Achievement")
	if action == "Unlocked" then
		ShowBanner("ACHIEVEMENT UNLOCKED: " .. title, THEME.gold, 4.5)
	elseif action == "Claimed" then
		local rewards = payload.Rewards
		local rewardText = ""
		if type(rewards) == "table" then
			for _, reward in ipairs(rewards) do
				if type(reward) == "table" and reward.Type == "money" then
					rewardText = rewardText .. " +" .. formatMoneyShort(tonumber(reward.Amount) or 0)
				elseif type(reward) == "table" and reward.Type == "braincells" then
					rewardText = rewardText .. " +" .. tostring(math.floor(tonumber(reward.Amount) or 0)) .. " Braincells"
				end
			end
		end
		ShowToast("Achievement reward claimed: " .. title .. rewardText, "success", 4)
	end
end)

local lastRate = 1.0
StockMarketFolder:GetAttributeChangedSignal("CurrentRate"):Connect(function()
	local newRate = StockMarketFolder:GetAttribute("CurrentRate") or 1.0
	
	if newRate >= 2.5 and lastRate < 2.5 then
		ShowBanner("📈 HYPER INFLATION! Sell now for massive profits!", THEME.success, 6)
	elseif newRate <= 0.6 and lastRate > 0.6 then
		ShowBanner("📉 MARKET CRASH! Prices are at historic lows!", THEME.error, 6)
	end
	
	lastRate = newRate
end)

initializeUI()
print("✓ NotificationManager V2 (Premium) Initialized!")
