--[[
	PlotManager Server Module
	
	Responsibility: Managing the state of plots (Assignment, Clearing, Tiers).
	Coordinates with TerrainGenerator for visuals.
	Moved from MapSystem to adhere to SRP.
]]



local PlotManager = {}
local Services = {}

local PlotsFolder
local Plots = {} -- {Index, Model, Bridge, Position, Owner, ClaimPart}
local PlayerToPlot = {}
local PlayerTierSystems = {}

local CONFIG = {
	MAX_PLAYERS = 8,
	PLOT_RADIUS = 400,
	MAIN_ISLAND_HEIGHT = 30,
	PLOT_MIN_HEIGHT = 50,
	PLOT_MAX_HEIGHT = 120,
}

local TIER_CONFIG = {
	MAX_TIERS = 6,
	MODELS_PER_TIER = 16,
	TIER_HEIGHT_MIN = 20,
	TIER_HEIGHT_MAX = 60,
	TIER_DISTANCE_MIN = 80,
	TIER_DISTANCE_MAX = 140,
	SIDE_OFFSETS = {
		[0] = Vector3.new(0, 0, 1),
		[1] = Vector3.new(1, 0, 0),
		[2] = Vector3.new(0, 0, -1),
		[3] = Vector3.new(-1, 0, 0),
	},
}

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
	local hubEdge = Vector3.new(dir2D.X * 100, CONFIG.MAIN_ISLAND_HEIGHT, dir2D.Z * 100)
	local plotEdge = Vector3.new(plotPos.X - dir2D.X * 60, plotPos.Y, plotPos.Z - dir2D.Z * 60)
	return CFrame.new((hubEdge + plotEdge) / 2, plotEdge), (plotEdge - hubEdge).Magnitude
end

local function calculateIncomingSide(parentPos, childPos)
	local dir = parentPos - childPos
	if math.abs(dir.Z) > math.abs(dir.X) then
		return dir.Z > 0 and 0 or 2
	else
		return dir.X > 0 and 1 or 3
	end
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function PlotManager.Init(services)
	print("   PlotManager (Module) - Initializing")
	Services = services or {}
	
	local TerrainGenerator = rawget(Services, "TerrainGenerator")
	if not TerrainGenerator then
		warn("PlotManager requires TerrainGenerator!")
	end
	
	-- Spawn Main Island
	if TerrainGenerator then
		TerrainGenerator.SpawnMainIsland(CONFIG.MAIN_ISLAND_HEIGHT)
	end
	
	-- Generate Plots
	PlotsFolder = Instance.new("Folder"); PlotsFolder.Name = "Plots"; PlotsFolder.Parent = workspace
	
	for i = 1, CONFIG.MAX_PLAYERS do
		local cf = calculatePlotCFrame(i)
		local pm, bm, claimPart
		
		if TerrainGenerator then
			pm = TerrainGenerator.CreatePlotModel()
			pm.Name = "Plot_"..i
			pm:PivotTo(cf)
			pm.Parent = PlotsFolder
			
			local bcf, bdist = calculateBridgeCFrame(cf)
			bm = TerrainGenerator.CreateBridge(bcf, bdist)
			bm.Name = "Bridge_"..i
			
			claimPart = TerrainGenerator.CreateClaimPart(pm)
		end
		
		Plots[i] = { Index = i, Model = pm, Bridge = bm, Position = cf, Owner = nil, ClaimPart = claimPart }
	end
	
	print("✓ PlotManager Initialized (Generated "..CONFIG.MAX_PLAYERS.." plots)")
end

function PlotManager.FindAvailablePlot()
	for i, p in pairs(Plots) do if not p.Owner then return i end end
	return nil
end

function PlotManager.AssignPlot(player, idx)
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
	
	local PlayerLifecycleManager = rawget(Services, "PlayerLifecycleManager")
	if PlayerLifecycleManager then
		PlayerLifecycleManager.SetMapReady(player)
	end
	
	return pData.Model
end

function PlotManager.ClearPlot(player)
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

function PlotManager.GetPlayerPlot(player)
	local idx = PlayerToPlot[player]
	return idx and Plots[idx] and Plots[idx].Model
end

function PlotManager.GetAllPlots()
	return Plots
end

function PlotManager.TeleportPlayer(player)
	local idx = PlayerToPlot[player]
	if not idx then return end
	local pData = Plots[idx]
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	if hrp then hrp.CFrame = CFrame.new(pData.Model:GetPivot().Position + Vector3.new(0, 10, 0)) end
end

-- Tier Logic
local function getAvailableSide(tierData, isFirstExpansion)
	local avail = {}
	for side = 0, 3 do
		local blocked = (side == tierData.BlockedSide)
		local used = false
		for _, u in tierData.UsedSides do if u == side then used = true; break end end
		if not blocked and not used then table.insert(avail, side) end
	end
	if #avail == 0 then return nil end

	-- First expansion: always pick the side opposite the bridge (away from main island)
	if isFirstExpansion then
		local oppositeSide = (tierData.BlockedSide + 2) % 4
		for _, s in avail do
			if s == oppositeSide then return oppositeSide end
		end
	end

	return avail[math.random(1, #avail)]
end

function PlotManager.SpawnTierPlot(player, parentTier)
	local TerrainGenerator = rawget(Services, "TerrainGenerator")
	if not TerrainGenerator then return nil end

	local sys = PlayerTierSystems[player]
	local isFirstExpansion = sys and #sys.Tiers == 1

	local side = getAvailableSide(parentTier, isFirstExpansion)
	if not side then warn("No sides for tier " .. player.Name); return nil end
	
	if not sys then return nil end
	local nextIdx = #sys.Tiers + 1
	if nextIdx > TIER_CONFIG.MAX_TIERS then return nil end
	
	local parentCF = parentTier.Model:GetPivot()
	local offset = TIER_CONFIG.SIDE_OFFSETS[side]
	local hOff = math.random(TIER_CONFIG.TIER_HEIGHT_MIN, TIER_CONFIG.TIER_HEIGHT_MAX)
	local dist = math.random(TIER_CONFIG.TIER_DISTANCE_MIN, TIER_CONFIG.TIER_DISTANCE_MAX)
	
	local newPos = parentCF.Position + (offset * dist)
	newPos = Vector3.new(newPos.X, parentCF.Position.Y + hOff, newPos.Z)
	
	local newModel = TerrainGenerator.CreatePlotModel()
	newModel.Name = string.format("Plot_%d_Tier_%d", sys.BasePlotIndex, nextIdx)
	
	local lookDir = parentCF.Position - newPos
	local newCF = CFrame.new(newPos) * CFrame.Angles(0, math.atan2(lookDir.X, lookDir.Z), 0)
	newModel:PivotTo(newCF)
	newModel:SetAttribute("OwnerId", player.UserId)
	newModel:SetAttribute("TierIndex", nextIdx)
	newModel.Parent = PlotsFolder
	
	-- Stairs
	local pEdge = parentCF.Position + (offset * 40); pEdge = Vector3.new(pEdge.X, pEdge.Y + 2, pEdge.Z)
	local cEdge = newPos - (offset * 40); cEdge = Vector3.new(cEdge.X, cEdge.Y + 2, cEdge.Z)
	
	local stairs = TerrainGenerator.CreateStairs(pEdge, cEdge)
	stairs.Name = string.format("Stairs_%d_Tier_%d", sys.BasePlotIndex, nextIdx)
	
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

function PlotManager.RestoreTiers(player, count)
	local sys = PlayerTierSystems[player]
	if not sys or count <= 1 then return end
	print("Restoring tiers for "..player.Name)
	for i = 2, count do
		local cur = sys.Tiers[#sys.Tiers]
		if cur then 
			local new = PlotManager.SpawnTierPlot(player, cur)
			if new then sys.CurrentTier = new.TierIndex end
		end
	end
end

function PlotManager.GetPlayerTierSystem(player)
	return PlayerTierSystems[player]
end

-- ADD THIS LINE:
PlotManager.TIER_CONFIG = TIER_CONFIG

return PlotManager
