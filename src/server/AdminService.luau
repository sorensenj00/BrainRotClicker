--[[
	AdminService Server Module
	
	Handles admin commands for testing purposes.
	SECURED: Now requires admin permissions to execute.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local AdminAction = RemoteEvents:FindFirstChild("AdminAction") or Instance.new("RemoteFunction")
AdminAction.Name = "AdminAction"
AdminAction.Parent = RemoteEvents

-- Security Configuration
local ADMIN_USER_IDS = {
	[1340966465] = true, -- Placeholder
}

local IS_STUDIO = RunService:IsStudio()

local AdminService = {}
local Services = {}
local handlers = {}

--------------------------------------------------------------------------------
-- HELPER
--------------------------------------------------------------------------------

local function isAdmin(player)
	if IS_STUDIO then return true end
	if ADMIN_USER_IDS[player.UserId] then return true end
	if player.UserId == game.CreatorId then return true end
	return false
end

--------------------------------------------------------------------------------
-- HANDLERS
--------------------------------------------------------------------------------

handlers.ResetPlot = function(player)
	if Services.DataManager and Services.DataManager.ResetPlayerData then
		Services.DataManager.ResetPlayerData(player, false)
		print("✓ Admin: Reset all DataStore data for " .. player.Name)
	end
	
	if Services.MapSystem and Services.MapSystem.ResetPlayerPlot then
		Services.MapSystem.ResetPlayerPlot(player)
		
		if Services.ShopManager and Services.ShopManager.ResetPlayerData then
			Services.ShopManager.ResetPlayerData(player)
		end
		
		-- Money Reset
		local ls = player:FindFirstChild("leaderstats")
		local m = ls and ls:FindFirstChild("Money")
		if m then m.Value = 100 end
		
		return true, "Full data reset complete!"
	end
	return false, "MapSystem not available"
end

handlers.WipeProfile = function(player)
	return false, "WipeProfile disabled"
end

handlers.AddMoney = function(player)
	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	if m then
		m.Value += 1000000
		return true, "Added $1,000,000"
	end
	return false, "No leaderstats"
end

handlers.ToggleFly = function(player)
	local isFlying = player:GetAttribute("IsFlying")
	local newState = not isFlying
	player:SetAttribute("IsFlying", newState)
	return true, newState and "Flight Enabled" or "Flight Disabled"
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function AdminService.Init(services)
	print("   AdminService (Module) - Initializing")
	Services = services or {}
	
	AdminAction.OnServerInvoke = function(player, action, ...)
		if not isAdmin(player) then
			warn(string.format("SECURITY: Unauthorized admin attempt by %s (%d) for action '%s'", player.Name, player.UserId, tostring(action)))
			return false, "Permission Denied"
		end
		
		local handler = handlers[action]
		if handler then
			return handler(player, ...)
		end
		return false, "Unknown action"
	end
	
	print("✓ AdminService Initialized")
end

return AdminService
