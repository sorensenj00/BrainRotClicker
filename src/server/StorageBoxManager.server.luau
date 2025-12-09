--[[
	StorageBoxManager Server Script
	
	Creates a visual storage box on each player's plot.
	Brainrots shoot their produce (via ProjectileVisuals) into this storage.
	
	The storage box is positioned at the center of the plot.
]]

-- Services
local Players = game:GetService("Players")

-- Configuration
local STORAGE_CONFIG = {
	-- Box appearance
	SIZE = Vector3.new(8, 6, 8),
	COLOR = Color3.fromRGB(80, 140, 200),
	MATERIAL = Enum.Material.SmoothPlastic,
	TRANSPARENCY = 0.2,
	
	-- Position (relative to plot center)
	OFFSET_Y = 3, -- Height above plot surface
}

--------------------------------------------------------------------------------
-- STORAGE CREATION
--------------------------------------------------------------------------------

--[[
	Finds the player's plot.
]]
local function findPlayerPlot(player)
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	
	for _, plot in plotsFolder:GetChildren() do
		if plot:GetAttribute("OwnerId") == player.UserId then
			return plot
		end
	end
	
	return nil
end

--[[
	Gets the plot floor/island part.
]]
local function getPlotFloor(plot)
	return plot:FindFirstChild("Island") 
		or plot:FindFirstChild("PlotFloor") 
		or plot:FindFirstChild("Floor")
		or plot:FindFirstChildWhichIsA("BasePart")
end

--[[
	Creates a storage box on the player's plot.
]]
local function createStorageBox(player)
	local plot = findPlayerPlot(player)
	if not plot then 
		warn("StorageBoxManager: No plot found for " .. player.Name)
		return nil
	end
	
	-- Check if storage already exists
	local existingStorage = plot:FindFirstChild("Storage")
	if existingStorage then
		return existingStorage
	end
	
	local floor = getPlotFloor(plot)
	if not floor then
		warn("StorageBoxManager: No floor found for " .. player.Name)
		return nil
	end
	
	-- Calculate position (center of plot, on top)
	local floorPos = floor.Position
	local floorSize = floor.Size
	local storageY = floorPos.Y + (floorSize.Y / 2) + STORAGE_CONFIG.OFFSET_Y + (STORAGE_CONFIG.SIZE.Y / 2)
	
	-- Create storage box
	local storage = Instance.new("Part")
	storage.Name = "Storage"
	storage.Size = STORAGE_CONFIG.SIZE
	storage.Position = Vector3.new(floorPos.X, storageY, floorPos.Z)
	storage.Anchored = true
	storage.CanCollide = false
	storage.Color = STORAGE_CONFIG.COLOR
	storage.Material = STORAGE_CONFIG.MATERIAL
	storage.Transparency = STORAGE_CONFIG.TRANSPARENCY
	
	-- Add a subtle glow
	local pointLight = Instance.new("PointLight")
	pointLight.Color = STORAGE_CONFIG.COLOR
	pointLight.Range = 15
	pointLight.Brightness = 0.3
	pointLight.Parent = storage
	
	-- Add label
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StorageLabel"
	billboard.Size = UDim2.new(0, 100, 0, 30)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = storage
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "📦 STORAGE"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = billboard
	
	storage.Parent = plot
	
	print("StorageBoxManager: Created storage for " .. player.Name)
	return storage
end

--[[
	Removes the storage box when player leaves (optional cleanup).
]]
local function removeStorageBox(player)
	local plot = findPlayerPlot(player)
	if plot then
		local storage = plot:FindFirstChild("Storage")
		if storage then
			storage:Destroy()
		end
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

-- Create storage for existing players
for _, player in Players:GetPlayers() do
	task.defer(function()
		-- Wait a bit for plot to be assigned
		task.wait(1)
		createStorageBox(player)
	end)
end

-- Create storage when new players join
Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		-- Wait for plot assignment
		task.wait(2)
		createStorageBox(player)
	end)
end)

-- Cleanup on player leave (optional)
-- Players.PlayerRemoving:Connect(removeStorageBox)

-- Export API
_G.StorageBoxManager = {
	CreateStorage = createStorageBox,
	RemoveStorage = removeStorageBox,
}

print("✓ StorageBoxManager initialized")
