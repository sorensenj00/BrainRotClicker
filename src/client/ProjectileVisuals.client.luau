--[[
	ProjectileVisuals Client Script
	
	Handles visual projectile effects for brainrot units.
	Units "throw" projectiles at their island's Storage container every income cycle.
	
	This is purely visual - the server handles actual money logic.
	Inspired by The Gnorp Apologue.
	
	Features:
	- CollectionService detection for "ActiveBrainrot" tagged units
	- Per-unit coroutine loops based on CycleTime
	- Bezier curve projectile arcs
	- Storage impact effects (squash animation + particles)
	- Multi-island support
]]

-- Services
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Get player
local LocalPlayer = Players.LocalPlayer

-- Configuration
local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopConfig"))

-- Tags
local BRAINROT_TAG = "ActiveBrainrot"

-- ============================================================================
-- PROJECTILE CONFIGURATION
-- Change these values to customize projectile behavior
-- ============================================================================
local PROJECTILE_CONFIG = {
	-- Projectile flight settings
	FLIGHT_TIME = 0.5,              -- Seconds to reach Storage (LOWER = FASTER)
	ARC_HEIGHT = 8,                 -- Studs above midpoint for arc peak
	STEPS = 30,                     -- Number of bezier curve samples (smoothness)
	
	-- Projectile appearance
	SIZE = Vector3.new(0.8, 0.8, 0.8),
	MATERIAL = Enum.Material.Neon,
	SHAPE = Enum.PartType.Ball,
	DEFAULT_COLOR = Color3.fromRGB(255, 255, 255), -- White fallback
	TRANSPARENCY = 0,
	
	-- Impact effects
	SQUASH_SCALE = 1.15,            -- Storage scales up by 15%
	SQUASH_DURATION = 0.1,          -- Seconds for squash animation
	PARTICLE_COUNT = 8,             -- Number of particles on impact
	PARTICLE_LIFETIME = 0.5,        -- Seconds particles last
	PARTICLE_SPEED = 15,            -- Particle velocity
	
	-- Performance
	MAX_PROJECTILES = 100,          -- Max concurrent projectiles (prevents lag)
}

-- Track active projectiles for performance limiting
local activeProjectileCount = 0

-- Track unit loops (to clean up when units are removed)
local unitLoops: {[Instance]: thread} = {}

-- Cache true original sizes for storage parts to prevent size drift
local storageOriginalSizes: {[BasePart]: Vector3} = {}

-- ============================================================================
-- MATH HELPER: BEZIER CURVE
-- ============================================================================

--[[
	Samples a point on a quadratic Bezier curve.
	Creates a natural arc from start to end with a peak in the middle.
	
	@param startPos Vector3 - Starting position (unit)
	@param endPos Vector3 - Ending position (storage)
	@param height number - Peak height of the arc above midpoint
	@param t number - Parameter from 0 to 1 (0 = start, 1 = end)
	@return Vector3 - The interpolated position on the curve
]]
local function sampleBezier(startPos: Vector3, endPos: Vector3, height: number, t: number): Vector3
	-- Control point is at the midpoint, elevated by height
	local midPoint = (startPos + endPos) / 2 + Vector3.new(0, height, 0)
	
	-- Quadratic Bezier: B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
	-- Simplified using nested lerps for readability:
	local p0 = startPos:Lerp(midPoint, t)
	local p1 = midPoint:Lerp(endPos, t)
	return p0:Lerp(p1, t)
end

--[[
	Calculates dynamic arc height based on distance and elevation.
	For brainrots on higher-tier islands, this creates a high-arcing trajectory
	that rises above intermediate islands before landing in the storage.
	
	@param startPos Vector3 - Starting position (brainrot unit)
	@param endPos Vector3 - Ending position (storage tank)
	@return number - The calculated arc height above the midpoint
]]
local function calculateDynamicArcHeight(startPos: Vector3, endPos: Vector3): number
	-- Calculate horizontal distance (ignoring Y)
	local horizontalDistance = (Vector3.new(endPos.X, 0, endPos.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude
	
	-- Calculate elevation difference (positive if brainrot is higher than storage)
	local elevationDiff = startPos.Y - endPos.Y
	
	-- Base arc height scales with horizontal distance
	-- A projectile traveling 100 studs should arc ~25 studs high
	local distanceBasedArc = horizontalDistance * 0.25
	
	-- If brainrot is higher than storage, add extra height to create a nice lob
	-- The projectile should go UP first, then come DOWN gracefully to the storage
	local elevationBoost = math.max(0, elevationDiff * 0.5)
	
	-- Use the configured minimum as the floor
	return math.max(PROJECTILE_CONFIG.ARC_HEIGHT, distanceBasedArc + elevationBoost)
end

-- ============================================================================
-- STORAGE FINDER
-- ============================================================================

--[[
	Finds the Storage part for a given brainrot unit.
	Supports multi-island by looking at the unit's parent hierarchy.
	
	@param brainrot Instance - The brainrot unit
	@return BasePart? - The Storage part, or nil if not found
]]
local function findStorageForUnit(brainrot: Instance): BasePart?
	-- Get the unit's TierIndex to find the correct island's storage
	local _tierIndex = brainrot:GetAttribute("TierIndex")
	
	-- Walk up to find the plot/island model
	local parent = brainrot.Parent
	while parent and parent.Name ~= "Brainrots" do
		parent = parent.Parent
	end
	
	-- Go up one more level to get the plot/island
	if parent then
		local plot = parent.Parent
		if plot then
			local storage = plot:FindFirstChild("Storage")
			if storage then
				if storage:IsA("BasePart") then
					return storage
				elseif storage:IsA("Model") then
					return storage.PrimaryPart or storage:FindFirstChildWhichIsA("BasePart", true)
				end
			end
		end
	end
	
	-- Fallback: search all plots for player's storage
	local ownerId = brainrot:GetAttribute("OwnerId")
	if not ownerId then return nil end
	
	local plotsFolder = workspace:FindFirstChild("Plots")
	if plotsFolder then
		for _, plot in plotsFolder:GetChildren() do
			local plotOwnerId = plot:GetAttribute("OwnerId")
			if plotOwnerId == ownerId then
				local storage = plot:FindFirstChild("Storage")
				if storage then
					if storage:IsA("BasePart") then
						return storage
					elseif storage:IsA("Model") then
						return storage.PrimaryPart or storage:FindFirstChildWhichIsA("BasePart", true)
					end
				end
			end
		end
	end
	
	return nil
end

-- ============================================================================
-- UNIT POSITION HELPER
-- ============================================================================

--[[
	Gets the position of a brainrot unit.
	Handles both Model and Part-based units.
	
	@param brainrot Instance - The brainrot unit
	@return Vector3? - The position, or nil if not found
]]
local function getUnitPosition(brainrot: Instance): Vector3?
	if brainrot:IsA("Model") then
		if brainrot.PrimaryPart then
			return brainrot.PrimaryPart.Position
		else
			-- Try to get bounding box center
			local success, cf = pcall(function()
				return brainrot:GetPivot()
			end)
			if success then
				return cf.Position
			end
		end
	elseif brainrot:IsA("BasePart") then
		return brainrot.Position
	end
	return nil
end

-- ============================================================================
-- IMPACT EFFECTS
-- ============================================================================

--[[
	Plays a squash animation on the storage part.
	Scales up briefly then returns to normal.
	Uses cached original size to prevent compounding growth.
	
	@param storage BasePart - The storage part to animate
]]
local function playSquashAnimation(storage: BasePart)
	-- Cache the true original size on first impact (prevents size drift)
	if not storageOriginalSizes[storage] then
		storageOriginalSizes[storage] = storage.Size
	end
	
	local originalSize = storageOriginalSizes[storage]
	local squashedSize = originalSize * PROJECTILE_CONFIG.SQUASH_SCALE
	
	-- Scale up
	local squashTween = TweenService:Create(
		storage,
		TweenInfo.new(PROJECTILE_CONFIG.SQUASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = squashedSize}
	)
	
	-- Scale back down to the CACHED original size (not current size)
	local returnTween = TweenService:Create(
		storage,
		TweenInfo.new(PROJECTILE_CONFIG.SQUASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Size = originalSize}
	)
	
	squashTween:Play()
	squashTween.Completed:Wait()
	returnTween:Play()
end

--[[
	Spawns impact particles at the collision point.
	
	@param position Vector3 - Where to spawn particles
	@param color Color3 - Color of the particles
]]
local function spawnImpactParticles(position: Vector3, color: Color3)
	-- Create a temporary part for the particle emitter
	local particlePart = Instance.new("Part")
	particlePart.Size = Vector3.new(0.1, 0.1, 0.1)
	particlePart.Position = position
	particlePart.Anchored = true
	particlePart.CanCollide = false
	particlePart.Transparency = 1
	particlePart.Parent = workspace
	
	-- Create particle emitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0)
	})
	emitter.Lifetime = NumberRange.new(PROJECTILE_CONFIG.PARTICLE_LIFETIME * 0.5, PROJECTILE_CONFIG.PARTICLE_LIFETIME)
	emitter.Speed = NumberRange.new(PROJECTILE_CONFIG.PARTICLE_SPEED * 0.5, PROJECTILE_CONFIG.PARTICLE_SPEED)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Acceleration = Vector3.new(0, -30, 0) -- Gravity
	emitter.Rate = 0 -- We'll use Emit() instead
	emitter.Parent = particlePart
	
	-- Burst particles
	emitter:Emit(PROJECTILE_CONFIG.PARTICLE_COUNT)
	
	-- Clean up after particles fade
	task.delay(PROJECTILE_CONFIG.PARTICLE_LIFETIME + 0.1, function()
		particlePart:Destroy()
	end)
end

-- ============================================================================
-- PROJECTILE CREATION AND ANIMATION
-- ============================================================================

--[[
	Creates and animates a projectile from a unit to its storage.
	
	@param startPos Vector3 - Starting position (unit)
	@param endPos Vector3 - Ending position (storage)
	@param color Color3 - Projectile color
	@param storage BasePart - The storage part (for impact effects)
]]
local function fireProjectile(startPos: Vector3, endPos: Vector3, color: Color3, storage: BasePart)
	-- Performance check
	if activeProjectileCount >= PROJECTILE_CONFIG.MAX_PROJECTILES then
		return
	end
	
	-- Calculate dynamic arc height based on distance and elevation
	local arcHeight = calculateDynamicArcHeight(startPos, endPos)
	
	activeProjectileCount = activeProjectileCount + 1
	
	-- Create the projectile part
	local projectile = Instance.new("Part")
	projectile.Name = "IncomeProjectile"
	projectile.Size = PROJECTILE_CONFIG.SIZE
	projectile.Shape = PROJECTILE_CONFIG.SHAPE
	projectile.Material = PROJECTILE_CONFIG.MATERIAL
	projectile.Color = color
	projectile.Transparency = PROJECTILE_CONFIG.TRANSPARENCY
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CastShadow = false
	projectile.Position = startPos
	projectile.Parent = workspace
	
	-- Add a subtle glow effect
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Range = 3
	pointLight.Brightness = 0.5
	pointLight.Parent = projectile
	
	-- Animate along bezier curve
	local stepTime = PROJECTILE_CONFIG.FLIGHT_TIME / PROJECTILE_CONFIG.STEPS
	
	task.spawn(function()
		for i = 1, PROJECTILE_CONFIG.STEPS do
			local t = i / PROJECTILE_CONFIG.STEPS
			local newPos = sampleBezier(startPos, endPos, arcHeight, t)
			
			-- Use TweenService for smooth interpolation between steps
			local tween = TweenService:Create(
				projectile,
				TweenInfo.new(stepTime, Enum.EasingStyle.Linear),
				{Position = newPos}
			)
			tween:Play()
			tween.Completed:Wait()
		end
		
		-- Projectile reached storage - play impact effects
		task.spawn(function()
			playSquashAnimation(storage)
		end)
		spawnImpactParticles(endPos, color)
		
		-- Cleanup
		projectile:Destroy()
		activeProjectileCount = activeProjectileCount - 1
	end)
end

-- ============================================================================
-- UNIT LOOP MANAGEMENT
-- ============================================================================

--[[
	Gets the unit type name from a brainrot instance.
	The unit type is stored in the UnitType attribute or derived from name.
	
	@param brainrot Instance - The brainrot unit
	@return string - The unit type name
]]
local function getUnitTypeName(brainrot: Instance): string
	-- Check for UnitType attribute first
	local unitType = brainrot:GetAttribute("UnitType")
	if unitType then
		return unitType
	end
	
	-- Parse from name (format: "UnitName_UserId_Timestamp")
	local name = brainrot.Name
	local underscorePos = name:find("_[%d]+_[%d]+$")
	if underscorePos then
		return name:sub(1, underscorePos - 1)
	end
	
	return name
end

--[[
	Starts the projectile loop for a brainrot unit.
	Fires projectiles at the unit's CycleTime interval.
	
	@param brainrot Instance - The brainrot unit
]]
local function startUnitLoop(brainrot: Instance)
	-- Only process units owned by local player
	local ownerId = brainrot:GetAttribute("OwnerId")
	if not ownerId or ownerId ~= LocalPlayer.UserId then
		return
	end
	
	-- Don't start if already running
	if unitLoops[brainrot] then
		return
	end
	
	-- Get unit configuration
	local unitTypeName = getUnitTypeName(brainrot)
	local unitConfig = ShopConfig.Units[unitTypeName]
	
	-- Default values if config not found
	local cycleTime = brainrot:GetAttribute("IncomeInterval") or (unitConfig and unitConfig.CycleTime) or 3
	local projectileColor = (unitConfig and unitConfig.ProjectileColor) or PROJECTILE_CONFIG.DEFAULT_COLOR
	
	-- Start the loop
	local loopThread = task.spawn(function()
		-- Small initial delay to stagger projectiles from units spawned together
		task.wait(math.random() * 0.5)
		
		while brainrot and brainrot.Parent do
			-- Wait for cycle time
			task.wait(cycleTime)
			
			-- Get current positions
			local startPos = getUnitPosition(brainrot)
			local storage = findStorageForUnit(brainrot)
			
			if startPos and storage then
				local endPos = storage.Position
				fireProjectile(startPos, endPos, projectileColor, storage)
			end
		end
	end)
	
	unitLoops[brainrot] = loopThread
end

--[[
	Stops the projectile loop for a brainrot unit.
	
	@param brainrot Instance - The brainrot unit
]]
local function stopUnitLoop(brainrot: Instance)
	local loopThread = unitLoops[brainrot]
	if loopThread then
		task.cancel(loopThread)
		unitLoops[brainrot] = nil
	end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local function initialize()
	print("═══════════════════════════════════════════")
	print("   ProjectileVisuals - Initializing")
	print("═══════════════════════════════════════════")
	
	-- Handle existing brainrots
	for _, brainrot in CollectionService:GetTagged(BRAINROT_TAG) do
		task.spawn(startUnitLoop, brainrot)
	end
	
	-- Handle new brainrots added
	CollectionService:GetInstanceAddedSignal(BRAINROT_TAG):Connect(function(brainrot)
		task.spawn(startUnitLoop, brainrot)
	end)
	
	-- Handle brainrots removed
	CollectionService:GetInstanceRemovedSignal(BRAINROT_TAG):Connect(function(brainrot)
		stopUnitLoop(brainrot)
	end)
	
	print("✓ ProjectileVisuals initialized")
	print(string.format("  - Flight Time: %.2fs (change FLIGHT_TIME to adjust speed)", PROJECTILE_CONFIG.FLIGHT_TIME))
	print(string.format("  - Arc Height: %d studs", PROJECTILE_CONFIG.ARC_HEIGHT))
	print("═══════════════════════════════════════════")
end

-- Start the system
initialize()
