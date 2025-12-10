--[[
	ConvenienceUpgradesManager Server Script
	
	Handles:
	1. Purchase of convenience upgrades
	2. Applying upgrade effects (walkspeed, income multipliers, etc.)
	3. Creating the Convenience Shop vendor on main island
	4. Spawning Auto-Collector bots
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ConvenienceUpgradesConfig = require(Shared:WaitForChild("ConvenienceUpgradesConfig"))

-- Config
local SHOP_CONFIG = {
	VENDOR_SIZE = Vector3.new(6, 8, 6),
	VENDOR_POSITION_OFFSET = Vector3.new(30, 10, -30),
}

-- Remotes
local function getRemote(name, class, parent)
	local r = parent:FindFirstChild(name) or Instance.new(class)
	r.Name = name
	r.Parent = parent
	return r
end

local RE = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder", ReplicatedStorage)
RE.Name = "RemoteEvents"
local PurchaseUpgradeEvent = getRemote("PurchaseConvenienceUpgrade", "RemoteEvent", RE)
local GetUpgradesInfoEvent = getRemote("GetConvenienceUpgradesInfo", "RemoteFunction", RE)

-- State
local PlayerUpgrades = {} -- UserId -> list of owned upgrade names
local PlayerCollectorBots = {} -- UserId -> list of bots

-- Helper: Effect Calculations
local function getEffects(upgrades)
	local effects = { Income = 1.0, Cycle = 0.0, Walk = 1.0, Jump = 1.0, Bridge = 1.0, Lucky = 0.0, Critical = 0.0, Bots = 0, Home = false }
	
	for _, name in upgrades do
		local cfg = ConvenienceUpgradesConfig.GetConfig(name)
		if cfg then
			if cfg.EffectType == "IncomeMultiplier" then effects.Income += cfg.EffectValue
			elseif cfg.EffectType == "CycleReduction" then effects.Cycle += cfg.EffectValue
			elseif cfg.EffectType == "Walkspeed" then effects.Walk += cfg.EffectValue
			elseif cfg.EffectType == "JumpPower" then effects.Jump += cfg.EffectValue
			elseif cfg.EffectType == "BridgeSpeed" then effects.Bridge = math.max(effects.Bridge, cfg.EffectValue)
			elseif cfg.EffectType == "LuckyChance" then effects.Lucky = cfg.EffectValue
			elseif cfg.EffectType == "CriticalChance" then effects.Critical = cfg.EffectValue
			elseif cfg.EffectType == "AutoCollector" then effects.Bots += cfg.EffectValue
			elseif cfg.EffectType == "TeleportHome" then effects.Home = true
			end
		end
	end
	effects.Cycle = math.min(effects.Cycle, 0.75)
	return effects
end

-- Apply Effects
local function applyEffects(player)
	local upgrades = PlayerUpgrades[player.UserId] or {}
	local eff = getEffects(upgrades)
	
	-- Character
	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = 16 * eff.Walk
			hum.JumpPower = 50 * eff.Jump
		end
	end
	
	-- Attributes (for BrainrotManager)
	player:SetAttribute("IncomeMultiplier", eff.Income)
	player:SetAttribute("CycleReduction", eff.Cycle)
	player:SetAttribute("LuckyChance", eff.Lucky)
	player:SetAttribute("CriticalChance", eff.Critical)
	
	-- Bots
	local currentBots = PlayerCollectorBots[player.UserId] or {}
	local plot = _G.BrainrotManager and _G.BrainrotManager.GetPlayerPlot(player)
	
	if plot then
		while #currentBots < eff.Bots do
			local idx = #currentBots + 1
			local bot = Instance.new("Model")
			bot.Name = "Bot_"..idx
			local p = Instance.new("Part", bot)
			p.Size = Vector3.new(3,3,3)
			p.BrickColor = idx == 1 and BrickColor.Blue() or BrickColor.Green()
			p.Shape = Enum.PartType.Ball
			p.Anchored = false
			p.CanCollide = false

			-- Simple visual (Eyes)
			local e1 = Instance.new("Part", bot) e1.Size = Vector3.new(0.5,0.5,0.5) e1.Color = Color3.new(1,1,1) e1.Shape = Enum.PartType.Ball
			local e2 = e1:Clone() e2.Parent = bot
			p.CFrame = plot:GetPivot() * CFrame.new(0,10,0)

			local wc = Instance.new("WeldConstraint", p) wc.Part0 = p wc.Part1 = e1
			local wc2 = Instance.new("WeldConstraint", p) wc2.Part0 = p wc2.Part1 = e2
			e1.CFrame = p.CFrame * CFrame.new(0.6,0.5,-1.2)
			e2.CFrame = p.CFrame * CFrame.new(-0.6,0.5,-1.2)

			bot.PrimaryPart = p
			bot.Parent = plot
			table.insert(currentBots, bot)
		end
		-- Remove excess
		while #currentBots > eff.Bots do
			local b = table.remove(currentBots)
			if b then b:Destroy() end
		end
	end
	PlayerCollectorBots[player.UserId] = currentBots
end

-- Vendor
local function createVendor()
	local main = workspace:WaitForChild("MainIsland", 10)
	if not main or main:FindFirstChild("ConvenienceShopVendor") then return end
	
	local p = Instance.new("Part", main)
	p.Name = "ConvenienceShopVendor"
	p.Size = SHOP_CONFIG.VENDOR_SIZE
	p.BrickColor = BrickColor.new("Bright orange")
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.Position = main:GetPivot().Position + SHOP_CONFIG.VENDOR_POSITION_OFFSET
	
	local bb = Instance.new("BillboardGui", p)
	bb.Size = UDim2.new(6,0,3,0)
	bb.StudsOffset = Vector3.new(0,6,0)
	local bg = Instance.new("Frame", bb)
	bg.Size = UDim2.fromScale(1,1)
	bg.BackgroundColor3 = Color3.fromRGB(60,40,20)
	bg.BackgroundTransparency = 0.2
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0.1,0)
	
	local txt = Instance.new("TextLabel", bg)
	txt.Text = "⚡ UPGRADES"
	txt.Size = UDim2.fromScale(1,0.4)
	txt.TextColor3 = Color3.fromRGB(255,200,100)
	txt.BackgroundTransparency = 1
	txt.TextScaled = true
	txt.Font = Enum.Font.GothamBold
	
	local prox = Instance.new("ProximityPrompt", p)
	prox.ActionText = "Open Upgrades"
	prox.KeyboardKeyCode = Enum.KeyCode.E
	
	CollectionService:AddTag(p, "ConvenienceShopVendor")
end

-- Handlers
local function handlePurchase(player, name)
	local owned = PlayerUpgrades[player.UserId] or {}
	local can, reason = ConvenienceUpgradesConfig.CanPurchase(name, owned)
	if not can then return false, reason end
	
	local cfg = ConvenienceUpgradesConfig.GetConfig(name)
	local ls = player:FindFirstChild("leaderstats")
	local money = ls and ls:FindFirstChild("Money")
	
	if not money or money.Value < cfg.Price then return false, "Not enough money" end
	
	money.Value -= cfg.Price
	table.insert(owned, name)
	PlayerUpgrades[player.UserId] = owned
	
	applyEffects(player)
	return true, "Purchased " .. name
end

PurchaseUpgradeEvent.OnServerEvent:Connect(function(plr, name)
	local s, m = handlePurchase(plr, name)
	PurchaseUpgradeEvent:FireClient(plr, s, m)
end)

GetUpgradesInfoEvent.OnServerInvoke = function(plr)
	return {
		OwnedUpgrades = PlayerUpgrades[plr.UserId] or {},
		AllUpgrades = ConvenienceUpgradesConfig.GetAllUpgradesSorted(),
		Categories = ConvenienceUpgradesConfig.GetCategories()
	}
end

-- Lifecycle
local function onPlayerAdded(plr)
	if not PlayerUpgrades[plr.UserId] then PlayerUpgrades[plr.UserId] = {} end
	plr.CharacterAdded:Connect(function() task.wait(0.5) applyEffects(plr) end)
	if plr.Character then applyEffects(plr) end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(plr)
	if PlayerCollectorBots[plr.UserId] then
		for _, b in PlayerCollectorBots[plr.UserId] do b:Destroy() end
	end
	PlayerCollectorBots[plr.UserId] = nil
	PlayerUpgrades[plr.UserId] = nil
end)

for _, p in Players:GetPlayers() do task.spawn(onPlayerAdded, p) end
task.spawn(function() task.wait(2) createVendor() end)

-- API
_G.ConvenienceUpgrades = {
	GetPlayerUpgrades = function(p) return PlayerUpgrades[p.UserId] or {} end,
	SetPlayerUpgrades = function(p, u) PlayerUpgrades[p.UserId] = u; applyEffects(p) end,
	HasTeleportHome = function(p) return getEffects(PlayerUpgrades[p.UserId] or {}).Home end,
	ResetPlayerUpgrades = function(p)
		PlayerUpgrades[p.UserId] = {}
		if PlayerCollectorBots[p.UserId] then for _, b in PlayerCollectorBots[p.UserId] do b:Destroy() end end
		PlayerCollectorBots[p.UserId] = nil
		applyEffects(p)
	end
}

print("✓ ConvenienceUpgradesManager Initialized")
