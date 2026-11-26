--!strict
-- Points of interest out on the water: the sunken steeple leaning out of the lake with its
-- bell just under the surface, the old buoy, the reeds along the east shore, and a few
-- dead snags and rocks at the narrows.
-- ctx fields: see world/Assemble.luau. Anchors set here: steeple, steepleBell, buoy,
-- reeds, narrows.

local Landmarks = {}

Landmarks.name = "Landmarks"

Landmarks.STEEPLE_LEAN = 18 -- degrees
Landmarks.STEEPLE_SINK = 14 -- the tower's foot is this far below the water surface
Landmarks.STEEPLE_SCALE = 1.3 -- every height along the tower, from the first gray-box size
-- Share of the lean that goes across the boat's line of approach (dock end to steeple)
-- rather than toward the boat. A lean straight at the viewer is foreshortened and reads as
-- upright, so most of it goes sideways (to the west as seen from the dock).
Landmarks.STEEPLE_LEAN_ACROSS = 0.7
Landmarks.REED_CLUMPS = 55

-- Unit horizontal direction the steeple leans: mostly across the approach from the dock,
-- partly back toward the dock.
function Landmarks.steepleLeanDir(cfg: any): (number, number)
	local lake = cfg.Lake
	local s, e = lake.steeple, lake.dockEnd
	local ax, az = s.x - e.x, s.z - e.z
	local al = math.sqrt(ax * ax + az * az)
	ax, az = ax / al, az / al
	local k = Landmarks.STEEPLE_LEAN_ACROSS
	-- (-az, ax) is the approach turned left (west for a northward approach).
	local lx, lz = k * -az + (1 - k) * -ax, k * ax + (1 - k) * -az
	local ll = math.sqrt(lx * lx + lz * lz)
	return lx / ll, lz / ll
end

-- Horizontal offset of the steeple's waterline from its foot, along the lean.
-- BoatService uses the same formula to keep the boat clear of it.
function Landmarks.steepleWaterline(cfg: any): (number, number)
	local s = cfg.Lake.steeple
	local ux, uz = Landmarks.steepleLeanDir(cfg)
	local lean = math.rad(Landmarks.STEEPLE_LEAN)
	local off = Landmarks.STEEPLE_SINK * math.tan(lean) / math.cos(lean)
	return s.x + ux * off, s.z + uz * off
end

function Landmarks.build(ctx: any)
	local cfg, look, parts, Rng, rng = ctx.cfg, ctx.look, ctx.parts, ctx.Rng, ctx.rng
	local lake = cfg.Lake
	local pal = look.Palette
	local wy = lake.waterY

	-- The steeple. Built in a frame whose +Y runs up the leaning tower.
	local st = lake.steeple
	local steepleF = parts.folder(ctx.parent, "Steeple")
	local footPos = Vector3.new(st.x, wy - Landmarks.STEEPLE_SINK / math.cos(math.rad(Landmarks.STEEPLE_LEAN)), st.z)
	local lx, lz = Landmarks.steepleLeanDir(cfg)
	local frame = parts.facing(footPos, Vector3.new(lx, 0, lz)) * CFrame.Angles(math.rad(-Landmarks.STEEPLE_LEAN), 0, 0)
	local W = 12
	local S = Landmarks.STEEPLE_SCALE
	local function tower(
		name: string,
		size: Vector3,
		s: number,
		x: number?,
		z: number?,
		color: Color3?,
		mat: Enum.Material?
	)
		return parts.block(
			steepleF,
			name,
			size,
			frame * CFrame.new(x or 0, s, z or 0),
			color or pal.stone,
			mat or Enum.Material.Slate
		)
	end
	-- Heights along the tower axis, all scaled by S. The belfry straddles the waterline.
	local shaftH = 8 * S
	tower("Shaft", Vector3.new(W, shaftH, W), shaftH / 2)
	tower("BelfryFloor", Vector3.new(W, 0.6, W), shaftH + 0.3)
	local belfryLo = shaftH + 0.6
	local belfryH = 7 * S
	local belfryMid = belfryLo + belfryH / 2
	tower("BelfryBody", Vector3.new(W - 1.2, belfryH, W - 1.2), belfryMid)
	for i, c in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
		tower("BelfryPost" .. i, Vector3.new(1.6, belfryH, 1.6), belfryMid, c[1] * (W / 2 - 0.8), c[2] * (W / 2 - 0.8))
	end
	-- Dark openings (louver holes) on the four faces of the belfry.
	local face = (W - 1.2) / 2 + 0.12
	local openY = belfryMid + 0.6
	for i, f in { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } } do
		local size = if f[1] == 0 then Vector3.new(2.6, 4.6, 0.3) else Vector3.new(0.3, 4.6, 2.6)
		tower("BelfryOpening" .. i, size, openY, f[1] * face, f[2] * face, pal.silhouette, Enum.Material.SmoothPlastic)
	end
	local corniceY = belfryLo + belfryH + 0.5
	tower("Cornice", Vector3.new(W + 1, 1, W + 1), corniceY)
	tower("RoofBase", Vector3.new(W - 1, 1.5, W - 1), corniceY + 1.25, 0, 0, pal.spire)
	local s = corniceY + 2
	local tierH = 6 * S
	for i, w in { 8, 5.5, 3.5, 2.0 } do
		tower("Spire" .. i, Vector3.new(w, tierH, w), s + tierH / 2, 0, 0, pal.spire)
		s += tierH
	end
	tower("CrossUp", Vector3.new(0.6, 4.4, 0.6), s + 2.2, 0, 0, pal.metal, Enum.Material.Metal)
	tower("CrossBar", Vector3.new(2.8, 0.6, 0.6), s + 3.1, 0, 0, pal.metal, Enum.Material.Metal)
	local steepleAnchor = parts.block(
		steepleF,
		"SteepleAnchor",
		Vector3.new(1, 1, 1),
		CFrame.new(st.x, wy + 6, st.z),
		pal.stone,
		Enum.Material.Slate,
		{ collide = false, query = false, shadow = false, transparency = 1 }
	)
	ctx.anchors.steeple = steepleAnchor
	-- The bell hangs in the belfry, under the surface. Cylinder axis is X, so turn it upright.
	local bellCF = frame * CFrame.new(0, belfryLo + 3.4, 0) * CFrame.Angles(0, 0, math.rad(90))
	local bell = parts.block(steepleF, "Bell", Vector3.new(3.2, 3.4, 3.4), bellCF, pal.bell, Enum.Material.Metal, {
		shape = "Cylinder",
	})
	parts.block(
		steepleF,
		"BellLip",
		Vector3.new(0.5, 4, 4),
		frame * CFrame.new(0, belfryLo + 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		pal.bell,
		Enum.Material.Metal,
		{ shape = "Cylinder" }
	)
	ctx.anchors.steepleBell = bell

	-- The old buoy: a float, a cage and a cap.
	local by = lake.buoy
	local buoyF = parts.folder(ctx.parent, "Buoy")
	local float = parts.block(
		buoyF,
		"Float",
		Vector3.new(3, 4.4, 4.4),
		CFrame.new(by.x, wy + 0.4, by.z) * CFrame.Angles(math.rad(4), 0, math.rad(90 + 5)),
		pal.buoy,
		Enum.Material.Metal,
		{ shape = "Cylinder" }
	)
	ctx.anchors.buoy = float
	for i = 1, 3 do
		local a = (i - 1) * 2 * math.pi / 3
		parts.block(
			buoyF,
			"Bar" .. i,
			Vector3.new(0.3, 4.2, 0.3),
			CFrame.new(by.x + math.cos(a) * 1.4, wy + 3.8, by.z + math.sin(a) * 1.4)
				* CFrame.Angles(math.rad(4), 0, math.rad(5)),
			pal.buoyCage,
			Enum.Material.CorrodedMetal
		)
	end
	parts.block(
		buoyF,
		"Cap",
		Vector3.new(3.4, 0.4, 3.4),
		CFrame.new(by.x + 0.2, wy + 6, by.z) * CFrame.Angles(math.rad(4), 0, math.rad(5)),
		pal.buoyCage,
		Enum.Material.CorrodedMetal
	)

	-- Reeds: clumps of thin stalks inside the reed disk and inside the lake.
	local rd = lake.reeds
	local reedF = parts.folder(ctx.parent, "Reeds")
	local placed, tries = 0, 0
	while placed < Landmarks.REED_CLUMPS and tries < Landmarks.REED_CLUMPS * 6 do
		tries += 1
		local a = Rng.range(rng, 0, 2 * math.pi)
		local r = rd.radius * math.sqrt(Rng.next(rng))
		local x, z = rd.x + math.cos(a) * r, rd.z + math.sin(a) * r
		if parts.ellipse(lake.radiusX - 6, lake.radiusZ - 6, x, z) < 1 then
			placed += 1
			for k = 1, 3 do
				local h = Rng.range(rng, 4, 8)
				local ox, oz = Rng.range(rng, -1.5, 1.5), Rng.range(rng, -1.5, 1.5)
				parts.block(
					reedF,
					"Reed" .. placed .. "_" .. k,
					Vector3.new(0.25, h, 0.25),
					CFrame.new(x + ox, wy - 1 + h / 2, z + oz)
						* CFrame.Angles(math.rad(Rng.range(rng, -12, 12)), 0, math.rad(Rng.range(rng, -12, 12))),
					pal.reed,
					Enum.Material.Grass,
					{ collide = false, shadow = false, query = false }
				)
			end
		end
	end
	if placed < Landmarks.REED_CLUMPS then
		table.insert(
			ctx.warnings,
			string.format("Landmarks: placed %d of %d reed clumps", placed, Landmarks.REED_CLUMPS)
		)
	end
	local reedAnchor = parts.block(
		reedF,
		"ReedsAnchor",
		Vector3.new(1, 1, 1),
		CFrame.new(rd.x, wy + 2, rd.z),
		pal.reed,
		Enum.Material.Grass,
		{ collide = false, query = false, shadow = false, transparency = 1 }
	)
	ctx.anchors.reeds = reedAnchor

	-- The narrows: a few dead snags and rocks on its rim so the stop has something to see.
	local nw = lake.narrows
	local narrowsF = parts.folder(ctx.parent, "Narrows")
	for i = 1, 7 do
		local a = Rng.range(rng, 0, 2 * math.pi)
		local r = nw.radius * Rng.range(rng, 0.7, 1.0)
		local x, z = nw.x + math.cos(a) * r, nw.z + math.sin(a) * r
		if parts.ellipse(lake.radiusX - 10, lake.radiusZ - 10, x, z) < 1 then
			local h = Rng.range(rng, 6, 14)
			parts.block(
				narrowsF,
				"Snag" .. i,
				Vector3.new(1.2, h, 1.2),
				CFrame.new(x, wy - 1 + h / 2, z)
					* CFrame.Angles(math.rad(Rng.range(rng, -18, 18)), 0, math.rad(Rng.range(rng, -18, 18))),
				pal.trunk,
				Enum.Material.Wood,
				{ collide = false }
			)
		end
	end
	for i = 1, 3 do
		local a = Rng.range(rng, 0, 2 * math.pi)
		local r = nw.radius * Rng.range(rng, 0.8, 1.1)
		local x, z = nw.x + math.cos(a) * r, nw.z + math.sin(a) * r
		if parts.ellipse(lake.radiusX - 10, lake.radiusZ - 10, x, z) < 1 then
			parts.block(
				narrowsF,
				"Rock" .. i,
				Vector3.new(Rng.range(rng, 4, 8), 3, Rng.range(rng, 4, 8)),
				CFrame.new(x, wy, z) * CFrame.Angles(0, Rng.range(rng, 0, 6.28), math.rad(Rng.range(rng, -10, 10))),
				pal.stone,
				Enum.Material.Rock,
				{ collide = false }
			)
		end
	end
	ctx.anchors.narrows = parts.block(
		narrowsF,
		"NarrowsAnchor",
		Vector3.new(1, 1, 1),
		CFrame.new(nw.x, wy + 2, nw.z),
		pal.stone,
		Enum.Material.Rock,
		{ collide = false, query = false, shadow = false, transparency = 1 }
	)
end

return Landmarks
