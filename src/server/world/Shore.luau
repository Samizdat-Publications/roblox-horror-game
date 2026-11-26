--!strict
-- The ring of shore around the lake ellipse and the crooked tree line on it.
-- Two rings of slabs (a near bank and a far rise), a mud strip at the waterline so the
-- edge reads on a phone, and trees in three kinds: crooked broadleaf (a bent trunk,
-- branches, two leaf clumps), dead and bare, and conifers of stacked narrowing tiers.
-- ctx fields: see world/Assemble.luau.

local Shore = {}

Shore.name = "Shore"

Shore.SEGMENTS = 96
Shore.FAR_SEGMENTS = 64
Shore.TREES = 190
Shore.CONIFER_SHARE = 0.35
Shore.DEAD_SHARE = 0.15 -- the rest are crooked broadleaf trees
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

	-- A unit direction tilted `tilt` radians from straight up, toward compass angle `yaw`.
	local function tiltDir(yaw: number, tilt: number): Vector3
		local s = math.sin(tilt)
		return Vector3.new(s * math.cos(yaw), math.cos(tilt), s * math.sin(yaw))
	end
	-- A square beam of width w from a to b (a little longer so joints overlap).
	local function beam(model: Model, name: string, a: Vector3, b: Vector3, w: number, color: Color3, opts: any?)
		local d = b - a
		local len = d.Magnitude
		parts.block(
			model,
			name,
			Vector3.new(w, w, len + w * 0.6),
			CFrame.lookAt((a + b) / 2, b, Vector3.new(1, 0, 0)),
			color,
			Enum.Material.Wood,
			opts
		)
	end
	local deadWood = pal.trunk:Lerp(pal.stone, 0.35)

	-- Crooked trunk in two leaning segments; returns the base, the kink and the top.
	local function trunk(model: Model, x: number, z: number, h: number, w: number, color: Color3)
		local yaw = Rng.range(rng, 0, tau)
		local p0 = Vector3.new(x, wy, z)
		local p1 = p0 + tiltDir(yaw, math.rad(Rng.range(rng, 3, 9))) * (h * 0.55)
		local p2 = p1 + tiltDir(yaw + Rng.range(rng, -2.2, 2.2), math.rad(Rng.range(rng, 4, 13))) * (h * 0.45)
		beam(model, "Trunk", p0, p1, w, color)
		beam(model, "TrunkTop", p1, p2, w * 0.72, color)
		return p0, p1, p2
	end
	-- Point at fraction t (0 base, 1 top) up a two-segment trunk.
	local function along(p0: Vector3, p1: Vector3, p2: Vector3, t: number): Vector3
		if t < 0.55 then
			return p0:Lerp(p1, t / 0.55)
		end
		return p1:Lerp(p2, (t - 0.55) / 0.45)
	end
	-- Two or three branches angled up and out at different heights; returns the tips.
	local function branches(
		model: Model,
		p0: Vector3,
		p1: Vector3,
		p2: Vector3,
		h: number,
		w: number,
		color: Color3,
		tiltLo: number,
		tiltHi: number
	)
		local n = Rng.int(rng, 2, 3)
		local yaw0 = Rng.range(rng, 0, tau)
		local tips = {}
		for i = 1, n do
			local t = 0.4 + 0.45 * (i - 1) / n + Rng.range(rng, 0, 0.1)
			local from = along(p0, p1, p2, t)
			local yaw = yaw0 + tau * (i - 1) / n + Rng.range(rng, -0.6, 0.6)
			local len = h * Rng.range(rng, 0.16, 0.3) * (1.1 - 0.3 * t)
			local tip = from + tiltDir(yaw, math.rad(Rng.range(rng, tiltLo, tiltHi))) * len
			beam(model, "Branch" .. i, from, tip, w * Rng.range(rng, 0.35, 0.5), color, { collide = false })
			table.insert(tips, tip)
		end
		return tips
	end
	local function canopy(model: Model, name: string, at: Vector3, scale: number)
		parts.block(
			model,
			name,
			Vector3.new(Rng.range(rng, 5, 10) * scale, Rng.range(rng, 3.5, 6) * scale, Rng.range(rng, 5, 10) * scale),
			CFrame.new(at)
				* CFrame.Angles(
					math.rad(Rng.range(rng, -10, 10)),
					Rng.range(rng, 0, tau),
					math.rad(Rng.range(rng, -10, 10))
				),
			pal.canopy,
			Enum.Material.Grass,
			{ collide = false }
		)
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
			local tree = Instance.new("Model")
			tree.Name = "Tree" .. planted
			-- Heights vary a lot; about one tree in eight towers over the rest.
			local h = if Rng.next(rng) < 0.12 then Rng.range(rng, 56, 80) else Rng.range(rng, 18, 46)
			local kind = Rng.next(rng)
			if kind < Shore.CONIFER_SHARE then
				-- Conifer: a thin leaning trunk and 3 or 4 block tiers that narrow toward the top.
				local w = Rng.range(rng, 0.9, 1.4)
				local yaw = Rng.range(rng, 0, tau)
				local p0 = Vector3.new(x, wy, z)
				local top = p0 + tiltDir(yaw, math.rad(Rng.range(rng, 2, 7))) * h
				beam(tree, "Trunk", p0, top, w, pal.trunk)
				tree.Name ..= "Conifer"
				local tiers = Rng.int(rng, 3, 4)
				local baseW = Rng.range(rng, 8, 13) * math.clamp(h / 40, 0.7, 1.5)
				local span = h * 0.78
				local tierH = span / tiers * 1.35
				for i = 1, tiers do
					local f = (i - 1) / tiers
					local tw = baseW * (1 - 0.72 * f) * Rng.range(rng, 0.9, 1.1)
					local at = p0:Lerp(top, 0.22 + 0.78 * f + tierH / h * 0.35)
					parts.block(
						tree,
						"Tier" .. i,
						Vector3.new(tw, tierH * (1 - 0.25 * f), tw),
						CFrame.new(at)
							* CFrame.Angles(
								math.rad(Rng.range(rng, -5, 5)),
								i * 0.45 + Rng.range(rng, -0.3, 0.3),
								math.rad(Rng.range(rng, -5, 5))
							),
						pal.canopy,
						Enum.Material.Grass,
						{ collide = false }
					)
				end
			elseif kind < Shore.CONIFER_SHARE + Shore.DEAD_SHARE then
				-- Dead tree: pale bare trunk and branches, no canopy.
				tree.Name ..= "Dead"
				local w = Rng.range(rng, 1.1, 2.0)
				local p0, p1, p2 = trunk(tree, x, z, h, w, deadWood)
				branches(tree, p0, p1, p2, h, w, deadWood, 30, 65)
			else
				-- Crooked broadleaf: two-segment trunk, branches, a crown at the top and one
				-- clump of leaves at the end of a branch.
				local w = Rng.range(rng, 1.3, 2.4)
				local p0, p1, p2 = trunk(tree, x, z, h, w, pal.trunk)
				local tips = branches(tree, p0, p1, p2, h, w, pal.trunk, 30, 55)
				local sc = math.clamp(h / 34, 0.8, 1.6)
				canopy(tree, "Crown", p2, sc)
				canopy(tree, "Leaves", tips[Rng.int(rng, 1, #tips)], sc * 0.75)
			end
			tree.Parent = treesF
		end
	end
	if planted < Shore.TREES then
		table.insert(ctx.warnings, string.format("Shore: planted %d of %d trees", planted, Shore.TREES))
	end
end

return Shore
