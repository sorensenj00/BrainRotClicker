--[[
	AdminPanel Client Script
	
	Categorized admin testing panel with sections:
	- Player: Reset Plot, Add Money, Toggle Fly
	- Economy: Give Items, Wipe Inventory
	- Market: Force Local Crash, Force Local Moon
	- Shops: Quick-open all shop UIs
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for RemoteEvents
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local AdminAction = RemoteEvents:WaitForChild("AdminAction")

-- Theme
local THEME = {
	BG = Color3.fromRGB(18, 18, 24),
	PANEL = Color3.fromRGB(28, 28, 36),
	SECTION = Color3.fromRGB(35, 35, 45),
	ACCENT = Color3.fromRGB(255, 70, 70),
	AMBER = Color3.fromRGB(255, 182, 39),
	GREEN = Color3.fromRGB(0, 255, 136),
	RED = Color3.fromRGB(255, 51, 51),
	BLUE = Color3.fromRGB(60, 130, 255),
	WHITE = Color3.fromRGB(230, 230, 235),
	MUTED = Color3.fromRGB(110, 110, 125),
	BTN = Color3.fromRGB(50, 50, 65),
	BTN_HOVER = Color3.fromRGB(70, 70, 90),
	INPUT_BG = Color3.fromRGB(20, 20, 28),
}

local FONT_BOLD = Enum.Font.GothamBold
local FONT_MONO = Enum.Font.RobotoMono

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AdminPanel"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

-- Toggle Button (Bottom Right)
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "ToggleBtn"
toggleBtn.Size = UDim2.new(0, 50, 0, 50)
toggleBtn.Position = UDim2.new(1, -60, 1, -60)
toggleBtn.BackgroundColor3 = THEME.ACCENT
toggleBtn.Text = "DEV"
toggleBtn.TextColor3 = THEME.WHITE
toggleBtn.Font = FONT_BOLD
toggleBtn.TextSize = 14
toggleBtn.AutoButtonColor = true
toggleBtn.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0.5, 0)
uiCorner.Parent = toggleBtn

-- Main Panel (wider, scrollable)
local panel = Instance.new("ScrollingFrame")
panel.Name = "MainPanel"
panel.Size = UDim2.new(0, 420, 0, 600)
panel.Position = UDim2.new(1, -440, 1, -620)
panel.BackgroundColor3 = THEME.BG
panel.BorderSizePixel = 0
panel.ScrollBarThickness = 4
panel.ScrollBarImageColor3 = THEME.AMBER
panel.CanvasSize = UDim2.new(0, 0, 0, 0)
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.Visible = false
panel.Parent = screenGui

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke")
stroke.Color = THEME.ACCENT
stroke.Thickness = 2
stroke.Transparency = 0.3
stroke.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingBottom = UDim.new(0, 12)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = panel

-- Status label (feedback)
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.Size = UDim2.new(1, 0, 0, 0) -- Hidden initially
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = THEME.GREEN
statusLabel.Font = FONT_MONO
statusLabel.TextSize = 11
statusLabel.TextWrapped = true
statusLabel.Text = ""
statusLabel.AutomaticSize = Enum.AutomaticSize.Y
statusLabel.LayoutOrder = 0
statusLabel.Parent = panel

local function showStatus(msg, color)
	statusLabel.Text = msg
	statusLabel.TextColor3 = color or THEME.GREEN
	statusLabel.Size = UDim2.new(1, 0, 0, 20)
	task.delay(3, function()
		if statusLabel.Text == msg then
			statusLabel.Text = ""
			statusLabel.Size = UDim2.new(1, 0, 0, 0)
		end
	end)
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local layoutOrder = 0
local function nextOrder()
	layoutOrder += 1
	return layoutOrder
end

local function createSectionHeader(text, icon, color)
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 28)
	header.BackgroundColor3 = THEME.SECTION
	header.Text = icon .. " " .. text
	header.TextColor3 = color or THEME.AMBER
	header.Font = FONT_BOLD
	header.TextSize = 13
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.LayoutOrder = nextOrder()
	header.Parent = panel
	
	Instance.new("UICorner", header).CornerRadius = UDim.new(0, 6)
	
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.Parent = header
	
	return header
end

local function createButton(text, color, callback)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 36)
	btn.BackgroundColor3 = color or THEME.BTN
	btn.Text = text
	btn.TextColor3 = THEME.WHITE
	btn.Font = FONT_BOLD
	btn.TextSize = 13
	btn.AutoButtonColor = false
	btn.LayoutOrder = nextOrder()
	btn.Parent = panel
	
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = THEME.BTN_HOVER}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = color or THEME.BTN}):Play()
	end)
	
	btn.MouseButton1Click:Connect(function()
		btn.BackgroundColor3 = THEME.AMBER
		task.delay(0.1, function() btn.BackgroundColor3 = color or THEME.BTN end)
		callback()
	end)
	
	return btn
end

local function createTextInput(placeholder)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 0, 34)
	frame.BackgroundColor3 = THEME.INPUT_BG
	frame.LayoutOrder = nextOrder()
	frame.Parent = panel
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
	
	local stroke2 = Instance.new("UIStroke")
	stroke2.Color = THEME.MUTED
	stroke2.Thickness = 1
	stroke2.Transparency = 0.5
	stroke2.Parent = frame
	
	local textBox = Instance.new("TextBox")
	textBox.Size = UDim2.new(1, -16, 1, 0)
	textBox.Position = UDim2.new(0, 8, 0, 0)
	textBox.BackgroundTransparency = 1
	textBox.TextColor3 = THEME.WHITE
	textBox.PlaceholderText = placeholder
	textBox.PlaceholderColor3 = THEME.MUTED
	textBox.Font = FONT_MONO
	textBox.TextSize = 13
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.ClearTextOnFocus = false
	textBox.Text = ""
	textBox.Parent = frame
	
	return textBox
end

--------------------------------------------------------------------------------
-- SECTIONS
--------------------------------------------------------------------------------

-- === PLAYER ===
createSectionHeader("PLAYER", "👤", THEME.BLUE)

createButton("🔄 Reset Plot", nil, function()
	local success, msg = AdminAction:InvokeServer("ResetPlot")
	showStatus(msg, success and THEME.GREEN or THEME.RED)
end)

createButton("💰 Add $1M", nil, function()
	local success, msg = AdminAction:InvokeServer("AddMoney")
	showStatus(msg, success and THEME.GREEN or THEME.RED)
end)

createButton("🕊️ Toggle Fly", nil, function()
	local success, msg = AdminAction:InvokeServer("ToggleFly")
	showStatus(msg, success and THEME.GREEN or THEME.RED)
end)

createButton("💀 WIPE DATA", Color3.fromRGB(80, 30, 30), function()
	local success, msg = AdminAction:InvokeServer("WipeProfile")
	showStatus(msg, success and THEME.GREEN or THEME.RED)
	if success then
		game.Players.LocalPlayer:Kick("Data wiped! Rejoin for fresh start.")
	end
end)

-- === ECONOMY ===
createSectionHeader("ECONOMY", "📦", THEME.GREEN)

local itemIdInput = createTextInput("Item ID (e.g. Guac1, Skibidi)")

createButton("📦 Give 1000x Items", Color3.fromRGB(30, 70, 45), function()
	local itemId = itemIdInput.Text
	if itemId == "" then
		showStatus("Enter an Item ID first!", THEME.RED)
		return
	end
	local success, msg = AdminAction:InvokeServer("GiveItems", itemId, 1000)
	showStatus(msg, success and THEME.GREEN or THEME.RED)
end)

createButton("🗑️ Wipe Inventory", Color3.fromRGB(80, 50, 20), function()
	local success, msg = AdminAction:InvokeServer("WipeInventory")
	showStatus(msg, success and THEME.GREEN or THEME.RED)
end)

-- === MARKET ===
createSectionHeader("MARKET", "📈", THEME.AMBER)

createButton("🔻 Force Local CRASH", Color3.fromRGB(100, 20, 20), function()
	local success, msg = AdminAction:InvokeServer("ForceLocalCrash")
	showStatus(msg, success and THEME.GREEN or THEME.RED)
end)

createButton("🚀 Force Local MOON", Color3.fromRGB(20, 80, 50), function()
	local success, msg = AdminAction:InvokeServer("ForceLocalMoon")
	showStatus(msg, success and THEME.GREEN or THEME.RED)
end)

-- === SHOPS ===
createSectionHeader("SHOPS", "🛒", THEME.MUTED)

local adminEvent = ReplicatedStorage:FindFirstChild("AdminOpenShop")
if not adminEvent then
	adminEvent = Instance.new("BindableEvent")
	adminEvent.Name = "AdminOpenShop"
	adminEvent.Parent = ReplicatedStorage
end

local shopButtons = {
	{"🛒 Cart Shop", "CartShop"},
	{"🏝️ Island Shop", "IslandShop"},
	{"🧠 Machine Shop", "MachineShop"},
	{"📦 Storage Shop", "StorageUpgrades"},
	{"⚡ Conv. Shop", "ConvenienceUpgrades"},
	{"🏛️ Artifact Exchange", "ArtifactExchange"},
}

for _, shop in ipairs(shopButtons) do
	createButton(shop[1], nil, function()
		adminEvent:Fire(shop[2])
	end)
end

-- Toggle Logic
toggleBtn.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

--------------------------------------------------------------------------------
-- FLIGHT LOGIC
--------------------------------------------------------------------------------

local flightConnection = nil
local bodyVelocity = nil
local bodyGyro = nil
local FLIGHT_SPEED = 50

local function stopFlying()
	if flightConnection then
		flightConnection:Disconnect()
		flightConnection = nil
	end
	
	if bodyVelocity then bodyVelocity:Destroy(); bodyVelocity = nil end
	if bodyGyro then bodyGyro:Destroy(); bodyGyro = nil end
	
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
		end
	end
end

local function startFlying()
	stopFlying()
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not hrp or not humanoid then return end
	
	bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Velocity = Vector3.new(0, 0, 0)
	bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bodyVelocity.Parent = hrp
	
	bodyGyro = Instance.new("BodyGyro")
	bodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	bodyGyro.CFrame = hrp.CFrame
	bodyGyro.Parent = hrp
	
	humanoid.PlatformStand = true
	
	flightConnection = RunService.RenderStepped:Connect(function()
		if not player:GetAttribute("IsFlying") then
			stopFlying()
			return
		end
		
		local camCFrame = workspace.CurrentCamera.CFrame
		local moveDir = Vector3.new(0, 0, 0)
		
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir += camCFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir -= camCFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir -= camCFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir += camCFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir += Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir -= Vector3.new(0, 1, 0) end
		
		if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end
		
		bodyVelocity.Velocity = moveDir * FLIGHT_SPEED
		bodyGyro.CFrame = camCFrame
	end)
end

player:GetAttributeChangedSignal("IsFlying"):Connect(function()
	if player:GetAttribute("IsFlying") then startFlying() else stopFlying() end
end)

player.CharacterAdded:Connect(function()
	if player:GetAttribute("IsFlying") then
		task.wait(0.5)
		startFlying()
	end
end)

print("✓ AdminPanel loaded (categorized)")
