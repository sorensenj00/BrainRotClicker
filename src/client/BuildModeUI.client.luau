--[[
	BuildModeUI Client Script (Refactored)
	
	"Architect Overlay" interface for placing and arranging brainrots.
	Follows SRP: Delegates 3D logic to subsystems.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

-- Helper Modules
local BuildGridVisualizer = require(script.Parent:WaitForChild("BuildGridVisualizer"))
local BuildInteractionService = require(script.Parent:WaitForChild("BuildInteractionService"))
local BuildCameraController = require(script.Parent:WaitForChild("BuildCameraController"))
local ViewportPreview = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ViewportPreview"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- Remotes
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local GetGrid = RemoteFunctions:WaitForChild("GetGrid")
local GetInventoryRemote = RemoteEvents:WaitForChild("GetInventory")
local PlaceBrainrotRemote = RemoteEvents:WaitForChild("PlaceBrainrot")
local MoveUnitRemote = RemoteFunctions:WaitForChild("MoveUnit")
local StashUnitRemote = RemoteFunctions:WaitForChild("StashUnit")

-- State
local isInBuildMode = false
local buildModeGui = nil
local inventoryPanel = nil
local inventoryPreviews = {}
local isRefreshingInventory = false
local lastDragStart = 0
local uiConnections = {}

local function cleanupConnections()
	for _, conn in ipairs(uiConnections) do
		conn:Disconnect()
	end
	uiConnections = {}
end

-- Config
local CONFIG = {
	THEME_BG = Color3.fromRGB(20, 20, 30),
	THEME_ACCENT_PURPLE = Color3.fromRGB(80, 60, 140),
	THEME_TEXT_PRIMARY = Color3.fromRGB(255, 255, 255),
	THEME_BUTTON_RADIUS = 6,
}

--------------------------------------------------------------------------------
-- UI GENERATION
--------------------------------------------------------------------------------

local function updateStatus(text)
	if buildModeGui and buildModeGui:FindFirstChild("BottomBar") then
		buildModeGui.BottomBar.Status.Text = text
	end
end

local function createBuildModeUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BuildModeUI"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 100
	
	-- Top Bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 50)
	topBar.BackgroundTransparency = 1
	topBar.Parent = screenGui
	
	local exitButton = Instance.new("TextButton")
	exitButton.Name = "ExitButton"
	exitButton.Size = UDim2.new(0, 90, 0, 36)
	exitButton.Position = UDim2.new(1, -105, 0.5, -18)
	exitButton.BackgroundColor3 = CONFIG.THEME_ACCENT_PURPLE
	exitButton.Text = "EXIT"
	exitButton.TextColor3 = CONFIG.THEME_TEXT_PRIMARY
	exitButton.Font = Enum.Font.GothamBold
	exitButton.TextSize = 14
	exitButton.Parent = topBar
	
	local uc = Instance.new("UICorner")
	uc.CornerRadius = UDim.new(0, CONFIG.THEME_BUTTON_RADIUS)
	uc.Parent = exitButton
	
	-- Status Bar
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(1, 0, 0, 36)
	bottomBar.Position = UDim2.new(0, 0, 1, -36)
	bottomBar.BackgroundTransparency = 1
	bottomBar.Parent = screenGui
	
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Size = UDim2.new(1, -40, 1, 0)
	statusLabel.Position = UDim2.new(0, 20, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "Build Mode Active"
	statusLabel.TextColor3 = CONFIG.THEME_TEXT_PRIMARY
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = bottomBar
	
	return screenGui, exitButton
end

local function getBrainrotModel(unitName)
	-- Look everywhere
	local paths = {
		ReplicatedStorage:FindFirstChild("Brainrots"),
		ReplicatedStorage:FindFirstChild("Units"),
		ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Brainrots")
	}
	for _, f in ipairs(paths) do
		if f and f:FindFirstChild(unitName) then return f[unitName] end
	end
	return nil
end

local function refreshInventory()
	if not inventoryPanel or isRefreshingInventory then return end
	isRefreshingInventory = true
	
	local scrollFrame = inventoryPanel:FindFirstChild("ItemsList")
	if scrollFrame then
		for _, child in scrollFrame:GetChildren() do
			if not child:IsA("UIListLayout") then child:Destroy() end
		end
		
		-- Fetch inventory
		local success, inv = pcall(function() return GetInventoryRemote:InvokeServer() end)
		if success and inv and inv.units then
			for unitName, unitData in pairs(inv.units) do
				if unitData.status == "stored" and (unitData.level or 0) > 0 then
					-- Create Card
					local card = Instance.new("Frame")
					card.Name = "Item_"..unitName
					card.Size = UDim2.new(1, 0, 0, 80)
					card.BackgroundColor3 = Color3.fromRGB(40,40,50)
					card.Parent = scrollFrame
					Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)
					
					-- Name
					local lbl = Instance.new("TextLabel")
					lbl.Text = unitName
					lbl.Size = UDim2.new(1, -70, 0, 20)
					lbl.Position = UDim2.new(0, 70, 0, 10)
					lbl.BackgroundTransparency = 1
					lbl.TextColor3 = CONFIG.THEME_TEXT_PRIMARY
					lbl.Font = Enum.Font.GothamBold
					lbl.TextXAlignment = Enum.TextXAlignment.Left
					lbl.Parent = card
					
					-- Drag Overlay
					local btn = Instance.new("TextButton")
					btn.Size = UDim2.new(1,0,1,0)
					btn.BackgroundTransparency = 1
					btn.Text = ""
					btn.Parent = card
					
					btn.MouseButton1Down:Connect(function()
						lastDragStart = tick() -- Record exactly when drag started
						BuildInteractionService.StartDrag(unitName, unitData.rarity)
					end)
					-- Preview
					local previewContainer = Instance.new("Frame")
					previewContainer.Size = UDim2.new(0, 60, 0, 60)
					previewContainer.Position = UDim2.new(0, 5, 0, 10)
					previewContainer.BackgroundColor3 = Color3.fromRGB(30,30,35)
					previewContainer.Parent = card
					Instance.new("UICorner", previewContainer).CornerRadius = UDim.new(0, 6)
					
					local model = getBrainrotModel(unitName)
					if model then
						ViewportPreview.Create(model, previewContainer)
					end
				end
			end
		end
	end
	
	isRefreshingInventory = false
end

local function createInventoryPanel(parent)
	local panel = Instance.new("Frame")
	panel.Name = "InventoryPanel"
	panel.Size = UDim2.new(0, 220, 1, -110)
	panel.Position = UDim2.new(0, 10, 0, 60)
	panel.BackgroundColor3 = CONFIG.THEME_BG
	panel.BackgroundTransparency = 0.1
	panel.Parent = parent
	
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(50,50,70)
	s.Thickness = 2
	s.Parent = panel
	
	local list = Instance.new("ScrollingFrame")
	list.Name = "ItemsList"
	list.Size = UDim2.new(1, -20, 1, -20)
	list.Position = UDim2.new(0, 10, 0, 10)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Parent = panel
	
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list
	
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
	end)
	
	inventoryPanel = panel
	return panel
end

--------------------------------------------------------------------------------
-- MAIN LOGIC
--------------------------------------------------------------------------------
local function exitBuildMode()
	if not isInBuildMode then return end
	isInBuildMode = false
	
	BuildCameraController.TweenToNormalMode()
	BuildGridVisualizer.Destroy()
	BuildInteractionService.CancelDrag()
	
	if buildModeGui then
		buildModeGui:Destroy()
		buildModeGui = nil
	end
	
	if cleanupConnections then cleanupConnections() end
end

local function enterBuildMode()
	if isInBuildMode then return end
	isInBuildMode = true
	
	-- 1. Initialize Visuals
	local gridState = GetGrid:InvokeServer()
	local plotPos = BuildGridVisualizer.Render(gridState)
	
	if not plotPos then
		warn("Could not find plot!")
		isInBuildMode = false
		return
	end
	
	-- 2. Camera
	BuildCameraController.TweenToBuildMode(plotPos)
	
	-- 3. UI
	local gui, exitBtn = createBuildModeUI()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	buildModeGui = gui
	
	createInventoryPanel(gui)
	refreshInventory()
	
	exitBtn.MouseButton1Click:Connect(exitBuildMode)
	
	-- 5. Cursor Logic (Dynamic UX)
	local GRAB_CURSOR = "rbxassetid://12465243883" -- Open hand
	local DRAGGING_CURSOR = "rbxassetid://12465244192" -- Closed hand
	local DEFAULT_CURSOR = ""
	
	table.insert(uiConnections, game:GetService("RunService").RenderStepped:Connect(function()
		if not isInBuildMode then 
			UserInputService.MouseIcon = DEFAULT_CURSOR
			return 
		end
		
		if BuildInteractionService.IsDragging() then
			UserInputService.MouseIcon = DRAGGING_CURSOR
		else
			local slot = BuildInteractionService.GetHoveredSlot()
			local tile = slot and BuildGridVisualizer.GetTile(slot)
			
			-- If we are hovering over an occupied tile, show the grab cursor!
			if tile and tile:GetAttribute("IsOccupied") then
				UserInputService.MouseIcon = GRAB_CURSOR
			else
				UserInputService.MouseIcon = DEFAULT_CURSOR
			end
		end
	end))

	-- Listeners
	table.insert(uiConnections, BuildInteractionService.StatusChanged:Connect(updateStatus))
	table.insert(uiConnections, BuildInteractionService.UnitDropped:Connect(function(unitName, rarity, slot)
		task.spawn(function()
			local success, msg = PlaceBrainrotRemote:InvokeServer(unitName, rarity, slot)
			if success then
				updateStatus("✓ Placed " .. unitName)
				-- Refresh grid
				local newState = GetGrid:InvokeServer()
				local newPos = BuildGridVisualizer.Render(newState)
				-- Refresh inventory
				refreshInventory()
			else
				updateStatus("✗ " .. (msg or "Placement failed"))
			end
		end)
	end))
	
	table.insert(uiConnections, BuildInteractionService.UnitMoved:Connect(function(fromSlot, toSlot)
		-- OPTIMISTIC UPDATE: Instantly change the tiles locally so it feels incredibly fast
		local fromTile = BuildGridVisualizer.GetTile(fromSlot)
		local toTile = BuildGridVisualizer.GetTile(toSlot)
		
		local unitName = fromTile:GetAttribute("UnitName")
		
		-- Locally update attributes immediately
		fromTile:SetAttribute("IsOccupied", false)
		fromTile:SetAttribute("UnitName", nil)
		BuildGridVisualizer.Unhighlight(fromSlot) -- Refresh visual state
		
		toTile:SetAttribute("IsOccupied", true)
		toTile:SetAttribute("UnitName", unitName)
		BuildGridVisualizer.Unhighlight(toSlot) -- Refresh visual state
		
		updateStatus("✓ Moved") -- Optimistic success message
		
		-- Now tell the server in the background
		task.spawn(function()
			local success, msg = MoveUnitRemote:InvokeServer(fromSlot, toSlot)
			if not success then
				-- Only if the server rejects it (e.g., hacker, or lag), we fetch the real grid to fix it
				warn("Server rejected move:", msg)
				updateStatus("✗ " .. (msg or "Move failed"))
				local newState = GetGrid:InvokeServer()
				BuildGridVisualizer.Render(newState)
			else
				-- Server confirmed, we are good. 
				-- Maybe play a sound here?
			end
		end)
	end))
end


-- Connect to Toggle Event from HUD
local BuildToggleEvent = ReplicatedStorage:WaitForChild("BuildModeToggleEvent", 2)
if not BuildToggleEvent then
	-- Create if it doesn't exist (fallback if HUD loads later, though HUD usually creates it)
	BuildToggleEvent = Instance.new("BindableEvent")
	BuildToggleEvent.Name = "BuildModeToggleEvent"
	BuildToggleEvent.Parent = ReplicatedStorage
end

BuildToggleEvent.Event:Connect(function()
	if isInBuildMode then
		exitBuildMode()
	else
		enterBuildMode()
	end
end)



local function isMouseOverGui(guiObject)
	if not guiObject then return false end
	local mouse = UserInputService:GetMouseLocation()
	local pos = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	return mouse.X >= pos.X and mouse.X <= pos.X + size.X and
	       mouse.Y >= pos.Y and mouse.Y <= pos.Y + size.Y
end

local function handleDrop()
	if isMouseOverGui(inventoryPanel) then
		local fromSlot = BuildInteractionService.GetDraggedFromSlot()
		if fromSlot then
			local success = StashUnitRemote:InvokeServer(fromSlot)
			if success then
				updateStatus("✓ Stashed to Inventory")
				BuildInteractionService.Stop()
				local newState = GetGrid:InvokeServer()
				BuildGridVisualizer.Render(newState)
				refreshInventory()
			end
		else
			updateStatus("Cancelled placement")
			BuildInteractionService.CancelDrag()
		end
	else
		BuildInteractionService.CompleteDrag()
	end
end

-- Wire up exit button (re-find it since we created it in enter)
UserInputService.InputBegan:Connect(function(input, processed)
	if isInBuildMode and input.UserInputType == Enum.UserInputType.MouseButton1 then
		if BuildInteractionService.IsDragging() then
			-- If they just started dragging milliseconds ago, ignore this click (fixes the instant cancel bug)
			if tick() - lastDragStart < 0.2 then
				return 
			end
			handleDrop()
			return
		end
	end

	if processed then return end
	
	if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.G then
		if isInBuildMode then exitBuildMode() else enterBuildMode() end
	end
	
	if input.KeyCode == Enum.KeyCode.R and isInBuildMode and BuildInteractionService.IsDragging() then
		-- Tell the Interaction Service to rotate
		BuildInteractionService.RotateGhost()
	end
	
	if isInBuildMode then
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if not BuildInteractionService.IsDragging() then
				local slot = BuildInteractionService.GetHoveredSlot()
				if slot then
					local tile = BuildGridVisualizer.GetTile(slot)
					if tile and tile:GetAttribute("IsOccupied") then
						local unitName = tile:GetAttribute("UnitName")
						local rarity = "Normal"
						
						lastDragStart = tick() -- Record pick up time
						BuildInteractionService.StartDragFromSlot(slot, unitName, rarity)
					end
				end
			end
		end
		
		if input.KeyCode == Enum.KeyCode.Escape then
			if BuildInteractionService.IsDragging() then
				BuildInteractionService.CancelDrag()
			else
				exitBuildMode()
			end
		end
	end
end)

-- ADD this new InputEnded event to fully support hold-to-drag and drop:
UserInputService.InputEnded:Connect(function(input, processed)
	if isInBuildMode and input.UserInputType == Enum.UserInputType.MouseButton1 then
		if BuildInteractionService.IsDragging() then
			-- If user held the button to drag, releasing it should complete the drop
			if tick() - lastDragStart > 0.2 then
				handleDrop()
			end
		end
	end
end)

-- Handle Exit Button created dynamically
-- We need to connect it after creation.
-- Instead of complex wiring, let's just check in input or define exit globally.
-- The local function exitBuildMode is defined above.
-- Re-injecting the connection into enterBuildMode:
-- See enterBuildMode above.
-- ...
-- exitBtn.MouseButton1Click:Connect(exitBuildMode) -- Fix this line in actual code
