--[[
	AdminPanel Client Script
	
	Provides a UI for testing commands.
	- Reset Plot
	- Add Money
	- Toggle Fly
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

-- Configuration
local UI_CONFIG = {
	BUTTON_SIZE = UDim2.new(0, 50, 0, 50),
	PANEL_SIZE = UDim2.new(0, 200, 0, 250),
	COLOR_PRIMARY = Color3.fromRGB(40, 40, 50),
	COLOR_ACCENT = Color3.fromRGB(255, 100, 100), -- Red for dev
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
}

--------------------------------------------------------------------------------
-- UI CREATION
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AdminPanel"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Toggle Button (Bottom Right)
local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "ToggleBtn"
toggleBtn.Size = UI_CONFIG.BUTTON_SIZE
toggleBtn.Position = UDim2.new(1, -60, 1, -60)
toggleBtn.BackgroundColor3 = UI_CONFIG.COLOR_ACCENT
toggleBtn.Text = "DEV"
toggleBtn.TextColor3 = UI_CONFIG.TEXT_COLOR
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.AutoButtonColor = true
toggleBtn.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0.5, 0)
uiCorner.Parent = toggleBtn

-- Main Panel
local panel = Instance.new("Frame")
panel.Name = "MainPanel"
panel.Size = UI_CONFIG.PANEL_SIZE
panel.Position = UDim2.new(1, -270, 1, -320)
panel.BackgroundColor3 = UI_CONFIG.COLOR_PRIMARY
panel.Visible = false
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 10)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
listLayout.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 15)
padding.PaddingBottom = UDim.new(0, 15)
padding.PaddingLeft = UDim.new(0, 15)
padding.PaddingRight = UDim.new(0, 15)
padding.Parent = panel

-- Helper to create buttons
local function createButton(text, callback)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 40)
	btn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	btn.Text = text
	btn.TextColor3 = UI_CONFIG.TEXT_COLOR
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.AutoButtonColor = true
	btn.Parent = panel
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn
	
	btn.MouseButton1Click:Connect(function()
		-- Visual feedback
		local originalColor = btn.BackgroundColor3
		btn.BackgroundColor3 = Color3.fromRGB(100, 100, 110)
		task.delay(0.1, function() btn.BackgroundColor3 = originalColor end)
		
		callback()
	end)
	
	return btn
end

-- Create Buttons
createButton("🔄 Reset Plot", function()
	local success, msg = AdminAction:InvokeServer("ResetPlot")
	print(msg)
end)

createButton("💰 Add $1M", function()
	local success, msg = AdminAction:InvokeServer("AddMoney")
	print(msg)
end)

createButton("🕊️ Toggle Fly", function()
	local success, msg = AdminAction:InvokeServer("ToggleFly")
	print(msg)
end)

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
	
	if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
	if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end
	
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.PlatformStand = false
		end
	end
end

local function startFlying()
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not hrp or not humanoid then return end
	
	-- Create physics movers
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
		
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			moveDir += camCFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			moveDir -= camCFrame.LookVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			moveDir -= camCFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			moveDir += camCFrame.RightVector
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			moveDir += Vector3.new(0, 1, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			moveDir -= Vector3.new(0, 1, 0)
		end
		
		if moveDir.Magnitude > 0 then
			moveDir = moveDir.Unit
		end
		
		bodyVelocity.Velocity = moveDir * FLIGHT_SPEED
		bodyGyro.CFrame = camCFrame
	end)
end

-- Listen for attribute change
player:GetAttributeChangedSignal("IsFlying"):Connect(function()
	if player:GetAttribute("IsFlying") then
		startFlying()
	else
		stopFlying()
	end
end)

-- Handle respawn
player.CharacterAdded:Connect(function()
	if player:GetAttribute("IsFlying") then
		task.wait(0.5)
		startFlying()
	end
end)

print("✓ AdminPanel loaded")
