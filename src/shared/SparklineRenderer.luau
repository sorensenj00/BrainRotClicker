--[[
	SparklineRenderer Module
	
	Lightweight EditableImage-based sparkline graphs for HUD elements.
	Renders a single colored line on a canvas (default 256x80).
	
	Usage:
		local spark = SparklineRenderer.new(parentFrame, Vector2.new(256, 80))
		spark:Update({1.0, 1.05, 0.98, 1.12, ...})
		spark:Destroy()
]]

local AssetService = game:GetService("AssetService")

local SparklineRenderer = {}
SparklineRenderer.__index = SparklineRenderer

function SparklineRenderer.new(parentFrame: Frame, resolution: Vector2?)
	local self = setmetatable({}, SparklineRenderer)
	
	local res = resolution or Vector2.new(256, 80)
	
	-- Create EditableImage
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({
			Size = res,
		})
	end)
	
	if not ok or not img then
		warn("SparklineRenderer: Failed to create EditableImage:", img)
		self.disabled = true
		return self
	end
	
	self.image = img
	self.width = res.X
	self.height = res.Y
	self.disabled = false
	
	-- Create ImageLabel to display it
	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "Sparkline"
	imageLabel.BackgroundTransparency = 1
	imageLabel.Size = UDim2.fromScale(1, 1)
	imageLabel.ScaleType = Enum.ScaleType.Fit
	imageLabel.ResampleMode = Enum.ResamplerMode.Pixelated
	imageLabel.ImageContent = Content.fromObject(img)
	imageLabel.Parent = parentFrame
	
	self.imageLabel = imageLabel
	
	return self
end

function SparklineRenderer:Update(dataHistory: {number}, upColor: Color3?, downColor: Color3?)
	if self.disabled or not self.image then return end
	if not dataHistory or #dataHistory < 2 then return end
	
	local img = self.image
	local w = self.width
	local h = self.height
	
	local bullColor = upColor or Color3.fromRGB(0, 255, 136)
	local bearColor = downColor or Color3.fromRGB(255, 51, 51)
	
	-- Clear canvas (transparent black)
	img:DrawRectangle(
		Vector2.new(0, 0),
		Vector2.new(w, h),
		Color3.new(0, 0, 0),
		1, -- fully transparent
		Enum.ImageCombineType.Overwrite
	)
	
	-- Find min/max for scaling
	local minVal, maxVal = math.huge, -math.huge
	for _, v in ipairs(dataHistory) do
		if v < minVal then minVal = v end
		if v > maxVal then maxVal = v end
	end
	
	-- Add padding so line doesn't touch edges
	local range = math.max(maxVal - minVal, 0.01)
	local padded = range * 1.2
	local base = minVal - (padded - range) / 2
	
	-- Determine trend color
	local startPrice = dataHistory[1]
	local endPrice = dataHistory[#dataHistory]
	local color = (endPrice >= startPrice) and bullColor or bearColor
	local glowColor = color
	
	-- Convert data points to pixel coordinates
	local points = {}
	local count = #dataHistory
	for i, val in ipairs(dataHistory) do
		-- Use w-1 and h-1 bounds for pixel coordinates
		local x = ((i - 1) / (count - 1)) * (w - 4) + 2
		local y = h - 2 - ((val - base) / padded) * (h - 4)
		y = math.clamp(y, 1, h - 2)
		table.insert(points, Vector2.new(x, y))
	end
	
	-- Draw glow (thicker, semi-transparent)
	for i = 1, #points - 1 do
		img:DrawLine(points[i], points[i + 1], glowColor, 0.6, Enum.ImageCombineType.AlphaBlend)
	end
	
	-- Draw main line
	for i = 1, #points - 1 do
		img:DrawLine(points[i], points[i + 1], color, 0, Enum.ImageCombineType.AlphaBlend)
	end
	
	-- Draw end dot (current price)
	local lastPt = points[#points]
	if lastPt then
		img:DrawCircle(lastPt, 3, color, 0.3, Enum.ImageCombineType.AlphaBlend)
		img:DrawCircle(lastPt, 2, color, 0, Enum.ImageCombineType.AlphaBlend)
	end
end

function SparklineRenderer:Destroy()
	if self.imageLabel then
		self.imageLabel:Destroy()
		self.imageLabel = nil
	end
	if self.image then
		self.image:Destroy()
		self.image = nil
	end
end

return SparklineRenderer
