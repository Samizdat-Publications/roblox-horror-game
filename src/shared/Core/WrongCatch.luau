--!strict
-- Wrong Catch traits: a fish that is almost right. Exactly one trait differs from the
-- Field Guide. Tier 1 is obvious (a third eye, a glow, a blink), tier 2 is medium (an
-- extra back fin, the wrong tail, the wrong whisker count), tier 3 is subtle (one bar too
-- many or too few). Eyeshine is never the mutation: it is normal for the Walleye, so the
-- trap only works if the book stays true.
-- This module is only the traits; the rule's consequences live in entities/WrongCatch (M4).

local Types = require(script.Parent.Types)
local Rng = require(script.Parent.Rng)

type Traits = Types.Traits
type Tail = Types.Tail

local WrongCatch = {}

WrongCatch.TAILS = { "Forked", "Round", "Square", "Uneven" } :: { Tail }

-- Mutation kinds by tier. Each changes exactly one trait.
WrongCatch.KINDS = {
	{ "ThirdEye", "Glow", "Blink" },
	{ "ExtraDorsal", "WrongTail", "Barbels" },
	{ "Stripes" },
} :: { { string } }

-- Which trait each kind changes (for tests and the Field Guide check).
WrongCatch.TRAIT_OF = {
	ThirdEye = "eyes",
	Glow = "glow",
	Blink = "blinks",
	ExtraDorsal = "dorsal",
	WrongTail = "tail",
	Barbels = "barbels",
	Stripes = "stripes",
} :: { [string]: string }

WrongCatch.TRAIT_NAMES = { "eyes", "dorsal", "stripes", "barbels", "tail", "eyeshine", "glow", "blinks" }

function WrongCatch.copyTraits(t: Traits): Traits
	return {
		eyes = t.eyes,
		dorsal = t.dorsal,
		stripes = t.stripes,
		barbels = t.barbels,
		tail = t.tail,
		eyeshine = t.eyeshine,
		glow = t.glow,
		blinks = t.blinks,
	}
end

-- The Field Guide's traits for a species (a fresh copy).
function WrongCatch.bookTraits(cfg: any, species: string): Traits
	local fish = cfg.Fish[species]
	assert(fish ~= nil, "unknown species " .. tostring(species))
	return WrongCatch.copyTraits(fish.traits)
end

-- Returns traits with exactly one change for `tier` (clamped to 1..3), and the kind used.
function WrongCatch.mutate(cfg: any, rng: Rng.RngState, species: string, tier: number): (Traits, string)
	local t = WrongCatch.bookTraits(cfg, species)
	local kinds = WrongCatch.KINDS[math.clamp(math.floor(tier), 1, 3)]
	local kind = Rng.pick(rng, kinds)
	if kind == "ThirdEye" then
		t.eyes += 1
	elseif kind == "Glow" then
		t.glow = true
	elseif kind == "Blink" then
		t.blinks = true
	elseif kind == "ExtraDorsal" then
		t.dorsal += 1
	elseif kind == "WrongTail" then
		local others: { Tail } = {}
		for _, tail in WrongCatch.TAILS do
			if tail ~= t.tail then
				table.insert(others, tail)
			end
		end
		t.tail = Rng.pick(rng, others)
	elseif kind == "Barbels" then
		-- Two whiskers more, or two fewer if it has whiskers to lose.
		if t.barbels >= 2 and Rng.next(rng) < 0.5 then
			t.barbels -= 2
		else
			t.barbels += 2
		end
	elseif kind == "Stripes" then
		-- One bar too many, or one too few if it has bars.
		if t.stripes >= 1 and Rng.next(rng) < 0.5 then
			t.stripes -= 1
		else
			t.stripes += 1
		end
	end
	return t, kind
end

-- The names of traits that differ from the Field Guide (empty for a true fish).
function WrongCatch.diff(cfg: any, species: string, traits: Traits): { string }
	local book = cfg.Fish[species].traits
	local out: { string } = {}
	for _, name in WrongCatch.TRAIT_NAMES do
		if (traits :: any)[name] ~= book[name] then
			table.insert(out, name)
		end
	end
	return out
end

-- True when every trait matches the Field Guide.
function WrongCatch.matchesBook(cfg: any, species: string, traits: Traits): boolean
	return #WrongCatch.diff(cfg, species, traits) == 0
end

return WrongCatch
