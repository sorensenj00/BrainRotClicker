--[[
	ShopManager Server Script
	Handles all purchase logic for the shop system.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopConfig"))

-- Remotes
local RE = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyUnitRemote = Instance.new("RemoteFunction", RE) BuyUnitRemote.Name = "BuyUnit"
local OwnershipChangedEvent = Instance.new("RemoteEvent", RE) OwnershipChangedEvent.Name = "OwnershipChanged"
local UnlockProgressChangedEvent = Instance.new("RemoteEvent", RE) UnlockProgressChangedEvent.Name = "UnlockProgressChanged"
local GetOwnershipRemote = Instance.new("RemoteFunction", RE) GetOwnershipRemote.Name = "GetOwnership"

-- State
local PlayerData = {} -- { [Player] = { owned = {}, unlock = 5 } }

-- Helper: Get Data
local function getData(player)
	if not PlayerData[player] then
		PlayerData[player] = { owned = {}, unlock = ShopConfig.INITIAL_UNLOCKED }
		for u, _ in pairs(ShopConfig.Units) do PlayerData[player].owned[u] = 0 end
	end
	return PlayerData[player]
end

-- Helpers
local function getOwned(player, unit) return getData(player).owned[unit] or 0 end
local function getUnlock(player) return getData(player).unlock end

local function updateUnlock(player)
	local data = getData(player)
	if data.unlock < ShopConfig.GetTotalUnits() then
		data.unlock += 1
		UnlockProgressChangedEvent:FireClient(player, data.unlock)
	end
end

-- Handlers
local function handleBuy(player, unitName)
	local data = getData(player)
	local unitCfg = ShopConfig.GetConfig(unitName)
	
	-- Checks
	if not unitCfg then return false, "Unknown unit" end
	if not ShopConfig.IsUnitUnlocked(unitName, data.unlock) then return false, "Locked" end
	
	local count = data.owned[unitName]
	local price = ShopConfig.CalculatePrice(unitName, count)
	
	local ls = player:FindFirstChild("leaderstats")
	local money = ls and ls:FindFirstChild("Money")
	if not money or money.Value < price then return false, "Not enough money" end
	
	-- Transaction
	money.Value -= price
	
	-- Spawn
	if _G.BrainrotManager then
		local unit = _G.BrainrotManager.SpawnBrainrot(player, unitCfg.ModelName)
		if not unit then
			money.Value += price -- Refund
			return false, "Spawn failed"
		end
		
		-- Pass true for isActive to correctly update active count
		local rarity = _G.BrainrotManager.AddToInventory(player, unitName, nil, true)
		local rCfg = _G.BrainrotManager.RARITY_CONFIG[rarity]
		local rMult = rCfg and rCfg.incomeMultiplier or 1
		
		-- Stats
		local newCount = count + 1
		local inc = ShopConfig.CalculateEffectiveIncome(unitName, newCount) * rMult
		local cyc = ShopConfig.CalculateEffectiveCycleTime(unitName, newCount)
		
		unit:SetAttribute("IncomeAmount", inc)
		unit:SetAttribute("IncomeInterval", cyc)
		unit:SetAttribute("UnitType", unitName)
		unit:SetAttribute("Rarity", rarity)
		
		-- Milestones
		if #ShopConfig.GetMilestonesReached(newCount) > #ShopConfig.GetMilestonesReached(count) then
			_G.BrainrotManager.UpdateAllUnitStats(player, unitName, inc, cyc)
		end
	end
	
	data.owned[unitName] = count + 1
	updateUnlock(player)
	
	local newPrice = ShopConfig.CalculatePrice(unitName, count + 1)
	OwnershipChangedEvent:FireClient(player, unitName, count + 1, newPrice)
	
	return true, "Purchased!"
end

BuyUnitRemote.OnServerInvoke = handleBuy

GetOwnershipRemote.OnServerInvoke = function(player)
	local data = getData(player)
	local res = { units = {}, unlockProgress = data.unlock }
	for u, c in pairs(data.owned) do
		res.units[u] = { count = c, price = ShopConfig.CalculatePrice(u, c) }
	end
	return res
end

-- Lifecycle
local function initPlayer(player)
	local data = getData(player)
	local f = Instance.new("Folder", player) f.Name = "OwnedUnits"
	for u, c in pairs(data.owned) do
		local v = Instance.new("IntValue", f) v.Name = u v.Value = c
	end
	local uv = Instance.new("IntValue", player) uv.Name = "UnlockProgress" uv.Value = data.unlock
end

Players.PlayerAdded:Connect(initPlayer)
Players.PlayerRemoving:Connect(function(p) PlayerData[p] = nil end)
for _, p in Players:GetPlayers() do task.spawn(initPlayer, p) end

-- API
_G.ShopManager = {
	GetOwnedCount = getOwned,
	GetUnlockProgress = getUnlock,
	SetPlayerData = function(player, owned, unlock)
		local data = getData(player)
		data.unlock = unlock
		data.owned = owned

		-- Sync IntValues if they exist (legacy support)
		local uv = player:FindFirstChild("UnlockProgress") if uv then uv.Value = unlock end
		local of = player:FindFirstChild("OwnedUnits")
		if of then
			for u, c in pairs(owned) do
				local v = of:FindFirstChild(u) if v then v.Value = c end
			end
		end
		
		UnlockProgressChangedEvent:FireClient(player, unlock)
		for u, c in pairs(owned) do
			OwnershipChangedEvent:FireClient(player, u, c, ShopConfig.CalculatePrice(u, c))
		end
	end,
	ResetPlayerData = function(player)
		local data = getData(player)
		data.unlock = ShopConfig.INITIAL_UNLOCKED
		for u, _ in pairs(data.owned) do data.owned[u] = 0 end
		_G.ShopManager.SetPlayerData(player, data.owned, data.unlock)
	end
}

print("✓ ShopManager Initialized")
