--!strict
-- The lake surface and the lake bed. Water is one large flat Part (decided in the brief):
-- dark, slightly glossy, not collidable, with a bed a few studs down so a swimmer wades.
-- ctx fields: see world/Assemble.luau.

local Water = {}

Water.name = "Water"

Water.BED_DEPTH = 4.5 -- studs below the surface: a character's head stays above water

function Water.build(ctx: any)
	local cfg, look, parts = ctx.cfg, ctx.look, ctx.parts
	local lake = cfg.Lake
	local y = lake.waterY

	-- Covers the ellipse plus a margin that runs under the shore ring. Under 2048 per axis.
	local sx = math.min(2040, lake.radiusX * 2 + 80)
	local sz = math.min(2040, lake.radiusZ * 2 + 80)

	local water = parts.block(
		ctx.parent,
		"Water",
		Vector3.new(sx, 1, sz),
		CFrame.new(0, y - 0.5, 0),
		-- The design palette's water (#0B1418) rendered pure black in Studio on 11/26/2026.
		-- The surface is lifted to this and lets the lighting do the darkening.
		Color3.fromRGB(30, 58, 62),
		Enum.Material.SmoothPlastic,
		{ collide = false, shadow = false, reflectance = 0.28 }
	)
	water:SetAttribute("WaterY", y)
	ctx.anchors.water = water

	local bedTop = y - Water.BED_DEPTH
	parts.block(
		ctx.parent,
		"LakeBed",
		Vector3.new(sx, 2, sz),
		CFrame.new(0, bedTop - 1, 0),
		look.Palette.lakeBed,
		Enum.Material.Mud,
		{ shadow = false }
	)
	ctx.anchors.bedY = bedTop
end

return Water
