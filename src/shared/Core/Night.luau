--!strict
-- One night on the lake: the composition every shell drives (docs/ARCHITECTURE.md, Night).
--
--   Night.new(cfg, params) -> NightState
--   Night.step(state, input) -> { Event }
--   Night.view(state) -> NightView
--   Night.result(state) -> NightResult?
--   Night.debugForce(state, rule, opts) -> { Event }
--
-- Core M2 scope: clock, fishing, hold, bank, lantern and oil refills, motor, the lake's
-- attention (a stub that already follows cfg.Attention and drives the chorus band),
-- Wrong Catch traits on catches, and clear and fail. Rules, the director, deaths and
-- flooding arrive in M3 and M4; their state fields exist so the view is complete.

local Types = require(script.Parent.Types)
local Rng = require(script.Parent.Rng)
local LakeMap = require(script.Parent.LakeMap)
local NightClock = require(script.Parent.NightClock)
local Quota = require(script.Parent.Quota)
local Lantern = require(script.Parent.Lantern)
local Fishing = require(script.Parent.Fishing)

type Event = Types.Event
type Catch = Types.Catch
type NightParams = Types.NightParams
type NightInput = Types.NightInput
type NightView = Types.NightView
type NightResult = Types.NightResult
type RuleId = Types.RuleId
type PlayerId = Types.PlayerId

export type CrewMember = {
	id: PlayerId,
	alive: boolean,
	fishing: Fishing.FishState,
	bailing: boolean,
}

export type NightState = {
	cfg: any,
	params: NightParams,
	rng: Rng.RngState,
	fishRng: Rng.RngState,
	clock: NightClock.ClockState,
	quota: Quota.QuotaState,
	lantern: Lantern.LanternState,
	motorOn: boolean,
	hold: { Catch },
	holdMax: number,
	crew: { [PlayerId]: CrewMember },
	order: { PlayerId },
	attention: number,
	attentionFloor: number,
	chorus: number,
	flood: number,
	safe: boolean,
	boatSpeed: number,
	phase: Types.NightPhase,
	started: boolean,
	wrongChance: number,
	wrongTier: number,
	teachWrong: boolean, -- tonight teaches Wrong Catch: one wrong fish by catch N
	wrongSeen: number,
	hooked: number, -- fish hooked tonight (for the teaching guarantee)
	biteMult: number,
	caught: number,
	keptWrong: number,
	scaresSurvived: number,
	deaths: { { player: PlayerId, rule: string } },
	result: NightResult?,
	lastIntents: { Types.Intent }, -- this tick's rule-facing intents (Knock, Wave, BailHold)
}

local Night = {}

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
	local supplies = params.supplies or {}
	local refills = cfg.Lantern.refillsPerNight + (if has(supplies, "OilCan") then 1 else 0)
	local burnMult = if has(supplies, "TrimmedWick") then 1.2 else 1
	local crew: { [PlayerId]: CrewMember } = {}
	local order: { PlayerId } = {}
	for _, id in params.playerIds do
		crew[id] = { id = id, alive = true, fishing = Fishing.new(), bailing = false }
		table.insert(order, id)
	end
	local wrongChance, wrongTier = wrongOdds(cfg, params)
	return {
		cfg = cfg,
		params = params,
		rng = rng,
		fishRng = Rng.fork(rng, "fish"),
		clock = NightClock.new(cfg),
		quota = Quota.new(params.quota),
		lantern = Lantern.new(cfg, refills, burnMult),
		motorOn = false,
		hold = {},
		holdMax = cfg.Fishing.holdMax + (if has(supplies, "BigCooler") then 2 else 0),
		crew = crew,
		order = order,
		attention = 0,
		attentionFloor = 0,
		chorus = 3,
		flood = 0,
		safe = true,
		boatSpeed = 0,
		phase = "Night",
		started = false,
		wrongChance = wrongChance,
		wrongTier = wrongTier,
		teachWrong = has(params.newRules, "WrongCatch"),
		wrongSeen = 0,
		hooked = 0,
		biteMult = if has(supplies, "LuckyLure") then 0.75 else 1,
		caught = 0,
		keptWrong = 0,
		scaresSurvived = 0,
		deaths = {},
		result = nil,
		lastIntents = {},
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

local function hour(s: NightState): number
	return NightClock.hour(s.cfg, s.clock)
end

-- Banked value of a catch: a wrong fish counts triple (cfg.Fishing.wrongPointsMult).
local function value(cfg: any, c: Catch): number
	return if c.wrong then c.points * cfg.Fishing.wrongPointsMult else c.points
end

-- Keep or throw back the fish on a player's line.
local function decide(s: NightState, m: CrewMember, keep: boolean, events: { Event })
	local c = Fishing.take(m.fishing)
	if c == nil then
		return
	end
	local cfg = s.cfg
	if keep and #s.hold < s.holdMax then
		table.insert(s.hold, c)
		-- Kept reports the Field Guide points so a client cannot tell a wrong fish by its value.
		table.insert(events, { kind = "Kept", player = m.id, data = { points = c.points } })
		if c.wrong then
			s.keptWrong += 1
			s.attention = math.min(1, s.attention + cfg.Attention.keptWrong)
			s.attentionFloor = math.min(1, s.attentionFloor + cfg.Attention.keptWrongFloor)
		end
	else
		local why = if keep then "HoldFull" else "ThrownBack"
		table.insert(events, { kind = "Released", player = m.id, data = { why = why } })
	end
end

-- Empties the hold into the cooler.
local function bank(s: NightState, events: { Event })
	if #s.hold == 0 then
		return
	end
	local points, count = 0, #s.hold
	for _, c in s.hold do
		points += value(s.cfg, c)
	end
	s.hold = {}
	table.insert(events, { kind = "Banked", data = { count = count, points = points } })
	push(events, Quota.bank(s.quota, count, points, s.clock.elapsed))
end

-- Loses the whole hold over the side (used by rule fails from M3 on).
function Night.loseHold(s: NightState): { Event }
	local count = #s.hold
	if count == 0 then
		return {}
	end
	s.hold = {}
	return { { kind = "HoldLost", data = { count = count } } }
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
	}
end

local function handleIntent(s: NightState, intent: Types.Intent, boatPos: Types.Vec2, events: { Event })
	local m = s.crew[intent.player]
	if m == nil then
		return
	end
	local kind = intent.kind
	if not m.alive then
		-- The drowned only ring the bell (M3).
		if kind == "GhostBell" then
			table.insert(s.lastIntents, intent)
		end
		return
	end
	local cfg = s.cfg
	if kind == "ToggleLantern" then
		push(events, Lantern.toggle(s.lantern))
	elseif kind == "ToggleMotor" then
		s.motorOn = not s.motorOn
		table.insert(events, { kind = "MotorChanged", player = m.id, data = { on = s.motorOn } })
	elseif kind == "Cast" then
		push(events, Fishing.cast(cfg, m.fishing, s.fishRng, m.id, intent.num or 1, castOpts(s, boatPos)))
	elseif kind == "ReelHold" then
		local before = m.fishing.phase
		if before == "Bite" then
			-- Teaching night: the Nth fish hooked is wrong if none has been yet.
			m.fishing.forceWrong = s.teachWrong and s.wrongSeen == 0 and s.hooked + 1 >= cfg.Fishing.teachWrongByCatch
		end
		Fishing.reel(cfg, m.fishing, s.fishRng, intent.flag == true)
		if before == "Bite" and m.fishing.phase == "Reeling" then
			s.hooked += 1
			local c = m.fishing.catch
			if c ~= nil and c.wrong then
				s.wrongSeen += 1
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
		table.insert(s.lastIntents, intent)
	else
		-- Knock, Wave: for the rules (M3 and M4).
		table.insert(s.lastIntents, intent)
	end
end

-- The attention stub (Core.Attention replaces it in M3 with the same numbers).
local function stepAttention(s: NightState, dt: number)
	local A = s.cfg.Attention
	local reelers = 0
	for _, id in s.order do
		local m = s.crew[id]
		if m.alive and Fishing.isReeling(m.fishing) then
			reelers += 1
		end
	end
	local rise = 0
	if s.motorOn then
		rise += A.motorPerSec
	end
	if s.lantern.on then
		rise += A.lanternPerSec
	end
	rise += A.reelPerSec * reelers
	if s.safe then
		s.attention -= A.safeDecayPerSec * dt
	elseif rise > 0 then
		s.attention += rise * dt
	else
		s.attention -= A.decayPerSec * dt
	end
	s.attention = math.clamp(s.attention, s.attentionFloor, 1)
end

-- Chorus band from attention: 3 full, 2 thin, 1 sparse. (Rules silence it to 0 from M3.)
local function chorusBand(cfg: any, attention: number): number
	local b = cfg.Director.chorusBands
	if attention < b[1] then
		return 3
	elseif attention < b[2] then
		return 2
	elseif attention < b[3] then
		return 1
	end
	return 1
end

local function buildResult(s: NightState, cleared: boolean): NightResult
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
				decide(s, m, true, events) -- out of time: the fish is kept
			end
		end
	end

	NightClock.step(s.clock, dt)
	stepAttention(s, dt)
	local band = chorusBand(cfg, s.attention)
	if band ~= s.chorus then
		s.chorus = band
		table.insert(events, { kind = "Chorus", data = { band = band } })
	end

	if aliveCount(s) == 0 then
		finish(s, false, "CrewLost", events)
	elseif NightClock.done(s.clock) then
		if Quota.isMet(s.quota) then
			finish(s, true, nil, events)
		else
			finish(s, false, "QuotaShort", events)
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

-- Studio scenarios and tests only. Rules arrive in Core M3; until then this is a no-op
-- that returns no events.
function Night.debugForce(_s: NightState, _rule: RuleId, _opts: any?): { Event }
	return {}
end

return Night
