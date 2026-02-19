--[[
	ShopInteraction Module
	
	Shared logic for handling:
	- ProximityPrompt interactions
	- Keybind interactions (E to open/close)
	- Distance checks (using Pivot to support Models)
	- UI toggling
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer

local ShopInteraction = {}
ShopInteraction.__index = ShopInteraction

export type ShopConfig = {
	PromptTag: string,        -- Tag on the shop model/part (e.g., "IslandShopVendor")
	InteractionDist: number?, -- Max distance to keep shop open (default: 20)
	Keybind: Enum.KeyCode?,   -- Key to toggle shop (default: E)
	OnOpen: () -> (),         -- Callback when shop opens
	OnClose: () -> (),        -- Callback when shop closes
}

function ShopInteraction.new(config: ShopConfig)
	local self = setmetatable({}, ShopInteraction)
	
	self.Config = config
	self.Config.InteractionDist = config.InteractionDist or 20
	self.Config.Keybind = config.Keybind or Enum.KeyCode.E
	
	self.IsOpen = false
	self.Connections = {}
	
	self:Init()
	
	return self
end

function ShopInteraction:Init()
	-- 1. ProximityPrompt Listener
	self:SetupPromptListener()
	
	-- 2. Input Listener (Hotkeys)
	table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == self.Config.Keybind then
			if self.IsOpen then
				self:Close()
			else
				-- Check if near any vendor of this type
				if self:IsNearVendor() then
					self:Open()
				end
			end
		elseif input.KeyCode == Enum.KeyCode.Escape then
			if self.IsOpen then
				self:Close()
			end
		end
	end))
	
	-- 3. Distance Check Loop (Heartbeat) - Only runs when shop is open
	table.insert(self.Connections, RunService.Heartbeat:Connect(function()
		if not self.IsOpen then return end
		
		if not self:IsNearVendor() then
			self:Close()
		end
	end))
end

function ShopInteraction:SetupPromptListener()
	local function onInstanceAdded(instance)
		if not instance:IsDescendantOf(workspace) then return end
		
		print("[ShopInteraction] Found potential vendor:", instance.Name, "for tag:", self.Config.PromptTag)
		
		-- Wait for prompt to exist (it might be added by server script slightly after tag)
		local prompt = instance:WaitForChild("ShopPrompt", 10)
		if prompt and prompt:IsA("ProximityPrompt") then
			print("[ShopInteraction] Found ShopPrompt for:", instance.Name)
			table.insert(self.Connections, prompt.Triggered:Connect(function(playerWhoTriggered)
				if playerWhoTriggered == Player then
					print("[ShopInteraction] Prompt triggered by local player for:", instance.Name)
					self:Toggle()
				end
			end))
		else
			warn("[ShopInteraction] ShopPrompt NOT found or not a ProximityPrompt for:", instance.Name)
		end
	end

	-- Listen for existing
	for _, instance in CollectionService:GetTagged(self.Config.PromptTag) do
		onInstanceAdded(instance)
	end
	
	-- Listen for new
	table.insert(self.Connections, CollectionService:GetInstanceAddedSignal(self.Config.PromptTag):Connect(onInstanceAdded))
end

function ShopInteraction:IsNearVendor()
	local char = Player.Character
	if not char then return false end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end
	
	local myPos = hrp.Position
	
	for _, vendor in CollectionService:GetTagged(self.Config.PromptTag) do
		-- Use GetPivot() to safely get position of Parts OR Models
		local vendorPos
		if vendor:IsA("Model") then
			vendorPos = vendor:GetPivot().Position
		elseif vendor:IsA("BasePart") then
			vendorPos = vendor.Position
		else
			continue
		end
		
		if (vendorPos - myPos).Magnitude <= self.Config.InteractionDist then
			return true
		end
	end
	
	return false
end

function ShopInteraction:Toggle()
	if self.IsOpen then
		self:Close()
	else
		self:Open()
	end
end

function ShopInteraction:Open()
	if self.IsOpen then return end
	self.IsOpen = true
	if self.Config.OnOpen then self.Config.OnOpen() end
end

function ShopInteraction:Close()
	if not self.IsOpen then return end
	self.IsOpen = false
	if self.Config.OnClose then self.Config.OnClose() end
end

function ShopInteraction:Destroy()
	for _, conn in self.Connections do
		conn:Disconnect()
	end
	self.Connections = {}
end

return ShopInteraction
