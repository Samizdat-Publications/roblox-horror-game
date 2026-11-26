--!strict
-- Rule 5, the Watcher on the Shore (docs/DESIGN.md). Near a shore a tall still figure
-- stands in the trees on the shore nearest the boat, `steps` steps from the waterline.
-- Gaze decides what it does (bearing from the boat; a player with the book open is not
-- looking at anything):
--   staring: within stareCone of it; edge of sight: within edgeCone; else looking away.
-- EdgeOfSight (as printed): staring for stareLimit seconds makes it lunge stareSteps
-- closer; with nobody watching it steps closer every unwatchedStep seconds; held at
-- someone's edge of sight it holds.
-- StareItDown (amendment): someone must stare; with nobody staring it steps closer every
-- unwatchedStep seconds. Staring never makes it lunge.
-- It is gone (pass) after `presence` seconds, or once the boat is retreatDist away.
-- At the waterline: every lantern dies and it takes the nearest player (EntityFail).
-- A first sighting with `only` set is seen by that one player: only their gaze counts
-- (they can answer it alone) until they die.
-- Inside the dock light it never steps; its presence clock still runs.

local Types = require(script.Parent.Parent.Types)
local Rng = require(script.Parent.Parent.Rng)
local LakeMap = require(script.Parent.Parent.LakeMap)
local EntityBase = require(script.Parent.Parent.EntityBase)

type Event = Types.Event
type EntityObs = Types.EntityObs
type Vec2 = Types.Vec2
type PlayerId = Types.PlayerId

export type WatcherState = {
	base: EntityBase.Base,
	shore: Vec2, -- the waterline point
	out: Vec2, -- unit vector from the water to the trees
	step: number, -- steps left to the waterline
	pos: Vec2,
	stareT: number,
	unwatchedT: number,
	present: number,
	stareLimit: number,
	unwatchedStep: number,
}

local Watcher = {}

Watcher.id = "Watcher" :: Types.RuleId

local function posAt(s: WatcherState, step: number): Vec2
	local len = s.base.cfg.Rules.Watcher.stepLen
	return { x = s.shore.x + s.out.x * step * len, z = s.shore.z + s.out.z * step * len }
end

function Watcher.new(cfg: any, rng: Rng.RngState, ctx: EntityBase.SpawnCtx): WatcherState
	local R = cfg.Rules.Watcher
	local base = EntityBase.new("Watcher", cfg, rng, ctx, R.warn)
	local boatPos = if ctx.boat then ctx.boat.pos else cfg.Lake.dockEnd
	local shore = LakeMap.nearestShorePoint(cfg, boatPos)
	local dx, dz = shore.x - boatPos.x, shore.z - boatPos.z
	local d = math.sqrt(dx * dx + dz * dz)
	local out = if d > 1e-6 then { x = dx / d, z = dz / d } else { x = 0, z = -1 }
	local s: WatcherState = {
		base = base,
		shore = shore,
		out = out,
		step = R.steps,
		pos = shore,
		stareT = 0,
		unwatchedT = 0,
		present = 0,
		stareLimit = R.stareLimit * base.scale,
		unwatchedStep = R.unwatchedStep * base.scale,
	}
	s.pos = posAt(s, s.step)
	return s
end

-- Near a shore, and not before spawnMin seconds into the night.
function Watcher.eligible(cfg: any, info: any): boolean
	local R = cfg.Rules.Watcher
	return info.elapsed >= R.spawnMin and LakeMap.distanceToShore(cfg, info.boatPos) <= R.shoreRange
end

-- How one player's gaze meets the figure: "Stare", "Edge" or "Away".
function Watcher.gazeAt(cfg: any, boatPos: Vec2, figure: Vec2, p: Types.PlayerObs): string
	if p.bookOpen then
		return "Away"
	end
	local R = cfg.Rules.Watcher
	local diff = math.abs(EntityBase.wrapAngle(p.gazeYaw - EntityBase.bearing(boatPos, figure)))
	if diff < R.stareCone then
		return "Stare"
	elseif diff <= R.edgeCone then
		return "Edge"
	end
	return "Away"
end

local function nearest(s: WatcherState, obs: EntityObs): PlayerId?
	-- Seats are a boat length apart; the figure takes whoever is closest to its shore.
	-- Positions per seat are presentation, so pick the living player facing it the least.
	local best: PlayerId? = nil
	local bestDiff = -1
	local bearing = EntityBase.bearing(obs.boat.pos, s.pos)
	for _, p in obs.players do
		if obs.alive[p.id] then
			local diff = math.abs(EntityBase.wrapAngle(p.gazeYaw - bearing))
			if diff > bestDiff then
				best, bestDiff = p.id, diff
			end
		end
	end
	return best
end

local function stepTo(s: WatcherState, step: number, events: { Event })
	s.step = math.max(0, step)
	s.pos = posAt(s, s.step)
	table.insert(
		events,
		EntityBase.ev(s.base, "EntityMoved", { pos = { x = s.pos.x, z = s.pos.z }, step = s.step }, s.base.only)
	)
end

function Watcher.step(s: WatcherState, obs: EntityObs): { Event }
	local events: { Event } = {}
	local b = s.base
	local cfg = b.cfg
	local R = cfg.Rules.Watcher
	local dt = obs.dt
	if not EntityBase.advance(b, dt, events) then
		return events
	end
	if b.cueAt == nil then
		EntityBase.cue(b, { pos = { x = s.pos.x, z = s.pos.z }, step = s.step, steps = R.steps }, events)
		EntityBase.setStage(b, "Window", events)
		return events
	end

	s.present += dt
	if s.present >= R.presence or LakeMap.dist(obs.boat.pos, s.pos) >= R.retreatDist then
		EntityBase.pass(b, events, { pos = { x = s.pos.x, z = s.pos.z } })
		return events
	end
	if s.step <= 0 then
		-- At the waterline: the fail is waiting on the warning time (EntityBase holds it).
		return events
	end
	if obs.safe then
		return events
	end

	local anyStare, anyEdge = false, false
	local soloAlive = b.only ~= nil and obs.alive[b.only :: PlayerId] == true
	for _, p in obs.players do
		if obs.alive[p.id] and (not soloAlive or p.id == b.only) then
			local g = Watcher.gazeAt(cfg, obs.boat.pos, s.pos, p)
			if g == "Stare" then
				anyStare = true
			elseif g == "Edge" then
				anyEdge = true
			end
		end
	end

	if b.variant == "StareItDown" then
		if anyStare then
			s.unwatchedT = 0
		else
			s.unwatchedT += dt
			if s.unwatchedT >= s.unwatchedStep then
				s.unwatchedT = 0
				stepTo(s, s.step - 1, events)
			end
		end
	else
		if anyStare then
			s.unwatchedT = 0
			s.stareT += dt
			if s.stareT >= s.stareLimit then
				s.stareT = 0
				stepTo(s, s.step - R.stareSteps, events)
			end
		elseif anyEdge then
			s.unwatchedT = 0
			s.stareT = 0
		else
			s.stareT = 0
			s.unwatchedT += dt
			if s.unwatchedT >= s.unwatchedStep then
				s.unwatchedT = 0
				stepTo(s, s.step - 1, events)
			end
		end
	end

	if s.step <= 0 then
		local who = nearest(s, obs)
		EntityBase.fail(b, events, { kill = if who then { who } else {}, cause = "Reached", snuff = true })
	end
	return events
end

function Watcher.stage(s: WatcherState): Types.EntityStage
	return s.base.stage
end

function Watcher.done(s: WatcherState): boolean
	return EntityBase.done(s.base)
end

return Watcher
