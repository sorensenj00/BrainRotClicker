--[[
	ViewportPreview Module
	
	Creates spinning or static 3D previews of models inside ViewportFrames.
	Used for inventory UI to show brainrot models instead of static images.
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

local function getModelBounds(model: Model): (CFrame, Vector3)
	local cf, size = model:GetBoundingBox()
	return cf, size
end

local function positionCamera(camera: Camera, model: Model, size: Vector3)
	local cf, _ = getModelBounds(model)
	
	local maxDimension = math.max(size.X, size.Y, size.Z)
	local fovRad = math.rad(CONFIG.CAMERA_FOV / 2)
	local distance = (maxDimension / 2) / math.tan(fovRad) * 1.5
	
	local cameraOffset = Vector3.new(distance * 0.6, distance * 0.6, distance * 0.6)
	
	local targetPos = cf.Position + Vector3.new(0, size.Y * 0.1, 0)
	
	camera.CFrame = CFrame.new(cf.Position + cameraOffset, targetPos)
	camera.FieldOfView = CONFIG.CAMERA_FOV
end

-- Core Setup Logic (Shared between modes)
local function setupViewport(model: Model, parent: GuiObject, size: UDim2?): (ViewportFrame, Model, Camera)
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
	
	local previewModel = model:Clone()
	previewModel.Parent = viewport
	
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	previewModel.Parent = worldModel
	
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	
	local _, modelSize = getModelBounds(previewModel)
	positionCamera(camera, previewModel, modelSize)

	return viewport, previewModel, camera
end

--[[
	Creates a new ViewportPreview with spinning enabled.
]]
function ViewportPreview.Create(model: Model, parent: GuiObject, size: UDim2?): any
	local self = setmetatable({}, ViewportPreview)
	
	local viewport, previewModel, camera = setupViewport(model, parent, size)
	
	self.viewport = viewport
	self.model = previewModel
	self.worldModel = viewport:FindFirstChildOfClass("WorldModel")
	self.camera = camera
	self.modelCenter, _ = getModelBounds(previewModel)
	self.rotation = 0
	self.spinConnection = nil
	
	self:StartSpin()
	
	return self
end

--[[
	Creates a static ViewportPreview (no spinning or object creation, just returns the frame).
]]
function ViewportPreview.CreateStatic(model: Model, parent: GuiObject, size: UDim2?): ViewportFrame
	local viewport, _model, _camera = setupViewport(model, parent, size)
	return viewport
end

--[[
	Creates a static ViewportPreview with a fully colored silhouette effect.
]]
function ViewportPreview.CreateSilhouette(model: Model, parent: GuiObject, size: UDim2?, color: Color3?): ViewportFrame
	local viewport, previewModel, _camera = setupViewport(model, parent, size)
	
	local targetColor = color or Color3.fromRGB(0, 0, 0)
	
	for _, desc in ipairs(previewModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Color = targetColor
			desc.Material = Enum.Material.Neon
			-- Remove any decals or textures
			for _, child in ipairs(desc:GetChildren()) do
				if child:IsA("Texture") or child:IsA("Decal") then
					child:Destroy()
				end
			end
		end
	end
	
	return viewport
end


function ViewportPreview:StartSpin()
	if self.spinConnection then return end
	
	self.spinConnection = RunService.Heartbeat:Connect(function(dt)
		if not self.model or not self.model.Parent then
			self:Destroy()
			return
		end
		
		if self.model.PrimaryPart then
			self.model.PrimaryPart.CFrame *= CFrame.Angles(0, dt * CONFIG.SPIN_SPEED, 0)
		end
	end)
end

function ViewportPreview:StopSpin()
	if self.spinConnection then
		self.spinConnection:Disconnect()
		self.spinConnection = nil
	end
end

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
