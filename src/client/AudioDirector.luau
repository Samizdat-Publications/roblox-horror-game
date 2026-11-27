--!strict
-- Builds sounds from SoundRegistry, mixes the ambience layers from the NightView, plays the
-- night's events as sound, and plays one-shots at world positions. Any registry id that is 0
-- is skipped silently, and any id set nonzero later starts automatically: layers and
-- one-shots are looked up by name, never hard-wired to an instance.
--
-- Ambience layers (registry name -> where it plays):
--   beds:    bed-hull-lap and bed-lake-air (2D), bed-wind-trees (eight shore emitters)
--   chorus:  chorus-frogs-full (2D) at band 3 only, chorus-crickets while the chorus sings
--   dock:    dock-water-loop at the dock end
--   boat:    lantern-flame-loop at the lantern while lit, motor-idle-loop at the motor
-- The frog chorus is built from pieces (brief, 11/26/2026): the full loop at band 3, plus
-- single frog calls from random points along the nearest shore at band-dependent gaps
-- (Look.Mix.frogGaps), gradual between bands except the instant drop to 0 (Chorus), and
-- frog-first-back once when the chorus comes back from silence.
-- The dock radio is a playlist at the shack: radio-tune-1, static, radio-tune-2, static.
-- Tapes play through the Voice group, which carries an equalizer and a light distortion so
-- the clean speech sounds like a cassette, with ui-tape-click before and ui-tape-stop after.
-- One-shots: lantern-on/off, motor-start/stop, oar strokes and oarlock while rowing, hull
-- creaks, loon and owl calls on shore, and the fishing sounds from the night's events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))
local SoundRegistry = require(Shared:WaitForChild("SoundRegistry"))
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local LakeMap = require(Shared:WaitForChild("Core"):WaitForChild("LakeMap"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))
local ViewState = require(script.Parent:WaitForChild("ViewState"))
local Chorus = require(script.Parent:WaitForChild("Chorus"))
local Events = require(script.Parent:WaitForChild("Events"))

type NightView = Types.NightView

-- Where a layer plays. "2d" is not positional; the others resolve to world parts.
type Where = "2d" | "shore" | "dock" | "lantern" | "motor" | "hull"

type LayerDef = { key: string, sound: string, where: Where, base: string }

local LAYERS: { LayerDef } = {
	{ key = "hullLap", sound = "bed-hull-lap", where = "2d", base = "hullLap" },
	{ key = "lakeAir", sound = "bed-lake-air", where = "2d", base = "lakeAir" },
	{ key = "windTrees", sound = "bed-wind-trees", where = "shore", base = "windTrees" },
	{ key = "chorusFull", sound = "chorus-frogs-full", where = "2d", base = "chorus" },
	{ key = "crickets", sound = "chorus-crickets", where = "2d", base = "crickets" },
	{ key = "dockWater", sound = "dock-water-loop", where = "dock", base = "dockWater" },
	{ key = "lanternFlame", sound = "lantern-flame-loop", where = "lantern", base = "lanternFlame" },
	{ key = "motorIdle", sound = "motor-idle-loop", where = "motor", base = "motorIdle" },
	{ key = "reel", sound = "reel-click-loop", where = "hull", base = "reel" },
}

local CHORUS_KEYS = { chorusFull = true, crickets = true }
-- Layers a playing tape ducks.
local DUCKED =
	{ hullLap = true, lakeAir = true, windTrees = true, chorusFull = true, crickets = true, dockWater = true }

local FROG_CALLS = { "frog-peeper-a", "frog-peeper-b", "frog-bull-a", "frog-bull-b", "frog-gray-a", "frog-green-a" }

local RADIO_PLAYLIST = { "radio-tune-1", "radio-static-loop", "radio-tune-2", "radio-static-loop" }

local TAPES: { [string]: string } = {
	Night1 = "tape-night-1",
	Night2 = "tape-night-2",
	Night3 = "tape-night-3",
	Night4 = "tape-night-4",
	Night5 = "tape-night-5",
	Amendment = "tape-amended",
	Endless = "tape-endless",
}

local AudioDirector = {}

AudioDirector.SHORE_EMITTERS = 8

type Layer = {
	def: LayerDef,
	sounds: { Sound }, -- one per emitter (shore) or one
	volume: number, -- current mix level 0..1 (before the entry's own volume)
	parentKey: string?, -- the anchor the sounds currently hang on
}

type PlayOpts = { speed: number?, volume: number? }

local groups: { [string]: SoundGroup } = {}
local layers: { Layer } = {}
local emitterFolder: Folder? = nil
local shoreEmitters: { BasePart } = {}
local pool: { BasePart } = {}
local poolNext = 1
local frogPool: { BasePart } = {}
local frogNext = 1
local rnd = Random.new()
local tapePlaying = false
local tapeQueue: { string } = {}
local reeling = false

----------------------------------------------------------------------------------------
-- SEAM: Core.SoundMix
-- Target level 0..1 for every layer, from a NightView and the chorus level. Mix rules
-- (DESIGN.md): the chorus density follows the director; the motor ducks the chorus; silence
-- is used on purpose (the beds drop to Config.Mix.bedSilent when the chorus is dead).
local function mixFor(view: NightView, chorusLevel: number): { [string]: number }
	local motorMask = if view.motorOn then Config.Boat.motorSoundMask else 0
	local duck = 1 - motorMask
	local bed = if chorusLevel <= 0 then Config.Mix.bedSilent / Config.Mix.bed else 1
	return {
		hullLap = bed,
		lakeAir = bed,
		windTrees = 1,
		chorusFull = math.clamp(chorusLevel - 2, 0, 1) * duck,
		crickets = math.clamp(chorusLevel / 2, 0, 1) * duck,
		dockWater = 1,
		lanternFlame = if view.lanternOn then 1 else 0,
		motorIdle = if view.motorOn then 1 else 0,
		reel = if reeling then 1 else 0,
	}
end
-- END SEAM
----------------------------------------------------------------------------------------

local function makeGroups()
	for _, name in SoundRegistry.GROUPS do
		local g = Instance.new("SoundGroup")
		g.Name = "DeadCalm" .. name
		g.Volume = Look.Mix.groups[name] or 1
		if name == "Voice" then
			-- The tapes are clean speech; the cassette is made here.
			local T = Look.Mix.tape
			local eq = Instance.new("EqualizerSoundEffect")
			eq.Name = "Cassette"
			eq.LowGain = T.lowGain
			eq.MidGain = T.midGain
			eq.HighGain = T.highGain
			eq.Parent = g
			local dist = Instance.new("DistortionSoundEffect")
			dist.Name = "Tape"
			dist.Level = T.distortion
			dist.Parent = g
		end
		g.Parent = SoundService
		groups[name] = g
	end
end

local function emitterPart(name: string, pos: Vector3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(pos)
	p.Parent = emitterFolder
	return p
end

-- Make a Sound for a registry entry, or nil when its id is 0.
local function makeSound(name: string, parent: Instance?): Sound?
	local entry = SoundRegistry.get(name)
	local uri = SoundRegistry.uri(name)
	if entry == nil or uri == nil then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = uri
	s.Looped = entry.looped == true
	s.Volume = entry.volume or 0.5
	if entry.group and groups[entry.group] then
		s.SoundGroup = groups[entry.group]
	end
	if entry.spatial then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = entry.minDist or 10
		s.RollOffMaxDistance = entry.maxDist or 200
	end
	-- Non-spatial sounds play from SoundService; spatial ones from a part in the world.
	s.Parent = if entry.spatial and parent then parent else SoundService
	return s
end

local function anchorFor(where: Where): (Instance?, string?)
	if where == "dock" then
		return BoatClient.find("Dock", "DockEnd"), "dock"
	elseif where == "lantern" then
		return BoatClient.part("LanternGlow"), "lantern"
	elseif where == "motor" then
		return BoatClient.part("Motor"), "motor"
	elseif where == "hull" then
		return BoatClient.hull(), "hull"
	end
	return nil, nil
end

-- Create layer sounds that are missing (id nonzero and anchor present). Cheap to repeat.
local function ensureLayers()
	for _, layer in layers do
		local def = layer.def
		if not SoundRegistry.available(def.sound) then
			continue
		end
		if def.where == "shore" then
			if #layer.sounds == 0 then
				for i, part in shoreEmitters do
					local s = makeSound(def.sound, part)
					if s then
						-- Stagger the copies so the shore does not phase.
						s.TimePosition = (i - 1) * 3.7
						table.insert(layer.sounds, s)
					end
				end
			end
		elseif def.where == "2d" then
			if #layer.sounds == 0 then
				local s = makeSound(def.sound, nil)
				if s then
					table.insert(layer.sounds, s)
				end
			end
		else
			local anchor, key = anchorFor(def.where)
			local current = layer.sounds[1]
			if anchor and (current == nil or current.Parent ~= anchor) then
				if current then
					current:Destroy()
					layer.sounds = {}
				end
				local s = makeSound(def.sound, anchor)
				if s then
					table.insert(layer.sounds, s)
					layer.parentKey = key
				end
			end
		end
	end
end

local function stepLayers(dt: number)
	local chorusLevel = Chorus.level()
	local targets = mixFor(ViewState.get(), chorusLevel)
	for _, layer in layers do
		local def = layer.def
		local target = (targets[def.key] or 0) * (Look.Mix.layers[def.base] or 1)
		if tapePlaying and DUCKED[def.key] then
			target *= Look.Mix.tape.duck
		end
		if CHORUS_KEYS[def.key] and chorusLevel <= 0 then
			layer.volume = 0 -- the drop to silence is instant
		else
			local rate = if CHORUS_KEYS[def.key] then Look.Mix.chorusFadePerSecond else Look.Mix.fadePerSecond
			local stepV = rate * dt
			layer.volume += math.clamp(target - layer.volume, -stepV, stepV)
		end
		local entry = SoundRegistry.get(def.sound)
		local base = if entry then entry.volume or 0.5 else 0.5
		for _, s in layer.sounds do
			s.Volume = base * layer.volume
			if layer.volume > 0.001 then
				if not s.IsPlaying then
					s:Play()
				end
			elseif s.IsPlaying then
				s:Stop()
			end
		end
	end
end

-- Play a one-shot by registry name at a part, a position, or (nil) in 2D. Silent for id 0.
-- opts.speed sets PlaybackSpeed, opts.volume multiplies the registry volume.
function AudioDirector.play(name: string, at: (BasePart | Vector3)?, opts: PlayOpts?): Sound?
	if not SoundRegistry.available(name) then
		return nil
	end
	local parent: Instance? = nil
	if typeof(at) == "Vector3" then
		local p = pool[poolNext]
		poolNext = poolNext % #pool + 1
		p.CFrame = CFrame.new(at)
		parent = p
	elseif typeof(at) == "Instance" then
		parent = at :: BasePart
	end
	local s = makeSound(name, parent)
	if s == nil then
		return nil
	end
	s.Looped = false
	if opts then
		if opts.speed then
			s.PlaybackSpeed = opts.speed
		end
		if opts.volume then
			s.Volume *= opts.volume
		end
	end
	s.Ended:Once(function()
		s:Destroy()
	end)
	-- A sound that never loads never ends; clean it up anyway.
	task.delay(90, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	s:Play()
	return s
end

-- A looping sound by registry name on a part (spatial entries) or in 2D. Nil for id 0.
-- The caller stops and destroys it (fx modules do it on pass, fail and reset).
function AudioDirector.loop(name: string, at: BasePart?, volume: number?): Sound?
	local s = makeSound(name, at)
	if s == nil then
		return nil
	end
	s.Looped = true
	if volume then
		s.Volume *= volume
	end
	s:Play()
	return s
end

-- The registry volume for a name (fx modules fade loops relative to it).
function AudioDirector.baseVolume(name: string): number
	local e = SoundRegistry.get(name)
	return if e then e.volume or 0.5 else 0.5
end

----------------------------------------------------------------------------------------
-- The frog chorus from pieces

-- Seconds between single calls at a chorus level (0..3), or nil when silent. Between two
-- bands the gaps blend on a log scale; below band 1 they stretch as the chorus wakes.
function AudioDirector.frogGap(level: number): (number?, number?)
	if level <= 0 then
		return nil, nil
	end
	local gaps = Look.Mix.frogGaps
	if level < 1 then
		local k = math.max(level, 0.3)
		return gaps[1][1] / k, gaps[1][2] / k
	end
	local lo = math.clamp(math.floor(level), 1, 3)
	local hi = math.min(3, lo + 1)
	local f = math.clamp(level - lo, 0, 1)
	local a, b = gaps[lo], gaps[hi]
	local function blend(x: number, y: number): number
		return math.exp(math.log(x) + (math.log(y) - math.log(x)) * f)
	end
	return blend(a[1], b[1]), blend(a[2], b[2])
end

-- A random point just off the nearest shore to the listener.
local function shoreSpot(): Vector3
	local lake = Config.Lake
	local pos = BoatClient.pose()
	local cam = Workspace.CurrentCamera
	local from = pos or (if cam then cam.CFrame.Position else Vector3.zero)
	local near = LakeMap.nearestShorePoint(Config, { x = from.X, z = from.Z })
	local a = math.atan2(near.z / lake.radiusZ, near.x / lake.radiusX)
	a += rnd:NextNumber(-Look.Mix.frogShoreSpread, Look.Mix.frogShoreSpread)
	local k = rnd:NextNumber(0.99, 1.04)
	return Vector3.new(math.cos(a) * lake.radiusX * k, lake.waterY + 0.8, math.sin(a) * lake.radiusZ * k)
end

local function playFrog()
	local name = FROG_CALLS[rnd:NextInteger(1, #FROG_CALLS)]
	if not SoundRegistry.available(name) or #frogPool == 0 then
		return
	end
	local p = frogPool[frogNext]
	frogNext = frogNext % #frogPool + 1
	p.CFrame = CFrame.new(shoreSpot())
	local pitch, vol = Look.Mix.frogPitch, Look.Mix.frogVolume
	local motorKeep = if ViewState.get().motorOn then 1 - Config.Boat.motorSoundMask else 1
	local tapeKeep = if tapePlaying then Look.Mix.tape.duck else 1
	AudioDirector.play(name, p, {
		speed = rnd:NextNumber(pitch[1], pitch[2]),
		volume = rnd:NextNumber(vol[1], vol[2]) * motorKeep * tapeKeep,
	})
end

local function startFrogs()
	local timer = 0.5
	RunService.Heartbeat:Connect(function(dt)
		local level = Chorus.level()
		local lo, hi = AudioDirector.frogGap(level)
		if lo == nil or hi == nil then
			timer = rnd:NextNumber(0.3, 1.2) -- the first call after a silence comes quickly
			return
		end
		timer -= dt
		if timer <= 0 then
			playFrog()
			timer = rnd:NextNumber(lo, hi)
		end
	end)
	Chorus.onRise(function()
		AudioDirector.play("frog-first-back")
	end)
end

----------------------------------------------------------------------------------------
-- The dock radio: a playlist from the shack

local function startRadio()
	local i = 1
	local current: Sound? = nil
	local endsAt = 0
	local ended = false
	local function advance()
		if current then
			current:Destroy()
			current = nil
		end
		i = i % #RADIO_PLAYLIST + 1
	end
	RunService.Heartbeat:Connect(function()
		local anchor = BoatClient.find("Dock", "Shack", "ShackRadio")
		local s = current
		if s ~= nil and s.Parent == nil then
			current = nil -- the shack streamed out; start this item again when it is back
			s = nil
		end
		if anchor == nil then
			return
		end
		if s == nil then
			for _ = 1, #RADIO_PLAYLIST do
				local name = RADIO_PLAYLIST[i]
				local snd = makeSound(name, anchor)
				if snd then
					local static = name == "radio-static-loop"
					snd.Looped = static
					local level = Look.Mix.layers[if static then "radioStatic" else "radio"] or 1
					snd.Volume *= level
					ended = false
					snd.Ended:Connect(function()
						ended = true
					end)
					endsAt = os.clock() + (if static then Look.Mix.radioStaticSeconds else 400)
					snd:Play()
					current = snd
					return
				end
				i = i % #RADIO_PLAYLIST + 1
			end
			return
		end
		if ended or os.clock() >= endsAt then
			advance()
		end
	end)
end

----------------------------------------------------------------------------------------
-- The owner's tapes

local function runTapes()
	while #tapeQueue > 0 do
		local name = table.remove(tapeQueue, 1) :: string
		tapePlaying = true
		AudioDirector.play("ui-tape-click")
		task.wait(Look.Mix.tape.clickGap)
		local s = AudioDirector.play(name)
		if s then
			local done = false
			s.Ended:Once(function()
				done = true
			end)
			local t0 = os.clock()
			while not done and s.Parent ~= nil and os.clock() - t0 < 90 do
				if os.clock() - t0 > 4 and s.IsLoaded and not s.IsPlaying then
					break
				end
				task.wait(0.1)
			end
		end
		AudioDirector.play("ui-tape-stop")
		task.wait(0.4)
		tapePlaying = false
	end
end

function AudioDirector.playTape(name: string)
	table.insert(tapeQueue, name)
	if #tapeQueue == 1 and not tapePlaying then
		task.spawn(runTapes)
	end
end

function AudioDirector.tapePlaying(): boolean
	return tapePlaying
end

----------------------------------------------------------------------------------------
-- The night's events as sound

local function bobberOf(id: number?): BasePart?
	local f = Workspace:FindFirstChild("DeadCalmFishing")
	local b = f and id and f:FindFirstChild("Bobber_" .. tostring(id))
	if b and b:IsA("BasePart") then
		return b
	end
	return nil
end

local function onEvent(e: Events.Event)
	local data = e.data or {}
	local hull = BoatClient.hull()
	local kind = e.kind
	if kind == "Tape" then
		local name = TAPES[tostring(data.id)]
		if name then
			AudioDirector.playTape(name)
		end
	elseif kind == "CastOut" then
		AudioDirector.play("cast-whoosh", hull)
		task.delay(0.7, function()
			AudioDirector.play("line-plop", bobberOf(e.player) or hull)
		end)
	elseif kind == "Bite" then
		local b = bobberOf(e.player) or hull
		AudioDirector.play("bobber-tap", b)
		task.delay(0.25, function()
			AudioDirector.play("bobber-under", bobberOf(e.player) or hull)
		end)
	elseif kind == "HookLost" then
		if data.why == "Snap" then
			AudioDirector.play("line-snap", hull)
		end
	elseif kind == "Caught" then
		local points = if type(data.catch) == "table" then tonumber(data.catch.points) or 1 else 1
		AudioDirector.play(if points >= 3 then "fish-splash-big" else "fish-splash-small", hull)
		task.delay(0.5, function()
			AudioDirector.play("line-creak", hull)
		end)
	elseif kind == "Kept" then
		AudioDirector.play("fish-land-thud", hull)
	elseif kind == "Released" then
		AudioDirector.play("fish-release", hull)
	elseif kind == "Banked" then
		local cooler = BoatClient.find("Dock", "DockCooler")
		AudioDirector.play("cooler-open", cooler or hull)
		task.delay(0.9, function()
			AudioDirector.play("cooler-close", cooler or hull)
		end)
	elseif kind == "OilRefilled" then
		AudioDirector.play("oil-refill", hull)
	elseif kind == "QuotaMet" then
		AudioDirector.play("quota-met")
	elseif kind == "NightCleared" then
		AudioDirector.play("night-cleared-sting")
	elseif kind == "NightFailed" then
		AudioDirector.play("night-failed-sting")
		task.delay(2.5, function()
			AudioDirector.playTape("tape-night-failed")
		end)
	end
end

-- Reel clicks while any line is being reeled in (tension rising means the reel is held).
local function startReelWatch()
	local last: { [number]: number } = {}
	ViewState.onChange(function(view: NightView)
		local any = false
		for _, p in view.players or {} do
			if type(p) == "table" and p.fishing == "Reeling" then
				local prev = last[p.id]
				if prev ~= nil and p.tension > prev + 0.002 then
					any = true
				end
				last[p.id] = p.tension
			elseif type(p) == "table" then
				last[p.id] = nil
			end
		end
		reeling = any
	end)
end

----------------------------------------------------------------------------------------

-- One-shots that follow the boat and the shore without any night logic.
local function startIncidentals()
	local lastLantern: boolean? = nil
	local lastMotor: boolean? = nil
	local lastPos: Vector3? = nil
	local strokeT = 0
	local strokeSide = false
	local creakT = Look.Mix.hullCreakMin
	local wildT = Look.Mix.wildlifeMin

	RunService.Heartbeat:Connect(function(dt)
		local view = ViewState.get()
		if lastLantern ~= nil and view.lanternOn ~= lastLantern then
			AudioDirector.play(if view.lanternOn then "lantern-on" else "lantern-off", BoatClient.part("LanternGlow"))
		end
		lastLantern = view.lanternOn
		if lastMotor ~= nil and view.motorOn ~= lastMotor then
			AudioDirector.play(if view.motorOn then "motor-start" else "motor-stop", BoatClient.part("Motor"))
		end
		lastMotor = view.motorOn

		local hull = BoatClient.hull()
		if hull then
			local pos = hull.Position
			local speed = if lastPos and dt > 0 then (pos - lastPos).Magnitude / dt else 0
			lastPos = pos
			if not view.motorOn and speed > Config.Boat.stillSpeed then
				strokeT -= dt
				if strokeT <= 0 then
					strokeT = Look.Mix.oarStrokeSeconds
					strokeSide = not strokeSide
					AudioDirector.play(if strokeSide then "oar-stroke-a" else "oar-stroke-b", hull)
					if rnd:NextNumber() < 0.25 then
						AudioDirector.play("oarlock-creak", hull)
					end
				end
			else
				strokeT = 0
			end
			creakT -= dt
			if creakT <= 0 then
				creakT = rnd:NextNumber(Look.Mix.hullCreakMin, Look.Mix.hullCreakMax)
				AudioDirector.play("hull-creak", hull)
			end
		end

		wildT -= dt
		if wildT <= 0 then
			wildT = rnd:NextNumber(Look.Mix.wildlifeMin, Look.Mix.wildlifeMax)
			if Chorus.band() >= 2 and #shoreEmitters > 0 then
				local calls = { "loon-call", "loon-tremolo", "owl-hoot" }
				local spot = shoreEmitters[rnd:NextInteger(1, #shoreEmitters)]
				AudioDirector.play(calls[rnd:NextInteger(1, #calls)], spot.Position)
			end
		end
	end)
end

function AudioDirector.init()
	makeGroups()
	local folder = Instance.new("Folder")
	folder.Name = "DeadCalmAudio"
	folder.Parent = Workspace
	emitterFolder = folder

	local lake = Config.Lake
	for i = 1, AudioDirector.SHORE_EMITTERS do
		local a = (i - 0.5) * 2 * math.pi / AudioDirector.SHORE_EMITTERS
		local pos = Vector3.new(math.cos(a) * (lake.radiusX + 40), lake.waterY + 18, math.sin(a) * (lake.radiusZ + 40))
		table.insert(shoreEmitters, emitterPart("Shore" .. i, pos))
	end
	for i = 1, 10 do
		table.insert(pool, emitterPart("OneShot" .. i, Vector3.new(0, lake.waterY, 0)))
	end
	for i = 1, 12 do
		table.insert(frogPool, emitterPart("Frog" .. i, Vector3.new(0, lake.waterY, 0)))
	end

	for _, def in LAYERS do
		table.insert(layers, { def = def, sounds = {}, volume = 0, parentKey = nil })
	end

	local acc = 1
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 1 then
			acc = 0
			ensureLayers()
		end
		stepLayers(dt)
	end)
	startIncidentals()
	startFrogs()
	startRadio()
	startReelWatch()
	Events.onAny(onEvent)
end

-- For checks: which layers have live sounds right now, and their levels.
function AudioDirector.debugState(): { [string]: any }
	local out = {}
	for _, layer in layers do
		out[layer.def.key] = { sounds = #layer.sounds, volume = layer.volume }
	end
	out.chorusLevel = Chorus.level()
	out.tapePlaying = tapePlaying
	return out
end

return AudioDirector
