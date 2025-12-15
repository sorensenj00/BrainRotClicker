--[[
	TransportManager Server Module
	
	Handles the transport system for carrying items from storage to market.
	
	CONVERTED TO MODULE SCRIPT
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

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

-- State
local PlayerTransport = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getItemStorage()
	return _G.ItemStorageManager
end

local function getBackpackCapacity(player)
	local t = PlayerTransport[player]
	local vid = t and t.selectedVehicle or CONFIG.DEFAULT_VEHICLE
	local vc = CONFIG.VEHICLES[vid]
	return vc and vc.capacity or 100
end

local function getBackpackUsage(player)
	local ISM = getItemStorage()
	if not ISM then return 0 end
	local bp = ISM.GetBackpackContents(player)
	local total = 0
	for _, c in pairs(bp) do total += c end
	return total
end

local function getBackpackSpace(player)
	return getBackpackCapacity(player) - getBackpackUsage(player)
end

local function initializePlayer(player)
	PlayerTransport[player] = { selectedVehicle = CONFIG.DEFAULT_VEHICLE }
	local ISM = getItemStorage()
	-- Retry once for startup race condition logic if needed, but Init usually handles it
	if ISM and ISM.SetBackpackCapacity then
		ISM.SetBackpackCapacity(player, getBackpackCapacity(player))
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function TransportManager.Init()
	print("   TransportManager (Module) - Initializing")
	
	Players.PlayerAdded:Connect(function(player)
		-- Wait briefly for ISM
		task.wait(1) 
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
		-- Check Money
		local ls = player:FindFirstChild("leaderstats")
		local m = ls and ls:FindFirstChild("Money")
		if not m or m.Value < conf.price then return false, "Not enough cash" end
		m.Value -= conf.price
	end
	
	t.selectedVehicle = vehicleId
	
	local ISM = getItemStorage()
	if ISM and ISM.SetBackpackCapacity then
		ISM.SetBackpackCapacity(player, getBackpackCapacity(player))
	end
	
	VehicleUpdated:FireClient(player, vehicleId, getBackpackCapacity(player))
	return true
end

function TransportManager.LoadFromStorage(player, itemId, count)
	local ISM = getItemStorage()
	if not ISM then return 0 end
	
	local space = getBackpackSpace(player)
	if space <= 0 then return 0 end
	
	local count = count or 1
	local loaded = ISM.TransferToBackpack(player, itemId, math.min(count, space))
	
	if loaded > 0 then
		BackpackLoaded:FireClient(player, itemId, loaded)
	end
	return loaded
end

function TransportManager.LoadMaxFromStorage(player)
	local ISM = getItemStorage()
	if not ISM then return {} end
	
	local space = getBackpackSpace(player)
	if space <= 0 then return {} end
	
	local loaded = {}
	local storage = ISM.GetStorageContents(player)
	local list = {}
	
	for id, c in pairs(storage) do
		local info = ItemConfig.Items[id]
		if info and c > 0 then
			table.insert(list, { id = id, count = c, val = info.basePrice or 1 })
		end
	end
	table.sort(list, function(a,b) return a.val > b.val end)
	
	for _, item in ipairs(list) do
		if space <= 0 then break end
		local toLoad = math.min(item.count, space)
		local didLoad = ISM.TransferToBackpack(player, item.id, toLoad)
		if didLoad > 0 then
			loaded[item.id] = didLoad
			space -= didLoad
		end
	end
	
	local total = 0
	for _, c in pairs(loaded) do total += c end
	if total > 0 then
		BackpackLoaded:FireClient(player, nil, total)
	end
	return loaded
end

function TransportManager.GetVehicleInfo(player)
	local sel = PlayerTransport[player] and PlayerTransport[player].selectedVehicle or CONFIG.DEFAULT_VEHICLE
	return {
		selectedVehicle = sel,
		capacity = getBackpackCapacity(player),
		currentLoad = getBackpackUsage(player),
		availableVehicles = CONFIG.VEHICLES
	}
end

function TransportManager.GetTransportData(player)
	return { selectedVehicle = PlayerTransport[player] and PlayerTransport[player].selectedVehicle or CONFIG.DEFAULT_VEHICLE }
end

function TransportManager.SetTransportData(player, data)
	if not PlayerTransport[player] then PlayerTransport[player] = {} end
	PlayerTransport[player].selectedVehicle = data.selectedVehicle or CONFIG.DEFAULT_VEHICLE
	
	local ISM = getItemStorage()
	if ISM and ISM.SetBackpackCapacity then
		ISM.SetBackpackCapacity(player, getBackpackCapacity(player))
	end
end

-- Export Config
TransportManager.CONFIG = CONFIG
TransportManager.GetBackpackCapacity = getBackpackCapacity
TransportManager.GetBackpackUsage = getBackpackUsage
TransportManager.GetBackpackSpace = getBackpackSpace

return TransportManager
