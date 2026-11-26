-- Core.Fishing: cast rules, bite window, the reel bar, snap, slack, catch, privacy.
return function(t, Shared)
	local Fishing = require(Shared.Core.Fishing)
	local Rng = require(Shared.Core.Rng)
	local Config = require(Shared.Config)
	local F = Config.Fishing

	local function opts(over)
		local o = { boatSpeed = 0, safe = false, zone = "Shallows", hour = 23 }
		for k, v in over or {} do
			o[k] = v
		end
		return o
	end

	local function runUntil(f, r, phase, seconds)
		local events = {}
		for _ = 1, math.floor(seconds / 0.1) do
			for _, e in Fishing.step(Config, f, 0.1, r, 1) do
				table.insert(events, e)
			end
			if f.phase == phase then
				break
			end
		end
		return events
	end

	t.test("cast needs an idle line, a still boat, and open water", function()
		local r = Rng.new(1)
		local f = Fishing.new()
		local e = Fishing.cast(Config, f, r, 1, 0.5, opts({ boatSpeed = F.castSpeedLimit + 1 }))
		t.eq(e[1].data.why, "Moving", "moving boat")
		e = Fishing.cast(Config, f, r, 1, 0.5, opts({ safe = true }))
		t.eq(e[1].data.why, "DockLight", "no bites in the dock light")
		e = Fishing.cast(Config, f, r, 1, 0.5, opts())
		t.eq(e[1].kind, "CastOut", "cast")
		t.eq(f.phase, "Waiting", "waiting")
		t.ok(f.timer >= F.biteMin and f.timer <= F.biteMax, "bite time in range")
		t.eq(#Fishing.cast(Config, f, r, 1, 0.5, opts()), 0, "already cast")
	end)

	t.test("bite comes, and is missed if not reeled in the window", function()
		local r = Rng.new(2)
		local f = Fishing.new()
		Fishing.cast(Config, f, r, 1, 1, opts())
		local e = runUntil(f, r, "Bite", F.biteMax + 1)
		t.eq(e[#e].kind, "Bite", "bite event")
		e = runUntil(f, r, "Idle", F.biteWindow + 0.5)
		t.eq(e[#e].kind, "HookLost", "lost")
		t.eq(e[#e].data.why, "Missed", "missed")
	end)

	t.test("lucky lure shortens the wait", function()
		local f = Fishing.new()
		Fishing.cast(Config, f, Rng.new(3), 1, 1, opts({ biteMult = 0.75 }))
		t.ok(f.timer <= F.biteMax * 0.75, "shorter")
	end)

	local function hooked(seed)
		local r = Rng.new(seed)
		local f = Fishing.new()
		Fishing.cast(Config, f, r, 1, 1, opts())
		runUntil(f, r, "Bite", F.biteMax + 1)
		Fishing.reel(Config, f, r, true)
		return f, r
	end

	t.test("reeling inside the band lands the fish", function()
		local landed = 0
		for seed = 1, 30 do
			local f, r = hooked(seed)
			t.eq(f.phase, "Reeling", "hooked")
			local caught = nil
			for _ = 1, 600 do
				Fishing.reel(Config, f, r, f.tension < f.center)
				for _, e in Fishing.step(Config, f, 0.1, r, 1) do
					if e.kind == "Caught" then
						caught = e
					end
				end
				if f.phase ~= "Reeling" then
					break
				end
			end
			if caught then
				landed += 1
				t.eq(f.phase, "Deciding", "deciding")
				t.eq(caught.data.catch.wrong, nil, "wrong flag never leaves the server")
				t.eq(caught.data.catch.tier, nil, "tier never leaves the server")
				t.ok(Config.Fish[caught.data.catch.species] ~= nil, "species")
			end
		end
		t.ok(landed >= 27, "a careful reeler lands nearly every fish: " .. landed)
	end)

	t.test("holding too long snaps the line", function()
		local f, r = hooked(4)
		local e = {}
		for _ = 1, 100 do
			for _, x in Fishing.step(Config, f, 0.1, r, 1) do
				table.insert(e, x)
			end
			if f.phase == "Idle" then
				break
			end
		end
		t.eq(e[#e].data.why, "Snap", "snapped")
	end)

	t.test("letting it run slack loses the fish", function()
		local f, r = hooked(5)
		Fishing.reel(Config, f, r, false)
		local e = runUntil(f, r, "Idle", 10)
		t.eq(e[#e].data.why, "Slack", "slack")
	end)

	t.test("band stays on the bar and its width follows fish size", function()
		local f, r = hooked(6)
		local i = math.clamp((f.catch :: any).points, 1, 3)
		t.eq(f.width, F.zoneWidth[i], "width by size")
		for _ = 1, 300 do
			Fishing.reel(Config, f, r, f.tension < f.center)
			Fishing.step(Config, f, 0.1, r, 1)
			if f.phase ~= "Reeling" then
				break
			end
			local lo, hi = Fishing.band(f)
			t.ok(lo >= 0 and hi <= 1, "band on the bar")
		end
	end)

	t.test("forced wrong catch is wrong; decide timer expires; take resets", function()
		local r = Rng.new(7)
		local f = Fishing.new()
		Fishing.cast(Config, f, r, 1, 1, opts({ forceWrong = true, wrongTier = 1 }))
		runUntil(f, r, "Bite", F.biteMax + 1)
		Fishing.reel(Config, f, r, true)
		t.ok((f.catch :: any).wrong, "wrong")
		t.eq((f.catch :: any).tier, 1, "tier")
		for _ = 1, 600 do
			Fishing.reel(Config, f, r, f.tension < f.center)
			Fishing.step(Config, f, 0.1, r, 1)
			if f.phase ~= "Reeling" then
				break
			end
		end
		if f.phase == "Deciding" then
			runUntil(f, r, "Never", F.decideSeconds + 0.5)
			t.ok(f.expired, "expired")
			local c = Fishing.take(f)
			t.ok(c ~= nil and c.wrong, "took the catch")
			t.eq(f.phase, "Idle", "idle after take")
		end
	end)

	t.test("cut and interrupt", function()
		local r = Rng.new(8)
		local f = Fishing.new()
		t.eq(#Fishing.cut(f, 1), 0, "nothing to cut")
		Fishing.cast(Config, f, r, 1, 1, opts())
		t.eq(Fishing.cut(f, 1)[1].data.why, "Cut", "cut")
		Fishing.cast(Config, f, r, 1, 1, opts())
		t.eq(Fishing.interrupt(f, 1, "Hum")[1].data.why, "Hum", "interrupted")
		t.eq(f.phase, "Idle", "idle")
	end)
end
