--[[
	ShopUI Client Script
	
	Features:
	- Scrolling shop panel with progressive unlocking
	- Live price/milestone updates
	- Ownership count display
	- Purchase handling
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Modules
local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopConfig"))

-- Remotes
local RE = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyUnitRemote = RE:WaitForChild("BuyUnit")
local GetOwnershipRemote = RE:WaitForChild("GetOwnership")
local OwnershipChangedEvent = RE:WaitForChild("OwnershipChanged")
local UnlockProgressChangedEvent = RE:WaitForChild("UnlockProgressChanged")

-- Constants
local UI_CONFIG = {
	SHOP_WIDTH = 280,
	BUTTON_HEIGHT = 110,
	OPEN_POS = UDim2.new(1, -290, 0, 10),
	CLOSED_POS = UDim2.new(1, 10, 0, 10),
	COLORS = {
		BG = Color3.fromRGB(35, 35, 50),
		BTN = Color3.fromRGB(50, 50, 70),
		HOVER = Color3.fromRGB(65, 65, 90),
		DISABLED = Color3.fromRGB(40, 40, 50),
		ACCENT = Color3.fromRGB(100, 220, 100),
		LOCKED = Color3.fromRGB(20, 20, 25),
		TEXT = Color3.fromRGB(255, 255, 255),
		PRICE = Color3.fromRGB(255, 215, 0),
	}
}

-- State
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ShopGui, ScrollFrame
local OwnedCounts = {}
local ShopButtons = {}
local UnlockProgress = ShopConfig.INITIAL_UNLOCKED
local ShopVisible = false

-- Helper: Format Money
local function fmt(v)
	local s = {"K","M","B","T","Qa","Qi","Sx","Sp","Oc","No","Dc"}
	if v < 1000 then return "$" .. math.floor(v) end
	local i = math.min(math.floor(math.log(v, 1000)), #s)
	return string.format("$%.1f%s", v / 1000^i, s[i])
end

-- UI Creation
local function createUI()
	local sg = Instance.new("ScreenGui", PlayerGui) sg.Name = "ShopUI" sg.ResetOnSpawn = false
	
	local panel = Instance.new("Frame", sg) panel.Name = "ShopPanel"
	panel.Size = UDim2.new(0, UI_CONFIG.SHOP_WIDTH, 1, -20)
	panel.Position = UI_CONFIG.CLOSED_POS
	panel.BackgroundColor3 = UI_CONFIG.COLORS.BG
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
	
	local title = Instance.new("TextLabel", panel) title.Text = "🧠 BRAINROT SHOP"
	title.Size = UDim2.new(1, -40, 0, 50) title.BackgroundTransparency = 1
	title.TextColor3 = UI_CONFIG.COLORS.TEXT title.Font = Enum.Font.GothamBold title.TextSize = 20
	
	local close = Instance.new("TextButton", panel) close.Text = "✕"
	close.Size = UDim2.new(0, 30, 0, 30) close.Position = UDim2.new(1, -40, 0, 10)
	close.BackgroundColor3 = Color3.fromRGB(200, 60, 60) Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)
	close.MouseButton1Click:Connect(function() toggleShop(false) end)
	
	local sf = Instance.new("ScrollingFrame", panel) sf.Name = "ItemList"
	sf.Size = UDim2.new(1, -20, 1, -60) sf.Position = UDim2.new(0, 10, 0, 55)
	sf.BackgroundTransparency = 1 sf.BorderSizePixel = 0 sf.ScrollBarThickness = 6
	
	local lay = Instance.new("UIListLayout", sf) lay.Padding = UDim.new(0, 8) lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() sf.CanvasSize = UDim2.new(0,0,0,lay.AbsoluteContentSize.Y+10) end)
	
	ShopGui, ScrollFrame = sg, sf
end

-- Button Logic
local function updateButton(name)
	local btn = ShopButtons[name]
	if not btn then return end
	
	local count = OwnedCounts[name] or 0
	local cfg = ShopConfig.GetConfig(name)
	local price = ShopConfig.CalculatePrice(name, count)
	
	btn.Price.Text = fmt(price)
	-- btn.Badge is a Frame, its child "Text" is the label
	if btn:FindFirstChild("Badge") and btn.Badge:FindFirstChild("Text") then
		btn.Badge.Text.Text = tostring(count)
	end
	
	-- Income
	local inc = ShopConfig.CalculateEffectiveIncome(name, count)
	local cyc = ShopConfig.CalculateEffectiveCycleTime(name, count)
	btn.Income.Text = string.format("+$%d / %.1fs", inc, cyc)
	
	-- Milestone
	local nextMs, prog = ShopConfig.GetNextMilestone(count)
	if nextMs then
		local typeStr = nextMs.milestoneType == "speed" and "x2 Spd" or "x"..nextMs.multiplier.." $$"
		btn.Milestone.Text = string.format("%d/%d (%s)", prog, nextMs.quantity, typeStr)
		btn.Milestone.TextColor3 = Color3.fromRGB(150, 200, 255)
	else
		btn.Milestone.Text = "MAXED"
		btn.Milestone.TextColor3 = UI_CONFIG.COLORS.ACCENT
	end
	
	-- Affordability
	local money = Player:FindFirstChild("leaderstats") and Player.leaderstats:FindFirstChild("Money")
	local canAfford = money and money.Value >= price
	btn.BackgroundColor3 = canAfford and UI_CONFIG.COLORS.BTN or UI_CONFIG.COLORS.DISABLED
end

local function createButton(name, cfg, order, locked)
	local btn = Instance.new("Frame")
	btn.Size = UDim2.new(1, 0, 0, UI_CONFIG.BUTTON_HEIGHT)
	btn.BackgroundColor3 = locked and UI_CONFIG.COLORS.LOCKED or UI_CONFIG.COLORS.BTN
	btn.LayoutOrder = order
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	
	-- Elements
	local function txt(n, p, s, t, c)
		local l = Instance.new("TextLabel", btn) l.Name = n l.Position = p l.Size = s
		l.BackgroundTransparency = 1 l.Text = t l.TextColor3 = c or UI_CONFIG.COLORS.TEXT
		l.Font = Enum.Font.GothamBold l.TextSize = 14 l.TextXAlignment = Enum.TextXAlignment.Left
		return l
	end

	if locked then
		txt("Name", UDim2.new(0,10,0,10), UDim2.new(1,-20,1,-20), "???", UI_CONFIG.COLORS.DISABLED).TextSize = 24
	else
		txt("Name", UDim2.new(0,10,0,5), UDim2.new(1,-60,0,20), name).TextTruncate = Enum.TextTruncate.AtEnd
		local inc = txt("Income", UDim2.new(0,10,0,25), UDim2.new(1,-20,0,15), "", UI_CONFIG.COLORS.DISABLED) inc.Font = Enum.Font.Gotham inc.TextSize = 11
		local ms = txt("Milestone", UDim2.new(0,10,0,40), UDim2.new(1,-20,0,15), "") ms.Font = Enum.Font.Gotham ms.TextSize = 11
		
		local pr = txt("Price", UDim2.new(0,10,1,-30), UDim2.new(1,-20,0,25), "", UI_CONFIG.COLORS.PRICE) pr.TextSize = 18
		
		local bg = Instance.new("Frame", btn) bg.Name = "Badge" bg.Position = UDim2.new(1,-40,0,5) bg.Size = UDim2.new(0,35,0,20)
		bg.BackgroundColor3 = UI_CONFIG.COLORS.ACCENT Instance.new("UICorner", bg).CornerRadius = UDim.new(0,4)
		local bgt = txt("Text", UDim2.fromScale(0,0), UDim2.fromScale(1,1), "0", Color3.new(0,0,0)) bgt.Parent = bg bgt.TextXAlignment = Enum.TextXAlignment.Center
		
		local click = Instance.new("TextButton", btn) click.Size = UDim2.fromScale(1,1) click.BackgroundTransparency = 1 click.Text = ""
		click.MouseButton1Click:Connect(function()
			BuyUnitRemote:InvokeServer(name)
			-- Optimistic update handled by event
		end)
		
		ShopButtons[name] = btn
	end
	
	return btn
end

local function refresh()
	if not ScrollFrame then return end
	for _, c in ScrollFrame:GetChildren() do if c:IsA("Frame") then c:Destroy() end end
	ShopButtons = {}
	
	local units = ShopConfig.GetVisibleUnits(UnlockProgress)
	for i, u in units do
		local btn = createButton(u.name, u.config, i, u.isLocked)
		btn.Parent = ScrollFrame
		if not u.isLocked then updateButton(u.name) end
	end
end

-- Global Toggle
function toggleShop(force)
	if force ~= nil then ShopVisible = force else ShopVisible = not ShopVisible end
	if not ShopGui then return end
	
	local panel = ShopGui.ShopPanel
	local target = ShopVisible and UI_CONFIG.OPEN_POS or UI_CONFIG.CLOSED_POS
	TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = target}):Play()
end

-- Init
createUI()

task.spawn(function()
	local data = GetOwnershipRemote:InvokeServer()
	if data then
		UnlockProgress = data.unlockProgress
		for u, d in pairs(data.units) do OwnedCounts[u] = d.count end
		refresh()
	end
end)

-- Events
OwnershipChangedEvent.OnClientEvent:Connect(function(name, count, price)
	OwnedCounts[name] = count
	updateButton(name)
	-- Update others for affordability
	for n, _ in pairs(ShopButtons) do updateButton(n) end
end)

UnlockProgressChangedEvent.OnClientEvent:Connect(function(prog)
	UnlockProgress = prog
	refresh()
end)

if Player:FindFirstChild("leaderstats") and Player.leaderstats:FindFirstChild("Money") then
	Player.leaderstats.Money:GetPropertyChangedSignal("Value"):Connect(function()
		for n, _ in pairs(ShopButtons) do updateButton(n) end
	end)
end

-- Inputs
UserInputService.InputBegan:Connect(function(io, gp)
	if not gp and io.KeyCode == Enum.KeyCode.B then toggleShop() end
end)

-- Bindable for other UIs
local be = ReplicatedStorage:FindFirstChild("ShopToggleEvent") or Instance.new("BindableEvent", ReplicatedStorage)
be.Name = "ShopToggleEvent"
be.Event:Connect(toggleShop)

print("✓ ShopUI Loaded")
