--!strict
-- Builds sounds from SoundRegistry, mixes the ambience layers from the NightView, and
-- plays one-shots at world positions. Any registry id that is 0 is skipped silently, and
-- any id set nonzero later starts automatically: layers and one-shots are looked up by
-- name, never hard-wired to an instance.
--
-- Ambience layers (registry name -> where it plays):
--   beds:    bed-hull-lap and bed-lake-air (2D), bed-wind-trees (eight shore emitters)
--   chorus:  chorus-frogs-full / thin / sparse by NightView.chorus band 3 / 2 / 1,
--            chorus-crickets while any band is singing
--   dock:    radio-tune-1 and radio-static-loop at the shack radio, dock-water-loop at the
--            dock end
--   boat:    lantern-flame-loop at the lantern while lit, motor-idle-loop at the motor
-- One-shots: lantern-on/off, motor-start/stop, oar strokes and oarlock while rowing, hull
-- creaks, loon and owl calls on shore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))
local SoundRegistry = require(Shared:WaitForChild("SoundRegistry"))
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))
local ViewState = require(script.Parent:WaitForChild("ViewState"))

type NightView = Types.NightView

-- Where a layer plays. "2d" is not positional; the others resolve to world parts.
type Where = "2d" | "shore" | "radio" | "dock" | "lantern" | "motor" | "hull"

type LayerDef = { key: string, sound: string, where: Where, base: string }

local LAYERS: { LayerDef } = {
	{ key = "hullLap", sound = "bed-hull-lap", where = "2d", base = "hullLap" },
	{ key = "lakeAir", sound = "bed-lake-air", where = "2d", base = "lakeAir" },
	{ key = "windTrees", sound = "bed-wind-trees", where = "shore", base = "windTrees" },
	{ key = "chorusFull", sound = "chorus-frogs-full", where = "2d", base = "chorus" },
	{ key = "chorusThin", sound = "chorus-frogs-thin", where = "2d", base = "chorus" },
	{ key = "chorusSparse", sound = "chorus-frogs-sparse", where = "2d", base = "chorus" },
	{ key = "crickets", sound = "chorus-crickets", where = "2d", base = "crickets" },
	{ key = "radio", sound = "radio-tune-1", where = "radio", base = "radio" },
	{ key = "radioStatic", sound = "radio-static-loop", where = "radio", base = "radioStatic" },
	{ key = "dockWater", sound = "dock-water-loop", where = "dock", base = "dockWater" },
	{ key = "lanternFlame", sound = "lantern-flame-loop", where = "lantern", base = "lanternFlame" },
	{ key = "motorIdle", sound = "motor-idle-loop", where = "motor", base = "motorIdle" },
}

local CHORUS_KEYS = { chorusFull = true, chorusThin = true, chorusSparse = true, crickets = true }

local AudioDirector = {}

AudioDirector.SHORE_EMITTERS = 8

type Layer = {
	def: LayerDef,
	sounds: { Sound }, -- one per emitter (shore) or one
	volume: number, -- current mix level 0..1 (before the entry's own volume)
	parentKey: string?, -- the anchor the sounds currently hang on
}

local groups: { [string]: SoundGroup } = {}
local layers: { Layer } = {}
local emitterFolder: Folder? = nil
local shoreEmitters: { BasePart } = {}
local pool: { BasePart } = {}
local poolNext = 1

----------------------------------------------------------------------------------------
-- SEAM: Core.SoundMix
-- Target level 0..1 for every layer, from a NightView. Mix rules (DESIGN.md): the chorus
-- density follows the director; the motor ducks the chorus; silence is used on purpose.
local function mixFor(view: NightView): { [string]: number }
	local band = view.chorus
	local motorMask = if view.motorOn then Config.Boat.motorSoundMask else 0
	local duck = 1 - motorMask
	return {
		hullLap = 1,
		lakeAir = 1,
		windTrees = 1,
		chorusFull = (if band >= 3 then 1 else 0) * duck,
		chorusThin = (if band == 2 then 1 else 0) * duck,
		chorusSparse = (if band == 1 then 1 else 0) * duck,
		crickets = (if band >= 1 then 1 else 0) * duck,
		radio = 1,
		radioStatic = 1,
		dockWater = 1,
		lanternFlame = if view.lanternOn then 1 else 0,
		motorIdle = if view.motorOn then 1 else 0,
	}
end
-- END SEAM
----------------------------------------------------------------------------------------

local function makeGroups()
	for _, name in SoundRegistry.GROUPS do
		local g = Instance.new("SoundGroup")
		g.Name = "DeadCalm" .. name
		g.Volume = Look.Mix.groups[name] or 1
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
	if where == "radio" then
		return BoatClient.find("Dock", "Shack", "ShackRadio"), "radio"
	elseif where == "dock" then
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
	local targets = mixFor(ViewState.get())
	for _, layer in layers do
		local def = layer.def
		local target = (targets[def.key] or 0) * (Look.Mix.layers[def.base] or 1)
		local rate = if CHORUS_KEYS[def.key] then Look.Mix.chorusFadePerSecond else Look.Mix.fadePerSecond
		local stepV = rate * dt
		layer.volume += math.clamp(target - layer.volume, -stepV, stepV)
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
function AudioDirector.play(name: string, at: (BasePart | Vector3)?): Sound?
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
	s.Ended:Once(function()
		s:Destroy()
	end)
	-- A sound that never loads never ends; clean it up anyway.
	task.delay(60, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	s:Play()
	return s
end

-- One-shots that follow the boat and the shore without any night logic.
local function startIncidentals()
	local lastLantern: boolean? = nil
	local lastMotor: boolean? = nil
	local lastPos: Vector3? = nil
	local strokeT = 0
	local strokeSide = false
	local creakT = Look.Mix.hullCreakMin
	local wildT = Look.Mix.wildlifeMin
	local rnd = Random.new()

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
			if view.chorus >= 2 and #shoreEmitters > 0 then
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
	for i = 1, 6 do
		table.insert(pool, emitterPart("OneShot" .. i, Vector3.new(0, lake.waterY, 0)))
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
end

-- For checks: which layers have live sounds right now, and their levels.
function AudioDirector.debugState(): { [string]: any }
	local out = {}
	for _, layer in layers do
		out[layer.def.key] = { sounds = #layer.sounds, volume = layer.volume }
	end
	return out
end

return AudioDirector
