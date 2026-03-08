--[[
	RadioStations

	GTA-style radio metadata shared by the client UI and controller.
	Stations use audio from workspace.Music. Length is required so the
	controller can tune into the correct live broadcast position when
	players switch stations. Adjust `length` per track if needed.
]]

export type RadioStation = {
	id: string,
	displayName: string,
	soundId: string,
	length: number,
	offset: number?,
	volume: number?,
	description: string?,
}

local RadioStations = {
	SWITCH_SFX_ID = "rbxassetid://138090596",
	STATIONS = {
		{ id = "blessing", displayName = "Blessing on blessing", soundId = "rbxassetid://101100004040565", length = 200, offset = 0, volume = 0.4 },
		{ id = "claire", displayName = "Claire de Lune", soundId = "rbxassetid://115549034177805", length = 300, offset = 45, volume = 0.4 },
		{ id = "counting", displayName = "Counting Seconds", soundId = "rbxassetid://118001868442400", length = 220, offset = 90, volume = 0.4 },
		{ id = "crystal_rain", displayName = "Crystal Rain Nocturne Aria", soundId = "rbxassetid://72946578678565", length = 240, offset = 60, volume = 0.38 },
		{ id = "dust_strings", displayName = "Dust on the Strings", soundId = "rbxassetid://120468402079559", length = 210, offset = 120, volume = 0.4 },
		{ id = "empire", displayName = "Empire of Glass", soundId = "rbxassetid://140604739006649", length = 260, offset = 30, volume = 0.4 },
		{ id = "fall_into_me", displayName = "Fall into me", soundId = "rbxassetid://138663275863248", length = 230, offset = 75, volume = 0.4 },
		{ id = "half_lit", displayName = "Half-Lit Room", soundId = "rbxassetid://105658685895725", length = 200, offset = 15, volume = 0.38 },
		{ id = "indigo", displayName = "Indigo Dreams Lounge Aria", soundId = "rbxassetid://86168857785828", length = 280, offset = 100, volume = 0.38 },
		{ id = "raining_tacos", displayName = "It's Raining Tacos", soundId = "rbxassetid://89714927103166", length = 180, offset = 0, volume = 0.42 },
		{ id = "kamikaze", displayName = "Kamikaze Phonk", soundId = "rbxassetid://129663577526906", length = 190, offset = 50, volume = 0.42 },
		{ id = "elevator", displayName = "Life in an Elevator", soundId = "rbxassetid://90888110211229", length = 220, offset = 80, volume = 0.4 },
		{ id = "love_sound", displayName = "Love Without Sound", soundId = "rbxassetid://70533545241864", length = 250, offset = 40, volume = 0.38 },
		{ id = "morning_star", displayName = "Morning Star", soundId = "rbxassetid://98659760752136", length = 270, offset = 110, volume = 0.4 },
		{ id = "nyan_drill", displayName = "NYAN CAT DRILL", soundId = "rbxassetid://115951752143395", length = 170, offset = 20, volume = 0.42 },
		{ id = "crab_rave", displayName = "Noisestorm - Crab Rave", soundId = "rbxassetid://127970030854181", length = 200, offset = 65, volume = 0.42 },
		{ id = "pain_sound", displayName = "Pain without sound", soundId = "rbxassetid://89374258802194", length = 240, offset = 95, volume = 0.38 },
		{ id = "parry_tacos", displayName = "Parry Gripp - Raining Tacos", soundId = "rbxassetid://74801239248346", length = 175, offset = 10, volume = 0.42 },
		{ id = "sandi", displayName = "Sandi (Gratitude Mix)", soundId = "rbxassetid://90622311738612", length = 260, offset = 130, volume = 0.4 },
		{ id = "shattered", displayName = "Shattered Constellations", soundId = "rbxassetid://96980982085286", length = 290, offset = 55, volume = 0.38 },
		{ id = "sleep_princess", displayName = "Sleep Now Little Princess", soundId = "rbxassetid://76290369778125", length = 230, offset = 85, volume = 0.38 },
		{ id = "still_here", displayName = "Still Here", soundId = "rbxassetid://95862025875711", length = 210, offset = 25, volume = 0.4 },
		{ id = "velvet_dusk", displayName = "Velvet Dusk Harmony", soundId = "rbxassetid://74298742892359", length = 255, offset = 70, volume = 0.38 },
	},
}

function RadioStations.GetAll(): { RadioStation }
	return RadioStations.STATIONS
end

return RadioStations
