--[[
	MewingManager Server Module
	
	Tracks and rewards players for "Mewing" (staying AFK/silent).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

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
local COMPONENT_KEY = "Mewing"

local function getDataService()
	return rawget(Services, "DataService")
end

local function getAchievementManager()
	return rawget(Services, "AchievementsManager")
end

local function getDefaultState()
	return {
		LastActivityTime = os.time(),
		CurrentTier = 0,
		HasCosmetic = false,
		HasReachedLockedIn = false,
		HasReachedGigaChad = false,
	}
end

local function getOrInitState(player)
	local state = PlayerMewingState[player]
	if state then
		return state
	end
	state = getDefaultState()
	PlayerMewingState[player] = state
	return state
end

local function persistState(player)
	local state = PlayerMewingState[player]
	local ds = getDataService()
	if not state or not ds then
		return
	end
	ds.SetComponentData(player, COMPONENT_KEY, {
		LastActivityTime = state.LastActivityTime,
		CurrentTier = state.CurrentTier,
		HasReachedLockedIn = state.HasReachedLockedIn == true,
		HasReachedGigaChad = state.HasReachedGigaChad == true,
	})
end

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local function applyGigaChadCosmetic(player)
	local state = getOrInitState(player)
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
	local state = getOrInitState(player)
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
	persistState(player)
	
	if had then
		MewingUpdateEvent:FireClient(player, { type = "break", reason = reason })
		
		-- Refresh all global bonuses when streak breaks
		local BonusManager = rawget(Services, "BonusManager")
		if BonusManager and BonusManager.RefreshAll then
			BonusManager.RefreshAll(player)
		end
	end
end

local function hasValidCharacter(player)
	local char = player.Character
	if not char then
		return false
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	return hrp ~= nil
end

local function checkMovement(player)
	local state = getOrInitState(player)
	if not state then return false end
	local char = player.Character
	if not char then return true end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return true end
	
	local pos = hrp.Position
	if hrp.AssemblyLinearVelocity.Magnitude > CONFIG.MOVEMENT_THRESHOLD then return true end
	if state.LastPosition and (pos - state.LastPosition).Magnitude > 1 then return true end
	
	state.LastPosition = pos
	return false
end

local function updateMewingStreaks()
	local now = os.time()
	
	for player, state in pairs(PlayerMewingState) do
		if not player.Parent then continue end

		if not hasValidCharacter(player) then
			if state.CurrentTier > 0 then
				breakStreak(player, "Character invalid")
			else
				state.LastActivityTime = now
				persistState(player)
			end
			continue
		end
		
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
				if tData.time >= 300 then
					state.HasReachedLockedIn = true
					local achievementManager = getAchievementManager()
					if achievementManager and achievementManager.RecordProgress then
						achievementManager.RecordProgress(player, "mewing_locked_in", 1)
					end
				end
				if tData.time >= 600 then
					state.HasReachedGigaChad = true
					local achievementManager = getAchievementManager()
					if achievementManager and achievementManager.RecordProgress then
						achievementManager.RecordProgress(player, "mewing_gigachad", 1)
					end
				end
				
				MewingUpdateEvent:FireClient(player, {
					type = "tier_up", tier = newTier, name = tData.name, emoji = tData.emoji, multiplier = tData.multiplier
				})
				
				-- Refresh all global bonuses when tier increases
				local BonusManager = rawget(Services, "BonusManager")
				if BonusManager and BonusManager.RefreshAll then
					BonusManager.RefreshAll(player)
				end
			end
			persistState(player)
		end
	end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function MewingManager.Init(services)
	print("   MewingManager (Module) - Initializing")
	Services = services or {}

	local ds = getDataService()
	if ds then
		ds.RegisterHandler(COMPONENT_KEY, {
			DefaultData = getDefaultState(),
			OnLoad = function(player, data)
				local state = getOrInitState(player)
				if type(data) == "table" then
					state.LastActivityTime = tonumber(data.LastActivityTime) or os.time()
					state.CurrentTier = tonumber(data.CurrentTier) or 0
					state.HasReachedLockedIn = data.HasReachedLockedIn == true
					state.HasReachedGigaChad = data.HasReachedGigaChad == true
				end
				player:SetAttribute("MewingTier", state.CurrentTier)
				local tierData = CONFIG.TIERS[state.CurrentTier]
				player:SetAttribute("MewingMultiplier", tierData and tierData.multiplier or 1.0)
			end,
			OnSave = function(player, _data)
				local state = PlayerMewingState[player]
				if not state then
					return getDefaultState()
				end
				return {
					LastActivityTime = state.LastActivityTime,
					CurrentTier = state.CurrentTier,
					HasReachedLockedIn = state.HasReachedLockedIn == true,
					HasReachedGigaChad = state.HasReachedGigaChad == true,
				}
			end,
			OnRelease = function(player)
				PlayerMewingState[player] = nil
			end,
		})
	end
	
	Players.PlayerAdded:Connect(function(player)
		PlayerMewingState[player] = getDefaultState()
		player:SetAttribute("MewingMultiplier", 1.0)
		player:SetAttribute("MewingTier", 0)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		PlayerMewingState[player] = nil
	end)
	
	for _, p in Players:GetPlayers() do
		local loadedData = ds and ds.GetComponentData and ds.GetComponentData(p, COMPONENT_KEY) or nil
		local state = getDefaultState()
		if type(loadedData) == "table" then
			state.LastActivityTime = tonumber(loadedData.LastActivityTime) or state.LastActivityTime
			state.CurrentTier = tonumber(loadedData.CurrentTier) or state.CurrentTier
			state.HasReachedLockedIn = loadedData.HasReachedLockedIn == true
			state.HasReachedGigaChad = loadedData.HasReachedGigaChad == true
		end
		PlayerMewingState[p] = state
		p:SetAttribute("MewingTier", state.CurrentTier)
		local tierData = CONFIG.TIERS[state.CurrentTier]
		p:SetAttribute("MewingMultiplier", tierData and tierData.multiplier or 1.0)
	end
	
	-- Chat Detection
	task.spawn(function()
		local tc = TextChatService:WaitForChild("TextChannels", 5)
		if tc then
			local gc = tc:FindFirstChild("RBXGeneral")
			if gc then
				gc.MessageReceived:Connect(function(msg)
					local source = msg.TextSource
					if not source then
						return
					end
					local p = Players:GetPlayerByUserId(source.UserId)
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
	
	task.spawn(function()
		while true do
			task.wait(CONFIG.CHECK_INTERVAL)
			updateMewingStreaks()
		end
	end)
	print("✓ MewingManager Initialized")
end

MewingManager.BreakStreak = breakStreak
MewingManager.GetPlayerState = function(player) return PlayerMewingState[player] end

return MewingManager
