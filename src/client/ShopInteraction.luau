--[[
	ShopInteraction Module
	
	Shared logic for handling:
	- ProximityPrompt interactions
	- Keybind interactions (E to open/close)
	- Distance checks (using Pivot to support Models)
	- UI toggling
]]

local _UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

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
	
	-- 2. Input Listener (Hotkeys) - REMOVED for mobile compatibility and to prevent double-firing with ProximityPrompt
	
	-- 3. Distance Check Loop (Heartbeat) - Only runs when shop is open
	table.insert(self.Connections, RunService.Heartbeat:Connect(function()
		if not self.IsOpen then return end
		
		if not self:IsNearVendor() then
			self:Close()
		end
	end))
end

function ShopInteraction:SetupPromptListener()
	local function resolvePrompt(instance: Instance): ProximityPrompt?
		if instance:IsA("ProximityPrompt") then
			return instance
		end
		local named = instance:FindFirstChild("ShopPrompt", true)
		if named and named:IsA("ProximityPrompt") then
			return named
		end
		return instance:FindFirstChildWhichIsA("ProximityPrompt", true)
	end

	local function onInstanceAdded(instance)
		if not instance:IsDescendantOf(workspace) then return end
		
		print("[ShopInteraction] Found potential vendor:", instance.Name, "for tag:", self.Config.PromptTag)
		
		task.spawn(function()
			local prompt
			for _ = 1, 20 do
				prompt = resolvePrompt(instance)
				if prompt then break end
				task.wait(0.5)
			end
			
			if prompt and prompt:IsA("ProximityPrompt") then
				print("[ShopInteraction] Found ShopPrompt for:", instance.Name)
				table.insert(self.Connections, prompt.Triggered:Connect(function(playerWhoTriggered)
					local isLocalTrigger = (playerWhoTriggered == nil) or (playerWhoTriggered == Player)
					if isLocalTrigger then
						print("[ShopInteraction] Prompt triggered by local player for:", instance.Name)
						self:Toggle()
					end
				end))
			else
				warn("[ShopInteraction] ShopPrompt NOT found or not a ProximityPrompt for:", instance.Name)
			end
		end)
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
		local prompt: ProximityPrompt?
		if vendor:IsA("ProximityPrompt") then
			prompt = vendor
		else
			local named = vendor:FindFirstChild("ShopPrompt", true)
			if named and named:IsA("ProximityPrompt") then
				prompt = named
			else
				prompt = vendor:FindFirstChildWhichIsA("ProximityPrompt", true)
			end
		end

		local promptWorldPos: Vector3? = nil
		if prompt then
			local holder = prompt.Parent
			if holder and holder:IsA("Attachment") then
				holder = holder.Parent
			end
			if holder and holder:IsA("BasePart") then
				promptWorldPos = holder.Position
			elseif prompt.Adornee and prompt.Adornee:IsA("BasePart") then
				promptWorldPos = prompt.Adornee.Position
			end
		end

		if promptWorldPos then
			if (promptWorldPos - myPos).Magnitude <= (self.Config.InteractionDist + 5) then
				return true
			end
		else
			-- Use GetPivot() to safely get position of Parts OR Models as fallback
			local vendorPos
			if vendor:IsA("Model") then
				vendorPos = vendor:GetPivot().Position
			elseif vendor:IsA("BasePart") then
				vendorPos = vendor.Position
			else
				continue
			end
			
			if (vendorPos - myPos).Magnitude <= (self.Config.InteractionDist + 5) then
				return true
			end
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
