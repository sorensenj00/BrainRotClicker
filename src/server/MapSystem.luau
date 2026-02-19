--[[
	MapSystem Server Module
	(Formerly init.server.luau)
	
	Handles:
	1. Spawning the central MainIsland hub
	2. Generating 8 player plots in a circular formation
	3. Creating bridges connecting each plot to the hub
	4. Assigning plots to players
	5. Tier System (expanding plots)
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
	MODELS_PER_TIER = 16,
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

local MainIslandTemplate, BridgeTemplate
local Plots = {}
local PlayerToPlot = {}
local PlotsFolder
local PlayerTierSystems = {}

local MapSystem = {}
local Services = {}

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

--------------------------------------------------------------------------------
-- PROCEDURAL GENERATION
--------------------------------------------------------------------------------

local function generateUniquePlayerPlot()
	local rng = Random.new()
	local topDiameter = 120 
	local topY = 50 

	local model = Instance.new("Model")
	model.Name = "PlayerPlot_BridgeSafe"
	model.Parent = game.Workspace

	-- THE FIX: An invisible Root part to handle flawless orientation
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.CFrame = CFrame.new(0, topY, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.Parent = model
	model.PrimaryPart = root

	-- Folders to keep your Explorer clean
	local visualsFolder = Instance.new("Folder")
	visualsFolder.Name = "VisualDetails"
	visualsFolder.Parent = model

	local rockFolder = Instance.new("Folder")
	rockFolder.Name = "RockBase"
	rockFolder.Parent = model

	-- Randomize island base tone
	local themeVal = rng:NextInteger(1, 3)
	local baseR, baseG, baseB
	if themeVal == 1 then baseR, baseG, baseB = 120, 110, 100 -- Sandstone
	elseif themeVal == 2 then baseR, baseG, baseB = 90, 95, 110 -- Slate Blue
	else baseR, baseG, baseB = 80, 80, 80 end -- Dark Gray

	-- 1. Grass Top
	local grass = Instance.new("Part")
	grass.Name = "MainPlatform"
	grass.Shape = Enum.PartType.Cylinder
	grass.Size = Vector3.new(2, topDiameter, topDiameter)
	grass.CFrame = CFrame.new(0, topY, 0) * CFrame.Angles(0, 0, math.rad(90))
	grass.Material = Enum.Material.Grass
	grass.Color = Color3.fromRGB(91, 154, 76)
	grass.Anchored = true
	grass.Parent = model

	-- 2. Dirt Base 
	local dirt = Instance.new("Part")
	dirt.Name = "DirtBase"
	dirt.Shape = Enum.PartType.Cylinder
	dirt.Size = Vector3.new(3, topDiameter - 2, topDiameter - 2) 
	dirt.CFrame = CFrame.new(0, topY - 2.5, 0) * CFrame.Angles(0, 0, math.rad(90))
	dirt.Material = Enum.Material.Fabric
	dirt.Color = Color3.fromRGB(105, 64, 40)
	dirt.Anchored = true
	dirt.Parent = model

	-- 3. The Balanced Rock Cone (ANTI-CLIP MATH APPLIED)
	local depth = 45 
	local numRockLayers = 15
	local layerHeight = depth / numRockLayers
	local lastY = topY - 3

	for layer = 1, numRockLayers do
		local progress = layer / numRockLayers
		local curve = 1 - math.pow(progress, 1.5)
		local maxAllowedDiameter = (topDiameter - 6) * curve
		if maxAllowedDiameter < 5 then maxAllowedDiameter = 5 end

		local safeWidth = maxAllowedDiameter / 1.45 
		
		-- FIX: Push the entire cone down further from the grass
		lastY = topY - 5 - (layer * layerHeight)

		local darken = 1 - (progress * 0.6)
		local rColor = Color3.fromRGB(baseR * darken, baseG * darken, baseB * darken)

		-- Solid Core
		local core = Instance.new("Part")
		core.Shape = Enum.PartType.Cylinder
		core.Size = Vector3.new(layerHeight * 1.5, safeWidth * 1.3, safeWidth * 1.3)
		core.CFrame = CFrame.new(0, lastY, 0) * CFrame.Angles(0, 0, math.rad(90))
		core.Material = Enum.Material.Slate
		core.Color = rColor
		core.Anchored = true
		core.Parent = rockFolder

		-- Exterior jagged rocks
		local numRocks = rng:NextInteger(6, 9) 
		for r = 1, numRocks do
			local rock = Instance.new("Part")
			rock.Shape = Enum.PartType.Block
			
			-- FIX: Reduce the max height slightly to prevent tall spikes
			rock.Size = Vector3.new(safeWidth * rng:NextNumber(0.8, 1.1), layerHeight * rng:NextNumber(1.0, 1.6), safeWidth * rng:NextNumber(0.8, 1.1))
			
			-- FIX: Random offset is ONLY allowed to go down (-1.5 to 0), never up!
			rock.CFrame = CFrame.new(0, lastY + rng:NextNumber(-1.5, 0), 0) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.1, 0.1))
			
			rock.Material = Enum.Material.Slate
			rock.Color = rColor
			rock.Anchored = true
			rock.Parent = rockFolder
		end
	end

	-- 4. Overgrown Vines
	for v = 1, rng:NextInteger(5, 8) do
		local vine = Instance.new("Part")
		local vLength = rng:NextNumber(6, 14)
		vine.Size = Vector3.new(rng:NextNumber(0.8, 1.5), vLength, rng:NextNumber(0.8, 1.5))
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = (topDiameter / 2) - 2 
		local vx = math.cos(angle) * dist
		local vz = math.sin(angle) * dist
		vine.CFrame = CFrame.new(vx, topY - 2 - (vLength/2), vz) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1))
		vine.Material = Enum.Material.Grass
		vine.Color = Color3.fromRGB(70, 120, 55)
		vine.Anchored = true
		vine.Parent = visualsFolder
	end

	-- 5. Glowing Magic Core & Underglow Light
	local magicCore = Instance.new("Part")
	magicCore.Shape = Enum.PartType.Block
	magicCore.Size = Vector3.new(4, 6, 4)
	magicCore.CFrame = CFrame.new(0, lastY - 2, 0) * CFrame.Angles(rng:NextNumber(0,3), rng:NextNumber(0,3), rng:NextNumber(0,3))
	magicCore.Material = Enum.Material.Neon
	magicCore.Color = Color3.fromRGB(85, 255, 255)
	magicCore.Anchored = true
	magicCore.Parent = visualsFolder

	local coreLight = Instance.new("PointLight")
	coreLight.Color = Color3.fromRGB(85, 255, 255)
	coreLight.Range = 35
	coreLight.Brightness = 3
	coreLight.Parent = magicCore

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(Color3.fromRGB(85, 255, 255))
	particles.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)})
	particles.Lifetime = NumberRange.new(3, 6)
	particles.Rate = 20
	particles.Speed = NumberRange.new(2, 5)
	particles.EmissionDirection = Enum.NormalId.Bottom
	particles.Parent = magicCore

	-- 6. Floating Debris Halo
	for d = 1, rng:NextInteger(12, 18) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = (topDiameter / 2) * rng:NextNumber(1.05, 1.6) 
		local dx = math.cos(angle) * dist
		local dz = math.sin(angle) * dist
		
		-- FIX: Push debris start height further down (from 5 to 15) so rotated debris corners don't clip the grass
		local dy = topY - rng:NextNumber(15, 45) 
		
		local debris = Instance.new("Part")
		debris.Shape = Enum.PartType.Block
		local baseSize = rng:NextNumber(3, 9) 
		debris.Size = Vector3.new(baseSize * rng:NextNumber(0.6, 1.4), baseSize * rng:NextNumber(0.6, 1.4), baseSize * rng:NextNumber(0.6, 1.4))
		debris.CFrame = CFrame.new(dx, dy, dz) * CFrame.Angles(rng:NextNumber(0,3), rng:NextNumber(0,3), rng:NextNumber(0,3))
		debris.Material = Enum.Material.Slate
		debris.Color = Color3.fromRGB(baseR * 0.8, baseG * 0.8, baseB * 0.8)
		debris.Anchored = true
		debris.Parent = visualsFolder
	end

	-- 7. Visual Guide for 80x80 Build Area
	local plotGuide = Instance.new("Part")
	plotGuide.Name = "PlotBounds_80x80"
	plotGuide.Size = Vector3.new(80, 1, 80)
	plotGuide.CFrame = CFrame.new(0, topY + 1.5, 0) 
	plotGuide.Color = Color3.fromRGB(255, 0, 0)
	plotGuide.Transparency = 0.8
	plotGuide.Anchored = true
	plotGuide.CanCollide = false
	plotGuide.Parent = model

	return model
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
	
	local newModel = generateUniquePlayerPlot()
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
		local pm = generateUniquePlayerPlot(); pm.Name = "Plot_"..i; pm:PivotTo(cf); pm.Parent = PlotsFolder
		
		local bcf, bdist = calculateBridgeCFrame(cf)
		local bm = BridgeTemplate:Clone(); bm.Name = "Bridge_"..i
		for _, part in bm:GetDescendants() do if part:IsA("BasePart") then part.Size = Vector3.new(part.Size.X, part.Size.Y, bdist) end end
		bm:PivotTo(bcf); bm.Parent = workspace
		
		Plots[i] = { Index = i, Model = pm, Bridge = bm, Position = cf, Owner = nil, ClaimPart = createClaimPart(pm) }
		

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
	
	local PlayerLifecycleManager = rawget(Services, "PlayerLifecycleManager")
	if PlayerLifecycleManager then
		PlayerLifecycleManager.SetMapReady(player)
	end
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

function MapSystem.Init(services)
	print("   MapSystem (Module) - Initializing")
	Services = services or {}
	
	local models = ReplicatedStorage:FindFirstChild("Models")
	MainIslandTemplate = (models and models:FindFirstChild("MainIsland")) or ServerStorage:FindFirstChild("MainIsland") or ReplicatedStorage:FindFirstChild("MainIsland")

	BridgeTemplate = ServerStorage:FindFirstChild("Bridge") or ReplicatedStorage:FindFirstChild("Bridge")
	
	-- Placeholders
	if not MainIslandTemplate then
		local m = Instance.new("Model"); m.Name="MainIsland"; local p = Instance.new("Part"); p.Name="Island"; p.Size=Vector3.new(100,20,100); p.Anchored=true; p.Color=Color3.new(0,1,0); p.Parent=m; m.PrimaryPart=p; m.Parent=ServerStorage; MainIslandTemplate=m
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

MapSystem.GetPlayerPlot = function(p) local idx = PlayerToPlot[p]; return idx and Plots[idx] and Plots[idx].Model end
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
