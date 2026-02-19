--[[
	BuildCameraController Client Module
	
	Responsibility: Managing Camera states (Isometric View vs Player View).
]]

local TweenService = game:GetService("TweenService")
local BuildCameraController = {}

local CONFIG = {
	CAMERA_HEIGHT = 60,
	CAMERA_ANGLE = 45,
	TWEEN_TIME = 0.5,
}

local camera = workspace.CurrentCamera
local savedCFrame = nil

function BuildCameraController.TweenToBuildMode(targetPos)
	savedCFrame = camera.CFrame
	
	local angleRad = math.rad(CONFIG.CAMERA_ANGLE)
	local distance = CONFIG.CAMERA_HEIGHT / math.sin(angleRad)
	
	local camPos = targetPos + Vector3.new(0, CONFIG.CAMERA_HEIGHT, distance * math.cos(angleRad))
	local targetCF = CFrame.new(camPos, targetPos)
	
	camera.CameraType = Enum.CameraType.Scriptable
	
	TweenService:Create(camera, TweenInfo.new(CONFIG.TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = targetCF
	}):Play()
end

function BuildCameraController.TweenToNormalMode()
	if not savedCFrame then return end
	
	local tween = TweenService:Create(camera, TweenInfo.new(CONFIG.TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = savedCFrame
	})
	tween:Play()
	
	tween.Completed:Connect(function()
		camera.CameraType = Enum.CameraType.Custom
		savedCFrame = nil
	end)
end

return BuildCameraController
