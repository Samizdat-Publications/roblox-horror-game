--!strict
-- Rule 3, the Neighbor (docs/DESIGN.md, reworked by the design review of 11/26/2026).
-- Two forms, drawn per spawn:
--
-- Boat (most of the time): a slow oarlock creak with nobody rowing (the cue,
-- creakSeconds), then a second lantern in the fog appearDist away. While the crew's
-- lantern is lit it drifts toward the boat at driftSpeed; with the lantern out it loses
-- track and drifts toward where the boat was when it last saw the light.
--   Counter: lantern out, and the boat kept more than holdDist from it, until it gives up
--   (lingerMin..lingerMax seconds of that) and drifts away (pass). It also gives up after
--   presenceMax seconds whatever happens.
--   Fail: it comes within killDist while the lantern is lit (the helm is taken), or any
--   living player waves while it is present (the waver is taken).
--   While present it sends 1 or 2 fake callouts in a living crewmate's name (kind
--   "Callout", data { phrase, fake = true, as }): "LanternOn", "Wave" or "GoHome". The
--   shell shows them exactly like real callouts, so the crew learns to distrust them.
--   With only one player alive there is nobody to impersonate: no fake callouts.
--   Amendment NoWaveRowAway: the crew must also move away; closing on it at all (faster
--   than closeSpeed for more than closeGrace seconds) takes the helm.
-- False beacon (falseBeaconChance): a steady light falseBeaconDist away, never on the
-- bearing of the real dock. It burns falseBeaconSeconds, then goes out (pass). Rowing to
-- within falseBeaconKill of it, or waving, is the fail.
-- Every fail snuffs the lantern and sits a silhouette in the boat.
-- Inside the dock light nothing fails and it does not follow; its clocks still run.

local Types = require(script.Parent.Parent.Types)
local Rng = require(script.Parent.Parent.Rng)
local LakeMap = require(script.Parent.Parent.LakeMap)
local EntityBase = require(script.Parent.Parent.EntityBase)

type Event = Types.Event
type EntityObs = Types.EntityObs
type Vec2 = Types.Vec2
type PlayerId = Types.PlayerId

export type NeighborState = {
	base: EntityBase.Base,
	form: string, -- "Boat" | "FalseBeacon"
	phase: string, -- Boat: "Creak" | "Hunt" | "Leave". Beacon: "Burn"
	pos: Vec2,
	lastSeen: Vec2?, -- where it last saw the boat's light
	giveUpLen: number,
	darkFor: number, -- seconds of lantern out with the boat past holdDist
	timer: number,
	present: number,
	closing: number, -- NoWaveRowAway: seconds spent closing on it
	moveClock: number,
	calloutsAt: { number }, -- presence times of the fake callouts still to come
}

local Neighbor = {}

Neighbor.id = "Neighbor" :: Types.RuleId
Neighbor.MOVE_EVERY = 0.5 -- EntityMoved at most this often while it drifts
Neighbor.LEAVE_MAX = 20 -- the drift away ends (pass) after this long at most
Neighbor.FAKE_PHRASES = { "LanternOn", "Wave", "GoHome" }

local function dist(a: Vec2, b: Vec2): number
	return LakeMap.dist(a, b)
end

local function along(from: Vec2, bearing: number, d: number): Vec2
	return { x = from.x + math.sin(bearing) * d, z = from.z + math.cos(bearing) * d }
end

local function onWater(cfg: any, p: Vec2): boolean
	return LakeMap.inside(cfg, p) and LakeMap.distanceToShore(cfg, p) >= 20
end

-- A spot `d` from the boat on open water (for the false beacon never within 60 degrees of
-- the dock's bearing). Never within 30 degrees of the bow: seen dead ahead it hides behind the
-- crew's own bow lantern (found in Studio 11/26/2026), and off the bow different seats see it
-- first. Falls back toward the lake center.
local BOW_CLEAR = math.rad(30)
local function placeAt(
	cfg: any,
	rng: Rng.RngState,
	boatPos: Vec2,
	d: number,
	avoidDock: boolean,
	heading: number?
): Vec2
	local dock = EntityBase.bearing(boatPos, cfg.Lake.dockEnd)
	for _ = 1, 32 do
		local a = Rng.range(rng, -math.pi, math.pi)
		local p = along(boatPos, a, d)
		local farFromDock = math.abs(EntityBase.wrapAngle(a - dock)) >= math.pi / 3
		local offBow = heading == nil or math.abs(EntityBase.wrapAngle(a - heading)) >= BOW_CLEAR
		if onWater(cfg, p) and offBow and (farFromDock or not avoidDock) and not LakeMap.isSafe(cfg, p) then
			return p
		end
	end
	local a = EntityBase.bearing(boatPos, { x = 0, z = 0 })
	local dd = d
	while dd > 30 do
		local p = along(boatPos, a, dd)
		if onWater(cfg, p) then
			return p
		end
		dd -= 20
	end
	return along(boatPos, a, 30)
end

function Neighbor.new(cfg: any, rng: Rng.RngState, ctx: EntityBase.SpawnCtx): NeighborState
	local R = cfg.Rules.Neighbor
	local base = EntityBase.new("Neighbor", cfg, rng, ctx, R.warn)
	local form = if ctx.form ~= nil
		then ctx.form
		elseif Rng.next(rng) < R.falseBeaconChance then "FalseBeacon"
		else "Boat"
	local boatPos = if ctx.boat then ctx.boat.pos else cfg.Lake.dockEnd
	local d = if form == "Boat" then R.appearDist else R.falseBeaconDist
	local callouts: { number } = {}
	if form == "Boat" then
		local n = Rng.int(rng, R.fakeCallouts[1], R.fakeCallouts[2])
		for _ = 1, n do
			-- Early enough that even a crew that goes dark at once still hears them.
			table.insert(callouts, Rng.range(rng, R.creakSeconds + 2, R.creakSeconds + R.lingerMin - 2))
		end
		table.sort(callouts)
	end
	return {
		base = base,
		form = form,
		phase = if form == "Boat" then "Creak" else "Burn",
		pos = placeAt(cfg, rng, boatPos, d, form == "FalseBeacon", if ctx.boat then ctx.boat.heading else nil),
		lastSeen = nil,
		giveUpLen = Rng.range(rng, R.lingerMin, R.lingerMax),
		darkFor = 0,
		timer = 0,
		present = 0,
		closing = 0,
		moveClock = 0,
		calloutsAt = callouts,
	}
end

-- Not before a random time in spawnMin..spawnMax into the night (drawn by Night once).
function Neighbor.eligible(cfg: any, info: any): boolean
	local earliest = if info.neighborEarliest ~= nil then info.neighborEarliest else cfg.Rules.Neighbor.spawnMin
	return info.elapsed >= earliest
end

local function helmOf(obs: EntityObs): PlayerId?
	for _, p in obs.players do
		if p.helm and obs.alive[p.id] then
			return p.id
		end
	end
	for _, p in obs.players do
		if obs.alive[p.id] then
			return p.id
		end
	end
	return nil
end

local function taken(s: NeighborState, events: { Event }, who: PlayerId?, cause: string)
	EntityBase.fail(s.base, events, {
		kill = if who then { who } else {},
		cause = cause,
		snuff = true,
		silhouette = true,
	})
end

local function moved(s: NeighborState, events: { Event }, dt: number)
	s.moveClock += dt
	if s.moveClock >= Neighbor.MOVE_EVERY then
		s.moveClock = 0
		table.insert(
			events,
			EntityBase.ev(s.base, "EntityMoved", { pos = { x = s.pos.x, z = s.pos.z }, phase = s.phase }, s.base.only)
		)
	end
end

-- Moves toward (sign 1) or away from (sign -1) a point, stopping short of it.
local function drift(s: NeighborState, toward: Vec2, speed: number, dt: number, sign: number)
	local d = dist(s.pos, toward)
	if d < 2 and sign > 0 then
		return
	end
	local step = math.min(speed * dt, if sign > 0 then d - 1 else speed * dt)
	local ux, uz = (toward.x - s.pos.x) / d, (toward.z - s.pos.z) / d
	local nextPos = { x = s.pos.x + ux * step * sign, z = s.pos.z + uz * step * sign }
	if LakeMap.inside(s.base.cfg, nextPos) and LakeMap.distanceToShore(s.base.cfg, nextPos) >= 5 then
		s.pos = nextPos
	end
end

-- A fake callout in a living crewmate's name.
local function fakeCallout(s: NeighborState, obs: EntityObs, events: { Event })
	local alive: { PlayerId } = {}
	for _, p in obs.players do
		if obs.alive[p.id] then
			table.insert(alive, p.id)
		end
	end
	-- Solo: there is no crewmate to impersonate, so no fake callouts.
	if #alive <= 1 then
		return
	end
	local as = Rng.pick(s.base.rng, alive)
	local phrase = Rng.pick(s.base.rng, Neighbor.FAKE_PHRASES)
	table.insert(events, {
		kind = "Callout",
		entity = "Neighbor",
		player = as,
		data = { phrase = phrase, fake = true, as = as },
	})
end

function Neighbor.step(s: NeighborState, obs: EntityObs): { Event }
	local events: { Event } = {}
	local b = s.base
	local cfg = b.cfg
	local R = cfg.Rules.Neighbor
	local dt = obs.dt
	if not EntityBase.advance(b, dt, events) then
		return events
	end
	local boatPos = obs.boat.pos
	if b.cueAt == nil then
		EntityBase.cue(b, { form = s.form, pos = { x = s.pos.x, z = s.pos.z } }, events)
		if s.form == "FalseBeacon" then
			EntityBase.setStage(b, "Window", events)
		end
		if obs.lanternOn then
			s.lastSeen = { x = boatPos.x, z = boatPos.z }
		end
		return events
	end
	s.present += dt
	s.timer += dt

	-- The fails (never inside the dock light).
	if not obs.safe then
		for _, it in obs.intents do
			if it.kind == "Wave" and obs.alive[it.player] then
				taken(s, events, it.player, "Waved")
				return events
			end
		end
		local d = dist(boatPos, s.pos)
		if s.form == "FalseBeacon" then
			if d < R.falseBeaconKill then
				taken(s, events, helmOf(obs), "Beacon")
				return events
			end
		elseif s.phase == "Hunt" then
			if obs.lanternOn and d < R.killDist then
				taken(s, events, helmOf(obs), "Closed")
				return events
			end
			-- Judged only once the warning time is up: a boat already moving when the creak came is not punished.
			if b.variant == "NoWaveRowAway" and d > 1e-6 and EntityBase.canFail(b) then
				-- The boat's speed toward it.
				local v = obs.boat.vel
				local toward = (v.x * (s.pos.x - boatPos.x) + v.z * (s.pos.z - boatPos.z)) / d
				if toward > R.closeSpeed then
					s.closing += dt
					if s.closing > R.closeGrace then
						taken(s, events, helmOf(obs), "Closed")
						return events
					end
				else
					s.closing = 0
				end
			end
		end
	end

	if s.form == "FalseBeacon" then
		if s.timer >= R.falseBeaconSeconds then
			EntityBase.pass(b, events, { form = s.form })
		end
		return events
	end

	-- Fake callouts while it is out there.
	while #s.calloutsAt > 0 and s.present >= s.calloutsAt[1] and s.phase ~= "Leave" do
		table.remove(s.calloutsAt, 1)
		fakeCallout(s, obs, events)
	end

	if s.phase == "Creak" then
		if s.timer >= R.creakSeconds then
			s.phase = "Hunt"
			s.timer = 0
			EntityBase.setStage(b, "Window", events, { pos = { x = s.pos.x, z = s.pos.z } })
		end
	elseif s.phase == "Hunt" then
		if obs.lanternOn and not obs.safe then
			s.lastSeen = { x = boatPos.x, z = boatPos.z }
		end
		if s.lastSeen ~= nil then
			drift(s, s.lastSeen :: Vec2, R.driftSpeed, dt, 1)
			moved(s, events, dt)
		end
		local d = dist(boatPos, s.pos)
		if not obs.lanternOn and (d > R.holdDist or obs.safe) then
			s.darkFor += dt
		elseif obs.lanternOn then
			s.darkFor = 0
		end
		if s.darkFor >= s.giveUpLen or s.present >= R.presenceMax then
			s.phase = "Leave"
			s.timer = 0
		end
	elseif s.phase == "Leave" then
		drift(s, boatPos, R.driftSpeed * 1.5, dt, -1)
		moved(s, events, dt)
		if dist(boatPos, s.pos) >= R.leaveDist or s.timer >= Neighbor.LEAVE_MAX then
			EntityBase.pass(b, events, { form = s.form })
		end
	end
	return events
end

function Neighbor.stage(s: NeighborState): Types.EntityStage
	return s.base.stage
end

function Neighbor.done(s: NeighborState): boolean
	return EntityBase.done(s.base)
end

return Neighbor
