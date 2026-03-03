local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared:WaitForChild("UIConfig"))

local UIUtils = {}

function UIUtils.addCorner(inst: Instance, r: any): UICorner
	local c = Instance.new("UICorner")
	if typeof(r) == "UDim" then
		c.CornerRadius = r
	elseif type(r) == "number" then
		c.CornerRadius = UDim.new(0, r)
	else
		c.CornerRadius = UDim.new(0, 5)
	end
	c.Parent = inst
	return c
end

function UIUtils.addStroke(inst: Instance, color: Color3?, thick: number?, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(45, 45, 58)
	s.Thickness = thick or 1
	s.Transparency = transparency or 0.3
	s.Parent = inst
	return s
end

-- Shared Tween Animation Logic
function UIUtils.openShop(frame: GuiObject)
	frame.Position = UDim2.new(0.5, 0, 0.5, 50)
	frame.Size = UDim2.new(0, 0, 0, 0)
	frame.Visible = true
	
	TweenService:Create(frame, UIConfig.TWEEN_INFO.Open, {
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 800, 0, 600)
	}):Play()
end

function UIUtils.closeShop(frame: GuiObject)
	local tween = TweenService:Create(frame, UIConfig.TWEEN_INFO.Close, {
		Position = UDim2.new(0.5, 0, 0.5, 50),
		Size = UDim2.new(0, 0, 0, 0)
	})
	tween:Play()
	tween.Completed:Wait()
	frame.Visible = false
end

function UIUtils.decodeItems(encoded: any): any
	if type(encoded) ~= "table" then return encoded end
	
	local success, IC = pcall(function() 
		return require(Shared:WaitForChild("ItemConfig")) 
	end)
	
	if not success or not IC or not IC.SHORT_TO_ID then return encoded end
	
	local decoded = {}
	for k, count in pairs(encoded) do
		local shortId = tonumber(k)
		if shortId and IC.SHORT_TO_ID[shortId] then
			decoded[IC.SHORT_TO_ID[shortId]] = count
		else
			decoded[k] = count
		end
	end
	return decoded
end

return UIUtils
