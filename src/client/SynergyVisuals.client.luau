--[[
	SynergyVisuals Client Script (V3)
	
	Draws beam effects between brainrot units in the same 2x2 cluster
	when they form a valid synergy pair. Beams update when units are
	placed, removed, or change production mode.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

-- Shared configs
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))

local BRAINROT_TAG = "ActiveBrainrot"

--------------------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------------------

local BEAM_CONFIG = {
	Color = ColorSequence.new(Color3.fromRGB(180, 100, 255), Color3.fromRGB(100, 200, 255)),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0.4),
	}),
	Width0 = 0.6,
	Width1 = 0.6,
	TextureSpeed = 0.8,
	FaceCamera = true,
	LightEmission = 0.7,
	LightInfluence = 0.2,
	Segments = 10,
	CurveSize0 = 1,
	CurveSize1 = -1,
}

local PARTICLE_CONFIG = {
	Color = ColorSequence.new(Color3.fromRGB(200, 120, 255)),
	Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Lifetime = NumberRange.new(0.8, 1.5),
	Rate = 6,
	Speed = NumberRange.new(0.5, 1.5),
	SpreadAngle = Vector2.new(30, 30),
	LightEmission = 0.8,
	LightInfluence = 0.1,
}

--------------------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------------------

local activeBeams = {} -- { beam, attachment0, attachment1, particleA, particleB }

local function getAttachPart(unitModel)
	return unitModel.PrimaryPart
		or unitModel:FindFirstChild("HumanoidRootPart")
		or unitModel:FindFirstChild("RootPart")
		or unitModel:FindFirstChildWhichIsA("BasePart")
end

local function getClusterSlots(slotIndex)
	local clusterIdx = math.floor((slotIndex - 1) / 4)
	local baseSlot = clusterIdx * 4 + 1
	return { baseSlot, baseSlot + 1, baseSlot + 2, baseSlot + 3 }
end

local function clearAllBeams()
	for _, beamData in ipairs(activeBeams) do
		if beamData.beam then beamData.beam:Destroy() end
		if beamData.att0 then beamData.att0:Destroy() end
		if beamData.att1 then beamData.att1:Destroy() end
		if beamData.particleA then beamData.particleA:Destroy() end
		if beamData.particleB then beamData.particleB:Destroy() end
	end
	activeBeams = {}
end

local function createBeam(unitA, unitB)
	local partA = getAttachPart(unitA)
	local partB = getAttachPart(unitB)
	if not partA or not partB then return end
	
	-- Create attachments
	local att0 = Instance.new("Attachment")
	att0.Name = "SynergyAtt0"
	att0.Position = Vector3.new(0, 2, 0)
	att0.Parent = partA
	
	local att1 = Instance.new("Attachment")
	att1.Name = "SynergyAtt1"
	att1.Position = Vector3.new(0, 2, 0)
	att1.Parent = partB
	
	-- Create beam
	local beam = Instance.new("Beam")
	beam.Name = "SynergyBeam"
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Color = BEAM_CONFIG.Color
	beam.Transparency = BEAM_CONFIG.Transparency
	beam.Width0 = BEAM_CONFIG.Width0
	beam.Width1 = BEAM_CONFIG.Width1
	beam.TextureSpeed = BEAM_CONFIG.TextureSpeed
	beam.FaceCamera = BEAM_CONFIG.FaceCamera
	beam.LightEmission = BEAM_CONFIG.LightEmission
	beam.LightInfluence = BEAM_CONFIG.LightInfluence
	beam.Segments = BEAM_CONFIG.Segments
	beam.CurveSize0 = BEAM_CONFIG.CurveSize0
	beam.CurveSize1 = BEAM_CONFIG.CurveSize1
	beam.Parent = partA
	
	-- Particle effects at synergy nodes
	local particleA = Instance.new("ParticleEmitter")
	particleA.Name = "SynergyParticle"
	particleA.Color = PARTICLE_CONFIG.Color
	particleA.Size = PARTICLE_CONFIG.Size
	particleA.Transparency = PARTICLE_CONFIG.Transparency
	particleA.Lifetime = PARTICLE_CONFIG.Lifetime
	particleA.Rate = PARTICLE_CONFIG.Rate
	particleA.Speed = PARTICLE_CONFIG.Speed
	particleA.SpreadAngle = PARTICLE_CONFIG.SpreadAngle
	particleA.LightEmission = PARTICLE_CONFIG.LightEmission
	particleA.LightInfluence = PARTICLE_CONFIG.LightInfluence
	particleA.Parent = att0
	
	local particleB = particleA:Clone()
	particleB.Parent = att1
	
	table.insert(activeBeams, {
		beam = beam,
		att0 = att0,
		att1 = att1,
		particleA = particleA,
		particleB = particleB,
	})
end

--------------------------------------------------------------------------------
-- SCAN & REFRESH
--------------------------------------------------------------------------------

local function refreshSynergyVisuals()
	clearAllBeams()
	
	-- Build map of slot → unit model (only own units)
	local slotToUnit = {}
	for _, unit in CollectionService:GetTagged(BRAINROT_TAG) do
		if unit:GetAttribute("OwnerId") == player.UserId then
			local slot = unit:GetAttribute("GridSlot")
			if slot then
				slotToUnit[slot] = unit
			end
		end
	end
	
	-- Check each pair within each cluster
	local checked = {} -- Prevent duplicate beam pairs
	
	for slot, unit in pairs(slotToUnit) do
		local unitType = unit:GetAttribute("UnitType")
		if not unitType then continue end
		
		local clusterSlots = getClusterSlots(slot)
		for _, neighborSlot in ipairs(clusterSlots) do
			if neighborSlot ~= slot and slotToUnit[neighborSlot] then
				-- Create a sorted key to avoid duplicate beams
				local pairKey = math.min(slot, neighborSlot) .. "_" .. math.max(slot, neighborSlot)
				if not checked[pairKey] then
					checked[pairKey] = true
					
					local neighborUnit = slotToUnit[neighborSlot]
					local neighborType = neighborUnit:GetAttribute("UnitType")
					
					if neighborType then
						local synergy = ItemConfig.GetSynergyOverride(unitType, neighborType)
						if synergy then
							createBeam(unit, neighborUnit)
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- INIT
--------------------------------------------------------------------------------

-- Initial scan after a brief delay
task.spawn(function()
	task.wait(2)
	refreshSynergyVisuals()
end)

-- Refresh when units are added/removed
CollectionService:GetInstanceAddedSignal(BRAINROT_TAG):Connect(function()
	task.wait(0.5) -- Wait for attributes
	refreshSynergyVisuals()
end)

CollectionService:GetInstanceRemovedSignal(BRAINROT_TAG):Connect(function()
	task.wait(0.1)
	refreshSynergyVisuals()
end)

-- Refresh when mode changes (synergy state may change)
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local ModeChangedEvent = RemoteEvents:WaitForChild("ModeChanged")

ModeChangedEvent.OnClientEvent:Connect(function()
	task.wait(0.1)
	refreshSynergyVisuals()
end)
