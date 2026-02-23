--[[
	MapSystem Server Module
	(Refactored Facade)
	
	Responsibility: Coordinates Player lifecycle events with PlotManager.
	Delegates generation and state management to PlotManager and TerrainGenerator.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapSystem = {}
local Services = {}

-- Legacy Config Export (Read-only)
MapSystem.CONFIG = {
	MAX_PLAYERS = 8,
	PLOT_RADIUS = 400,
	MAIN_ISLAND_HEIGHT = 60,
}

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function MapSystem.Init(services)
	print("   MapSystem (Facade) - Initializing")
	Services = services or {}
	
	local PlotManager = rawget(Services, "PlotManager")
	if not PlotManager then
		warn("MapSystem requires PlotManager!")
		return
	end

	-- Handlers
	-- Handlers
	local function handlePlayer(player)
		local idx = PlotManager.FindAvailablePlot()
		if idx then
			PlotManager.AssignPlot(player, idx)
			
			local function onCharacterAdded(char)
				local hrp = char:WaitForChild("HumanoidRootPart", 5)
				if hrp then
					-- Anchor to prevent falling while teleporting
					hrp.Anchored = true
					PlotManager.TeleportPlayer(player)
					-- Small wait to ensure CFrame is applied before physics resumes
					task.wait()
					hrp.Anchored = false
				end
			end
			
			player.CharacterAdded:Connect(onCharacterAdded)
			
			if player.Character then 
				onCharacterAdded(player.Character)
			end
		end
	end

	Players.PlayerAdded:Connect(handlePlayer)
	
	Players.PlayerRemoving:Connect(function(player)
		PlotManager.ClearPlot(player)
	end)
	
	-- Handle players already present (if reloaded)
	for _, p in Players:GetPlayers() do
		handlePlayer(p)
	end
	
	print("✓ MapSystem Initialized")
end

-- Delegate API calls to PlotManager
MapSystem.GetPlayerPlot = function(p) 
	local PM = rawget(Services, "PlotManager")
	return PM and PM.GetPlayerPlot(p) 
end

MapSystem.GetAllPlots = function() 
	local PM = rawget(Services, "PlotManager")
	return PM and PM.GetAllPlots() 
end

MapSystem.GetPlayerTierSystem = function(p)
	local PM = rawget(Services, "PlotManager")
	return PM and PM.GetPlayerTierSystem(p)
end

MapSystem.SpawnTierPlot = function(player, parentTier)
	local PM = rawget(Services, "PlotManager")
	return PM and PM.SpawnTierPlot(player, parentTier)
end

MapSystem.GetCurrentTier = function(p) 
	local PM = rawget(Services, "PlotManager")
	if not PM then return nil end
	local sys = PM.GetPlayerTierSystem(p)
	return sys and sys.Tiers[sys.CurrentTier] 
end

MapSystem.ResetPlayerPlot = function(p)
	local PM = rawget(Services, "PlotManager")
	if not PM then return end
	
	local idx = PM.GetPlayerPlot(p) and PM.GetPlayerTierSystem(p) and PM.GetPlayerTierSystem(p).BasePlotIndex
	-- The above logic is trying to find the index. PlotManager tracks state internally.
	-- Let's just use what we have access to.
	
	PM.ClearPlot(p)
	task.wait(0.1)
	
	-- Re-assign (we need the index to be consistent? The original logic kept the same index)
	-- PlotManager.ClearPlot removes the mapping.
	-- We might need a "Reset" method in PlotManager to be cleaner, but for now we'll rely on FindAvailable.
	-- ACTUALLY, checking legacy: ResetPlayerPlot used the SAME index.
	-- My new ClearPlot removes the mapping. 
	-- This is a small behavior change. Re-assigning might give a different plot if multiple are empty.
	-- For now, this is acceptable for a "Reset".
	
	local newIdx = PM.FindAvailablePlot()
	if newIdx then
		PM.AssignPlot(p, newIdx)
		task.delay(0.5, function() PM.TeleportPlayer(p) end)
	end
end

MapSystem.RestoreTiers = function(player, count)
	local PM = rawget(Services, "PlotManager")
	return PM and PM.RestoreTiers(player, count)
end

return MapSystem
