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

local MARKET_INTEL_UNLOCK_LIFETIME_EARNINGS = 1500
local MARKET_UNLOCK_LIFETIME_EARNINGS = 2500
local MANUAL_LOGISTICS_UNLOCK_LIFETIME_EARNINGS = 3500
local SYNERGY_UNLOCK_LIFETIME_EARNINGS = 4000
local ARTIFACTS_UNLOCK_LIFETIME_EARNINGS = 8000
local CONTRACTS_UNLOCK_LIFETIME_EARNINGS = 12000

local CORE_UNLOCK_SEQUENCE = {
	{
		attribute = "MarketIntelUnlocked",
		title = "Market Intel",
		target = MARKET_INTEL_UNLOCK_LIFETIME_EARNINGS,
		description = "Live trend intel and better sell callouts.",
	},
	{
		attribute = "DetailedMarketUnlocked",
		title = "Market Terminal",
		target = MARKET_UNLOCK_LIFETIME_EARNINGS,
		description = "Open the market terminal and target better sell windows.",
	},
	{
		attribute = "ManualLogisticsUnlocked",
		title = "Logistics",
		target = MANUAL_LOGISTICS_UNLOCK_LIFETIME_EARNINGS,
		description = "Cart throughput tools open up as your volume grows.",
	},
	{
		attribute = "SynergyUnlocked",
		title = "Synergies",
		target = SYNERGY_UNLOCK_LIFETIME_EARNINGS,
		description = "Pair weird units for rarer, higher-value outputs.",
	},
	{
		attribute = "ArtifactsUnlocked",
		title = "Artifacts",
		target = ARTIFACTS_UNLOCK_LIFETIME_EARNINGS,
		description = "Rare relics can start dropping from production.",
	},
	{
		attribute = "ContractsUnlocked",
		title = "Contracts",
		target = CONTRACTS_UNLOCK_LIFETIME_EARNINGS,
		description = "Bulk buyers appear with bigger payout asks.",
	},
}

local MIDGAME_GOAL_SEQUENCE = {
	"midgame_targeted_seller",
	"midgame_expand_line",
	"midgame_full_cart",
	"midgame_first_synergy",
	"midgame_cart_tier_two",
	"midgame_first_contract",
}

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
		Meta = {},
		LastUpdated = 0,
	}
end

local function getLifetimeEarnings(player)
	local ds = getDataService()
	local rootData = ds and ds.GetData and ds.GetData(player)
	return math.max(0, math.floor(tonumber(rootData and rootData.lifetimeEarnings) or 0))
end

local function getArtifactInventorySummary(player)
	local ds = getDataService()
	if not ds or not ds.GetComponentData then
		return 0, false
	end

	local artifactData = ds.GetComponentData(player, "Artifacts")
	if type(artifactData) ~= "table" then
		return 0, false
	end

	local count = 0
	local hasEquipped = false
	for _, artifact in pairs(artifactData) do
		if type(artifact) == "table" then
			count += 1
			if artifact.EquippedTo ~= nil then
				hasEquipped = true
			end
		end
	end

	return count, hasEquipped
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

local function getAchievementProgress(state, achievementId)
	local progressMap = state and state.Progress or {}
	return tonumber(progressMap[achievementId]) or 0
end

local function getMaxGoalProgress(state, goalType)
	local highest = 0
	local defs = DefinitionsByGoal[goalType] or {}
	for _, def in ipairs(defs) do
		highest = math.max(highest, getAchievementProgress(state, def.Id))
	end
	return highest
end

local function getOnboardingStage(state)
	local highestStage = 0
	local progressMap = state and state.Progress or {}

	for _, def in ipairs(AchievementsConfig.GetDefinitions()) do
		if def.OnboardingOrder then
			local progressValue = tonumber(progressMap[def.Id]) or 0
			if progressValue >= (def.TargetValue or 0) then
				highestStage = math.max(highestStage, def.OnboardingOrder)
			end
		end
	end

	return highestStage
end

local function hasCompletedGoal(state, goalType)
	local progressMap = state and state.Progress or {}

	for _, def in ipairs(AchievementsConfig.GetDefinitions()) do
		if def.GoalType == goalType then
			local progressValue = tonumber(progressMap[def.Id]) or 0
			if progressValue >= (def.TargetValue or 0) then
				return true
			end
		end
	end

	return false
end

local function hasCompletedAchievement(state, achievementId)
	local definition = DefinitionsById[achievementId]
	if not definition then
		return false
	end
	return getAchievementProgress(state, achievementId) >= (definition.TargetValue or 0)
end

local function getNextMidgameGoal(state, unlockStates, terminalIntroComplete, tutorialComplete)
	if tutorialComplete ~= true or terminalIntroComplete ~= true then
		return nil
	end

	for _, achievementId in ipairs(MIDGAME_GOAL_SEQUENCE) do
		local definition = DefinitionsById[achievementId]
		if definition and not hasCompletedAchievement(state, achievementId) then
			local available = true

			if achievementId == "midgame_full_cart" or achievementId == "midgame_cart_tier_two" then
				available = unlockStates.ManualLogisticsUnlocked == true
			elseif achievementId == "midgame_first_synergy" then
				available = unlockStates.SynergyUnlocked == true
			elseif achievementId == "midgame_first_contract" then
				available = unlockStates.ContractsUnlocked == true
			end

			if available then
				return definition
			end

			return nil
		end
	end

	return nil
end

local function refreshPlayerUnlockAttributes(player, state)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local resolvedState = state or getState(player) or getDefaultState()
	resolvedState.Meta = resolvedState.Meta or {}
	local onboardingStage = getOnboardingStage(resolvedState)
	local terminalIntroComplete = hasCompletedGoal(resolvedState, "first_cart_sale")
	local firstSynergyActivated = hasCompletedGoal(resolvedState, "synergy_activated")
	local synergyUniqueProgress = getMaxGoalProgress(resolvedState, "synergy_unique_active")
	if synergyUniqueProgress >= 3 then
		resolvedState.Meta.SynergyReferenceUnlocked = true
	end
	local synergyReferenceUnlocked = resolvedState.Meta.SynergyReferenceUnlocked == true
	local tutorialComplete = onboardingStage >= 5
	local lifetimeEarnings = getLifetimeEarnings(player)
	local marketIntelUnlocked = lifetimeEarnings >= MARKET_INTEL_UNLOCK_LIFETIME_EARNINGS
	local marketUnlocked = lifetimeEarnings >= MARKET_UNLOCK_LIFETIME_EARNINGS
	local manualLogisticsUnlocked = lifetimeEarnings >= MANUAL_LOGISTICS_UNLOCK_LIFETIME_EARNINGS
	local synergyUnlocked = lifetimeEarnings >= SYNERGY_UNLOCK_LIFETIME_EARNINGS
	local artifactsUnlocked = lifetimeEarnings >= ARTIFACTS_UNLOCK_LIFETIME_EARNINGS
	local contractsUnlocked = lifetimeEarnings >= CONTRACTS_UNLOCK_LIFETIME_EARNINGS
	local _artifactCount, hasEquippedArtifact = getArtifactInventorySummary(player)
	local firstArtifactFound = hasCompletedGoal(resolvedState, "artifact_drop")
	if hasEquippedArtifact then
		resolvedState.Meta.FirstArtifactEquipped = true
	end
	local firstArtifactEquipped = resolvedState.Meta.FirstArtifactEquipped == true
	local synergyGuideStage = 0
	if synergyUnlocked then
		if synergyReferenceUnlocked then
			synergyGuideStage = 3
		elseif firstSynergyActivated then
			synergyGuideStage = 2
		else
			synergyGuideStage = 1
		end
	end
	local artifactGuideStage = 0
	if artifactsUnlocked then
		if firstArtifactEquipped then
			artifactGuideStage = 3
		elseif firstArtifactFound then
			artifactGuideStage = 2
		else
			artifactGuideStage = 1
		end
	end
	local unlockStates = {
		MarketIntelUnlocked = marketIntelUnlocked,
		DetailedMarketUnlocked = marketUnlocked,
		ManualLogisticsUnlocked = manualLogisticsUnlocked,
		SynergyUnlocked = synergyUnlocked,
		ArtifactsUnlocked = artifactsUnlocked,
		ContractsUnlocked = contractsUnlocked,
	}
	local nextGoal = getNextMidgameGoal(resolvedState, unlockStates, terminalIntroComplete, tutorialComplete)

	local nextUnlock = nil
	for _, unlockDef in ipairs(CORE_UNLOCK_SEQUENCE) do
		if unlockStates[unlockDef.attribute] ~= true then
			nextUnlock = unlockDef
			break
		end
	end

	player:SetAttribute("OnboardingStage", onboardingStage)
	player:SetAttribute("TerminalIntroComplete", terminalIntroComplete)
	player:SetAttribute("TutorialComplete", tutorialComplete)
	player:SetAttribute("LifetimeEarnings", lifetimeEarnings)
	player:SetAttribute("MarketIntelUnlocked", marketIntelUnlocked)
	player:SetAttribute("DetailedMarketUnlocked", marketUnlocked)
	player:SetAttribute("ManualLogisticsUnlocked", manualLogisticsUnlocked)
	player:SetAttribute("SynergyUnlocked", synergyUnlocked)
	player:SetAttribute("FirstSynergyActivated", firstSynergyActivated)
	player:SetAttribute("SynergyGuideStage", synergyGuideStage)
	player:SetAttribute("SynergyReferenceUnlocked", synergyReferenceUnlocked)
	player:SetAttribute("ArtifactsUnlocked", artifactsUnlocked)
	player:SetAttribute("FirstArtifactFound", firstArtifactFound)
	player:SetAttribute("FirstArtifactEquipped", firstArtifactEquipped)
	player:SetAttribute("ArtifactGuideStage", artifactGuideStage)
	player:SetAttribute("ContractsUnlocked", contractsUnlocked)
	player:SetAttribute("NextGoalName", nextGoal and nextGoal.Title or "")
	player:SetAttribute("NextGoalDescription", nextGoal and nextGoal.Description or "")
	player:SetAttribute("NextGoalTarget", nextGoal and (nextGoal.TargetValue or 0) or 0)
	player:SetAttribute(
		"NextGoalProgress",
		nextGoal and math.min(getAchievementProgress(resolvedState, nextGoal.Id), nextGoal.TargetValue or 0) or 0
	)
	player:SetAttribute("NextUnlockName", nextUnlock and nextUnlock.title or "")
	player:SetAttribute("NextUnlockTarget", nextUnlock and nextUnlock.target or lifetimeEarnings)
	player:SetAttribute("NextUnlockProgress", nextUnlock and math.min(lifetimeEarnings, nextUnlock.target) or lifetimeEarnings)
	player:SetAttribute("NextUnlockDescription", nextUnlock and nextUnlock.description or "All core systems unlocked.")
end

local evaluateAllUnlocks

local function pushSnapshot(player)
	local snapshot = buildSnapshot(player)
	if evaluateAllUnlocks then
		evaluateAllUnlocks(player, snapshot.State)
	end
	refreshPlayerUnlockAttributes(player, snapshot.State)
	AchievementUpdatedEvent:FireClient(player, snapshot)
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
		refreshPlayerUnlockAttributes(player)
		money:GetPropertyChangedSignal("Value"):Connect(function()
			AchievementsManager.SetProgress(player, "cash_balance_reached", money.Value)
			refreshPlayerUnlockAttributes(player)
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

	if definition.AutoClaim == true then
		local hasAdvancedPending = false
		for _, reward in ipairs(definition.Rewards or {}) do
			local ok, err, isPending = awardReward(player, reward)
			if not ok then
				warn(string.format("AchievementsManager: failed to auto-claim %s for %s: %s", achievementId, player.Name, tostring(err)))
				break
			end
			if isPending then
				hasAdvancedPending = true
			end
		end

		state.Claimed[achievementId] = true
		AchievementNotifyEvent:FireClient(player, {
			Action = "ObjectiveComplete",
			AchievementId = achievementId,
			Title = definition.Title,
			Rewards = definition.Rewards,
			HasAdvancedPending = hasAdvancedPending,
		})
		return true
	end

	AchievementNotifyEvent:FireClient(player, {
		Action = "Unlocked",
		AchievementId = achievementId,
		Title = definition.Title,
	})
	return true
end

evaluateAllUnlocks = function(player, state)
	if type(state) ~= "table" then
		return
	end

	state.Progress = state.Progress or {}
	state.Unlocked = state.Unlocked or {}
	state.Claimed = state.Claimed or {}
	state.Meta = state.Meta or {}

	local changed = false
	for _, definition in ipairs(AchievementsConfig.GetDefinitions()) do
		if unlockIfNeeded(player, definition.Id, definition, state) then
			changed = true
		end
	end

	if changed then
		state.LastUpdated = os.time()
	end
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
	state.Meta = state.Meta or {}

	if goalType == "synergy_unique_active" and numericValue >= 3 then
		state.Meta.SynergyReferenceUnlocked = true
	end

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

	if definition.AutoClaim == true then
		return false, "Automatically claimed"
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

function AchievementsManager.RefreshPlayerUnlockAttributes(player)
	refreshPlayerUnlockAttributes(player)
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
					refreshPlayerUnlockAttributes(player)
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
			refreshPlayerUnlockAttributes(player)
			pushSnapshot(player)
		end)
		attachMoneyBalanceObserver(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		refreshPlayerUnlockAttributes(player)
		attachMoneyBalanceObserver(player)
	end

	print("✓ AchievementsManager Initialized")
end

return AchievementsManager
