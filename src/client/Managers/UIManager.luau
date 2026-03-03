local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIManager = {
	_shops = {},
	_pending = {},
}

local function normalizeShopName(name: any): string
	local s = string.lower(tostring(name or ""))
	s = string.gsub(s, "[%s_%-]", "")
	return s
end

local SHOP_ALIASES = {
	cart = "cartshop",
	cartupgrades = "cartshop",
	island = "islandshop",
	islandupgrades = "islandshop",
	machine = "machineshop",
	unit = "machineshop",
	unitshop = "machineshop",
	storage = "storageupgrades",
	convenience = "convenienceupgrades",
	artifact = "artifactexchange",
}

local function resolveShopKey(rawName: any): string
	local key = normalizeShopName(rawName)
	return SHOP_ALIASES[key] or key
end

function UIManager.RegisterShop(shopName, toggleFunc)
	local key = resolveShopKey(shopName)
	UIManager._shops[key] = toggleFunc

	-- Replay queued opens that arrived before this shop script initialized.
	local pendingCount = UIManager._pending[key]
	if pendingCount and pendingCount > 0 then
		UIManager._pending[key] = nil
		for _ = 1, pendingCount do
			toggleFunc()
		end
	end
end

function UIManager.ToggleShop(shopName)
	local key = resolveShopKey(shopName)
	if UIManager._shops[key] then
		UIManager._shops[key]()
	else
		-- Queue request so it can fire once the UI script registers.
		UIManager._pending[key] = (UIManager._pending[key] or 0) + 1
		warn("UIManager: Shop not found yet, queued open - " .. tostring(shopName))
	end
end

local function initialize()
	-- Listen to the global admin event
	local adminEvent = ReplicatedStorage:WaitForChild("AdminOpenShop", 5)
	if adminEvent then
		adminEvent.Event:Connect(function(shopName)
			UIManager.ToggleShop(shopName)
		end)
	end
end

task.spawn(initialize)

return UIManager
