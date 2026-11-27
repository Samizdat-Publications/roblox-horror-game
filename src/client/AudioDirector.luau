--!strict
-- Builds sounds from SoundRegistry, mixes the ambience layers from the NightView, plays the
-- night's events as sound, and plays one-shots at world positions. Any registry id that is 0
-- is skipped silently, and any id set nonzero later starts automatically: layers and
-- one-shots are looked up by name, never hard-wired to an instance. An id-0 entry with a
-- `derive` table is built here from a real sound (speed, region, effects, layers, repeat
-- timer) and plays by the same name; an entry's `repeat` plays it several times.
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

-- repeatGap overrides the registry's `repeat` gap (the knocks follow the server's timing).
type PlayOpts = { speed: number?, volume: number?, repeatGap: number? }

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
local tapeRunning = false -- a runTapes loop is working through the queue
local tapeGen = 0 -- bumped by stopTape; a loop from an older generation quits
local currentTape: Sound? = nil
local tapeOpenUntil = -math.huge -- Tape events are taken until this time (night start)
local tapeQueue: { string } = {}
local reeling = false

-- Scare polish 2 mix state. Any Rule-group sound playing (unless its entry says duck = false)
-- ducks the Ambience group; so does an EntityCue for Look.Mix.cueHold seconds.
local duckers: { [Sound]: boolean } = {}
local duckHoldUntil = -math.huge
local duckLevel = 1 -- current Ambience duck multiplier (1 = none)
local muteKeys: { [string]: boolean } = {}
local muteLevel = 1
local muteFadeSeconds: number? = nil -- the fade the last muteAmbience call asked for
local hushKeys: { [string]: boolean } = {}
local hushLevel = 1 -- every group but Rule (the finale's dead silence before the bell)
local chorusOverrideUntil = -math.huge -- listening test: hold the chorus at band 3
local ambienceBase = Look.Mix.groups.Ambience or 1 -- the group level before trim, duck, mute
local ambienceLastSet = ambienceBase
local ambienceLastFactor = 1
local underPart: BasePart? = nil -- follows the hull, just under the keel (knocks)
local auditionPart: BasePart? = nil -- listening test: where a far cue plays

-- The chorus level this client mixes with: the real one, or 3 while a listening test holds
-- the full chorus underneath.
local function chorusLevel(): number
	if os.clock() < chorusOverrideUntil then
		return 3
	end
	return Chorus.level()
end

----------------------------------------------------------------------------------------
-- SEAM: Core.SoundMix
-- Target level 0..1 for every layer, from a NightView and the chorus level. Mix rules
-- (DESIGN.md): the chorus density follows the director; the motor ducks the chorus; silence
-- is used on purpose (the beds drop to Config.Mix.bedSilent when the chorus is dead).
local function mixFor(view: NightView, level: number): { [string]: number }
	local motorMask = if view.motorOn then Config.Boat.motorSoundMask else 0
	local duck = 1 - motorMask
	local bed = if level <= 0 then Config.Mix.bedSilent / Config.Mix.bed else 1
	return {
		hullLap = bed,
		lakeAir = bed,
		windTrees = 1,
		chorusFull = math.clamp(level - 2, 0, 1) * duck,
		crickets = math.clamp(level / 2, 0, 1) * duck,
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

----------------------------------------------------------------------------------------
-- Derived sounds (SoundRegistry `derive`): a piece is one Sound made from a real id and
-- shaped with PlaybackSpeed, a PlaybackRegion and SoundEffect children. Callers never see
-- the difference: play() and loop() return the first piece, named after the entry.

-- Effect children from a derive's `effects` list. Unknown classes or properties are skipped
-- with a warning (SoundRegistry.EFFECT_PROPS lists what the docs confirm).
local function addEffects(s: Sound, effects: { SoundRegistry.Effect })
	for i, fx in effects do
		local allowed = SoundRegistry.EFFECT_PROPS[fx.class]
		if allowed == nil then
			warn("AudioDirector: unknown effect class " .. tostring(fx.class) .. " on " .. s.Name)
			continue
		end
		local e: any = Instance.new(fx.class :: any)
		e.Name = "Derive" .. i
		for prop, value in fx.props or {} do
			if allowed[prop] then
				e[prop] = value
			else
				warn("AudioDirector: " .. fx.class .. " has no property " .. prop .. " (" .. s.Name .. ")")
			end
		end
		e.Parent = s
	end
end

local function regionStart(part: SoundRegistry.Derive?): number
	local r = part and part.region
	if r and r[1] and r[2] and r[2] > r[1] then
		return r[1]
	end
	return 0
end

local function shapePiece(s: Sound, part: SoundRegistry.Derive)
	if part.speed then
		s.PlaybackSpeed = part.speed
	end
	local r = part.region
	if r and r[1] and r[2] and r[2] > r[1] then
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = NumberRange.new(r[1], r[2])
		s.TimePosition = r[1]
	end
	if part.effects then
		addEffects(s, part.effects)
	end
end

-- A Sound with the entry's mix settings (volume, group, rolloff) playing `uri`.
local function buildSound(name: string, entry: SoundRegistry.SoundEntry, uri: string, parent: Instance?): Sound
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

-- Make a Sound for a registry entry (a derived entry is shaped from its source), or nil
-- when there is nothing to play.
local function makeSound(name: string, parent: Instance?): Sound?
	local entry = SoundRegistry.get(name)
	local uri = SoundRegistry.uri(name)
	if entry == nil or uri == nil then
		return nil
	end
	local s = buildSound(name, entry, uri, parent)
	local d = entry.derive
	if entry.id == 0 and d then
		shapePiece(s, d)
		if d.repeatEvery then
			s.Looped = false -- the repeat timer replays it instead
		end
	end
	return s
end

-- A layer of a derived entry: the entry's mix settings, the layer's source and shape.
local function makeLayer(name: string, layer: SoundRegistry.Derive, parent: Instance?): Sound?
	local entry = SoundRegistry.get(name)
	local uri = SoundRegistry.uri(layer.from)
	if entry == nil or uri == nil then
		return nil
	end
	local s = buildSound(name, entry, uri, parent)
	s.Looped = false
	s.Volume *= layer.volume or 1
	shapePiece(s, layer)
	return s
end

-- Runs one piece's timing (repeat timer, duration cut, fades) and calls `done` once when the
-- piece is over: ended, cut, or destroyed. Volume is only written when the piece fades, so
-- callers that set Volume themselves (Watcher's tone) keep control.
local function runPiece(s: Sound, part: SoundRegistry.Derive?, oneShot: boolean, done: () -> ())
	local finished = false
	local function finish()
		if not finished then
			finished = true
			done()
		end
	end
	s.Destroying:Once(finish)
	local every = part and part.repeatEvery
	local dur = part and part.duration
	if oneShot and every and dur == nil then
		every = nil -- a one-shot repeat needs a duration, or it would never end
	end
	local fadeIn = part and part.fadeIn
	local fadeOut = part and part.fadeOut
	if every == nil and dur == nil then
		s.Ended:Once(finish)
		if fadeIn == nil then
			return
		end
	end
	local start = regionStart(part)
	task.spawn(function()
		local base = s.Volume
		local t0 = os.clock()
		local nextAt = every
		local fades = (fadeIn ~= nil and fadeIn > 0) or (dur ~= nil and fadeOut ~= nil and fadeOut > 0)
		while s.Parent ~= nil and not finished do
			local t = os.clock() - t0
			if fades then
				local k = 1
				if fadeIn and fadeIn > 0 and t < fadeIn then
					k = t / fadeIn
				end
				if dur and fadeOut and fadeOut > 0 then
					k = math.min(k, math.clamp((dur - t) / fadeOut, 0, 1))
				end
				s.Volume = base * k
			end
			if dur and t >= dur then
				s:Stop()
				break
			end
			if nextAt and every and t >= nextAt then
				nextAt += every
				s.TimePosition = start
				s:Play()
			end
			task.wait()
		end
		if dur or every then
			finish()
		end
	end)
end

-- Starts a sound made by makeSound: its own timing, its layers and its `repeat` copies.
-- One-shots are destroyed when every piece is over; destroying the returned sound early
-- cancels pieces that have not started and stops the ones playing.
local function startPlayback(name: string, s: Sound, oneShot: boolean, repeatGap: number?)
	local entry = SoundRegistry.get(name)
	if entry == nil then
		return
	end
	local d = if entry.id == 0 then entry.derive else nil
	local rep = entry["repeat"]
	local startVol = s.Volume
	local pending = 1
	local dead = false
	local copies: { Sound } = {}

	local function pieceDone()
		pending -= 1
		if pending <= 0 and oneShot and not dead then
			task.defer(function()
				if s.Parent then
					s:Destroy()
				end
			end)
		end
	end

	s.Destroying:Once(function()
		dead = true
		for _, c in copies do
			if c.Parent then
				c:Destroy()
			end
		end
	end)

	local function schedule(delay: number, part: SoundRegistry.Derive?, build: () -> Sound?)
		pending += 1
		task.delay(delay, function()
			if dead then
				pieceDone()
				return
			end
			local c = build()
			if c == nil then
				pieceDone()
				return
			end
			c.Looped = false
			if startVol > 0 then
				c.Volume *= s.Volume / startVol -- follow what the caller did to the first piece
			end
			table.insert(copies, c)
			runPiece(c, part, true, function()
				task.defer(function()
					if c.Parent then
						c:Destroy()
					end
				end)
				pieceDone()
			end)
			c:Play()
		end)
	end

	runPiece(s, d, oneShot, pieceDone)

	if d and d.layers then
		for _, layer in d.layers do
			schedule(layer.delay or 0, layer, function()
				return makeLayer(name, layer, s.Parent)
			end)
		end
	end
	if rep and rep.count > 1 then
		local gap = repeatGap or rep.gap
		for i = 1, rep.count - 1 do
			schedule(gap * i, d, function()
				return makeSound(name, s.Parent)
			end)
		end
	end
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

-- A part that follows the hull just under the keel: knocks play from here (close and dry).
function AudioDirector.under(): BasePart?
	return underPart
end

-- True while the ambience is ducked for a rule cue.
function AudioDirector.ducking(): boolean
	return duckLevel < 0.98
end

-- Mutes the Ambience group (frogs, chorus, beds, the water) while any key is on: the death
-- card, the finale. `seconds` is how long the fade takes (default Look.Mix.muteFade).
function AudioDirector.muteAmbience(key: string, on: boolean, seconds: number?)
	muteKeys[key] = if on then true else nil
	muteFadeSeconds = seconds
end

-- Hushes every group except Rule while any key is on (the motor, the lantern, fishing,
-- music, the tapes): the finale's dead silence before the bell. Rule sounds (the bell) still
-- play. Fades over Look.Mix.hushFade.
function AudioDirector.hush(key: string, on: boolean)
	hushKeys[key] = if on then true else nil
end

-- Polish round 2 (Neon finale v7 heard no motor on the run home): a multiplier on one
-- layer's mix target, by layer key (fx/Finale lifts "motorIdle" for the run home). 1 clears.
local layerBoost: { [string]: number } = {}
function AudioDirector.boostLayer(key: string, mult: number)
	layerBoost[key] = if math.abs(mult - 1) < 1e-3 then nil else mult
end

-- A sound that ducks the ambience while it plays (Rule group unless duck = false).
local function trackDuck(name: string, s: Sound)
	local entry = SoundRegistry.get(name)
	if entry == nil or entry.group ~= "Rule" or entry.duck == false then
		return
	end
	duckers[s] = true
	s.Destroying:Once(function()
		duckers[s] = nil
	end)
end

local function anyDucker(): boolean
	for s in duckers do
		if s.Parent == nil then
			duckers[s] = nil
		elseif s.IsPlaying and s.Volume > 0.02 then
			return true
		end
	end
	return false
end

-- Ambience group level: base, eased down toward band 3, ducked for cues, muted for cards.
local function stepGroups(dt: number)
	local g = groups.Ambience
	if g == nil then
		return
	end
	local M = Look.Mix
	local band3 = math.clamp(chorusLevel() - 2, 0, 1)
	local trim = 1 + (M.band3Trim - 1) * band3
	local wantDuck = if anyDucker() or os.clock() < duckHoldUntil then M.cueDuck else 1
	if wantDuck < duckLevel then
		duckLevel = math.max(wantDuck, duckLevel - dt * (1 - M.cueDuck) / M.duckAttack)
	else
		duckLevel = math.min(wantDuck, duckLevel + dt * (1 - M.cueDuck) / M.duckRelease)
	end
	local wantMute = if next(muteKeys) ~= nil then 0 else 1
	local k = dt / math.max(0.01, muteFadeSeconds or M.muteFade)
	muteLevel += math.clamp(wantMute - muteLevel, -k, k)
	local wantHush = if next(hushKeys) ~= nil then 0 else 1
	local kh = dt / math.max(0.01, M.hushFade or 0.12)
	hushLevel += math.clamp(wantHush - hushLevel, -kh, kh)
	for name, other in groups do
		if name ~= "Ambience" and name ~= "Rule" then
			other.Volume = (M.groups[name] or 1) * hushLevel
		end
	end
	-- Polish 3: fx/Finale no longer writes this group (it calls muteAmbience). A change made
	-- by anyone else since the last frame still moves the base, so this mix rides on top of
	-- it instead of fighting it.
	if math.abs(g.Volume - ambienceLastSet) > 1e-4 and ambienceLastFactor > 0.01 then
		ambienceBase = g.Volume / ambienceLastFactor
	end
	local factor = trim * duckLevel * muteLevel * hushLevel
	g.Volume = math.clamp(ambienceBase * factor, 0, 10)
	ambienceLastSet = g.Volume
	ambienceLastFactor = factor
	local u = underPart
	local hull = BoatClient.hull()
	if u and hull then
		u.CFrame = hull.CFrame * CFrame.new(0, -1.6, 0)
	end
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
	local level = chorusLevel()
	local targets = mixFor(ViewState.get(), level)
	for _, layer in layers do
		local def = layer.def
		local target = (targets[def.key] or 0) * (Look.Mix.layers[def.base] or 1) * (layerBoost[def.key] or 1)
		if tapePlaying and DUCKED[def.key] then
			target *= Look.Mix.tape.duck
		end
		if CHORUS_KEYS[def.key] and level <= 0 then
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
			s.PlaybackSpeed *= opts.speed -- on top of a derived entry's own speed
		end
		if opts.volume then
			s.Volume *= opts.volume
		end
	end
	-- Destroyed when every piece is over (one piece for a plain sound: when it ends).
	startPlayback(name, s, true, opts and opts.repeatGap)
	trackDuck(name, s)
	-- A sound that never loads never ends; clean it up anyway.
	task.delay(90, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	s:Play()
	-- Companions (`with`): same place, same options, stopped with this one.
	local entry = SoundRegistry.get(name)
	if entry and entry.with then
		for _, other in entry.with do
			local c = AudioDirector.play(other, at, opts)
			if c then
				s.Destroying:Once(function()
					if c.Parent then
						c:Destroy()
					end
				end)
			end
		end
	end
	return s
end

-- A looping sound by registry name on a part (spatial entries) or in 2D. Nil when there is
-- nothing to play. The caller stops and destroys it (fx modules do it on pass, fail and
-- reset); destroying it also ends a derived loop's repeat timer and layers.
function AudioDirector.loop(name: string, at: BasePart?, volume: number?): Sound?
	local s = makeSound(name, at)
	if s == nil then
		return nil
	end
	local entry = SoundRegistry.get(name)
	local d = if entry and entry.id == 0 then entry.derive else nil
	s.Looped = not (d ~= nil and d.repeatEvery ~= nil)
	if volume then
		s.Volume *= volume
	end
	startPlayback(name, s, false)
	trackDuck(name, s)
	s:Play()
	return s
end

----------------------------------------------------------------------------------------
-- Studio listening test (DebugBot "play_sound")

-- Where the real fx play a cue (Scare polish 2: the first test played everything at the
-- hull, which is not where the Neighbor or the Watcher are heard in a night). Returns the
-- anchor kind and a short label for the log.
--   far    the Neighbor: Config.Rules.Neighbor.appearDist off the bow, 40 degrees to one side
--   shore  the Watcher and the shore fake-outs: the nearest shore point
--   buoy   a buoy clank: 150 studs off to port
--   under  knocks and water in the boat: just under the keel
--   cooler the dock cooler (WrongCatch), else the hull
--   lantern, motor  those boat parts
--   hull   every other spatial cue; nil plays 2D
function AudioDirector.auditionSpot(name: string): string?
	local entry = SoundRegistry.get(name)
	if entry == nil or not entry.spatial then
		return nil
	end
	if string.sub(name, 1, 9) == "neighbor-" then
		return "far"
	elseif string.sub(name, 1, 8) == "watcher-" or name == "fake-branch-snap" or name == "fake-loon-scream" then
		return "shore"
	elseif name == "fake-buoy-clank" then
		return "buoy"
	elseif
		string.sub(name, 1, 6) == "knock-"
		or name == "fake-single-knock"
		or name == "flood-in-loop"
		or name == "bail-scoop"
	then
		return "under"
	elseif string.sub(name, 1, 7) == "cooler-" then
		return "cooler"
	elseif string.sub(name, 1, 8) == "lantern-" or name == "fake-lantern-flicker" then
		return "lantern"
	elseif string.sub(name, 1, 6) == "motor-" then
		return "motor"
	end
	return "hull"
end

local function placeAudition(pos: Vector3): BasePart?
	local p = auditionPart
	if p == nil or p.Parent == nil then
		p = emitterPart("Audition", pos)
		auditionPart = p
	end
	local ap = p :: BasePart
	ap.CFrame = CFrame.new(pos)
	return ap
end

local function auditionAnchor(kind: string?): BasePart?
	local hull = BoatClient.hull()
	if kind == nil then
		return nil
	elseif kind == "under" then
		return underPart or hull
	elseif kind == "lantern" then
		return BoatClient.part("LanternGlow") or hull
	elseif kind == "motor" then
		return BoatClient.part("Motor") or hull
	elseif kind == "cooler" then
		return BoatClient.find("Dock", "DockCooler") or hull
	elseif hull == nil then
		return nil
	end
	local y = Config.Lake.waterY + 0.5
	if kind == "far" then
		local d = Config.Rules.Neighbor.appearDist
		local dir = (hull.CFrame * CFrame.Angles(0, math.rad(-40), 0)).LookVector
		return placeAudition(Vector3.new(hull.Position.X + dir.X * d, y + 2, hull.Position.Z + dir.Z * d))
	elseif kind == "buoy" then
		local dir = -hull.CFrame.RightVector
		return placeAudition(Vector3.new(hull.Position.X + dir.X * 150, y + 1, hull.Position.Z + dir.Z * 150))
	elseif kind == "shore" then
		local near = LakeMap.nearestShorePoint(Config, { x = hull.Position.X, z = hull.Position.Z })
		return placeAudition(Vector3.new(near.x, y + 6, near.z))
	end
	return hull
end

-- Plays any registry sound by name on this client the way the real fx would: at the same
-- place relative to the boat (auditionSpot), through the same group, so it ducks the
-- ambience like a real cue. Loops stop after `seconds` (default 8). opts.ambience = true
-- holds the full band-3 chorus (loop, crickets, single frogs) under it, so the test is
-- honest. Returns whether it played, and where.
local auditions: { Sound } = {}
function AudioDirector.audition(name: string, seconds: number?, opts: { ambience: boolean? }?): (boolean, string?)
	if not SoundRegistry.available(name) then
		return false, nil
	end
	local secs = seconds or 8
	if opts and opts.ambience then
		-- Long enough to bridge the gap to the next cue in a sequence (no drop to silence).
		chorusOverrideUntil = math.max(chorusOverrideUntil, os.clock() + secs + 6)
	end
	local entry = SoundRegistry.get(name)
	local kind = AudioDirector.auditionSpot(name)
	local at = auditionAnchor(kind)
	local s: Sound?
	if entry and entry.looped then
		s = AudioDirector.loop(name, at)
		local loopSound = s
		if loopSound then
			task.delay(secs, function()
				if loopSound.Parent then
					loopSound:Destroy()
				end
			end)
		end
	else
		s = AudioDirector.play(name, at)
	end
	if s then
		table.insert(auditions, s)
	end
	return s ~= nil, kind or "2d"
end

-- Stops every sound started by audition and lets the chorus go back to the night's level.
function AudioDirector.stopAuditions()
	for _, s in auditions do
		if s.Parent then
			s:Destroy()
		end
	end
	auditions = {}
	chorusOverrideUntil = -math.huge
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
		local level = chorusLevel()
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

-- Tapes play only at night start (Studio and Neon fixes, 11/26/2026): a Tape event is
-- taken only within TAPE_WINDOW seconds of NightStarted. Any rule cue cuts the tape.
AudioDirector.TAPE_WINDOW = 3
AudioDirector.TAPE_CUT = 0.25 -- seconds to fade a cut tape (inside the 0.3 s the cue needs)
AudioDirector.tapesMuted = false -- Studio scenarios: no tapes at all

local function runTapes(gen: number)
	while #tapeQueue > 0 and gen == tapeGen do
		local name = table.remove(tapeQueue, 1) :: string
		tapePlaying = true
		AudioDirector.play("ui-tape-click")
		task.wait(Look.Mix.tape.clickGap)
		if gen ~= tapeGen then
			break
		end
		local s = AudioDirector.play(name)
		currentTape = s
		if s then
			local done = false
			s.Ended:Once(function()
				done = true
			end)
			local t0 = os.clock()
			while not done and s.Parent ~= nil and gen == tapeGen and os.clock() - t0 < 90 do
				if os.clock() - t0 > 4 and s.IsLoaded and not s.IsPlaying then
					break
				end
				task.wait(0.05)
			end
		end
		if gen ~= tapeGen then
			break
		end
		currentTape = nil
		AudioDirector.play("ui-tape-stop")
		task.wait(0.4)
		tapePlaying = false
	end
	if gen == tapeGen then
		tapePlaying = false
		tapeRunning = false
	end
end

function AudioDirector.playTape(name: string)
	if AudioDirector.tapesMuted then
		return
	end
	table.insert(tapeQueue, name)
	if not tapeRunning then
		tapeRunning = true
		task.spawn(runTapes, tapeGen)
	end
end

-- Cuts the tape now: the voice fades out in TAPE_CUT seconds and the queue is dropped.
-- `click` plays ui-tape-stop when a tape was actually cut.
function AudioDirector.stopTape(click: boolean)
	local wasPlaying = tapePlaying
	tapeGen += 1
	tapeQueue = {}
	tapeRunning = false
	tapePlaying = false
	local s = currentTape
	currentTape = nil
	if s and s.Parent then
		local v0 = s.Volume
		task.spawn(function()
			local t0 = os.clock()
			while s.Parent and os.clock() - t0 < AudioDirector.TAPE_CUT do
				s.Volume = v0 * (1 - (os.clock() - t0) / AudioDirector.TAPE_CUT)
				task.wait()
			end
			s:Destroy()
		end)
	end
	if click and wasPlaying then
		AudioDirector.play("ui-tape-stop")
	end
end

-- Studio scenarios: no tapes while muted (and cut the one playing).
function AudioDirector.muteTapes(on: boolean)
	AudioDirector.tapesMuted = on
	if on then
		AudioDirector.stopTape(false)
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
		if name and os.clock() <= tapeOpenUntil then
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
	elseif kind == "NightStarted" then
		-- A new night cancels whatever tape was left over; its own tape follows.
		AudioDirector.stopTape(false)
		tapeOpenUntil = os.clock() + AudioDirector.TAPE_WINDOW
	elseif kind == "EntityCue" then
		-- Rule cues duck everything else: the tape is cut so it never talks over a cue, and the
		-- ambience ducks at once (the cue's own sounds keep it down while they play).
		AudioDirector.stopTape(true)
		duckHoldUntil = os.clock() + Look.Mix.cueHold
	end
	-- NightFailed: the sting and the "Rough night" tape come with the end card (NightCards).
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
				-- No random creak over a rule cue (it masked the knocks).
				if not AudioDirector.ducking() then
					AudioDirector.play("hull-creak", hull)
				end
			end
		end

		wildT -= dt
		if wildT <= 0 then
			wildT = rnd:NextNumber(Look.Mix.wildlifeMin, Look.Mix.wildlifeMax)
			if chorusLevel() >= 2 and #shoreEmitters > 0 and not AudioDirector.ducking() then
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
	underPart = emitterPart("UnderKeel", Vector3.new(0, lake.waterY - 1, 0))

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
		stepGroups(dt)
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
		local s = layer.sounds[1]
		out[layer.def.key] = {
			sounds = #layer.sounds,
			volume = layer.volume,
			soundVolume = if s then s.Volume else nil,
			playing = s ~= nil and s.IsPlaying,
			loaded = s ~= nil and s.IsLoaded,
			parent = if s and s.Parent then s.Parent.Name else nil,
			group = if s and s.SoundGroup then s.SoundGroup.Name else nil,
		}
	end
	out.chorusLevel = chorusLevel()
	out.tapePlaying = tapePlaying
	local gv = {}
	for name, g in groups do
		gv[name] = g.Volume
	end
	out.groups = gv
	out.duck = duckLevel
	out.mute = muteLevel
	out.hush = hushLevel
	out.motorBoost = layerBoost.motorIdle or 1
	return out
end

return AudioDirector
