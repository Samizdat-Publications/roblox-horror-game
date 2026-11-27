-- Core.Profile, Core.Leaderboard and Core.SaveLogic: the save schema, safe defaults,
-- migration, stats, the cosmetic unlock rules from docs/DESIGN.md, equipped validation,
-- the best-Endless-night board, and loading and saving through an in-memory store that
-- can be told to fail.
return function(t, Shared)
	local Profile = require(Shared.Core.Profile)
	local Leaderboard = require(Shared.Core.Leaderboard)
	local SaveLogic = require(Shared.Core.SaveLogic)
	local Config = require(Shared.Config)

	-- An in-memory store. `failNext[method] = n` makes the next n calls of that method error.
	local function mockStore(initial)
		local store = { data = initial or {}, failNext = {}, calls = { GetAsync = 0, SetAsync = 0, UpdateAsync = 0 } }
		local function maybeFail(method)
			store.calls[method] += 1
			local n = store.failNext[method] or 0
			if n > 0 then
				store.failNext[method] = n - 1
				error("mock store: " .. method .. " failed", 0)
			end
		end
		local function copy(v)
			if type(v) ~= "table" then
				return v
			end
			local out = {}
			for k, x in v do
				out[k] = copy(x)
			end
			return out
		end
		function store:GetAsync(key)
			maybeFail("GetAsync")
			return copy(self.data[key])
		end
		function store:SetAsync(key, value)
			maybeFail("SetAsync")
			self.data[key] = copy(value)
		end
		function store:UpdateAsync(key, transform)
			maybeFail("UpdateAsync")
			local new = transform(copy(self.data[key]))
			if new ~= nil then
				self.data[key] = copy(new)
			end
			return new
		end
		return store
	end

	local function sleeper()
		local slept = {}
		return slept, function(s)
			table.insert(slept, s)
		end
	end

	local function has(list, v)
		for _, x in list do
			if x == v then
				return true
			end
		end
		return false
	end

	t.test("defaults: version, zero stats, the starting cosmetics unlocked and equipped", function()
		local p = Profile.default(Config)
		t.eq(p.version, Config.SAVE_VERSION, "version")
		for k, v in p.stats do
			t.eq(v, 0, "stat " .. k)
		end
		t.eq(p.equipped.lantern, "Amber", "lantern")
		t.eq(p.equipped.paint, "BareWood", "paint")
		t.eq(p.equipped.hat, "None", "hat")
		t.ok(Profile.unlocked(Config, p, "lantern", "Amber"), "Amber unlocked")
		t.ok(not Profile.unlocked(Config, p, "lantern", "BoneWhite"), "Bone White locked")
		t.ok(not Profile.unlocked(Config, p, "hat", "BucketHat"), "Bucket Hat locked")
	end)

	t.test("every unlock rule names a real cosmetic and every cosmetic has a rule", function()
		for _, rule in Profile.UNLOCKS do
			t.ok(has(Config.Cosmetics[rule.slot], rule.id), "real: " .. rule.slot .. "." .. rule.id)
		end
		for slot, ids in Config.Cosmetics do
			for _, id in ids do
				local found = false
				for _, rule in Profile.UNLOCKS do
					if rule.slot == slot and rule.id == id then
						found = true
					end
				end
				t.ok(found, "rule for " .. slot .. "." .. id)
			end
		end
	end)

	t.test("Bucket Hat for clearing night 1; Bone White and Sou'wester for a run", function()
		local p = Profile.default(Config)
		local new = Profile.recordNight(Config, p, { cleared = true, mode = "Story", difficulty = "Normal", night = 1 })
		t.ok(has(new, "hat.BucketHat"), "bucket hat")
		t.eq(p.stats.nightsCleared, 1, "night counted")
		local failed =
			Profile.recordNight(Config, p, { cleared = false, mode = "Story", difficulty = "Normal", night = 2 })
		t.eq(#failed, 0, "nothing for a failed night")
		t.eq(p.stats.nightsCleared, 1, "failed night not counted")
		new = Profile.recordRun(Config, p, { cleared = true, mode = "Story", difficulty = "Normal", solo = false })
		t.ok(has(new, "lantern.BoneWhite") and has(new, "hat.Souwester"), "run unlocks")
		t.ok(not has(new, "paint.RobinEgg"), "not solo")
		t.eq(p.stats.runsCleared, 1, "run counted")
	end)

	t.test("Marsh Green only for clearing night 3 on Nightmare", function()
		local p = Profile.default(Config)
		Profile.recordNight(Config, p, { cleared = true, mode = "Story", difficulty = "Normal", night = 3 })
		t.ok(not Profile.unlocked(Config, p, "lantern", "MarshGreen"), "not on Normal")
		Profile.recordNight(Config, p, { cleared = false, mode = "Story", difficulty = "Nightmare", night = 3 })
		t.ok(not Profile.unlocked(Config, p, "lantern", "MarshGreen"), "not for a failed night")
		local new =
			Profile.recordNight(Config, p, { cleared = true, mode = "Story", difficulty = "Nightmare", night = 3 })
		t.ok(has(new, "lantern.MarshGreen"), "Nightmare night 3")
	end)

	t.test("Blue Hour for the fifth Endless night; best Endless night only goes up", function()
		local p = Profile.default(Config)
		for night = 6, 9 do
			Profile.recordNight(Config, p, { cleared = true, mode = "Endless", difficulty = "Normal", night = night })
		end
		t.eq(p.stats.bestEndlessNight, 9, "best 9")
		t.ok(not Profile.unlocked(Config, p, "lantern", "BlueHour"), "not yet")
		local new =
			Profile.recordNight(Config, p, { cleared = true, mode = "Endless", difficulty = "Normal", night = 10 })
		t.ok(has(new, "lantern.BlueHour"), "night 10 is the fifth Endless night")
		Profile.recordRun(
			Config,
			p,
			{ cleared = false, mode = "Endless", difficulty = "Normal", solo = false, bestNight = 7 }
		)
		t.eq(p.stats.bestEndlessNight, 10, "never lowered")
	end)

	t.test("Oxblood at 100 fish banked, Hull Black at 25 scares survived, Robin Egg for a solo run", function()
		local p = Profile.default(Config)
		for _ = 1, 9 do
			Profile.recordNight(Config, p, {
				cleared = false,
				mode = "Story",
				difficulty = "Normal",
				night = 1,
				fishBanked = 11,
				scaresSurvived = 2,
			})
		end
		t.eq(p.stats.fishBanked, 99, "99 fish")
		t.ok(not Profile.unlocked(Config, p, "paint", "Oxblood"), "not at 99")
		local new = Profile.recordNight(
			Config,
			p,
			{ cleared = false, mode = "Story", difficulty = "Normal", night = 1, fishBanked = 1, scaresSurvived = 7 }
		)
		t.ok(has(new, "paint.Oxblood"), "100 fish")
		t.ok(has(new, "paint.HullBlack"), "25 scares")
		new = Profile.recordRun(Config, p, { cleared = true, mode = "Story", difficulty = "Normal", solo = true })
		t.ok(has(new, "paint.RobinEgg"), "solo run")
		t.eq(p.stats.soloRunsCleared, 1, "solo counted")
	end)

	t.test("equip refuses locked or unknown items; validate repairs a bad equip", function()
		local p = Profile.default(Config)
		t.ok(not Profile.equip(Config, p, "lantern", "BoneWhite"), "locked")
		t.ok(not Profile.equip(Config, p, "lantern", "Gold"), "unknown")
		t.ok(not Profile.equip(Config, p, "cape", "Red"), "unknown slot")
		t.eq(p.equipped.lantern, "Amber", "unchanged")
		Profile.recordRun(Config, p, { cleared = true, mode = "Story", difficulty = "Normal", solo = false })
		t.ok(Profile.equip(Config, p, "lantern", "BoneWhite"), "unlocked")
		t.eq(p.equipped.lantern, "BoneWhite", "equipped")
		p.equipped.paint = "Oxblood"
		p.equipped.hat = 42 :: any
		Profile.validate(Config, p)
		t.eq(p.equipped.paint, "BareWood", "locked paint undone")
		t.eq(p.equipped.hat, "None", "garbage undone")
		t.eq(p.equipped.lantern, "BoneWhite", "valid kept")
	end)

	t.test("migrate: nothing stored, current, garbage, version 0, and a future version", function()
		local p, status = Profile.migrate(Config, nil)
		t.eq(status, "New", "new")
		t.eq(p.version, Config.SAVE_VERSION, "version")
		local cur = Profile.serialize(Profile.default(Config))
		local _, s2 = Profile.migrate(Config, cur)
		t.eq(s2, "Current", "current")
		local _, s3 = Profile.migrate(Config, "not a table")
		t.eq(s3, "Repaired", "garbage")
		local old = {
			nightsCleared = 6,
			runsCleared = 1,
			bestEndless = 8,
			fishBanked = 140,
			scaresSurvived = 30,
			cosmetics = { lantern = "BoneWhite", paint = "Oxblood", hat = "Souwester" },
		}
		local m, s4 = Profile.migrate(Config, old)
		t.eq(s4, "Migrated", "migrated")
		t.eq(m.version, Config.SAVE_VERSION, "new version")
		t.eq(m.stats.nightsCleared, 6, "nights")
		t.eq(m.stats.bestEndlessNight, 8, "best endless renamed")
		t.eq(m.stats.fishBanked, 140, "fish")
		t.ok(Profile.unlocked(Config, m, "paint", "Oxblood"), "unlocks rebuilt from stats")
		t.eq(m.equipped.lantern, "BoneWhite", "equipped kept when unlocked")
		t.eq(m.equipped.hat, "Souwester", "hat kept")
		local future = Profile.serialize(Profile.default(Config))
		future.version = Config.SAVE_VERSION + 3
		future.stats.runsCleared = 2
		local f, s5 = Profile.migrate(Config, future)
		t.eq(s5, "Future", "future")
		t.eq(f.version, Config.SAVE_VERSION + 3, "keeps its version")
		t.eq(f.stats.runsCleared, 2, "reads what it can")
	end)

	t.test("migrate repairs bad numbers and drops unknown unlocks", function()
		local raw = Profile.serialize(Profile.default(Config))
		raw.stats.fishBanked = -5
		raw.stats.scaresSurvived = 0 / 0
		raw.stats.runsCleared = 2.7
		raw.unlocked.lantern.Gold = true
		raw.unlocked.cape = { Red = true }
		raw.equipped.lantern = "BlueHour"
		local p, status = Profile.migrate(Config, raw)
		t.eq(status, "Repaired", "repaired")
		t.eq(p.stats.fishBanked, 0, "negative to 0")
		t.eq(p.stats.scaresSurvived, 0, "NaN to 0")
		t.eq(p.stats.runsCleared, 2, "floored")
		t.eq(p.unlocked.lantern.Gold, nil, "unknown unlock dropped")
		t.eq(p.unlocked.cape, nil, "unknown slot dropped")
		t.eq(p.equipped.lantern, "Amber", "locked equip undone")
	end)

	t.test("merge never loses progress", function()
		local a = Profile.default(Config)
		local b = Profile.default(Config)
		a.stats.fishBanked = 120
		b.stats.fishBanked = 40
		b.stats.scaresSurvived = 30
		b.flags.NightmareNight3 = true
		Profile.refresh(Config, a)
		Profile.refresh(Config, b)
		Profile.equip(Config, a, "paint", "Oxblood")
		local m = Profile.merge(Config, a, b)
		t.eq(m.stats.fishBanked, 120, "max fish")
		t.eq(m.stats.scaresSurvived, 30, "max scares")
		t.ok(m.flags.NightmareNight3, "flag kept")
		t.ok(Profile.unlocked(Config, m, "lantern", "MarshGreen"), "unlock from b")
		t.ok(Profile.unlocked(Config, m, "paint", "HullBlack"), "unlock from b's stats")
		t.eq(m.equipped.paint, "Oxblood", "a's equip")
	end)

	t.test("Leaderboard: best night first, earlier wins a tie, then user id; ranks share ties", function()
		local entries = {
			{ userId = 5, bestNight = 9, at = 300 },
			{ userId = 2, bestNight = 12, at = 900 },
			{ userId = 7, bestNight = 9, at = 100 },
			{ userId = 3, bestNight = 9, at = 100 },
			{ userId = 9, bestNight = 0, at = 50 },
			{ userId = 4, bestNight = 7, at = 10 },
		}
		local top = Leaderboard.top(entries, 10)
		t.eq(#top, 5, "zero nights left off")
		t.eq(top[1].userId, 2, "best night first")
		t.eq(top[2].userId, 3, "tie: same time, lower id")
		t.eq(top[3].userId, 7, "then the other")
		t.eq(top[2].rank, 2, "rank 2")
		t.eq(top[3].rank, 2, "shared rank")
		t.eq(top[4].userId, 5, "later time")
		t.eq(top[4].rank, 4, "competition ranking")
		t.eq(top[5].userId, 4, "last")
		t.eq(#Leaderboard.top(entries, 2), 2, "top N")
		t.eq(#Leaderboard.top(entries, 0), 0, "top 0")
		t.eq(entries[1].rank, nil, "input untouched")
	end)

	t.test("Leaderboard.submit keeps one best entry per player and trims", function()
		local board = {}
		t.ok(Leaderboard.submit(board, { userId = 1, bestNight = 8, at = 10 }, 3), "added")
		t.ok(not Leaderboard.submit(board, { userId = 1, bestNight = 7, at = 20 }, 3), "worse ignored")
		t.ok(not Leaderboard.submit(board, { userId = 1, bestNight = 8, at = 5 }, 3), "equal ignored")
		t.ok(Leaderboard.submit(board, { userId = 1, bestNight = 11, at = 30 }, 3), "better replaces")
		t.eq(#board, 1, "one entry")
		Leaderboard.submit(board, { userId = 2, bestNight = 9, at = 1 }, 3)
		Leaderboard.submit(board, { userId = 3, bestNight = 10, at = 1 }, 3)
		t.ok(not Leaderboard.submit(board, { userId = 4, bestNight = 6, at = 1 }, 3), "did not make it")
		t.eq(#board, 3, "trimmed")
		t.eq(board[1].userId, 1, "sorted")
		t.ok(not Leaderboard.submit(board, { userId = 5, bestNight = 0, at = 1 }, 3), "zero refused")
	end)

	t.test("Leaderboard encode sorts like compare and round-trips", function()
		local a = Leaderboard.encode(12, 1800000000)
		local b = Leaderboard.encode(12, 1700000000)
		local c = Leaderboard.encode(11, 1)
		t.ok(b > a, "earlier ranks higher on a tie")
		t.ok(a > c, "more nights ranks higher")
		local n, at = Leaderboard.decode(a)
		t.eq(n, 12, "night back")
		t.eq(at, 1800000000, "time back")
	end)

	t.test("SaveLogic.retry: backoff doubles, caps, and gives up", function()
		local slept, sleep = sleeper()
		local calls = 0
		local ok, v, attempts = SaveLogic.retry(function()
			calls += 1
			if calls < 3 then
				error("nope")
			end
			return "yes"
		end, { attempts = 5, baseDelay = 1, maxDelay = 8, sleep = sleep })
		t.ok(ok and v == "yes", "succeeds on the third try")
		t.eq(attempts, 3, "attempts")
		t.eq(table.concat(slept, ","), "1,2", "backoff 1, 2")
		slept, sleep = sleeper()
		local ok2, _, attempts2, err = SaveLogic.retry(function()
			error("down", 0)
		end, { attempts = 6, baseDelay = 1, maxDelay = 8, sleep = sleep })
		t.ok(not ok2, "gives up")
		t.eq(attempts2, 6, "all tries")
		t.eq(table.concat(slept, ","), "1,2,4,8,8", "capped at maxDelay, no sleep after the last")
		t.eq(err, "down", "last error")
	end)

	t.test("load: new player, stored profile, retries through failures, total outage is safe", function()
		local _, sleep = sleeper()
		local store = mockStore()
		local r = SaveLogic.load(Config, store, "u1", { sleep = sleep })
		t.eq(r.status, "New", "new")
		t.ok(r.canSave, "may save")
		local saved = Profile.default(Config)
		saved.stats.runsCleared = 3
		store.data.u2 = Profile.serialize(saved)
		store.failNext.GetAsync = 2
		local r2 = SaveLogic.load(Config, store, "u2", { sleep = sleep })
		t.eq(r2.status, "Current", "loaded")
		t.eq(r2.attempts, 3, "after two failures")
		t.eq(r2.profile.stats.runsCleared, 3, "data")
		store.failNext.GetAsync = 99
		local r3 = SaveLogic.load(Config, store, "u2", { sleep = sleep })
		t.eq(r3.status, "LoadFailed", "outage")
		t.ok(not r3.canSave, "never save defaults over a real profile")
		t.eq(r3.profile.stats.runsCleared, 0, "safe defaults to play with")
		local s = SaveLogic.save(Config, store, "u2", r3.profile, { sleep = sleep }, r3.canSave)
		t.eq(s.status, "NotAllowed", "save refused")
		t.eq(store.data.u2.stats.runsCleared, 3, "stored data untouched")
	end)

	t.test("save: merges with what is stored, retries, and never writes over a future save", function()
		local _, sleep = sleeper()
		local store = mockStore()
		local p = Profile.default(Config)
		Profile.recordNight(
			Config,
			p,
			{ cleared = true, mode = "Story", difficulty = "Normal", night = 1, fishBanked = 5 }
		)
		local s = SaveLogic.save(Config, store, "k", p, { sleep = sleep })
		t.ok(s.ok and s.status == "Saved", "saved")
		t.eq(store.data.k.stats.fishBanked, 5, "stored")
		-- Another server saved more meanwhile; this stale session must not lower it.
		store.data.k.stats.fishBanked = 50
		store.failNext.UpdateAsync = 1
		local stale = Profile.default(Config)
		stale.stats.fishBanked = 7
		local s2 = SaveLogic.save(Config, store, "k", stale, { sleep = sleep })
		t.ok(s2.ok, "saved after a retry")
		t.eq(s2.attempts, 2, "two tries")
		t.eq(store.data.k.stats.fishBanked, 50, "merge kept the larger")
		store.failNext.UpdateAsync = 99
		local s3 = SaveLogic.save(Config, store, "k", p, { sleep = sleep })
		t.eq(s3.status, "Failed", "outage")
		t.eq(s3.attempts, Config.Save.attempts, "cfg.Save.attempts tries")
		store.failNext.UpdateAsync = 0
		local future = Profile.serialize(Profile.default(Config))
		future.version = Config.SAVE_VERSION + 1
		store.data.f = future
		local s4 = SaveLogic.save(Config, store, "f", p, { sleep = sleep })
		t.eq(s4.status, "Future", "refused")
		t.eq(store.data.f.version, Config.SAVE_VERSION + 1, "future save untouched")
		local loaded = SaveLogic.load(Config, store, "f", { sleep = sleep })
		t.eq(loaded.status, "Future", "loads as future")
		t.ok(not loaded.canSave, "and will not save")
	end)

	t.test("submitBest only ever raises a player's board value", function()
		local _, sleep = sleeper()
		local store = mockStore()
		t.eq(SaveLogic.submitBest(store, "u", 8, 100, { sleep = sleep }).status, "Saved", "first")
		t.eq(SaveLogic.submitBest(store, "u", 7, 200, { sleep = sleep }).status, "Unchanged", "worse")
		t.eq(SaveLogic.submitBest(store, "u", 8, 50, { sleep = sleep }).status, "Unchanged", "equal")
		store.failNext.UpdateAsync = 2
		local r = SaveLogic.submitBest(store, "u", 9, 300, { sleep = sleep })
		t.eq(r.status, "Saved", "better, after retries")
		t.eq(r.attempts, 3, "tries")
		local n = Leaderboard.decode(store.data.u)
		t.eq(n, 9, "stored best")
		t.eq(SaveLogic.submitBest(store, "u", 0, 1, { sleep = sleep }).status, "Unchanged", "zero")
	end)
end
