--[[
	MewingManager Server Module
	
	Tracks and rewards players for "Mewing" (staying AFK/silent).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local MewingUpdateEvent = RemoteEvents:FindFirstChild("MewingUpdate") or Instance.new("RemoteEvent")
MewingUpdateEvent.Name = "MewingUpdate"
MewingUpdateEvent.Parent = RemoteEvents

local CONFIG = {
	CHECK_INTERVAL = 1,
	MOVEMENT_THRESHOLD = 0.1,
	TIERS = {
		{ time = 60, name = "Streak Started", multiplier = 1.05, emoji = "🤫" },
		{ time = 300, name = "Locked In", multiplier = 1.10, emoji = "🔒" },
		{ time = 600, name = "GigaChad", multiplier = 1.20, emoji = "🗿", cosmetic = true },
	},
}

local MewingManager = {}
local Services = {}
local PlayerMewingState = {}
local lastCheck = 0

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local function applyGigaChadCosmetic(player)
	local state = PlayerMewingState[player]
	if not state or state.HasCosmetic then return end
	local char = player.Character
	if not char then return end
	local head = char:FindFirstChild("Head")
	if not head then return end
	
	local jaw = Instance.new("Part")
	jaw.Name = "GigaChadJawline"
	jaw.Size = Vector3.new(1.5, 0.5, 1.2)
	jaw.BrickColor = BrickColor.new("Light orange")
	jaw.Material = Enum.Material.SmoothPlastic
	jaw.CanCollide = false
	jaw.Massless = true
	
	local w = Instance.new("Weld")
	w.Part0 = head; w.Part1 = jaw; w.C0 = CFrame.new(0, -0.6, 0.1); w.Parent = jaw
	
	jaw.Parent = char
	state.HasCosmetic = true
end

local function breakStreak(player, reason)
	local state = PlayerMewingState[player]
	if not state then return end
	local had = state.CurrentTier > 0
	
	state.LastActivityTime = os.time()
	state.CurrentTier = 0
	
	if state.HasCosmetic then
		local char = player.Character
		if char then
			local jaw = char:FindFirstChild("GigaChadJawline")
			if jaw then jaw:Destroy() end
		end
		state.HasCosmetic = false
	end
	
	player:SetAttribute("MewingMultiplier", 1.0)
	player:SetAttribute("MewingTier", 0)
	
	if had then
		MewingUpdateEvent:FireClient(player, { type = "break", reason = reason })
	end
end

local function checkMovement(player)
	local state = PlayerMewingState[player]
	if not state then return false end
	local char = player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	
	local pos = hrp.Position
	if hrp.AssemblyLinearVelocity.Magnitude > CONFIG.MOVEMENT_THRESHOLD then return true end
	if state.LastPosition and (pos - state.LastPosition).Magnitude > 1 then return true end
	
	state.LastPosition = pos
	return false
end

local function updateMewingStreaks()
	local now = os.time()
	if now - lastCheck < CONFIG.CHECK_INTERVAL then return end
	lastCheck = now
	
	for player, state in pairs(PlayerMewingState) do
		if not player.Parent then continue end
		
		if checkMovement(player) then
			breakStreak(player, "Movement detected")
			continue
		end
		
		local streak = now - state.LastActivityTime
		local newTier = 0
		local tData = nil
		
		for i, tier in ipairs(CONFIG.TIERS) do
			if streak >= tier.time then newTier = i; tData = tier end
		end
		
		if newTier ~= state.CurrentTier then
			state.CurrentTier = newTier
			if newTier > 0 and tData then
				player:SetAttribute("MewingMultiplier", tData.multiplier)
				player:SetAttribute("MewingTier", newTier)
				if tData.cosmetic then applyGigaChadCosmetic(player) end
				
				MewingUpdateEvent:FireClient(player, {
					type = "tier_up", tier = newTier, name = tData.name, emoji = tData.emoji, multiplier = tData.multiplier
				})
			end
		end
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function MewingManager.Init(services)
	print("   MewingManager (Module) - Initializing")
	Services = services or {}
	
	Players.PlayerAdded:Connect(function(player)
		PlayerMewingState[player] = { LastActivityTime = os.time(), CurrentTier = 0, HasCosmetic = false }
		player:SetAttribute("MewingMultiplier", 1.0)
		player:SetAttribute("MewingTier", 0)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		PlayerMewingState[player] = nil
	end)
	
	for _, p in Players:GetPlayers() do
		PlayerMewingState[p] = { LastActivityTime = os.time(), CurrentTier = 0, HasCosmetic = false }
	end
	
	-- Chat Detection
	task.spawn(function()
		local tc = TextChatService:WaitForChild("TextChannels", 5)
		if tc then
			local gc = tc:FindFirstChild("RBXGeneral")
			if gc then
				gc.MessageReceived:Connect(function(msg)
					local p = Players:GetPlayerByUserId(msg.TextSource.UserId)
					if p then breakStreak(p, "Chatted") end
				end)
			end
		else
			-- Legacy
			local lce = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
			if lce then
				local omd = lce:FindFirstChild("OnMessageDoneFiltering")
				if omd then
					omd.OnServerEvent:Connect(function(p) breakStreak(p, "Chatted") end)
				end
			end
		end
	end)
	
	RunService.Heartbeat:Connect(updateMewingStreaks)
	print("✓ MewingManager Initialized")
end

MewingManager.BreakStreak = breakStreak
MewingManager.GetPlayerState = function(player) return PlayerMewingState[player] end

return MewingManager
