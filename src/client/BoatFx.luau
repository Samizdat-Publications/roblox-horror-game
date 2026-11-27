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
--     (the server's boat is hidden on this client meanwhile) and the camera rolls with it;
--     the held fish and a bucket fly over the gunwale and splash (hold-lost-splash).
--   * plunge(): the camera drops under the surface with a cold blue-green underwater tint
--     and blur, and stays there until clearCamera() (Drowned) or a new night.
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
BoatFx.CAPSIZE = { roll = 0.62, heave = 1.4, pitch = 0.16, rollPeriod = 0.55, heavePeriod = 0.42 }
BoatFx.PLUNGE = { seconds = 0.35, depth = 3.2, maxHold = 14 }
BoatFx.UNDERWATER = Color3.fromRGB(60, 160, 150) -- the tint under the surface
BoatFx.GRAVITY = 42

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

function BoatFx.reset()
	buzzTarget, buzzLevel = 0, 0
	shiverTarget, shiverLevel = 0, 0
	shakeAmp, shakeUntil = 0, 0
	flickerUntil = 0
	leak = false
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
		local a = 0.035
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
		Look.Palette.metal:Lerp(Color3.new(1, 1, 1), 0.2),
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
end

-- The boat is thrown for `seconds`: a local copy rolls and heaves, the camera rolls with it,
-- and `fishCount` fish plus a bucket go over the side.
function BoatFx.capsize(seconds: number, fishCount: number)
	local model = BoatClient.model()
	local hull = BoatClient.hull()
	if model == nil or hull == nil then
		return
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
	launchHold(hull, math.clamp(fishCount, 1, 4))
	AudioDirector.play("hold-lost-splash", hull)
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
	local C = BoatFx.CAPSIZE
	local env = math.min(1, t / 0.18)
	-- Thrown hard to one side, back over, and up and down on the swell.
	local roll = C.roll * env * math.sin(2 * math.pi * t / C.rollPeriod + 0.4)
	local heave = C.heave * env * math.abs(math.sin(2 * math.pi * t / C.heavePeriod))
	local pitch = C.pitch * env * math.sin(2 * math.pi * t / (C.rollPeriod * 0.8))
	capsizeRoll = CFrame.new(0, heave, 0) * CFrame.Angles(pitch, 0, roll)
	copy:PivotTo(hull.CFrame * capsizeRoll)
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
		if capsizeCopy ~= nil and hull then
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
		amp += buzzLevel * 0.02
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
