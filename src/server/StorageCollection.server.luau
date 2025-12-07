--[[
	StorageCollection Server Script
	
	Handles the Storage collection system on player plots.
	- Creates ProximityPrompt on Storage parts when plots are assigned
	- Transfers CurrentStorage to leaderstats.Money when collected
	- Plays cash register sound and disables overflow smoke
]]

-- Services
local Players = game:GetService("Players")
local _ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Configuration
local COLLECTION_CONFIG = {
	HOLD_DURATION = 0.5,
	MAX_ACTIVATION_DISTANCE = 10,
	CASH_REGISTER_SOUND_ID = "rbxassetid://138081500", -- Cash register
}

-- Wait for BrainrotManager API
local function waitForBrainrotManager()
	local attempts = 0
	while not _G.BrainrotManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.BrainrotManager
end

-- Wait for MapSystem API
local function waitForMapSystem()
	local attempts = 0
	while not _G.MapSystem and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.MapSystem
end

--------------------------------------------------------------------------------
-- STORAGE COLLECTION
--------------------------------------------------------------------------------

--[[
	Sets up the Storage part on a plot with ProximityPrompt for collection.
	Called when a plot is assigned to a player.
	
	@param plot Instance - The plot model
	@param player Player - The player who owns the plot
]]
local function setupStorageForPlot(plot: Instance, player: Player)
	-- Wait for BrainrotManager to create the Storage part
	local storagePart = plot:FindFirstChild("Storage")
	if not storagePart then
		-- Try to get BrainrotManager to create it
		local BrainrotManager = waitForBrainrotManager()
		if BrainrotManager and BrainrotManager.CreateStoragePart then
			-- Get plot CFrame for positioning
			local plotCFrame: CFrame
			if plot:IsA("Model") and plot.PrimaryPart then
				plotCFrame = plot.PrimaryPart.CFrame
			elseif plot:IsA("Model") then
				plotCFrame = plot:GetPivot()
			else
				local primaryPart = plot:FindFirstChild("Island") or plot:FindFirstChildWhichIsA("BasePart")
				if primaryPart then
					plotCFrame = primaryPart.CFrame
				else
					warn("StorageCollection: Cannot determine plot CFrame")
					return
				end
			end
			
			storagePart = BrainrotManager.CreateStoragePart(plot, plotCFrame)
		end
	end
	
	if not storagePart then
		warn(string.format("StorageCollection: No Storage part found for plot owned by %s", player.Name))
		return
	end
	
	-- Check if ProximityPrompt already exists
	if storagePart:FindFirstChild("CollectPrompt") then
		return
	end
	
	-- Create ProximityPrompt for collection
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.ActionText = "Collect Cash"
	prompt.ObjectText = "Storage"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = COLLECTION_CONFIG.HOLD_DURATION
	prompt.MaxActivationDistance = COLLECTION_CONFIG.MAX_ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = storagePart
	
	-- Create collection sound
	local collectSound = Instance.new("Sound")
	collectSound.Name = "CollectSound"
	collectSound.SoundId = COLLECTION_CONFIG.CASH_REGISTER_SOUND_ID
	collectSound.Volume = 0.5
	collectSound.Parent = storagePart
	
	-- Handle prompt triggered
	prompt.Triggered:Connect(function(triggeringPlayer: Player)
		-- Only allow the plot owner to collect
		local ownerId = plot:GetAttribute("OwnerId")
		if not ownerId or triggeringPlayer.UserId ~= ownerId then
			warn(string.format("StorageCollection: %s tried to collect from plot they don't own", triggeringPlayer.Name))
			return
		end
		
		-- Get current storage amount
		local currentStorage = plot:GetAttribute("CurrentStorage") or 0
		if currentStorage <= 0 then
			return -- Nothing to collect
		end
		
		-- Transfer to leaderstats
		local leaderstats = triggeringPlayer:FindFirstChild("leaderstats")
		if not leaderstats then return end
		
		local money = leaderstats:FindFirstChild("Money")
		if not money then return end
		
		-- Get current market rate
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local stockMarketFolder = ReplicatedStorage:FindFirstChild("StockMarket")
		local marketRate = 1.0
		local rateName = "NORMAL"
		
		if stockMarketFolder then
			marketRate = stockMarketFolder:GetAttribute("CurrentRate") or 1.0
			rateName = stockMarketFolder:GetAttribute("RateName") or "NORMAL"
		end
		
		-- Calculate final value
		local baseValue = currentStorage
		local finalValue = math.floor(baseValue * marketRate)
		
		-- Add to player's money
		money.Value = money.Value + finalValue
		
		-- Reset storage
		plot:SetAttribute("CurrentStorage", 0)
		
		-- Update visual
		local BrainrotManager = _G.BrainrotManager
		if BrainrotManager and BrainrotManager.UpdateStorageVisual then
			local maxStorage = plot:GetAttribute("MaxStorage") or 500
			BrainrotManager.UpdateStorageVisual(plot, 0, maxStorage)
		end
		
		-- Play sound
		collectSound:Play()
		
		-- Disable smoke
		local smoke = storagePart:FindFirstChild("OverflowSmoke")
		if smoke then
			smoke.Enabled = false
		end
		
		print(string.format("✓ %s collected $%d (Base: $%d, Rate: x%.1f %s)", 
			triggeringPlayer.Name, finalValue, baseValue, marketRate, rateName))
	end)
	
	print(string.format("✓ Storage ProximityPrompt created for %s's plot", player.Name))
end

--[[
	Cleans up the Storage ProximityPrompt when a plot is released.
	
	@param plot Instance - The plot model
]]
local function cleanupStorageForPlot(plot: Instance)
	local storagePart = plot:FindFirstChild("Storage")
	if storagePart then
		local prompt = storagePart:FindFirstChild("CollectPrompt")
		if prompt then
			prompt:Destroy()
		end
		
		local sound = storagePart:FindFirstChild("CollectSound")
		if sound then
			sound:Destroy()
		end
	end
	
	-- Reset storage attribute
	plot:SetAttribute("CurrentStorage", 0)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   StorageCollection - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Wait for MapSystem to be available
	local MapSystem = waitForMapSystem()
	if not MapSystem then
		warn("StorageCollection: MapSystem not available!")
		return
	end
	
	-- Wait a moment for plots to be generated
	task.wait(1)
	
	-- Setup storage for all existing plots with owners
	local allPlots = MapSystem.GetAllPlots()
	for _, plotData in allPlots do
		if plotData.Owner then
			setupStorageForPlot(plotData.Model, plotData.Owner)
		end
	end
	
	-- Listen for new players being assigned plots
	-- This hooks into the plot assignment in init.server.luau via attributes
	local PlotsFolder = workspace:FindFirstChild("Plots")
	if PlotsFolder then
		for _, plot in PlotsFolder:GetChildren() do
			plot:GetAttributeChangedSignal("OwnerId"):Connect(function()
				local ownerId = plot:GetAttribute("OwnerId")
				if ownerId then
					local player = Players:GetPlayerByUserId(ownerId)
					if player then
						setupStorageForPlot(plot, player)
					end
				else
					-- Plot was released
					cleanupStorageForPlot(plot)
				end
			end)
		end
	end
	
	-- Cleanup when players leave
	Players.PlayerRemoving:Connect(function(player: Player)
		local BrainrotManager = _G.BrainrotManager
		if BrainrotManager and BrainrotManager.GetPlayerPlot then
			local plot = BrainrotManager.GetPlayerPlot(player)
			if plot then
				cleanupStorageForPlot(plot)
			end
		end
	end)
	
	print("✓ StorageCollection initialized")
	print("═══════════════════════════════════════════")
end

-- Start the system
initialize()

-- Export for other scripts
_G.StorageCollection = {
	SetupStorageForPlot = setupStorageForPlot,
	CleanupStorageForPlot = cleanupStorageForPlot,
}
