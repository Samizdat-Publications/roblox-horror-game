--!strict
-- The scare director (docs/ARCHITECTURE.md, Director; docs/DESIGN.md, The director).
--
--   Director.new(cfg, rng, params) -> DirectorState
--   Director.step(d, dt, ctx) -> { Decision }
--      ctx = { attention, activeReal, safe, timeLeft, elapsed, eligible: { RuleId }, aliveIds }
--   Director.resolved(d, rule, passed, at?)
--   Director.noteSpawn(d, rule)   -- a rule started outside the director (Night.debugForce)
--   Director.log(d) -> { { t, kind, id } }
--
-- Each night cycles calm, build and peak. A real scare spawns at the peak; after it
-- resolves the director guarantees a quiet gap and starts a new calm. Tonight's new rules
-- come first, one at a time, inside the teaching band, flagged teaching. High attention
-- shortens calm phases, sustained high attention adds one real scare, and very high
-- attention can bring a second rule while one is active (maxConcurrent). Fake-outs fill
-- the calm and build phases on their own budget and never land near a real cue.
-- The chorus band is the tension: max(attention, the phase's tension), 3 full to 1 sparse.
-- Only the rules decide silence (band 0).
--
-- Invariants (proven by tests/Director.spec.luau over hundreds of seeds):
--   no real spawn before openingGrace, inside a quiet gap, or while the boat is safe;
--   real and fake budgets never exceeded; each new director rule spawns once with
--   teaching = true inside the teaching band (when the world allows it); no fake-out
--   within fakeClear seconds of a real cue; a real cue with `only` set leaves at least
--   soloCueMinSeconds of night; never more than maxConcurrent real rules active.

local Types = require(script.Parent.Types)
local Rng = require(script.Parent.Rng)
local Fakeouts = require(script.Parent.Fakeouts)

type RuleId = Types.RuleId
type PlayerId = Types.PlayerId
type NightParams = Types.NightParams

export type Decision = {
	kind: string, -- "Spawn" | "Fakeout" | "Chorus"
	rule: RuleId?,
	teaching: boolean?,
	only: PlayerId?,
	id: string?,
	band: number?,
}

export type Ctx = {
	attention: number,
	activeReal: number,
	safe: boolean,
	timeLeft: number,
	elapsed: number,
	eligible: { RuleId },
	aliveIds: { PlayerId },
}

export type LogEntry = { t: number, kind: string, id: string, teaching: boolean?, only: PlayerId? }

export type DirectorState = {
	cfg: any,
	rng: Rng.RngState,
	params: NightParams,
	now: number,
	realBudget: number,
	fakeBudget: number,
	realUsed: number,
	fakeUsed: number,
	bonusAdded: boolean,
	highFor: number,
	teachQueue: { RuleId },
	teachAt: number,
	bandStart: number,
	bandEnd: number,
	active: { [string]: number }, -- rule -> spawn time
	activeCount: number,
	lastResolved: number,
	lastSpawn: number,
	lastFake: number,
	lastRule: string?,
	lastFakeId: string?,
	cycleStart: number,
	calmLen: number,
	buildLen: number,
	nextReal: number,
	nextFakeAt: number,
	attention: number,
	band: number,
	watcherSeen: boolean,
	entries: { LogEntry },
}

local Director = {}

-- Rules the director spawns. WrongCatch follows the crew's own choices and Finale is the
-- night 5 clock (Core M5); neither is a director spawn.
Director.RULES = { "Hum", "Neighbor", "Knocking", "Watcher" } :: { RuleId }

local NEVER = math.huge
local PAST = -math.huge

local function has(list: { any }, v: any): boolean
	for _, x in list do
		if x == v then
			return true
		end
	end
	return false
end

local function drawCycle(d: DirectorState, start: number)
	local D = d.cfg.Director
	local shrink = 1 - d.cfg.Attention.calmShrink * math.clamp(d.attention, 0, 1)
	d.cycleStart = start
	d.calmLen = Rng.range(d.rng, D.calmMin, D.calmMax) * shrink
	d.buildLen = Rng.range(d.rng, D.buildMin, D.buildMax)
	d.nextReal = start + d.calmLen + d.buildLen
end

local function fakeSpread(d: DirectorState, timeLeft: number): number
	local left = d.fakeBudget - d.fakeUsed
	return math.max(0, 2 * timeLeft / (left + 1) - d.cfg.Director.fakeGap)
end

function Director.new(cfg: any, rng: Rng.RngState, params: NightParams): DirectorState
	local N = cfg.Night
	local length = N.realSeconds
	local teach: { RuleId } = {}
	for _, r in params.newRules do
		if has(Director.RULES, r) and has(params.rules, r) then
			table.insert(teach, r)
		end
	end
	local d: DirectorState = {
		cfg = cfg,
		rng = rng,
		params = params,
		now = 0,
		realBudget = math.max(0, math.floor(params.real)),
		fakeBudget = math.max(0, math.floor(params.fake)),
		realUsed = 0,
		fakeUsed = 0,
		bonusAdded = false,
		highFor = 0,
		teachQueue = teach,
		teachAt = NEVER,
		bandStart = N.teachFrom * length,
		bandEnd = N.teachTo * length,
		active = {},
		activeCount = 0,
		lastResolved = PAST,
		lastSpawn = PAST,
		lastFake = PAST,
		lastRule = nil,
		lastFakeId = nil,
		cycleStart = 0,
		calmLen = 0,
		buildLen = 0,
		nextReal = NEVER,
		nextFakeAt = NEVER,
		attention = 0,
		band = 3,
		watcherSeen = false,
		entries = {},
	}
	-- The teaching budget comes first: never fewer real scares than new rules to teach.
	d.realBudget = math.max(d.realBudget, #teach)
	if #teach > 0 then
		local span = d.bandEnd - d.bandStart
		d.teachAt = d.bandStart + Rng.range(rng, 0, 0.12 * span)
	end
	drawCycle(d, 0)
	d.nextReal = math.max(d.nextReal, N.openingGrace)
	d.nextFakeAt = cfg.Director.fakeGap + Rng.range(rng, 0, fakeSpread(d, length))
	return d
end

local function logEntry(d: DirectorState, kind: string, id: string, teaching: boolean?, only: PlayerId?)
	table.insert(d.entries, { t = d.now, kind = kind, id = id, teaching = teaching, only = only })
end

local function bandFor(cfg: any, tension: number): number
	local b = cfg.Director.chorusBands
	if tension < b[1] then
		return 3
	elseif tension < b[2] then
		return 2
	end
	return 1
end

-- The next planned real spawn time (teaching or the cycle's peak).
local function planned(d: DirectorState): number
	if #d.teachQueue > 0 then
		return d.teachAt
	end
	if d.realUsed >= d.realBudget then
		return NEVER
	end
	return d.nextReal
end

local function phaseTension(d: DirectorState, ctx: Ctx): number
	local t = ctx.elapsed
	if ctx.safe then
		return 0
	end
	if d.activeCount > 0 then
		return 0.9
	end
	if t < d.lastResolved + d.params.quietGap then
		return 0.2
	end
	local p = planned(d)
	if p == NEVER then
		return 0.1
	end
	local build = d.buildLen
	if t >= p then
		return 0.9 -- the peak, waiting for the world to allow the scare
	elseif p - t <= build then
		return 0.3 + 0.55 * (1 - (p - t) / build)
	end
	local calmStart = math.max(d.cycleStart, d.lastResolved)
	local calmEnd = p - build
	local f = if calmEnd > calmStart then math.clamp((t - calmStart) / (calmEnd - calmStart), 0, 1) else 1
	return 0.1 + 0.15 * f
end

local function pickAlive(d: DirectorState, ids: { PlayerId }): PlayerId?
	if #ids == 0 then
		return nil
	end
	return Rng.pick(d.rng, ids)
end

-- Every gate a real spawn must pass (the invariants live here).
local function realAllowed(d: DirectorState, ctx: Ctx): boolean
	local cfg = d.cfg
	local t = ctx.elapsed
	local active = math.max(d.activeCount, ctx.activeReal)
	return t >= cfg.Night.openingGrace
		and t >= d.lastResolved + d.params.quietGap
		and not ctx.safe
		and active < math.max(1, d.params.maxConcurrent)
		and d.realUsed < d.realBudget
		and t >= d.lastFake + cfg.Director.fakeClear
		and ctx.timeLeft >= math.max(cfg.Director.lateCutoff, cfg.Director.soloCueMinSeconds)
end

local function spawn(d: DirectorState, ctx: Ctx, rule: RuleId, teaching: boolean, out: { Decision })
	local only: PlayerId? = nil
	if rule == "Watcher" and not d.watcherSeen then
		-- The first sighting of the night goes to one player.
		only = pickAlive(d, ctx.aliveIds)
	end
	if rule == "Watcher" then
		d.watcherSeen = true
	end
	d.realUsed += 1
	d.active[rule] = ctx.elapsed
	d.activeCount += 1
	d.lastSpawn = ctx.elapsed
	d.lastRule = rule
	d.nextReal = NEVER -- the next cycle starts when this one resolves
	logEntry(d, "Spawn", rule, teaching, only)
	table.insert(out, { kind = "Spawn", rule = rule, teaching = teaching, only = only })
end

function Director.step(d: DirectorState, dt: number, ctx: Ctx): { Decision }
	local cfg = d.cfg
	local D = cfg.Director
	local out: { Decision } = {}
	local t = ctx.elapsed
	d.now = t
	d.attention = ctx.attention

	-- Sustained high attention adds one real scare (once per night).
	if ctx.attention >= cfg.Attention.budgetBonusAt then
		d.highFor += dt
		if d.highFor >= cfg.Attention.budgetBonusSeconds and not d.bonusAdded then
			d.bonusAdded = true
			d.realBudget += 1
			logEntry(d, "Bonus", "real")
		end
	else
		d.highFor = 0
	end

	-- Real scares.
	if realAllowed(d, ctx) then
		if #d.teachQueue > 0 then
			if t >= d.teachAt and d.activeCount == 0 and ctx.activeReal == 0 then
				for i, rule in d.teachQueue do
					if has(ctx.eligible, rule) then
						table.remove(d.teachQueue, i)
						spawn(d, ctx, rule, true, out)
						break
					end
				end
			end
		elseif #ctx.eligible > 0 then
			local overlap = d.activeCount > 0
				and ctx.attention >= cfg.Attention.budgetBonusAt
				and t >= d.lastSpawn + D.overlapAfter
			if (d.activeCount == 0 and ctx.activeReal == 0 and t >= d.nextReal) or overlap then
				local pool: { RuleId } = {}
				for _, r in ctx.eligible do
					if r ~= d.lastRule and d.active[r] == nil then
						table.insert(pool, r)
					end
				end
				if #pool == 0 then
					for _, r in ctx.eligible do
						if d.active[r] == nil then
							table.insert(pool, r)
						end
					end
				end
				if #pool > 0 then
					spawn(d, ctx, Rng.pick(d.rng, pool), false, out)
				end
			end
		end
	end

	-- Fake-outs: calm and build only, spaced, on budget, never near a real cue.
	local p = planned(d)
	if
		d.fakeUsed < d.fakeBudget
		and t >= d.nextFakeAt
		and d.activeCount == 0
		and ctx.activeReal == 0
		and not ctx.safe
		and t >= d.lastSpawn + D.fakeClear
		and t >= d.lastFake + D.fakeGap
		-- Not just before a planned real scare, nor at a peak still waiting on the world.
		and p - t > D.fakeClear + 1
		and #out == 0
	then
		local id = Fakeouts.pick(cfg, d.rng, d.lastFakeId)
		local only: PlayerId? = nil
		if Rng.next(d.rng) < D.onlyOneChance then
			only = pickAlive(d, ctx.aliveIds)
		end
		d.fakeUsed += 1
		d.lastFake = t
		d.lastFakeId = id
		d.nextFakeAt = t + D.fakeGap + Rng.range(d.rng, 0, fakeSpread(d, ctx.timeLeft))
		logEntry(d, "Fakeout", id, nil, only)
		table.insert(out, { kind = "Fakeout", id = id, only = only })
	end

	-- The chorus follows the tension.
	local band = bandFor(cfg, math.max(ctx.attention, phaseTension(d, ctx)))
	if band ~= d.band then
		d.band = band
		table.insert(out, { kind = "Chorus", band = band })
	end
	return out
end

-- A real rule resolved: the quiet gap starts now and a new cycle is drawn. t is the
-- night time of the resolution (defaults to the last step's time).
function Director.resolved(d: DirectorState, rule: RuleId, passed: boolean, at: number?)
	if d.active[rule] == nil then
		return
	end
	if at ~= nil then
		d.now = at
	end
	d.active[rule] = nil
	d.activeCount = math.max(0, d.activeCount - 1)
	d.lastResolved = d.now
	logEntry(d, if passed then "Pass" else "Fail", rule)
	if d.activeCount == 0 then
		drawCycle(d, d.now)
		d.nextReal = math.max(d.nextReal, d.now + d.params.quietGap)
	end
end

-- A rule started outside the director (Studio scenarios): count it as active so the
-- invariants still hold around it. It does not use the budget.
function Director.noteSpawn(d: DirectorState, rule: RuleId)
	if d.active[rule] ~= nil then
		return
	end
	d.active[rule] = d.now
	d.activeCount += 1
	d.lastSpawn = d.now
	d.nextReal = NEVER
	local i = table.find(d.teachQueue, rule)
	if i ~= nil then
		table.remove(d.teachQueue, i)
	end
	logEntry(d, "Forced", rule)
end

function Director.isActive(d: DirectorState, rule: RuleId): boolean
	return d.active[rule] ~= nil
end

function Director.log(d: DirectorState): { LogEntry }
	return d.entries
end

return Director
