--[[
	BrainrotManager Server Script
	
	Handles:
	1. Spawning Brainrot units on player plots
	2. Inventory management (Active/Stored)
	3. Rarity rolling
	4. Grid placement integration with Tiers
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SynergyConfig = require(Shared:WaitForChild("SynergyConfig"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

-- Config
local CONFIG = {
	SPAWN_HEIGHT = 10,
	STARTING_MONEY = 1000,
}

local RARITY_CONFIG = {
	Normal = { chance = 0.90, color = Color3.fromRGB(255, 255, 255) },
	Spicy = { chance = 0.09, color = Color3.fromRGB(255, 80, 80) },
	Galaxy = { chance = 0.01, color = Color3.fromRGB(180, 100, 255) },
}
local RARITY_ORDER = {"Normal", "Spicy", "Galaxy"}

-- Tags
local BRAINROT_TAG = "ActiveBrainrot"

-- Remotes
local function getRemote(name, class, parent)
	local r = parent:FindFirstChild(name) or Instance.new(class)
	r.Name = name
	r.Parent = parent
	return r
end

local RE = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder", ReplicatedStorage)
RE.Name = "RemoteEvents"
local RF = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder", ReplicatedStorage)
RF.Name = "RemoteFunctions"

local SpawnBrainrotEvent = getRemote("SpawnBrainrot", "RemoteEvent", RE)
local InventoryChangedEvent = getRemote("InventoryChanged", "RemoteEvent", RE)
local GetInventoryRemote = getRemote("GetInventory", "RemoteFunction", RE)
local PlaceBrainrotRemote = getRemote("PlaceBrainrot", "RemoteFunction", RE)
local RemoveBrainrotRemote = getRemote("RemoveBrainrot", "RemoteFunction", RE)

-- State: {[Player]: {[unitName]: {[rarity]: {total: number, active: number}}}}
local PlayerInventory = {}

-- Helper Functions
local function rollRarity()
	local r = math.random()
	local cum = 0
	for _, name in RARITY_ORDER do
		cum += RARITY_CONFIG[name].chance
		if r <= cum then return name end
	end
	return "Normal"
end

local function getPlayerInventory(player)
	if not PlayerInventory[player] then PlayerInventory[player] = {} end
	return PlayerInventory[player]
end

local function updateSynergies(player)
	local inv = getPlayerInventory(player)
	local unitMults = {}
	local globalMult = 1
	
	for _, syn in SynergyConfig.GetAllSynergies() do
		local met, _ = SynergyConfig.CheckSynergyProgress(syn.Id, inv)
		if met then
			for _, eff in syn.Effects do
				if eff.Type == "IncomeMultiplier" then
					if eff.Target == "All" then globalMult *= eff.Value
					elseif eff.Target == "Specific" and eff.TargetUnits then
						for _, u in eff.TargetUnits do unitMults[u] = (unitMults[u] or 1) * eff.Value end
					end
				elseif eff.Type == "GlobalIncomeBoost" then globalMult *= eff.Value end
			end
		end
	end
	
	for _, b in CollectionService:GetTagged(BRAINROT_TAG) do
		if b:GetAttribute("OwnerId") == player.UserId then
			local uType = b:GetAttribute("UnitType")
			local mult = globalMult * (unitMults[uType] or 1)
			if math.abs((b:GetAttribute("SynergyMultiplier") or 1) - mult) > 0.001 then
				b:SetAttribute("SynergyMultiplier", mult)
			end
		end
	end
end

local function spawnBrainrot(player, unitName, targetTier, targetSlot)
	if not unitName then return nil end
	if not _G.GridManager then warn("No GridManager") return nil end
	
	local tier, slot
	if targetTier and targetSlot then
		tier, slot = targetTier, targetSlot
	else
		tier, slot = _G.GridManager.FindEmptySlot(player)
	end
	
	if not tier or not slot then warn("No empty slot for " .. player.Name) return nil end
	
	-- Get Template
	local template = ReplicatedStorage.Brainrots:FindFirstChild(unitName)
	if not template then warn("Template not found: " .. unitName) return nil end
	
	local brainrot = template:Clone()
	brainrot.Name = unitName
	
	-- Setup Attributes
	brainrot:SetAttribute("OwnerId", player.UserId)
	brainrot:SetAttribute("UnitType", unitName)
	brainrot:SetAttribute("UnitId", tostring(player.UserId).."_"..tostring(os.time()).."_"..math.random(1000,9999))
	brainrot:SetAttribute("SpawnTime", os.time())
	
	CollectionService:AddTag(brainrot, BRAINROT_TAG)
	
	-- Place on Grid
	local success = _G.GridManager.PlaceUnit(player, brainrot, tier, slot)
	if not success then brainrot:Destroy() return nil end
	
	-- Parent to plot
	local plots = workspace:FindFirstChild("Plots")
	local plotModel
	
	-- Try to find specific tier model
	if _G.MapSystem then
		local ts = _G.MapSystem.GetPlayerTierSystem(player)
		if ts and ts.Tiers[tier] then
			plotModel = ts.Tiers[tier].Model
		end
	end
	
	if not plotModel then
		-- Fallback search
		for _, p in plots:GetChildren() do
			if p:GetAttribute("OwnerId") == player.UserId then plotModel = p break end
		end
	end
	
	if plotModel then
		brainrot.Parent = plotModel:FindFirstChild("Brainrots") or Instance.new("Folder", plotModel)
		if brainrot.Parent.Name ~= "Brainrots" then brainrot.Parent.Name = "Brainrots" end
	else
		brainrot.Parent = workspace -- Fallback
	end
	
	-- VFX cleanup
	local vfx = brainrot:FindFirstChild("VfxInstance", true)
	if vfx and vfx:IsA("BasePart") then vfx.Transparency = 1 end

	return brainrot
end

-- API Functions
local function addToInventory(player, unitName, rarity)
	rarity = rarity or rollRarity()
	local inv = getPlayerInventory(player)
	if not inv[unitName] then inv[unitName] = {} end
	if not inv[unitName][rarity] then inv[unitName][rarity] = {total = 0, active = 0} end
	
	inv[unitName][rarity].total += 1
	InventoryChangedEvent:FireClient(player, unitName, inv[unitName])
	updateSynergies(player)
	
	return rarity
end

local function placeBrainrotFromInventory(player, unitName, rarity, slotIndex)
	local inv = getPlayerInventory(player)
	if not inv[unitName] or not inv[unitName][rarity] then return false, "Not in inventory" end
	local data = inv[unitName][rarity]
	if data.total - data.active <= 0 then return false, "None stored" end
	
	local brainrot = spawnBrainrot(player, unitName, nil, slotIndex) -- nil tier = auto find
	if not brainrot then return false, "Spawn failed" end
	
	brainrot:SetAttribute("Rarity", rarity)
	data.active += 1
	InventoryChangedEvent:FireClient(player, unitName, inv[unitName])
	updateSynergies(player)
	
	return true
end

local function removeBrainrotToInventory(player, unitName, rarity)
	local inv = getPlayerInventory(player)
	if not inv[unitName] or not inv[unitName][rarity] then return false, "Not in inventory" end
	local data = inv[unitName][rarity]
	-- Note: active count is decremented even if we can't find model (stat sync)
	
	-- Find brainrot
	local target
	for _, b in CollectionService:GetTagged(BRAINROT_TAG) do
		if b:GetAttribute("OwnerId") == player.UserId
		and b:GetAttribute("UnitType") == unitName
		and (b:GetAttribute("Rarity") or "Normal") == rarity then
			target = b
			break
		end
	end
	
	if target then
		-- Remove from grid
		local tier = target:GetAttribute("TierIndex")
		local slot = target:GetAttribute("GridSlot")
		if tier and slot and _G.GridManager then _G.GridManager.StashUnit(player, tier, slot) end
		target:Destroy()
	end
	
	data.active = math.max(0, data.active - 1)
	InventoryChangedEvent:FireClient(player, unitName, inv[unitName])
	updateSynergies(player)
	
	return true
end

-- Remotes Handlers
GetInventoryRemote.OnServerInvoke = function(plr)
	return { units = getPlayerInventory(plr), rarityConfig = RARITY_CONFIG, rarityOrder = RARITY_ORDER }
end
PlaceBrainrotRemote.OnServerInvoke = placeBrainrotFromInventory
RemoveBrainrotRemote.OnServerInvoke = removeBrainrotToInventory

-- Lifecycle
Players.PlayerAdded:Connect(function(player)
	if not player:FindFirstChild("leaderstats") then
		local ls = Instance.new("Folder", player)
		ls.Name = "leaderstats"
		Instance.new("IntValue", ls).Name = "Money" -- Value set by DataManager
	end
	getPlayerInventory(player)
end)

Players.PlayerRemoving:Connect(function(player)
	for _, b in CollectionService:GetTagged(BRAINROT_TAG) do
		if b:GetAttribute("OwnerId") == player.UserId then b:Destroy() end
	end
	PlayerInventory[player] = nil
end)

-- Public API
_G.BrainrotManager = {
	SpawnBrainrot = spawnBrainrot,
	AddToInventory = addToInventory,
	GetInventoryData = getPlayerInventory,
	RollRarity = rollRarity,
	PlaceBrainrotFromInventory = placeBrainrotFromInventory,
	RemoveBrainrotToInventory = removeBrainrotToInventory,

	-- Persistence hooks
	SetInventoryData = function(p, d) PlayerInventory[p] = d end,
	GetPlacementData = function(p)
		local d = {}
		for _, b in CollectionService:GetTagged(BRAINROT_TAG) do
			if b:GetAttribute("OwnerId") == p.UserId then
				table.insert(d, {
					unitType = b:GetAttribute("UnitType"),
					rarity = b:GetAttribute("Rarity"),
					gridSlot = b:GetAttribute("GridSlot"),
					tierIndex = b:GetAttribute("TierIndex")
				})
			end
		end
		return d
	end,
	SpawnFromPlacement = function(p, d)
		local b = spawnBrainrot(p, d.unitType, d.tierIndex, d.gridSlot)
		if b then b:SetAttribute("Rarity", d.rarity) end
		return b
	end
}

print("✓ BrainrotManager Initialized")
