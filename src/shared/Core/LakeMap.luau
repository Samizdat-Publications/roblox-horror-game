--!strict
-- The lake as geometry: zones, the shoreline, the dock light.
-- The shore is the ellipse (x / radiusX)^2 + (z / radiusZ)^2 = 1 from cfg.Lake.
-- Every function takes cfg so tests can pass altered copies.

local Types = require(script.Parent.Types)
local Rng = require(script.Parent.Rng)

type Vec2 = Types.Vec2

local LakeMap = {}

local function dist(a: Vec2, b: Vec2): number
	local dx, dz = a.x - b.x, a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end
LakeMap.dist = dist

local function within(p: Vec2, c: { x: number, z: number }, r: number): boolean
	local dx, dz = p.x - c.x, p.z - c.z
	return dx * dx + dz * dz <= r * r
end

-- True when p is on the water (strictly inside the shoreline).
function LakeMap.inside(cfg: any, p: Vec2): boolean
	local L = cfg.Lake
	local u, v = p.x / L.radiusX, p.z / L.radiusZ
	return u * u + v * v < 1
end

-- The closest point on the shoreline to p. Works for points inside or outside the lake.
-- Trig-free iteration on the ellipse (converges in a few rounds for any point).
function LakeMap.nearestShorePoint(cfg: any, p: Vec2): Vec2
	local a, b = cfg.Lake.radiusX, cfg.Lake.radiusZ
	local px, pz = math.abs(p.x), math.abs(p.z)
	if px < 1e-9 and pz < 1e-9 then
		-- The center: the nearest shore is the end of the short axis.
		if a <= b then
			return { x = a, z = 0 }
		end
		return { x = 0, z = -b }
	end
	local tx, tz = 0.70710678118, 0.70710678118
	for _ = 1, 4 do
		local x, z = a * tx, b * tz
		local ex = (a * a - b * b) * tx * tx * tx / a
		local ez = (b * b - a * a) * tz * tz * tz / b
		local rx, rz = x - ex, z - ez
		local qx, qz = px - ex, pz - ez
		local r = math.sqrt(rx * rx + rz * rz)
		local q = math.sqrt(qx * qx + qz * qz)
		if q < 1e-12 then
			break
		end
		tx = math.clamp((qx * r / q + ex) / a, 0, 1)
		tz = math.clamp((qz * r / q + ez) / b, 0, 1)
		local t = math.sqrt(tx * tx + tz * tz)
		tx /= t
		tz /= t
	end
	local sx = if p.x < 0 then -1 else 1
	local sz = if p.z < 0 then -1 else 1
	return { x = a * tx * sx, z = b * tz * sz }
end

-- Distance from p to the shoreline (positive inside the lake and outside it alike).
function LakeMap.distanceToShore(cfg: any, p: Vec2): number
	return dist(p, LakeMap.nearestShorePoint(cfg, p))
end

-- Zones are checked in cfg.Zones order: Steeple, Reeds, Narrows, Shallows, else Open.
function LakeMap.zoneAt(cfg: any, p: Vec2): string
	local L = cfg.Lake
	for _, zone in cfg.Zones do
		if zone == "Steeple" and within(p, L.steeple, L.steepleRadius) then
			return zone
		elseif zone == "Reeds" and within(p, L.reeds, L.reeds.radius) then
			return zone
		elseif zone == "Narrows" and within(p, L.narrows, L.narrows.radius) then
			return zone
		elseif zone == "Shallows" and within(p, L.dockEnd, L.shallowsDist) then
			return zone
		elseif zone == "Open" then
			return zone
		end
	end
	return "Open"
end

-- Inside the beacon's light around the dock end: no real rule starts or advances here.
function LakeMap.isSafe(cfg: any, p: Vec2): boolean
	return within(p, cfg.Lake.dockEnd, cfg.Lake.safeRadius)
end

-- Close enough to the dock end to bank the hold or take the oil can.
function LakeMap.canBank(cfg: any, p: Vec2): boolean
	return within(p, cfg.Lake.dockEnd, cfg.Lake.bankRadius)
end

export type PointOpts = {
	shoreMargin: number?, -- keep at least this far from the shore (default 15)
	avoidSafe: boolean?, -- reject points inside the dock light (default false)
	tries: number?, -- rejection sampling attempts (default 400)
}

-- A uniformly random water point in `zone`. Returns nil if none was found (zone too small
-- for the margins). Draws only from the rng passed in.
function LakeMap.randomPointInZone(cfg: any, rng: Rng.RngState, zone: string, opts: PointOpts?): Vec2?
	local o: PointOpts = opts or {}
	local margin = o.shoreMargin or 15
	local L = cfg.Lake
	-- Sample inside the zone's own circle when it has one, else the whole lake box.
	local cx, cz, rx, rz = 0, 0, L.radiusX, L.radiusZ
	if zone == "Steeple" then
		cx, cz, rx, rz = L.steeple.x, L.steeple.z, L.steepleRadius, L.steepleRadius
	elseif zone == "Reeds" then
		cx, cz, rx, rz = L.reeds.x, L.reeds.z, L.reeds.radius, L.reeds.radius
	elseif zone == "Narrows" then
		cx, cz, rx, rz = L.narrows.x, L.narrows.z, L.narrows.radius, L.narrows.radius
	elseif zone == "Shallows" then
		cx, cz, rx, rz = L.dockEnd.x, L.dockEnd.z, L.shallowsDist, L.shallowsDist
	end
	for _ = 1, o.tries or 400 do
		local p = { x = cx + Rng.range(rng, -rx, rx), z = cz + Rng.range(rng, -rz, rz) }
		if
			LakeMap.inside(cfg, p)
			and LakeMap.distanceToShore(cfg, p) >= margin
			and LakeMap.zoneAt(cfg, p) == zone
			and not (o.avoidSafe and LakeMap.isSafe(cfg, p))
		then
			return p
		end
	end
	return nil
end

return LakeMap
