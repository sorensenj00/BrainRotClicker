--[[
	MapManager Server Script

	Handles:
	1. Spawning the central MainIsland hub
	2. Generating 8 player plots in a circular formation
	3. Plot assignment and lifecycle management
	4. Tier system expansion logic
]]

-- Services
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Config
local CONFIG = {
	MAX_PLAYERS = 8,
	PLOT_RADIUS = 400,
	MAIN_ISLAND_HEIGHT = 30,
	PLOT_MIN_HEIGHT = 50,
	PLOT_MAX_HEIGHT = 120,
}

local TIER_CONFIG = {
	MODELS_PER_TIER = 12,
	MAX_TIERS = 6,
	TIER_HEIGHT_MIN = 20,
	TIER_HEIGHT_MAX = 60,
	TIER_DISTANCE_MIN = 80,
	TIER_DISTANCE_MAX = 140,
	SIDE_OFFSETS = {
		[0] = Vector3.new(0, 0, 1),
		[1] = Vector3.new(1, 0, 0),
		[2] = Vector3.new(0, 0, -1),
		[3] = Vector3.new(-1, 0, 0),
	},
}

-- State
local Plots = {} -- {Index, Model, Bridge, Position, Owner, ClaimPart}
local PlayerToPlot = {}
local PlayerTierSystems = {}
local PlotsFolder

-- Templates
local Templates = {}

local function initTemplates()
	local function get(name)
		return ServerStorage:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name)
	end
	Templates.MainIsland = get("MainIsland")
	Templates.PlayerPlot = get("PlayerPlot")
	Templates.Bridge = get("Bridge")
end

-- Math Helpers
local function calculatePlotCFrame(index)
	local angle = (index - 1) * ((2 * math.pi) / CONFIG.MAX_PLAYERS)
	local x = CONFIG.PLOT_RADIUS * math.cos(angle)
	local z = CONFIG.PLOT_RADIUS * math.sin(angle)
	local y = math.random(CONFIG.PLOT_MIN_HEIGHT, CONFIG.PLOT_MAX_HEIGHT)
	return CFrame.new(x, y, z) * CFrame.Angles(0, -(angle + math.pi), 0)
end

local function calculateIncomingSide(parentPos, childPos)
	local dir = parentPos - childPos
	if math.abs(dir.Z) > math.abs(dir.X) then
		return dir.Z > 0 and 0 or 2
	else
		return dir.X > 0 and 1 or 3
	end
end

-- Map Generation
local function generateMap()
	-- Main Island
	local hub = Templates.MainIsland:Clone()
	hub.Name = "MainIsland"
	hub:PivotTo(CFrame.new(0, CONFIG.MAIN_ISLAND_HEIGHT, 0))
	hub.Parent = workspace

	-- Plots
	PlotsFolder = Instance.new("Folder", workspace)
	PlotsFolder.Name = "Plots"

	for i = 1, CONFIG.MAX_PLAYERS do
		local cf = calculatePlotCFrame(i)
		local plot = Templates.PlayerPlot:Clone()
		plot.Name = "Plot_"..i
		plot:PivotTo(cf)
		plot.Parent = PlotsFolder

		-- Bridge
		local dir = (cf.Position * Vector3.new(1,0,1)).Unit
		local hubEdge = Vector3.new(dir.X*50, CONFIG.MAIN_ISLAND_HEIGHT+10, dir.Z*50)
		local plotEdge = cf.Position - (dir * 40) + Vector3.new(0,10,0)

		local bridge = Templates.Bridge:Clone()
		bridge.Name = "Bridge_"..i
		local dist = (plotEdge - hubEdge).Magnitude
		for _, p in bridge:GetDescendants() do
			if p:IsA("BasePart") then p.Size = Vector3.new(p.Size.X, p.Size.Y, dist) end
		end
		bridge:PivotTo(CFrame.lookAt((hubEdge+plotEdge)/2, plotEdge))
		bridge.Parent = workspace

		Plots[i] = { Index = i, Model = plot, Bridge = bridge, Position = cf, Owner = nil }
	end
end

-- Tier System
local function spawnTierPlot(player, parentTier)
	local ts = PlayerTierSystems[player]
	if not ts or #ts.Tiers >= TIER_CONFIG.MAX_TIERS then return nil end

	-- Pick side
	local side
	local attempts = {0,1,2,3}
	for i=#attempts, 2, -1 do local j=math.random(i); attempts[i], attempts[j] = attempts[j], attempts[i] end

	for _, s in attempts do
		if s ~= parentTier.BlockedSide then
			local used = false
			for _, u in parentTier.UsedSides do if u == s then used = true break end end
			if not used then side = s break end
		end
	end
	if not side then return nil end

	-- Spawn
	local pCF = parentTier.Model:GetPivot()
	local offset = TIER_CONFIG.SIDE_OFFSETS[side]
	local newPos = pCF.Position + (offset * math.random(TIER_CONFIG.TIER_DISTANCE_MIN, TIER_CONFIG.TIER_DISTANCE_MAX))
	newPos = Vector3.new(newPos.X, pCF.Y + math.random(TIER_CONFIG.TIER_HEIGHT_MIN, TIER_CONFIG.TIER_HEIGHT_MAX), newPos.Z)

	local newPlot = Templates.PlayerPlot:Clone()
	newPlot.Name = "Plot_"..ts.BasePlotIndex.."_Tier_"..(#ts.Tiers+1)
	newPlot:PivotTo(CFrame.new(newPos, pCF.Position))
	newPlot:SetAttribute("OwnerId", player.UserId)
	newPlot:SetAttribute("TierIndex", #ts.Tiers+1)
	newPlot.Parent = PlotsFolder

	table.insert(parentTier.UsedSides, side)

	-- Create Bridge/Stairs
	-- Note: The logic for stairs vs flat bridge is simplified here.
	-- Since new tiers are always higher, we should ideally use stairs or an angled bridge.
	-- For this refactor, we'll use a simple angled bridge to ensure connectivity.
	local bridge = Templates.Bridge:Clone()
	bridge.Name = "Bridge_Tier_"..(#ts.Tiers+1)

	local plotRadius = 40
	local pEdge = pCF.Position + offset * plotRadius
	local cEdge = newPos - offset * plotRadius
	local dist = (cEdge - pEdge).Magnitude

	for _, p in bridge:GetDescendants() do
		if p:IsA("BasePart") then p.Size = Vector3.new(p.Size.X, p.Size.Y, dist) end
	end
	bridge:PivotTo(CFrame.lookAt((pEdge+cEdge)/2, cEdge))
	bridge.Parent = workspace

	local newTier = {
		TierIndex = #ts.Tiers+1,
		Model = newPlot,
		Bridge = bridge,
		ParentTier = parentTier,
		BlockedSide = calculateIncomingSide(pCF.Position, newPos),
		UsedSides = {},
		GridIndex = 0
	}
	table.insert(ts.Tiers, newTier)
	ts.CurrentTier = newTier.TierIndex -- Update current tier pointer

	return newTier
end

-- Player Management
local function assignPlot(player)
	for i, data in Plots do
		if not data.Owner then
			data.Owner = player
			PlayerToPlot[player] = i
			data.Model:SetAttribute("OwnerId", player.UserId)
			data.Model:SetAttribute("TierIndex", 1)

			-- Init Tier System
			local blocked = calculateIncomingSide(Vector3.zero, data.Position.Position)
			PlayerTierSystems[player] = {
				BasePlotIndex = i,
				Tiers = {{ TierIndex = 1, Model = data.Model, BlockedSide = blocked, UsedSides = {}, GridIndex = 0 }},
				CurrentTier = 1,
				TotalModels = 0
			}
			return
		end
	end
end

local function teleportPlayer(player)
	local i = PlayerToPlot[player]
	if i and Plots[i] then
		local char = player.Character or player.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if hrp then hrp.CFrame = Plots[i].Model:GetPivot() + Vector3.new(0,10,0) end
	end
end

local function clearPlot(player)
	local i = PlayerToPlot[player]
	if not i then return end

	-- Clear tiers
	local ts = PlayerTierSystems[player]
	if ts then
		for j=#ts.Tiers, 2, -1 do
			if ts.Tiers[j].Model then ts.Tiers[j].Model:Destroy() end
			if ts.Tiers[j].Bridge then ts.Tiers[j].Bridge:Destroy() end
		end
		PlayerTierSystems[player] = nil
	end

	-- Clear buildings on main plot
	if Plots[i].Model:FindFirstChild("Brainrots") then Plots[i].Model.Brainrots:Destroy() end

	Plots[i].Owner = nil
	Plots[i].Model:SetAttribute("OwnerId", nil)
	PlayerToPlot[player] = nil
end

-- Init
initTemplates()
generateMap()

Players.PlayerAdded:Connect(function(plr)
	assignPlot(plr)
	plr.CharacterAdded:Connect(function() task.wait(0.5) teleportPlayer(plr) end)
	if plr.Character then teleportPlayer(plr) end
end)

Players.PlayerRemoving:Connect(clearPlot)

-- Export
_G.MapSystem = {
	GetPlayerPlot = function(p) return Plots[PlayerToPlot[p]] end,
	GetAllPlots = function() return Plots end,
	GetPlayerTierSystem = function(p) return PlayerTierSystems[p] end,
	GetCurrentTier = function(p)
		local ts = PlayerTierSystems[p]
		return ts and ts.Tiers[ts.CurrentTier]
	end,
	SpawnTierPlot = spawnTierPlot,
	TIER_CONFIG = TIER_CONFIG,
	RestoreTiers = function(player, count)
		local ts = PlayerTierSystems[player]
		if not ts then return end
		-- Only spawn if needed
		for i=#ts.Tiers+1, count do
			local parent = ts.Tiers[#ts.Tiers]
			if parent then spawnTierPlot(player, parent) end
		end
	end
}

print("✓ MapManager Initialized")
