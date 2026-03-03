--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

local ContractConfig = {}

export type ContractType = "FlashOrder" | "MegaProject"
export type ContractTier = "Light" | "Medium" | "Hard"

export type ContractReward = {
	CashBonus: number?,
	ArtifactRarity: string?,
	GlobalBuff: string?,
}

export type ContractTemplate = {
	Id: string,
	Type: ContractType,
	Name: string,
	Description: string,
	TargetSector: string?,
	TargetItemId: string?,
	Multiplier: number,
	Duration: number,
	BaseAmountRequired: number,
	MinContributionPct: number,
	Reward: ContractReward?,
}

export type ActiveContract = {
	InstanceId: string,
	TemplateId: string,
	Type: ContractType,
	Name: string,
	Description: string,
	TargetItemId: string,
	CurrentAmount: number,
	RequiredAmount: number,
	Multiplier: number,
	StartTime: number,
	EndTime: number,
	IsCompleted: boolean,
	IsExpired: boolean,
	Contributions: {[number]: number},
}

export type DeliverResponse = {
	Success: boolean,
	Message: string,
	AmountDelivered: number,
	CashEarned: number,
}

export type ContractEventPayload = {
	Action: "Spawned" | "Updated" | "Completed" | "Expired",
	Contract: ActiveContract?,
	InstanceId: string?,
	NewCurrentAmount: number?,
	Winners: {number}?,
}

ContractConfig.Tiers = {
	Light = { AmountMultiplier = 0.75 },
	Medium = { AmountMultiplier = 1.0 },
	Hard = { AmountMultiplier = 1.5 },
}

ContractConfig.FlashOrderTemplates = {
	{
		Id = "flash_tech_startup_panic",
		Type = "FlashOrder",
		Name = "Tech Startup Panic",
		Description = "Massive emergency procurement for cutting-edge tech components.",
		TargetSector = "Tech",
		Multiplier = 5.0,
		Duration = 300,
		BaseAmountRequired = 1200,
		MinContributionPct = 0,
	},
	{
		Id = "flash_action_munitions",
		Type = "FlashOrder",
		Name = "Action Munitions Rush",
		Description = "A private contractor is paying top dollar for action-grade supplies.",
		TargetSector = "Action",
		Multiplier = 4.5,
		Duration = 300,
		BaseAmountRequired = 1400,
		MinContributionPct = 0,
	},
	{
		Id = "flash_food_festival",
		Type = "FlashOrder",
		Name = "Mega Food Festival",
		Description = "Event organizers need emergency food shipments right now.",
		TargetSector = "Food",
		Multiplier = 4.0,
		Duration = 300,
		BaseAmountRequired = 1800,
		MinContributionPct = 0,
	},
}

ContractConfig.MegaProjectTemplates = {
	{
		Id = "mega_operation_mars",
		Type = "MegaProject",
		Name = "Operation Mars",
		Description = "Build and launch the first off-world colony. Every unit counts.",
		TargetSector = "Tech",
		Multiplier = 0,
		Duration = 300,
		BaseAmountRequired = 50000,
		MinContributionPct = 0.02,
		Reward = {
			CashBonus = 250000,
			GlobalBuff = "ServerSpeed2x",
		},
	},
	{
		Id = "mega_titan_wall",
		Type = "MegaProject",
		Name = "Titan Wall Initiative",
		Description = "Construct a continent-scale defensive wall before deadline.",
		TargetSector = "Action",
		Multiplier = 0,
		Duration = 300,
		BaseAmountRequired = 45000,
		MinContributionPct = 0.02,
		Reward = {
			CashBonus = 200000,
			ArtifactRarity = "Epic",
		},
	},
}

local allItemsBySector: {[string]: {string}} = {}

local function buildSectorLookup()
	if next(allItemsBySector) ~= nil then
		return
	end

	for itemId, _ in pairs(ItemConfig.Items) do
		local sector = ItemConfig.GetSectorByItemId(itemId)
		if not allItemsBySector[sector] then
			allItemsBySector[sector] = {}
		end
		table.insert(allItemsBySector[sector], itemId)
	end
end

local function pickRandom<T>(arr: {T}): T?
	if #arr == 0 then return nil end
	return arr[math.random(1, #arr)]
end

function ContractConfig.GetTierForServerCapacity(serverCapacity: number): ContractTier
	if serverCapacity >= 40000 then
		return "Hard"
	elseif serverCapacity >= 18000 then
		return "Medium"
	end
	return "Light"
end

function ContractConfig.ComputeCapacityFactor(serverCapacity: number): number
	local normalized = math.max(serverCapacity, 0) / 10000
	return math.clamp(normalized, 1, 12)
end

function ContractConfig.ComputeRequiredAmount(template: ContractTemplate, serverCapacity: number, tier: ContractTier): number
	local factor = ContractConfig.ComputeCapacityFactor(serverCapacity)
	local tierConfig = ContractConfig.Tiers[tier]
	local amount = template.BaseAmountRequired * factor * (tierConfig and tierConfig.AmountMultiplier or 1)
	return math.max(1, math.floor(amount))
end

function ContractConfig.PickRandomTemplate(kind: ContractType?): ContractTemplate?
	if kind == "FlashOrder" then
		return pickRandom(ContractConfig.FlashOrderTemplates)
	elseif kind == "MegaProject" then
		return pickRandom(ContractConfig.MegaProjectTemplates)
	end

	local chooseMega = math.random() < 0.35
	if chooseMega then
		return pickRandom(ContractConfig.MegaProjectTemplates)
	end
	return pickRandom(ContractConfig.FlashOrderTemplates)
end

function ContractConfig.ResolveTargetItemId(template: ContractTemplate): string?
	if template.TargetItemId then
		return template.TargetItemId
	end

	if template.TargetSector then
		buildSectorLookup()
		local pool = allItemsBySector[template.TargetSector]
		if pool and #pool > 0 then
			return pool[math.random(1, #pool)]
		end
	end

	-- Fallback to any known item if sector lookup failed.
	local fallback = {}
	for itemId, _ in pairs(ItemConfig.Items) do
		table.insert(fallback, itemId)
	end
	return pickRandom(fallback)
end

function ContractConfig.BuildActiveContract(template: ContractTemplate, context: {ServerCapacity: number, StartTime: number?}): ActiveContract?
	local targetItemId = ContractConfig.ResolveTargetItemId(template)
	if not targetItemId then
		return nil
	end

	local serverCapacity = context.ServerCapacity or 0
	local tier = ContractConfig.GetTierForServerCapacity(serverCapacity)
	local requiredAmount = ContractConfig.ComputeRequiredAmount(template, serverCapacity, tier)

	local startTime = context.StartTime or os.time()
	return {
		InstanceId = HttpService:GenerateGUID(false),
		TemplateId = template.Id,
		Type = template.Type,
		Name = template.Name,
		Description = template.Description,
		TargetItemId = targetItemId,
		CurrentAmount = 0,
		RequiredAmount = requiredAmount,
		Multiplier = template.Multiplier,
		StartTime = startTime,
		EndTime = startTime + template.Duration,
		IsCompleted = false,
		IsExpired = false,
		Contributions = {},
	}
end

return ContractConfig
