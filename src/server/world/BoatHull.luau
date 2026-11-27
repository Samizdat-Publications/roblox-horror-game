--!strict
-- The rowboat's geometry: hull, four seats, the bow lantern, the hold box, the motor and
-- oars. Every part is unanchored and welded to the Hull, which is the PrimaryPart and the
-- model's pivot. BoatService adds the drive constraints. No requires (Lune loads this).
--
-- Local frame: the Hull's center is the origin at the waterline, forward is -Z, port is -X.
-- Seats face: bow and helm forward, port seat out to port, starboard seat out to starboard.

local BoatHull = {}

BoatHull.LENGTH = 14
BoatHull.BEAM = 5.4
BoatHull.SEAT_ORDER = { "HelmSeat", "BowSeat", "PortSeat", "StarboardSeat" }

export type Built = {
	model: Model,
	hull: BasePart,
	seats: { [string]: Seat },
	lanternGlow: BasePart,
	lanternLight: PointLight,
	motor: BasePart,
	hold: BasePart,
}

function BoatHull.build(ctx: any, at: CFrame): Built
	local look, parts = ctx.look, ctx.parts
	local pal = look.Palette
	local model = Instance.new("Model")
	model.Name = "DeadCalmBoat"

	local G = "Boat"
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material, opts: any?)
		local o = opts or {}
		o.anchored = false
		o.group = G
		return parts.block(model, name, size, at * offset, color, mat, o)
	end
	local function p(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y, z)
	end

	local wood, trim = pal.boatWood, pal.boatTrim
	local hull = piece("Hull", Vector3.new(4.6, 0.5, 12), p(0, 0, 0), wood, Enum.Material.WoodPlanks)
	piece("SidePort", Vector3.new(0.4, 1.7, 12), p(-2.5, 0.75, 0), wood, Enum.Material.WoodPlanks)
	piece("SideStarboard", Vector3.new(0.4, 1.7, 12), p(2.5, 0.75, 0), wood, Enum.Material.WoodPlanks)
	piece("Transom", Vector3.new(5.4, 1.7, 0.4), p(0, 0.75, 6.1), wood, Enum.Material.WoodPlanks)
	-- Bow: two planks angled in to a point.
	local function bowPlank(name: string, side: number)
		local a = Vector3.new(side * 2.5, 0.85, -6)
		local b = Vector3.new(0, 0.85, -9)
		local mid = (a + b) / 2
		piece(
			name,
			Vector3.new(0.4, 1.9, (b - a).Magnitude + 0.3),
			CFrame.lookAt(mid, b),
			wood,
			Enum.Material.WoodPlanks
		)
	end
	bowPlank("BowPort", -1)
	bowPlank("BowStarboard", 1)
	piece("BowFloor", Vector3.new(2.4, 0.5, 2.8), p(0, 0, -7.2), wood, Enum.Material.WoodPlanks)
	piece("GunwalePort", Vector3.new(0.6, 0.25, 12), p(-2.5, 1.7, 0), trim, Enum.Material.Wood)
	piece("GunwaleStarboard", Vector3.new(0.6, 0.25, 12), p(2.5, 1.7, 0), trim, Enum.Material.Wood)
	piece("Keel", Vector3.new(0.5, 0.5, 14.5), p(0, -0.4, -1), trim, Enum.Material.Wood)

	-- Thwarts (benches) under the seats.
	piece("ThwartStern", Vector3.new(4.6, 0.3, 1.4), p(0, 0.6, 4.4), trim, Enum.Material.Wood)
	piece("ThwartMid", Vector3.new(4.6, 0.3, 1.4), p(0, 0.6, -1.4), trim, Enum.Material.Wood)
	piece("ThwartBow", Vector3.new(3.2, 0.3, 1.4), p(0, 0.6, -5.2), trim, Enum.Material.Wood)

	local seats: { [string]: Seat } = {}
	local function seat(name: string, offset: CFrame)
		local s = piece(name, Vector3.new(2, 0.4, 1.6), offset, pal.seat, Enum.Material.Wood, { class = "Seat" })
		local st = s :: any
		st.Disabled = false
		seats[name] = st :: Seat
	end
	-- A Seat's occupant faces the seat's LookVector (-Z). Helm and bow keep the hull's
	-- orientation, so they face the bow; BoatService moors the boat bow out (+z, north).
	seat("HelmSeat", p(0, 0.95, 4.4))
	seat("BowSeat", p(0, 0.95, -5.2))
	seat("PortSeat", p(-1.15, 0.95, -1.4) * CFrame.Angles(0, math.rad(90), 0))
	seat("StarboardSeat", p(1.15, 0.95, -1.4) * CFrame.Angles(0, math.rad(-90), 0))

	-- The hold box (a cooler-sized wooden crate) in the middle, in hull wood tones.
	local hold =
		piece("Hold", Vector3.new(2.2, 1.3, 1.6), p(0, 0.9, 1.6), wood:Lerp(trim, 0.45), Enum.Material.WoodPlanks)
	piece("HoldLid", Vector3.new(2.3, 0.2, 1.7), p(0, 1.65, 1.6), trim, Enum.Material.Wood)

	-- The lantern on a post at the bow.
	-- The post, arm and cap cast no shadow: from the lantern they threw a black wedge straight
	-- down the middle of the boat, right where the helm looks (Studio 11/26/2026).
	-- Polish round 2 (Neon finale v7: the lantern sat dead centre on the horizon in the seated
	-- view): the post is 1 stud shorter (foot unchanged) and the arm, cap and glass come down
	-- with it, so the lantern sits just below the horizon line. Light and shadows unchanged.
	piece("LanternPost", Vector3.new(0.3, 3.4, 0.3), p(0, 1.9, -7.4), trim, Enum.Material.Wood, { shadow = false })
	piece(
		"LanternArm",
		Vector3.new(0.25, 0.25, 1.3),
		p(0, 3.5, -7.95),
		pal.metal,
		Enum.Material.Metal,
		{ shadow = false }
	)
	piece(
		"LanternCap",
		Vector3.new(0.9, 0.2, 0.9),
		p(0, 3.35, -8.55),
		pal.metal,
		Enum.Material.Metal,
		{ shadow = false }
	)
	local glow = piece(
		"LanternGlow",
		Vector3.new(0.75, 0.75, 0.75),
		p(0, 2.85, -8.55),
		-- A deeper orange than the light itself: Neon plus bloom washes a lantern-colored ball to
		-- lemon yellow (seen in Studio 11/26/2026).
		Color3.fromRGB(255, 118, 36),
		Enum.Material.Neon,
		{ shape = "Ball", shadow = false, collide = false }
	)
	local light = parts.light(glow, "LanternLight", look.Lantern)

	-- Outboard motor on the transom, and a tiller.
	local motor = piece("Motor", Vector3.new(1.2, 1.6, 1.2), p(0, 1.9, 6.8), pal.motor, Enum.Material.Metal)
	piece("MotorShaft", Vector3.new(0.4, 2.6, 0.4), p(0, 0.2, 7), pal.motor, Enum.Material.Metal, { collide = false })
	piece("Tiller", Vector3.new(0.2, 0.2, 1.6), p(0, 2.2, 5.6), pal.metal, Enum.Material.Metal, { collide = false })

	-- Oars resting along the inside of the hull.
	piece("OarPort", Vector3.new(0.3, 0.2, 7), p(-1.9, 1.15, 0.2), trim, Enum.Material.Wood, { collide = false })
	piece("OarStarboard", Vector3.new(0.3, 0.2, 7), p(1.9, 1.15, 0.2), trim, Enum.Material.Wood, { collide = false })

	-- Weld everything to the hull. Only the hull carries mass, so the drive is predictable.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= hull then
			d.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = hull
			w.Part1 = d
			w.Parent = d
		end
	end
	model.PrimaryPart = hull

	return {
		model = model,
		hull = hull,
		seats = seats,
		lanternGlow = glow,
		lanternLight = light,
		motor = motor,
		hold = hold,
	}
end

return BoatHull
