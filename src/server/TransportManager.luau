--[[
	TransportManager Server Module

	Handles the transport system for carrying items from storage to market.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemConfig -- = require(Shared:WaitForChild("ItemConfig"))

local function getItemConfig()
	if not ItemConfig then
		local SharedRef = ReplicatedStorage:WaitForChild("Shared")
		ItemConfig = require(SharedRef:WaitForChild("ItemConfig"))
	end
	return ItemConfig
end

-- Config
local CONFIG = {
	DEFAULT_VEHICLE = "Sneakers",
	VEHICLES = {
		Sneakers = { capacity = 100, price = 0, description = "Basic transport, small capacity" },
		Cart = { capacity = 500, price = 5000, description = "Wooden cart, medium capacity" },
		Hoverboard = { capacity = 2000, price = 50000, description = "Futuristic hover transport" },
		Truck = { capacity = 10000, price = 500000, description = "Massive hauler, huge capacity" },
	},
}

-- Remotes
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local VehicleUpdated = RemoteEvents:FindFirstChild("VehicleUpdated") or Instance.new("RemoteEvent")
VehicleUpdated.Name = "VehicleUpdated"
VehicleUpdated.Parent = RemoteEvents

local BackpackLoaded = RemoteEvents:FindFirstChild("BackpackLoaded") or Instance.new("RemoteEvent")
BackpackLoaded.Name = "BackpackLoaded"
BackpackLoaded.Parent = RemoteEvents

local SelectVehicleRemote = RemoteFunctions:FindFirstChild("SelectVehicle") or Instance.new("RemoteFunction")
SelectVehicleRemote.Name = "SelectVehicle"
SelectVehicleRemote.Parent = RemoteFunctions

local GetVehicleInfoRemote = RemoteFunctions:FindFirstChild("GetVehicleInfo") or Instance.new("RemoteFunction")
GetVehicleInfoRemote.Name = "GetVehicleInfo"
GetVehicleInfoRemote.Parent = RemoteFunctions

local LoadFromStorageRemote = RemoteFunctions:FindFirstChild("LoadFromStorage") or Instance.new("RemoteFunction")
LoadFromStorageRemote.Name = "LoadFromStorage"
LoadFromStorageRemote.Parent = RemoteFunctions

local LoadMaxFromStorageRemote = RemoteFunctions:FindFirstChild("LoadMaxFromStorage") or Instance.new("RemoteFunction")
LoadMaxFromStorageRemote.Name = "LoadMaxFromStorage"
LoadMaxFromStorageRemote.Parent = RemoteFunctions

-- Module
local TransportManager = {}
local Services = {}

-- State
local PlayerTransport = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getCartManager()
	return rawget(Services, "CartManager")
end

local function getItemStorage()
	return rawget(Services, "ItemStorageManager")
end

local function getCartCapacity(player)
	local t = PlayerTransport[player]
	local vid = t and t.selectedVehicle or CONFIG.DEFAULT_VEHICLE
	local vc = CONFIG.VEHICLES[vid]
	return vc and vc.capacity or 100
end

local function getCartUsage(player)
	local CM = getCartManager()
	if not CM then return 0 end
	local cart = CM.GetCartState(player)
	if not cart then return 0 end

	local total = 0
	for _, c in pairs(cart.Inventory) do total += c end
	return total
end

local function initializePlayer(player)
	PlayerTransport[player] = { selectedVehicle = CONFIG.DEFAULT_VEHICLE }

	-- Sync attribute for UI
	player:SetAttribute("CartCapacity", getCartCapacity(player))

	-- Update Cart Capacity if cart exists
	local CM = getCartManager()
	if CM then
		-- CM might create cart later, so handled in CM or on vehicle select
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function TransportManager.Init(services)
	print("   TransportManager (Module) - Initializing")
	Services = services or {}

	Players.PlayerAdded:Connect(function(player)
		initializePlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		PlayerTransport[player] = nil
	end)

	for _, p in Players:GetPlayers() do initializePlayer(p) end

	SelectVehicleRemote.OnServerInvoke = TransportManager.SelectVehicle
	GetVehicleInfoRemote.OnServerInvoke = TransportManager.GetVehicleInfo
	LoadFromStorageRemote.OnServerInvoke = TransportManager.LoadFromStorage
	LoadMaxFromStorageRemote.OnServerInvoke = TransportManager.LoadMaxFromStorage

	print("✓ TransportManager Initialized")
end

function TransportManager.SelectVehicle(player, vehicleId)
	local t = PlayerTransport[player]
	if not t then return false end

	local conf = CONFIG.VEHICLES[vehicleId]
	if not conf then return false, "Unknown Vehicle" end

	if vehicleId ~= "Sneakers" then
		local DataService = rawget(Services, "DataService")
		if not DataService then return false, "Economy offline" end
		if not DataService.DeductMoney(player, conf.price) then return false, "Not enough cash" end
	end

	t.selectedVehicle = vehicleId
	player:SetAttribute("CartCapacity", conf.capacity)

	-- Update Cart Capacity
	local CM = getCartManager()
	if CM then
		-- Create a Setter in CartManager or just update if exposed?
		-- CM.GetCartState returns reference?
		-- Use encapsulated update method
		if CM.UpdateCapacity then
			CM.UpdateCapacity(player, conf.capacity)
		else
			-- Fallback if not available (should be)
			local cart = CM.GetCartState(player)
			if cart then
				cart.Capacity = conf.capacity
			end
		end
	end

	VehicleUpdated:FireClient(player, vehicleId, conf.capacity)
	return true
end

function TransportManager.LoadFromStorage(player, itemId, count)
	if type(itemId) ~= "string" then return 0 end
	if type(count) ~= "number" then return 0 end
	count = math.floor(count)
	if count <= 0 then return 0 end

	local CM = getCartManager()
	local ISM = getItemStorage()
	if not CM or not ISM then return 0 end

	local cart = CM.GetCartState(player)
	if not cart then return 0 end
	if cart.State ~= "idle" then return 0 end
	if not cart.Model then return 0 end -- Safety: Cart must exist physically

	-- FIX: Distance Check
	-- Player must be near their cart to load it
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and cart.Model and cart.Model.PrimaryPart then
		local dist = (hrp.Position - cart.Model.PrimaryPart.Position).Magnitude
		if dist > 30 then
			warn(player.Name .. " tried to load cart from too far away ("..math.floor(dist).." studs)")
			return 0
		end
	end

	local current = 0
	for _, c in pairs(cart.Inventory) do current += c end
	local space = cart.Capacity - current

	local toMove = math.min(count, space)
	if toMove <= 0 then return 0 end

	local actuallyRemoved = ISM.RemoveFromStorage(player, itemId, toMove)
	if actuallyRemoved > 0 then
		CM.LoadItem(player, itemId, actuallyRemoved)
	end
	return actuallyRemoved
end

function TransportManager.LoadMaxFromStorage(player)
	local CM = getCartManager()
	local ISM = getItemStorage()
	if not CM or not ISM then return {} end

	local cart = CM.GetCartState(player)
	if not cart then return {} end
	if cart.State ~= "idle" then return {} end

	local current = 0
	for _, c in pairs(cart.Inventory) do current += c end
	local space = cart.Capacity - current

	if space <= 0 then return {} end

	local loaded = {}
	local storage = ISM.GetStorageContents(player)
	local list = {}

	for id, c in pairs(storage) do
		local ic = getItemConfig()
		local info = ic.Items[id]
		if info and c > 0 then
			table.insert(list, { id = id, count = c, val = info.basePrice or 1 })
		end
	end
	table.sort(list, function(a,b) return a.val > b.val end)

	for _, item in ipairs(list) do
		if space <= 0 then break end
		local toLoad = math.min(item.count, space)
		local didLoad = ISM.RemoveFromStorage(player, item.id, toLoad)
		if didLoad > 0 then
			CM.LoadItem(player, item.id, didLoad)
			loaded[item.id] = didLoad
			space -= didLoad
		end
	end

	return loaded
end

function TransportManager.GetVehicleInfo(player)
	local sel = PlayerTransport[player] and PlayerTransport[player].selectedVehicle or CONFIG.DEFAULT_VEHICLE

	local inventory = {}
	local CM = getCartManager()
	if CM then
		local cart = CM.GetCartState(player)
		if cart then inventory = cart.Inventory end
	end

	return {
		selectedVehicle = sel,
		capacity = getCartCapacity(player),
		currentLoad = getCartUsage(player),
		availableVehicles = CONFIG.VEHICLES,
		inventory = inventory
	}
end

function TransportManager.GetTransportData(player)
	return { selectedVehicle = PlayerTransport[player] and PlayerTransport[player].selectedVehicle or CONFIG.DEFAULT_VEHICLE }
end

function TransportManager.SetTransportData(player, data)
	if not PlayerTransport[player] then PlayerTransport[player] = {} end
	PlayerTransport[player].selectedVehicle = data.selectedVehicle or CONFIG.DEFAULT_VEHICLE

	local CM = getCartManager()
	if CM and CM.UpdateCapacity then
		CM.UpdateCapacity(player, getCartCapacity(player))
	end
end

-- Export Config
TransportManager.CONFIG = CONFIG
TransportManager.GetCartCapacity = getCartCapacity
TransportManager.GetCartUsage = getCartUsage

return TransportManager
