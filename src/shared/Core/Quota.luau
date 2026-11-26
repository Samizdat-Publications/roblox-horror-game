--!strict
-- The bait shop's quota: points banked in the dock cooler against tonight's target.

local Types = require(script.Parent.Types)

type Event = Types.Event

export type QuotaState = {
	target: number,
	banked: number, -- points
	fish: number, -- fish banked
	met: boolean, -- QuotaMet has been sent (it is sent once per night)
	metAt: number?, -- real seconds into the night when it was first met
}

local Quota = {}

-- Base quota scaled for the living crew size at night start (never below 1).
function Quota.scaled(cfg: any, base: number, crew: number): number
	local i = math.clamp(math.floor(crew), 1, #cfg.Scaling.quota)
	return math.max(1, math.floor(base * cfg.Scaling.quota[i] + 0.5))
end

function Quota.new(target: number): QuotaState
	return { target = target, banked = 0, fish = 0, met = false, metAt = nil }
end

function Quota.isMet(q: QuotaState): boolean
	return q.banked >= q.target
end

-- Adds banked points. Sends QuotaMet the first time the target is reached.
function Quota.bank(q: QuotaState, fish: number, points: number, now: number): { Event }
	q.banked += points
	q.fish += fish
	if not q.met and q.banked >= q.target then
		q.met = true
		q.metAt = now
		return { { kind = "QuotaMet", data = { banked = q.banked, quota = q.target } } }
	end
	return {}
end

-- Takes points back out (the cooler knocks). Never below zero. QuotaMet is not resent.
function Quota.remove(q: QuotaState, fish: number, points: number)
	q.banked = math.max(0, q.banked - points)
	q.fish = math.max(0, q.fish - fish)
end

return Quota
