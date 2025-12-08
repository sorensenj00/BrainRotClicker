--[[
	AdminService Server Script
	
	Handles admin commands for testing purposes.
	- Reset Plot
	- Add Money
	- Toggle Fly
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Ensure RemoteEvents folder exists
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not RemoteEvents then
	RemoteEvents = Instance.new("Folder")
	RemoteEvents.Name = "RemoteEvents"
	RemoteEvents.Parent = ReplicatedStorage
end

-- Create AdminAction RemoteFunction
local AdminAction = RemoteEvents:FindFirstChild("AdminAction")
if not AdminAction then
	AdminAction = Instance.new("RemoteFunction")
	AdminAction.Name = "AdminAction"
	AdminAction.Parent = RemoteEvents
end

-- Wait for systems
local function waitForSystem(name)
	local attempts = 0
	while not _G[name] and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G[name]
end

-- Handlers
local handlers = {}

handlers.ResetPlot = function(player)
	local MapSystem = waitForSystem("MapSystem")
	if MapSystem and MapSystem.ResetPlayerPlot then
		MapSystem.ResetPlayerPlot(player)
		
		-- Also clear inventory
		local BrainrotManager = waitForSystem("BrainrotManager")
		if BrainrotManager and BrainrotManager.ClearPlayerInventory then
			BrainrotManager.ClearPlayerInventory(player)
		end
		
		-- Reset Money
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local money = leaderstats:FindFirstChild("Money")
			if money then
				money.Value = 0
			end
		end
		
		return true, "Plot reset successfully"
	end
	return false, "MapSystem not available"
end

handlers.AddMoney = function(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local money = leaderstats:FindFirstChild("Money")
		if money then
			money.Value += 1000000
			return true, "Added $1,000,000"
		end
	end
	return false, "No leaderstats found"
end

handlers.ToggleFly = function(player)
	local isFlying = player:GetAttribute("IsFlying")
	local newState = not isFlying
	player:SetAttribute("IsFlying", newState)
	
	-- Give visual feedback
	if newState then
		-- Create a force if needed, but client handles movement
		-- We just mark the player as allowed to fly
	end
	
	return true, newState and "Flight Enabled" or "Flight Disabled"
end

-- Main handler
AdminAction.OnServerInvoke = function(player, action, ...)
	-- In a real game, check for admin permissions here
	-- if not isAdmin(player) then return false, "No permission" end
	
	local handler = handlers[action]
	if handler then
		return handler(player, ...)
	end
	return false, "Unknown action"
end

print("✓ AdminService initialized")
