--!strict
-- Rule 1, the Hum (docs/DESIGN.md). The whole chorus stops at once (the cue). After a
-- beat of silence a low hum rises; from its first note the crew has `warn` seconds to
-- comply, then must hold for holdMin..holdMax seconds: nobody reeling, motor off, boat
-- still, and the lantern out (as printed) or lit (amendment LanternLit). `grace` seconds
-- of noise in total are forgiven. Pass: the hum sinks away and the frogs come back.
-- Fail: the boat is thrown, the hold goes over the side, and whoever made the most noise
-- is pulled under.
--
-- Inside the dock light nothing counts as noise (no rule advances there); the hold timer
-- still runs, so a crew that reaches the light is let go.
-- An amended LanternLit Hum never counts a dark lantern against a crew that cannot light
-- it (no oil, or snuffed by another rule).

local Types = require(script.Parent.Parent.Types)
local Rng = require(script.Parent.Parent.Rng)
local EntityBase = require(script.Parent.Parent.EntityBase)

type Event = Types.Event
type EntityObs = Types.EntityObs
type PlayerId = Types.PlayerId

export type HumState = {
	base: EntityBase.Base,
	phase: string, -- "Silence" | "Comply" | "Hold"
	silence: number,
	comply: number,
	holdLen: number,
	held: number,
	noise: number,
	blame: { [PlayerId]: number },
	why: { [PlayerId]: { [string]: number } },
}

local Hum = {}

Hum.id = "Hum" :: Types.RuleId

function Hum.new(cfg: any, rng: Rng.RngState, ctx: EntityBase.SpawnCtx): HumState
	local R = cfg.Rules.Hum
	local base = EntityBase.new("Hum", cfg, rng, ctx, R.silence + R.warn)
	return {
		base = base,
		phase = "Silence",
		silence = R.silence,
		comply = R.warn * base.scale,
		holdLen = Rng.range(rng, R.holdMin, R.holdMax),
		held = 0,
		noise = 0,
		blame = {},
		why = {},
	}
end

-- Any rule may be started anywhere the director allows.
function Hum.eligible(_cfg: any, _info: any): boolean
	return true
end

local function helmOf(obs: EntityObs): PlayerId?
	for _, p in obs.players do
		if p.helm and obs.alive[p.id] then
			return p.id
		end
	end
	return nil
end

local function firstAlive(obs: EntityObs): PlayerId?
	for _, p in obs.players do
		if obs.alive[p.id] then
			return p.id
		end
	end
	return nil
end

local function aliveOr(obs: EntityObs, id: PlayerId?): PlayerId?
	if id ~= nil and obs.alive[id] then
		return id
	end
	return nil
end

-- The violations this tick, each with the player it is blamed on.
local function violations(s: HumState, obs: EntityObs): { { who: PlayerId?, why: string } }
	local cfg = s.base.cfg
	local out = {}
	for _, p in obs.players do
		if obs.alive[p.id] and obs.reeling[p.id] then
			table.insert(out, { who = p.id, why = "Reeling" })
		end
	end
	local o = obs :: any
	if obs.motorOn then
		table.insert(out, { who = aliveOr(obs, o.lastMotor) or helmOf(obs), why = "Motor" })
	end
	local v = obs.boat.vel
	if math.sqrt(v.x * v.x + v.z * v.z) >= cfg.Boat.stillSpeed then
		table.insert(out, { who = helmOf(obs) or aliveOr(obs, o.lastMotor), why = "Moving" })
	end
	if s.base.variant == "LanternLit" then
		if not obs.lanternOn and o.lanternCanLight ~= false then
			table.insert(out, { who = aliveOr(obs, o.lastLantern), why = "LanternDark" })
		end
	elseif obs.lanternOn then
		table.insert(out, { who = aliveOr(obs, o.lastLantern), why = "LanternLit" })
	end
	return out
end

local function loudest(s: HumState, obs: EntityObs): (PlayerId?, string)
	local best: PlayerId? = nil
	local bestN = -1
	for _, p in obs.players do
		local n = s.blame[p.id]
		if obs.alive[p.id] and n ~= nil and n > bestN then
			best, bestN = p.id, n
		end
	end
	if best == nil then
		best = helmOf(obs) or firstAlive(obs)
	end
	local cause, causeN = "Noise", -1
	if best ~= nil then
		for why, n in s.why[best] or {} do
			if n > causeN or (n == causeN and why < cause) then
				cause, causeN = why, n
			end
		end
	end
	return best, cause
end

function Hum.step(s: HumState, obs: EntityObs): { Event }
	local events: { Event } = {}
	local b = s.base
	local dt = obs.dt
	if not EntityBase.advance(b, dt, events) then
		return events
	end
	if b.cueAt == nil then
		b.silent = true
		EntityBase.cue(b, { silence = s.silence, comply = s.comply, hold = s.holdLen }, events)
		return events
	end
	if s.phase == "Silence" then
		if b.stageTime >= s.silence then
			s.phase = "Comply"
			EntityBase.setStage(b, "Window", events) -- the hum rises
		end
	elseif s.phase == "Comply" then
		if b.stageTime >= s.comply then
			s.phase = "Hold"
		end
	elseif s.phase == "Hold" then
		s.held += dt
		if not obs.safe then
			local vs = violations(s, obs)
			if #vs > 0 then
				s.noise += dt
				for _, v in vs do
					if v.who ~= nil then
						local who = v.who :: PlayerId
						s.blame[who] = (s.blame[who] or 0) + dt
						local w = s.why[who] or {}
						w[v.why] = (w[v.why] or 0) + dt
						s.why[who] = w
					end
				end
			end
		end
		if s.noise > b.cfg.Rules.Hum.grace then
			local victim, cause = loudest(s, obs)
			EntityBase.fail(b, events, {
				kill = if victim then { victim } else {},
				cause = cause,
				blame = victim,
				rock = true,
				loseHold = true,
			})
		elseif s.held >= s.holdLen then
			EntityBase.pass(b, events)
		end
	end
	return events
end

function Hum.stage(s: HumState): Types.EntityStage
	return s.base.stage
end

function Hum.done(s: HumState): boolean
	return EntityBase.done(s.base)
end

return Hum
