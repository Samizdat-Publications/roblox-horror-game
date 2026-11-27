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
--     and the camera rolls with it; white foam bursts at both gunwales under a brief cold
--     flash, and the held fish, a bucket, an oar and the tackle box fly over the gunwale and
--     splash (hold-lost-splash).
--   * plunge(): the camera drops under the surface with a cold blue-green underwater tint,
--     blur and bubbles rushing up, and stays there until clearCamera() (Drowned) or a new
--     night.
--   * rock(seconds): the drowned see the boat still rocking for a few seconds.
--   * rings(on): expanding rings on the water around the hull (the Hum building).
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
BoatFx.FOAM = { flecks = 30, color = Color3.fromRGB(236, 246, 246), life = 1.0 }
BoatFx.FLASH = { color = Color3.fromRGB(190, 215, 230), brightness = 1.8, range = 30 }
-- After the death card the drowned see the boat still rocking for a few seconds.
BoatFx.ROCK = { seconds = 5, roll = 0.16, heave = 0.35, rollPeriod = 2.3, heavePeriod = 1.7 }
BoatFx.PLUNGE = { seconds = 0.35, depth = 3.2, maxHold = 14 }
BoatFx.BUBBLES = 22
BoatFx.UNDERWATER = Color3.fromRGB(60, 160, 150) -- the tint under the surface
BoatFx.GRAVITY = 42
-- The Hum's rings: expanding circles on the water around the hull while it builds.
BoatFx.RINGS = { every = 0.8, from = 10, to = 44, life = 2.6, color = Color3.fromRGB(150, 175, 180) }
BoatFx.BUZZ_CAMERA = 0.04 -- camera rattle at full buzz (was 0.02, Neon wanted it felt)
BoatFx.MOTOR_RUMBLE = 0.008 -- camera rumble while the outboard runs
BoatFx.MOTOR_SHAKE = 0.06 -- the outboard copy's jitter in studs (was 0.035)

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

local function spawnRing(hull: BasePart)
	-- A ring of short flat segments on the water, growing and fading.
	local R = BoatFx.RINGS
	local center = Vector3.new(hull.Position.X, Config.Lake.waterY + 0.08, hull.Position.Z)
	local n = 28
	local segs: { BasePart } = {}
	for i = 1, n do
		segs[i] = Common.part(
			"HumRing",
			Vector3.new(1, 0.06, 0.22),
			CFrame.new(center),
			R.color,
			Enum.Material.Neon,
			{ transparency = 0.55 }
		)
	end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < R.life and segs[1].Parent do
			local t = (os.clock() - t0) / R.life
			local r = (R.from + (R.to - R.from) * (1 - (1 - t) * (1 - t))) / 2
			local len = 2 * math.pi * r / n * 1.05
			for i, s in segs do
				local a = (i - 1) * 2 * math.pi / n
				s.Size = Vector3.new(len, 0.06, 0.22)
				s.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
					* CFrame.Angles(0, -a + math.pi / 2, 0)
				s.Transparency = 0.55 + t * 0.45
			end
			task.wait()
		end
		for _, s in segs do
			s:Destroy()
		end
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
	for _, name in { "Motor", "MotorShaft" } do
		local real = BoatClient.part(name)
		if real then
			local p = Common.part("Local" .. name, real.Size, real.CFrame, real.Color, real.Material)
			table.insert(motorCopies, { part = p, real = real })
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
	local ring = Common.part(
		"Splash",
		Vector3.new(0.2, size, size),
		CFrame.new(at.X, Config.Lake.waterY + 0.05, at.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Look.Palette.water:Lerp(Color3.new(1, 1, 1), 0.55),
		Enum.Material.SmoothPlastic,
		{ shape = Enum.PartType.Cylinder, transparency = 0.25 }
	)
	local spout = Common.part(
		"Spout",
		Vector3.new(size * 0.35, size * 0.9, size * 0.35),
		CFrame.new(at.X, Config.Lake.waterY + size * 0.45, at.Z),
		Look.Palette.water:Lerp(Color3.new(1, 1, 1), 0.7),
		Enum.Material.SmoothPlastic,
		{ shape = Enum.PartType.Ball, transparency = 0.3 }
	)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.9 do
			local t = (os.clock() - t0) / 0.9
			ring.Size = Vector3.new(0.2, size * (1 + t * 2.5), size * (1 + t * 2.5))
			ring.Transparency = 0.25 + t * 0.75
			spout.Size = Vector3.new(size * 0.35, math.max(0.05, size * 0.9 * (1 - t)), size * 0.35)
			spout.Transparency = 0.3 + t * 0.7
			task.wait()
		end
		ring:Destroy()
		spout:Destroy()
	end)
	AudioDirector.play("hold-lost-splash", at)
end

-- Something thrown over the gunwale: flies, spins, splashes, sinks.
local function throwItem(item: BasePart, from: CFrame, vel: Vector3, spin: Vector3)
	item.CFrame = from
	task.spawn(function()
		local t0 = os.clock()
		local splashed = false
		while item.Parent and os.clock() - t0 < 3 do
			local t = os.clock() - t0
			local pos = from.Position + vel * t + Vector3.new(0, -0.5 * BoatFx.GRAVITY * t * t, 0)
			if not splashed and pos.Y < Config.Lake.waterY and t > 0.15 then
				splashed = true
				splash(pos, 2.4)
			end
			if splashed then
				pos = Vector3.new(pos.X, math.max(pos.Y, Config.Lake.waterY - 2), pos.Z)
				item.Transparency = math.min(1, item.Transparency + 0.06)
			end
			item.CFrame = CFrame.new(pos) * from.Rotation * CFrame.Angles(spin.X * t, spin.Y * t, spin.Z * t)
			task.wait()
		end
		item:Destroy()
	end)
end

local FISH_SPECIES = { "YellowPerch", "Pumpkinseed", "Walleye", "Bullhead", "ChainPickerel" }

local function launchHold(hull: BasePart, fishCount: number)
	local base = hull.CFrame * CFrame.new(0, 1.9, 1.6)
	local side = if rnd:NextNumber() < 0.5 then -1 else 1
	for i = 1, fishCount do
		local spec = (Look.Fish :: any)[FISH_SPECIES[(i - 1) % #FISH_SPECIES + 1]]
		local fish = Common.part(
			"ThrownFish",
			if spec then Vector3.new(spec.width, spec.height, spec.length) else Vector3.new(0.45, 0.7, 1.8),
			base,
			if spec then spec.body else Color3.fromRGB(150, 140, 90),
			Enum.Material.SmoothPlastic
		)
		local out = hull.CFrame.RightVector * side * rnd:NextNumber(7, 11)
			+ hull.CFrame.LookVector * rnd:NextNumber(-3, 3)
		task.delay((i - 1) * 0.12, function()
			throwItem(fish, base, out + Vector3.new(0, rnd:NextNumber(13, 17), 0), Vector3.new(9, 3, 4))
		end)
		side = -side
	end
	-- A bait bucket goes too.
	local bucket = Common.part(
		"ThrownBucket",
		Vector3.new(1.3, 1.2, 1.2),
		base,
		Look.Palette.metal:Lerp(Color3.new(1, 1, 1), 0.45),
		Enum.Material.Metal,
		{ shape = Enum.PartType.Cylinder }
	)
	task.delay(0.08, function()
		throwItem(
			bucket,
			hull.CFrame * CFrame.new(0, 1.6, 3.4),
			hull.CFrame.RightVector * side * 9 + Vector3.new(0, 15, 0),
			Vector3.new(6, 2, 8)
		)
	end)
	-- Loose gear: an oar and the tackle box (pale enough to read in the dark).
	local oar = Common.part(
		"ThrownOar",
		Vector3.new(0.3, 0.3, 6.5),
		base,
		Look.Palette.boatWood:Lerp(Color3.new(1, 1, 1), 0.35),
		Enum.Material.Wood
	)
	task.delay(0.15, function()
		throwItem(
			oar,
			hull.CFrame * CFrame.new(-side * 1.4, 1.8, -1),
			hull.CFrame.RightVector * -side * 8 + Vector3.new(0, 14, 0),
			Vector3.new(2, 7, 1)
		)
	end)
	local box = Common.part(
		"ThrownTackle",
		Vector3.new(1.4, 0.8, 0.9),
		base,
		Color3.fromRGB(196, 92, 60),
		Enum.Material.SmoothPlastic
	)
	task.delay(0.22, function()
		throwItem(
			box,
			hull.CFrame * CFrame.new(side * 1, 1.5, -2.5),
			hull.CFrame.RightVector * side * 7 + hull.CFrame.LookVector * 3 + Vector3.new(0, 16, 0),
			Vector3.new(7, 5, 3)
		)
	end)
end

-- White foam at both gunwales: Neon flecks thrown up and out that fall and fade.
local function foamBurst(hull: BasePart)
	local F = BoatFx.FOAM
	for i = 1, F.flecks do
		local side = if i % 2 == 0 then 1 else -1
		local from = hull.CFrame * CFrame.new(side * 2.3, 0.2, rnd:NextNumber(-5, 5))
		local size = rnd:NextNumber(0.3, 0.75)
		local fleck = Common.part(
			"Foam",
			Vector3.new(size, size, size),
			from,
			F.color,
			Enum.Material.Neon,
			{ shape = Enum.PartType.Ball, transparency = 0.15 }
		)
		local vel = hull.CFrame.RightVector * side * rnd:NextNumber(4, 10) + Vector3.new(0, rnd:NextNumber(8, 16), 0)
		local delay = rnd:NextNumber(0, 0.25)
		task.delay(delay, function()
			local t0 = os.clock()
			while fleck.Parent and os.clock() - t0 < F.life do
				local t = os.clock() - t0
				local pos = from.Position + vel * t + Vector3.new(0, -0.5 * BoatFx.GRAVITY * t * t, 0)
				fleck.CFrame = CFrame.new(Vector3.new(pos.X, math.max(pos.Y, Config.Lake.waterY), pos.Z))
				fleck.Transparency = 0.15 + 0.85 * (t / F.life)
				task.wait()
			end
			fleck:Destroy()
		end)
	end
	-- A pale ring of foam on the water on each side.
	for _, side in { -1, 1 } do
		local at = hull.Position + hull.CFrame.RightVector * side * 3
		local ring = Common.part(
			"FoamRing",
			Vector3.new(0.12, 6, 6),
			CFrame.new(at.X, Config.Lake.waterY + 0.06, at.Z) * CFrame.Angles(0, 0, math.rad(90)),
			F.color,
			Enum.Material.Neon,
			{ shape = Enum.PartType.Cylinder, transparency = 0.35 }
		)
		task.spawn(function()
			local t0 = os.clock()
			while ring.Parent and os.clock() - t0 < 1.3 do
				local t = (os.clock() - t0) / 1.3
				ring.Size = Vector3.new(0.12, 6 + t * 12, 6 + t * 12)
				ring.Transparency = 0.35 + t * 0.65
				task.wait()
			end
			ring:Destroy()
		end)
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
