-- The Lake Wakes (entities/Finale) inside Core.Night: the bell at 4 AM, the silent lake,
-- the locked lantern and its oil clock, stopping too long, the dark, waving, Neighbor boats
-- and false beacons, home with the owner's fish, and dawn without it.
return function(t, Shared)
	local Night = require(Shared.Core.Night)
	local Config = require(Shared.Config)
	local L = Config.Lake
	local F = Config.Rules.Finale

	local OUT = { x = 0, z = L.dockEnd.z + 300 }
	local AT_DOCK = { x = L.dockEnd.x, z = L.dockEnd.z }
	local MOVING = { x = 0, z = 6 }

	-- A Config copy with no hazards (for tests about stillness, oil and waving).
	local Calm = table.clone(Config)
	Calm.Rules = table.clone(Config.Rules)
	Calm.Rules.Finale = table.clone(Config.Rules.Finale)
	Calm.Rules.Finale.hazardMin = 5000 -- off the lake: never placed
	Calm.Rules.Finale.hazardMax = 5001
	Calm.Rules.Finale.crossCount = 0 -- M8: the boat across the bow is the nearest; none here

	local function params(over)
		local p = {
			seed = 515,
			night = 5,
			mode = "Story",
			difficulty = "Normal",
			playerIds = { 1, 2 },
			rules = { "Finale" },
			newRules = { "Finale" },
			amendments = {},
			real = 0,
			fake = 0,
			quietGap = 30,
			quota = 1,
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
			if s.phase == "Cleared" or s.phase == "Failed" then
				break
			end
		end
	end

	local function all(events, kind, entity)
		local out = {}
		for _, e in events do
			if e.kind == kind and (entity == nil or e.entity == entity) then
				table.insert(out, e)
			end
		end
		return out
	end

	local function steepleCat(wrong)
		local traits = table.clone(Config.Fish.SteepleCat.traits)
		if wrong then
			traits.glow = true
		end
		return {
			species = "SteepleCat",
			points = 3,
			wrong = wrong == true,
			tier = if wrong then 1 else 0,
			traits = traits,
		}
	end

	-- Steps a Finale night (moving, on the water) to just after the bell.
	local function toBell(s, sink)
		stepFor(s, s.finaleAt + 0.15 - s.clock.elapsed, { vel = MOVING }, sink)
	end

	t.test("the bell rings at 4 AM: cue, silence, lantern lit and locked, oil as the clock", function()
		local s = Night.new(Config, params())
		local events = {}
		stepFor(s, s.finaleAt - 1, { vel = MOVING }, events)
		t.eq(#all(events, "EntityCue", "Finale"), 0, "no bell before 4 AM")
		t.eq(s.phase, "Night", "still night")
		toBell(s, events)
		local cue = all(events, "EntityCue", "Finale")[1]
		t.ok(cue ~= nil and cue.data.bell == true, "the bell is the cue")
		t.ok(math.abs(s.finaleAt - (F.hour - 22) / 7 * Config.Night.realSeconds) < 1e-6, "4 AM")
		t.eq(s.phase, "Finale", "phase")
		t.eq(s.chorus, 0, "every water sound stops")
		t.ok(s.lantern.on and s.lantern.lockedOn, "locked on")
		t.ok(s.lantern.oil > 0.95, "refilled")
		local refused = Night.step(s, input({ vel = MOVING, intents = { { kind = "ToggleLantern", player = 1 } } }))
		t.ok(s.lantern.on, "cannot be put out")
		t.eq(#all(refused, "LanternChanged"), 0, "no change")
		t.eq(Night.view(s).phase, "Finale", "view phase")
	end)

	t.test("moving keeps everyone; sitting still takes someone, not before the warning", function()
		local s = Night.new(Calm, params({ playerIds = { 1, 2, 3 } }))
		local events = {}
		toBell(s, events)
		-- Polish round 3: oilSeconds is 23, so the whole test must end before the lantern runs
		-- dry (10 s moving + two still spells, about 18.4 s).
		stepFor(s, 10, { vel = MOVING }, events)
		t.eq(#all(events, "PlayerDied"), 0, "moving: nobody taken")
		local still = {}
		stepFor(s, F.stopLimit - 0.3, {}, still)
		t.eq(#all(still, "PlayerDied"), 0, "not before stopLimit")
		stepFor(s, 0.5, {}, still)
		local died = all(still, "PlayerDied")
		t.eq(#died, 1, "one taken")
		t.eq(died[1].data.text, "Death.Finale.Still", "death card")
		t.eq(#all(still, "EntityStrike", "Finale"), 1, "a strike, not the outcome")
		t.eq(#all(still, "EntityFail", "Finale"), 0, "the finale goes on")
		stepFor(s, F.stopLimit + 0.2, {}, still)
		t.eq(#all(still, "PlayerDied"), 2, "and again")
	end)

	t.test("no strike lands before the bell's warning time, even sitting still", function()
		local s = Night.new(Calm, params({ warningScale = 1.4 }))
		local events = {}
		stepFor(s, s.finaleAt + 0.15, {}, events)
		stepFor(s, F.warn * 1.4 - 0.3, {}, events)
		t.eq(#all(events, "PlayerDied"), 0, "held until warn x scale")
	end)

	t.test("the last player taken is the finale's fail and the night is lost", function()
		local s = Night.new(Calm, params({ playerIds = { 1 } }))
		local events = {}
		toBell(s, events)
		stepFor(s, F.warn + F.stopLimit * 1.0 + 1, {}, events)
		t.eq(#all(events, "EntityFail", "Finale"), 1, "fail")
		t.eq(#all(events, "EntityStrike", "Finale"), 0, "no strike for the last one")
		t.eq(s.phase, "Failed", "night failed")
		t.eq(all(events, "NightFailed")[1].data.reason, "CrewLost", "crew lost")
	end)

	t.test("the locked lantern runs dry after oilSeconds and the dark takes someone", function()
		local s = Night.new(Calm, params({ playerIds = { 1, 2, 3 } }))
		local events = {}
		toBell(s, events)
		-- Keep clear of hazards: a hazard can only strike near the boat, and the boat stays put far away.
		local before = #all(events, "PlayerDied")
		stepFor(s, F.oilSeconds - 1, { vel = MOVING }, events)
		t.ok(s.lantern.on, "still lit before oilSeconds")
		stepFor(s, 1.5, { vel = MOVING }, events)
		t.ok(not s.lantern.on, "dry")
		local dark = 0
		for _, e in all(events, "PlayerDied") do
			if e.data.text == "Death.Finale.Dark" then
				dark += 1
			end
		end
		t.ok(dark >= 1 and #all(events, "PlayerDied") > before, "the dark takes someone")
	end)

	t.test("waving on the way home takes the waver", function()
		local s = Night.new(Calm, params())
		local events = {}
		toBell(s, events)
		stepFor(s, F.warn + 0.2, { vel = MOVING }, events)
		local e = Night.step(s, input({ vel = MOVING, intents = { { kind = "Wave", player = 2 } } }))
		local died = all(e, "PlayerDied")
		t.eq(#died, 1, "taken")
		t.eq(died[1].player, 2, "the waver")
		t.eq(died[1].data.text, "Death.Finale.Waved", "card")
	end)

	t.test("Neighbor boats and false beacons show up on a fast clock and take the helm up close", function()
		local s = Night.new(Config, params({ playerIds = { 1, 2 } }))
		local events = {}
		toBell(s, events)
		stepFor(s, F.warn + F.neighborEvery * 2 + 0.5, { vel = MOVING }, events)
		local appear = {}
		for _, e in all(events, "EntityMoved", "Finale") do
			if e.data.appear then
				table.insert(appear, e)
			end
		end
		t.ok(#appear >= 2, "two or more hazards in " .. tostring(F.neighborEvery * 2) .. " s")
		for _, e in appear do
			local d = math.sqrt((e.data.pos.x - OUT.x) ^ 2 + (e.data.pos.z - OUT.z) ^ 2)
			local side = d >= F.hazardMin - 1 and d <= F.hazardMax + 1
			local ahead = d >= F.aheadMin - 1 and d <= F.aheadMax + 1
			t.ok(side or ahead, "placed in range (" .. math.floor(d) .. ")")
		end
		-- Sail onto the newest live hazard.
		local h = s.rules[1].state.hazards[#s.rules[1].state.hazards]
		t.ok(h ~= nil, "a live hazard")
		-- An earlier boat may already have drifted in and taken the helm: then the next seat steers.
		local helm = if s.crew[1].alive then 1 else 2
		local hit = {}
		stepFor(s, 0.3, { pos = { x = h.pos.x, z = h.pos.z }, vel = MOVING }, hit)
		local died = all(hit, "PlayerDied")
		t.eq(#died, 1, "taken up close")
		t.eq(died[1].player, helm, "the helm")
		local want = if h.form == "Boat" then "Death.Finale.Closed" else "Death.Finale.Beacon"
		t.eq(died[1].data.text, want, "card for the form")
	end)

	t.test(
		"a run home from the steeple shows three or more hazards, two ahead of the bow (one across it), a beacon to the side, none on the way home",
		function()
			local N = Config.Rules.Neighbor
			local Rule = require(Shared.Core.entities.Finale)
			local LakeMap = require(Shared.Core.LakeMap)
			local dock = Config.Lake.dockEnd
			for seed = 1, 20 do
				local s = Night.new(Config, params({ seed = seed, playerIds = { 1, 2, 3, 4 } }))
				local start = Config.Lake.steeple
				toBell(s)
				-- Motor straight home at full speed from the steeple, about 30 s to the light.
				local pos = { x = start.x, z = start.z }
				local dx, dz = dock.x - start.x, dock.z - start.z
				local len = math.sqrt(dx * dx + dz * dz)
				local vel = { x = dx / len * Config.Boat.motorSpeed, z = dz / len * Config.Boat.motorSpeed }
				local boats, beacons, ahead, sideBeacons, crosses = 0, 0, 0, 0, 0
				for _ = 1, 400 do -- 40 s
					local e = Night.step(s, input({ pos = { x = pos.x, z = pos.z }, vel = vel }))
					for _, ev in all(e, "EntityMoved", "Finale") do
						if ev.data.appear then
							local p = ev.data.pos
							if ev.data.form == "Boat" then
								boats += 1
							else
								beacons += 1
							end
							local kill = if ev.data.form == "Boat" then N.killDist else N.falseBeaconKill
							local off = Rule.distToSegment(p, pos, dock)
							t.ok(off >= kill + F.hazardClear - 1e-6, "seed " .. seed .. ": clear of the way home")
							local d = math.sqrt((p.x - pos.x) ^ 2 + (p.z - pos.z) ^ 2)
							-- Angle off the line home (the bow line of a boat heading home).
							local hx, hz = dock.x - pos.x, dock.z - pos.z
							local cosA = ((p.x - pos.x) * hx + (p.z - pos.z) * hz) / (d * math.sqrt(hx * hx + hz * hz))
							local angle = math.acos(math.clamp(cosA, -1, 1))
							t.ok(angle > 0.05, "seed " .. seed .. ": never dead ahead")
							local isAhead = d >= F.aheadMin - 1
								and d <= F.aheadMax + 1
								and angle >= F.aheadAngleMin - 1e-3
								and angle <= F.aheadAngleMax + 1e-3
							local isSide = d >= F.hazardMin - 1
								and d <= F.hazardMax + 1
								and angle >= F.hazardAngleMin - 1e-3
								and angle <= F.hazardAngleMax + 1e-3
							-- M8: across the bow, crossAlong down the way home and just past the
							-- clearance off it (the nearest any hazard is placed).
							local along = d * cosA
							local clear = kill + F.hazardClear
							local isCross = ev.data.form == "Boat"
								and along >= F.crossAlong[1] - 1e-3
								and along <= F.crossAlong[2] + 1e-3
								and off <= clear + F.crossExtra + 0.1
							t.ok(
								isAhead or isSide or isCross,
								"seed " .. seed .. ": ahead, across the bow or to the side"
							)
							if isAhead or isCross then
								ahead += 1
							end
							if isCross then
								crosses += 1
								-- Never within kill distance plus hazardClear of the boat either.
								t.ok(d >= clear, "seed " .. seed .. ": the crossing boat is placed clear of the boat")
							end
							if ev.data.form == "FalseBeacon" and isSide then
								-- Rowing for it leaves the way home: it sits well off the line.
								sideBeacons += 1
							end
						end
					end
					if s.phase ~= "Finale" or LakeMap.isSafe(Config, pos) then
						break
					end
					pos = { x = pos.x + vel.x * 0.1, z = pos.z + vel.z * 0.1 }
				end
				t.ok(boats + beacons >= 3, "seed " .. seed .. ": three or more hazards (" .. (boats + beacons) .. ")")
				t.ok(boats >= 2, "seed " .. seed .. ": two or more boats (" .. boats .. ")")
				t.ok(ahead >= 2, "seed " .. seed .. ": two or more ahead of the bow (" .. ahead .. ")")
				t.ok(sideBeacons >= 1, "seed " .. seed .. ": a false beacon off to the side (" .. sideBeacons .. ")")
				t.ok(crosses >= 1, "seed " .. seed .. ": a boat across the bow (" .. crosses .. ")")
				t.eq(s.rules[1].state.crossPlaced, F.crossCount, "seed " .. seed .. ": placed across the bow once")
			end
		end
	)

	t.test("home with the Steeple Cat aboard: pass, hold banked, night cleared at once", function()
		local s = Night.new(Config, params({ quota = 3 }))
		local events = {}
		toBell(s, events)
		table.insert(s.hold, steepleCat(false))
		stepFor(s, 1, { pos = AT_DOCK }, events)
		t.eq(#all(events, "EntityPass", "Finale"), 1, "pass")
		t.eq(#all(events, "Banked"), 1, "the owner takes the hold")
		t.eq(s.phase, "Cleared", "cleared before dawn")
		t.ok(s.clock.elapsed < Config.Night.realSeconds, "before 5 AM")
		local r = Night.result(s)
		t.ok(r ~= nil and r.cleared, "result")
	end)

	t.test("a wrong Steeple Cat is not the owner's fish", function()
		local s = Night.new(Config, params({ quota = 1 }))
		toBell(s)
		table.insert(s.cooler, steepleCat(true))
		s.quota.banked = 9
		local events = {}
		stepFor(s, 400, { pos = AT_DOCK }, events)
		t.eq(#all(events, "EntityPass", "Finale"), 0, "no pass")
		t.eq(s.phase, "Failed", "lost at dawn")
		t.eq(all(events, "NightFailed")[1].data.reason, "SpecialOrder", "reason")
	end)

	t.test("a Steeple Cat banked earlier counts the moment the boat is home", function()
		local s = Night.new(Config, params({ quota = 3 }))
		table.insert(s.cooler, steepleCat(false))
		s.quota.banked = 3
		local events = {}
		stepFor(s, s.finaleAt + 1, { pos = AT_DOCK }, events)
		t.eq(#all(events, "EntityPass", "Finale"), 1, "pass at the bell")
		t.eq(s.phase, "Cleared", "cleared")
	end)

	t.test("home with the cat but short of quota: safe, and the night fails at dawn", function()
		local s = Night.new(Config, params({ quota = 30 }))
		toBell(s)
		table.insert(s.hold, steepleCat(false))
		local events = {}
		stepFor(s, 400, { pos = AT_DOCK }, events)
		t.eq(#all(events, "EntityPass", "Finale"), 1, "pass")
		t.eq(#all(events, "PlayerDied"), 0, "safe in the light")
		t.eq(all(events, "NightFailed")[1].data.reason, "QuotaShort", "short")
	end)

	t.test("the bell lets director rules go and the director stops", function()
		local s = Night.new(Config, params({ rules = { "Hum", "Neighbor", "Finale" } }))
		stepFor(s, s.finaleAt - 3, { vel = MOVING })
		local cue = Night.debugForce(s, "Hum", {})
		t.eq(#all(cue, "EntityCue", "Hum"), 1, "the Hum starts")
		local events = {}
		stepFor(s, 3.3, {}, events)
		local passes = all(events, "EntityPass", "Hum")
		t.eq(#passes, 1, "the Hum is let go")
		t.eq(passes[1] and passes[1].data.endedBy, "Finale", "by the bell")
		s = Night.new(Config, params({ rules = { "Hum", "Neighbor", "Finale" }, real = 12, fake = 12 }))
		toBell(s)
		local after = {}
		stepFor(s, 40, { vel = MOVING }, after)
		local cues = 0
		for _, e in all(after, "EntityCue") do
			if e.entity ~= "Finale" then
				cues += 1
			end
		end
		t.eq(cues, 0, "no new director scare after the bell")
		t.eq(#all(after, "Fakeout"), 0, "no fake-outs after the bell")
	end)

	t.test("no real scare starts within the late cutoff before the bell", function()
		for seed = 1, 40 do
			local s = Night.new(
				Config,
				params({ seed = seed, rules = { "Hum", "Neighbor", "Knocking", "Watcher", "Finale" }, real = 8 })
			)
			for _ = 1, math.floor(s.finaleAt / 0.1) do
				Night.step(s, input({ vel = MOVING }))
			end
			for _, entry in s.director.entries do
				if entry.kind == "Spawn" then
					t.ok(entry.t <= s.finaleAt - Config.Director.lateCutoff + 0.11, "spawn too close to the bell")
				end
			end
		end
	end)

	t.test("debugForce rings the bell on any night", function()
		local s = Night.new(Config, params({ night = 1, rules = { "Hum" }, newRules = {} }))
		stepFor(s, 2, { vel = MOVING })
		local e = Night.debugForce(s, "Finale", nil)
		t.eq(#all(e, "EntityCue", "Finale"), 1, "cue")
		t.eq(s.phase, "Finale", "phase")
		t.eq(#Night.debugForce(s, "Finale", nil), 0, "only once")
	end)
end
