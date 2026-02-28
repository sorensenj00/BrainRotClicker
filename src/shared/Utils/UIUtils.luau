local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

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

function UIUtils.addStroke(inst: Instance, color: Color3?, thick: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(45, 45, 58)
	s.Thickness = thick or 1
	s.Transparency = 0.3
	s.Parent = inst
	return s
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
