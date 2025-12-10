--[[
	TransportUI Client Script
	
	Handles transport/vehicle selection and storage transfer.
	Press T to toggle.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Modules
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- Remotes
local RE = ReplicatedStorage:WaitForChild("RemoteEvents")
local RF = ReplicatedStorage:WaitForChild("RemoteFunctions")

local StorageUpdatedEvent = RE:WaitForChild("StorageUpdated")
local BackpackUpdatedEvent = RE:WaitForChild("BackpackUpdated")
local VehicleUpdatedEvent = RE:WaitForChild("VehicleUpdated")

local GetStorage = RF:WaitForChild("GetStorage")
local GetBackpack = RF:WaitForChild("GetBackpack")
local LoadFromStorage = RF:WaitForChild("LoadFromStorage")
local LoadMaxFromStorage = RF:WaitForChild("LoadMaxFromStorage")

-- Config
local COLORS = {
	BG = Color3.fromRGB(15, 15, 25),
	PANEL = Color3.fromRGB(25, 25, 40),
	ACCENT = Color3.fromRGB(100, 200, 255),
	TEXT = Color3.fromRGB(255, 255, 255),
	SUCCESS = Color3.fromRGB(100, 255, 150),
	DANGER = Color3.fromRGB(255, 100, 100),
	ITEM_BG = Color3.fromRGB(35, 35, 55),
}

-- State
local Player = Players.LocalPlayer
local UI, MainFrame
local IsOpen = false
local Data = { Storage={}, StorageCap=2000, Backpack={}, BackpackCap=100 }

-- Helper: Get Total
local function getTotal(items)
	local t = 0
	for _, c in pairs(items) do t += c end
	return t
end

-- UI Creation
local function createUI()
	UI = Instance.new("ScreenGui", Player.PlayerGui) UI.Name = "TransportUI" UI.ResetOnSpawn = false
	
	MainFrame = Instance.new("Frame", UI) MainFrame.Name = "Main"
	MainFrame.Size = UDim2.new(0, 700, 0, 500) MainFrame.Position = UDim2.new(0.5, -350, 0.5, -250)
	MainFrame.BackgroundColor3 = COLORS.BG MainFrame.BackgroundTransparency = 0.1 MainFrame.Visible = false
	Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 16)
	
	-- Header
	local head = Instance.new("Frame", MainFrame) head.Size = UDim2.new(1,0,0,50) head.BackgroundColor3 = COLORS.PANEL
	Instance.new("UICorner", head).CornerRadius = UDim.new(0, 16)
	local title = Instance.new("TextLabel", head) title.Text = "📦 TRANSPORT" title.TextColor3 = COLORS.TEXT
	title.Size = UDim2.fromScale(1,1) title.BackgroundTransparency = 1 title.Font = Enum.Font.GothamBold title.TextSize = 22
	local close = Instance.new("TextButton", head) close.Text = "✕" close.Size = UDim2.new(0,40,0,40)
	close.Position = UDim2.new(1,-45,0,5) close.BackgroundColor3 = COLORS.DANGER close.TextColor3 = COLORS.TEXT
	Instance.new("UICorner", close).CornerRadius = UDim.new(0,8)
	close.MouseButton1Click:Connect(function() toggle(false) end)
	
	-- Panels
	local function panel(name, pos, col)
		local p = Instance.new("Frame", MainFrame) p.Name = name
		p.Size = UDim2.new(0.5, -15, 1, -120) p.Position = pos
		p.BackgroundColor3 = COLORS.PANEL p.BackgroundTransparency = 0.5
		Instance.new("UICorner", p).CornerRadius = UDim.new(0, 12)

		local t = Instance.new("TextLabel", p) t.Text = name == "Storage" and "🏭 STORAGE" or "🎒 BACKPACK"
		t.Size = UDim2.new(1,-20,0,30) t.Position = UDim2.new(0,10,0,10) t.TextColor3 = col
		t.BackgroundTransparency = 1 t.Font = Enum.Font.GothamBold t.TextXAlignment = Enum.TextXAlignment.Left

		local bar = Instance.new("Frame", p) bar.Name = "Bar" bar.Size = UDim2.new(1,-20,0,20)
		bar.Position = UDim2.new(0,10,0,45) bar.BackgroundColor3 = COLORS.ITEM_BG
		local fill = Instance.new("Frame", bar) fill.Name = "Fill" fill.Size = UDim2.fromScale(0,1) fill.BackgroundColor3 = col
		local txt = Instance.new("TextLabel", bar) txt.Name = "Text" txt.Size = UDim2.fromScale(1,1)
		txt.BackgroundTransparency = 1 txt.TextColor3 = COLORS.TEXT txt.Font = Enum.Font.GothamBold
		
		local sf = Instance.new("ScrollingFrame", p) sf.Name = "List"
		sf.Size = UDim2.new(1,-20,1,-80) sf.Position = UDim2.new(0,10,0,75)
		sf.BackgroundTransparency = 1 sf.BorderSizePixel = 0 sf.ScrollBarThickness = 4
		Instance.new("UIListLayout", sf).Padding = UDim.new(0, 5)
		
		return p
	end
	
	panel("Storage", UDim2.new(0,10,0,60), COLORS.ACCENT)
	panel("Backpack", UDim2.new(0.5,5,0,60), COLORS.SUCCESS)
	
	-- Bottom
	local bot = Instance.new("Frame", MainFrame) bot.Size = UDim2.new(1,-20,0,50)
	bot.Position = UDim2.new(0,10,1,-55) bot.BackgroundColor3 = COLORS.PANEL
	Instance.new("UICorner", bot).CornerRadius = UDim.new(0,12)
	
	local load = Instance.new("TextButton", bot) load.Text = "LOAD MAX"
	load.Size = UDim2.new(0,200,0,40) load.Position = UDim2.fromScale(0.5,0.5) load.AnchorPoint = Vector2.new(0.5,0.5)
	load.BackgroundColor3 = COLORS.ACCENT load.TextColor3 = COLORS.TEXT load.Font = Enum.Font.GothamBold
	Instance.new("UICorner", load).CornerRadius = UDim.new(0,8)
	load.MouseButton1Click:Connect(function() LoadMaxFromStorage:InvokeServer() end)
end

-- Refresh
local function refreshPanel(name, items, cap)
	local p = MainFrame:FindFirstChild(name)
	if not p then return end
	
	local usage = getTotal(items)
	local ratio = math.clamp(usage/math.max(1,cap), 0, 1)
	p.Bar.Fill:TweenSize(UDim2.fromScale(ratio, 1), "Out", "Quad", 0.3, true)
	p.Bar.Text.Text = usage .. " / " .. cap
	
	local list = p.List
	for _, c in list:GetChildren() do if c:IsA("Frame") then c:Destroy() end end
	
	for id, count in pairs(items) do
		if count > 0 then
			local row = Instance.new("Frame", list) row.Size = UDim2.new(1,0,0,40)
			row.BackgroundColor3 = COLORS.ITEM_BG row.BackgroundTransparency = 0.3
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
			
			local n = Instance.new("TextLabel", row) n.Text = id n.TextColor3 = COLORS.TEXT
			n.Size = UDim2.new(0.5,-10,1,0) n.Position = UDim2.new(0,10,0,0) n.BackgroundTransparency = 1
			n.TextXAlignment = Enum.TextXAlignment.Left n.Font = Enum.Font.Gotham

			local c = Instance.new("TextLabel", row) c.Text = "x"..count c.TextColor3 = COLORS.TEXT
			c.Size = UDim2.new(0,60,1,0) c.Position = UDim2.fromScale(0.5,0) c.BackgroundTransparency = 1
			c.Font = Enum.Font.GothamBold

			if name == "Storage" then
				local btn = Instance.new("TextButton", row) btn.Text = "LOAD"
				btn.Size = UDim2.new(0,60,0,28) btn.Position = UDim2.new(1,-70,0.5,-14)
				btn.BackgroundColor3 = COLORS.ACCENT btn.TextColor3 = COLORS.TEXT
				Instance.new("UICorner", btn).CornerRadius = UDim.new(0,6)
				btn.MouseButton1Click:Connect(function() LoadFromStorage:InvokeServer(id, 10) end)
			end
		end
	end
	list.CanvasSize = UDim2.new(0,0,0,list.UIListLayout.AbsoluteContentSize.Y)
end

function toggle(force)
	if force ~= nil then IsOpen = force else IsOpen = not IsOpen end
	if IsOpen then
		local s, st, sc = GetStorage:InvokeServer()
		local b, bt, bc = GetBackpack:InvokeServer()
		Data = {Storage=s, StorageCap=sc, Backpack=b, BackpackCap=bc}
		refreshPanel("Storage", Data.Storage, Data.StorageCap)
		refreshPanel("Backpack", Data.Backpack, Data.BackpackCap)
		MainFrame.Visible = true
	else
		MainFrame.Visible = false
	end
end

-- Events
StorageUpdatedEvent.OnClientEvent:Connect(function(items, tot, cap)
	Data.Storage = items Data.StorageCap = cap
	if IsOpen then refreshPanel("Storage", items, cap) end
end)

BackpackUpdatedEvent.OnClientEvent:Connect(function(items, tot, cap)
	Data.Backpack = items Data.BackpackCap = cap
	if IsOpen then refreshPanel("Backpack", items, cap) end
end)

VehicleUpdatedEvent.OnClientEvent:Connect(function(vid, cap)
	Data.BackpackCap = cap
	if IsOpen then refreshPanel("Backpack", Data.Backpack, cap) end
end)

UserInputService.InputBegan:Connect(function(io, gp)
	if not gp and io.KeyCode == Enum.KeyCode.T then toggle() end
end)

createUI()
print("✓ TransportUI Loaded")
