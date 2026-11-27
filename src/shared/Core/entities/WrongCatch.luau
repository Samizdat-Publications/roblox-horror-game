--!strict
-- Rule 2, Wrong Catch: the consequences (docs/DESIGN.md). The traits live in
-- Core.FishMutations; this is what happens when a crew keeps one anyway.
--
-- Throwing a wrong fish back is the counter: nothing starts. Keeping it raises the lake's
-- attention at once, with a floor for the rest of the night (Night applies that through
-- Core.Attention at the keep). Night starts this rule when a kept wrong fish reaches the
-- cooler. Its cue is the cooler settling as the lid closes (nothing new is revealed: the
-- Banked total already shows the tripled value and the choice is final). Some time later
-- (knockDelayMin..knockDelayMax) the cooler knocks from inside and fishEaten banked fish
-- are gone: EntityFail with effects { eatBanked }. A kept wrong fish lost before it is
-- banked never starts the rule.
-- The cooler is not the lake: its timer runs in the dock light too.

local Types = require(script.Parent.Parent.Types)
local Rng = require(script.Parent.Parent.Rng)
local EntityBase = require(script.Parent.Parent.EntityBase)

type Event = Types.Event
type EntityObs = Types.EntityObs

export type WrongCatchState = {
	base: EntityBase.Base,
	knockIn: number,
	waited: number,
}

local WrongCatch = {}

WrongCatch.id = "WrongCatch" :: Types.RuleId

function WrongCatch.new(cfg: any, rng: Rng.RngState, ctx: EntityBase.SpawnCtx): WrongCatchState
	local R = cfg.Rules.WrongCatch
	-- The knock delay is the warning; it is the same for every crew size.
	local c = table.clone(ctx)
	c.warningScale = 1
	c.teaching = false
	c.only = nil
	local base = EntityBase.new("WrongCatch", cfg, rng, c, R.knockDelayMin)
	base.variant = "Default"
	return { base = base, knockIn = Rng.range(rng, R.knockDelayMin, R.knockDelayMax), waited = 0 }
end

-- Never a director spawn.
function WrongCatch.eligible(_cfg: any, _info: any): boolean
	return false
end

function WrongCatch.step(s: WrongCatchState, obs: EntityObs): { Event }
	local events: { Event } = {}
	local b = s.base
	if not EntityBase.advance(b, obs.dt, events) then
		return events
	end
	if b.cueAt == nil then
		EntityBase.cue(b, { source = "Cooler" }, events)
		EntityBase.setStage(b, "Window", events)
		return events
	end
	s.waited += obs.dt
	if s.waited >= s.knockIn then
		EntityBase.fail(b, events, { eatBanked = b.cfg.Rules.WrongCatch.fishEaten, cause = "Cooler" })
	end
	return events
end

function WrongCatch.stage(s: WrongCatchState): Types.EntityStage
	return s.base.stage
end

function WrongCatch.done(s: WrongCatchState): boolean
	return EntityBase.done(s.base)
end

return WrongCatch
