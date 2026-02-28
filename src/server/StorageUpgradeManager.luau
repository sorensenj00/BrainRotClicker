--[[
	StorageUpgradeManager Server Module

	Handles the storage upgrade shop on the Main Island.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local function getOrCreateRemote(parent, remoteName, className)
	local remote = parent:FindFirstChild(remoteName)
	if remote and not remote:IsA(className) then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new(className)
		remote.Name = remoteName
		remote.Parent = parent
	end
	return remote
end

local UpgradeStorageEvent = getOrCreateRemote(RemoteEvents, "UpgradeStorageRequest", "RemoteEvent")
local UpgradeStorageTierEvent = getOrCreateRemote(RemoteEvents, "UpgradeStorageTierRequest", "RemoteEvent")
local GetStorageInfoEvent = getOrCreateRemote(RemoteFunctions, "GetStorageInfo", "RemoteFunction")
local StorageUpgradedEvent = getOrCreateRemote(RemoteEvents, "StorageUpgraded", "RemoteEvent")

local CONFIG = {
	BASE_STORAGE = 2000,
	BASE_PRICE = 5000,
	MULTIPLIER = 2,
	BASE_TIER_PRICE = 25000,
	TIER_PRICE_MULTIPLIER = 2.5,
	TIER_CAPACITY_BONUS = 1.5,
	MAX_TIER_FALLBACK = 5,
	VENDOR_DISTANCE = 20,
}

local StorageUpgradeManager = {}
local Services = {}

-- Admin bypass (mirrors AdminService)
local ADMIN_USER_IDS = { [1340966465] = true }
local IS_STUDIO = RunService:IsStudio()
local function isAdmin(player)
	if IS_STUDIO then return true end
	if ADMIN_USER_IDS[player.UserId] then return true end
	if player.UserId == game.CreatorId then return true end
	return false
end

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

local function getTierPrice(tier)
	local idx = math.max(1, tier - 1)
	return math.floor(CONFIG.BASE_TIER_PRICE * (CONFIG.TIER_PRICE_MULTIPLIER ^ (idx - 1)))
end

local function getPlayerPlot(player)
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if plot:GetAttribute("OwnerId") == player.UserId then
			return plot
		end
	end
	return nil
end

local function getStorageModelFolder()
	local models = ReplicatedStorage:FindFirstChild("Models")
	return models and models:FindFirstChild("PlayerStorage")
end

local function getMaxStorageTier()
	local folder = getStorageModelFolder()
	if not folder then
		return CONFIG.MAX_TIER_FALLBACK
	end
	local maxTier = 1
	for _, child in ipairs(folder:GetChildren()) do
		local tier = tonumber(string.match(child.Name, "^PlayerStorageTier(%d+)$"))
		if tier and tier > maxTier then
			maxTier = tier
		end
	end
	return math.max(maxTier, 1)
end

local function getStorageTier(player)
	local tier = tonumber(player:GetAttribute("StorageTier"))
	if tier and tier >= 1 then
		return math.floor(tier)
	end
	local ds = rawget(Services, "DataService")
	local storedTier = ds and tonumber(ds.GetComponentData(player, "storageTier"))
	tier = (storedTier and storedTier >= 1) and math.floor(storedTier) or 1
	player:SetAttribute("StorageTier", tier)
	return tier
end

local function getCapacityUpgradeLevel(player)
	local lvl = tonumber(player:GetAttribute("StorageUpgradeLevel"))
	if lvl and lvl >= 0 then
		return math.floor(lvl)
	end

	local ds = rawget(Services, "DataService")
	local storedLevel = ds and tonumber(ds.GetComponentData(player, "storageUpgradeLevel"))
	if storedLevel and storedLevel >= 0 then
		lvl = math.floor(storedLevel)
	else
		local baseCap = tonumber(player:GetAttribute("BaseStorageCapacity")) or CONFIG.BASE_STORAGE
		lvl = math.max(0, getUpgradeLevel(baseCap))
	end

	player:SetAttribute("StorageUpgradeLevel", lvl)
	return lvl
end

local function setCapacityUpgradeLevel(player, level)
	local safeLevel = math.max(0, math.floor(tonumber(level) or 0))
	player:SetAttribute("StorageUpgradeLevel", safeLevel)
	local ds = rawget(Services, "DataService")
	if ds then
		ds.SetComponentData(player, "storageUpgradeLevel", safeLevel)
	end
end

local function setStorageTier(player, tier)
	local safeTier = math.max(1, math.floor(tonumber(tier) or 1))
	player:SetAttribute("StorageTier", safeTier)
	local ds = rawget(Services, "DataService")
	if ds then
		ds.SetComponentData(player, "storageTier", safeTier)
	end
end

local function replaceStorageVisual(player, tier)
	local plot = getPlayerPlot(player)
	if not plot then
		return false, "No owned plot"
	end

	local folder = getStorageModelFolder()
	local template = folder and folder:FindFirstChild("PlayerStorageTier" .. tostring(tier))
	if not template then
		return false, "Missing storage tier model"
	end

	local oldStorage = plot:FindFirstChild("Storage")
	local targetCFrame
	if oldStorage then
		if oldStorage:IsA("Model") then
			targetCFrame = oldStorage:GetPivot()
		elseif oldStorage:IsA("BasePart") then
			targetCFrame = oldStorage.CFrame
		end
	end
	if not targetCFrame then
		targetCFrame = plot:GetPivot()
	end

	local newStorage = template:Clone()
	newStorage.Name = "Storage"
	newStorage.Parent = plot
	if newStorage:IsA("Model") then
		newStorage:PivotTo(targetCFrame)
	elseif newStorage:IsA("BasePart") then
		newStorage.CFrame = targetCFrame
	end
	CollectionService:AddTag(newStorage, "PhysicalStorageHUD")

	if oldStorage then
		oldStorage:Destroy()
	end
	return true
end

local function isNearStorageVendor(player)
	if isAdmin(player) then return true end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local mainIsland = workspace:FindFirstChild("MainIsland")
	local shopsFolder = mainIsland and mainIsland:FindFirstChild("Shops")
	local vendor = shopsFolder and shopsFolder:FindFirstChild("StorageShop")
	local target = vendor and (vendor.PrimaryPart or vendor:FindFirstChildWhichIsA("BasePart", true))
	if not target then return true end

	return (hrp.Position - target.Position).Magnitude <= CONFIG.VENDOR_DISTANCE
end

local function buildStorageInfo(player)
	local ISM = rawget(Services, "ItemStorageManager")
	local baseCap = tonumber(player:GetAttribute("BaseStorageCapacity")) or CONFIG.BASE_STORAGE
	local displayCap = ISM and ISM.GetStorageCapacity(player) or baseCap
	local lvl = getCapacityUpgradeLevel(player)

	local tier = getStorageTier(player)
	local maxTier = getMaxStorageTier()
	local canTierUp = tier < maxTier

	local nextCap = getNewMaxStorage(baseCap)
	local capPrice = getUpgradePrice(lvl)
	local nextTier = math.min(tier + 1, maxTier)
	local tierPrice = canTierUp and getTierPrice(nextTier) or nil

	return {
		currentMax = baseCap, -- legacy compatibility
		upgradeLevel = lvl, -- legacy compatibility
		nextPrice = capPrice, -- legacy compatibility
		nextMaxStorage = nextCap, -- legacy compatibility
		displayMax = displayCap,
		capacity = {
			level = lvl,
			current = baseCap,
			next = nextCap,
			price = capPrice,
		},
		tier = {
			current = tier,
			next = nextTier,
			max = maxTier,
			canUpgrade = canTierUp,
			price = tierPrice,
		}
	}
end

local function handleUpgradeStorage(player)
	if not isNearStorageVendor(player) then
		return false, "Too far from vendor"
	end

	local ISM = rawget(Services, "ItemStorageManager")
	if not ISM then return false, "ItemStorageManager failed" end

	local baseCap = player:GetAttribute("BaseStorageCapacity") or CONFIG.BASE_STORAGE
	local lvl = getCapacityUpgradeLevel(player)
	local price = getUpgradePrice(lvl)

	local ls = player:FindFirstChild("leaderstats")
	local money = ls and ls:FindFirstChild("Money")
	if not money or money.Value < price then return false, "Not enough money" end

	money.Value -= price
	local newBaseCap = getNewMaxStorage(baseCap)
	setCapacityUpgradeLevel(player, lvl + 1)

	-- Update the base capacity; RefreshCapacity will apply multipliers automatically
	ISM.SetStorageCapacity(player, newBaseCap)
	StorageUpgradedEvent:FireClient(player, buildStorageInfo(player))
	return true, "Storage Upgraded!"
end

local function handleUpgradeStorageTier(player)
	if not isNearStorageVendor(player) then
		return false, "Too far from vendor"
	end

	local ISM = rawget(Services, "ItemStorageManager")
	if not ISM then return false, "ItemStorageManager failed" end

	local tier = getStorageTier(player)
	local maxTier = getMaxStorageTier()
	if tier >= maxTier then
		return false, "Already max tier"
	end

	local nextTier = tier + 1
	local price = getTierPrice(nextTier)
	local ls = player:FindFirstChild("leaderstats")
	local money = ls and ls:FindFirstChild("Money")
	if not money or money.Value < price then
		return false, "Not enough money"
	end

	money.Value -= price
	setStorageTier(player, nextTier)

	local baseCap = tonumber(player:GetAttribute("BaseStorageCapacity")) or CONFIG.BASE_STORAGE
	local newBaseCap = math.floor(baseCap * CONFIG.TIER_CAPACITY_BONUS)
	ISM.SetStorageCapacity(player, newBaseCap)

	local ok, err = replaceStorageVisual(player, nextTier)
	if not ok then
		warn("StorageUpgradeManager: failed to replace storage visual:", err)
	end

	StorageUpgradedEvent:FireClient(player, buildStorageInfo(player))
	return true, "Storage Tier Upgraded!"
end

local function handleGetStorageInfo(player)
	return buildStorageInfo(player)
end

local function setupStorageVendor()
	local mainIsland = workspace:WaitForChild("MainIsland", 10)
	if not mainIsland then return end

	-- FIX: Look in the Shops folder!
	local shopsFolder = mainIsland:WaitForChild("Shops", 10)
	if not shopsFolder then return end

	-- FIX: Look for StorageShop, not StorageVendor
	local vendor = shopsFolder:WaitForChild("StorageShop", 10)
	if not vendor then return end

	local CollectionService = game:GetService("CollectionService")
	CollectionService:AddTag(vendor, "StorageUpgradeVendor")

	-- Ensure prompt exists (Added 'true' to recursive search)
	local primary = vendor:FindFirstChild("Meshes/tung tung", true) or vendor.PrimaryPart or vendor:FindFirstChildWhichIsA("BasePart", true)
	if primary and not vendor:FindFirstChild("ShopPrompt", true) then
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "ShopPrompt" -- Fixed: Must be "ShopPrompt" for ShopInteraction to find it
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

	task.spawn(function()
		task.wait(2)
		setupStorageVendor()
	end)

	UpgradeStorageEvent.OnServerEvent:Connect(function(player)
		local s, msg = handleUpgradeStorage(player)
		UpgradeStorageEvent:FireClient(player, s, msg)
	end)

	UpgradeStorageTierEvent.OnServerEvent:Connect(function(player)
		local s, msg = handleUpgradeStorageTier(player)
		UpgradeStorageTierEvent:FireClient(player, s, msg)
	end)

	GetStorageInfoEvent.OnServerInvoke = handleGetStorageInfo

	print("✓ StorageUpgradeManager Initialized")
end

StorageUpgradeManager.CONFIG = CONFIG
StorageUpgradeManager.GetUpgradeLevel = getUpgradeLevel
StorageUpgradeManager.GetUpgradePrice = getUpgradePrice
StorageUpgradeManager.GetNewMaxStorage = getNewMaxStorage

return StorageUpgradeManager
