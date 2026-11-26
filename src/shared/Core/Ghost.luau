--!strict
-- The drowned (docs/DESIGN.md, Death and the drowned). A dead player floats near the boat
-- as a dim light and can ring a faint bell every cfg.Ghost.bellCooldown seconds. What the
-- drowned can see (outlines the living cannot) is presentation; Core only rules on the bell.
--
--   Ghost.new(cfg) -> GhostState
--   Ghost.ring(g, player, now) -> { Event }   -- GhostBell, or nothing while cooling down

local Types = require(script.Parent.Types)

type Event = Types.Event
type PlayerId = Types.PlayerId

export type GhostState = {
	cooldown: number,
	last: { [PlayerId]: number },
}

local Ghost = {}

function Ghost.new(cfg: any): GhostState
	return { cooldown = cfg.Ghost.bellCooldown, last = {} }
end

function Ghost.canRing(g: GhostState, player: PlayerId, now: number): boolean
	local last = g.last[player]
	return last == nil or now - last >= g.cooldown - 1e-9
end

function Ghost.ring(g: GhostState, player: PlayerId, now: number): { Event }
	if not Ghost.canRing(g, player, now) then
		return {}
	end
	g.last[player] = now
	return { { kind = "GhostBell", player = player } }
end

return Ghost
