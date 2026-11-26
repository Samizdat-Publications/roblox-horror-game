-- Core.LakeMap: inside, shore distance, nearest shore point, zones, safe light, sampling.
return function(t, Shared)
	local LakeMap = require(Shared.Core.LakeMap)
	local Rng = require(Shared.Core.Rng)
	local Config = require(Shared.Config)
	local L = Config.Lake

	local function near(a, b, eps, msg)
		t.ok(math.abs(a - b) <= eps, string.format("%s: %.4f vs %.4f", msg, a, b))
	end

	t.test("inside the ellipse, outside past the shore", function()
		t.ok(LakeMap.inside(Config, { x = 0, z = 0 }), "center")
		t.ok(LakeMap.inside(Config, L.dockEnd), "dock end is on water")
		t.ok(not LakeMap.inside(Config, { x = L.radiusX + 1, z = 0 }), "east of the shore")
		t.ok(not LakeMap.inside(Config, { x = 0, z = -L.radiusZ - 1 }), "south of the shore")
		t.ok(not LakeMap.inside(Config, L.shack), "the shack is on land")
	end)

	t.test("distance to shore on the axes is exact", function()
		near(LakeMap.distanceToShore(Config, { x = 0, z = 0 }), math.min(L.radiusX, L.radiusZ), 1e-6, "center")
		near(LakeMap.distanceToShore(Config, { x = 500, z = 0 }), L.radiusX - 500, 1e-6, "east axis")
		near(LakeMap.distanceToShore(Config, { x = 0, z = 400 }), 60, 1e-6, "north axis")
		near(LakeMap.distanceToShore(Config, L.dockEnd), L.radiusZ - 384, 1e-6, "dock end")
		near(LakeMap.distanceToShore(Config, { x = 0, z = 500 }), 40, 1e-6, "outside, north")
	end)

	t.test("nearest shore point lies on the shore and beats a fine scan", function()
		local r = Rng.new(8)
		for _ = 1, 200 do
			local p = { x = Rng.range(r, -700, 700), z = Rng.range(r, -520, 520) }
			local q = LakeMap.nearestShorePoint(Config, p)
			local u, v = q.x / L.radiusX, q.z / L.radiusZ
			near(u * u + v * v, 1, 1e-6, "on the ellipse")
			local d = LakeMap.dist(p, q)
			local best = math.huge
			for i = 0, 3599 do
				local a = i / 3600 * 2 * math.pi
				local s = { x = L.radiusX * math.cos(a), z = L.radiusZ * math.sin(a) }
				best = math.min(best, LakeMap.dist(p, s))
			end
			t.ok(d <= best + 0.05, string.format("nearest %.3f worse than scan %.3f", d, best))
		end
	end)

	t.test("zones in priority order", function()
		t.eq(LakeMap.zoneAt(Config, L.steeple), "Steeple", "steeple")
		t.eq(LakeMap.zoneAt(Config, { x = L.reeds.x, z = L.reeds.z }), "Reeds", "reeds")
		t.eq(LakeMap.zoneAt(Config, { x = L.narrows.x, z = L.narrows.z }), "Narrows", "narrows")
		t.eq(LakeMap.zoneAt(Config, { x = 0, z = -300 }), "Shallows", "near the dock")
		t.eq(LakeMap.zoneAt(Config, { x = -300, z = -50 }), "Open", "open water")
		-- Overlap check: a copy where the reeds cover the steeple; steeple still wins.
		local cfg = table.clone(Config)
		cfg.Lake = table.clone(L)
		cfg.Lake.reeds = { x = L.steeple.x, z = L.steeple.z, radius = 300 }
		t.eq(LakeMap.zoneAt(cfg, L.steeple), "Steeple", "priority with overlap")
	end)

	t.test("safe light and bank range", function()
		t.ok(LakeMap.isSafe(Config, L.dockEnd), "dock end is safe")
		t.ok(LakeMap.isSafe(Config, { x = 0, z = L.dockEnd.z + L.safeRadius - 1 }), "edge of the light")
		t.ok(not LakeMap.isSafe(Config, { x = 0, z = L.dockEnd.z + L.safeRadius + 1 }), "just outside")
		t.ok(LakeMap.canBank(Config, { x = 10, z = L.dockEnd.z + 10 }), "can bank close in")
		t.ok(not LakeMap.canBank(Config, { x = 0, z = L.dockEnd.z + 50 }), "too far to bank")
	end)

	t.test("random points land in their zone, on water, deterministic", function()
		for _, zone in Config.Zones do
			local r1, r2 = Rng.new(77), Rng.new(77)
			for _ = 1, 40 do
				local p = LakeMap.randomPointInZone(Config, r1, zone, { shoreMargin = 15, avoidSafe = true })
				local q = LakeMap.randomPointInZone(Config, r2, zone, { shoreMargin = 15, avoidSafe = true })
				t.ok(p ~= nil, "no point found in " .. zone)
				local pp = p :: any
				t.eq(pp.x, (q :: any).x, "deterministic x")
				t.eq(LakeMap.zoneAt(Config, pp), zone, "zone")
				t.ok(LakeMap.inside(Config, pp), "on water")
				t.ok(LakeMap.distanceToShore(Config, pp) >= 15, "shore margin")
				t.ok(not LakeMap.isSafe(Config, pp), "avoided the dock light")
			end
		end
	end)

	t.test("random point returns nil when the zone cannot fit the margin", function()
		local r = Rng.new(1)
		local p = LakeMap.randomPointInZone(Config, r, "Steeple", { shoreMargin = 5000, tries = 50 })
		t.eq(p, nil, "impossible margin")
	end)
end
