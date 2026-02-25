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
	
	local myPlot = ClientPlotService.GetMyPlot()
	if not myPlot then return false end
	
	local floor = myPlot:FindFirstChild("Island")
		or myPlot:FindFirstChild("PlotFloor")
		or myPlot:FindFirstChild("Floor")
		or myPlot:FindFirstChildWhichIsA("BasePart")
	
	if floor then
		local floorPos = floor.Position
		local floorSize = floor.Size
		
		-- Check if position is within plot bounds (XZ)
		local dx = math.abs(pos.X - floorPos.X)
		local dz = math.abs(pos.Z - floorPos.Z)
		
		if dx <= floorSize.X / 2 + 10 and dz <= floorSize.Z / 2 + 10 then
			return true
		end
	end
	
	return false
end

return ClientPlotService
