-- Core.Night with the rules in: debugForce, deaths and death cards, the whole crew lost,
-- the in-water drag, the drowned's bell, the leak and bailing and sinking, Wrong Catch
-- consequences, the director's teaching spawn, fake callouts and the night tallies.
return function(t, Shared)
	local Night = require(Shared.Core.Night)
	local Config = require(Shared.Config)
	local L = Config.Lake

	local OUT = { x = 0, z = L.dockEnd.z + 150 }
	local AT_DOCK = { x = L.dockEnd.x, z = L.dockEnd.z }

	local function params(over)
		local p = {
			seed = 77,
			night = 1,
			mode = "Story",
			difficulty = "Normal",
			playerIds = { 1, 2 },
			rules = { "Hum", "WrongCatch", "Neighbor", "Knocking", "Watcher" },
			newRules = {},
			amendments = {},
			real = 0,
			fake = 0,
			quietGap = 30,
			quota = 4,
			maxConcurrent = 1,
			warningScale = 1,
		}
		for k, v in over or {} do
			p[k] = v
		end
		return p
	end

	local function input(o)
		o = o or {}
		return {
			dt = o.dt or 0.1,
			boat = { pos = o.pos or OUT, vel = o.vel or { x = 0, z = 0 }, heading = 0, throttle = 0, steer = 0 },
			players = o.players or {},
			intents = o.intents or {},
		}
	end

	local function stepFor(s, seconds, o, sink)
		for _ = 1, math.floor(seconds / 0.1 + 0.5) do
			local i = input(type(o) == "function" and o(s) or o)
			for _, e in Night.step(s, i) do
				if sink then
					table.insert(sink, e)
				end
			end
			if s.phase ~= "Night" then
				break
			end
		end
	end

	local function find(events, kind)
		for _, e in events do
			if e.kind == kind then
				return e
			end
		end
		return nil
	end

	local function all(events, kind)
		local out = {}
		for _, e in events do
			if e.kind == kind then
				table.insert(out, e)
			end
		end
		return out
	end

	-- Puts a fish on every living line (for the reeling noise and the hold).
	local function reelEveryone(s)
		local intents = {}
		for _, id in s.order do
			local m = s.crew[id]
			if m.alive then
				local f = m.fishing
				if f.phase == "Idle" then
					table.insert(intents, { kind = "Cast", player = id, num = 1 })
				elseif f.phase == "Bite" or f.phase == "Reeling" then
					table.insert(intents, { kind = "ReelHold", player = id, flag = true })
				end
			end
		end
		return { intents = intents }
	end

	t.test("debugForce starts the Hum now: its cue comes back and the frogs stop", function()
		local s = Night.new(Config, params())
		stepFor(s, 1, {})
		local e = Night.debugForce(s, "Hum", { variant = "LanternLit" })
		local cue = find(e, "EntityCue")
		t.ok(cue ~= nil and cue.entity == "Hum" and cue.data.variant == "LanternLit", "cue")
		local events = {}
		stepFor(s, 0.2, {}, events)
		t.eq(s.chorus, 0, "silent")
		t.eq(#Night.debugForce(s, "Hum", nil), 0, "never twice at once")
	end)

	t.test("breaking the Hum's silence: death card, hold lost, boat rocked, tally", function()
		local s = Night.new(Config, params())
		s.lantern.on = false -- nights start lit; this test is about the reeling alone
		stepFor(s, 1, {})
		Night.debugForce(s, "Hum", {})
		local events = {}
		stepFor(s, 30, reelEveryone, events)
		local died = find(events, "PlayerDied")
		t.ok(died ~= nil, "someone was pulled under")
		t.eq(died.data.rule, "Hum", "rule")
		t.eq(died.data.variant, "LanternOut", "variant")
		t.eq(died.data.text, "Death.Hum.Reeling", "death card")
		t.ok(find(events, "BoatRocked") ~= nil, "rocked")
		t.eq(#s.deaths, 1, "one death")
		t.eq(s.tally[died.player].brokeSilence, 1, "tally: broke the silence")
		t.eq(s.tally[died.player].deaths, 1, "tally: death")
		t.ok(s.crew[died.player].alive == false, "dead")
		t.eq(s.crew[died.player].fishing.phase, "Idle", "line gone")
	end)

	t.test("the whole crew gone fails the night", function()
		local s = Night.new(Config, params({ playerIds = { 1 } }))
		stepFor(s, 1, {})
		Night.debugForce(s, "Hum", {})
		local events = {}
		Night.step(s, input({ intents = { { kind = "ToggleMotor", player = 1 } } }))
		stepFor(s, 40, {}, events)
		local failed = find(events, "NightFailed")
		t.ok(failed ~= nil and failed.data.reason == "CrewLost", "crew lost")
		t.eq(failed.data.result.deaths[1].rule, "Hum", "result names the rule")
		t.ok(failed.data.result.tallies ~= nil and failed.data.result.tallies[1].deaths == 1, "tallies in the result")
	end)

	t.test("Rule 0: a swimmer hears the pull and is taken", function()
		local s = Night.new(Config, params())
		local events = {}
		local swim = {
			players = {
				{ id = 1, seated = true, helm = true, inWater = false, gazeYaw = 0, bookOpen = false },
				{ id = 2, seated = false, helm = false, inWater = true, gazeYaw = 0, bookOpen = false },
			},
		}
		stepFor(s, 7, swim, events)
		local warn = find(events, "DragWarning")
		t.ok(warn ~= nil and warn.only == 2 and warn.player == 2, "the swimmer hears it")
		local died = find(events, "PlayerDied")
		t.ok(died ~= nil and died.player == 2 and died.data.rule == "Water", "taken")
		t.eq(died.data.text, "Death.Water.Drag", "card")
		t.ok(s.crew[1].alive, "the one in the boat is fine")
	end)

	t.test("climbing back in resets the drag", function()
		local s = Night.new(Config, params())
		local function p(inWater)
			return {
				players = {
					{ id = 2, seated = not inWater, helm = false, inWater = inWater, gazeYaw = 0, bookOpen = false },
				},
			}
		end
		for _ = 1, 3 do
			stepFor(s, 4, p(true))
			stepFor(s, 1, p(false))
		end
		t.ok(s.crew[2].alive, "never taken")
	end)

	t.test("the drowned ring a bell every 15 seconds", function()
		local s = Night.new(Config, params())
		s.crew[2].alive = false
		local events = {}
		stepFor(s, 20, { intents = { { kind = "GhostBell", player = 2 } } }, events)
		t.eq(#all(events, "GhostBell"), 2, "at 0 and 15 s")
		events = {}
		stepFor(s, 1, { intents = { { kind = "GhostBell", player = 1 } } }, events)
		t.eq(#all(events, "GhostBell"), 0, "the living have no bell")
	end)

	-- Forces a Knocking and answers it wrong twice.
	local function floodBoat(s)
		Night.debugForce(s, "Knocking", { variant = "AnswerTwo" })
		stepFor(s, 30, {})
	end

	t.test("Knocking wrong twice: water comes in and with nobody bailing the boat sinks", function()
		local s = Night.new(Config, params())
		stepFor(s, 1, {})
		local events = {}
		floodBoat(s)
		t.ok(s.leakOn, "leaking")
		stepFor(s, Config.Rules.Knocking.floodSeconds + 5, {}, events)
		t.ok(find(events, "Sunk") ~= nil, "sunk")
		t.eq(#all(events, "PlayerDied"), 2, "everyone")
		t.eq(find(events, "PlayerDied").data.text, "Death.Knocking.Sunk", "card")
		t.eq(find(events, "NightFailed").data.reason, "Sunk", "reason")
	end)

	t.test("bailing plugs the leak and empties the boat; no fishing while bailing", function()
		local s = Night.new(Config, params())
		stepFor(s, 1, {})
		floodBoat(s)
		local bail = {
			intents = { { kind = "BailHold", player = 1, flag = true }, { kind = "BailHold", player = 2, flag = true } },
		}
		stepFor(s, 0.1, bail)
		local e = Night.step(s, input({ intents = { { kind = "Cast", player = 1, num = 1 } } }))
		t.eq(s.crew[1].fishing.phase, "Idle", "no cast while bailing")
		t.eq(find(e, "CastOut"), nil, "no CastOut")
		stepFor(s, 60, {})
		t.ok(not s.leakOn, "plugged")
		t.eq(s.flood, 0, "dry")
		t.ok(s.crew[1].alive and s.crew[2].alive, "nobody lost")
		t.ok(s.tally[1].bailedSeconds > 5, "tally: bailed seconds")
	end)

	t.test("knocks answered while the Knocking is out are tallied", function()
		local s = Night.new(Config, params())
		stepFor(s, 1, {})
		Night.debugForce(s, "Knocking", { variant = "AnswerTwo" })
		stepFor(s, 4, {})
		local events = {}
		stepFor(s, 0.1, { intents = { { kind = "Knock", player = 1 } } }, events)
		stepFor(s, 0.1, { intents = { { kind = "Knock", player = 2 } } }, events)
		stepFor(s, 10, {}, events)
		t.ok(find(events, "EntityPass") ~= nil, "answered right")
		t.eq(s.tally[1].knocksAnswered + s.tally[2].knocksAnswered, 2, "tally")
	end)

	-- Lands one fish on player 1's line and keeps or throws it back.
	local function landOne(s, keep)
		for _ = 1, 600 do
			local f = s.crew[1].fishing
			local intents = {}
			if f.phase == "Idle" then
				table.insert(intents, { kind = "Cast", player = 1, num = 1 })
			elseif f.phase == "Bite" then
				table.insert(intents, { kind = "ReelHold", player = 1, flag = true })
			elseif f.phase == "Reeling" then
				table.insert(intents, { kind = "ReelHold", player = 1, flag = f.tension < f.center })
			elseif f.phase == "Deciding" then
				table.insert(intents, { kind = "CatchDecision", player = 1, flag = keep })
				Night.step(s, input({ intents = intents }))
				return
			end
			Night.step(s, input({ intents = intents }))
		end
	end

	t.test("Wrong Catch kept: attention jumps with a floor, the cooler knocks and eats fish", function()
		local s = Night.new(Config, params({ playerIds = { 1 } }))
		stepFor(s, 1, {})
		-- Two true fish in the cooler first.
		landOne(s, true)
		landOne(s, true)
		Night.step(s, input({ pos = AT_DOCK, intents = { { kind = "Bank", player = 1 } } }))
		local before = s.quota.banked
		Night.debugForce(s, "WrongCatch", nil)
		landOne(s, true)
		t.eq(s.keptWrong, 1, "kept wrong")
		t.eq(s.tally[1].keptWrong, 1, "tally")
		t.ok(s.attn.floor >= Config.Attention.keptWrongFloor, "floor")
		local events = {}
		for _, e in Night.step(s, input({ pos = AT_DOCK, intents = { { kind = "Bank", player = 1 } } })) do
			table.insert(events, e)
		end
		local cue = find(events, "EntityCue")
		t.ok(cue ~= nil and cue.entity == "WrongCatch", "the cooler settles")
		local afterBank = s.quota.banked
		t.ok(afterBank > before, "banked triple")
		stepFor(s, Config.Rules.WrongCatch.knockDelayMax + 2, { pos = AT_DOCK }, events)
		local fail = find(events, "EntityFail")
		t.ok(fail ~= nil and fail.entity == "WrongCatch", "the cooler knocked")
		t.eq(fail.data.effects.eaten.count, Config.Rules.WrongCatch.fishEaten, "two fish gone")
		t.eq(s.quota.banked, afterBank - fail.data.effects.eaten.points, "points gone")
		t.eq(#s.cooler, 3 - Config.Rules.WrongCatch.fishEaten, "cooler")
	end)

	t.test("Wrong Catch thrown back: nothing happens", function()
		local s = Night.new(Config, params({ playerIds = { 1 } }))
		stepFor(s, 1, {})
		Night.debugForce(s, "WrongCatch", nil)
		landOne(s, false)
		t.eq(s.keptWrong, 0, "not kept")
		t.eq(s.attn.floor, 0, "no floor")
		local events = {}
		stepFor(s, 150, { pos = AT_DOCK }, events)
		t.eq(find(events, "EntityCue"), nil, "no rule started")
	end)

	t.test("the director teaches the night's new rule inside the band", function()
		local p = params({ rules = { "Hum" }, newRules = { "Hum" }, real = 2, fake = 3, quietGap = 50 })
		local s = Night.new(Config, p)
		s.lantern.on = false -- a still, dark crew (nights start lit)
		local events = {}
		local cueAt = nil
		for _ = 1, 3600 do
			for _, e in Night.step(s, input({})) do
				table.insert(events, e)
				if e.kind == "EntityCue" and cueAt == nil then
					cueAt = s.clock.elapsed
				end
			end
			if s.phase ~= "Night" then
				break
			end
		end
		local cue = find(events, "EntityCue")
		t.ok(cue ~= nil and cue.entity == "Hum" and cue.data.teaching == true, "teaching Hum")
		local len = Config.Night.realSeconds
		t.ok(cueAt >= Config.Night.teachFrom * len and cueAt <= Config.Night.teachTo * len, "inside the band")
		t.ok(#all(events, "EntityPass") >= 1, "a still dark crew passed")
		t.eq(#s.deaths, 0, "nobody died")
		t.ok(#all(events, "Fakeout") >= 1, "fake-outs fired")
		t.eq(s.scaresSurvived, #all(events, "EntityPass"), "scares survived")
	end)

	t.test("the Neighbor's fake callouts come in a crewmate's name", function()
		local s = Night.new(Config, params({ playerIds = { 1, 2, 3 } }))
		stepFor(s, 1, { pos = { x = 0, z = 0 } })
		Night.debugForce(s, "Neighbor", { form = "Boat" })
		local events = {}
		stepFor(s, 60, { pos = { x = 0, z = 0 } }, events)
		local fakes = 0
		for _, e in events do
			if e.kind == "Callout" and e.data.fake then
				fakes += 1
				t.ok(s.crew[e.player] ~= nil, "a crewmate")
			end
		end
		t.ok(fakes >= 1, "fake callouts")
	end)

	t.test("staring at the Watcher is tallied once per look", function()
		local s = Night.new(Config, params())
		local near = { x = L.radiusX - 120, z = 0 }
		stepFor(s, 1, { pos = near })
		Night.debugForce(s, "Watcher", {})
		local w = s.rules[1].state
		local bearing = math.atan2(w.pos.x - near.x, w.pos.z - near.z)
		local function look(at)
			return {
				pos = near,
				players = { { id = 1, seated = true, helm = true, inWater = false, gazeYaw = at, bookOpen = false } },
			}
		end
		stepFor(s, 1, look(bearing))
		stepFor(s, 1, look(bearing + 0.9))
		stepFor(s, 1, look(bearing))
		t.eq(s.tally[1].timesStaredAtWatcher, 2, "two looks")
	end)

	t.test("a player who left the game is never taken or counted by any rule", function()
		local near = { x = L.radiusX - 120, z = 0 }
		local function seat(id, at, present)
			return {
				id = id,
				seated = present ~= false,
				helm = id == 1,
				inWater = false,
				gazeYaw = at,
				bookOpen = false,
				present = present,
			}
		end
		-- A shared sighting: player 2 left and faces away the most, player 1 looks away too.
		local s = Night.new(Config, params())
		stepFor(s, 1, { pos = near })
		Night.debugForce(s, "Watcher", {})
		local w = s.rules[1].state
		local bearing = math.atan2(w.pos.x - near.x, w.pos.z - near.z)
		local events = {}
		stepFor(s, 60, function()
			return { pos = near, players = { seat(1, bearing + 2.0), seat(2, bearing + math.pi, false) } }
		end, events)
		local fail = find(events, "EntityFail")
		t.ok(fail ~= nil, "it reached the waterline")
		for _, id in fail.data.effects.kill do
			t.ok(id ~= 2, "the departed player is never taken")
		end
		t.ok(s.crew[2].alive, "player 2 untouched")

		-- A solo sighting cued to the player who then left: it passes and takes nobody.
		local s2 = Night.new(Config, params())
		stepFor(s2, 1, { pos = near })
		Night.debugForce(s2, "Watcher", { only = 2 })
		local e2 = {}
		stepFor(s2, 60, function()
			return { pos = near, players = { seat(1, bearing + math.pi), seat(2, 0, false) } }
		end, e2)
		t.eq(#all(e2, "EntityFail"), 0, "no fail")
		t.ok(find(e2, "EntityPass") ~= nil, "passed")
		t.ok(s2.crew[1].alive and s2.crew[2].alive, "nobody taken")

		-- Every rule sees the departed player as gone (and the director's alive list skips them).
		local s3 = Night.new(Config, params())
		stepFor(s3, 1, { pos = near, players = { seat(1, 0), seat(2, 0, false) } })
		t.eq(s3.lastObs.alive[2], false, "rules see the departed player as gone")
		t.eq(s3.lastObs.alive[1], true, "the present player is alive")
		t.ok(s3.absent[2] == true, "marked absent")
	end)

	t.test("rules replay from the seed", function()
		local function play()
			local s = Night.new(Config, params({ real = 4, fake = 4, newRules = { "Neighbor" }, night = 3 }))
			local log = {}
			for _ = 1, 3600 do
				for _, e in Night.step(s, input({ pos = { x = 0, z = 0 } })) do
					table.insert(log, e.kind .. tostring(e.entity or (e.data and e.data.id) or ""))
				end
				if s.phase ~= "Night" then
					break
				end
			end
			return table.concat(log, ",")
		end
		t.eq(play(), play(), "replay")
	end)

	t.test("in the dock light a rule pauses: no fail, no pass, it resumes outside", function()
		local s = Night.new(Config, params())
		s.lantern.on = false
		stepFor(s, 1, {})
		Night.debugForce(s, "Hum", {})
		local hum = s.rules[1].state
		-- Into the light while reeling (noise): nothing moves for a long time.
		local events = {}
		stepFor(s, 60, function(st)
			local o = reelEveryone(st)
			o.pos = AT_DOCK
			return o
		end, events)
		t.eq(find(events, "EntityFail"), nil, "no fail in the light")
		t.eq(find(events, "EntityPass"), nil, "no pass in the light either")
		t.eq(hum.held, 0, "the hold timer did not run")
		t.ok(#s.rules == 1 and s.rules[1].id == "Hum", "still active")
		-- Back out, still and dark: it picks up and passes.
		events = {}
		stepFor(s, 40, {}, events)
		t.ok(find(events, "EntityPass") ~= nil, "passes once outside")
	end)

	t.test("a rule paused in the light never holds the night: dawn still ends it", function()
		local s = Night.new(Config, params({ quota = 0 }))
		s.lantern.on = false
		stepFor(s, 1, {})
		Night.debugForce(s, "Hum", {})
		stepFor(s, Config.Night.realSeconds + 5, { pos = AT_DOCK })
		t.ok(s.phase == "Cleared" or s.phase == "Failed", "the night ended")
	end)

	t.test("a deciding timeout throws the fish back with data.timeout", function()
		local s = Night.new(Config, params({ rules = { "Hum" } }))
		stepFor(s, 0.1, {})
		local m = s.crew[1]
		m.fishing.phase = "Deciding"
		m.fishing.catch = { species = "Pumpkinseed", points = 1, wrong = false, tier = 0, traits = {} }
		m.fishing.timer = 0.05
		local events = {}
		stepFor(s, 0.3, {}, events)
		local r = find(events, "Released")
		t.ok(r ~= nil and r.data.timeout == true and r.data.why == "ThrownBack", "released on timeout")
		t.eq(#s.hold, 0, "not kept")
		t.eq(find(events, "Kept"), nil, "no Kept")
	end)

	t.test("a solo Neighbor sends no fake callouts", function()
		local s = Night.new(Config, params({ playerIds = { 1 } }))
		stepFor(s, 1, { pos = { x = 0, z = 0 } })
		Night.debugForce(s, "Neighbor", { form = "Boat" })
		local events = {}
		stepFor(s, 60, { pos = { x = 0, z = 0 } }, events)
		for _, e in events do
			t.ok(not (e.kind == "Callout" and e.data.fake), "no fake callout")
		end
	end)

	t.test("a touch player's Watcher cones are wider by touchConeBonus", function()
		local Watcher = require(Shared.Core.entities.Watcher)
		local R = Config.Rules.Watcher
		local boat = { x = 0, z = 0 }
		local figure = { x = 0, z = 100 } -- bearing 0
		local function gaze(yaw, touch)
			return Watcher.gazeAt(
				Config,
				boat,
				figure,
				{ id = 1, seated = true, helm = true, inWater = false, gazeYaw = yaw, bookOpen = false, touch = touch }
			)
		end
		local b = R.touchConeBonus
		t.ok(b > 0, "a bonus")
		t.eq(gaze(R.stareCone + b / 2, nil), "Edge", "mouse: just past the stare cone is the edge")
		t.eq(gaze(R.stareCone + b / 2, true), "Stare", "touch: inside the wider stare cone")
		t.eq(gaze(R.edgeCone + b / 2, false), "Away", "mouse: just past the edge cone is away")
		t.eq(gaze(R.edgeCone + b / 2, true), "Edge", "touch: inside the wider edge cone")
	end)

	t.test("a Hum fail kills the motor and says so", function()
		local s = Night.new(Config, params())
		s.lantern.on = false
		stepFor(s, 1, {})
		stepFor(s, 0.1, { intents = { { kind = "ToggleMotor", player = 1 } } })
		t.ok(s.motorOn, "motor on")
		Night.debugForce(s, "Hum", {})
		local events = {}
		stepFor(s, 30, {}, events)
		t.ok(find(events, "EntityFail") ~= nil, "the Hum failed (motor noise)")
		t.eq(s.motorOn, false, "motor off")
		local mc = nil
		for _, e in events do
			if e.kind == "MotorChanged" then
				mc = e
			end
		end
		t.ok(mc ~= nil and mc.data.on == false and mc.entity == "Hum", "MotorChanged off")
	end)
end
