--[[
	ArtifactUpgradeManager Server Module

	Handles 5-to-1 artifact rarity upgrades at the Tun vendor in MarketShop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local GetArtifactUpgradeStateFunc = RemoteFunctions:FindFirstChild("GetArtifactUpgradeState") or Instance.new("RemoteFunction")
GetArtifactUpgradeStateFunc.Name = "GetArtifactUpgradeState"
GetArtifactUpgradeStateFunc.Parent = RemoteFunctions

local CombineArtifactsFunc = RemoteFunctions:FindFirstChild("CombineArtifacts") or Instance.new("RemoteFunction")
CombineArtifactsFunc.Name = "CombineArtifacts"
CombineArtifactsFunc.Parent = RemoteFunctions

local Services = {}
local ArtifactUpgradeManager = {}

local ADMIN_USER_IDS = { [1340966465] = true }
local IS_STUDIO = RunService:IsStudio()

local UpgradeConfig
local function getUpgradeConfig()
	if not UpgradeConfig then
		local shared = ReplicatedStorage:WaitForChild("Shared")
		UpgradeConfig = require(shared:WaitForChild("ArtifactUpgradeConfig"))
	end
	return UpgradeConfig
end

local function isAdmin(player)
	if IS_STUDIO then return true end
	if ADMIN_USER_IDS[player.UserId] then return true end
	if player.UserId == game.CreatorId then return true end
	return false
end

local function getArtifactManager()
	return rawget(Services, "ArtifactManager")
end

local function getVendorTargetPart()
	local mainIsland = workspace:FindFirstChild("MainIsland")
	local shopsFolder = mainIsland and mainIsland:FindFirstChild("Shops")
	local marketShop = shopsFolder and shopsFolder:FindFirstChild("MarketShop")
	local tun = marketShop and marketShop:FindFirstChild("Tun", true)

	if not tun then
		return nil, nil
	end

	if tun:IsA("BasePart") then
		return tun, tun
	end

	if tun:IsA("Model") then
		local promptParent = tun.PrimaryPart or tun:FindFirstChildWhichIsA("BasePart", true)
		return tun, promptParent
	end

	local modelParent = tun:FindFirstAncestorOfClass("Model")
	if modelParent then
		local promptParent = modelParent.PrimaryPart or modelParent:FindFirstChildWhichIsA("BasePart", true)
		return modelParent, promptParent
	end

	return nil, nil
end

local function setupVendor()
	local cfg = getUpgradeConfig()
	local vendorInstance, promptParent = getVendorTargetPart()
	if not vendorInstance or not promptParent then
		warn("ArtifactUpgradeManager: Could not find Tun vendor in MainIsland/Shops/MarketShop")
		return
	end

	if not CollectionService:HasTag(vendorInstance, cfg.VENDOR_TAG) then
		CollectionService:AddTag(vendorInstance, cfg.VENDOR_TAG)
	end

	if not vendorInstance:FindFirstChild("ShopPrompt", true) then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ShopPrompt"
		prompt.ActionText = "Upgrade Artifacts"
		prompt.ObjectText = "Artifact Combiner"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = cfg.VENDOR_DISTANCE
		prompt.Parent = promptParent
	end
end

local function isNearVendor(player)
	if isAdmin(player) then return true end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local _, targetPart = getVendorTargetPart()
	if not targetPart then return true end

	local cfg = getUpgradeConfig()
	return (hrp.Position - targetPart.Position).Magnitude <= cfg.VENDOR_DISTANCE
end

local function buildUpgradeState(player)
	local cfg = getUpgradeConfig()
	local artifactManager = getArtifactManager()
	if not artifactManager or not artifactManager.GetArtifacts then
		return {
			counts = {},
			upgrades = {},
			requiredCount = cfg.REQUIRED_COUNT,
			rarityOrder = cfg.RARITY_ORDER,
		}
	end

	local data = artifactManager.GetArtifacts(player)
	local unequipped = data and data.unequipped or {}
	local counts = {}

	for _, rarity in ipairs(cfg.RARITY_ORDER) do
		counts[rarity] = 0
	end

	for _, artifact in ipairs(unequipped) do
		if artifact and artifact.Rarity and counts[artifact.Rarity] ~= nil then
			counts[artifact.Rarity] += 1
		end
	end

	local upgrades = {}
	for _, rarity in ipairs(cfg.RARITY_ORDER) do
		local nextRarity = cfg.GetNextRarity(rarity)
		local count = counts[rarity] or 0
		upgrades[rarity] = {
			count = count,
			required = cfg.REQUIRED_COUNT,
			canUpgrade = nextRarity ~= nil,
			nextRarity = nextRarity,
			ready = nextRarity ~= nil and count >= cfg.REQUIRED_COUNT,
		}
	end

	return {
		counts = counts,
		upgrades = upgrades,
		requiredCount = cfg.REQUIRED_COUNT,
		rarityOrder = cfg.RARITY_ORDER,
	}
end

local function rollbackArtifacts(player, removedArtifacts)
	local artifactManager = getArtifactManager()
	if not artifactManager then return end

	for _, artifact in ipairs(removedArtifacts) do
		if artifactManager.RestoreArtifact then
			artifactManager.RestoreArtifact(player, artifact)
		elseif artifactManager.AddArtifact then
			artifactManager.AddArtifact(player, artifact)
		end
	end
end

function ArtifactUpgradeManager.CombineArtifacts(player, sourceRarity, artifactGuids)
	if not isNearVendor(player) then
		return false, "You are too far from the upgrade vendor."
	end

	local cfg = getUpgradeConfig()
	if type(sourceRarity) ~= "string" then
		return false, "Invalid rarity."
	end

	local nextRarity = cfg.GetNextRarity(sourceRarity)
	if not nextRarity then
		return false, "This rarity cannot be upgraded."
	end

	local artifactManager = getArtifactManager()
	if not artifactManager or not artifactManager.GetArtifacts or not artifactManager.RemoveArtifact or not artifactManager.GenerateArtifact or not artifactManager.AddArtifact then
		return false, "Artifact system unavailable."
	end

	local artifacts = artifactManager.GetArtifacts(player)
	local allArtifacts = artifacts and artifacts.all or {}
	local selected = {}

	if artifactGuids ~= nil then
		if type(artifactGuids) ~= "table" then
			return false, "Invalid selection payload."
		end

		local seen = {}
		for _, guid in ipairs(artifactGuids) do
			if type(guid) ~= "string" then
				return false, "Invalid artifact id."
			end
			if seen[guid] then
				return false, "Duplicate artifact id in selection."
			end
			seen[guid] = true
			table.insert(selected, guid)
		end
	else
		for guid, artifact in pairs(allArtifacts) do
			if artifact and artifact.Rarity == sourceRarity and not artifact.EquippedTo then
				table.insert(selected, guid)
				if #selected >= cfg.REQUIRED_COUNT then
					break
				end
			end
		end
	end

	if #selected ~= cfg.REQUIRED_COUNT then
		return false, string.format("You need exactly %d %s artifacts.", cfg.REQUIRED_COUNT, sourceRarity)
	end

	local removedArtifacts = {}
	for _, guid in ipairs(selected) do
		local artifact = allArtifacts[guid]
		if not artifact then
			return false, "One or more artifacts were not found."
		end
		if artifact.EquippedTo then
			return false, "Equipped artifacts cannot be upgraded."
		end
		if artifact.Rarity ~= sourceRarity then
			return false, "All selected artifacts must match rarity."
		end
	end

	for _, guid in ipairs(selected) do
		local artifact = allArtifacts[guid]
		local removed = artifactManager.RemoveArtifact(player, guid)
		if not removed then
			rollbackArtifacts(player, removedArtifacts)
			return false, "Could not consume selected artifacts."
		end
		table.insert(removedArtifacts, artifact)
	end

	local newArtifact = artifactManager.GenerateArtifact(nextRarity)
	if not newArtifact then
		rollbackArtifacts(player, removedArtifacts)
		return false, "Could not generate upgraded artifact."
	end

	local granted = artifactManager.AddArtifact(player, newArtifact)
	if not granted then
		rollbackArtifacts(player, removedArtifacts)
		return false, "Could not grant upgraded artifact."
	end

	return true, {
		sourceRarity = sourceRarity,
		newRarity = nextRarity,
		requiredCount = cfg.REQUIRED_COUNT,
		consumedGUIDs = selected,
		newArtifact = newArtifact,
	}
end

function ArtifactUpgradeManager.GetUpgradeState(player)
	return buildUpgradeState(player)
end

function ArtifactUpgradeManager.Init(services)
	print("   ArtifactUpgradeManager (Module) - Initializing")
	Services = services or {}

	setupVendor()

	GetArtifactUpgradeStateFunc.OnServerInvoke = function(player)
		return ArtifactUpgradeManager.GetUpgradeState(player)
	end

	CombineArtifactsFunc.OnServerInvoke = function(player, sourceRarity, artifactGuids)
		return ArtifactUpgradeManager.CombineArtifacts(player, sourceRarity, artifactGuids)
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			buildUpgradeState(player)
		end)
	end)

	print("✓ ArtifactUpgradeManager Initialized")
end

return ArtifactUpgradeManager
