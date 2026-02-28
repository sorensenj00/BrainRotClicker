local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ClientPlotService = {}

function ClientPlotService.GetMyPlot()
	local player = Players.LocalPlayer
	if not player then return nil end
	
	local plotsFolder = Workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	
	for _, plot in plotsFolder:GetChildren() do
		local ownerId = plot:GetAttribute("OwnerId")
		if ownerId == player.UserId then
			return plot
		end
	end
	
	return nil
end

function ClientPlotService.GetMyPlots()
	local player = Players.LocalPlayer
	if not player then return {} end
	
	local plotsFolder = Workspace:FindFirstChild("Plots")
	if not plotsFolder then return {} end
	
	local myPlots = {}
	for _, plot in plotsFolder:GetChildren() do
		local ownerId = plot:GetAttribute("OwnerId")
		if ownerId == player.UserId then
			table.insert(myPlots, plot)
		end
	end
	
	return myPlots
end

function ClientPlotService.IsOnMyIsland(playerPos)
	local player = Players.LocalPlayer
	if not player then return false end
	
	-- Support passing an optional position, else use HumanoidRootPart
	local pos = playerPos
	if not pos then
		local character = player.Character
		if not character then return false end
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then return false end
		pos = hrp.Position
	end
	
	local myPlots = ClientPlotService.GetMyPlots()
	if #myPlots == 0 then return false end
	
	for _, plot in myPlots do
		local root = plot.PrimaryPart or plot:FindFirstChild("Root") or plot:FindFirstChild("MainPlatform") or plot:FindFirstChildWhichIsA("BasePart")
		if root then
			local plotPos = root.Position
			
			-- The main platform is a cylinder of radius 60. 
			-- Check if the player is within a 70 stud radius (including a small buffer)
			local dx = pos.X - plotPos.X
			local dz = pos.Z - plotPos.Z
			
			if dx*dx + dz*dz <= 70 * 70 then
				return true
			end
		end
	end
	
	return false
end

return ClientPlotService
