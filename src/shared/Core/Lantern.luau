--!strict
-- The boat lantern: on, off, forced out by a rule, burning oil, refilled at the dock.

local Types = require(script.Parent.Types)

type Event = Types.Event

export type LanternState = {
	on: boolean,
	oil: number, -- 0..1
	refills: number, -- oil cans left at the dock tonight
	forcedFor: number, -- seconds left before it can be relit after a rule snuffed it
	lockedOn: boolean, -- the finale locks it lit
	burnMult: number, -- above 1 burns slower (Trimmed Wick)
	lowSent: boolean,
}

local Lantern = {}

function Lantern.new(cfg: any, refills: number?, burnMult: number?): LanternState
	return {
		on = false,
		oil = 1,
		refills = refills or cfg.Lantern.refillsPerNight,
		forcedFor = 0,
		lockedOn = false,
		burnMult = burnMult or 1,
		lowSent = false,
	}
end

local function changed(l: LanternState, forced: boolean): Event
	return { kind = "LanternChanged", data = { on = l.on, forced = forced } }
end

-- Player request. Returns the events it caused (none if refused).
function Lantern.setOn(l: LanternState, on: boolean): { Event }
	if l.on == on then
		return {}
	end
	if on and (l.oil <= 0 or l.forcedFor > 0) then
		return {}
	end
	if not on and l.lockedOn then
		return {}
	end
	l.on = on
	return { changed(l, false) }
end

function Lantern.toggle(l: LanternState): { Event }
	return Lantern.setOn(l, not l.on)
end

-- A rule snuffs it. It cannot be relit for `seconds` (default cfg.Lantern.forcedOutSeconds).
function Lantern.forceOut(cfg: any, l: LanternState, seconds: number?): { Event }
	l.forcedFor = math.max(l.forcedFor, seconds or cfg.Lantern.forcedOutSeconds)
	l.lockedOn = false
	if not l.on then
		return {}
	end
	l.on = false
	return { changed(l, true) }
end

-- The finale: lit and locked. Returns events.
function Lantern.lockOn(l: LanternState): { Event }
	l.lockedOn = true
	l.forcedFor = 0
	if l.on or l.oil <= 0 then
		return {}
	end
	l.on = true
	return { changed(l, true) }
end

-- Burns oil while lit. Sends OilLow once per fill and OilOut when it runs dry.
function Lantern.step(cfg: any, l: LanternState, dt: number): { Event }
	local events: { Event } = {}
	if l.forcedFor > 0 then
		l.forcedFor = math.max(0, l.forcedFor - dt)
	end
	if not l.on then
		return events
	end
	l.oil = math.max(0, l.oil - dt / (cfg.Lantern.burnSeconds * l.burnMult))
	if not l.lowSent and l.oil <= cfg.Lantern.lowAt then
		l.lowSent = true
		table.insert(events, { kind = "OilLow" })
	end
	if l.oil <= 0 then
		l.on = false
		l.lockedOn = false
		table.insert(events, { kind = "OilOut" })
		table.insert(events, changed(l, true))
	end
	return events
end

-- Uses one oil can (the caller checks the boat is at the dock).
function Lantern.refill(l: LanternState): { Event }
	if l.refills <= 0 or l.oil >= 1 then
		return {}
	end
	l.refills -= 1
	l.oil = 1
	l.lowSent = false
	return { { kind = "OilRefilled" } }
end

return Lantern
