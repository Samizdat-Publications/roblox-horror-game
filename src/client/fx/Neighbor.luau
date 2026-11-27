--!strict
-- Rule 3, the Neighbor, on screen. Two forms (data.form):
--   Boat: EntityCue starts an oarlock creaking out in the fog with nobody rowing
--         (neighbor-oarlock-loop at data.pos). EntityStage Window shows a rowboat there with
--         its own lantern and a figure sitting in it, one arm raised, waving a little too
--         slowly. EntityMoved drifts it (smoothed between the half-second updates). It
--         always faces your boat. Pass: its lantern dims and the boat fades into the fog
--         (neighbor-pass). Fail: neighbor-fail and it is simply gone (the server sits a
--         silhouette in your boat).
--   FalseBeacon: a steady warm light on a pole where the dock is not. It never blinks.
--         Pass or fail: it goes out.
-- The drowned see the boat outlined; a false beacon is not (only the real beacon is). Fake callouts are the Callouts module's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Look = require(Shared:WaitForChild("Look"))

local client = script.Parent.Parent
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local Common = require(script.Parent:WaitForChild("Common"))

local Neighbor = {}

Neighbor.WAVE_PERIOD = 3.6 -- seconds per wave: a little too slow
Neighbor.FOLLOW = 1.6 -- how quickly the drawn boat closes on its reported position

type Built = {
	model: Model,
	hullPart: BasePart,
	figure: Common.Figure?,
	parts: { { part: BasePart, offset: CFrame } },
	light: PointLight?,
}

local form = "Boat"
local target: Vector3? = nil
local drawn: Vector3? = nil
local built: Built? = nil
local creak: Sound? = nil
local emitter: BasePart? = nil
local clock = 0
local conn: RBXScriptConnection? = nil

local function stopCreak()
	local c = creak
	creak = nil
	if c then
		c:Destroy()
	end
	local em = emitter
	emitter = nil
	if em then
		em:Destroy()
	end
end

local function clear(fade: number)
	local b = built
	built = nil
	if b then
		if fade > 0 then
			Common.fadeOut(b.model, fade)
		else
			b.model:Destroy()
		end
	end
	target, drawn = nil, nil
end

local function facingCF(pos: Vector3): CFrame
	local hull = BoatClient.hull()
	local look = if hull then hull.Position else pos + Vector3.new(0, 0, 1)
	local flat = Vector3.new(look.X, pos.Y, look.Z)
	if (flat - pos).Magnitude < 0.1 then
		flat = pos + Vector3.new(0, 0, 1)
	end
	return CFrame.lookAt(pos, flat)
end

local function buildBoat(pos: Vector3): Built
	local m = Instance.new("Model")
	m.Name = "NeighborBoat"
	m.Parent = Common.folder()
	local dark = Look.Palette.silhouette:Lerp(Look.Palette.boatTrim, 0.35)
	local list: { { part: BasePart, offset: CFrame } } = {}
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material?): BasePart
		local p = Common.part(name, size, CFrame.new(pos) * offset, color, mat, { parent = m })
		table.insert(list, { part = p, offset = offset })
		return p
	end
	-- Facing -Z like ours: a low dark hull, two sides, a pointed bow.
	local hullPart = piece("Hull", Vector3.new(4.2, 0.5, 11), CFrame.new(0, 0.1, 0), dark, Enum.Material.WoodPlanks)
	piece("SideL", Vector3.new(0.35, 1.4, 11), CFrame.new(-2.2, 0.75, 0), dark, Enum.Material.WoodPlanks)
	piece("SideR", Vector3.new(0.35, 1.4, 11), CFrame.new(2.2, 0.75, 0), dark, Enum.Material.WoodPlanks)
	piece("Stern", Vector3.new(4.6, 1.4, 0.35), CFrame.new(0, 0.75, 5.5), dark, Enum.Material.WoodPlanks)
	piece("BowL", Vector3.new(0.35, 1.5, 3.6), CFrame.new(-1.1, 0.8, -6.8) * CFrame.Angles(0, -0.55, 0), dark)
	piece("BowR", Vector3.new(0.35, 1.5, 3.6), CFrame.new(1.1, 0.8, -6.8) * CFrame.Angles(0, 0.55, 0), dark)
	-- Its own lantern on a post at the bow: the light you see first in the fog.
	piece("Post", Vector3.new(0.25, 4, 0.25), CFrame.new(0, 2.4, -6.3), dark)
	local glow = piece(
		"Lantern",
		Vector3.new(0.75, 0.75, 0.75),
		CFrame.new(0, 4.3, -6.8),
		Look.Palette.lantern:Lerp(Color3.fromRGB(255, 230, 190), 0.3),
		Enum.Material.Neon
	)
	glow.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color = Look.Palette.lantern
	light.Range = 34
	light.Brightness = 2.2
	light.Shadows = false
	light.Parent = glow
	-- The figure, sitting amidships facing your boat (the bow end), a little too tall.
	local fig = Common.figure("Rower", { height = 6.4, width = 1.7, seated = true })
	fig.model.Parent = m
	Common.outline(m)
	return { model = m, hullPart = hullPart, figure = fig, parts = list, light = light }
end

local function buildBeacon(pos: Vector3): Built
	local m = Instance.new("Model")
	m.Name = "FalseBeacon"
	m.Parent = Common.folder()
	local list: { { part: BasePart, offset: CFrame } } = {}
	local pole = Common.part(
		"Pole",
		Vector3.new(0.5, 14, 0.5),
		CFrame.new(pos + Vector3.new(0, 7, 0)),
		Look.Palette.silhouette,
		nil,
		{ parent = m }
	)
	table.insert(list, { part = pole, offset = CFrame.new(0, 7, 0) })
	local lamp = Common.part(
		"Lamp",
		Vector3.new(2.5, 3, 2.5),
		CFrame.new(pos + Vector3.new(0, 15, 0)),
		Look.Beacon.Color,
		Enum.Material.Neon,
		{ parent = m }
	)
	table.insert(list, { part = lamp, offset = CFrame.new(0, 15, 0) })
	local light = Instance.new("PointLight")
	light.Color = Look.Beacon.Color
	light.Range = Look.Beacon.Range
	light.Brightness = Look.Beacon.Brightness
	light.Shadows = false
	light.Parent = lamp
	-- Not outlined (Polish 3): the drowned see a faint outline on the real dock beacon only,
	-- so a light with no outline is a false one (Drowned.luau).
	return { model = m, hullPart = pole, figure = nil, parts = list, light = light }
end

local function step(dt: number)
	clock += dt
	local b = built
	local tg = target
	if b == nil or tg == nil then
		return
	end
	local d = drawn or tg
	d = d:Lerp(tg, math.min(1, dt * Neighbor.FOLLOW))
	drawn = d
	if form ~= "Boat" then
		return -- the false beacon stands still
	end
	local bob = math.sin(clock * 0.9) * 0.15
	local base = facingCF(d) * CFrame.new(0, bob, 0) * CFrame.Angles(math.sin(clock * 0.7) * 0.02, 0, 0)
	for _, item in b.parts do
		item.part.CFrame = base * item.offset
	end
	local fig = b.figure
	if fig then
		-- Seated amidships, facing the bow (and your boat). One arm up, waving slowly.
		local wave = math.sin(clock * 2 * math.pi / Neighbor.WAVE_PERIOD)
		Common.placeFigure(fig, base * CFrame.new(0, 0.35, -0.5), math.rad(150) + wave * 0.38, -0.15)
	end
	local em = emitter
	if em then
		em.CFrame = CFrame.new(d)
	end
end

local function ensureLoop()
	if conn == nil then
		conn = RunService.RenderStepped:Connect(step)
	end
end

function Neighbor.handle(e: any)
	local data = e.data or {}
	local pos = if type(data.pos) == "table" then Common.water(data.pos) else nil
	if e.kind == "EntityCue" then
		clear(0)
		stopCreak()
		form = if data.form == "FalseBeacon" then "FalseBeacon" else "Boat"
		if pos == nil then
			return
		end
		target, drawn = pos, pos
		ensureLoop()
		if form == "Boat" then
			local em = Common.emitter(pos)
			emitter = em
			creak = AudioDirector.loop("neighbor-oarlock-loop", em)
		else
			built = buildBeacon(pos)
		end
	elseif e.kind == "EntityStage" and data.stage == "Window" and form == "Boat" then
		local at = pos or target
		if at == nil or built ~= nil then
			return
		end
		target, drawn = at, at
		built = buildBoat(at)
		ensureLoop()
		step(0)
		-- The creak goes on a little quieter once you can see the boat (0.8, Scare polish 2:
		-- it has to stay above the ambience).
		local c = creak
		if c then
			c.Volume *= 0.8
		end
	elseif e.kind == "EntityMoved" then
		if pos then
			target = pos
		end
	elseif e.kind == "EntityPass" then
		stopCreak()
		if form == "Boat" then
			AudioDirector.play("neighbor-pass", built and built.hullPart or nil)
		end
		clear(if form == "Boat" then 3 else 1.2)
	elseif e.kind == "EntityFail" then
		stopCreak()
		AudioDirector.play("neighbor-fail")
		clear(0)
	elseif e.kind == "EntityStage" and data.stage == "Cooldown" then
		stopCreak()
	end
end

-- Where to look: the drawn boat's figure, else the creak or the light, or nil
-- (DebugBot frames it for captures).
function Neighbor.focus(): Vector3?
	local d = drawn or target
	if d == nil then
		return nil
	end
	return d + Vector3.new(0, if form == "Boat" then 3 else 12, 0)
end

function Neighbor.reset()
	stopCreak()
	clear(0)
end

return Neighbor
