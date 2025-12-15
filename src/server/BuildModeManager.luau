--[[
	BuildModeManager Server Module
	
	Manages Build Mode state for players.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local BuildModeChangedEvent = RemoteEvents:FindFirstChild("BuildModeChanged") or Instance.new("RemoteEvent")
BuildModeChangedEvent.Name = "BuildModeChanged"
BuildModeChangedEvent.Parent = RemoteEvents

local EnterBuildModeFunction = RemoteFunctions:FindFirstChild("EnterBuildMode") or Instance.new("RemoteFunction")
EnterBuildModeFunction.Name = "EnterBuildMode"
EnterBuildModeFunction.Parent = RemoteFunctions

local ExitBuildModeFunction = RemoteFunctions:FindFirstChild("ExitBuildMode") or Instance.new("RemoteFunction")
ExitBuildModeFunction.Name = "ExitBuildMode"
ExitBuildModeFunction.Parent = RemoteFunctions

local GetBuildModeStateFunction = RemoteFunctions:FindFirstChild("GetBuildModeState") or Instance.new("RemoteFunction")
GetBuildModeStateFunction.Name = "GetBuildModeState"
GetBuildModeStateFunction.Parent = RemoteFunctions

local BuildModeManager = {}
local Services = {}
local PlayerBuildModeState = {}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local function getPlayerState(player)
	if not PlayerBuildModeState[player.UserId] then
		PlayerBuildModeState[player.UserId] = { inBuildMode = false, enterTime = 0 }
	end
	return PlayerBuildModeState[player.UserId]
end

local function isInBuildMode(player)
	return getPlayerState(player).inBuildMode
end

local function enterBuildMode(player)
	local state = getPlayerState(player)
	if state.inBuildMode then return false, "Already in Build Mode" end
	
	state.inBuildMode = true
	state.enterTime = os.clock()
	
	BuildModeChangedEvent:FireAllClients(player.UserId, true)
	return true
end

local function exitBuildMode(player)
	local state = getPlayerState(player)
	if not state.inBuildMode then return false, "Not in Build Mode" end
	state.inBuildMode = false
	BuildModeChangedEvent:FireAllClients(player.UserId, false)
	return true
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function BuildModeManager.Init(services)
	print("   BuildModeManager (Module) - Initializing")
	Services = services or {}
	
	Players.PlayerRemoving:Connect(function(player)
		if isInBuildMode(player) then exitBuildMode(player) end
		PlayerBuildModeState[player.UserId] = nil
	end)
	
	EnterBuildModeFunction.OnServerInvoke = enterBuildMode
	ExitBuildModeFunction.OnServerInvoke = exitBuildMode
	GetBuildModeStateFunction.OnServerInvoke = function(player)
		local s = getPlayerState(player)
		return { inBuildMode = s.inBuildMode, enterTime = s.enterTime }
	end
	
	print("✓ BuildModeManager Initialized")
end

BuildModeManager.EnterBuildMode = enterBuildMode
BuildModeManager.ExitBuildMode = exitBuildMode
BuildModeManager.IsInBuildMode = isInBuildMode

return BuildModeManager
