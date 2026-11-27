--!strict
-- One night on the lake: the composition every shell drives (docs/ARCHITECTURE.md, Night).
--
--   Night.new(cfg, params) -> NightState
--   Night.step(state, input) -> { Event }
--   Night.view(state) -> NightView
--   Night.result(state) -> NightResult?
--   Night.debugForce(state, rule, opts) -> { Event }   -- start a rule now (Studio, tests)
--
-- Owns: clock, quota, hold and cooler, lantern and refills, motor, each player's line and
-- alive flag, attention (Core.Attention), the Director, the active rules
-- (Core.entities.*), deaths, the drowned's bell (Core.Ghost), the in-water drag timer,
-- the leak, bailing and sinking, and clear and fail.
--
-- Rules never touch the crew: a rule's EntityFail carries effects (kill, loseHold, rock,
-- snuff, flood, eatBanked) and Night applies them. PlayerDied carries the rule, the
-- variant and a death card text id "Death.<Rule>.<Cause>" (Core.Rulebook maps them, M5).
-- The Finale (night 5's clock, Core M5) is not a director rule. When "Finale" is in
-- params.rules, at cfg.Rules.Finale.hour Night rings the bell: every director rule still
-- out is let go (it passes with data.endedBy = "Finale"), the director stops spawning and
-- sending fake-outs, the lantern is refilled and locked on with its oil burning down in
-- oilSeconds x warningScale, the phase becomes "Finale", and entities.Finale starts.
-- Its EntityStrike events take a player without ending it. When it passes (home with the
-- special order) the hold is banked at once and, if the quota is met, the night is cleared
-- right there (the shell skips to dawn). A Finale night is never cleared without that pass:
-- at dawn it fails with reason "SpecialOrder" (no true needSpecies fish banked) or
-- "NotHome". Before the bell the director sees the night as ending at the bell, so its
-- late cutoff keeps new scares away from 4 AM.
-- In the dock light a director rule is paused (Night.rulePaused) and the director starts
-- none; fish bite less near the dock (Fishing.dockFactor).

local Types = require(script.Parent.Types)
local Rng = require(script.Parent.Rng)
local LakeMap = require(script.Parent.LakeMap)
local NightClock = require(script.Parent.NightClock)
local Quota = require(script.Parent.Quota)
local Lantern = require(script.Parent.Lantern)
local Fishing = require(script.Parent.Fishing)
local FishTable = require(script.Parent.FishTable)
local Attention = require(script.Parent.Attention)
local Director = require(script.Parent.Director)
local Fakeouts = require(script.Parent.Fakeouts)
local Ghost = require(script.Parent.Ghost)
local Hum = require(script.Parent.entities.Hum)
local Neighbor = require(script.Parent.entities.Neighbor)
local Knocking = require(script.Parent.entities.Knocking)
local Watcher = require(script.Parent.entities.Watcher)
local WrongCatchRule = require(script.Parent.entities.WrongCatch)
local Finale = require(script.Parent.entities.Finale)
local EntityBase = require(script.Parent.EntityBase)

type Event = Types.Event
type Catch = Types.Catch
type NightParams = Types.NightParams
type NightInput = Types.NightInput
type NightView = Types.NightView
type NightResult = Types.NightResult
type RuleId = Types.RuleId
type PlayerId = Types.PlayerId
type PlayerObs = Types.PlayerObs
type EntityObs = Types.EntityObs
type PlayerTally = Types.PlayerTally

export type CrewMember = {
	id: PlayerId,
	alive: boolean,
	fishing: Fishing.FishState,
	bailing: boolean,
	inWaterFor: number,
	dragWarned: boolean,
}

export type ActiveRule = {
	id: RuleId,
	mod: any,
	state: any,
	real: boolean, -- a director rule (counts toward activeReal and the quiet gap)
}

export type NightState = {
	cfg: any,
	params: NightParams,
	rng: Rng.RngState,
	fishRng: Rng.RngState,
	fakeRng: Rng.RngState,
	coolerRng: Rng.RngState,
	clock: NightClock.ClockState,
	quota: Quota.QuotaState,
	lantern: Lantern.LanternState,
	motorOn: boolean,
	hold: { Catch },
	holdMax: number,
	cooler: { Catch },
	crew: { [PlayerId]: CrewMember },
	order: { PlayerId },
	attn: Attention.AttentionState,
	director: Director.DirectorState,
	ghost: Ghost.GhostState,
	rules: { ActiveRule },
	ruleCount: number,
	directorBand: number,
	dipFor: number,
	chorus: number,
	flood: number,
	leakOn: boolean,
	plugLeft: number, -- seconds of bailing until the leak is plugged
	floodSent: number,
	sunk: boolean,
	safe: boolean,
	boatSpeed: number,
	phase: Types.NightPhase,
	started: boolean,
	wrongChance: number,
	wrongTier: number,
	teachWrong: boolean, -- tonight teaches Wrong Catch: one wrong fish by catch N
	forceWrongNext: boolean, -- debugForce("WrongCatch"): the next fish hooked is wrong
	wrongSeen: number,
	hooked: number, -- fish hooked tonight (for the teaching guarantee)
	biteMult: number,
	caught: number,
	keptWrong: number,
	scaresSurvived: number,
	deaths: { { player: PlayerId, rule: string } },
	result: NightResult?,
	lastIntents: { Types.Intent }, -- this tick's rule-facing intents (Knock, Wave, BailHold)
	lastLantern: PlayerId?,
	lastMotor: PlayerId?,
	neighborEarliest: number,
	lastObs: EntityObs?,
	absent: { [PlayerId]: boolean }, -- left the game (PlayerObs.present == false): no rule counts or takes them
	tally: { [PlayerId]: PlayerTally },
	staring: { [PlayerId]: boolean }, -- staring at a Watcher last tick (for the tally)
	finaleNight: boolean, -- "Finale" is in tonight's rules
	finaleAt: number, -- seconds into the night when the bell rings
	finaleStarted: boolean,
	finalePassed: boolean,
	specialGiven: boolean, -- a true special-order fish has been hooked tonight
}

local Night = {}

-- The rule modules by id. Finale joins in Core M5.
Night.RULES = {
	Hum = Hum,
	Neighbor = Neighbor,
	Knocking = Knocking,
	Watcher = Watcher,
	WrongCatch = WrongCatchRule,
	Finale = Finale,
} :: { [string]: any }

local function has(list: { any }, v: any): boolean
	for _, x in list do
		if x == v then
			return true
		end
	end
	return false
end

-- Wrong Catch odds for a night: Story nights from cfg.Nights, Endless from cfg.Endless.
local function wrongOdds(cfg: any, params: NightParams): (number, number)
	if not has(params.rules, "WrongCatch") then
		return 0, 1
	end
	local n = cfg.Nights[params.night]
	if params.mode == "Endless" or n == nil then
		return cfg.Endless.wrongChance, cfg.Endless.wrongTier
	end
	return n.wrongChance, n.wrongTier
end

function Night.new(cfg: any, params: NightParams): NightState
	assert(#params.playerIds >= 1, "a night needs at least one player")
	local rng = Rng.new(params.seed)
	local tally: { [PlayerId]: PlayerTally } = {}
	local crew: { [PlayerId]: CrewMember } = {}
	local order: { PlayerId } = {}
	for _, id in params.playerIds do
		crew[id] = {
			id = id,
			alive = true,
			fishing = Fishing.new(),
			bailing = false,
			inWaterFor = 0,
			dragWarned = false,
		}
		table.insert(order, id)
		tally[id] = {
			player = id,
			brokeSilence = 0,
			keptWrong = 0,
			knocksAnswered = 0,
			bailedSeconds = 0,
			timesStaredAtWatcher = 0,
			deaths = 0,
		}
	end
	local wrongChance, wrongTier = wrongOdds(cfg, params)
	local ruleRng = Rng.fork(rng, "rules")
	local R = cfg.Rules.Neighbor
	local clock = NightClock.new(cfg)
	-- Every night starts with the lantern lit and burning (the opening row out under it).
	local lantern = Lantern.new(cfg, cfg.Lantern.refillsPerNight, 1)
	lantern.on = true
	return {
		cfg = cfg,
		params = params,
		rng = rng,
		fishRng = Rng.fork(rng, "fish"),
		fakeRng = Rng.fork(rng, "fakeouts"),
		coolerRng = Rng.fork(rng, "cooler"),
		clock = clock,
		quota = Quota.new(params.quota),
		lantern = lantern,
		motorOn = false,
		hold = {},
		holdMax = cfg.Fishing.holdMax,
		cooler = {},
		crew = crew,
		order = order,
		attn = Attention.new(),
		director = Director.new(cfg, Rng.fork(rng, "director"), params),
		ghost = Ghost.new(cfg),
		rules = {},
		ruleCount = 0,
		directorBand = 3,
		dipFor = 0,
		chorus = 3,
		flood = 0,
		leakOn = false,
		plugLeft = 0,
		floodSent = 0,
		sunk = false,
		safe = true,
		boatSpeed = 0,
		phase = "Night",
		started = false,
		wrongChance = wrongChance,
		wrongTier = wrongTier,
		teachWrong = has(params.newRules, "WrongCatch"),
		forceWrongNext = false,
		wrongSeen = 0,
		hooked = 0,
		biteMult = 1,
		caught = 0,
		keptWrong = 0,
		scaresSurvived = 0,
		deaths = {},
		result = nil,
		lastIntents = {},
		lastLantern = nil,
		lastMotor = nil,
		neighborEarliest = Rng.range(ruleRng, R.spawnMin, R.spawnMax),
		lastObs = nil,
		absent = {},
		tally = tally,
		staring = {},
		finaleNight = has(params.rules, "Finale"),
		finaleAt = NightClock.secondsAt(cfg, clock, cfg.Rules.Finale.hour),
		finaleStarted = false,
		finalePassed = false,
		specialGiven = false,
	}
end

local function push(events: { Event }, more: { Event })
	for _, e in more do
		table.insert(events, e)
	end
end

local function aliveCount(s: NightState): number
	local n = 0
	for _, id in s.order do
		if s.crew[id].alive then
			n += 1
		end
	end
	return n
end

local function aliveIds(s: NightState): { PlayerId }
	local out = {}
	for _, id in s.order do
		if s.crew[id].alive and not s.absent[id] then
			table.insert(out, id)
		end
	end
	return out
end

local function hour(s: NightState): number
	return NightClock.hour(s.cfg, s.clock)
end

-- Banked value of a catch: a wrong fish counts triple (cfg.Fishing.wrongPointsMult).
local function value(cfg: any, c: Catch): number
	return if c.wrong then c.points * cfg.Fishing.wrongPointsMult else c.points
end

-- A player dies. `cause` picks the death card: "Death.<rule>.<cause>".
local function die(s: NightState, id: PlayerId, rule: string, variant: string, cause: string, events: { Event })
	local m = s.crew[id]
	if m == nil or not m.alive then
		return
	end
	m.alive = false
	m.bailing = false
	s.tally[id].deaths += 1
	push(events, Fishing.interrupt(m.fishing, id, rule))
	table.insert(s.deaths, { player = id, rule = rule })
	table.insert(events, {
		kind = "PlayerDied",
		player = id,
		data = { rule = rule, variant = variant, text = "Death." .. rule .. "." .. cause },
	})
end

-- Keep or throw back the fish on a player's line. `timeout`: the choice ran out of time
-- (Released then carries data.timeout = true).
local function decide(s: NightState, m: CrewMember, keep: boolean, events: { Event }, timeout: boolean?)
	local c = Fishing.take(m.fishing)
	if c == nil then
		return
	end
	if keep and #s.hold < s.holdMax then
		table.insert(s.hold, c)
		-- Kept reports the Field Guide points so a client cannot tell a wrong fish by its value.
		table.insert(events, { kind = "Kept", player = m.id, data = { points = c.points } })
		if c.wrong then
			s.keptWrong += 1
			s.tally[m.id].keptWrong += 1
			Attention.keptWrong(s.cfg, s.attn)
		end
	else
		local why = if keep then "HoldFull" else "ThrownBack"
		local data: { [string]: any } = { why = why }
		if timeout then
			data.timeout = true
		end
		table.insert(events, { kind = "Released", player = m.id, data = data })
	end
end

local startRule: (s: NightState, id: RuleId, opts: { [string]: any }, events: { Event }) -> ActiveRule?

-- Empties the hold into the cooler. Every kept wrong fish starts a Wrong Catch knock.
local function bank(s: NightState, events: { Event })
	if #s.hold == 0 then
		return
	end
	local points, count, wrong = 0, #s.hold, 0
	for _, c in s.hold do
		points += value(s.cfg, c)
		table.insert(s.cooler, c)
		if c.wrong then
			wrong += 1
		end
	end
	s.hold = {}
	table.insert(events, { kind = "Banked", data = { count = count, points = points } })
	push(events, Quota.bank(s.quota, count, points, s.clock.elapsed))
	if has(s.params.rules, "WrongCatch") then
		for _ = 1, wrong do
			startRule(s, "WrongCatch", {}, events)
		end
	end
end

-- Loses the whole hold over the side.
function Night.loseHold(s: NightState): { Event }
	local count = #s.hold
	if count == 0 then
		return {}
	end
	s.hold = {}
	return { { kind = "HoldLost", data = { count = count } } }
end

-- The cooler knocks: `n` banked fish are gone, at random.
local function eatBanked(s: NightState, n: number): (number, number)
	local fish, points = 0, 0
	for _ = 1, n do
		if #s.cooler == 0 then
			break
		end
		local i = Rng.int(s.coolerRng, 1, #s.cooler)
		local c = table.remove(s.cooler, i) :: Catch
		fish += 1
		points += value(s.cfg, c)
	end
	Quota.remove(s.quota, fish, points)
	return fish, points
end

local function castOpts(s: NightState, boatPos: Types.Vec2): Fishing.CastOpts
	return {
		boatSpeed = s.boatSpeed,
		safe = s.safe,
		zone = LakeMap.zoneAt(s.cfg, boatPos),
		hour = hour(s),
		wrongChance = s.wrongChance,
		wrongTier = s.wrongTier,
		biteMult = s.biteMult,
		biteChance = Fishing.dockFactor(s.cfg, boatPos),
	}
end

local function ruleActive(s: NightState, id: RuleId): boolean
	for _, r in s.rules do
		if r.id == id then
			return true
		end
	end
	return false
end

local function handleIntent(s: NightState, intent: Types.Intent, boatPos: Types.Vec2, events: { Event })
	local m = s.crew[intent.player]
	if m == nil then
		return
	end
	local kind = intent.kind
	if not m.alive then
		-- The drowned only ring the bell.
		if kind == "GhostBell" then
			push(events, Ghost.ring(s.ghost, m.id, s.clock.elapsed))
		end
		return
	end
	local cfg = s.cfg
	if kind == "ToggleLantern" then
		local e = Lantern.toggle(s.lantern)
		if #e > 0 then
			s.lastLantern = m.id
		end
		push(events, e)
	elseif kind == "ToggleMotor" then
		s.motorOn = not s.motorOn
		s.lastMotor = m.id
		table.insert(events, { kind = "MotorChanged", player = m.id, data = { on = s.motorOn } })
	elseif kind == "Cast" then
		if not m.bailing then
			push(events, Fishing.cast(cfg, m.fishing, s.fishRng, m.id, intent.num or 1, castOpts(s, boatPos)))
		end
	elseif kind == "ReelHold" then
		if m.bailing then
			return
		end
		local before = m.fishing.phase
		if before == "Bite" then
			-- Teaching night: the Nth fish hooked is wrong if none has been yet.
			local teach = s.teachWrong and s.wrongSeen == 0 and s.hooked + 1 >= cfg.Fishing.teachWrongByCatch
			m.fishing.forceWrong = teach or s.forceWrongNext
			-- The owner's order: on a Finale night the first fish hooked where and when the
			-- special species bites is one, true to the book (cfg.Rules.Finale.firstOrderSure).
			-- "When" is the hook's hour, so a line cast just before 3 AM still counts.
			local need = cfg.Rules.Finale.needSpecies
			local f = m.fishing
			if
				s.finaleNight
				and not s.specialGiven
				and cfg.Rules.Finale.firstOrderSure
				and (FishTable.weights(cfg, f.zone, hour(s))[need] or 0) > 0
			then
				f.forceSpecies = need
			end
		end
		Fishing.reel(cfg, m.fishing, s.fishRng, intent.flag == true)
		if before == "Bite" and m.fishing.phase == "Reeling" then
			s.hooked += 1
			s.forceWrongNext = false
			local c = m.fishing.catch
			if c ~= nil and c.wrong then
				s.wrongSeen += 1
			end
			if c ~= nil and not c.wrong and c.species == cfg.Rules.Finale.needSpecies then
				s.specialGiven = true
			end
		end
	elseif kind == "CutLine" then
		push(events, Fishing.cut(m.fishing, m.id))
	elseif kind == "CatchDecision" then
		decide(s, m, intent.flag == true, events)
	elseif kind == "Bank" then
		if LakeMap.canBank(cfg, boatPos) then
			bank(s, events)
		end
	elseif kind == "RefillOil" then
		if LakeMap.canBank(cfg, boatPos) then
			push(events, Lantern.refill(s.lantern))
		end
	elseif kind == "Callout" then
		table.insert(events, { kind = "Callout", player = m.id, data = { phrase = intent.text } })
	elseif kind == "BailHold" then
		m.bailing = intent.flag == true
		if m.bailing then
			-- No fishing while bailing.
			push(events, Fishing.interrupt(m.fishing, m.id, "Bailing"))
		end
		table.insert(s.lastIntents, intent)
	else
		-- Knock, Wave: for the rules.
		if kind == "Knock" and ruleActive(s, "Knocking") then
			s.tally[m.id].knocksAnswered += 1
		end
		table.insert(s.lastIntents, intent)
	end
end

local function reelers(s: NightState): number
	local n = 0
	for _, id in s.order do
		local m = s.crew[id]
		if m.alive and Fishing.isReeling(m.fishing) then
			n += 1
		end
	end
	return n
end

-- Every crew member gets an observation, in crew order (missing ones are seated defaults).
-- The server reports a player who left with present = false; that entry is kept as given.
local function playersObs(s: NightState, given: { PlayerObs }): { PlayerObs }
	local byId: { [PlayerId]: PlayerObs } = {}
	for _, p in given do
		byId[p.id] = p
	end
	local out: { PlayerObs } = {}
	for i, id in s.order do
		local p = byId[id]
		if p == nil then
			p = { id = id, seated = true, helm = i == 1, inWater = false, gazeYaw = 0, bookOpen = false }
		end
		table.insert(out, p :: PlayerObs)
	end
	return out
end

-- The special order (a true needSpecies fish) is in the hold or the cooler.
local function specialAboard(s: NightState): boolean
	local want = s.cfg.Rules.Finale.needSpecies
	for _, list in { s.hold, s.cooler } do
		for _, c in list do
			if c.species == want and not c.wrong then
				return true
			end
		end
	end
	return false
end

local function entityObs(s: NightState, dt: number, input: NightInput, players: { PlayerObs }): EntityObs
	local alive: { [PlayerId]: boolean } = {}
	local reeling: { [PlayerId]: boolean } = {}
	for _, id in s.order do
		local m = s.crew[id]
		-- A player who left the game is not alive to the rules: none can count or take them.
		alive[id] = m.alive and not s.absent[id]
		reeling[id] = alive[id] and Fishing.isReeling(m.fishing)
	end
	local l = s.lantern
	return {
		dt = dt,
		boat = input.boat,
		players = players,
		alive = alive,
		reeling = reeling,
		lanternOn = l.on,
		motorOn = s.motorOn,
		safe = s.safe,
		intents = s.lastIntents,
		timeLeft = NightClock.timeLeft(s.clock),
		lanternCanLight = l.oil > 0 and l.forcedFor <= 0,
		lastLantern = s.lastLantern,
		lastMotor = s.lastMotor,
		specialAboard = s.finaleNight and specialAboard(s),
	}
end

local function isReal(id: RuleId): boolean
	return has(Director.RULES, id)
end

-- Creates a rule and runs its first (zero-length) step so the cue goes out this tick.
startRule = function(s: NightState, id: RuleId, opts: { [string]: any }, events: { Event }): ActiveRule?
	local mod = Night.RULES[id]
	if mod == nil then
		return nil
	end
	s.ruleCount += 1
	local cfg = s.cfg
	local obs = s.lastObs
	local boat = if obs then obs.boat else nil
	local variant = opts.variant or (s.params.amendments or {})[id]
	local ctx = {
		variant = variant,
		teaching = opts.teaching == true,
		warningScale = s.params.warningScale,
		only = opts.only,
		boat = boat,
		aliveIds = aliveIds(s),
		elapsed = s.clock.elapsed,
		form = opts.form,
	}
	local rng = Rng.fork(s.rng, "rule:" .. id .. ":" .. tostring(s.ruleCount))
	local r: ActiveRule = { id = id, mod = mod, state = mod.new(cfg, rng, ctx), real = isReal(id) }
	table.insert(s.rules, r)
	if obs ~= nil then
		local o = table.clone(obs)
		o.dt = 0
		o.intents = {}
		push(events, mod.step(r.state, o))
	end
	return r
end

-- Applies a rule's fail effects.
local function applyFail(s: NightState, r: ActiveRule, e: Event, events: { Event })
	local data = e.data or {}
	local fx = data.effects or {}
	local variant = data.variant or "Default"
	local cause = fx.cause or "Taken"
	if r.id == "Hum" and fx.blame ~= nil and s.tally[fx.blame] ~= nil then
		s.tally[fx.blame].brokeSilence += 1
	end
	if fx.rock then
		table.insert(events, { kind = "BoatRocked", entity = r.id })
	end
	if r.id == "Hum" and s.motorOn then
		-- The boat is thrown: the motor dies with it.
		s.motorOn = false
		table.insert(events, { kind = "MotorChanged", entity = r.id, data = { on = false } })
	end
	if fx.loseHold then
		push(events, Night.loseHold(s))
	end
	if fx.snuff then
		push(events, Lantern.forceOut(s.cfg, s.lantern))
	end
	if fx.flood and not s.leakOn then
		s.leakOn = true
		s.plugLeft = s.cfg.Rules.Knocking.floodLasts
		table.insert(events, { kind = "Flooding", entity = r.id, data = { level = s.flood, leak = true } })
		s.floodSent = s.flood
	end
	if fx.eatBanked ~= nil and fx.eatBanked > 0 then
		local fish, points = eatBanked(s, fx.eatBanked)
		fx.eaten = { count = fish, points = points }
	end
	for _, id in fx.kill or {} do
		die(s, id, r.id, variant, cause, events)
	end
end

-- A director rule is paused while the boat is in the dock light: its own timers stop (it
-- moves neither toward a fail nor toward a pass) and it picks up where it left off once
-- the boat leaves. A rule that already has its outcome (cooldown) runs on. Wrong Catch is
-- not a director rule (it starts at the dock, on banking) and the Finale passes in the
-- light, so neither pauses. A crew that sits in the light past dawn simply ends the night.
function Night.rulePaused(s: NightState, r: ActiveRule): boolean
	return s.safe and r.real and r.state.base.outcome == nil and not s.finaleStarted
end

local function stepRules(s: NightState, obs: EntityObs, events: { Event })
	local keep: { ActiveRule } = {}
	for _, r in s.rules do
		local stepped = if Night.rulePaused(s, r) then {} else r.mod.step(r.state, obs)
		for _, e in stepped do
			table.insert(events, e)
			if e.kind == "EntityPass" then
				if r.real then
					s.scaresSurvived += 1
					Director.resolved(s.director, r.id, true, s.clock.elapsed)
				elseif r.id == "Finale" then
					s.scaresSurvived += 1
					s.finalePassed = true -- Night.step banks the hold right after the rules
				end
			elseif e.kind == "EntityStrike" then
				-- The Finale takes someone and goes on.
				applyFail(s, r, e, events)
			elseif e.kind == "EntityFail" then
				applyFail(s, r, e, events)
				if r.real then
					Director.resolved(s.director, r.id, false, s.clock.elapsed)
				end
			end
		end
		if not r.mod.done(r.state) then
			table.insert(keep, r)
		end
	end
	s.rules = keep
end

-- Counts each time a living player's gaze lands straight on an active Watcher.
local function tallyStares(s: NightState, obs: EntityObs)
	local figure: Types.Vec2? = nil
	for _, r in s.rules do
		if r.id == "Watcher" and r.state.base.outcome == nil and r.state.base.cueAt ~= nil then
			figure = r.state.pos
		end
	end
	for _, p in obs.players do
		local now = false
		if figure ~= nil and obs.alive[p.id] then
			now = Watcher.gazeAt(s.cfg, obs.boat.pos, figure :: Types.Vec2, p) == "Stare"
		end
		if now and not s.staring[p.id] then
			s.tally[p.id].timesStaredAtWatcher += 1
		end
		s.staring[p.id] = now
	end
end

-- The leak, the bailing and the sinking (water comes in from a Knocking fail).
local function stepFlood(s: NightState, dt: number, events: { Event })
	local K = s.cfg.Rules.Knocking
	local bailers = 0
	for _, id in s.order do
		local m = s.crew[id]
		if m.alive and m.bailing then
			bailers += 1
			if s.flood > 0 then
				s.tally[id].bailedSeconds += dt
			end
		end
	end
	local before = s.flood
	if s.leakOn and not s.safe then
		s.flood += dt / K.floodSeconds
	end
	if bailers > 0 and s.flood > 0 then
		s.flood -= bailers * dt / K.bailSeconds
		if s.leakOn then
			s.plugLeft -= dt
			if s.plugLeft <= 0 then
				s.leakOn = false
			end
		end
	end
	s.flood = math.clamp(s.flood, 0, 1)
	if s.flood ~= before and (math.abs(s.flood - s.floodSent) >= 0.05 or s.flood == 0 or s.flood >= 1) then
		s.floodSent = s.flood
		table.insert(events, { kind = "Flooding", data = { level = s.flood, leak = s.leakOn } })
	end
	if s.flood >= 1 and not s.sunk then
		s.sunk = true
		table.insert(events, { kind = "Sunk" })
		for _, id in s.order do
			die(s, id, "Knocking", (s.params.amendments or {}).Knocking or "AnswerTwo", "Sunk", events)
		end
	end
end

-- Rule 0: a swimmer outside the dock light hears a pull at warnAt and is taken at dragSeconds.
local function stepWater(s: NightState, dt: number, players: { PlayerObs }, events: { Event })
	local W = s.cfg.Water
	local scale = s.params.warningScale or 1
	for _, p in players do
		local m = s.crew[p.id]
		if m ~= nil and m.alive then
			if p.inWater then
				m.inWaterFor += dt
				if not m.dragWarned and m.inWaterFor >= W.warnAt * scale then
					m.dragWarned = true
					table.insert(events, { kind = "DragWarning", player = m.id, only = m.id })
				end
				if m.inWaterFor >= W.dragSeconds * scale then
					die(s, m.id, "Water", "Default", "Drag", events)
				end
			else
				m.inWaterFor = 0
				m.dragWarned = false
			end
		end
	end
end

local function activeRealCount(s: NightState): number
	local n = 0
	for _, r in s.rules do
		if r.real and r.state.base.outcome == nil then
			n += 1
		end
	end
	return n
end

local function eligible(s: NightState, boatPos: Types.Vec2): { RuleId }
	local info = { elapsed = s.clock.elapsed, boatPos = boatPos, neighborEarliest = s.neighborEarliest }
	local out: { RuleId } = {}
	if s.finaleStarted then
		return out
	end
	for _, id in Director.RULES do
		if has(s.params.rules, id) and not ruleActive(s, id) then
			local mod = Night.RULES[id]
			if mod ~= nil and mod.eligible(s.cfg, info) then
				table.insert(out, id)
			end
		end
	end
	return out
end

local function stepDirector(s: NightState, dt: number, boatPos: Types.Vec2, events: { Event })
	-- On a Finale night the director's night ends at the bell.
	local timeLeft = NightClock.timeLeft(s.clock)
	if s.finaleNight then
		timeLeft = math.max(0, s.finaleAt - s.clock.elapsed)
	end
	local decisions = Director.step(s.director, dt, {
		attention = s.attn.value,
		activeReal = activeRealCount(s),
		safe = s.safe,
		timeLeft = timeLeft,
		elapsed = s.clock.elapsed,
		eligible = eligible(s, boatPos),
		aliveIds = aliveIds(s),
	})
	for _, d in decisions do
		if d.kind == "Spawn" and d.rule ~= nil then
			startRule(s, d.rule :: RuleId, { teaching = d.teaching, only = d.only }, events)
		elseif d.kind == "Fakeout" and d.id ~= nil and not s.finaleStarted then
			local e = Fakeouts.event(s.cfg, s.fakeRng, d.id :: string, d.only, boatPos)
			if d.id == "ChorusDip" then
				s.dipFor = Fakeouts.DIP_SECONDS
			end
			table.insert(events, e)
		elseif d.kind == "Chorus" and d.band ~= nil then
			s.directorBand = d.band :: number
		end
	end
end

-- The chorus the crew hears: silent while a rule wants silence, else the director's band,
-- one band thinner during a ChorusDip.
local function stepChorus(s: NightState, dt: number, events: { Event })
	s.dipFor = math.max(0, s.dipFor - dt)
	local band = s.directorBand
	if s.dipFor > 0 then
		band = math.max(1, band - 1)
	end
	for _, r in s.rules do
		if r.state.base.silent then
			band = 0
		end
	end
	if band ~= s.chorus then
		s.chorus = band
		table.insert(events, { kind = "Chorus", data = { band = band } })
	end
end

-- 4 AM on a Finale night: the bell. Lets every director rule go, locks the lantern on with
-- its oil as the finale's clock, and starts the Finale.
local function startFinale(s: NightState, events: { Event })
	if s.finaleStarted then
		return
	end
	s.finaleStarted = true
	s.phase = "Finale"
	local cfg = s.cfg
	for _, r in s.rules do
		if r.real and r.state.base.outcome == nil and r.state.base.pending == nil then
			if EntityBase.pass(r.state.base, events, { endedBy = "Finale" }) then
				Director.resolved(s.director, r.id, true, s.clock.elapsed)
			end
		end
	end
	local l = s.lantern
	l.oil = 1
	l.lowSent = false
	l.burnMult = cfg.Rules.Finale.oilSeconds * (s.params.warningScale or 1) / cfg.Lantern.burnSeconds
	push(events, Lantern.lockOn(l))
	startRule(s, "Finale", {}, events)
end

local function buildResult(s: NightState, cleared: boolean): NightResult
	local tallies: { PlayerTally } = {}
	for _, id in s.order do
		table.insert(tallies, table.clone(s.tally[id]))
	end
	local deaths = {}
	for _, d in s.deaths do
		table.insert(deaths, { player = d.player, rule = d.rule })
	end
	return {
		cleared = cleared,
		banked = s.quota.banked,
		quota = s.quota.target,
		caught = s.caught,
		scaresSurvived = s.scaresSurvived,
		deaths = deaths,
		keptWrong = s.keptWrong,
		tallies = tallies,
		bankedFish = s.quota.fish,
	}
end

local function finish(s: NightState, cleared: boolean, reason: string?, events: { Event })
	local result = buildResult(s, cleared)
	s.result = result
	if cleared then
		s.phase = "Cleared"
		table.insert(events, { kind = "NightCleared", data = { result = result } })
	else
		s.phase = "Failed"
		table.insert(events, { kind = "NightFailed", data = { reason = reason, result = result } })
	end
end

function Night.step(s: NightState, input: NightInput): { Event }
	local events: { Event } = {}
	if s.phase == "Cleared" or s.phase == "Failed" then
		return events
	end
	local cfg = s.cfg
	local p = s.params
	if not s.started then
		s.started = true
		table.insert(events, { kind = "NightStarted", data = { night = p.night, seed = p.seed, quota = p.quota } })
		for _, rule in p.newRules do
			table.insert(events, { kind = "RuleUnlocked", data = { rule = rule } })
		end
		local tape = if p.mode == "Endless" then "Endless" else "Night" .. tostring(p.night)
		table.insert(events, { kind = "Tape", data = { id = tape } })
		if next(p.amendments or {}) ~= nil then
			table.insert(events, { kind = "Tape", data = { id = "Amendment" } })
		end
	end

	local dt = math.clamp(input.dt, 0, 1)
	local boat = input.boat
	s.safe = LakeMap.isSafe(cfg, boat.pos)
	s.boatSpeed = math.sqrt(boat.vel.x * boat.vel.x + boat.vel.z * boat.vel.z)
	s.lastIntents = {}
	local players = playersObs(s, input.players)
	local absent: { [PlayerId]: boolean } = {}
	for _, po in players do
		if po.present == false then
			absent[po.id] = true
		end
	end
	s.absent = absent

	for _, intent in input.intents do
		handleIntent(s, intent, boat.pos, events)
	end

	push(events, Lantern.step(cfg, s.lantern, dt))

	for _, id in s.order do
		local m = s.crew[id]
		if m.alive then
			for _, e in Fishing.step(cfg, m.fishing, dt, s.fishRng, id) do
				if e.kind == "Caught" then
					s.caught += 1
				end
				table.insert(events, e)
			end
			if m.fishing.phase == "Deciding" and m.fishing.expired then
				-- Out of time: thrown back (cfg.Fishing.timeoutKeeps = false) or kept.
				decide(s, m, cfg.Fishing.timeoutKeeps == true, events, true)
			end
		end
	end

	NightClock.step(s.clock, dt)
	Attention.step(cfg, s.attn, dt, {
		motorOn = s.motorOn,
		lanternOn = s.lantern.on,
		reelers = reelers(s),
		safe = s.safe,
	})

	stepWater(s, dt, players, events)
	if s.finaleNight and not s.finaleStarted and s.clock.elapsed >= s.finaleAt - 1e-9 and aliveCount(s) > 0 then
		if s.lastObs == nil then
			s.lastObs = entityObs(s, 0, input, players)
		end
		startFinale(s, events)
	end
	local obs = entityObs(s, dt, input, players)
	s.lastObs = obs
	local passedBefore = s.finalePassed
	stepRules(s, obs, events)
	if s.finalePassed and not passedBefore then
		bank(s, events) -- home: the owner takes the hold
	end
	tallyStares(s, obs)
	stepFlood(s, dt, events)
	if aliveCount(s) > 0 then
		stepDirector(s, dt, boat.pos, events)
	end
	stepChorus(s, dt, events)

	if aliveCount(s) == 0 then
		finish(s, false, if s.sunk then "Sunk" else "CrewLost", events)
	elseif s.finalePassed and not passedBefore and Quota.isMet(s.quota) then
		finish(s, true, nil, events) -- home with the owner's fish: the shell skips to dawn
	elseif NightClock.done(s.clock) then
		if not Quota.isMet(s.quota) then
			finish(s, false, "QuotaShort", events)
		elseif s.finaleNight and not s.finalePassed then
			finish(s, false, if specialAboard(s) then "NotHome" else "SpecialOrder", events)
		else
			finish(s, true, nil, events)
		end
	end
	return events
end

function Night.view(s: NightState): NightView
	local players = {}
	for _, id in s.order do
		local m = s.crew[id]
		local lo, hi = Fishing.band(m.fishing)
		table.insert(players, {
			id = id,
			alive = m.alive,
			fishing = m.fishing.phase,
			tension = m.fishing.tension,
			zoneLo = lo,
			zoneHi = hi,
			progress = m.fishing.progress,
			bailing = m.bailing,
		})
	end
	local rules: { RuleId } = table.clone(s.params.rules)
	return {
		night = s.params.night,
		mode = s.params.mode,
		difficulty = s.params.difficulty,
		phase = s.phase,
		clock = hour(s),
		timeLeft = NightClock.timeLeft(s.clock),
		quota = s.quota.target,
		banked = s.quota.banked,
		hold = #s.hold,
		holdMax = s.holdMax,
		oil = s.lantern.oil,
		refills = s.lantern.refills,
		lanternOn = s.lantern.on,
		motorOn = s.motorOn,
		chorus = s.chorus,
		flood = s.flood,
		safe = s.safe,
		rules = rules,
		players = players,
	}
end

function Night.result(s: NightState): NightResult?
	return s.result
end

-- Studio scenarios and tests only: start a rule now, outside the director's schedule.
-- opts = { variant?, teaching?, only?, form? ("Boat" | "FalseBeacon" for the Neighbor) }.
-- "WrongCatch" makes the next fish hooked a wrong one. "Finale" rings the bell now (the
-- night becomes a Finale night: it then needs the Finale's pass to clear).
-- The rule is told to the director as active so the quiet gap still follows it.
-- Returns the events of the rule's first step (its cue).
function Night.debugForce(s: NightState, rule: RuleId, opts: any?): { Event }
	local o = opts or {}
	local events: { Event } = {}
	if s.phase == "Cleared" or s.phase == "Failed" then
		return events
	end
	if rule == "WrongCatch" then
		s.forceWrongNext = true
		return events
	end
	if rule == "Finale" then
		-- Rings the bell now, on any night.
		if s.lastObs == nil then
			local dock = s.cfg.Lake.dockEnd
			local input0: NightInput = {
				dt = 0,
				boat = {
					pos = { x = dock.x, z = dock.z },
					vel = { x = 0, z = 0 },
					heading = 0,
					throttle = 0,
					steer = 0,
				},
				players = {},
				intents = {},
			}
			s.lastObs = entityObs(s, 0, input0, playersObs(s, {}))
		end
		s.finaleNight = true
		s.finaleAt = math.min(s.finaleAt, s.clock.elapsed)
		startFinale(s, events)
		return events
	end
	if Night.RULES[rule] == nil or ruleActive(s, rule) then
		return events
	end
	if s.lastObs == nil then
		-- Not stepped yet: observe a still boat at the dock end.
		local dock = s.cfg.Lake.dockEnd
		local input: NightInput = {
			dt = 0,
			boat = { pos = { x = dock.x, z = dock.z }, vel = { x = 0, z = 0 }, heading = 0, throttle = 0, steer = 0 },
			players = {},
			intents = {},
		}
		s.lastObs = entityObs(s, 0, input, playersObs(s, {}))
	end
	startRule(s, rule, o, events)
	if isReal(rule) then
		Director.noteSpawn(s.director, rule)
	end
	return events
end

return Night
