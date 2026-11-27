-- Core.Night (M2 scope; rules, deaths and the director are in NightRules.spec.luau): start events, fishing through to the hold, banking, quota, oil,
-- motor, attention and chorus, wrong catches, clear and fail, determinism, the view.
return function(t, Shared)
	local Night = require(Shared.Core.Night)
	local Config = require(Shared.Config)
	local L = Config.Lake

	local function params(over)
		local p = {
			seed = 1234,
			night = 1,
			mode = "Story",
			difficulty = "Normal",
			playerIds = { 1, 2 },
			rules = { "Hum" },
			newRules = { "Hum" },
			amendments = {},
			supplies = {},
			real = 0, -- these M2 specs are about fishing: no director scares unless asked
			fake = 0,
			quietGap = 75,
			quota = 4,
			maxConcurrent = 1,
			warningScale = 1,
		}
		for k, v in over or {} do
			p[k] = v
		end
		return p
	end

	local AT_DOCK = { x = L.dockEnd.x, z = L.dockEnd.z }
	local OUT = { x = 0, z = L.dockEnd.z + 150 }

	local function input(pos, intents, dt)
		return {
			dt = dt or 0.1,
			boat = { pos = pos, vel = { x = 0, z = 0 }, heading = 0, throttle = 0, steer = 0 },
			players = {},
			intents = intents or {},
		}
	end

	local function kindsOf(events)
		local set = {}
		for _, e in events do
			set[e.kind] = (set[e.kind] or 0) + 1
		end
		return set
	end

	-- Plays the reel bar perfectly for every player and keeps (or not) each catch.
	local function fishOnce(s, pos, keepFn)
		local all = {}
		for _ = 1, 600 do
			local intents = {}
			for _, id in s.order do
				local f = s.crew[id].fishing
				if f.phase == "Idle" then
					table.insert(intents, { kind = "Cast", player = id, num = 1 })
				elseif f.phase == "Bite" then
					table.insert(intents, { kind = "ReelHold", player = id, flag = true })
				elseif f.phase == "Reeling" then
					table.insert(intents, { kind = "ReelHold", player = id, flag = f.tension < f.center })
				elseif f.phase == "Deciding" then
					local keep = if keepFn then keepFn(f.catch) else true
					table.insert(intents, { kind = "CatchDecision", player = id, flag = keep })
				end
			end
			for _, e in Night.step(s, input(pos, intents)) do
				table.insert(all, e)
			end
			if #s.hold >= s.holdMax or s.phase ~= "Night" then
				break
			end
		end
		return all
	end

	t.test("first step announces the night, the new rule and the tape", function()
		local s = Night.new(Config, params())
		local k = kindsOf(Night.step(s, input(AT_DOCK)))
		t.eq(k.NightStarted, 1, "NightStarted")
		t.eq(k.RuleUnlocked, 1, "RuleUnlocked")
		t.eq(k.Tape, 1, "Tape")
		t.eq(kindsOf(Night.step(s, input(AT_DOCK))).NightStarted, nil, "only once")
	end)

	t.test("an amendment adds the amendment tape", function()
		local s = Night.new(Config, params({ amendments = { Hum = "LanternLit" } }))
		t.eq(kindsOf(Night.step(s, input(AT_DOCK))).Tape, 2, "two tapes")
	end)

	t.test("no fish bite in the dock light", function()
		local s = Night.new(Config, params())
		local e = Night.step(s, input(AT_DOCK, { { kind = "Cast", player = 1, num = 1 } }))
		local lost = nil
		for _, x in e do
			if x.kind == "HookLost" then
				lost = x
			end
		end
		t.ok(lost ~= nil and lost.data.why == "DockLight", "refused in the light")
	end)

	t.test("fish fill the hold, bank only at the dock, quota met, night cleared at dawn", function()
		local s = Night.new(Config, params({ quota = 4 }))
		local events = fishOnce(s, OUT)
		local k = kindsOf(events)
		t.ok((k.Caught or 0) >= s.holdMax, "caught")
		t.eq(#s.hold, s.holdMax, "hold full")
		Night.step(s, input(OUT, { { kind = "Bank", player = 1 } }))
		t.eq(#s.hold, s.holdMax, "cannot bank out on the lake")
		local e = Night.step(s, input(AT_DOCK, { { kind = "Bank", player = 2 } }))
		k = kindsOf(e)
		t.eq(k.Banked, 1, "banked")
		t.eq(k.QuotaMet, 1, "quota met")
		t.eq(#s.hold, 0, "hold empty")
		t.ok(s.quota.banked >= 4, "points banked")
		local last = {}
		for _ = 1, Config.Night.realSeconds * 10 + 10 do
			last = Night.step(s, input(AT_DOCK, {}, 0.1))
			if s.phase ~= "Night" then
				break
			end
		end
		t.eq(kindsOf(last).NightCleared, 1, "cleared")
		local r = Night.result(s) :: any
		t.ok(r.cleared, "result cleared")
		t.eq(r.banked, s.quota.banked, "result banked")
		t.eq(#Night.step(s, input(AT_DOCK)), 0, "nothing after the end")
	end)

	t.test("quota short at dawn fails the night", function()
		-- No rules: a lit, idle crew must not meet a Hum before dawn.
		local s = Night.new(Config, params({ quota = 50, rules = {}, newRules = {} }))
		local last = {}
		for _ = 1, Config.Night.realSeconds + 5 do
			last = Night.step(s, input(OUT, {}, 1)) -- Night clamps dt to 1 second
			if s.phase ~= "Night" then
				break
			end
		end
		t.eq(s.phase, "Failed", "failed")
		local failed = nil
		for _, e in last do
			if e.kind == "NightFailed" then
				failed = e
			end
		end
		t.ok(failed ~= nil and failed.data.reason == "QuotaShort", "reason")
		t.eq((Night.result(s) :: any).cleared, false, "not cleared")
	end)

	t.test("a lost crew fails the night", function()
		local s = Night.new(Config, params())
		for _, id in s.order do
			s.crew[id].alive = false
		end
		local e = Night.step(s, input(OUT))
		local reason = nil
		for _, x in e do
			if x.kind == "NightFailed" then
				reason = x.data.reason
			end
		end
		t.eq(reason, "CrewLost", "crew lost")
	end)

	t.test("throwing back keeps the hold empty; a full hold releases", function()
		local s = Night.new(Config, params())
		local events = fishOnce(s, OUT, function()
			return false
		end)
		t.eq(#s.hold, 0, "nothing kept")
		t.ok((kindsOf(events).Released or 0) > 0, "released")
	end)

	t.test("the teaching night forces a wrong fish by the Nth hook, and kept wrong counts triple", function()
		local s = Night.new(
			Config,
			params({ night = 2, rules = { "Hum", "WrongCatch" }, newRules = { "WrongCatch" }, playerIds = { 1 } })
		)
		local sawWrong = false
		local keptWrongPoints = 0
		for _ = 1, 10 do
			fishOnce(s, OUT, function(c)
				if c.wrong then
					sawWrong = true
					keptWrongPoints += c.points * Config.Fishing.wrongPointsMult
				end
				return true
			end)
			if s.hooked >= Config.Fishing.teachWrongByCatch then
				break
			end
		end
		t.ok(sawWrong, "a wrong fish by catch " .. Config.Fishing.teachWrongByCatch)
		t.ok(s.keptWrong >= 1, "kept wrong counted")
		t.ok(s.attn.floor >= Config.Attention.keptWrongFloor, "attention floor rose")
		local expected = 0
		for _, c in s.hold do
			expected += if c.wrong then c.points * Config.Fishing.wrongPointsMult else c.points
		end
		Night.step(s, input(AT_DOCK, { { kind = "Bank", player = 1 } }))
		t.eq(s.quota.banked, expected, "banked value counts wrong fish triple")
		t.ok(keptWrongPoints > 0, "wrong points")
	end)

	t.test("no wrong fish on a night without the rule", function()
		local s = Night.new(Config, params({ playerIds = { 1, 2, 3, 4 } }))
		for _ = 1, 4 do
			fishOnce(s, OUT, function(c)
				t.ok(not c.wrong, "wrong fish on night 1")
				return true
			end)
			s.hold = {}
		end
	end)

	t.test("Kept and Caught never reveal a wrong fish", function()
		local s = Night.new(
			Config,
			params({ night = 2, rules = { "Hum", "WrongCatch" }, newRules = { "WrongCatch" }, playerIds = { 1 } })
		)
		for _ = 1, 3 do
			for _, e in fishOnce(s, OUT) do
				if e.kind == "Caught" then
					t.eq(e.data.catch.wrong, nil, "caught has no wrong flag")
				elseif e.kind == "Kept" then
					t.ok(e.data.points <= 3, "kept shows book points only")
				end
			end
			s.hold = {}
		end
	end)

	t.test("lantern burns, refills only at the dock, motor toggles", function()
		local s = Night.new(Config, params({ rules = {}, newRules = {} })) -- no rules: attention cannot bring a Hum
		t.ok(s.lantern.on, "every night starts with the lantern lit")
		Night.step(s, input(OUT, {}, 1))
		for _ = 1, 300 do
			Night.step(s, input(OUT, {}, 1))
		end
		t.ok(s.lantern.oil < 0.5, "burned")
		Night.step(s, input(OUT, { { kind = "RefillOil", player = 1 } }))
		t.ok(s.lantern.oil < 0.5, "no refill out on the lake")
		Night.step(s, input(AT_DOCK, { { kind = "RefillOil", player = 1 } }))
		t.ok(s.lantern.oil > 0.99, "refilled at the dock")
		local e = Night.step(s, input(OUT, { { kind = "ToggleMotor", player = 2 } }))
		t.eq(kindsOf(e).MotorChanged, 1, "motor event")
		t.ok(s.motorOn, "motor on")
	end)

	t.test("attention rises with the motor and thins the chorus; the dock drains it", function()
		local s = Night.new(Config, params())
		Night.step(s, input(OUT, { { kind = "ToggleMotor", player = 1 } }))
		local bands = {}
		for _ = 1, 60 do
			for _, e in Night.step(s, input(OUT, {}, 1)) do
				if e.kind == "Chorus" then
					table.insert(bands, e.data.band)
				end
			end
		end
		t.ok(#bands >= 2 and bands[1] == 2, "chorus thinned: " .. table.concat(bands, ","))
		t.ok(s.chorus < 3, "not full")
		Night.step(s, input(OUT, { { kind = "ToggleMotor", player = 1 } }))
		for _ = 1, 60 do
			Night.step(s, input(AT_DOCK, {}, 1))
		end
		t.eq(s.attn.value, 0, "drained at the dock")
		t.eq(s.chorus, 3, "full chorus again")
	end)

	t.test("dead players and unknown players are ignored; callouts pass through", function()
		local s = Night.new(Config, params())
		s.crew[2].alive = false
		local e = Night.step(
			s,
			input(OUT, {
				{ kind = "ToggleLantern", player = 2 },
				{ kind = "ToggleLantern", player = 99 },
				{ kind = "Callout", player = 1, text = "HoldStill" },
			})
		)
		t.ok(s.lantern.on, "dead and unknown cannot act (it starts lit and stays lit)")
		t.eq(kindsOf(e).Callout, 1, "callout")
	end)

	t.test("supplies are ignored (the pick was cut)", function()
		local s = Night.new(Config, params({ supplies = { "OilCan", "BigCooler", "LuckyLure", "TrimmedWick" } }))
		t.eq(s.lantern.refills, Config.Lantern.refillsPerNight, "no extra can")
		t.eq(s.holdMax, Config.Fishing.holdMax, "no bigger hold")
		t.eq(s.biteMult, 1, "no lucky lure")
		t.eq(s.lantern.burnMult, 1, "no trimmed wick")
	end)

	t.test("same seed and inputs give the same night", function()
		local function play()
			local s = Night.new(Config, params({ night = 2, rules = { "Hum", "WrongCatch" }, newRules = {} }))
			local log = {}
			for _ = 1, 3 do
				for _, e in fishOnce(s, OUT) do
					table.insert(log, e.kind .. (if e.data and e.data.catch then e.data.catch.species else ""))
				end
				s.hold = {}
			end
			return table.concat(log, ",")
		end
		t.eq(play(), play(), "replay")
	end)

	t.test("view has every NightView field", function()
		local s = Night.new(Config, params())
		Night.step(s, input(OUT))
		local v = Night.view(s)
		for _, k in
			{
				"night",
				"mode",
				"difficulty",
				"phase",
				"clock",
				"timeLeft",
				"quota",
				"banked",
				"hold",
				"holdMax",
				"oil",
				"refills",
				"lanternOn",
				"motorOn",
				"chorus",
				"flood",
				"safe",
				"rules",
				"players",
			}
		do
			t.ok((v :: any)[k] ~= nil, "view." .. k)
		end
		t.eq(#v.players, 2, "players")
		t.eq(v.players[1].fishing, "Idle", "fishing phase")
		t.eq(v.safe, false, "out on the lake")
	end)
end
