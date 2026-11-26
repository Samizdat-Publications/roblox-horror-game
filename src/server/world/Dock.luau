--!strict
-- The dock (sagging planks on posts), the cooler and oil can at its end, the beacon on its
-- pole, the bait shack with a lit window and the radio, and the spawn point on shore.
-- ctx fields: see world/Assemble.luau. Anchors set here: dockEnd, cooler, oilCan,
-- beaconLamp, beaconLight, shackRadio, shackWindow.

local Dock = {}

Dock.name = "Dock"

Dock.WIDTH = 8
Dock.DECK_HEIGHT = 2.2 -- deck top above the water
Dock.PLANK_STEP = 1.8
Dock.SAG = 0.9

function Dock.build(ctx: any)
	local cfg, look, parts, Rng, rng = ctx.cfg, ctx.look, ctx.parts, ctx.Rng, ctx.rng
	local lake = cfg.Lake
	local pal = look.Palette
	local wy = lake.waterY
	local bedY = ctx.anchors.bedY or (wy - 4.5)

	local foot, tip = lake.dockFoot, lake.dockEnd
	-- The dock runs from 18 studs inland of its foot to its end. It is built along +z from
	-- the foot; the brief's layout has the dock pointing north, so direction is (tip - foot).
	local dx, dz = tip.x - foot.x, tip.z - foot.z
	local dlen = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / dlen, dz / dlen
	local startX, startZ = foot.x - ux * 18, foot.z - uz * 18
	local length = dlen + 18
	local deckY = wy + Dock.DECK_HEIGHT
	local along = parts.facing(Vector3.new(startX, 0, startZ), Vector3.new(ux, 0, uz))

	local deck = parts.folder(ctx.parent, "Deck")

	-- Planks. t runs 0 at the inland start to 1 at the end; the sag peaks mid-span over water.
	local n = math.floor(length / Dock.PLANK_STEP)
	for i = 0, n do
		local d = i * Dock.PLANK_STEP + Dock.PLANK_STEP / 2
		local overWater = d > 18
		local missing = overWater and d < length - 8 and Rng.next(rng) < 0.05
		if not missing then
			local sag = if overWater then Dock.SAG * math.sin(math.pi * (d - 18) / dlen) else 0
			local y = deckY - 0.18 - sag + Rng.range(rng, -0.06, 0.06)
			local cf = along
				* CFrame.new(Rng.range(rng, -0.15, 0.15), y, -d)
				* CFrame.Angles(
					math.rad(Rng.range(rng, -1.5, 1.5)),
					math.rad(Rng.range(rng, -2, 2)),
					math.rad(Rng.range(rng, -2.5, 2.5))
				)
			parts.block(
				deck,
				"Plank" .. i,
				Vector3.new(Dock.WIDTH + Rng.range(rng, -0.3, 0.4), 0.35, Dock.PLANK_STEP - 0.2),
				cf,
				pal.dockWood:Lerp(pal.dockPost, Rng.range(rng, 0, 0.35)),
				Enum.Material.WoodPlanks
			)
		end
	end

	-- Stringers under the planks, in four pieces each side so they follow the sag.
	for side = -1, 1, 2 do
		for seg = 0, 3 do
			local d0 = seg * length / 4
			local d1 = (seg + 1) * length / 4
			local function sagAt(d: number): number
				if d <= 18 then
					return 0
				end
				return Dock.SAG * math.sin(math.pi * (d - 18) / dlen)
			end
			local y0 = deckY - 0.6 - sagAt(d0)
			local y1 = deckY - 0.6 - sagAt(d1)
			local p0 = (along * CFrame.new(side * (Dock.WIDTH / 2 - 0.6), y0, -d0)).Position
			local p1 = (along * CFrame.new(side * (Dock.WIDTH / 2 - 0.6), y1, -d1)).Position
			local mid = (p0 + p1) / 2
			parts.block(
				deck,
				"Stringer" .. side .. "_" .. seg,
				Vector3.new(0.6, 0.6, (p1 - p0).Magnitude + 0.2),
				CFrame.lookAt(mid, p1),
				pal.dockPost,
				Enum.Material.Wood
			)
		end
	end

	-- Posts every 9.5 studs over the water, slightly crooked.
	local posts = parts.folder(ctx.parent, "Posts")
	local d = 18
	local k = 0
	while d <= length + 0.1 do
		for side = -1, 1, 2 do
			k += 1
			local sag = Dock.SAG * math.sin(math.pi * math.clamp((d - 18) / dlen, 0, 1))
			local top = deckY - 0.5 - sag
			local h = top - (bedY - 1)
			local pos = (along * CFrame.new(side * (Dock.WIDTH / 2 + 0.2), top - h / 2, -d)).Position
			parts.block(
				posts,
				"Post" .. k,
				Vector3.new(0.9, h, 0.9),
				CFrame.new(pos) * CFrame.Angles(math.rad(Rng.range(rng, -3, 3)), 0, math.rad(Rng.range(rng, -3, 3))),
				pal.dockPost,
				Enum.Material.Wood
			)
		end
		d += 9.5
	end
	-- A taller tie post at the end corner.
	local tiePos = (along * CFrame.new(Dock.WIDTH / 2 + 0.3, deckY + 0.6, -length + 0.4)).Position
	parts.block(posts, "TiePost", Vector3.new(0.8, 3.6, 0.8), CFrame.new(tiePos), pal.dockPost, Enum.Material.Wood)

	-- The end of the dock: where the boat ties up and the cooler sits.
	local endCF = along * CFrame.new(0, deckY - Dock.SAG * 0.05, -length)
	local endAnchor = parts.block(
		ctx.parent,
		"DockEnd",
		Vector3.new(1, 1, 1),
		CFrame.new(tip.x, deckY, tip.z),
		pal.dockPost,
		Enum.Material.Wood,
		{ collide = false, query = false, shadow = false, transparency = 1 }
	)
	ctx.anchors.dockEnd = endAnchor

	local cooler = parts.block(
		ctx.parent,
		"DockCooler",
		Vector3.new(3, 1.8, 2),
		endCF * CFrame.new(-2, 0.9, 2.2),
		pal.cooler,
		Enum.Material.SmoothPlastic
	)
	parts.block(
		cooler,
		"Lid",
		Vector3.new(3.1, 0.25, 2.1),
		endCF * CFrame.new(-2, 1.9, 2.2),
		pal.cooler:Lerp(pal.ink, 0.2),
		Enum.Material.SmoothPlastic
	)
	ctx.anchors.cooler = cooler

	local oil = parts.block(
		ctx.parent,
		"OilCan",
		Vector3.new(1.2, 1.4, 1.2),
		endCF * CFrame.new(1.6, 0.7, 2.6),
		Color3.fromRGB(110, 40, 30),
		Enum.Material.Metal
	)
	ctx.anchors.oilCan = oil

	-- The beacon: a pole by the dock with a warm lamp. The client makes it blink twice.
	local beacon = lake.beacon
	local poleH = beacon.height - (bedY - 1)
	parts.block(
		ctx.parent,
		"BeaconPole",
		Vector3.new(1.2, poleH, 1.2),
		CFrame.new(beacon.x + 6, beacon.height - poleH / 2, beacon.z),
		pal.dockPost,
		Enum.Material.Wood
	)
	parts.block(
		ctx.parent,
		"BeaconHousing",
		Vector3.new(2.6, 2.4, 2.6),
		CFrame.new(beacon.x + 6, beacon.height + 1.2, beacon.z),
		pal.metal,
		Enum.Material.Metal
	)
	local lamp = parts.block(
		ctx.parent,
		"BeaconLamp",
		Vector3.new(1.9, 1.9, 1.9),
		CFrame.new(beacon.x + 6, beacon.height + 3.2, beacon.z),
		look.Beacon.Color,
		Enum.Material.Neon,
		{ shape = "Ball", shadow = false }
	)
	ctx.anchors.beaconLamp = lamp
	ctx.anchors.beaconLight = parts.light(lamp, "BeaconLight", look.Beacon)

	-- The bait shack, facing the lake (north), with a lit window and the radio inside.
	local shack = lake.shack
	local sw, sd, sh = 16, 12, 9
	local floorY = wy + 2.2
	local base = CFrame.new(shack.x, floorY, shack.z)
	local shackF = parts.folder(ctx.parent, "Shack")
	local wall, roof = pal.shackWall, pal.shackRoof
	local function sb(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material, opts: any?)
		return parts.block(shackF, name, size, base * offset, color, mat, opts)
	end
	sb("Floor", Vector3.new(sw, 1, sd), CFrame.new(0, -0.5, 0), pal.dockPost, Enum.Material.WoodPlanks)
	sb("WallSouth", Vector3.new(sw, sh, 0.6), CFrame.new(0, sh / 2, -sd / 2), wall, Enum.Material.WoodPlanks)
	sb("WallWest", Vector3.new(0.6, sh, sd), CFrame.new(-sw / 2, sh / 2, 0), wall, Enum.Material.WoodPlanks)
	sb("WallEast", Vector3.new(0.6, sh, sd), CFrame.new(sw / 2, sh / 2, 0), wall, Enum.Material.WoodPlanks)
	-- North wall (+z, facing the lake) with a door on the west side and a window on the east.
	local wz = sd / 2
	sb("WallNorthA", Vector3.new(3, sh, 0.6), CFrame.new(-6.5, sh / 2, wz), wall, Enum.Material.WoodPlanks)
	sb("Door", Vector3.new(3, 7, 0.4), CFrame.new(-3.5, 3.5, wz + 0.1), pal.dockPost, Enum.Material.Wood)
	sb(
		"WallNorthB",
		Vector3.new(3, sh - 7, 0.6),
		CFrame.new(-3.5, 7 + (sh - 7) / 2, wz),
		wall,
		Enum.Material.WoodPlanks
	)
	sb("WallNorthC", Vector3.new(2, sh, 0.6), CFrame.new(-1, sh / 2, wz), wall, Enum.Material.WoodPlanks)
	sb("WallNorthBelow", Vector3.new(4, 3.5, 0.6), CFrame.new(2, 1.75, wz), wall, Enum.Material.WoodPlanks)
	sb(
		"WallNorthAbove",
		Vector3.new(4, sh - 6.5, 0.6),
		CFrame.new(2, 6.5 + (sh - 6.5) / 2, wz),
		wall,
		Enum.Material.WoodPlanks
	)
	sb("WallNorthD", Vector3.new(4, sh, 0.6), CFrame.new(6, sh / 2, wz), wall, Enum.Material.WoodPlanks)
	local window = sb(
		"Window",
		Vector3.new(4, 3, 0.2),
		CFrame.new(2, 5, wz),
		look.Palette.window,
		Enum.Material.Neon,
		{ transparency = 0.25, shadow = false }
	)
	ctx.anchors.shackWindow = window
	-- Gable roof, ridge along x.
	local pitch = math.rad(28)
	local half = sd / 2 + 1
	local slant = half / math.cos(pitch)
	local rise = math.tan(pitch) * half
	sb(
		"RoofNorth",
		Vector3.new(sw + 2, 0.6, slant),
		CFrame.new(0, sh + rise / 2, half / 2) * CFrame.Angles(pitch, 0, 0),
		roof,
		Enum.Material.Slate
	)
	sb(
		"RoofSouth",
		Vector3.new(sw + 2, 0.6, slant),
		CFrame.new(0, sh + rise / 2, -half / 2) * CFrame.Angles(-pitch, 0, 0),
		roof,
		Enum.Material.Slate
	)
	sb(
		"GableEast",
		Vector3.new(0.6, rise, sd - 2),
		CFrame.new(sw / 2, sh + rise / 2 - 0.3, 0),
		wall,
		Enum.Material.WoodPlanks
	)
	sb(
		"GableWest",
		Vector3.new(0.6, rise, sd - 2),
		CFrame.new(-sw / 2, sh + rise / 2 - 0.3, 0),
		wall,
		Enum.Material.WoodPlanks
	)
	sb("Step", Vector3.new(4, 0.6, 2), CFrame.new(-3.5, -1.2, wz + 1.3), pal.dockPost, Enum.Material.Wood)
	-- Inside: a shelf under the window, the radio on it, and the warm light.
	sb("Shelf", Vector3.new(5, 0.4, 1.6), CFrame.new(2, 3.2, wz - 1.2), pal.dockPost, Enum.Material.Wood)
	local radio = sb(
		"ShackRadio",
		Vector3.new(1.8, 1.1, 0.9),
		CFrame.new(2, 3.95, wz - 1.2),
		Color3.fromRGB(70, 52, 36),
		Enum.Material.Wood
	)
	sb(
		"RadioDial",
		Vector3.new(0.6, 0.6, 0.1),
		CFrame.new(2.4, 4.0, wz - 0.72),
		look.Palette.window,
		Enum.Material.Neon,
		{ shadow = false }
	)
	ctx.anchors.shackRadio = radio
	local lightHolder = sb(
		"ShackLightHolder",
		Vector3.new(0.4, 0.4, 0.4),
		CFrame.new(1, 6.5, 0),
		look.Palette.window,
		Enum.Material.Neon,
		{ shadow = false, collide = false }
	)
	parts.light(lightHolder, "WindowLight", look.Window)

	-- Spawn on shore beside the shack. Players are seated in the boat automatically, so this
	-- is only where a fresh character appears for a moment.
	local spawn = parts.block(
		ctx.parent,
		"Spawn",
		Vector3.new(6, 1, 6),
		CFrame.new(shack.x + 16, wy + 1.2, shack.z + 8),
		pal.dockPost,
		Enum.Material.WoodPlanks,
		{ class = "SpawnLocation" }
	)
	local sp = spawn :: any
	sp.Neutral = true
	sp.Duration = 0
end

return Dock
