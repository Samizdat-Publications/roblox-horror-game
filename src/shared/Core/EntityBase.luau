--!strict
-- The stage machine every rule shares (docs/ARCHITECTURE.md, Rule modules):
-- Idle -> Cue -> Window -> Pass or Fail -> Cooldown (then done).
--
-- Fairness lives here so no rule can break it:
--   * EntityCue is sent once, when the cue starts.
--   * Exactly one of EntityPass or EntityFail is sent; later calls are ignored.
--   * A fail is never sent until the cue has been out for `warn` seconds. A rule may ask
--     for a fail earlier (someone waved at once); it is held as pending and sent the moment
--     the warning time is up. `warn` is the rule's own minimum, scaled by warningScale (and
--     teachWarnMult when teaching); a cue shown to one player (`only`) waits at least
--     cfg.Director.soloCueMinSeconds.
--   * After the outcome the rule lingers in its Pass or Fail stage for ruleCooldown
--     seconds (presentation), then goes to Cooldown and is done.
--
-- Fail effects are data for Night to apply (rules never touch the crew):
--   kill = { PlayerId }, cause = string (death card), loseHold, rock, snuff (lantern out),
--   flood (start a leak), eatBanked (fish taken from the cooler).

local Types = require(script.Parent.Types)
local Rng = require(script.Parent.Rng)

type Event = Types.Event
type RuleId = Types.RuleId
type PlayerId = Types.PlayerId
type EntityStage = Types.EntityStage

export type Effects = {
	kill: { PlayerId }?,
	cause: string?,
	loseHold: boolean?,
	rock: boolean?,
	snuff: boolean?,
	flood: boolean?,
	eatBanked: number?,
	[string]: any,
}

-- What Night hands every rule's `new`.
export type SpawnCtx = {
	variant: string?,
	teaching: boolean?,
	warningScale: number?,
	only: PlayerId?,
	boat: Types.BoatObs?,
	aliveIds: { PlayerId }?,
	elapsed: number?,
	[string]: any,
}

export type Base = {
	id: RuleId,
	cfg: any,
	rng: Rng.RngState,
	variant: string,
	teaching: boolean,
	only: PlayerId?,
	scale: number, -- every warning window is multiplied by this
	warn: number, -- seconds from the cue before any fail may be sent
	stage: EntityStage,
	stageTime: number,
	age: number,
	cueAt: number?,
	outcome: string?, -- "Pass" | "Fail"
	pending: Effects?, -- a fail asked for before the warning time was up
	silent: boolean, -- the rule wants the chorus dead (the Hum)
	isDone: boolean,
}

local EntityBase = {}

-- `warnSeconds` is the rule's minimum cue-to-fail time before scaling.
function EntityBase.new(id: RuleId, cfg: any, rng: Rng.RngState, ctx: SpawnCtx, warnSeconds: number): Base
	local variants = cfg.Amendments[id]
	local variant = ctx.variant or (if variants then variants[1] else "Default")
	local teaching = ctx.teaching == true
	local scale = (ctx.warningScale or 1) * (if teaching then cfg.Director.teachWarnMult else 1)
	local warn = warnSeconds * scale
	if ctx.only ~= nil then
		warn = math.max(warn, cfg.Director.soloCueMinSeconds)
	end
	return {
		id = id,
		cfg = cfg,
		rng = rng,
		variant = variant,
		teaching = teaching,
		only = ctx.only,
		scale = scale,
		warn = warn,
		stage = "Idle",
		stageTime = 0,
		age = 0,
		cueAt = nil,
		outcome = nil,
		pending = nil,
		silent = false,
		isDone = false,
	}
end

function EntityBase.ev(b: Base, kind: string, data: { [string]: any }?, only: PlayerId?): Event
	return { kind = kind, entity = b.id, only = only, data = data }
end

function EntityBase.setStage(b: Base, stage: EntityStage, events: { Event }, extra: { [string]: any }?)
	if b.stage == stage then
		return
	end
	b.stage = stage
	b.stageTime = 0
	local only = if b.outcome == nil then b.only else nil
	local d: { [string]: any } = { stage = stage, variant = b.variant }
	for k, v in extra or {} do
		d[k] = v
	end
	table.insert(events, EntityBase.ev(b, "EntityStage", d, only))
end

-- Starts the cue. `data` carries rule data such as positions.
function EntityBase.cue(b: Base, data: { [string]: any }?, events: { Event })
	if b.cueAt ~= nil then
		return
	end
	b.cueAt = b.age
	local d: { [string]: any } = { variant = b.variant, teaching = b.teaching, warn = b.warn }
	for k, v in data or {} do
		d[k] = v
	end
	table.insert(events, EntityBase.ev(b, "EntityCue", d, b.only))
	EntityBase.setStage(b, "Cue", events)
end

function EntityBase.resolved(b: Base): boolean
	return b.outcome ~= nil or b.pending ~= nil
end

function EntityBase.canFail(b: Base): boolean
	return b.cueAt ~= nil and b.age - (b.cueAt :: number) >= b.warn - 1e-9
end

function EntityBase.pass(b: Base, events: { Event }, data: { [string]: any }?): boolean
	if EntityBase.resolved(b) then
		return false
	end
	b.outcome = "Pass"
	b.silent = false
	local d: { [string]: any } = { variant = b.variant, teaching = b.teaching }
	for k, v in data or {} do
		d[k] = v
	end
	table.insert(events, EntityBase.ev(b, "EntityPass", d))
	EntityBase.setStage(b, "Pass", events)
	return true
end

-- Withdraws a fail that is still held for the warning time and passes instead. For a rule
-- whose only cued player is gone: the fail would land on someone who never got the cue.
-- Returns true if the rule passed now.
function EntityBase.withdraw(b: Base, events: { Event }, data: { [string]: any }?): boolean
	if b.outcome ~= nil then
		return false
	end
	b.pending = nil
	return EntityBase.pass(b, events, data)
end

local function sendFail(b: Base, effects: Effects, events: { Event })
	b.outcome = "Fail"
	b.pending = nil
	b.silent = false
	table.insert(
		events,
		EntityBase.ev(b, "EntityFail", { variant = b.variant, teaching = b.teaching, effects = effects })
	)
	EntityBase.setStage(b, "Fail", events)
end

-- Asks for the fail. Sent now if the warning time is up, else held until it is.
-- Returns true if it was sent now.
function EntityBase.fail(b: Base, events: { Event }, effects: Effects): boolean
	if EntityBase.resolved(b) then
		return false
	end
	if EntityBase.canFail(b) then
		sendFail(b, effects, events)
		return true
	end
	b.pending = effects
	return false
end

-- Call at the top of every rule step: ages the rule, sends a pending fail when allowed,
-- and finishes the cooldown. Returns true while the rule should keep running its logic.
function EntityBase.advance(b: Base, dt: number, events: { Event }): boolean
	b.age += dt
	b.stageTime += dt
	if b.pending ~= nil and EntityBase.canFail(b) then
		sendFail(b, b.pending :: Effects, events)
	end
	if b.outcome ~= nil then
		if not b.isDone and b.stageTime >= b.cfg.Director.ruleCooldown and b.stage ~= "Cooldown" then
			EntityBase.setStage(b, "Cooldown", events)
			b.isDone = true
		end
		return false
	end
	return b.pending == nil
end

function EntityBase.done(b: Base): boolean
	return b.isDone
end

-- The living player ids, in a stable order.
function EntityBase.aliveList(alive: { [PlayerId]: boolean }, players: { Types.PlayerObs }): { PlayerId }
	local out: { PlayerId } = {}
	for _, p in players do
		if alive[p.id] then
			table.insert(out, p.id)
		end
	end
	return out
end

-- Bearing from a to b in the gaze convention (0 faces +z).
function EntityBase.bearing(a: Types.Vec2, b: Types.Vec2): number
	return math.atan2(b.x - a.x, b.z - a.z)
end

function EntityBase.wrapAngle(a: number): number
	a = a % (2 * math.pi)
	if a > math.pi then
		a -= 2 * math.pi
	end
	return a
end

return EntityBase
