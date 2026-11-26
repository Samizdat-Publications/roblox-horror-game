--!strict
-- Which species bites, by zone and game hour, from the weights in cfg.Fish.

local Rng = require(script.Parent.Rng)

local FishTable = {}

-- Species keys in sorted order (stable across Lune and Roblox).
function FishTable.species(cfg: any): { string }
	local out: { string } = {}
	for key in cfg.Fish do
		table.insert(out, key)
	end
	table.sort(out)
	return out
end

-- The bite weights for a zone at an hour. Species with an `afterHour` only bite after it.
function FishTable.weights(cfg: any, zone: string, hour: number): { [string]: number }
	local w: { [string]: number } = {}
	for key, fish in cfg.Fish do
		local weight = fish.zones[zone] or 0
		if fish.afterHour ~= nil and hour < fish.afterHour then
			weight = 0
		end
		if weight > 0 then
			w[key] = weight
		end
	end
	return w
end

-- Picks a species key. Falls back to the Shallows table if a zone has no fish at this hour.
function FishTable.pick(cfg: any, rng: Rng.RngState, zone: string, hour: number): string
	local w = FishTable.weights(cfg, zone, hour)
	if next(w) == nil then
		w = FishTable.weights(cfg, "Shallows", hour)
	end
	return Rng.weighted(rng, w)
end

return FishTable
