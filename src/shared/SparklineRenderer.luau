--[[
	SparklineRenderer Module (Refactored)
	
	Ultra-performant, hardware-accelerated Sparkline graphs using 
	the "Pill-Frame" technique and strict Object Pooling.
	No EditableImage or pixel rasterization required.
]]

local SparklineRenderer = {}
SparklineRenderer.__index = SparklineRenderer

function SparklineRenderer.new(parentFrame: Frame, resolution: Vector2?)
	local self = setmetatable({}, SparklineRenderer)
	
	local res = resolution or Vector2.new(256, 80)
	self.width = res.X
	self.height = res.Y
	self.disabled = false
	
	-- Create a container for the vector frames
	local container = Instance.new("Frame")
	container.Name = "SparklineContainer"
	container.BackgroundTransparency = 1
	container.Size = UDim2.fromScale(1, 1)
	container.Parent = parentFrame
	
	self.container = container
	
	-- Object Pools to prevent Garbage Collection stutters
	self.linePool = {}
	self.dotPool = {}
	
	return self
end

function SparklineRenderer:Update(dataHistory: {number}, upColor: Color3?, downColor: Color3?)
	if self.disabled or not self.container then return end
	if not dataHistory or #dataHistory < 2 then return end
	
	local bullColor = upColor or Color3.fromRGB(0, 255, 136)
	local bearColor = downColor or Color3.fromRGB(255, 51, 51)
	
	-- Find min/max for scaling
	local minVal, maxVal = math.huge, -math.huge
	for _, v in ipairs(dataHistory) do
		if v < minVal then minVal = v end
		if v > maxVal then maxVal = v end
	end
	
	local range = math.max(maxVal - minVal, 0.01)
	local padded = range * 1.2
	local base = minVal - (padded - range) / 2
	
	-- Determine trend color
	local startPrice = dataHistory[1]
	local endPrice = dataHistory[#dataHistory]
	local color = (endPrice >= startPrice) and bullColor or bearColor
	
	-- Calculate points relative to internal dimensions
	local points = {}
	local count = #dataHistory
	for i, val in ipairs(dataHistory) do
		-- Scale points to fit exactly in the UI frame
		local x = ((i - 1) / (count - 1)) * self.container.AbsoluteSize.X
		local y = self.container.AbsoluteSize.Y - (((val - base) / padded) * self.container.AbsoluteSize.Y)
		table.insert(points, Vector2.new(x, y))
	end
	
	local activeLines = 0
	
	-- Draw lines using the pool
	for i = 1, #points - 1 do
		activeLines += 1
		local p1 = points[i]
		local p2 = points[i + 1]
		
		local distance = (p2 - p1).Magnitude
		local center = (p1 + p2) / 2
		local rotation = math.deg(math.atan2(p2.Y - p1.Y, p2.X - p1.X))
		
		-- Fetch or create pooled line segment
		local segment = self.linePool[activeLines]
		if not segment then
			local glow = Instance.new("Frame")
			glow.BorderSizePixel = 0
			glow.AnchorPoint = Vector2.new(0.5, 0.5)
			Instance.new("UICorner", glow).CornerRadius = UDim.new(0.5, 0)
			glow.Parent = self.container
			
			local core = Instance.new("Frame")
			core.BorderSizePixel = 0
			core.AnchorPoint = Vector2.new(0.5, 0.5)
			Instance.new("UICorner", core).CornerRadius = UDim.new(0.5, 0)
			core.Parent = self.container
			
			segment = {glow = glow, core = core}
			self.linePool[activeLines] = segment
		end
		
		-- Update Glow Layer
		segment.glow.Visible = true
		segment.glow.BackgroundColor3 = color
		segment.glow.BackgroundTransparency = 0.6
		segment.glow.Position = UDim2.new(0, center.X, 0, center.Y)
		segment.glow.Size = UDim2.new(0, distance, 0, 6) -- Glow thickness
		segment.glow.Rotation = rotation
		segment.glow.ZIndex = 1
		
		-- Update Core Layer
		segment.core.Visible = true
		segment.core.BackgroundColor3 = color
		segment.core.BackgroundTransparency = 0
		segment.core.Position = UDim2.new(0, center.X, 0, center.Y)
		segment.core.Size = UDim2.new(0, distance, 0, 2) -- Core thickness
		segment.core.Rotation = rotation
		segment.core.ZIndex = 2
	end
	
	-- Hide unused lines in the pool
	for i = activeLines + 1, #self.linePool do
		self.linePool[i].glow.Visible = false
		self.linePool[i].core.Visible = false
	end
	
	-- Draw End Dot (Current Price)
	local dot = self.dotPool[1]
	if not dot then
		local glow = Instance.new("Frame")
		glow.BorderSizePixel = 0
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		Instance.new("UICorner", glow).CornerRadius = UDim.new(0.5, 0)
		glow.Parent = self.container
		
		local core = Instance.new("Frame")
		core.BorderSizePixel = 0
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		Instance.new("UICorner", core).CornerRadius = UDim.new(0.5, 0)
		core.Parent = self.container
		
		dot = {glow = glow, core = core}
		self.dotPool[1] = dot
	end
	
	local lastPt = points[#points]
	if lastPt then
		dot.glow.Visible = true
		dot.glow.BackgroundColor3 = color
		dot.glow.BackgroundTransparency = 0.5
		dot.glow.Position = UDim2.new(0, lastPt.X, 0, lastPt.Y)
		dot.glow.Size = UDim2.new(0, 10, 0, 10)
		dot.glow.ZIndex = 3
		
		dot.core.Visible = true
		dot.core.BackgroundColor3 = Color3.new(1, 1, 1)
		dot.core.BackgroundTransparency = 0
		dot.core.Position = UDim2.new(0, lastPt.X, 0, lastPt.Y)
		dot.core.Size = UDim2.new(0, 4, 0, 4)
		dot.core.ZIndex = 4
	else
		dot.glow.Visible = false
		dot.core.Visible = false
	end
end

function SparklineRenderer:Destroy()
	if self.container then
		self.container:Destroy()
		self.container = nil
	end
	self.linePool = nil
	self.dotPool = nil
end

return SparklineRenderer