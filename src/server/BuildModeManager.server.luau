--[[
	BuildModeManager Server Script
	
	Manages Build Mode state for players.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Helper to get or create remote instance
local function getRemote(name, class, parent)
	local remote = parent:FindFirstChild(name)
	if not remote then
		remote = Instance.new(class)
		remote.Name = name
		remote.Parent = parent
	end
	return remote
end

-- Remotes
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder", ReplicatedStorage)
RemoteEvents.Name = "RemoteEvents"
local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder", ReplicatedStorage)
RemoteFunctions.Name = "RemoteFunctions"

local BuildModeChangedEvent = getRemote("BuildModeChanged", "RemoteEvent", RemoteEvents)
local EnterBuildModeFunction = getRemote("EnterBuildMode", "RemoteFunction", RemoteFunctions)
local ExitBuildModeFunction = getRemote("ExitBuildMode", "RemoteFunction", RemoteFunctions)
local GetBuildModeStateFunction = getRemote("GetBuildModeState", "RemoteFunction", RemoteFunctions)

-- State: { [userId] = { inBuildMode = boolean, enterTime = number } }
local PlayerBuildModeState = {}

local function getPlayerState(player)
	if not PlayerBuildModeState[player.UserId] then
		PlayerBuildModeState[player.UserId] = { inBuildMode = false, enterTime = 0 }
	end
	return PlayerBuildModeState[player.UserId]
end

local function toggleBuildMode(player, isActive)
	local state = getPlayerState(player)
	if state.inBuildMode == isActive then
		return false, isActive and "Already in Build Mode" or "Not in Build Mode"
	end
	
	state.inBuildMode = isActive
	state.enterTime = isActive and os.clock() or state.enterTime
	
	BuildModeChangedEvent:FireAllClients(player.UserId, isActive)
	return true
end

-- Handlers
EnterBuildModeFunction.OnServerInvoke = function(player)
	return toggleBuildMode(player, true)
end

ExitBuildModeFunction.OnServerInvoke = function(player)
	return toggleBuildMode(player, false)
end

GetBuildModeStateFunction.OnServerInvoke = function(player)
	return getPlayerState(player)
end

-- Cleanup
Players.PlayerRemoving:Connect(function(player)
	if getPlayerState(player).inBuildMode then
		toggleBuildMode(player, false)
	end
	PlayerBuildModeState[player.UserId] = nil
end)
