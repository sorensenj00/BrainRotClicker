--[[
	ViewportPreview Module
	
	Creates spinning 3D previews of models inside ViewportFrames.
	Used for inventory UI to show brainrot models instead of static images.
	
	Usage:
		local ViewportPreview = require(path.to.ViewportPreview)
		local preview = ViewportPreview.Create(model, parentFrame)
		-- Later:
		preview:Destroy()
]]

local RunService = game:GetService("RunService")

local ViewportPreview = {}
ViewportPreview.__index = ViewportPreview

-- Configuration
local CONFIG = {
	SPIN_SPEED = 30, -- degrees per second
	CAMERA_FOV = 50,
	DEFAULT_SIZE = UDim2.new(1, 0, 1, 0),
	BACKGROUND_COLOR = Color3.fromRGB(30, 25, 40),
	BACKGROUND_TRANSPARENCY = 0.5,
}

--[[
	Calculates the bounding box of a model.
	@param model Model - The model to measure
	@return CFrame, Vector3 - The center CFrame and size
]]
local function getModelBounds(model: Model): (CFrame, Vector3)
	local cf, size = model:GetBoundingBox()
	return cf, size
end

--[[
	Positions the camera to fit the model in view.
	@param camera Camera - The viewport camera
	@param model Model - The model to frame
	@param size Vector3 - The bounding box size
]]
local function positionCamera(camera: Camera, model: Model, size: Vector3)
	local cf, _ = getModelBounds(model)
	
	-- Calculate distance based on model size
	local maxDimension = math.max(size.X, size.Y, size.Z)
	local fovRad = math.rad(CONFIG.CAMERA_FOV / 2)
	local distance = (maxDimension / 2) / math.tan(fovRad) * 1.5
	
	-- Position camera higher and looking down at model center
	local cameraOffset = Vector3.new(distance * 0.6, distance * 0.6, distance * 0.6)
	
	-- Look slightly higher than center to frame the head better
	local targetPos = cf.Position + Vector3.new(0, size.Y * 0.1, 0)
	
	camera.CFrame = CFrame.new(cf.Position + cameraOffset, targetPos)
	camera.FieldOfView = CONFIG.CAMERA_FOV
end

--[[
	Creates a new ViewportPreview.
	@param model Model - The model to preview (will be cloned)
	@param parent GuiObject - The parent UI element
	@param size UDim2? - Optional size override
	@return ViewportPreview
]]
function ViewportPreview.Create(model: Model, parent: GuiObject, size: UDim2?): any
	local self = setmetatable({}, ViewportPreview)
	
	-- Create ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ModelPreview"
	viewport.Size = size or CONFIG.DEFAULT_SIZE
	viewport.Position = UDim2.new(0, 0, 0, 0)
	viewport.BackgroundColor3 = CONFIG.BACKGROUND_COLOR
	viewport.BackgroundTransparency = CONFIG.BACKGROUND_TRANSPARENCY
	viewport.BorderSizePixel = 0
	viewport.Parent = parent
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = viewport
	
	-- Clone model for viewport
	local previewModel = model:Clone()
	previewModel.Parent = viewport
	
	-- Create WorldModel container (required for proper rendering)
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	previewModel.Parent = worldModel
	
	-- Create camera
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	
	-- Get model bounds and position camera
	local _, modelSize = getModelBounds(previewModel)
	positionCamera(camera, previewModel, modelSize)
	
	-- Store references
	self.viewport = viewport
	self.model = previewModel
	self.worldModel = worldModel
	self.camera = camera
	self.modelCenter, _ = getModelBounds(previewModel)
	self.rotation = 0
	self.spinConnection = nil
	
	-- Start spinning
	self:StartSpin()
	
	return self
end

--[[
	Starts the spin animation.
]]
function ViewportPreview:StartSpin()
	if self.spinConnection then return end
	
	self.spinConnection = RunService.RenderStepped:Connect(function(dt)
		if not self.model or not self.model.Parent then
			self:Destroy()
			return
		end
		
		-- Update rotation
		self.rotation = self.rotation + CONFIG.SPIN_SPEED * dt
		
		-- Rotate model around Y axis
		local centerCF = self.modelCenter
		local rotationCF = CFrame.Angles(0, math.rad(self.rotation), 0)
		self.model:PivotTo(CFrame.new(centerCF.Position) * rotationCF)
	end)
end

--[[
	Stops the spin animation.
]]
function ViewportPreview:StopSpin()
	if self.spinConnection then
		self.spinConnection:Disconnect()
		self.spinConnection = nil
	end
end

--[[
	Destroys the preview and cleans up.
]]
function ViewportPreview:Destroy()
	self:StopSpin()
	
	if self.viewport then
		self.viewport:Destroy()
		self.viewport = nil
	end
	
	self.model = nil
	self.worldModel = nil
	self.camera = nil
end

return ViewportPreview
