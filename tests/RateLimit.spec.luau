-- Core.RateLimit: burst, refill rate, cap, clock going backwards, per-player buckets.
return function(t, Shared)
	local RateLimit = require(Shared.Core.RateLimit)
	local Config = require(Shared.Config)

	t.test("allows a burst up to capacity, then refuses", function()
		local b = RateLimit.new(3, 1)
		t.ok(RateLimit.take(b, 0), "1")
		t.ok(RateLimit.take(b, 0), "2")
		t.ok(RateLimit.take(b, 0), "3")
		t.ok(not RateLimit.take(b, 0), "4 refused")
	end)

	t.test("refills at perSec and caps at capacity", function()
		local b = RateLimit.new(2, 4)
		RateLimit.take(b, 10)
		RateLimit.take(b, 10)
		t.ok(not RateLimit.take(b, 10.1), "0.4 tokens is not enough")
		t.ok(RateLimit.take(b, 10.25), "one token after a quarter second")
		t.eq(RateLimit.peek(b, 100), 2, "capped")
	end)

	t.test("costs above one", function()
		local b = RateLimit.new(5, 1)
		t.ok(RateLimit.take(b, 0, 4), "cost 4")
		t.ok(not RateLimit.take(b, 0, 2), "only 1 left")
	end)

	t.test("a clock that goes backwards refills nothing", function()
		local b = RateLimit.new(1, 10)
		t.ok(RateLimit.take(b, 50), "first")
		t.ok(not RateLimit.take(b, 40), "time went back")
		t.ok(not RateLimit.take(b, 50.05), "still measured from 50")
		t.ok(RateLimit.take(b, 50.1), "refilled from the old mark")
	end)

	t.test("sustained spam is held to the rate", function()
		local b = RateLimit.new(Config.Net.intentBurst, Config.Net.intentPerSec)
		local allowed = 0
		for i = 0, 999 do
			if RateLimit.take(b, i * 0.01) then
				allowed += 1
			end
		end
		-- 10 seconds of 100 per second: burst plus rate times time, at most.
		t.ok(allowed <= Config.Net.intentBurst + Config.Net.intentPerSec * 10 + 1, "allowed " .. allowed)
		t.ok(allowed >= Config.Net.intentPerSec * 10, "not starved " .. allowed)
	end)

	t.test("forPlayer builds one bucket per client remote", function()
		local buckets = RateLimit.forPlayer(Config)
		for _, name in { "Intent", "Gaze", "BoatInput", "Lobby", "Book", "Cosmetic" } do
			t.ok(buckets[name] ~= nil, name)
		end
		t.eq(buckets.Intent.capacity, Config.Net.intentBurst, "intent burst")
		-- Toggling the book never spends the Lobby bucket (Start, Hello stay free).
		for _ = 1, 6 do
			RateLimit.take(buckets.Book, 0)
		end
		t.ok(not RateLimit.take(buckets.Book, 0), "book bucket spent")
		t.ok(RateLimit.take(buckets.Lobby, 0), "lobby bucket untouched")
	end)
end
