--[[
	BuildModeUI Client Script
	
	"Architect Overlay" interface for placing and arranging brainrots.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridConfig = require(Shared:WaitForChild("GridConfig"))
local ViewportPreview = require(Shared:WaitForChild("ViewportPreview"))

-- Assets
local BrainrotsFolder = ReplicatedStorage:WaitForChild("Brainrots")

-- Remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")

local EnterBuildMode = RemoteFunctions:WaitForChild("EnterBuildMode")
local ExitBuildMode = RemoteFunctions:WaitForChild("ExitBuildMode")
local GetGrid = RemoteFunctions:WaitForChild("GetGrid")
local MoveUnit = RemoteFunctions:WaitForChild("MoveUnit")
local SwapUnits = RemoteFunctions:WaitForChild("SwapUnits")
local GetInventoryRemote = RemoteEvents:WaitForChild("GetInventory")
local PlaceBrainrotRemote = RemoteEvents:WaitForChild("PlaceBrainrot")
local RemoveBrainrotRemote = RemoteEvents:WaitForChild("RemoveBrainrot")

-- Local State
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local state = {
	active = false,
	dragging = false,
	dragData = nil, -- {name, rarity, fromSlot, originalModel}
	gui = nil,
	gridFolder = nil,
	tiles = {},
	ghost = nil,
	savedCamCF = nil
}

-- Config Local Overrides
local CAM_HEIGHT = 60
local CAM_ANGLE = 45

--------------------------------------------------------------------------------
-- UTILS
--------------------------------------------------------------------------------

local function updateStatus(text)
	if state.gui and state.gui:FindFirstChild("BottomBar") and state.gui.BottomBar:FindFirstChild("Status") then
		state.gui.BottomBar.Status.Text = text
	end
end

local function getPlotInfo()
	-- Find player's plot floor
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end
	
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerId") == LocalPlayer.UserId then
			local floor = plot:FindFirstChild("Island") or plot:FindFirstChild("PlotFloor")
				or plot:FindFirstChild("Floor") or plot:FindFirstChildWhichIsA("BasePart")
			
			if floor and floor:IsA("BasePart") then
				return floor.Position, floor.Size
			elseif plot:IsA("Model") then
				local cf, size = plot:GetBoundingBox()
				return cf.Position, size
			end
			return plot:IsA("BasePart") and plot.Position, plot:IsA("BasePart") and plot.Size
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- GRID VISUALS
--------------------------------------------------------------------------------

local function createTile(slot, pos, occupied, unitName)
	local tile = Instance.new("Part")
	tile.Name = "Tile_" .. slot
	tile.Size = Vector3.new(GridConfig.TILE_SIZE - 0.5, 0.1, GridConfig.TILE_SIZE - 0.5)
	tile.Position = pos
	tile.Anchored = true
	tile.CanCollide = false
	tile.Transparency = 1
	tile:SetAttribute("Slot", slot)
	tile:SetAttribute("Occupied", occupied)
	
	local box = Instance.new("SelectionBox", tile)
	box.Adornee = tile
	box.Color3 = occupied and GridConfig.COLORS.OCCUPIED or GridConfig.COLORS.EMPTY
	box.LineThickness = 0.03
	box.Transparency = 0.3
	
	if not occupied then
		local bb = Instance.new("BillboardGui", tile)
		bb.Size = UDim2.new(1,0,0.5,0)
		bb.StudsOffset = Vector3.new(0,0.5,0)
		local lbl = Instance.new("TextLabel", bb)
		lbl.Size = UDim2.fromScale(1,1)
		lbl.BackgroundTransparency = 1
		lbl.Text = tostring(slot)
		lbl.TextColor3 = Color3.fromRGB(150,150,150)
		lbl.TextScaled = true
		lbl.Font = Enum.Font.Gotham
	end
	return tile
end

local function renderGrid()
	local gridData = GetGrid:InvokeServer() or {slots={}}
	local center, size = getPlotInfo()
	if not center then return end
	
	if state.gridFolder then state.gridFolder:Destroy() end
	state.gridFolder = Instance.new("Folder", workspace)
	state.tiles = {}
	
	local plotTopY = center.Y + (size.Y/2) + 0.5
	
	for slotIndex = 1, 16 do -- Hardcoded to 16 for visual simplicity or use config
		local xOff, zOff = GridConfig.GetSlotOffset(slotIndex, size.X, size.Z)
		local pos = Vector3.new(center.X + xOff, plotTopY, center.Z + zOff)
		
		local unitName = gridData.slots["1"] and gridData.slots["1"][tostring(slotIndex)] -- Support nested tier 1
		if not unitName then -- Support legacy flat structure
			unitName = gridData.slots[tostring(slotIndex)] or gridData.slots[slotIndex]
		end

		local tile = createTile(slotIndex, pos, unitName ~= nil, unitName)
		tile.Parent = state.gridFolder
		state.tiles[slotIndex] = tile
	end
	
	return Vector3.new(center.X, plotTopY, center.Z) -- Return center for camera
end

--------------------------------------------------------------------------------
-- GHOST & DRAG
--------------------------------------------------------------------------------

local function createGhost(unitName)
	if state.ghost then state.ghost:Destroy() end
	
	-- Try to find model in Brainrots folder first
	local model = BrainrotsFolder:FindFirstChild(unitName)

	-- Fallback to Units folder if it exists
	if not model then
		local unitsFolder = ReplicatedStorage:FindFirstChild("Units")
		if unitsFolder then
			model = unitsFolder:FindFirstChild(unitName)
		end
	end

	local ghost = model and model:Clone() or Instance.new("Model")
	
	if not model then
		local p = Instance.new("Part", ghost)
		p.Size = Vector3.new(3,5,3)
		ghost.PrimaryPart = p
	end
	
	for _, p in ghost:GetDescendants() do
		if p:IsA("BasePart") then
			p.Transparency = 0.5
			p.Color = GridConfig.COLORS.HOVER
			p.CanCollide = false
			p.Anchored = true
		end
	end
	
	ghost.Parent = workspace
	state.ghost = ghost
end

local function getSlotUnderMouse()
	if not state.gridFolder then return nil end
	local mouse = LocalPlayer:GetMouse()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local res = workspace:Raycast(ray.Origin, ray.Direction * 1000, RaycastParams.new())
	
	if res and res.Instance and res.Instance:IsDescendantOf(state.gridFolder) then
		return res.Instance:GetAttribute("Slot") or res.Instance.Parent:GetAttribute("Slot")
	end
	return nil
end

local function updateDrag()
	if not state.dragging then return end
	
	local slot = getSlotUnderMouse()
	if slot and state.tiles[slot] then
		local tile = state.tiles[slot]
		local occupied = tile:GetAttribute("Occupied")

		-- Update ghost position
		if state.ghost then
			state.ghost:PivotTo(CFrame.new(tile.Position + Vector3.new(0,2,0)))
			-- Color logic
			local valid = not occupied or (state.dragData.fromSlot and state.dragData.fromSlot ~= slot) -- Swap valid
			for _, p in state.ghost:GetDescendants() do
				if p:IsA("BasePart") then p.Color = valid and GridConfig.COLORS.HOVER or GridConfig.COLORS.INVALID end
			end
		end
	end
end

local function startDrag(name, rarity, fromSlot, originalModel)
	if state.dragging then return end
	state.dragging = true
	state.dragData = {name = name, rarity = rarity, fromSlot = fromSlot, originalModel = originalModel}

	createGhost(name)
	updateStatus("Drag to " .. (fromSlot and "move/swap" or "place"))
	
	if originalModel then
		for _, p in originalModel:GetDescendants() do if p:IsA("BasePart") then p.Transparency = 1 end end
	end
end

local function endDrag()
	if not state.dragging then return end
	
	local slot = getSlotUnderMouse()
	local data = state.dragData
	
	-- Restore original model
	if data.originalModel then
		for _, p in data.originalModel:GetDescendants() do if p:IsA("BasePart") then p.Transparency = 0 end end
	end
	
	if slot then
		local tile = state.tiles[slot]
		local occupied = tile:GetAttribute("Occupied")
		
		if data.fromSlot then
			-- Move/Swap (Tier 1 fixed for now)
			if slot ~= data.fromSlot then
				if occupied then
					SwapUnits:InvokeServer(1, data.fromSlot, slot)
				else
					MoveUnit:InvokeServer(1, data.fromSlot, slot)
				end
			end
		else
			-- Place from Inventory
			if not occupied then
				PlaceBrainrotRemote:InvokeServer(data.name, data.rarity, slot)
			else
				updateStatus("Slot occupied!")
			end
		end
		task.wait(0.1)
		renderGrid()
		-- Refresh inventory if needed (handled by events generally)
	end
	
	state.dragging = false
	state.dragData = nil
	if state.ghost then state.ghost:Destroy() state.ghost = nil end
	updateStatus("Ready")
end

--------------------------------------------------------------------------------
-- UI CONSTRUCTION
--------------------------------------------------------------------------------

local function createInvCard(parent, unit, rarity, count, active)
	local frame = Instance.new("Frame", parent)
	frame.BackgroundColor3 = Color3.fromRGB(40,40,50)
	frame.Size = UDim2.new(1,0,0,50)
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0,6)
	
	local name = Instance.new("TextLabel", frame)
	name.Text = unit .. " (" .. rarity .. ")"
	name.TextColor3 = Color3.new(1,1,1)
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0,10,0,5)
	name.Size = UDim2.new(1,-10,0,20)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Font = Enum.Font.GothamBold
	name.TextSize = 12
	
	local status = Instance.new("TextLabel", frame)
	status.Text = "Stored: " .. count .. " | Active: " .. active
	status.TextColor3 = Color3.fromRGB(150,150,150)
	status.BackgroundTransparency = 1
	status.Position = UDim2.new(0,10,0,25)
	status.Size = UDim2.new(1,-10,0,15)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Font = Enum.Font.Gotham
	status.TextSize = 10
	
	local btn = Instance.new("TextButton", frame)
	btn.Text = "Place"
	btn.Size = UDim2.new(0,50,0,30)
	btn.Position = UDim2.new(1,-60,0.5,-15)
	btn.BackgroundColor3 = Color3.fromRGB(60,180,60)
	Instance.new("UICorner", btn)
	
	btn.MouseButton1Down:Connect(function()
		if count > 0 then startDrag(unit, rarity) end
	end)
	
	return frame
end

local function refreshInventory(scroll)
	for _, c in scroll:GetChildren() do if c:IsA("Frame") then c:Destroy() end end
	
	local data = GetInventoryRemote:InvokeServer()
	if not data or not data.units then return end
	
	local y = 0
	for name, rarities in pairs(data.units) do
		for rarity, info in pairs(rarities) do
			if info.total > 0 then
				local stored = info.total - info.active
				createInvCard(scroll, name, rarity, stored, info.active).Position = UDim2.new(0,0,0,y)
				y += 55
			end
		end
	end
	scroll.CanvasSize = UDim2.new(0,0,0,y)
end

local function createUI()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildModeUI"
	gui.ResetOnSpawn = false
	
	-- Top Bar
	local top = Instance.new("Frame", gui)
	top.Name = "TopBar"
	top.Size = UDim2.new(1,0,0,50)
	top.BackgroundColor3 = Color3.fromRGB(30,30,40)
	
	local title = Instance.new("TextLabel", top)
	title.Text = "🏗️ BUILD MODE"
	title.TextColor3 = Color3.new(1,0.8,0.2)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 24
	title.Size = UDim2.fromScale(0.5, 1)
	title.Position = UDim2.new(0,20,0,0)
	title.BackgroundTransparency = 1
	title.TextXAlignment = Enum.TextXAlignment.Left
	
	local exitBtn = Instance.new("TextButton", top)
	exitBtn.Name = "ExitButton"
	exitBtn.Text = "EXIT"
	exitBtn.BackgroundColor3 = Color3.fromRGB(200,60,60)
	exitBtn.Size = UDim2.new(0,80,0,30)
	exitBtn.Position = UDim2.new(1,-100,0.5,-15)
	Instance.new("UICorner", exitBtn)
	
	-- Inventory
	local inv = Instance.new("Frame", gui)
	inv.Name = "Inventory"
	inv.Size = UDim2.new(0,250,1,-120)
	inv.Position = UDim2.new(0,10,0,60)
	inv.BackgroundColor3 = Color3.fromRGB(30,30,40)
	Instance.new("UICorner", inv)
	
	local scroll = Instance.new("ScrollingFrame", inv)
	scroll.Size = UDim2.new(1,-20,1,-20)
	scroll.Position = UDim2.new(0,10,0,10)
	scroll.BackgroundTransparency = 1
	scroll.ScrollBarThickness = 4
	
	-- Bottom Status
	local bot = Instance.new("Frame", gui)
	bot.Name = "BottomBar"
	bot.Size = UDim2.new(1,0,0,40)
	bot.Position = UDim2.fromScale(0,1)
	bot.AnchorPoint = Vector2.new(0,1)
	bot.BackgroundColor3 = Color3.fromRGB(30,30,40)
	
	local status = Instance.new("TextLabel", bot)
	status.Name = "Status"
	status.Size = UDim2.new(1,-40,1,0)
	status.Position = UDim2.new(0,20,0,0)
	status.BackgroundTransparency = 1
	status.TextColor3 = Color3.new(0.8,0.8,0.8)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Font = Enum.Font.Gotham
	status.Text = "Ready"
	
	-- Events
	exitBtn.MouseButton1Click:Connect(function()
		ExitBuildMode:InvokeServer()
		-- Toggle logic handled by state check
	end)
	
	refreshInventory(scroll)
	
	-- Expose update function
	gui:SetAttribute("RefreshInv", true)
	
	return gui
end

--------------------------------------------------------------------------------
-- MAIN LOGIC
--------------------------------------------------------------------------------

local function toggleBuildMode(forceState)
	if forceState == state.active then return end
	
	if forceState then
		-- Enter
		local success = EnterBuildMode:InvokeServer()
		if not success then return end
		state.active = true

		-- Cam
		state.savedCamCF = camera.CFrame
		local center = renderGrid()
		if center then
			camera.CameraType = Enum.CameraType.Scriptable
			local rad = math.rad(CAM_ANGLE)
			local dist = CAM_HEIGHT / math.sin(rad)
			local pos = center + Vector3.new(0, CAM_HEIGHT, dist * math.cos(rad))
			TweenService:Create(camera, TweenInfo.new(0.5), {CFrame = CFrame.new(pos, center)}):Play()
		end
		
		state.gui = createUI()
		state.gui.Parent = PlayerGui

		-- Bind input
		RunService:BindToRenderStep("BuildModeDrag", Enum.RenderPriority.Input.Value, updateDrag)

	else
		-- Exit
		ExitBuildMode:InvokeServer()
		state.active = false
		
		if state.gui then state.gui:Destroy() end
		if state.gridFolder then state.gridFolder:Destroy() end
		if state.ghost then state.ghost:Destroy() end
		
		-- Cam
		if state.savedCamCF then
			local t = TweenService:Create(camera, TweenInfo.new(0.5), {CFrame = state.savedCamCF})
			t:Play()
			t.Completed:Once(function() camera.CameraType = Enum.CameraType.Custom end)
		end

		RunService:UnbindFromRenderStep("BuildModeDrag")
	end
end

-- Input
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.G or input.KeyCode == Enum.KeyCode.Tab then
		toggleBuildMode(not state.active)
	end
end)

local mouse = LocalPlayer:GetMouse()
mouse.Button1Down:Connect(function()
	if not state.active or state.dragging then return end
	
	-- Check world click
	local slot = getSlotUnderMouse()
	if slot then
		local tile = state.tiles[slot]
		if tile:GetAttribute("Occupied") then
			-- Find model
			local brainrot
			for _, b in CollectionService:GetTagged("ActiveBrainrot") do
				if b:GetAttribute("GridSlot") == slot and b:GetAttribute("OwnerId") == LocalPlayer.UserId then
					brainrot = b
					break
				end
			end
			if brainrot then
				startDrag(brainrot.Name, brainrot:GetAttribute("Rarity"), slot, brainrot)
			end
		end
	end
end)

mouse.Button1Up:Connect(function()
	if state.dragging then endDrag() end
end)

-- Remote Listeners
RemoteEvents.WaitForChild("BuildModeChanged").OnClientEvent:Connect(function(uid, active)
	if uid == LocalPlayer.UserId then
		toggleBuildMode(active)
	end
end)

RemoteEvents.WaitForChild("GridUpdated").OnClientEvent:Connect(function()
	if state.active then
		renderGrid()
		-- Refresh inventory
		if state.gui then
			refreshInventory(state.gui.Inventory.ScrollingFrame)
		end
	end
end)

print("✓ BuildModeUI Loaded")
