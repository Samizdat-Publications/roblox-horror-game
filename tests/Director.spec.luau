-- Core.Director: property tests of every invariant in docs/ARCHITECTURE.md (Director)
-- over 500 seeds for each Story night 1 to 5, against a randomized world: the boat
-- comes and goes from the dock light, the Watcher's shore comes and goes, rules last a
-- random time, and on a third of the seeds the crew is loud (attention high for long
-- stretches, which shortens calm phases, earns the bonus scare and allows overlaps).
return function(t, Shared)
	local Director = require(Shared.Core.Director)
	local Rng = require(Shared.Core.Rng)
	local Config = require(Shared.Config)
	local N, D = Config.Night, Config.Director

	local SEEDS = 500
	local DT = 0.5

	local function has(list, v)
		for _, x in list do
			if x == v then
				return true
			end
		end
		return false
	end

	local function storyParams(night, crew, seed)
		local rules, newRules = {}, {}
		for n = 1, night do
			for _, r in Config.Nights[n].newRules do
				table.insert(rules, r)
				if n == night then
					table.insert(newRules, r)
				end
			end
		end
		local nn = Config.Nights[night]
		local ids = {}
		for i = 1, crew do
			table.insert(ids, i)
		end
		return {
			seed = seed,
			night = night,
			mode = "Story",
			difficulty = "Normal",
			playerIds = ids,
			rules = rules,
			newRules = newRules,
			amendments = {},
			supplies = {},
			real = math.max(1, math.floor(nn.real * Config.Scaling.budget[crew] + 0.5)),
			fake = nn.fake,
			quietGap = nn.quietGap,
			quota = 10,
			maxConcurrent = nn.maxConcurrent,
			warningScale = Config.Scaling.warning[crew],
		}
	end

	-- One randomized night. Returns the list of violations and the number of checks made.
	local function runNight(night, k, dt)
		local seed = night * 7907 + k * 104729
		local w = Rng.new(seed + 17) -- the world's own stream
		local crew = Rng.int(w, 1, 4)
		local params = storyParams(night, crew, seed)
		local d = Director.new(Config, Rng.fork(Rng.new(seed), "director"), params)
		local loud = Rng.next(w) < 0.33
		local length = N.realSeconds
		local bandStart, bandEnd = N.teachFrom * length, N.teachTo * length
		local directorRules = {}
		for _, r in params.rules do
			if has(Director.RULES, r) then
				table.insert(directorRules, r)
			end
		end
		local alive = {}
		for _, id in params.playerIds do
			table.insert(alive, id)
		end

		local bad, checks = {}, 0
		local function check(ok, msg)
			checks += 1
			if not ok then
				table.insert(bad, string.format("night %d seed %d: %s", night, k, msg))
			end
		end

		local active = {} -- rule -> resolve time
		local activeN = 0
		local spawns, fakes, resolutions = {}, {}, {}
		local safeUntil = Rng.range(w, 3, 15) -- leaving the dock at the start
		local nextSafe = safeUntil + Rng.range(w, 60, 150)
		local shoreAwayUntil, nextShoreAway = 0, Rng.range(w, 30, 120)
		local attention = 0

		local time = 0
		while time < length do
			time = math.min(length, time + dt)
			-- The world.
			if time >= nextSafe then
				safeUntil = time + Rng.range(w, 8, 22)
				nextSafe = safeUntil + Rng.range(w, 60, 150)
			end
			local safe = time < safeUntil
			if time >= nextShoreAway then
				shoreAwayUntil = time + Rng.range(w, 5, 20)
				nextShoreAway = shoreAwayUntil + Rng.range(w, 30, 120)
			end
			local target = if loud then 0.9 else 0.15
			attention = math.clamp(attention + (target - attention) * 0.05 * dt + Rng.range(w, -0.02, 0.02), 0, 1)
			if safe then
				attention = math.max(0, attention - 0.05 * dt)
			end

			-- Rules resolve first (Night steps the rules before the director).
			for _, rule in directorRules do
				if active[rule] ~= nil and time >= active[rule] then
					active[rule] = nil
					activeN -= 1
					Director.resolved(d, rule, Rng.next(w) < 0.7, time)
					table.insert(resolutions, time)
				end
			end

			local eligible = {}
			for _, rule in directorRules do
				if active[rule] == nil and not (rule == "Watcher" and time < shoreAwayUntil) then
					table.insert(eligible, rule)
				end
			end
			local ctx = {
				attention = attention,
				activeReal = activeN,
				safe = safe,
				timeLeft = length - time,
				elapsed = time,
				eligible = eligible,
				aliveIds = alive,
			}
			for _, dec in Director.step(d, dt, ctx) do
				if dec.kind == "Spawn" then
					-- The invariants a spawn must meet, from the world's side.
					check(time >= N.openingGrace, "spawn in the opening grace at " .. time)
					check(not safe, "spawn while safe at " .. time)
					for _, r in resolutions do
						check(
							time >= r + params.quietGap - 1e-9,
							string.format("spawn at %.1f inside the quiet gap after %.1f", time, r)
						)
					end
					check(activeN < params.maxConcurrent, "over maxConcurrent at " .. time)
					check(has(eligible, dec.rule), "spawned an ineligible rule " .. tostring(dec.rule))
					if dec.only ~= nil then
						check(length - time >= D.soloCueMinSeconds, "solo cue too late at " .. time)
						check(has(alive, dec.only), "solo cue to a stranger")
					end
					table.insert(spawns, { t = time, rule = dec.rule, teaching = dec.teaching, only = dec.only })
					-- Realistic rule lengths: a Knocking answered fast, a Watcher held off, a slow Neighbor.
					active[dec.rule] = time + Rng.range(w, 6, 45)
					activeN += 1
				elseif dec.kind == "Fakeout" then
					check(not safe, "fake-out in the dock light")
					check(has(Config.Fakeouts, dec.id), "unknown fake-out " .. tostring(dec.id))
					table.insert(fakes, time)
				elseif dec.kind == "Chorus" then
					check(dec.band >= 1 and dec.band <= 3, "director chose silence")
				end
			end
			check(activeN <= params.maxConcurrent, "active over maxConcurrent")
		end

		-- Budgets.
		local bonus = 0
		for _, e in Director.log(d) do
			if e.kind == "Bonus" then
				bonus += 1
			end
		end
		check(bonus <= 1, "bonus scare more than once")
		local teach = 0
		for _, r in params.newRules do
			if has(Director.RULES, r) then
				teach += 1
			end
		end
		check(#spawns <= math.max(params.real, teach) + bonus, string.format("real budget: %d spawns", #spawns))
		check(#fakes <= params.fake, string.format("fake budget: %d fakes of %d", #fakes, params.fake))
		-- Teaching: every new director rule, once, first, flagged, inside the band.
		for _, r in params.newRules do
			if has(Director.RULES, r) then
				local first = nil
				for _, sp in spawns do
					if sp.rule == r then
						first = sp
						break
					end
				end
				check(first ~= nil, "new rule " .. r .. " never spawned")
				if first then
					check(first.teaching == true, "first " .. r .. " not teaching")
					check(first.t >= bandStart and first.t <= bandEnd, string.format("teaching %s at %.1f", r, first.t))
				end
			end
		end
		for _, sp in spawns do
			if sp.teaching then
				check(has(params.newRules, sp.rule), "teaching flag on an old rule")
			end
		end
		-- No fake-out near a real cue.
		for _, f in fakes do
			for _, sp in spawns do
				check(
					math.abs(f - sp.t) >= D.fakeClear - 1e-9,
					string.format("fake at %.1f near real at %.1f", f, sp.t)
				)
			end
		end
		-- The first Watcher of the night goes to one player.
		for _, sp in spawns do
			if sp.rule == "Watcher" then
				check(sp.only ~= nil, "first Watcher not solo")
				break
			end
		end
		return bad, checks, #spawns, #fakes
	end

	local summary = {}

	t.test("every invariant holds over 500 seeds per night", function()
		local violations, checks, nights = {}, 0, 0
		local spawns, fakes = 0, 0
		for night = 1, 5 do
			for k = 1, SEEDS do
				local bad, n, sp, fk = runNight(night, k, DT)
				nights += 1
				checks += n
				spawns += sp
				fakes += fk
				for _, b in bad do
					table.insert(violations, b)
				end
			end
		end
		summary.line = string.format(
			"Director property: %d seeds x 5 nights = %d nights, %d checks, %d real spawns, %d fake-outs, %d violations",
			SEEDS,
			nights,
			checks,
			spawns,
			fakes,
			#violations
		)
		print("    " .. summary.line)
		for i = 1, math.min(8, #violations) do
			print("      " .. violations[i])
		end
		t.eq(#violations, 0, "violations")
	end)

	t.test("the invariants also hold at the server tick (dt 0.1)", function()
		local violations = 0
		for night = 1, 5 do
			for k = 1, 30 do
				local bad = runNight(night, 10000 + k, N.tick)
				violations += #bad
			end
		end
		t.eq(violations, 0, "violations at dt 0.1")
	end)

	t.test("same seed, same night", function()
		local function play()
			local p = storyParams(4, 2, 99)
			local d = Director.new(Config, Rng.new(99), p)
			local log = {}
			for i = 1, 1080 do
				local ctx = {
					attention = 0.2,
					activeReal = 0,
					safe = false,
					timeLeft = 540 - i * 0.5,
					elapsed = i * 0.5,
					eligible = { "Hum", "Knocking", "Watcher" },
					aliveIds = { 1, 2 },
				}
				for _, dec in Director.step(d, 0.5, ctx) do
					table.insert(log, dec.kind .. tostring(dec.rule or dec.id or dec.band))
					if dec.kind == "Spawn" then
						Director.resolved(d, dec.rule, true, i * 0.5)
					end
				end
			end
			return table.concat(log, ",")
		end
		t.eq(play(), play(), "replay")
	end)

	t.test("the chorus thins in the build before a scare and is full in the dock light", function()
		local p = storyParams(1, 2, 5)
		local d = Director.new(Config, Rng.new(5), p)
		local minBand, sawSpawn = 3, false
		for i = 1, 600 do
			local time = i * 0.5
			local ctx = {
				attention = 0,
				activeReal = 0,
				safe = false,
				timeLeft = 540 - time,
				elapsed = time,
				eligible = { "Hum" },
				aliveIds = { 1, 2 },
			}
			for _, dec in Director.step(d, 0.5, ctx) do
				if dec.kind == "Chorus" then
					minBand = math.min(minBand, dec.band)
				elseif dec.kind == "Spawn" then
					sawSpawn = true
				end
			end
			if sawSpawn then
				break
			end
		end
		t.ok(sawSpawn, "the teaching Hum came")
		t.eq(minBand, 1, "sparse before the scare")
		local bands = {}
		for _, dec in
			Director.step(d, 0.5, {
				attention = 0,
				activeReal = 0,
				safe = true,
				timeLeft = 200,
				elapsed = 301,
				eligible = {},
				aliveIds = { 1 },
			})
		do
			if dec.kind == "Chorus" then
				table.insert(bands, dec.band)
			end
		end
		t.eq(bands[#bands], 3, "full in the light")
	end)

	t.test("a forced rule (debug) counts as active and its quiet gap follows", function()
		local p = storyParams(3, 2, 7)
		local d = Director.new(Config, Rng.new(7), p)
		d.now = 200
		Director.noteSpawn(d, "Neighbor")
		t.ok(Director.isActive(d, "Neighbor"), "active")
		Director.resolved(d, "Neighbor", true, 210)
		local spawned = nil
		for i = 1, 200 do
			local time = 210 + i * 0.5
			for _, dec in
				Director.step(d, 0.5, {
					attention = 0,
					activeReal = 0,
					safe = false,
					timeLeft = 540 - time,
					elapsed = time,
					eligible = { "Hum" },
					aliveIds = { 1, 2 },
				})
			do
				if dec.kind == "Spawn" and spawned == nil then
					spawned = time
				end
			end
		end
		t.ok(spawned == nil or spawned >= 210 + p.quietGap, "quiet gap after the forced rule")
	end)
end
