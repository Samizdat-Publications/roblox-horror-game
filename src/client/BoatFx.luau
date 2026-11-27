--!strict
-- What happens to your boat, on screen, for players with the sound off (brief, 11/26/2026):
--   * buzz(level): the floorboards visibly buzz (a rapid small offset on local floor slats)
--     and the camera trembles a hair. The Hum drives it.
--   * shiver(level): the lantern flame shivers fast (WorldFx reads lanternFactor).
--   * shake(amount, seconds): a knock or a blow on the hull shakes the camera.
--   * flicker(seconds): the lantern nearly dies for a moment (the fake-out).
--   * the water in the boat rises with view.flood, and every bailing crewmate throws a scoop
--     of it over the side with a sound.
--   * the outboard shakes while the motor runs (a local copy of the motor jitters; the
--     server's motor part is hidden on this client with LocalTransparencyModifier).
--   * capsize(seconds, fish): the boat is thrown. A local copy of the boat rolls and heaves
--     in one big throw that dies away (the server's boat is hidden on this client meanwhile)
--     and the camera rolls with it; spray bursts at both gunwales (ParticleEmitter droplets)
--     under a brief cold flash, and the held fish (the Field Guide's models), a pail, an oar
--     and the tackle box fly over the gunwale and splash (hold-lost-splash).
--   * plunge(): the camera drops under the surface with a cold blue-green underwater tint,
--     blur and bubbles rushing up, and stays there until clearCamera() (Drowned) or a new
--     night.
--   * rock(seconds): the drowned see the boat still rocking for a few seconds.
--   * rings(on): slow, murky dark ripples on the water around the hull (the Hum building).
-- The slats and the water are local parts that follow the hull every frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))

local client = script.Parent
local BoatClient = require(client:WaitForChild("BoatClient"))
local ViewState = require(client:WaitForChild("ViewState"))
local AudioDirector = require(client:WaitForChild("AudioDirector"))
local Common = require(client:WaitForChild("fx"):WaitForChild("Common"))

local BoatFx = {}

BoatFx.SLATS = 5
BoatFx.FLOOD_DEPTH = 1.35 -- water depth in the boat when full
BoatFx.SCOOP_EVERY = 1.1
-- Scare polish 2: one big throw that dies away over the whole 1.2 s (the old fast wobble read
-- as a half-second snap), with a foam burst and a cold flash so it reads in the dark.
BoatFx.CAPSIZE = { roll = 0.85, heave = 1.8, pitch = 0.2, rollPeriod = 0.95, heavePeriod = 0.6 }
-- M8 polish (Neon: "giant white spheres and blue spheres"): the foam and the splashes are short
-- ParticleEmitter bursts of small soft droplets (Emit, no Neon balls). `bursts` points along
-- each gunwale, `count` droplets each. The pale foam ring on the water stays, dimmer.
BoatFx.FOAM = { bursts = 4, count = 14, color = Color3.fromRGB(200, 214, 214), life = 1.0 }
-- The droplets: an engine texture (rbxasset://, not an uploaded asset id), soft and small,
-- thrown up and pulled down fast, fading out.
BoatFx.SPRAY = {
	texture = "rbxasset://textures/particles/smoke_main.dds",
	color = Color3.fromRGB(196, 210, 212),
	size = { 0.45, 0.12 },
	lifetime = { 0.45, 0.9 },
	speed = { 9, 17 },
	spread = 28,
	gravity = 46,
	drag = 1.2,
}
BoatFx.FLASH = { color = Color3.fromRGB(190, 215, 230), brightness = 1.8, range = 30 }
-- After the death card the drowned see the boat still rocking for a few seconds.
BoatFx.ROCK = { seconds = 5, roll = 0.16, heave = 0.35, rollPeriod = 2.3, heavePeriod = 1.7 }
BoatFx.PLUNGE = { seconds = 0.35, depth = 3.2, maxHold = 14 }
BoatFx.BUBBLES = 22
BoatFx.UNDERWATER = Color3.fromRGB(60, 160, 150) -- the tint under the surface
BoatFx.GRAVITY = 42
-- The Hum's rings: expanding circles on the water around the hull while it builds.
-- M8 polish (Neon: "the glowing cyan rings look sci-fi"): murky, low-contrast dark ripples
-- (no Neon) with a faint pale edge just outside, slower and closer to the hull.
BoatFx.RINGS = {
	every = 1.5,
	from = 7,
	to = 24,
	life = 3.8,
	segments = 24,
	color = Color3.fromRGB(16, 24, 26),
	alpha = 0.45, -- the dark band at its most opaque (transparency 1 - alpha)
	width = 0.55,
	edge = Color3.fromRGB(122, 136, 134),
	edgeAlpha = 0.22,
	edgeWidth = 0.12,
}
BoatFx.BUZZ_CAMERA = 0.04 -- camera rattle at full buzz (was 0.02, Neon wanted it felt)
-- M8 polish (Neon: the motor did not read): a little more rumble and jitter at the stern, and
-- a faint churn of droplets behind the shaft while the outboard runs.
BoatFx.MOTOR_RUMBLE = 0.012 -- camera rumble while the outboard runs (was 0.008)
BoatFx.MOTOR_SHAKE = 0.08 -- the outboard copy's jitter in studs (was 0.06)
BoatFx.MOTOR_PARTS = { "Motor", "MotorShaft", "Tiller" } -- the stern pieces that vibrate
BoatFx.MOTOR_CHURN = { rate = 14, speed = { 2, 5 }, size = { 0.3, 0.08 }, lifetime = { 0.4, 0.8 } }
-- Polish round 2 (Neon hum-fail v4: "the motor state hides in tiny HUD text"): small dark
-- exhaust puffs rise from the top of the outboard while it runs (engine smoke texture, not an
-- uploaded id), drifting up and aft.
BoatFx.MOTOR_EXHAUST = {
	rate = 7,
	color = { Color3.fromRGB(46, 47, 49), Color3.fromRGB(84, 86, 88) },
	size = { 0.3, 1.5 },
	transparency = { 0.35, 1 },
	lifetime = { 1.1, 1.8 },
	speed = { 1.4, 2.4 },
	rise = 1.6, -- upward acceleration, studs per second squared
	aft = 0.8, -- drift toward the stern, studs per second squared
}
-- Polish round 2 (orchestrator frames: a huge pail and a white disc filled the lower left at
-- the capsize). Debris starts at the gunwale away from the camera and is thrown outward; no
-- item's center comes closer than `minCamDist` plus its own radius. The splashes and the foam
-- are thin low-contrast rings of segments (the old ones were filled discs, a flat Cylinder,
-- which the rolled camera saw edge on as a bright white disc), and a segment or a spray burst
-- within `minCamDist` of the camera is not drawn.
BoatFx.DEBRIS = { minCamDist = 6, gunwale = 2.4, lift = 1.6, out = { 8, 11 }, up = { 11, 14 }, away = 3 }
BoatFx.FOAM_RING = {
	from = 4,
	to = 15,
	life = 1.3,
	segments = 24,
	color = Color3.fromRGB(150, 164, 164),
	alpha = 0.32,
	width = 0.45,
	edge = Color3.fromRGB(150, 164, 164),
	edgeAlpha = 0,
	edgeWidth = 0.1,
}

local buzzLevel = 0
local buzzTarget = 0
local shiverLevel = 0
local shiverTarget = 0
local shakeAmp = 0
local shakeUntil = 0
local shakeLen = 0.0001
local flickerUntil = 0
local clock = 0
local rnd = Random.new()

local slats: { { part: BasePart, offset: CFrame, seed: number } } = {}
local water: BasePart? = nil
local floodLoop: Sound? = nil
local leak = false
local scoopT: { [number]: number } = {}

-- The motor's local stand-in.
local motorCopies: { { part: BasePart, real: BasePart } } = {}
-- The capsize: a local copy of the boat that rolls, and the camera rolls with it.
local capsizeCopy: Model? = nil
local capsizeHidden: { BasePart } = {}
local capsizeT0 = 0
local capsizeLen = 0
local capsizeRoll = CFrame.new() -- this frame's roll, in the hull's frame
local copyMode = "throw" -- "throw" (the camera rolls too) or "rock" (the drowned watch)
local rings = false
local ringT = 0
-- The plunge under the surface.
local plungeT0: number? = nil
local plungeFrom = 0 -- camera height when the plunge started
local underwater: { Instance } = {}

function BoatFx.buzz(level: number)
	buzzTarget = math.clamp(level, 0, 1)
end

function BoatFx.shiver(level: number)
	shiverTarget = math.clamp(level, 0, 1)
end

-- A one-off shake. Overlapping shakes keep the stronger one.
function BoatFx.shake(amount: number, seconds: number)
	local now = clock
	local left = math.max(0, shakeUntil - now)
	local current = if left > 0 then shakeAmp * (left / shakeLen) else 0
	if amount >= current then
		shakeAmp = amount
		shakeUntil = now + seconds
		shakeLen = math.max(seconds, 0.0001)
	end
end

function BoatFx.flicker(seconds: number)
	flickerUntil = math.max(flickerUntil, clock + seconds)
end

-- Multiplier for the lantern's brightness this frame (WorldFx applies it).
function BoatFx.lanternFactor(): number
	if clock < flickerUntil then
		-- Nearly out, catching twice.
		local n = math.noise(clock * 18, 4.2)
		return math.clamp(0.08 + n * 0.5, 0.02, 0.5)
	end
	if shiverLevel > 0.01 then
		local n = math.noise(clock * 38, 1.3)
		return 1 - shiverLevel * (0.45 + n * 0.6)
	end
	return 1
end

function BoatFx.setLeak(on: boolean)
	leak = on
end

-- Expanding rings on the water around the hull (the Hum building).
function BoatFx.rings(on: boolean)
	if on and not rings then
		ringT = 0
	end
	rings = on
end

type RingSpec = {
	from: number,
	to: number,
	life: number,
	segments: number,
	color: Color3,
	alpha: number,
	width: number,
	edge: Color3,
	edgeAlpha: number,
	edgeWidth: number,
}

local function cameraPos(): Vector3?
	local cam = Workspace.CurrentCamera
	return if cam then cam.CFrame.Position else nil
end

-- A ring on the water at `center` (diameter R.from to R.to over R.life): short flat segments
-- with an optional faint edge just outside, growing and fading, easing in so it never pops.
-- `clearCam`: segments within BoatFx.DEBRIS.minCamDist of the camera are not drawn.
local function waterRing(name: string, center: Vector3, R: RingSpec, clearCam: boolean?)
	local n = R.segments
	local dark: { BasePart } = {}
	local edge: { BasePart } = {}
	for i = 1, n do
		dark[i] = Common.part(
			name,
			Vector3.new(1, 0.04, R.width),
			CFrame.new(center),
			R.color,
			Enum.Material.SmoothPlastic,
			{ transparency = 1 }
		)
		edge[i] = Common.part(
			name .. "Edge",
			Vector3.new(1, 0.04, R.edgeWidth),
			CFrame.new(center + Vector3.new(0, 0.01, 0)),
			R.edge,
			Enum.Material.SmoothPlastic,
			{ transparency = 1 }
		)
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < R.life and dark[1].Parent do
			local t = (os.clock() - t0) / R.life
			local r = (R.from + (R.to - R.from) * (1 - (1 - t) * (1 - t))) / 2
			local rEdge = r + R.width * 0.5 + R.edgeWidth
			-- In over the first fifth, then out.
			local k = math.min(1, t / 0.2) * (1 - t)
			local cam = if clearCam then cameraPos() else nil
			local near = BoatFx.DEBRIS.minCamDist
			for i = 1, n do
				local a = (i - 1) * 2 * math.pi / n
				local turn = CFrame.Angles(0, -a + math.pi / 2, 0)
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				local d, e = dark[i], edge[i]
				local hide = cam ~= nil and ((center + dir * r) - cam).Magnitude < near
				d.Size = Vector3.new(2 * math.pi * r / n * 1.08, 0.04, R.width)
				d.CFrame = CFrame.new(center + dir * r) * turn
				d.Transparency = if hide then 1 else 1 - R.alpha * k
				e.Size = Vector3.new(2 * math.pi * rEdge / n * 1.08, 0.04, R.edgeWidth)
				e.CFrame = CFrame.new(center + dir * rEdge + Vector3.new(0, 0.01, 0)) * turn
				e.Transparency = if hide or R.edgeAlpha <= 0 then 1 else 1 - R.edgeAlpha * k
			end
			task.wait()
		end
		for i = 1, n do
			dark[i]:Destroy()
			edge[i]:Destroy()
		end
	end)
end

-- The Hum's murky ripple around the hull.
local function spawnRing(hull: BasePart)
	local center = Vector3.new(hull.Position.X, Config.Lake.waterY + 0.06, hull.Position.Z)
	waterRing("HumRing", center, BoatFx.RINGS)
end

-- A short burst of small soft droplets (a ParticleEmitter Emit) at `cf`, thrown along the
-- frame's up axis. `count` droplets, `speedMul` on the speed range. Cleans itself up.
local function spray(cf: CFrame, count: number, speedMul: number?)
	local S = BoatFx.SPRAY
	local k = speedMul or 1
	local anchor = Common.part("Spray", Vector3.new(0.2, 0.2, 0.2), cf, Color3.new(), nil, { transparency = 1 })
	local att = Instance.new("Attachment")
	att.Parent = anchor
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Droplets"
	pe.Enabled = false
	pe.Rate = 0
	pe.Texture = S.texture
	pe.Color = ColorSequence.new(S.color)
	pe.Size = NumberSequence.new(S.size[1], S.size[2])
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.6, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(S.lifetime[1], S.lifetime[2])
	pe.Speed = NumberRange.new(S.speed[1] * k, S.speed[2] * k)
	pe.SpreadAngle = Vector2.new(S.spread, S.spread)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Acceleration = Vector3.new(0, -S.gravity, 0)
	pe.Drag = S.drag
	pe.LightInfluence = 0.7
	pe.LightEmission = 0.1
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Parent = att
	pe:Emit(count)
	task.delay(S.lifetime[2] + 0.3, function()
		anchor:Destroy()
	end)
end

function BoatFx.reset()
	buzzTarget, buzzLevel = 0, 0
	shiverTarget, shiverLevel = 0, 0
	shakeAmp, shakeUntil = 0, 0
	flickerUntil = 0
	leak = false
	rings = false
	local l = floodLoop
	if l then
		l:Destroy()
		floodLoop = nil
	end
	BoatFx.clearCamera()
end

----------------------------------------------------------------------------------------
-- The outboard shakes while it runs

local function setMotorCopies(on: boolean)
	if not on then
		for _, c in motorCopies do
			c.part:Destroy()
			if c.real.Parent then
				c.real.LocalTransparencyModifier = 0
			end
		end
		motorCopies = {}
		return
	end
	if #motorCopies > 0 then
		return
	end
	for _, name in BoatFx.MOTOR_PARTS do
		local real = BoatClient.part(name)
		if real then
			local p = Common.part("Local" .. name, real.Size, real.CFrame, real.Color, real.Material)
			table.insert(motorCopies, { part = p, real = real })
			if name == "MotorShaft" then
				-- A faint churn of droplets at the foot of the shaft while it runs.
				local C, S = BoatFx.MOTOR_CHURN, BoatFx.SPRAY
				local att = Instance.new("Attachment")
				att.Position = Vector3.new(0, -real.Size.Y / 2, 0)
				att.Parent = p
				local pe = Instance.new("ParticleEmitter")
				pe.Name = "Churn"
				pe.Texture = S.texture
				pe.Color = ColorSequence.new(S.color)
				pe.Size = NumberSequence.new(C.size[1], C.size[2])
				pe.Transparency = NumberSequence.new(0.45, 1)
				pe.Lifetime = NumberRange.new(C.lifetime[1], C.lifetime[2])
				pe.Speed = NumberRange.new(C.speed[1], C.speed[2])
				pe.SpreadAngle = Vector2.new(35, 35)
				pe.EmissionDirection = Enum.NormalId.Top
				pe.Acceleration = Vector3.new(0, -S.gravity * 0.6, 0)
				pe.LightInfluence = 0.7
				pe.Rate = C.rate
				pe.Parent = att
			elseif name == "Motor" then
				-- Exhaust: small dark puffs from the top of the outboard, drifting up and aft.
				local X = BoatFx.MOTOR_EXHAUST
				local att = Instance.new("Attachment")
				att.Name = "ExhaustPort"
				att.Position = Vector3.new(0, real.Size.Y / 2 + 0.1, real.Size.Z * 0.25)
				att.Parent = p
				local pe = Instance.new("ParticleEmitter")
				pe.Name = "Exhaust"
				pe.Texture = BoatFx.SPRAY.texture
				pe.Color = ColorSequence.new(X.color[1], X.color[2])
				pe.Size = NumberSequence.new(X.size[1], X.size[2])
				pe.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.12, X.transparency[1]),
					NumberSequenceKeypoint.new(1, X.transparency[2]),
				})
				pe.Lifetime = NumberRange.new(X.lifetime[1], X.lifetime[2])
				pe.Speed = NumberRange.new(X.speed[1], X.speed[2])
				pe.SpreadAngle = Vector2.new(18, 18)
				pe.EmissionDirection = Enum.NormalId.Top
				pe.Acceleration = real.CFrame.LookVector * -X.aft + Vector3.new(0, X.rise, 0)
				pe.Drag = 0.8
				pe.Rotation = NumberRange.new(0, 360)
				pe.RotSpeed = NumberRange.new(-40, 40)
				pe.LightInfluence = 0.6
				pe.LightEmission = 0
				pe.Rate = X.rate
				pe.Parent = att
			end
		end
	end
end

local function stepMotor()
	local on = ViewState.get().motorOn == true
	setMotorCopies(on)
	if not on then
		return
	end
	local hidden = capsizeCopy ~= nil
	for i, c in motorCopies do
		if c.real.Parent == nil then
			continue
		end
		c.real.LocalTransparencyModifier = 1
		local a = BoatFx.MOTOR_SHAKE
		local j = CFrame.new(
			math.noise(clock * 41, i * 3.1) * a,
			math.noise(clock * 53, i * 5.7) * a,
			math.noise(clock * 47, i * 7.9) * a
		) * CFrame.Angles(math.noise(clock * 37, i) * 0.03, 0, math.noise(clock * 43, i + 2) * 0.03)
		c.part.CFrame = c.real.CFrame * j
		c.part.Transparency = if hidden then 1 else c.real.Transparency
		local churn = c.part:FindFirstChild("Churn", true)
		if churn and churn:IsA("ParticleEmitter") then
			churn.Enabled = not hidden
		end
		local exhaust = c.part:FindFirstChild("Exhaust", true)
		if exhaust and exhaust:IsA("ParticleEmitter") then
			exhaust.Enabled = not hidden
			-- Up and aft in the world as the boat turns (Acceleration is in world space).
			exhaust.Acceleration = c.real.CFrame.LookVector * -BoatFx.MOTOR_EXHAUST.aft
				+ Vector3.new(0, BoatFx.MOTOR_EXHAUST.rise, 0)
		end
	end
end

----------------------------------------------------------------------------------------
-- The boat is thrown

local function endCapsize()
	local m = capsizeCopy
	capsizeCopy = nil
	capsizeRoll = CFrame.new()
	for _, p in capsizeHidden do
		if p.Parent then
			p.LocalTransparencyModifier = 0
		end
	end
	capsizeHidden = {}
	if m then
		m:Destroy()
	end
end

local function splash(at: Vector3, size: number)
	-- A thin low-contrast ring spreading on the water and a short burst of droplets (no discs,
	-- no spheres). Nothing is drawn within BoatFx.DEBRIS.minCamDist of the camera.
	local R = BoatFx.FOAM_RING
	local spec: RingSpec = {
		from = size,
		to = size * 3.5,
		life = 0.9,
		segments = 18,
		color = R.color,
		alpha = R.alpha,
		width = 0.3,
		edge = R.edge,
		edgeAlpha = 0,
		edgeWidth = R.edgeWidth,
	}
	waterRing("Splash", Vector3.new(at.X, Config.Lake.waterY + 0.05, at.Z), spec, true)
	local cam = cameraPos()
	if cam == nil or (at - cam).Magnitude >= BoatFx.DEBRIS.minCamDist then
		spray(CFrame.new(at.X, Config.Lake.waterY + 0.1, at.Z), math.floor(6 + size * 3), 0.6 + size * 0.12)
	end
	AudioDirector.play("hold-lost-splash", at)
end

-- Every part of a thrown item (one part or a model).
local function itemParts(item: Instance): { BasePart }
	local list: { BasePart } = {}
	if item:IsA("BasePart") then
		table.insert(list, item)
	end
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function placeItem(item: Instance, cf: CFrame)
	if item:IsA("Model") then
		item:PivotTo(cf)
	elseif item:IsA("BasePart") then
		item.CFrame = cf
	end
end

-- Pushes an item's center out to at least BoatFx.DEBRIS.minCamDist plus its radius from the
-- camera (the camera rolls with the throw, so this is checked every frame).
local function clearOfCamera(pos: Vector3, radius: number): Vector3
	local cam = cameraPos()
	if cam == nil then
		return pos
	end
	local d = pos - cam
	local m = BoatFx.DEBRIS.minCamDist + radius
	if d.Magnitude >= m then
		return pos
	end
	local dir = if d.Magnitude > 1e-3 then d.Unit else Vector3.new(0, 1, 0)
	return cam + dir * m
end

-- Something thrown over the gunwale (a part or a model): flies, spins, splashes, sinks.
-- `radius` is the item's half length: its center keeps that much more than minCamDist away
-- from the camera.
local function throwItem(item: Instance, from: CFrame, vel: Vector3, spin: Vector3, radius: number)
	from = CFrame.new(clearOfCamera(from.Position, radius)) * from.Rotation
	placeItem(item, from)
	local parts = itemParts(item)
	task.spawn(function()
		local t0 = os.clock()
		local splashed = false
		local fade = 0
		while item.Parent and os.clock() - t0 < 3 do
			local t = os.clock() - t0
			local pos = from.Position + vel * t + Vector3.new(0, -0.5 * BoatFx.GRAVITY * t * t, 0)
			if not splashed and pos.Y < Config.Lake.waterY and t > 0.15 then
				splashed = true
				splash(pos, 2.4)
			end
			pos = clearOfCamera(pos, radius)
			if splashed then
				pos = Vector3.new(pos.X, math.max(pos.Y, Config.Lake.waterY - 2), pos.Z)
				fade = math.min(1, fade + 0.06)
				for _, p in parts do
					p.LocalTransparencyModifier = fade
				end
			end
			placeItem(item, CFrame.new(pos) * from.Rotation * CFrame.Angles(spin.X * t, spin.Y * t, spin.Z * t))
			task.wait()
		end
		item:Destroy()
	end)
end

local FISH_SPECIES = { "YellowPerch", "Pumpkinseed", "Walleye", "Bullhead", "ChainPickerel" }
BoatFx.GUIDE_FOLDER = "DeadCalmFieldGuide" -- the server's fish models (the ones the catch uses)

-- A real fish model (the Field Guide's drawing), inert and local; a plain body as a fallback.
local function thrownFish(species: string, at: CFrame): Instance
	local folder = ReplicatedStorage:FindFirstChild(BoatFx.GUIDE_FOLDER)
	local src = folder and folder:FindFirstChild(species)
	if src and src:IsA("Model") then
		local m = src:Clone()
		m.Name = "ThrownFish"
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			elseif d:IsA("LuaSourceContainer") or d:IsA("Sound") then
				d:Destroy()
			end
		end
		m.Parent = Common.folder()
		m:PivotTo(at)
		return m
	end
	local spec = (Look.Fish :: any)[species]
	return Common.part(
		"ThrownFish",
		if spec then Vector3.new(spec.width, spec.height, spec.length) else Vector3.new(0.45, 0.7, 1.8),
		at,
		if spec then spec.body else Color3.fromRGB(150, 140, 90),
		Enum.Material.SmoothPlastic
	)
end

-- A bait bucket at real size (about 1.2 studs tall, handle up): an upright pail, a darker
-- rim and a wire handle. `at` is the middle of the pail body.
local function thrownBucket(at: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "ThrownBucket"
	local tin = Look.Palette.metal:Lerp(Color3.new(1, 1, 1), 0.25)
	local up = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder's axis is X: stand it up
	local body = Common.part(
		"Pail",
		Vector3.new(0.95, 0.85, 0.85),
		at * up,
		tin,
		Enum.Material.Metal,
		{ shape = Enum.PartType.Cylinder, parent = m }
	)
	Common.part(
		"Rim",
		Vector3.new(0.08, 0.92, 0.92),
		at * CFrame.new(0, 0.46, 0) * up,
		tin:Lerp(Color3.new(0, 0, 0), 0.35),
		Enum.Material.Metal,
		{ shape = Enum.PartType.Cylinder, parent = m }
	)
	local wire = tin:Lerp(Color3.new(0, 0, 0), 0.5)
	Common.part("HandleL", Vector3.new(0.05, 0.24, 0.05), at * CFrame.new(-0.44, 0.58, 0), wire, nil, { parent = m })
	Common.part("HandleR", Vector3.new(0.05, 0.24, 0.05), at * CFrame.new(0.44, 0.58, 0), wire, nil, { parent = m })
	Common.part("HandleTop", Vector3.new(0.9, 0.05, 0.05), at * CFrame.new(0, 0.7, 0), wire, nil, { parent = m })
	m.PrimaryPart = body
	return m
end

-- An oar: a round shaft, a grip and a flat blade (pale enough to read in the dark).
local function thrownOar(at: CFrame): Model
	local m = Instance.new("Model")
	m.Name = "ThrownOar"
	local wood = Look.Palette.boatWood:Lerp(Color3.new(1, 1, 1), 0.35)
	local along = CFrame.Angles(0, math.rad(90), 0) -- the Cylinder's X axis along the oar (Z)
	local shaft = Common.part(
		"Shaft",
		Vector3.new(5.2, 0.24, 0.24),
		at * along,
		wood,
		Enum.Material.Wood,
		{ shape = Enum.PartType.Cylinder, parent = m }
	)
	Common.part(
		"Grip",
		Vector3.new(0.7, 0.3, 0.3),
		at * CFrame.new(0, 0, -2.75) * along,
		wood:Lerp(Color3.new(0, 0, 0), 0.3),
		Enum.Material.Wood,
		{ shape = Enum.PartType.Cylinder, parent = m }
	)
	Common.part(
		"Blade",
		Vector3.new(0.7, 0.1, 1.6),
		at * CFrame.new(0, 0, 3.3),
		wood,
		Enum.Material.Wood,
		{ parent = m }
	)
	m.PrimaryPart = shaft
	return m
end

-- The gunwale away from the camera (+1 starboard, -1 port), and the end of the boat away
-- from it (+1 stern, -1 bow), in the hull's frame.
local function farFrom(hull: BasePart): (number, number)
	local cam = cameraPos()
	local randomSide = if rnd:NextNumber() < 0.5 then -1 else 1
	if cam == nil then
		return randomSide, -1
	end
	local l = hull.CFrame:PointToObjectSpace(cam)
	local side = if math.abs(l.X) < 0.3 then randomSide elseif l.X > 0 then -1 else 1
	return side, if l.Z > 0 then -1 else 1
end

local function launchHold(hull: BasePart, fishCount: number)
	local D = BoatFx.DEBRIS
	local side, endZ = farFrom(hull)
	local right = hull.CFrame.RightVector * side
	-- A spot on the far gunwale `z` studs along the boat toward the end away from the camera.
	local function onGunwale(z: number, lift: number?): CFrame
		return hull.CFrame * CFrame.new(side * D.gunwale, lift or D.lift, endZ * z)
	end
	-- Outward from the far gunwale, a little away from the camera too, and up.
	local function outward(from: CFrame): Vector3
		local cam = cameraPos()
		local away = Vector3.zero
		if cam then
			local d = from.Position - cam
			d = Vector3.new(d.X, 0, d.Z)
			if d.Magnitude > 1e-3 then
				away = d.Unit * D.away
			end
		end
		return right * rnd:NextNumber(D.out[1], D.out[2]) + away + Vector3.new(0, rnd:NextNumber(D.up[1], D.up[2]), 0)
	end
	for i = 1, fishCount do
		local at = onGunwale(1.5 + (i - 1) * 1.1, D.lift + 0.3)
		local fish = thrownFish(FISH_SPECIES[(i - 1) % #FISH_SPECIES + 1], at)
		task.delay((i - 1) * 0.12, function()
			throwItem(fish, at, outward(at), Vector3.new(9, 3, 4), 1.1)
		end)
	end
	-- The bait bucket goes too (real size).
	local bucketAt = onGunwale(2.4)
	local bucket = thrownBucket(bucketAt)
	bucket.Parent = Common.folder()
	task.delay(0.08, function()
		throwItem(bucket, bucketAt, outward(bucketAt), Vector3.new(6, 2, 8), 0.7)
	end)
	-- Loose gear: an oar (lying along the far gunwale) and the tackle box.
	local oarAt = onGunwale(1.2, D.lift + 0.2)
	local oar = thrownOar(oarAt)
	oar.Parent = Common.folder()
	task.delay(0.15, function()
		throwItem(oar, oarAt, outward(oarAt), Vector3.new(2, 7, 1), 3.3)
	end)
	local boxAt = onGunwale(3.6, D.lift - 0.1)
	local box = Common.part(
		"ThrownTackle",
		Vector3.new(1.4, 0.8, 0.9),
		boxAt,
		Color3.fromRGB(196, 92, 60),
		Enum.Material.SmoothPlastic
	)
	task.delay(0.22, function()
		throwItem(box, boxAt, outward(boxAt), Vector3.new(7, 5, 3), 0.8)
	end)
end

-- Spray at both gunwales: droplet bursts thrown up and out along each side, and a pale ring of
-- foam on the water on each side.
local function foamBurst(hull: BasePart)
	local F = BoatFx.FOAM
	local near = BoatFx.DEBRIS.minCamDist
	for _, side in { -1, 1 } do
		for i = 1, F.bursts do
			local z = -5 + (i - 1) * (10 / math.max(1, F.bursts - 1))
			local at = hull.CFrame * CFrame.new(side * 2.4, 0.3, z)
			-- Never a burst right in front of the camera.
			local cam = cameraPos()
			if cam and (at.Position - cam).Magnitude < near then
				continue
			end
			-- Tilted out over the side so the droplets fly away from the boat.
			-- The emitter's Top face points up and out (about 30 degrees off vertical).
			local up = (hull.CFrame.UpVector + hull.CFrame.RightVector * side * 0.58).Unit
			local cf = CFrame.fromMatrix(at.Position, hull.CFrame.LookVector, up)
			task.delay(rnd:NextNumber(0, 0.2), function()
				spray(cf, F.count)
			end)
		end
		-- A thin pale ring of foam on the water on each side (segments near the camera hidden).
		local at = hull.Position + hull.CFrame.RightVector * side * 4
		waterRing("FoamRing", Vector3.new(at.X, Config.Lake.waterY + 0.06, at.Z), BoatFx.FOAM_RING, true)
	end
end

-- A local, inert copy of the boat that rolls in place of the real one (hidden on this client).
local function startCopy(seconds: number, mode: string): boolean
	local model = BoatClient.model()
	local hull = BoatClient.hull()
	if model == nil or hull == nil then
		return false
	end
	endCapsize()
	local copy = model:Clone()
	-- Strip anything that could act: joints (a SeatWeld would grab a character), sounds,
	-- scripts, constraints. The copy is anchored, local and inert.
	for _, d in copy:GetDescendants() do
		if
			d:IsA("JointInstance")
			or d:IsA("WeldConstraint")
			or d:IsA("Constraint")
			or d:IsA("Sound")
			or d:IsA("LuaSourceContainer")
			or d:IsA("Highlight")
		then
			d:Destroy()
		end
	end
	for _, d in copy:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			if d:IsA("Seat") then
				d.Disabled = true
			end
		end
	end
	copy.Name = "CapsizeCopy"
	copy.Parent = Common.folder()
	capsizeCopy = copy
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			table.insert(capsizeHidden, d)
		end
	end
	capsizeT0 = clock
	capsizeLen = seconds
	copyMode = mode
	return true
end

-- The boat is thrown for `seconds`: a local copy rolls and heaves, the camera rolls with it,
-- foam bursts at both gunwales under a brief cold flash, and `fishCount` fish, a bucket, an
-- oar and the tackle box go over the side.
function BoatFx.capsize(seconds: number, fishCount: number)
	if not startCopy(seconds, "throw") then
		return
	end
	local hull = BoatClient.hull() :: BasePart
	local copy = capsizeCopy
	if copy then
		local glow = Instance.new("PointLight")
		glow.Name = "ThrownFlash"
		glow.Color = BoatFx.FLASH.color
		glow.Brightness = BoatFx.FLASH.brightness
		glow.Range = BoatFx.FLASH.range
		glow.Shadows = false
		local anchor = copy.PrimaryPart or copy:FindFirstChildWhichIsA("BasePart", true)
		if anchor then
			glow.Parent = anchor
		else
			glow:Destroy()
		end
	end
	foamBurst(hull)
	launchHold(hull, math.clamp(fishCount, 1, 4))
	AudioDirector.play("hold-lost-splash", hull)
end

-- The drowned see the boat still rocking for a few seconds (no camera roll).
function BoatFx.rock(seconds: number?)
	startCopy(seconds or BoatFx.ROCK.seconds, "rock")
end

local function stepCapsize()
	local copy = capsizeCopy
	local hull = BoatClient.hull()
	if copy == nil or hull == nil then
		return
	end
	local t = clock - capsizeT0
	if t >= capsizeLen then
		endCapsize()
		return
	end
	if copyMode == "rock" then
		local R = BoatFx.ROCK
		local k = 1 - t / capsizeLen
		local roll = R.roll * k * math.sin(2 * math.pi * t / R.rollPeriod)
		local heave = R.heave * k * math.sin(2 * math.pi * t / R.heavePeriod)
		capsizeRoll = CFrame.new(0, heave, 0) * CFrame.Angles(roll * 0.3, 0, roll)
		copy:PivotTo(hull.CFrame * capsizeRoll)
		return
	end
	local C = BoatFx.CAPSIZE
	local env = math.min(1, t / 0.1)
	-- Thrown hard to one side and back over, dying away over the whole throw; up and down on
	-- the swell.
	local u = t / capsizeLen
	local decay = math.exp(-t / (capsizeLen * 0.75)) * (1 - u * u * u) -- level again at the end
	local roll = C.roll * env * decay * math.sin(2 * math.pi * t / C.rollPeriod + 0.5)
	local heave = C.heave * env * decay * math.abs(math.sin(2 * math.pi * t / C.heavePeriod + 0.3))
	local pitch = C.pitch * env * decay * math.sin(2 * math.pi * t / (C.rollPeriod * 0.8))
	capsizeRoll = CFrame.new(0, heave, 0) * CFrame.Angles(pitch, 0, roll)
	copy:PivotTo(hull.CFrame * capsizeRoll)
	local flash = copy:FindFirstChild("ThrownFlash", true)
	if flash and flash:IsA("PointLight") then
		flash.Brightness = BoatFx.FLASH.brightness * math.clamp(1 - t / capsizeLen, 0, 1)
	end
end

----------------------------------------------------------------------------------------
-- Under the surface

local function clearUnderwater()
	for _, inst in underwater do
		inst:Destroy()
	end
	underwater = {}
end

local function makeUnderwater(cam: Camera)
	clearUnderwater()
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "DeadCalmUnderwater"
	cc.TintColor = BoatFx.UNDERWATER
	cc.Brightness = -0.08
	cc.Contrast = 0.15
	cc.Saturation = -0.25
	cc.Parent = cam
	table.insert(underwater, cc)
	local blur = Instance.new("BlurEffect")
	blur.Name = "DeadCalmUnderwaterBlur"
	blur.Size = 10
	blur.Parent = cam
	table.insert(underwater, blur)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DeadCalmUnderwater"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(14, 62, 60)
	f.BackgroundTransparency = 0.45
	f.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	table.insert(underwater, gui)
end

-- The camera goes under: a quick drop below the surface, then it stays down.
function BoatFx.plunge()
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return
	end
	local my = clock
	plungeT0 = my
	plungeFrom = cam.CFrame.Position.Y
	task.delay(BoatFx.PLUNGE.seconds * 0.6, function()
		if plungeT0 == my then
			makeUnderwater(cam)
		end
	end)
	-- Bubbles rush up past the camera as it goes down.
	task.delay(BoatFx.PLUNGE.seconds, function()
		if plungeT0 ~= my then
			return
		end
		for _ = 1, BoatFx.BUBBLES do
			local from = cam.CFrame
				* CFrame.new(rnd:NextNumber(-2.2, 2.2), rnd:NextNumber(-2.5, -0.5), -rnd:NextNumber(2.5, 6))
			local size = rnd:NextNumber(0.12, 0.4)
			local b = Common.part(
				"Bubble",
				Vector3.new(size, size, size),
				from,
				Color3.fromRGB(200, 240, 235),
				Enum.Material.Neon,
				{ shape = Enum.PartType.Ball, transparency = 0.35 }
			)
			local rise = rnd:NextNumber(3, 7)
			task.delay(rnd:NextNumber(0, 0.9), function()
				local t0 = os.clock()
				while b.Parent and os.clock() - t0 < 1.4 do
					local t = os.clock() - t0
					b.CFrame = from + Vector3.new(math.sin(t * 9 + size * 20) * 0.15, rise * t, 0)
					b.Transparency = 0.35 + 0.65 * (t / 1.4)
					task.wait()
				end
				b:Destroy()
			end)
		end
	end)
	local hull = BoatClient.hull()
	if hull then
		splash(hull.Position + hull.CFrame.RightVector * 2.6, 3.2)
	end
end

-- Ends every camera effect of a fail (the drowned camera takes over, or a new night).
function BoatFx.clearCamera()
	endCapsize()
	plungeT0 = nil
	clearUnderwater()
end

function BoatFx.capsizing(): boolean
	return capsizeCopy ~= nil
end

-- True while this camera is under the surface after a fail.
function BoatFx.plunging(): boolean
	return plungeT0 ~= nil
end

local function buildSlats(hull: BasePart)
	for _, s in slats do
		s.part:Destroy()
	end
	slats = {}
	local wood = Look.Palette.boatWood:Lerp(Look.Palette.boatTrim, 0.35)
	for i = 1, BoatFx.SLATS do
		local x = -1.8 + (i - 1) * (3.6 / (BoatFx.SLATS - 1))
		local offset = CFrame.new(x, 0.29, 0.2)
		local p = Common.part(
			"FloorSlat" .. i,
			Vector3.new(0.72, 0.07, 10.4),
			hull.CFrame * offset,
			wood,
			Enum.Material.WoodPlanks
		)
		table.insert(slats, { part = p, offset = offset, seed = i * 7.3 })
	end
end

local function stepWater(hull: BasePart, flood: number)
	local w = water
	if w == nil or w.Parent == nil then
		w = Common.part(
			"BoatWater",
			Vector3.new(4.4, 0.1, 11.4),
			hull.CFrame,
			Look.Palette.water:Lerp(Look.Palette.fog, 0.3),
			Enum.Material.SmoothPlastic,
			{ transparency = 0.25, reflectance = 0.15 }
		)
		water = w
	end
	local wp = w :: BasePart
	if flood <= 0.005 then
		wp.Transparency = 1
		return
	end
	local depth = math.max(0.08, flood * BoatFx.FLOOD_DEPTH)
	wp.Size = Vector3.new(4.4, depth, 11.4)
	local slosh = math.sin(clock * 1.3) * 0.03
	wp.CFrame = hull.CFrame * CFrame.new(0, 0.26 + depth / 2, 0.2) * CFrame.Angles(slosh, 0, slosh * 0.6)
	wp.Transparency = 0.25
end

-- A scoop of water thrown over the side by a bailing crewmate (a visual tell for the sound).
local function scoop(hull: BasePart, side: number)
	local from = hull.CFrame * CFrame.new(side * 1.2, 1.2, rnd:NextNumber(-3, 3))
	local blob = Common.part(
		"Scoop",
		Vector3.new(0.5, 0.35, 0.5),
		from,
		Look.Palette.water:Lerp(Color3.new(1, 1, 1), 0.25),
		Enum.Material.SmoothPlastic,
		{ transparency = 0.35, shape = Enum.PartType.Ball }
	)
	local out = hull.CFrame.RightVector * side
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.6 do
			local t = os.clock() - t0
			blob.CFrame = from + out * (t * 6) + Vector3.new(0, 2.2 * t - 6 * t * t, 0)
			blob.Transparency = 0.35 + t
			task.wait()
		end
		blob:Destroy()
	end)
	AudioDirector.play("bail-scoop", hull)
end

local function stepFlood(dt: number, hull: BasePart)
	local view = ViewState.get()
	local flood = tonumber(view.flood) or 0
	stepWater(hull, flood)
	local wantLoop = flood > 0.005 and leak
	if wantLoop and floodLoop == nil then
		floodLoop = AudioDirector.loop("flood-in-loop", hull)
	elseif not wantLoop and floodLoop then
		local l = floodLoop :: Sound
		l:Destroy()
		floodLoop = nil
	end
	for i, p in view.players or {} do
		if type(p) == "table" and p.bailing and p.alive and flood > 0.005 then
			local id = tonumber(p.id) or i
			scoopT[id] = (scoopT[id] or rnd:NextNumber(0, 0.5)) - dt
			if (scoopT[id] :: number) <= 0 then
				scoopT[id] = BoatFx.SCOOP_EVERY
				scoop(hull, if i % 2 == 0 then -1 else 1)
			end
		elseif type(p) == "table" then
			scoopT[tonumber(p.id) or i] = nil
		end
	end
end

function BoatFx.init()
	local builtFor: BasePart? = nil
	RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local k = math.min(1, dt * 4)
		buzzLevel += (buzzTarget - buzzLevel) * k
		shiverLevel += (shiverTarget - shiverLevel) * k
		local hull = BoatClient.hull()
		if hull == nil then
			return
		end
		if builtFor ~= hull then
			buildSlats(hull)
			builtFor = hull
		end
		for _, s in slats do
			local j = CFrame.new()
			if buzzLevel > 0.01 then
				local a = buzzLevel * 0.045
				j = CFrame.new(
					math.noise(clock * 55, s.seed) * a,
					math.abs(math.noise(clock * 61, s.seed + 3)) * a * 1.6,
					math.noise(clock * 47, s.seed + 9) * a
				)
			end
			s.part.CFrame = hull.CFrame * capsizeRoll * s.offset * j
		end
		stepFlood(dt, hull)
		stepMotor()
		stepCapsize()
		if rings then
			ringT -= dt
			if ringT <= 0 then
				ringT = BoatFx.RINGS.every
				spawnRing(hull)
			end
		end
	end)
	-- Camera shake after the camera scripts have placed the camera (Enum.RenderPriority.Camera
	-- is 200), so the offset lands on this frame.
	RunService:BindToRenderStep("DeadCalmBoatShake", Enum.RenderPriority.Camera.Value + 2, function()
		local cam = Workspace.CurrentCamera
		if cam == nil then
			return
		end
		-- The boat is thrown: the camera rolls with the local copy of the boat.
		local hull = BoatClient.hull()
		if capsizeCopy ~= nil and copyMode == "throw" and hull then
			local pivot = hull.CFrame
			cam.CFrame = pivot * capsizeRoll * pivot:Inverse() * cam.CFrame
		end
		-- Pulled under: drop below the surface, looking up a little toward it.
		local p0 = plungeT0
		if p0 ~= nil then
			local P = BoatFx.PLUNGE
			local t = clock - p0
			if t > P.maxHold then
				BoatFx.clearCamera()
			else
				local k = math.min(1, t / P.seconds)
				k = k * k
				local bottom = Config.Lake.waterY - P.depth
				local drop = math.max(0, plungeFrom - bottom) * k
				cam.CFrame = (cam.CFrame - Vector3.new(0, drop, 0)) * CFrame.Angles(0.35 * k, 0, 0.25 * k)
			end
		end
		local amp = 0
		local left = shakeUntil - clock
		if left > 0 then
			amp = shakeAmp * (left / shakeLen)
		end
		amp += buzzLevel * BoatFx.BUZZ_CAMERA
		-- The running outboard: a faint steady rumble through the boat.
		local me = ViewState.me()
		if ViewState.get().motorOn == true and capsizeCopy == nil and (me == nil or me.alive ~= false) then
			amp += BoatFx.MOTOR_RUMBLE
		end
		if amp <= 0.0005 then
			return
		end
		local t = clock * 30
		local off = Vector3.new(math.noise(t, 0.1), math.noise(t, 5.7), math.noise(t, 9.9)) * amp
		local roll = math.noise(t, 13.1) * amp * 0.06
		cam.CFrame = cam.CFrame * CFrame.new(off) * CFrame.Angles(0, 0, roll)
	end)
end

return BoatFx
