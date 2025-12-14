--[[
	UnitInteractionManager Server Script
	
	Handles ProximityPrompts on brainrot units for the equipment UI.
	
	Features:
	- Creates ProximityPrompt on every spawned brainrot unit
	- Fires event to open equipment UI when triggered
	- Cleans up prompts when units are removed
	
	Part of Phase 4: Interaction & UI.
]]

-- Services
local _Players = game:GetService("Players")  -- Reserved for future use
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

-- Constants
local BRAINROT_TAG = "ActiveBrainrot"

-- Remote events
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if not RemoteEvents then
	RemoteEvents = Instance.new("Folder")
	RemoteEvents.Name = "RemoteEvents"
	RemoteEvents.Parent = ReplicatedStorage
end

-- Create event for opening unit UI
local OpenUnitUIEvent = RemoteEvents:FindFirstChild("OpenUnitUI") or Instance.new("RemoteEvent")
OpenUnitUIEvent.Name = "OpenUnitUI"
OpenUnitUIEvent.Parent = RemoteEvents

-- Configuration
local CONFIG = {
	PROMPT_ACTION_TEXT = "Inspect",
	PROMPT_OBJECT_TEXT = "Equipment",
	PROMPT_KEY = Enum.KeyCode.E,
	PROMPT_HOLD_DURATION = 0,
	PROMPT_MAX_DISTANCE = 15,
	PROMPT_LINE_OF_SIGHT = false,
}

--------------------------------------------------------------------------------
-- PROMPT MANAGEMENT
--------------------------------------------------------------------------------

--[[
	Creates a ProximityPrompt for a brainrot unit.
	@param unit Model - The brainrot model
]]
local function createPromptForUnit(unit)
	-- Skip if already has prompt
	if unit:FindFirstChild("InspectPrompt") then
		return
	end
	
	-- Find attachment point (prefer root part)
	local attachPart = unit.PrimaryPart 
		or unit:FindFirstChild("HumanoidRootPart")
		or unit:FindFirstChild("RootPart")
		or unit:FindFirstChildWhichIsA("BasePart")
	
	if not attachPart then
		warn("UnitInteractionManager: No attachment part for " .. unit.Name)
		return
	end
	
	-- Create the prompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "InspectPrompt"
	prompt.ActionText = CONFIG.PROMPT_ACTION_TEXT
	prompt.ObjectText = CONFIG.PROMPT_OBJECT_TEXT
	prompt.KeyboardKeyCode = CONFIG.PROMPT_KEY
	prompt.HoldDuration = CONFIG.PROMPT_HOLD_DURATION
	prompt.MaxActivationDistance = CONFIG.PROMPT_MAX_DISTANCE
	prompt.RequiresLineOfSight = CONFIG.PROMPT_LINE_OF_SIGHT
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = attachPart
	
	-- Connect trigger
	prompt.Triggered:Connect(function(playerWhoTriggered)
		-- Verify player owns this unit
		local ownerId = unit:GetAttribute("OwnerId")
		if ownerId ~= playerWhoTriggered.UserId then
			return
		end
		
		-- Gather unit data
		-- Auto-generate UnitId if missing (migration for old units)
		local unitId = unit:GetAttribute("UnitId")
		if not unitId then
			local HttpService = game:GetService("HttpService")
			unitId = HttpService:GenerateGUID(false)
			unit:SetAttribute("UnitId", unitId)
			print(string.format("🔧 Migrated unit %s with new UnitId", unit.Name))
		end
		
		local unitData = {
			unitGUID = unitId,
			unitType = unit:GetAttribute("UnitType") or unit.Name,
			level = unit:GetAttribute("Level") or 1,
			rarity = unit:GetAttribute("Rarity") or "Normal",
			gridSlot = unit:GetAttribute("GridSlot"),
			itemTier = unit:GetAttribute("ItemTier") or 1,
		}
		
		-- Fire event to client
		OpenUnitUIEvent:FireClient(playerWhoTriggered, unitData)
		
		print(string.format("🔍 %s inspecting %s", playerWhoTriggered.Name, unitData.unitType))
	end)
end

--[[
	Removes the ProximityPrompt from a unit.
	@param unit Model - The brainrot model
]]
local function removePromptFromUnit(unit)
	local existingPrompt = unit:FindFirstChild("InspectPrompt", true)
	if existingPrompt then
		existingPrompt:Destroy()
	end
end

--------------------------------------------------------------------------------
-- TAG LISTENER
--------------------------------------------------------------------------------

-- Add prompts to existing tagged units
for _, unit in CollectionService:GetTagged(BRAINROT_TAG) do
	task.spawn(function()
		-- Wait a frame for unit to be fully set up
		task.wait()
		createPromptForUnit(unit)
	end)
end

-- Add prompts when new units are tagged
CollectionService:GetInstanceAddedSignal(BRAINROT_TAG):Connect(function(unit)
	task.spawn(function()
		-- Wait a frame for attributes to be set
		task.wait()
		createPromptForUnit(unit)
	end)
end)

-- Remove prompts when units are untagged
CollectionService:GetInstanceRemovedSignal(BRAINROT_TAG):Connect(function(unit)
	removePromptFromUnit(unit)
end)

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

print("═══════════════════════════════════════════")
print("   UnitInteractionManager - Initializing")
print("═══════════════════════════════════════════")
print("✓ UnitInteractionManager initialized")
print("  • Prompt key: " .. CONFIG.PROMPT_KEY.Name)
print("  • Max distance: " .. CONFIG.PROMPT_MAX_DISTANCE .. " studs")
print("═══════════════════════════════════════════")

-- Export API
_G.UnitInteractionManager = {
	CreatePromptForUnit = createPromptForUnit,
	RemovePromptFromUnit = removePromptFromUnit,
}
