--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ContractConfig = require(Shared:WaitForChild("ContractConfig"))
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local GetActiveContractsFunction = RemoteFunctions:FindFirstChild("GetActiveContracts") or Instance.new("RemoteFunction")
GetActiveContractsFunction.Name = "GetActiveContracts"
GetActiveContractsFunction.Parent = RemoteFunctions

local DeliverToContractFunction = RemoteFunctions:FindFirstChild("DeliverToContract") or Instance.new("RemoteFunction")
DeliverToContractFunction.Name = "DeliverToContract"
DeliverToContractFunction.Parent = RemoteFunctions

local ContractEvent = RemoteEvents:FindFirstChild("ContractEvent") or Instance.new("RemoteEvent")
ContractEvent.Name = "ContractEvent"
ContractEvent.Parent = RemoteEvents

local ContractManager = {}
local Services = {}

local function recordAchievement(player, goalType, amount)
	local achievementManager = rawget(Services, "AchievementsManager")
	if achievementManager and achievementManager.RecordProgress then
		achievementManager.RecordProgress(player, goalType, amount)
	end
end

local ActiveContracts: {[string]: ContractConfig.ActiveContract} = {}
local PlayerLocks: {[number]: boolean} = {}
local ContractLocks: {[string]: boolean} = {}

local CONFIG = {
	SPAWN_INTERVAL_MIN = 10 * 60,
	SPAWN_INTERVAL_MAX = 15 * 60,
	FIRST_CONTRACT_DELAY = 60,
	FIRST_CONTRACT_REQUIRED_AMOUNT_MULTIPLIER = 0.35,
	EXPIRATION_TICK = 1.0,
	MAX_DELIVER_PER_CALL = 100000,
}

local InitialContractSpawned = false

local function now()
	return os.time()
end

local function cloneContract(contract: ContractConfig.ActiveContract): ContractConfig.ActiveContract
	local copy: ContractConfig.ActiveContract = {
		InstanceId = contract.InstanceId,
		TemplateId = contract.TemplateId,
		Type = contract.Type,
		Name = contract.Name,
		Description = contract.Description,
		TargetItemId = contract.TargetItemId,
		CurrentAmount = contract.CurrentAmount,
		RequiredAmount = contract.RequiredAmount,
		Multiplier = contract.Multiplier,
		StartTime = contract.StartTime,
		EndTime = contract.EndTime,
		IsCompleted = contract.IsCompleted,
		IsExpired = contract.IsExpired,
		Contributions = {},
	}
	for userId, amount in pairs(contract.Contributions) do
		copy.Contributions[userId] = amount
	end
	return copy
end

local function buildClientContractDictionary(): {[string]: ContractConfig.ActiveContract}
	local out: {[string]: ContractConfig.ActiveContract} = {}
	for instanceId, contract in pairs(ActiveContracts) do
		out[instanceId] = cloneContract(contract)
	end
	return out
end

local function broadcast(payload: ContractConfig.ContractEventPayload)
	ContractEvent:FireAllClients(payload)
end

local function getService(name: string)
	return rawget(Services, name)
end

local function getServerCartCapacity(): number
	local total = 0
	local cartManager = getService("CartManager")
	for _, player in ipairs(Players:GetPlayers()) do
		local cap = tonumber(player:GetAttribute("CartCapacity"))
		if not cap and cartManager and cartManager.GetCartState then
			local cart = cartManager.GetCartState(player)
			cap = cart and tonumber(cart.Capacity) or nil
		end
		total += math.max(tonumber(cap) or 200, 0)
	end
	return total
end

local function getSpawnIntervalSeconds(): number
	local forced = tonumber(workspace:GetAttribute("ContractSpawnIntervalSec"))
	if forced and forced > 0 then
		return math.floor(forced)
	end
	return math.random(CONFIG.SPAWN_INTERVAL_MIN, CONFIG.SPAWN_INTERVAL_MAX)
end

local function anyPlayerCanUseContracts(): boolean
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("ContractsUnlocked") == true then
			return true
		end
	end
	return false
end

local function getBestPlayerContractTarget(player: Player): (string?, number)
	local bestItemId = nil
	local bestCount = 0
	local itemStorageManager = getService("ItemStorageManager")
	local cartManager = getService("CartManager")
	local storageContents = {}

	if itemStorageManager and itemStorageManager.GetStorageContents then
		storageContents = itemStorageManager.GetStorageContents(player) or {}
		for itemId, count in pairs(storageContents) do
			local numericCount = math.floor(tonumber(count) or 0)
			if numericCount > bestCount then
				bestItemId = itemId
				bestCount = numericCount
			end
		end
	end

	if cartManager and cartManager.GetCartState then
		local cart = cartManager.GetCartState(player)
		if cart and type(cart.Inventory) == "table" then
			for itemId, count in pairs(cart.Inventory) do
				local combinedCount = math.floor(tonumber(count) or 0) + math.floor(tonumber(storageContents[itemId]) or 0)
				if combinedCount > bestCount then
					bestItemId = itemId
					bestCount = combinedCount
				end
			end
		end
	end

	return bestItemId, bestCount
end

local function getFlashTemplateForItem(itemId: string?): ContractConfig.ContractTemplate?
	if not itemId then
		return nil
	end

	local sector = ItemConfig.GetSectorByItemId(itemId)
	local matchingTemplates = {}
	for _, template in ipairs(ContractConfig.FlashOrderTemplates) do
		if template.TargetSector == sector then
			table.insert(matchingTemplates, template)
		end
	end

	if #matchingTemplates == 0 then
		return nil
	end

	return matchingTemplates[math.random(1, #matchingTemplates)]
end

local function getInitialContractContext(): {Template: ContractConfig.ContractTemplate?, TargetItemId: string?, RequiredAmountMultiplier: number}
	local bestItemId = nil
	local bestCount = 0

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("ContractsUnlocked") == true then
			local itemId, count = getBestPlayerContractTarget(player)
			if count > bestCount then
				bestItemId = itemId
				bestCount = count
			end
		end
	end

	return {
		Template = getFlashTemplateForItem(bestItemId) or ContractConfig.PickRandomTemplate("FlashOrder"),
		TargetItemId = bestItemId,
		RequiredAmountMultiplier = CONFIG.FIRST_CONTRACT_REQUIRED_AMOUNT_MULTIPLIER,
	}
end

local function removeContract(instanceId: string)
	ActiveContracts[instanceId] = nil
	ContractLocks[instanceId] = nil
end

local function markExpired(contract: ContractConfig.ActiveContract)
	contract.IsExpired = true
	broadcast({
		Action = "Expired",
		Contract = cloneContract(contract),
		InstanceId = contract.InstanceId,
		NewCurrentAmount = contract.CurrentAmount,
	})
	removeContract(contract.InstanceId)
end

local function awardMegaProjectRewards(contract: ContractConfig.ActiveContract): {number}
	local winners: {number} = {}
	local template = nil :: ContractConfig.ContractTemplate?
	for _, candidate in ipairs(ContractConfig.MegaProjectTemplates) do
		if candidate.Id == contract.TemplateId then
			template = candidate
			break
		end
	end
	if not template then
		return winners
	end

	local threshold = contract.RequiredAmount * math.max(0, template.MinContributionPct or 0)
	local dataService = getService("DataService")

	for userId, amount in pairs(contract.Contributions) do
		if amount >= threshold then
			table.insert(winners, userId)
			local player = Players:GetPlayerByUserId(userId)
			if player and dataService and template.Reward and template.Reward.CashBonus and dataService.AddMoney then
				dataService.AddMoney(player, template.Reward.CashBonus)
			end
		end
	end

	return winners
end

local function completeContract(contract: ContractConfig.ActiveContract)
	if contract.IsCompleted or contract.IsExpired then
		return
	end
	contract.IsCompleted = true

	local winners: {number}? = nil
	if contract.Type == "MegaProject" then
		winners = awardMegaProjectRewards(contract)
		if winners then
			for _, userId in ipairs(winners) do
				local winnerPlayer = Players:GetPlayerByUserId(userId)
				if winnerPlayer then
					recordAchievement(winnerPlayer, "mega_project_contributor", 1)
				end
			end
		end
	end

	broadcast({
		Action = "Completed",
		Contract = cloneContract(contract),
		InstanceId = contract.InstanceId,
		NewCurrentAmount = contract.CurrentAmount,
		Winners = winners,
	})

	removeContract(contract.InstanceId)
end

local function spawnContract(spawnContext: {Template: ContractConfig.ContractTemplate?, TargetItemId: string?, RequiredAmountMultiplier: number?}?)
	local template = (spawnContext and spawnContext.Template) or ContractConfig.PickRandomTemplate()
	if not template then
		return false
	end

	local contract = ContractConfig.BuildActiveContract(template, {
		ServerCapacity = getServerCartCapacity(),
		StartTime = now(),
		TargetItemId = spawnContext and spawnContext.TargetItemId or nil,
		RequiredAmountMultiplier = spawnContext and spawnContext.RequiredAmountMultiplier or nil,
	})
	if not contract then
		return false
	end

	ActiveContracts[contract.InstanceId] = contract
	broadcast({
		Action = "Spawned",
		Contract = cloneContract(contract),
		InstanceId = contract.InstanceId,
		NewCurrentAmount = contract.CurrentAmount,
	})
	return true
end

local function getTemplateById(templateId: string): ContractConfig.ContractTemplate?
	for _, template in ipairs(ContractConfig.FlashOrderTemplates) do
		if template.Id == templateId then
			return template
		end
	end
	for _, template in ipairs(ContractConfig.MegaProjectTemplates) do
		if template.Id == templateId then
			return template
		end
	end
	return nil
end

local function buildResponse(success: boolean, message: string, delivered: number, earned: number): ContractConfig.DeliverResponse
	return {
		Success = success,
		Message = message,
		AmountDelivered = delivered,
		CashEarned = earned,
	}
end

local function deliverToContract(player: Player, instanceId: string, maxAmount: number?): ContractConfig.DeliverResponse
	local userId = player.UserId
	if PlayerLocks[userId] then
		return buildResponse(false, "Delivery already in progress.", 0, 0)
	end

	PlayerLocks[userId] = true
	local ok, result = pcall(function()
		if type(instanceId) ~= "string" or instanceId == "" then
			return buildResponse(false, "Invalid contract id.", 0, 0)
		end

		local contract = ActiveContracts[instanceId]
		if not contract then
			return buildResponse(false, "Contract not found.", 0, 0)
		end
		if contract.IsCompleted or contract.IsExpired then
			return buildResponse(false, "Contract is no longer active.", 0, 0)
		end

		local cartManager = getService("CartManager")
		if not cartManager or not cartManager.GetCartState or not cartManager.RemoveFromCartInventory then
			return buildResponse(false, "Cart service unavailable.", 0, 0)
		end

		local cart = cartManager.GetCartState(player)
		if not cart or cart.State ~= "at_market" then
			return buildResponse(false, "Cart must be at market.", 0, 0)
		end

		local inCart = tonumber(cart.Inventory and cart.Inventory[contract.TargetItemId]) or 0
		if inCart <= 0 then
			return buildResponse(false, "No matching items in cart.", 0, 0)
		end

		local remaining = math.max(0, contract.RequiredAmount - contract.CurrentAmount)
		if remaining <= 0 then
			return buildResponse(false, "Contract is already full.", 0, 0)
		end

		local deliverCap = CONFIG.MAX_DELIVER_PER_CALL
		if type(maxAmount) == "number" and maxAmount > 0 then
			deliverCap = math.min(deliverCap, math.floor(maxAmount))
		end

		local toDeliver = math.min(inCart, remaining, deliverCap)
		if toDeliver <= 0 then
			return buildResponse(false, "Nothing to deliver.", 0, 0)
		end

		local removed = cartManager.RemoveFromCartInventory(player, contract.TargetItemId, toDeliver)
		if removed <= 0 then
			return buildResponse(false, "Delivery failed.", 0, 0)
		end

		contract.CurrentAmount += removed
		contract.Contributions[userId] = (contract.Contributions[userId] or 0) + removed

		local itemInfo = ItemConfig.Items[contract.TargetItemId]
		local basePrice = tonumber(itemInfo and itemInfo.basePrice) or 1
		basePrice = math.max(1, basePrice)
		local sector = ItemConfig.GetSectorByItemId(contract.TargetItemId)

		local stockMarketManager = getService("StockMarketManager")
		if stockMarketManager and stockMarketManager.AdjustPool and sector ~= "Neutral" then
			stockMarketManager.AdjustPool(sector, -removed, removed * basePrice)
		end

		local cashEarned = 0
		if contract.Type == "FlashOrder" then
			cashEarned = math.floor(removed * basePrice * contract.Multiplier)
			local dataService = getService("DataService")
			if dataService and dataService.AddMoney and cashEarned > 0 then
				dataService.AddMoney(player, cashEarned)
			end
		end

		broadcast({
			Action = "Updated",
			InstanceId = contract.InstanceId,
			NewCurrentAmount = contract.CurrentAmount,
		})

		if not ContractLocks[contract.InstanceId] then
			ContractLocks[contract.InstanceId] = true
			if contract.CurrentAmount >= contract.RequiredAmount then
				if contract.Type == "FlashOrder" then
					recordAchievement(player, "flash_order_finisher", 1)
				end
				completeContract(contract)
			end
			ContractLocks[contract.InstanceId] = nil
		end

		return buildResponse(true, "Delivered successfully.", removed, cashEarned)
	end)

	PlayerLocks[userId] = nil
	if not ok then
		warn("ContractManager: DeliverToContract failed:", result)
		return buildResponse(false, "Internal error.", 0, 0)
	end
	return result :: ContractConfig.DeliverResponse
end

local function runSpawnLoop()
	task.spawn(function()
		while true do
			if not anyPlayerCanUseContracts() then
				task.wait(60)
				continue
			end
			if not InitialContractSpawned and next(ActiveContracts) == nil then
				task.wait(CONFIG.FIRST_CONTRACT_DELAY)
				if not anyPlayerCanUseContracts() or next(ActiveContracts) ~= nil then
					continue
				end
				if spawnContract(getInitialContractContext()) then
					InitialContractSpawned = true
				end
				continue
			end
			task.wait(getSpawnIntervalSeconds())
			if not anyPlayerCanUseContracts() then
				continue
			end
			spawnContract()
		end
	end)
end

local function runExpirationLoop()
	task.spawn(function()
		while true do
			task.wait(CONFIG.EXPIRATION_TICK)
			local current = now()
			for _, contract in pairs(ActiveContracts) do
				if not contract.IsCompleted and not contract.IsExpired and current >= contract.EndTime then
					markExpired(contract)
				end
			end
		end
	end)
end

function ContractManager.GetActiveContracts()
	return buildClientContractDictionary()
end

function ContractManager.Init(services)
	print("   ContractManager (Module) - Initializing")
	Services = services or {}

	GetActiveContractsFunction.OnServerInvoke = function(_player: Player)
		return ContractManager.GetActiveContracts()
	end

	DeliverToContractFunction.OnServerInvoke = function(player: Player, instanceId: string, maxAmount: number?)
		return deliverToContract(player, instanceId, maxAmount)
	end

	Players.PlayerRemoving:Connect(function(player)
		PlayerLocks[player.UserId] = nil
	end)

	runSpawnLoop()
	runExpirationLoop()

	print("✓ ContractManager Initialized")
end

ContractManager._spawnContract = spawnContract
ContractManager._getTemplateById = getTemplateById

return ContractManager
