-- Core.Rng: determinism, bounds, forks, weights, and a pinned sequence that catches any
-- drift between Lune and Roblox.
return function(t, Shared)
	local Rng = require(Shared.Core.Rng)

	t.test("same seed gives the same stream", function()
		local a, b = Rng.new(42), Rng.new(42)
		for i = 1, 200 do
			t.eq(Rng.next(a), Rng.next(b), "draw " .. i)
		end
	end)

	t.test("different seeds give different streams", function()
		local a, b = Rng.new(1), Rng.new(2)
		local same = 0
		for _ = 1, 50 do
			if Rng.next(a) == Rng.next(b) then
				same += 1
			end
		end
		t.ok(same < 3, "seeds 1 and 2 matched " .. same .. " of 50 draws")
	end)

	t.test("pinned first five values for seed 12345", function()
		-- Mulberry32 reference values (checked against an independent Python version).
		local expected = { 4207900869, 1317490944, 2079646450, 3513001552, 2187978186 }
		local r = Rng.new(12345)
		for i, want in expected do
			t.eq(Rng.next(r) * 4294967296, want, "value " .. i)
		end
	end)

	t.test("next stays in [0, 1)", function()
		local r = Rng.new(7)
		for _ = 1, 5000 do
			local x = Rng.next(r)
			t.ok(x >= 0 and x < 1, "out of range: " .. x)
		end
	end)

	t.test("int stays inside inclusive bounds and hits both ends", function()
		local r = Rng.new(99)
		local seenLo, seenHi = false, false
		for _ = 1, 5000 do
			local x = Rng.int(r, -3, 4)
			t.ok(x >= -3 and x <= 4 and x == math.floor(x), "bad int " .. x)
			seenLo = seenLo or x == -3
			seenHi = seenHi or x == 4
		end
		t.ok(seenLo and seenHi, "never reached an end of the range")
		t.eq(Rng.int(r, 5, 5), 5, "single value range")
	end)

	t.test("range stays inside [lo, hi)", function()
		local r = Rng.new(5)
		for _ = 1, 5000 do
			local x = Rng.range(r, 10, 12.5)
			t.ok(x >= 10 and x < 12.5, "out of range: " .. x)
		end
	end)

	t.test("pick returns list members", function()
		local r = Rng.new(3)
		local list = { "a", "b", "c" }
		local seen = {}
		for _ = 1, 300 do
			local v = Rng.pick(r, list)
			t.ok(v == "a" or v == "b" or v == "c", "not a member: " .. tostring(v))
			seen[v] = true
		end
		t.ok(seen.a and seen.b and seen.c, "did not pick every member")
	end)

	t.test("weighted respects weights over many draws", function()
		local r = Rng.new(2024)
		local weights = { Rare = 1, Common = 6, Mid = 3, Never = 0 }
		local counts = { Rare = 0, Common = 0, Mid = 0, Never = 0 }
		local n = 20000
		for _ = 1, n do
			local k = Rng.weighted(r, weights)
			counts[k] += 1
		end
		t.eq(counts.Never, 0, "zero weight was picked")
		local function near(key, share)
			local got = counts[key] / n
			t.ok(math.abs(got - share) < 0.02, string.format("%s share %.3f, expected %.2f", key, got, share))
		end
		near("Rare", 0.1)
		near("Mid", 0.3)
		near("Common", 0.6)
	end)

	t.test("weighted does not depend on table construction order", function()
		local w1 = { b = 2, a = 1, c = 3 }
		local w2 = {}
		w2.c = 3
		w2.a = 1
		w2.b = 2
		local r1, r2 = Rng.new(11), Rng.new(11)
		for i = 1, 200 do
			t.eq(Rng.weighted(r1, w1), Rng.weighted(r2, w2), "draw " .. i)
		end
	end)

	t.test("fork is deterministic and independent of the parent's draws", function()
		local a = Rng.new(500)
		local f1 = Rng.fork(a, "director")
		for _ = 1, 37 do
			Rng.next(a)
		end
		local f2 = Rng.fork(a, "director")
		for i = 1, 100 do
			t.eq(Rng.next(f1), Rng.next(f2), "fork draw " .. i)
		end
	end)

	t.test("forks with different labels or seeds differ, and do not move the parent", function()
		local parent = Rng.new(500)
		local control = Rng.new(500)
		local fa = Rng.fork(parent, "fish")
		local fb = Rng.fork(parent, "rule:Hum")
		local fc = Rng.fork(Rng.new(501), "fish")
		local sameAB, sameAC = 0, 0
		for _ = 1, 100 do
			local x = Rng.next(fa)
			if x == Rng.next(fb) then
				sameAB += 1
			end
			if x == Rng.next(fc) then
				sameAC += 1
			end
		end
		t.ok(sameAB < 3, "labels fish and rule:Hum matched " .. sameAB .. " times")
		t.ok(sameAC < 3, "seeds 500 and 501 matched " .. sameAC .. " times")
		for i = 1, 50 do
			t.eq(Rng.next(parent), Rng.next(control), "parent moved by forking, draw " .. i)
		end
	end)

	t.test("seeds normalize to 32 bits", function()
		t.eq(Rng.next(Rng.new(4294967296 + 12345)), Rng.next(Rng.new(12345)), "2^32 + seed")
		t.eq(Rng.next(Rng.new(12345.7)), Rng.next(Rng.new(12345)), "fractional seed floors")
		local neg = Rng.new(-1)
		t.eq(neg.seed, 4294967295, "negative seed wraps")
	end)

	t.test("Config loads through Shared", function()
		local Config = require(Shared.Config)
		t.eq(Config.TITLE, "Don't Wave Back", "title")
	end)
end
