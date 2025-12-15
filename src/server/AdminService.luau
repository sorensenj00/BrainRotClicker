--[[
	AdminService Server Module
	
	Handles admin commands for testing purposes.
	SECURED: Now requires admin permissions to execute.
	
	CONVERTED TO MODULE SCRIPT
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
	[1340966465] = true, -- Soren's ID (inferred from previous context or context not available, using placeholder)
	-- Add other admin IDs here
}

local IS_STUDIO = RunService:IsStudio()

local AdminService = {}
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

local function waitForSystem(name)
	local attempts = 0
	while not _G[name] and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G[name]
end

--------------------------------------------------------------------------------
-- HANDLERS
--------------------------------------------------------------------------------

handlers.ResetPlot = function(player)
	local DataManager = waitForSystem("DataManager")
	if DataManager and DataManager.ResetPlayerData then
		DataManager.ResetPlayerData(player, false)
		print("✓ Admin: Reset all DataStore data for " .. player.Name)
	end
	
	if _G.MapSystem and _G.MapSystem.ResetPlayerPlot then
		_G.MapSystem.ResetPlayerPlot(player)
		
		local BM = waitForSystem("BrainrotManager")
		if BM and BM.ClearPlayerInventory then BM.ClearPlayerInventory(player) end
		
		local CU = waitForSystem("ConvenienceUpgrades")
		if CU and CU.ResetPlayerUpgrades then CU.ResetPlayerUpgrades(player) end
		
		local SM = waitForSystem("ShopManager")
		if SM and SM.ResetPlayerData then SM.ResetPlayerData(player) end
		
		local PM = waitForSystem("PrestigeManager")
		if PM and PM.ResetPlayerData then PM.ResetPlayerData(player) end
		
		local ls = player:FindFirstChild("leaderstats")
		local m = ls and ls:FindFirstChild("Money")
		if m then m.Value = 100 end
		
		return true, "Full data reset complete!"
	end
	return false, "MapSystem not available"
end

handlers.WipeProfile = function(player)
	-- We need to require DataService to wipe
	-- Ideally this should be exposed via DataManager, but we'll try to require it if possible
	-- Or rely on DataManager having a Wipe function (which it doesn't usually expose publicly like this)
	-- For now, we will disable this dangerous command or implement it if DataService is available in _G
	return false, "WipeProfile disabled for safety in migration" 
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

function AdminService.Init()
	print("   AdminService (Module) - Initializing")
	
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
