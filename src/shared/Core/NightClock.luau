--!strict
-- Real seconds to game hours. 10 PM (22.0) to 5 AM (29.0) over cfg.Night.realSeconds.

export type ClockState = {
	elapsed: number, -- real seconds since the night started
	length: number, -- real seconds in this night
}

local NightClock = {}

function NightClock.new(cfg: any, length: number?): ClockState
	return { elapsed = 0, length = length or cfg.Night.realSeconds }
end

function NightClock.step(c: ClockState, dt: number)
	c.elapsed = math.min(c.length, c.elapsed + math.max(0, dt))
end

function NightClock.fraction(c: ClockState): number
	return c.elapsed / c.length
end

function NightClock.timeLeft(c: ClockState): number
	return c.length - c.elapsed
end

function NightClock.done(c: ClockState): boolean
	return c.elapsed >= c.length
end

-- Game hour, 22.0 at the start and cfg.Night.endHour (29.0) at dawn.
function NightClock.hour(cfg: any, c: ClockState): number
	local N = cfg.Night
	return N.startHour + (N.endHour - N.startHour) * NightClock.fraction(c)
end

-- Real seconds from the start of the night until game hour `hour`.
function NightClock.secondsAt(cfg: any, c: ClockState, hour: number): number
	local N = cfg.Night
	return (hour - N.startHour) / (N.endHour - N.startHour) * c.length
end

-- "10:00 PM" style text for the HUD and logs.
function NightClock.label(hour: number): string
	local h = math.floor(hour) % 24
	local m = math.floor((hour - math.floor(hour)) * 60)
	local suffix = if h >= 12 then "PM" else "AM"
	local h12 = h % 12
	if h12 == 0 then
		h12 = 12
	end
	return string.format("%d:%02d %s", h12, m, suffix)
end

return NightClock
