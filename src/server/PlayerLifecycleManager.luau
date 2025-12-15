--[[
	PlayerLifecycleManager Server Module
	
	Central coordinator for player loading state.
	Gates client interaction until all systems (Data, Map, Grid) are ready.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Events
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local PlayerReadyEvent = RemoteEvents:FindFirstChild("PlayerReady") or Instance.new("RemoteEvent")
PlayerReadyEvent.Name = "PlayerReady"
PlayerReadyEvent.Parent = RemoteEvents

-- State Definitions
type PlayerState = {
	DataLoaded: boolean,
	MapReady: boolean,
	GridRestored: boolean,
}

local PlayerStates: {[Player]: PlayerState} = {}
local PlayerLifecycleManager = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function checkReady(player: Player)
	local state = PlayerStates[player]
	if not state then return end
	
	if state.DataLoaded and state.MapReady and state.GridRestored then
		print("PlayerLifecycleManager: " .. player.Name .. " is READY!")
		PlayerReadyEvent:FireClient(player)
		-- Clean up state monitoring, we are done
		-- (Optional: Keep tracking if we want to handle re-syncs, but for loading screen it's one-off)
	end
end

local function getOrInitState(player: Player)
	if not PlayerStates[player] then
		PlayerStates[player] = {
			DataLoaded = false,
			MapReady = false,
			GridRestored = false -- Will be set true immediately if data says grid is empty
		}
	end
	return PlayerStates[player]
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function PlayerLifecycleManager.Init()
	print("   PlayerLifecycleManager (Module) - Initializing")
	
	Players.PlayerRemoving:Connect(function(player)
		PlayerStates[player] = nil
	end)
	
	print("✓ PlayerLifecycleManager Initialized")
end

function PlayerLifecycleManager.SetDataLoaded(player: Player)
	local state = getOrInitState(player)
	state.DataLoaded = true
	-- print("Lifecycle: Data Loaded for " .. player.Name)
	checkReady(player)
end

function PlayerLifecycleManager.SetMapReady(player: Player)
	local state = getOrInitState(player)
	state.MapReady = true
	-- print("Lifecycle: Map Ready for " .. player.Name)
	checkReady(player)
end

function PlayerLifecycleManager.SetGridRestored(player: Player)
	local state = getOrInitState(player)
	state.GridRestored = true
	-- print("Lifecycle: Grid Restored for " .. player.Name)
	checkReady(player)
end

function PlayerLifecycleManager.IsReady(player: Player)
	local state = PlayerStates[player]
	return state and state.DataLoaded and state.MapReady and state.GridRestored
end

return PlayerLifecycleManager
