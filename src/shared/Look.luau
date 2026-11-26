--!strict
-- Look, mix and UI constants (lighting, colors, fog, mix levels, fonts).
-- Gameplay numbers live in Config.luau. The local session tunes these in Studio.
-- Colors are Color3.fromRGB so the Lune tools (which inject Color3) can load this file.

local Look = {}

-- DESIGN.md palette.
Look.Palette = {
	water = Color3.fromRGB(11, 20, 24), -- #0B1418
	fog = Color3.fromRGB(27, 42, 46), -- #1B2A2E
	lantern = Color3.fromRGB(255, 180, 90), -- #FFB45A
	beacon = Color3.fromRGB(255, 226, 168), -- #FFE2A8
	wrongGlow = Color3.fromRGB(140, 255, 193), -- #8CFFC1
	silhouette = Color3.fromRGB(5, 6, 7), -- #050607
	pinEyes = Color3.fromRGB(232, 244, 255), -- #E8F4FF
	paper = Color3.fromRGB(233, 223, 195), -- #E9DFC3
	ink = Color3.fromRGB(42, 33, 24), -- #2A2118
	amendInk = Color3.fromRGB(122, 46, 30), -- #7A2E1E
	dawn = Color3.fromRGB(242, 185, 138), -- #F2B98A
	-- World materials (not in DESIGN.md; chosen dark so the lantern does the work).
	lakeBed = Color3.fromRGB(20, 22, 18),
	shore = Color3.fromRGB(24, 28, 22),
	mud = Color3.fromRGB(30, 27, 22),
	trunk = Color3.fromRGB(18, 16, 14),
	canopy = Color3.fromRGB(12, 18, 15),
	dockWood = Color3.fromRGB(58, 48, 38),
	dockPost = Color3.fromRGB(34, 29, 24),
	shackWall = Color3.fromRGB(44, 40, 34),
	shackRoof = Color3.fromRGB(28, 26, 24),
	window = Color3.fromRGB(255, 196, 120),
	stone = Color3.fromRGB(52, 54, 52),
	spire = Color3.fromRGB(30, 33, 34),
	bell = Color3.fromRGB(70, 60, 38),
	buoy = Color3.fromRGB(96, 34, 28),
	buoyCage = Color3.fromRGB(40, 40, 38),
	reed = Color3.fromRGB(38, 44, 28),
	boatWood = Color3.fromRGB(82, 64, 46),
	boatTrim = Color3.fromRGB(52, 40, 30),
	seat = Color3.fromRGB(70, 56, 40),
	metal = Color3.fromRGB(46, 46, 44),
	cooler = Color3.fromRGB(150, 140, 120),
	motor = Color3.fromRGB(34, 38, 40),
}

-- Lighting, Atmosphere and post effects. LightingController applies these at server start.
Look.Lighting = {
	ClockTime = 0,
	-- Tuned in Studio 11/26/2026: the first values rendered near pure black. These keep the
	-- shore silhouettes and the fog band readable while the lantern stays the brightest thing.
	Brightness = 1.2,
	Ambient = Color3.fromRGB(38, 52, 58),
	OutdoorAmbient = Color3.fromRGB(62, 82, 88),
	EnvironmentDiffuseScale = 0.2,
	EnvironmentSpecularScale = 0.3,
	GlobalShadows = true,
	ExposureCompensation = 0.35,
	atmosphere = {
		Density = 0.42,
		Offset = 0.05,
		Haze = 1.6,
		Glare = 0,
		Color = Color3.fromRGB(43, 64, 69),
		Decay = Color3.fromRGB(30, 46, 52),
	},
	colorCorrection = {
		Brightness = 0.03,
		Contrast = 0.1,
		Saturation = -0.1,
		TintColor = Color3.fromRGB(226, 242, 240), -- a faint pull toward teal
	},
	bloom = {
		Intensity = 0.6,
		Size = 24,
		Threshold = 1.6,
	},
	sky = {
		CelestialBodiesShown = false,
		StarCount = 0,
	},
}

-- The boat's lantern. The client flickers it between flickerLow and 1 times Brightness.
Look.Lantern = {
	Range = 40,
	Brightness = 2.6,
	Color = Color3.fromRGB(255, 176, 96),
	Shadows = true,
	flickerLow = 0.88,
	flickerSpeed = 7, -- noise steps per second
}

-- The dock beacon: a steady warm light that blinks off twice every `period` seconds.
Look.Beacon = {
	Range = 60,
	Brightness = 4,
	Color = Color3.fromRGB(255, 226, 168),
	Shadows = false,
	period = 6,
	blinkOn = 0.45, -- each dark blink lasts this long
	blinkGap = 0.35, -- light between the two blinks
}

-- The shack window glow.
Look.Window = {
	Range = 22,
	Brightness = 1.2,
	Color = Color3.fromRGB(255, 196, 120),
}

-- Mix: SoundGroup volumes and the base level of each ambience layer (0..1, multiplied by
-- the registry entry's own volume).
Look.Mix = {
	groups = {
		Ambience = 0.9,
		Boat = 0.8,
		Fishing = 0.8,
		Rule = 1.0,
		UI = 0.6,
		Music = 0.6,
		Voice = 1.0,
	},
	layers = {
		hullLap = 0.7,
		lakeAir = 0.6,
		windTrees = 0.5,
		chorus = 0.9,
		crickets = 0.45,
		radio = 0.8,
		radioStatic = 0.25,
		dockWater = 0.6,
		lanternFlame = 0.5,
		motorIdle = 0.8,
	},
	fadePerSecond = 1.5, -- how fast a layer moves toward its target volume
	chorusFadePerSecond = 4, -- the chorus changes fast: silence must be sudden
	oarStrokeSeconds = 1.7, -- one stroke per this many seconds while rowing
	hullCreakMin = 8,
	hullCreakMax = 20,
	wildlifeMin = 30, -- seconds between a loon or owl call on shore
	wildlifeMax = 70,
}

-- UI: paper and ink.
Look.UI = {
	paper = Color3.fromRGB(233, 223, 195),
	ink = Color3.fromRGB(42, 33, 24),
	-- Enum.Font items checked against the current API dump (Lune reflection 0.741).
	typewriterFont = "SpecialElite",
	handFont = "PermanentMarker",
	hudTextSize = 18,
	hudPaperTransparency = 0.15,
}

-- Camera shots for captures (DebugDriver "camera"). Offsets in studs.
Look.Shots = {
	fieldOfView = 70,
	bowHeight = 3.2,
	topHeight = 140,
}

return Look
