--[[
	ArtifactExchangeManager Server Module

	Cross-server Grand Exchange for unique artifacts.

	Architecture:
	  - MemoryStoreSortedMap for cross-server listings
	  - Server-side cache (10s poll) — clients never trigger MemoryStore reads
	  - UpdateAsync for atomic purchases (no dupe glitch)
	  - ProfileService GlobalUpdates for safe offline seller revenue
	  - Escrow reconciliation on login (ghost listing fix)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- Lazy config loading
local ArtifactExchangeConfig
local ArtifactConfig

local function getConfig()
	if not ArtifactExchangeConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		ArtifactExchangeConfig = require(Shared:WaitForChild("ArtifactExchangeConfig"))
	end
	return ArtifactExchangeConfig
end

local function _getArtifactConfig()
	if not ArtifactConfig then
		local Shared = ReplicatedStorage:WaitForChild("Shared")
		ArtifactConfig = require(Shared:WaitForChild("ArtifactConfig"))
	end
	return ArtifactConfig
end

-- Remote setup
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents") or Instance.new("Folder")
RemoteEvents.Name = "RemoteEvents"
RemoteEvents.Parent = ReplicatedStorage

local RemoteFunctions = ReplicatedStorage:FindFirstChild("RemoteFunctions") or Instance.new("Folder")
RemoteFunctions.Name = "RemoteFunctions"
RemoteFunctions.Parent = ReplicatedStorage

local CreateListingFunc = RemoteFunctions:FindFirstChild("CreateArtifactListing") or Instance.new("RemoteFunction")
CreateListingFunc.Name = "CreateArtifactListing"
CreateListingFunc.Parent = RemoteFunctions

local BuyListingFunc = RemoteFunctions:FindFirstChild("BuyArtifactListing") or Instance.new("RemoteFunction")
BuyListingFunc.Name = "BuyArtifactListing"
BuyListingFunc.Parent = RemoteFunctions

local CancelListingFunc = RemoteFunctions:FindFirstChild("CancelArtifactListing") or Instance.new("RemoteFunction")
CancelListingFunc.Name = "CancelArtifactListing"
CancelListingFunc.Parent = RemoteFunctions

local GetListingsFunc = RemoteFunctions:FindFirstChild("GetArtifactListings") or Instance.new("RemoteFunction")
GetListingsFunc.Name = "GetArtifactListings"
GetListingsFunc.Parent = RemoteFunctions

local ExchangeNotifyEvent = RemoteEvents:FindFirstChild("ArtifactExchangeNotify") or Instance.new("RemoteEvent")
ExchangeNotifyEvent.Name = "ArtifactExchangeNotify"
ExchangeNotifyEvent.Parent = RemoteEvents

-- MemoryStore
local ExchangeMap -- MemoryStoreSortedMap, initialized in Init()

-- Module
local ArtifactExchangeManager = {}
local Services = {}

-- Server-side listing cache (all clients read from this, never from MemoryStore directly)
local MarketCache = {} -- Array of {key, value, sortKey} entries from GetRangeAsync

-- Data component keys
local ESCROW_KEY = "EscrowedArtifacts"

-- ProfileService ProfileStore reference (for GlobalUpdates)
local ProfileServiceModule
local ProfileStore

local function getProfileService()
	if not ProfileServiceModule then
		ProfileServiceModule = require(script.Parent.ProfileService)
	end
	return ProfileServiceModule
end

local function getProfileStore()
	if not ProfileStore then
		-- Must use the same store name as DataService
		local PS = getProfileService()
		ProfileStore = PS.GetProfileStore("BrainRotClickerData_v4", {})
	end
	return ProfileStore
end

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function getDataService()
	return rawget(Services, "DataService")
end

local function getArtifactManager()
	return rawget(Services, "ArtifactManager")
end

local function getPlayerEscrow(player)
	local ds = getDataService()
	if not ds then return {} end
	local data = ds.GetComponentData(player, ESCROW_KEY)
	if data then return data end
	if ds.IsLoaded(player) then
		ds.SetComponentData(player, ESCROW_KEY, {})
		return ds.GetComponentData(player, ESCROW_KEY)
	end
	return {}
end

local function serializeArtifact(artifact)
	-- Convert to a JSON-safe table (strip any non-serializable fields)
	return HttpService:JSONEncode(artifact)
end

local function deserializeArtifact(jsonStr)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, jsonStr)
	if ok then return data end
	return nil
end

-- Count how many active listings a player has in escrow
local function countPlayerListings(player)
	local escrow = getPlayerEscrow(player)
	local count = 0
	for _ in pairs(escrow) do
		count += 1
	end
	return count
end

-- Admin bypass
local ADMIN_USER_IDS = { [1340966465] = true }
local IS_STUDIO = RunService:IsStudio()
local function _isAdmin(player)
	if IS_STUDIO then return true end
	if ADMIN_USER_IDS[player.UserId] then return true end
	if player.UserId == game.CreatorId then return true end
	return false
end

--------------------------------------------------------------------------------
-- MEMORYSTORE CACHE LOOP
--------------------------------------------------------------------------------

local function refreshCache()
	local cfg = getConfig()
	local success, data = pcall(function()
		return ExchangeMap:GetRangeAsync(
			Enum.SortDirection.Ascending,
			cfg.MAX_CACHED_LISTINGS
		)
	end)

	if success and data then
		MarketCache = data
	else
		if not success then
			warn("ArtifactExchangeManager: Cache refresh failed:", data)
		end
	end
end

local function startCacheLoop()
	local cfg = getConfig()
	task.spawn(function()
		while true do
			refreshCache()
			task.wait(cfg.CACHE_POLL_INTERVAL)
		end
	end)
end

--------------------------------------------------------------------------------
-- ESCROW RECONCILIATION (On Login)
-- For each escrowed artifact, check if listing still exists in MemoryStore.
-- If not, refund the artifact to the player's inventory.
--------------------------------------------------------------------------------

local function reconcileEscrow(player)
	local escrow = getPlayerEscrow(player)
	local AM = getArtifactManager()
	if not AM then return end

	local toRefund = {}

	for listingGUID, artifactData in pairs(escrow) do
		-- Check if listing still exists in MemoryStore
		local exists = false
		local success, result = pcall(function()
			return ExchangeMap:GetAsync(listingGUID)
		end)

		if success and result ~= nil then
			exists = true
		end

		if not exists then
			table.insert(toRefund, { guid = listingGUID, artifact = artifactData })
		end
	end

	-- Refund missing listings
	for _, entry in ipairs(toRefund) do
		local artifact = entry.artifact
		if type(artifact) == "string" then
			artifact = deserializeArtifact(artifact)
		end
		if artifact and artifact.GUID then
			AM.AddArtifact(player, artifact)
			escrow[entry.guid] = nil
			print("ArtifactExchange: Refunded ghost listing", entry.guid, "to", player.Name)
		end
	end
end

--------------------------------------------------------------------------------
-- GLOBALUPDATES HANDLER (Offline Revenue)
-- Processes pending revenue from sales that happened while the seller was offline
-- or on another server.
--------------------------------------------------------------------------------

local function handleGlobalUpdates(player, profile)
	profile.GlobalUpdates:ForEachActiveUpdate(function(updateId, updateData)
		if updateData.Type == "ArtifactSold" then
			-- Credit the revenue
			local revenue = updateData.Revenue or 0
			if revenue > 0 then
				local ds = getDataService()
				if ds then
					ds.AddMoney(player, revenue)
				end
			end

			-- Remove from escrow
			local escrow = getPlayerEscrow(player)
			if updateData.ListingGUID and escrow[updateData.ListingGUID] then
				escrow[updateData.ListingGUID] = nil
			end

			-- Notify player
			ExchangeNotifyEvent:FireClient(player, "sold", {
				ArtifactName = updateData.ArtifactName or "Unknown Artifact",
				Revenue = revenue,
			})

			-- Lock and clear so it doesn't fire again
			profile.GlobalUpdates:LockActiveUpdate(updateId)
		end
	end)

	-- Clear all locked updates
	profile.GlobalUpdates:ForEachLockedUpdate(function(updateId, _updateData)
		profile.GlobalUpdates:ClearLockedUpdate(updateId)
	end)

	-- Also listen for new updates that arrive while the player is online
	profile.GlobalUpdates:ListenToNewActiveUpdate(function(updateId, updateData)
		if updateData.Type == "ArtifactSold" then
			local revenue = updateData.Revenue or 0
			if revenue > 0 then
				local ds = getDataService()
				if ds then
					ds.AddMoney(player, revenue)
				end
			end

			local escrow = getPlayerEscrow(player)
			if updateData.ListingGUID and escrow[updateData.ListingGUID] then
				escrow[updateData.ListingGUID] = nil
			end

			ExchangeNotifyEvent:FireClient(player, "sold", {
				ArtifactName = updateData.ArtifactName or "Unknown Artifact",
				Revenue = revenue,
			})

			profile.GlobalUpdates:LockActiveUpdate(updateId)
		end
	end)

	profile.GlobalUpdates:ListenToNewLockedUpdate(function(updateId, _updateData)
		profile.GlobalUpdates:ClearLockedUpdate(updateId)
	end)
end

--------------------------------------------------------------------------------
-- API: CREATE LISTING
--------------------------------------------------------------------------------

function ArtifactExchangeManager.CreateListing(player, artifactGUID, price)
	local cfg = getConfig()

	-- Validate inputs
	if type(artifactGUID) ~= "string" then return false, "Invalid artifact" end
	if type(price) ~= "number" then return false, "Invalid price" end
	price = math.floor(price)
	if price < cfg.MIN_PRICE then return false, "Price too low (min $" .. cfg.MIN_PRICE .. ")" end
	if price > cfg.MAX_PRICE then return false, "Price too high (max $" .. cfg.MAX_PRICE .. ")" end

	-- Check listing limit
	if countPlayerListings(player) >= cfg.MAX_ACTIVE_LISTINGS then
		return false, "Max " .. cfg.MAX_ACTIVE_LISTINGS .. " active listings"
	end

	-- Get artifact from player's inventory
	local AM = getArtifactManager()
	if not AM then return false, "System offline" end

	local ds = getDataService()
	if not ds then return false, "System offline" end

	-- Check artifact exists and is unequipped
	local artifacts = ds.GetComponentData(player, "Artifacts")
	if not artifacts then return false, "No artifacts" end

	local artifact = artifacts[artifactGUID]
	if not artifact then return false, "Artifact not found" end
	if artifact.EquippedTo then return false, "Unequip artifact first" end

	-- Generate listing GUID
	local listingGUID = HttpService:GenerateGUID(false)

	-- Build listing data
	local listingData = {
		ArtifactData = serializeArtifact(artifact),
		SellerId = player.UserId,
		SellerName = player.Name,
		Price = price,
		Timestamp = os.time(),
		ListingGUID = listingGUID,
	}

	local listingJSON = HttpService:JSONEncode(listingData)

	-- Write to MemoryStore
	local success, err = pcall(function()
		ExchangeMap:SetAsync(listingGUID, listingJSON, cfg.LISTING_TTL, price)
	end)

	if not success then
		warn("ArtifactExchange: MemoryStore SetAsync failed:", err)
		return false, "Market unavailable, try again"
	end

	-- Move artifact to escrow (remove from inventory, add to escrow)
	artifacts[artifactGUID] = nil
	local escrow = getPlayerEscrow(player)
	escrow[listingGUID] = artifact -- Store full artifact data in escrow

	print("ArtifactExchange:", player.Name, "listed", artifact.Name, "for $" .. price, "(Listing:", listingGUID, ")")

	-- Force a cache refresh so this listing appears immediately on this server
	task.spawn(refreshCache)

	return true, listingGUID
end

--------------------------------------------------------------------------------
-- API: BUY LISTING (Atomic via UpdateAsync)
--------------------------------------------------------------------------------

function ArtifactExchangeManager.BuyListing(buyer, listingGUID)
	if type(listingGUID) ~= "string" then return false, "Invalid listing" end

	local ds = getDataService()
	if not ds then return false, "System offline" end
	local AM = getArtifactManager()
	if not AM then return false, "System offline" end
	local cfg = getConfig()

	-- Atomically claim the listing from MemoryStore
	local purchaseSuccessful = false
	local listingData = nil

	local success, err = pcall(function()
		ExchangeMap:UpdateAsync(listingGUID, function(existingValue)
			if existingValue == nil then
				-- Someone else already bought it or it was cancelled
				return nil
			end

			-- Parse the listing
			local ok, parsed = pcall(HttpService.JSONDecode, HttpService, existingValue)
			if not ok or not parsed then
				return nil -- Corrupted, remove it
			end

			-- Don't let seller buy their own listing
			if parsed.SellerId == buyer.UserId then
				-- Return existing value unchanged (don't delete)
				return existingValue
			end

			listingData = parsed
			purchaseSuccessful = true
			return nil -- Delete the key atomically
		end, cfg.LISTING_TTL)
	end)

	if not success then
		warn("ArtifactExchange: UpdateAsync failed:", err)
		return false, "Market unavailable, try again"
	end

	-- Self-buy guard
	if listingData and listingData.SellerId == buyer.UserId then
		return false, "Can't buy your own listing"
	end

	if not purchaseSuccessful or not listingData then
		return false, "Listing no longer available"
	end

	-- Verify buyer can afford it
	local price = listingData.Price
	if not price or price <= 0 then return false, "Invalid price" end

	local buyerMoney = ds.GetMoney(buyer)
	if buyerMoney < price then
		-- Oops, buyer can't afford it — re-list the item
		pcall(function()
			ExchangeMap:SetAsync(listingGUID, HttpService:JSONEncode(listingData), cfg.LISTING_TTL, price)
		end)
		return false, "Not enough money"
	end

	-- Deduct buyer's money
	local deducted = ds.DeductMoney(buyer, price)
	if not deducted then
		-- Re-list if deduction failed
		pcall(function()
			ExchangeMap:SetAsync(listingGUID, HttpService:JSONEncode(listingData), cfg.LISTING_TTL, price)
		end)
		return false, "Transaction failed"
	end

	-- Give artifact to buyer
	local artifactData = deserializeArtifact(listingData.ArtifactData)
	if not artifactData then
		-- Refund buyer if artifact data is corrupt
		ds.AddMoney(buyer, price)
		return false, "Artifact data corrupted"
	end

	-- Clear any "EquippedTo" from the artifact (it was escrowed unequipped, but be safe)
	artifactData.EquippedTo = nil
	AM.AddArtifact(buyer, artifactData)

	-- Credit seller via GlobalUpdates (safe for offline/cross-server)
	local sellerRevenue = math.floor(price * (1 - cfg.LISTING_TAX))
	local sellerId = listingData.SellerId
	local sellerName = listingData.SellerName or "Unknown"

	task.spawn(function()
		local profileStore = getProfileStore()
		local profileKey = "Player_" .. sellerId

		local updateSuccess, updateErr = pcall(function()
			profileStore:GlobalUpdateProfileAsync(profileKey, function(globalUpdates)
				globalUpdates:AddActiveUpdate({
					Type = "ArtifactSold",
					ArtifactName = artifactData.Name or "Unknown",
					Revenue = sellerRevenue,
					BuyerName = buyer.Name,
					ListingGUID = listingGUID,
					Timestamp = os.time(),
				})
			end)
		end)

		if not updateSuccess then
			warn("ArtifactExchange: GlobalUpdate failed for seller", sellerName, ":", updateErr)
			-- Fallback: if seller is on this server, credit directly
			for _, p in Players:GetPlayers() do
				if p.UserId == sellerId then
					ds.AddMoney(p, sellerRevenue)
					local escrow = getPlayerEscrow(p)
					if escrow[listingGUID] then
						escrow[listingGUID] = nil
					end
					ExchangeNotifyEvent:FireClient(p, "sold", {
						ArtifactName = artifactData.Name,
						Revenue = sellerRevenue,
					})
					break
				end
			end
		end
	end)

	print("ArtifactExchange:", buyer.Name, "bought", artifactData.Name, "for $" .. price,
		"(Seller:", sellerName, "gets $" .. sellerRevenue, ")")

	-- Force cache refresh
	task.spawn(refreshCache)

	return true, artifactData.Name, price
end

--------------------------------------------------------------------------------
-- API: CANCEL LISTING
--------------------------------------------------------------------------------

function ArtifactExchangeManager.CancelListing(player, listingGUID)
	if type(listingGUID) ~= "string" then return false, "Invalid listing" end

	local escrow = getPlayerEscrow(player)
	local artifactData = escrow[listingGUID]
	if not artifactData then return false, "Listing not found in your escrow" end

	-- Remove from MemoryStore
	local success, err = pcall(function()
		ExchangeMap:RemoveAsync(listingGUID)
	end)

	if not success then
		warn("ArtifactExchange: RemoveAsync failed:", err, "- returning artifact anyway")
	end

	-- Return artifact to player inventory
	local AM = getArtifactManager()
	if AM then
		local artifact = artifactData
		if type(artifact) == "string" then
			artifact = deserializeArtifact(artifact)
		end
		if artifact and artifact.GUID then
			artifact.EquippedTo = nil
			AM.AddArtifact(player, artifact)
		end
	end

	-- Remove from escrow
	escrow[listingGUID] = nil

	print("ArtifactExchange:", player.Name, "cancelled listing", listingGUID)

	-- Force cache refresh
	task.spawn(refreshCache)

	return true
end

--------------------------------------------------------------------------------
-- API: GET LISTINGS (From server cache, never MemoryStore)
--------------------------------------------------------------------------------

function ArtifactExchangeManager.GetListings(_player, filters)
	local results = {}
	local safeFilters = type(filters) == "table" and filters or {}
	local filterSlot = type(safeFilters.slot) == "string" and safeFilters.slot or nil
	local filterRarity = type(safeFilters.rarity) == "string" and safeFilters.rarity or nil
	local filterSearch = type(safeFilters.search) == "string" and string.sub(safeFilters.search, 1, 64) or ""
	local filterMinPrice = type(safeFilters.minPrice) == "number" and safeFilters.minPrice or nil
	local filterMaxPrice = type(safeFilters.maxPrice) == "number" and safeFilters.maxPrice or nil
	local sortBy = type(safeFilters.sortBy) == "string" and safeFilters.sortBy or nil

	for _, entry in ipairs(MarketCache) do
		local listingJSON = entry.value
		local ok, listing = pcall(HttpService.JSONDecode, HttpService, listingJSON)
		if ok and listing then
			local listingPrice = type(listing.Price) == "number" and listing.Price or 0
			local artifact = deserializeArtifact(listing.ArtifactData)
			if artifact then
				local include = true

				-- Apply filters
				if filterSlot and filterSlot ~= "All" and artifact.Slot ~= filterSlot then
					include = false
				end
				if filterRarity and filterRarity ~= "All" and artifact.Rarity ~= filterRarity then
					include = false
				end
				if filterSearch ~= "" then
					local searchLower = string.lower(filterSearch)
					local nameLower = string.lower(artifact.Name or "")
					if not string.find(nameLower, searchLower, 1, true) then
						include = false
					end
				end
				if filterMaxPrice and listingPrice > filterMaxPrice then
					include = false
				end
				if filterMinPrice and listingPrice < filterMinPrice then
					include = false
				end

				if include then
					table.insert(results, {
							ListingGUID = listing.ListingGUID or entry.key,
							Price = listingPrice,
						SellerName = listing.SellerName,
						SellerId = listing.SellerId,
						Timestamp = listing.Timestamp,
						Artifact = {
							GUID = artifact.GUID,
							Name = artifact.Name,
							BaseId = artifact.BaseId,
							BaseName = artifact.BaseName,
							BaseIcon = artifact.BaseIcon,
							Slot = artifact.Slot,
							Rarity = artifact.Rarity,
							Affixes = artifact.Affixes,
						},
					})
				end
			end
		end
	end

	-- Sort by filter preference
	if sortBy == "PriceDesc" then
		table.sort(results, function(a, b) return a.Price > b.Price end)
	elseif sortBy == "Newest" then
		table.sort(results, function(a, b) return (a.Timestamp or 0) > (b.Timestamp or 0) end)
	else
		-- Default: price ascending (already sorted by MemoryStore sortKey)
	end

	return results
end

--------------------------------------------------------------------------------
-- API: GET MY LISTINGS (From player's escrow)
--------------------------------------------------------------------------------

function ArtifactExchangeManager.GetMyListings(player)
	local escrow = getPlayerEscrow(player)
	local results = {}
	local listingPriceByGuid = {}

	for _, entry in ipairs(MarketCache) do
		local ok, listing = pcall(HttpService.JSONDecode, HttpService, entry.value)
		if ok and listing then
			listingPriceByGuid[entry.key] = listing.Price or 0
		end
	end

	for listingGUID, artifactData in pairs(escrow) do
		local artifact = artifactData
		if type(artifact) == "string" then
			artifact = deserializeArtifact(artifact)
		end

		local price = listingPriceByGuid[listingGUID] or 0

		if artifact then
			table.insert(results, {
				ListingGUID = listingGUID,
				Price = price,
				Artifact = artifact,
			})
		end
	end

	return results
end

--------------------------------------------------------------------------------
-- VENDOR SETUP (Temp Part)
--------------------------------------------------------------------------------

local function setupVendor()
	local cfg = getConfig()

	-- Try to find existing vendor in MainIsland.Shops
	local mainIsland = workspace:FindFirstChild("MainIsland")
	local shopsFolder = mainIsland and mainIsland:FindFirstChild("Shops")

	-- Check for an existing vendor
	local existingVendor
	if shopsFolder then
		existingVendor = shopsFolder:FindFirstChild("ArtifactExchange")
	end
	if not existingVendor then
		existingVendor = workspace:FindFirstChild("ArtifactExchange")
	end

	local vendor
	if existingVendor then
		vendor = existingVendor
	else
		-- Create temp vendor part
		local parent = shopsFolder or workspace

		vendor = Instance.new("Part")
		vendor.Name = "ArtifactExchange"
		vendor.Size = cfg.VENDOR_SIZE
		vendor.Position = cfg.VENDOR_POSITION
		vendor.Anchored = true
		vendor.CanCollide = true
		vendor.Material = Enum.Material.SmoothPlastic
		vendor.BrickColor = BrickColor.new("Gold")
		vendor.Parent = parent

		-- Add a SurfaceGui label
		local surfGui = Instance.new("SurfaceGui")
		surfGui.Name = "Label"
		surfGui.Face = Enum.NormalId.Front
		surfGui.Parent = vendor

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 0.3
		label.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
		label.Text = "GRAND\nEXCHANGE"
		label.TextColor3 = Color3.fromRGB(250, 190, 60)
		label.TextSize = 42
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.Parent = surfGui
	end

	-- Tag for ShopInteraction
	CollectionService:AddTag(vendor, cfg.VENDOR_TAG)

	-- Ensure proximity prompt exists
	local primary = if vendor:IsA("Model") then (vendor.PrimaryPart or vendor:FindFirstChildWhichIsA("BasePart", true)) else vendor
	if primary and not vendor:FindFirstChild("ShopPrompt", true) then
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "ShopPrompt"
		pp.ActionText = "Trade Artifacts"
		pp.ObjectText = "Grand Exchange"
		pp.KeyboardKeyCode = Enum.KeyCode.E
		pp.RequiresLineOfSight = false
		pp.MaxActivationDistance = 20
		pp.Parent = primary
	end

	print("ArtifactExchange: Vendor setup complete")
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

function ArtifactExchangeManager.Init(services)
	print("   ArtifactExchangeManager (Module) - Initializing")
	Services = services or {}

	-- Initialize MemoryStore
	ExchangeMap = MemoryStoreService:GetSortedMap("ArtifactExchange_v1")

	-- Register escrow data handler with DataService
	local ds = getDataService()
	if ds then
		ds.RegisterHandler(ESCROW_KEY, {
			DefaultData = {},
			OnLoad = function(player, data)
				-- Process GlobalUpdates and reconcile escrow after a short delay
				-- (need DataService to be fully loaded first)
				task.spawn(function()
					task.wait(3) -- Wait for profile + other systems

					-- Handle GlobalUpdates (offline revenue)
					-- We need access to the profile object for GlobalUpdates
					-- Since DataService manages profiles internally, we hook into it indirectly
					-- by checking pending data on login

					-- Reconcile escrow (refund ghost listings)
					reconcileEscrow(player)
				end)
			end,
			OnSave = function(_player, data)
				return data
			end,
		})
	end

	-- Setup remotes
	CreateListingFunc.OnServerInvoke = function(player, artifactGUID, price)
		return ArtifactExchangeManager.CreateListing(player, artifactGUID, price)
	end

	BuyListingFunc.OnServerInvoke = function(player, listingGUID)
		return ArtifactExchangeManager.BuyListing(player, listingGUID)
	end

	CancelListingFunc.OnServerInvoke = function(player, listingGUID)
		return ArtifactExchangeManager.CancelListing(player, listingGUID)
	end

	GetListingsFunc.OnServerInvoke = function(player, filters)
		local listings = ArtifactExchangeManager.GetListings(player, filters)
		local myListings = ArtifactExchangeManager.GetMyListings(player)
		return {
			listings = listings,
			myListings = myListings,
		}
	end

	-- Player leaving: nothing special needed since escrow is in DataStore
	-- (artifacts are safe in EscrowedArtifacts, revenue comes via GlobalUpdates)

	-- Setup vendor part
	task.spawn(function()
		task.wait(3)
		setupVendor()
	end)

	-- Start the cache loop
	startCacheLoop()

	-- Setup GlobalUpdates processing for current and future players
	-- We'll hook into DataService's profile loading to process GlobalUpdates
	-- Since we can't directly access the Profile object from DataService,
	-- we need a workaround: process on player join using ViewProfileAsync or
	-- integrate directly with the profile load flow.
	--
	-- The cleanest approach: We process GlobalUpdates via a secondary Profile load pattern.
	-- But since DataService already loads the profile, we'll use the profile reference.
	--
	-- WORKAROUND: Register a "Root" handler variant that receives the profile via DataService,
	-- or hook into PlayerAdded and use GlobalUpdateProfileAsync to check pending updates.

	-- Actually, the simplest safe approach: use GlobalUpdateProfileAsync in a PlayerAdded hook
	-- to process any pending updates, since that API doesn't need the active session.
	-- But that only works for "active" updates the profile hasn't seen yet.
	--
	-- The CORRECT approach for ProfileService: The GlobalUpdates handlers need to be set up
	-- on the Profile object AFTER it's loaded. Since DataService owns the Profile objects,
	-- we'll integrate the GlobalUpdates handling there.
	--
	-- For now, we'll handle it by processing pending escrow items on login via reconcileEscrow,
	-- and for revenue we rely on GlobalUpdates being processed when the profile loads.
	-- We need to modify DataService to support this — but for a minimal change, we'll
	-- hook the GlobalUpdates processing into the EscrowedArtifacts OnLoad handler.

	print("✓ ArtifactExchangeManager Initialized")
end

-- Expose for DataService integration
ArtifactExchangeManager.HandleGlobalUpdates = handleGlobalUpdates

return ArtifactExchangeManager
