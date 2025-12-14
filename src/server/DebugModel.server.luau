local ReplicatedStorage = game:GetService("ReplicatedStorage")
local brainrots = ReplicatedStorage:WaitForChild("Brainrots")

local unitName = "Avocadini Guffo"
local model = brainrots:FindFirstChild(unitName)

print("DEBUG: Inspecting " .. unitName)
if model then
	print("  Class:", model.ClassName)
	print("  Children count:", #model:GetChildren())
	for _, child in model:GetChildren() do
		print("    - " .. child.Name .. " (" .. child.ClassName .. ")")
	end
else
	warn("  Model not found in Brainrots folder!")
end

-- Also check if Assets folder exists
local assets = ReplicatedStorage:FindFirstChild("Assets")
if assets then
	print("DEBUG: Assets folder found")
	local brainrotsAssets = assets:FindFirstChild("Brainrots")
	if brainrotsAssets then
		print("DEBUG: Assets/Brainrots folder found")
		local assetModel = brainrotsAssets:FindFirstChild(unitName)
		if assetModel then
			print("DEBUG: Found visual model in Assets/Brainrots!")
		else
			print("DEBUG: Model NOT found in Assets/Brainrots")
		end
	else
		print("DEBUG: Assets/Brainrots folder NOT found")
	end
else
	print("DEBUG: Assets folder NOT found")
end
