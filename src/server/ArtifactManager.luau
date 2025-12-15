--[[
	ArtifactManager Server Module
	
	Handles artifact generation, inventory, and equipment.
	
	CONVERTED TO MODULE SCRIPT
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))
local DataService = require(script.Parent.DataService)

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local ArtifactDroppedEvent = RemoteEvents:FindFirstChild("ArtifactDropped") or Instance.new("RemoteEvent")
ArtifactDroppedEvent.Name = "ArtifactDropped"
ArtifactDroppedEvent.Parent = RemoteEvents

local ArtifactEquippedEvent = RemoteEvents:FindFirstChild("ArtifactEquipped") or Instance.new("RemoteEvent")
ArtifactEquippedEvent.Name = "ArtifactEquipped"
ArtifactEquippedEvent.Parent = RemoteEvents

local EquipArtifactFunction = RemoteFunctions:FindFirstChild("EquipArtifact") or Instance.new("RemoteFunction")
EquipArtifactFunction.Name = "EquipArtifact"
EquipArtifactFunction.Parent = RemoteFunctions

local UnequipArtifactFunction = RemoteFunctions:FindFirstChild("UnequipArtifact") or Instance.new("RemoteFunction")
UnequipArtifactFunction.Name = "UnequipArtifact"
UnequipArtifactFunction.Parent = RemoteFunctions

local GetArtifactsFunction = RemoteFunctions:FindFirstChild("GetArtifacts") or Instance.new("RemoteFunction")
GetArtifactsFunction.Name = "GetArtifacts"
GetArtifactsFunction.Parent = RemoteFunctions

local COMPONENT_KEY = "Artifacts"
local ArtifactManager = {}

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getPlayerArtifacts(player)
	local data = DataService.GetComponentData(player, COMPONENT_KEY)
	if data then return data end
	if DataService.IsLoaded(player) then
		DataService.SetComponentData(player, COMPONENT_KEY, {})
		return DataService.GetComponentData(player, COMPONENT_KEY)
	end
	return {} -- Fallback
end

local function generateGUID() return HttpService:GenerateGUID(false) end

local function generateArtifact(rarity, slot)
	rarity = rarity or ArtifactConfig.RollRarity()
	slot = slot or ArtifactConfig.EquipmentSlots[math.random(#ArtifactConfig.EquipmentSlots)]
	local base = ArtifactConfig.GetRandomBase(slot)
	if not base then return nil end
	
	local numAffixes = ArtifactConfig.AffixCountByRarity[rarity] or 1
	local affixes = {}
	local used = {}
	
	for i = 1, math.ceil(numAffixes/2) do
		local pre = ArtifactConfig.GetRandomPrefix()
		if pre and not used[pre.key] then table.insert(affixes, pre.data); used[pre.key]=true end
	end
	for i = 1, math.floor(numAffixes/2) do
		local suf = ArtifactConfig.GetRandomSuffix()
		if suf and not used[suf.key] then table.insert(affixes, suf.data); used[suf.key]=true end
	end
	
	local name = ""
	for _, a in ipairs(affixes) do
		if a.Name:sub(1,2)=="of" then name = name.." "..a.Name else name = a.Name.." "..name end
	end
	name = name:gsub("^%s+", ""):gsub("%s+$", "") .. " " .. base.Name
	
	return {
		GUID = generateGUID(),
		Name = name,
		BaseId = base.Id,
		BaseName = base.Name,
		BaseIcon = base.Icon,
		Slot = slot,
		Rarity = rarity,
		Affixes = affixes,
		EquippedTo = nil,
		CreatedAt = os.time()
	}
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function ArtifactManager.Init()
	print("   ArtifactManager (Module) - Initializing")
	
	DataService.RegisterHandler(COMPONENT_KEY, {
		DefaultData = {},
		OnLoad = function(p, d) 
			-- No-op logging
		end,
		OnSave = function(p, d) return d end
	})
	
	EquipArtifactFunction.OnServerInvoke = ArtifactManager.EquipArtifact
	UnequipArtifactFunction.OnServerInvoke = ArtifactManager.UnequipArtifact
	GetArtifactsFunction.OnServerInvoke = function(player)
		local all = getPlayerArtifacts(player)
		local un = {}
		for _, a in pairs(all) do if not a.EquippedTo then table.insert(un, a) end end
		return { all = all, unequipped = un }
	end
	
	print("✓ ArtifactManager Initialized")
end

function ArtifactManager.AddArtifact(player, artifact)
	if not artifact or not artifact.GUID then return false end
	local inv = getPlayerArtifacts(player)
	inv[artifact.GUID] = artifact
	ArtifactDroppedEvent:FireClient(player, artifact)
	return true
end

function ArtifactManager.RemoveArtifact(player, guid)
	local inv = getPlayerArtifacts(player)
	if inv[guid] and not inv[guid].EquippedTo then
		inv[guid] = nil
		return true
	end
	return false
end

function ArtifactManager.EquipArtifact(player, unitGUID, artifactGUID, slot)
	local inv = getPlayerArtifacts(player)
	local art = inv[artifactGUID]
	if not art then return false, "Not found" end
	if art.Slot ~= slot then return false, "Wrong slot" end
	if art.EquippedTo then return false, "Equipped" end
	
	-- Check occupied
	for _, a in pairs(inv) do
		if a.EquippedTo == unitGUID and a.Slot == slot then return false, "Slot occupied" end
	end
	
	art.EquippedTo = unitGUID
	
	-- Update Unit Attr
	local BM = _G.BrainrotManager
	if BM and BM.GetUnitByGUID then
		local unit = BM.GetUnitByGUID(player, unitGUID)
		if unit then
			local ed = unit:GetAttribute("EquippedArtifacts")
			ed = ed and HttpService:JSONDecode(ed) or {}
			ed[slot] = artifactGUID
			unit:SetAttribute("EquippedArtifacts", HttpService:JSONEncode(ed))
		end
	end
	
	ArtifactEquippedEvent:FireClient(player, artifactGUID, unitGUID, slot, true)
	return true
end

function ArtifactManager.UnequipArtifact(player, unitGUID, slot)
	local inv = getPlayerArtifacts(player)
	local targetArt
	for _, a in pairs(inv) do
		if a.EquippedTo == unitGUID and a.Slot == slot then targetArt=a; break end
	end
	
	if not targetArt then return false, "No artifact" end
	
	targetArt.EquippedTo = nil
	local BM = _G.BrainrotManager
	if BM and BM.GetUnitByGUID then
		local unit = BM.GetUnitByGUID(player, unitGUID)
		if unit then
			local ed = unit:GetAttribute("EquippedArtifacts")
			ed = ed and HttpService:JSONDecode(ed) or {}
			ed[slot] = nil
			unit:SetAttribute("EquippedArtifacts", HttpService:JSONEncode(ed))
		end
	end
	
	ArtifactEquippedEvent:FireClient(player, targetArt.GUID, unitGUID, slot, false)
	return true
end

function ArtifactManager.CalculateUnitArtifactStats(player, unitGUID)
	local stats = { CycleTimeMult = 1, LuckBonus = 0, ItemTierBonus = 0, SynergyRangeBonus = 0 }
	local inv = getPlayerArtifacts(player)
	for _, art in pairs(inv) do
		if art.EquippedTo == unitGUID then
			local s = ArtifactConfig.CalculateArtifactStats(art)
			stats.CycleTimeMult *= s.CycleTimeMult
			stats.LuckBonus += s.LuckBonus
			stats.ItemTierBonus += s.ItemTierBonus
			stats.SynergyRangeBonus += s.SynergyRangeBonus
		end
	end
	-- clamps...
	stats.CycleTimeMult = math.max(stats.CycleTimeMult, ArtifactConfig.StatLimits.CycleTimeMin)
	stats.LuckBonus = math.min(stats.LuckBonus, ArtifactConfig.StatLimits.MaxLuckBonus)
	return stats
end

ArtifactManager.GenerateArtifact = generateArtifact

return ArtifactManager
