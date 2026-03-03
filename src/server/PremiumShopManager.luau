--[[
	PremiumShopManager

	Handles:
	- Robux Developer Product receipts -> Braincells
	- Spending Braincells on premium perks
	- Premium shop vendor tagging + prompt setup
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PremiumShopConfig = require(Shared:WaitForChild("PremiumShopConfig"))

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local function getOrCreateRemote(parent: Instance, remoteName: string, className: string)
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

local SpendBraincellsRemote = getOrCreateRemote(RemoteFunctions, "SpendBraincells", "RemoteFunction")
local GetPremiumShopStateRemote = getOrCreateRemote(RemoteFunctions, "GetPremiumShopState", "RemoteFunction")
local PremiumShopNoticeEvent = getOrCreateRemote(RemoteEvents, "PremiumShopNotice", "RemoteEvent")

local PremiumShopManager = {}
local Services = {}

local RECENT_PURCHASE_IDS = {}
local RECEIPT_CONNECTED = false

local VENDOR_TAG = "PremiumShopVendor"
local VENDOR_DISTANCE = 20

local ADMIN_USER_IDS = { [1340966465] = true }
local IS_STUDIO = RunService:IsStudio()

local function isAdmin(player: Player): boolean
	if IS_STUDIO then return true end
	if ADMIN_USER_IDS[player.UserId] then return true end
	if player.UserId == game.CreatorId then return true end
	return false
end

local function getDataService()
	return rawget(Services, "DataService")
end

local function getArtifactManager()
	return rawget(Services, "ArtifactManager")
end

local function recordAchievement(player: Player, goalType: string, amount: number)
	local achievementManager = rawget(Services, "AchievementsManager")
	if achievementManager and achievementManager.RecordProgress then
		achievementManager.RecordProgress(player, goalType, amount)
	end
end

local function getBraincells(player: Player): number
	local ds = getDataService()
	if ds and ds.GetBraincells then
		return ds.GetBraincells(player)
	end
	return 0
end

local function addBraincells(player: Player, amount: number): boolean
	local ds = getDataService()
	if ds and ds.AddBraincells then
		return ds.AddBraincells(player, amount)
	end
	return false
end

local function deductBraincells(player: Player, amount: number): boolean
	local ds = getDataService()
	if ds and ds.DeductBraincells then
		return ds.DeductBraincells(player, amount)
	end
	return false
end

local function getVendorModel(): Model?
	local mainIsland = workspace:FindFirstChild("MainIsland")
	local shopsFolder = mainIsland and mainIsland:FindFirstChild("Shops")
	local marketShop = shopsFolder and shopsFolder:FindFirstChild("RobuxShop")
	local vendor = marketShop and marketShop:FindFirstChild("Tun", true)

	if vendor and vendor:IsA("Model") then
		return vendor
	end
	return nil
end

local function isNearVendor(player: Player): boolean
	if isAdmin(player) then return true end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local vendor = getVendorModel()
	if not vendor then return true end
	local distance = (hrp.Position - vendor:GetPivot().Position).Magnitude
	return distance <= VENDOR_DISTANCE
end

local function setupVendor()
	local vendor = getVendorModel()
	if not vendor then
		warn("PremiumShopManager: RobuxShop model not found in workspace")
		return
	end

	if not CollectionService:HasTag(vendor, VENDOR_TAG) then
		CollectionService:AddTag(vendor, VENDOR_TAG)
	end

	local promptParent = vendor:FindFirstChild("Tun", true)
	if not promptParent or not promptParent:IsA("BasePart") then
		promptParent = vendor.PrimaryPart or vendor:FindFirstChildWhichIsA("BasePart", true)
	end

	if not promptParent then
		warn("PremiumShopManager: No valid prompt parent found on RobuxShop")
		return
	end

	if not vendor:FindFirstChild("ShopPrompt", true) then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.ActionText = "Open Premium Shop"
		prompt.ObjectText = "Braincells Vendor"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = VENDOR_DISTANCE
		prompt.Parent = promptParent
	end
end

local function rollCrateRarity(itemMetadata)
	local legendaryChance = 0.05
	if itemMetadata and type(itemMetadata.LegendaryChance) == "number" then
		legendaryChance = itemMetadata.LegendaryChance
	end
	if math.random() < legendaryChance then
		return "Legendary"
	end
	return "Rare"
end

local function spendOnPremiumCrate(player: Player, itemDef)
	local artifactManager = getArtifactManager()
	if not artifactManager or not artifactManager.GenerateArtifact or not artifactManager.AddArtifact then
		return false, "Artifact system unavailable", nil
	end

	local rarity = rollCrateRarity(itemDef.Metadata)
	local artifact = artifactManager.GenerateArtifact(rarity)
	if not artifact then
		return false, "Could not generate artifact", nil
	end

	local added = artifactManager.AddArtifact(player, artifact)
	if not added then
		return false, "Could not grant artifact", nil
	end

	return true, "Premium crate opened!", {
		Type = "Artifact",
		ArtifactName = artifact.Name,
		Rarity = artifact.Rarity,
	}
end

local function spendOnInstantStorageFill(_player: Player)
	return true, "Storage fill placeholder purchased.", {
		Type = "Placeholder",
		Perk = "InstantStorageFill",
	}
end

local function spendOnMarketManipulator(player: Player, itemDef)
	local sector = "Tech"
	if itemDef.Metadata and type(itemDef.Metadata.DefaultSector) == "string" then
		sector = itemDef.Metadata.DefaultSector
	end

	local message = string.format("%s just pumped the %s market!", player.Name, sector)
	PremiumShopNoticeEvent:FireAllClients({
		Type = "MarketManipulator",
		Message = message,
		PlayerName = player.Name,
		Sector = sector,
		DurationSeconds = (itemDef.Metadata and itemDef.Metadata.DurationSeconds) or 600,
	})

	return true, message, {
		Type = "Placeholder",
		Perk = "MarketManipulator",
		Sector = sector,
	}
end

function PremiumShopManager.SpendBraincells(player: Player, itemId: string)
	if type(itemId) ~= "string" then
		return {
			success = false,
			message = "Invalid item id",
			braincellsLeft = getBraincells(player),
		}
	end

	if not isNearVendor(player) then
		return {
			success = false,
			message = "Too far from vendor",
			braincellsLeft = getBraincells(player),
		}
	end

	local itemDef = PremiumShopConfig.GetShopItem(itemId)
	if not itemDef then
		return {
			success = false,
			message = "Unknown premium item",
			braincellsLeft = getBraincells(player),
		}
	end

	if not deductBraincells(player, itemDef.Price) then
		return {
			success = false,
			message = "Not enough Braincells",
			braincellsLeft = getBraincells(player),
		}
	end

	local ok, message, rewardData
	if itemId == "premium_crate" then
		ok, message, rewardData = spendOnPremiumCrate(player, itemDef)
	elseif itemId == "instant_storage_fill" then
		ok, message, rewardData = spendOnInstantStorageFill(player)
	elseif itemId == "market_manipulator" then
		ok, message, rewardData = spendOnMarketManipulator(player, itemDef)
	else
		ok, message, rewardData = false, "Unhandled premium item", nil
	end

	if not ok then
		addBraincells(player, itemDef.Price)
		return {
			success = false,
			message = message or "Purchase failed",
			braincellsLeft = getBraincells(player),
		}
	end

	recordAchievement(player, "braincells_spent_total", itemDef.Price)
	if itemId == "premium_crate" then
		recordAchievement(player, "premium_crates_opened", 1)
	elseif itemId == "market_manipulator" then
		recordAchievement(player, "market_manipulator_used", 1)
	end

	return {
		success = true,
		message = message or "Purchased!",
		braincellsLeft = getBraincells(player),
		rewardData = rewardData,
	}
end

local function handleReceipt(receiptInfo)
	if not receiptInfo or not receiptInfo.PurchaseId then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if RECENT_PURCHASE_IDS[receiptInfo.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local pack = PremiumShopConfig.GetPackByProductId(receiptInfo.ProductId)
	if not pack then
		warn("PremiumShopManager: Unknown ProductId in receipt:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local granted = addBraincells(player, pack.Braincells)
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	RECENT_PURCHASE_IDS[receiptInfo.PurchaseId] = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function PremiumShopManager.GetClientState(player: Player)
	return {
		Braincells = getBraincells(player),
		Packs = PremiumShopConfig.GetAllPacksSorted(),
		ShopItems = PremiumShopConfig.GetAllShopItemsSorted(),
	}
end

function PremiumShopManager.Init(services)
	print("   PremiumShopManager (Module) - Initializing")
	Services = services or {}

	task.spawn(function()
		task.wait(2)
		setupVendor()
	end)

	SpendBraincellsRemote.OnServerInvoke = PremiumShopManager.SpendBraincells
	GetPremiumShopStateRemote.OnServerInvoke = PremiumShopManager.GetClientState

	if not RECEIPT_CONNECTED then
		MarketplaceService.ProcessReceipt = handleReceipt
		RECEIPT_CONNECTED = true
	end

	print("✓ PremiumShopManager Initialized")
end

return PremiumShopManager
