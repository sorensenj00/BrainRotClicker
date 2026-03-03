--[[
	AchievementsManager

	Data-driven achievement progression with unlock + claim flow.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AchievementsConfig = require(Shared:WaitForChild("AchievementsConfig"))

local COMPONENT_KEY = "Achievements"

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local AchievementUpdatedEvent = RemoteEvents:FindFirstChild("AchievementUpdated") or Instance.new("RemoteEvent")
AchievementUpdatedEvent.Name = "AchievementUpdated"
AchievementUpdatedEvent.Parent = RemoteEvents

local AchievementNotifyEvent = RemoteEvents:FindFirstChild("AchievementNotify") or Instance.new("RemoteEvent")
AchievementNotifyEvent.Name = "AchievementNotify"
AchievementNotifyEvent.Parent = RemoteEvents

local GetAchievementsSnapshotFunction = RemoteFunctions:FindFirstChild("GetAchievementsSnapshot") or Instance.new("RemoteFunction")
GetAchievementsSnapshotFunction.Name = "GetAchievementsSnapshot"
GetAchievementsSnapshotFunction.Parent = RemoteFunctions

local ClaimAchievementRewardFunction = RemoteFunctions:FindFirstChild("ClaimAchievementReward") or Instance.new("RemoteFunction")
ClaimAchievementRewardFunction.Name = "ClaimAchievementReward"
ClaimAchievementRewardFunction.Parent = RemoteFunctions

local AchievementsManager = {}
local Services = {}
local DataService

local DefinitionsById = {}
local DefinitionsByGoal = {}

local function deepCopy(tbl)
	local copy = {}
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			copy[k] = deepCopy(v)
		else
			copy[k] = v
		end
	end
	return copy
end

local function getDataService()
	if not DataService then
		DataService = rawget(Services, "DataService")
	end
	return DataService
end

local function buildDefinitionIndex()
	DefinitionsById = {}
	DefinitionsByGoal = {}

	for _, def in ipairs(AchievementsConfig.GetDefinitions()) do
		DefinitionsById[def.Id] = def
		DefinitionsByGoal[def.GoalType] = DefinitionsByGoal[def.GoalType] or {}
		table.insert(DefinitionsByGoal[def.GoalType], def)
	end
end

local function getDefaultState()
	return {
		Progress = {},
		Unlocked = {},
		Claimed = {},
		LastUpdated = 0,
	}
end

local function getState(player)
	local ds = getDataService()
	if not ds then
		return nil
	end

	local state = ds.GetComponentData(player, COMPONENT_KEY)
	if state then
		return state
	end

	if ds.IsLoaded(player) then
		local defaults = getDefaultState()
		ds.SetComponentData(player, COMPONENT_KEY, defaults)
		return ds.GetComponentData(player, COMPONENT_KEY)
	end

	return nil
end

local function buildSnapshot(player)
	local state = getState(player)
	if not state then
		return {
			Definitions = AchievementsConfig.GetDefinitions(),
			State = getDefaultState(),
		}
	end

	return {
		Definitions = AchievementsConfig.GetDefinitions(),
		State = state,
	}
end

local function pushSnapshot(player)
	AchievementUpdatedEvent:FireClient(player, buildSnapshot(player))
end

local function attachMoneyBalanceObserver(player)
	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", 15)
		if not leaderstats then
			return
		end
		local money = leaderstats:WaitForChild("Money", 15)
		if not money then
			return
		end
		AchievementsManager.SetProgress(player, "cash_balance_reached", money.Value)
		money:GetPropertyChangedSignal("Value"):Connect(function()
			AchievementsManager.SetProgress(player, "cash_balance_reached", money.Value)
		end)
	end)
end

local function awardReward(player, reward)
	if type(reward) ~= "table" then
		return false, "Invalid reward", false
	end

	if reward.AdvancedPending == true then
		return true, nil, true
	end

	if reward.Type == "money" then
		local ds = getDataService()
		if not ds then
			return false, "Data service unavailable"
		end
		local amount = math.max(0, math.floor(tonumber(reward.Amount) or 0))
		if amount <= 0 then
			return false, "Invalid reward amount"
		end
		ds.AddMoney(player, amount)
		return true, nil, false
	end

	if reward.Type == "braincells" then
		local ds = getDataService()
		if not ds then
			return false, "Data service unavailable", false
		end
		local amount = math.max(0, math.floor(tonumber(reward.Amount) or 0))
		if amount <= 0 then
			return false, "Invalid reward amount", false
		end
		ds.AddBraincells(player, amount)
		return true, nil, false
	end

	return true, nil, true
end

local function unlockIfNeeded(player, achievementId, definition, state)
	if state.Unlocked[achievementId] then
		return false
	end

	local progressValue = state.Progress[achievementId] or 0
	if progressValue < (definition.TargetValue or 0) then
		return false
	end

	state.Unlocked[achievementId] = true
	AchievementNotifyEvent:FireClient(player, {
		Action = "Unlocked",
		AchievementId = achievementId,
		Title = definition.Title,
	})
	return true
end

function AchievementsManager.RecordProgress(player, goalType, amount)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local numericAmount = math.floor(tonumber(amount) or 0)
	if numericAmount <= 0 then
		return
	end

	local defs = DefinitionsByGoal[goalType]
	if not defs or #defs == 0 then
		return
	end

	local state = getState(player)
	if not state then
		return
	end

	state.Progress = state.Progress or {}
	state.Unlocked = state.Unlocked or {}
	state.Claimed = state.Claimed or {}

	local changed = false
	for _, def in ipairs(defs) do
		local achievementId = def.Id
		local current = state.Progress[achievementId] or 0
		local target = def.TargetValue or 0
		if current < target then
			local nextValue = math.min(target, current + numericAmount)
			if nextValue ~= current then
				state.Progress[achievementId] = nextValue
				changed = true
				unlockIfNeeded(player, achievementId, def, state)
			end
		end
	end

	if changed then
		state.LastUpdated = os.time()
		pushSnapshot(player)
	end
end

function AchievementsManager.SetProgress(player, goalType, absoluteValue)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local numericValue = math.max(0, math.floor(tonumber(absoluteValue) or 0))
	local defs = DefinitionsByGoal[goalType]
	if not defs or #defs == 0 then
		return
	end

	local state = getState(player)
	if not state then
		return
	end

	state.Progress = state.Progress or {}
	state.Unlocked = state.Unlocked or {}
	state.Claimed = state.Claimed or {}

	local changed = false
	for _, def in ipairs(defs) do
		local achievementId = def.Id
		local target = def.TargetValue or 0
		local nextValue = math.min(target, numericValue)
		if (state.Progress[achievementId] or 0) ~= nextValue then
			state.Progress[achievementId] = nextValue
			changed = true
			unlockIfNeeded(player, achievementId, def, state)
		end
	end

	if changed then
		state.LastUpdated = os.time()
		pushSnapshot(player)
	end
end

function AchievementsManager.MarkGoalComplete(player, goalType)
	AchievementsManager.RecordProgress(player, goalType, 1)
end

function AchievementsManager.ClaimReward(player, achievementId)
	local definition = DefinitionsById[achievementId]
	if not definition then
		return false, "Unknown achievement"
	end

	local state = getState(player)
	if not state then
		return false, "Data unavailable"
	end

	state.Progress = state.Progress or {}
	state.Unlocked = state.Unlocked or {}
	state.Claimed = state.Claimed or {}

	if state.Claimed[achievementId] then
		return false, "Already claimed"
	end

	if not state.Unlocked[achievementId] then
		return false, "Not unlocked"
	end

	local rewards = definition.Rewards or {}
	local hadAppliedReward = false
	local hasAdvancedPending = false

	for _, reward in ipairs(rewards) do
		local ok, err, isPending = awardReward(player, reward)
		if not ok then
			return false, err or "Reward failed"
		end
		if isPending then
			hasAdvancedPending = true
		else
			hadAppliedReward = true
		end
	end

	if (not hadAppliedReward) and hasAdvancedPending then
		return false, "Reward unlocks in phase 3"
	end

	state.Claimed[achievementId] = true
	state.LastUpdated = os.time()

	AchievementNotifyEvent:FireClient(player, {
		Action = "Claimed",
		AchievementId = achievementId,
		Title = definition.Title,
		Rewards = definition.Rewards,
		HasAdvancedPending = hasAdvancedPending,
	})

	pushSnapshot(player)
	return true, "Claimed"
end

function AchievementsManager.GetSnapshot(player)
	return buildSnapshot(player)
end

function AchievementsManager.Init(services)
	print("   AchievementsManager (Module) - Initializing")
	Services = services or {}
	buildDefinitionIndex()

	local ds = getDataService()
	if ds then
		ds.RegisterHandler(COMPONENT_KEY, {
			DefaultData = getDefaultState(),
			OnLoad = function(player, data)
				if type(data) ~= "table" then
					ds.SetComponentData(player, COMPONENT_KEY, deepCopy(getDefaultState()))
				end
				task.defer(function()
					pushSnapshot(player)
				end)
			end,
			OnSave = function(_player, data)
				return data
			end,
		})
	end

	GetAchievementsSnapshotFunction.OnServerInvoke = function(player)
		return AchievementsManager.GetSnapshot(player)
	end

	ClaimAchievementRewardFunction.OnServerInvoke = function(player, achievementId)
		if type(achievementId) ~= "string" then
			return false, "Invalid achievement id"
		end
		return AchievementsManager.ClaimReward(player, achievementId)
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			pushSnapshot(player)
		end)
		attachMoneyBalanceObserver(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		attachMoneyBalanceObserver(player)
	end

	print("✓ AchievementsManager Initialized")
end

return AchievementsManager
