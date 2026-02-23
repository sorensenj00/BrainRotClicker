--[[
	BonusManager Server Module
	
	Central aggregator for all global player bonuses and multipliers.
	Ensures that Prestige, Mewing, Upgrades, and other systems stack correctly.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BonusManager = {}
local Services = {}

--------------------------------------------------------------------------------
-- AGGREGATORS
--------------------------------------------------------------------------------

function BonusManager.GetTotalIncomeMultiplier(player: Player): number
	local multi = 1.0
	
	-- 1. Prestige Multiplier
	local PrestigeManager = rawget(Services, "PrestigeManager")
	if PrestigeManager and PrestigeManager.GetTotalIncomeMultiplier then
		multi *= PrestigeManager.GetTotalIncomeMultiplier(player)
	end
	
	-- 2. Convenience Upgrades
	local ConvenienceUpgradesManager = rawget(Services, "ConvenienceUpgradesManager")
	if ConvenienceUpgradesManager and ConvenienceUpgradesManager.CalculateIncomeMultiplier then
		local upgs = ConvenienceUpgradesManager.GetPlayerUpgrades(player)
		multi *= ConvenienceUpgradesManager.CalculateIncomeMultiplier(upgs)
	end
	
	-- 3. Mewing Bonus
	local mewMulti = player:GetAttribute("MewingMultiplier")
	if mewMulti then
		multi *= mewMulti
	end
	
	return math.max(0.1, multi)
end

function BonusManager.GetTotalSpeedMultiplier(player: Player): number
	local multi = 1.0
	
	-- 1. Convenience Upgrades (Cycle Reduction)
	-- Note: CycleReduction is usually 0..0.75, so speed multiplier is 1 / (1 - reduction)
	local ConvenienceUpgradesManager = rawget(Services, "ConvenienceUpgradesManager")
	if ConvenienceUpgradesManager and ConvenienceUpgradesManager.CalculateCycleReduction then
		local upgs = ConvenienceUpgradesManager.GetPlayerUpgrades(player)
		local reduction = ConvenienceUpgradesManager.CalculateCycleReduction(upgs)
		multi *= (1 - reduction) -- Lower is faster in our production engine (it's measuring interval)
	end
	
	return math.max(0.1, multi)
end

function BonusManager.GetTotalLuckMultiplier(player: Player): number
	local bonus = 0
	
	-- 1. Convenience Upgrades (LuckyChance/CriticalChance)
	local ConvenienceUpgradesManager = rawget(Services, "ConvenienceUpgradesManager")
	if ConvenienceUpgradesManager and ConvenienceUpgradesManager.GetPlayerUpgrades then
		local upgs = ConvenienceUpgradesManager.GetPlayerUpgrades(player)
		-- Summing additive luck bonuses
		local conf = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ConvenienceUpgradesConfig"))
		for _, name in ipairs(upgs) do
			local c = conf.GetConfig(name)
			if c and c.EffectType == "LuckyChance" then
				bonus += c.EffectValue
			end
		end
	end
	
	return 1 + bonus
end

function BonusManager.GetTotalStorageMultiplier(player: Player): number
	local multi = 1.0
	
	-- Future: Add storage multipliers from Prestige or Special Items here
	
	return multi
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function BonusManager.Init(services)
	print("   BonusManager (Module) - Initializing")
	Services = services or {}
	print("✓ BonusManager Initialized")
end

-- Force a refresh of all systems that depend on global bonuses
function BonusManager.RefreshAll(player: Player)
	-- 1. Refresh Unit Production Attributes (HUD)
	local IPM = rawget(Services, "ItemProductionManager")
	if IPM and IPM.RefreshUnitAttributes then
		IPM.RefreshUnitAttributes(player)
	end
	
	-- 2. Refresh Storage Capacity
	local ISM = rawget(Services, "ItemStorageManager")
	if ISM and ISM.RefreshCapacity then
		ISM.RefreshCapacity(player)
	end
	
	-- 3. Sync to Client Attributes (for local UI speed predictions)
	player:SetAttribute("GlobalIncomeMultiplier", BonusManager.GetTotalIncomeMultiplier(player))
end

return BonusManager
