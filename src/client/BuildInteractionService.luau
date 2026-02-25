--[[
	BuildInteractionService Client Module
	
	Responsibility: Handling Input (Mouse/Touch), Raycasting, and Drag-and-Drop state.
	Coordinates with BuildGridVisualizer.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildGridVisualizer = require(script.Parent.BuildGridVisualizer)
local ClientPlotService = require(script.Parent:WaitForChild("ClientPlotService"))

local BuildInteractionService = {}
export type BuildInteractionService = {
	StartDrag: (string, string) -> (),
	StartDragFromSlot: (number, string, string) -> (),
	CompleteDrag: () -> (),
	Stop: () -> (),
	CancelDrag: () -> (),
	IsDragging: () -> boolean,
	GetHoveredSlot: () -> number?,
	GetDraggedFromSlot: () -> number?,
	StatusChanged: RBXScriptSignal,
	UnitDropped: RBXScriptSignal,
	UnitMoved: RBXScriptSignal,
}


-- Events
local StatusChanged = Instance.new("BindableEvent")
BuildInteractionService.StatusChanged = StatusChanged.Event

local UnitDropped = Instance.new("BindableEvent")
BuildInteractionService.UnitDropped = UnitDropped.Event

-- Config
local CONFIG = {
	DRAG_HEIGHT = 4.0,
	DRAG_SMOOTHNESS = 20.0,
	TILT_STRENGTH = 0.3,
	TILT_RETURN_SPEED = 10.0,
	MAX_TILT_ANGLE = 25,
	
	HOVER_COLOR = Color3.fromRGB(100, 200, 255),
	INVALID_COLOR = Color3.fromRGB(255, 80, 80),
	VALID_GHOST_COLOR = Color3.fromRGB(100, 255, 100),
	INVALID_GHOST_COLOR = Color3.fromRGB(255, 80, 80),
}

-- State
local isDragging = false
local draggedUnit = nil
local placementGhost = nil
local dragConnection = nil
local isGhostValid = false
local ghostCenterOffset = Vector3.new()
local currentHoverSlot = nil
local currentRotation = 0

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getPlayerPlot()
	return ClientPlotService.GetMyPlot()
end

local function getMousePlanePosition(floorHeight)
	local camera = workspace.CurrentCamera -- ADD THIS HERE
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	
	local normal = Vector3.new(0, 1, 0)
	local p0 = Vector3.new(0, floorHeight, 0)
	
	local denominator = ray.Direction:Dot(normal)
	
	if math.abs(denominator) > 0.001 then
		local t = (p0 - ray.Origin):Dot(normal) / denominator
		if t > 0 then
			return ray.Origin + ray.Direction * t
		end
	end
	return nil
end

local function getSlotUnderMouse()
	local camera = workspace.CurrentCamera
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	
	local tilesMap = BuildGridVisualizer.GetSlotUnderMouse() 
	local filterList = {}
	for _, tile in pairs(tilesMap) do table.insert(filterList, tile) end
	
	local plot = getPlayerPlot()
	if plot then
		-- Fallback to look for units generally, in case they aren't in a 'Brainrots' folder
		local brainrots = plot:FindFirstChild("Brainrots") or plot:FindFirstChild("Units")
		if brainrots then
			table.insert(filterList, brainrots)
		else
			-- If no folder, insert everything in plot so raycast hits the units
			for _, child in plot:GetChildren() do
				if child:IsA("Model") then table.insert(filterList, child) end
			end
		end
	end
	
	params.FilterDescendantsInstances = filterList
	
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if result and result.Instance then
		-- 1. Check if we hit a Grid Tile directly
		local slot = result.Instance:GetAttribute("SlotIndex")
		if slot then return slot end
		
		-- 2. Check if we hit a Unit Model
		local model = result.Instance:FindFirstAncestorWhichIsA("Model")
		if model then
			slot = model:GetAttribute("GridSlot")
			if slot then return slot end
			
			-- FALLBACK: If the unit model is missing the attribute, find which tile is physically closest to it!
			local modelPos = model:GetPivot().Position
			local closestSlot = nil
			local minDist = math.huge
			for index, tile in pairs(tilesMap) do
				local tilePos = tile.Position
				-- Ignore Y axis to calculate pure ground distance
				local dist = Vector2.new(tilePos.X - modelPos.X, tilePos.Z - modelPos.Z).Magnitude
				if dist < minDist and dist < 10 then 
					minDist = dist
					closestSlot = index
				end
			end
			return closestSlot
		end
	end
	return nil
end

local originalModelStates = {}

local function setModelTransparency(model, isHidden)
	if not model then return end
	
	if isHidden then
		originalModelStates = {} -- Clear old cache
		for _, child in model:GetDescendants() do
			if child:IsA("BasePart") or child:IsA("Decal") or child:IsA("Texture") then
				originalModelStates[child] = child.Transparency
				child.Transparency = 1
			elseif child:IsA("ParticleEmitter") or child:IsA("Trail") or child:IsA("Beam") or child:IsA("Highlight") then
				originalModelStates[child] = child.Enabled
				child.Enabled = false
			end
		end
	else
		-- Restore all original transparencies and particle states
		for child, originalValue in pairs(originalModelStates) do
			if child and child.Parent then
				if child:IsA("BasePart") or child:IsA("Decal") or child:IsA("Texture") then
					child.Transparency = originalValue
				elseif child:IsA("ParticleEmitter") or child:IsA("Trail") or child:IsA("Beam") or child:IsA("Highlight") then
					child.Enabled = originalValue
				end
			end
		end
		originalModelStates = {}
	end
end

local function setModelColor(model, color)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then part.Color = color end
	end
	local highlight = model:FindFirstChildWhichIsA("Highlight")
	if highlight then
		highlight.FillColor = color
		highlight.OutlineColor = color
	end
end

local function createGhost(unitName)
	local ghost
	
	-- Logic to find model (ReplicatedStorage lookups)
	-- For simplicity, reproducing the logic from BuildModeUI
	-- Should ideally be in a shared asset manager
	local function findModel(name)
		local paths = {
			ReplicatedStorage:FindFirstChild("Brainrots"),
			ReplicatedStorage:FindFirstChild("Units"),
			ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Brainrots")
		}
		for _, folder in ipairs(paths) do
			if folder and folder:FindFirstChild(name) then return folder[name] end
		end
		return nil
	end
	
	local original = findModel(unitName)
	if original then
		ghost = original:Clone()
		local cf, _ = original:GetBoundingBox()
		ghostCenterOffset = original:GetPivot().Position - cf.Position
	else
		-- Fallback
		ghost = Instance.new("Model")
		local p = Instance.new("Part")
		p.Size = Vector3.new(3,5,3); p.Anchored=true; p.Parent=ghost; ghost.PrimaryPart=p
		ghostCenterOffset = Vector3.new()
	end
	
	-- Cleanup scripts/humanoids
	for _, item in ghost:GetDescendants() do
		if item:IsA("Script") or item:IsA("Humanoid") or item:IsA("Sound") or item:IsA("ParticleEmitter") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			item.CanCollide = false
			item.Anchored = true
			if item:IsA("MeshPart") then
				item.Material = Enum.Material.ForceField
			else
				item.Transparency = 1 
			end
		end
	end
	
	ghost.Name = "PlacementGhost"
	ghost.Parent = workspace
	return ghost
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

local draggedFromSlot = nil
local originalUnitModel = nil

-- New Event
local UnitMoved = Instance.new("BindableEvent")
BuildInteractionService.UnitMoved = UnitMoved.Event

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

-- (getPlayerPlot is already defined above)

-- ... (Existing helpers: getMousePlanePosition, getSlotUnderMouse, setModelTransparency, setModelColor, createGhost) ...

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function BuildInteractionService.StartDrag(unitName, rarity)
	if isDragging then return end
	isDragging = true
	draggedUnit = {name = unitName, rarity = rarity}
	draggedFromSlot = nil -- New placement
	currentRotation = 0
	
	local floorHeight = BuildGridVisualizer.GetGridFloorHeight()
	local startPos = getMousePlanePosition(floorHeight) or Vector3.new(0, floorHeight, 0)
	local currentPos = startPos
	local currentTilt = CFrame.new()
	
	placementGhost = createGhost(unitName)
	placementGhost:PivotTo(CFrame.new(startPos + Vector3.new(0, CONFIG.DRAG_HEIGHT, 0) + ghostCenterOffset))
	
	StatusChanged:Fire("🎯 Release to place " .. unitName)
	
	dragConnection = RunService.RenderStepped:Connect(function(dt)
		if not isDragging then return end
		
		-- Physics Drag
		local rawMouse = getMousePlanePosition(floorHeight)
		if not rawMouse then return end
		local targetPos = rawMouse + Vector3.new(0, CONFIG.DRAG_HEIGHT, 0)
		
		local lerp = math.clamp(dt * CONFIG.DRAG_SMOOTHNESS, 0, 1)
		local newPos = currentPos:Lerp(targetPos, lerp)
		
		-- Tilt
		local vel = (newPos - currentPos) / dt
		currentPos = newPos
		local tiltAxis = vel:Cross(Vector3.yAxis)
		local speed = vel.Magnitude
		local targetRot = CFrame.new()
		if speed > 0.1 and tiltAxis.Magnitude > 0.01 then
			targetRot = CFrame.fromAxisAngle(tiltAxis.Unit, -math.rad(math.clamp(speed * CONFIG.TILT_STRENGTH, -CONFIG.MAX_TILT_ANGLE, CONFIG.MAX_TILT_ANGLE)))
		end
		currentTilt = currentTilt:Lerp(targetRot, dt * CONFIG.TILT_RETURN_SPEED)
		
		if placementGhost then
			placementGhost:PivotTo(CFrame.new(currentPos + ghostCenterOffset) * currentTilt)
		end
		
		-- Grid Interaction
		local slot = getSlotUnderMouse()
		
		if currentHoverSlot and currentHoverSlot ~= slot then
			BuildGridVisualizer.Unhighlight(currentHoverSlot)
		end
		currentHoverSlot = slot
		
		if slot then
			local tile = BuildGridVisualizer.GetTile(slot)
			local isOccupied = tile and tile:GetAttribute("IsOccupied")
			
			-- If moving, it's ok to hover over the slot we came from (it's effectively empty)
			if isOccupied and (not draggedFromSlot or slot ~= draggedFromSlot) then
				setModelColor(placementGhost, CONFIG.INVALID_GHOST_COLOR)
				BuildGridVisualizer.Highlight(slot, CONFIG.INVALID_COLOR)
				isGhostValid = false
				
				-- Still conform to tilt if invalid? Maybe keep it loose.
				if placementGhost then
					placementGhost:PivotTo(CFrame.new(currentPos + ghostCenterOffset) * currentTilt * CFrame.Angles(0, math.rad(currentRotation), 0))
				end
			else
				setModelColor(placementGhost, CONFIG.VALID_GHOST_COLOR)
				BuildGridVisualizer.Highlight(slot, CONFIG.HOVER_COLOR)
				isGhostValid = true
				
				-- SNAP TO GRID: If hovering over a valid slot, snap directly to the tile's center
				if tile then
					-- Keep the ghost at ground level, but centered exactly on the tile
					local snapPos = tile.Position + Vector3.new(0, ghostCenterOffset.Y, 0)
					placementGhost:PivotTo(CFrame.new(snapPos) * CFrame.Angles(0, math.rad(currentRotation), 0)) 
				end
			end
		else
			isGhostValid = false
			setModelColor(placementGhost, CONFIG.INVALID_GHOST_COLOR)
			-- SMOOTH FOLLOW: If not hovering over a valid grid slot, follow the mouse smoothly with the tilt effect
			if placementGhost then
				placementGhost:PivotTo(CFrame.new(currentPos + ghostCenterOffset) * currentTilt * CFrame.Angles(0, math.rad(currentRotation), 0))
			end
		end
	end)
end

function BuildInteractionService.RotateGhost()
	currentRotation = (currentRotation + 90) % 360
end

function BuildInteractionService.StartDragFromSlot(slotIndex, unitName, rarity)
	if isDragging then return end
	
	-- Hide existing model so it doesn't duplicate visually while dragging
	local plot = getPlayerPlot()
	if plot then
		local brainrots = plot:FindFirstChild("Brainrots") or plot:FindFirstChild("Units")
		local searchFolder = brainrots and brainrots:GetChildren() or plot:GetChildren()
		
		for _, child in searchFolder do
			if child:IsA("Model") then
				local childSlot = child:GetAttribute("GridSlot")
				
				-- Fallback if attribute is missing
				if not childSlot then
					local tile = BuildGridVisualizer.GetTile(slotIndex)
					if tile then
						local tilePos = tile.Position
						local childPos = child:GetPivot().Position
						local dist = Vector2.new(tilePos.X - childPos.X, tilePos.Z - childPos.Z).Magnitude
						if dist < 5 then -- Model is standing on this tile
							childSlot = slotIndex
						end
					end
				end
				
				if childSlot == slotIndex then
					originalUnitModel = child
					setModelTransparency(child, true) -- Hide it using the new logic
					break
				end
			end
		end
	end
	
	BuildInteractionService.StartDrag(unitName, rarity)
	
	-- Polish: Make drag ghost match original model scale
	if originalUnitModel and placementGhost then
		placementGhost:ScaleTo(originalUnitModel:GetScale())
	end
	
	draggedFromSlot = slotIndex
	StatusChanged:Fire("🎯 Moving " .. unitName)
end

function BuildInteractionService.CompleteDrag()
	if not isDragging then return end
	
	local slot = getSlotUnderMouse()
	if slot and isGhostValid then
		if draggedFromSlot then
			if slot == draggedFromSlot then
				-- Moved to same slot = Cancel
				BuildInteractionService.CancelDrag()
			else
				UnitMoved:Fire(draggedFromSlot, slot)
				-- Don't cancel yet, wait for UI/Server to confirm?
				-- Actually we should probably cleanup local state now, 
				-- assuming server will update grid and trigger redraw.
				draggedFromSlot = nil -- Prevent CancelDrag from unhiding old model, since server will move it
				if originalUnitModel then
					-- Keep hidden until grid refresh destroys/moves it
					-- Actually, visual refresh will destroy old tiles/grid.
					originalUnitModel = nil
				end
				BuildInteractionService.Stop()
			end
		else
			UnitDropped:Fire(draggedUnit.name, draggedUnit.rarity, slot)
			BuildInteractionService.Stop()
		end
	else
		StatusChanged:Fire("Drag cancelled")
		BuildInteractionService.CancelDrag()
	end
end

function BuildInteractionService.Stop()
	isDragging = false
	draggedUnit = nil
	draggedFromSlot = nil
	
	-- Unhide the real model immediately when drag stops
	if originalUnitModel then
		setModelTransparency(originalUnitModel, false) 
		originalUnitModel = nil
	end
	
	if dragConnection then dragConnection:Disconnect() end
	if placementGhost then placementGhost:Destroy() end
	placementGhost = nil
	if currentHoverSlot then BuildGridVisualizer.Unhighlight(currentHoverSlot) end
	currentHoverSlot = nil
end

-- Replace CancelDrag with this (Stop handles the unhiding now):
function BuildInteractionService.CancelDrag()
	BuildInteractionService.Stop()
end

function BuildInteractionService.IsDragging()
	return isDragging
end

function BuildInteractionService.GetHoveredSlot()
	return getSlotUnderMouse()
end

function BuildInteractionService.GetDraggedFromSlot()
	return draggedFromSlot
end

return BuildInteractionService
