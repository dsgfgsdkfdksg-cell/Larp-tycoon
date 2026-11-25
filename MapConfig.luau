-- Optional ModuleScript named LarpTycoonMapConfig in ServerStorage.
-- The generator also works by itself with the same built-in defaults.
return {
	PlotCount = 8, -- even, from 2 to 16; half on either side of the plaza
	PlotWidth = 104, -- minimum 104 studs to preserve the building and stair clearances
	PlotDepth = 104, -- minimum 104 studs
	PlotGap = 12, -- minimum 12 studs
	PlazaDepth = 100, -- minimum 100 studs
	RoadWidth = 18, -- minimum 16 studs
	SidewalkWidth = 8, -- minimum 8 studs
	BorderWidth = 24, -- minimum 20 studs
	Brand = {
		Red = "#E32F43",
		White = "#F2F2EB",
		Gold = "#F8BE5B",
	},
	PlotColors = {
		"#FF586C", "#54D9FA", "#FFBD63", "#A28AFF",
		"#6FE795", "#F483CF", "#799DFF", "#F6E974",
	},
}
