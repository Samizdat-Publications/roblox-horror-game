--[[
Full-run simulation (Core M5): whole runs through Core.Run with the three crew bots of
tools/sim/crewbot.luau, for Normal and Nightmare and crew sizes 1 to 4, and the run
scorecard artifacts/score/run.md (and run.json).

    lune run tools/sim/run.luau [--fast] [--seeds N] [--difficulty Normal|Nightmare]
        [--crew N] [--policy follow|blind|greedy] [--out NAME] [--endless]

Each run starts with Run.new(cfg, { seed, difficulty, playerIds, firstRun = true }) and
plays Run.nightParams nights to dawn until Run.finishNight says RunCleared or RunOver
(retries per cfg.Difficulty). Targets (docs/CLOUD-BRIEF.md, Chunk M5):
  * follow clears a Normal run in at least 95% of seeds, a Nightmare run in at least 70%;
  * blind has a death by the end of night 2 in at least 90% of seeds;
  * greedy sees clearly more real scares than follow (median per run, and per night played).
--endless also plays follow-bot Endless runs (from night 6) and reports how far they get.
Writes run-fast.* with --fast (40 seeds). Exit 1 if a target misses on a full run.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local loader = require("./loader")
local crewbot = require("./crewbot")
local simParams = require("./params")

local fast = false
local seeds: number? = nil
local onlyDifficulty: string? = nil
local onlyCrew: number? = nil
local onlyPolicy: string? = nil
local outName: string? = nil
local endless = false
local i = 1
while i <= #process.args do
	local arg = process.args[i]
	if arg == "--fast" then
		fast = true
	elseif arg == "--seeds" then
		i += 1
		seeds = tonumber(process.args[i])
	elseif arg == "--difficulty" then
		i += 1
		onlyDifficulty = process.args[i]
	elseif arg == "--crew" then
		i += 1
		onlyCrew = tonumber(process.args[i])
	elseif arg == "--policy" then
		i += 1
		onlyPolicy = process.args[i]
	elseif arg == "--out" then
		i += 1
		outName = process.args[i]
	elseif arg == "--endless" then
		endless = true
	else
		print("run sim: unknown argument " .. arg)
		process.exit(2)
	end
	i += 1
end
local nSeeds = seeds or (if fast then 40 else 300)

local Shared, req = loader.load()
local cfg = req(Shared.Config)
local Run = req(Shared.Core.Run)
local core = simParams.core(Shared, req)

local function median(xs: { number }): number?
	if #xs == 0 then
		return nil
	end
	local c = table.clone(xs)
	table.sort(c)
	local n = #c
	if n % 2 == 1 then
		return c[(n + 1) / 2]
	end
	return (c[n / 2] + c[n / 2 + 1]) / 2
end

local function pct(x: number): string
	return string.format("%.0f%%", 100 * x)
end

-- One whole run. Returns its stats.
local function playRun(seed: number, difficulty: string, crew: number, policy: string, mode: string?)
	local ids = {}
	for p = 1, crew do
		table.insert(ids, p)
	end
	local run = Run.new(cfg, { seed = seed, difficulty = difficulty, mode = mode or "Story", playerIds = ids })
	local st = {
		cleared = false,
		nights = 0,
		retries = 0,
		real = 0,
		deathByNight2 = false,
		wipedByNight2 = false,
		lastNight = run.night,
		reasons = {},
		deathCards = {},
		finaleTries = 0,
		finalePasses = 0,
		bestNight = 0,
	}
	local guard = 0
	while not run.over and guard < 60 do
		guard += 1
		local p = Run.nightParams(run)
		local out = crewbot.runNight(core, cfg, p, { policy = policy })
		st.nights += 1
		st.real += #out.realSpawns
		if p.night <= 2 and #out.deaths > 0 then
			st.deathByNight2 = true
		end
		if p.night <= 2 and out.wiped then
			st.wipedByNight2 = true
		end
		for _, d in out.deaths do
			st.deathCards[d.text or d.rule] = (st.deathCards[d.text or d.rule] or 0) + 1
		end
		if p.night == 5 and p.mode == "Story" then
			st.finaleTries += 1
			if out.finalePassed then
				st.finalePasses += 1
			end
		end
		local result = out.result
		assert(result ~= nil, "a night played to dawn has a result")
		if not result.cleared then
			local key = string.format("n%d %s", p.night, out.failReason or "?")
			st.reasons[key] = (st.reasons[key] or 0) + 1
		end
		st.lastNight = p.night
		local outcome = Run.finishNight(run, result)
		if outcome == "RetryNight" then
			st.retries += 1
		end
	end
	st.cleared = run.cleared
	st.bestNight = run.bestNight
	return st
end

local difficulties = { "Normal", "Nightmare" }
local policies = { "follow", "blind", "greedy" }
local cells = {}
local misses = {}
local t0 = os.clock()
for _, difficulty in difficulties do
	if onlyDifficulty ~= nil and onlyDifficulty ~= difficulty then
		continue
	end
	for crew = 1, 4 do
		if onlyCrew ~= nil and onlyCrew ~= crew then
			continue
		end
		local cell = { difficulty = difficulty, crew = crew, seeds = nSeeds }
		for _, policy in policies do
			if onlyPolicy ~= nil and onlyPolicy ~= policy then
				continue
			end
			-- The blind and greedy bots only need Normal for their targets; Nightmare reports follow.
			if difficulty == "Nightmare" and policy ~= "follow" and onlyPolicy == nil then
				continue
			end
			local agg = {
				cleared = 0,
				deathByNight2 = 0,
				wipedByNight2 = 0,
				real = {},
				realPerNight = {},
				nights = {},
				retries = {},
				reasons = {},
				deathCards = {},
				finaleTries = 0,
				finalePasses = 0,
				lastNight = {},
			}
			for k = 1, nSeeds do
				local seed = 900001 + k * 7919 + crew * 104729
				local st = playRun(seed, difficulty, crew, policy)
				if st.cleared then
					agg.cleared += 1
				end
				if st.deathByNight2 then
					agg.deathByNight2 += 1
				end
				if st.wipedByNight2 then
					agg.wipedByNight2 += 1
				end
				table.insert(agg.real, st.real)
				table.insert(agg.realPerNight, st.real / math.max(1, st.nights))
				table.insert(agg.nights, st.nights)
				table.insert(agg.retries, st.retries)
				table.insert(agg.lastNight, st.lastNight)
				agg.finaleTries += st.finaleTries
				agg.finalePasses += st.finalePasses
				for key, n in st.reasons do
					agg.reasons[key] = (agg.reasons[key] or 0) + n
				end
				for key, n in st.deathCards do
					agg.deathCards[key] = (agg.deathCards[key] or 0) + n
				end
			end
			cell[policy] = {
				clearRate = agg.cleared / nSeeds,
				deathByNight2 = agg.deathByNight2 / nSeeds,
				wipedByNight2 = agg.wipedByNight2 / nSeeds,
				realMedian = median(agg.real),
				realPerNightMedian = median(agg.realPerNight),
				nightsMedian = median(agg.nights),
				retriesMedian = median(agg.retries),
				lastNightMedian = median(agg.lastNight),
				finaleRate = if agg.finaleTries > 0 then agg.finalePasses / agg.finaleTries else nil,
				reasons = agg.reasons,
				deathCards = agg.deathCards,
			}
			print(
				string.format(
					"%s crew %d %s: clear %s, death by n2 %s, real median %s (%.0f s)",
					difficulty,
					crew,
					policy,
					pct(agg.cleared / nSeeds),
					pct(agg.deathByNight2 / nSeeds),
					tostring(median(agg.real)),
					os.clock() - t0
				)
			)
		end
		-- Targets.
		local f, b, g = cell.follow, cell.blind, cell.greedy
		local target = if difficulty == "Normal" then 0.95 else 0.70
		cell.ok = true
		if f ~= nil and f.clearRate < target then
			cell.ok = false
			table.insert(
				misses,
				string.format("%s crew %d follow clear %s < %s", difficulty, crew, pct(f.clearRate), pct(target))
			)
		end
		if b ~= nil and b.deathByNight2 < 0.9 then
			cell.ok = false
			table.insert(
				misses,
				string.format("%s crew %d blind death by night 2 %s", difficulty, crew, pct(b.deathByNight2))
			)
		end
		if g ~= nil and f ~= nil and not ((g.realPerNightMedian or 0) > (f.realPerNightMedian or 0)) then
			cell.ok = false
			table.insert(misses, string.format("%s crew %d greedy not scarier", difficulty, crew))
		end
		table.insert(cells, cell)
	end
end

local endlessCells = {}
if endless then
	for crew = 1, 4 do
		if onlyCrew ~= nil and onlyCrew ~= crew then
			continue
		end
		local best = {}
		local n = math.max(10, math.floor(nSeeds / 4))
		for k = 1, n do
			local st = playRun(700001 + k * 7919 + crew * 104729, "Normal", crew, "follow", "Endless")
			table.insert(best, st.bestNight)
		end
		table.sort(best)
		table.insert(endlessCells, {
			crew = crew,
			seeds = n,
			bestMedian = median(best),
			bestMin = best[1],
			bestMax = best[#best],
		})
		print(string.format("Endless crew %d: best night median %s", crew, tostring(median(best))))
	end
end
local elapsed = os.clock() - t0

local function f1(x: number?): string
	return if x == nil then "-" else string.format("%.1f", x)
end

local lines = {
	"# Full-run scorecard" .. (if fast then " (fast)" else ""),
	"",
	string.format(
		"Whole runs through Core.Run, %d seeds per cell, first runs (Normal gets one amendment on night 5), retries: Normal %s, Nightmare %s. Bots: tools/sim/crewbot.luau.",
		nSeeds,
		tostring(cfg.Difficulty.Normal.retries),
		tostring(cfg.Difficulty.Nightmare.retries)
	),
	"Targets: follow clears Normal >= 95% and Nightmare >= 70%; blind has a death by the end of night 2 in >= 90%; greedy sees more real scares per night than follow.",
	"",
	"| Difficulty | Crew | Follow: run cleared | Follow: nights played (median) | Follow: retries (median) | Follow: finale passed per try | Follow: real scares per run (median) | Blind: death by night 2 | Blind: crew lost by night 2 | Greedy: run cleared | Greedy: real scares per night (median) | Follow: real scares per night (median) | OK |",
	"|---|---|---|---|---|---|---|---|---|---|---|---|---|",
}
for _, c in cells do
	local f, b, g = c.follow or {}, c.blind or {}, c.greedy or {}
	table.insert(
		lines,
		string.format(
			"| %s | %d | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |",
			c.difficulty,
			c.crew,
			if f.clearRate then pct(f.clearRate) else "-",
			f1(f.nightsMedian),
			f1(f.retriesMedian),
			if f.finaleRate then pct(f.finaleRate) else "-",
			f1(f.realMedian),
			if b.deathByNight2 then pct(b.deathByNight2) else "-",
			if b.wipedByNight2 then pct(b.wipedByNight2) else "-",
			if g.clearRate then pct(g.clearRate) else "-",
			if g.realPerNightMedian then string.format("%.2f", g.realPerNightMedian) else "-",
			if f.realPerNightMedian then string.format("%.2f", f.realPerNightMedian) else "-",
			if c.ok then "yes" else "MISS"
		)
	)
end
table.insert(lines, "")
table.insert(lines, "Follow-bot failed nights by night and reason (all cells):")
local reasons = {}
for _, c in cells do
	if c.follow then
		for key, n in c.follow.reasons do
			reasons[c.difficulty .. " " .. key] = (reasons[c.difficulty .. " " .. key] or 0) + n
		end
	end
end
local keys = {}
for key in reasons do
	table.insert(keys, key)
end
table.sort(keys)
for _, key in keys do
	table.insert(lines, string.format("- %s: %d", key, reasons[key]))
end
if #keys == 0 then
	table.insert(lines, "- none")
end
table.insert(lines, "")
table.insert(lines, "Follow-bot deaths by death card (all cells):")
local cards = {}
for _, c in cells do
	if c.follow then
		for key, n in c.follow.deathCards do
			cards[key] = (cards[key] or 0) + n
		end
	end
end
local ck = {}
for key in cards do
	table.insert(ck, key)
end
table.sort(ck)
for _, key in ck do
	table.insert(lines, string.format("- %s: %d", key, cards[key]))
end
if #ck == 0 then
	table.insert(lines, "- none")
end
if #endlessCells > 0 then
	table.insert(lines, "")
	table.insert(lines, "## Endless (follow bot, Normal)")
	table.insert(lines, "")
	table.insert(lines, "| Crew | Seeds | Best night min/median/max |")
	table.insert(lines, "|---|---|---|")
	for _, e in endlessCells do
		table.insert(
			lines,
			string.format(
				"| %d | %d | %s/%s/%s |",
				e.crew,
				e.seeds,
				tostring(e.bestMin),
				tostring(e.bestMedian),
				tostring(e.bestMax)
			)
		)
	end
end
table.insert(lines, "")
table.insert(lines, string.format("Simulated in %.1f s.", elapsed))
if #misses > 0 then
	table.insert(lines, "")
	table.insert(lines, "Misses: " .. table.concat(misses, "; "))
end
local md = table.concat(lines, "\n") .. "\n"

fs.writeDir("artifacts/score")
local base = "artifacts/score/" .. (outName or (if fast then "run-fast" else "run"))
fs.writeFile(base .. ".md", md)
fs.writeFile(
	base .. ".json",
	serde.encode("json", { fast = fast, seeds = nSeeds, cells = cells, endless = endlessCells }, true)
)
print(md)
if #misses > 0 and not fast and onlyDifficulty == nil and onlyCrew == nil and onlyPolicy == nil then
	process.exit(1)
end
process.exit(0)
