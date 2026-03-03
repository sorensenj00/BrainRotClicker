--[[
	DroneOpsConfig Shared Module

	Central configuration for drone buff/nerf abilities.
]]

local DroneOpsConfig = {}

DroneOpsConfig.SECTORS = {
	"Food",
	"Animals",
	"Entertainment",
	"Mystic",
	"Tech",
	"Action",
}

DroneOpsConfig.ABILITIES = {
	EMP = {
		cooldown = 90,
		duration = 30,
		productionMultiplier = 0.5, -- 50% output -> 2x interval
		type = "offense",
	},
	BLOCKADE = {
		cooldown = 80,
		duration = 20,
		cartSpeedMultiplier = 0.25, -- 75% slower cart
		type = "offense",
	},
	SCOUT = {
		cooldown = 45,
		type = "intel",
	},
	OVERCLOCK = {
		cooldown = 90,
		duration = 30,
		productionMultiplier = 1.25,
		fatigueDuration = 10,
		fatigueMultiplier = 0.9,
		type = "support",
	},
}

DroneOpsConfig.GUARDRAILS = {
	sharedOffenseCooldown = 15,
	targetImmunitySeconds = 25,
	maxTargetSectorDebuffs = 1,
}

DroneOpsConfig.DRONE = {
	speedStudsPerSecond = 120,
	spawnHeight = 8,
	impactParticleLifetime = 2.5,
}

return DroneOpsConfig
