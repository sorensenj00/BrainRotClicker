--[[
	ArtifactUpgradeConfig - Shared Configuration for Artifact Upgrades

	Defines the 5-to-1 rarity upgrade chain and vendor constants.
]]

local ArtifactUpgradeConfig = {}

ArtifactUpgradeConfig.REQUIRED_COUNT = 5
ArtifactUpgradeConfig.VENDOR_TAG = "ArtifactUpgradeVendor"
ArtifactUpgradeConfig.VENDOR_DISTANCE = 20

ArtifactUpgradeConfig.RARITY_ORDER = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
}

ArtifactUpgradeConfig.UPGRADE_CHAIN = {
	Common = "Uncommon",
	Uncommon = "Rare",
	Rare = "Epic",
	Epic = "Legendary",
}

function ArtifactUpgradeConfig.GetNextRarity(rarity)
	return ArtifactUpgradeConfig.UPGRADE_CHAIN[rarity]
end

function ArtifactUpgradeConfig.CanUpgradeRarity(rarity)
	return ArtifactUpgradeConfig.GetNextRarity(rarity) ~= nil
end

return ArtifactUpgradeConfig
