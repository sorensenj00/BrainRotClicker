--[[
	NetWorthStatueManager Server Module

	- Calculates per-player NetWorth (Money + Storage + Cart value)
	- Updates leaderstats.NetWorth every 2 seconds
	- Shows the top player's avatar as a large gold statue on MainIsland
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NetWorthStatueManager = {}
local Services = {}

local CONFIG = {
	UPDATE_INTERVAL = 20,
	FALLBACK_CENTER = Vector3.new(0, 32, 0),
	FALLBACK_Y_OFFSET = 0,
	PEDESTAL_SIZE = Vector3.new(10, 2, 10),
	PEDESTAL_LIFT = 2,
	STATUE_SCALE = 3,
	RAYCAST_HEIGHT = 300,
	RAYCAST_DEPTH = 1200,
	STATUE_VERSION = 4,
	COIN_EMITTER_TEXTURE = "rbxassetid://1281285222",
}

local currentLeaderUserId = nil

local function getMarketManager()
	return rawget(Services, "MarketManager")
end

local function getDataService()
	return rawget(Services, "DataService")
end

local function getItemStorageManager()
	return rawget(Services, "ItemStorageManager")
end

local function getCartManager()
	return rawget(Services, "CartManager")
end

local function ensureNetWorthStat(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return nil end

	local netWorth = leaderstats:FindFirstChild("NetWorth")
	if not netWorth then
		netWorth = Instance.new("IntValue")
		netWorth.Name = "NetWorth"
		netWorth.Value = 0
		netWorth.Parent = leaderstats
	end

	return netWorth
end

local function resolveBasePosition()
	local mainIsland = workspace:FindFirstChild("MainIsland")
	if mainIsland then
		local anchor = mainIsland:FindFirstChild("StatueAnchor", true)
		if anchor then
			if anchor:IsA("BasePart") then
				return anchor.Position
			end
			if anchor:IsA("Model") then
				return anchor:GetPivot().Position
			end
		end

		for _, desc in ipairs(mainIsland:GetDescendants()) do
			if desc:IsA("BasePart") then
				local lower = string.lower(desc.Name)
				if string.find(lower, "hole", 1, true)
					or string.find(lower, "void", 1, true)
					or string.find(lower, "singularity", 1, true)
					or string.find(lower, "black", 1, true)
				then
					return desc.Position
				end
			end
		end

		local islandPart = mainIsland:FindFirstChild("Island")
		if islandPart and islandPart:IsA("BasePart") then
			return islandPart.Position
		end
	end

	return CONFIG.FALLBACK_CENTER + Vector3.new(0, CONFIG.FALLBACK_Y_OFFSET, 0)
end

local function getAnchorCFrame(ignoreInstance)
	local basePos = resolveBasePosition()
	local rayOrigin = basePos + Vector3.new(0, CONFIG.RAYCAST_HEIGHT, 0)
	local rayDir = Vector3.new(0, -CONFIG.RAYCAST_DEPTH, 0)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	if ignoreInstance then
		rayParams.FilterDescendantsInstances = {ignoreInstance}
	else
		rayParams.FilterDescendantsInstances = {}
	end
	rayParams.IgnoreWater = true

	local result = workspace:Raycast(rayOrigin, rayDir, rayParams)
	local groundY = basePos.Y
	if result then
		groundY = result.Position.Y
	end

	local centerY = groundY + (CONFIG.PEDESTAL_SIZE.Y / 2) + CONFIG.PEDESTAL_LIFT
	return CFrame.new(basePos.X, centerY, basePos.Z)
end

local function ensureStatueContainer()
	local mainIsland = workspace:WaitForChild("MainIsland", 30)
	if not mainIsland then
		return nil, nil
	end

	local container = mainIsland:FindFirstChild("NetWorthStatue")
	if not container then
		container = Instance.new("Model")
		container.Name = "NetWorthStatue"
		container.Parent = mainIsland
	end

	local pedestal = container:FindFirstChild("Pedestal")
	if not pedestal then
		pedestal = Instance.new("Part")
		pedestal.Name = "Pedestal"
		pedestal.Anchored = true
		pedestal.CanCollide = true
		pedestal.Material = Enum.Material.Glass
		pedestal.Color = Color3.fromRGB(15, 15, 15)
		pedestal.Size = CONFIG.PEDESTAL_SIZE
		pedestal.Parent = container

		for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right}) do
			local surfaceGui = Instance.new("SurfaceGui")
			surfaceGui.Name = "NeonGraph_" .. face.Name
			surfaceGui.Face = face
			surfaceGui.LightInfluence = 0
			surfaceGui.Parent = pedestal

			local img = Instance.new("ImageLabel")
			img.Name = "GraphImage"
			img.Size = UDim2.new(1, 0, 1, 0)
			img.BackgroundTransparency = 1
			img.Image = "rbxassetid://7093288282"
			img.Parent = surfaceGui
		end
	end

	local pedestalCF = getAnchorCFrame(container)
	pedestal.CFrame = pedestalCF

	return container, pedestal
end

local function computeInventoryValue(items, marketManager)
	if type(items) ~= "table" then
		return 0
	end

	local total = 0
	for itemId, count in pairs(items) do
		if type(count) == "number" and count > 0 then
			local unitValue = marketManager.GetItemPrice(itemId)
			total += (unitValue * count)
		end
	end
	return total
end

local function computeNetWorth(player)
	local dataService = getDataService()
	local marketManager = getMarketManager()
	local itemStorageManager = getItemStorageManager()
	local cartManager = getCartManager()
	if not (dataService and marketManager and itemStorageManager and cartManager) then
		return 0
	end

	local money = dataService.GetMoney(player) or 0
	local storageItems = itemStorageManager.GetStorageContents(player) or {}
	local cartData = cartManager.GetCartState(player)
	local cartItems = (cartData and cartData.Inventory) or {}

	local storageValue = computeInventoryValue(storageItems, marketManager)
	local cartValue = computeInventoryValue(cartItems, marketManager)

	return math.floor(money + storageValue + cartValue)
end

local function formatWorth(netWorth)
	return tostring(math.floor(netWorth or 0)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function updateStatueBillboard(avatarModel, displayName, netWorth)
	local bg = avatarModel and avatarModel:FindFirstChild("NetWorthTag")
	if not bg then
		return
	end

	local frameImage = bg:FindFirstChild("GoldFrame")
	if not frameImage then
		return
	end

	local titleLabel = frameImage:FindFirstChild("TitleLabel")
	local nameLabel = frameImage:FindFirstChild("NameLabel")
	local valueLabel = frameImage:FindFirstChild("ValueLabel")

	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = "Island Tycoon Champion"
	end
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = displayName or "Unknown Champion"
	end
	if valueLabel and valueLabel:IsA("TextLabel") then
		valueLabel.Text = "$" .. formatWorth(netWorth)
	end
end

local function buildAvatarStatue(player, pedestal, container, netWorth)
	local userId = player.UserId
    local ok, avatarModel = pcall(function()
        return Players:CreateHumanoidModelFromUserId(userId)
    end)
    if not ok or not avatarModel then
        return nil
    end

    avatarModel.Name = "AvatarStatue"
    avatarModel:SetAttribute("StatueVersion", CONFIG.STATUE_VERSION)
    avatarModel.Parent = container
    task.wait()

    pcall(function()
        avatarModel:ScaleTo(CONFIG.STATUE_SCALE)
    end)

    local hrp = avatarModel:WaitForChild("HumanoidRootPart", 3)
    local humanoid = avatarModel:WaitForChild("Humanoid", 3)

    for _, desc in ipairs(avatarModel:GetDescendants()) do
        if desc:IsA("Script") or desc:IsA("LocalScript") then
            desc:Destroy()
        elseif desc:IsA("BasePart") then
            if desc.Name == "HumanoidRootPart" then
                desc.Anchored = true
            else
                desc.Anchored = false
            end
            desc.CanCollide = false
        elseif desc:IsA("Humanoid") then
            desc.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            desc.AutoRotate = false
        end
    end

    -- 1. PLACERING (Fikset så den ignorerer store hatte/vinger)
    if hrp and humanoid then
        -- Udregn den præcise afstand fra centrum af hoften og ned til underkanten af foden
        local rootToFloor = (hrp.Size.Y / 2) + humanoid.HipHeight
        local topOfPedestal = pedestal.Position.Y + (pedestal.Size.Y / 2)

		local minJusteringY = 10 -- Sæt til f.eks. -0.5 for at sænke ham lidt, eller 1 for at løfte ham.
        
        local targetPosition = Vector3.new(pedestal.Position.X, topOfPedestal + rootToFloor + minJusteringY, pedestal.Position.Z)
        avatarModel:PivotTo(CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(180), 0))
    end

    -- 2. TEKST OVER HOVEDET (BillboardGui)
    if hrp then
        local bg = Instance.new("BillboardGui")
        bg.Name = "NetWorthTag"
        bg.Size = UDim2.new(0, 230, 0, 86)
        bg.StudsOffset = Vector3.new(0, 4 * CONFIG.STATUE_SCALE, 0) -- Højden over hovedet
        bg.AlwaysOnTop = true
        bg.Adornee = hrp
        bg.Parent = avatarModel

        local frameImage = Instance.new("ImageLabel")
        frameImage.Name = "GoldFrame"
        frameImage.Size = UDim2.new(1, 0, 1, 0)
        frameImage.BackgroundTransparency = 1
        frameImage.Image = "rbxassetid://2845688941"
        frameImage.Parent = bg

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Name = "TitleLabel"
        titleLabel.Size = UDim2.new(1, -20, 0, 20)
        titleLabel.Position = UDim2.new(0, 10, 0, 8)
        titleLabel.BackgroundTransparency = 1
        titleLabel.Font = Enum.Font.GothamBold
        titleLabel.TextColor3 = Color3.fromRGB(255, 239, 170)
        titleLabel.TextSize = 14
        titleLabel.TextStrokeTransparency = 0.4
        titleLabel.Text = "Island Tycoon Champion"
        titleLabel.Parent = frameImage

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NameLabel"
        nameLabel.Size = UDim2.new(1, -20, 0, 28)
        nameLabel.Position = UDim2.new(0, 10, 0, 26)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBlack
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextScaled = true
        nameLabel.TextStrokeTransparency = 0.2
        nameLabel.Text = player.DisplayName
        nameLabel.Parent = frameImage

        local valueLabel = Instance.new("TextLabel")
        valueLabel.Name = "ValueLabel"
        valueLabel.Size = UDim2.new(1, -20, 0, 24)
        valueLabel.Position = UDim2.new(0, 10, 1, -28)
        valueLabel.BackgroundTransparency = 1
        valueLabel.Font = Enum.Font.GothamBold
        valueLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
        valueLabel.TextSize = 18
        valueLabel.TextStrokeTransparency = 0.3
        valueLabel.Text = "$" .. formatWorth(netWorth)
        valueLabel.Parent = frameImage
    end

    -- 3. ROTATION (Gør at figuren drejer rundt om sig selv)
    if hrp then
        task.spawn(function()
            local rotSpeed = math.rad(30) -- Bestemmer hvor hurtigt den drejer (30 grader i sekundet)
            while avatarModel.Parent do
                local dt = RunService.Heartbeat:Wait()
                if hrp.Parent then
                    hrp.CFrame = hrp.CFrame * CFrame.Angles(0, rotSpeed * dt, 0)
                else
                    break
                end
            end
        end)
    end

    -- 4. DANS
    if humanoid then
        local animator = humanoid:FindFirstChild("Animator")
        if not animator then
            animator = Instance.new("Animator")
            animator.Parent = humanoid
        end
        local animation = Instance.new("Animation")
        animation.AnimationId = "rbxassetid://507771019" 
        local danceTrack = animator:LoadAnimation(animation)
        danceTrack.Looped = true
        danceTrack:Play()
    end

    return avatarModel
end

local function refreshLeaderAndStatue()
    local container, pedestal = ensureStatueContainer()
    if not container or not pedestal then
        return
    end

    -- Hold piedestalen justeret, hvis ankeret flytter sig.
    pedestal.CFrame = getAnchorCFrame(container)

    local leader = nil
    local leaderWorth = -1

    for _, player in ipairs(Players:GetPlayers()) do
        local worth = computeNetWorth(player)
        local stat = ensureNetWorthStat(player)
        if stat then
            stat.Value = worth
        end

        if (worth > leaderWorth) or (worth == leaderWorth and leader and player.UserId < leader.UserId) or (worth == leaderWorth and not leader) then
            leader = player
            leaderWorth = worth
        end
    end

    if not leader then
        return
    end

    local currentAvatar = container:FindFirstChild("AvatarStatue")
    local isCurrentValid = currentAvatar and (currentAvatar:GetAttribute("StatueVersion") == CONFIG.STATUE_VERSION)
    if currentLeaderUserId == leader.UserId and isCurrentValid then
        updateStatueBillboard(currentAvatar, leader.DisplayName, leaderWorth)
        return
    end

    local newAvatar = buildAvatarStatue(leader, pedestal, container, leaderWorth)
    if not newAvatar then
        return
    end

    -- Find og slet den gamle avatar statue
    -- Da den nye allerede er lagt ind i containeren af buildAvatarStatue, 
    -- sikrer vi os, at vi ikke sletter den nye ved et uheld.
    for _, child in ipairs(container:GetChildren()) do
        if child.Name == "AvatarStatue" and child ~= newAvatar then
            child:Destroy()
        end
    end
    
    newAvatar.Name = "AvatarStatue"
    currentLeaderUserId = leader.UserId
end

function NetWorthStatueManager.Init(services)
	print("   NetWorthStatueManager (Module) - Initializing")
	Services = services or {}

	task.spawn(function()
		local mainIsland = workspace:WaitForChild("MainIsland", 30)
		if mainIsland then
			local blackHole = mainIsland:FindFirstChild("black hole")
			if blackHole then
				local emitter = blackHole:FindFirstChild("CoinEmitter")
				if not emitter then
					emitter = Instance.new("ParticleEmitter")
					emitter.Name = "CoinEmitter"
					emitter.Texture = "rbxassetid://1281285222"
					emitter.Speed = NumberRange.new(15, 25)
					emitter.Acceleration = Vector3.new(0, -20, 0)
					emitter.RotSpeed = NumberRange.new(-180, 180)
					emitter.Parent = blackHole
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			refreshLeaderAndStatue()
			task.wait(CONFIG.UPDATE_INTERVAL)
		end
	end)

	print("✓ NetWorthStatueManager Initialized")
end

return NetWorthStatueManager
