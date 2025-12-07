--[[
	MewingUI Client Script
	
	Displays the player's Mewing streak status.
	Shows:
	- Current streak tier and emoji
	- Time in current streak
	- Income multiplier bonus
	- Visual feedback when streak breaks
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
-- RunService not needed for this UI
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

-- Player
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Configuration
local CONFIG = {
	TIER_COLORS = {
		[0] = Color3.fromRGB(100, 100, 100),
		[1] = Color3.fromRGB(180, 180, 255),
		[2] = Color3.fromRGB(100, 255, 100),
		[3] = Color3.fromRGB(255, 215, 0),
	},
	SOUNDS = {
		TIER_UP = "rbxassetid://6895079853",
		BREAK = "rbxassetid://5702385985",
	},
}

-- Wait for RemoteEvents
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local MewingUpdateEvent = RemoteEvents:WaitForChild("MewingUpdate", 30)
if not MewingUpdateEvent then
	warn("MewingUI: MewingUpdate event not found!")
	return
end

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MewingUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Main container (left side, below center)
local container = Instance.new("Frame")
container.Name = "MewingContainer"
container.Size = UDim2.new(0, 160, 0, 60)
container.Position = UDim2.new(0, 20, 0.6, 0)
container.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
container.BackgroundTransparency = 0.3
container.BorderSizePixel = 0
container.Visible = false -- Hidden until streak starts
container.Parent = screenGui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 10)
containerCorner.Parent = container

local containerStroke = Instance.new("UIStroke")
containerStroke.Thickness = 2
containerStroke.Color = Color3.fromRGB(60, 60, 80)
containerStroke.Parent = container

-- Emoji / Icon
local emojiLabel = Instance.new("TextLabel")
emojiLabel.Name = "Emoji"
emojiLabel.Size = UDim2.new(0, 50, 1, 0)
emojiLabel.Position = UDim2.new(0, 0, 0, 0)
emojiLabel.BackgroundTransparency = 1
emojiLabel.Text = "🤫"
emojiLabel.TextSize = 32
emojiLabel.Font = Enum.Font.GothamBold
emojiLabel.Parent = container

-- Status text container
local textContainer = Instance.new("Frame")
textContainer.Name = "TextContainer"
textContainer.Size = UDim2.new(1, -55, 1, 0)
textContainer.Position = UDim2.new(0, 55, 0, 0)
textContainer.BackgroundTransparency = 1
textContainer.Parent = container

-- Tier name
local tierLabel = Instance.new("TextLabel")
tierLabel.Name = "TierLabel"
tierLabel.Size = UDim2.new(1, 0, 0.5, 0)
tierLabel.Position = UDim2.new(0, 0, 0, 5)
tierLabel.BackgroundTransparency = 1
tierLabel.Text = "Mewing..."
tierLabel.TextColor3 = Color3.fromRGB(200, 200, 220)
tierLabel.TextSize = 14
tierLabel.Font = Enum.Font.GothamBold
tierLabel.TextXAlignment = Enum.TextXAlignment.Left
tierLabel.Parent = textContainer

-- Bonus label
local bonusLabel = Instance.new("TextLabel")
bonusLabel.Name = "BonusLabel"
bonusLabel.Size = UDim2.new(1, 0, 0.5, 0)
bonusLabel.Position = UDim2.new(0, 0, 0.5, -5)
bonusLabel.BackgroundTransparency = 1
bonusLabel.Text = "+0%"
bonusLabel.TextColor3 = Color3.fromRGB(150, 255, 150)
bonusLabel.TextSize = 12
bonusLabel.Font = Enum.Font.GothamMedium
bonusLabel.TextXAlignment = Enum.TextXAlignment.Left
bonusLabel.Parent = textContainer

--------------------------------------------------------------------------------
-- SOUND SETUP
--------------------------------------------------------------------------------

local tierUpSound = Instance.new("Sound")
tierUpSound.SoundId = CONFIG.SOUNDS.TIER_UP
tierUpSound.Volume = 0.6
tierUpSound.Parent = SoundService

local breakSound = Instance.new("Sound")
breakSound.SoundId = CONFIG.SOUNDS.BREAK
breakSound.Volume = 0.7
breakSound.Parent = SoundService

--------------------------------------------------------------------------------
-- UPDATE LOGIC
--------------------------------------------------------------------------------

local function showUI()
	if not container.Visible then
		container.Visible = true
		container.Position = UDim2.new(0, -160, 0.6, 0)
		local tween = TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
			Position = UDim2.new(0, 20, 0.6, 0)
		})
		tween:Play()
	end
end

local function hideUI()
	if container.Visible then
		local tween = TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0, -160, 0.6, 0)
		})
		tween:Play()
		tween.Completed:Wait()
		container.Visible = false
	end
end

local function onMewingUpdate(data)
	if data.type == "tier_up" then
		showUI()
		
		-- Update visuals
		emojiLabel.Text = data.emoji or "🤫"
		tierLabel.Text = data.name or "Mewing"
		bonusLabel.Text = string.format("+%.0f%%", (data.multiplier - 1) * 100)
		
		-- Color
		local color = CONFIG.TIER_COLORS[data.tier] or CONFIG.TIER_COLORS[1]
		containerStroke.Color = color
		tierLabel.TextColor3 = color
		
		-- Play sound
		tierUpSound:Play()
		
		-- Animate
		emojiLabel.TextSize = 24
		local tween = TweenService:Create(emojiLabel, TweenInfo.new(0.3, Enum.EasingStyle.Back), {
			TextSize = 32
		})
		tween:Play()
		
	elseif data.type == "break" then
		-- Play break sound
		breakSound:Play()
		
		-- Flash red
		local _originalColor = containerStroke.Color
		containerStroke.Color = Color3.fromRGB(255, 50, 50)
		task.wait(0.3)
		
		-- Hide UI
		hideUI()
	end
end

-- Connect event
MewingUpdateEvent.OnClientEvent:Connect(onMewingUpdate)

-- Check initial state (in case player rejoins mid-streak)
local function checkInitialState()
	local tier = player:GetAttribute("MewingTier") or 0
	local multiplier = player:GetAttribute("MewingMultiplier") or 1.0
	
	if tier > 0 then
		local tierNames = {"Streak Started", "Locked In", "GigaChad"}
		local emojis = {"🤫", "🔒", "🗿"}
		onMewingUpdate({
			type = "tier_up",
			tier = tier,
			name = tierNames[tier] or "Mewing",
			emoji = emojis[tier] or "🤫",
			multiplier = multiplier,
		})
	end
end

-- Wait a bit for attributes to load
task.delay(2, checkInitialState)

print("✓ MewingUI initialized")
