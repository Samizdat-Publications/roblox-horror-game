--!strict
-- The Lake Rules book (docs/DESIGN.md, The Lake Rules and Amendments).
--
--   Rulebook.NUMBERS[rule]                       -- 0 Water, 1 Hum, ... 6 Finale
--   Rulebook.ruleText(cfg, rule, variant?)       -- text id: "Rule.Hum" or "Rule.Hum.LanternLit"
--   Rulebook.taped(cfg, mode, night)             -- rules taped into the book by that night
--   Rulebook.page(cfg, rules, amendments)        -- the book's page, in rule order
--   Rulebook.amendments(cfg, opts)               -- { [RuleId] = variant } from the run seed
--   Rulebook.tapes(params)                       -- tape ids for a night's opening
--   Rulebook.deathText(rule, cause)              -- "Death.<Rule>.<Cause>"
--   Rulebook.deathCard(id)                       -- { text, rule, number, ruleText }
--   Rulebook.TEXT[id]                            -- the English for every id above
--
-- Amendment policies (cfg.Difficulty, cfg.Endless):
--   Normal, first run: by the book, then exactly one amendment, on night amendFromNight (5),
--     one amendable rule drawn from the run seed.
--   Normal, later runs: from night amendFromNight, each amendable rule taped in is amended
--     with chance amendChance (redrawn each night).
--   Nightmare and Endless: the same from Nightmare's amendFromNight (Endless: every night).
-- Everything is drawn from forks of the run seed, so a retried night keeps its page.
-- The Finale (Rule 6) and Wrong Catch have no amendments.

local Types = require(script.Parent.Types)
local Rng = require(script.Parent.Rng)

type RuleId = Types.RuleId
type NightParams = Types.NightParams

export type PageLine = {
	rule: string, -- RuleId, or "Water" for Rule 0
	number: number,
	text: string, -- text id of the printed rule
	amended: string?, -- text id of tonight's amendment, if any
}

export type DeathCard = {
	text: string, -- the death card's text id
	rule: string, -- RuleId or "Water"
	number: number,
	ruleText: string, -- text id of the rule it names
}

export type AmendOpts = {
	seed: number, -- the run seed
	difficulty: Types.Difficulty,
	mode: Types.Mode,
	night: number,
	rules: { RuleId }, -- rules active that night
	firstRun: boolean?,
}

local Rulebook = {}

Rulebook.NUMBERS = {
	Water = 0,
	Hum = 1,
	WrongCatch = 2,
	Neighbor = 3,
	Knocking = 4,
	Watcher = 5,
	Finale = 6,
} :: { [string]: number }

-- Amendable rules in a fixed order (draws never depend on table order).
Rulebook.AMENDABLE = { "Hum", "Neighbor", "Knocking", "Watcher" } :: { RuleId }

-- The English for every text id. Rule text is the owner's (docs/DESIGN.md).
Rulebook.TEXT = {
	["Rule.Water"] = "Rule 0. Stay in the boat. The water is not yours at night.",
	["Rule.Hum"] = "Rule 1. When the frogs stop all at once, stop reeling, cut the motor, put out the lantern, and hold still until they sing again.",
	["Rule.WrongCatch"] = "Rule 2. Check every catch against the Field Guide. If it is not in the book, throw it back. I do not care what it weighs.",
	["Rule.Neighbor"] = "Rule 3. There are no other boats on Blackwater Lake. If you see one, you did not. Never wave back. Never row toward a light that is not the dock beacon. Ours blinks twice.",
	["Rule.Knocking"] = "Rule 4. If something knocks three times on the hull, answer with two. Not one. Not three.",
	["Rule.Watcher"] = "Rule 5. Do not stare at the shore. Do not turn your back on it either. Keep it at the edge of your eye.",
	["Rule.Finale"] = "Rule 6. If the bell rings by itself, go home. Lights on. Do not stop. Bring my fish.",
	["Rule.Hum.LanternLit"] = "LEAVE THE LANTERN LIT. It hates the dark now.",
	["Rule.Knocking.AnswerOne"] = "ONE. Just one.",
	["Rule.Knocking.AnswerNone"] = "DO NOT ANSWER. Let it knock.",
	["Rule.Watcher.StareItDown"] = "STARE AT IT. Someone must. Do not look away first.",
	["Rule.Neighbor.NoWaveRowAway"] = "AND ROW AWAY FROM IT. Do not let it get any closer.",

	["Death.Water.Drag"] = "You left the boat. Rule 0.",
	["Death.Hum.Reeling"] = "You kept reeling while the frogs were quiet. Rule 1.",
	["Death.Hum.Motor"] = "The motor was running while the frogs were quiet. Rule 1.",
	["Death.Hum.Moving"] = "The boat kept moving while the frogs were quiet. Rule 1.",
	["Death.Hum.LanternLit"] = "The lantern was lit while the frogs were quiet. Rule 1.",
	["Death.Hum.LanternDark"] = "The lantern was dark. The book said to leave it lit. Rule 1.",
	["Death.Hum.Noise"] = "Something in the boat made noise while the frogs were quiet. Rule 1.",
	["Death.Neighbor.Waved"] = "You waved back. Rule 3.",
	["Death.Neighbor.Closed"] = "You let the other boat come close. Rule 3.",
	["Death.Neighbor.Beacon"] = "You rowed toward a light that did not blink twice. Rule 3.",
	["Death.Knocking.Sunk"] = "You answered the knocking wrong, and the boat went down. Rule 4.",
	["Death.Watcher.Reached"] = "You let the thing on the shore reach the water. Rule 5.",
	["Death.Finale.Still"] = "You stopped. The bell said go home. Rule 6.",
	["Death.Finale.Dark"] = "The lantern ran dry before you got home. Rule 6.",
	["Death.Finale.Waved"] = "You waved back on the way home. Rule 6.",
	["Death.Finale.Closed"] = "You let the other boat come close on the way home. Rule 6.",
	["Death.Finale.Beacon"] = "You followed the wrong light home. Rule 6.",
	["Death.Unknown"] = "The lake took you.",

	["Tape.Night1"] = "Night one. Quota's on the cooler. Rules are taped in the boat. Read them. Mostly it's just frogs out there. If the frogs quit, you quit too. That's all. Coffee's in the shack.",
	["Tape.Night2"] = "Night two. You'll pull up things that look almost right. Almost is the problem. Count the eyes. Use the book. I don't pay for what isn't in the book. Officially.",
	["Tape.Night3"] = "Night three. There's nobody else on this lake. I've held the only license since the dam went in. So if somebody waves at you, be rude.",
	["Tape.Night4"] = "Night four. Two things. If it knocks, answer short. And don't go staring into my trees. Don't ignore them, neither. You'll work it out.",
	["Tape.Night5"] = "Last night. I need one fish from over the steeple. They bite after three. And if you hear the bell, it isn't me ringing it. Come home. Don't stop for anything in that book.",
	["Tape.Endless"] = "Another night. Same lake, same quota board. The book's in the boat. Read it, it changes.",
	["Tape.Amendment"] = "One more thing. I changed the book. Read it again.",
	["Tape.NightFailed"] = "Rough night. Lake gives you one back. It doesn't do that forever.",
	["Tape.RunCleared"] = "Huh. You're still here. Pay's in the envelope. Same time tomorrow?",
} :: { [string]: string }

-- Every death card id Core can send (the shell's string table is checked against this).
Rulebook.DEATHS = {
	"Death.Water.Drag",
	"Death.Hum.Reeling",
	"Death.Hum.Motor",
	"Death.Hum.Moving",
	"Death.Hum.LanternLit",
	"Death.Hum.LanternDark",
	"Death.Hum.Noise",
	"Death.Neighbor.Waved",
	"Death.Neighbor.Closed",
	"Death.Neighbor.Beacon",
	"Death.Knocking.Sunk",
	"Death.Watcher.Reached",
	"Death.Finale.Still",
	"Death.Finale.Dark",
	"Death.Finale.Waved",
	"Death.Finale.Closed",
	"Death.Finale.Beacon",
} :: { string }

local function has(list: { any }, v: any): boolean
	for _, x in list do
		if x == v then
			return true
		end
	end
	return false
end

-- Text id of a rule as printed, or of its amendment when `variant` is not the printed one.
function Rulebook.ruleText(cfg: any, rule: string, variant: string?): string
	local variants = cfg.Amendments[rule]
	if variant ~= nil and variants ~= nil and variant ~= variants[1] then
		return "Rule." .. rule .. "." .. variant
	end
	return "Rule." .. rule
end

-- The rules taped into the book by a night: Story accumulates cfg.Nights; Endless has them all.
function Rulebook.taped(cfg: any, mode: Types.Mode, night: number): { RuleId }
	local out: { RuleId } = {}
	local last = if mode == "Endless" then #cfg.Nights else math.min(night, #cfg.Nights)
	for n = 1, last do
		for _, r in cfg.Nights[n].newRules do
			if not (mode == "Endless" and r == "Finale") and not has(out, r) then
				table.insert(out, r)
			end
		end
	end
	return out
end

-- The page: Rule 0 always, then each rule in `rules`, in rule-number order.
function Rulebook.page(cfg: any, rules: { RuleId }, amendments: { [string]: string }?): { PageLine }
	local am = amendments or {}
	local out: { PageLine } = { { rule = "Water", number = 0, text = "Rule.Water", amended = nil } }
	for _, r in rules do
		local variant = am[r]
		local amended = nil
		if variant ~= nil and Rulebook.ruleText(cfg, r, variant) ~= "Rule." .. r then
			amended = Rulebook.ruleText(cfg, r, variant)
		end
		table.insert(out, { rule = r, number = Rulebook.NUMBERS[r] or 99, text = "Rule." .. r, amended = amended })
	end
	table.sort(out, function(a, b)
		return a.number < b.number
	end)
	return out
end

local function drawVariant(cfg: any, rng: Rng.RngState, rule: string): string
	local variants = cfg.Amendments[rule]
	return variants[Rng.int(rng, 2, #variants)]
end

-- Tonight's amendments: { [RuleId] = variant } holding only the amended rules.
function Rulebook.amendments(cfg: any, o: AmendOpts): { [string]: string }
	local out: { [string]: string } = {}
	local root = Rng.new(o.seed)
	local candidates: { RuleId } = {}
	for _, r in Rulebook.AMENDABLE do
		local variants = cfg.Amendments[r]
		if has(o.rules, r) and variants ~= nil and #variants >= 2 then
			table.insert(candidates, r)
		end
	end
	if #candidates == 0 then
		return out
	end
	local from, chance
	if o.mode == "Endless" then
		from, chance = 1, cfg.Endless.amendChance
	else
		local D = cfg.Difficulty[o.difficulty] or cfg.Difficulty.Normal
		from, chance = D.amendFromNight, D.amendChance
		if o.night < from then
			return out
		end
		if o.firstRun ~= false and not D.amendOnFirstRun then
			-- The first Normal run: exactly one amendment, on night amendFromNight.
			if o.night == from then
				local r = Rng.fork(root, "amend:first")
				local rule = Rng.pick(r, candidates)
				out[rule] = drawVariant(cfg, r, rule)
			end
			return out
		end
	end
	if o.night < from then
		return out
	end
	local r = Rng.fork(root, "amend:" .. tostring(o.night))
	for _, rule in candidates do
		-- Both draws are always taken so one rule's outcome never shifts another's.
		local roll = Rng.next(r)
		local variant = drawVariant(cfg, r, rule)
		if roll < chance then
			out[rule] = variant
		end
	end
	return out
end

-- Tape ids that open a night (the Night module sends the same as Tape events).
function Rulebook.tapes(params: NightParams): { string }
	local out = { if params.mode == "Endless" then "Endless" else "Night" .. tostring(params.night) }
	if next(params.amendments or {}) ~= nil then
		table.insert(out, "Amendment")
	end
	return out
end

function Rulebook.deathText(rule: string, cause: string): string
	return "Death." .. rule .. "." .. cause
end

-- The death card for a text id. Unknown ids fall back to "Death.Unknown".
function Rulebook.deathCard(id: string): DeathCard
	local rule = string.match(id, "^Death%.(%w+)%.%w+$")
	if rule == nil or Rulebook.NUMBERS[rule] == nil or Rulebook.TEXT[id] == nil then
		return { text = "Death.Unknown", rule = "Water", number = 0, ruleText = "Rule.Water" }
	end
	return { text = id, rule = rule, number = Rulebook.NUMBERS[rule], ruleText = "Rule." .. rule }
end

return Rulebook
