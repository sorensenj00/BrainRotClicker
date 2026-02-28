--[[
	DataService.luau

	A SOLID, modular data manager powered by ProfileService.
	Handles player data persistence and allows other systems to register
	data handlers without tightly coupling with the persistence layer.
]]

local Players = game:GetService("Players")

local ProfileService = require(script.Parent.ProfileService)

-- PlayerLifecycleManager (Lazy Loaded to avoid circular require at module load time)
local PlayerLifecycleManager
local function getPlayerLifecycleManager()
	if not PlayerLifecycleManager then
		PlayerLifecycleManager = require(script.Parent.PlayerLifecycleManager)
	end
	return PlayerLifecycleManager
end

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
	-- Called when data is unloaded/released. Use this to clear cache.
	OnRelease: (player: Player) -> (),
	-- Default data for this component (if structure is partitioned)
	DefaultData: any?
}

type CartUpgrades = {
	Capacity: number,
	Model: number
}

local DataService = {}
local Profiles: {[Player]: Profile} = {}
local Handlers: {[string]: DataHandler} = {}

-- The store used for the new system (V3 - Clean Start)
local DATA_VERSION = "BrainRotClickerData_v4"
local ProfileStore = ProfileService.GetProfileStore(
	DATA_VERSION,
	{
		-- V3 Clean Schema - No legacy migration needed
		money = 0,
		lifetimeEarnings = 0,
		
		-- Brainrot Inventory (owned but not placed)
		Inventory = {},
		
		-- Grid Placements (units on islands with tier info)
		GridPlacements = {},
		
		-- Artifacts (all owned, with equipment links)
		Artifacts = {},
		
		-- Artifact Exchange Escrow (GUIDs of artifacts listed for sale)
		EscrowedArtifacts = {},
		
		-- Cart Upgrades (Persisted)
		CartUpgrades = {
			Capacity = 0,
			Model = 1 -- Tier 1 default
		},
		
		-- Item Storage & Backpack
		ItemStorage = {},
		Backpack = {},
		
		-- Prestige System
		Prestige = {
			totalMeatballs = 0,
			spentMeatballs = 0,
			prestigeCount = 0,
			meatballUpgrades = {}
		},
		
		-- Upgrades & Progress
		storageCapacity = 2000,
		purchasedTiers = 1,
		unlockedGridSlots = 4,
		unlockProgress = 5,
		selectedVehicle = "Sneakers",
		vehicleCapacities = {},
		convenienceUpgrades = {},
		discoveredSynergies = {}
	}
)

--------------------------------------------------------------------------------
-- PUBLIC API
--------------------------------------------------------------------------------

--[[
	ECONOMY API
]]
function DataService.GetMoney(player: Player): number
	local profile = Profiles[player]
	if profile and profile.Data then
		return profile.Data.money or 0
	end
	return 0
end

function DataService.AddMoney(player: Player, amount: number)
	local profile = Profiles[player]
	if profile and profile.Data then
		profile.Data.money = (profile.Data.money or 0) + amount
		profile.Data.lifetimeEarnings = (profile.Data.lifetimeEarnings or 0) + amount
		
		-- Sync to leaderstats for client display (Legacy support)
		local ls = player:FindFirstChild("leaderstats")
		local m = ls and ls:FindFirstChild("Money")
		if m then m.Value = profile.Data.money end
		
		return true
	end
	return false
end

function DataService.DeductMoney(player: Player, amount: number): boolean
	local profile = Profiles[player]
	if profile and profile.Data then
		local current = profile.Data.money or 0
		if current >= amount then
			profile.Data.money = current - amount
			
			-- Sync to leaderstats
			local ls = player:FindFirstChild("leaderstats")
			local m = ls and ls:FindFirstChild("Money")
			if m then m.Value = profile.Data.money end
			
			return true
		end
	end
	return false
end

--[[
	CART API
]]
function DataService.GetCartUpgrades(player: Player)
	local profile = Profiles[player]
	if profile and profile.Data then
		return profile.Data.CartUpgrades or { Capacity = 0, Model = 1 }
	end
	return { Capacity = 0, Model = 1 }
end

function DataService.SetCartUpgrades(player: Player, upgrades: CartUpgrades)
	local profile = Profiles[player]
	if profile and profile.Data then
		profile.Data.CartUpgrades = upgrades
		return true
	end
	return false
end

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
	Gets the current data for a player (entire profile).
]]
function DataService.GetData(player: Player)
	local profile = Profiles[player]
	if profile then
		return profile.Data
	end
	return nil
end

--[[
	Gets a specific component's data slice.
	@param player Player
	@param componentKey string - The component key (e.g., "Inventory", "Prestige")
	@return any? - The component data, or nil if not found
]]
function DataService.GetComponentData(player: Player, componentKey: string): any?
	local profile = Profiles[player]
	if profile and profile.Data then
		return profile.Data[componentKey]
	end
	return nil
end

--[[
	Sets a specific component's data (replaces entirely).
	Use this when you want to overwrite the component data.
	@param player Player
	@param componentKey string - The component key
	@param data any - The new data to set
	@return boolean - Whether the operation was successful
]]
function DataService.SetComponentData(player: Player, componentKey: string, data: any): boolean
	local profile = Profiles[player]
	if profile and profile.Data then
		profile.Data[componentKey] = data
		return true
	end
	return false
end

--[[
	Updates a specific component's data (merges with existing).
	Use this when you want to update specific fields without replacing all data.
	@param player Player
	@param componentKey string - The component key
	@param updates table - The fields to update/merge
	@return boolean - Whether the operation was successful
]]
function DataService.UpdateComponentData(player: Player, componentKey: string, updates: {[string]: any}): boolean
	local profile = Profiles[player]
	if not profile or not profile.Data then
		return false
	end
	
	-- Initialize component data if it doesn't exist
	if not profile.Data[componentKey] then
		profile.Data[componentKey] = {}
	end
	
	-- Merge updates into existing data
	local componentData = profile.Data[componentKey]
	if type(componentData) == "table" and type(updates) == "table" then
		for k, v in pairs(updates) do
			componentData[k] = v
		end
		return true
	end
	
	return false
end

--[[
	Checks if a player's profile is loaded and ready.
	@param player Player
	@return boolean - Whether the profile is loaded
]]
function DataService.IsLoaded(player: Player): boolean
	return Profiles[player] ~= nil
end

--[[
	Gets the raw Profile object for a player (for GlobalUpdates integration).
	@param player Player
	@return Profile? - The ProfileService profile, or nil
]]
function DataService.GetProfile(player: Player)
	return Profiles[player]
end

--[[
	COMPLETELY WIPES a player's profile from the DataStore.
	Use this to fix corrupted data. The player will start fresh on next join.
	@param player Player
	@return boolean - Whether the wipe was successful
]]
function DataService.WipePlayerData(player: Player): boolean
	-- First release the current profile if loaded
	local profile = Profiles[player]
	if profile then
		profile:Release()
		Profiles[player] = nil
	end
	
	-- Wipe the profile from DataStore
	local success = ProfileStore:WipeProfileAsync("Player_" .. player.UserId)
	if success then
		print("DataService: WIPED all data for " .. player.Name .. " (UserId: " .. player.UserId .. ")")
	else
		warn("DataService: Failed to wipe data for " .. player.Name)
	end
	
	return success
end

--------------------------------------------------------------------------------
-- V3: No migration needed - fresh start
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function deepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			v = deepCopy(v)
		end
		copy[k] = v
	end
	return copy
end

--[[
	Sanitizes strings to only contain valid ASCII characters (DataStore safe).
	Removes any characters outside the printable ASCII range (32-126) except newlines.
	@param str string - The string to sanitize
	@return string - The sanitized string
]]
local function sanitizeString(str: string): string
	-- Remove any characters that are not printable ASCII (32-126) or newlines/tabs
	local sanitized = string.gsub(str, "[^%w%s%p]", "")
	return sanitized
end

--[[
	Recursively sanitizes all data for DataStore safety.
	Removes non-ASCII characters from strings and skips unsaveable types.
	@param data any - The data to sanitize
	@return any - The sanitized data
]]
local function sanitizeData(data: any): any
	if type(data) == "string" then
		return sanitizeString(data)
	elseif type(data) == "table" then
		local clean = {}
		for k, v in pairs(data) do
			-- Sanitize key if it's a string
			local cleanKey = type(k) == "string" and sanitizeString(k) or k
			clean[cleanKey] = sanitizeData(v)
		end
		return clean
	elseif type(data) == "number" or type(data) == "boolean" then
		return data
	else
		-- Skip userdata, functions, threads, etc.
		return nil
	end
end

--------------------------------------------------------------------------------
-- PLAYER LIFECYCLE
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if Profiles[player] then return end -- Prevent double loading
	
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

			-- V3: No migration needed - ProfileService Reconcile() applies defaults from template

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
							local defaults = deepCopy(handler.DefaultData)
							for k, v in pairs(defaults) do
								profile.Data[k] = v
							end
						end
						dataToPass = profile.Data
					else
						-- For specific keys
						if not profile.Data[key] and handler.DefaultData then
							profile.Data[key] = deepCopy(handler.DefaultData)
						end
						dataToPass = profile.Data[key]
					end

					handler.OnLoad(player, dataToPass)
				end)
			end
			
			-- Process GlobalUpdates (Grand Exchange offline revenue, etc.)
			task.spawn(function()
				-- Process existing active updates
				for _, update in ipairs(profile.GlobalUpdates:GetActiveUpdates()) do
					local updateId = update[1]
					local updateData = update[2]
					if updateData.Type == "ArtifactSold" then
						local revenue = updateData.Revenue or 0
						if revenue > 0 then
							profile.Data.money = (profile.Data.money or 0) + revenue
							profile.Data.lifetimeEarnings = (profile.Data.lifetimeEarnings or 0) + revenue
							local ls = player:FindFirstChild("leaderstats")
							local m = ls and ls:FindFirstChild("Money")
							if m then m.Value = profile.Data.money end
							print("DataService: Credited $" .. revenue .. " artifact sale revenue to " .. player.Name)
						end
						-- Remove from escrow if present
						if updateData.ListingGUID and profile.Data.EscrowedArtifacts then
							profile.Data.EscrowedArtifacts[updateData.ListingGUID] = nil
						end
						profile.GlobalUpdates:LockActiveUpdate(updateId)
					end
				end
				-- Clear locked updates
				for _, update in ipairs(profile.GlobalUpdates:GetLockedUpdates()) do
					local updateId = update[1]
					profile.GlobalUpdates:ClearLockedUpdate(updateId)
				end
				-- Listen for future updates while online
				profile.GlobalUpdates:ListenToNewActiveUpdate(function(updateId, updateData)
					if updateData.Type == "ArtifactSold" then
						local revenue = updateData.Revenue or 0
						if revenue > 0 then
							profile.Data.money = (profile.Data.money or 0) + revenue
							profile.Data.lifetimeEarnings = (profile.Data.lifetimeEarnings or 0) + revenue
							local ls = player:FindFirstChild("leaderstats")
							local m = ls and ls:FindFirstChild("Money")
							if m then m.Value = profile.Data.money end
						end
						if updateData.ListingGUID and profile.Data.EscrowedArtifacts then
							profile.Data.EscrowedArtifacts[updateData.ListingGUID] = nil
						end
						-- Notify client about the sale
						local ReplicatedStorage = game:GetService("ReplicatedStorage")
						local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
						local notifyEvent = RemoteEvents and RemoteEvents:FindFirstChild("ArtifactExchangeNotify")
						if notifyEvent then
							notifyEvent:FireClient(player, "sold", {
								ArtifactName = updateData.ArtifactName or "Unknown",
								Revenue = revenue,
							})
						end
						profile.GlobalUpdates:LockActiveUpdate(updateId)
					end
				end)
				profile.GlobalUpdates:ListenToNewLockedUpdate(function(updateId, _updateData)
					profile.GlobalUpdates:ClearLockedUpdate(updateId)
				end)
			end)

			local plm = getPlayerLifecycleManager()
			if plm then plm.SetDataLoaded(player) end

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

		-- SANITIZE strings in-place before release to prevent UTF-8 errors
		-- Use in-place sanitization to avoid breaking ProfileService internal structures
		local function sanitizeInPlace(tbl)
			for k, v in pairs(tbl) do
				if type(v) == "string" then
					-- Remove non-ASCII characters
					tbl[k] = string.gsub(v, "[^%w%s%p]", "")
				elseif type(v) == "table" then
					sanitizeInPlace(v)
				end
			end
		end
		sanitizeInPlace(profile.Data)

		profile:Release()
		
		-- Notify Handlers of release/cleanup
		for key, handler in pairs(Handlers) do
			if handler.OnRelease then
				task.spawn(function()
					handler.OnRelease(player)
				end)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

local Initialized = false

function DataService.Init()
	if Initialized then return end
	Initialized = true
	
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	game:BindToClose(function()
		print("DataService: Server closing, releasing profiles...")
		
		-- Trigger safe removal for all players
		for _, player in ipairs(Players:GetPlayers()) do
			-- Use coroutines to parallelize saving
			task.spawn(onPlayerRemoving, player)
		end
		
		-- Wait for all profiles to be released (saved)
		local startTime = os.clock()
		while next(Profiles) ~= nil do
			if os.clock() - startTime > 30 then 
				warn("DataService: BindToClose timed out waiting for saves!")
				break 
			end
			task.wait(0.1)
		end
		
		print("DataService: All profiles released.")
	end)
end

return DataService
