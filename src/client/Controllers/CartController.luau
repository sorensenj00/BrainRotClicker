local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local CartUpdateEvent = RemoteEvents:WaitForChild("CartUpdate")
local GetVehicleInfoFunction = RemoteFunctions:WaitForChild("GetVehicleInfo")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIUtils = require(Shared:WaitForChild("Utils"):WaitForChild("UIUtils"))

local CartController = {
	State = "idle",
	Inventory = {},
	Capacity = 200,
	ItemCount = 0,
	
	_callbacks = {}
}

function CartController.OnChanged(callback: (string, any, number, number) -> ())
	table.insert(CartController._callbacks, callback)
	-- fire immediately with current state
	task.spawn(callback, CartController.State, CartController.Inventory, CartController.Capacity, CartController.ItemCount)
end

local function fireCallbacks()
	for _, cb in CartController._callbacks do
		task.spawn(cb, CartController.State, CartController.Inventory, CartController.Capacity, CartController.ItemCount)
	end
end

local function calculateItemCount()
	local count = 0
	for _, c in pairs(CartController.Inventory) do
		count += c
	end
	CartController.ItemCount = count
end



-- Proper init
task.spawn(function()
	local player = Players.LocalPlayer
	-- Wait for player to be fully loaded if necessary
	local success, info = pcall(function() return GetVehicleInfoFunction:InvokeServer() end)
	if success and info then
		CartController.Inventory = UIUtils.decodeItems(info.inventory) or {}
		CartController.Capacity = player:GetAttribute("CartCapacity") or info.capacity or 200
		calculateItemCount()
		fireCallbacks()
	end
end)

CartUpdateEvent.OnClientEvent:Connect(function(state, inventory, capacity)
	CartController.State = state or "idle"
	CartController.Inventory = UIUtils.decodeItems(inventory) or {}
	CartController.Capacity = capacity or CartController.Capacity
	calculateItemCount()
	fireCallbacks()
end)

return CartController
