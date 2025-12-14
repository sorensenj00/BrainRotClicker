--[[
	ArtifactManager Server Script
	
	Handles artifact generation, inventory, and equipment.
	
	Features:
	- Procedural artifact generation with prefixes/suffixes
	- Per-player artifact inventory (GUID indexed)
	- Equipment to units (Head, Body, Accessory slots)
	- Stat calculation for equipped artifacts
	
	Part of Phase 3: Artifact System.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- Shared configs
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))

-- Remote events
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not RemoteEvents then
	RemoteEvents = Instance.new("Folder")
	RemoteEvents.Name = "RemoteEvents"
	RemoteEvents.Parent = ReplicatedStorage
end

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions")
if not RemoteFunctions then
	RemoteFunctions = Instance.new("Folder")
	RemoteFunctions.Name = "RemoteFunctions"
	RemoteFunctions.Parent = ReplicatedStorage
end

-- Create events
local ArtifactDroppedEvent = RemoteEvents:FindFirstChild("ArtifactDropped") or Instance.new("RemoteEvent")
ArtifactDroppedEvent.Name = "ArtifactDropped"
ArtifactDroppedEvent.Parent = RemoteEvents

local ArtifactEquippedEvent = RemoteEvents:FindFirstChild("ArtifactEquipped") or Instance.new("RemoteEvent")
ArtifactEquippedEvent.Name = "ArtifactEquipped"
ArtifactEquippedEvent.Parent = RemoteEvents

-- Create functions
local EquipArtifactFunction = RemoteFunctions:FindFirstChild("EquipArtifact") or Instance.new("RemoteFunction")
EquipArtifactFunction.Name = "EquipArtifact"
EquipArtifactFunction.Parent = RemoteFunctions

local UnequipArtifactFunction = RemoteFunctions:FindFirstChild("UnequipArtifact") or Instance.new("RemoteFunction")
UnequipArtifactFunction.Name = "UnequipArtifact"
UnequipArtifactFunction.Parent = RemoteFunctions

local GetArtifactsFunction = RemoteFunctions:FindFirstChild("GetArtifacts") or Instance.new("RemoteFunction")
GetArtifactsFunction.Name = "GetArtifacts"
GetArtifactsFunction.Parent = RemoteFunctions

--------------------------------------------------------------------------------
-- PLAYER ARTIFACT DATA
--------------------------------------------------------------------------------

-- { [userId] = { [GUID] = artifactData } }
local PlayerArtifacts = {}

--[[
	Gets or creates artifact inventory for a player.
	@param player Player
	@return table - Artifact inventory
]]
local function getPlayerArtifacts(player)
	if not PlayerArtifacts[player.UserId] then
		PlayerArtifacts[player.UserId] = {}
	end
	return PlayerArtifacts[player.UserId]
end

--------------------------------------------------------------------------------
-- ARTIFACT GENERATION
--------------------------------------------------------------------------------

--[[
	Generates a unique GUID for an artifact.
	@return string - Unique identifier
]]
local function generateGUID()
	return HttpService:GenerateGUID(false)
end

--[[
	Generates a procedural artifact.
	@param rarity string? - Force a specific rarity, or nil to roll
	@param slot string? - Force a specific slot, or nil to random
	@return table - The generated artifact data
]]
local function generateArtifact(rarity, slot)
	-- Roll rarity if not specified
	rarity = rarity or ArtifactConfig.RollRarity()
	
	-- Pick random slot if not specified
	slot = slot or ArtifactConfig.EquipmentSlots[math.random(#ArtifactConfig.EquipmentSlots)]
	
	-- Get base artifact for this slot
	local base = ArtifactConfig.GetRandomBase(slot)
	if not base then
		warn("ArtifactManager: No base artifact for slot " .. slot)
		return nil
	end
	
	-- Generate affixes based on rarity
	local numAffixes = ArtifactConfig.AffixCountByRarity[rarity] or 1
	local affixes = {}
	local usedAffixes = {}
	
	-- Add prefix(es)
	for i = 1, math.ceil(numAffixes / 2) do
		local prefix = ArtifactConfig.GetRandomPrefix()
		if prefix and not usedAffixes[prefix.key] then
			table.insert(affixes, prefix.data)
			usedAffixes[prefix.key] = true
		end
	end
	
	-- Add suffix(es)
	for i = 1, math.floor(numAffixes / 2) do
		local suffix = ArtifactConfig.GetRandomSuffix()
		if suffix and not usedAffixes[suffix.key] then
			table.insert(affixes, suffix.data)
			usedAffixes[suffix.key] = true
		end
	end
	
	-- Build name from affixes
	local name = ""
	for _, affix in ipairs(affixes) do
		if affix.Name:sub(1, 2) == "of" then
			name = name .. " " .. affix.Name
		else
			name = affix.Name .. " " .. name
		end
	end
	name = name:gsub("^%s+", ""):gsub("%s+$", "") -- Trim
	name = name .. " " .. base.Name
	
	-- Create artifact
	local artifact = {
		GUID = generateGUID(),
		Name = name,
		BaseId = base.Id,
		BaseName = base.Name,
		BaseIcon = base.Icon,
		Slot = slot,
		Rarity = rarity,
		Color = ArtifactConfig.RarityColors[rarity],
		Affixes = affixes,
		EquippedTo = nil, -- unitGUID when equipped
		CreatedAt = os.time(),
	}
	
	return artifact
end

--------------------------------------------------------------------------------
-- INVENTORY MANAGEMENT
--------------------------------------------------------------------------------

--[[
	Adds an artifact to a player's inventory.
	@param player Player
	@param artifact table - The artifact data
	@return boolean - Success
]]
local function addArtifact(player, artifact)
	if not artifact or not artifact.GUID then
		warn("ArtifactManager: Invalid artifact")
		return false
	end
	
	local inventory = getPlayerArtifacts(player)
	inventory[artifact.GUID] = artifact
	
	-- Notify client
	ArtifactDroppedEvent:FireClient(player, artifact)
	
	print(string.format("📿 %s received: %s (%s)", player.Name, artifact.Name, artifact.Rarity))
	return true
end

--[[
	Removes an artifact from a player's inventory.
	@param player Player
	@param artifactGUID string - The artifact's GUID
	@return boolean - Success
]]
local function removeArtifact(player, artifactGUID)
	local inventory = getPlayerArtifacts(player)
	
	if not inventory[artifactGUID] then
		return false
	end
	
	-- Don't allow removing equipped artifacts
	if inventory[artifactGUID].EquippedTo then
		warn("ArtifactManager: Cannot remove equipped artifact")
		return false
	end
	
	inventory[artifactGUID] = nil
	return true
end

--[[
	Gets all unequipped artifacts for a player.
	@param player Player
	@return table - Array of unequipped artifacts
]]
local function getUnequippedArtifacts(player)
	local inventory = getPlayerArtifacts(player)
	local unequipped = {}
	
	for guid, artifact in pairs(inventory) do
		if not artifact.EquippedTo then
			table.insert(unequipped, artifact)
		end
	end
	
	return unequipped
end

--[[
	Gets artifacts equipped to a specific unit.
	@param player Player
	@param unitGUID string - The unit's GUID
	@return table - { [slot] = artifact }
]]
local function getUnitEquippedArtifacts(player, unitGUID)
	local inventory = getPlayerArtifacts(player)
	local equipped = {}
	
	for guid, artifact in pairs(inventory) do
		if artifact.EquippedTo == unitGUID then
			equipped[artifact.Slot] = artifact
		end
	end
	
	return equipped
end

--------------------------------------------------------------------------------
-- EQUIPMENT SYSTEM
--------------------------------------------------------------------------------

--[[
	Equips an artifact to a unit.
	@param player Player
	@param unitGUID string - The unit's GUID
	@param artifactGUID string - The artifact's GUID
	@param slot string - The equipment slot
	@return boolean, string? - Success, error message
]]
local function equipArtifact(player, unitGUID, artifactGUID, slot)
	local inventory = getPlayerArtifacts(player)
	
	-- Validate artifact exists
	local artifact = inventory[artifactGUID]
	if not artifact then
		return false, "Artifact not found"
	end
	
	-- Validate slot matches
	if artifact.Slot ~= slot then
		return false, "Artifact cannot be equipped in that slot"
	end
	
	-- Validate artifact is not already equipped
	if artifact.EquippedTo then
		return false, "Artifact is already equipped"
	end
	
	-- Check if slot is already occupied on unit
	local currentEquip = getUnitEquippedArtifacts(player, unitGUID)
	if currentEquip[slot] then
		return false, "Slot is already occupied"
	end
	
	-- Equip the artifact
	artifact.EquippedTo = unitGUID
	
	-- Update unit's attribute for client replication
	local BrainrotManager = _G.BrainrotManager
	if BrainrotManager and BrainrotManager.GetUnitByGUID then
		local unit = BrainrotManager.GetUnitByGUID(player, unitGUID)
		if unit then
			-- Store equipped artifact GUIDs as JSON attribute
			local equippedData = unit:GetAttribute("EquippedArtifacts") or {}
			if type(equippedData) == "string" then
				equippedData = HttpService:JSONDecode(equippedData)
			end
			equippedData[slot] = artifactGUID
			unit:SetAttribute("EquippedArtifacts", HttpService:JSONEncode(equippedData))
		end
	end
	
	-- Notify client
	ArtifactEquippedEvent:FireClient(player, artifactGUID, unitGUID, slot, true)
	
	print(string.format("⚔️ %s equipped %s to unit %s (%s slot)", 
		player.Name, artifact.Name, unitGUID:sub(1, 8), slot))
	return true
end

--[[
	Unequips an artifact from a unit.
	@param player Player
	@param unitGUID string - The unit's GUID
	@param slot string - The equipment slot
	@return boolean, string? - Success, error message
]]
local function unequipArtifact(player, unitGUID, slot)
	local equipped = getUnitEquippedArtifacts(player, unitGUID)
	local artifact = equipped[slot]
	
	if not artifact then
		return false, "No artifact in that slot"
	end
	
	-- Unequip
	artifact.EquippedTo = nil
	
	-- Update unit's attribute
	local BrainrotManager = _G.BrainrotManager
	if BrainrotManager and BrainrotManager.GetUnitByGUID then
		local unit = BrainrotManager.GetUnitByGUID(player, unitGUID)
		if unit then
			local equippedData = unit:GetAttribute("EquippedArtifacts") or {}
			if type(equippedData) == "string" then
				equippedData = HttpService:JSONDecode(equippedData)
			end
			equippedData[slot] = nil
			unit:SetAttribute("EquippedArtifacts", HttpService:JSONEncode(equippedData))
		end
	end
	
	-- Notify client
	ArtifactEquippedEvent:FireClient(player, artifact.GUID, unitGUID, slot, false)
	
	print(string.format("⚔️ %s unequipped %s from unit %s (%s slot)", 
		player.Name, artifact.Name, unitGUID:sub(1, 8), slot))
	return true
end

--------------------------------------------------------------------------------
-- STAT CALCULATION
--------------------------------------------------------------------------------

--[[
	Calculates the combined stat bonuses from all artifacts equipped to a unit.
	@param player Player
	@param unitGUID string - The unit's GUID
	@return table - Combined stats { CycleTimeMult, LuckBonus, ItemTierBonus, SynergyRangeBonus }
]]
local function calculateUnitArtifactStats(player, unitGUID)
	local stats = {
		CycleTimeMult = 1,
		LuckBonus = 0,
		ItemTierBonus = 0,
		SynergyRangeBonus = 0,
	}
	
	local equipped = getUnitEquippedArtifacts(player, unitGUID)
	
	for slot, artifact in pairs(equipped) do
		local artifactStats = ArtifactConfig.CalculateArtifactStats(artifact)
		stats.CycleTimeMult = stats.CycleTimeMult * artifactStats.CycleTimeMult
		stats.LuckBonus = stats.LuckBonus + artifactStats.LuckBonus
		stats.ItemTierBonus = stats.ItemTierBonus + artifactStats.ItemTierBonus
		stats.SynergyRangeBonus = stats.SynergyRangeBonus + artifactStats.SynergyRangeBonus
	end
	
	-- Apply stat limits
	stats.CycleTimeMult = math.max(stats.CycleTimeMult, ArtifactConfig.StatLimits.CycleTimeMin)
	stats.LuckBonus = math.min(stats.LuckBonus, ArtifactConfig.StatLimits.MaxLuckBonus)
	stats.ItemTierBonus = math.min(stats.ItemTierBonus, ArtifactConfig.StatLimits.MaxTierBonus)
	stats.SynergyRangeBonus = math.min(stats.SynergyRangeBonus, ArtifactConfig.StatLimits.MaxSynergyRange)
	
	return stats
end

--------------------------------------------------------------------------------
-- DATA PERSISTENCE
--------------------------------------------------------------------------------

--[[
	Gets all artifacts for saving.
	@param player Player
	@return table - Artifact inventory
]]
local function getArtifactData(player)
	return getPlayerArtifacts(player)
end

--[[
	Loads artifact data from save.
	@param player Player
	@param data table - Saved artifact data
]]
local function loadArtifactData(player, data)
	if not data then return end
	PlayerArtifacts[player.UserId] = data
	print(string.format("📿 Loaded %d artifacts for %s", 
		#data and #data or 0, player.Name))
end

--------------------------------------------------------------------------------
-- REMOTE FUNCTION HANDLERS
--------------------------------------------------------------------------------

EquipArtifactFunction.OnServerInvoke = function(player, unitGUID, artifactGUID, slot)
	return equipArtifact(player, unitGUID, artifactGUID, slot)
end

UnequipArtifactFunction.OnServerInvoke = function(player, unitGUID, slot)
	return unequipArtifact(player, unitGUID, slot)
end

GetArtifactsFunction.OnServerInvoke = function(player)
	return {
		all = getPlayerArtifacts(player),
		unequipped = getUnequippedArtifacts(player),
	}
end

--------------------------------------------------------------------------------
-- CLEANUP
--------------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	PlayerArtifacts[player.UserId] = nil
end)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

print("═══════════════════════════════════════════")
print("   ArtifactManager - Initializing")
print("═══════════════════════════════════════════")
print("✓ ArtifactManager initialized")
print("  • Rarity weights loaded: " .. tostring(ArtifactConfig.RarityWeights.Common) .. "% Common")
print("═══════════════════════════════════════════")

-- Export API
_G.ArtifactManager = {
	-- Generation
	GenerateArtifact = generateArtifact,
	
	-- Inventory
	AddArtifact = addArtifact,
	RemoveArtifact = removeArtifact,
	GetPlayerArtifacts = getPlayerArtifacts,
	GetUnequippedArtifacts = getUnequippedArtifacts,
	GetUnitEquippedArtifacts = getUnitEquippedArtifacts,
	
	-- Equipment
	EquipArtifact = equipArtifact,
	UnequipArtifact = unequipArtifact,
	
	-- Stats
	CalculateUnitArtifactStats = calculateUnitArtifactStats,
	
	-- Persistence
	GetArtifactData = getArtifactData,
	LoadArtifactData = loadArtifactData,
}
