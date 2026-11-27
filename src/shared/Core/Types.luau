--!strict
-- Shared types for the pure rules engine (the contract).
-- The server shell and the Lune simulator both code against this file.
-- Additive changes only: add fields or kinds freely, but never rename or remove
-- one without a line in DECISIONS.md.

-- Lake positions are 2D, in studs. Origin is the lake center. +z is north, +x is east.
export type Vec2 = { x: number, z: number }

export type Difficulty = "Normal" | "Nightmare"
export type Mode = "Story" | "Endless"

-- Stable key for a player: UserId on the server, 1..4 in simulations.
export type PlayerId = number

-- Rule ids. One module per id under Core/entities.
export type RuleId = "Hum" | "WrongCatch" | "Neighbor" | "Knocking" | "Watcher" | "Finale"

-- What the world reports about one player this tick. Observations, never decisions.
export type PlayerObs = {
	id: PlayerId,
	seated: boolean, -- in a boat seat
	helm: boolean, -- in the helm seat
	inWater: boolean, -- swimming, outside the dock's safe light
	gazeYaw: number, -- radians, world space, atan2(look.x, look.z). Client reported, range checked.
	bookOpen: boolean, -- rulebook or field guide is covering the view
	touch: boolean?, -- plays on a touch screen (the Watcher's cones are wider)
	present: boolean?, -- false: left the game mid-night (rules never count or take them); nil means present
}

export type BoatObs = {
	pos: Vec2,
	vel: Vec2,
	heading: number, -- radians, same convention as gazeYaw
	throttle: number, -- -1..1, helm input this tick after the server clamp
	steer: number, -- -1..1
}

export type IntentKind =
	"ToggleLantern"
	| "ToggleMotor"
	| "Cast" -- num = power 0..1
	| "ReelHold" -- flag = held
	| "CutLine"
	| "CatchDecision" -- flag = keep
	| "Bank"
	| "RefillOil"
	| "Knock"
	| "Wave"
	| "BailHold" -- flag = held
	| "GhostBell"
	| "Callout" -- text = phrase id from Config.Callouts

-- A discrete player action since the last tick. Net has already validated it.
export type Intent = {
	kind: IntentKind,
	player: PlayerId,
	num: number?,
	flag: boolean?,
	text: string?,
}

export type NightInput = {
	dt: number,
	boat: BoatObs,
	players: { PlayerObs },
	intents: { Intent },
}

-- Everything the rules want the world to show or do comes out as events.
-- `kind` values are listed in docs/ARCHITECTURE.md (Events).
export type Event = {
	kind: string,
	entity: RuleId?, -- for entity events
	player: PlayerId?, -- the subject (who caught it, who died)
	only: PlayerId?, -- if set, present this to that one player only
	data: { [string]: any }?,
}

export type FishingPhase = "Idle" | "Waiting" | "Bite" | "Reeling" | "Deciding"

export type PlayerView = {
	id: PlayerId,
	alive: boolean,
	fishing: FishingPhase,
	tension: number, -- 0..1
	zoneLo: number, -- 0..1, the safe band of the reel bar
	zoneHi: number,
	progress: number, -- 0..1
	bailing: boolean,
}

export type NightPhase = "Night" | "Finale" | "Cleared" | "Failed"

-- The replicated snapshot the HUD and the audio mix read. Small on purpose.
export type NightView = {
	night: number,
	mode: Mode,
	difficulty: Difficulty,
	phase: NightPhase,
	clock: number, -- game hours, 22.0 at start, 29.0 is 5 AM
	timeLeft: number, -- real seconds
	quota: number, -- points needed
	banked: number, -- points banked
	hold: number, -- fish in the boat
	holdMax: number,
	oil: number, -- 0..1
	refills: number, -- oil cans left at the dock tonight
	lanternOn: boolean,
	motorOn: boolean,
	chorus: number, -- frog chorus band: 3 full, 2 thin, 1 sparse, 0 silent
	flood: number, -- 0..1 water in the boat
	safe: boolean, -- boat is inside the dock light
	rules: { RuleId }, -- rules taped into the book so far
	players: { PlayerView },
}

-- Checkable traits of a fish. The Field Guide lists the true values per species.
export type Tail = "Forked" | "Round" | "Square" | "Uneven"
export type Traits = {
	eyes: number,
	dorsal: number, -- dorsal fins
	stripes: number, -- vertical bars
	barbels: number, -- whiskers
	tail: Tail,
	eyeshine: boolean, -- eyes shine in lantern light (normal for exactly one species)
	glow: boolean, -- body glow (never normal)
	blinks: boolean, -- fish do not have eyelids (never normal)
	-- Added 11/26/2026 (additive, default false): glanceable tier 3 tells.
	wrongEyeDir: boolean?, -- one eye looks the wrong way (never normal)
	flipFin: boolean?, -- a fin on the wrong side (never normal)
}

export type Catch = {
	species: string, -- key into Config.Fish
	points: number,
	wrong: boolean, -- server-side truth, never sent to clients
	tier: number, -- 0 for a true fish; 1 obvious, 2 medium, 3 subtle for a wrong one
	traits: Traits, -- what the players see
}

-- One night's setup, produced by Core.Run and consumed by Core.Night.
export type NightParams = {
	seed: number,
	night: number, -- 1..5 in Story, 6+ in Endless
	mode: Mode,
	difficulty: Difficulty,
	playerIds: { PlayerId },
	rules: { RuleId }, -- rules active tonight (including tonight's new ones)
	newRules: { RuleId }, -- taught tonight with the long warning
	amendments: { [string]: string }, -- RuleId -> variant id, see Config.Amendments
	supplies: { string }?, -- supply ids picked so far this run (the pick was cut 11/26/2026; ignored)
	real: number, -- real scare budget
	fake: number, -- fake-out budget
	quietGap: number, -- seconds guaranteed quiet after a real scare resolves
	quota: number, -- points, already scaled for crew size
	maxConcurrent: number, -- real rules allowed at once
	warningScale: number, -- multiplies every warning window
}

-- Added 11/26/2026 (additive): one player's night, for the end-of-night card.
export type PlayerTally = {
	player: PlayerId,
	brokeSilence: number, -- Hum fails this player caused (the loudest)
	keptWrong: number, -- wrong fish this player kept
	knocksAnswered: number, -- knocks sent while the Knocking was out
	bailedSeconds: number, -- seconds bailing water
	timesStaredAtWatcher: number, -- times this player's gaze landed straight on the Watcher
	deaths: number,
}

export type NightResult = {
	cleared: boolean,
	banked: number,
	quota: number,
	caught: number,
	scaresSurvived: number,
	deaths: { { player: PlayerId, rule: string } },
	keptWrong: number,
	tallies: { PlayerTally }?, -- added 11/26/2026, in crew order
	bankedFish: number?, -- added in Core M5: fish (not points) in the cooler at the end (for Profile)
}

export type EntityStage = "Idle" | "Cue" | "Window" | "Pass" | "Fail" | "Cooldown"

-- What every rule module sees each tick.
export type EntityObs = {
	dt: number,
	boat: BoatObs,
	players: { PlayerObs },
	alive: { [PlayerId]: boolean },
	reeling: { [PlayerId]: boolean },
	lanternOn: boolean,
	motorOn: boolean,
	safe: boolean, -- boat inside the dock light
	intents: { Intent },
	timeLeft: number,
	-- Added in Core M3 (additive): who to blame for the boat's noise and light.
	lanternCanLight: boolean?, -- false when the lantern has no oil or a rule snuffed it
	lastLantern: PlayerId?, -- the player who last toggled the lantern tonight
	lastMotor: PlayerId?, -- the player who last toggled the motor tonight
	-- Added in Core M5 (additive): the Finale's special order (a true
	-- cfg.Rules.Finale.needSpecies fish) is in the hold or the cooler.
	specialAboard: boolean?,
}

return {}
