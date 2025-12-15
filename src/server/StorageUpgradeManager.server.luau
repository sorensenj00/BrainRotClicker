--[[
	StorageUpgradeManager Server Script
	
	Handles the storage upgrade shop on the Main Island.
	- Storage doubles with each upgrade: 500 → 1000 → 2000 → 4000...
	- Price doubles with each upgrade: 100 → 200 → 400 → 800...
	- Creates StorageVendor part with ProximityPrompt on Main Island
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Configuration
local CONFIG = {
	BASE_STORAGE = 500,     -- Starting max storage
	BASE_PRICE = 100,       -- Starting upgrade price
	MULTIPLIER = 2,         -- Both storage and price multiply by 2
}

-- Wait for RemoteEvents folder
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

-- Create RemoteFunctions for storage upgrade
local UpgradeStorageRemote = Instance.new("RemoteFunction")
UpgradeStorageRemote.Name = "UpgradeStorage"
UpgradeStorageRemote.Parent = RemoteEvents

local GetStorageInfoRemote = Instance.new("RemoteFunction")
GetStorageInfoRemote.Name = "GetStorageInfo"
GetStorageInfoRemote.Parent = RemoteEvents

-- Create RemoteEvent to notify client of storage upgrade
local StorageUpgradedEvent = Instance.new("RemoteEvent")
StorageUpgradedEvent.Name = "StorageUpgraded"
StorageUpgradedEvent.Parent = RemoteEvents

-- Wait for BrainrotManager API (legacy, kept for compatibility)
local function _waitForBrainrotManager()
	local attempts = 0
	while not _G.BrainrotManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.BrainrotManager
end

--------------------------------------------------------------------------------
-- STORAGE CALCULATIONS
--------------------------------------------------------------------------------

--[[
	Calculates how many upgrades a player has based on their max storage.
	
	@param maxStorage number - Current max storage
	@return number - Number of upgrades purchased
]]
local function getUpgradeLevel(maxStorage: number): number
	-- Formula: BASE_STORAGE * (2 ^ level) = maxStorage
	-- So: level = log2(maxStorage / BASE_STORAGE)
	if maxStorage <= CONFIG.BASE_STORAGE then
		return 0
	end
	return math.floor(math.log(maxStorage / CONFIG.BASE_STORAGE) / math.log(2))
end

--[[
	Calculates the price for the next storage upgrade.
	
	@param upgradeLevel number - Current upgrade level (0-based)
	@return number - Price for the next upgrade
]]
local function getUpgradePrice(upgradeLevel: number): number
	return CONFIG.BASE_PRICE * (CONFIG.MULTIPLIER ^ upgradeLevel)
end

--[[
	Calculates what the new max storage will be after upgrading.
	
	@param currentMax number - Current max storage
	@return number - New max storage after upgrade
]]
local function getNewMaxStorage(currentMax: number): number
	return currentMax * CONFIG.MULTIPLIER
end

--------------------------------------------------------------------------------
-- PURCHASE LOGIC (DELEGATES TO ItemStorageManager)
--------------------------------------------------------------------------------

-- Wait for ItemStorageManager API
local function waitForItemStorageManager()
	local attempts = 0
	while not _G.ItemStorageManager and attempts < 50 do
		attempts += 1
		task.wait(0.1)
	end
	return _G.ItemStorageManager
end

--[[
	Handles a storage upgrade request from a client.
	Now delegates to ItemStorageManager for the actual upgrade.
	
	@param player Player - The player making the purchase
	@return boolean, string? - Success status and optional message
]]
local function handleUpgradeStorage(player: Player): (boolean, string?)
	-- Security: Verify player is near StorageVendor on Main Island
	local mainIsland = workspace:FindFirstChild("MainIsland")
	local storageVendor = mainIsland and mainIsland:FindFirstChild("StorageVendor")
	if storageVendor then
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local distance = (hrp.Position - storageVendor.Position).Magnitude
			if distance > 20 then
				return false, "You must be at the storage vendor to upgrade!"
			end
		end
	end
	
	-- Delegate to ItemStorageManager
	local ItemStorageManager = waitForItemStorageManager()
	if not ItemStorageManager then
		return false, "Server error: ItemStorageManager not available"
	end
	
	local success, message = ItemStorageManager.UpgradeStorage(player)
	
	if success then
		-- Get updated info to notify client
		local info = ItemStorageManager.GetStorageUpgradeInfo(player)
		StorageUpgradedEvent:FireClient(player, {
			currentMax = info.currentCapacity,
			upgradeLevel = info.upgradeLevel,
			nextPrice = info.nextPrice,
			nextMaxStorage = info.nextCapacity,
		})
	end
	
	return success, message
end

--[[
	Gets storage info for a player (for UI).
	Now delegates to ItemStorageManager.
	
	@param player Player - The player to get info for
	@return table - Storage upgrade info
]]
local function handleGetStorageInfo(player: Player)
	local ItemStorageManager = waitForItemStorageManager()
	if not ItemStorageManager then
		return {
			currentMax = CONFIG.BASE_STORAGE,
			upgradeLevel = 0,
			nextPrice = CONFIG.BASE_PRICE,
			nextMaxStorage = CONFIG.BASE_STORAGE * 2,
		}
	end
	
	local info = ItemStorageManager.GetStorageUpgradeInfo(player)
	
	-- Map to expected format for UI compatibility
	return {
		currentMax = info.currentCapacity,
		upgradeLevel = info.upgradeLevel,
		nextPrice = info.nextPrice,
		nextMaxStorage = info.nextCapacity,
	}
end

--------------------------------------------------------------------------------
-- STORAGE VENDOR CREATION
--------------------------------------------------------------------------------

--[[
	Creates the StorageVendor part on the Main Island.
]]
local function createStorageVendor()
	local mainIsland = workspace:WaitForChild("MainIsland", 30)
	if not mainIsland then
		warn("StorageUpgradeManager: MainIsland not found")
		return
	end
	
	-- Check if already exists
	if mainIsland:FindFirstChild("StorageVendor") then
		return
	end
	
	-- Create the vendor part
	local storageVendor = Instance.new("Part")
	storageVendor.Name = "StorageVendor"
	storageVendor.Size = Vector3.new(6, 8, 6)
	storageVendor.BrickColor = BrickColor.new("Deep orange")
	storageVendor.Material = Enum.Material.Neon
	storageVendor.Anchored = true
	storageVendor.CanCollide = true
	
	-- Position near the shop vendor but offset
	local shopVendor = mainIsland:FindFirstChild("ShopVendor")
	if shopVendor then
		storageVendor.Position = shopVendor.Position + Vector3.new(15, 0, 0)
	else
		local primaryPart = mainIsland.PrimaryPart or mainIsland:FindFirstChildWhichIsA("BasePart")
		if primaryPart then
			storageVendor.Position = primaryPart.Position + Vector3.new(35, 10, 0)
		else
			-- Fallback: main island is at height 30, so position at 40
			storageVendor.Position = Vector3.new(35, 40, 0)
		end
	end
	
	storageVendor.Parent = mainIsland
	
	-- Add visual label
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(5, 0, 2, 0)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.Parent = storageVendor
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "📦 STORAGE"
	label.TextColor3 = Color3.fromRGB(255, 200, 100)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard
	
	-- Create ProximityPrompt (client will use this to open UI)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StoragePrompt"
	prompt.ActionText = "Upgrade Storage"
	prompt.ObjectText = "Storage"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = storageVendor
	
	print("✓ StorageVendor created on Main Island")
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   StorageUpgradeManager - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Create storage vendor on main island
	task.spawn(createStorageVendor)
	
	-- Connect remote functions
	UpgradeStorageRemote.OnServerInvoke = handleUpgradeStorage
	GetStorageInfoRemote.OnServerInvoke = handleGetStorageInfo
	
	print("✓ StorageUpgradeManager initialized")
	print(string.format("  • Base Storage: %d", CONFIG.BASE_STORAGE))
	print(string.format("  • Base Price: $%d", CONFIG.BASE_PRICE))
	print(string.format("  • Multiplier: x%d per upgrade", CONFIG.MULTIPLIER))
	print("═══════════════════════════════════════════")
end

-- Start the system
initialize()

-- Export for other scripts
_G.StorageUpgradeManager = {
	CONFIG = CONFIG,
	GetUpgradeLevel = getUpgradeLevel,
	GetUpgradePrice = getUpgradePrice,
	GetNewMaxStorage = getNewMaxStorage,
}
