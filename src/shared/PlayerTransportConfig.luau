local PlayerTransportConfig = {}

PlayerTransportConfig.DEFAULT_TRANSPORT_ID = "PlayerBike"

PlayerTransportConfig.TRANSPORTS = {
	PlayerBike = {
		id = "PlayerBike",
		displayName = "Bicycle",
		modelName = "PlayerBike",
		price = 0,
		description = "A reliable starter ride for getting around your island.",
		unlockByDefault = true,
		sortOrder = 1,
	},
	PlayerScooter = {
		id = "PlayerScooter",
		displayName = "Scooter",
		modelName = "PlayerScooter",
		price = 2500,
		description = "A quicker personal transport with a tighter footprint.",
		unlockByDefault = false,
		sortOrder = 2,
	},
	PlayerDrone = {
		id = "PlayerDrone",
		displayName = "Drone",
		modelName = "PlayerDrone",
		price = 12000,
		description = "A premium airborne transport for flexing on your plot.",
		unlockByDefault = false,
		sortOrder = 3,
	},
}

function PlayerTransportConfig.GetSortedTransports()
	local transports = {}
	for _, transport in pairs(PlayerTransportConfig.TRANSPORTS) do
		table.insert(transports, transport)
	end

	table.sort(transports, function(a, b)
		if a.sortOrder == b.sortOrder then
			return a.id < b.id
		end
		return a.sortOrder < b.sortOrder
	end)

	return transports
end

return PlayerTransportConfig
