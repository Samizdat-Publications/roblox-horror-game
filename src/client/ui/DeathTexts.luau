--!strict
-- The death card's words, by text id "Death.<Rule>.<Cause>" (PlayerDied.data.text). In the
-- owner's voice from the rulebook: second person, short, dry, practical. Never gory: the
-- card says what you did and which rule it was.

local DeathTexts = {}

DeathTexts.RULE_NUMBER = {
	Water = 0,
	Hum = 1,
	WrongCatch = 2,
	Neighbor = 3,
	Knocking = 4,
	Watcher = 5,
	Finale = 6,
} :: { [string]: number }

DeathTexts.TEXT = {
	["Death.Water.Drag"] = "You got out of the boat. The water is not yours at night.",
	["Death.Hum.Reeling"] = "You kept reeling while the frogs were quiet.",
	["Death.Hum.Motor"] = "The motor was running while the frogs were quiet.",
	["Death.Hum.Moving"] = "The boat kept moving while the frogs were quiet.",
	["Death.Hum.LanternLit"] = "The lantern stayed lit while the frogs were quiet.",
	["Death.Hum.LanternDark"] = "The lantern was dark. The book said leave it lit.",
	["Death.Hum.Noise"] = "Somebody made noise while the frogs were quiet.",
	["Death.Neighbor.Waved"] = "You waved back.",
	["Death.Neighbor.Closed"] = "You let the other boat come close.",
	["Death.Neighbor.Beacon"] = "You rowed toward a light that did not blink twice.",
	["Death.Knocking.Sunk"] = "You answered the knocking wrong. The boat went down.",
	["Death.Watcher.Reached"] = "You let the thing on the shore reach the water.",
	["Death.Finale.Still"] = "You stopped. The bell said go home.",
	["Death.Finale.Dark"] = "The lantern ran dry before you got home.",
	["Death.Finale.Waved"] = "You waved back on the way home.",
	["Death.Finale.Closed"] = "You let the other boat come close on the way home.",
	["Death.Finale.Beacon"] = "You followed the wrong light home.",
} :: { [string]: string }

DeathTexts.FALLBACK = "The lake took you."

-- The card's main line and its rule line ("Rule 1."), from a text id.
function DeathTexts.card(id: any): (string, string)
	local key = if type(id) == "string" then id else ""
	local line = DeathTexts.TEXT[key] or DeathTexts.FALLBACK
	local rule = string.match(key, "^Death%.(%w+)%.")
	local n = if rule then DeathTexts.RULE_NUMBER[rule] else nil
	return line, if n ~= nil then string.format("Rule %d.", n) else ""
end

return DeathTexts
