--!strict
-- Every sound the game plays, by name. Id 0 means "not available yet": the shell skips it
-- silently. Every nonzero id must be listed in audio/ids.json with its source, or the gate
-- fails (tools/lint/asset_ids.py).
--
-- One entry per id in audio/sounds.json (same key) plus the tapes in audio/tapes.json.
-- To add a sound: upload it, record it in audio/ids.json, then set `id` here. AudioDirector
-- starts ambience layers and one-shots automatically for any id that is nonzero.
-- minDist and maxDist are the rolloff range for spatial sounds (studs).
--
-- Derived sounds (11/26/2026, while the account's audio uploads are capped until about
-- 12/26/2026): an entry with id 0 may carry a `derive` table instead. AudioDirector builds it
-- from another entry's real id (`from`) with PlaybackSpeed, a PlaybackRegion, SoundEffect
-- children, delayed layers and a repeat timer. Callers play it by name like any other sound.
-- `from` (and every layer's `from`) must name an entry with a real id; the lint checks it.
-- When the real upload lands: set the id, delete the derive table.
--   from         source entry name (real id)
--   speed        PlaybackSpeed (pitch and tempo together)
--   region       { start, stop } in seconds of the source (PlaybackRegion)
--   effects      { { class = "<SoundEffect class>", props = { Prop = n } } }, see EFFECT_PROPS
--   volume       layers only: multiplier on the entry's volume
--   delay        layers only: seconds after the sound starts
--   duration     seconds the piece lasts before it is cut (one-shots and loops)
--   fadeIn, fadeOut  seconds; fadeOut ends at `duration`
--   repeatEvery  replay the piece every n seconds (a loop for looped entries; one-shots need
--                a duration)
--   layers       more pieces, each a table of the fields above
-- `["repeat"] = { count, gap }` (any entry, real or derived) plays the whole sound `count`
-- times, `gap` seconds apart (library knocks are single thuds).
-- Scare polish 2 (11/26/2026):
--   with   other entry names started together with this one, at the same place and with
--          the same options (the knocks' low thump layer); they stop when it is destroyed
--   duck   false keeps a Rule-group sound from ducking the ambience (every other Rule sound
--          ducks it while it plays, see Look.Mix.cueDuck)

export type Group = "Ambience" | "Boat" | "Fishing" | "Rule" | "UI" | "Music" | "Voice"

export type Effect = { class: string, props: { [string]: number }? }

export type Derive = {
	from: string,
	speed: number?,
	region: { number }?,
	effects: { Effect }?,
	volume: number?,
	delay: number?,
	duration: number?,
	fadeIn: number?,
	fadeOut: number?,
	repeatEvery: number?,
	layers: { Derive }?,
}

export type RepeatSpec = { count: number, gap: number }

export type SoundEntry = {
	id: number,
	volume: number?,
	looped: boolean?,
	spatial: boolean?,
	group: Group?, -- mix group, see Look.Mix.groups
	minDist: number?,
	maxDist: number?,
	derive: Derive?,
	["repeat"]: RepeatSpec?,
	with: { string }?,
	duck: boolean?,
}

local SoundRegistry = {}

SoundRegistry.GROUPS = { "Ambience", "Boat", "Fishing", "Rule", "UI", "Music", "Voice" } :: { Group }

-- The SoundEffect classes and properties a derive may set. Checked against
-- create.roblox.com/docs on 11/26/2026: all exist, none deprecated. Ranges from the docs:
-- gains and levels in dB -80..10; Reverb DecayTime 0.1..20; Echo Delay 0.01..5 s;
-- Distortion Level 0..1; PitchShift Octave 0.5..2 (one octave down..up per effect, so stack
-- effects for more); Tremolo Frequency 0.1..20, Depth and Duty 0..1. Priority orders effects
-- (higher first, 0 is the default). There is no band-pass class: use an EqualizerSoundEffect
-- with LowGain and HighGain cut.
SoundRegistry.EFFECT_PROPS = {
	EqualizerSoundEffect = { HighGain = true, MidGain = true, LowGain = true, Priority = true },
	ReverbSoundEffect = {
		DecayTime = true,
		Density = true,
		Diffusion = true,
		DryLevel = true,
		WetLevel = true,
		Priority = true,
	},
	EchoSoundEffect = { Delay = true, DryLevel = true, Feedback = true, WetLevel = true, Priority = true },
	DistortionSoundEffect = { Level = true, Priority = true },
	PitchShiftSoundEffect = { Octave = true, Priority = true },
	ChorusSoundEffect = { Depth = true, Mix = true, Rate = true, Priority = true },
	TremoloSoundEffect = { Depth = true, Duty = true, Frequency = true, Priority = true },
} :: { [string]: { [string]: boolean } }

-- audio/sounds.json
local sounds: { [string]: SoundEntry } = {
	["bed-hull-lap"] = { id = 82149066729139, volume = 0.5, looped = true, spatial = false, group = "Ambience" },
	["bed-lake-air"] = { id = 107231803674893, volume = 0.5, looped = true, spatial = false, group = "Ambience" },
	["bed-wind-trees"] = {
		id = 106088702716339,
		volume = 0.5,
		looped = true,
		spatial = true,
		group = "Ambience",
		minDist = 40,
		maxDist = 700,
	},
	["chorus-frogs-full"] = { id = 95125265524882, volume = 0.6, looped = true, spatial = false, group = "Ambience" },
	["chorus-crickets"] = { id = 84329609517658, volume = 0.6, looped = true, spatial = false, group = "Ambience" },
	["frog-first-back"] = { id = 107148567442804, volume = 0.7, looped = false, spatial = false, group = "Ambience" },
	["frog-peeper-a"] = {
		id = 111644507336636,
		volume = 0.55,
		looped = false,
		spatial = true,
		group = "Ambience",
		minDist = 40,
		maxDist = 700,
	},
	["frog-peeper-b"] = {
		id = 70895207467617,
		volume = 0.55,
		looped = false,
		spatial = true,
		group = "Ambience",
		minDist = 40,
		maxDist = 700,
	},
	["frog-bull-a"] = {
		id = 115607930670826,
		volume = 0.55,
		looped = false,
		spatial = true,
		group = "Ambience",
		minDist = 40,
		maxDist = 700,
	},
	["frog-bull-b"] = {
		id = 86239846520818,
		volume = 0.55,
		looped = false,
		spatial = true,
		group = "Ambience",
		minDist = 40,
		maxDist = 700,
	},
	["frog-gray-a"] = {
		id = 105495499452464,
		volume = 0.55,
		looped = false,
		spatial = true,
		group = "Ambience",
		minDist = 40,
		maxDist = 700,
	},
	["frog-green-a"] = {
		id = 114707982207463,
		volume = 0.55,
		looped = false,
		spatial = true,
		group = "Ambience",
		minDist = 40,
		maxDist = 700,
	},
	["loon-call"] = {
		id = 70768048790401,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Ambience",
		minDist = 40,
		maxDist = 700,
	},
	["loon-tremolo"] = {
		id = 73252861727593,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Ambience",
		minDist = 40,
		maxDist = 700,
	},
	["owl-hoot"] = {
		id = 125542025359851,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Ambience",
		minDist = 40,
		maxDist = 700,
	},
	["oar-stroke-a"] = {
		id = 98369926767605,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["oar-stroke-b"] = {
		id = 100635770775586,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["oarlock-creak"] = {
		id = 99132082822278,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["hull-creak"] = {
		id = 99949033701523,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["motor-start"] = {
		id = 100574507808603,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	-- Scare polish 2: Neon could not hear the motor in two clips. Louder, and full level
	-- anywhere in the boat (minDist 12).
	["motor-idle-loop"] = {
		id = 112605178204236,
		volume = 1.4,
		looped = true,
		spatial = true,
		group = "Boat",
		minDist = 12,
		maxDist = 140,
	},
	["motor-stop"] = {
		id = 92446962847841,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["lantern-on"] = {
		id = 87048960934007,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["lantern-off"] = {
		id = 74526415801575,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["lantern-flame-loop"] = {
		id = 79552539202953,
		volume = 0.7,
		looped = true,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["lantern-squeak"] = {
		id = 99122380975608,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["dock-water-loop"] = {
		id = 87816269884236,
		volume = 0.7,
		looped = true,
		spatial = true,
		group = "Ambience",
		minDist = 8,
		maxDist = 120,
	},
	["dock-creak"] = {
		id = 86254523157733,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Ambience",
		minDist = 8,
		maxDist = 120,
	},
	["cooler-open"] = {
		id = 109548894003530,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["cooler-close"] = {
		id = 113433863652835,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["oil-refill"] = {
		id = 77006642621475,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Boat",
		minDist = 4,
		maxDist = 90,
	},
	["radio-static-loop"] = {
		id = 106357675483653,
		volume = 0.7,
		looped = true,
		spatial = true,
		group = "Ambience",
		minDist = 6,
		maxDist = 170,
	},
	["radio-tune-1"] = {
		id = 73606075287940,
		volume = 0.7,
		looped = true,
		spatial = true,
		group = "Ambience",
		minDist = 6,
		maxDist = 170,
	},
	["radio-tune-2"] = {
		id = 140690385837815,
		volume = 0.7,
		looped = true,
		spatial = true,
		group = "Ambience",
		minDist = 6,
		maxDist = 170,
	},
	["cast-whoosh"] = {
		id = 92124052240173,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Fishing",
		minDist = 4,
		maxDist = 90,
	},
	["line-plop"] = {
		id = 92320903076691,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Fishing",
		minDist = 4,
		maxDist = 90,
	},
	["bobber-tap"] = {
		id = 128818977028659,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Fishing",
		minDist = 4,
		maxDist = 90,
	},
	["bobber-under"] = {
		id = 85720926099384,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Fishing",
		minDist = 4,
		maxDist = 90,
	},
	["reel-click-loop"] = {
		id = 129695637905269,
		volume = 0.7,
		looped = true,
		spatial = true,
		group = "Fishing",
		minDist = 4,
		maxDist = 90,
	},
	["line-creak"] = {
		id = 136606003639961,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Fishing",
		minDist = 4,
		maxDist = 90,
	},
	["line-snap"] = {
		id = 115099972696353,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Fishing",
		minDist = 4,
		maxDist = 90,
	},
	["fish-splash-small"] = {
		id = 78714006518452,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Fishing",
		minDist = 4,
		maxDist = 90,
	},
	["fish-splash-big"] = {
		id = 132324525183589,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Fishing",
		minDist = 4,
		maxDist = 90,
	},
	["fish-land-thud"] = {
		id = 121930116231581,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Fishing",
		minDist = 4,
		maxDist = 90,
	},
	["fish-release"] = {
		id = 83053999749150,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Fishing",
		minDist = 4,
		maxDist = 90,
	},
	["quota-met"] = { id = 74964876913374, volume = 0.7, looped = false, spatial = false, group = "Fishing" },
	["hum-rise"] = { id = 93285128856151, volume = 0.9, looped = false, spatial = false, group = "Rule" },
	["hum-hold-loop"] = { id = 139783212326514, volume = 0.9, looped = true, spatial = false, group = "Rule" },
	-- Scare polish 2: the hum's mid-range layer for phone speakers. Two octaves up puts the
	-- sub-bass fundamental near 150 to 250 Hz (inside LowGain, which is below 400 Hz); mids
	-- and highs are cut so it stays a hull resonance, a touch of distortion adds the buzz.
	["hum-hull-resonance"] = {
		id = 0,
		volume = 0.55,
		looped = true,
		spatial = false,
		group = "Rule",
		derive = {
			from = "hum-hold-loop",
			effects = {
				{ class = "PitchShiftSoundEffect", props = { Octave = 2, Priority = 4 } },
				{ class = "PitchShiftSoundEffect", props = { Octave = 2, Priority = 3 } },
				{ class = "DistortionSoundEffect", props = { Level = 0.18, Priority = 2 } },
				{ class = "EqualizerSoundEffect", props = { LowGain = 2, MidGain = -9, HighGain = -30, Priority = 1 } },
			},
		},
	},
	["hum-pass"] = { id = 127034738461551, volume = 0.7, looped = false, spatial = false, group = "Rule" },
	["hum-fail"] = { id = 97194209521825, volume = 0.7, looped = false, spatial = false, group = "Rule" },
	["hold-lost-splash"] = {
		id = 139756463189300,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 4,
		maxDist = 90,
	},
	["death-drag"] = { id = 112545370208743, volume = 0.7, looped = false, spatial = false, group = "Rule" },
	["death-sting"] = { id = 120117132238934, volume = 0.7, looped = false, spatial = false, group = "Rule" },
	["water-pull-warning"] = { id = 125472514231870, volume = 0.7, looped = false, spatial = false, group = "Rule" },
	["ghost-bell"] = {
		id = 109354337663641,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 4,
		maxDist = 90,
	},
	["ghost-loop"] = {
		id = 94730476572844,
		volume = 0.7,
		looped = true,
		spatial = false,
		group = "Rule",
		duck = false,
	},
	["wrong-blink"] = {
		id = 0,
		volume = 0.35,
		looped = false,
		spatial = true,
		minDist = 4,
		maxDist = 90,
		group = "Rule",
		derive = { from = "lantern-squeak", region = { 0, 0.1 }, speed = 2.5 },
	},
	["wrong-glow-loop"] = {
		id = 0,
		volume = 0.12,
		looped = true,
		spatial = true,
		minDist = 4,
		maxDist = 90,
		group = "Rule",
		derive = {
			from = "hum-hold-loop",
			effects = {
				{ class = "PitchShiftSoundEffect", props = { Octave = 2, Priority = 4 } },
				{ class = "PitchShiftSoundEffect", props = { Octave = 2, Priority = 3 } },
				{ class = "PitchShiftSoundEffect", props = { Octave = 2, Priority = 2 } },
				{ class = "TremoloSoundEffect", props = { Frequency = 3, Depth = 0.5, Priority = 1 } },
			},
		},
	},
	["cooler-knock-inside"] = {
		id = 0,
		volume = 1.1,
		looped = false,
		spatial = true,
		minDist = 30,
		maxDist = 300,
		group = "Rule",
		derive = {
			from = "knock-answer",
			effects = { { class = "EqualizerSoundEffect", props = { LowGain = 4, HighGain = -30, MidGain = -8 } } },
		},
		["repeat"] = { count = 3, gap = 0.9 },
	},
	["cooler-eaten"] = {
		id = 0,
		volume = 0.65,
		looped = false,
		spatial = true,
		minDist = 4,
		maxDist = 90,
		group = "Rule",
		derive = {
			from = "cooler-close",
			speed = 0.7,
			layers = { { from = "fish-land-thud", delay = 0.2, volume = 0.9 } },
		},
	},
	-- Scare polish 2: distance comes from the reverb and a gentle high cut, not from volume.
	-- minDist covers the Neighbor's real distance (Config appearDist 200, holdDist 90), so
	-- the rolloff no longer takes 15 dB off at the spot where it actually plays.
	["neighbor-oarlock-loop"] = {
		id = 0,
		volume = 1.3,
		looped = true,
		spatial = true,
		minDist = 160,
		maxDist = 900,
		group = "Rule",
		derive = {
			from = "oarlock-creak",
			speed = 0.8,
			repeatEvery = 2,
			effects = {
				{ class = "EqualizerSoundEffect", props = { HighGain = -12, MidGain = -2 } },
				{ class = "ReverbSoundEffect", props = { DecayTime = 3.5, DryLevel = -4, WetLevel = -3 } },
			},
		},
	},
	["neighbor-pass"] = {
		id = 0,
		volume = 1.3,
		looped = false,
		spatial = true,
		minDist = 160,
		maxDist = 900,
		group = "Rule",
		derive = {
			from = "oarlock-creak",
			speed = 0.8,
			repeatEvery = 2,
			duration = 6,
			fadeOut = 6,
			effects = {
				{ class = "EqualizerSoundEffect", props = { HighGain = -12, MidGain = -2 } },
				{ class = "ReverbSoundEffect", props = { DecayTime = 3.5, DryLevel = -4, WetLevel = -3 } },
			},
		},
	},
	["neighbor-fail"] = {
		id = 0,
		volume = 0.75,
		looped = false,
		spatial = false,
		group = "Rule",
		derive = { from = "lantern-off", layers = { { from = "hull-creak", delay = 0.8, speed = 0.7, volume = 1.2 } } },
	},
	-- Scare polish 2: knocks are close and dry, played from just under the hull (AudioDirector
	-- "under" anchor) at full volume anywhere in the boat (minDist 14), each with a short low
	-- thump under it (`with`).
	["knock-three-soft"] = {
		id = 9120885468,
		volume = 1.3,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 14,
		maxDist = 120,
		["repeat"] = { count = 3, gap = 1.1 },
		with = { "knock-thump-soft" },
	},
	["knock-three-hard"] = {
		id = 9126267413,
		volume = 2,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 14,
		maxDist = 120,
		["repeat"] = { count = 3, gap = 1.1 },
		with = { "knock-thump-hard" },
	},
	["knock-thump-soft"] = {
		id = 0,
		volume = 0.8,
		looped = false,
		spatial = true,
		minDist = 14,
		maxDist = 120,
		group = "Rule",
		derive = {
			from = "fish-land-thud",
			speed = 0.55,
			duration = 0.35,
			fadeOut = 0.15,
			effects = { { class = "EqualizerSoundEffect", props = { LowGain = 6, MidGain = -8, HighGain = -30 } } },
		},
		["repeat"] = { count = 3, gap = 1.1 },
	},
	["knock-thump-hard"] = {
		id = 0,
		volume = 1.3,
		looped = false,
		spatial = true,
		minDist = 14,
		maxDist = 120,
		group = "Rule",
		derive = {
			from = "fish-land-thud",
			speed = 0.45,
			duration = 0.45,
			fadeOut = 0.2,
			effects = { { class = "EqualizerSoundEffect", props = { LowGain = 8, MidGain = -6, HighGain = -30 } } },
		},
		["repeat"] = { count = 3, gap = 1.1 },
	},
	["knock-answer"] = {
		id = 9126267607,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 4,
		maxDist = 90,
	},
	["knock-pass"] = {
		id = 0,
		volume = 0.9,
		looped = false,
		spatial = true,
		minDist = 14,
		maxDist = 120,
		group = "Rule",
		derive = {
			from = "hull-creak",
			speed = 0.6,
			effects = { { class = "EqualizerSoundEffect", props = { HighGain = -30, MidGain = -8 } } },
			layers = {
				{ from = "dock-water-loop", delay = 0.6, duration = 2, fadeIn = 0.6, fadeOut = 1.2, volume = 0.7 },
			},
		},
	},
	["flood-in-loop"] = {
		id = 0,
		volume = 0.8,
		looped = true,
		spatial = true,
		minDist = 4,
		maxDist = 90,
		group = "Rule",
		derive = {
			from = "dock-water-loop",
			speed = 1.3,
			effects = { { class = "EqualizerSoundEffect", props = { HighGain = -12 } } },
		},
	},
	["bail-scoop"] = {
		id = 109267501301998,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 4,
		maxDist = 90,
	},
	["boat-sink"] = {
		id = 0,
		volume = 0.7,
		looped = false,
		spatial = false,
		group = "Rule",
		derive = { from = "hold-lost-splash", layers = { { from = "death-drag", delay = 0.6 } } },
	},
	["watcher-tone-loop"] = {
		id = 0,
		volume = 0.12,
		looped = true,
		spatial = false,
		group = "Rule",
		derive = {
			from = "hum-hold-loop",
			effects = {
				-- Scare polish 2: the second shift is 1.8, not 2 (about two semitones lower), to
				-- sit apart from the insects' chirps (Neon).
				{ class = "PitchShiftSoundEffect", props = { Octave = 2, Priority = 4 } },
				{ class = "PitchShiftSoundEffect", props = { Octave = 1.8, Priority = 3 } },
				{ class = "EqualizerSoundEffect", props = { LowGain = -40, HighGain = -18, Priority = 2 } },
				{ class = "TremoloSoundEffect", props = { Frequency = 0.4, Depth = 0.6, Duty = 0.5, Priority = 1 } },
			},
		},
	},
	-- Scare polish 2: the Watcher stands on a shore up to Config shoreRange (260) away, so
	-- minDist 150 keeps its steps near full level there; distance is the reverb and high cut.
	["watcher-step"] = {
		id = 0,
		volume = 1.3,
		looped = false,
		spatial = true,
		minDist = 150,
		maxDist = 900,
		group = "Rule",
		derive = {
			from = "dock-creak",
			region = { 0, 0.6 },
			speed = 0.7,
			effects = {
				{ class = "EqualizerSoundEffect", props = { LowGain = 3, HighGain = -12, MidGain = -2 } },
				{ class = "ReverbSoundEffect", props = { DecayTime = 2.5, DryLevel = -3, WetLevel = -5 } },
			},
		},
	},
	["watcher-lunge"] = {
		id = 0,
		volume = 1.5,
		looped = false,
		spatial = true,
		minDist = 150,
		maxDist = 900,
		group = "Rule",
		derive = {
			from = "dock-creak",
			region = { 0, 0.6 },
			speed = 1.4,
			layers = {
				{ from = "dock-creak", region = { 0, 0.6 }, speed = 1.4, delay = 0.3 },
				{ from = "dock-creak", region = { 0, 0.6 }, speed = 1.4, delay = 0.6 },
			},
		},
	},
	["watcher-fail"] = {
		id = 0,
		volume = 0.7,
		looped = false,
		spatial = false,
		group = "Rule",
		derive = {
			from = "hum-pass",
			region = { 0, 1 },
			speed = 0.6,
			layers = { { from = "fish-release", delay = 1.8, speed = 0.6 } },
		},
	},
	["watcher-pass"] = {
		id = 0,
		volume = 0.5,
		looped = false,
		spatial = true,
		minDist = 40,
		maxDist = 700,
		group = "Rule",
		derive = { from = "bed-wind-trees", duration = 4, fadeIn = 1.5, fadeOut = 2 },
	},
	["lanterns-die"] = {
		id = 0,
		volume = 0.6,
		looped = false,
		spatial = false,
		group = "Rule",
		derive = {
			from = "lantern-off",
			layers = {
				{ from = "lantern-off", delay = 0.15, speed = 0.94 },
				{ from = "lantern-off", delay = 0.3, speed = 1.07 },
			},
		},
	},
	["fake-loon-scream"] = {
		id = 0,
		volume = 0.7,
		looped = false,
		spatial = true,
		minDist = 40,
		maxDist = 700,
		group = "Rule",
		derive = {
			from = "loon-call",
			speed = 1.15,
			effects = { { class = "DistortionSoundEffect", props = { Level = 0.2 } } },
		},
	},
	["fake-branch-snap"] = {
		id = 9120258724,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 40,
		maxDist = 700,
	},
	["fake-fish-jump"] = {
		id = 9119481909,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 4,
		maxDist = 90,
	},
	["fake-single-knock"] = {
		id = 9126267639,
		volume = 1.2,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 14,
		maxDist = 120,
	},
	["fake-buoy-clank"] = {
		id = 9126005978,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 20,
		maxDist = 400,
	},
	["fake-lantern-flicker"] = {
		id = 0,
		volume = 0.5,
		looped = false,
		spatial = true,
		minDist = 4,
		maxDist = 90,
		group = "Rule",
		derive = {
			from = "lantern-flame-loop",
			duration = 1.2,
			fadeIn = 0.2,
			fadeOut = 0.4,
			effects = { { class = "TremoloSoundEffect", props = { Frequency = 7, Depth = 0.8 } } },
		},
	},
	["bell-dock-solo"] = {
		id = 74186365454636,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 40,
		maxDist = 700,
	},
	["bell-underwater"] = {
		id = 100107464196456,
		volume = 0.7,
		looped = false,
		spatial = true,
		group = "Rule",
		minDist = 4,
		maxDist = 90,
	},
	["lake-silence-drop"] = {
		id = 0,
		volume = 0.6,
		looped = false,
		spatial = false,
		group = "Rule",
		derive = { from = "hum-pass", region = { 0, 1 }, speed = 0.6 },
	},
	["lake-groan"] = {
		id = 0,
		volume = 0.6,
		looped = false,
		spatial = false,
		group = "Rule",
		derive = {
			from = "hum-fail",
			speed = 0.45,
			effects = { { class = "ReverbSoundEffect", props = { DecayTime = 8, DryLevel = -4, WetLevel = -2 } } },
		},
	},
	["finale-bed"] = { id = 9043560891, volume = 0.5, looped = true, spatial = false, group = "Music" },
	["title-theme"] = {
		id = 0,
		volume = 0.5,
		looped = true,
		spatial = false,
		group = "Music",
		derive = { from = "radio-tune-1" },
	},
	["dawn-cue"] = { id = 9045880234, volume = 0.5, looped = false, spatial = false, group = "Music" },
	["run-cleared"] = {
		id = 0,
		volume = 0.5,
		looped = false,
		spatial = false,
		group = "Music",
		derive = { from = "radio-tune-2", duration = 40, fadeOut = 4 },
	},
	["night-cleared-sting"] = {
		id = 0,
		volume = 0.5,
		looped = false,
		spatial = false,
		group = "Music",
		derive = { from = "quota-met" },
	},
	["night-failed-sting"] = {
		id = 0,
		volume = 0.5,
		looped = false,
		spatial = false,
		group = "Music",
		derive = { from = "death-sting" },
	},
	["ui-book-open"] = { id = 9118834867, volume = 0.5, looped = false, spatial = false, group = "UI" },
	["ui-book-close"] = { id = 0, volume = 0.5, looped = false, spatial = false, group = "UI" },
	["ui-page-turn"] = { id = 9118836942, volume = 0.5, looped = false, spatial = false, group = "UI" },
	["ui-tape-click"] = { id = 0, volume = 0.5, looped = false, spatial = false, group = "UI" },
	["ui-tape-stop"] = { id = 0, volume = 0.5, looped = false, spatial = false, group = "UI" },
	["ui-pencil-scratch"] = { id = 0, volume = 0.5, looped = false, spatial = false, group = "UI" },
	["ui-stamp"] = {
		id = 0,
		volume = 0.45,
		looped = false,
		spatial = false,
		group = "UI",
		derive = { from = "knock-answer", region = { 0, 0.18 }, speed = 1.5 },
	},
	["ui-envelope"] = { id = 0, volume = 0.5, looped = false, spatial = false, group = "UI" },
	["ui-tick"] = {
		id = 0,
		volume = 0.35,
		looped = false,
		spatial = false,
		group = "UI",
		derive = { from = "cooler-close", region = { 0, 0.06 }, speed = 2.2 },
	},
	["callout-blip"] = {
		id = 0,
		volume = 0.35,
		looped = false,
		spatial = true,
		minDist = 4,
		maxDist = 90,
		group = "UI",
		derive = { from = "knock-answer", region = { 0, 0.06 }, speed = 2.6 },
	},
	-- Added by shell S3 (not in audio/sounds.json yet): a rod dropped on the floorboards when its owner is taken.
	["rod-clatter"] = {
		id = 0,
		volume = 0.6,
		looped = false,
		spatial = true,
		minDist = 4,
		maxDist = 90,
		group = "Rule",
		derive = { from = "fish-land-thud", speed = 1.6 },
	},
	-- Polish 3 (Neon's finale review, 11/26/2026): derived stand-ins for the finale and dawn.
	-- The bell at 4 AM after dead silence: loud from anywhere on the lake, echoing.
	-- Finale v2: non-spatial (a spatial bell at the dock was inaudible from the steeple,
	-- about 600 studs out). It plays from SoundService at full strength everywhere.
	["finale-bell"] = {
		id = 0,
		volume = 1.0,
		looped = false,
		spatial = false,
		group = "Rule",
		duck = false,
		derive = {
			from = "bell-dock-solo",
			effects = {
				{ class = "EchoSoundEffect", props = { Delay = 0.42, Feedback = 0.4, DryLevel = 0, WetLevel = -5 } },
				{ class = "ReverbSoundEffect", props = { DecayTime = 5, DryLevel = -2, WetLevel = -6 } },
			},
		},
	},
	-- The pursuit layer under the motor: the hum pitched down, pulsing (fx/Finale quickens the
	-- tremolo as the boat slows), over a darker, slower finale bed.
	["finale-chase-drone"] = {
		id = 0,
		volume = 0.55,
		looped = true,
		spatial = false,
		group = "Music",
		derive = {
			from = "hum-hold-loop",
			speed = 0.7,
			effects = {
				{ class = "TremoloSoundEffect", props = { Frequency = 1.6, Depth = 0.6 } },
				{ class = "EqualizerSoundEffect", props = { LowGain = 4, MidGain = -2, HighGain = -14 } },
			},
		},
	},
	["finale-chase-under"] = {
		id = 0,
		volume = 0.32,
		looped = true,
		spatial = false,
		group = "Music",
		derive = {
			from = "finale-bed",
			speed = 0.8,
			effects = {
				{ class = "EqualizerSoundEffect", props = { LowGain = 2, MidGain = -3, HighGain = -12 } },
				{ class = "ReverbSoundEffect", props = { DecayTime = 3, DryLevel = -2, WetLevel = -8 } },
			},
		},
	},
	-- Distant unnatural sounds from the finale's hazards: a whine at a false beacon, a toll
	-- through water when one appears.
	["finale-hazard-whine"] = {
		id = 0,
		volume = 0.5,
		looped = true,
		spatial = true,
		minDist = 50,
		maxDist = 500,
		group = "Rule",
		duck = false,
		derive = {
			from = "hum-hold-loop",
			effects = {
				{ class = "PitchShiftSoundEffect", props = { Octave = 2, Priority = 3 } },
				{ class = "TremoloSoundEffect", props = { Frequency = 5, Depth = 0.7, Priority = 2 } },
				{
					class = "EqualizerSoundEffect",
					props = { LowGain = -30, MidGain = 0, HighGain = -10, Priority = 1 },
				},
				{ class = "ReverbSoundEffect", props = { DecayTime = 4, DryLevel = -4, WetLevel = -2 } },
			},
		},
	},
	["finale-hazard-toll"] = {
		id = 0,
		volume = 0.8,
		looped = false,
		spatial = true,
		minDist = 60,
		maxDist = 600,
		group = "Rule",
		duck = false,
		derive = {
			from = "bell-underwater",
			speed = 0.75,
			effects = { { class = "ReverbSoundEffect", props = { DecayTime = 6, DryLevel = -3, WetLevel = -1 } } },
		},
	},
	-- Dawn birds: no bird recording exists yet, so peepers sped up into chirps with a loon
	-- far off. A stand-in to replace with a real dawn chorus upload.
	["dawn-birds"] = {
		id = 0,
		volume = 0.45,
		looped = false,
		spatial = false,
		group = "Music",
		derive = {
			from = "frog-peeper-a",
			speed = 1.5,
			layers = {
				{ from = "frog-peeper-b", speed = 1.75, delay = 0.7, volume = 0.8 },
				{ from = "loon-call", speed = 1.35, delay = 1.6, volume = 0.45 },
			},
		},
		["repeat"] = { count = 3, gap = 2.4 },
	},
}

-- audio/tapes.json (the owner's voice)
local tapes: { [string]: SoundEntry } = {
	["tape-night-1"] = { id = 101850613359911, volume = 1, looped = false, spatial = false, group = "Voice" },
	["tape-night-2"] = { id = 77115207199664, volume = 1, looped = false, spatial = false, group = "Voice" },
	["tape-night-3"] = { id = 118630441803216, volume = 1, looped = false, spatial = false, group = "Voice" },
	["tape-night-4"] = { id = 106557648851301, volume = 1, looped = false, spatial = false, group = "Voice" },
	["tape-night-5"] = { id = 126859445197865, volume = 1, looped = false, spatial = false, group = "Voice" },
	["tape-amended"] = { id = 116256975763999, volume = 1, looped = false, spatial = false, group = "Voice" },
	["tape-night-failed"] = { id = 84674041475848, volume = 1, looped = false, spatial = false, group = "Voice" },
	["tape-run-cleared"] = { id = 98400071277465, volume = 1, looped = false, spatial = false, group = "Voice" },
	["tape-endless"] = { id = 74383841194194, volume = 1, looped = false, spatial = false, group = "Voice" },
	["tape-title"] = { id = 93311841197490, volume = 1, looped = false, spatial = false, group = "Voice" },
}

SoundRegistry.entries = {} :: { [string]: SoundEntry }
for name, entry in sounds do
	SoundRegistry.entries[name] = entry
end
for name, entry in tapes do
	SoundRegistry.entries[name] = entry
end

function SoundRegistry.get(name: string): SoundEntry?
	return SoundRegistry.entries[name]
end

-- The real id behind a name: its own id, or for a derived entry its source's id. 0 if none.
local function realId(name: string): number
	local e = SoundRegistry.entries[name]
	if e == nil then
		return 0
	end
	if e.id ~= 0 then
		return e.id
	end
	local d = e.derive
	if d then
		local src = SoundRegistry.entries[d.from]
		if src and src.id ~= 0 then
			return src.id
		end
	end
	return 0
end

-- True when the sound can be played: a real id, or a derive whose source has one.
function SoundRegistry.available(name: string): boolean
	return realId(name) ~= 0
end

-- True when the entry is built in the engine from another sound.
function SoundRegistry.isDerived(name: string): boolean
	local e = SoundRegistry.entries[name]
	return e ~= nil and e.id == 0 and e.derive ~= nil
end

-- The content string for a playable entry (a derived entry gives its source's), or nil when
-- there is nothing to play (skip silently).
function SoundRegistry.uri(name: string): string?
	local id = realId(name)
	if id == 0 then
		return nil
	end
	return "rbxassetid://" .. tostring(id)
end

return SoundRegistry
