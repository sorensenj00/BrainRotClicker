--[[
	ConvenienceUpgradesManager Server Script
	
	Handles:
	1. Purchase of convenience upgrades
	2. Applying upgrade effects (walkspeed, income multipliers, etc.)
	3. Creating the Convenience Shop vendor on main island
	4. Spawning Auto-Collector bots
	5. Creating Speed Treadmill Bridge boost zones
	
	Works with ConvenienceUpgradesConfig for upgrade definitions.
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local _TweenService = game:GetService("TweenService")
local _RunService = game:GetService("RunService")

-- Modules
local ConvenienceUpgradesConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ConvenienceUpgradesConfig"))

-- Configuration
local SHOP_CONFIG = {
	VENDOR_SIZE = Vector3.new(6, 8, 6),
	VENDOR_POSITION_OFFSET = Vector3.new(30, 10, -30), -- Different position from Island Shop
	BOT_SPEED = 30, -- Walkspeed of collector bots
	BOT_COLLECT_INTERVAL = 5, -- Seconds between collections
}

-- Remote Events
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local PurchaseUpgradeEvent = RemoteEvents:FindFirstChild("PurchaseConvenienceUpgrade") or Instance.new("RemoteEvent")
PurchaseUpgradeEvent.Name = "PurchaseConvenienceUpgrade"
PurchaseUpgradeEvent.Parent = RemoteEvents

local GetUpgradesInfoEvent = RemoteEvents:FindFirstChild("GetConvenienceUpgradesInfo") or Instance.new("RemoteFunction")
GetUpgradesInfoEvent.Name = "GetConvenienceUpgradesInfo"
GetUpgradesInfoEvent.Parent = RemoteEvents

-- Player upgrade data (will be saved via DataManager)
local PlayerUpgrades: {[number]: {string}} = {} -- UserId -> list of owned upgrade names

-- Track active collector bots per player
local PlayerCollectorBots: {[number]: {Model}} = {}

--------------------------------------------------------------------------------
-- UPGRADE EFFECT CALCULATIONS
--------------------------------------------------------------------------------

--[[
	Calculates total income multiplier from owned upgrades.
	
	@param upgrades {string} - List of owned upgrade names
	@return number - Total multiplier (1.0 = base, 1.85 = +85%)
]]
local function calculateIncomeMultiplier(upgrades: {string}): number
	local multiplier = 1.0
	
	for _, upgradeName in upgrades do
		local config = ConvenienceUpgradesConfig.GetConfig(upgradeName)
		if config and config.EffectType == "IncomeMultiplier" then
			multiplier = multiplier + config.EffectValue
		end
	end
	
	return multiplier
end

--[[
	Calculates total cycle time reduction from owned upgrades.
	
	@param upgrades {string} - List of owned upgrade names
	@return number - Total reduction (0.0 = no reduction, 0.30 = 30% faster)
]]
local function calculateCycleReduction(upgrades: {string}): number
	local reduction = 0.0
	
	for _, upgradeName in upgrades do
		local config = ConvenienceUpgradesConfig.GetConfig(upgradeName)
		if config and config.EffectType == "CycleReduction" then
			reduction = reduction + config.EffectValue
		end
	end
	
	return math.min(reduction, 0.75) -- Cap at 75% reduction
end

--[[
	Calculates walkspeed multiplier from owned upgrades.
	
	@param upgrades {string} - List of owned upgrade names
	@return number - Total multiplier (1.0 = base)
]]
local function calculateWalkspeedMultiplier(upgrades: {string}): number
	local multiplier = 1.0
	
	for _, upgradeName in upgrades do
		local config = ConvenienceUpgradesConfig.GetConfig(upgradeName)
		if config and config.EffectType == "Walkspeed" then
			multiplier = multiplier + config.EffectValue
		end
	end
	
	return multiplier
end

--[[
	Gets the bridge speed multiplier.
	
	@param upgrades {string} - List of owned upgrade names
	@return number - Bridge speed multiplier (1 = normal, 2 or 3 = boosted)
]]
local function getBridgeSpeedMultiplier(upgrades: {string}): number
	local highest = 1
	
	for _, upgradeName in upgrades do
		local config = ConvenienceUpgradesConfig.GetConfig(upgradeName)
		if config and config.EffectType == "BridgeSpeed" then
			highest = math.max(highest, config.EffectValue)
		end
	end
	
	return highest
end

--[[
	Checks if player has a specific effect type.
	
	@param upgrades {string} - List of owned upgrade names
	@param effectType string - The effect type to check
	@return boolean
]]
local function hasEffect(upgrades: {string}, effectType: string): boolean
	for _, upgradeName in upgrades do
		local config = ConvenienceUpgradesConfig.GetConfig(upgradeName)
		if config and config.EffectType == effectType then
			return true
		end
	end
	return false
end

--[[
	Gets lucky chance value (for 2x bonus).
	
	@param upgrades {string} - List of owned upgrade names
	@return number - Chance (0.0 to 1.0)
]]
local function getLuckyChance(upgrades: {string}): number
	for _, upgradeName in upgrades do
		local config = ConvenienceUpgradesConfig.GetConfig(upgradeName)
		if config and config.EffectType == "LuckyChance" then
			return config.EffectValue
		end
	end
	return 0
end

--[[
	Gets critical chance value (for 5x bonus).
	
	@param upgrades {string} - List of owned upgrade names
	@return number - Chance (0.0 to 1.0)
]]
local function getCriticalChance(upgrades: {string}): number
	for _, upgradeName in upgrades do
		local config = ConvenienceUpgradesConfig.GetConfig(upgradeName)
		if config and config.EffectType == "CriticalChance" then
			return config.EffectValue
		end
	end
	return 0
end

--[[
	Counts how many auto-collector bots player should have.
	
	@param upgrades {string} - List of owned upgrade names
	@return number - Number of bots
]]
local function countAutoCollectorBots(upgrades: {string}): number
	local count = 0
	
	for _, upgradeName in upgrades do
		local config = ConvenienceUpgradesConfig.GetConfig(upgradeName)
		if config and config.EffectType == "AutoCollector" then
			count = count + config.EffectValue
		end
	end
	
	return count
end

--------------------------------------------------------------------------------
-- APPLY UPGRADE EFFECTS
--------------------------------------------------------------------------------

--[[
	Applies walkspeed and jump boosts to a player's character.
	Called when character spawns or upgrades are purchased.
	
	@param player Player - The player to apply effects to
]]
local function applyCharacterEffects(player: Player)
	local character = player.Character
	if not character then return end
	
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	
	local upgrades = PlayerUpgrades[player.UserId] or {}
	
	-- Apply walkspeed
	local walkMultiplier = calculateWalkspeedMultiplier(upgrades)
	humanoid.WalkSpeed = 16 * walkMultiplier -- 16 is default Roblox walkspeed
	
	-- Apply jump boost
	local jumpMultiplier = 1.0
	for _, upgradeName in upgrades do
		local config = ConvenienceUpgradesConfig.GetConfig(upgradeName)
		if config and config.EffectType == "JumpPower" then
			jumpMultiplier = jumpMultiplier + config.EffectValue
		end
	end
	humanoid.JumpPower = 50 * jumpMultiplier -- 50 is default Roblox jump power
	
	print(string.format("✓ Applied effects to %s: WalkSpeed=%.1f, JumpPower=%.1f", 
		player.Name, humanoid.WalkSpeed, humanoid.JumpPower))
end

--------------------------------------------------------------------------------
-- AUTO-COLLECTOR BOT SYSTEM
--------------------------------------------------------------------------------

--[[
	Creates a cute collector bot model for a player.
	
	@param player Player - The bot's owner
	@param botIndex number - Which bot this is (1, 2, etc.)
	@return Model - The bot model
]]
local function createCollectorBot(player: Player, botIndex: number): Model
	local bot = Instance.new("Model")
	bot.Name = "CollectorBot_" .. botIndex
	
	-- Main body (cute cube)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 3, 3)
		local botColor = botIndex == 1 and "Bright blue" or "Bright green"
	body.BrickColor = BrickColor.new(botColor)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = false
	body.CanCollide = false
	body.Parent = bot
	
	-- Make it round
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	
	-- Eyes
	local eye1 = Instance.new("Part")
	eye1.Name = "Eye1"
	eye1.Size = Vector3.new(0.5, 0.5, 0.5)
	eye1.BrickColor = BrickColor.new("White")
	eye1.Material = Enum.Material.Neon
	eye1.Anchored = false
	eye1.CanCollide = false
	eye1.Parent = bot
	
	local eye1Mesh = Instance.new("SpecialMesh")
	eye1Mesh.MeshType = Enum.MeshType.Sphere
	eye1Mesh.Parent = eye1
	
	local eye2 = eye1:Clone()
	eye2.Name = "Eye2"
	eye2.Parent = bot
	
	-- Weld eyes to body
	local weld1 = Instance.new("WeldConstraint")
	weld1.Part0 = body
	weld1.Part1 = eye1
	weld1.Parent = body
	eye1.CFrame = body.CFrame * CFrame.new(0.6, 0.5, -1.2)
	
	local weld2 = Instance.new("WeldConstraint")
	weld2.Part0 = body
	weld2.Part1 = eye2
	weld2.Parent = body
	eye2.CFrame = body.CFrame * CFrame.new(-0.6, 0.5, -1.2)
	
	-- Billboard with cute label
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(3, 0, 1, 0)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = body
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "🤖 Collector Bot " .. botIndex
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard
	
	bot.PrimaryPart = body
	
	-- Set ownership
	bot:SetAttribute("OwnerId", player.UserId)
	bot:SetAttribute("BotIndex", botIndex)
	
	-- Tag for system
	CollectionService:AddTag(bot, "CollectorBot")
	
	return bot
end

--[[
	Updates the collector bots for a player based on their upgrades.
	
	@param player Player - The player to update bots for
]]
local function updateCollectorBots(player: Player)
	local upgrades = PlayerUpgrades[player.UserId] or {}
	local neededBots = countAutoCollectorBots(upgrades)
	local currentBots = PlayerCollectorBots[player.UserId] or {}
	
	-- Get player's plot
	local plot = _G.BrainrotManager and _G.BrainrotManager.GetPlayerPlot(player)
	if not plot then
		return
	end
	
	-- Create new bots if needed
	while #currentBots < neededBots do
		local botIndex = #currentBots + 1
		local bot = createCollectorBot(player, botIndex)
		
		-- Get plot position for initial spawn
		local plotPart = plot:FindFirstChild("Island") or plot:FindFirstChildWhichIsA("BasePart")
		if plotPart then
			bot:PivotTo(plotPart.CFrame * CFrame.new(0, 10, 0))
		end
		
		bot.Parent = plot
		table.insert(currentBots, bot)
		print(string.format("✓ Spawned Collector Bot %d for %s", botIndex, player.Name))
	end
	
	-- Remove excess bots if player lost upgrades (shouldn't normally happen)
	while #currentBots > neededBots do
		local bot = table.remove(currentBots)
		if bot then
			bot:Destroy()
		end
	end
	
	PlayerCollectorBots[player.UserId] = currentBots
end

--------------------------------------------------------------------------------
-- VENDOR CREATION
--------------------------------------------------------------------------------

--[[
	Creates the Convenience Upgrades Shop vendor part on the main island.
]]
local function createConvenienceShopVendor()
	-- Wait for main island
	local mainIsland = workspace:WaitForChild("MainIsland", 10)
	if not mainIsland then
		warn("MainIsland not found, cannot create Convenience Shop vendor")
		return nil
	end
	
	-- Check if vendor already exists
	if mainIsland:FindFirstChild("ConvenienceShopVendor") then
		return mainIsland:FindFirstChild("ConvenienceShopVendor")
	end
	
	-- Get main island position
	local mainIslandPos = Vector3.new(0, 30, 0)
	local islandPart = mainIsland:FindFirstChild("Island") or mainIsland:FindFirstChildWhichIsA("BasePart")
	if islandPart then
		mainIslandPos = islandPart.Position
	end
	
	-- Create the vendor part
	local vendorPart = Instance.new("Part")
	vendorPart.Name = "ConvenienceShopVendor"
	vendorPart.Size = SHOP_CONFIG.VENDOR_SIZE
	vendorPart.BrickColor = BrickColor.new("Bright orange")
	vendorPart.Material = Enum.Material.Neon
	vendorPart.Anchored = true
	vendorPart.CanCollide = true
	vendorPart.Position = mainIslandPos + SHOP_CONFIG.VENDOR_POSITION_OFFSET
	
	-- Create BillboardGui for display
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "ShopDisplay"
	billboardGui.Size = UDim2.new(6, 0, 3, 0)
	billboardGui.StudsOffset = Vector3.new(0, 6, 0)
	billboardGui.AlwaysOnTop = false
	billboardGui.Parent = vendorPart
	
	-- Background frame
	local bgFrame = Instance.new("Frame")
	bgFrame.Name = "Background"
	bgFrame.Size = UDim2.new(1, 0, 1, 0)
	bgFrame.BackgroundColor3 = Color3.fromRGB(60, 40, 20)
	bgFrame.BackgroundTransparency = 0.2
	bgFrame.Parent = billboardGui
	
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0.1, 0)
	uiCorner.Parent = bgFrame
	
	-- Title label
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, 0, 0.4, 0)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "⚡ UPGRADES"
	titleLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Parent = bgFrame
	
	-- Subtitle label
	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.Size = UDim2.new(1, 0, 0.3, 0)
	subtitleLabel.Position = UDim2.new(0, 0, 0.4, 0)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Text = "Speed • Income • Bots"
	subtitleLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	subtitleLabel.TextScaled = true
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.Parent = bgFrame
	
	-- Instruction label
	local instructLabel = Instance.new("TextLabel")
	instructLabel.Name = "Instruction"
	instructLabel.Size = UDim2.new(1, 0, 0.25, 0)
	instructLabel.Position = UDim2.new(0, 0, 0.7, 0)
	instructLabel.BackgroundTransparency = 1
	instructLabel.Text = "Press E to open"
	instructLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	instructLabel.TextScaled = true
	instructLabel.Font = Enum.Font.Gotham
	instructLabel.Parent = bgFrame
	
	-- Tag for proximity detection
	CollectionService:AddTag(vendorPart, "ConvenienceShopVendor")
	
	-- Create ProximityPrompt for interaction
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ConvenienceShopPrompt"
	prompt.ActionText = "Open Upgrades"
	prompt.ObjectText = "Convenience Shop"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = vendorPart
	
	vendorPart.Parent = mainIsland
	
	print("✓ Created Convenience Shop vendor on Main Island")
	return vendorPart
end

--------------------------------------------------------------------------------
-- PURCHASE HANDLING
--------------------------------------------------------------------------------

--[[
	Handles a player's request to purchase an upgrade.
	
	@param player Player - The player attempting to purchase
	@param upgradeName string - The upgrade to purchase
	@return boolean, string - Success status and message
]]
local function handleUpgradePurchase(player: Player, upgradeName: string): (boolean, string)
	-- Get player's owned upgrades
	local ownedUpgrades = PlayerUpgrades[player.UserId] or {}
	
	-- Check if can purchase
	local canPurchase, reason = ConvenienceUpgradesConfig.CanPurchase(upgradeName, ownedUpgrades)
	if not canPurchase then
		return false, reason or "Cannot purchase"
	end
	
	-- Get upgrade config
	local config = ConvenienceUpgradesConfig.GetConfig(upgradeName)
	if not config then
		return false, "Upgrade not found"
	end
	
	-- Check money
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return false, "Could not find your money"
	end
	
	local money = leaderstats:FindFirstChild("Money")
	if not money then
		return false, "Could not find your money"
	end
	
	if money.Value < config.Price then
		return false, string.format("Not enough money! Need $%d, have $%d", config.Price, money.Value)
	end
	
	-- Deduct money
	money.Value = money.Value - config.Price
	
	-- Add to owned upgrades
	table.insert(ownedUpgrades, upgradeName)
	PlayerUpgrades[player.UserId] = ownedUpgrades
	
	-- Apply effects immediately
	applyCharacterEffects(player)
	updateCollectorBots(player)
	
	-- Update brainrot income/cycle if applicable
	applyBrainrotUpgrades(player)
	
	print(string.format("✓ %s purchased '%s' for $%d", player.Name, upgradeName, config.Price))
	
	return true, string.format("Purchased %s %s!", config.Icon, upgradeName)
end

--[[
	Applies income multiplier and cycle reduction to player's brainrots.
	
	@param player Player - The player to update
]]
function applyBrainrotUpgrades(player: Player)
	local upgrades = PlayerUpgrades[player.UserId] or {}
	local incomeMultiplier = calculateIncomeMultiplier(upgrades)
	local cycleReduction = calculateCycleReduction(upgrades)
	local luckyChance = getLuckyChance(upgrades)
	local criticalChance = getCriticalChance(upgrades)
	
	-- Store modifiers on player for BrainrotManager to read
	player:SetAttribute("IncomeMultiplier", incomeMultiplier)
	player:SetAttribute("CycleReduction", cycleReduction)
	player:SetAttribute("LuckyChance", luckyChance)
	player:SetAttribute("CriticalChance", criticalChance)
	
	print(string.format("✓ Updated %s's brainrot modifiers: Income=%.0f%%, Cycle=-%.0f%%, Lucky=%.0f%%, Crit=%.0f%%",
		player.Name, (incomeMultiplier - 1) * 100, cycleReduction * 100, luckyChance * 100, criticalChance * 100))
end

--------------------------------------------------------------------------------
-- REMOTE EVENT HANDLERS
--------------------------------------------------------------------------------

PurchaseUpgradeEvent.OnServerEvent:Connect(function(player, upgradeName)
	local success, message = handleUpgradePurchase(player, upgradeName)
	PurchaseUpgradeEvent:FireClient(player, success, message)
end)

GetUpgradesInfoEvent.OnServerInvoke = function(player)
	local ownedUpgrades = PlayerUpgrades[player.UserId] or {}
	
	return {
		OwnedUpgrades = ownedUpgrades,
		AllUpgrades = ConvenienceUpgradesConfig.GetAllUpgradesSorted(),
		Categories = ConvenienceUpgradesConfig.GetCategories(),
	}
end

--------------------------------------------------------------------------------
-- PLAYER EVENTS
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Only initialize if not already set by DataManager (avoids overwriting restored upgrades)
	if PlayerUpgrades[player.UserId] == nil then
		PlayerUpgrades[player.UserId] = {}
	end
	
	-- Apply effects when character spawns
	player.CharacterAdded:Connect(function()
		task.wait(0.5) -- Wait for humanoid
		applyCharacterEffects(player)
	end)
	
	-- Apply to existing character
	if player.Character then
		applyCharacterEffects(player)
	end
end

local function onPlayerRemoving(player: Player)
	-- Clean up bots
	local bots = PlayerCollectorBots[player.UserId]
	if bots then
		for _, bot in bots do
			bot:Destroy()
		end
	end
	PlayerCollectorBots[player.UserId] = nil
	
	-- Clear upgrades from memory (DataManager handles saving)
	PlayerUpgrades[player.UserId] = nil
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   ConvenienceUpgradesManager - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Connect player events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	-- Handle existing players
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	
	-- Wait for other systems
	task.wait(2)
	
	-- Create the vendor
	createConvenienceShopVendor()
	
	print("✓ ConvenienceUpgradesManager initialized")
	print("═══════════════════════════════════════════")
end

task.spawn(initialize)

--------------------------------------------------------------------------------
-- MODULE API
--------------------------------------------------------------------------------

_G.ConvenienceUpgrades = {
	GetPlayerUpgrades = function(player: Player): {string}
		return PlayerUpgrades[player.UserId] or {}
	end,
	SetPlayerUpgrades = function(player: Player, upgrades: {string})
		PlayerUpgrades[player.UserId] = upgrades
		applyCharacterEffects(player)
		updateCollectorBots(player)
		applyBrainrotUpgrades(player)
	end,
	CalculateIncomeMultiplier = calculateIncomeMultiplier,
	CalculateCycleReduction = calculateCycleReduction,
	GetBridgeSpeedMultiplier = getBridgeSpeedMultiplier,
	HasTeleportHome = function(player: Player): boolean
		local upgrades = PlayerUpgrades[player.UserId] or {}
		return hasEffect(upgrades, "TeleportHome")
	end,
}
