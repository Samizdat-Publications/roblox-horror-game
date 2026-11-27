-- Core.Run: the night table, rules accumulating, crew and difficulty scaling, retries,
-- RunCleared after night 5, the cut supply pick, and Endless night generation.
return function(t, Shared)
	local Run = require(Shared.Core.Run)
	local Quota = require(Shared.Core.Quota)
	local Config = require(Shared.Config)

	local function ids(n)
		local out = {}
		for i = 1, n do
			table.insert(out, i)
		end
		return out
	end

	local function result(cleared, over)
		local r = {
			cleared = cleared,
			banked = 10,
			quota = 10,
			caught = 8,
			scaresSurvived = 2,
			deaths = {},
			keptWrong = 0,
		}
		for k, v in over or {} do
			r[k] = v
		end
		return r
	end

	local function has(list, v)
		for _, x in list do
			if x == v then
				return true
			end
		end
		return false
	end

	t.test("Story night table: rules accumulate and new rules come from Config.Nights", function()
		local run = Run.new(Config, { seed = 11, playerIds = ids(4) })
		local seen = {}
		for night = 1, 5 do
			local p = Run.nightParams(run)
			t.eq(p.night, night, "night")
			t.eq(p.mode, "Story", "mode")
			for _, r in Config.Nights[night].newRules do
				table.insert(seen, r)
				t.ok(has(p.newRules, r), "new rule " .. r)
			end
			t.eq(#p.rules, #seen, "rules so far on night " .. night)
			for _, r in seen do
				t.ok(has(p.rules, r), "keeps " .. r)
			end
			t.eq(p.quota, Quota.scaled(Config, Config.Nights[night].quota, 4), "quota")
			t.eq(p.maxConcurrent, Config.Nights[night].maxConcurrent, "concurrent")
			t.eq(Run.finishNight(run, result(true)), if night < 5 then "NextNight" else "RunCleared", "outcome")
		end
		t.ok(run.cleared and run.over, "cleared")
		t.eq(run.nightsCleared, 5, "five nights")
		t.ok(has(Run.nightParams(run).rules, "Finale") or true, "params still readable")
	end)

	t.test("crew size scales quota, warnings and the real budget; solo warns longest", function()
		local solo = Run.nightParams(Run.new(Config, { seed = 3, playerIds = ids(1) }))
		local four = Run.nightParams(Run.new(Config, { seed = 3, playerIds = ids(4) }))
		t.ok(solo.quota < four.quota, "solo quota smaller")
		t.ok(solo.warningScale > four.warningScale, "solo warns longer")
		t.eq(solo.warningScale, Config.Scaling.warning[1], "solo scale")
		t.eq(four.real, math.max(1, math.floor(Config.Nights[1].real * Config.Scaling.budget[4] + 0.5)), "budget")
		t.ok(solo.real >= 1, "never below one")
	end)

	t.test("Nightmare: shorter warnings, more real scares, shorter quiet gaps", function()
		local n = Run.nightParams(Run.new(Config, { seed = 5, playerIds = ids(2), difficulty = "Normal" }))
		local m = Run.nightParams(Run.new(Config, { seed = 5, playerIds = ids(2), difficulty = "Nightmare" }))
		t.eq(m.difficulty, "Nightmare", "difficulty")
		t.ok(m.warningScale < n.warningScale, "warnings")
		local n4 = Run.nightParams(Run.new(Config, { seed = 5, playerIds = ids(4), difficulty = "Normal" }))
		local m4 = Run.nightParams(Run.new(Config, { seed = 5, playerIds = ids(4), difficulty = "Nightmare" }))
		t.ok(m4.real > n4.real, "budget")
		t.ok(m.real >= n.real, "never fewer")
		t.ok(m.quietGap < n.quietGap, "quiet gap")
		t.ok(
			math.abs(m.warningScale - Config.Scaling.warning[2] * Config.Difficulty.Nightmare.warning) < 1e-9,
			"crew x difficulty"
		)
	end)

	t.test("a failed night is retried with a fresh seed and the same page, until retries run out", function()
		local run = Run.new(Config, { seed = 99, playerIds = ids(2), difficulty = "Normal" })
		Run.finishNight(run, result(true))
		Run.finishNight(run, result(true))
		Run.finishNight(run, result(true))
		Run.finishNight(run, result(true))
		local first = Run.nightParams(run)
		t.eq(first.night, 5, "night 5")
		local retries = Config.Difficulty.Normal.retries
		for k = 1, retries do
			t.eq(Run.finishNight(run, result(false)), "RetryNight", "retry " .. k)
			local again = Run.nightParams(run)
			t.eq(again.night, 5, "same night")
			t.ok(again.seed ~= first.seed, "fresh seed")
			t.eq(next(again.amendments), next(first.amendments), "same page")
			t.eq(run.attempt, k + 1, "attempt")
		end
		t.eq(Run.finishNight(run, result(false)), "RunOver", "out of retries")
		t.ok(run.over and not run.cleared, "over")
	end)

	t.test("no retry limit when retries is nil", function()
		local cfg = table.clone(Config)
		cfg.Difficulty = table.clone(Config.Difficulty)
		cfg.Difficulty.Normal = table.clone(Config.Difficulty.Normal)
		cfg.Difficulty.Normal.retries = nil
		local run = Run.new(cfg, { seed = 1, playerIds = ids(1) })
		for _ = 1, 20 do
			t.eq(Run.finishNight(run, result(false)), "RetryNight", "retry")
		end
	end)

	t.test("Normal first run: by the book until night 5, then exactly one amendment", function()
		for seed = 1, 60 do
			local run = Run.new(Config, { seed = seed, playerIds = ids(3) })
			for night = 1, 5 do
				local p = Run.nightParams(run)
				local n = 0
				for _ in p.amendments do
					n += 1
				end
				t.eq(n, if night == 5 then 1 else 0, "amendments on night " .. night)
				Run.finishNight(run, result(true))
			end
		end
	end)

	t.test("the run is seeded: same seed, same nights", function()
		local a = Run.new(Config, { seed = 2024, playerIds = ids(2), difficulty = "Nightmare" })
		local b = Run.new(Config, { seed = 2024, playerIds = ids(2), difficulty = "Nightmare" })
		for _ = 1, 5 do
			local pa, pb = Run.nightParams(a), Run.nightParams(b)
			t.eq(pa.seed, pb.seed, "seed")
			for k, v in pa.amendments do
				t.eq(pb.amendments[k], v, "amendment " .. k)
			end
			Run.finishNight(a, result(true))
			Run.finishNight(b, result(true))
		end
	end)

	t.test("the supply pick is cut", function()
		local run = Run.new(Config, { seed = 1, playerIds = ids(2) })
		t.eq(#Run.supplyChoices(run), 0, "no choices")
		Run.chooseSupply(run, "OilCan")
		t.eq(#Run.nightParams(run).supplies, 0, "no supplies")
	end)

	t.test("crew changes between nights rescale the next night", function()
		local run = Run.new(Config, { seed = 8, playerIds = ids(4) })
		Run.finishNight(run, result(true))
		Run.setPlayers(run, { 7 })
		local p = Run.nightParams(run)
		t.eq(#p.playerIds, 1, "one player")
		t.eq(p.quota, Quota.scaled(Config, Config.Nights[2].quota, 1), "solo quota")
	end)

	t.test("run totals and the solo-run flag for the profile", function()
		local run = Run.new(Config, { seed = 4, playerIds = ids(1) })
		for _ = 1, 5 do
			Run.finishNight(run, result(true, { banked = 9, bankedFish = 7, scaresSurvived = 3 }))
		end
		t.eq(run.fishBanked, 35, "banked")
		t.eq(run.scaresSurvived, 15, "scares")
		t.ok(run.soloRun, "solo")
		local duo = Run.new(Config, { seed = 4, playerIds = ids(1) })
		Run.finishNight(duo, result(true))
		Run.setPlayers(duo, ids(2))
		Run.finishNight(duo, result(true))
		t.ok(not duo.soloRun, "not solo once someone joins")
	end)

	t.test("Endless: starts at night 6, random rule mixes, growth with caps, one life", function()
		local mixes = {}
		local run = Run.new(Config, { seed = 77, playerIds = ids(4), mode = "Endless" })
		t.eq(run.night, 6, "night 6")
		local prev = nil
		for k = 1, 30 do
			local p = Run.nightParams(run)
			t.eq(p.mode, "Endless", "mode")
			t.eq(p.night, 5 + k, "night")
			t.eq(#p.newRules, 0, "no teaching")
			t.ok(not has(p.rules, "Finale"), "no finale")
			local director = 0
			for _, r in p.rules do
				if r ~= "WrongCatch" then
					director += 1
				end
			end
			t.ok(director >= Config.Endless.rulesMin and director <= Config.Endless.rulesMax, "mix size")
			mixes[table.concat(p.rules, ",")] = true
			local base = math.min(
				Config.Endless.realCap,
				math.floor(Config.Endless.realBase + Config.Endless.realPerNight * (k - 1))
			)
			t.eq(p.real, math.max(1, math.floor(base * Config.Scaling.budget[4] + 0.5)), "real budget")
			t.ok(p.quietGap >= Config.Endless.quietGapFloor - 1e-9, "quiet floor")
			if prev then
				t.ok(p.quota >= prev.quota, "quota never falls")
			end
			prev = p
			Run.finishNight(run, result(true))
		end
		local kinds = 0
		for _ in mixes do
			kinds += 1
		end
		t.ok(kinds >= 4, "mixes vary: " .. kinds)
		t.eq(run.bestNight, 35, "best night")
		t.eq(Run.finishNight(run, result(false)), "RunOver", "a failed Endless night ends it")
		t.eq(run.bestNight, 35, "best night kept")
	end)

	t.test("Endless amendments come from the seed, any rule any night", function()
		local amended = 0
		for seed = 1, 40 do
			local run = Run.new(Config, { seed = seed, playerIds = ids(2), mode = "Endless" })
			local p = Run.nightParams(run)
			for rule, variant in p.amendments do
				amended += 1
				t.ok(has(p.rules, rule), "only rules in tonight's mix")
				t.ok(variant ~= Config.Amendments[rule][1], "never the printed variant")
			end
		end
		t.ok(amended > 10, "amendments happen: " .. amended)
	end)
end
