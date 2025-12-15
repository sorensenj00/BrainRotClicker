--[[
	MapSystem Server Module
	(Formerly init.server.luau)
	
	Handles:
	1. Spawning the central MainIsland hub
	2. Generating 8 player plots in a circular formation
	3. Creating bridges connecting each plot to the hub
	4. Assigning plots to players
	5. Tier System (expanding plots)
	
	CONVERTED TO MODULE SCRIPT
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CONFIG = {
	MAX_PLAYERS = 8,
	PLOT_RADIUS = 400,
	MAIN_ISLAND_HEIGHT = 30,
	PLOT_MIN_HEIGHT = 50,
	PLOT_MAX_HEIGHT = 120,
}

local TIER_CONFIG = {
	MODELS_PER_TIER = 12,
	MAX_TIERS = 6,
	TIER_HEIGHT_MIN = 20,
	TIER_HEIGHT_MAX = 60,
	TIER_DISTANCE_MIN = 80,
	TIER_DISTANCE_MAX = 140,
	STAIR_WIDTH = 10,
	STAIR_DEPTH = 4,
	STAIR_HEIGHT = 3,
	GRID_COLUMNS = 6,
	GRID_ROWS = 2,
	SIDE_OFFSETS = {
		[0] = Vector3.new(0, 0, 1),
		[1] = Vector3.new(1, 0, 0),
		[2] = Vector3.new(0, 0, -1),
		[3] = Vector3.new(-1, 0, 0),
	},
}

local MainIslandTemplate, PlayerPlotTemplate, BridgeTemplate
local Plots = {}
local PlayerToPlot = {}
local PlotsFolder
local PlayerTierSystems = {}

local MapSystem = {}

--------------------------------------------------------------------------------
-- UTILITY
--------------------------------------------------------------------------------

local function calculatePlotCFrame(index)
	local i = index - 1
	local angle = i * ((2 * math.pi) / CONFIG.MAX_PLAYERS)
	local x = CONFIG.PLOT_RADIUS * math.cos(angle)
	local z = CONFIG.PLOT_RADIUS * math.sin(angle)
	local h = math.random(CONFIG.PLOT_MIN_HEIGHT, CONFIG.PLOT_MAX_HEIGHT)
	return CFrame.new(x, h, z) * CFrame.Angles(0, -(angle + math.pi), 0)
end

local function calculateBridgeCFrame(plotCFrame)
	local plotPos = plotCFrame.Position
	local dir2D = Vector3.new(plotPos.X, 0, plotPos.Z).Unit
	local hubEdge = Vector3.new(dir2D.X * 50, CONFIG.MAIN_ISLAND_HEIGHT + 10, dir2D.Z * 50)
	local plotEdge = Vector3.new(plotPos.X - dir2D.X * 40, plotPos.Y + 10, plotPos.Z - dir2D.Z * 40)
	return CFrame.new((hubEdge + plotEdge) / 2, plotEdge), (plotEdge - hubEdge).Magnitude
end

--------------------------------------------------------------------------------
-- TIER SYSTEM
--------------------------------------------------------------------------------

local function getAvailableSide(tierData)
	local avail = {}
	for side = 0, 3 do
		local blocked = (side == tierData.BlockedSide)
		local used = false
		for _, u in tierData.UsedSides do if u == side then used = true; break end end
		if not blocked and not used then table.insert(avail, side) end
	end
	if #avail == 0 then return nil end
	return avail[math.random(1, #avail)]
end

local function calculateIncomingSide(parentPos, childPos)
	local dir = parentPos - childPos
	if math.abs(dir.Z) > math.abs(dir.X) then
		return dir.Z > 0 and 0 or 2
	else
		return dir.X > 0 and 1 or 3
	end
end

local function spawnTierPlot(player, parentTier)
	local side = getAvailableSide(parentTier)
	if not side then warn("No sides for tier " .. player.Name); return nil end
	
	local sys = PlayerTierSystems[player]
	if not sys then return nil end
	local nextIdx = #sys.Tiers + 1
	if nextIdx > TIER_CONFIG.MAX_TIERS then return nil end
	
	local parentCF = parentTier.Model:GetPivot()
	local offset = TIER_CONFIG.SIDE_OFFSETS[side]
	local hOff = math.random(TIER_CONFIG.TIER_HEIGHT_MIN, TIER_CONFIG.TIER_HEIGHT_MAX)
	local dist = math.random(TIER_CONFIG.TIER_DISTANCE_MIN, TIER_CONFIG.TIER_DISTANCE_MAX)
	
	local newPos = parentCF.Position + (offset * dist)
	newPos = Vector3.new(newPos.X, parentCF.Position.Y + hOff, newPos.Z)
	
	local newModel = PlayerPlotTemplate:Clone()
	newModel.Name = string.format("Plot_%d_Tier_%d", sys.BasePlotIndex, nextIdx)
	
	local lookDir = parentCF.Position - newPos
	local newCF = CFrame.new(newPos) * CFrame.Angles(0, math.atan2(lookDir.X, lookDir.Z), 0)
	newModel:PivotTo(newCF)
	newModel:SetAttribute("OwnerId", player.UserId)
	newModel:SetAttribute("TierIndex", nextIdx)
	newModel.Parent = PlotsFolder
	
	-- Stairs
	local stairs = Instance.new("Model")
	stairs.Name = string.format("Stairs_%d_Tier_%d", sys.BasePlotIndex, nextIdx)
	
	local pEdge = parentCF.Position + (offset * 40); pEdge = Vector3.new(pEdge.X, pEdge.Y + 2, pEdge.Z)
	local cEdge = newPos - (offset * 40); cEdge = Vector3.new(cEdge.X, cEdge.Y + 2, cEdge.Z)
	
	local vDist = cEdge.Y - pEdge.Y
	local hDist = (Vector3.new(cEdge.X, 0, cEdge.Z) - Vector3.new(pEdge.X, 0, pEdge.Z)).Magnitude
	
	local steps = math.max(1, math.floor(vDist / TIER_CONFIG.STAIR_HEIGHT))
	local sH = vDist / steps; local sD = hDist / steps
	local dir = (Vector3.new(cEdge.X, 0, cEdge.Z) - Vector3.new(pEdge.X, 0, pEdge.Z)).Unit
	
	for i = 0, steps - 1 do
		local s = Instance.new("Part")
		s.Name = "Step_"..i
		s.Size = Vector3.new(TIER_CONFIG.STAIR_WIDTH, math.max(0.5, sH), math.max(0.5, sD))
		s.Anchored = true; s.CanCollide = true; s.Material = Enum.Material.Concrete
		s.Position = Vector3.new(pEdge.X + dir.X*(i+0.5)*sD, pEdge.Y + (i+0.5)*sH, pEdge.Z + dir.Z*(i+0.5)*sD)
		s.CFrame = CFrame.new(s.Position) * CFrame.Angles(0, math.atan2(dir.X, dir.Z), 0)
		s.Parent = stairs
	end
	if stairs:FindFirstChild("Step_0") then stairs.PrimaryPart = stairs.Step_0 end
	stairs.Parent = workspace
	
	table.insert(parentTier.UsedSides, side)
	
	local incSide = calculateIncomingSide(parentCF.Position, newPos)
	local newTierData = {
		TierIndex = nextIdx,
		Model = newModel,
		Bridge = stairs,
		ParentTier = parentTier,
		BlockedSide = incSide,
		UsedSides = {},
		GridIndex = 0
	}
	table.insert(sys.Tiers, newTierData)
	return newTierData
end

--------------------------------------------------------------------------------
-- PLOTS
--------------------------------------------------------------------------------

local function createClaimPart(model)
	local p = Instance.new("Part")
	p.Name = "ClaimPart"; p.Size = Vector3.new(10, 1, 10); p.BrickColor = BrickColor.new("Lime green")
	p.Transparency = 0.3; p.Anchored = true; p.CanCollide = false
	p.Position = model:GetPivot().Position + Vector3.new(0, 3, 0)
	p.Parent = model
	return p
end

local function generatePlots()
	PlotsFolder = Instance.new("Folder"); PlotsFolder.Name = "Plots"; PlotsFolder.Parent = workspace
	for i = 1, CONFIG.MAX_PLAYERS do
		local cf = calculatePlotCFrame(i)
		local pm = PlayerPlotTemplate:Clone(); pm.Name = "Plot_"..i; pm:PivotTo(cf); pm.Parent = PlotsFolder
		
		local bcf, bdist = calculateBridgeCFrame(cf)
		local bm = BridgeTemplate:Clone(); bm.Name = "Bridge_"..i
		for _, part in bm:GetDescendants() do if part:IsA("BasePart") then part.Size = Vector3.new(part.Size.X, part.Size.Y, bdist) end end
		bm:PivotTo(bcf); bm.Parent = workspace
		
		Plots[i] = { Index = i, Model = pm, Bridge = bm, Position = cf, Owner = nil, ClaimPart = createClaimPart(pm) }
		
		if workspace:FindFirstChild("MainIsland") then
			local zp = Instance.new("Part"); zp.Name="Zipline_"..i; zp.Size=Vector3.new(4,8,4); zp.Anchored=true; zp.CanCollide=false; zp.Transparency=0.5
			local dir = (cf.Position - Vector3.new(0,CONFIG.MAIN_ISLAND_HEIGHT,0)).Unit
			zp.Position = Vector3.new(0,CONFIG.MAIN_ISLAND_HEIGHT,0) + dir*45
			zp.Parent = workspace.MainIsland
		end
	end
end

local function findAvailablePlot()
	for i, p in pairs(Plots) do if not p.Owner then return i end end
	return nil
end

local function assignPlotToPlayer(player, idx)
	local pData = Plots[idx]
	if not pData or pData.Owner then return end
	
	pData.Owner = player
	PlayerToPlot[player] = idx
	pData.Model:SetAttribute("OwnerId", player.UserId)
	pData.Model:SetAttribute("TierIndex", 1)
	if pData.ClaimPart then pData.ClaimPart.BrickColor = BrickColor.new("Really red"); pData.ClaimPart.Transparency = 0.7 end
	
	Instance.new("Folder", pData.Model).Name = "PlayerBuildings"
	
	local blocked = calculateIncomingSide(Vector3.new(0,0,0), pData.Position.Position)
	PlayerTierSystems[player] = {
		BasePlotIndex = idx,
		Tiers = {{TierIndex=1, Model=pData.Model, Bridge=pData.Bridge, ParentTier=nil, BlockedSide=blocked, UsedSides={}, GridIndex=0}},
		CurrentTier = 1,
		TotalModels = 0
	}
	print("✓ Assigned Plot " .. idx .. " to " .. player.Name)
	
	local PlayerLifecycleManager = require(script.Parent.PlayerLifecycleManager)
	PlayerLifecycleManager.SetMapReady(player)
end

local function teleportPlayer(player)
	local idx = PlayerToPlot[player]
	if not idx then return end
	local pData = Plots[idx]
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then hrp.CFrame = CFrame.new(pData.Model:GetPivot().Position + Vector3.new(0, 10, 0)) end
end

local function clearPlayerPlot(player)
	local idx = PlayerToPlot[player]
	if not idx then return end
	local pData = Plots[idx]
	
	local sys = PlayerTierSystems[player]
	if sys then
		for i = #sys.Tiers, 2, -1 do
			local t = sys.Tiers[i]
			if t.Bridge then t.Bridge:Destroy() end
			if t.Model then t.Model:Destroy() end
		end
		PlayerTierSystems[player] = nil
	end
	
	if pData.Model:FindFirstChild("PlayerBuildings") then pData.Model.PlayerBuildings:Destroy() end
	if pData.Model:FindFirstChild("Brainrots") then pData.Model.Brainrots:Destroy() end
	
	if pData.ClaimPart then pData.ClaimPart.BrickColor = BrickColor.new("Lime green"); pData.ClaimPart.Transparency = 0.3 end
	pData.Owner = nil
	PlayerToPlot[player] = nil
	pData.Model:SetAttribute("OwnerId", nil)
	pData.Model:SetAttribute("TierIndex", nil)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function MapSystem.Init()
	print("   MapSystem (Module) - Initializing")
	
	MainIslandTemplate = ServerStorage:FindFirstChild("MainIsland") or ReplicatedStorage:FindFirstChild("MainIsland")
	PlayerPlotTemplate = ServerStorage:FindFirstChild("PlayerPlot") or ReplicatedStorage:FindFirstChild("PlayerPlot")
	BridgeTemplate = ServerStorage:FindFirstChild("Bridge") or ReplicatedStorage:FindFirstChild("Bridge")
	
	-- Placeholders
	if not MainIslandTemplate then
		local m = Instance.new("Model"); m.Name="MainIsland"; local p = Instance.new("Part"); p.Name="Island"; p.Size=Vector3.new(100,20,100); p.Anchored=true; p.Color=Color3.new(0,1,0); p.Parent=m; m.PrimaryPart=p; m.Parent=ServerStorage; MainIslandTemplate=m
	end
	if not PlayerPlotTemplate then
		local m = Instance.new("Model"); m.Name="PlayerPlot"; local p = Instance.new("Part"); p.Name="Island"; p.Size=Vector3.new(80,15,80); p.Anchored=true; p.Color=Color3.new(0,1,0); p.Parent=m; m.PrimaryPart=p; m.Parent=ServerStorage; PlayerPlotTemplate=m
	end
	if not BridgeTemplate then
		local m = Instance.new("Model"); m.Name="Bridge"; local p = Instance.new("Part"); p.Name="BridgePart"; p.Size=Vector3.new(10,2,50); p.Anchored=true; p.Color=Color3.new(0.6,0.4,0.2); p.Parent=m; m.PrimaryPart=p; m.Parent=ServerStorage; BridgeTemplate=m
	end
	
	-- Spawn Main
	local mi = MainIslandTemplate:Clone(); mi.Name="MainIsland"; mi:PivotTo(CFrame.new(0, CONFIG.MAIN_ISLAND_HEIGHT, 0)); mi.Parent=workspace
	
	-- Generate Plots
	generatePlots()
	
	-- Handlers
	Players.PlayerAdded:Connect(function(player)
		local idx = findAvailablePlot()
		if idx then
			assignPlotToPlayer(player, idx)
			player.CharacterAdded:Connect(function() task.wait(1); teleportPlayer(player) end)
			if player.Character then task.wait(1); teleportPlayer(player) end
		end
	end)
	
	Players.PlayerRemoving:Connect(clearPlayerPlot)
	
	for _, p in Players:GetPlayers() do
		local idx = findAvailablePlot()
		if idx then assignPlotToPlayer(p, idx) end
	end
	
	print("✓ MapSystem Initialized")
end

MapSystem.GetPlayerPlot = function(p) local idx = PlayerToPlot[p]; return idx and Plots[idx] end
MapSystem.GetAllPlots = function() return Plots end
MapSystem.CONFIG = CONFIG
MapSystem.TIER_CONFIG = TIER_CONFIG
MapSystem.GetPlayerTierSystem = function(p) return PlayerTierSystems[p] end
MapSystem.SpawnTierPlot = spawnTierPlot
MapSystem.GetCurrentTier = function(p) local s = PlayerTierSystems[p]; return s and s.Tiers[s.CurrentTier] end
MapSystem.ResetPlayerPlot = function(p)
	local idx = PlayerToPlot[p]
	if idx then
		clearPlayerPlot(p)
		task.wait(0.1)
		assignPlotToPlayer(p, idx)
		task.delay(0.5, function() teleportPlayer(p) end)
	end
end
MapSystem.RestoreTiers = function(player, count)
	local sys = PlayerTierSystems[player]
	if not sys or count <= 1 then return end
	print("Restoring tiers for "..player.Name)
	for i = 2, count do
		local cur = sys.Tiers[#sys.Tiers]
		if cur then 
			local new = spawnTierPlot(player, cur)
			if new then sys.CurrentTier = new.TierIndex end
		end
	end
end

return MapSystem
