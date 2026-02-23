--[[
	ArtifactManager Server Module
	
	Handles artifact generation, inventory, and equipment.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
-- Lazy Config
local ArtifactConfig

local function getArtifactConfig()
	if not ArtifactConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))
	end
	return ArtifactConfig
end
local DataService -- Will be set from Services.DataService

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
local Services = {} 

-- Getter for DataService (to avoid circular require)
local function getDataService()
	if not DataService then
		-- Use rawget to avoid strict table metatable errors
		DataService = rawget(Services, "DataService")
	end
	return DataService
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getPlayerArtifacts(player)
	local ds = getDataService()
	if not ds then return {} end
	
	local data = ds.GetComponentData(player, COMPONENT_KEY)
	if data then return data end
	if ds.IsLoaded(player) then
		ds.SetComponentData(player, COMPONENT_KEY, {})
		return ds.GetComponentData(player, COMPONENT_KEY)
	end
	return {}
end

local function generateGUID() return HttpService:GenerateGUID(false) end

local function generateArtifact(rarity, slot)
	local ac = getArtifactConfig()
	rarity = rarity or ac.RollRarity()
	slot = slot or ac.EquipmentSlots[math.random(#ac.EquipmentSlots)]
	local base = ac.GetRandomBase(slot)
	if not base then return nil end
	
	local numAffixes = ac.AffixCountByRarity[rarity] or 1
	local affixes = {}
	local used = {}
	
	for i = 1, math.ceil(numAffixes/2) do
		local pre = ac.GetRandomPrefix()
		if pre and not used[pre.key] then table.insert(affixes, pre.data); used[pre.key]=true end
	end
	for i = 1, math.floor(numAffixes/2) do
		local suf = ac.GetRandomSuffix()
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

function ArtifactManager.Init(services)
	print("   ArtifactManager (Module) - Initializing")
	Services = services or {}
	
	local ds = getDataService()
	if ds then
		ds.RegisterHandler(COMPONENT_KEY, {
			DefaultData = {},
			OnLoad = function(p, d) 
				-- No-op logging
			end,
			OnSave = function(p, d) return d end
		})
	else
		warn("ArtifactManager: DataService not available during Init")
	end
	
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
	
	-- Update Unit Attr (Visual/Client sync)
	-- Need to find the physical unit if we want to replicate visual
	-- BrainrotManager used to help with this.
	-- We can skip visual sync attribute here if not critical or find unit manually.
	
	ArtifactEquippedEvent:FireClient(player, artifactGUID, unitGUID, slot, true)
	
	-- Refresh attributes to reflect new artifact stats in HUD
	local ItemProductionManager = rawget(Services, "ItemProductionManager")
	if ItemProductionManager and ItemProductionManager.RefreshUnitAttributes then
		ItemProductionManager.RefreshUnitAttributes(player)
	end
	
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
	
	ArtifactEquippedEvent:FireClient(player, targetArt.GUID, unitGUID, slot, false)
	
	-- Refresh attributes to reflect removed artifact stats in HUD
	local ItemProductionManager = rawget(Services, "ItemProductionManager")
	if ItemProductionManager and ItemProductionManager.RefreshUnitAttributes then
		ItemProductionManager.RefreshUnitAttributes(player)
	end
	
	return true
end

function ArtifactManager.CalculateUnitArtifactStats(player, unitGUID)
	local stats = { CycleTimeMult = 1, LuckBonus = 0, ItemTierBonus = 0, SynergyRangeBonus = 0 }
	local inv = getPlayerArtifacts(player)
	local ac = getArtifactConfig()
	for _, art in pairs(inv) do
		if art.EquippedTo == unitGUID then
			local s = ac.CalculateArtifactStats(art)
			stats.CycleTimeMult *= s.CycleTimeMult
			stats.LuckBonus += s.LuckBonus
			stats.ItemTierBonus += s.ItemTierBonus
			stats.SynergyRangeBonus += s.SynergyRangeBonus
		end
	end

	stats.CycleTimeMult = math.max(stats.CycleTimeMult, ac.StatLimits.CycleTimeMin)
	stats.LuckBonus = math.min(stats.LuckBonus, ac.StatLimits.MaxLuckBonus)
	return stats
end

ArtifactManager.GenerateArtifact = generateArtifact

return ArtifactManager
