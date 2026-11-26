--!strict
-- Token bucket. Pure: the caller passes the current time (the server uses os.clock()).

export type Bucket = {
	capacity: number,
	perSec: number,
	tokens: number,
	last: number?, -- time of the last refill, nil until first use
}

local RateLimit = {}

function RateLimit.new(capacity: number, perSec: number): Bucket
	assert(capacity > 0 and perSec >= 0, "RateLimit needs capacity > 0 and perSec >= 0")
	return { capacity = capacity, perSec = perSec, tokens = capacity, last = nil }
end

local function refill(b: Bucket, now: number)
	if b.last == nil then
		b.last = now
		return
	end
	local elapsed = now - (b.last :: number)
	if elapsed > 0 then
		b.tokens = math.min(b.capacity, b.tokens + elapsed * b.perSec)
		b.last = now
	end
	-- Time going backwards (clock reset) refills nothing and keeps the old mark.
end

-- Takes `cost` tokens (default 1) if available. Returns true when allowed.
function RateLimit.take(b: Bucket, now: number, cost: number?): boolean
	refill(b, now)
	local c = cost or 1
	if b.tokens >= c then
		b.tokens -= c
		return true
	end
	return false
end

-- Tokens available at `now`, without taking any.
function RateLimit.peek(b: Bucket, now: number): number
	refill(b, now)
	return b.tokens
end

-- The buckets Net keeps per player, from cfg.Net.
function RateLimit.forPlayer(cfg: any): { [string]: Bucket }
	local N = cfg.Net
	return {
		Intent = RateLimit.new(N.intentBurst, N.intentPerSec),
		Gaze = RateLimit.new(math.max(1, N.gazeHz), N.gazeHz),
		BoatInput = RateLimit.new(math.max(1, N.boatHz), N.boatHz),
		Lobby = RateLimit.new(4, 2),
		Cosmetic = RateLimit.new(4, 2),
	}
end

return RateLimit
