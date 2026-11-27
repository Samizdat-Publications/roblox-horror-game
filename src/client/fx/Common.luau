--!strict
-- Shared helpers for the rule presentations (client/fx/*): local parts in one folder, world
-- positions from lake Vec2s, ground height by raycast, figures built from parts, fades,
-- and the drowned's outlines (things only a dead player can see).
-- Everything here is local to this client and never replicated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))

local Common = {}

Common.FOLDER = "DeadCalmFx"
Common.OUTLINE = Color3.fromRGB(150, 205, 230) -- the drowned's outline color

local folder: Folder? = nil
local drowned = false

-- Models the drowned see outlined, and parts only the drowned see at all.
local outlined: { [Instance]: Color3 } = {}
local highlights: { [Instance]: Highlight } = {}
local ghostOnly: { [BasePart]: number } = {} -- part -> its transparency when shown

function Common.folder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = Common.FOLDER
	nf.Parent = Workspace
	folder = nf
	return nf
end

export type PartOpts = {
	shape: Enum.PartType?,
	transparency: number?,
	parent: Instance?,
	reflectance: number?,
}

function Common.part(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	opts: PartOpts?
): Part
	local o: PartOpts = opts or {}
	local p = Instance.new("Part")
	p.Name = name
	if o.shape then
		p.Shape = o.shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = o.transparency or 0
	p.Reflectance = o.reflectance or 0
	p.Parent = o.parent or Common.folder()
	return p
end

-- A world point on the water from a lake Vec2 ({x, z}).
function Common.water(v: any, lift: number?): Vector3
	local x = if type(v) == "table" then tonumber(v.x) or 0 else 0
	local z = if type(v) == "table" then tonumber(v.z) or 0 else 0
	return Vector3.new(x, Config.Lake.waterY + (lift or 0), z)
end

-- The ground height at (x, z): a downward ray against the world (not the boat or the fx).
function Common.groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local world = Workspace:FindFirstChild("DeadCalmWorld")
	if world == nil then
		return Config.Lake.waterY + 3
	end
	-- Only the ground and the bank, so a tree canopy never counts as the ground.
	local only: { Instance } = {}
	for _, name in { "Ground", "Bank" } do
		local f = world:FindFirstChild(name, true)
		if f then
			table.insert(only, f)
		end
	end
	params.FilterDescendantsInstances = if #only > 0 then only else { world }
	local hit = Workspace:Raycast(Vector3.new(x, 300, z), Vector3.new(0, -400, 0), params)
	if hit then
		return math.max(hit.Position.Y, Config.Lake.waterY)
	end
	return Config.Lake.waterY + 3
end

-- An invisible anchor for a spatial sound.
function Common.emitter(pos: Vector3): Part
	return Common.part("Emitter", Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), Color3.new(), nil, { transparency = 1 })
end

-- Fades every part of a model (or one part) to invisible over `seconds`, then destroys it.
function Common.fadeOut(inst: Instance, seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	local list: { Instance } = { inst }
	for _, d in inst:GetDescendants() do
		table.insert(list, d)
	end
	for _, d in list do
		if d:IsA("BasePart") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("Light") then
			TweenService:Create(d, info, { Brightness = 0 }):Play()
		end
	end
	task.delay(seconds + 0.1, function()
		inst:Destroy()
	end)
end

export type Figure = {
	model: Model,
	root: CFrame, -- feet center, facing -Z of the root
	arm: BasePart?, -- the right arm, pivoting at the shoulder (waving figures)
	shoulder: Vector3?, -- the right shoulder in root space
	armLen: number,
	eyes: { BasePart },
	locals: { [BasePart]: CFrame }, -- each part's place in the root frame
}

export type FigureOpts = {
	height: number, -- studs, feet to crown
	width: number, -- shoulder width
	eyes: boolean?, -- pin eyes
	seated: boolean?, -- sitting (the Neighbor in its boat)
}

-- A silhouette built from parts: legs, torso, head and arms in the silhouette color,
-- optional pin eyes. The model's parts are anchored; place it with Common.placeFigure.
function Common.figure(name: string, o: FigureOpts): Figure
	local m = Instance.new("Model")
	m.Name = name
	local black = Look.Palette.silhouette
	local h, w = o.height, o.width
	local legH = if o.seated then h * 0.18 else h * 0.46
	local torsoH = h * 0.36
	local headH = h * 0.12
	local base = CFrame.new()
	local locals: { [BasePart]: CFrame } = {}
	local function piece(pn: string, size: Vector3, at: CFrame): BasePart
		local p = Common.part(pn, size, at, black, Enum.Material.SmoothPlastic, { parent = m })
		locals[p] = at
		return p
	end
	local legW = w * 0.3
	if o.seated then
		piece("LegL", Vector3.new(legW, legH, h * 0.25), base * CFrame.new(-w * 0.2, legH / 2, -h * 0.1))
		piece("LegR", Vector3.new(legW, legH, h * 0.25), base * CFrame.new(w * 0.2, legH / 2, -h * 0.1))
	else
		piece("LegL", Vector3.new(legW, legH, legW), base * CFrame.new(-w * 0.2, legH / 2, 0))
		piece("LegR", Vector3.new(legW, legH, legW), base * CFrame.new(w * 0.2, legH / 2, 0))
	end
	local torsoY = legH + torsoH / 2
	piece("Torso", Vector3.new(w, torsoH, w * 0.45), base * CFrame.new(0, torsoY, 0))
	local headY = legH + torsoH + headH / 2 + h * 0.01
	local head = piece("Head", Vector3.new(w * 0.5, headH, w * 0.5), base * CFrame.new(0, headY, 0))
	local armLen = h * 0.38
	local armW = w * 0.2
	local shoulderY = legH + torsoH - armW / 2
	piece("ArmL", Vector3.new(armW, armLen, armW), base * CFrame.new(-w / 2 - armW / 2, shoulderY - armLen / 2, 0))
	local shoulder = Vector3.new(w / 2 + armW / 2, shoulderY, 0)
	local arm =
		piece("ArmR", Vector3.new(armW, armLen, armW), base * CFrame.new(shoulder) * CFrame.new(0, -armLen / 2, 0))
	local eyes: { BasePart } = {}
	if o.eyes then
		local es = math.max(0.12, w * 0.07)
		for i, sx in { -1, 1 } do
			local e = Common.part(
				"Eye" .. i,
				Vector3.new(es, es, es),
				CFrame.new(),
				Look.Palette.pinEyes,
				Enum.Material.Neon,
				{ parent = m, shape = Enum.PartType.Ball }
			)
			locals[e] = (CFrame.new(sx * w * 0.11, headY + headH * 0.1, -w * 0.25 - es * 0.3))
			table.insert(eyes, e)
		end
	end
	m.PrimaryPart = head
	m.Parent = Common.folder()
	return {
		model = m,
		root = base,
		arm = arm,
		shoulder = shoulder,
		armLen = armLen,
		eyes = eyes,
		locals = locals,
	}
end

-- Places a figure with its feet at `root` (facing root.LookVector). `armAngle` raises the
-- right arm (0 hangs, pi lifts it straight up), swinging sideways by `armSwing` radians.
function Common.placeFigure(f: Figure, root: CFrame, armAngle: number?, armSwing: number?)
	f.root = root
	for p, loc in f.locals do
		p.CFrame = root * loc
	end
	local arm, shoulder = f.arm, f.shoulder
	if arm and shoulder and armAngle then
		local pivot = root * CFrame.new(shoulder) * CFrame.Angles(0, 0, armAngle) * CFrame.Angles(armSwing or 0, 0, 0)
		arm.CFrame = pivot * CFrame.new(0, -f.armLen / 2, 0)
	end
end

----------------------------------------------------------------------------------------
-- The drowned see more

local function applyOutline(inst: Instance, color: Color3)
	if highlights[inst] then
		return
	end
	local hl = Instance.new("Highlight")
	hl.Name = "DrownedSight"
	hl.Adornee = inst
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.FillTransparency = 0.85
	hl.FillColor = color
	hl.OutlineColor = color
	hl.OutlineTransparency = 0.1
	hl.Parent = inst
	highlights[inst] = hl
end

-- The drowned see this model outlined through fog and water.
function Common.outline(inst: Instance, color: Color3?)
	outlined[inst] = color or Common.OUTLINE
	if drowned then
		applyOutline(inst, outlined[inst])
	end
	inst.Destroying:Once(function()
		outlined[inst] = nil
		highlights[inst] = nil
	end)
end

-- Only the drowned see these parts at all (the shape under the hull).
function Common.ghostOnly(part: BasePart, shownTransparency: number)
	ghostOnly[part] = shownTransparency
	part.Transparency = if drowned then shownTransparency else 1
	part.Destroying:Once(function()
		ghostOnly[part] = nil
	end)
end

function Common.setDrowned(on: boolean)
	drowned = on
	for inst, color in outlined do
		if on then
			applyOutline(inst, color)
		else
			local hl = highlights[inst]
			if hl then
				hl:Destroy()
				highlights[inst] = nil
			end
		end
	end
	for part, t in ghostOnly do
		part.Transparency = if on then t else 1
	end
end

function Common.isDrowned(): boolean
	return drowned
end

-- Bearing in the gaze convention (atan2(dx, dz)) from a to b.
function Common.bearing(from: Vector3, to: Vector3): number
	return math.atan2(to.X - from.X, to.Z - from.Z)
end

function Common.wrapAngle(a: number): number
	a = a % (2 * math.pi)
	if a > math.pi then
		a -= 2 * math.pi
	end
	return a
end

return Common
