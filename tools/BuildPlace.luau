-- Run from the repository root with Lune 0.11.1: lune run tools/BuildPlace.luau
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local source = fs.readFile("MapGenerator.luau")
local config = luau.load(fs.readFile("MapConfig.luau"))()
local WORLD, ASSETS = "LarpTycoonMap", "LarpTycoonAssets"
local V = roblox.Vector3.new

local function applyGenerator(place, overrides)
	local runService = {
		IsStudio = function() return true end,
		IsRunning = function() return false end,
	}
	local environment = {
		game = {
			GetService = function(_, service)
				return if service == "RunService" then runService else place:GetService(service)
			end,
		},
		require = function(module)
			assert(module == place:GetService("ServerStorage").LarpTycoonMapConfig)
			return overrides
		end,
	}
	for _, key in { "Instance", "Enum", "Color3", "CFrame", "Vector3", "Vector2", "UDim2" } do
		environment[key] = roblox[key]
	end
	return luau.load(source, { environment = environment, debugName = "MapGenerator.luau" })()
end

local function near(value, expected)
	assert(math.abs(value - expected) < .002, string.format("%.6f ~= %.6f", value, expected))
end

local function namedChildren(parent, name)
	local count = 0
	for _, child in parent:GetChildren() do
		if child.Name == name then
			count += 1
		end
	end
	return count
end

local function checkWalkableRoutes(world, settings, spawn, roadCenter, plots)
	local obstacles = {}
	for _, part in world:GetDescendants() do
		if part:IsA("BasePart") and part.CanCollide then
			local frame = part.CFrame
			local half = part.Size / 2
			local yExtent = math.abs(frame.XVector.Y) * half.X + math.abs(frame.YVector.Y) * half.Y
				+ math.abs(frame.ZVector.Y) * half.Z
			if frame.Position.Y + yExtent > 1 and frame.Position.Y - yExtent < 2.25 then
				table.insert(obstacles, { frame, half })
			end
		end
	end
	local function walk(waypoints)
		for i = 2, #waypoints do
			local a, b = waypoints[i - 1], waypoints[i]
			local steps = math.max(1, math.ceil((b - a).Magnitude))
			for step = 0, steps do
				local point = a:Lerp(b, step / steps)
				for _, obstacle in obstacles do
					local position = obstacle[1]:PointToObjectSpace(point)
					local limits = obstacle[2]
					assert(math.abs(position.X) > limits.X + .9 or math.abs(position.Y) > limits.Y + .2
						or math.abs(position.Z) > limits.Z + .9, "Blocked pedestrian route: " .. tostring(point))
				end
			end
		end
	end
	local function point(x, z)
		return V(x, 2.05, z)
	end
	local start = point(0, spawn.CFrame.Position.Z)
	local edge = settings.PlazaDepth / 2 - 6
	walk({ start, point(0, 19), point(22, 19), point(22, -20), point(0, -20) })
	for _, side in { -1, 1 } do
		local walkZ = side * (roadCenter + settings.RoadWidth / 2 + settings.SidewalkWidth / 2)
		if side == -1 then
			walk({ start, point(0, edge), point(42, edge), point(42, -edge), point(0, -edge), point(0, walkZ) })
		else
			walk({ start, point(0, walkZ) })
		end
		for _, plot in plots do
			local pad = plot.Integration.ClaimPad.CFrame.Position
			if pad.Z * side > 0 then
				local foundation = plot.Site.Foundation.CFrame.Position
				walk({ point(0, walkZ), point(pad.X, walkZ), point(pad.X, pad.Z), point(foundation.X, foundation.Z) })
			end
		end
	end
end

local function checkGeometry(place, settings)
	local workspace = place:GetService("Workspace")
	local world = workspace[WORLD]
	local storage = place:GetService("ServerStorage")
	local assets = storage[ASSETS]
	local plots = world.Plots:GetChildren()
	assert(#plots == settings.PlotCount)
	assert(namedChildren(workspace, WORLD) == 1 and namedChildren(storage, ASSETS) == 1)
	for _, name in { "LarpTycoonSky", "LarpTycoonAtmosphere", "LarpTycoonBloom", "LarpTycoonColor" } do
		assert(namedChildren(place:GetService("Lighting"), name) == 1)
	end
	local spawn = world.Plaza["Arrival Court"].CentralSpawn
	assert(spawn:IsA("SpawnLocation") and spawn.Enabled and spawn.Neutral)
	assert(world.Plaza["Crown Fountain"] and world.Plaza["LARP STUDIO"])
	local roadCenter = settings.PlazaDepth / 2 + settings.SidewalkWidth + settings.RoadWidth / 2
	local plotStart = roadCenter + settings.RoadWidth / 2 + settings.SidewalkWidth
	local halfColumns = #plots / 2
	local seenColors = {}
	for _, plot in plots do
		local id = plot:GetAttribute("PlotId")
		local tint = plot:GetAttribute("AccentColor"):ToHex()
		assert(not seenColors[tint], "Repeated plot accent")
		seenColors[tint] = true
		local lot = plot.Site.Lot
			local entry = plot.Site.EntryWalk
		near(lot.Size.X, settings.PlotWidth)
		near(lot.Size.Z, settings.PlotDepth)
		local column = (id - 1) % halfColumns + 1
		near(lot.CFrame.Position.X, (column - (halfColumns + 1) / 2) * (settings.PlotWidth + settings.PlotGap))
		near(math.abs(lot.CFrame.Position.Z) - lot.Size.Z / 2, plotStart)
		assert(lot.CFrame.Position.Z * (entry.CFrame.Position.Z - lot.CFrame.Position.Z) < 0)
		near(math.abs(entry.CFrame.Position.Z) - entry.Size.Z / 2, plotStart)
		near(plot.Integration.PlotOrigin.CFrame:PointToObjectSpace(plot.Integration.ClaimPad.CFrame.Position).X, 0)
		assert(plot.Integration.OwnerSign.SignFace.Display.OwnerLabel:IsA("TextLabel"))
		assert(#plot.Unlocked:GetChildren() == 0)
		assert(plot:GetAttribute("UpgradeCapacity") == 64)
		for level = 1, 4 do
			local floorId = string.format("Floor%02d", level)
			local floor = plot.Sockets[floorId]
			local shell = assets.FloorShells[floorId]
			assert(#floor:GetChildren() == 16 and #assets.UpgradeModels[floorId]:GetChildren() == 16)
			near((shell.PrimaryPart.CFrame * shell.PrimaryPart.PivotOffset).Position.Magnitude, 0)
			for _, slot in floor:GetChildren() do
				local itemLocal = slot:GetAttribute("ItemCFrame").Position
				local buttonLocal = slot:GetAttribute("ButtonCFrame").Position
				local template = assets.UpgradeModels[floorId][slot.Name]
				assert(template:GetAttribute("DisplayName") == slot:GetAttribute("DisplayName"))
				assert(template:GetAttribute("Kind") == slot:GetAttribute("Kind"))
				near(itemLocal.Y, .5 + (level - 1) * 14)
				near(buttonLocal.Z, itemLocal.Z - 4.65)
				assert(math.abs(itemLocal.X) < 30 and itemLocal.Z <= 26 and itemLocal.Z >= -17)
				assert(#slot:GetChildren() == 0)
				near((template.PrimaryPart.CFrame * template.PrimaryPart.PivotOffset).Position.Magnitude, 0)
				local requires = template:GetAttribute("RequiresUpgradeId")
				if requires then
					local previous = floor[requires]:GetAttribute("ItemCFrame")
					near(previous.Position.Z, itemLocal.Z)
					near(previous.Position.X + 15, itemLocal.X)
				end
			end
			if level > 1 then
				local stair = shell.StairFromPreviousFloor
				assert(namedChildren(stair, "Tread") == 20)
				near(stair.Landing.CFrame.Position.X + stair.Landing.Size.X / 2, -shell.Deck.Size.X / 2)
				near(stair.Landing.CFrame.Position.Y + stair.Landing.Size.Y / 2, floor:GetAttribute("DeckY"))
				near(shell.Deck.CFrame.Position.Y + shell.Deck.Size.Y / 2, floor:GetAttribute("DeckY"))
			end
		end
	end
	local physicalParts, lights = 0, 0
	for _, root in { world, assets } do
		for _, instance in root:GetDescendants() do
			if instance:IsA("BasePart") then
				assert(instance.Anchored and not instance.CanTouch)
				assert(math.max(instance.Size.X, instance.Size.Y, instance.Size.Z) <= 2048)
				if root == world then
					physicalParts += 1
				end
			elseif instance:IsA("Light") then
				lights += 1
			elseif instance:IsA("LuaSourceContainer") then
				error("Unexpected executable source in generated content")
			end
		end
	end
	assert(lights == 6)
	checkWalkableRoutes(world, settings, spawn, roadCenter, plots)
	return #world:GetDescendants(), #assets:GetDescendants(), physicalParts
end

local place = roblox.Instance.new("DataModel")
local workspace = place:GetService("Workspace")
local control = roblox.Instance.new("Folder")
control.Name = "UnrelatedWorkspaceContent"
control.Parent = workspace
applyGenerator(place)
local worldCount, assetCount, partCount = checkGeometry(place, config)
local previousWorld = workspace[WORLD]
applyGenerator(place)
assert(control.Parent == workspace and previousWorld ~= workspace[WORLD])
local worldAgain, assetsAgain, partsAgain = checkGeometry(place, config)
assert(worldAgain == worldCount and assetsAgain == assetCount and partsAgain == partCount)
control:Destroy()

local configurable = roblox.Instance.new("DataModel")
local module = roblox.Instance.new("ModuleScript")
module.Name = "LarpTycoonMapConfig"
module.Parent = configurable:GetService("ServerStorage")
applyGenerator(configurable, config)
local configWorld, configAssets, configParts = checkGeometry(configurable, config)
assert(configWorld == worldCount and configAssets == assetCount and configParts == partCount)
local expanded = table.clone(config)
expanded.PlotCount, expanded.PlotWidth, expanded.PlotDepth, expanded.PlotGap = 16, 240, 240, 48
expanded.PlazaDepth, expanded.RoadWidth, expanded.SidewalkWidth, expanded.BorderWidth = 200, 32, 16, 48
applyGenerator(configurable, expanded)
checkGeometry(configurable, expanded)
local validWorld = configurable:GetService("Workspace")[WORLD]
local invalid = table.clone(expanded)
invalid.PlotCount = 7
assert(not pcall(applyGenerator, configurable, invalid))
assert(configurable:GetService("Workspace")[WORLD] == validWorld)

local placeXml = roblox.serializePlace(place, true)
local restored = roblox.deserializePlace(placeXml)
local restoredWorld, restoredAssets, restoredParts = checkGeometry(restored, config)
assert(restoredWorld == worldCount and restoredAssets == assetCount and restoredParts == partCount)
if process.args[1] == "--check" then
	assert(fs.readFile("LarpTycoon.rbxlx") == placeXml, "LarpTycoon.rbxlx must be rebuilt with this generator")
else
	assert(#process.args == 0, "Usage: lune run tools/BuildPlace.luau [--check]")
	fs.writeFile("LarpTycoon.rbxlx", placeXml)
end
print(string.format("Verified: %d world descendants (%d BaseParts), %d template descendants, six lights.", worldCount, partCount, assetCount))
