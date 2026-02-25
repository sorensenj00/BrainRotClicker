local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIManager = {
	_shops = {}
}

function UIManager.RegisterShop(shopName, toggleFunc)
	UIManager._shops[shopName] = toggleFunc
end

function UIManager.ToggleShop(shopName)
	if UIManager._shops[shopName] then
		UIManager._shops[shopName]()
	else
		warn("UIManager: Shop not found or not registered - " .. tostring(shopName))
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
