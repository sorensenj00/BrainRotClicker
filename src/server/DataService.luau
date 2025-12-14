--[[
	DataService.luau

	A SOLID, modular data manager powered by ProfileService.
	Handles player data persistence and allows other systems to register
	data handlers without tightly coupling with the persistence layer.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local ProfileService = require(script.Parent.ProfileService)

-- Types
type Profile = {
	Data: {[string]: any},
	Release: (self: Profile) -> (),
	ListenToRelease: (self: Profile, callback: () -> ()) -> (),
	IsActive: (self: Profile) -> boolean,
	Reconcile: (self: Profile) -> ()
}

type DataHandler = {
	-- Called when data is loaded. Use this to apply data to the player.
	OnLoad: (player: Player, data: any) -> (),
	-- Called before save (optional). Use this if you need to update the table before saving.
	-- Note: ProfileService auto-saves the 'Data' table, so if you keep that table up-to-date,
	-- you don't technically need this. But for legacy adapters, it's useful.
	OnSave: (player: Player, data: any) -> (),
	-- Default data for this component (if structure is partitioned)
	DefaultData: any?
}

local DataService = {}
local Profiles: {[Player]: Profile} = {}
local Handlers: {[string]: DataHandler} = {}

-- The store used for the new system
local DATA_VERSION = "BrainRotClickerData_v2"
local ProfileStore = ProfileService.GetProfileStore(
	DATA_VERSION,
	{
		-- Initial Template
		-- We use a flag to detect new profiles for migration
		__IsNew = true
	}
)

-- Legacy store for migration
local LegacyStore = DataStoreService:GetDataStore("BrainRotClickerData_v1")

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
	Registers a handler for a specific data component.
	Ideally, we would partition data like:
	Profile.Data = {
		Shop = {...},
		Inventory = {...}
	}
	And handlers would register for "Shop", "Inventory".

	However, to support the "Legacy" blob migration, we allow a "Root" handler
	that receives the entire data table.
]]
function DataService.RegisterHandler(key: string, handler: DataHandler)
	Handlers[key] = handler
end

--[[
	Gets the current data for a player.
]]
function DataService.GetData(player: Player)
	local profile = Profiles[player]
	if profile then
		return profile.Data
	end
	return nil
end

--------------------------------------------------------------------------------
-- MIGRATION LOGIC
--------------------------------------------------------------------------------

local function migrateLegacyData(player: Player, profile: Profile)
	print("DataService: Checking for legacy data to migrate...")

	local success, result = pcall(function()
		return LegacyStore:GetAsync("Player_" .. player.UserId)
	end)

	if success and result then
		print("DataService: Found legacy data, migrating...")

		-- Deep copy legacy data into profile data
		-- We assume the legacy data structure is compatible with what the game expects
		for k, v in pairs(result) do
			profile.Data[k] = v
		end

		-- Mark as migrated
		profile.Data.__IsNew = nil
		print("DataService: Migration successful.")
	elseif success then
		-- Success was true, but result was nil -> No legacy data existed. Safe to start fresh.
		print("DataService: No legacy data found, starting fresh.")
		profile.Data.__IsNew = nil
	else
		-- Success was false -> DataStore error.
		-- CRITICAL: Do NOT mark as migrated or new. Kick player to prevent data loss.
		warn("DataService: Failed to check legacy data (DataStore Error): " .. tostring(result))
		player:Kick("Data Load Error: Failed to retrieve legacy data. Please rejoin.")

		-- Return false to signal migration failure
		return false
	end
	return true
end

--------------------------------------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)

	if profile then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile:ListenToRelease(function()
			Profiles[player] = nil
			-- Kick player if profile is loaded on another server
			player:Kick("Profile released - Your data has been loaded on another server.")
		end)

		if player:IsDescendantOf(Players) then
			Profiles[player] = profile

			-- Migration Check
			local migrationSuccess = true
			if profile.Data.__IsNew then
				migrationSuccess = migrateLegacyData(player, profile)
			end

			if not migrationSuccess then
				profile:Release()
				return
			end

			-- Notify Handlers
			for key, handler in pairs(Handlers) do
				task.spawn(function()
					-- If key is "Root" or "Legacy", pass the whole table.
					-- Otherwise, pass profile.Data[key] (future proofing)
					local dataToPass = profile.Data

					if key == "Root" or key == "Legacy" then
						-- For Root/Legacy, if the profile is empty (no keys), apply defaults
						-- We check specifically for a critical key like 'money' to decide if it's empty
						if not next(profile.Data) and handler.DefaultData then
							print("DataService: Applying default data for new player...")
							for k, v in pairs(handler.DefaultData) do
								profile.Data[k] = v
							end
						end
						dataToPass = profile.Data
					else
						-- For specific keys
						if not profile.Data[key] and handler.DefaultData then
							profile.Data[key] = handler.DefaultData
						end
						dataToPass = profile.Data[key]
					end

					handler.OnLoad(player, dataToPass)
				end)
			end

			print("DataService: Profile loaded for " .. player.Name)
		else
			profile:Release()
		end
	else
		player:Kick("DataService: Could not load profile. Please rejoin.")
	end
end

local function onPlayerRemoving(player: Player)
	local profile = Profiles[player]
	if profile then
		-- Notify Handlers to perform any final updates before release
		for key, handler in pairs(Handlers) do
			if handler.OnSave then
				local dataToPass = profile.Data
				if key ~= "Root" and key ~= "Legacy" then
					dataToPass = profile.Data[key]
				end

				-- The handler might return modified data, or modify it in place.
				-- For the Legacy adapter, it effectively gathers data and returns it.
				-- If OnSave returns a table, we update the profile.
				local savedData = handler.OnSave(player, dataToPass)
				if savedData and (key == "Root" or key == "Legacy") then
					-- Merge/Overwrite for Root/Legacy
					for k, v in pairs(savedData) do
						profile.Data[k] = v
					end
				elseif savedData then
					profile.Data[key] = savedData
				end
			end
		end

		profile:Release()
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function DataService.Init()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return DataService
