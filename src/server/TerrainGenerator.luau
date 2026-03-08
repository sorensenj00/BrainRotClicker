--[[
	TerrainGenerator Server Module
	
	Responsibility: Pure procedural generation of map assets (Plots, Bridges, Stairs).
	Moved from MapSystem to adhere to SRP.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local TerrainGenerator = {}

-- Configs moved from MapSystem (Visual/Generation specific)
local GEN_CONFIG = {
	TIER_STAIR_WIDTH = 10,
	TIER_STAIR_HEIGHT = 3,
	BRIDGE_DECK_WIDTH = 16,
	BRIDGE_DECK_THICKNESS = 1.2,
	BRIDGE_SEGMENT_ARC_LENGTH = 12,
	BRIDGE_SEGMENT_OVERLAP = 1.25,
	BRIDGE_CURVE_FACTOR = 0.085,
	BRIDGE_CURVE_MIN = 14,
	BRIDGE_CURVE_MAX = 28,
	BRIDGE_TANGENT_FACTOR = 0.22,
	BRIDGE_TANGENT_MIN = 28,
	BRIDGE_TANGENT_MAX = 72,
	BRIDGE_CAP_LENGTH = 12,
	BRIDGE_ANCHOR_STRIP_LENGTH = 1,
	BRIDGE_SEAM_OVERLAP = 0.3,
	BRIDGE_CURB_WIDTH = 0.55,
	BRIDGE_CURB_HEIGHT = 0.8,
	BRIDGE_CURB_INSET = 0.45,
	BRIDGE_UNDERBEAM_HEIGHT = 0.8,
	BRIDGE_UNDERBEAM_WIDTH_SCALE = 0.72,
	BRIDGE_PLOT_DOCK_LOCAL = Vector3.new(50, 50.4, 0),
	BRIDGE_HUB_DOCK_INSET = 46,
	BRIDGE_HUB_DOCK_Y_OFFSET = 0,
	BRIDGE_SURFACE_CAST_HEIGHT = 120,
	BRIDGE_SURFACE_CAST_DEPTH = 260,
}

local BridgeTemplate
local MainIslandTemplate
local HFTTerminalTemplate -- [NEW] Reference for the terminal
local FulfillmentKioskTemplate
local DroneKioskTemplate
local TransportPadTemplate
local TransportKioskTemplate

local SPAWN_ADVANCED_STARTER_FEATURES = false

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
	FulfillmentKioskTemplate = models and models:FindFirstChild("Fulfillment_Kiosk")
	DroneKioskTemplate = models and models:FindFirstChild("Drone_kiosk")
	TransportPadTemplate = models and models:FindFirstChild("TransportPad")
	TransportKioskTemplate = models and models:FindFirstChild("Transport_Kiosk")
	
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

local function createHiddenMarker(name, cframe, parent, size)
	local marker = Instance.new("Part")
	marker.Name = name
	marker.Size = size or Vector3.new(1, 1, 1)
	marker.CFrame = cframe
	marker.Transparency = 1
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Parent = parent
	return marker
end

local function getHorizontalUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.001 then
		return nil
	end
	return flat.Unit
end

local function getSurfaceYForModel(model, worldPosition)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { model }

	local castHeight = GEN_CONFIG.BRIDGE_SURFACE_CAST_HEIGHT
	local origin = Vector3.new(worldPosition.X, worldPosition.Y + castHeight, worldPosition.Z)
	local direction = Vector3.new(0, -GEN_CONFIG.BRIDGE_SURFACE_CAST_DEPTH, 0)
	local rayResult = workspace:Raycast(origin, direction, rayParams)

	if rayResult then
		return rayResult.Position.Y
	end

	local fallbackY = model:GetPivot().Position.Y
	local _, boundsSize = model:GetBoundingBox()
	return fallbackY + (boundsSize.Y * 0.5)
end

local function cubicBezier(p0, p1, p2, p3, t)
	local invT = 1 - t
	return (invT ^ 3) * p0
		+ 3 * (invT ^ 2) * t * p1
		+ 3 * invT * (t ^ 2) * p2
		+ (t ^ 3) * p3
end

local function buildBridgePath(layout)
	local span = layout.PathEndPos - layout.PathStartPos
	local spanLength = span.Magnitude
	local sampleCount = math.max(12, math.ceil(spanLength / GEN_CONFIG.BRIDGE_SEGMENT_ARC_LENGTH))
	local tangentDistance = math.clamp(
		spanLength * GEN_CONFIG.BRIDGE_TANGENT_FACTOR,
		GEN_CONFIG.BRIDGE_TANGENT_MIN,
		GEN_CONFIG.BRIDGE_TANGENT_MAX
	)
	local curveMagnitude = math.clamp(
		spanLength * GEN_CONFIG.BRIDGE_CURVE_FACTOR,
		GEN_CONFIG.BRIDGE_CURVE_MIN,
		GEN_CONFIG.BRIDGE_CURVE_MAX
	) * (layout.CurveSign or 1)

	local startControl = layout.PathStartPos + (layout.StartTangent * tangentDistance)
	local endControl = layout.PathEndPos - (layout.EndTangent * tangentDistance)
	local points = table.create(sampleCount + 1)

	for index = 0, sampleCount do
		local alpha = index / sampleCount
		local basePoint = cubicBezier(layout.PathStartPos, startControl, endControl, layout.PathEndPos, alpha)
		local lateralOffset = layout.CurveNormal * (math.sin(alpha * math.pi) * curveMagnitude)
		points[index + 1] = basePoint + lateralOffset
	end

	return points
end

local function createBridgeDeckPart(name, size, cframe, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.Material = material
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

function TerrainGenerator.GetStarterBridgeLayout(mainIsland, plotModel, plotIndex)
	if not mainIsland or not plotModel then
		return nil
	end

	local plotDock = plotModel:FindFirstChild("BridgeDock", true)
	if not plotDock or not plotDock:IsA("BasePart") then
		warn("TerrainGenerator: Plot model is missing BridgeDock marker")
		return nil
	end

	local plotForward = getHorizontalUnit(plotDock.CFrame.LookVector)
	if not plotForward then
		return nil
	end

	local stripLength = GEN_CONFIG.BRIDGE_ANCHOR_STRIP_LENGTH
	local startSurfaceY = getSurfaceYForModel(plotModel, plotDock.Position)
	local startAnchorCenter = Vector3.new(
		plotDock.Position.X,
		startSurfaceY - (GEN_CONFIG.BRIDGE_DECK_THICKNESS * 0.5),
		plotDock.Position.Z
	)
	local startAnchorCFrame = CFrame.lookAt(startAnchorCenter, startAnchorCenter + plotForward, Vector3.yAxis)

	local hubCenter = mainIsland:GetPivot().Position
	local hubDirection = getHorizontalUnit(plotDock.Position - hubCenter) or plotForward
	local _, hubBounds = mainIsland:GetBoundingBox()
	local hubRadius = math.max(18, (math.max(hubBounds.X, hubBounds.Z) * 0.5) - GEN_CONFIG.BRIDGE_HUB_DOCK_INSET)
	local hubDockPos = hubCenter + (hubDirection * hubRadius)
	local hubSurfaceY = hubCenter.Y + GEN_CONFIG.BRIDGE_HUB_DOCK_Y_OFFSET
	local endAnchorCenter = Vector3.new(
		hubDockPos.X,
		hubSurfaceY - (GEN_CONFIG.BRIDGE_DECK_THICKNESS * 0.5),
		hubDockPos.Z
	)
	local endAnchorForward = getHorizontalUnit(hubCenter - endAnchorCenter) or plotForward
	local endAnchorCFrame = CFrame.lookAt(endAnchorCenter, endAnchorCenter + endAnchorForward, Vector3.yAxis)

	local startTangent = getHorizontalUnit(endAnchorCenter - startAnchorCenter) or plotForward
	local endTangent = endAnchorForward
	local curveNormal = Vector3.new(-startTangent.Z, 0, startTangent.X)

	if curveNormal.Magnitude < 0.001 then
		curveNormal = Vector3.new(0, 0, 1)
	else
		curveNormal = curveNormal.Unit
	end

	return {
		StartPos = startAnchorCenter,
		EndPos = endAnchorCenter,
		StartAnchorCFrame = startAnchorCFrame,
		EndAnchorCFrame = endAnchorCFrame,
		StartTangent = startTangent,
		EndTangent = endTangent,
		PathStartPos = startAnchorCenter + (startTangent * ((stripLength * 0.5) - GEN_CONFIG.BRIDGE_SEAM_OVERLAP)),
		PathEndPos = endAnchorCenter - (endTangent * ((stripLength * 0.5) - GEN_CONFIG.BRIDGE_SEAM_OVERLAP)),
		CurveNormal = curveNormal,
		CurveSign = (plotIndex % 2 == 0) and 1 or -1,
		DeckWidth = GEN_CONFIG.BRIDGE_DECK_WIDTH,
		DeckThickness = GEN_CONFIG.BRIDGE_DECK_THICKNESS,
		CapLength = stripLength,
	}
end

function TerrainGenerator.SpawnMainIsland(height)
	local mi = MainIslandTemplate:Clone()
	mi.Name = "MainIsland"
	mi:PivotTo(CFrame.new(0, height, 0))
	mi.Parent = workspace
	return mi
end

function TerrainGenerator.CreateBridge(layout)
	if not layout then
		return nil
	end

	local bridgeModel = Instance.new("Model")
	bridgeModel.Name = "Bridge"

	local points = buildBridgePath(layout)
	local deckWidth = layout.DeckWidth or GEN_CONFIG.BRIDGE_DECK_WIDTH
	local deckThickness = layout.DeckThickness or GEN_CONFIG.BRIDGE_DECK_THICKNESS
	local overlap = GEN_CONFIG.BRIDGE_SEGMENT_OVERLAP
	local deckColor = Color3.fromRGB(151, 104, 66)
	local accentColor = Color3.fromRGB(100, 67, 40)
	local curbCenterOffset = (deckWidth * 0.5) - GEN_CONFIG.BRIDGE_CURB_INSET
	local primaryPart

	for index = 1, #points - 1 do
		local fromPoint = points[index]
		local toPoint = points[index + 1]
		local segmentVector = toPoint - fromPoint
		local segmentLength = segmentVector.Magnitude

		if segmentLength > 0.05 then
			local direction = segmentVector.Unit
			local segmentCF = CFrame.lookAt((fromPoint + toPoint) * 0.5, toPoint, Vector3.yAxis)
			local deck = createBridgeDeckPart(
				string.format("Deck_%02d", index),
				Vector3.new(deckWidth, deckThickness, segmentLength + overlap),
				segmentCF,
				deckColor,
				Enum.Material.WoodPlanks,
				bridgeModel
			)

			if not primaryPart then
				primaryPart = deck
				bridgeModel.PrimaryPart = deck
			end

			CollectionService:AddTag(deck, "BridgeLane")

			local underBeam = createBridgeDeckPart(
				string.format("UnderBeam_%02d", index),
				Vector3.new(deckWidth * GEN_CONFIG.BRIDGE_UNDERBEAM_WIDTH_SCALE, GEN_CONFIG.BRIDGE_UNDERBEAM_HEIGHT, segmentLength),
				segmentCF * CFrame.new(0, -(deckThickness * 0.65), 0),
				accentColor,
				Enum.Material.Wood,
				bridgeModel
			)
			underBeam.CanCollide = false
			underBeam.CanQuery = false
			underBeam.CanTouch = false

			for _, sign in ipairs({ -1, 1 }) do
				local curbOffset = Vector3.new(sign * curbCenterOffset, (GEN_CONFIG.BRIDGE_CURB_HEIGHT - deckThickness) * 0.5, 0)
				createBridgeDeckPart(
					string.format("Curb_%02d_%s", index, sign < 0 and "L" or "R"),
					Vector3.new(GEN_CONFIG.BRIDGE_CURB_WIDTH, GEN_CONFIG.BRIDGE_CURB_HEIGHT, segmentLength + overlap * 0.5),
					segmentCF * CFrame.new(curbOffset),
					accentColor,
					Enum.Material.Wood,
					bridgeModel
				)
			end

			if index % 3 == 1 then
				local postHeight = 3.4
				for _, sign in ipairs({ -1, 1 }) do
					local postOffset = Vector3.new(sign * curbCenterOffset, (postHeight * 0.5) + 0.2, 0)
					local post = createBridgeDeckPart(
						string.format("Post_%02d_%s", index, sign < 0 and "L" or "R"),
						Vector3.new(0.45, postHeight, 0.45),
						segmentCF * CFrame.new(postOffset),
						Color3.fromRGB(86, 59, 39),
						Enum.Material.Wood,
						bridgeModel
					)
					post.CanCollide = false
					post.CanQuery = false
					post.CanTouch = false
				end
			end

			local laneCenter = (fromPoint + toPoint) * 0.5
			local laneMarker = createBridgeDeckPart(
				string.format("LaneStripe_%02d", index),
				Vector3.new(deckWidth * 0.08, 0.08, math.max(2, segmentLength * 0.55)),
				segmentCF * CFrame.new(0, (deckThickness * 0.5) + 0.04, 0),
				Color3.fromRGB(255, 223, 96),
				Enum.Material.Neon,
				bridgeModel
			)
			laneMarker.CanCollide = false
			laneMarker.CanQuery = false
			laneMarker.CanTouch = false

			local arrowMarker = createBridgeDeckPart(
				string.format("ArrowGuide_%02d", index),
				Vector3.new(deckWidth * 0.04, 0.08, 1.8),
				CFrame.lookAt(laneCenter + (direction * (segmentLength * 0.18)), toPoint, Vector3.yAxis)
					* CFrame.new(0, (deckThickness * 0.5) + 0.05, 0),
				Color3.fromRGB(255, 242, 169),
				Enum.Material.Neon,
				bridgeModel
			)
			arrowMarker.CanCollide = false
			arrowMarker.CanQuery = false
			arrowMarker.CanTouch = false
		end
	end

	local capLength = layout.CapLength or GEN_CONFIG.BRIDGE_ANCHOR_STRIP_LENGTH
	for _, capData in ipairs({
		{
			Name = "PlotCap",
			CFrame = layout.StartAnchorCFrame or CFrame.lookAt(layout.StartPos, layout.StartPos + layout.StartTangent, Vector3.yAxis),
			Hidden = true,
		},
		{
			Name = "HubCap",
			CFrame = layout.EndAnchorCFrame or CFrame.lookAt(layout.EndPos, layout.EndPos + layout.EndTangent, Vector3.yAxis),
		},
	}) do
		local cap = createBridgeDeckPart(
			capData.Name,
			Vector3.new(deckWidth + 1.5, deckThickness, capLength),
			capData.CFrame,
			Color3.fromRGB(171, 126, 80),
			Enum.Material.WoodPlanks,
			bridgeModel
		)
		CollectionService:AddTag(cap, "BridgeLane")
		if capData.Hidden then
			cap.Transparency = 1
		end
		if not primaryPart then
			primaryPart = cap
			bridgeModel.PrimaryPart = cap
		end
	end

	bridgeModel.Parent = workspace
	return bridgeModel
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

	createHiddenMarker(
		"BridgeDock",
		CFrame.lookAt(GEN_CONFIG.BRIDGE_PLOT_DOCK_LOCAL, GEN_CONFIG.BRIDGE_PLOT_DOCK_LOCAL + Vector3.new(1, 0, 0)),
		model,
		Vector3.new(GEN_CONFIG.BRIDGE_DECK_WIDTH + 1.5, 0.2, GEN_CONFIG.BRIDGE_ANCHOR_STRIP_LENGTH)
	)

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
	magicCore.Name = "MagicCore"
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

	-- 6. Floating Debris Halo (tagged for client-side animation)
	for d = 1, rng:NextInteger(12, 18) do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = (topDiameter / 2) * rng:NextNumber(1.05, 1.6) 
		local dx = math.cos(angle) * dist
		local dz = math.sin(angle) * dist
		local dy = topY - rng:NextNumber(15, 45) 
		
		local debris = Instance.new("Part")
		debris.Name = "FloatingDebris"
		debris.Shape = Enum.PartType.Block
		local baseSize = rng:NextNumber(3, 9) 
		debris.Size = Vector3.new(baseSize * rng:NextNumber(0.6, 1.4), baseSize * rng:NextNumber(0.6, 1.4), baseSize * rng:NextNumber(0.6, 1.4))
		debris.CFrame = CFrame.new(dx, dy, dz) * CFrame.Angles(rng:NextNumber(0,3), rng:NextNumber(0,3), rng:NextNumber(0,3))
		debris.Material = Enum.Material.Slate
		debris.Color = Color3.fromRGB(baseR * 0.8, baseG * 0.8, baseB * 0.8)
		debris.Anchored = true
		debris.CanCollide = false

		-- Store orbit metadata as attributes for the client animator
		debris:SetAttribute("OrbitAngle", angle)
		debris:SetAttribute("OrbitRadius", dist)
		debris:SetAttribute("OrbitHeight", dy)
		debris:SetAttribute("OrbitSpeed", rng:NextNumber(0.04, 0.12))
		debris:SetAttribute("WobbleSpeed", rng:NextNumber(0.5, 1.5))
		debris:SetAttribute("WobbleAmount", rng:NextNumber(3.0, 8.0))
		debris:SetAttribute("TumbleX", rng:NextNumber(-0.5, 0.5))
		debris:SetAttribute("TumbleY", rng:NextNumber(-0.5, 0.5))
		debris:SetAttribute("TumbleZ", rng:NextNumber(-0.5, 0.5))

		CollectionService:AddTag(debris, "FloatingDebris")
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
	if isStarterPlot and SPAWN_ADVANCED_STARTER_FEATURES and HFTTerminalTemplate then
		local terminal = HFTTerminalTemplate:Clone()
		
		-- Place it off to the side of the bridge connection
		-- Radius is 60. We position it at X=30, Z=-40 (near the edge)
		-- Angles(0, math.rad(-35), 0) turns it to face inward towards the center
		local termX = 30
		local termZ = -40
		local termY = topY + 5 -- Matches the surface height
		
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

	-- 9. Spawn Fulfillment Kiosk on Starter Plot Only
	if isStarterPlot and SPAWN_ADVANCED_STARTER_FEATURES and FulfillmentKioskTemplate then
		local kiosk = FulfillmentKioskTemplate:Clone()

		-- Bridge connection is on the +X edge of the plot.
		-- Place kiosk just behind that connection so it is near the bridge entrance.
		local kioskX = 50
		local kioskZ = -13
		local kioskY = topY + 1.3

		kiosk:PivotTo(CFrame.new(kioskX, kioskY, kioskZ) * CFrame.Angles(0, math.rad(-90), 0))
		kiosk.Parent = model

		-- Keep compatibility with existing client prompt listeners.
		for _, desc in kiosk:GetDescendants() do
			if desc:IsA("ProximityPrompt") and not CollectionService:HasTag(desc, "TransportCartPrompt") then
				CollectionService:AddTag(desc, "TransportCartPrompt")
			end
		end
	end

	-- 10. Spawn Drone Kiosk on starter plot opposite bridge side from storage kiosk
	if isStarterPlot and SPAWN_ADVANCED_STARTER_FEATURES and DroneKioskTemplate then
		local droneKiosk = DroneKioskTemplate:Clone()

		-- Fulfillment kiosk sits off the left side of the bridge approach.
		-- Drone kiosk mirrors it on the right side to keep the center lane clear.
		local kioskX = 50
		local kioskZ = 13
		local kioskY = topY + 1.3

		droneKiosk:PivotTo(CFrame.new(kioskX, kioskY, kioskZ) * CFrame.Angles(0, math.rad(-90), 0))
		droneKiosk.Parent = model

		local attachPart = droneKiosk.PrimaryPart or droneKiosk:FindFirstChildWhichIsA("BasePart", true)
		if attachPart then
			local prompt = attachPart:FindFirstChild("DroneKioskPrompt")
			if not prompt then
				prompt = Instance.new("ProximityPrompt")
				prompt.Name = "DroneKioskPrompt"
				prompt.ActionText = "Open Drone Ops"
				prompt.ObjectText = "Drone Kiosk"
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = 12
				prompt.Parent = attachPart
			end
		end
	end

	if isStarterPlot and SPAWN_ADVANCED_STARTER_FEATURES and TransportPadTemplate then
		local transportPad = TransportPadTemplate:Clone()
		transportPad.Name = "PlayerTransportPad"

		local padX = -48
		local padZ = 0
		local padY = topY + 2

		transportPad:PivotTo(CFrame.new(padX, padY, padZ) * CFrame.Angles(0, math.rad(90), 0))

		local spawnSource = transportPad:FindFirstChild("Spawn", true)
		if spawnSource and spawnSource:IsA("BasePart") then
			local runtimeSpawn = Instance.new("Part")
			runtimeSpawn.Name = "RuntimeSpawnMarker"
			runtimeSpawn.Anchored = true
			runtimeSpawn.CanCollide = false
			runtimeSpawn.CanQuery = false
			runtimeSpawn.CanTouch = false
			runtimeSpawn.Transparency = 1
			runtimeSpawn.Size = Vector3.new(1, 1, 1)
			runtimeSpawn.CFrame = spawnSource.CFrame
			runtimeSpawn.Parent = transportPad
		else
			warn("TerrainGenerator: TransportPad template is missing Spawn part")
		end

		transportPad.Parent = model
	end

	if isStarterPlot and SPAWN_ADVANCED_STARTER_FEATURES and TransportKioskTemplate then
		local transportKiosk = TransportKioskTemplate:Clone()
		transportKiosk.Name = "PlayerTransportKiosk"

		local kioskX = -42
		local kioskZ = -10
		local kioskY = topY + 1.3

		transportKiosk:PivotTo(CFrame.new(kioskX, kioskY, kioskZ) * CFrame.Angles(0, math.rad(55), 0))
		transportKiosk.Parent = model

		local attachPart = transportKiosk.PrimaryPart or transportKiosk:FindFirstChildWhichIsA("BasePart", true)
		if attachPart then
			local prompt = attachPart:FindFirstChild("PlayerTransportKioskPrompt")
			if not prompt then
				prompt = Instance.new("ProximityPrompt")
				prompt.Name = "PlayerTransportKioskPrompt"
				prompt.ActionText = "Open Transport Kiosk"
				prompt.ObjectText = "Transport Kiosk"
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = 12
				prompt.Parent = attachPart
			end
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
