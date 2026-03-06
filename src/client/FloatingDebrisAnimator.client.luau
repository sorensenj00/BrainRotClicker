--[[
	FloatingDebrisAnimator (Client)

	Finds all parts tagged "FloatingDebris" via CollectionService and animates
	them with:
	  • Slow orbit around the island centre (the Root part of the plot model)
	  • Gentle vertical wobble (sine wave)
	  • Slow tumbling rotation for a magical feel

	Each debris part stores its own randomised parameters as Attributes set by
	TerrainGenerator on the server.
]]

local RunService     = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local TAG = "FloatingDebris"

--------------------------------------------------------------------------------
-- Per-debris runtime data
--------------------------------------------------------------------------------
type DebrisData = {
	part: BasePart,
	centerX: number,
	centerZ: number,
	startAngle: number,
	radius: number,
	height: number,
	orbitSpeed: number,
	wobbleSpeed: number,
	wobbleAmount: number,
	tumbleX: number,
	tumbleY: number,
	tumbleZ: number,
	baseRotation: CFrame,
}

local activeDebris: { DebrisData } = {}
local partToIndex: { [BasePart]: number } = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getPlotCenter(part: BasePart): (number, number, number)
	-- Walk up to the plot model and find the MagicCore for the orbit centre
	local model = part.Parent and part.Parent.Parent -- VisualDetails -> PlotModel
	local visuals = part.Parent -- VisualDetails folder
	local core = visuals and visuals:FindFirstChild("MagicCore")
	if core and core:IsA("BasePart") then
		return core.Position.X, core.Position.Z, core.Position.Y
	end
	-- Fallback to Root if MagicCore not found
	if model and model:FindFirstChild("Root") then
		local root = model.Root :: BasePart
		return root.Position.X, root.Position.Z, root.Position.Y
	end
	return 0, 0, 0
end

local function registerDebris(part: BasePart)
	if partToIndex[part] then return end -- already tracked

	local cx, cz, cy = getPlotCenter(part)

	local data: DebrisData = {
		part         = part,
		centerX      = cx,
		centerZ      = cz,
		startAngle   = part:GetAttribute("OrbitAngle")   or 0,
		radius       = part:GetAttribute("OrbitRadius")  or 60,
		height       = cy,
		orbitSpeed   = part:GetAttribute("OrbitSpeed")   or 0.08,
		wobbleSpeed  = part:GetAttribute("WobbleSpeed")  or 1.5,
		wobbleAmount = part:GetAttribute("WobbleAmount") or 1.0,
		tumbleX      = part:GetAttribute("TumbleX")      or 0.2,
		tumbleY      = part:GetAttribute("TumbleY")      or 0.1,
		tumbleZ      = part:GetAttribute("TumbleZ")      or 0.15,
		baseRotation = (part.CFrame - part.Position),     -- keep initial random tilt
	}

	table.insert(activeDebris, data)
	partToIndex[part] = #activeDebris
end

local function unregisterDebris(part: BasePart)
	local idx = partToIndex[part]
	if not idx then return end

	-- Swap-remove for O(1)
	local last = #activeDebris
	if idx ~= last then
		activeDebris[idx] = activeDebris[last]
		partToIndex[activeDebris[idx].part] = idx
	end
	activeDebris[last] = nil
	partToIndex[part]  = nil
end

--------------------------------------------------------------------------------
-- Bootstrap existing + future debris
--------------------------------------------------------------------------------
for _, part in CollectionService:GetTagged(TAG) do
	if part:IsA("BasePart") then
		registerDebris(part)
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst)
	if inst:IsA("BasePart") then
		registerDebris(inst)
	end
end)

CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
	if inst:IsA("BasePart") then
		unregisterDebris(inst)
	end
end)

--------------------------------------------------------------------------------
-- Animation loop
--------------------------------------------------------------------------------
RunService.Heartbeat:Connect(function()
	local t = time()

	for _, data in activeDebris do
		-- Orbit position
		local angle = data.startAngle + t * data.orbitSpeed
		local x = data.centerX + math.cos(angle) * data.radius
		local z = data.centerZ + math.sin(angle) * data.radius

		-- Vertical wobble
		local y = data.height + math.sin(t * data.wobbleSpeed) * data.wobbleAmount

		-- Tumbling rotation layered onto the original random tilt
		local tumble = CFrame.Angles(
			t * data.tumbleX,
			t * data.tumbleY,
			t * data.tumbleZ
		)

		data.part.CFrame = CFrame.new(x, y, z) * data.baseRotation * tumble
	end
end)
