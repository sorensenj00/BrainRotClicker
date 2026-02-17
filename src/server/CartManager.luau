--[[
	CartManager Server Module
	
	Handles the physical transport cart system.
	- Spawns/Despawns carts for players
	- Manages cart inventory (distinct from backpack)
	- Handles rolling movement (Plot <-> Market)
	- Integrates with MarketManager for selling
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")

-- Create specific remotes for Cart system
-- (Using existing Transport hooks where possible, but adding specific events for cart state)
local CartUpdateEvent = RemoteEvents:FindFirstChild("CartUpdate") or Instance.new("RemoteEvent")
CartUpdateEvent.Name = "CartUpdate"
CartUpdateEvent.Parent = RemoteEvents

local PushCartRemote = RemoteEvents:FindFirstChild("PushCart") or Instance.new("RemoteEvent")
PushCartRemote.Name = "PushCart"
PushCartRemote.Parent = RemoteEvents

local ReturnCartRemote = RemoteEvents:FindFirstChild("ReturnCart") or Instance.new("RemoteEvent")
ReturnCartRemote.Name = "ReturnCart"
ReturnCartRemote.Parent = RemoteEvents

local CartManager = {}
local Services = {}

-- State
local PlayerCarts = {} -- [Player] = { Model, State, Inventory, Capacity }
-- States: "idle" (at plot), "rolling_to_market", "at_market", "rolling_to_plot"

local CONFIG = {
	ROLL_SPEED = 40, -- Studs per second
	DEFAULT_CAPACITY = 200,
}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getMapSystem()
	return rawget(Services, "MapSystem")
end

local function getMarketManager()
	return rawget(Services, "MarketManager")
end

local function createPlaceholderCart()
	local m = Instance.new("Model")
	m.Name = "TransportCart"
	
	-- Base (Anchored, PrimaryPart)
	local base = Instance.new("Part")
	base.Name = "PrimaryPart"
	base.Size = Vector3.new(6, 2, 8)
	base.BrickColor = BrickColor.new("Brown")
	base.Material = Enum.Material.Wood
	base.TopSurface = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.Anchored = true -- Driven by TweenService
	base.CanCollide = false -- Prevent sticking in geometry
	base.Parent = m
	m.PrimaryPart = base
	
	-- Wheels (Unanchored, Welded)
	local function addWheel(name, x, z)
		local w = Instance.new("Part")
		w.Name = name
		w.Size = Vector3.new(1, 2, 2)
		w.BrickColor = BrickColor.new("Really black")
		w.Material = Enum.Material.Metal
		w.Shape = Enum.PartType.Cylinder
		w.CFrame = base.CFrame * CFrame.new(x, -1, z) * CFrame.Angles(0, 0, math.pi/2)
		w.Anchored = false
		w.CanCollide = false
		w.Parent = m
		
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = base
		weld.Part1 = w
		weld.Parent = base
	end
	addWheel("Wheel_FR", 3.5, 3)
	addWheel("Wheel_BR", 3.5, -3)
	addWheel("Wheel_FL", -3.5, 3)
	addWheel("Wheel_BL", -3.5, -3)
	
	-- Box (Unanchored, Welded)
	local box = Instance.new("Part")
	box.Name = "CartBox"
	box.Size = Vector3.new(5, 3, 7)
	box.Position = base.Position + Vector3.new(0, 2.5, 0)
	box.BrickColor = BrickColor.new("Dirt brown")
	box.Material = Enum.Material.WoodPlanks
	box.Anchored = false
	box.CanCollide = false
	box.Transparency = 0
	box.TopSurface = Enum.SurfaceType.Smooth
	box.Parent = m
	
	local boxWeld = Instance.new("WeldConstraint")
	boxWeld.Part0 = base
	boxWeld.Part1 = box
	boxWeld.Parent = base
	
	-- Capacity Bar (SurfaceGui)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(200, 50)
	sg.Parent = box
	
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.Parent = sg
	
	local bar = Instance.new("Frame")
	bar.Name = "FillBar"
	bar.Size = UDim2.new(0, 0, 1, 0)
	bar.BackgroundColor3 = Color3.new(0, 1, 0)
	bar.BorderSizePixel = 0
	bar.Parent = frame
	
	-- Attachment for ProximityPrompt
	local att = Instance.new("Attachment")
	att.Name = "PromptAttachment"
	att.Position = Vector3.new(0, 2, -4)
	att.Parent = base
	
	return m
end

local function getCartTemplate()
	local t = ServerStorage:FindFirstChild("TransportCart")
	if not t then
		t = createPlaceholderCart()
		t.Parent = ServerStorage
	end
	return t
end

local function updateCartVisuals(cartData)
	local model = cartData.Model
	if not model then return end
	
	-- Update capacity bar
	local box = model:FindFirstChild("CartBox")
	if box and box:FindFirstChild("SurfaceGui") then
		local bar = box.SurfaceGui:FindFirstChild("Frame"):FindFirstChild("FillBar")
		local current = 0
		for _, c in pairs(cartData.Inventory) do current += c end
		local ratio = math.min(1, current / math.max(1, cartData.Capacity))
		if bar then
			bar.Size = UDim2.new(ratio, 0, 1, 0)
			bar.BackgroundColor3 = ratio >= 1 and Color3.new(1, 0, 0) or Color3.new(0, 1, 0)
		end
	end
	
	-- Position prompt
	local prompt = model.PrimaryPart:FindFirstChild("CartPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CartPrompt"
		prompt.ObjectText = "Transport Cart"
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0.5
		prompt.Parent = model.PrimaryPart
	end
	
	prompt.Enabled = (cartData.State == "idle" or cartData.State == "at_market")
	
	if cartData.State == "idle" then
		prompt.ActionText = "Push to Market"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
	elseif cartData.State == "at_market" then
		prompt.ActionText = "Return Cart"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
	else
		prompt.Enabled = false
	end
end

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local function spawnCart(player)
	if PlayerCarts[player] then return PlayerCarts[player] end
	
	local MS = getMapSystem()
	local plot = MS.GetPlayerPlot(player)
	if not plot then return nil end
	
	local template = getCartTemplate()
	local model = template:Clone()
	model.Name = "Cart_" .. player.Name
	
	-- Initial Position (Start of bridge)
	local plotPos = plot:GetPivot().Position
	local mainPos = Vector3.new(0, MS.CONFIG.MAIN_ISLAND_HEIGHT + 6, 0)
	local dir = (mainPos - plotPos).Unit
	local spawnPos = plotPos + (dir * 35) -- Edge of plot
	spawnPos = Vector3.new(spawnPos.X, plotPos.Y + 10, spawnPos.Z) -- Higher up to avoid clipping ramp/bridge
	
	model:PivotTo(CFrame.new(spawnPos, spawnPos + dir))
	model.Parent = workspace
	
	local data = {
		Model = model,
		State = "idle",
		Inventory = {},
		Capacity = CONFIG.DEFAULT_CAPACITY,
		StartPos = spawnPos,
		EndPos = mainPos + (dir * -45), -- Edge of main island
		BridgeDir = dir
	}
	
	-- Tag for client-side HUD
	game:GetService("CollectionService"):AddTag(model, "PhysicalCartHUD")
	
	PlayerCarts[player] = data
	updateCartVisuals(data)
	
	-- Connect prompt locally
	local prompt = model.PrimaryPart:WaitForChild("CartPrompt")
	prompt.Triggered:Connect(function(triggerPlayer)
		if triggerPlayer == player then
			CartManager.HandlePrompt(player)
		end
	end)
	
	return data
end

local function moveCart(player, targetState)
	print("CartManager: moveCart called for", player.Name, "to", targetState)
	local data = PlayerCarts[player]
	if not data then 
		print("CartManager: No cart data found")
		return 
	end
	
	local startP, endP
	if targetState == "rolling_to_market" then
		startP = data.StartPos
		endP = data.EndPos
	else
		startP = data.EndPos
		endP = data.StartPos
	end
	
	data.State = targetState
	updateCartVisuals(data)
	CartUpdateEvent:FireClient(player, data.State, data.Inventory, data.Capacity)
	
	-- Calculate time
	local dist = (startP - endP).Magnitude
	local time = dist / CONFIG.ROLL_SPEED
	print("CartManager: Starting tween, time:", time, "dist:", dist)
	
	-- Correct orientation: Facing movement direction
	local lookCF = CFrame.new(startP, endP)
	data.Model:PivotTo(lookCF)
	
	-- Tween
	local tweenInfo = TweenInfo.new(time, Enum.EasingStyle.Linear)
	local tween = TweenService:Create(data.Model.PrimaryPart, tweenInfo, {
		CFrame = CFrame.new(endP, endP + (endP - startP).Unit) -- Maintain look direction approximately
	})
	
	tween:Play()
	tween.Completed:Connect(function()
		print("CartManager: Tween completed")
		if targetState == "rolling_to_market" then
			data.State = "at_market"
			-- Auto Sell
			local MM = getMarketManager()
			if MM and MM.SellCartContents then
				MM.SellCartContents(player, data.Inventory)
				data.Inventory = {} -- Clear after sell
			end
		else
			data.State = "idle"
		end
		updateCartVisuals(data)
		CartUpdateEvent:FireClient(player, data.State, data.Inventory, data.Capacity)
	end)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function CartManager.Init(services)
	Services = services
	print("   CartManager (Module) - Initializing")
	
	Players.PlayerAdded:Connect(function(player)
		task.wait(2) -- Wait for plot
		spawnCart(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		if PlayerCarts[player] then
			if PlayerCarts[player].Model then
				PlayerCarts[player].Model:Destroy()
			end
			PlayerCarts[player] = nil
		end
	end)
	
	PushCartRemote.OnServerEvent:Connect(function(player)
		print("CartManager: PushCart remote received")
		CartManager.HandlePrompt(player)
	end)
	
	ReturnCartRemote.OnServerEvent:Connect(function(player)
		print("CartManager: ReturnCart remote received")
		CartManager.HandlePrompt(player)
	end)
	
	-- Initial players
	for _, p in Players:GetPlayers() do
		task.spawn(function()
			task.wait(2)
			spawnCart(p)
		end)
	end
	
	print("✓ CartManager Initialized")
end

function CartManager.LoadItem(player, itemId, count)
	local data = PlayerCarts[player]
	if not data then return 0 end
	if data.State ~= "idle" then return 0 end
	
	local current = 0
	for _, c in pairs(data.Inventory) do current += c end
	
	local space = data.Capacity - current
	local toLoad = math.min(count, space)
	if toLoad <= 0 then return 0 end
	
	-- Assume items already deducted from source by caller
	data.Inventory[itemId] = (data.Inventory[itemId] or 0) + toLoad
	updateCartVisuals(data)
	CartUpdateEvent:FireClient(player, data.State, data.Inventory, data.Capacity)
	
	return toLoad
end

function CartManager.HandlePrompt(player)
	print("CartManager: HandlePrompt called for", player.Name)
	local data = PlayerCarts[player]
	if not data then 
		print("CartManager: No data found in HandlePrompt")
		return 
	end
	
	print("CartManager: Current State:", data.State)
	if data.State == "idle" then
		-- Pushing to market (allow even if empty for testing)
		moveCart(player, "rolling_to_market")
	elseif data.State == "at_market" then
		moveCart(player, "rolling_to_plot")
	end
end

function CartManager.GetCartState(player)
	return PlayerCarts[player]
end

function CartManager.SetCapacity(player, capacity)
	local data = PlayerCarts[player]
	if not data then return end
	data.Capacity = capacity
	updateCartVisuals(data)
	CartUpdateEvent:FireClient(player, data.State, data.Inventory, data.Capacity)
end

return CartManager
