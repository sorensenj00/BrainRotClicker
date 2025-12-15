--[[
	UnitInteractionManager Server Module
	
	Handles ProximityPrompts on brainrot units.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local BRAINROT_TAG = "ActiveBrainrot"

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local OpenUnitUIEvent = RemoteEvents:FindFirstChild("OpenUnitUI") or Instance.new("RemoteEvent")
OpenUnitUIEvent.Name = "OpenUnitUI"
OpenUnitUIEvent.Parent = RemoteEvents

local CONFIG = {
	PROMPT_ACTION_TEXT = "Inspect",
	PROMPT_OBJECT_TEXT = "Equipment",
	PROMPT_KEY = Enum.KeyCode.E,
	PROMPT_HOLD_DURATION = 0,
	PROMPT_MAX_DISTANCE = 15,
	PROMPT_LINE_OF_SIGHT = false,
}

local UnitInteractionManager = {}
local Services = {}

--------------------------------------------------------------------------------
-- LOGIC
--------------------------------------------------------------------------------

local function createPromptForUnit(unit)
	if unit:FindFirstChild("InspectPrompt") then return end
	
	local attachPart = unit.PrimaryPart 
		or unit:FindFirstChild("HumanoidRootPart")
		or unit:FindFirstChild("RootPart")
		or unit:FindFirstChildWhichIsA("BasePart")
	
	if not attachPart then return end
	
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "InspectPrompt"
	prompt.ActionText = CONFIG.PROMPT_ACTION_TEXT
	prompt.ObjectText = CONFIG.PROMPT_OBJECT_TEXT
	prompt.KeyboardKeyCode = CONFIG.PROMPT_KEY
	prompt.HoldDuration = CONFIG.PROMPT_HOLD_DURATION
	prompt.MaxActivationDistance = CONFIG.PROMPT_MAX_DISTANCE
	prompt.RequiresLineOfSight = CONFIG.PROMPT_LINE_OF_SIGHT
	prompt.Parent = attachPart
	
	prompt.Triggered:Connect(function(player)
		local ownerId = unit:GetAttribute("OwnerId")
		if ownerId ~= player.UserId then return end
		
		local unitId = unit:GetAttribute("UnitId")
		if not unitId then
			unitId = HttpService:GenerateGUID(false)
			unit:SetAttribute("UnitId", unitId)
		end
		
		local data = {
			unitGUID = unitId,
			unitType = unit:GetAttribute("UnitType") or unit.Name,
			level = unit:GetAttribute("Level") or 1,
			rarity = unit:GetAttribute("Rarity") or "Normal",
			gridSlot = unit:GetAttribute("GridSlot"),
			itemTier = unit:GetAttribute("ItemTier") or 1,
		}
		
		OpenUnitUIEvent:FireClient(player, data)
	end)
end

local function removePromptFromUnit(unit)
	local p = unit:FindFirstChild("InspectPrompt", true)
	if p then p:Destroy() end
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function UnitInteractionManager.Init(services)
	print("   UnitInteractionManager (Module) - Initializing")
	Services = services or {}
	
	for _, unit in CollectionService:GetTagged(BRAINROT_TAG) do
		task.spawn(function()
			task.wait()
			createPromptForUnit(unit)
		end)
	end
	
	CollectionService:GetInstanceAddedSignal(BRAINROT_TAG):Connect(function(unit)
		task.spawn(function()
			task.wait()
			createPromptForUnit(unit)
		end)
	end)
	
	CollectionService:GetInstanceRemovedSignal(BRAINROT_TAG):Connect(function(unit)
		removePromptFromUnit(unit)
	end)
	
	print("✓ UnitInteractionManager Initialized")
end

UnitInteractionManager.CreatePromptForUnit = createPromptForUnit
UnitInteractionManager.RemovePromptFromUnit = removePromptFromUnit

return UnitInteractionManager
