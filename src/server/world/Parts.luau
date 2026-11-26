--!strict
-- Part factory for the world builders. No requires and no services: world modules get it
-- through ctx.parts, and tools/shell/world_count.luau loads it in Lune with Instance,
-- Vector3, CFrame, Color3 and Enum injected.

export type Opts = {
	collide: boolean?, -- default true
	shadow: boolean?, -- default true
	query: boolean?, -- default true
	transparency: number?,
	reflectance: number?,
	anchored: boolean?, -- default true
	group: string?, -- collision group, default from Parts.group
	shape: string?, -- "Block" (default), "Cylinder", "Ball"
	class: string?, -- "Part" (default), "Seat", "SpawnLocation"
}

local Parts = {}

-- Collision group every new part joins unless opts.group says otherwise. WorldBuilder sets
-- it to "World" before building and BoatHull uses "Boat".
Parts.group = "Default"

function Parts.block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	opts: Opts?
): BasePart
	local o: Opts = opts or {}
	local p = Instance.new((o.class or "Part") :: any) :: Part
	p.Name = name
	if o.shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif o.shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	end
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Anchored = if o.anchored == nil then true else o.anchored
	p.CanCollide = if o.collide == nil then true else o.collide
	p.CanTouch = false
	p.CanQuery = if o.query == nil then true else o.query
	p.CastShadow = if o.shadow == nil then true else o.shadow
	p.Transparency = o.transparency or 0
	p.Reflectance = o.reflectance or 0
	p.CollisionGroup = o.group or Parts.group
	p.Parent = parent
	return p
end

function Parts.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function Parts.light(parent: Instance, name: string, props: { [string]: any }): PointLight
	local l = Instance.new("PointLight")
	l.Name = name
	l.Range = props.Range
	l.Brightness = props.Brightness
	l.Color = props.Color
	l.Shadows = props.Shadows == true
	l.Parent = parent
	return l
end

-- A CFrame at `pos` whose -Z (LookVector) points along `dir` on the ground plane.
function Parts.facing(pos: Vector3, dir: Vector3): CFrame
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-6 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + flat.Unit)
end

-- Point on the lake's shore ellipse at angle a (radians), and the outward normal there.
function Parts.shorePoint(rx: number, rz: number, a: number): (number, number, number, number)
	local x, z = rx * math.cos(a), rz * math.sin(a)
	local nx, nz = math.cos(a) / rx, math.sin(a) / rz
	local len = math.sqrt(nx * nx + nz * nz)
	return x, z, nx / len, nz / len
end

-- 1 on the shore ellipse, less inside, more outside.
function Parts.ellipse(rx: number, rz: number, x: number, z: number): number
	return (x / rx) ^ 2 + (z / rz) ^ 2
end

return Parts
