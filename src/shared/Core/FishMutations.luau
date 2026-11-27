--!strict
-- FishMutations (Wrong Catch traits): a fish that is almost right. Exactly one trait differs from the
-- Field Guide, and it is always one you can see at a glance on a phone (design change
-- 11/26/2026): tier 1 is obvious (a glow, a third eye), tier 2 is medium (the wrong tail
-- shape, an extra back fin), tier 3 is subtle (it blinks, one eye looks the wrong way, or a
-- fin is on the wrong side). Counts that need counting (bars, whiskers) are never the
-- mutation. Eyeshine is never the mutation either: it is normal for the Walleye, so the
-- trap only works if the book stays true.
-- This module is only the traits; the rule's consequences live in entities/WrongCatch (M4).

local Types = require(script.Parent.Types)
local Rng = require(script.Parent.Rng)

type Traits = Types.Traits
type Tail = Types.Tail

local FishMutations = {}

FishMutations.TAILS = { "Forked", "Round", "Square", "Uneven" } :: { Tail }

-- Mutation kinds by tier. Each changes exactly one trait.
FishMutations.KINDS = {
	{ "Glow", "ThirdEye" },
	{ "WrongTail", "ExtraDorsal" },
	{ "Blink", "WrongEyeDir", "FlipFin" },
} :: { { string } }

-- Which trait each kind changes (for tests and the Field Guide check).
FishMutations.TRAIT_OF = {
	ThirdEye = "eyes",
	Glow = "glow",
	Blink = "blinks",
	ExtraDorsal = "dorsal",
	WrongTail = "tail",
	WrongEyeDir = "wrongEyeDir",
	FlipFin = "flipFin",
} :: { [string]: string }

FishMutations.TRAIT_NAMES =
	{ "eyes", "dorsal", "stripes", "barbels", "tail", "eyeshine", "glow", "blinks", "wrongEyeDir", "flipFin" }

function FishMutations.copyTraits(t: Traits): Traits
	return {
		eyes = t.eyes,
		dorsal = t.dorsal,
		stripes = t.stripes,
		barbels = t.barbels,
		tail = t.tail,
		eyeshine = t.eyeshine,
		glow = t.glow,
		blinks = t.blinks,
		wrongEyeDir = t.wrongEyeDir == true,
		flipFin = t.flipFin == true,
	}
end

-- The Field Guide's traits for a species (a fresh copy).
function FishMutations.bookTraits(cfg: any, species: string): Traits
	local fish = cfg.Fish[species]
	assert(fish ~= nil, "unknown species " .. tostring(species))
	return FishMutations.copyTraits(fish.traits)
end

-- Returns traits with exactly one change for `tier` (clamped to 1..3), and the kind used.
function FishMutations.mutate(cfg: any, rng: Rng.RngState, species: string, tier: number): (Traits, string)
	local t = FishMutations.bookTraits(cfg, species)
	local kinds = FishMutations.KINDS[math.clamp(math.floor(tier), 1, 3)]
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
		for _, tail in FishMutations.TAILS do
			if tail ~= t.tail then
				table.insert(others, tail)
			end
		end
		t.tail = Rng.pick(rng, others)
	elseif kind == "WrongEyeDir" then
		t.wrongEyeDir = true
	elseif kind == "FlipFin" then
		t.flipFin = true
	end
	return t, kind
end

-- The names of traits that differ from the Field Guide (empty for a true fish).
function FishMutations.diff(cfg: any, species: string, traits: Traits): { string }
	local book = cfg.Fish[species].traits
	local out: { string } = {}
	for _, name in FishMutations.TRAIT_NAMES do
		local a, b = (traits :: any)[name], book[name]
		if type(a) == "boolean" or type(b) == "boolean" then
			-- An absent flag means false (older traits tables have no tier 3 flags).
			a, b = a == true, b == true
		end
		if a ~= b then
			table.insert(out, name)
		end
	end
	return out
end

-- True when every trait matches the Field Guide.
function FishMutations.matchesBook(cfg: any, species: string, traits: Traits): boolean
	return #FishMutations.diff(cfg, species, traits) == 0
end

return FishMutations
