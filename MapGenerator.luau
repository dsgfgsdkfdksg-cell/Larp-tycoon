-- LARP Studio | Paste this entire file into the Roblox Studio Command Bar in Edit mode.
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
assert(RunService:IsStudio() and not RunService:IsRunning(), "Run from the Studio Command Bar in Edit mode")

local WORLD_NAME = "LarpTycoonMap"
local ASSET_NAME = "LarpTycoonAssets"
local SIGNATURE = "LARP Studio / MapGenerator"
local VERSION = 1

local config = {
	PlotCount = 8,
	PlotWidth = 104,
	PlotDepth = 104,
	PlotGap = 12,
	PlazaDepth = 100,
	RoadWidth = 18,
	SidewalkWidth = 8,
	BorderWidth = 24,
	Brand = { Red = "#E32F43", White = "#F2F2EB", Gold = "#F8BE5B" },
	PlotColors = { "#FF586C", "#54D9FA", "#FFBD63", "#A28AFF", "#6FE795", "#F483CF", "#799DFF", "#F6E974" },
}
local configModule = ServerStorage:FindFirstChild("LarpTycoonMapConfig")
if configModule then
	assert(configModule:IsA("ModuleScript"), "LarpTycoonMapConfig must be a ModuleScript")
	local overrides = require(configModule)
	assert(type(overrides) == "table", "LarpTycoonMapConfig must return a table")
	for key, value in pairs(overrides) do
		assert(config[key] ~= nil, "Unknown map setting: " .. tostring(key))
		config[key] = value
	end
end

local function checkSize(key, minimum, maximum)
	local value = config[key]
	assert(type(value) == "number" and value >= minimum and value <= maximum,
		string.format("%s must be between %d and %d", key, minimum, maximum))
end

checkSize("PlotCount", 2, 16)
assert(config.PlotCount % 2 == 0, "PlotCount must be even")
checkSize("PlotWidth", 104, 240)
checkSize("PlotDepth", 104, 240)
checkSize("PlotGap", 12, 48)
checkSize("PlazaDepth", 100, 200)
checkSize("RoadWidth", 16, 32)
checkSize("SidewalkWidth", 8, 16)
checkSize("BorderWidth", 20, 48)

local function color(hex)
	assert(type(hex) == "string" and string.match(hex, "^#%x%x%x%x%x%x$"), "Colors must use #RRGGBB")
	return Color3.fromHex(hex)
end

local C = {
	Red = color(config.Brand.Red), White = color(config.Brand.White), Gold = color(config.Brand.Gold),
	Ink = color("#151C27"), Steel = color("#303E50"), Trim = color("#52647B"),
	Asphalt = color("#252E3A"), Paving = color("#ABB6BE"), Stone = color("#737F8D"),
	Lawn = color("#426853"), Hedge = color("#284D40"), Leaf = color("#4D8763"),
	LeafLight = color("#77A66C"), Bark = color("#534233"), Glass = color("#81A9BE"),
	Water = color("#47C7EC"), Foam = color("#ADF6FF"),
}
local accents = {}
local palette = config.PlotColors
assert(type(palette) == "table" and #palette > 0, "Provide at least one plot color")
local usedAccents = {}
for i = 1, config.PlotCount do
	local accent = if i <= #palette then color(palette[i]) else Color3.fromHSV((i * 0.618034) % 1, 0.62, 1)
	local hex = accent:ToHex()
	assert(not usedAccents[hex], "Each plot must have a different accent color: #" .. hex)
	usedAccents[hex] = true
	accents[i] = accent
end

local V = Vector3.new
local CF = CFrame.new
local M = Enum.Material
local IDENTITY = CF()
local FLOOR_HEIGHT = 14
local DECK = 0.5
local BUILD_WIDTH = 64
local BUILD_DEPTH = 60
local BUILD_CENTER_Z = 6
local STAIR_RISE = FLOOR_HEIGHT / 20
local STAIR_RUN = 1.5
local columns = config.PlotCount / 2
local pitch = config.PlotWidth + config.PlotGap
local halfPlaza = config.PlazaDepth / 2
local roadZ = halfPlaza + config.SidewalkWidth + config.RoadWidth / 2
local innerPlot = roadZ + config.RoadWidth / 2 + config.SidewalkWidth
local plotZ = innerPlot + config.PlotDepth / 2
local halfX = math.max((columns * pitch - config.PlotGap) / 2, 75) + config.BorderWidth
local halfZ = innerPlot + config.PlotDepth + config.BorderWidth
local outerCrossingX = math.min(halfX - 40, pitch)
local signTextColor = C.White

local function object(class, parent, name, properties)
	local instance = Instance.new(class)
	instance.Name = name
	for property, value in pairs(properties or {}) do
		instance[property] = value
	end
	instance.Parent = parent
	return instance
end

local function folder(parent, name)
	return object("Folder", parent, name)
end

local function model(parent, name)
	return object("Model", parent, name)
end

local function block(parent, frame, name, size, x, y, z, tint, material, options)
	local properties = {
		Size = size,
		CFrame = frame * CF(x, y, z) * (options and options.rotation or IDENTITY),
		Anchored = true,
		CanCollide = not options or options.collide ~= false,
		CanTouch = options ~= nil and options.touch == true,
		CastShadow = not options or options.shadow ~= false,
		Color = tint,
		Material = material or M.SmoothPlastic,
		Transparency = options and options.transparency or 0,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
	}
	if options and options.shape then
		properties.Shape = options.shape
	end
	local part = object(options and options.class or "Part", parent, name, properties)
	if options and options.query == false then
		assert(not part.CanCollide, "CanQuery can be disabled only on non-collidable parts")
		part.CanQuery = false
	end
	return part
end

local DETAIL = { collide = false, query = false, shadow = false }
local GHOST = { collide = false, query = false, shadow = false, transparency = 1 }
local GLASS = { transparency = 0.4, shadow = false }
local BALL = { shape = Enum.PartType.Ball, collide = false, query = false }
local function cylinder(parent, frame, name, diameter, height, x, y, z, tint, material, options)
	local settings = table.clone(options or {})
	settings.shape = Enum.PartType.Cylinder
	settings.rotation = CFrame.Angles(0, 0, math.pi / 2)
	return block(parent, frame, name, V(height, diameter, diameter), x, y, z, tint, material, settings)
end

local function label(part, name, text, tint)
	local panel = object("SurfaceGui", part, "Display", {
		Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = Vector2.new(640, 200), LightInfluence = 0, MaxDistance = 165,
	})
	return object("TextLabel", panel, name, {
		BackgroundTransparency = 1, Position = UDim2.fromScale(0.035, 0.06),
		Size = UDim2.fromScale(0.93, 0.88), Text = text, TextColor3 = tint or signTextColor,
		TextWrapped = true, TextScaled = true, Font = Enum.Font.GothamBold,
	})
end

local function sign(parent, frame, name, text, tint, width, height)
	local post = model(parent, name)
	for _, x in ipairs({ -width * .38, width * .38 }) do
		block(post, frame, "Support", V(.5, 3.6, .5), x, 1.8, 0, C.Steel, M.Metal)
	end
	local face = block(post, frame, "SignFace", V(width, height, .55), 0, 3.35, 0, C.Ink, M.Metal)
	block(post, frame, "Accent", V(width, .17, .57), 0, 3.35 - height / 2, 0, tint, M.Neon, DETAIL)
	return post, label(face, if name == "OwnerSign" then "OwnerLabel" else "Label", text)
end

local function tree(parent, frame, x, z, scale)
	local planting = model(parent, "Linden")
	cylinder(planting, frame, "Trunk", .75 * scale, 7 * scale, x, 3.5 * scale, z, C.Bark, M.Wood)
	block(planting, frame, "Canopy", V(7, 8, 7) * scale, x, 8.6 * scale, z, C.Leaf, M.Grass, BALL)
	block(planting, frame, "Crown", V(5.4, 5.1, 5.5) * scale,
		x + 1.25 * scale, 10 * scale, z - .6 * scale, C.LeafLight, M.Grass, BALL)
end

local function planter(parent, frame, x, z, length)
	local box = model(parent, "Planter")
	block(box, frame, "Curb", V(length, .65, 3.5), x, .325, z, C.Stone, M.Concrete)
	block(box, frame, "Soil", V(length - .5, .12, 3), x, .68, z, C.Hedge, M.Grass, DETAIL)
	for i = -1, 1 do
		block(box, frame, "Shrub", V(length / 3, 1.6, 2.75), x + i * length / 3, 1.37, z,
			if i == 0 then C.LeafLight else C.Leaf, M.Grass, BALL)
	end
end

local function bench(parent, frame)
	local seat = model(parent, "Bench")
	for _, x in ipairs({ -2.3, 2.3 }) do
		block(seat, frame, "Foot", V(.45, 1.4, 1.35), x, .7, 0, C.Steel, M.Metal)
	end
	block(seat, frame, "Seat", V(6, .24, 1.72), 0, 1.47, 0, color("#B37750"), M.WoodPlanks)
	block(seat, frame, "Back", V(6, .8, .25), 0, 2.07, .78, color("#B37750"), M.WoodPlanks)
end

local function lamp(parent, frame, withLight)
	local post = model(parent, "Streetlight")
	block(post, frame, "Pedestal", V(1.25, .65, 1.25), 0, .325, 0, C.Stone, M.Concrete)
	block(post, frame, "Pole", V(.44, 10, .44), 0, 5, 0, C.Ink, M.Metal)
	block(post, frame, "Bracket", V(2.55, .22, .56), .95, 9.8, 0, C.Ink, M.Metal)
	local emitter = block(post, frame, "Diffuser", V(1.55, .13, .45), 1.3, 9.63, 0, C.Gold, M.Neon, DETAIL)
	if withLight then
		object("PointLight", emitter, "WarmLight", { Color = C.Gold, Range = 16, Brightness = 1.2, Shadows = false })
	end
end

local function longStrip(parent, name, x, y, z, length, height, width, tint, material, options)
	local sections = math.ceil(length / 500)
	local section = length / sections
	for i = 1, sections do
		block(parent, IDENTITY, name, V(section, height, width), x - length / 2 + (i - .5) * section, y, z,
			tint, material, options)
	end
end

local function buildStreet(parent)
	local streets = folder(parent, "Streets")
	local apronX = halfX - config.BorderWidth + 4
	local endRadius = config.RoadWidth / 2
	local function crossingAt(x)
		return math.abs(x) < 6.4 or math.abs(math.abs(x) - outerCrossingX) < 6.4
	end
	for _, direction in ipairs({ -1, 1 }) do
		local z = roadZ * direction
		longStrip(streets, "Roadbed", 0, .11, z, apronX * 2, .22, config.RoadWidth, C.Asphalt, M.Asphalt)
		for _, endSign in ipairs({ -1, 1 }) do
			cylinder(streets, IDENTITY, "RoadEnd", config.RoadWidth, .22, endSign * apronX, .11, z, C.Asphalt, M.Asphalt)
		end
		for x = -math.floor((apronX - endRadius) / 16) * 16, apronX - endRadius, 16 do
			if not crossingAt(x) then
				block(streets, IDENTITY, "LaneDash", V(5.1, .028, .18), x, .235, z, C.Gold, nil, DETAIL)
			end
		end
		for _, offset in ipairs({ -1, 1 }) do
			local walkZ = z + offset * (endRadius + config.SidewalkWidth / 2)
			longStrip(streets, "Sidewalk", 0, .16, walkZ, (apronX + 4) * 2, .32, config.SidewalkWidth, C.Paving, M.Pavement)
			longStrip(streets, "CurbInlay", 0, .33, walkZ - offset * (config.SidewalkWidth / 2 - .38),
				apronX * 2, .028, .3, C.Stone, nil, DETAIL)
		end
		for _, crossingX in ipairs({ -outerCrossingX, 0, outerCrossingX }) do
			for stripe = -3, 3 do
				block(streets, IDENTITY, "ZebraStripe", V(.65, .028, config.RoadWidth - 1.6),
					crossingX + stripe * 1.15, .237, z, C.White, nil, DETAIL)
			end
		end
	end
	return streets
end

local GLYPHS = {
	L = { "10000", "10000", "10000", "10000", "10000", "10000", "11111" },
	A = { "01110", "11011", "10001", "10001", "11111", "10001", "10001" },
	R = { "11110", "10001", "10001", "11110", "10100", "10010", "10001" },
	P = { "11110", "10001", "10001", "11110", "10000", "10000", "10000" },
	S = { "01111", "10000", "10000", "01110", "00001", "00001", "11110" },
	T = { "11111", "00100", "00100", "00100", "00100", "00100", "00100" },
	U = { "10001", "10001", "10001", "10001", "10001", "10001", "01110" },
	D = { "11110", "10001", "10001", "10001", "10001", "10001", "11110" },
	I = { "11111", "00100", "00100", "00100", "00100", "00100", "11111" },
	O = { "01110", "10001", "10001", "10001", "10001", "10001", "01110" },
}

local function buildLogo(parent, z)
	local sculpture = model(parent, "LARP STUDIO")
	local frame = CF(0, .36, z) * CFrame.Angles(0, math.pi, 0)
	block(sculpture, frame, "Plinth", V(64, 1.15, 4.5), 0, .575, 0, C.Ink, M.Metal)
	block(sculpture, frame, "GoldSeam", V(63.2, .11, 4.52), 0, .91, 0, C.Gold, M.Neon, DETAIL)
	local phrase = "LARP STUDIO"
	local cursor = -31.5
	for i = 1, #phrase do
		local glyph = GLYPHS[string.sub(phrase, i, i)]
		if glyph then
			for row, line in ipairs(glyph) do
				for first, run in string.gmatch(line, "()(1+)") do
					local width = #run
					block(sculpture, frame, "LetterStroke", V(width, 1, 1.5),
						cursor + first - 1 + width / 2, 1.15 + 7.5 - row, 0,
						if i <= 4 then C.Red else C.White, M.Metal)
				end
			end
			cursor += 6
		else
			cursor += 4
		end
	end
end

local function buildFountain(parent)
	local fountain = model(parent, "Crown Fountain")
	cylinder(fountain, IDENTITY, "Plinth", 30, .48, 0, .57, 0, C.Ink, M.Concrete)
	cylinder(fountain, IDENTITY, "GoldBowlRim", 27.4, .86, 0, 1.17, 0, C.Gold, M.Metal)
	cylinder(fountain, IDENTITY, "BasinInset", 25.7, .1, 0, 1.607, 0, C.Water, M.Glass, DETAIL)
	cylinder(fountain, IDENTITY, "SculptureBase", 7.2, .44, 0, 1.77, 0, C.Steel, M.Metal)
	cylinder(fountain, IDENTITY, "Column", 2.3, 3.5, 0, 3.55, 0, C.Ink, M.Metal)
	cylinder(fountain, IDENTITY, "UpperBowl", 6.8, .6, 0, 5.52, 0, C.Gold, M.Metal)
	cylinder(fountain, IDENTITY, "UpperWater", 5.9, .08, 0, 5.856, 0, C.Foam, M.Glass, DETAIL)
	for i = 0, 7 do
		local angle = i * math.pi / 4
		local jetFrame = CFrame.Angles(0, angle, 0)
		for step = 0, 6 do
			local u, v = step / 7, (step + 1) / 7
			local a = jetFrame * V(2.12 + 7.8 * u, 5.86 + 6.5 * u - 10.75 * u * u, 0)
			local b = jetFrame * V(2.12 + 7.8 * v, 5.86 + 6.5 * v - 10.75 * v * v, 0)
			block(fountain, CFrame.lookAt((a + b) / 2, b), "WaterArc", V(.16, .16, (b - a).Magnitude + .04),
				0, 0, 0, if i % 2 == 0 then C.Foam else C.Water, M.Neon, DETAIL)
		end
	end
end

local function buildPlaza(parent)
	local plaza = folder(parent, "Plaza")
	local pavedX = math.min(halfX - config.BorderWidth - 2, 76)
	block(plaza, IDENTITY, "Promenade", V(pavedX * 2, .36, config.PlazaDepth), 0, .18, 0, C.Paving, M.Pavement)
	for _, side in ipairs({ -1, 1 }) do
		if outerCrossingX + 4 > pavedX then
			local linkWidth = outerCrossingX + 4 - pavedX
			for _, endSign in ipairs({ -1, 1 }) do
				block(plaza, IDENTITY, "CrossingLink", V(linkWidth, .32, 8), side * (pavedX + linkWidth / 2),
					.16, endSign * (halfPlaza - 4), C.Paving, M.Pavement)
			end
		end
		block(plaza, IDENTITY, "LongInlay", V(.22, .025, config.PlazaDepth - 2), side * 20, .375, 0, C.Trim, nil, DETAIL)
		for _, z in ipairs({ -16, 16 }) do
			block(plaza, IDENTITY, "CourtInlay", V(17, .025, .22), side * 28.6, .375, z, C.Trim, nil, DETAIL)
		end
		for _, z in ipairs({ -29, 1, 32 }) do
			local x = side * 52
			planter(plaza, CF(0, .36, 0), x, z, 10)
			tree(plaza, CF(0, .36, 0), x, z, .9)
			lamp(plaza, CF(side * 36, .36, z) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0), true)
		end
		for _, z in ipairs({ -8, 10 }) do
			bench(plaza, CF(side * 30.5, .36, z) * CFrame.Angles(0, side * math.pi / 2, 0))
		end
	end
	buildFountain(plaza)
	buildLogo(plaza, -33)

	local arrivals = model(plaza, "Arrival Court")
	cylinder(arrivals, IDENTITY, "ArrivalMedallion", 22, .14, 0, .41, 32, C.Ink, M.Metal)
	cylinder(arrivals, IDENTITY, "MedallionInlay", 19, .055, 0, .478, 32, C.Red, M.Metal)
	local spawn = block(arrivals, IDENTITY, "CentralSpawn", V(13, .12, 11), 0, .57, 32, C.Ink, M.SmoothPlastic,
		{ class = "SpawnLocation" })
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Duration = 0
	for _, x in ipairs({ -17, 17 }) do
		sign(arrivals, CF(x, .36, 33) * CFrame.Angles(0, math.pi, 0), "Directory",
			"LARP TYCOON\nPLOTS ACROSS BOTH AVENUES", C.Gold, 12, 2.8)
	end
end

local CATALOG = {
	{
		"Ore Hopper", "Starter Conveyor", "Basic Sorter", "Cash Collector",
		"Twin Hopper", "Roller Conveyor", "Metal Press", "Press Collector",
		"Gravel Feeder", "Wide Conveyor", "Ore Purifier", "Refinery Collector",
		"Tool Rack", "Safety Barrier", "Reception Desk", "Lobby Planter",
	},
	{
		"Steel Feeder", "Steel Conveyor", "Hydraulic Press", "Steel Collector",
		"Alloy Hopper", "Sealed Conveyor", "Alloy Furnace", "Alloy Collector",
		"Supply Feeder", "Fast Conveyor", "Quality Scanner", "Supply Collector",
		"Control Desk", "Glass Divider", "Sample Cabinet", "Atrium Planter",
	},
	{
		"Crystal Synthesizer", "Maglev Conveyor", "Laser Cutter", "Crystal Collector",
		"Microfabricator", "Optical Conveyor", "Precision Scanner", "Chip Collector",
		"Plasma Feeder", "Pulse Conveyor", "Plasma Assembler", "Plasma Collector",
		"Command Desk", "Hologram Panel", "Research Display", "Biolab Planter",
	},
	{
		"Auric Reactor", "Gold Conveyor", "Signature Forge", "Bullion Collector",
		"Diamond Fabricator", "Diamond Conveyor", "Gem Polisher", "Diamond Collector",
		"Prestige Reactor", "Prestige Conveyor", "Crown Assembler", "Prestige Collector",
		"Studio Desk", "VIP Divider", "Trophy Display", "Sky Garden",
	},
}
local FLOOR_NAMES = { "Foundry", "Industrial Works", "Research Lab", "LARP Executive" }
local FLOOR_TINTS = { C.Red, color("#5EC4DB"), color("#A295FF"), C.Gold }
local SLOT_X = { -22.5, -7.5, 7.5, 22.5 }
local SLOT_Z = { -13, -1, 11, 23 }
local PRODUCTION = { "Generator", "Conveyor", "Processor", "Collector" }
local DECOR = { "Desk", "Barrier", "Display", "Planter" }

local function floorId(level)
	return string.format("Floor%02d", level)
end

local function upgradeId(level, index)
	return string.format("F%02d_U%02d", level, index)
end

local function accentPart(parent, frame, name, size, x, y, z, tint)
	local part = block(parent, frame, name, size, x, y, z, tint, M.Neon, DETAIL)
	part:SetAttribute("UsePlotAccent", true)
	return part
end

local function addPlotSockets(plot)
	local sockets = folder(plot, "Sockets")
	for level, names in ipairs(CATALOG) do
		local floor = folder(sockets, floorId(level))
		local y = DECK + (level - 1) * FLOOR_HEIGHT
		floor:SetAttribute("FloorName", FLOOR_NAMES[level])
		floor:SetAttribute("DeckY", y)
		for index, title in ipairs(names) do
			local row = math.ceil(index / 4)
			local column = (index - 1) % 4 + 1
			local id = upgradeId(level, index)
			local item = folder(floor, id)
			item:SetAttribute("DisplayName", title)
			local kind = if row == 4 then DECOR[column] else PRODUCTION[column]
			item:SetAttribute("Kind", kind)
			item:SetAttribute("ItemCFrame", CF(SLOT_X[column], y, SLOT_Z[row]))
			item:SetAttribute("ButtonCFrame", CF(SLOT_X[column], y + .1, SLOT_Z[row] - 4.65))
		end
	end
end

local function buildPlot(parent, index, frame, tint)
	local plot = model(parent, string.format("Plot%02d", index))
	plot:SetAttribute("PlotId", index)
	plot:SetAttribute("AccentColor", tint)
	plot:SetAttribute("OwnerUserId", 0)
	plot:SetAttribute("FloorCount", #CATALOG)
	plot:SetAttribute("UpgradeCapacity", #CATALOG * #CATALOG[1])
	local shell = folder(plot, "Site")
	local connectors = folder(plot, "Integration")
	folder(plot, "Unlocked")
	local halfWidth, halfDepth = config.PlotWidth / 2, config.PlotDepth / 2
	block(shell, frame, "Lot", V(config.PlotWidth, .18, config.PlotDepth), 0, .09, 0, C.Lawn, M.Grass)
	block(shell, frame, "Foundation", V(BUILD_WIDTH, DECK - .18, BUILD_DEPTH),
		0, (DECK + .18) / 2, BUILD_CENTER_Z, C.Steel, M.Concrete)
	block(shell, frame, "FoundationFront", V(BUILD_WIDTH, .14, .19), 0, .34, -24.05, tint, M.Neon, DETAIL)
	block(shell, frame, "EntryWalk", V(9, .3, halfDepth - 24), 0, .15, (-halfDepth - 24) / 2, C.Paving, M.Pavement)
	for _, x in ipairs({ -29.75, 29.75 }) do
		block(shell, frame, "DeckInlay", V(.16, .018, BUILD_DEPTH - 3), x, DECK + .012, BUILD_CENTER_Z, C.Trim, nil, DETAIL)
	end
	for _, side in ipairs({ -1, 1 }) do
		local edge = side * (halfWidth - 1.1)
		block(shell, frame, "SideKerb", V(.7, .58, config.PlotDepth - 9), edge, .33, 0, C.Stone, M.Concrete)
		tree(shell, frame * CF(0, .18, 0), side * (halfWidth - 7), -halfDepth + 12, .8)
		tree(shell, frame * CF(0, .18, 0), side * (halfWidth - 7), halfDepth - 7, .85)
		planter(shell, frame * CF(0, .18, 0), side * 17, halfDepth - 5, 20)
		lamp(shell, frame * CF(side * 8.6, .18, -halfDepth + 11) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0), false)
	end
	for _, x in ipairs({ -24, 24 }) do
		local gateway = model(shell, "ArrivalColumn")
		block(gateway, frame, "Column", V(2.45, 6.6, 2.1), x, 3.5, -halfDepth + 6.5, C.Ink, M.Metal)
		block(gateway, frame, "Blade", V(.34, 4.7, .18), x, 3.75, -halfDepth + 5.39, tint, M.Neon, DETAIL)
		block(gateway, frame, "Cap", V(2.7, .22, 2.35), x, 6.89, -halfDepth + 6.5, C.Gold, M.Metal)
	end
	local padZ = -halfDepth + 15
	cylinder(connectors, frame, "ClaimBase", 7.4, .18, 0, .39, padZ, C.Ink, M.Metal)
	local pad = cylinder(connectors, frame, "ClaimPad", 6.75, .12, 0, .54, padZ, tint, M.Neon)
	pad:SetAttribute("PlotId", index)
	block(connectors, frame, "ClaimPromptPivot", V(.3, .3, .3), 0, 2.5, padZ, C.Gold, nil, GHOST)
	local _, owner = sign(connectors, frame * CF(-15, .18, padZ + 2), "OwnerSign",
		string.format("PLOT %02d\nAVAILABLE", index), tint, 15, 2.9)
	owner:SetAttribute("PlotId", index)
	sign(shell, frame * CF(15, .18, padZ + 2), "ClaimGuide", "CLAIM PAD\nTYCOON ENTRANCE", tint, 13, 2.55)
	local origin = block(connectors, frame, "PlotOrigin", V(.3, .3, .3), 0, 0, 0, C.Gold, nil, GHOST)
	plot.PrimaryPart = origin
	addPlotSockets(plot)
	return plot
end

local function buildStair(parent, level, tint)
	local stairs = model(parent, "StairFromPreviousFloor")
	local startY = DECK + (level - 2) * FLOOR_HEIGHT
	local finishY = startY + FLOOR_HEIGHT
	local direction = if level % 2 == 0 then -1 else 1
	local x = if level % 2 == 0 then -43 else -36
	local railX = if level % 2 == 0 then -46 else -33
	local rotation = CFrame.Angles(-direction * math.atan(STAIR_RISE / STAIR_RUN), 0, 0)
	for step = 1, 20 do
		local z = direction * (step - 10.5) * STAIR_RUN
		local y = startY + step * STAIR_RISE
		block(stairs, IDENTITY, "Tread", V(5.7, .3, STAIR_RUN), x, y - .15, z, C.Steel, M.Metal)
		if step % 5 == 0 then
			block(stairs, IDENTITY, "RailPost", V(.18, 2.6, .18), railX, y + 1.3, z, C.Trim, M.Metal)
		end
	end
	block(stairs, IDENTITY, "Handrail", V(.22, .22, math.sqrt(30 ^ 2 + 14 ^ 2)),
		railX, startY + FLOOR_HEIGHT / 2 + 2.6, 0, tint, M.Metal, { rotation = rotation })
	block(stairs, IDENTITY, "Landing", V(15, .42, 5), -39.5, finishY - .21, direction * 17.5, C.Steel, M.Metal)
	block(stairs, IDENTITY, "LandingGuard", V(.24, 2.6, 4.65), -46.9, finishY + 1.3,
		direction * 17.5, C.Trim, M.Metal)
	local takeoffY = if level == 2 then .18 else startY
	if level == 2 then
		block(stairs, IDENTITY, "Approach", V(9, .32, 5), x, (DECK + takeoffY) / 2,
			-direction * 17.5, C.Steel, M.Concrete)
	end
end

local function setTemplateOrigin(template)
	local anchor = template:FindFirstChildWhichIsA("BasePart", true)
	assert(anchor, "Template has no BasePart: " .. template.Name)
	anchor.PivotOffset = anchor.CFrame:Inverse()
	template.PrimaryPart = anchor
end

local function buildFloorTemplate(parent, level)
	local shell = model(parent, floorId(level))
	shell:SetAttribute("FloorNumber", level)
	shell:SetAttribute("DisplayName", FLOOR_NAMES[level])
	local y = DECK + (level - 1) * FLOOR_HEIGHT
	local tint = FLOOR_TINTS[level]
	if level > 1 then
		block(shell, IDENTITY, "Deck", V(BUILD_WIDTH, .55, BUILD_DEPTH), 0, y - .275, BUILD_CENTER_Z, C.Steel, M.Concrete)
		buildStair(shell, level, tint)
		for _, z in ipairs({ -23.5, 35.5 }) do
			for _, x in ipairs({ -22, 0, 22 }) do
				block(shell, IDENTITY, "Balustrade", V(18.9, 2.65, .26), x, y + 1.325, z, C.Glass, M.Glass, GLASS)
			end
			block(shell, IDENTITY, "BalustradeCap", V(63, .13, .29), 0, y + 2.7, z, C.Trim, M.Metal)
		end
		local landingZ = if level % 2 == 0 then -17.5 else 17.5
		for _, segment in ipairs({ { -24, landingZ - 2.5 }, { landingZ + 2.5, 36 } }) do
			local startZ, endZ = segment[1], segment[2]
			block(shell, IDENTITY, "SideGuard", V(.24, 2.65, endZ - startZ),
				-31.8, y + 1.325, (startZ + endZ) / 2, C.Glass, M.Glass, GLASS)
		end
		block(shell, IDENTITY, "SideGuard", V(.24, 2.65, 59), 31.8, y + 1.325, BUILD_CENTER_Z, C.Glass, M.Glass, GLASS)
	end
	for _, x in ipairs({ -30.65, 30.65 }) do
		for _, z in ipairs({ -22.5, 34.5 }) do
			block(shell, IDENTITY, "Pier", V(1.38, FLOOR_HEIGHT - .55, 1.38), x, y + (FLOOR_HEIGHT - .55) / 2, z, C.Ink, M.Metal)
			accentPart(shell, IDENTITY, "PierInlay", V(.16, 3.8, .12), x, y + 3.7, z - .75, tint)
		end
		block(shell, IDENTITY, "SideBeam", V(1.14, .65, 56.5), x, y + FLOOR_HEIGHT - .86, BUILD_CENTER_Z, C.Steel, M.Metal)
	end
	for _, z in ipairs({ -22.5, 34.5 }) do
		block(shell, IDENTITY, "SpanBeam", V(62.5, .83, 1.18), 0, y + FLOOR_HEIGHT - .83, z, C.Ink, M.Metal)
		accentPart(shell, IDENTITY, "TrimLight", V(54, .115, .12), 0, y + FLOOR_HEIGHT - .7, z - .65, tint)
	end
	if level == #CATALOG then
		block(shell, IDENTITY, "PenthouseCanopy", V(54, .85, 23), 0, y + FLOOR_HEIGHT - .82, 17.4, C.Ink, M.Metal)
		block(shell, IDENTITY, "RoofGlazing", V(36, .28, 16), 0, y + FLOOR_HEIGHT - .26, 17.4, C.Glass, M.Glass, GLASS)
	end
	setTemplateOrigin(shell)
end

local function buildUpgradeTemplate(parent, level, index, title)
	local row, column = math.ceil(index / 4), (index - 1) % 4 + 1
	local kind = if row == 4 then DECOR[column] else PRODUCTION[column]
	local tint = FLOOR_TINTS[level]
	local variant = model(parent, upgradeId(level, index))
	variant:SetAttribute("DisplayName", title)
	variant:SetAttribute("Kind", kind)
	variant:SetAttribute("FloorNumber", level)
	if row < 4 and column > 1 then
		variant:SetAttribute("RequiresUpgradeId", upgradeId(level, index - 1))
	end
	local function detail(name, size, x, y, z, material, shade)
		return block(variant, IDENTITY, name, size, x, y, z, shade or C.Steel, material or M.Metal)
	end
	local function glow(name, size, x, y, z)
		accentPart(variant, IDENTITY, name, size, x, y, z, tint)
	end
	if kind == "Conveyor" then
		detail("Housing", V(15, .75, 4.7), 0, 1.025, 0)
		detail("Belt", V(14.8, .2, 3.77), 0, 1.5, 0, M.Rubber, C.Ink)
		for _, x in ipairs({ -5.8, 5.8 }) do
			detail("Stand", V(.65, 1.05, 4.12), x, .525, 0)
		end
		for _, z in ipairs({ -2.15, 2.15 }) do
			glow("BeltEdge", V(14.9, .12, .1), 0, 1.59, z)
		end
		for x = -6, 6, 2 do
			block(variant, IDENTITY, "RollerInlay", V(.08, .02, 3.69), x, 1.606, 0, C.Trim, M.Metal, DETAIL)
		end
	elseif kind == "Generator" or kind == "Processor" or kind == "Collector" then
		local height = 2.9 + (level - 1) * .65 + (row - 1) * .27
		local equipmentX = if kind == "Generator" then -2.2 elseif kind == "Collector" then 2.2 else 0
		detail("Mount", V(7.9, .39, 5), 0, .195, 0)
		detail("EquipmentHousing", V(4.25, height, 4.1), equipmentX, height / 2 + .39, 0, M.Metal, C.Ink)
		detail("Lens", V(2.9, height * .38, .23), equipmentX, height * .67 + .39, -2.12, M.Glass, C.Glass)
		glow("OperatingStrip", V(3.33, .13, .11), equipmentX, height * .38 + .39, -2.28)
		if kind == "Generator" then
			cylinder(variant, IDENTITY, "Hopper", 3.55, 1.3, equipmentX, height + 1.02, 0, C.Trim, M.Metal)
			cylinder(variant, IDENTITY, "HopperRim", 3.76, .24, equipmentX, height + 1.78, 0, tint, M.Metal)
		elseif kind == "Processor" then
			for _, z in ipairs({ -1.5, 1.5 }) do
				detail("Arm", V(6, .37, .36), 0, height + .45, z)
			end
		else
			detail("Terminal", V(2.8, 1, .62), equipmentX, height - .1, -2.55)
			glow("TerminalDisplay", V(2.3, .55, .08), equipmentX, height, -2.9)
		end
	elseif kind == "Desk" then
		detail("Pedestal", V(5, 2.6, 1.8), 0, 1.3, 0)
		detail("Counter", V(6, .3, 2.6), 0, 2.75, 0, M.WoodPlanks, C.Ink)
		glow("DeskInlay", V(5, .12, .08), 0, 2.1, -.94)
	elseif kind == "Barrier" then
		detail("Base", V(7.2, .45, .85), 0, .225, 0)
		block(variant, IDENTITY, "Screen", V(6.85, 3 + level * .3, .22), 0, 1.91 + level * .15, 0, C.Glass, M.Glass, GLASS)
		glow("UpperEdge", V(7, .13, .18), 0, 3.45 + level * .3, 0)
	elseif kind == "Display" then
		detail("Plinth", V(2.8, 1.45, 2.35), 0, .725, 0)
		block(variant, IDENTITY, "Exhibit", V(1.8, 1.8, 1.8), 0, 2.86, 0, tint, M.Glass,
			{ rotation = CFrame.Angles(.48, math.pi / 4, .48) })
		glow("DisplayRing", V(2.75, .14, 2.3), 0, 1.51, 0)
	else
		planter(variant, IDENTITY, 0, 0, 5.8)
	end
	if row < 4 then
		variant:SetAttribute("InletCFrame", CF(-7.5, 1.62, 0))
		variant:SetAttribute("OutletCFrame", CF(7.5, 1.62, 0))
	end
	setTemplateOrigin(variant)
end

local function buildAssets()
	local assets = folder(nil, ASSET_NAME)
	local shells = folder(assets, "FloorShells")
	local upgrades = folder(assets, "UpgradeModels")
	for level, names in ipairs(CATALOG) do
		buildFloorTemplate(shells, level)
		local floor = folder(upgrades, floorId(level))
		for index, title in ipairs(names) do
			buildUpgradeTemplate(floor, level, index, title)
		end
	end
	return assets
end

local function buildParkEdge(parent)
	local edge = folder(parent, "ParkEdge")
	local rearZ = halfZ - 11
	local flankX = halfX - 9
	for _, side in ipairs({ -1, 1 }) do
		longStrip(edge, "RidgeFooting", 0, .44, side * rearZ, 2 * (halfX - 7), .88, 11, C.Hedge, M.Grass)
		block(edge, IDENTITY, "RidgeFooting", V(12, .88, 2 * (halfZ - 14)), side * flankX, .44, 0, C.Hedge, M.Grass)
		for x = -halfX + 17, halfX - 14, 26 do
			local height = 13 + math.floor(math.abs(x) / 9) % 6
			local ridgeFrame = CF(x, 0, side * (halfZ + 3)) * CFrame.Angles(0, side * math.rad(12), 0)
			block(edge, ridgeFrame, "StoneRidge", V(31, height, 21), 0, height * .41, 0, C.Hedge, M.Slate,
				{ class = "WedgePart", collide = false, query = false })
			if math.floor(x / 26) % 2 == 0 then
				tree(edge, IDENTITY, x, side * (rearZ - 3), .92)
			end
		end
		for z = -halfZ + 24, halfZ - 18, 25 do
			tree(edge, IDENTITY, side * (flankX + 1), z, if math.floor(z / 25) % 2 == 0 then 1.2 else .86)
		end
		-- Flush with the outer planting, above the highest unlockable roof.
		local barrier = { transparency = 1, shadow = false }
		longStrip(edge, "Boundary", 0, 36, side * (halfZ - 5), 2 * halfX, 72, 2, C.Hedge, nil, barrier)
		block(edge, IDENTITY, "Boundary", V(2, 72, 2 * halfZ), side * (halfX - 4), 36, 0, C.Hedge, nil, barrier)
	end
end

local function buildWorld()
	local world = model(nil, WORLD_NAME)
	world:SetAttribute("GameTitle", "LARP Tycoon")
	world:SetAttribute("Developer", "LARP Studio")
	world:SetAttribute("PlotCount", config.PlotCount)
	world:SetAttribute("PlotWidth", config.PlotWidth)
	world:SetAttribute("PlotDepth", config.PlotDepth)
	world:SetAttribute("FloorHeight", FLOOR_HEIGHT)
	local ground = folder(world, "Ground")
	longStrip(ground, "IslandGround", 0, -3, 0, halfX * 2, 6, halfZ * 2, C.Lawn, M.Grass)
	buildStreet(world)
	buildPlaza(world)
	buildParkEdge(world)
	local plots = folder(world, "Plots")
	for row, z in ipairs({ plotZ, -plotZ }) do
		for column = 1, columns do
			local x = (column - (columns + 1) / 2) * pitch
			local index = (row - 1) * columns + column
			local angle = if row == 1 then 0 else math.pi
			buildPlot(plots, index, CF(x, 0, z) * CFrame.Angles(0, angle, 0), accents[index])
		end
	end
	return world
end

local function makeLighting()
	local effects = {
		object("Sky", nil, "LarpTycoonSky", { CelestialBodiesShown = true, StarCount = 700 }),
		object("Atmosphere", nil, "LarpTycoonAtmosphere", {
			Density = .23, Offset = .15, Color = color("#D1E3F2"), Decay = color("#A8A8B7"), Glare = .11, Haze = 1.05,
		}),
		object("BloomEffect", nil, "LarpTycoonBloom", { Intensity = .19, Size = 28, Threshold = 1.45 }),
		object("ColorCorrectionEffect", nil, "LarpTycoonColor", {
			Brightness = .02, Contrast = .07, Saturation = -.04, TintColor = color("#FFF3EB"),
		}),
	}
	return effects
end

local function findGenerated(parent, name)
	local generated = {}
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then
			assert(child:GetAttribute("Generator") == SIGNATURE,
				parent.Name .. "/" .. name .. " already exists and is not owned by this generator")
			table.insert(generated, child)
		end
	end
	return generated
end

local function mount(parent, instance, previous)
	instance:SetAttribute("Generator", SIGNATURE)
	instance:SetAttribute("GeneratorVersion", VERSION)
	for _, old in ipairs(previous) do
		old:Destroy()
	end
	instance.Parent = parent
end

local oldWorld = findGenerated(Workspace, WORLD_NAME)
local oldAssets = findGenerated(ServerStorage, ASSET_NAME)
local newEffects = makeLighting()
local oldEffects = {}
for i, effect in ipairs(newEffects) do
	oldEffects[i] = findGenerated(Lighting, effect.Name)
end
local world = buildWorld()
local assets = buildAssets()

Lighting.LightingStyle = Enum.LightingStyle.Realistic
Lighting.ClockTime = 16.1
Lighting.GeographicLatitude = 36
Lighting.Brightness = 2.4
Lighting.GlobalShadows = true
Lighting.Ambient = color("#617187")
Lighting.OutdoorAmbient = color("#98A4BC")
Lighting.EnvironmentDiffuseScale = .35
Lighting.EnvironmentSpecularScale = .65
Lighting.ExposureCompensation = .08
for _, child in ipairs(Lighting:GetChildren()) do
	if (child:IsA("Sky") or child:IsA("Atmosphere")) and child:GetAttribute("Generator") ~= SIGNATURE then
		warn("LARP Tycoon: review existing Lighting effect " .. child.Name .. " if it overrides the generated sky or atmosphere")
	end
end
for i, effect in ipairs(newEffects) do
	mount(Lighting, effect, oldEffects[i])
end
mount(ServerStorage, assets, oldAssets)
mount(Workspace, world, oldWorld)
print(string.format("LARP Tycoon | %d plots, %d floors and %d upgrade slots per plot. Save the place to keep the map.",
	config.PlotCount, #CATALOG, #CATALOG * #CATALOG[1]))
