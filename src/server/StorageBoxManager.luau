--[[
	StorageBoxManager Server Module
	
	Creates a visual storage box on each player's plot.
	
	CONVERTED TO MODULE SCRIPT
]]

local Players = game:GetService("Players")

local STORAGE_CONFIG = {
	SIZE = Vector3.new(8, 6, 8),
	COLOR = Color3.fromRGB(80, 140, 200),
	MATERIAL = Enum.Material.SmoothPlastic,
	TRANSPARENCY = 0.2,
	OFFSET_Y = 3,
}

local StorageBoxManager = {}

--------------------------------------------------------------------------------
-- STORAGE LOGIC
--------------------------------------------------------------------------------

local function createStorageBox(player)
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	
	local plot
	for _, p in plotsFolder:GetChildren() do
		if p:GetAttribute("OwnerId") == player.UserId then plot = p; break end
	end
	if not plot then return nil end
	
	if plot:FindFirstChild("Storage") then return plot:FindFirstChild("Storage") end
	
	local floor = plot:FindFirstChild("Island") or plot:FindFirstChildWhichIsA("BasePart")
	if not floor then return nil end
	
	local fp = floor.Position
	local fs = floor.Size
	local sy = fp.Y + (fs.Y / 2) + STORAGE_CONFIG.OFFSET_Y + (STORAGE_CONFIG.SIZE.Y / 2)
	
	local storage = Instance.new("Part")
	storage.Name = "Storage"
	storage.Size = STORAGE_CONFIG.SIZE
	storage.Position = Vector3.new(fp.X, sy, fp.Z)
	storage.Anchored = true
	storage.CanCollide = false
	storage.Color = STORAGE_CONFIG.COLOR
	storage.Material = STORAGE_CONFIG.MATERIAL
	storage.Transparency = STORAGE_CONFIG.TRANSPARENCY
	storage.Parent = plot
	
	local pl = Instance.new("PointLight"); pl.Color = STORAGE_CONFIG.COLOR; pl.Range = 15; pl.Brightness = 0.3; pl.Parent = storage
	
	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0,100,0,30); bb.StudsOffset = Vector3.new(0,4,0); bb.Parent = storage
	local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1; lbl.Text = "📦 STORAGE"; lbl.TextColor3 = Color3.new(1,1,1); lbl.TextScaled = true; lbl.Parent = bb
	
	return storage
end

local function removeStorageBox(player)
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return end
	for _, plot in plotsFolder:GetChildren() do
		if plot:GetAttribute("OwnerId") == player.UserId then
			local s = plot:FindFirstChild("Storage")
			if s then s:Destroy() end
			break
		end
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function StorageBoxManager.Init()
	print("   StorageBoxManager (Module) - Initializing")
	
	for _, player in Players:GetPlayers() do
		task.defer(function()
			task.wait(1)
			createStorageBox(player)
		end)
	end
	
	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			task.wait(2)
			createStorageBox(player)
		end)
	end)
	
	print("✓ StorageBoxManager Initialized")
end

StorageBoxManager.CreateStorage = createStorageBox
StorageBoxManager.RemoveStorage = removeStorageBox

return StorageBoxManager
