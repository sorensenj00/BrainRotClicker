--[[
	TerrainGenerator Server Module
	
	Responsibility: Pure procedural generation of map assets (Plots, Bridges, Stairs).
	Moved from MapSystem to adhere to SRP.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TerrainGenerator = {}

-- Configs moved from MapSystem (Visual/Generation specific)
local GEN_CONFIG = {
	TIER_STAIR_WIDTH = 10,
	TIER_STAIR_HEIGHT = 3,
}

local BridgeTemplate
local MainIslandTemplate
local HFTTerminalTemplate -- [NEW] Reference for the terminal

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function TerrainGenerator.Init()
	print("   TerrainGenerator (Module) - Initializing")
	
	local models = ReplicatedStorage:FindFirstChild("Models")
	MainIslandTemplate = (models and models:FindFirstChild("MainIsland")) or ServerStorage:FindFirstChild("MainIsland") or ReplicatedStorage:FindFirstChild("MainIsland")
	BridgeTemplate = ServerStorage:FindFirstChild("Bridge") or ReplicatedStorage:FindFirstChild("Bridge")
	
	-- [NEW] Load the HFT Terminal from ReplicatedStorage.Models
	HFTTerminalTemplate = models and models:FindFirstChild("Plot_HFT_Terminal")
	
	-- Placeholders if missing
	if not MainIslandTemplate then
		local m = Instance.new("Model"); m.Name="MainIsland"; local p = Instance.new("Part"); p.Name="Island"; p.Size=Vector3.new(100,20,100); p.Anchored=true; p.Color=Color3.new(0,1,0); p.Parent=m; m.PrimaryPart=p; m.Parent=ServerStorage; MainIslandTemplate=m
	end

	if not BridgeTemplate then
		local m = Instance.new("Model"); m.Name="Bridge"; local p = Instance.new("Part"); p.Name="BridgePart"; p.Size=Vector3.new(10,2,50); p.Anchored=true; p.Color=Color3.new(0.6,0.4,0.2); p.Parent=m; m.PrimaryPart=p; m.Parent=ServerStorage; BridgeTemplate=m
	end
	
	print("✓ TerrainGenerator Initialized")
end

--------------------------------------------------------------------------------
-- GENERATION FUNCTIONS
--------------------------------------------------------------------------------

function TerrainGenerator.SpawnMainIsland(height)
	local mi = MainIslandTemplate:Clone()
	mi.Name = "MainIsland"
	mi:PivotTo(CFrame.new(0, height, 0))
	mi.Parent = workspace
	return mi
end

function TerrainGenerator.CreateBridge(cframe, dist)
	local bm = BridgeTemplate:Clone()
	bm.Name = "Bridge"
	for _, part in bm:GetDescendants() do 
		if part:IsA("BasePart") then 
			part.Size = Vector3.new(part.Size.X, part.Size.Y, dist) 
		end 
	end
	bm:PivotTo(cframe)
	bm.Parent = workspace
	return bm
end

function TerrainGenerator.CreateClaimPart(model)
	local p = Instance.new("Part")
	p.Name = "ClaimPart"; p.Size = Vector3.new(10, 1, 10); p.BrickColor = BrickColor.new("Lime green")
	p.Transparency = 1; p.Anchored = true; p.CanCollide = false
	p.Position = model:GetPivot().Position + Vector3.new(0, 3, 0)
	p.Parent = model
	return p
end

-- Formerly generateUniquePlayerPlot
-- [NEW] Added isStarterPlot parameter
function TerrainGenerator.CreatePlotModel(isStarterPlot)
	local rng = Random.new()
	local topDiameter = 120 
	local topY = 50 

	local model = Instance.new("Model")
	model.Name = "PlayerPlot_BridgeSafe"
	model.Parent = game.Workspace

	-- An invisible Root part to handle flawless orientation
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.CFrame = CFrame.new(0, topY, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.Parent = model
	model.PrimaryPart = root

	-- Folders
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

	-- 3. The Balanced Rock Cone
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
			rock.Size = Vector3.new(safeWidth * rng:NextNumber(0.8, 1.1), layerHeight * rng:NextNumber(1.0, 1.6), safeWidth * rng:NextNumber(0.8, 1.1))
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
		local vLength = rng:NextNumber(15, 70)
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
	plotGuide.Size = Vector3.new(80, 0, 80)
	plotGuide.CFrame = CFrame.new(0, topY + 1.5, 0) 
	plotGuide.Color = Color3.fromRGB(255, 0, 0)
	plotGuide.Transparency = 1
	plotGuide.Anchored = true
	plotGuide.CanCollide = false
	plotGuide.Parent = model

	-- =========================================================
	-- [NEW] 8. Spawn HFT Terminal on Starter Plot Only
	-- =========================================================
	if isStarterPlot and HFTTerminalTemplate then
		local terminal = HFTTerminalTemplate:Clone()
		
		-- Place it off to the side of the bridge connection
		-- Radius is 60. We position it at X=30, Z=-40 (near the edge)
		-- Angles(0, math.rad(-35), 0) turns it to face inward towards the center
		local termX = 30
		local termZ = -40
		local termY = topY + 1.5 -- Matches the surface height
		
		terminal:PivotTo(CFrame.new(termX, termY, termZ) * CFrame.Angles(0, math.rad(-35), 0))
		terminal.Parent = model
		
		local attachPart = terminal.PrimaryPart or terminal:FindFirstChildWhichIsA("BasePart", true)
		if attachPart then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "HFTTerminalPrompt"
			prompt.ActionText = "Open Terminal"
			prompt.ObjectText = "HFT Terminal"
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = 12
			prompt.Parent = attachPart
		end
	end

	return model
end

function TerrainGenerator.CreateStairs(startPos, endPos)
	local stairs = Instance.new("Model")
	
	local vDist = endPos.Y - startPos.Y
	local hDist = (Vector3.new(endPos.X, 0, endPos.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude
	
	local steps = math.max(1, math.floor(vDist / GEN_CONFIG.TIER_STAIR_HEIGHT))
	local sH = vDist / steps; local sD = hDist / steps
	local dir = (Vector3.new(endPos.X, 0, endPos.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Unit
	
	for i = 0, steps - 1 do
		local s = Instance.new("Part")
		s.Name = "Step_"..i
		s.Size = Vector3.new(GEN_CONFIG.TIER_STAIR_WIDTH, math.max(0.5, sH), math.max(0.5, sD))
		s.Anchored = true; s.CanCollide = true; s.Material = Enum.Material.Concrete
		s.Position = Vector3.new(startPos.X + dir.X*(i+0.5)*sD, startPos.Y + (i+0.5)*sH, startPos.Z + dir.Z*(i+0.5)*sD)
		s.CFrame = CFrame.new(s.Position) * CFrame.Angles(0, math.atan2(dir.X, dir.Z), 0)
		s.Parent = stairs
	end
	if stairs:FindFirstChild("Step_0") then stairs.PrimaryPart = stairs.Step_0 end
	stairs.Parent = workspace
	
	return stairs
end

return TerrainGenerator
