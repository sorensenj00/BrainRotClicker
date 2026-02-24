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
        
        local wp1 = model:GetAttribute("CartWP1")
        local wp2 = model:GetAttribute("CartWP2")
        local wp3 = model:GetAttribute("CartWP3")
        local duration = model:GetAttribute("CartDuration") or 0
        local startTime = model:GetAttribute("CartStartTime") or 0
        
        if not wp1 or not wp2 or not wp3 then continue end
        
        local dist1 = (wp2 - wp1).Magnitude
        local dist2 = (wp3 - wp2).Magnitude
        local totalDist = dist1 + dist2
        local ratio1 = totalDist > 0 and (dist1 / totalDist) or 0.5
        
        local targetCFrame
        
        if state == "idle" then
            local dir = (wp2 - wp1).Unit
            targetCFrame = CFrame.new(wp1, wp1 + dir)
        elseif state == "at_market" or state == "selling" then
            local dir = (wp3 - wp2).Unit
            targetCFrame = CFrame.new(wp3, wp3 + dir)
        elseif state == "rolling_to_market" then
            if duration <= 0 then
                local dir = (wp3 - wp2).Unit
                targetCFrame = CFrame.new(wp3, wp3 + dir)
            else
                local alpha = math.clamp((now - startTime) / duration, 0, 1)
                -- Ease InOutQuad for smoother start and stop
                local easedAlpha = alpha < 0.5 and 2 * alpha * alpha or 1 - math.pow(-2 * alpha + 2, 2) / 2
                
                local currentPos
                local dir
                if easedAlpha <= ratio1 then
                    -- Segment 1: wp1 -> wp2
                    local segmentAlpha = easedAlpha / ratio1
                    currentPos = wp1:Lerp(wp2, segmentAlpha)
                    dir = (wp2 - wp1).Unit
                else
                    -- Segment 2: wp2 -> wp3
                    local segmentAlpha = (easedAlpha - ratio1) / (1 - ratio1)
                    currentPos = wp2:Lerp(wp3, segmentAlpha)
                    dir = (wp3 - wp2).Unit
                end
                
                -- Always face the movement direction
                targetCFrame = CFrame.new(currentPos, currentPos + dir)
            end
        elseif state == "rolling_to_plot" then
            if duration <= 0 then
                local dir = (wp2 - wp1).Unit
                targetCFrame = CFrame.new(wp1, wp1 - dir)
            else
                local alpha = math.clamp((now - startTime) / duration, 0, 1)
                local easedAlpha = alpha < 0.5 and 2 * alpha * alpha or 1 - math.pow(-2 * alpha + 2, 2) / 2
                
                -- Traveling in reverse: 0 alpha = WP3, 1 alpha = WP1
                -- Inverse ratio: Segment 1 (start to middle) is wp3 -> wp2
                local revRatio1 = 1 - ratio1
                
                local currentPos
                local dir
                if easedAlpha <= revRatio1 then
                    -- Segment 1 (reverse): wp3 -> wp2
                    local segmentAlpha = easedAlpha / revRatio1
                    currentPos = wp3:Lerp(wp2, segmentAlpha)
                    dir = (wp3 - wp2).Unit -- Positive direction (pointing towards plot if we negate)
                else
                    -- Segment 2 (reverse): wp2 -> wp1
                    local segmentAlpha = (easedAlpha - revRatio1) / ratio1
                    currentPos = wp2:Lerp(wp1, segmentAlpha)
                    dir = (wp2 - wp1).Unit
                end
                
                -- Face the opposite direction
                targetCFrame = CFrame.new(currentPos, currentPos - dir)
            end
        end
        
        if targetCFrame and model.PrimaryPart then
            -- Add drone bobbing effect
            local bobOffset = Vector3.new(0, math.sin(now * 3) * 1.5, 0)
            
            -- Add tilt effect based on state (only tilt when moving)
            local tiltCFrame = CFrame.identity
            if state == "rolling_to_market" or state == "rolling_to_plot" then
                -- Pitch forward slightly (-X rotation relative to facing direction)
                tiltCFrame = CFrame.Angles(math.rad(-15), 0, 0)
            end
            
            model:PivotTo(targetCFrame * tiltCFrame + bobOffset)
        end
	end
end)

print("✓ CartVisualsController Initialized")
