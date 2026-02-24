--[[
	AdminService Server Module
	
	Handles admin commands for testing purposes.
	SECURED: Now requires admin permissions to execute.
]]

local _Players = game:GetService("Players")
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
-- HANDLERS: Player
--------------------------------------------------------------------------------

handlers.ResetPlot = function(player)
	local DataManager = rawget(Services, "DataManager")
	if DataManager and DataManager.ResetPlayerData then
		DataManager.ResetPlayerData(player, false)
		print("✓ Admin: Reset all DataStore data for " .. player.Name)
	end
	
	local MapSystem = rawget(Services, "MapSystem")
	if MapSystem and MapSystem.ResetPlayerPlot then
		MapSystem.ResetPlayerPlot(player)
		
		local ShopManager = rawget(Services, "ShopManager")
		if ShopManager and ShopManager.ResetPlayerData then
			ShopManager.ResetPlayerData(player)
		end
		
		-- Money Reset
		local ls = player:FindFirstChild("leaderstats")
		local m = ls and ls:FindFirstChild("Money")
		if m then m.Value = 100 end
		
		return true, "Full data reset complete!"
	end
	return false, "MapSystem not available"
end

handlers.WipeProfile = function(_player)
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
-- HANDLERS: Economy
--------------------------------------------------------------------------------

handlers.GiveItems = function(player, itemId, count)
	if type(itemId) ~= "string" or itemId == "" then
		return false, "Invalid ItemId"
	end
	
	local giveCount = tonumber(count) or 1000
	if giveCount <= 0 or giveCount > 100000 then
		return false, "Invalid count (1-100000)"
	end
	
	-- Validate item exists
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
	if not ItemConfig.Items[itemId] then
		return false, "Unknown item: " .. itemId
	end
	
	local ISM = rawget(Services, "ItemStorageManager")
	if not ISM then
		return false, "ItemStorageManager not available"
	end
	
	local added = ISM.AddToStorage(player, itemId, giveCount)
	return true, string.format("Gave %dx %s (stored %d)", giveCount, itemId, added)
end

handlers.WipeInventory = function(player)
	local ISM = rawget(Services, "ItemStorageManager")
	if ISM and ISM.ResetPlayerStorage then
		ISM.ResetPlayerStorage(player)
		return true, "Storage & Backpack wiped!"
	end
	return false, "ItemStorageManager not available"
end

--------------------------------------------------------------------------------
-- HANDLERS: Market
--------------------------------------------------------------------------------

handlers.ForceLocalCrash = function(player)
	local SM = rawget(Services, "StockMarketManager")
	if SM and SM.ForceLocalShock then
		SM.ForceLocalShock(false) -- crash
		return true, "🔻 FORCED LOCAL CRASH — prices tanked on this server!"
	end
	return false, "StockMarketManager not available"
end

handlers.ForceLocalMoon = function(player)
	local SM = rawget(Services, "StockMarketManager")
	if SM and SM.ForceLocalShock then
		SM.ForceLocalShock(true) -- moon
		return true, "🚀 FORCED LOCAL MOON — prices spiked on this server!"
	end
	return false, "StockMarketManager not available"
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
