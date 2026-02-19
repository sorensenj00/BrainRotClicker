--[[
	BuildInteractionService Client Module
	
	Responsibility: Handling Input (Mouse/Touch), Raycasting, and Drag-and-Drop state.
	Coordinates with BuildGridVisualizer.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local BuildGridVisualizer = require(script.Parent.BuildGridVisualizer)

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

local camera = workspace.CurrentCamera

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getPlayerPlot()
	local player = Players.LocalPlayer
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end
	for _, p in plots:GetChildren() do
		if p:GetAttribute("OwnerId") == player.UserId then return p end
	end
	return nil
end

local function getMousePlanePosition(floorHeight)
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
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	
	-- Raycast against tiles AND units
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	
	local tilesMap = BuildGridVisualizer.GetSlotUnderMouse() -- Is actually a table of tiles
	local filterList = {}
	for _, tile in pairs(tilesMap) do table.insert(filterList, tile) end
	
	-- Add Brainrots folder to filter so we can click on units to select them
	local plot = getPlayerPlot()
	if plot then
		local brainrots = plot:FindFirstChild("Brainrots")
		if brainrots then
			table.insert(filterList, brainrots)
		end
	end
	
	params.FilterDescendantsInstances = filterList
	
	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if result and result.Instance then
		-- 1. Check if it's a tile
		local slot = result.Instance:GetAttribute("SlotIndex")
		if slot then return slot end
		
		-- 2. Check if it's a unit part (find model ancestor)
		local model = result.Instance:FindFirstAncestorWhichIsA("Model")
		if model then
			slot = model:GetAttribute("GridSlot")
			if slot then return slot end
		end
	end
	return nil
end

local function setModelTransparency(model, transparency)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then part.Transparency = transparency end
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

local function getPlayerPlot()
	local player = Players.LocalPlayer
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end
	for _, p in plots:GetChildren() do
		if p:GetAttribute("OwnerId") == player.UserId then return p end
	end
	return nil
end

-- ... (Existing helpers: getMousePlanePosition, getSlotUnderMouse, setModelTransparency, setModelColor, createGhost) ...

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function BuildInteractionService.StartDrag(unitName, rarity)
	if isDragging then return end
	isDragging = true
	draggedUnit = {name = unitName, rarity = rarity}
	draggedFromSlot = nil -- New placement
	
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
			else
				setModelColor(placementGhost, CONFIG.VALID_GHOST_COLOR)
				BuildGridVisualizer.Highlight(slot, CONFIG.HOVER_COLOR)
				isGhostValid = true
			end
		else
			isGhostValid = false
			setModelColor(placementGhost, CONFIG.INVALID_GHOST_COLOR)
		end
	end)
end

function BuildInteractionService.StartDragFromSlot(slotIndex, unitName, rarity)
	if isDragging then return end
	
	-- Hide existing model
	local plot = getPlayerPlot()
	if plot then
		local brainrots = plot:FindFirstChild("Brainrots")
		if brainrots then
			for _, child in brainrots:GetChildren() do
				if child:GetAttribute("GridSlot") == slotIndex then
					originalUnitModel = child
					setModelTransparency(child, 1) -- Hide
					-- Also hide overheads if any? 
					-- BaseParts transparency should handle visual model.
					break
				end
			end
		end
	end
	
	BuildInteractionService.StartDrag(unitName, rarity)
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
	originalUnitModel = nil
	if dragConnection then dragConnection:Disconnect() end
	if placementGhost then placementGhost:Destroy() end
	placementGhost = nil
	if currentHoverSlot then BuildGridVisualizer.Unhighlight(currentHoverSlot) end
	currentHoverSlot = nil
end

function BuildInteractionService.CancelDrag()
	if originalUnitModel then
		setModelTransparency(originalUnitModel, 0) -- Restore visibility
	end
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
