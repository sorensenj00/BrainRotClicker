local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RadioStations = require(Shared:WaitForChild("RadioStations"))

local RadioController = {}

local stations = RadioStations.GetAll()
local stateChanged = Instance.new("BindableEvent")

local playbackSound: Sound? = nil
local switchSound: Sound? = nil
local currentStationIndex = 1
local isOff = true
local isLoading = false
local statusMessage = "Radio Off"
local loadGeneration = 0

local function ensurePlaybackSound(): Sound
	if playbackSound and playbackSound.Parent then
		return playbackSound
	end

	local sound = Instance.new("Sound")
	sound.Name = "MoneyHUDRadio"
	sound.Looped = true
	sound.Volume = 0.4
	sound.RollOffMaxDistance = 0
	sound.Parent = SoundService
	playbackSound = sound
	return sound
end

local function ensureSwitchSound(): Sound?
	if switchSound and switchSound.Parent then
		return switchSound
	end

	local soundId = RadioStations.SWITCH_SFX_ID
	if type(soundId) ~= "string" or soundId == "" then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = "MoneyHUDRadioSwitch"
	sound.SoundId = soundId
	sound.Volume = 0.25
	sound.Parent = SoundService
	switchSound = sound
	return sound
end

local function getStation(index: number)
	return stations[math.clamp(index, 1, #stations)]
end

local function getLiveTimePosition(station)
	local length = tonumber(station.length) or 0
	if length <= 0 then
		return 0
	end

	local offset = tonumber(station.offset) or 0
	local now = workspace:GetServerTimeNow()
	return (now + offset) % length
end

local function getState()
	return {
		stationIndex = currentStationIndex,
		station = stations[currentStationIndex],
		isOff = isOff,
		isLoading = isLoading,
		statusMessage = statusMessage,
	}
end

local function fireChanged()
	stateChanged:Fire(getState())
end

local function playSwitchSfx()
	local sound = ensureSwitchSound()
	if not sound then
		return
	end

	sound.TimePosition = 0
	sound:Play()
end

local function stopPlayback()
	if playbackSound then
		playbackSound:Stop()
	end
end

local function preloadStationAudio()
	local assets = {}
	for _, station in ipairs(stations) do
		if type(station.soundId) == "string" and station.soundId ~= "" then
			table.insert(assets, station.soundId)
		end
	end

	if #assets == 0 then
		return
	end

	pcall(function()
		ContentProvider:PreloadAsync(assets)
	end)
end

function RadioController.GetStations()
	return stations
end

function RadioController.GetCurrentStation()
	return stations[currentStationIndex], currentStationIndex
end

function RadioController.GetState()
	return getState()
end

function RadioController.SetOff()
	loadGeneration += 1
	isOff = true
	isLoading = false
	statusMessage = "Radio Off"
	stopPlayback()
	fireChanged()
end

function RadioController.PlayStation(index: number)
	if #stations == 0 then
		return false, "No stations configured"
	end

	currentStationIndex = math.clamp(index, 1, #stations)
	local station = getStation(currentStationIndex)
	if not station then
		return false, "Unknown station"
	end

	loadGeneration += 1
	local generation = loadGeneration
	isOff = false
	isLoading = true
	statusMessage = "Tuning " .. station.displayName .. "..."
	fireChanged()
	playSwitchSfx()

	local sound = ensurePlaybackSound()
	sound:Stop()
	sound.SoundId = station.soundId
	sound.Volume = tonumber(station.volume) or 0.4

	if type(station.soundId) ~= "string" or station.soundId == "" then
		isLoading = false
		isOff = true
		statusMessage = station.displayName .. " has no SoundId yet"
		fireChanged()
		return false, "Station missing SoundId"
	end

	if not sound.IsLoaded then
		local ok = pcall(function()
			sound.Loaded:Wait()
		end)
		if not ok then
			isLoading = false
			isOff = true
			statusMessage = station.displayName .. " failed to load"
			fireChanged()
			return false, "Failed to load station audio"
		end
	end

	if generation ~= loadGeneration then
		return false, "Superseded"
	end

	local liveTime = getLiveTimePosition(station)
	pcall(function()
		sound.TimePosition = liveTime
	end)

	sound:Play()
	isLoading = false
	statusMessage = station.displayName
	fireChanged()
	return true
end

function RadioController.NextStation()
	if #stations == 0 then
		return false, "No stations configured"
	end

	local nextIndex = currentStationIndex + 1
	if nextIndex > #stations then
		nextIndex = 1
	end

	return RadioController.PlayStation(nextIndex)
end

function RadioController.PreviousStation()
	if #stations == 0 then
		return false, "No stations configured"
	end

	local previousIndex = currentStationIndex - 1
	if previousIndex < 1 then
		previousIndex = #stations
	end

	return RadioController.PlayStation(previousIndex)
end

RadioController.Changed = stateChanged.Event

task.spawn(preloadStationAudio)

return RadioController
