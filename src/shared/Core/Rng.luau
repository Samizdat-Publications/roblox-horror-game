--!strict
-- Seeded random numbers for the pure core.
-- Algorithm: Mulberry32 (a 32-bit counter run through a mixing hash), built only on
-- bit32 and an exact 32-bit multiply, so Lune and Roblox produce the same stream for the
-- same seed. Forks hash (seed, label) with FNV-1a and the Murmur3 finalizer.
-- A fork depends only on the parent's seed and the label, never on how many numbers the
-- parent has drawn, so adding a draw in one subsystem never shifts another.

export type RngState = {
	seed: number, -- the normalized 32-bit seed this stream started from
	state: number, -- the Mulberry32 counter, advanced on every draw
}

local Rng = {}

local TWO32 = 4294967296

-- (a * b) mod 2^32 for 32-bit unsigned a and b, exact in doubles (no product over 2^53).
local function mul32(a: number, b: number): number
	local alo = a % 65536
	local ahi = (a - alo) / 65536
	return (((ahi * b) % 65536) * 65536 + alo * b) % TWO32
end

local function normalize(seed: number): number
	assert(type(seed) == "number", "Rng seed must be a number")
	assert(seed == seed and seed ~= math.huge and seed ~= -math.huge, "Rng seed must be finite")
	return math.floor(seed) % TWO32
end

-- Murmur3 fmix32: spreads every input bit over the output.
local function fmix(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

function Rng.new(seed: number): RngState
	local s = normalize(seed)
	return { seed = s, state = s }
end

-- Uniform in [0, 1). Values are exact multiples of 2^-32.
function Rng.next(r: RngState): number
	local a = (r.state + 0x6D2B79F5) % TWO32
	r.state = a
	local t = mul32(bit32.bxor(a, bit32.rshift(a, 15)), bit32.bor(a, 1))
	t = bit32.bxor(t, (t + mul32(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % TWO32)
	t = bit32.bxor(t, bit32.rshift(t, 14))
	return t / TWO32
end

-- Integer in [lo, hi], both inclusive.
function Rng.int(r: RngState, lo: number, hi: number): number
	assert(lo == math.floor(lo) and hi == math.floor(hi), "Rng.int bounds must be integers")
	assert(lo <= hi, "Rng.int needs lo <= hi")
	return lo + math.floor(Rng.next(r) * (hi - lo + 1))
end

-- Real number in [lo, hi).
function Rng.range(r: RngState, lo: number, hi: number): number
	return lo + (hi - lo) * Rng.next(r)
end

function Rng.pick<T>(r: RngState, list: { T }): T
	local n = #list
	assert(n > 0, "Rng.pick on an empty list")
	return list[Rng.int(r, 1, n)]
end

-- Keys sort by type name, then by value, so the draw does not depend on table order.
local function keyLess(a: any, b: any): boolean
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return ta < tb
	end
	if ta == "number" or ta == "string" then
		return a < b
	end
	return tostring(a) < tostring(b)
end

-- Picks a key with probability weight / total. Keys with weight <= 0 are never picked.
function Rng.weighted<K>(r: RngState, weights: { [K]: number }): K
	local keys: { K } = {}
	local total = 0
	for k, w in weights do
		if w > 0 then
			table.insert(keys, k)
			total += w
		end
	end
	assert(#keys > 0 and total > 0, "Rng.weighted needs at least one positive weight")
	table.sort(keys, keyLess)
	local x = Rng.next(r) * total
	for _, k in keys do
		x -= weights[k]
		if x < 0 then
			return k
		end
	end
	return keys[#keys] -- only reachable through float rounding at the top end
end

-- An independent stream derived from this stream's seed and a label.
function Rng.fork(r: RngState, label: string): RngState
	local h = 2166136261 -- FNV-1a offset basis
	for i = 0, 3 do
		h = mul32(bit32.bxor(h, bit32.extract(r.seed, i * 8, 8)), 16777619)
	end
	for i = 1, #label do
		h = mul32(bit32.bxor(h, string.byte(label, i)), 16777619)
	end
	return Rng.new(fmix(h))
end

return Rng
