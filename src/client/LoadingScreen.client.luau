--[[
	LoadingScreen Client Script
	
	Blocks view/interaction until server confirms all data and world elements are ready.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PlayerReadyEvent = RemoteEvents:WaitForChild("PlayerReady")

-- Config
local CONFIG = {
	BG_COLOR = Color3.fromRGB(15, 15, 20),
	ACCENT_COLOR = Color3.fromRGB(140, 80, 160), -- Purple/Pink theme
	FADE_TIME = 0.8,
}

-- UI State
local screenGui
local mainFrame
local dotsLabel
local isLoaded = false

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local function createLoadingUI()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LoadingScreen"
	screenGui.IgnoreGuiInset = true -- Cover topbar
	screenGui.DisplayOrder = 10000 -- On top of everything
	screenGui.ResetOnSpawn = false
	screenGui.Parent = PlayerGui
	
	mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.BackgroundColor3 = CONFIG.BG_COLOR
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = screenGui
	
	-- Loading Container
	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, 300, 0, 100)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.new(0.5, 0, 0.5, 0)
	container.BackgroundTransparency = 1
	container.Parent = mainFrame
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Text = "BRAINROT CLICKER"
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 32
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Parent = container
	
	-- Loading Text
	dotsLabel = Instance.new("TextLabel")
	dotsLabel.Text = "Loading..."
	dotsLabel.Font = Enum.Font.GothamMedium
	dotsLabel.TextSize = 18
	dotsLabel.TextColor3 = CONFIG.ACCENT_COLOR
	dotsLabel.Size = UDim2.new(1, 0, 0, 20)
	dotsLabel.Position = UDim2.new(0, 0, 0, 50)
	dotsLabel.BackgroundTransparency = 1
	dotsLabel.Parent = container
	
	-- Disable Core GUIs explicitly
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local function animateDots()
	local dots = "..."
	local count = 0
	while not isLoaded and mainFrame.Parent do
		count = (count + 1) % 4
		dotsLabel.Text = "Loading" .. string.rep(".", count)
		task.wait(0.5)
	end
end

local function onReady()
	if isLoaded then return end
	isLoaded = true
	
	print("LoadingScreen: Server says READY. Fading out...")
	
	-- Fade out
	local tweenInfo = TweenInfo.new(CONFIG.FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(mainFrame, tweenInfo, {BackgroundTransparency = 1})
	
	-- Fade text too
	for _, child in mainFrame:GetDescendants() do
		if child:IsA("TextLabel") then
			TweenService:Create(child, tweenInfo, {TextTransparency = 1}):Play()
		end
	end
	
	tween:Play()
	tween.Completed:Wait()
	
	screenGui:Destroy()
	
	-- Re-enable Core GUIs
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) -- Keep custom if needed, or true
end

-- Init
createLoadingUI()
task.spawn(animateDots)

-- Listen for signal
PlayerReadyEvent.OnClientEvent:Connect(onReady)

-- Timeout Safety (15s)
task.delay(15, function()
	if not isLoaded then
		warn("LoadingScreen: Timed out waiting for server!")
		dotsLabel.Text = "Taking longer than expected..."
		-- Optional: Reveal anyway or show Retry button
		task.wait(5)
		if not isLoaded then
			dotsLabel.Text = "Connection slow. Please Rejoin."
		end
	end
end)
