--[[
	PrestigeManager Server Module
	
	Handles:
	1. Meatball calculation based on lifetime earnings
	2. Prestige execution (reset + award meatballs)
	3. Meatball Shop purchases
	4. Golden Meatball Altar creation and interaction
	5. Income multipliers from meatballs and upgrades
	
	CONVERTED TO MODULE SCRIPT
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Lazy Config
local PrestigeConfig

local function getPrestigeConfig()
	if not PrestigeConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		PrestigeConfig = require(Shared:WaitForChild("PrestigeConfig"))
	end
	return PrestigeConfig
end

local DataService = require(script.Parent.DataService)
-- We can require DataManager directly now if needed for Reset, but _G works broadly for now.
-- Actually, let's use _G.DataManager for reset to avoid cyclic dependency if DataManager requires PrestigeManager 
-- (DataManager reads PrestigeManager for starting bonus).
-- Circular dependency risk: DataManager -> PrestigeManager (Bonus) -> DataManager (Reset). 
-- Solution: One must use lazy access. PrestigeManager using _G.DataManager inside execution function is safe lazy access.

-- Remotes
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PrestigeEvent = RemoteEvents:FindFirstChild("PrestigeEvent") or Instance.new("RemoteEvent")
PrestigeEvent.Name = "PrestigeEvent"
PrestigeEvent.Parent = RemoteEvents

local COMPONENT_KEY = "Prestige"
local DEFAULT_PRESTIGE_DATA = {
	lifetimeEarnings = 0,
	totalMeatballs = 0,
	spentMeatballs = 0,
	prestigeCount = 0,
	meatballUpgrades = {},
}

-- Module
local PrestigeManager = {}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function getPrestigeData(player)
	local data = DataService.GetComponentData(player, COMPONENT_KEY)
	if data then return data end
	if DataService.IsLoaded(player) then
		local d = {}
		for k, v in pairs(DEFAULT_PRESTIGE_DATA) do
			if type(v) == "table" then d[k] = {} else d[k] = v end
		end
		DataService.SetComponentData(player, COMPONENT_KEY, d)
		return DataService.GetComponentData(player, COMPONENT_KEY)
	end
	return nil
end

local function calculateTotalMeatballsFromEarnings(lifetimeEarnings)
	local pc = getPrestigeConfig()
	if lifetimeEarnings < pc.MEATBALL_DIVISOR then return 0 end
	return math.floor(pc.MEATBALL_MULTIPLIER * math.sqrt(lifetimeEarnings / pc.MEATBALL_DIVISOR))
end

local function calculatePendingMeatballs(player)
	local data = getPrestigeData(player)
	if not data then return 0, 0 end
	local current = data.totalMeatballs
	local projected = calculateTotalMeatballsFromEarnings(data.lifetimeEarnings)
	return math.max(0, projected - current), projected
end

--------------------------------------------------------------------------------
-- ALTAR LOGIC
--------------------------------------------------------------------------------

local function createAltar()
	task.wait(2)
	local mainIsland = Workspace:WaitForChild("MainIsland", 10)
	if not mainIsland then
		mainIsland = Instance.new("Part")
		mainIsland.Name = "MainIsland"
		mainIsland.Size = Vector3.new(100, 1, 100)
		mainIsland.Anchored = true
		mainIsland.Parent = Workspace
	end
	
	local model = Instance.new("Model")
	model.Name = "GoldenMeatballAltar"
	
	local sphere = Instance.new("Part")
	sphere.Name = "Sphere"
	sphere.Size = Vector3.new(12, 12, 12)
	sphere.Shape = Enum.PartType.Ball
	sphere.Color = Color3.fromRGB(255, 215, 0)
	sphere.Material = Enum.Material.Neon
	sphere.Anchored = true
	sphere.Position = Vector3.new(30, 40, 50)
	sphere.Parent = model
	
	task.spawn(function()
		local RunService = game:GetService("RunService")
		local y = sphere.Position.Y
		local t = 0
		RunService.Heartbeat:Connect(function(dt)
			if not sphere or not sphere.Parent then return end
			t += dt
			sphere.Position = Vector3.new(sphere.Position.X, y + math.sin(t)*2, sphere.Position.Z)
			sphere.Orientation += Vector3.new(0, 1, 0)
		end)
	end)
	
	local p = Instance.new("ProximityPrompt")
	p.ObjectText = "Golden Meatball Altar"
	p.ActionText = "Open Prestige Menu"
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.MaxActivationDistance = 20
	p.Parent = sphere
	
	p.Triggered:Connect(function(player)
		local pending, _ = calculatePendingMeatballs(player)
		local data = getPrestigeData(player)
		if data then
			PrestigeEvent:FireClient(player, "OpenMenu", {
				totalMeatballs = data.totalMeatballs,
				spentMeatballs = data.spentMeatballs,
				pendingMeatballs = pending,
				lifetimeEarnings = data.lifetimeEarnings,
				upgrades = data.meatballUpgrades
			})
		end
	end)
	
	model.Parent = Workspace
	print("✓ Golden Meatball Altar created")
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

function PrestigeManager.Init()
	print("   PrestigeManager (Module) - Initializing")
	
	DataService.RegisterHandler(COMPONENT_KEY, {
		DefaultData = DEFAULT_PRESTIGE_DATA,
		OnLoad = function(p, d) 
			print("PrestigeManager: Loaded for " .. p.Name) 
		end,
		OnSave = function(p, d) return d end
	})
	
	PrestigeEvent.OnServerEvent:Connect(function(player, action, ...)
		local args = {...}
		if action == "Prestige" then
			PrestigeManager.ExecutePrestige(player)
		elseif action == "PurchaseUpgrade" then
			local success = PrestigeManager.PurchaseUpgrade(player, args[1])
			if success then
				local pending, _ = calculatePendingMeatballs(player)
				local data = getPrestigeData(player)
				if data then
					PrestigeEvent:FireClient(player, "UpdateData", {
						totalMeatballs = data.totalMeatballs,
						spentMeatballs = data.spentMeatballs,
						pendingMeatballs = pending,
						lifetimeEarnings = data.lifetimeEarnings,
						upgrades = data.meatballUpgrades
					})
				end
			end
		end
	end)
	
	task.spawn(createAltar)
	print("✓ PrestigeManager Initialized")
end

function PrestigeManager.AddLifetimeEarnings(player, amount)
	local data = getPrestigeData(player)
	if data then data.lifetimeEarnings += amount end
end

function PrestigeManager.GetMeatballIncomeMultiplier(player)
	local data = getPrestigeData(player)
	if not data then return 1 end
	local unspent = data.totalMeatballs - data.spentMeatballs
	local pc = getPrestigeConfig()
	return 1 + (unspent * pc.MEATBALL_BONUS_RATE)
end

function PrestigeManager.GetShopMultiplier(player)
	local data = getPrestigeData(player)
	if not data then return 1 end
	local m = 1
	local pc = getPrestigeConfig()
	for _, id in ipairs(data.meatballUpgrades) do
		local item = pc.GetItem(id)
		if item and item.Effect == "IncomeMultiplier" then m += item.Value end
	end
	return m
end

function PrestigeManager.GetTotalIncomeMultiplier(player)
	return PrestigeManager.GetMeatballIncomeMultiplier(player) * PrestigeManager.GetShopMultiplier(player)
end

function PrestigeManager.GetStartingMoneyBonus(player)
	local data = getPrestigeData(player)
	if not data then return 0 end
	local b = 0
	local pc = getPrestigeConfig()
	for _, id in ipairs(data.meatballUpgrades) do
		local item = pc.GetItem(id)
		if item and item.Effect == "StartingMoney" then b += item.Value end
	end
	return b
end

function PrestigeManager.ExecutePrestige(player)
	local pending = calculatePendingMeatballs(player)
	local pc = getPrestigeConfig()
	if pending < pc.MINIMUM_PRESTIGE_GAIN then return false, "Not enough meatballs" end
	
	local data = getPrestigeData(player)
	if not data then return false, "No Data" end
	
	data.totalMeatballs += pending
	data.prestigeCount += 1
	
	if _G.DataManager and _G.DataManager.ResetPlayerData then
		_G.DataManager.ResetPlayerData(player, true)
	else
		warn("PrestigeManager: Check DataManager usage")
	end
	
	player:LoadCharacter()
	PrestigeEvent:FireClient(player, "PrestigeCompleted", { gained = pending, total = data.totalMeatballs })
	return true
end

function PrestigeManager.PurchaseUpgrade(player, upgradeId)
	local data = getPrestigeData(player)
	if not data then return false end
	
	if not data then return false end
	
	local pc = getPrestigeConfig()
	local item = pc.GetItem(upgradeId)
	if not item then return false end
	
	for _, id in ipairs(data.meatballUpgrades) do
		if id == upgradeId then return false end
	end
	
	if data.totalMeatballs < item.UnlockAt then return false end
	
	local unspent = data.totalMeatballs - data.spentMeatballs
	if unspent < item.Price then return false end
	
	data.spentMeatballs += item.Price
	table.insert(data.meatballUpgrades, upgradeId)
	return true
end

-- Export API & Compatibility
PrestigeManager.GetPlayerData = function(player) return getPrestigeData(player) or DEFAULT_PRESTIGE_DATA end
PrestigeManager.InitializePlayerData = function(p, d) if d and DataService.IsLoaded(p) then DataService.SetComponentData(p, COMPONENT_KEY, d) end end

return PrestigeManager
