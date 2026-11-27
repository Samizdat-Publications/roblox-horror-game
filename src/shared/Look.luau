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
	-- Second pass (after Neon's look review scored phone readability 2/10): a lighter gray-green
	-- fog band that lifts the shore silhouettes, still dark enough to read as night.
	Brightness = 1.3,
	Ambient = Color3.fromRGB(40, 54, 56),
	OutdoorAmbient = Color3.fromRGB(64, 80, 80),
	EnvironmentDiffuseScale = 0.2,
	EnvironmentSpecularScale = 0.3,
	GlobalShadows = true,
	ExposureCompensation = 0.3,
	atmosphere = {
		Density = 0.46,
		Offset = 0.12,
		Haze = 2,
		Glare = 0,
		Color = Color3.fromRGB(58, 72, 70),
		Decay = Color3.fromRGB(34, 44, 46),
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

-- Dawn after the finale (Polish 3, Neon's fix 4): fx/Finale tweens the client's Lighting,
-- Atmosphere and ColorCorrection from the night (Look.Lighting) to these over `seconds`, and
-- puts them back at the next night or on the title. The fog lifts a little and turns warm.
Look.Dawn = {
	seconds = 2.6,
	ClockTime = 6.3,
	Brightness = 2.4,
	Ambient = Color3.fromRGB(118, 98, 86),
	OutdoorAmbient = Color3.fromRGB(176, 142, 118),
	ExposureCompensation = 0.35,
	atmosphere = {
		Density = 0.36,
		Offset = 0.2,
		Haze = 1.4,
		Glare = 0.4,
		Color = Color3.fromRGB(236, 186, 146),
		Decay = Color3.fromRGB(206, 146, 112),
	},
	colorCorrection = {
		Brightness = 0.06,
		Contrast = 0.08,
		Saturation = 0.05,
		TintColor = Color3.fromRGB(255, 232, 210),
	},
}

-- The finale on screen (Polish 3, Neon's fixes 1, 2, 5). fx/Finale reads these.
Look.Finale = {
	-- Finale v2 (Neon 2/10): the bell was spatial at the dock (inaudible from the steeple)
	-- and its three strokes overlapped. Now: true silence, then three slow tolls heard from
	-- anywhere, one Sound per toll (the last is cut before the next starts), and the motor
	-- and the chase music stay hushed until the tolls are done.
	silence = 1.75, -- seconds of dead silence at the bell before the first stroke
	bellStrokes = 3,
	bellGap = 2.8, -- seconds between strokes (slow)
	bellCut = 0.3, -- the previous toll fades out over this long as the next one starts
	bellVolume = 1.6, -- multiplies finale-bell (non-spatial, from SoundService)
	afterBell = 1.2, -- seconds after the last stroke before the motor and the chase come back
	captionHold = 4.5, -- "The bell. Go home." stays this long
	-- The locked lantern's cone over the bow: a SpotLight in an Attachment on the lantern,
	-- aimed forward along the bow and `tilt` degrees down so the water ahead and any hazard
	-- in it are lit. Range is clamped to 60 by the engine (lights cap at 60 studs), so 60.
	cone = {
		brightness = 4,
		range = 60,
		angle = 70,
		tilt = 14,
		shadows = true,
		color = Color3.fromRGB(255, 176, 92),
	},
	-- Finale v6 (Neon finale-v5 2/10): the sky column is gone (it out-shone the false
	-- beacons). Home is a modest warm light post at the dock end, near the water (`offset`
	-- from the dock end, `height` studs of post, a small Neon lamp on top), with a small
	-- halo drawn over the fog so it shows across the lake. It double-blinks with the beacon.
	-- The false beacons wear the same halo and blink wrong.
	beaconShaft = {
		height = 8,
		width = 0.5,
		lamp = 1.1,
		offset = Vector3.new(3, 0, -1),
		lightRange = 24,
		lightBrightness = 2.5,
	},
	beaconHalo = { studs = 9, minPixels = 14, maxDistance = 2500, ringTransparency = { 0.72, 0.5, 0.2 } },
	-- How the false beacons blink wrong: "Steady" (always lit, a faint shimmer) or "Single"
	-- (one dark flicker every `period` seconds, where the real one blinks twice).
	falseBlink = { period = 6, dark = 0.45, shimmer = 0.08 },
	captionAfterToll = 0.4, -- "The bell. Go home." shows this long after the first toll is heard
	captionWaitMax = 1.5, -- at most this long waiting for the toll Sound to start before the delay
	-- Hazards are drawn closer than Core holds them so they read through the fog: the gap
	-- beyond the kill radius is scaled by `pull` (the kill distance itself is unchanged).
	pull = 0.5,
	hazardLightRange = 44,
	hazardLightBrightness = 3.2,
	-- The pursuit layer under the motor; its pulse quickens as the boat slows.
	pulseCalm = 1.6, -- Hz at speed
	pulseScared = 4.5, -- Hz when the boat is nearly stopped
	vignetteMax = 0.85,
	oilWarn = 0.35, -- below this the oil bar pulses red
	oilWarnFinale = 0.25, -- in the finale the bar is red all along and pulses below this
}

-- The boat's lantern. The client flickers it between flickerLow and 1 times Brightness.
Look.Lantern = {
	Range = 60,
	Brightness = 3.6,
	Color = Color3.fromRGB(255, 150, 60),
	Shadows = true,
	flickerLow = 0.88,
	flickerSpeed = 7, -- noise steps per second
}

-- The dock beacon: a steady warm light that blinks off twice every `period` seconds.
Look.Beacon = {
	Range = 62,
	Brightness = 6,
	Color = Color3.fromRGB(255, 186, 104),
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
	-- Scare polish 2 (11/26/2026, Neon's listening test: the ambience buried every rule cue).
	-- Ambience is the base level below chorus band 2; band3Trim takes it down further as the
	-- chorus climbs to band 3 (0.75 * 0.6 = 0.45, about 6 dB under the old 0.9). The Rule
	-- group is up about 4 dB. SoundGroup.Volume ranges 0..10 (creator docs).
	groups = {
		Ambience = 0.75,
		Boat = 0.8,
		Fishing = 0.8,
		Rule = 1.6,
		UI = 0.6,
		Music = 0.6,
		Voice = 1.0,
	},
	band3Trim = 0.6, -- Ambience group multiplier at chorus band 3 (eases in from band 2)
	-- While any rule cue sounds (a Rule-group sound playing, or for cueHold seconds after an
	-- EntityCue) the Ambience group ducks by this much: 0.4 is about -8 dB. The Boat group's
	-- random creaks are held back meanwhile.
	cueDuck = 0.4,
	cueHold = 3,
	duckAttack = 0.12, -- seconds to reach the duck
	duckRelease = 1.0, -- seconds to come back
	muteFade = 0.3, -- seconds to mute the ambience (death card)
	hushFade = 0.12, -- seconds for AudioDirector.hush to reach silence (the finale's bell)
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
		motorIdle = 1.0,
		reel = 0.6,
	},
	fadePerSecond = 1.5, -- how fast a layer moves toward its target volume
	chorusFadePerSecond = 4, -- the chorus changes fast: silence must be sudden
	oarStrokeSeconds = 1.7, -- one stroke per this many seconds while rowing
	hullCreakMin = 8,
	hullCreakMax = 20,
	wildlifeMin = 30, -- seconds between a loon or owl call on shore
	wildlifeMax = 70,
	-- The frog chorus from pieces (brief, 11/26/2026): seconds between single frog calls at
	-- each band, the full loop only at band 3. Bands change gradually except the drop to 0.
	frogGaps = {
		{ 5, 11 }, -- band 1
		{ 1.5, 4 }, -- band 2
		{ 0.4, 1.2 }, -- band 3 (under the loop)
	},
	chorusRisePerSecond = 1 / 3, -- how fast the chorus level climbs between bands
	frogShoreSpread = 0.45, -- radians either side of the nearest shore point
	frogPitch = { 0.9, 1.12 },
	frogVolume = { 0.65, 1.0 },
	radioStaticSeconds = 4, -- static between the two radio tunes
	tape = {
		lowGain = -14, -- dB, EqualizerSoundEffect on the Voice group: a cheap cassette
		midGain = 2,
		highGain = -12,
		distortion = 0.12, -- DistortionSoundEffect.Level
		clickGap = 0.35, -- seconds between the tape click and the voice
		duck = 0.6, -- ambience is multiplied by this while a tape plays
	},
}

-- Fireflies: the visual twin of the frog chorus. Many at bands 2 and 3, a few at band 1,
-- frozen in place and then faded at band 0.
Look.Fireflies = {
	count = 36,
	color = Color3.fromRGB(214, 255, 140),
	size = 0.22,
	fadePerSecond = 0.8,
	freezeHold = 0.6, -- seconds frozen in place before they fade
	freezeFade = 2.5,
	boatRing = { 8, 30 }, -- studs from the boat
	shoreSpread = 0.5, -- radians either side of the nearest shore point
	relocateDist = 150, -- a fly this far from the boat moves when it next goes dark
}

-- Fish built from parts (server/world/FishModel). Sizes in studs: length, height, width.
Look.Fish = {
	Pumpkinseed = {
		length = 1.4,
		height = 1.0,
		width = 0.45,
		body = Color3.fromRGB(120, 140, 70),
		fin = Color3.fromRGB(150, 110, 50),
		bar = Color3.fromRGB(50, 60, 30),
	},
	YellowPerch = {
		length = 1.8,
		height = 0.7,
		width = 0.45,
		body = Color3.fromRGB(190, 170, 70),
		fin = Color3.fromRGB(190, 110, 50),
		bar = Color3.fromRGB(45, 50, 30),
	},
	Bullhead = {
		length = 1.8,
		height = 0.65,
		width = 0.55,
		body = Color3.fromRGB(85, 70, 50),
		fin = Color3.fromRGB(70, 58, 42),
		bar = Color3.fromRGB(40, 32, 24),
	},
	Papermouth = {
		length = 1.7,
		height = 0.9,
		width = 0.4,
		body = Color3.fromRGB(175, 180, 175),
		fin = Color3.fromRGB(140, 145, 140),
		bar = Color3.fromRGB(60, 62, 60),
		tallFin = true,
	},
	ChainPickerel = {
		length = 2.6,
		height = 0.55,
		width = 0.42,
		body = Color3.fromRGB(80, 110, 60),
		fin = Color3.fromRGB(110, 120, 70),
		bar = Color3.fromRGB(35, 50, 30),
		finBack = true,
	},
	Walleye = {
		length = 2.2,
		height = 0.7,
		width = 0.5,
		body = Color3.fromRGB(150, 140, 90),
		fin = Color3.fromRGB(120, 110, 70),
		bar = Color3.fromRGB(55, 50, 35),
	},
	OldPlank = {
		length = 3.4,
		height = 0.8,
		width = 0.7,
		body = Color3.fromRGB(90, 95, 92),
		fin = Color3.fromRGB(70, 74, 72),
		bar = Color3.fromRGB(45, 48, 46),
	},
	SteepleCat = {
		length = 3.0,
		height = 0.8,
		width = 0.75,
		body = Color3.fromRGB(70, 85, 105),
		fin = Color3.fromRGB(55, 66, 82),
		bar = Color3.fromRGB(35, 42, 52),
	},
	eye = Color3.fromRGB(215, 205, 160),
	pupil = Color3.fromRGB(10, 10, 12),
	glowTransparency = 0.6,
	glowRange = 7,
	glowBrightness = 1.2,
	blinkEvery = { 1.6, 3.2 }, -- seconds between blinks
	blinkFor = 0.18,
}

-- Fishing gear (server FishingService).
Look.Gear = {
	rod = Color3.fromRGB(60, 45, 30),
	line = Color3.fromRGB(205, 205, 190),
	lineWidth = 0.04,
	bobber = Color3.fromRGB(190, 45, 32),
	bobberCap = Color3.fromRGB(230, 225, 210),
	token = Color3.fromRGB(150, 150, 140), -- the fish shapes on the hold lid
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
