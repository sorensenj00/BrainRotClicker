--[[
	ItemProductionManager Server Script
	
	Handles item production for the Sell a Brainrot system.
	
	Features:
	- Produces items based on owned brainrot counts
	- Milestone-based tier unlocks (1/10/50/100 owned)
	- Produces to ItemStorageManager instead of money
	- Pauses production when storage is full
	
	This REPLACES the income generation in BrainrotManager.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Wait for shared modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

-- Constants
local CONFIG = {
	PRODUCTION_TICK = 1,  -- Check production every 1 second
	STORAGE_FULL_CHECK_INTERVAL = 5,  -- Check storage status every 5 seconds for sleeping animation
}

-- Tags
local BRAINROT_TAG = "ActiveBrainrot"

-- Production state per player
-- { [Player] = { categoryProduction = { [category] = { lastProduced = { [tier] = tick } } } } }
local PlayerProduction = {}

-- Remote events for production feedback
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not RemoteEvents then
	RemoteEvents = Instance.new("Folder")
	RemoteEvents.Name = "RemoteEvents"
	RemoteEvents.Parent = ReplicatedStorage
end

local ItemProducedEvent = RemoteEvents:FindFirstChild("ItemProduced") or Instance.new("RemoteEvent")
ItemProducedEvent.Name = "ItemProduced"
ItemProducedEvent.Parent = RemoteEvents

local StorageFullEvent = RemoteEvents:FindFirstChild("StorageFull") or Instance.new("RemoteEvent")
StorageFullEvent.Name = "StorageFull"
StorageFullEvent.Parent = RemoteEvents

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Waits for ItemStorageManager to be available.
	@return table? - The ItemStorageManager API or nil
]]
local function waitForItemStorageManager()
	local attempts = 0
	while not _G.ItemStorageManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.ItemStorageManager
end

--[[
	Waits for BrainrotManager to be available.
	@return table? - The BrainrotManager API or nil
]]
local function waitForBrainrotManager()
	local attempts = 0
	while not _G.BrainrotManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.BrainrotManager
end

--[[
	Gets the count of brainrots per category for a player.
	Counts from actual active tagged brainrots (more reliable than inventory).
	@param player Player - The player
	@return { [category] = count } - Category counts
]]
local function getCategoryCounts(player)
	local counts = {}
	local debugOnce = not PlayerProduction[player] or not PlayerProduction[player]._debuggedCategories
	local unmappedTypes = {}
	
	-- Count from actual placed brainrots (tagged with ActiveBrainrot)
	local taggedCount = 0
	for _, brainrot in CollectionService:GetTagged(BRAINROT_TAG) do
		local ownerId = brainrot:GetAttribute("OwnerId")
		if ownerId == player.UserId then
			taggedCount = taggedCount + 1
			local unitType = brainrot:GetAttribute("UnitType")
			if unitType then
				local category = ItemConfig.GetBrainrotCategory(unitType)
				if category then
					counts[category] = (counts[category] or 0) + 1
				else
					unmappedTypes[unitType] = true
				end
			end
		end
	end
	
	-- Debug log once per player
	if debugOnce and taggedCount > 0 then
		print(string.format("🔍 ItemProductionManager: %s has %d tagged brainrots", player.Name, taggedCount))
		for category, count in pairs(counts) do
			print(string.format("   • %s: %d brainrots", category, count))
		end
		local unmappedList = {}
		for unitType, _ in pairs(unmappedTypes) do
			table.insert(unmappedList, unitType)
		end
		if #unmappedList > 0 then
			print(string.format("   ⚠️ Unmapped types: %s", table.concat(unmappedList, ", ")))
		end
		if PlayerProduction[player] then
			PlayerProduction[player]._debuggedCategories = true
		end
	end
	
	return counts
end

--[[
	Initializes production state for a player.
	@param player Player - The player
]]
local function initializePlayer(player)
	PlayerProduction[player] = {
		categoryProduction = {},
		lastStorageFullWarning = 0,
	}
	print(string.format("✓ ItemProductionManager: Initialized for %s", player.Name))
end

--[[
	Cleans up production state for a player.
	@param player Player - The player
]]
local function cleanupPlayer(player)
	PlayerProduction[player] = nil
end

--------------------------------------------------------------------------------
-- PRODUCTION LOGIC
--------------------------------------------------------------------------------

--[[
	Produces items for a player based on their owned brainrots.
	Called every production tick.
	@param player Player - The player
]]
local function produceItems(player)
	local production = PlayerProduction[player]
	if not production then return end
	
	local ItemStorageManager = _G.ItemStorageManager
	if not ItemStorageManager then return end
	
	-- Check if storage is full
	if ItemStorageManager.IsStorageFull(player) then
		-- Notify client (throttled)
		local now = tick()
		if now - production.lastStorageFullWarning > CONFIG.STORAGE_FULL_CHECK_INTERVAL then
			production.lastStorageFullWarning = now
			StorageFullEvent:FireClient(player)
			
			-- Update brainrot sleeping animations
			updateSleepingState(player, true)
		end
		return
	else
		-- Storage not full, wake up brainrots
		updateSleepingState(player, false)
	end
	
	-- Get category counts
	local categoryCounts = getCategoryCounts(player)
	
	-- Debug: log category counts periodically
	local hasCategories = false
	for category, count in pairs(categoryCounts) do
		hasCategories = true
		-- Uncomment for debug: print(string.format("  Category %s: %d owned", category, count))
	end
	
	if not hasCategories and tick() % 10 < CONFIG.PRODUCTION_TICK then
		-- Log every ~10 seconds if no categories found
		-- print(string.format("ItemProductionManager: %s has no brainrot categories", player.Name))
	end
	
	-- Process each category
	local now = tick()
	for category, ownedCount in pairs(categoryCounts) do
		if ownedCount > 0 then
			-- Get productions for this category based on milestones
			local productions = ItemConfig.GetProductions(category, ownedCount)
			
			-- Initialize category tracking if needed
			if not production.categoryProduction[category] then
				production.categoryProduction[category] = {
					lastProduced = {},
				}
			end
			local categoryProd = production.categoryProduction[category]
			
			-- Check each tier's production
			for _, prod in ipairs(productions) do
				local tier = ItemConfig.Items[prod.itemId] and ItemConfig.Items[prod.itemId].tier or 1
				local lastProduced = categoryProd.lastProduced[tier] or 0
				local timeSinceLastProd = now - lastProduced
				
				-- Check if enough time has passed for this tier
				if timeSinceLastProd >= prod.rate then
					-- Produce the item
					local added = ItemStorageManager.AddToStorage(player, prod.itemId, 1)
					
					if added > 0 then
						-- Update last produced time
						categoryProd.lastProduced[tier] = now
						
						-- Notify client for visual feedback
						ItemProducedEvent:FireClient(player, prod.itemId, 1)
						
						-- Debug log
						print(string.format("📦 %s produced: %s", player.Name, prod.itemId))
					end
				end
			end
		end
	end
end

--[[
	Updates the sleeping state for all brainrots of a player.
	When storage is full, brainrots "sleep" (visual feedback).
	@param player Player - The player
	@param isSleeping boolean - Whether brainrots should be sleeping
]]
function updateSleepingState(player, isSleeping)
	local BrainrotManager = _G.BrainrotManager
	if not BrainrotManager or not BrainrotManager.GetPlayerPlot then return end
	
	local plot = BrainrotManager.GetPlayerPlot(player)
	if not plot then return end
	
	-- Find all brainrots on the plot
	for _, child in pairs(plot:GetDescendants()) do
		if child:IsA("Model") and CollectionService:HasTag(child, BRAINROT_TAG) then
			-- Set sleeping attribute
			child:SetAttribute("IsSleeping", isSleeping)
			
			-- Visual feedback: add/remove Zzz particles
			local existingZzz = child:FindFirstChild("SleepParticles")
			
			if isSleeping and not existingZzz then
				-- Add sleeping particles
				local primaryPart = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
				if primaryPart then
					local attachment = Instance.new("Attachment")
					attachment.Name = "SleepParticles"
					attachment.Position = Vector3.new(0, 2, 0)
					attachment.Parent = primaryPart
					
					local particles = Instance.new("ParticleEmitter")
					particles.Name = "ZzzParticles"
					particles.Texture = "rbxassetid://6576860692"  -- Z character texture
					particles.Rate = 2
					particles.Speed = NumberRange.new(1, 2)
					particles.Lifetime = NumberRange.new(1, 2)
					particles.Size = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.5),
						NumberSequenceKeypoint.new(1, 1.5),
					})
					particles.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(0.8, 0),
						NumberSequenceKeypoint.new(1, 1),
					})
					particles.SpreadAngle = Vector2.new(20, 20)
					particles.Parent = attachment
				end
			elseif not isSleeping and existingZzz then
				-- Remove sleeping particles
				existingZzz:Destroy()
			end
		end
	end
end

--------------------------------------------------------------------------------
-- PRODUCTION LOOP
--------------------------------------------------------------------------------

local function startProductionLoop()
	task.spawn(function()
		while true do
			task.wait(CONFIG.PRODUCTION_TICK)
			
			-- Process all players
			for player, _ in pairs(PlayerProduction) do
				if player.Parent then  -- Player still connected
					task.spawn(produceItems, player)
				end
			end
		end
	end)
	
	print("✓ ItemProductionManager: Production loop started")
end

--------------------------------------------------------------------------------
-- PLAYER EVENTS
--------------------------------------------------------------------------------

local function onPlayerAdded(player)
	-- Wait for dependencies
	task.wait(2)
	waitForItemStorageManager()
	waitForBrainrotManager()
	
	initializePlayer(player)
end

local function onPlayerRemoving(player)
	cleanupPlayer(player)
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   ItemProductionManager - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Connect player events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	-- Handle existing players
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	
	-- Start the production loop
	startProductionLoop()
	
	print("✓ ItemProductionManager initialized")
	print("  • Production tick: " .. CONFIG.PRODUCTION_TICK .. "s")
	print("═══════════════════════════════════════════")
end

initialize()

-- Export API for other scripts
_G.ItemProductionManager = {
	ProduceItems = produceItems,
	GetCategoryCounts = getCategoryCounts,
	UpdateSleepingState = updateSleepingState,
}
