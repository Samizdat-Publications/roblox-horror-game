--!strict
-- Rule 6, the Lake Wakes (docs/DESIGN.md): night 5's clock, not a director rule.
-- At 4 AM (cfg.Rules.Finale.hour) the dock bell rings by itself (the cue) and every water
-- sound stops (the chorus is silent for the whole finale). Night locks the lantern on and
-- its oil becomes the finale's clock (it runs dry oilSeconds x warningScale after the bell).
--
-- The crew must go home:
--   * Pass: the boat reaches the dock light with the special order (a true
--     cfg.Rules.Finale.needSpecies fish) aboard or banked (obs.specialAboard).
--   * Strikes (EntityStrike, effects { kill, cause }): the lake takes someone but the
--     finale goes on. Never before `warn` after the bell, never inside the dock light.
--       Still: the boat sat still (below cfg.Boat.stillSpeed) for stopLimit x scale
--         seconds; a random living player is taken and the clock restarts.
--       Dark: the locked lantern ran dry on the water; someone is taken at once and again
--         every darkEvery x scale seconds.
--       Waved: anyone waves (the waver).
--       Closed: a Neighbor boat comes within cfg.Rules.Neighbor.killDist (the helm).
--       Beacon: the boat comes within cfg.Rules.Neighbor.falseBeaconKill of a false
--         beacon (the helm).
--   * Hazards on a fast clock: from hazardFirst x scale after the bell (never before warn),
--     every neighborEvery x scale seconds a Neighbor boat or a false beacon (hazardForms in
--     order) shows up hazardMin..hazardMax away, hazardAngleMin..Max off the boat's bearing
--     to the dock (never dead ahead), and at least its kill distance plus hazardClear off
--     the straight way home (it never blocks the run; no fair spot: retry in hazardRetry
--     seconds). Finale v6: the first aheadCount Neighbor boats are placed AHEAD instead,
--     aheadAngleMin..Max off the bearing home at aheadMin..aheadMax studs (same clearance
--     rule), so the helm has to steer around them; false beacons stay to the side. M8 polish:
--     the first crossCount of those come in across the bow (crossAlong studs down the way home,
--     clearance plus 0..crossExtra off the line: the nearest any hazard is placed, still
--     clear of the way home). Boats drift toward the lit lantern at
--     boatDrift. Each is gone after hazardLife seconds. Sent as EntityMoved with data
--     { hazard = n, form, pos, appear? , gone? }.
--   * Fail (EntityFail): the last living player is taken, or dawn comes first (no kill,
--     cause "Dawn": Night then judges the night).

local Types = require(script.Parent.Parent.Types)
local Rng = require(script.Parent.Parent.Rng)
local LakeMap = require(script.Parent.Parent.LakeMap)
local EntityBase = require(script.Parent.Parent.EntityBase)

type Event = Types.Event
type EntityObs = Types.EntityObs
type Vec2 = Types.Vec2
type PlayerId = Types.PlayerId

export type Hazard = {
	id: number,
	form: string, -- "Boat" | "FalseBeacon"
	pos: Vec2,
	age: number,
	moveClock: number,
}

export type FinaleState = {
	base: EntityBase.Base,
	hazards: { Hazard },
	nextHazard: number, -- age of the next hazard
	hazardCount: number,
	aheadPlaced: number, -- hazards placed ahead of the boat so far (R.aheadCount)
	crossPlaced: number, -- of those, the boats placed across the bow (R.crossCount)
	stillFor: number,
	darkFor: number, -- seconds dark on the water since the last Dark strike
	darkStruck: boolean, -- the first Dark strike has landed
	strikes: number,
}

local Finale = {}

Finale.id = "Finale" :: Types.RuleId
Finale.MOVE_EVERY = 0.5

function Finale.new(cfg: any, rng: Rng.RngState, ctx: EntityBase.SpawnCtx): FinaleState
	local R = cfg.Rules.Finale
	local base = EntityBase.new("Finale", cfg, rng, ctx, R.warn)
	return {
		base = base,
		hazards = {},
		nextHazard = math.max(base.warn, (R.hazardFirst or 0) * base.scale),
		hazardCount = 0,
		aheadPlaced = 0,
		crossPlaced = 0,
		stillFor = 0,
		darkFor = 0,
		darkStruck = false,
		strikes = 0,
	}
end

-- Never started by the director: Night starts it at cfg.Rules.Finale.hour.
function Finale.eligible(_cfg: any, _info: any): boolean
	return false
end

local function aliveIds(obs: EntityObs): { PlayerId }
	return EntityBase.aliveList(obs.alive, obs.players)
end

local function helmOf(obs: EntityObs): PlayerId?
	for _, p in obs.players do
		if p.helm and obs.alive[p.id] then
			return p.id
		end
	end
	return aliveIds(obs)[1]
end

-- Takes `who`. The last living player ends the finale as its fail.
local function strike(s: FinaleState, obs: EntityObs, who: PlayerId?, cause: string, events: { Event })
	if who == nil or not obs.alive[who] then
		return
	end
	local effects = { kill = { who }, cause = cause }
	if #aliveIds(obs) <= 1 then
		EntityBase.fail(s.base, events, effects)
		return
	end
	obs.alive[who] = false -- later checks this tick see it
	s.strikes += 1
	table.insert(events, EntityBase.ev(s.base, "EntityStrike", { variant = s.base.variant, effects = effects }))
end

local function onWater(cfg: any, p: Vec2): boolean
	return LakeMap.inside(cfg, p)
		and LakeMap.distanceToShore(cfg, p) >= 20
		and LakeMap.dist(p, cfg.Lake.dockEnd) > cfg.Lake.safeRadius + cfg.Rules.Neighbor.killDist
end

-- Distance from p to the segment a..b (the straight way home).
function Finale.distToSegment(p: Vec2, a: Vec2, b: Vec2): number
	local abx, abz = b.x - a.x, b.z - a.z
	local len2 = abx * abx + abz * abz
	local u = if len2 > 1e-9 then math.clamp(((p.x - a.x) * abx + (p.z - a.z) * abz) / len2, 0, 1) else 0
	local cx, cz = a.x + abx * u, a.z + abz * u
	return math.sqrt((p.x - cx) ^ 2 + (p.z - cz) ^ 2)
end

-- The form of the next hazard: R.hazardForms in order (repeating), else by beaconChance.
local function nextForm(s: FinaleState): string
	local R = s.base.cfg.Rules.Finale
	local forms = R.hazardForms
	if type(forms) == "table" and #forms > 0 then
		return forms[s.hazardCount % #forms + 1]
	end
	return if Rng.next(s.base.rng) < R.beaconChance then "FalseBeacon" else "Boat"
end

-- One candidate spot AHEAD (finale v6, Neon 2/10 "a calm commute"): aheadAngleMin..Max off the
-- bearing home at aheadMin..aheadMax studs, close enough to the bow line that the helm has to
-- steer a little. The distance is drawn from the part of the range that can still be `clear`
-- of the straight way home at that angle (d sin a >= clear), so most draws are fair; the
-- caller still checks the segment distance and the water. Nil when the angle cannot be fair.
local function aheadSpot(s: FinaleState, boatPos: Vec2, home: number, clear: number): Vec2?
	local b = s.base
	local R = b.cfg.Rules.Finale
	local side = if Rng.next(b.rng) < 0.5 then -1 else 1
	local off = Rng.range(b.rng, R.aheadAngleMin, R.aheadAngleMax)
	local lo = math.max(R.aheadMin, clear / math.max(1e-3, math.sin(off)))
	if lo > R.aheadMax then
		return nil
	end
	local d = Rng.range(b.rng, lo, R.aheadMax)
	local a = home + side * off
	return { x = boatPos.x + math.sin(a) * d, z = boatPos.z + math.cos(a) * d }
end

-- One candidate spot ACROSS THE BOW (M8 polish): crossAlong studs down the bearing home and
-- `clear` plus 0..crossExtra studs to one side of it, so it sits as close to the way home as
-- the fairness rule allows. The caller still checks the segment distance and the water.
local function crossSpot(s: FinaleState, boatPos: Vec2, home: number, clear: number): Vec2
	local b = s.base
	local R = b.cfg.Rules.Finale
	local side = if Rng.next(b.rng) < 0.5 then -1 else 1
	local along = Rng.range(b.rng, R.crossAlong[1], R.crossAlong[2])
	local lateral = clear + 0.05 + Rng.range(b.rng, 0, R.crossExtra or 0) -- 0.05: float margin
	-- Along the bearing: (sin, cos); square to it, on the water plane: (cos, -sin).
	local fx, fz = math.sin(home), math.cos(home)
	return {
		x = boatPos.x + fx * along + fz * lateral * side,
		z = boatPos.z + fz * along - fx * lateral * side,
	}
end

-- One candidate spot to the side (the older placement): hazardAngleMin..Max off the bearing
-- home at hazardMin..hazardMax studs. A player who steered for it would leave the way home.
local function sideSpot(s: FinaleState, boatPos: Vec2, home: number): Vec2
	local b = s.base
	local R = b.cfg.Rules.Finale
	local side = if Rng.next(b.rng) < 0.5 then -1 else 1
	local a = home + side * Rng.range(b.rng, R.hazardAngleMin, R.hazardAngleMax)
	local d = Rng.range(b.rng, R.hazardMin, R.hazardMax)
	return { x = boatPos.x + math.sin(a) * d, z = boatPos.z + math.cos(a) * d }
end

-- Whether the next hazard goes ahead of the boat: a Neighbor boat while fewer than aheadCount
-- have been placed ahead. False beacons always go to the side.
local function wantsAhead(s: FinaleState, form: string): boolean
	local R = s.base.cfg.Rules.Finale
	return form == "Boat" and (R.aheadCount or 0) > s.aheadPlaced
end

-- Places one hazard off the way home. False when no fair spot was found this tick.
local function spawnHazard(s: FinaleState, obs: EntityObs, events: { Event }): boolean
	local b = s.base
	local cfg = b.cfg
	local R = cfg.Rules.Finale
	local N = cfg.Rules.Neighbor
	local boatPos = obs.boat.pos
	local dock = cfg.Lake.dockEnd
	local home = EntityBase.bearing(boatPos, dock)
	local form = nextForm(s)
	local clear = (if form == "FalseBeacon" then N.falseBeaconKill else N.killDist) + (R.hazardClear or 0)
	local ahead = wantsAhead(s, form)
	local cross = ahead and (R.crossCount or 0) > s.crossPlaced and R.crossAlong ~= nil
	-- Across the bow first when wanted (12 tries), then ahead (to try 24); if the lake gives no
	-- fair spot ahead (near the dock light), the side placement takes the slot so the clock
	-- keeps its rhythm.
	for try = 1, if ahead then 40 else 16 do
		local isCross = cross and try <= 12
		local isAhead = ahead and try <= 24
		local p = if isCross
			then crossSpot(s, boatPos, home, clear)
			elseif isAhead then aheadSpot(s, boatPos, home, clear)
			else sideSpot(s, boatPos, home)
		if p and onWater(cfg, p) and Finale.distToSegment(p, boatPos, dock) >= clear then
			if isAhead then
				s.aheadPlaced += 1
			end
			if isCross then
				s.crossPlaced += 1
			end
			s.hazardCount += 1
			local h: Hazard = { id = s.hazardCount, form = form, pos = p, age = 0, moveClock = 0 }
			table.insert(s.hazards, h)
			table.insert(
				events,
				EntityBase.ev(
					b,
					"EntityMoved",
					{ hazard = h.id, form = form, pos = { x = p.x, z = p.z }, appear = true }
				)
			)
			return true
		end
	end
	return false
end

local function stepHazards(s: FinaleState, obs: EntityObs, events: { Event }): boolean
	local b = s.base
	local cfg = b.cfg
	local R = cfg.Rules.Finale
	local N = cfg.Rules.Neighbor
	local dt = obs.dt
	local boatPos = obs.boat.pos
	local keep: { Hazard } = {}
	local struck = false
	for _, h in s.hazards do
		h.age += dt
		local d = LakeMap.dist(boatPos, h.pos)
		local gone = h.age >= R.hazardLife
		if not gone and not obs.safe then
			if h.form == "Boat" then
				if obs.lanternOn and d > 2 then
					local step = math.min(R.boatDrift * dt, d - 1)
					local nextPos = {
						x = h.pos.x + (boatPos.x - h.pos.x) / d * step,
						z = h.pos.z + (boatPos.z - h.pos.z) / d * step,
					}
					if LakeMap.inside(cfg, nextPos) and not LakeMap.isSafe(cfg, nextPos) then
						h.pos = nextPos
					end
				end
				h.moveClock += dt
				if h.moveClock >= Finale.MOVE_EVERY then
					h.moveClock = 0
					table.insert(
						events,
						EntityBase.ev(
							b,
							"EntityMoved",
							{ hazard = h.id, form = h.form, pos = { x = h.pos.x, z = h.pos.z } }
						)
					)
				end
				if not struck and LakeMap.dist(boatPos, h.pos) < N.killDist and EntityBase.canFail(b) then
					strike(s, obs, helmOf(obs), "Closed", events)
					struck, gone = true, true
				end
			elseif not struck and d < N.falseBeaconKill and EntityBase.canFail(b) then
				strike(s, obs, helmOf(obs), "Beacon", events)
				struck, gone = true, true
			end
		end
		if gone then
			table.insert(events, EntityBase.ev(b, "EntityMoved", { hazard = h.id, form = h.form, gone = true }))
		else
			table.insert(keep, h)
		end
	end
	s.hazards = keep
	return struck
end

function Finale.step(s: FinaleState, obs: EntityObs): { Event }
	local events: { Event } = {}
	local b = s.base
	local cfg = b.cfg
	local R = cfg.Rules.Finale
	local dt = obs.dt
	if not EntityBase.advance(b, dt, events) then
		return events
	end
	if b.cueAt == nil then
		b.silent = true
		EntityBase.cue(b, {
			bell = true,
			oilSeconds = R.oilSeconds * b.scale,
			stopLimit = R.stopLimit * b.scale,
			needSpecies = R.needSpecies,
		}, events)
		return events
	end
	if b.stage == "Cue" and EntityBase.canFail(b) then
		EntityBase.setStage(b, "Window", events)
	end

	-- Home with the owner's fish: the run is won.
	if obs.safe and obs.specialAboard == true then
		EntityBase.pass(b, events, { home = true })
		return events
	end

	local live = EntityBase.canFail(b)
	if not obs.safe then
		-- Waving.
		for _, it in obs.intents do
			if it.kind == "Wave" and obs.alive[it.player] and live then
				strike(s, obs, it.player, "Waved", events)
				if EntityBase.resolved(b) then
					return events
				end
				break
			end
		end
		-- Sitting still.
		local v = obs.boat.vel
		local speed = math.sqrt(v.x * v.x + v.z * v.z)
		if speed < cfg.Boat.stillSpeed then
			s.stillFor += dt
		else
			s.stillFor = 0
		end
		if live and s.stillFor >= R.stopLimit * b.scale then
			s.stillFor = 0
			strike(s, obs, Rng.pick(b.rng, aliveIds(obs)), "Still", events)
			if EntityBase.resolved(b) then
				return events
			end
		end
		-- The lantern ran dry.
		if not obs.lanternOn then
			s.darkFor += dt
			if live and (not s.darkStruck or s.darkFor >= R.darkEvery * b.scale) then
				s.darkStruck = true
				s.darkFor = 0
				local ids = aliveIds(obs)
				if #ids > 0 then
					strike(s, obs, Rng.pick(b.rng, ids), "Dark", events)
					if EntityBase.resolved(b) then
						return events
					end
				end
			end
		end
	else
		s.stillFor = 0
	end

	-- Neighbors and false beacons on a fast clock.
	if b.age >= s.nextHazard and not obs.safe then
		if spawnHazard(s, obs, events) then
			s.nextHazard = b.age + R.neighborEvery * b.scale
		else
			s.nextHazard = b.age + (R.hazardRetry or 1)
		end
	end
	stepHazards(s, obs, events)
	if EntityBase.resolved(b) then
		return events
	end

	-- Dawn came first.
	if obs.timeLeft <= dt + 1e-6 then
		EntityBase.fail(b, events, { cause = "Dawn" })
	end
	return events
end

function Finale.stage(s: FinaleState): Types.EntityStage
	return s.base.stage
end

function Finale.done(s: FinaleState): boolean
	return EntityBase.done(s.base)
end

return Finale
