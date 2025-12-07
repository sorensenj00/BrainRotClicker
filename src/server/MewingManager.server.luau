--[[
	MewingManager Server Script
	
	Tracks and rewards players for "Mewing" (staying AFK/silent).
	
	Mechanics:
	- Tracks last activity time (chat, movement)
	- Awards streak tiers with increasing income bonuses
	- Applies GigaChad jawline cosmetic at max tier
	
	Tiers:
	- 0-60s: Nothing
	- 60s+: Streak Started (+5%)
	- 300s+: Locked In (+10%)
	- 600s+: GigaChad (+20% + Cosmetic)
]]

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

-- Configuration
local CONFIG = {
	CHECK_INTERVAL = 1, -- Check every second
	MOVEMENT_THRESHOLD = 0.1, -- Velocity threshold for "moving"
	
	TIERS = {
		{ time = 60, name = "Streak Started", multiplier = 1.05, emoji = "🤫" },
		{ time = 300, name = "Locked In", multiplier = 1.10, emoji = "🔒" },
		{ time = 600, name = "GigaChad", multiplier = 1.20, emoji = "🗿", cosmetic = true },
	},
	
	SOUNDS = {
		STREAK_START = "rbxassetid://6895079853",
		STREAK_BREAK = "rbxassetid://5702385985", -- Bye bye sound
	},
}

-- State tracking per player
local PlayerMewingState: {[Player]: {
	LastActivityTime: number,
	CurrentTier: number,
	HasCosmetic: boolean,
	LastPosition: Vector3?,
}} = {}

-- Remote Events for client notification
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not RemoteEvents then
	RemoteEvents = Instance.new("Folder")
	RemoteEvents.Name = "RemoteEvents"
	RemoteEvents.Parent = ReplicatedStorage
end

local MewingUpdateEvent = RemoteEvents:FindFirstChild("MewingUpdate") or Instance.new("RemoteEvent")
MewingUpdateEvent.Name = "MewingUpdate"
MewingUpdateEvent.Parent = RemoteEvents

--------------------------------------------------------------------------------
-- ACTIVITY DETECTION
--------------------------------------------------------------------------------

--[[
	Resets a player's mewing streak due to activity.
]]
local function breakStreak(player: Player, reason: string)
	local state = PlayerMewingState[player]
	if not state then return end
	
	local hadStreak = state.CurrentTier > 0
	
	-- Reset state
	state.LastActivityTime = os.time()
	state.CurrentTier = 0
	
	-- Remove cosmetic if present
	if state.HasCosmetic then
		local character = player.Character
		if character then
			local jawline = character:FindFirstChild("GigaChadJawline")
			if jawline then
				jawline:Destroy()
			end
		end
		state.HasCosmetic = false
	end
	
	-- Reset player attribute
	player:SetAttribute("MewingMultiplier", 1.0)
	player:SetAttribute("MewingTier", 0)
	
	if hadStreak then
		-- Notify client
		MewingUpdateEvent:FireClient(player, {
			type = "break",
			reason = reason,
		})
		print(string.format("🤫 %s broke their Mewing streak: %s", player.Name, reason))
	end
end

--[[
	Checks if player has moved significantly.
]]
local function checkMovement(player: Player): boolean
	local state = PlayerMewingState[player]
	if not state then return false end
	
	local character = player.Character
	if not character then return false end
	
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	
	local currentPos = hrp.Position
	
	-- Check velocity
	if hrp.AssemblyLinearVelocity.Magnitude > CONFIG.MOVEMENT_THRESHOLD then
		return true
	end
	
	-- Check position change
	if state.LastPosition then
		local delta = (currentPos - state.LastPosition).Magnitude
		if delta > 1 then -- Moved more than 1 stud
			return true
		end
	end
	
	state.LastPosition = currentPos
	return false
end

--------------------------------------------------------------------------------
-- COSMETIC SYSTEM
--------------------------------------------------------------------------------

--[[
	Applies the GigaChad jawline cosmetic to a player.
]]
local function applyGigaChadCosmetic(player: Player)
	local state = PlayerMewingState[player]
	if not state or state.HasCosmetic then return end
	
	local character = player.Character
	if not character then return end
	
	local head = character:FindFirstChild("Head")
	if not head then return end
	
	-- Create a simple jawline part (placeholder - would be a proper mesh in production)
	local jawline = Instance.new("Part")
	jawline.Name = "GigaChadJawline"
	jawline.Size = Vector3.new(1.5, 0.5, 1.2)
	jawline.BrickColor = BrickColor.new("Light orange")
	jawline.Material = Enum.Material.SmoothPlastic
	jawline.CanCollide = false
	jawline.Massless = true
	
	-- Weld to head
	local weld = Instance.new("Weld")
	weld.Part0 = head
	weld.Part1 = jawline
	weld.C0 = CFrame.new(0, -0.6, 0.1) -- Position below head
	weld.Parent = jawline
	
	jawline.Parent = character
	state.HasCosmetic = true
	
	print(string.format("🗿 %s achieved GigaChad status!", player.Name))
end

--------------------------------------------------------------------------------
-- STREAK UPDATE LOGIC
--------------------------------------------------------------------------------

local lastCheck = 0

local function updateMewingStreaks()
	local now = os.time()
	
	-- Only check every CONFIG.CHECK_INTERVAL seconds
	if now - lastCheck < CONFIG.CHECK_INTERVAL then
		return
	end
	lastCheck = now
	
	for player, state in pairs(PlayerMewingState) do
		if not player.Parent then continue end -- Player left
		
		-- Check for movement
		if checkMovement(player) then
			breakStreak(player, "Movement detected")
			continue
		end
		
		-- Calculate streak time
		local streakTime = now - state.LastActivityTime
		
		-- Determine tier
		local newTier = 0
		local tierData = nil
		
		for i, tier in ipairs(CONFIG.TIERS) do
			if streakTime >= tier.time then
				newTier = i
				tierData = tier
			end
		end
		
		-- Tier changed
		if newTier ~= state.CurrentTier then
			state.CurrentTier = newTier
			
			if newTier > 0 and tierData then
				-- Update multiplier
				player:SetAttribute("MewingMultiplier", tierData.multiplier)
				player:SetAttribute("MewingTier", newTier)
				
				-- Apply cosmetic if GigaChad tier
				if tierData.cosmetic then
					applyGigaChadCosmetic(player)
				end
				
				-- Notify client
				MewingUpdateEvent:FireClient(player, {
					type = "tier_up",
					tier = newTier,
					name = tierData.name,
					emoji = tierData.emoji,
					multiplier = tierData.multiplier,
				})
				
				print(string.format("🤫 %s reached Mewing tier %d: %s (%.0f%%)", 
					player.Name, newTier, tierData.name, (tierData.multiplier - 1) * 100))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- EVENT HANDLERS
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	-- Initialize state
	PlayerMewingState[player] = {
		LastActivityTime = os.time(),
		CurrentTier = 0,
		HasCosmetic = false,
		LastPosition = nil,
	}
	
	-- Set initial attributes
	player:SetAttribute("MewingMultiplier", 1.0)
	player:SetAttribute("MewingTier", 0)
	
	print(string.format("🤫 Mewing tracking started for %s", player.Name))
end

local function onPlayerRemoving(player: Player)
	PlayerMewingState[player] = nil
end

--------------------------------------------------------------------------------
-- CHAT DETECTION
--------------------------------------------------------------------------------

-- Modern TextChatService approach
local function setupChatDetection()
	-- Try to get TextChannel for general chat
	local textChannels = TextChatService:WaitForChild("TextChannels", 5)
	if textChannels then
		local generalChannel = textChannels:FindFirstChild("RBXGeneral")
		if generalChannel then
			generalChannel.MessageReceived:Connect(function(message)
				local player = Players:GetPlayerByUserId(message.TextSource.UserId)
				if player then
					breakStreak(player, "Chatted")
				end
			end)
			print("✓ Chat detection via TextChatService")
			return
		end
	end
	
	-- Fallback: Legacy chat detection
	local legacyChatEvent = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
	if legacyChatEvent then
		local onMessageDone = legacyChatEvent:FindFirstChild("OnMessageDoneFiltering")
		if onMessageDone and onMessageDone:IsA("RemoteEvent") then
			onMessageDone.OnServerEvent:Connect(function(player)
				breakStreak(player, "Chatted")
			end)
			print("✓ Chat detection via Legacy Chat")
			return
		end
	end
	
	warn("MewingManager: Could not set up chat detection")
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local function initialize()
	print("═══════════════════════════════════════════")
	print("   MewingManager - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Connect player events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	-- Handle existing players
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	
	-- Setup chat detection
	task.spawn(setupChatDetection)
	
	-- Start update loop
	RunService.Heartbeat:Connect(updateMewingStreaks)
	
	print("✓ MewingManager initialized")
	print("═══════════════════════════════════════════")
end

initialize()

-- Export for other scripts
_G.MewingManager = {
	BreakStreak = breakStreak,
	GetPlayerState = function(player)
		return PlayerMewingState[player]
	end,
}
