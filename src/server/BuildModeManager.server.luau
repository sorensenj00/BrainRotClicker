--[[
	BuildModeManager Server Script
	
	Manages Build Mode state for players.
	
	Features:
	- Track when player is in Build Mode
	- Validate placement/move requests
	- Apply grid changes atomically
	
	Part of Phase 2B: Build Mode system.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Remote events
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not RemoteEvents then
	RemoteEvents = Instance.new("Folder")
	RemoteEvents.Name = "RemoteEvents"
	RemoteEvents.Parent = ReplicatedStorage
end

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions")
if not RemoteFunctions then
	RemoteFunctions = Instance.new("Folder")
	RemoteFunctions.Name = "RemoteFunctions"
	RemoteFunctions.Parent = ReplicatedStorage
end

-- Create events
local BuildModeChangedEvent = RemoteEvents:FindFirstChild("BuildModeChanged") or Instance.new("RemoteEvent")
BuildModeChangedEvent.Name = "BuildModeChanged"
BuildModeChangedEvent.Parent = RemoteEvents

-- Create functions
local EnterBuildModeFunction = RemoteFunctions:FindFirstChild("EnterBuildMode") or Instance.new("RemoteFunction")
EnterBuildModeFunction.Name = "EnterBuildMode"
EnterBuildModeFunction.Parent = RemoteFunctions

local ExitBuildModeFunction = RemoteFunctions:FindFirstChild("ExitBuildMode") or Instance.new("RemoteFunction")
ExitBuildModeFunction.Name = "ExitBuildMode"
ExitBuildModeFunction.Parent = RemoteFunctions

local GetBuildModeStateFunction = RemoteFunctions:FindFirstChild("GetBuildModeState") or Instance.new("RemoteFunction")
GetBuildModeStateFunction.Name = "GetBuildModeState"
GetBuildModeStateFunction.Parent = RemoteFunctions

--------------------------------------------------------------------------------
-- BUILD MODE STATE
--------------------------------------------------------------------------------

-- { [userId] = { inBuildMode = boolean, enterTime = number } }
local PlayerBuildModeState = {}

--[[
	Gets or creates build mode state for a player.
]]
local function getPlayerState(player)
	if not PlayerBuildModeState[player.UserId] then
		PlayerBuildModeState[player.UserId] = {
			inBuildMode = false,
			enterTime = 0,
		}
	end
	return PlayerBuildModeState[player.UserId]
end

--[[
	Checks if player is in build mode.
]]
local function isInBuildMode(player)
	local state = getPlayerState(player)
	return state.inBuildMode
end

--[[
	Enters build mode for a player.
]]
local function enterBuildMode(player)
	local state = getPlayerState(player)
	
	if state.inBuildMode then
		return false, "Already in Build Mode"
	end
	
	state.inBuildMode = true
	state.enterTime = os.clock()
	
	-- Notify all clients (for visibility)
	BuildModeChangedEvent:FireAllClients(player.UserId, true)
	
	print(string.format("✓ %s entered Build Mode", player.Name))
	return true
end

--[[
	Exits build mode for a player.
]]
local function exitBuildMode(player)
	local state = getPlayerState(player)
	
	if not state.inBuildMode then
		return false, "Not in Build Mode"
	end
	
	state.inBuildMode = false
	
	-- Notify all clients
	BuildModeChangedEvent:FireAllClients(player.UserId, false)
	
	local duration = os.clock() - state.enterTime
	print(string.format("✓ %s exited Build Mode (%.1fs)", player.Name, duration))
	return true
end

--------------------------------------------------------------------------------
-- REMOTE FUNCTION HANDLERS
--------------------------------------------------------------------------------

EnterBuildModeFunction.OnServerInvoke = function(player)
	return enterBuildMode(player)
end

ExitBuildModeFunction.OnServerInvoke = function(player)
	return exitBuildMode(player)
end

GetBuildModeStateFunction.OnServerInvoke = function(player)
	local state = getPlayerState(player)
	return {
		inBuildMode = state.inBuildMode,
		enterTime = state.enterTime,
	}
end

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	-- Exit build mode if active
	if isInBuildMode(player) then
		exitBuildMode(player)
	end
	PlayerBuildModeState[player.UserId] = nil
end)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

print("✓ BuildModeManager initialized")

-- Export API
_G.BuildModeManager = {
	EnterBuildMode = enterBuildMode,
	ExitBuildMode = exitBuildMode,
	IsInBuildMode = isInBuildMode,
}
