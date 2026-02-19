--[[
	BuildGridVisualizer Client Module
	
	Responsibility: Rendering the build grid and tile highlights.
	Uses PlotBounds_80x80 for alignment.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GridTopology = require(Shared:WaitForChild("GridTopology"))

local BuildGridVisualizer = {}

-- Config
local CONFIG = {
	TILE_SIZE = 10,
	TILE_HEIGHT = 0.1,
	EMPTY_COLOR = Color3.fromRGB(100, 100, 150),
	OCCUPIED_COLOR = Color3.fromRGB(80, 200, 80),
	HOVER_COLOR = Color3.fromRGB(100, 200, 255),
	INVALID_COLOR = Color3.fromRGB(255, 80, 80),
}

-- State
local gridContainer = nil
local gridTiles = {}
local gridFloorHeight = 0

--------------------------------------------------------------------------------
-- HELPERS
--------------------------------------------------------------------------------

local function createGridTile(slotIndex, cframe, isOccupied, unitName)
	local tile = Instance.new("Part")
	tile.Name = "BuildTile_" .. slotIndex
	tile.Size = Vector3.new(CONFIG.TILE_SIZE - 0.5, CONFIG.TILE_HEIGHT, CONFIG.TILE_SIZE - 0.5)
	tile.CFrame = cframe
	tile.Anchored = true
	tile.CanCollide = false
	tile.Transparency = 1  -- Fully invisible
	tile:SetAttribute("SlotIndex", slotIndex)
	tile:SetAttribute("IsOccupied", isOccupied)
	tile:SetAttribute("UnitName", unitName)
	
	-- Add border/outline effect
	local selectionBox = Instance.new("SelectionBox")
	selectionBox.Name = "Outline"
	selectionBox.Adornee = tile
	selectionBox.Color3 = isOccupied and CONFIG.OCCUPIED_COLOR or CONFIG.EMPTY_COLOR
	selectionBox.LineThickness = 0.03
	selectionBox.Transparency = 0.3
	selectionBox.Parent = tile
	
	-- Slot number label
	if not isOccupied then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "SlotLabel"
		billboard.Size = UDim2.new(1, 0, 0.5, 0)
		billboard.StudsOffset = Vector3.new(0, 0.5, 0)
		billboard.AlwaysOnTop = false
		billboard.Parent = tile
		
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = tostring(slotIndex)
		label.TextColor3 = Color3.fromRGB(150, 150, 150)
		label.TextScaled = true
		label.Font = Enum.Font.Gotham
		label.TextStrokeTransparency = 0.5
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.Parent = billboard
	end
	
	return tile
end

local function getPlotBoundsAndCFrame()
	-- Find player's plot
	local player = Players.LocalPlayer
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	
	local plot
	for _, p in plotsFolder:GetChildren() do
		if p:GetAttribute("OwnerId") == player.UserId then
			plot = p
			break
		end
	end
	
	if not plot then return nil end
	
	-- Prioritize PlotBounds_80x80
	local bounds = plot:FindFirstChild("PlotBounds_80x80")
	if bounds and bounds:IsA("BasePart") then
		return bounds.CFrame, bounds.Size
	end
	
	-- Fallback (should ideally not happen with new maps)
	local floor = plot:FindFirstChild("Island") or plot:FindFirstChild("PlotFloor")
	if floor and floor:IsA("BasePart") then return floor.CFrame, floor.Size end
	
	return nil
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function BuildGridVisualizer.Render(gridState)
	local plotCF, plotSize = getPlotBoundsAndCFrame()
	if not plotCF then return end
	
	gridFloorHeight = plotCF.Position.Y
	
	-- Clear old
	BuildGridVisualizer.Destroy()
	
	gridContainer = Instance.new("Folder")
	gridContainer.Name = "BuildModeGrid"
	gridContainer.Parent = workspace
	
	gridTiles = {}
	
	-- Create 16 tiles (Standard layout)
	for slotIndex = 1, 16 do
		local cframe = GridTopology.GetSlotCFrame(plotCF, plotSize, slotIndex, 0.1)
		
		-- FIX: Safely check for number key (1) OR string key ("1")
		local slotData = gridState.slots[slotIndex]
		if not slotData then
			slotData = gridState.slots[tostring(slotIndex)]
		end
		slotData = slotData or {}
		
		local unitName = nil
		if type(slotData) == "table" then
			-- Ensure we catch different naming conventions your database might use
			unitName = slotData.UnitName or slotData.unitType or slotData.unitName
		end
		
		local isOccupied = (unitName ~= nil)
		local tile = createGridTile(slotIndex, cframe, isOccupied, unitName)
		tile.Parent = gridContainer
		gridTiles[slotIndex] = tile
	end
	
	return plotCF.Position
end

function BuildGridVisualizer.Destroy()
	if gridContainer then
		gridContainer:Destroy()
		gridContainer = nil
		gridTiles = {}
	end
end

function BuildGridVisualizer.Highlight(slotIndex, color)
	local tile = gridTiles[slotIndex]
	if not tile then return end
	
	local outline = tile:FindFirstChild("Outline")
	if outline then
		outline.Color3 = color
		outline.Transparency = 0
	end
end

function BuildGridVisualizer.Unhighlight(slotIndex)
	local tile = gridTiles[slotIndex]
	if not tile then return end
	
	local isOccupied = tile:GetAttribute("IsOccupied")
	local outline = tile:FindFirstChild("Outline")
	if outline then
		outline.Color3 = isOccupied and CONFIG.OCCUPIED_COLOR or CONFIG.EMPTY_COLOR
		outline.Transparency = 0.3
	end
end

function BuildGridVisualizer.GetGridFloorHeight()
	return gridFloorHeight
end

function BuildGridVisualizer.GetTile(slotIndex)
	return gridTiles[slotIndex]
end

function BuildGridVisualizer.GetSlotUnderMouse()
	-- This assumes caller handles raycasting or we export tiles for raycast checks
	-- Pure visualizer shouldn't handle input, but exposing tiles helps.
	return gridTiles
end

return BuildGridVisualizer
