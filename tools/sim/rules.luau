--[[
Rules simulation: full Story nights 1 to 4 (to dawn) for crew sizes 1 to 4, with the
three bot policies of tools/sim/crewbot.luau, and the scorecard
artifacts/score/rules.md (and rules.json).

    lune run tools/sim/rules.luau [--fast] [--seeds N]

Per night and crew size:
  * follow (book as printed): survival (no deaths) and quota (night cleared) rates, median
    time to quota as a fraction of the night, real scares and fake-outs per night (min,
    median, max), the shortest gap seen between two real scares, banked points.
  * follow, amended: the same bot on a random amendment of every rule, drawn per seed.
  * blind: any death, whole crew lost, median time of the first death, deaths per night.
  * greedy: survival and real scares (median), against follow's.
  * a quota hint: the median points the follow bot has banked at 70% of the night, as a
    base (four-player) quota, for tuning Config.Nights.
Night 5 (the Finale) is played in whole runs by tools/sim/run.luau.
Writes rules-fast.* with --fast (24 seeds). Always exits 0 (a report, not a gate).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local loader = require("./loader")
local crewbot = require("./crewbot")
local simParams = require("./params")

local fast = false
local seeds: number? = nil
local i = 1
while i <= #process.args do
	local arg = process.args[i]
	if arg == "--fast" then
		fast = true
	elseif arg == "--seeds" then
		i += 1
		seeds = tonumber(process.args[i])
	else
		print("rules sim: unknown argument " .. arg)
		process.exit(2)
	end
	i += 1
end
local nSeeds = seeds or (if fast then 24 else 200)

local Shared, req = loader.load()
local cfg = req(Shared.Config)
local Quota = req(Shared.Core.Quota)
local Rng = req(Shared.Core.Rng)
local core = simParams.core(Shared, req)
local length = cfg.Night.realSeconds

local function sorted(xs)
	local c = table.clone(xs)
	table.sort(c)
	return c
end
local function median(xs): number?
	if #xs == 0 then
		return nil
	end
	local c = sorted(xs)
	local n = #c
	if n % 2 == 1 then
		return c[(n + 1) / 2]
	end
	return (c[n / 2] + c[n / 2 + 1]) / 2
end
local function minOf(xs): number?
	if #xs == 0 then
		return nil
	end
	return sorted(xs)[1]
end
local function maxOf(xs): number?
	if #xs == 0 then
		return nil
	end
	local c = sorted(xs)
	return c[#c]
end
local function pct(n, d): string
	return string.format("%.0f%%", 100 * n / math.max(1, d))
end
local function f2(x: number?): string
	return if x == nil then "-" else string.format("%.2f", x)
end
local function f0(x: number?): string
	return if x == nil then "-" else string.format("%.0f", x)
end

local function randomAmendments(seed)
	local r = Rng.new(seed + 991)
	local out = {}
	for rule, variants in cfg.Amendments do
		out[rule] = variants[Rng.int(r, 1, #variants)]
	end
	return out
end

local function bankedAt(timeline, t)
	local b = 0
	for _, x in timeline do
		if x.t <= t then
			b = x.banked
		end
	end
	return b
end

local cells = {}
local amendedDeathRules = {}
local contract = { checks = 0, bad = {} }
local cueAudit = { checks = 0, bad = {} }
local function audit(out)
	contract.checks += out.contractChecks
	for _, b in out.contractBad do
		table.insert(contract.bad, b)
	end
	cueAudit.checks += out.cueChecks or 0
	for _, b in out.cueBad or {} do
		table.insert(cueAudit.bad, b)
	end
end
local t0 = os.clock()
for night = 1, 4 do
	for crew = 1, 4 do
		local c = {
			night = night,
			crew = crew,
			quota = Quota.scaled(cfg, cfg.Nights[night].quota, crew),
			seeds = nSeeds,
		}
		local F = { alive = 0, cleared = 0, met = {}, real = {}, fakes = {}, gap = {}, banked = {}, at70 = {} }
		local A = { alive = 0, cleared = 0 }
		local B = { anyDeath = 0, wiped = 0, firstDeath = {}, deaths = 0, cleared = 0 }
		local G = { alive = 0, real = {}, cleared = 0 }
		local followDeathRules = {}
		for k = 1, nSeeds do
			local seed = night * 100003 + crew * 7919 + k * 31
			-- follow, as printed
			local out =
				crewbot.runNight(core, cfg, simParams.story(cfg, Quota, night, crew, seed), { policy = "follow" })
			audit(out)
			if #out.deaths == 0 then
				F.alive += 1
			end
			for _, d in out.deaths do
				followDeathRules[d.rule] = (followDeathRules[d.rule] or 0) + 1
			end
			if out.cleared then
				F.cleared += 1
			end
			if out.metAt then
				table.insert(F.met, out.metAt / length)
			end
			table.insert(F.real, #out.realSpawns)
			table.insert(F.fakes, out.fakes)
			for j = 2, #out.realSpawns do
				table.insert(F.gap, out.realSpawns[j] - out.realSpawns[j - 1])
			end
			table.insert(F.banked, out.banked)
			table.insert(F.at70, bankedAt(out.timeline, 0.7 * length))
			-- follow, amended
			local am = crewbot.runNight(
				core,
				cfg,
				simParams.story(cfg, Quota, night, crew, seed, randomAmendments(seed)),
				{ policy = "follow" }
			)
			audit(am)
			if #am.deaths == 0 then
				A.alive += 1
			end
			for _, d in am.deaths do
				local key = d.rule .. " (" .. tostring(am.amendments[d.rule]) .. ")"
				amendedDeathRules[key] = (amendedDeathRules[key] or 0) + 1
			end
			if am.cleared then
				A.cleared += 1
			end
			-- blind
			local bl = crewbot.runNight(core, cfg, simParams.story(cfg, Quota, night, crew, seed), { policy = "blind" })
			audit(bl)
			if #bl.deaths > 0 then
				B.anyDeath += 1
				table.insert(B.firstDeath, bl.deaths[1].t / length)
			end
			if bl.wiped then
				B.wiped += 1
			end
			if bl.cleared then
				B.cleared += 1
			end
			B.deaths += #bl.deaths
			-- greedy
			local gr =
				crewbot.runNight(core, cfg, simParams.story(cfg, Quota, night, crew, seed), { policy = "greedy" })
			audit(gr)
			if #gr.deaths == 0 then
				G.alive += 1
			end
			if gr.cleared then
				G.cleared += 1
			end
			table.insert(G.real, #gr.realSpawns)
		end
		c.follow = {
			survival = F.alive / nSeeds,
			quotaRate = F.cleared / nSeeds,
			metMedian = median(F.met),
			metRate = #F.met / nSeeds,
			realMin = minOf(F.real),
			realMedian = median(F.real),
			realMax = maxOf(F.real),
			fakeMin = minOf(F.fakes),
			fakeMedian = median(F.fakes),
			fakeMax = maxOf(F.fakes),
			shortestGap = minOf(F.gap),
			bankedMedian = median(F.banked),
			deathRules = followDeathRules,
		}
		local at70 = median(F.at70) or 0
		c.quotaHint = at70 / cfg.Scaling.quota[crew]
		c.amended = { survival = A.alive / nSeeds, quotaRate = A.cleared / nSeeds }
		c.blind = {
			anyDeath = B.anyDeath / nSeeds,
			wiped = B.wiped / nSeeds,
			firstDeathMedian = median(B.firstDeath),
			deathsPerNight = B.deaths / nSeeds,
			quotaRate = B.cleared / nSeeds,
		}
		c.greedy = { survival = G.alive / nSeeds, realMedian = median(G.real), quotaRate = G.cleared / nSeeds }
		table.insert(cells, c)
		print(string.format("night %d crew %d done (%.0f s)", night, crew, os.clock() - t0))
	end
end
local elapsed = os.clock() - t0

local lines = {
	"# Rules scorecard" .. (if fast then " (fast)" else ""),
	"",
	string.format(
		"Story nights 1 to 4 played to dawn, Normal, %d seeds per cell, night %d s. Bots: tools/sim/crewbot.luau. Night 5 (the Finale) is in the full-run scorecard (run.md).",
		nSeeds,
		length
	),
	"",
	"## Rule-following bot (book as printed)",
	"",
	"| Night | Crew | Quota | Survival | Quota rate | Time to quota (median) | Real scares min/med/max | Fake-outs min/med/max | Shortest real gap (s) | Banked (median) |",
	"|---|---|---|---|---|---|---|---|---|---|",
}
for _, c in cells do
	local f = c.follow
	table.insert(
		lines,
		string.format(
			"| %d | %d | %d | %s | %s | %s | %s/%s/%s | %s/%s/%s | %s | %s |",
			c.night,
			c.crew,
			c.quota,
			pct(f.survival, 1),
			pct(f.quotaRate, 1),
			f2(f.metMedian),
			f0(f.realMin),
			f0(f.realMedian),
			f0(f.realMax),
			f0(f.fakeMin),
			f0(f.fakeMedian),
			f0(f.fakeMax),
			if f.shortestGap then string.format("%.1f", f.shortestGap) else "-",
			f0(f.bankedMedian)
		)
	)
end
table.insert(lines, "")
table.insert(lines, "## Rule-following bot on amended rules, rule-blind bot, greedy bot")
table.insert(lines, "")
table.insert(
	lines,
	"| Night | Crew | Amended: survival | Amended: quota | Blind: any death | Blind: crew lost | Blind: first death (median, of night) | Blind: deaths per night | Greedy: survival | Greedy: real scares (median) | Follow: real scares (median) |"
)
table.insert(lines, "|---|---|---|---|---|---|---|---|---|---|---|")
for _, c in cells do
	table.insert(
		lines,
		string.format(
			"| %d | %d | %s | %s | %s | %s | %s | %.2f | %s | %s | %s |",
			c.night,
			c.crew,
			pct(c.amended.survival, 1),
			pct(c.amended.quotaRate, 1),
			pct(c.blind.anyDeath, 1),
			pct(c.blind.wiped, 1),
			f2(c.blind.firstDeathMedian),
			c.blind.deathsPerNight,
			pct(c.greedy.survival, 1),
			f0(c.greedy.realMedian),
			f0(c.follow.realMedian)
		)
	)
end
table.insert(lines, "")
table.insert(lines, "## Quota hint")
table.insert(lines, "")
table.insert(
	lines,
	"Median points the rule-following bot has banked at 70% of the night, as a base (four-player) quota."
)
table.insert(lines, "")
table.insert(lines, "| Night | Crew 1 | Crew 2 | Crew 3 | Crew 4 | Config quota |")
table.insert(lines, "|---|---|---|---|---|---|")
for night = 1, 4 do
	local row = { tostring(night) }
	for _, c in cells do
		if c.night == night then
			table.insert(row, string.format("%.1f", c.quotaHint))
		end
	end
	table.insert(row, tostring(cfg.Nights[night].quota))
	table.insert(lines, "| " .. table.concat(row, " | ") .. " |")
end
table.insert(lines, "")
table.insert(lines, "Follow-bot deaths by rule (all cells):")
local byRule = {}
for _, c in cells do
	for rule, n in c.follow.deathRules do
		byRule[rule] = (byRule[rule] or 0) + n
	end
end
local any = false
for rule, n in byRule do
	any = true
	table.insert(lines, string.format("- %s: %d", rule, n))
end
if not any then
	table.insert(lines, "- none")
end
table.insert(lines, "")
table.insert(lines, "Follow-bot deaths on amended rules, by rule and amendment (all cells):")
local anyA = false
for key, n in amendedDeathRules do
	anyA = true
	table.insert(lines, string.format("- %s: %d", key, n))
end
if not anyA then
	table.insert(lines, "- none")
end
table.insert(lines, "")
table.insert(
	lines,
	string.format(
		"Rule contract over every simulated night (one cue, exactly one outcome, no fail before the warning time): %d checks, %d violations.",
		contract.checks,
		#contract.bad
	)
)
for j = 1, math.min(10, #contract.bad) do
	table.insert(lines, "- " .. contract.bad[j])
end
table.insert(
	lines,
	string.format(
		"Cue received (every player a rule took had received that rule's cue): %d deaths checked, %d violations.",
		cueAudit.checks,
		#cueAudit.bad
	)
)
for j = 1, math.min(10, #cueAudit.bad) do
	table.insert(lines, "- " .. cueAudit.bad[j])
end
table.insert(lines, "")
table.insert(lines, string.format("Simulated in %.1f s.", elapsed))
local md = table.concat(lines, "\n") .. "\n"

fs.writeDir("artifacts/score")
local base = if fast then "artifacts/score/rules-fast" else "artifacts/score/rules"
fs.writeFile(base .. ".md", md)
for _, c in cells do
	c.follow.deathRules = nil
end
fs.writeFile(base .. ".json", serde.encode("json", { fast = fast, seeds = nSeeds, cells = cells }, true))
print(md)
process.exit(0)
