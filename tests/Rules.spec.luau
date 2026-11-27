-- The rule modules (Core.entities.*) driven directly with hand-made observations: for each
-- rule and each amendment variant, the cue, the correct counter and the fail, plus the
-- fairness rule (a fail never lands before the cue has been out for the warning time,
-- longer for a solo cue) and the event contract (one EntityCue, EntityStage changes,
-- exactly one of EntityPass or EntityFail).
return function(t, Shared)
	local Config = require(Shared.Config)
	local Rng = require(Shared.Core.Rng)
	local LakeMap = require(Shared.Core.LakeMap)
	local Hum = require(Shared.Core.entities.Hum)
	local Neighbor = require(Shared.Core.entities.Neighbor)
	local Knocking = require(Shared.Core.entities.Knocking)
	local Watcher = require(Shared.Core.entities.Watcher)
	local WrongCatch = require(Shared.Core.entities.WrongCatch)
	local EntityBase = require(Shared.Core.EntityBase)
	local L = Config.Lake

	local OUT = { x = 0, z = L.dockEnd.z + 150 }
	local CENTER = { x = 0, z = 0 }

	local function player(id, o)
		o = o or {}
		return {
			id = id,
			seated = true,
			helm = id == 1,
			inWater = false,
			gazeYaw = o.gaze or 0,
			bookOpen = o.book or false,
		}
	end

	-- An observation; `o` overrides.
	local function obs(o)
		o = o or {}
		return {
			dt = o.dt or 0.1,
			boat = { pos = o.pos or OUT, vel = o.vel or { x = 0, z = 0 }, heading = 0, throttle = 0, steer = 0 },
			players = o.players or { player(1), player(2) },
			alive = o.alive or { [1] = true, [2] = true },
			reeling = o.reeling or {},
			lanternOn = o.lanternOn == true,
			motorOn = o.motorOn == true,
			safe = o.safe == true,
			intents = o.intents or {},
			timeLeft = 300,
			lanternCanLight = if o.canLight == nil then true else o.canLight,
			lastLantern = o.lastLantern,
			lastMotor = o.lastMotor,
		}
	end

	-- Steps a rule until it is done (or `seconds` run out). `world(time, state)` returns
	-- the observation overrides for that tick. Returns the events, each stamped with `t`.
	local function run(mod, s, seconds, world)
		local out = {}
		local time = 0
		while time < seconds do
			local o = world and world(time, s) or {}
			o.dt = o.dt or 0.1
			for _, e in mod.step(s, obs(o)) do
				e.t = time
				table.insert(out, e)
			end
			time += o.dt
			if mod.done(s) then
				break
			end
		end
		return out
	end

	local function find(events, kind)
		for _, e in events do
			if e.kind == kind then
				return e
			end
		end
		return nil
	end

	local function count(events, kind)
		local n = 0
		for _, e in events do
			if e.kind == kind then
				n += 1
			end
		end
		return n
	end

	-- The contract every rule run must meet. Returns "Pass" or "Fail".
	local function contract(events, s, label)
		t.eq(count(events, "EntityCue"), 1, label .. ": one cue")
		t.ok(count(events, "EntityStage") >= 2, label .. ": stage changes")
		local p, f = count(events, "EntityPass"), count(events, "EntityFail")
		t.eq(p + f, 1, label .. ": exactly one of pass or fail")
		local cue = find(events, "EntityCue")
		local fail = find(events, "EntityFail")
		if fail then
			t.ok(
				fail.t - cue.t >= s.base.warn - 0.11,
				string.format("%s: fail %.1f s after the cue, warn %.1f", label, fail.t - cue.t, s.base.warn)
			)
		end
		return if p == 1 then "Pass" else "Fail"
	end

	local function rng(n)
		return Rng.new(n)
	end

	----------------------------------------------------------------- Hum
	t.test("Hum: the cue silences the chorus, a still dark crew passes", function()
		local s = Hum.new(Config, rng(1), { variant = "LanternOut", warningScale = 1 })
		local events = run(Hum, s, 40)
		local cue = find(events, "EntityCue")
		t.ok(cue ~= nil and cue.data.variant == "LanternOut", "cue with variant")
		t.eq(contract(events, s, "hum pass"), "Pass", "passed")
		t.ok(not s.base.silent, "the frogs come back")
		t.ok(Hum.done(s), "done")
	end)

	t.test("Hum: reeling through it fails, the reeler is taken, the hold goes over", function()
		local s = Hum.new(Config, rng(2), { variant = "LanternOut", warningScale = 1 })
		local silentDuringCue = nil
		local events = run(Hum, s, 40, function(time, st)
			if time > 0.5 and silentDuringCue == nil then
				silentDuringCue = st.base.silent
			end
			return { reeling = { [2] = true } }
		end)
		t.ok(silentDuringCue, "silent during the cue")
		t.eq(contract(events, s, "hum fail"), "Fail", "failed")
		local fx = find(events, "EntityFail").data.effects
		t.eq(fx.kill[1], 2, "the reeler")
		t.eq(fx.cause, "Reeling", "cause")
		t.ok(fx.rock and fx.loseHold, "rocked and hold lost")
		t.eq(fx.blame, 2, "blame")
	end)

	t.test("Hum: motor, moving and a lit lantern are noise, blamed on who did it", function()
		local cases = {
			{ o = { motorOn = true, lastMotor = 2 }, who = 2, cause = "Motor" },
			{ o = { vel = { x = 0, z = 5 } }, who = 1, cause = "Moving" },
			{ o = { lanternOn = true, lastLantern = 2 }, who = 2, cause = "LanternLit" },
		}
		for i, c in cases do
			local s = Hum.new(Config, rng(10 + i), { variant = "LanternOut", warningScale = 1 })
			local events = run(Hum, s, 40, function()
				return table.clone(c.o)
			end)
			t.eq(contract(events, s, c.cause), "Fail", c.cause .. " fails")
			local fx = find(events, "EntityFail").data.effects
			t.eq(fx.kill[1], c.who, c.cause .. " victim")
			t.eq(fx.cause, c.cause, c.cause .. " cause")
		end
	end)

	t.test("Hum: a little noise is forgiven, the dock light forgives everything", function()
		local s = Hum.new(Config, rng(20), { variant = "LanternOut", warningScale = 1 })
		local start = 2.5 + 5 + 1
		local events = run(Hum, s, 40, function(time)
			return { reeling = { [1] = time >= start and time < start + 0.3 } }
		end)
		t.eq(contract(events, s, "grace"), "Pass", "0.3 s forgiven")
		local s2 = Hum.new(Config, rng(21), { variant = "LanternOut", warningScale = 1 })
		local e2 = run(Hum, s2, 40, function()
			return { reeling = { [1] = true }, motorOn = true, safe = true }
		end)
		t.eq(contract(e2, s2, "safe"), "Pass", "nothing counts in the light")
	end)

	t.test("Hum amendment LanternLit: dark is the fail, lit is the counter", function()
		local s = Hum.new(Config, rng(30), { variant = "LanternLit", warningScale = 1 })
		local events = run(Hum, s, 40, function()
			return { lanternOn = false, lastLantern = 1 }
		end)
		t.eq(contract(events, s, "lit dark"), "Fail", "dark fails")
		t.eq(find(events, "EntityFail").data.effects.cause, "LanternDark", "cause")
		local s2 = Hum.new(Config, rng(31), { variant = "LanternLit", warningScale = 1 })
		t.eq(
			contract(
				run(Hum, s2, 40, function()
					return { lanternOn = true }
				end),
				s2,
				"lit lit"
			),
			"Pass",
			"lit passes"
		)
		local s3 = Hum.new(Config, rng(32), { variant = "LanternLit", warningScale = 1 })
		t.eq(
			contract(
				run(Hum, s3, 40, function()
					return { lanternOn = false, canLight = false }
				end),
				s3,
				"no oil"
			),
			"Pass",
			"a lantern that cannot be lit is not held against the crew"
		)
	end)

	t.test("Hum fairness: solo and teaching warnings are longer and a fail never comes early", function()
		for _, scale in { 1, 1.15, 1.4 } do
			for _, teaching in { false, true } do
				local s =
					Hum.new(Config, rng(40), { variant = "LanternOut", warningScale = scale, teaching = teaching })
				local events = run(Hum, s, 60, function()
					return { reeling = { [1] = true }, motorOn = true }
				end)
				t.eq(contract(events, s, "fair " .. scale), "Fail", "fails")
				local mult = if teaching then Config.Director.teachWarnMult else 1
				t.ok(
					s.base.warn >= (Config.Rules.Hum.silence + Config.Rules.Hum.warn) * scale * mult - 1e-6,
					"warn scaled"
				)
			end
		end
	end)

	----------------------------------------------------------------- Wrong Catch
	t.test("Wrong Catch: the cooler settles (cue), then knocks and eats banked fish", function()
		local R = Config.Rules.WrongCatch
		for seed = 1, 20 do
			local s = WrongCatch.new(Config, rng(seed), { warningScale = 1.4, teaching = true })
			local events = run(WrongCatch, s, R.knockDelayMax + 10)
			t.eq(contract(events, s, "cooler"), "Fail", "kept is always the fail")
			local fail = find(events, "EntityFail")
			t.ok(fail.t >= R.knockDelayMin - 0.11 and fail.t <= R.knockDelayMax + 0.2, "knock delay " .. fail.t)
			t.eq(fail.data.effects.eatBanked, R.fishEaten, "fish eaten")
			t.eq(find(events, "EntityCue").data.teaching, false, "never a teaching cue")
		end
	end)

	t.test("Wrong Catch: the cooler is not the lake, it knocks in the dock light too", function()
		local s = WrongCatch.new(Config, rng(3), {})
		local events = run(WrongCatch, s, 200, function()
			return { safe = true }
		end)
		t.ok(find(events, "EntityFail") ~= nil, "knocked")
	end)

	----------------------------------------------------------------- Neighbor
	local function nbrState(seed, form, variant, boatPos, scale)
		return Neighbor.new(Config, rng(seed), {
			variant = variant or "NoWave",
			form = form,
			warningScale = scale or 1,
			boat = { pos = boatPos or CENTER, vel = { x = 0, z = 0 }, heading = 0, throttle = 0, steer = 0 },
		})
	end

	t.test("Neighbor boat: lantern out and keeping away, it gives up and leaves; fake callouts", function()
		local s = nbrState(1, "Boat")
		local d0 = LakeMap.dist(s.pos, CENTER)
		t.ok(math.abs(d0 - Config.Rules.Neighbor.appearDist) < 1, "appears appearDist off")
		local events = run(Neighbor, s, 150, function()
			return { pos = CENTER, lanternOn = false }
		end)
		t.eq(contract(events, s, "nbr dark"), "Pass", "gave up")
		local fakes = 0
		for _, e in events do
			if e.kind == "Callout" then
				fakes += 1
				t.ok(e.data.fake == true, "marked fake")
				t.ok(e.data.as == 1 or e.data.as == 2, "as a living crewmate")
				t.eq(e.player, e.data.as, "shown as that crewmate")
				t.ok(table.find(Neighbor.FAKE_PHRASES, e.data.phrase) ~= nil, "phrase " .. tostring(e.data.phrase))
			end
		end
		local F = Config.Rules.Neighbor.fakeCallouts
		t.ok(fakes >= F[1] and fakes <= F[2], "fake callouts " .. fakes)
	end)

	t.test("Neighbor boat: with the lantern lit it drifts in and takes the helm", function()
		local s = nbrState(2, "Boat")
		local events = run(Neighbor, s, 150, function()
			return { pos = CENTER, lanternOn = true }
		end)
		t.eq(contract(events, s, "nbr lit"), "Fail", "taken")
		local fx = find(events, "EntityFail").data.effects
		t.eq(fx.kill[1], 1, "the helm")
		t.eq(fx.cause, "Closed", "cause")
		t.ok(fx.snuff and fx.silhouette, "lantern snuffed, silhouette aboard")
	end)

	t.test("Neighbor: the light lures it, then it hunts where the boat was", function()
		local s = nbrState(3, "Boat")
		-- Lit for 20 s at the center, then dark while the boat rows 150 studs away.
		local away = { x = 150, z = 0 }
		local events = run(Neighbor, s, 160, function(time)
			if time < 20 then
				return { pos = CENTER, lanternOn = true }
			end
			return { pos = away, lanternOn = false }
		end)
		t.eq(contract(events, s, "nbr lure"), "Pass", "lost the boat and gave up")
		t.ok(s.lastSeen ~= nil and LakeMap.dist(s.lastSeen, CENTER) < 1, "remembers the last light")
	end)

	t.test("Neighbor: a wave takes the waver, but never before the warning time", function()
		local s = nbrState(4, "Boat")
		local events = run(Neighbor, s, 40, function(time)
			if time >= 1 and time < 1.1 then
				return { pos = CENTER, intents = { { kind = "Wave", player = 2 } } }
			end
			return { pos = CENTER }
		end)
		t.eq(contract(events, s, "nbr wave"), "Fail", "taken")
		local fail = find(events, "EntityFail")
		t.eq(fail.data.effects.kill[1], 2, "the waver")
		t.eq(fail.data.effects.cause, "Waved", "cause")
		t.ok(fail.t >= Config.Rules.Neighbor.warn - 0.11, "held to the warning time")
	end)

	t.test("Neighbor amendment NoWaveRowAway: closing on it at all is the fail", function()
		local s = nbrState(5, "Boat", "NoWaveRowAway")
		local events = run(Neighbor, s, 60, function(_, st)
			local d = LakeMap.dist(st.pos, CENTER)
			local v = { x = (st.pos.x - CENTER.x) / d * 3, z = (st.pos.z - CENTER.z) / d * 3 }
			return { pos = CENTER, vel = v, lanternOn = false }
		end)
		t.eq(contract(events, s, "row toward"), "Fail", "closing fails")
		t.eq(find(events, "EntityFail").data.effects.cause, "Closed", "cause")
		local s2 = nbrState(6, "Boat", "NoWaveRowAway")
		local e2 = run(Neighbor, s2, 150, function(_, st)
			local d = LakeMap.dist(st.pos, CENTER)
			local v = { x = -(st.pos.x - CENTER.x) / d * 3, z = -(st.pos.z - CENTER.z) / d * 3 }
			return { pos = CENTER, vel = v, lanternOn = false }
		end)
		t.eq(contract(e2, s2, "row away"), "Pass", "moving away is the counter")
	end)

	t.test("Neighbor false beacon: never on the dock's bearing; leave it be and it goes out", function()
		local boat = { x = 100, z = -150 }
		for seed = 1, 20 do
			local s = nbrState(100 + seed, "FalseBeacon", "NoWave", boat)
			local a = EntityBase.bearing(boat, s.pos)
			local dock = EntityBase.bearing(boat, L.dockEnd)
			t.ok(math.abs(EntityBase.wrapAngle(a - dock)) >= math.pi / 3 - 1e-6, "not where the dock is")
		end
		local s = nbrState(7, "FalseBeacon", "NoWave", boat)
		local events = run(Neighbor, s, 90, function()
			return { pos = boat, lanternOn = true }
		end)
		t.eq(contract(events, s, "beacon"), "Pass", "went out")
	end)

	t.test("Neighbor false beacon: rowing to the light takes the helm", function()
		local s = nbrState(8, "FalseBeacon", "NoWave", CENTER)
		local target = s.pos
		local events = run(Neighbor, s, 90, function(time)
			local f = math.min(1, time / 30)
			return { pos = { x = target.x * f, z = target.z * f } }
		end)
		t.eq(contract(events, s, "to the light"), "Fail", "taken")
		t.eq(find(events, "EntityFail").data.effects.cause, "Beacon", "cause")
	end)

	t.test("Neighbor: nothing fails in the dock light", function()
		local s = nbrState(9, "Boat")
		local events = run(Neighbor, s, 200, function()
			return { pos = CENTER, lanternOn = true, safe = true, intents = { { kind = "Wave", player = 1 } } }
		end)
		t.eq(contract(events, s, "safe"), "Pass", "gave up at the dock")
	end)

	----------------------------------------------------------------- Knocking
	-- Knocks `n` times during the window of round `round` (from the stage event).
	local function knocker(plan)
		local windowAt = {}
		local sent = {}
		return function(time, st)
			if st.phase == "Window" and windowAt[st.round] == nil then
				windowAt[st.round] = time
			end
			local w = windowAt[st.round]
			local n = plan[st.round] or 0
			sent[st.round] = sent[st.round] or 0
			if w ~= nil and time >= w + 0.5 and sent[st.round] < n then
				sent[st.round] += 1
				return { intents = { { kind = "Knock", player = (sent[st.round] % 2) + 1 } } }
			end
			return {}
		end
	end

	t.test("Knocking AnswerTwo: two knocks pass, two players may share them", function()
		local s = Knocking.new(Config, rng(1), { variant = "AnswerTwo", warningScale = 1 })
		local events = run(Knocking, s, 40, knocker({ 2 }))
		t.eq(contract(events, s, "two"), "Pass", "passed")
		t.eq(find(events, "EntityCue").data.knocks, 3, "three knocks")
	end)

	t.test("Knocking: wrong once knocks again harder, right the second time passes", function()
		local s = Knocking.new(Config, rng(2), { variant = "AnswerTwo", warningScale = 1 })
		local events = run(Knocking, s, 40, knocker({ 3, 2 }))
		t.eq(contract(events, s, "second round"), "Pass", "passed in round 2")
		local hard = nil
		for _, e in events do
			if e.kind == "EntityStage" and e.data.round == 2 and e.data.stage == "Cue" then
				hard = e
			end
		end
		t.ok(hard ~= nil and hard.data.hard, "harder knocks")
		t.eq(s.window, Config.Rules.Knocking.secondWindow, "shorter window")
	end)

	t.test("Knocking: wrong twice floods the boat", function()
		local s = Knocking.new(Config, rng(3), { variant = "AnswerTwo", warningScale = 1 })
		local events = run(Knocking, s, 40, knocker({ 0, 1 }))
		t.eq(contract(events, s, "flood"), "Fail", "failed")
		local fx = find(events, "EntityFail").data.effects
		t.ok(fx.flood, "water comes in")
		t.eq(fx.kill, nil, "nobody taken yet")
	end)

	t.test("Knocking amendments: AnswerOne wants one, AnswerNone wants silence", function()
		local s1 = Knocking.new(Config, rng(4), { variant = "AnswerOne", warningScale = 1 })
		t.eq(contract(run(Knocking, s1, 40, knocker({ 1 })), s1, "one"), "Pass", "one passes")
		local s2 = Knocking.new(Config, rng(5), { variant = "AnswerOne", warningScale = 1 })
		t.eq(contract(run(Knocking, s2, 40, knocker({ 2, 2 })), s2, "one wrong"), "Fail", "two is wrong")
		local s3 = Knocking.new(Config, rng(6), { variant = "AnswerNone", warningScale = 1 })
		t.eq(contract(run(Knocking, s3, 40, knocker({ 0 })), s3, "none"), "Pass", "silence passes")
		local s4 = Knocking.new(Config, rng(7), { variant = "AnswerNone", warningScale = 1 })
		t.eq(contract(run(Knocking, s4, 40, knocker({ 1, 1 })), s4, "none wrong"), "Fail", "any knock is wrong")
	end)

	t.test("Knocking: knocks during the cue and knocks from the dead do not count", function()
		local s = Knocking.new(Config, rng(8), { variant = "AnswerNone", warningScale = 1 })
		local events = run(Knocking, s, 40, function(time, st)
			if st.phase == "Knocks" and time < 2 then
				return { intents = { { kind = "Knock", player = 1 } } }
			end
			return { intents = { { kind = "Knock", player = 2 } }, alive = { [1] = true, [2] = false } }
		end)
		t.eq(contract(events, s, "ignored"), "Pass", "not answers")
	end)

	t.test("Knocking fairness: a solo crew's windows are longer", function()
		local s = Knocking.new(Config, rng(9), { variant = "AnswerTwo", warningScale = 1.4 })
		t.ok(math.abs(s.window - Config.Rules.Knocking.window * 1.4) < 1e-6, "window scaled")
		local events = run(Knocking, s, 60, function(_, st)
			if st.phase == "Window" then
				return { intents = { { kind = "Knock", player = 1 } } }
			end
			return {}
		end)
		t.eq(contract(events, s, "solo"), "Fail", "fails, but not early")
	end)

	----------------------------------------------------------------- Watcher
	-- A boat 120 studs inside the east shore.
	local NEAR = { x = L.radiusX - 120, z = 0 }
	local function watcher(seed, variant, only, scale)
		return Watcher.new(Config, rng(seed), {
			variant = variant or "EdgeOfSight",
			only = only,
			warningScale = scale or 1,
			boat = { pos = NEAR, vel = { x = 0, z = 0 }, heading = 0, throttle = 0, steer = 0 },
		})
	end
	local function gazeFor(s, offset)
		return EntityBase.bearing(NEAR, s.pos) + offset
	end

	t.test("Watcher: it stands on the nearest shore, in the trees", function()
		local s = watcher(1)
		local shore = LakeMap.nearestShorePoint(Config, NEAR)
		t.ok(LakeMap.dist(s.shore, shore) < 1e-6, "nearest shore")
		t.ok(not LakeMap.inside(Config, s.pos), "in the trees")
		t.eq(s.step, Config.Rules.Watcher.steps, "steps out")
	end)

	t.test("Watcher EdgeOfSight: held at the edge of sight it holds, then it is gone", function()
		local s = watcher(2)
		local events = run(Watcher, s, 80, function(_, st)
			return {
				pos = NEAR,
				players = { player(1, { gaze = gazeFor(st, 0.8) }), player(2, { gaze = gazeFor(st, math.pi) }) },
			}
		end)
		t.eq(contract(events, s, "edge"), "Pass", "gone")
		t.eq(s.step, Config.Rules.Watcher.steps, "never stepped")
	end)

	t.test("Watcher EdgeOfSight: staring makes it lunge to the waterline", function()
		local s = watcher(3)
		local events = run(Watcher, s, 80, function(_, st)
			return {
				pos = NEAR,
				players = { player(1, { gaze = gazeFor(st, 0) }), player(2, { gaze = gazeFor(st, 0) }) },
			}
		end)
		t.eq(contract(events, s, "stare"), "Fail", "reached")
		local fx = find(events, "EntityFail").data.effects
		t.ok(fx.snuff, "every lantern dies")
		t.eq(#fx.kill, 1, "takes one")
		t.ok(count(events, "EntityMoved") >= 2, "lunged in steps")
	end)

	t.test("Watcher EdgeOfSight: unwatched (or reading the book) it steps closer", function()
		local s = watcher(4)
		local events = run(Watcher, s, 80, function(_, st)
			return {
				pos = NEAR,
				players = {
					player(1, { gaze = gazeFor(st, math.pi) }),
					player(2, { gaze = gazeFor(st, 0), book = true }),
				},
			}
		end)
		t.eq(contract(events, s, "away"), "Fail", "reached")
		t.eq(count(events, "EntityMoved"), Config.Rules.Watcher.steps, "one step at a time")
	end)

	t.test("Watcher amendment StareItDown: staring holds it, the edge does not", function()
		local s = watcher(5, "StareItDown")
		local events = run(Watcher, s, 80, function(_, st)
			return {
				pos = NEAR,
				players = { player(1, { gaze = gazeFor(st, 0) }), player(2, { gaze = gazeFor(st, math.pi) }) },
			}
		end)
		t.eq(contract(events, s, "stare down"), "Pass", "held off")
		local s2 = watcher(6, "StareItDown")
		local e2 = run(Watcher, s2, 80, function(_, st)
			return {
				pos = NEAR,
				players = { player(1, { gaze = gazeFor(st, 0.8) }), player(2, { gaze = gazeFor(st, 0.8) }) },
			}
		end)
		t.eq(contract(e2, s2, "edge under amendment"), "Fail", "the edge is not enough")
	end)

	t.test("Watcher: rowing well away loses it", function()
		local s = watcher(7)
		local far = { x = NEAR.x - Config.Rules.Watcher.retreatDist - 50, z = 0 }
		local events = run(Watcher, s, 80, function(time)
			return { pos = if time > 2 then far else NEAR, players = { player(1, { gaze = math.pi / 2 }) } }
		end)
		t.eq(contract(events, s, "retreat"), "Pass", "gone")
	end)

	t.test("Watcher solo sighting: only that player's eyes count, and it waits 12 s at least", function()
		local s = watcher(8, "EdgeOfSight", 1)
		t.ok(s.base.warn >= Config.Director.soloCueMinSeconds, "solo warning")
		local events = run(Watcher, s, 80, function(_, st)
			-- Player 2 happens to hold the spot at the edge of sight, but cannot see it.
			return {
				pos = NEAR,
				players = { player(1, { gaze = gazeFor(st, math.pi) }), player(2, { gaze = gazeFor(st, 0.8) }) },
			}
		end)
		t.eq(contract(events, s, "solo"), "Fail", "reached")
		local cue = find(events, "EntityCue")
		t.eq(cue.only, 1, "the cue is for one player")
		local fail = find(events, "EntityFail")
		t.ok(fail.t - cue.t >= Config.Director.soloCueMinSeconds - 0.11, "at least 12 s")
		t.eq(fail.only, nil, "the outcome is for everyone")
	end)

	t.test("Watcher solo sighting: the spotter dies mid-window, it passes and takes nobody", function()
		local s = watcher(10, "EdgeOfSight", 1)
		local events = run(Watcher, s, 80, function(time, st)
			-- Everyone looks away: with the spotter's eyes gone, nobody else ever saw it.
			return {
				pos = NEAR,
				players = { player(1, { gaze = gazeFor(st, math.pi) }), player(2, { gaze = gazeFor(st, math.pi) }) },
				alive = if time >= 5 then { [1] = false, [2] = true } else { [1] = true, [2] = true },
			}
		end)
		t.eq(contract(events, s, "spotter dies"), "Pass", "passes quietly")
		t.eq(count(events, "EntityFail"), 0, "no fail")
		t.ok(find(events, "EntityPass").data.spotterGone, "passed because the spotter is gone")
		t.eq(find(events, "EntityCue").only, 1, "the cue is unchanged: for the spotter")
	end)

	t.test("Watcher solo sighting: a fail held for the warning time is withdrawn if the spotter dies", function()
		local s = watcher(11, "EdgeOfSight", 1)
		local heldSeen = false
		local events = run(Watcher, s, 80, function(time, st)
			if st.base.pending ~= nil then
				heldSeen = true
			end
			-- The spotter stares: it lunges to the waterline before the 12 s solo warning is up.
			return {
				pos = NEAR,
				players = { player(1, { gaze = gazeFor(st, 0) }), player(2, { gaze = gazeFor(st, math.pi) }) },
				alive = if time >= 11 then { [1] = false, [2] = true } else { [1] = true, [2] = true },
			}
		end)
		t.ok(heldSeen, "the fail was held for the warning time")
		t.eq(contract(events, s, "held fail withdrawn"), "Pass", "passes quietly")
		t.eq(count(events, "EntityFail"), 0, "no fail")
	end)

	t.test("Watcher solo sighting: the fail takes the spotter, not whoever faces away most", function()
		local s = watcher(12, "EdgeOfSight", 1)
		local events = run(Watcher, s, 80, function(_, st)
			-- The spotter looks away (outside the edge); player 2 faces even further away.
			return {
				pos = NEAR,
				players = { player(1, { gaze = gazeFor(st, 2.0) }), player(2, { gaze = gazeFor(st, math.pi) }) },
			}
		end)
		t.eq(contract(events, s, "solo fail"), "Fail", "reached")
		local fx = find(events, "EntityFail").data.effects
		t.eq(#fx.kill, 1, "takes one")
		t.eq(fx.kill[1], 1, "takes the spotter")
	end)

	t.test("Watcher: it never steps in the dock light", function()
		local s = watcher(9)
		local events = run(Watcher, s, 80, function()
			return { pos = NEAR, safe = true }
		end)
		t.eq(contract(events, s, "safe"), "Pass", "gone")
		t.eq(count(events, "EntityMoved"), 0, "never moved")
	end)

	----------------------------------------------------------------- EntityBase
	t.test("EntityBase: one outcome only, a pending fail waits for the warning time", function()
		local b = EntityBase.new("Hum", Config, rng(1), { warningScale = 1 }, 5)
		local events = {}
		EntityBase.advance(b, 0.1, events)
		EntityBase.cue(b, nil, events)
		EntityBase.cue(b, nil, events)
		t.eq(count(events, "EntityCue"), 1, "one cue")
		t.eq(EntityBase.fail(b, events, { cause = "Test" }), false, "held")
		t.eq(EntityBase.pass(b, events), false, "a held fail beats a later pass")
		for _ = 1, 100 do
			EntityBase.advance(b, 0.1, events)
		end
		t.eq(count(events, "EntityFail"), 1, "sent once")
		t.eq(count(events, "EntityPass"), 0, "no pass")
		t.ok(EntityBase.done(b), "done after the cooldown")
		t.eq(b.stage, "Cooldown", "cooldown")
	end)
end
