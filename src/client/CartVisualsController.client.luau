--[[
	CartVisualsController Client Script
	
	Handles smooth interpolation of cart positions based on server attributes.
	Triggers client-side visual item funneling into the black hole.
]]

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local CART_TAG = "PhysicalCartHUD"

-- Keep track of state listeners to avoid duplicate funnel animations
local CartListeners = {}

local HOLE_POSITION = Vector3.new(0, 32, 0)

--------------------------------------------------------------------------------
-- FUNNEL ANIMATION
--------------------------------------------------------------------------------

local function spawnFunnelVisuals(cartModel)
	local primary = cartModel.PrimaryPart
	if not primary then return end
	
	local startCF = primary.CFrame
	
	-- Spawn 10-15 random shiny boxes
	local itemsToSpawn = math.random(10, 15)
	
	for i = 1, itemsToSpawn do
		task.delay(math.random() * 1.5, function()
			-- Create item visual block
			local part = Instance.new("Part")
			part.Size = Vector3.new(1.8, 1.8, 1.8)
			part.Color = Color3.fromRGB(math.random(100,255), math.random(100,255), math.random(100,255))
			part.Material = Enum.Material.Neon
			part.Anchored = true
			part.CanCollide = false
            
            -- Random offset from cart
			local offset = Vector3.new(math.random(-3,3), math.random(2,5), math.random(-3,3))
			part.CFrame = startCF * CFrame.new(offset)
			part.Parent = workspace
			
			-- Arc tween out of the cart into the black hole
			local t = 0
			local duration = 0.8 + (math.random() * 0.4)
			local startPos = part.Position
            local controlPos = startPos:Lerp(HOLE_POSITION, 0.5) + Vector3.new(0, math.random(15, 25), 0)
            
			local rotationSpeed = Vector3.new(math.random(-10,10), math.random(-10,10), math.random(-10,10))
            
			local conn
			conn = RunService.Heartbeat:Connect(function(dt)
				t += dt / duration
				if t >= 1 then
					part:Destroy()
					conn:Disconnect()
				else
                    -- Bezier curve interpolation
					local l1 = startPos:Lerp(controlPos, t)
					local l2 = controlPos:Lerp(HOLE_POSITION, t)
					part.Position = l1:Lerp(l2, t)
                    
                    -- Scale down as it gets sucked in
					part.Size = Vector3.new(1.8, 1.8, 1.8) * (1 - (t * 0.9))
                    
                    -- Spin
                    part.CFrame = part.CFrame * CFrame.Angles(rotationSpeed.X * dt, rotationSpeed.Y * dt, rotationSpeed.Z * dt)
				end
			end)
		end)
	end
end

--------------------------------------------------------------------------------
-- CART TWEENING
--------------------------------------------------------------------------------

local function setupCart(cartModel)
	if CartListeners[cartModel] then return end
    
	local conn = cartModel:GetAttributeChangedSignal("CartState"):Connect(function()
		local state = cartModel:GetAttribute("CartState")
		
		-- Trigger visuals only for the local player's cart (or we could do it for everyone)
        -- Let's trigger funnel animation for everyone to make the world feel alive
		if state == "at_market" then
			spawnFunnelVisuals(cartModel)
		end
	end)
	
	CartListeners[cartModel] = conn
end

-- Cleanup disconnected carts
CollectionService:GetInstanceRemovedSignal(CART_TAG):Connect(function(cartModel)
	if CartListeners[cartModel] then
		CartListeners[cartModel]:Disconnect()
		CartListeners[cartModel] = nil
	end
end)

-- Initialize existing carts
for _, cart in CollectionService:GetTagged(CART_TAG) do
	setupCart(cart)
end

-- New carts
CollectionService:GetInstanceAddedSignal(CART_TAG):Connect(setupCart)

-- Loop to interpolate positions
RunService.Heartbeat:Connect(function()
    local now = workspace:GetServerTimeNow()
    
	for _, model in CollectionService:GetTagged(CART_TAG) do
		local state = model:GetAttribute("CartState")
        if not state then continue end
        
        local startPos = model:GetAttribute("CartStartPos")
        local endPos = model:GetAttribute("CartEndPos")
        local duration = model:GetAttribute("CartDuration") or 0
        local startTime = model:GetAttribute("CartStartTime") or 0
        
        if not startPos or not endPos then continue end
        
        local targetCFrame
        local dir = (endPos - startPos).Unit
        
        -- Use a safe LookAt to prevent NaN when pos == lookPos
        if state == "idle" then
            targetCFrame = CFrame.new(startPos, startPos + dir)
        elseif state == "at_market" or state == "selling" then
             targetCFrame = CFrame.new(endPos, endPos + dir)
        elseif state == "rolling_to_market" then
            if duration <= 0 then
                targetCFrame = CFrame.new(endPos, endPos + dir)
            else
                local alpha = math.clamp((now - startTime) / duration, 0, 1)
                -- Ease InOutQuad for smoother start and stop
                local easedAlpha = alpha < 0.5 and 2 * alpha * alpha or 1 - math.pow(-2 * alpha + 2, 2) / 2
                
                local currentPos = startPos:Lerp(endPos, easedAlpha)
                
                -- Always face the movement direction
                targetCFrame = CFrame.new(currentPos, currentPos + dir)
            end
        elseif state == "rolling_to_plot" then
            if duration <= 0 then
                targetCFrame = CFrame.new(startPos, startPos - dir)
            else
                local alpha = math.clamp((now - startTime) / duration, 0, 1)
                local easedAlpha = alpha < 0.5 and 2 * alpha * alpha or 1 - math.pow(-2 * alpha + 2, 2) / 2
                
                local currentPos = endPos:Lerp(startPos, easedAlpha)
                
                -- Face the opposite direction
                targetCFrame = CFrame.new(currentPos, currentPos - dir)
            end
        end
        
        if targetCFrame and model.PrimaryPart then
            model:PivotTo(targetCFrame)
        end
	end
end)

print("✓ CartVisualsController Initialized")
