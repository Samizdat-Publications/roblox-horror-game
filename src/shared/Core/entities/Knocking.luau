--!strict
-- Rule 4, the Knocking (docs/DESIGN.md). Three slow knocks from under the hull (the cue,
-- `knockGap` apart). Then the window: any living players answer with the knock button,
-- exactly N knocks in total inside it. N is 2 as printed (AnswerTwo), 1 for AnswerOne,
-- 0 for AnswerNone ("let it knock"). Knocks before the window opens are not answers.
-- Too many knocks is wrong at once; otherwise the count is judged when the window ends.
-- Wrong once: it knocks again, harder, with a shorter window (secondWindow). Wrong
-- again: EntityFail with effects { flood }: water comes in and Night runs the leak, the
-- bailing and the sinking.
--
-- Inside the dock light the window does not run and knocks are not counted.

local Types = require(script.Parent.Parent.Types)
local Rng = require(script.Parent.Parent.Rng)
local EntityBase = require(script.Parent.Parent.EntityBase)

type Event = Types.Event
type EntityObs = Types.EntityObs

export type KnockingState = {
	base: EntityBase.Base,
	answer: number, -- knocks wanted
	round: number, -- 1 or 2
	phase: string, -- "Knocks" | "Window"
	knocksLen: number,
	window: number, -- this round's window, scaled
	left: number, -- window seconds left
	count: number, -- answers this round
	wrong: number, -- wrong rounds so far
}

local Knocking = {}

Knocking.id = "Knocking" :: Types.RuleId
Knocking.ANSWERS = { AnswerTwo = 2, AnswerOne = 1, AnswerNone = 0 } :: { [string]: number }
Knocking.CUE_KNOCKS = 3

function Knocking.new(cfg: any, rng: Rng.RngState, ctx: EntityBase.SpawnCtx): KnockingState
	local R = cfg.Rules.Knocking
	local base = EntityBase.new("Knocking", cfg, rng, ctx, R.window)
	local answer = Knocking.ANSWERS[base.variant]
	if answer == nil then
		answer = R.answer
	end
	return {
		base = base,
		answer = answer,
		round = 1,
		phase = "Knocks",
		knocksLen = Knocking.CUE_KNOCKS * R.knockGap,
		window = R.window * base.scale,
		left = R.window * base.scale,
		count = 0,
		wrong = 0,
	}
end

function Knocking.eligible(_cfg: any, _info: any): boolean
	return true
end

local function startRound(s: KnockingState, round: number, events: { Event })
	local R = s.base.cfg.Rules.Knocking
	s.round = round
	s.phase = "Knocks"
	s.count = 0
	s.window = (if round == 1 then R.window else R.secondWindow) * s.base.scale
	s.left = s.window
	if round > 1 then
		EntityBase.setStage(s.base, "Cue", events, {
			round = round,
			knocks = Knocking.CUE_KNOCKS,
			gap = R.knockGap,
			hard = true,
		})
	end
end

local function judge(s: KnockingState, events: { Event })
	if s.count == s.answer then
		EntityBase.pass(s.base, events, { round = s.round })
		return
	end
	s.wrong += 1
	if s.round == 1 then
		startRound(s, 2, events)
	else
		EntityBase.fail(s.base, events, { flood = true, cause = "Sunk" })
	end
end

function Knocking.step(s: KnockingState, obs: EntityObs): { Event }
	local events: { Event } = {}
	local b = s.base
	local R = b.cfg.Rules.Knocking
	if not EntityBase.advance(b, obs.dt, events) then
		return events
	end
	if b.cueAt == nil then
		EntityBase.cue(
			b,
			{ round = 1, knocks = Knocking.CUE_KNOCKS, gap = R.knockGap, answerWindow = s.window },
			events
		)
		return events
	end
	if s.phase == "Knocks" then
		if b.stageTime >= s.knocksLen then
			s.phase = "Window"
			EntityBase.setStage(b, "Window", events, { round = s.round, window = s.window })
		end
		return events
	end
	if obs.safe then
		return events
	end
	for _, it in obs.intents do
		if it.kind == "Knock" and obs.alive[it.player] then
			s.count += 1
		end
	end
	if s.count > s.answer then
		judge(s, events)
		return events
	end
	s.left -= obs.dt
	if s.left <= 0 then
		judge(s, events)
	end
	return events
end

function Knocking.stage(s: KnockingState): Types.EntityStage
	return s.base.stage
end

function Knocking.done(s: KnockingState): boolean
	return EntityBase.done(s.base)
end

return Knocking
