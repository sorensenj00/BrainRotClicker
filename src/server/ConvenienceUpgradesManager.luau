--[[
	ConvenienceUpgradesManager Server Module
	
	Handles:
	1. Purchase of convenience upgrades
	2. Applying upgrade effects (walkspeed, income multipliers, etc.)
	3. Creating the Convenience Shop vendor on main island
	4. Spawning Auto-Collector bots
	5. Creating Speed Treadmill Bridge boost zones
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConvenienceUpgradesConfig = require(Shared:WaitForChild("ConvenienceUpgradesConfig"))

-- Config
local _SHOP_CONFIG = {
	VENDOR_SIZE = Vector3.new(6, 8, 6),
	VENDOR_POSITION_OFFSET = Vector3.new(30, 10, -30),
	BOT_SPEED = 30,
	BOT_COLLECT_INTERVAL = 5,
}

-- Remotes
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local PurchaseUpgradeEvent = RemoteEvents:FindFirstChild("PurchaseConvenienceUpgrade") or Instance.new("RemoteEvent")
PurchaseUpgradeEvent.Name = "PurchaseConvenienceUpgrade"
PurchaseUpgradeEvent.Parent = RemoteEvents

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local GetUpgradesInfoEvent = RemoteFunctions:FindFirstChild("GetConvenienceUpgradesInfo") or Instance.new("RemoteFunction")
GetUpgradesInfoEvent.Name = "GetConvenienceUpgradesInfo"
GetUpgradesInfoEvent.Parent = RemoteFunctions

-- State
local PlayerUpgrades = {} 
local PlayerCollectorBots = {}
local PurchaseLocks = {}

local ConvenienceUpgradesManager = {}
local Services = {}

local LEGACY_UPGRADE_MAP: {[string]: string} = {
	["Speed Treadmill Bridge"] = "Bridge Thrusters I",
	["Walkspeed Boost I"] = "Runner Shoes I",
	["Jump Boost"] = "Jump Spring Mod",
	["Walkspeed Boost II"] = "Runner Shoes II",
	["Global Income +10%"] = "Profit Routing I",
	["Auto-Collector Bot I"] = "Collector Drone I",
	["Global Income +25%"] = "Profit Routing II",
	["Faster Cycles I"] = "Cycle Overclock I",
	["Auto-Collector Bot II"] = "Collector Drone II",
	["Faster Cycles II"] = "Cycle Overclock II",
	["Lucky Bonus Chance"] = "Lucky Payout Matrix",
	["Instant Teleport Home"] = "Home Warp Beacon",
	["Global Income +50%"] = "Profit Routing III",
	["Critical Bonus Chance"] = "Critical Payout Matrix",
	["Golden Speed Bridges"] = "Bridge Thrusters III",
}

local function getDataService()
	return rawget(Services, "DataService")
end

local function persistPlayerUpgrades(player: Player)
	local ds = getDataService()
	if ds and ds.SetComponentData then
		ds.SetComponentData(player, "convenienceUpgrades", PlayerUpgrades[player.UserId] or {})
	end
end

local function normalizeUpgradeList(upgrades: any): {string}
	if type(upgrades) ~= "table" then
		return {}
	end

	local seen = {}
	local normalized = {}
	for _, name in upgrades do
		if type(name) == "string" then
			local mapped = LEGACY_UPGRADE_MAP[name] or name
			if ConvenienceUpgradesConfig.GetConfig(mapped) and not seen[mapped] then
				seen[mapped] = true
				table.insert(normalized, mapped)
			end
		end
	end

	local changed = true
	while changed do
		changed = false
		for _, ownedName in normalized do
			local conf = ConvenienceUpgradesConfig.GetConfig(ownedName)
			local prereq = conf and conf.Prerequisite
			if prereq and not seen[prereq] then
				seen[prereq] = true
				table.insert(normalized, prereq)
				changed = true
			end
		end
	end

	table.sort(normalized, function(a, b)
		local ca = ConvenienceUpgradesConfig.GetConfig(a)
		local cb = ConvenienceUpgradesConfig.GetConfig(b)
		local pa = ca and ca.Price or math.huge
		local pb = cb and cb.Price or math.huge
		if pa == pb then
			return a < b
		end
		return pa < pb
	end)

	return normalized
end

local function sameUpgradeList(a: {string}, b: {string}): boolean
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function loadPlayerUpgrades(player: Player): {string}
	local ds = getDataService()
	local raw = {}
	if ds and ds.GetComponentData then
		raw = ds.GetComponentData(player, "convenienceUpgrades") or {}
	end

	local normalized = normalizeUpgradeList(raw)
	PlayerUpgrades[player.UserId] = normalized

	if not sameUpgradeList(raw, normalized) then
		persistPlayerUpgrades(player)
	end

	return normalized
end

--------------------------------------------------------------------------------
-- CALCULATIONS
--------------------------------------------------------------------------------

local function calculateIncomeMultiplier(upgrades)
	local m = 1.0
	for _, name in upgrades do
		local c = ConvenienceUpgradesConfig.GetConfig(name)
		if c and c.EffectType == "IncomeMultiplier" then
			m += c.EffectValue
		end
	end
	return math.max(0.1, m)
end

local function calculateCycleReduction(upgrades)
	local r = 0.0
	for _, name in upgrades do
		local c = ConvenienceUpgradesConfig.GetConfig(name)
		if c and c.EffectType == "CycleReduction" then
			r += c.EffectValue
		end
	end
	return math.min(r, 0.75)
end

local function calculateWalkspeedMultiplier(upgrades)
	local m = 1.0
	for _, name in upgrades do
		local c = ConvenienceUpgradesConfig.GetConfig(name)
		if c and c.EffectType == "Walkspeed" then
			m += c.EffectValue
		end
	end
	return m
end

local function getBridgeSpeedMultiplier(upgrades)
	local h = 1
	for _, name in upgrades do
		local c = ConvenienceUpgradesConfig.GetConfig(name)
		if c and c.EffectType == "BridgeSpeed" then
			h = math.max(h, c.EffectValue)
		end
	end
	return h
end

local function hasEffect(upgrades, effectType)
	for _, name in upgrades do
		local c = ConvenienceUpgradesConfig.GetConfig(name)
		if c and c.EffectType == effectType then
			return true
		end
	end
	return false
end

local function getLuckyChance(upgrades)
	local chance = 0
	for _, name in upgrades do
		local c = ConvenienceUpgradesConfig.GetConfig(name)
		if c and c.EffectType == "LuckyChance" then
			chance += c.EffectValue
		end
	end
	return math.clamp(chance, 0, 0.75)
end

local function getCriticalChance(upgrades)
	local chance = 0
	for _, name in upgrades do
		local c = ConvenienceUpgradesConfig.GetConfig(name)
		if c and c.EffectType == "CriticalChance" then
			chance += c.EffectValue
		end
	end
	return math.clamp(chance, 0, 0.5)
end

local function countAutoCollectorBots(upgrades)
	local c = 0
	for _, name in upgrades do
		local conf = ConvenienceUpgradesConfig.GetConfig(name)
		if conf and conf.EffectType == "AutoCollector" then
			c += conf.EffectValue
		end
	end
	return c
end

--------------------------------------------------------------------------------
-- APPLY EFFECTS
--------------------------------------------------------------------------------

local function applyCharacterEffects(player)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	
	local upgrades = PlayerUpgrades[player.UserId] or {}
	
	local wm = calculateWalkspeedMultiplier(upgrades)
	hum.WalkSpeed = 16 * wm
	
	local jm = 1.0
	for _, name in upgrades do
		local c = ConvenienceUpgradesConfig.GetConfig(name)
		if c and c.EffectType == "JumpPower" then
			jm += c.EffectValue
		end
	end
	hum.JumpPower = 50 * jm
end

function ConvenienceUpgradesManager.ApplyBrainrotUpgrades(player)
	local upgrades = PlayerUpgrades[player.UserId] or {}
	local inc = calculateIncomeMultiplier(upgrades)
	local cyc = calculateCycleReduction(upgrades)
	local luck = getLuckyChance(upgrades)
	local crit = getCriticalChance(upgrades)
	
	player:SetAttribute("IncomeMultiplier", inc)
	player:SetAttribute("CycleReduction", cyc)
	player:SetAttribute("LuckyChance", luck)
	player:SetAttribute("CriticalChance", crit)
end

--------------------------------------------------------------------------------
-- BOTS
--------------------------------------------------------------------------------

local function createCollectorBot(player, index)
	local bot = Instance.new("Model")
	bot.Name = "CollectorBot_" .. index
	
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(3, 3, 3)
	body.BrickColor = BrickColor.new("Bright blue")
	body.Material = Enum.Material.SmoothPlastic
	body.CanCollide = false
	body.Parent = bot
	
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	
	-- Eyes
	local eye1 = Instance.new("Part")
	eye1.Size = Vector3.new(0.5, 0.5, 0.5)
	eye1.BrickColor = BrickColor.new("White")
	eye1.Material = Enum.Material.Neon
	eye1.CanCollide = false
	eye1.Parent = bot
	local em1 = Instance.new("SpecialMesh")
	em1.MeshType = Enum.MeshType.Sphere
	em1.Parent = eye1
	
	local eye2 = eye1:Clone()
	eye2.Parent = bot
	
	local w1 = Instance.new("WeldConstraint")
	w1.Part0 = body
	w1.Part1 = eye1
	w1.Parent = body
	eye1.CFrame = body.CFrame * CFrame.new(0.6, 0.5, -1.2)
	
	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = body
	w2.Part1 = eye2
	w2.Parent = body
	eye2.CFrame = body.CFrame * CFrame.new(-0.6, 0.5, -1.2)
	
	-- Billboard
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(3, 1)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.Parent = body
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "🤖 Bot " .. index
	lbl.TextColor3 = Color3.new(1,1,1)
	lbl.TextScaled = true
	lbl.Parent = bb
	
	bot.PrimaryPart = body
	bot:SetAttribute("OwnerId", player.UserId)
	bot:SetAttribute("BotIndex", index)
	CollectionService:AddTag(bot, "CollectorBot")
	
	return bot
end

local function updateCollectorBots(player)
	local upgrades = PlayerUpgrades[player.UserId] or {}
	local needed = countAutoCollectorBots(upgrades)
	local current = PlayerCollectorBots[player.UserId] or {}
	
	local BM = rawget(Services, "BrainrotManager")
	local plot = BM and BM.GetPlayerPlot(player)
	if not plot then return end
	
	while #current < needed do
		local idx = #current + 1
		local bot = createCollectorBot(player, idx)
		local pp = plot:FindFirstChild("Island") or plot:FindFirstChildWhichIsA("BasePart")
		if pp then
			bot:PivotTo(pp.CFrame * CFrame.new(0, 10, 0))
		end
		bot.Parent = plot
		table.insert(current, bot)
	end
	
	while #current > needed do
		local bot = table.remove(current)
		if bot then
			bot:Destroy()
		end
	end
	
	PlayerCollectorBots[player.UserId] = current
end

--------------------------------------------------------------------------------
-- VENDOR
--------------------------------------------------------------------------------

local function setupConvenienceShopVendor()
	local mainIsland = workspace:WaitForChild("MainIsland", 10)
	if not mainIsland then return end
	
	local shopsFolder = mainIsland:WaitForChild("Shops", 10)
	if not shopsFolder then return end
	
	local vendor = shopsFolder:WaitForChild("ConvenienceShop", 10)
	if not vendor then return end
	
	CollectionService:AddTag(vendor, "ConvenienceShopVendor")
	
	-- Ensure prompt exists
	local primary = vendor:FindFirstChild("Meshes/tung tung", true) or vendor.PrimaryPart or vendor:FindFirstChildWhichIsA("BasePart", true)
	if primary and not vendor:FindFirstChild("ShopPrompt", true) then
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "ShopPrompt"
		pp.ActionText = "Open Upgrades"
		pp.ObjectText = "Convenience Shop"
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.RequiresLineOfSight = false
		pp.MaxActivationDistance = 20
		pp.Parent = primary
	end
end

--------------------------------------------------------------------------------
-- PURCHASE
--------------------------------------------------------------------------------

function ConvenienceUpgradesManager.HandleUpgradePurchase(player, upgradeName)
	if type(upgradeName) ~= "string" or upgradeName == "" then
		return false, "Invalid upgrade"
	end

	if PurchaseLocks[player.UserId] then
		return false, "Purchase in progress"
	end
	PurchaseLocks[player.UserId] = true

	local owned = PlayerUpgrades[player.UserId] or {}
	local can, reason = ConvenienceUpgradesConfig.CanPurchase(upgradeName, owned)

	if not can then
		PurchaseLocks[player.UserId] = nil
		return false, reason or "Cannot purchase"
	end
	
	local conf = ConvenienceUpgradesConfig.GetConfig(upgradeName)
	if not conf then
		PurchaseLocks[player.UserId] = nil
		return false, "Upgrade not found"
	end

	local ds = getDataService()
	if ds and ds.GetMoney then
		if ds.GetMoney(player) < conf.Price then
			PurchaseLocks[player.UserId] = nil
			return false, "Not enough money"
		end
		if not ds.DeductMoney(player, conf.Price) then
			PurchaseLocks[player.UserId] = nil
			return false, "Purchase failed"
		end
	else
		local ls = player:FindFirstChild("leaderstats")
		local m = ls and ls:FindFirstChild("Money")
		if not m or m.Value < conf.Price then
			PurchaseLocks[player.UserId] = nil
			return false, "Not enough money"
		end
		m.Value -= conf.Price
	end
	
	table.insert(owned, upgradeName)
	PlayerUpgrades[player.UserId] = normalizeUpgradeList(owned)
	persistPlayerUpgrades(player)
	
	applyCharacterEffects(player)
	updateCollectorBots(player)
	ConvenienceUpgradesManager.ApplyBrainrotUpgrades(player)
	
	-- Refresh all global bonuses
	local BonusManager = rawget(Services, "BonusManager")
	if BonusManager and BonusManager.RefreshAll then
		BonusManager.RefreshAll(player)
	end

	PurchaseLocks[player.UserId] = nil
	return true, "Purchased!"
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function ConvenienceUpgradesManager.Init(services)
	print("   ConvenienceUpgradesManager (Module) - Initializing")
	Services = services or {}
	
	Players.PlayerAdded:Connect(function(player)
		if not PlayerUpgrades[player.UserId] then
			loadPlayerUpgrades(player)
		end
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			applyCharacterEffects(player)
		end)
		if player.Character then
			applyCharacterEffects(player)
		end
		updateCollectorBots(player)
		ConvenienceUpgradesManager.ApplyBrainrotUpgrades(player)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		local bots = PlayerCollectorBots[player.UserId]
		if bots then
			for _, b in bots do
				b:Destroy()
			end
		end
		PlayerCollectorBots[player.UserId] = nil
		PlayerUpgrades[player.UserId] = nil
		PurchaseLocks[player.UserId] = nil
	end)
	
	for _, p in Players:GetPlayers() do
		if not PlayerUpgrades[p.UserId] then
			loadPlayerUpgrades(p)
		end
		if p.Character then
			applyCharacterEffects(p)
		end
		updateCollectorBots(p)
		ConvenienceUpgradesManager.ApplyBrainrotUpgrades(p)
	end
	
	task.spawn(setupConvenienceShopVendor)
	
	PurchaseUpgradeEvent.OnServerEvent:Connect(function(player, name)
		local s, m = ConvenienceUpgradesManager.HandleUpgradePurchase(player, name)
		PurchaseUpgradeEvent:FireClient(player, s, m)
	end)
	
	GetUpgradesInfoEvent.OnServerInvoke = function(player)
		local ds = getDataService()
		local currentMoney = 0
		if ds and ds.GetMoney then
			currentMoney = ds.GetMoney(player)
		else
			local ls = player:FindFirstChild("leaderstats")
			local moneyValue = ls and ls:FindFirstChild("Money")
			currentMoney = moneyValue and moneyValue.Value or 0
		end

		return {
			OwnedUpgrades = PlayerUpgrades[player.UserId] or {},
			AllUpgrades = ConvenienceUpgradesConfig.GetAllUpgradesSorted(),
			Categories = ConvenienceUpgradesConfig.GetCategories(),
			CurrentMoney = currentMoney,
		}
	end
	
	print("✓ ConvenienceUpgradesManager Initialized")
end

-- Export API
ConvenienceUpgradesManager.GetPlayerUpgrades = function(player)
	return PlayerUpgrades[player.UserId] or {}
end
ConvenienceUpgradesManager.SetPlayerUpgrades = function(player, upgs)
	PlayerUpgrades[player.UserId] = normalizeUpgradeList(upgs)
	persistPlayerUpgrades(player)
	applyCharacterEffects(player)
	updateCollectorBots(player)
	ConvenienceUpgradesManager.ApplyBrainrotUpgrades(player)
end

ConvenienceUpgradesManager.CalculateIncomeMultiplier = calculateIncomeMultiplier
ConvenienceUpgradesManager.CalculateCycleReduction = calculateCycleReduction
ConvenienceUpgradesManager.CalculateLuckyChance = getLuckyChance
ConvenienceUpgradesManager.CalculateCriticalChance = getCriticalChance
ConvenienceUpgradesManager.GetBridgeSpeedMultiplier = getBridgeSpeedMultiplier
ConvenienceUpgradesManager.HasTeleportHome = function(player)
	return hasEffect(PlayerUpgrades[player.UserId] or {}, "TeleportHome")
end

ConvenienceUpgradesManager.ResetPlayerUpgrades = function(player)
	PlayerUpgrades[player.UserId] = {}
	persistPlayerUpgrades(player)
	local bots = PlayerCollectorBots[player.UserId]
	if bots then
		for _, b in bots do
			b:Destroy()
		end
	end
	PlayerCollectorBots[player.UserId] = nil
	applyCharacterEffects(player)
	player:SetAttribute("IncomeMultiplier", 1)
	player:SetAttribute("CycleReduction", 0)
	player:SetAttribute("LuckyChance", 0)
	player:SetAttribute("CriticalChance", 0)
end

return ConvenienceUpgradesManager
