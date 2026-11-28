--!strict
-- Turns the fishing events from Core.Night into things in the world: a rod at every seat,
-- the bobber and the line, the bobber's dance through the bite and the fight, the fish on
-- the line (built from the catch's traits by world/FishModel, so a wrong fish looks wrong),
-- the fish tokens on the hold lid, and the Field Guide drawings the client clones.
--
-- The server never sends the `wrong` flag: the fish model carries only what players see.
-- All parts here are Boat collision group, CanCollide off, and either anchored (bobbers) or
-- Massless and welded to the boat (rods, fish on the line, hold tokens).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))

local BoatService = require(script.Parent:WaitForChild("BoatService"))
local world = script.Parent:WaitForChild("world")
local Parts = require(world:WaitForChild("Parts"))
local FishModel = require(world:WaitForChild("FishModel"))

type Event = Types.Event
type NightView = Types.NightView

local FishingService = {}

FishingService.FOLDER = "DeadCalmFishing"
FishingService.GUIDE_FOLDER = "DeadCalmFieldGuide"
FishingService.GROUP = "Boat"

type Line = {
	userId: number,
	seat: string,
	phase: string,
	t: number,
	castAt: Vector3?,
	bobber: BasePart?,
	bobberAtt: Attachment?,
	beam: Beam?,
	fish: Model?,
	serial: number,
	tension: number,
	progress: number,
}

local folder: Folder? = nil
local rods: { [string]: { part: BasePart, tip: Attachment } } = {}
local lines: { [number]: Line } = {}
local tokens: { BasePart } = {}
local serialCounter = 0
local clock = 0
local ctx = { parts = Parts, look = Look }

local function weldToHull(part: BasePart, hull: BasePart)
	part.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = hull
	w.Part1 = part
	w.Parent = part
end

-- One rod per seat, leaning out over the side the seat casts toward.
local function buildRods()
	local b = BoatService.get()
	for name in Look.Gear.seats do
		local base, tip = Look.rodLocal(name)
		local mid = (base + tip) / 2
		local len = (tip - base).Magnitude
		local cf = b.hull.CFrame * CFrame.lookAt(mid, tip)
		local rod =
			Parts.block(b.model, "Rod_" .. name, Vector3.new(0.12, 0.12, len), cf, Look.Gear.rod, Enum.Material.Wood, {
				anchored = false,
				collide = false,
				query = false,
				shadow = false,
				group = FishingService.GROUP,
			})
		weldToHull(rod, b.hull)
		local att = Instance.new("Attachment")
		att.Name = "RodTip"
		att.Position = Vector3.new(0, 0, -len / 2)
		-- Curve downward toward the water rather than sideways along the default +X attachment axis.
		att.Axis = Vector3.new(0, -1, 0)
		att.Parent = rod
		rods[name] = { part = rod, tip = att }
	end
end

-- The Field Guide drawings: one book-true fish per species, for the client to clone.
local function buildGuide()
	local old = ReplicatedStorage:FindFirstChild(FishingService.GUIDE_FOLDER)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = FishingService.GUIDE_FOLDER
	for species, def in Config.Fish do
		local m = FishModel.build(ctx, species, def.traits :: any, CFrame.new(), {})
		m.Name = species
		m.Parent = f
	end
	f.Parent = ReplicatedStorage
end

function FishingService.init()
	local old = Workspace:FindFirstChild(FishingService.FOLDER)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = FishingService.FOLDER
	f.Parent = Workspace
	folder = f
	buildRods()
	buildGuide()
end

local function seatName(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	local seat = p and BoatService.seatOf(p)
	if seat and Look.Gear.seats[seat.Name] then
		return seat.Name
	end
	return "HelmSeat"
end

-- Destroys this player's bobber (with its line beam), including any stray one the Line
-- record lost track of, so nothing is left floating once a fish is out of the water.
local function removeBobber(l: Line)
	if l.bobber then
		l.bobber:Destroy()
	end
	local f = folder
	if f then
		local name = "Bobber_" .. l.userId
		local stray = f:FindFirstChild(name)
		while stray do
			stray:Destroy()
			stray = f:FindFirstChild(name)
		end
	end
	l.bobber, l.bobberAtt, l.beam = nil, nil, nil
end

local function clearLine(l: Line)
	removeBobber(l)
	if l.fish then
		l.fish:Destroy()
	end
	l.bobber, l.bobberAtt, l.beam, l.fish, l.castAt = nil, nil, nil, nil, nil
	l.phase = "Idle"
end

local function lineFor(userId: number): Line
	local l = lines[userId]
	if l == nil then
		l = {
			userId = userId,
			seat = "HelmSeat",
			phase = "Idle",
			t = 0,
			serial = 0,
			tension = 0,
			progress = 0,
		}
		lines[userId] = l
	end
	return l
end

local function makeBeam(parent: Instance, a0: Attachment, a1: Attachment, curve: number): Beam
	local beam = Instance.new("Beam")
	beam.Name = "Line"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = Look.Gear.lineWidth
	beam.Width1 = Look.Gear.lineWidth
	beam.Color = ColorSequence.new(Look.Gear.line)
	beam.Transparency = NumberSequence.new(0.15)
	beam.FaceCamera = true
	beam.Segments = 12
	beam.CurveSize0 = curve
	beam.CurveSize1 = 0
	beam.LightInfluence = Look.Gear.lineLightInfluence
	beam.LightEmission = Look.Gear.lineLightEmission
	beam.Parent = parent
	return beam
end

local function rodTipWorld(seat: string): Vector3?
	local r = rods[seat]
	if r == nil then
		return nil
	end
	return r.tip.WorldPosition
end

local function onCast(l: Line, power: number)
	clearLine(l)
	local f = folder
	local r = rods[l.seat]
	if f == nil or r == nil then
		return
	end
	local hull = BoatService.get().hull
	local s = Look.Gear.seats[l.seat] or Look.Gear.seats.HelmSeat
	local _, tipLocal = Look.rodLocal(l.seat)
	local reach = 6 + math.clamp(power, 0, 1) * 8
	local p = hull.CFrame:PointToWorldSpace(tipLocal + s.dir * reach)
	local at = Vector3.new(p.X, Config.Lake.waterY + 0.1, p.Z)
	local bs = Look.Gear.bobberSize
	local cs = Look.Gear.bobberCapSize
	local capOffset = bs * 0.52
	local bobber = Parts.block(
		f,
		"Bobber_" .. l.userId,
		Vector3.new(bs, bs, bs),
		CFrame.new(at),
		Look.Gear.bobber,
		Enum.Material.SmoothPlastic,
		{
			anchored = true,
			collide = false,
			query = false,
			shadow = false,
			group = FishingService.GROUP,
			shape = "Ball",
		}
	)
	local cap = Parts.block(
		bobber,
		"Cap",
		Vector3.new(cs, cs, cs),
		CFrame.new(at + Vector3.new(0, capOffset, 0)),
		Look.Gear.bobberCap,
		Enum.Material.SmoothPlastic,
		{
			anchored = true,
			collide = false,
			query = false,
			shadow = false,
			group = FishingService.GROUP,
			shape = "Ball",
		}
	)
	cap:SetAttribute("Offset", capOffset)
	local att = Instance.new("Attachment")
	att.Name = "LineEnd"
	att.Parent = bobber
	l.beam = makeBeam(bobber, r.tip, att, 1.4)
	l.bobber, l.bobberAtt, l.castAt = bobber, att, at
	l.phase = "Waiting"
	l.t = 0
end

local function placeBobber(l: Line, pos: Vector3)
	local b = l.bobber
	if b == nil then
		return
	end
	b.CFrame = CFrame.new(pos)
	for _, c in b:GetChildren() do
		if c:IsA("BasePart") then
			local off = c:GetAttribute("Offset")
			c.CFrame = CFrame.new(pos + Vector3.new(0, if type(off) == "number" then off else 0, 0))
		end
	end
end

local function onCaught(l: Line, catch: any)
	-- The fish is out of the water: the bobber and its line go (the next cast makes new ones);
	-- from here the line runs from the rod tip to the fish's mouth.
	removeBobber(l)
	l.castAt = nil
	if l.fish then
		l.fish:Destroy()
		l.fish = nil
	end
	local f = folder
	local r = rods[l.seat]
	if f == nil or r == nil or type(catch) ~= "table" or type(catch.traits) ~= "table" then
		return
	end
	local species = if type(catch.species) == "string" then catch.species else "Pumpkinseed"
	local spec = Look.Fish[species] or Look.Fish.Pumpkinseed
	local tip = r.tip.WorldPosition
	-- Hanging from the line, head up, a little below the rod tip.
	local at = CFrame.new(tip - Vector3.new(0, 1.0 + spec.length / 2, 0)) * CFrame.Angles(math.rad(90), 0, 0)
	local m = FishModel.build(ctx, species, catch.traits, at, { anchored = false, group = FishingService.GROUP })
	serialCounter += 1
	l.serial = serialCounter
	m.Name = "DeadCalmFish_" .. l.userId
	m:SetAttribute("Serial", serialCounter)
	m:SetAttribute("UserId", l.userId)
	local body = m.PrimaryPart :: BasePart
	local w = Instance.new("WeldConstraint")
	w.Part0 = r.part
	w.Part1 = body
	w.Parent = body
	local mouth = body:FindFirstChild("Mouth") :: Attachment?
	if mouth then
		makeBeam(body, r.tip, mouth, 0)
	end
	m.Parent = f
	l.fish = m
	l.phase = "Deciding"
end

-- Core events for this tick (before they are sanitized for clients).
function FishingService.handle(events: { Event })
	for _, e in events do
		local id = e.player
		local data = e.data or {}
		if id == nil then
			continue
		end
		local kind = e.kind
		if kind == "CastOut" then
			local l = lineFor(id)
			l.seat = seatName(id)
			onCast(l, tonumber(data.power) or 0.6)
		elseif kind == "Bite" then
			local l = lineFor(id)
			l.phase = "Bite"
			l.t = 0
		elseif kind == "Caught" then
			onCaught(lineFor(id), data.catch)
		elseif kind == "HookLost" or kind == "Released" or kind == "Kept" or kind == "PlayerDied" then
			local l = lines[id]
			if l then
				clearLine(l)
			end
		end
	end
end

-- The serial of the fish now on a player's line (the client matches it to the Caught event).
function FishingService.serialOf(userId: number): number
	local l = lines[userId]
	return if l then l.serial else 0
end

function FishingService.fishOf(userId: number): Model?
	local l = lines[userId]
	return if l then l.fish else nil
end

function FishingService.summaryOf(userId: number): { [string]: any }?
	local m = FishingService.fishOf(userId)
	return if m then FishModel.summary(m) else nil
end

-- Fish tokens on the hold lid, one per fish in the hold.
function FishingService.syncHold(count: number)
	count = math.clamp(math.floor(count), 0, 8)
	if #tokens == count then
		return
	end
	local b = BoatService.get()
	while #tokens > count do
		local t = table.remove(tokens) :: BasePart
		t:Destroy()
	end
	while #tokens < count do
		local i = #tokens + 1
		local x = -0.8 + ((i - 1) % 4) * 0.53
		local y = 1.84 + math.floor((i - 1) / 4) * 0.2
		local cf = b.hull.CFrame * CFrame.new(x, y, 1.6) * CFrame.Angles(0, math.rad(8 * ((i % 3) - 1)), 0)
		local t = Parts.block(
			b.model,
			"HoldFish" .. i,
			Vector3.new(0.3, 0.2, 0.9),
			cf,
			Look.Gear.token,
			Enum.Material.SmoothPlastic,
			{
				anchored = false,
				collide = false,
				query = false,
				shadow = false,
				group = FishingService.GROUP,
			}
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = t
		weldToHull(t, b.hull)
		table.insert(tokens, t)
	end
end

-- Animates bobbers from the NightView (tension and progress per player). Called every tick.
function FishingService.step(dt: number, view: NightView?)
	clock += dt
	local byId: { [number]: any } = {}
	if view then
		for _, p in view.players do
			byId[p.id] = p
		end
	end
	local wy = Config.Lake.waterY
	for id, l in lines do
		l.t += dt
		local pv = byId[id]
		if l.bobber and l.castAt then
			local at = l.castAt :: Vector3
			if l.phase == "Waiting" or l.phase == "Bite" then
				-- Keep the floating bobber tethered within reach if the boat drifts or rows slowly.
				local tip = rodTipWorld(l.seat)
				if tip then
					local flat = Vector3.new(at.X - tip.X, 0, at.Z - tip.Z)
					local maxReach = 26
					if flat.Magnitude > maxReach then
						local clamped = tip + flat.Unit * maxReach
						at = Vector3.new(clamped.X, wy + 0.1, clamped.Z)
						l.castAt = at
					end
				end
			end
			if l.phase == "Waiting" then
				placeBobber(l, at + Vector3.new(0, 0.05 * math.sin(l.t * 2.2), 0))
			elseif l.phase == "Bite" then
				-- Pulled under in quick taps: the visual twin of the bobber tap.
				local dip = 0.35 * math.abs(math.sin(l.t * 13))
				placeBobber(l, Vector3.new(at.X, wy + 0.1 - dip, at.Z))
				if pv and pv.fishing == "Reeling" then
					l.phase = "Reeling"
				end
			end
			if pv and pv.fishing == "Reeling" then
				l.phase = "Reeling"
				local tip = rodTipWorld(l.seat) or at
				local near = Vector3.new(tip.X, wy, tip.Z)
				local p = at:Lerp(near, math.clamp(pv.progress or 0, 0, 1) * 0.85)
				local shake = (pv.tension or 0) * 0.25
				local jx = shake * math.noise(clock * 3, id % 97)
				local jz = shake * math.noise(clock * 3, 11 + id % 89)
				placeBobber(l, Vector3.new(p.X + jx, wy - 0.15 - 0.1 * (pv.tension or 0), p.Z + jz))
			end
		end
		local fish = l.fish
		if fish and fish:GetAttribute("Blinks") then
			FishModel.animateLids(fish, Look, clock, id % 13)
		end
		if pv and pv.fishing == "Idle" and l.phase ~= "Idle" then
			clearLine(l)
		end
	end
end

-- Clears every line and the hold tokens (a new night).
function FishingService.reset()
	for _, l in lines do
		clearLine(l)
	end
	FishingService.syncHold(0)
end

return FishingService
