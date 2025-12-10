--[[
	GridManager Server Script
	Manages grid-based brainrot placement on player plots.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Modules
local GridConfig = require(ReplicatedStorage.Shared.GridConfig)

-- Constants
local BRAINROT_TAG = "ActiveBrainrot"

-- Remotes
local function getRemote(name, class, parent)
	local remote = parent:FindFirstChild(name) or Instance.new(class)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder", ReplicatedStorage)
RemoteEvents.Name = "RemoteEvents"
local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder", ReplicatedStorage)
RemoteFunctions.Name = "RemoteFunctions"

local GridUpdatedEvent = getRemote("GridUpdated", "RemoteEvent", RemoteEvents)
local PlaceUnitFunction = getRemote("PlaceUnit", "RemoteFunction", RemoteFunctions)
local MoveUnitFunction = getRemote("MoveUnit", "RemoteFunction", RemoteFunctions)
local SwapUnitsFunction = getRemote("SwapUnits", "RemoteFunction", RemoteFunctions)
local StashUnitFunction = getRemote("StashUnit", "RemoteFunction", RemoteFunctions)
local GetGridFunction = getRemote("GetGrid", "RemoteFunction", RemoteFunctions)

-- Player Data: { [userId] = { gridSize = "starter", slots = { [tier] = { [slot] = unit } } } }
local PlayerGrids = {}

local function getPlayerGrid(player)
	if not PlayerGrids[player.UserId] then
		PlayerGrids[player.UserId] = { gridSize = "starter", slots = {} }
	end
	return PlayerGrids[player.UserId]
end

local function getTotalSlots(player)
	local sizeName = getPlayerGrid(player).gridSize
	local config = GridConfig.SIZES[sizeName] or GridConfig.SIZES.starter
	return config.rows * config.cols
end

-- Plot Helper
local function getPlotInfo(player, tierIndex)
	local tierSystem = _G.MapSystem and _G.MapSystem.GetPlayerTierSystem(player)
	if tierSystem and tierSystem.Tiers[tierIndex] then
		local model = tierSystem.Tiers[tierIndex].Model
		if model then
			return model:GetPivot().Position, Vector3.new(50,10,50) -- Standard size
		end
	end
	
	-- Fallback to main plot
	local plots = workspace:FindFirstChild("Plots")
	if not plots then return nil end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerId") == player.UserId then
			local floor = plot:FindFirstChild("Island") or plot:FindFirstChildWhichIsA("BasePart")
			return floor and floor.Position or plot:GetPivot().Position, Vector3.new(50,10,50)
		end
	end
	return nil
end

local function getSlotCFrame(player, tierIndex, slotIndex)
	local center, size = getPlotInfo(player, tierIndex)
	if not center then return CFrame.new(0, 10, 0) end
	
	local xOff, zOff = GridConfig.GetSlotOffset(slotIndex, size.X, size.Z)
	local posY = center.Y + (size.Y / 2) + GridConfig.GRID_OFFSET_Y
	local unitPos = Vector3.new(center.X + xOff, posY, center.Z + zOff)
	local lookDir = (center - unitPos) * Vector3.new(1,0,1)
	return CFrame.lookAt(unitPos, unitPos + lookDir)
end

-- Grid Operations
local function placeUnit(player, brainrot, tierIndex, slotIndex)
	local gridData = getPlayerGrid(player)
	if not gridData.slots[tierIndex] then gridData.slots[tierIndex] = {} end
	
	if slotIndex < 1 or slotIndex > getTotalSlots(player) then return false, "Invalid slot" end
	if gridData.slots[tierIndex][slotIndex] then return false, "Occupied" end
	
	gridData.slots[tierIndex][slotIndex] = brainrot
	brainrot:SetAttribute("GridSlot", slotIndex)
	brainrot:SetAttribute("TierIndex", tierIndex)
	
	local cf = getSlotCFrame(player, tierIndex, slotIndex)
	if brainrot:IsA("Model") then brainrot:PivotTo(cf) else brainrot.CFrame = cf end
	
	GridUpdatedEvent:FireClient(player, tierIndex, slotIndex, brainrot.Name, "placed")
	return true
end

local function moveUnit(player, tier, from, to)
	local gridData = getPlayerGrid(player)
	if not gridData.slots[tier] then return false, "Invalid tier" end
	
	local unit = gridData.slots[tier][from]
	if not unit then return false, "Empty source" end
	if gridData.slots[tier][to] then return false, "Occupied target" end
	
	gridData.slots[tier][from], gridData.slots[tier][to] = nil, unit
	unit:SetAttribute("GridSlot", to)
	
	local cf = getSlotCFrame(player, tier, to)
	if unit:IsA("Model") then unit:PivotTo(cf) else unit.CFrame = cf end
	
	GridUpdatedEvent:FireClient(player, tier, to, unit.Name, "moved")
	return true
end

local function swapUnits(player, tier, s1, s2)
	local gridData = getPlayerGrid(player)
	if not gridData.slots[tier] then return false, "Invalid tier" end
	
	local u1, u2 = gridData.slots[tier][s1], gridData.slots[tier][s2]
	if not u1 and not u2 then return false, "Nothing to swap" end
	
	gridData.slots[tier][s1], gridData.slots[tier][s2] = u2, u1
	
	if u1 then
		u1:SetAttribute("GridSlot", s2)
		local cf = getSlotCFrame(player, tier, s2)
		if u1:IsA("Model") then u1:PivotTo(cf) else u1.CFrame = cf end
		GridUpdatedEvent:FireClient(player, tier, s2, u1.Name, "swapped")
	end
	if u2 then
		u2:SetAttribute("GridSlot", s1)
		local cf = getSlotCFrame(player, tier, s1)
		if u2:IsA("Model") then u2:PivotTo(cf) else u2.CFrame = cf end
		GridUpdatedEvent:FireClient(player, tier, s1, u2.Name, "swapped")
	end
	return true
end

-- Handlers
PlaceUnitFunction.OnServerInvoke = function(player, id, tier, slot)
	for _, b in CollectionService:GetTagged(BRAINROT_TAG) do
		if b:GetAttribute("UnitId") == id and b:GetAttribute("OwnerId") == player.UserId then
			return placeUnit(player, b, tier, slot)
		end
	end
	return false, "Unit not found"
end

MoveUnitFunction.OnServerInvoke = function(player, tier, f, t) return moveUnit(player, tier, f, t) end
SwapUnitsFunction.OnServerInvoke = function(player, tier, s1, s2) return swapUnits(player, tier, s1, s2) end

StashUnitFunction.OnServerInvoke = function(player, tier, slot)
	local grid = getPlayerGrid(player)
	if not grid.slots[tier] then return false, "Invalid tier" end
	local unit = grid.slots[tier][slot]
	if not unit then return false, "Empty" end
	
	grid.slots[tier][slot] = nil
	unit:SetAttribute("GridSlot", nil)
	unit:SetAttribute("TierIndex", nil)
	GridUpdatedEvent:FireClient(player, tier, slot, nil, "stashed")
	
	if _G.BrainrotManager and _G.BrainrotManager.RemoveBrainrotToInventory then
		-- Just update stats, don't double remove (as it's already removed from grid)
		-- Actually, stash usually implies putting back to inventory.
		-- BrainrotManager.RemoveBrainrotToInventory expects unitName/rarity
		_G.BrainrotManager.RemoveBrainrotToInventory(player, unit:GetAttribute("UnitType"), unit:GetAttribute("Rarity"))
	end
	return true
end

GetGridFunction.OnServerInvoke = function(player)
	local grid = getPlayerGrid(player)
	local state = {}
	for t, slots in pairs(grid.slots) do
		state[t] = {}
		for s, u in pairs(slots) do state[t][s] = u:GetAttribute("UnitType") or u.Name end
	end
	return { gridSize = grid.gridSize, slots = state }
end

Players.PlayerRemoving:Connect(function(plr) PlayerGrids[plr.UserId] = nil end)

print("✓ GridManager initialized")

-- Export for other server scripts
_G.GridManager = {
	PlaceUnit = placeUnit,
	GetSlotCFrame = getSlotCFrame,
	FindEmptySlot = function(p)
		local g = getPlayerGrid(p)
		local maxSlots = getTotalSlots(p)

		-- Try current tier first
		local ts = _G.MapSystem and _G.MapSystem.GetPlayerTierSystem(p)
		local startTier = ts and ts.CurrentTier or 1

		-- Check current tier
		if not g.slots[startTier] then g.slots[startTier] = {} end
		if #g.slots[startTier] < maxSlots then -- Simple check (count keys)
			for i=1, maxSlots do if not g.slots[startTier][i] then return startTier, i end end
		end

		-- If full, check if we can expand
		if _G.MapSystem then
			local current = _G.MapSystem.GetCurrentTier(p)
			if current and current.TierIndex == startTier then
				-- Spawn new tier
				local newTier = _G.MapSystem.SpawnTierPlot(p, current)
				if newTier then
					if not g.slots[newTier.TierIndex] then g.slots[newTier.TierIndex] = {} end
					return newTier.TierIndex, 1
				end
			end
		end

		return nil, nil -- Full
	end,
	StashUnit = function(p, t, s) return StashUnitFunction.OnServerInvoke(p, t, s) end,
	GetGridPositions = function(p)
		local pos = {}
		local g = getPlayerGrid(p)
		for t, slots in pairs(g.slots) do
			for s, u in pairs(slots) do
				pos[tostring(t).."_"..tostring(s)] = {
					unitType = u:GetAttribute("UnitType"),
					rarity = u:GetAttribute("Rarity"),
					unitId = u:GetAttribute("UnitId"),
					tier = t,
					slot = s
				}
			end
		end
		return pos
	end
}
