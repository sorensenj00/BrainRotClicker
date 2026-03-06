local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlayerTransportConfig = require(Shared:WaitForChild("PlayerTransportConfig"))

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local GetCatalogRemote = RemoteFunctions:FindFirstChild("GetPlayerTransportCatalog") or Instance.new("RemoteFunction")
GetCatalogRemote.Name = "GetPlayerTransportCatalog"
GetCatalogRemote.Parent = RemoteFunctions

local PurchaseRemote = RemoteFunctions:FindFirstChild("PurchasePlayerTransport") or Instance.new("RemoteFunction")
PurchaseRemote.Name = "PurchasePlayerTransport"
PurchaseRemote.Parent = RemoteFunctions

local SpawnRemote = RemoteFunctions:FindFirstChild("SpawnPlayerTransport") or Instance.new("RemoteFunction")
SpawnRemote.Name = "SpawnPlayerTransport"
SpawnRemote.Parent = RemoteFunctions

local DespawnRemote = RemoteFunctions:FindFirstChild("DespawnPlayerTransport") or Instance.new("RemoteFunction")
DespawnRemote.Name = "DespawnPlayerTransport"
DespawnRemote.Parent = RemoteFunctions

local UpdatedEvent = RemoteEvents:FindFirstChild("PlayerTransportUpdated") or Instance.new("RemoteEvent")
UpdatedEvent.Name = "PlayerTransportUpdated"
UpdatedEvent.Parent = RemoteEvents

local SpawnedEvent = RemoteEvents:FindFirstChild("PlayerTransportSpawned") or Instance.new("RemoteEvent")
SpawnedEvent.Name = "PlayerTransportSpawned"
SpawnedEvent.Parent = RemoteEvents

local DespawnedEvent = RemoteEvents:FindFirstChild("PlayerTransportDespawned") or Instance.new("RemoteEvent")
DespawnedEvent.Name = "PlayerTransportDespawned"
DespawnedEvent.Parent = RemoteEvents

local COMPONENT_KEY = "PlayerTransport"

local PlayerTransportManager = {}
local Services = {}

type PlayerTransportState = {
	unlockedVehicles: {[string]: boolean},
	activeVehicleId: string?,
	activeVehicleModel: Model?,
	characterAddedConnection: RBXScriptConnection?,
	characterRemovingConnection: RBXScriptConnection?,
	humanoidDiedConnection: RBXScriptConnection?,
}

local PlayerStates: {[Player]: PlayerTransportState} = {}

local function getDefaultData()
	return {
		unlockedVehicles = {
			[PlayerTransportConfig.DEFAULT_TRANSPORT_ID] = true,
		},
		activeVehicleId = nil,
	}
end

local function cloneDefaultUnlockedVehicles()
	local unlocked = {}
	for _, transport in ipairs(PlayerTransportConfig.GetSortedTransports()) do
		if transport.unlockByDefault then
			unlocked[transport.id] = true
		end
	end
	return unlocked
end

local function getDataService()
	return rawget(Services, "DataService")
end

local function getMapSystem()
	return rawget(Services, "MapSystem")
end

local function getTransportTemplate(transportId: string): Model?
	local transport = PlayerTransportConfig.TRANSPORTS[transportId]
	if not transport then
		return nil
	end

	local models = ReplicatedStorage:FindFirstChild("Models")
	local playerTransportFolder = models and models:FindFirstChild("PlayerTransport")
	local template = playerTransportFolder and playerTransportFolder:FindFirstChild(transport.modelName)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

local function disconnectConnection(connection: RBXScriptConnection?)
	if connection then
		connection:Disconnect()
	end
end

local function ensureState(player: Player): PlayerTransportState
	local state = PlayerStates[player]
	if state then
		return state
	end

	state = {
		unlockedVehicles = cloneDefaultUnlockedVehicles(),
		activeVehicleId = nil,
		activeVehicleModel = nil,
		characterAddedConnection = nil,
		characterRemovingConnection = nil,
		humanoidDiedConnection = nil,
	}
	PlayerStates[player] = state
	return state
end

local function despawnActiveVehicle(player: Player)
	local state = PlayerStates[player]
	if not state then
		return
	end

	if state.activeVehicleModel then
		state.activeVehicleModel:Destroy()
		state.activeVehicleModel = nil
	end
	state.activeVehicleId = nil
end

local function getSpawnPart(player: Player): BasePart?
	local mapSystem = getMapSystem()
	if not mapSystem or not mapSystem.GetPlayerPlot then
		return nil
	end

	local plot = mapSystem.GetPlayerPlot(player)
	if not plot then
		return nil
	end

	local pad = plot:FindFirstChild("PlayerTransportPad", true)
	if not pad then
		return nil
	end

	local runtimeSpawn = pad:FindFirstChild("RuntimeSpawnMarker", true)
	if runtimeSpawn and runtimeSpawn:IsA("BasePart") then
		return runtimeSpawn
	end

	local spawnPart = pad:FindFirstChild("Spawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart
	end

	warn(string.format("PlayerTransportManager: Transport pad on %s is missing Spawn and RuntimeSpawnMarker", player.Name))
	return nil
end

local function getGroundedSpawnCFrame(spawnPart: BasePart, model: Model): CFrame
	local baseCFrame = spawnPart.CFrame
	local _, boundsSize = model:GetBoundingBox()
	local halfHeight = math.max(0.5, boundsSize.Y * 0.5)
	local castHeight = math.max(20, boundsSize.Y * 2)
	local castDepth = math.max(60, boundsSize.Y * 4)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { model }

	local origin = spawnPart.Position + Vector3.new(0, castHeight, 0)
	local direction = Vector3.new(0, -castDepth, 0)
	local rayResult = workspace:Raycast(origin, direction, rayParams)

	local surfaceY = spawnPart.Position.Y
	if rayResult then
		surfaceY = rayResult.Position.Y
	end

	local flatLook = Vector3.new(baseCFrame.LookVector.X, 0, baseCFrame.LookVector.Z)
	local finalPosition = Vector3.new(
		spawnPart.Position.X,
		surfaceY + halfHeight + 0.05,
		spawnPart.Position.Z
	)

	if flatLook.Magnitude < 0.001 then
		return CFrame.new(finalPosition)
	end

	return CFrame.lookAt(finalPosition, finalPosition + flatLook.Unit, Vector3.yAxis)
end

local function buildCatalog(player: Player)
	local state = ensureState(player)
	local vehicles = {}

	for _, transport in ipairs(PlayerTransportConfig.GetSortedTransports()) do
		table.insert(vehicles, {
			id = transport.id,
			displayName = transport.displayName,
			description = transport.description,
			price = transport.price,
			unlocked = state.unlockedVehicles[transport.id] == true,
			active = state.activeVehicleId == transport.id,
			available = getTransportTemplate(transport.id) ~= nil,
		})
	end

	return {
		vehicles = vehicles,
		activeVehicleId = state.activeVehicleId,
	}
end

local function pushCatalog(player: Player)
	UpdatedEvent:FireClient(player, buildCatalog(player))
end

local function attachHumanoidCleanup(player: Player, character: Model)
	local state = ensureState(player)
	disconnectConnection(state.humanoidDiedConnection)
	state.humanoidDiedConnection = nil

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid then
		state.humanoidDiedConnection = humanoid.Died:Connect(function()
			PlayerTransportManager.Despawn(player)
		end)
	end
end

local function bindCharacterHooks(player: Player)
	local state = ensureState(player)
	disconnectConnection(state.characterAddedConnection)
	disconnectConnection(state.characterRemovingConnection)
	disconnectConnection(state.humanoidDiedConnection)

	state.characterAddedConnection = player.CharacterAdded:Connect(function(character)
		attachHumanoidCleanup(player, character)
	end)

	state.characterRemovingConnection = player.CharacterRemoving:Connect(function()
		PlayerTransportManager.Despawn(player)
	end)

	if player.Character then
		task.defer(attachHumanoidCleanup, player, player.Character)
	end
end

local function sanitizeLoadedData(data)
	local unlockedVehicles = cloneDefaultUnlockedVehicles()
	if type(data) == "table" and type(data.unlockedVehicles) == "table" then
		for transportId, value in pairs(data.unlockedVehicles) do
			if PlayerTransportConfig.TRANSPORTS[transportId] then
				unlockedVehicles[transportId] = value == true
			end
		end
	end

	return {
		unlockedVehicles = unlockedVehicles,
		activeVehicleId = nil,
	}
end

function PlayerTransportManager.GetCatalog(player: Player)
	return buildCatalog(player)
end

function PlayerTransportManager.Purchase(player: Player, transportId: string)
	if type(transportId) ~= "string" then
		return false, "Invalid transport id", buildCatalog(player)
	end

	local transport = PlayerTransportConfig.TRANSPORTS[transportId]
	if not transport then
		return false, "Unknown transport", buildCatalog(player)
	end

	if not getTransportTemplate(transportId) then
		return false, "Transport model missing", buildCatalog(player)
	end

	local state = ensureState(player)
	if state.unlockedVehicles[transportId] then
		return false, "Already unlocked", buildCatalog(player)
	end

	if transport.unlockByDefault or transport.price <= 0 then
		state.unlockedVehicles[transportId] = true
		pushCatalog(player)
		return true, "Unlocked", buildCatalog(player)
	end

	local dataService = getDataService()
	if not dataService then
		return false, "Data unavailable", buildCatalog(player)
	end

	if not dataService.DeductMoney(player, transport.price) then
		return false, "Not enough cash", buildCatalog(player)
	end

	state.unlockedVehicles[transportId] = true
	pushCatalog(player)
	return true, "Purchase complete", buildCatalog(player)
end

function PlayerTransportManager.Spawn(player: Player, transportId: string)
	if type(transportId) ~= "string" then
		return false, "Invalid transport id", buildCatalog(player)
	end

	local transport = PlayerTransportConfig.TRANSPORTS[transportId]
	if not transport then
		return false, "Unknown transport", buildCatalog(player)
	end

	local state = ensureState(player)
	if not state.unlockedVehicles[transportId] then
		return false, "Transport locked", buildCatalog(player)
	end

	local template = getTransportTemplate(transportId)
	if not template then
		return false, "Transport model missing", buildCatalog(player)
	end

	local spawnPart = getSpawnPart(player)
	if not spawnPart then
		return false, "Transport pad spawn missing", buildCatalog(player)
	end

	despawnActiveVehicle(player)

	local clone = template:Clone()
	clone.Name = "PlayerTransport_" .. player.UserId
	clone:SetAttribute("OwnerId", player.UserId)
	clone:SetAttribute("TransportId", transportId)
	clone.Parent = workspace
	clone:PivotTo(getGroundedSpawnCFrame(spawnPart, clone))

	state.activeVehicleId = transportId
	state.activeVehicleModel = clone

	SpawnedEvent:FireClient(player, transportId)
	pushCatalog(player)
	return true, "Spawned", buildCatalog(player)
end

function PlayerTransportManager.Despawn(player: Player)
	local state = PlayerStates[player]
	if not state then
		return true, "No transport", buildCatalog(player)
	end

	local hadActiveTransport = state.activeVehicleModel ~= nil or state.activeVehicleId ~= nil
	despawnActiveVehicle(player)

	if hadActiveTransport then
		DespawnedEvent:FireClient(player)
		pushCatalog(player)
	end

	return true, "Despawned", buildCatalog(player)
end

function PlayerTransportManager.GetActiveVehicle(player: Player)
	local state = PlayerStates[player]
	return state and state.activeVehicleModel or nil
end

function PlayerTransportManager.Init(services)
	print("   PlayerTransportManager (Module) - Initializing")
	Services = services or {}

	local dataService = getDataService()
	if dataService then
		dataService.RegisterHandler(COMPONENT_KEY, {
			DefaultData = getDefaultData(),
			OnLoad = function(player, data)
				local loaded = sanitizeLoadedData(data)
				local state = ensureState(player)
				state.unlockedVehicles = loaded.unlockedVehicles
				state.activeVehicleId = nil
				state.activeVehicleModel = nil
				task.defer(pushCatalog, player)
			end,
			OnSave = function(player, _data)
				local state = ensureState(player)
				return {
					unlockedVehicles = state.unlockedVehicles,
					activeVehicleId = nil,
				}
			end,
			OnRelease = function(player)
				local state = PlayerStates[player]
				if not state then
					return
				end
				despawnActiveVehicle(player)
				disconnectConnection(state.characterAddedConnection)
				disconnectConnection(state.characterRemovingConnection)
				disconnectConnection(state.humanoidDiedConnection)
				PlayerStates[player] = nil
			end,
		})
	end

	GetCatalogRemote.OnServerInvoke = function(player)
		return PlayerTransportManager.GetCatalog(player)
	end

	PurchaseRemote.OnServerInvoke = function(player, transportId)
		return PlayerTransportManager.Purchase(player, transportId)
	end

	SpawnRemote.OnServerInvoke = function(player, transportId)
		return PlayerTransportManager.Spawn(player, transportId)
	end

	DespawnRemote.OnServerInvoke = function(player)
		return PlayerTransportManager.Despawn(player)
	end

	Players.PlayerAdded:Connect(function(player)
		ensureState(player)
		bindCharacterHooks(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		PlayerTransportManager.Despawn(player)
		local state = PlayerStates[player]
		if not state then
			return
		end
		disconnectConnection(state.characterAddedConnection)
		disconnectConnection(state.characterRemovingConnection)
		disconnectConnection(state.humanoidDiedConnection)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		ensureState(player)
		bindCharacterHooks(player)
	end

	print("✓ PlayerTransportManager Initialized")
end

return PlayerTransportManager
