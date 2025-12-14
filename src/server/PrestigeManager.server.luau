--[[
	PrestigeManager Server Script
	
	REFACTORED: Now uses DataService component-based persistence.
	Prestige data is stored directly in Profile.Data.Prestige.
	
	Handles:
	1. Meatball calculation based on lifetime earnings
	2. Prestige execution (reset + award meatballs)
	3. Meatball Shop purchases
	4. Golden Meatball Altar creation and interaction
	5. Income multipliers from meatballs and upgrades
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Wait for shared modules
local PrestigeConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PrestigeConfig"))

-- DataService for persistence
local DataService = require(script.Parent.DataService)

-- Remote Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local PrestigeEvent = RemoteEvents:FindFirstChild("PrestigeEvent") or Instance.new("RemoteEvent")
PrestigeEvent.Name = "PrestigeEvent"
PrestigeEvent.Parent = RemoteEvents

-- Component key for DataService
local COMPONENT_KEY = "Prestige"

-- Default prestige data
local DEFAULT_PRESTIGE_DATA = {
	lifetimeEarnings = 0,
	totalMeatballs = 0,
	spentMeatballs = 0,
	prestigeCount = 0,
	meatballUpgrades = {},
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
	Gets the prestige data directly from Profile.Data.Prestige.
	This is the authoritative source of truth.
]]
local function getPrestigeData(player: Player): {[string]: any}?
	local data = DataService.GetComponentData(player, COMPONENT_KEY)
	if data then
		return data
	end
	
	-- Initialize if not exists and profile is loaded
	if DataService.IsLoaded(player) then
		local defaultsCopy = {}
		for k, v in pairs(DEFAULT_PRESTIGE_DATA) do
			if type(v) == "table" then
				defaultsCopy[k] = {}
			else
				defaultsCopy[k] = v
			end
		end
		DataService.SetComponentData(player, COMPONENT_KEY, defaultsCopy)
		return DataService.GetComponentData(player, COMPONENT_KEY)
	end
	
	return nil
end

--[[
	Calculates how many meatballs a player should have based on lifetime earnings.
	Formula: 150 * sqrt(LifetimeEarnings / 1,000,000)
]]
local function calculateTotalMeatballsFromEarnings(lifetimeEarnings)
	if lifetimeEarnings < PrestigeConfig.MEATBALL_DIVISOR then
		return 0
	end
	
	local result = PrestigeConfig.MEATBALL_MULTIPLIER * math.sqrt(lifetimeEarnings / PrestigeConfig.MEATBALL_DIVISOR)
	return math.floor(result)
end

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
	Calculates pending meatballs (meatballs to gain if prestige now).
	Returns: pendingAmount, newTotal
]]
local function calculatePendingMeatballs(player)
	local data = getPrestigeData(player)
	if not data then return 0, 0 end
	
	local currentTotal = data.totalMeatballs
	
	-- Calculate what the total SHOULD be based on lifetime earnings
	local projectedTotal = calculateTotalMeatballsFromEarnings(data.lifetimeEarnings)
	
	-- Pending is the difference
	local pending = math.max(0, projectedTotal - currentTotal)
	
	return pending, projectedTotal
end

--[[
	Adds to lifetime earnings. Called by BrainrotManager when income is generated.
	Data is automatically persisted by ProfileService.
]]
local function addLifetimeEarnings(player, amount)
	local data = getPrestigeData(player)
	if data then
		data.lifetimeEarnings = data.lifetimeEarnings + amount
	end
end

--[[
	Gets the income multiplier from unspent meatballs.
	Formula: 1 + (UnspentMeatballs * 0.02)
]]
local function getMeatballIncomeMultiplier(player)
	local data = getPrestigeData(player)
	if not data then return 1 end
	
	local unspent = data.totalMeatballs - data.spentMeatballs
	return 1 + (unspent * PrestigeConfig.MEATBALL_BONUS_RATE)
end

--[[
	Gets the income multiplier from shop upgrades.
]]
local function getShopMultiplier(player)
	local data = getPrestigeData(player)
	if not data then return 1 end
	
	local multiplier = 1
	
	for _, upgradeId in ipairs(data.meatballUpgrades) do
		local item = PrestigeConfig.GetItem(upgradeId)
		if item and item.Effect == "IncomeMultiplier" then
			multiplier = multiplier + item.Value
		end
	end
	
	return multiplier
end

--[[
	Gets the total income multiplier (Meatballs * Shop).
]]
local function getTotalIncomeMultiplier(player)
	return getMeatballIncomeMultiplier(player) * getShopMultiplier(player)
end

--[[
	Gets starting money bonus from upgrades.
]]
local function getStartingMoneyBonus(player)
	local data = getPrestigeData(player)
	if not data then return 0 end
	
	local bonus = 0
	
	for _, upgradeId in ipairs(data.meatballUpgrades) do
		local item = PrestigeConfig.GetItem(upgradeId)
		if item and item.Effect == "StartingMoney" then
			bonus = bonus + item.Value
		end
	end
	
	return bonus
end

--[[
	Executes the prestige.
]]
local function executePrestige(player)
	local pending, _ = calculatePendingMeatballs(player)
	
	if pending < PrestigeConfig.MINIMUM_PRESTIGE_GAIN then
		return false, "Not enough meatballs to prestige (Min: " .. PrestigeConfig.MINIMUM_PRESTIGE_GAIN .. ")"
	end
	
	local data = getPrestigeData(player)
	if not data then return false, "Profile not loaded" end
	
	-- Update prestige data (auto-saved by ProfileService)
	data.totalMeatballs = data.totalMeatballs + pending
	data.prestigeCount = data.prestigeCount + 1
	
	-- Reset game progress via DataManager
	if _G.DataManager and _G.DataManager.ResetPlayerData then
		_G.DataManager.ResetPlayerData(player, true) -- true = keep prestige data
	else
		warn("DataManager.ResetPlayerData not found!")
		return false, "Internal error: Could not reset data"
	end
	
	-- Respawn character to reset position
	player:LoadCharacter()
	
	-- Notify client
	PrestigeEvent:FireClient(player, "PrestigeCompleted", {
		gained = pending,
		total = data.totalMeatballs
	})
	
	print(string.format("✓ %s prestiged! Gained %d meatballs (Total: %d)", player.Name, pending, data.totalMeatballs))
	return true, "Success"
end

--[[
	Purchases a meatball shop upgrade.
]]
local function purchaseUpgrade(player, upgradeId)
	local data = getPrestigeData(player)
	if not data then return false, "Profile not loaded" end
	
	local item = PrestigeConfig.GetItem(upgradeId)
	
	if not item then
		return false, "Item not found"
	end
	
	-- Check if already owned
	for _, ownedId in ipairs(data.meatballUpgrades) do
		if ownedId == upgradeId then
			return false, "Already owned"
		end
	end
	
	-- Check unlock requirement
	if data.totalMeatballs < item.UnlockAt then
		return false, "Item locked"
	end
	
	-- Check price (Unspent meatballs)
	local unspent = data.totalMeatballs - data.spentMeatballs
	if unspent < item.Price then
		return false, "Not enough meatballs"
	end
	
	-- Deduct price (auto-saved by ProfileService)
	data.spentMeatballs = data.spentMeatballs + item.Price
	
	-- Add upgrade
	table.insert(data.meatballUpgrades, upgradeId)
	
	print(string.format("✓ %s purchased meatball upgrade: %s", player.Name, item.Name))
	return true, "Success"
end

--[[
	Gets the player data - compatibility wrapper.
]]
local function getPlayerData(player)
	return getPrestigeData(player) or DEFAULT_PRESTIGE_DATA
end

--[[
	Initializes player data from saved data (legacy compatibility).
]]
local function initializePlayerData(player, savedData)
	if savedData and DataService.IsLoaded(player) then
		DataService.SetComponentData(player, COMPONENT_KEY, savedData)
	end
end

--------------------------------------------------------------------------------
-- DATA SERVICE HANDLER
--------------------------------------------------------------------------------

-- Register with DataService for automatic persistence
DataService.RegisterHandler(COMPONENT_KEY, {
	DefaultData = DEFAULT_PRESTIGE_DATA,
	
	OnLoad = function(player: Player, data: any)
		-- Data is already in Profile.Data.Prestige
		local meatballs = data and data.totalMeatballs or 0
		local prestiges = data and data.prestigeCount or 0
		print(string.format("PrestigeManager: Loaded for %s (%d meatballs, %d prestiges)", 
			player.Name, meatballs, prestiges))
	end,
	
	OnSave = function(player: Player, data: any)
		-- Data is already kept up-to-date in Profile.Data.Prestige
		return data
	end
})

--------------------------------------------------------------------------------
-- ALTAR CREATION
--------------------------------------------------------------------------------

local function createAltar()
	-- Wait for map to load
	task.wait(2)
	
	local mainIsland = Workspace:WaitForChild("MainIsland", 10)
	if not mainIsland then
		-- Create main island if it doesn't exist (fallback)
		mainIsland = Instance.new("Part")
		mainIsland.Name = "MainIsland"
		mainIsland.Size = Vector3.new(100, 1, 100)
		mainIsland.Position = Vector3.new(0, 0, 0)
		mainIsland.Anchored = true
		mainIsland.Parent = Workspace
	end
	
	local altarModel = Instance.new("Model")
	altarModel.Name = "GoldenMeatballAltar"
	
	-- Main sphere
	local sphere = Instance.new("Part")
	sphere.Name = "Sphere"
	sphere.Size = Vector3.new(12, 12, 12)
	sphere.Shape = Enum.PartType.Ball
	sphere.Color = Color3.fromRGB(255, 215, 0) -- Gold
	sphere.Material = Enum.Material.Neon
	sphere.Anchored = true
	sphere.CanCollide = true
	sphere.Position = Vector3.new(30, 40, 50) -- Positioned at same Y as shops
	sphere.Parent = altarModel
	
	-- Add floating animation
	task.spawn(function()
		local RunService = game:GetService("RunService")
		local originalY = sphere.Position.Y
		local t = 0
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			if not sphere or not sphere.Parent then
				connection:Disconnect()
				return
			end
			t = t + dt
			sphere.Position = Vector3.new(sphere.Position.X, originalY + math.sin(t) * 2, sphere.Position.Z)
			sphere.Orientation = sphere.Orientation + Vector3.new(0, 1, 0)
		end)
	end)
	
	-- Add particles
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxassetid://243098098" -- Generic sparkle
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 255, 0))
	particles.Size = NumberSequence.new(0.5, 0)
	particles.Lifetime = NumberRange.new(1, 2)
	particles.Rate = 20
	particles.Speed = NumberRange.new(5, 10)
	particles.SpreadAngle = Vector2.new(360, 360)
	particles.Parent = sphere
	
	-- Add ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Golden Meatball Altar"
	prompt.ActionText = "Open Prestige Menu"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 20
	prompt.RequiresLineOfSight = false
	prompt.Parent = sphere
	
	prompt.Triggered:Connect(function(player)
		-- Send current data to client
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
	
	altarModel.Parent = Workspace
	print("✓ Golden Meatball Altar created")
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

-- Handle client requests
PrestigeEvent.OnServerEvent:Connect(function(player, action, ...)
	local args = {...}
	
	if action == "Prestige" then
		executePrestige(player)
	elseif action == "PurchaseUpgrade" then
		local upgradeId = args[1]
		local success, _ = purchaseUpgrade(player, upgradeId)
		if success then
			-- Refresh client UI
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

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

task.spawn(createAltar)

-- Export API (backwards compatibility)
_G.PrestigeManager = {
	GetPlayerData = getPlayerData,
	InitializePlayerData = initializePlayerData,
	AddLifetimeEarnings = addLifetimeEarnings,
	GetTotalIncomeMultiplier = getTotalIncomeMultiplier,
	GetStartingMoneyBonus = getStartingMoneyBonus,
	ResetPlayerData = function(player)
		-- Reset prestige data to defaults (but this is usually NOT called on prestige)
		local defaultsCopy = {}
		for k, v in pairs(DEFAULT_PRESTIGE_DATA) do
			if type(v) == "table" then
				defaultsCopy[k] = {}
			else
				defaultsCopy[k] = v
			end
		end
		DataService.SetComponentData(player, COMPONENT_KEY, defaultsCopy)
		print(string.format("✓ Reset prestige data for %s", player.Name))
	end,
}

print("✓ PrestigeManager initialized (DataService integration)")
