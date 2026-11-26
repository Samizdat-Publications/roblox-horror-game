--!strict
-- The lake's hidden attention, 0..1. Its only display is the frog chorus (through the
-- Director's tension). The motor, the lantern and reeling raise it; stillness lets it
-- decay; the dock light drains it fast. A kept wrong fish adds a jump and raises a floor
-- it cannot fall below for the rest of the night (one floor step per fish, stacking).
-- The Director reads the value: high attention shortens calm phases and, sustained, adds
-- one real scare.
--
--   Attention.new() -> AttentionState
--   Attention.step(cfg, a, dt, facts) -- facts = { motorOn, lanternOn, reelers, safe }
--   Attention.keptWrong(cfg, a)

export type AttentionState = {
	value: number,
	floor: number,
}

export type Facts = {
	motorOn: boolean,
	lanternOn: boolean,
	reelers: number,
	safe: boolean,
}

local Attention = {}

function Attention.new(): AttentionState
	return { value = 0, floor = 0 }
end

function Attention.step(cfg: any, a: AttentionState, dt: number, f: Facts)
	local A = cfg.Attention
	local rise = 0
	if f.motorOn then
		rise += A.motorPerSec
	end
	if f.lanternOn then
		rise += A.lanternPerSec
	end
	rise += A.reelPerSec * f.reelers
	if f.safe then
		a.value -= A.safeDecayPerSec * dt
	elseif rise > 0 then
		a.value += rise * dt
	else
		a.value -= A.decayPerSec * dt
	end
	a.value = math.clamp(a.value, a.floor, 1)
end

-- A wrong fish was kept: a jump now, and a floor that stacks per fish.
function Attention.keptWrong(cfg: any, a: AttentionState)
	local A = cfg.Attention
	a.floor = math.min(1, a.floor + A.keptWrongFloor)
	a.value = math.clamp(a.value + A.keptWrong, a.floor, 1)
end

return Attention
