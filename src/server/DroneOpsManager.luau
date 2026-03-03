--[[
	DroneOpsManager Server Module

	Handles targeted drone buffs/nerfs:
	- EMP (target + sector)
	- BLOCKADE (target cart speed)
	- SCOUT (target storage snapshot)
	- OVERCLOCK (ally + sector)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local DroneOpsConfig = require(Shared:WaitForChild("DroneOpsConfig"))

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local DroneOpsNotifyEvent = RemoteEvents:FindFirstChild("DroneOpsNotify") or Instance.new("RemoteEvent")
DroneOpsNotifyEvent.Name = "DroneOpsNotify"
DroneOpsNotifyEvent.Parent = RemoteEvents

local DroneOpsCastFunction = RemoteFunctions:FindFirstChild("DroneOpsCastAbility") or Instance.new("RemoteFunction")
DroneOpsCastFunction.Name = "DroneOpsCastAbility"
DroneOpsCastFunction.Parent = RemoteFunctions

local DroneOpsCooldownsFunction = RemoteFunctions:FindFirstChild("DroneOpsGetCooldowns") or Instance.new("RemoteFunction")
DroneOpsCooldownsFunction.Name = "DroneOpsGetCooldowns"
DroneOpsCooldownsFunction.Parent = RemoteFunctions

local DroneOpsManager = {}
local Services = {}

local ActiveEmp = {} -- [targetUserId] = {[sector] = expiresAt}
local ActiveOverclock = {} -- [targetUserId] = {[sector] = expiresAt}
local ActiveOverclockFatigue = {} -- [targetUserId] = {[sector] = expiresAt}
local ActiveBlockade = {} -- [targetUserId] = expiresAt

local AbilityCooldowns = {} -- [senderUserId] = {[ability] = nextReadyAt}
local OffenseSharedCooldown = {} -- [senderUserId] = nextReadyAt
local TargetImmunity = {} -- [targetUserId] = {[abilityKey] = expiresAt}

local function now()
	return os.clock()
end

local function ensurePlayerMap(map, userId)
	if not map[userId] then
		map[userId] = {}
	end
	return map[userId]
end

local function isValidSector(sector)
	if type(sector) ~= "string" then return false end
	for _, s in ipairs(DroneOpsConfig.SECTORS) do
		if s == sector then
			return true
		end
	end
	return false
end

local function getPlayerByUserId(userId)
	if type(userId) ~= "number" then return nil end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == userId then
			return p
		end
	end
	return nil
end

local function getPlotPosition(player)
	if not player then return nil end
	local MapSystem = rawget(Services, "MapSystem")
	local plot = MapSystem and MapSystem.GetPlayerPlot and MapSystem.GetPlayerPlot(player)
	if plot and plot.Parent then
		return plot:GetPivot().Position
	end

	local plots = workspace:FindFirstChild("Plots")
	if plots then
		for _, candidate in ipairs(plots:GetChildren()) do
			if candidate:GetAttribute("OwnerId") == player.UserId then
				return candidate:GetPivot().Position
			end
		end
	end
	return nil
end

local function getDroneTemplate()
	local models = ReplicatedStorage:FindFirstChild("Models")
	return models and models:FindFirstChild("Drone")
end

local function fireNotify(player, message, typeKey, duration)
	if not player then return end
	DroneOpsNotifyEvent:FireClient(player, {
		message = message,
		type = typeKey or "info",
		duration = duration or 4,
	})
end

local function createImpactBurst(position)
	local part = Instance.new("Part")
	part.Name = "DroneImpactBurst"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Position = position
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(14, 25)
	emitter.Lifetime = NumberRange.new(0.4, 1.0)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(80, 200, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 180, 80)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 80, 80)),
	})
	emitter.Parent = part
	emitter:Emit(120)

	Debris:AddItem(part, DroneOpsConfig.DRONE.impactParticleLifetime)
end

local function launchDroneVisual(sender, target)
	local startPos = getPlotPosition(sender)
	local endPos = getPlotPosition(target)
	if not startPos or not endPos then return 0 end

	local template = getDroneTemplate()
	if not template then
		createImpactBurst(endPos + Vector3.new(0, DroneOpsConfig.DRONE.spawnHeight, 0))
		return 0
	end

	local drone = template:Clone()
	local startPoint = startPos + Vector3.new(0, DroneOpsConfig.DRONE.spawnHeight, 0)
	local endPoint = endPos + Vector3.new(0, DroneOpsConfig.DRONE.spawnHeight, 0)

	local movePart
	if drone:IsA("Model") then
		movePart = drone.PrimaryPart or drone:FindFirstChildWhichIsA("BasePart", true)
		if not movePart then
			drone:Destroy()
			createImpactBurst(endPoint)
			return 0
		end
		drone:PivotTo(CFrame.new(startPoint, endPoint))
	else
		movePart = drone
		movePart.CFrame = CFrame.new(startPoint, endPoint)
	end

	movePart.Anchored = true
	movePart.CanCollide = false
	drone.Parent = workspace

	local distance = (endPoint - startPoint).Magnitude
	local speed = math.max(20, DroneOpsConfig.DRONE.speedStudsPerSecond)
	local duration = math.max(0.2, distance / speed)
	local tween = TweenService:Create(movePart, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(endPoint, endPoint + Vector3.new(0, 0, 1)),
	})
	tween:Play()
	tween.Completed:Connect(function()
		createImpactBurst(endPoint)
		drone:Destroy()
	end)

	return duration
end

local function countActiveSectorDebuffs(targetUserId)
	local active = 0
	local current = now()
	local bySector = ActiveEmp[targetUserId]
	if not bySector then return 0 end
	for _, expires in pairs(bySector) do
		if expires and expires > current then
			active += 1
		end
	end
	return active
end

local function hasTargetImmunity(targetUserId, key)
	local map = TargetImmunity[targetUserId]
	if not map then return false end
	local expiresAt = map[key]
	return expiresAt and expiresAt > now()
end

local function setTargetImmunity(targetUserId, key)
	local map = ensurePlayerMap(TargetImmunity, targetUserId)
	map[key] = now() + DroneOpsConfig.GUARDRAILS.targetImmunitySeconds
end

local function isAbilityReady(senderUserId, ability)
	local abilityCfg = DroneOpsConfig.ABILITIES[ability]
	if not abilityCfg then return false, "Unknown ability." end
	local current = now()
	local personal = AbilityCooldowns[senderUserId]
	local nextReady = personal and personal[ability]
	if nextReady and nextReady > current then
		return false, string.format("%s cooldown: %.0fs", ability, math.max(0, nextReady - current))
	end
	if abilityCfg.type == "offense" then
		local sharedReady = OffenseSharedCooldown[senderUserId]
		if sharedReady and sharedReady > current then
			return false, string.format("Offense shared cooldown: %.0fs", math.max(0, sharedReady - current))
		end
	end
	return true
end

local function setAbilityCooldown(senderUserId, ability)
	local cfg = DroneOpsConfig.ABILITIES[ability]
	if not cfg then return end
	local map = ensurePlayerMap(AbilityCooldowns, senderUserId)
	map[ability] = now() + cfg.cooldown
	if cfg.type == "offense" then
		OffenseSharedCooldown[senderUserId] = now() + DroneOpsConfig.GUARDRAILS.sharedOffenseCooldown
	end
end

local function getCooldownSnapshotForPlayer(userId)
	local out = {}
	local current = now()
	for ability, cfg in pairs(DroneOpsConfig.ABILITIES) do
		local remaining = 0
		local personal = AbilityCooldowns[userId]
		local nextReady = personal and personal[ability]
		if nextReady and nextReady > current then
			remaining = math.max(0, nextReady - current)
		end
		if cfg.type == "offense" then
			local sharedReady = OffenseSharedCooldown[userId]
			if sharedReady and sharedReady > current then
				local sharedRemaining = math.max(0, sharedReady - current)
				if sharedRemaining > remaining then
					remaining = sharedRemaining
				end
			end
		end
		out[ability] = remaining
	end
	return out
end

local function applyEmp(sender, target, sector)
	local cfg = DroneOpsConfig.ABILITIES.EMP
	local targetBySector = ensurePlayerMap(ActiveEmp, target.UserId)
	targetBySector[sector] = now() + cfg.duration
	setTargetImmunity(target.UserId, "EMP")
	setAbilityCooldown(sender.UserId, "EMP")

	local travelTime = launchDroneVisual(sender, target)
	fireNotify(sender, string.format("EMP sent to %s (%s).", target.Name, sector), "warning", 3.5)
	task.delay(travelTime, function()
		fireNotify(target, string.format("EMP hit your %s sector. Production reduced.", sector), "error", 4)
	end)

	task.delay(cfg.duration, function()
		local current = ActiveEmp[target.UserId]
		local expiry = current and current[sector]
		if expiry and expiry <= now() then
			fireNotify(target, string.format("EMP ended on your %s sector.", sector), "info", 3)
		end
	end)
end

local function applyBlockade(sender, target)
	local cfg = DroneOpsConfig.ABILITIES.BLOCKADE
	ActiveBlockade[target.UserId] = now() + cfg.duration
	setTargetImmunity(target.UserId, "BLOCKADE")
	setAbilityCooldown(sender.UserId, "BLOCKADE")

	local travelTime = launchDroneVisual(sender, target)
	fireNotify(sender, string.format("Logistics blockade sent to %s.", target.Name), "warning", 3.5)
	task.delay(travelTime, function()
		fireNotify(target, "Your cart speed was blocked by 75%.", "error", 4)
	end)

	task.delay(cfg.duration, function()
		local expiry = ActiveBlockade[target.UserId]
		if expiry and expiry <= now() then
			fireNotify(target, "Logistics blockade ended. Cart speed restored.", "info", 3)
		end
	end)
end

local function applyOverclock(sender, target, sector)
	local cfg = DroneOpsConfig.ABILITIES.OVERCLOCK
	local targetBySector = ensurePlayerMap(ActiveOverclock, target.UserId)
	targetBySector[sector] = now() + cfg.duration
	setAbilityCooldown(sender.UserId, "OVERCLOCK")

	local travelTime = launchDroneVisual(sender, target)
	fireNotify(sender, string.format("Overclock sent to %s (%s).", target.Name, sector), "success", 3.5)
	task.delay(travelTime, function()
		fireNotify(target, string.format("Overclock boosted your %s sector.", sector), "success", 4)
	end)

	task.delay(cfg.duration, function()
		local fatigueMap = ensurePlayerMap(ActiveOverclockFatigue, target.UserId)
		fatigueMap[sector] = now() + cfg.fatigueDuration
		fireNotify(target, string.format("Overclock ended on %s. Fatigue active briefly.", sector), "warning", 3.5)
	end)
end

local function getScoutSnapshot(target)
	local ISM = rawget(Services, "ItemStorageManager")
	local CM = rawget(Services, "CartManager")
	local storageItems = {}
	local cartItems = {}
	if ISM and ISM.GetStorageContents then
		for id, count in pairs(ISM.GetStorageContents(target) or {}) do
			storageItems[id] = count
		end
	end
	if CM and CM.GetCartState then
		local cart = CM.GetCartState(target)
		for id, count in pairs((cart and cart.Inventory) or {}) do
			cartItems[id] = count
		end
	end
	return {
		targetUserId = target.UserId,
		targetName = target.Name,
		timestamp = os.time(),
		storage = storageItems,
		cart = cartItems,
	}
end

local function castAbility(sender, payload)
	if type(payload) ~= "table" then
		return false, "Invalid payload."
	end

	local ability = string.upper(tostring(payload.ability or ""))
	local targetUserId = tonumber(payload.targetUserId)
	local sector = payload.sector
	local target = getPlayerByUserId(targetUserId)
	if not target then
		return false, "Target not found."
	end
	if target == sender then
		return false, "Cannot target yourself."
	end

	local ready, reason = isAbilityReady(sender.UserId, ability)
	if not ready then
		return false, reason
	end

	if ability == "EMP" then
		if not isValidSector(sector) then return false, "Invalid sector." end
		if hasTargetImmunity(target.UserId, "EMP") then
			return false, "Target has EMP immunity."
		end
		if countActiveSectorDebuffs(target.UserId) >= DroneOpsConfig.GUARDRAILS.maxTargetSectorDebuffs then
			return false, "Target already has max active sector debuffs."
		end
		applyEmp(sender, target, sector)
		return true, "EMP sent."
	elseif ability == "BLOCKADE" then
		if hasTargetImmunity(target.UserId, "BLOCKADE") then
			return false, "Target has blockade immunity."
		end
		applyBlockade(sender, target)
		return true, "Blockade sent."
	elseif ability == "SCOUT" then
		setAbilityCooldown(sender.UserId, "SCOUT")
		local snapshot = getScoutSnapshot(target)
		fireNotify(sender, string.format("Scout snapshot retrieved: %s", target.Name), "info", 3)
		return true, snapshot
	elseif ability == "OVERCLOCK" then
		if not isValidSector(sector) then return false, "Invalid sector." end
		applyOverclock(sender, target, sector)
		return true, "Overclock sent."
	end

	return false, "Unknown ability."
end

function DroneOpsManager.Init(services)
	print("   DroneOpsManager (Module) - Initializing")
	Services = services or {}

	DroneOpsCastFunction.OnServerInvoke = function(player, payload)
		return castAbility(player, payload)
	end
	DroneOpsCooldownsFunction.OnServerInvoke = function(player)
		return getCooldownSnapshotForPlayer(player.UserId)
	end

	Players.PlayerRemoving:Connect(function(player)
		AbilityCooldowns[player.UserId] = nil
		OffenseSharedCooldown[player.UserId] = nil
		TargetImmunity[player.UserId] = nil
		ActiveEmp[player.UserId] = nil
		ActiveOverclock[player.UserId] = nil
		ActiveOverclockFatigue[player.UserId] = nil
		ActiveBlockade[player.UserId] = nil
	end)

	print("✓ DroneOpsManager Initialized")
end

function DroneOpsManager.GetProductionIntervalMultiplier(player, itemId)
	if not player or not itemId then return 1 end

	local sector = ItemConfig.GetSectorByItemId and ItemConfig.GetSectorByItemId(itemId) or "Neutral"
	local userId = player.UserId
	local current = now()
	local intervalMultiplier = 1

	local empSectors = ActiveEmp[userId]
	if empSectors then
		local empExpiry = empSectors[sector]
		if empExpiry and empExpiry > current then
			local prodMult = DroneOpsConfig.ABILITIES.EMP.productionMultiplier or 1
			if prodMult > 0 then
				intervalMultiplier *= (1 / prodMult)
			end
		end
	end

	local overclockSectors = ActiveOverclock[userId]
	if overclockSectors then
		local overclockExpiry = overclockSectors[sector]
		if overclockExpiry and overclockExpiry > current then
			local prodMult = DroneOpsConfig.ABILITIES.OVERCLOCK.productionMultiplier or 1
			if prodMult > 0 then
				intervalMultiplier *= (1 / prodMult)
			end
		end
	end

	local fatigueSectors = ActiveOverclockFatigue[userId]
	if fatigueSectors then
		local fatigueExpiry = fatigueSectors[sector]
		if fatigueExpiry and fatigueExpiry > current then
			local fatigueMult = DroneOpsConfig.ABILITIES.OVERCLOCK.fatigueMultiplier or 1
			if fatigueMult > 0 then
				intervalMultiplier *= (1 / fatigueMult)
			end
		end
	end

	return math.clamp(intervalMultiplier, 0.25, 4)
end

function DroneOpsManager.GetCartSpeedMultiplier(player)
	if not player then return 1 end
	local expiry = ActiveBlockade[player.UserId]
	if expiry and expiry > now() then
		return DroneOpsConfig.ABILITIES.BLOCKADE.cartSpeedMultiplier or 0.25
	end
	return 1
end

return DroneOpsManager
