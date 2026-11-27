-- Core.FishTable and Core.FishMutations.
return function(t, Shared)
	local FishTable = require(Shared.Core.FishTable)
	local FishMutations = require(Shared.Core.FishMutations)
	local Rng = require(Shared.Core.Rng)
	local Config = require(Shared.Config)

	t.test("eight species, sorted", function()
		local s = FishTable.species(Config)
		t.eq(#s, 8, "count")
		for i = 2, #s do
			t.ok(s[i - 1] < s[i], "sorted")
		end
	end)

	t.test("picks follow zone weights and never a zero-weight fish", function()
		local r = Rng.new(4)
		for _, zone in Config.Zones do
			local w = FishTable.weights(Config, zone, 28)
			for _ = 1, 300 do
				local k = FishTable.pick(Config, r, zone, 28)
				t.ok((w[k] or 0) > 0, zone .. " picked " .. k)
			end
		end
		local counts, n = {}, 6000
		for _ = 1, n do
			local k = FishTable.pick(Config, r, "Shallows", 23)
			counts[k] = (counts[k] or 0) + 1
		end
		local w = FishTable.weights(Config, "Shallows", 23)
		local total = 0
		for _, x in w do
			total += x
		end
		for k, x in w do
			t.ok(math.abs((counts[k] or 0) / n - x / total) < 0.03, "share of " .. k)
		end
	end)

	t.test("the Steeple Cat only bites after 3 AM", function()
		t.eq(FishTable.weights(Config, "Steeple", 26.9).SteepleCat, nil, "not before 3")
		t.ok((FishTable.weights(Config, "Steeple", 27).SteepleCat or 0) > 0, "from 3 AM")
		t.eq(FishTable.weights(Config, "Shallows", 28).SteepleCat, nil, "only by the steeple")
	end)

	t.test("a wrong fish differs from the book in exactly one trait, never eyeshine", function()
		local r = Rng.new(31)
		for _, species in FishTable.species(Config) do
			for tier = 1, 3 do
				for _ = 1, 60 do
					local traits, kind = FishMutations.mutate(Config, r, species, tier)
					local d = FishMutations.diff(Config, species, traits)
					t.eq(#d, 1, species .. " tier " .. tier .. " changed " .. #d .. " traits")
					t.ok(d[1] ~= "eyeshine", "eyeshine mutated")
					t.ok(d[1] ~= "stripes" and d[1] ~= "barbels", "a count mutated")
					t.eq(d[1], FishMutations.TRAIT_OF[kind], "kind names its trait")
					t.ok(not FishMutations.matchesBook(Config, species, traits), "fails the book")
				end
			end
		end
	end)

	t.test("tiers: 1 obvious, 2 medium, 3 subtle, all visible at a glance", function()
		local r = Rng.new(5)
		local seen = { {}, {}, {} }
		for tier = 1, 3 do
			for _ = 1, 300 do
				local _, kind = FishMutations.mutate(Config, r, "YellowPerch", tier)
				seen[tier][kind] = true
			end
		end
		t.ok(seen[1].ThirdEye and seen[1].Glow and not seen[1].Blink, "tier 1 kinds")
		t.ok(seen[2].ExtraDorsal and seen[2].WrongTail, "tier 2 kinds")
		t.ok(seen[3].Blink and seen[3].WrongEyeDir and seen[3].FlipFin and not seen[3].Glow, "tier 3 kinds")
		for tier = 1, 3 do
			t.ok(not seen[tier].Stripes and not seen[tier].Barbels, "never a count to check")
		end
	end)

	t.test("the walleye keeps its eyeshine when wrong", function()
		local r = Rng.new(9)
		for tier = 1, 3 do
			for _ = 1, 100 do
				local traits = FishMutations.mutate(Config, r, "Walleye", tier)
				t.eq(traits.eyeshine, true, "walleye eyeshine")
			end
		end
	end)

	t.test("mutate never edits the Field Guide", function()
		local r = Rng.new(2)
		for _ = 1, 200 do
			FishMutations.mutate(Config, r, "Bullhead", 2)
		end
		t.eq(Config.Fish.Bullhead.traits.barbels, 4, "book barbels")
		t.eq(Config.Fish.Bullhead.traits.tail, "Square", "book tail")
		t.ok(
			FishMutations.matchesBook(Config, "Bullhead", FishMutations.bookTraits(Config, "Bullhead")),
			"book matches"
		)
	end)
end
