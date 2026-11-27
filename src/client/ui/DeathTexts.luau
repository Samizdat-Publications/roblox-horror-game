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

-- Each card says what went wrong, then the counter, in one short line (Studio and Neon
-- fixes, 11/26/2026): the card is where the rule is learned.
DeathTexts.TEXT = {
	["Death.Water.Drag"] = "You got out of the boat. Stay in it. The water is not yours at night.",
	["Death.Hum.Reeling"] = "You kept reeling. When the frogs stop: let go of the reel, motor off, lantern out, hold still.",
	["Death.Hum.Motor"] = "You left the motor running. When the frogs stop: motor off, lantern out, hold still.",
	["Death.Hum.Moving"] = "You kept the boat moving. When the frogs stop: oars up, motor off, lantern out, hold still.",
	["Death.Hum.LanternLit"] = "You left the lantern lit. When the frogs stop: lantern out, motor off, hold still.",
	["Death.Hum.LanternDark"] = "You put the lantern out. The book changed: when the frogs stop, leave it lit and hold still.",
	["Death.Hum.Noise"] = "Somebody made noise. When the frogs stop, nobody moves until they sing again.",
	["Death.Neighbor.Waved"] = "You waved back. There are no other boats out here. Never wave back.",
	["Death.Neighbor.Closed"] = "You let the other boat come close. Lantern out, keep your distance, let it drift off.",
	["Death.Neighbor.Beacon"] = "You rowed toward the wrong light. Ours blinks twice. Count before you row.",
	["Death.Knocking.Sunk"] = "You answered the knocking wrong. Three knocks: answer with two, as the book says. Bail if it leaks.",
	["Death.Watcher.Reached"] = "You let the thing on the shore reach the water. Keep it at the edge of your eye. Never stare.",
	["Death.Finale.Still"] = "You stopped. When the bell rings: lights on, keep moving, go home.",
	["Death.Finale.Dark"] = "The lantern ran dry out there. When the bell rings, go straight home.",
	["Death.Finale.Waved"] = "You waved back on the way home. Never wave. Keep rowing.",
	["Death.Finale.Closed"] = "You let the other boat come close on the way home. Steer around it. Keep going.",
	["Death.Finale.Beacon"] = "You followed the wrong light home. Ours blinks twice.",
} :: { [string]: string }

DeathTexts.FALLBACK = "The lake took you. Read the book again."

-- The card's main line and its rule line ("Rule 1."), from a text id.
function DeathTexts.card(id: any): (string, string)
	local key = if type(id) == "string" then id else ""
	local line = DeathTexts.TEXT[key] or DeathTexts.FALLBACK
	local rule = string.match(key, "^Death%.(%w+)%.")
	local n = if rule then DeathTexts.RULE_NUMBER[rule] else nil
	return line, if n ~= nil then string.format("Rule %d.", n) else ""
end

return DeathTexts
