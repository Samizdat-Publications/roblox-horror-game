--!strict
-- Every gameplay number lives here. Tune this file, rerun the gate, and the pacing
-- scorecard (tools/sim) tells you what changed. Look, mix and UI constants live in Look.luau.
-- These are starting values from the design pass; the simulator tunes them.

local Config = {}

Config.TITLE = "Don't Wave Back"
Config.TAGLINE = "Night shift on Blackwater Lake. Read the Lake Rules."
Config.SAVE_VERSION = 1

Config.Players = { max = 4 }

-- One night runs 10 PM to 5 AM in game time.
Config.Night = {
	realSeconds = 540,
	startHour = 22,
	endHour = 29, -- 5 AM
	tick = 0.1, -- rules step in seconds
	openingGrace = 60, -- no real scare in the first seconds of a night
	teachFrom = 0.2, -- a new rule first appears between these fractions of the night
	teachTo = 0.45,
}

-- Indexed by living crew size at night start (1 to 4).
Config.Scaling = {
	quota = { 0.45, 0.7, 0.85, 1.0 },
	warning = { 1.4, 1.15, 1.0, 1.0 },
	budget = { 0.7, 0.85, 1.0, 1.0 }, -- real scare budget, rounded, never below 1
}

Config.Difficulty = {
	Normal = { warning = 1.0, budget = 1.0, quiet = 1.0, amendFromNight = 5, amendOnFirstRun = false },
	Nightmare = { warning = 0.7, budget = 1.4, quiet = 0.7, amendFromNight = 2, amendOnFirstRun = true },
}

-- Story nights. `rules` accumulate: a night uses every rule introduced so far.
Config.Nights = {
	{
		newRules = { "Hum" },
		real = 2,
		fake = 3,
		quietGap = 75,
		quota = 10,
		maxConcurrent = 1,
		wrongChance = 0,
		wrongTier = 1,
	},
	{
		newRules = { "WrongCatch" },
		real = 3,
		fake = 3,
		quietGap = 65,
		quota = 14,
		maxConcurrent = 1,
		wrongChance = 0.2,
		wrongTier = 1,
	},
	{
		newRules = { "Neighbor" },
		real = 4,
		fake = 4,
		quietGap = 55,
		quota = 18,
		maxConcurrent = 1,
		wrongChance = 0.16,
		wrongTier = 2,
	},
	{
		newRules = { "Knocking", "Watcher" },
		real = 5,
		fake = 4,
		quietGap = 45,
		quota = 22,
		maxConcurrent = 2,
		wrongChance = 0.16,
		wrongTier = 2,
	},
	{
		newRules = { "Finale" },
		real = 6,
		fake = 5,
		quietGap = 40,
		quota = 26,
		maxConcurrent = 2,
		wrongChance = 0.2,
		wrongTier = 3,
	},
}

-- Endless Nights (night 6 and up): each night adds to the last, with caps.
Config.Endless = {
	realBase = 6,
	realPerNight = 0.5,
	realCap = 10,
	fakeBase = 5,
	quietGapBase = 40,
	quietGapFloor = 25,
	quietGapStep = 2,
	quotaBase = 26,
	quotaPerNight = 3,
	maxConcurrent = 2,
	wrongChance = 0.22,
	wrongTier = 3,
}

-- The lake, in studs. Origin is the lake center, +z north, +x east. The dock is on the south shore.
Config.Lake = {
	radiusX = 620,
	radiusZ = 460,
	waterY = 0,
	dockFoot = { x = 0, z = -452 }, -- where the dock meets the shore
	dockEnd = { x = 0, z = -384 }, -- where the boat ties up and the cooler sits
	bankRadius = 30, -- boat must be this close to dockEnd to bank or refill
	safeRadius = 80, -- the beacon's light around dockEnd: no real rule starts or advances here
	beacon = { x = 0, z = -456, height = 36 },
	shack = { x = -52, z = -486 },
	steeple = { x = 170, z = 250 },
	steepleRadius = 95,
	buoy = { x = -330, z = 60 },
	reeds = { x = 430, z = -110, radius = 120 },
	narrows = { x = -130, z = 310, radius = 105 },
	shallowsDist = 230, -- within this distance of dockEnd is Shallows
}

-- Zones decide which fish bite. Checked in this order: Steeple, Reeds, Narrows, Shallows, else Open.
Config.Zones = { "Steeple", "Reeds", "Narrows", "Shallows", "Open" }

-- Eight species. `points` count toward the quota. `zones` are bite weights per zone.
-- Traits are what the Field Guide prints. A Wrong Catch changes exactly one of them.
Config.Fish = {
	Pumpkinseed = {
		name = "Pumpkinseed",
		points = 1,
		note = "Small, round, bright. Bites all night in the shallows.",
		traits = {
			eyes = 2,
			dorsal = 1,
			stripes = 0,
			barbels = 0,
			tail = "Forked",
			eyeshine = false,
			glow = false,
			blinks = false,
		},
		zones = { Shallows = 5, Reeds = 3, Open = 1, Narrows = 1, Steeple = 0 },
	},
	YellowPerch = {
		name = "Yellow Perch",
		points = 1,
		note = "Five dark bars, two back fins. Count the bars.",
		traits = {
			eyes = 2,
			dorsal = 2,
			stripes = 5,
			barbels = 0,
			tail = "Forked",
			eyeshine = false,
			glow = false,
			blinks = false,
		},
		zones = { Shallows = 4, Reeds = 2, Open = 3, Narrows = 2, Steeple = 0 },
	},
	Bullhead = {
		name = "Bullhead",
		points = 1,
		note = "Mud brown. Four whiskers. Square tail.",
		traits = {
			eyes = 2,
			dorsal = 1,
			stripes = 0,
			barbels = 4,
			tail = "Square",
			eyeshine = false,
			glow = false,
			blinks = false,
		},
		zones = { Shallows = 3, Reeds = 4, Open = 1, Narrows = 2, Steeple = 1 },
	},
	Papermouth = {
		name = "Papermouth",
		points = 2,
		note = "Silver and speckled. One tall back fin. No bars.",
		traits = {
			eyes = 2,
			dorsal = 1,
			stripes = 0,
			barbels = 0,
			tail = "Forked",
			eyeshine = false,
			glow = false,
			blinks = false,
		},
		zones = { Shallows = 1, Reeds = 3, Open = 3, Narrows = 3, Steeple = 1 },
	},
	ChainPickerel = {
		name = "Chain Pickerel",
		points = 2,
		note = "Long and green. One back fin, set far back. Round tail on ours.",
		traits = {
			eyes = 2,
			dorsal = 1,
			stripes = 0,
			barbels = 0,
			tail = "Round",
			eyeshine = false,
			glow = false,
			blinks = false,
		},
		zones = { Shallows = 0, Reeds = 5, Open = 2, Narrows = 2, Steeple = 0 },
	},
	Walleye = {
		name = "Walleye",
		points = 2,
		note = "Four dark saddles, two back fins. Its eyes shine in the lantern. That is normal. Only for this one.",
		traits = {
			eyes = 2,
			dorsal = 2,
			stripes = 4,
			barbels = 0,
			tail = "Forked",
			eyeshine = true,
			glow = false,
			blinks = false,
		},
		zones = { Shallows = 0, Reeds = 1, Open = 4, Narrows = 4, Steeple = 2 },
	},
	OldPlank = {
		name = "Old Plank",
		points = 3,
		note = "Lake sturgeon. Gray, armored, four whiskers, uneven tail. Older than the dam.",
		traits = {
			eyes = 2,
			dorsal = 1,
			stripes = 0,
			barbels = 4,
			tail = "Uneven",
			eyeshine = false,
			glow = false,
			blinks = false,
		},
		zones = { Shallows = 0, Reeds = 0, Open = 2, Narrows = 4, Steeple = 3 },
	},
	SteepleCat = {
		name = "Steeple Cat",
		points = 3,
		note = "Slate blue catfish. Eight whiskers. Forked tail. Only by the steeple, only after three.",
		traits = {
			eyes = 2,
			dorsal = 1,
			stripes = 0,
			barbels = 8,
			tail = "Forked",
			eyeshine = false,
			glow = false,
			blinks = false,
		},
		zones = { Shallows = 0, Reeds = 0, Open = 0, Narrows = 0, Steeple = 5 },
		afterHour = 27, -- 3 AM
	},
}

Config.Fishing = {
	castSpeedLimit = 2.0, -- boat must be slower than this (studs per second) to cast
	biteMin = 4,
	biteMax = 14,
	biteWindow = 1.8, -- seconds to start reeling after the bite
	tensionUp = 0.55, -- per second while reel is held
	tensionDown = 0.45, -- per second while released
	zoneWidth = { 0.34, 0.28, 0.22 }, -- by fish points 1, 2, 3
	zoneDrift = { 0.10, 0.16, 0.22 }, -- how fast the safe band wanders, by points
	progressUp = { 0.20, 0.15, 0.11 }, -- per second inside the band, by points
	progressDown = 0.06, -- per second outside the band
	snapAfter = 0.6, -- seconds at full tension before the line snaps
	slackAfter = 1.2, -- seconds at zero tension before the fish is gone
	decideSeconds = 12, -- keep or throw back; if time runs out the fish is kept
	holdMax = 4,
	wrongPointsMult = 3,
	teachWrongByCatch = 3, -- on the night Wrong Catch is new, one appears by this catch
}

Config.Lantern = {
	burnSeconds = 430, -- a full lantern left on lasts this long (about 80% of a night)
	lowAt = 0.2,
	refillsPerNight = 1,
	forcedOutSeconds = 12, -- when a rule kills the lantern
}

Config.Boat = {
	rowSpeed = 10, -- studs per second
	motorSpeed = 28,
	accel = 6,
	drag = 1.2,
	turnRate = 1.1, -- radians per second at full steer
	stillSpeed = 1.5, -- below this the boat counts as still
	motorSoundMask = 0.75, -- how much of the chorus the motor hides (for SoundMix)
}

-- The lake's attention, 0..1. Its only display is the frog chorus.
Config.Attention = {
	motorPerSec = 0.02,
	lanternPerSec = 0.004,
	reelPerSec = 0.008, -- per reeling player
	keptWrong = 0.25, -- added at once
	keptWrongFloor = 0.15, -- attention cannot fall below this per kept wrong catch (stacks)
	decayPerSec = 0.012, -- when still and quiet
	safeDecayPerSec = 0.05, -- inside the dock light
	budgetBonusAt = 0.7, -- sustained attention above this adds one real scare
	budgetBonusSeconds = 45,
	calmShrink = 0.35, -- high attention shortens calm phases by up to this fraction
}

Config.Director = {
	calmMin = 40,
	calmMax = 70,
	buildMin = 25,
	buildMax = 45,
	fakeGap = 20, -- seconds between fake-outs
	fakeClear = 8, -- no fake-out this close before or after a real cue
	onlyOneChance = 0.35, -- chance a fake-out goes to one player only
	chorusBands = { 0.3, 0.55, 0.8 }, -- tension thresholds: below first is band 3, then 2, then 1
	soloCueMinSeconds = 12, -- a real cue shown to one player must leave at least this long
}

Config.Fakeouts = {
	"LoonScream",
	"BranchSnap",
	"FishJump",
	"SingleKnock",
	"ChorusDip",
	"BuoyClank",
	"LanternFlicker",
	"FireflyLight",
}

Config.Rules = {
	Hum = {
		silence = 2.5, -- chorus is dead before the hum is heard
		warn = 5, -- seconds from the hum starting until everyone must comply
		holdMin = 10,
		holdMax = 15,
		grace = 0.6, -- total seconds of noise forgiven during the hold
	},
	WrongCatch = {
		knockDelayMin = 60, -- after a kept wrong fish is banked, the cooler knocks back this much later
		knockDelayMax = 140,
		fishEaten = 2, -- banked fish lost when the cooler knocks
	},
	Neighbor = {
		spawnMin = 160,
		spawnMax = 220,
		driftSpeed = 3,
		holdDist = 90,
		lingerMin = 25,
		lingerMax = 35,
		killDist = 45,
		falseBeaconChance = 0.35,
		falseBeaconDist = 320,
		falseBeaconKill = 60,
		falseBeaconSeconds = 60,
	},
	Knocking = {
		knockGap = 1.1,
		answer = 2,
		window = 6,
		secondWindow = 4.5,
		floodSeconds = 45, -- time to sink with nobody bailing
		bailSeconds = 30, -- one bailer empties a full boat in this long
		floodLasts = 20, -- water stops coming in after this
	},
	Watcher = {
		shoreRange = 260, -- boat must be this close to a shore for it to appear
		spawnMin = 120,
		steps = 5, -- steps from the trees to the waterline
		unwatchedStep = 4, -- seconds unwatched per step
		stareLimit = 3.5, -- seconds of staring before it lunges
		stareSteps = 2,
		stareCone = 0.44, -- radians (25 degrees): inside is staring
		edgeCone = 1.22, -- radians (70 degrees): between the cones is the edge of sight
		presence = 40, -- it leaves after this long if held off
		retreatDist = 320, -- or if the boat gets this far away
	},
	Finale = {
		hour = 28, -- 4 AM on night 5
		oilSeconds = 75, -- lantern burns out this long after the bell (scaled by warning)
		stopLimit = 4, -- seconds the boat may sit still
		neighborEvery = 14,
		needSpecies = "SteepleCat", -- the owner's special order: one must be in the hold or banked
	},
}

-- The owner's amendments. The first variant is the rule as printed. The cue never changes.
Config.Amendments = {
	Hum = { "LanternOut", "LanternLit" },
	Knocking = { "AnswerTwo", "AnswerOne", "AnswerNone" },
	Watcher = { "EdgeOfSight", "StareItDown" },
	Neighbor = { "NoWave", "NoWaveLanternOut" },
}

Config.Water = {
	dragSeconds = 6, -- a swimmer outside the dock light is taken after this long
	warnAt = 2,
}

Config.Ghost = { bellCooldown = 15 }

-- Between nights the crew picks one of three.
Config.Supplies = {
	OilCan = { name = "Spare Oil Can", text = "One more refill at the dock each night." },
	WaxedOars = { name = "Waxed Oars", text = "Row a fifth faster." },
	BigCooler = { name = "Second Stringer", text = "The boat holds two more fish." },
	LuckyLure = { name = "Lucky Lure", text = "Bites come a quarter sooner." },
	Spectacles = { name = "Owner's Spectacles", text = "Wrong fish are a little easier to spot." },
	BrassBell = { name = "Brass Bell", text = "The drowned ring louder and more often." },
	TrimmedWick = { name = "Trimmed Wick", text = "The lantern burns a little slower." },
	Thermos = { name = "Thermos", text = "A steadier crew: a little more time to react." },
}

-- Fixed phrases only. No free text anywhere in the game.
Config.Callouts = {
	"FrogsStopped",
	"LanternOut",
	"LanternOn",
	"HoldStill",
	"KnockOnce",
	"KnockTwice",
	"DontKnock",
	"DontWave",
	"DontLook",
	"LookAtIt",
	"ThrowItBack",
	"GoHome",
	"Wave",
}

Config.Net = {
	gazeHz = 5, -- gaze reports per second accepted
	boatHz = 20, -- helm input per second accepted
	intentBurst = 8, -- token bucket size for button intents
	intentPerSec = 6,
}

-- Cosmetics are earned by playing. No Robux anywhere.
Config.Cosmetics = {
	lantern = { "Amber", "BoneWhite", "MarshGreen", "BlueHour" },
	paint = { "BareWood", "Oxblood", "HullBlack", "RobinEgg" },
	hat = { "None", "BucketHat", "Souwester" },
}

return Config
