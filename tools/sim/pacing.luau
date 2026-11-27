--[[
Pacing simulation: the rule-following crew bot plays Story nights 1 to 5 for crew sizes
1 to 4 over many seeds, and the scorecard says how early it reaches the quota.

    lune run tools/sim/pacing.luau [--fast] [--seeds N]

Target (docs/CLOUD-BRIEF.md, Core M2): the bot reaches quota at 60 to 80 percent of the
night (median), and reaches it at all on nearly every seed. Night 5 (the Finale, Core M5)
needs 85% (80% fast): its whole-night success is the full-run sim's job.
Full run: 200 seeds per cell, strict band 0.60 to 0.80, quota reached in at least 95%.
--fast (the gate): 24 seeds per cell, loose band 0.55 to 0.85 (small samples are noisy),
quota reached in at least 90%.

The rule-following bot answers every rule (Core M3 and M4), so scares cost it time.
Each night stops as soon as the quota is met (nothing after that changes time-to-quota;
the full nights to dawn are in tools/sim/rules.luau). Writes artifacts/score/pacing.md and
artifacts/score/pacing.json (full) or pacing-fast.* (fast). Exit 1 on a miss.
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
		print("pacing sim: unknown argument " .. arg)
		process.exit(2)
	end
	i += 1
end
local nSeeds = seeds or (if fast then 24 else 200)
local bandLo, bandHi = if fast then 0.55 else 0.6, if fast then 0.85 else 0.8
local minReached = if fast then 0.9 else 0.95
local finaleMinReached = if fast then 0.8 else 0.85

local Shared, req = loader.load()
local cfg = req(Shared.Config)
local Quota = req(Shared.Core.Quota)
local core = simParams.core(Shared, req)

local function storyParams(night: number, crew: number, seed: number)
	return simParams.story(cfg, Quota, night, crew, seed)
end

local function median(xs: { number }): number?
	if #xs == 0 then
		return nil
	end
	table.sort(xs)
	local n = #xs
	if n % 2 == 1 then
		return xs[(n + 1) / 2]
	end
	return (xs[n / 2] + xs[n / 2 + 1]) / 2
end

local function pct(xs: { number }, p: number): number?
	if #xs == 0 then
		return nil
	end
	table.sort(xs)
	return xs[math.clamp(math.floor(p * (#xs - 1) + 1.5), 1, #xs)]
end

local cells = {}
local misses = {}
local length = cfg.Night.realSeconds
local t0 = os.clock()
for night = 1, 5 do
	for crew = 1, 4 do
		local fracs = {}
		local reached = 0
		local trips, wrongBack = 0, 0
		for k = 1, nSeeds do
			local seed = night * 100003 + crew * 7919 + k * 31
			local out = crewbot.runNight(core, cfg, storyParams(night, crew, seed), { stopAtQuota = true })
			if out.metAt ~= nil then
				reached += 1
				table.insert(fracs, out.metAt / length)
			end
			trips += out.trips
			wrongBack += out.thrownBack
		end
		local cell = {
			night = night,
			crew = crew,
			quota = Quota.scaled(cfg, cfg.Nights[night].quota, crew),
			seeds = nSeeds,
			reached = reached / nSeeds,
			median = median(table.clone(fracs)),
			p10 = pct(table.clone(fracs), 0.1),
			p90 = pct(table.clone(fracs), 0.9),
			trips = trips / nSeeds,
			thrownBack = wrongBack / nSeeds,
		}
		-- Night 5 is the Finale night: the crew leaves the Shallows for the steeple before 3 AM
		-- and a night it does not finish there (no Steeple Cat, or late) never banks its last
		-- hold. Its success is scored by the full-run sim (tools/sim/run.luau); here it only
		-- needs the quota to land in the band on finaleMinReached of seeds.
		local need = if cfg.Nights[night].newRules[1] == "Finale" then finaleMinReached else minReached
		cell.minReached = need
		local ok = cell.reached >= need and cell.median ~= nil and cell.median >= bandLo and cell.median <= bandHi
		cell.ok = ok
		if not ok then
			table.insert(misses, string.format("night %d crew %d", night, crew))
		end
		table.insert(cells, cell)
	end
end
local elapsed = os.clock() - t0

local function f2(x: number?): string
	return if x == nil then "-" else string.format("%.2f", x)
end

local lines = {
	"# Pacing scorecard" .. (if fast then " (fast)" else ""),
	"",
	string.format(
		"Rule-following crew bot, Story nights 1 to 5, Normal, %d seeds per cell, night %d s. Target: quota reached in at least %d%% of seeds (%d%% on the Finale night, scored by tools/sim/run.luau), median time to quota between %.2f and %.2f of the night.",
		nSeeds,
		length,
		math.floor(minReached * 100 + 0.5),
		math.floor(finaleMinReached * 100 + 0.5),
		bandLo,
		bandHi
	),
	"",
	"| Night | Crew | Quota | Reached | Median | P10 | P90 | Trips | Thrown back | OK |",
	"|---|---|---|---|---|---|---|---|---|---|",
}
for _, c in cells do
	table.insert(
		lines,
		string.format(
			"| %d | %d | %d | %.0f%% | %s | %s | %s | %.1f | %.1f | %s |",
			c.night,
			c.crew,
			c.quota,
			c.reached * 100,
			f2(c.median),
			f2(c.p10),
			f2(c.p90),
			c.trips,
			c.thrownBack,
			if c.ok then "yes" else "MISS"
		)
	)
end
table.insert(lines, "")
table.insert(lines, string.format("Simulated in %.1f s.", elapsed))
local md = table.concat(lines, "\n") .. "\n"

fs.writeDir("artifacts/score")
local base = if fast then "artifacts/score/pacing-fast" else "artifacts/score/pacing"
fs.writeFile(base .. ".md", md)
fs.writeFile(base .. ".json", serde.encode("json", { fast = fast, seeds = nSeeds, cells = cells }, true))
print(md)
if #misses > 0 then
	print("pacing sim: MISS in " .. table.concat(misses, ", "))
	process.exit(1)
end
print("pacing sim: all cells on target")
process.exit(0)
