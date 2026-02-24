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
local Shared = ReplicatedStorage:WaitForChild("Shared")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

-- Create specific remotes for Cart system
local CartUpdateEvent = RemoteEvents:FindFirstChild("CartUpdate") or Instance.new("RemoteEvent")
CartUpdateEvent.Name = "CartUpdate"
CartUpdateEvent.Parent = RemoteEvents

local PushCartRemote = RemoteEvents:FindFirstChild("PushCart") or Instance.new("RemoteEvent")
PushCartRemote.Name = "PushCart"
PushCartRemote.Parent = RemoteEvents

local ReturnCartRemote = RemoteEvents:FindFirstChild("ReturnCart") or Instance.new("RemoteEvent")
ReturnCartRemote.Name = "ReturnCart"
ReturnCartRemote.Parent = RemoteEvents

local GetCartInfoFunction = RemoteFunctions:FindFirstChild("GetCartInfo") or Instance.new("RemoteFunction")
GetCartInfoFunction.Name = "GetCartInfo"
GetCartInfoFunction.Parent = RemoteFunctions

local UnloadCartRemote = RemoteFunctions:FindFirstChild("UnloadCart") or Instance.new("RemoteFunction")
UnloadCartRemote.Name = "UnloadCart"
UnloadCartRemote.Parent = RemoteFunctions

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
local function getCartTemplate(tier)
	local tierName = "CartTier" .. (tier or 1)
	local models = ReplicatedStorage:FindFirstChild("Models")
	local carts = models and models:FindFirstChild("Carts")
	local t = carts and carts:FindFirstChild(tierName)

	if not t then
		-- Fallback to Tier 1 if specific tier not found
		t = carts and carts:FindFirstChild("CartTier1")
	end
	
	if not t then
		t = ServerStorage:FindFirstChild("TransportCart")

	end
	return t
end

local function updateCartVisuals(cartData)
	local model = cartData.Model
	if not model then return end
	
	-- Update capacity bar
	local box = model:FindFirstChild("CartBox") or model:FindFirstChild("Box")
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
	local promptPart = model.PrimaryPart
	if not promptPart then return end
	
	local prompt = promptPart:FindFirstChild("CartPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CartPrompt"
		prompt.ObjectText = "Transport Cart"
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0.5
		game:GetService("CollectionService"):AddTag(prompt, "TransportCartPrompt")
		prompt.Parent = promptPart
	end
	
	prompt.Enabled = (cartData.State == "idle" or cartData.State == "at_market")
	
	if cartData.State == "idle" or cartData.State == "at_market" then
		prompt.ActionText = "Manage Cart"
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
	
	-- Get Data
	local DataService = rawget(Services, "DataService")
	local upgrades = { Capacity = CONFIG.DEFAULT_CAPACITY, Model = 1 }
	if DataService then
		upgrades = DataService.GetCartUpgrades(player)
	end
	
	local template = getCartTemplate(upgrades.Model)
	local model = template:Clone()
	model.Name = "Cart_" .. player.Name
	
	-- Waypoints computation:
	-- WP1: Plot edge (Start of bridge)
	-- WP2: Hub edge (End of bridge, meeting Main Island)
	-- WP3: Market/Hole position (Center of Main Island)
	local plotPos = plot:GetPivot().Position
	local dir2D = Vector3.new(plotPos.X, 0, plotPos.Z).Unit
	
	-- From PlotManager: hubEdge = Vector3.new(dir2D.X * 100, 30, dir2D.Z * 100)
	local hubEdgePos = Vector3.new(dir2D.X * 100, MS.CONFIG.MAIN_ISLAND_HEIGHT or 30, dir2D.Z * 100)
	
	-- From PlotManager: plotEdge = Vector3.new(plotPos.X - dir2D.X * 60, plotPos.Y, plotPos.Z - dir2D.Z * 60)
	local plotEdgePos = Vector3.new(plotPos.X - dir2D.X * 60, plotPos.Y, plotPos.Z - dir2D.Z * 60)
	
	-- Add more to Y so the drone/cart doesn't clip into the bridge/ground, starting higher
	local yOffset = Vector3.new(0, 20, 0)
	
	local wp1 = plotEdgePos + yOffset
	local wp2 = hubEdgePos + yOffset
	local wp3 = Vector3.new(0, hubEdgePos.Y + 10, 0) -- Hole is at center, so X=0, Z=0
	
	local dir = (wp3 - wp1).Unit -- General direction for facing at spawn
	
	model:PivotTo(CFrame.new(wp1, wp1 + dir))
	model.Parent = workspace
	
	local Config = require(ReplicatedStorage.Shared.CartShopConfig)
	local capOverride = Config.GetValue("Capacity", upgrades.Capacity or 0)
	
	local data = {
		Model = model,
		State = "idle",
		Inventory = {},
		Capacity = capOverride > 0 and capOverride or CONFIG.DEFAULT_CAPACITY,
		Speed = CONFIG.ROLL_SPEED,
		ModelTier = upgrades.Model or 1,
		Waypoints = { wp1, wp2, wp3 },
		BridgeDir = dir
	}
	
	-- Tag for client-side HUD and visuals
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("CartState", "idle")
	model:SetAttribute("CartWP1", data.Waypoints[1])
	model:SetAttribute("CartWP2", data.Waypoints[2])
	model:SetAttribute("CartWP3", data.Waypoints[3])
	model:SetAttribute("CartDuration", 0)
	model:SetAttribute("CartStartTime", 0)
	
	game:GetService("CollectionService"):AddTag(model, "PhysicalCartHUD")
	
	PlayerCarts[player] = data
	updateCartVisuals(data)
	
	return data
end

local function moveCart(player, targetState)
	print("CartManager: moveCart called for", player.Name, "to", targetState)
	local data = PlayerCarts[player]
	if not data then 
		print("CartManager: No cart data found")
		return 
	end
	
	local dist = 0
	if data.Waypoints then
		dist = (data.Waypoints[1] - data.Waypoints[2]).Magnitude + (data.Waypoints[2] - data.Waypoints[3]).Magnitude
	end
	
	data.State = targetState
	updateCartVisuals(data)
	CartUpdateEvent:FireClient(player, data.State, data.Inventory, data.Capacity)
	
	-- Calculate time (distance already computed above or defaults)
	local speed = data.Speed or CONFIG.ROLL_SPEED
	local travelTime = dist / speed
	print("CartManager: Starting transport, time:", travelTime, "dist:", dist)
	
	-- Let client handle tweening using attributes
	data.Model:SetAttribute("CartDuration", travelTime)
	data.Model:SetAttribute("CartStartTime", workspace:GetServerTimeNow())
	data.Model:SetAttribute("CartState", targetState)
	
	-- Schedule arrival
	task.delay(travelTime, function()
		print("CartManager: Transport completed")
		if targetState == "rolling_to_market" then
			-- Cart arrived at market — stay here for manual trading
			data.State = "at_market"
			data.Model:SetAttribute("CartState", "at_market")
			updateCartVisuals(data)
			CartUpdateEvent:FireClient(player, "at_market", data.Inventory, data.Capacity)
			print("CartManager: Cart at market — awaiting player trades")
		else
			data.State = "idle"
			data.Model:SetAttribute("CartState", "idle")
			updateCartVisuals(data)
			CartUpdateEvent:FireClient(player, data.State, data.Inventory, data.Capacity)
		end
	end)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function CartManager.ApplyUpgrades(player, upgrades)
	local data = PlayerCarts[player]
	
	-- Logic:
	-- If model changed, we MUST respawn.
	-- If data doesn't exist, we just let spawnCart handle it later.
	
	if data and data.ModelTier ~= (upgrades.Model or 1) then
		-- Model Upgrade!
		-- If cart is moving, we might want to wait or just force it (it's weird to swap model while moving)
		-- For simpler UX, we'll force respawn at start position and preserve inventory if possible?
		-- Actually, just destroy and spawn new one at idle pos.
		
		if data.Model then data.Model:Destroy() end
		PlayerCarts[player] = nil
		
		-- Use spawnCart which re-reads DataService
		-- But spawnCart checks PlayerCarts presence.
		-- We nilled it, so it should work.
		spawnCart(player)
		
		-- Restore inventory? 
		-- spawnCart resets inventory. 
		-- If they upgrade while cart is full, they might lose items or we need to carefully port them.
		-- For now, let's assume they shouldn't upgrade mid-trip or accept it resets.
		-- Better: copy inventory over.
		
		local newData = PlayerCarts[player]
		if newData then
			newData.Inventory = data.Inventory
			updateCartVisuals(newData)
			CartUpdateEvent:FireClient(player, newData.State, newData.Inventory, newData.Capacity)
		end
		
		return
	end
	
	if not data then 
		-- Try spawning if they have a plot
		spawnCart(player)
		return 
	end

	local Config = require(Shared:WaitForChild("CartShopConfig"))
	
	-- Capacity
	local capVal = Config.GetValue("Capacity", upgrades.Capacity or 0)
	if capVal > 0 then
		data.Capacity = capVal
	end
	
	-- Speed is now fixed
	data.Speed = CONFIG.ROLL_SPEED
	
	updateCartVisuals(data)
	CartUpdateEvent:FireClient(player, data.State, data.Inventory, data.Capacity)
end

function CartManager.Init(services)
	Services = services
	print("   CartManager (Module) - Initializing")
	
	-- Use PlayerLifecycleManager for ready event
	local PLM = Services.PlayerLifecycleManager
	if PLM and PLM.PlayerReady then
		PLM.PlayerReady:Connect(function(player)
			spawnCart(player)
		end)
	else
		Players.PlayerAdded:Connect(function(player)
			task.wait(2)
			spawnCart(player)
		end)
	end
	
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
	
	-- GetCartInfo remote — lets client query cart state/inventory
	GetCartInfoFunction.OnServerInvoke = function(player)
		local data = PlayerCarts[player]
		if not data then
			return { state = "none", inventory = {}, capacity = 0, spaceRemaining = 0 }
		end
		local current = 0
		for _, c in pairs(data.Inventory) do current += c end
		return {
			state = data.State,
			inventory = data.Inventory,
			capacity = data.Capacity,
			spaceRemaining = data.Capacity - current,
		}
	end
	
	-- UnloadCart remote — unloads items from cart to storage when idle at plot
	UnloadCartRemote.OnServerInvoke = function(player)
		return CartManager.UnloadAll(player)
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

function CartManager.UpdateCapacity(player, capacity)
	local data = PlayerCarts[player]
	if not data then return end
	data.Capacity = capacity
	updateCartVisuals(data)
	CartUpdateEvent:FireClient(player, data.State, data.Inventory, data.Capacity)
end

--[[
	RemoveFromCartInventory: Removes items from cart inventory (for selling).
	Only works when cart is at_market.
	@return number of items actually removed
]]
function CartManager.RemoveFromCartInventory(player, itemId, count)
	local data = PlayerCarts[player]
	if not data then return 0 end
	if data.State ~= "at_market" then return 0 end
	
	local inCart = data.Inventory[itemId] or 0
	local toRemove = math.min(count, inCart)
	if toRemove <= 0 then return 0 end
	
	data.Inventory[itemId] = inCart - toRemove
	if data.Inventory[itemId] <= 0 then data.Inventory[itemId] = nil end
	
	updateCartVisuals(data)
	CartUpdateEvent:FireClient(player, data.State, data.Inventory, data.Capacity)
	return toRemove
end

--[[
	LoadItemAtMarket: Adds items to cart inventory (for buying at market).
	Only works when cart is at_market.
	@return number of items actually loaded
]]
function CartManager.LoadItemAtMarket(player, itemId, count)
	local data = PlayerCarts[player]
	if not data then return 0 end
	if data.State ~= "at_market" then return 0 end
	
	local current = 0
	for _, c in pairs(data.Inventory) do current += c end
	local space = data.Capacity - current
	local toLoad = math.min(count, space)
	if toLoad <= 0 then return 0 end
	
	data.Inventory[itemId] = (data.Inventory[itemId] or 0) + toLoad
	updateCartVisuals(data)
	CartUpdateEvent:FireClient(player, data.State, data.Inventory, data.Capacity)
	return toLoad
end

--[[
	UnloadAll: Moves all items from cart to storage.
	Only works when cart is idle (at plot).
	@return {[itemId] = count} of items unloaded
]]
function CartManager.UnloadAll(player)
	local data = PlayerCarts[player]
	if not data then return {} end
	if data.State ~= "idle" then return {} end
	
	local ISM = rawget(Services, "ItemStorageManager")
	if not ISM then return {} end
	
	local unloaded = {}
	for itemId, count in pairs(data.Inventory) do
		if count > 0 then
			local added = ISM.AddToStorage(player, itemId, count)
			if added > 0 then
				unloaded[itemId] = added
				data.Inventory[itemId] = (data.Inventory[itemId] or 0) - added
				if data.Inventory[itemId] <= 0 then data.Inventory[itemId] = nil end
			end
		end
	end
	
	updateCartVisuals(data)
	CartUpdateEvent:FireClient(player, data.State, data.Inventory, data.Capacity)
	print("CartManager: Unloaded items for", player.Name)
	return unloaded
end

function CartManager.GetCartSpaceRemaining(player)
	local data = PlayerCarts[player]
	if not data then return 0 end
	local current = 0
	for _, c in pairs(data.Inventory) do current += c end
	return data.Capacity - current
end

return CartManager
