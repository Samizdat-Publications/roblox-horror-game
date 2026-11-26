--!strict
-- The ring of shore around the lake ellipse and the crooked tree line on it.
-- Two rings of slabs (a near bank and a far rise), a mud strip at the waterline so the
-- edge reads on a phone, and trees: a trunk and two or three canopy blocks each.
-- ctx fields: see world/Assemble.luau.

local Shore = {}

Shore.name = "Shore"

Shore.SEGMENTS = 96
Shore.FAR_SEGMENTS = 64
Shore.TREES = 230
Shore.NEAR_DEPTH = 150
Shore.FAR_DEPTH = 260

function Shore.build(ctx: any)
	local cfg, look, parts, Rng, rng = ctx.cfg, ctx.look, ctx.parts, ctx.Rng, ctx.rng
	local lake = cfg.Lake
	local rx, rz, wy = lake.radiusX, lake.radiusZ, lake.waterY
	local pal = look.Palette
	local tau = 2 * math.pi

	local ring = parts.folder(ctx.parent, "Ground")
	local mudF = parts.folder(ctx.parent, "Bank")
	local treesF = parts.folder(ctx.parent, "Trees")

	-- One slab per angle step, tangent to the ellipse, reaching `depth` studs outward from
	-- `inset` studs inside the shoreline.
	local function slabRing(n: number, inset: number, depth: number, topLo: number, topHi: number, prefix: string)
		for i = 0, n - 1 do
			local a0 = tau * i / n
			local a1 = tau * (i + 1) / n
			local x0, z0, nx0, nz0 = parts.shorePoint(rx, rz, a0)
			local x1, z1, nx1, nz1 = parts.shorePoint(rx, rz, a1)
			local am = (a0 + a1) / 2
			local xm, zm, nxm, nzm = parts.shorePoint(rx, rz, am)
			-- Length from the outer edge, where neighbors spread apart most, plus overlap.
			local reach = depth - inset
			local ox0, oz0 = x0 + nx0 * reach, z0 + nz0 * reach
			local ox1, oz1 = x1 + nx1 * reach, z1 + nz1 * reach
			local len = math.sqrt((ox1 - ox0) ^ 2 + (oz1 - oz0) ^ 2) * 1.12 + 2
			local top = wy + Rng.range(rng, topLo, topHi)
			local h = top - (wy - 9)
			local mid = (depth / 2) - inset
			local center = Vector3.new(xm + nxm * mid, top - h / 2, zm + nzm * mid)
			parts.block(
				ring,
				prefix .. i,
				Vector3.new(len, h, depth),
				parts.facing(center, Vector3.new(nxm, 0, nzm)),
				pal.shore,
				Enum.Material.Grass,
				{ shadow = false }
			)
		end
	end

	slabRing(Shore.SEGMENTS, 3, Shore.NEAR_DEPTH, 1.2, 2.4, "Near")
	slabRing(Shore.FAR_SEGMENTS, -(Shore.NEAR_DEPTH - 20), Shore.FAR_DEPTH, 3, 7, "Far")

	-- Mud strip at the waterline: slightly lighter than the ground, just above the water.
	for i = 0, Shore.SEGMENTS - 1 do
		local a0 = tau * i / Shore.SEGMENTS
		local a1 = tau * (i + 1) / Shore.SEGMENTS
		local x0, z0 = parts.shorePoint(rx, rz, a0)
		local x1, z1 = parts.shorePoint(rx, rz, a1)
		local xm, zm, nxm, nzm = parts.shorePoint(rx, rz, (a0 + a1) / 2)
		local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2) + 3
		local w = Rng.range(rng, 7, 11)
		local center = Vector3.new(xm - nxm * (w / 2 - 4), wy + 0.15, zm - nzm * (w / 2 - 4))
		parts.block(
			mudF,
			"Mud" .. i,
			Vector3.new(len, 1, w),
			parts.facing(center, Vector3.new(nxm, 0, nzm)) * CFrame.Angles(math.rad(Rng.range(rng, 2, 5)), 0, 0),
			pal.mud,
			Enum.Material.Mud,
			{ shadow = false }
		)
	end

	-- Keep a clearing around the dock, the beacon and the shack.
	local clear = {
		{ x = lake.shack.x, z = lake.shack.z, r = 34 },
		{ x = lake.dockFoot.x, z = lake.dockFoot.z, r = 26 },
		{ x = lake.beacon.x, z = lake.beacon.z, r = 14 },
	}
	local function blocked(x: number, z: number): boolean
		for _, c in clear do
			if (x - c.x) ^ 2 + (z - c.z) ^ 2 < c.r * c.r then
				return true
			end
		end
		return false
	end

	local planted = 0
	local tries = 0
	while planted < Shore.TREES and tries < Shore.TREES * 4 do
		tries += 1
		local a = Rng.range(rng, 0, tau)
		local sx, sz, nx, nz = parts.shorePoint(rx, rz, a)
		local out = 10 + 110 * (Rng.next(rng) ^ 1.6) -- most trees crowd the waterline
		local x, z = sx + nx * out, sz + nz * out
		if not blocked(x, z) then
			planted += 1
			local ground = wy + 1.2
			local h = Rng.range(rng, 22, 46)
			local w = Rng.range(rng, 1.3, 2.4)
			local lean = CFrame.Angles(math.rad(Rng.range(rng, -6, 6)), 0, math.rad(Rng.range(rng, -6, 6)))
			local base = CFrame.new(x, ground, z) * CFrame.Angles(0, Rng.range(rng, 0, tau), 0) * lean
			local tree = Instance.new("Model")
			tree.Name = "Tree" .. planted
			parts.block(
				tree,
				"Trunk",
				Vector3.new(w, h, w),
				base * CFrame.new(0, h / 2 - 1, 0),
				pal.trunk,
				Enum.Material.Wood
			)
			local blocks = Rng.int(rng, 2, 3)
			for b = 1, blocks do
				local t = 0.5 + 0.5 * (b / blocks) - Rng.range(rng, 0, 0.12)
				local cw = Rng.range(rng, 6, 12) * (1.15 - 0.25 * b / blocks)
				local ch = Rng.range(rng, 5, 9)
				local cd = Rng.range(rng, 6, 12) * (1.15 - 0.25 * b / blocks)
				local off = CFrame.new(Rng.range(rng, -2, 2), h * t, Rng.range(rng, -2, 2))
				local twist = CFrame.Angles(
					math.rad(Rng.range(rng, -8, 8)),
					Rng.range(rng, 0, tau),
					math.rad(Rng.range(rng, -8, 8))
				)
				parts.block(
					tree,
					"Canopy" .. b,
					Vector3.new(cw, ch, cd),
					base * off * twist,
					pal.canopy,
					Enum.Material.Grass,
					{ collide = false }
				)
			end
			tree.Parent = treesF
		end
	end
	if planted < Shore.TREES then
		table.insert(ctx.warnings, string.format("Shore: planted %d of %d trees", planted, Shore.TREES))
	end
end

return Shore
