--[[
	StorageUpgradeManager Server Module
	
	Handles the storage upgrade shop on the Main Island.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local UpgradeStorageRemote = Instance.new("RemoteFunction")
UpgradeStorageRemote.Name = "UpgradeStorage"
UpgradeStorageRemote.Parent = RemoteEvents

local GetStorageInfoRemote = Instance.new("RemoteFunction")
GetStorageInfoRemote.Name = "GetStorageInfo"
GetStorageInfoRemote.Parent = RemoteEvents

local StorageUpgradedEvent = Instance.new("RemoteEvent")
StorageUpgradedEvent.Name = "StorageUpgraded"
StorageUpgradedEvent.Parent = RemoteEvents

local CONFIG = {
	BASE_STORAGE = 500,
	BASE_PRICE = 100,
	MULTIPLIER = 2,
}

local StorageUpgradeManager = {}
local Services = {}

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local function getUpgradeLevel(max)
	if max <= CONFIG.BASE_STORAGE then return 0 end
	return math.floor(math.log(max / CONFIG.BASE_STORAGE) / math.log(2))
end

local function getUpgradePrice(lvl)
	return CONFIG.BASE_PRICE * (CONFIG.MULTIPLIER ^ lvl)
end

local function getNewMaxStorage(curr)
	return curr * CONFIG.MULTIPLIER
end

local function handleUpgradeStorage(player)
	local mainIsland = workspace:FindFirstChild("MainIsland")
	local vendor = mainIsland and mainIsland:FindFirstChild("StorageVendor")
	if vendor then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - vendor.Position).Magnitude > 20 then
			return false, "Too far from vendor"
		end
	end
	
	local ISM = rawget(Services, "ItemStorageManager")
	if not ISM then return false, "ItemStorageManager failed" end
	
	-- Calculate price
	local currentCap = ISM.GetStorageCapacity(player)
	local lvl = getUpgradeLevel(currentCap)
	local price = getUpgradePrice(lvl)

	local ls = player:FindFirstChild("leaderstats")
	local money = ls and ls:FindFirstChild("Money")
	if not money or money.Value < price then return false, "Not enough money" end

	money.Value -= price
	local newCap = getNewMaxStorage(currentCap)

	ISM.SetStorageCapacity(player, newCap)

	local nextLvl = lvl + 1
	local nextPrice = getUpgradePrice(nextLvl)
	local nextCap = getNewMaxStorage(newCap)

	StorageUpgradedEvent:FireClient(player, {
		currentMax = newCap,
		upgradeLevel = nextLvl,
		nextPrice = nextPrice,
		nextMaxStorage = nextCap
	})

	return true, "Storage Upgraded!"
end

local function handleGetStorageInfo(player)
	local ISM = rawget(Services, "ItemStorageManager")
	local currentCap = ISM and ISM.GetStorageCapacity(player) or CONFIG.BASE_STORAGE
	local lvl = getUpgradeLevel(currentCap)
	return {
		currentMax = currentCap,
		upgradeLevel = lvl,
		nextPrice = getUpgradePrice(lvl),
		nextMaxStorage = getNewMaxStorage(currentCap)
	}
end


local function setupStorageVendor()
	local mainIsland = workspace:WaitForChild("MainIsland", 10)
	if not mainIsland then return end
	
	local vendor = mainIsland:WaitForChild("StorageVendor", 10)
	if not vendor then return end
	
	local CollectionService = game:GetService("CollectionService")
	CollectionService:AddTag(vendor, "StorageUpgradeVendor")
	
	-- Ensure prompt exists
	local primary = vendor.PrimaryPart or vendor:FindFirstChildWhichIsA("BasePart")
	if primary and not vendor:FindFirstChild("StoragePrompt", true) then
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "StoragePrompt"
		pp.ActionText = "Upgrade Storage"
		pp.ObjectText = "Storage Shop"
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.RequiresLineOfSight = false
		pp.MaxActivationDistance = 20
		pp.Parent = primary
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function StorageUpgradeManager.Init(services)
	print("   StorageUpgradeManager (Module) - Initializing")
	Services = services or {}
	
	task.spawn(setupStorageVendor)
	
	UpgradeStorageRemote.OnServerInvoke = handleUpgradeStorage
	GetStorageInfoRemote.OnServerInvoke = handleGetStorageInfo
	
	print("✓ StorageUpgradeManager Initialized")
end

StorageUpgradeManager.CONFIG = CONFIG
StorageUpgradeManager.GetUpgradeLevel = getUpgradeLevel
StorageUpgradeManager.GetUpgradePrice = getUpgradePrice
StorageUpgradeManager.GetNewMaxStorage = getNewMaxStorage

return StorageUpgradeManager
