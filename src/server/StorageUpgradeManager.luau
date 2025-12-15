--[[
	StorageUpgradeManager Server Module
	
	Handles the storage upgrade shop on the Main Island.
	
	CONVERTED TO MODULE SCRIPT
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
	
	local ISM = _G.ItemStorageManager
	if not ISM then return false, "ItemStorageManager failed" end
	
	local success, msg = ISM.UpgradeStorage(player)
	if success then
		local info = ISM.GetStorageUpgradeInfo(player)
		StorageUpgradedEvent:FireClient(player, {
			currentMax = info.currentCapacity,
			upgradeLevel = info.upgradeLevel,
			nextPrice = info.nextPrice,
			nextMaxStorage = info.nextCapacity
		})
	end
	return success, msg
end

local function handleGetStorageInfo(player)
	local ISM = _G.ItemStorageManager
	if not ISM then
		return { currentMax = CONFIG.BASE_STORAGE, upgradeLevel = 0, nextPrice = CONFIG.BASE_PRICE, nextMaxStorage = CONFIG.BASE_STORAGE*2 }
	end
	local info = ISM.GetStorageUpgradeInfo(player)
	return {
		currentMax = info.currentCapacity,
		upgradeLevel = info.upgradeLevel,
		nextPrice = info.nextPrice,
		nextMaxStorage = info.nextCapacity
	}
end

local function createStorageVendor()
	local mainIsland = workspace:WaitForChild("MainIsland", 30)
	if not mainIsland then return end
	if mainIsland:FindFirstChild("StorageVendor") then return end
	
	local part = Instance.new("Part")
	part.Name = "StorageVendor"
	part.Size = Vector3.new(6, 8, 6)
	part.BrickColor = BrickColor.new("Deep orange")
	part.Material = Enum.Material.Neon
	part.Anchored = true
	
	local sv = mainIsland:FindFirstChild("ShopVendor")
	if sv then
		part.Position = sv.Position + Vector3.new(15, 0, 0)
	else
		local pp = mainIsland.PrimaryPart or mainIsland:FindFirstChildWhichIsA("BasePart")
		if pp then part.Position = pp.Position + Vector3.new(35, 10, 0) 
		else part.Position = Vector3.new(35, 40, 0) end
	end
	
	part.Parent = mainIsland
	
	local bb = Instance.new("BillboardGui"); bb.Size=UDim2.new(5,0,2,0); bb.StudsOffset=Vector3.new(0,6,0); bb.Parent=part
	local lbl = Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Text="📦 STORAGE"; lbl.TextColor3=Color3.fromRGB(255,200,100); lbl.TextScaled=true; lbl.Parent=bb
	
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Upgrade Storage"
	pp.ObjectText = "Storage"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.Parent = part
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function StorageUpgradeManager.Init()
	print("   StorageUpgradeManager (Module) - Initializing")
	task.spawn(createStorageVendor)
	
	UpgradeStorageRemote.OnServerInvoke = handleUpgradeStorage
	GetStorageInfoRemote.OnServerInvoke = handleGetStorageInfo
	
	print("✓ StorageUpgradeManager Initialized")
end

StorageUpgradeManager.CONFIG = CONFIG
StorageUpgradeManager.GetUpgradeLevel = getUpgradeLevel
StorageUpgradeManager.GetUpgradePrice = getUpgradePrice
StorageUpgradeManager.GetNewMaxStorage = getNewMaxStorage

return StorageUpgradeManager
