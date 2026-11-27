--!strict
-- A run: five Story nights (or Endless Nights from night 6), retries, and the night table
-- (docs/ARCHITECTURE.md, Run).
--
--   Run.new(cfg, { seed, difficulty, mode, playerIds, firstRun }) -> RunState
--   Run.nightParams(run) -> NightParams
--   Run.finishNight(run, result) -> "NextNight" | "RetryNight" | "RunCleared" | "RunOver"
--   Run.setPlayers(run, ids)           -- crew changes between nights (late joiners)
--   Run.view(run) -> RunView           -- for the lobby and the night cards
--   Run.supplyChoices(run) -> {}       -- the supply pick was cut (11/26/2026): always empty
--   Run.chooseSupply(run, id)          -- no-op, kept so the contract stays callable
--
-- Story: night n uses every rule taped in so far (Rulebook.taped), cfg.Nights[n] for the
-- budgets and the quota, scaled by the crew size at night start (cfg.Scaling) and the
-- difficulty (cfg.Difficulty: warning windows, real budget, quiet gaps). Solo crews get
-- longer warnings through cfg.Scaling.warning. Clearing night 5 clears the run.
-- A failed night is played again with a fresh night seed and the same page of the book,
-- while the run has retries left (cfg.Difficulty[d].retries per run, nil = no limit);
-- then the run is over.
-- Endless (mode "Endless", starts at night 6): every night draws a mix of rules and
-- amendments from the run seed; budgets and quota grow per night from cfg.Endless with
-- caps. A failed Endless night ends the run (cfg.Endless.retries); bestNight is the
-- highest night cleared.

local Types = require(script.Parent.Types)
local Rng = require(script.Parent.Rng)
local Quota = require(script.Parent.Quota)
local Rulebook = require(script.Parent.Rulebook)

type NightParams = Types.NightParams
type NightResult = Types.NightResult
type RuleId = Types.RuleId
type PlayerId = Types.PlayerId

export type RunOpts = {
	seed: number,
	difficulty: Types.Difficulty?,
	mode: Types.Mode?,
	playerIds: { PlayerId },
	firstRun: boolean?,
}

export type RunState = {
	cfg: any,
	seed: number,
	difficulty: Types.Difficulty,
	mode: Types.Mode,
	playerIds: { PlayerId },
	firstRun: boolean,
	night: number,
	attempt: number, -- 1 on a night's first try
	retriesLeft: number?, -- nil: no limit
	nightsCleared: number,
	attempts: number, -- nights played in all
	bestNight: number, -- Endless: highest night cleared (0 if none)
	cleared: boolean, -- the Story run is cleared
	over: boolean, -- no more nights (cleared, or out of retries)
	scaresSurvived: number,
	fishBanked: number, -- fish (not points), from NightResult.bankedFish
	deaths: number,
	crewAtStart: number, -- crew size when the run began (a solo run stays solo)
	soloRun: boolean, -- every night so far was played by one player
}

export type RunView = {
	night: number,
	attempt: number,
	retriesLeft: number?,
	mode: Types.Mode,
	difficulty: Types.Difficulty,
	nightsCleared: number,
	bestNight: number,
	cleared: boolean,
	over: boolean,
}

local Run = {}

Run.ENDLESS_FROM = 6

local function difficultyCfg(cfg: any, d: Types.Difficulty): any
	return cfg.Difficulty[d] or cfg.Difficulty.Normal
end

function Run.new(cfg: any, o: RunOpts): RunState
	assert(#o.playerIds >= 1, "a run needs at least one player")
	local difficulty: Types.Difficulty = o.difficulty or "Normal"
	local mode: Types.Mode = o.mode or "Story"
	local retries = if mode == "Endless" then cfg.Endless.retries else difficultyCfg(cfg, difficulty).retries
	return {
		cfg = cfg,
		seed = math.floor(o.seed),
		difficulty = difficulty,
		mode = mode,
		playerIds = table.clone(o.playerIds),
		firstRun = o.firstRun ~= false,
		night = if mode == "Endless" then Run.ENDLESS_FROM else 1,
		attempt = 1,
		retriesLeft = retries,
		nightsCleared = 0,
		attempts = 0,
		bestNight = 0,
		cleared = false,
		over = false,
		scaresSurvived = 0,
		fishBanked = 0,
		deaths = 0,
		crewAtStart = #o.playerIds,
		soloRun = #o.playerIds == 1,
	}
end

-- The crew for the next night (players who joined or left between nights).
function Run.setPlayers(run: RunState, ids: { PlayerId })
	assert(#ids >= 1, "a night needs at least one player")
	run.playerIds = table.clone(ids)
end

-- A night seed from the run seed, the night and the attempt: a retry is a fresh night.
function Run.nightSeed(run: RunState): number
	local r = Rng.fork(Rng.new(run.seed), "night:" .. tostring(run.night) .. ":" .. tostring(run.attempt))
	return r.seed
end

local function has(list: { any }, v: any): boolean
	for _, x in list do
		if x == v then
			return true
		end
	end
	return false
end

-- Endless night `night`'s rule mix, from the run seed: rulesMin..rulesMax of the director
-- rules, plus Wrong Catch with chance wrongCatchChance. Never empty.
function Run.endlessRules(cfg: any, seed: number, night: number): { RuleId }
	local E = cfg.Endless
	local r = Rng.fork(Rng.new(seed), "endless:" .. tostring(night))
	local pool: { RuleId } = { "Hum", "Neighbor", "Knocking", "Watcher" }
	local n = Rng.int(r, math.min(E.rulesMin, #pool), math.min(E.rulesMax, #pool))
	local picked: { RuleId } = {}
	for _ = 1, n do
		local i = Rng.int(r, 1, #pool)
		table.insert(picked, table.remove(pool, i) :: RuleId)
	end
	local out: { RuleId } = {}
	-- Book order, so the page and the director see a stable list.
	for _, id in { "Hum", "WrongCatch", "Neighbor", "Knocking", "Watcher" } :: { RuleId } do
		if id == "WrongCatch" then
			if Rng.next(r) < E.wrongCatchChance then
				table.insert(out, id)
			end
		elseif has(picked, id) then
			table.insert(out, id)
		end
	end
	return out
end

local function crewIndex(cfg: any, crew: number): number
	return math.clamp(math.floor(crew), 1, #cfg.Scaling.quota)
end

local function realBudget(cfg: any, base: number, crew: number, D: any): number
	return math.max(1, math.floor(base * cfg.Scaling.budget[crewIndex(cfg, crew)] * D.budget + 0.5))
end

function Run.nightParams(run: RunState): NightParams
	local cfg = run.cfg
	local crew = #run.playerIds
	local ci = crewIndex(cfg, crew)
	local D = difficultyCfg(cfg, run.difficulty)
	local warningScale = cfg.Scaling.warning[ci] * D.warning
	local rules: { RuleId }
	local newRules: { RuleId }
	local real, fake, quietGap, quotaBase, maxConcurrent
	if run.mode == "Endless" then
		local E = cfg.Endless
		local k = math.max(1, run.night - Run.ENDLESS_FROM + 1)
		rules = Run.endlessRules(cfg, run.seed, run.night)
		newRules = {}
		real = realBudget(cfg, math.min(E.realCap, math.floor(E.realBase + E.realPerNight * (k - 1))), crew, D)
		fake = E.fakeBase
		quietGap = math.max(E.quietGapFloor, E.quietGapBase - E.quietGapStep * (k - 1)) * D.quiet
		quotaBase = E.quotaBase + E.quotaPerNight * (k - 1)
		maxConcurrent = E.maxConcurrent
	else
		local N = cfg.Nights[run.night]
		rules = Rulebook.taped(cfg, "Story", run.night)
		newRules = table.clone(N.newRules)
		real = realBudget(cfg, N.real, crew, D)
		fake = N.fake
		quietGap = N.quietGap * D.quiet
		quotaBase = N.quota
		maxConcurrent = N.maxConcurrent
	end
	local amendments = Rulebook.amendments(cfg, {
		seed = run.seed,
		difficulty = run.difficulty,
		mode = run.mode,
		night = run.night,
		rules = rules,
		firstRun = run.firstRun,
	})
	local ids = table.clone(run.playerIds)
	return {
		seed = Run.nightSeed(run),
		night = run.night,
		mode = run.mode,
		difficulty = run.difficulty,
		playerIds = ids,
		rules = rules,
		newRules = newRules,
		amendments = amendments,
		supplies = {},
		real = real,
		fake = fake,
		quietGap = quietGap,
		quota = Quota.scaled(cfg, quotaBase, crew),
		maxConcurrent = maxConcurrent,
		warningScale = warningScale,
	}
end

export type FinishOutcome = "NextNight" | "RetryNight" | "RunCleared" | "RunOver"

function Run.finishNight(run: RunState, result: NightResult): FinishOutcome
	assert(not run.over, "the run is over")
	run.attempts += 1
	run.scaresSurvived += result.scaresSurvived
	run.deaths += #result.deaths
	if #run.playerIds ~= 1 then
		run.soloRun = false
	end
	-- Fish banked count whether or not the night was cleared (Profile's "fish banked").
	run.fishBanked += result.bankedFish or 0
	if result.cleared then
		run.nightsCleared += 1
		if run.mode == "Endless" then
			run.bestNight = math.max(run.bestNight, run.night)
		elseif run.night >= #run.cfg.Nights then
			run.cleared = true
			run.over = true
			return "RunCleared"
		end
		run.night += 1
		run.attempt = 1
		return "NextNight"
	end
	if run.retriesLeft == nil or (run.retriesLeft :: number) > 0 then
		if run.retriesLeft ~= nil then
			run.retriesLeft = (run.retriesLeft :: number) - 1
		end
		run.attempt += 1
		return "RetryNight"
	end
	run.over = true
	return "RunOver"
end

function Run.view(run: RunState): RunView
	return {
		night = run.night,
		attempt = run.attempt,
		retriesLeft = run.retriesLeft,
		mode = run.mode,
		difficulty = run.difficulty,
		nightsCleared = run.nightsCleared,
		bestNight = run.bestNight,
		cleared = run.cleared,
		over = run.over,
	}
end

-- The supply pick was cut (design change 11/26/2026).
function Run.supplyChoices(_run: RunState): { string }
	return {}
end

function Run.chooseSupply(_run: RunState, _id: string) end

return Run
