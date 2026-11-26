--!strict
-- A fish built from parts, from a species and the traits the players see. A wrong fish is
-- built from its (mutated) traits, so it visibly looks wrong: a third eye, an extra back
-- fin, the wrong tail, a glow, eyelids that blink, an eye looking the wrong way, a fin on
-- the belly. The server builds the fish on the line and the Field Guide drawings; the
-- client clones them (it never sees a `wrong` flag, only the shape).
--
-- No requires and no services (like the world builders): ctx = { parts, look }.
-- Fish frame: the Body's center is the origin, the head points along -Z (LookVector), up is
-- +Y, the sides are +-X. The model's PrimaryPart is the Body; a "Mouth" Attachment sits on
-- the Body at the head end.

local FishModel = {}

FishModel.EYE_NAME = "Eye"
FishModel.PUPIL_NAME = "Pupil"
FishModel.LID_NAME = "Eyelid"

export type Traits = {
	eyes: number,
	dorsal: number,
	stripes: number,
	barbels: number,
	tail: string,
	eyeshine: boolean,
	glow: boolean,
	blinks: boolean,
	wrongEyeDir: boolean?,
	flipFin: boolean?,
}

-- Half-width of the body ellipsoid at height y and length position z (0 outside).
local function sideX(w: number, h: number, l: number, y: number, z: number): number
	local k = 1 - (y / (h / 2)) ^ 2 - (z / (l / 2)) ^ 2
	if k <= 0 then
		return 0
	end
	return (w / 2) * math.sqrt(k)
end

-- Height of the top of the body at length position z.
local function topY(h: number, l: number, z: number): number
	local k = 1 - (z / (l / 2)) ^ 2
	if k <= 0 then
		return 0
	end
	return (h / 2) * math.sqrt(k)
end

local function ellipsoid(part: BasePart)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = part
end

-- Builds the fish at `at` (the Body's CFrame). opts.anchored (default true), opts.group
-- (collision group, default "Default").
function FishModel.build(ctx: any, species: string, traits: Traits, at: CFrame, opts: any?): Model
	local o = opts or {}
	local parts, look = ctx.parts, ctx.look
	local F = look.Fish
	local spec = F[species] or F.Pumpkinseed
	local L, H, W = spec.length, spec.height, spec.width
	local anchored = if o.anchored == nil then true else o.anchored
	local group = o.group or "Default"

	local model = Instance.new("Model")
	model.Name = "Fish_" .. species

	local function piece(
		name: string,
		size: Vector3,
		offset: CFrame,
		color: Color3,
		mat: Enum.Material,
		extra: any?
	): BasePart
		local e = extra or {}
		return parts.block(model, name, size, at * offset, color, mat, {
			anchored = anchored,
			collide = false,
			query = false,
			shadow = false,
			group = group,
			shape = e.shape,
			class = e.class,
			transparency = e.transparency,
		})
	end

	local body = piece("Body", Vector3.new(W, H, L), CFrame.new(), spec.body, Enum.Material.SmoothPlastic)
	ellipsoid(body)
	local mouth = Instance.new("Attachment")
	mouth.Name = "Mouth"
	mouth.Position = Vector3.new(0, 0, -L / 2)
	mouth.Parent = body

	-- Stripes: thin ellipsoid slices a little larger than the body, so only a dark ring shows.
	local n = math.max(0, math.floor(traits.stripes))
	for i = 1, n do
		local z = -0.22 * L + (i - 0.5) / n * 0.5 * L
		local k = math.sqrt(math.max(0.05, 1 - (z / (L / 2)) ^ 2))
		local bar = piece(
			"Bar" .. i,
			Vector3.new(W * k * 1.06, H * k * 1.04, 0.1),
			CFrame.new(0, 0, z),
			spec.bar,
			Enum.Material.SmoothPlastic
		)
		ellipsoid(bar)
	end

	-- Eyes: a pair on the sides, then one on top of the head, then more pairs further back.
	local eyeR = math.clamp(H * 0.2, 0.14, 0.24)
	local eyeY, eyeZ = H * 0.12, -L * 0.34
	local spots: { { pos: Vector3, out: Vector3 } } = {}
	local count = math.max(0, math.floor(traits.eyes))
	local function sidePair(z: number)
		local x = sideX(W, H, L, eyeY, z) * 0.9
		table.insert(spots, { pos = Vector3.new(x, eyeY, z), out = Vector3.new(1, 0, 0) })
		table.insert(spots, { pos = Vector3.new(-x, eyeY, z), out = Vector3.new(-1, 0, 0) })
	end
	if count == 1 then
		table.insert(spots, { pos = Vector3.new(0, topY(H, L, eyeZ) * 0.92, eyeZ), out = Vector3.new(0, 1, 0) })
	else
		sidePair(eyeZ)
		if count >= 3 then
			local tz = eyeZ + L * 0.06
			table.insert(spots, { pos = Vector3.new(0, topY(H, L, tz) * 0.92, tz), out = Vector3.new(0, 1, 0) })
		end
		local extraPairs = math.max(0, math.ceil((count - 3) / 2))
		for p = 1, extraPairs do
			sidePair(eyeZ + p * L * 0.1)
		end
	end
	local eyeMat = if traits.eyeshine then Enum.Material.Neon else Enum.Material.SmoothPlastic
	local eyeColor = if traits.eyeshine then look.Palette.pinEyes else F.eye
	for i = 1, math.min(count, #spots) do
		local s = spots[i]
		piece(
			FishModel.EYE_NAME,
			Vector3.new(eyeR, eyeR, eyeR),
			CFrame.new(s.pos),
			eyeColor,
			eyeMat,
			{ shape = "Ball" }
		)
		-- The pupil looks out to the side, or (wrongEyeDir, first eye) back toward the tail and up.
		local look2 = s.out
		if traits.wrongEyeDir and i == 1 then
			look2 = (s.out * 0.3 + Vector3.new(0, 0.5, 1)).Unit
		end
		local pr = eyeR * 0.55
		piece(
			FishModel.PUPIL_NAME,
			Vector3.new(pr, pr, pr),
			CFrame.new(s.pos + look2 * eyeR * 0.3),
			look.Fish.pupil,
			Enum.Material.SmoothPlastic,
			{ shape = "Ball" }
		)
		if traits.blinks then
			local lr = eyeR * 1.12
			piece(
				FishModel.LID_NAME,
				Vector3.new(lr, lr, lr),
				CFrame.new(s.pos),
				spec.body,
				Enum.Material.SmoothPlastic,
				{ shape = "Ball", transparency = 1 }
			)
		end
	end

	-- Back fins along the top. A wedge's tall edge faces +Z, so it sweeps back to the tail.
	local d = math.max(0, math.floor(traits.dorsal))
	local finH = H * (if spec.tallFin then 0.75 else 0.42)
	local finL = L * (if d >= 2 then 0.18 else 0.26)
	local function finAt(i: number): number
		if spec.finBack and d == 1 then
			return L * 0.22
		end
		if d <= 1 then
			return -L * 0.02
		end
		return -L * 0.16 + (i - 1) / (d - 1) * L * 0.36
	end
	for i = 1, d do
		local z = finAt(i)
		local y = topY(H, L, z) + finH / 2 - H * 0.06
		piece(
			"BackFin" .. i,
			Vector3.new(0.06, finH, finL),
			CFrame.new(0, y, z),
			spec.fin,
			Enum.Material.SmoothPlastic,
			{ class = "WedgePart" }
		)
	end
	-- flipFin: a back fin on the belly, upside down.
	if traits.flipFin then
		local z = finAt(1)
		local y = -(topY(H, L, z) + finH / 2 - H * 0.06)
		piece(
			"BellyFin",
			Vector3.new(0.06, finH, finL),
			CFrame.new(0, y, z) * CFrame.Angles(0, 0, math.pi),
			spec.fin,
			Enum.Material.SmoothPlastic,
			{ class = "WedgePart" }
		)
	end

	-- Whiskers fan out from the mouth, half on each side, angled down.
	local b = math.max(0, math.floor(traits.barbels))
	local bl = L * 0.28
	for i = 1, b do
		local side = if i % 2 == 1 then 1 else -1
		local j = math.ceil(i / 2)
		local per = math.max(1, math.ceil(b / 2))
		local spread = if per == 1 then 0.5 else 0.25 + (j - 1) / (per - 1) * 0.6
		local down = -0.25 - (j - 1) * 0.15
		local dir = Vector3.new(side * spread, down, -0.6).Unit
		local base = Vector3.new(side * W * 0.15, -H * 0.12, -L * 0.47)
		local mid = base + dir * bl / 2
		piece(
			"Whisker" .. i,
			Vector3.new(0.04, 0.04, bl),
			CFrame.lookAt(mid, mid + dir),
			spec.fin,
			Enum.Material.SmoothPlastic
		)
	end

	-- Tail at the back (+Z).
	local tz = L / 2
	local tl = L * 0.3
	local tail = traits.tail
	if tail == "Round" then
		local dsz = H * 0.8
		piece(
			"Tail",
			Vector3.new(0.06, dsz, dsz),
			CFrame.new(0, 0, tz + dsz * 0.32),
			spec.fin,
			Enum.Material.SmoothPlastic,
			{ shape = "Cylinder" }
		)
	elseif tail == "Square" then
		piece(
			"Tail",
			Vector3.new(0.06, H * 0.8, tl * 0.8),
			CFrame.new(0, 0, tz + tl * 0.35),
			spec.fin,
			Enum.Material.SmoothPlastic
		)
	else
		-- Forked: two lobes in a V. Uneven: the upper lobe is longer (a sturgeon's tail).
		local upper = if tail == "Uneven" then tl * 1.5 else tl
		local lower = if tail == "Uneven" then tl * 0.7 else tl
		local function lobe(name: string, len: number, ang: number)
			local dir = Vector3.new(0, math.sin(ang), math.cos(ang))
			local base = Vector3.new(0, 0, tz - 0.05)
			local mid = base + dir * len / 2
			piece(
				name,
				Vector3.new(0.06, H * 0.22, len),
				CFrame.lookAt(mid, mid + dir),
				spec.fin,
				Enum.Material.SmoothPlastic
			)
		end
		lobe("TailUpper", upper, math.rad(35))
		lobe("TailLower", lower, math.rad(-35))
	end

	-- Glow: a faint shell and a small light. Nothing in the book glows.
	if traits.glow then
		local shell = piece(
			"Glow",
			Vector3.new(W * 1.12, H * 1.12, L * 1.06),
			CFrame.new(),
			look.Palette.wrongGlow,
			Enum.Material.Neon,
			{ transparency = F.glowTransparency }
		)
		ellipsoid(shell)
		local light = Instance.new("PointLight")
		light.Name = "GlowLight"
		light.Color = look.Palette.wrongGlow
		light.Range = F.glowRange
		light.Brightness = F.glowBrightness
		light.Shadows = false
		light.Parent = shell
	end

	model.PrimaryPart = body
	if not anchored then
		for _, x in model:GetDescendants() do
			if x:IsA("BasePart") and x ~= body then
				x.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = body
				weld.Part1 = x
				weld.Parent = x
			end
		end
		body.Massless = true
	end

	model:SetAttribute("Species", species)
	model:SetAttribute("Eyes", count)
	model:SetAttribute("Dorsal", d)
	model:SetAttribute("Stripes", n)
	model:SetAttribute("Barbels", b)
	model:SetAttribute("Tail", tail)
	model:SetAttribute("Eyeshine", traits.eyeshine == true)
	model:SetAttribute("Glow", traits.glow == true)
	model:SetAttribute("Blinks", traits.blinks == true)
	model:SetAttribute("WrongEyeDir", traits.wrongEyeDir == true)
	model:SetAttribute("FlipFin", traits.flipFin == true)
	model:SetAttribute("Length", L)
	return model
end

-- Plain summary of a built fish (for DebugDriver).
function FishModel.summary(model: Model): { [string]: any }
	local parts = 0
	for _, x in model:GetDescendants() do
		if x:IsA("BasePart") then
			parts += 1
		end
	end
	return {
		species = model:GetAttribute("Species"),
		eyes = model:GetAttribute("Eyes"),
		dorsal = model:GetAttribute("Dorsal"),
		stripes = model:GetAttribute("Stripes"),
		barbels = model:GetAttribute("Barbels"),
		tail = model:GetAttribute("Tail"),
		eyeshine = model:GetAttribute("Eyeshine"),
		glow = model:GetAttribute("Glow"),
		blinks = model:GetAttribute("Blinks"),
		wrongEyeDir = model:GetAttribute("WrongEyeDir"),
		flipFin = model:GetAttribute("FlipFin"),
		parts = parts,
	}
end

-- Blink animation step for any fish with eyelids: shut for blinkFor every blinkEvery.
-- `t` is a clock in seconds; `seed` staggers fish. Returns nothing; sets Transparency.
function FishModel.animateLids(model: Model, look: any, t: number, seed: number)
	local F = look.Fish
	local period = (F.blinkEvery[1] + F.blinkEvery[2]) / 2
	local phase = (t + seed * 0.731) % period
	local shut = phase < F.blinkFor
	for _, x in model:GetDescendants() do
		if x:IsA("BasePart") and x.Name == FishModel.LID_NAME then
			x.Transparency = if shut then 0 else 1
		end
	end
end

return FishModel
