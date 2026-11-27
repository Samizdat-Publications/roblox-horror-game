--!strict
-- The server half of the rules on screen: the things every player must see the same way.
-- Everything a single player may see alone (an `only` cue, the Watcher, the Neighbor's
-- boat, the fake-outs) is built on the client by the fx modules, from the events.
--
--   * A death you can see: the taken player's character is hidden (no body, ever), their hat
--     (or a stand-in cap) floats on the water beside their seat and slowly sinks, and their
--     rod clatters into the bottom of the boat.
--   * The Neighbor's fail: a silhouette sits in the taken player's seat for a while.
--   * Knocks: every Knock intent is heard on the hull by the whole crew (a server Sound, so it
--     replicates), since Core sends no event for a knock.
--   * A new night puts everything back: characters shown, rods back in their holders,
--     anyone left out of the boat seated again.
--
-- Sounds with id 0 are skipped silently, like everywhere else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))
local SoundRegistry = require(Shared:WaitForChild("SoundRegistry"))
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))

local server = script.Parent
local BoatService = require(server:WaitForChild("BoatService"))
local NightService = require(server:WaitForChild("NightService"))
local Net = require(server:WaitForChild("Net"))

type Event = Types.Event

local EntityPresenter = {}

EntityPresenter.FOLDER = "DeadCalmPresenter"
EntityPresenter.HAT_FLOAT = 7 -- seconds the hat bobs on the water before it sinks
EntityPresenter.HAT_SINK = 5
EntityPresenter.SILHOUETTE_SECONDS = 25

-- Seat offsets in the hull frame (BoatHull: forward is -Z, port is -X) and the side the
-- hat lands on.
local SEAT_SIDE: { [string]: Vector3 } = {
	HelmSeat = Vector3.new(3.6, 0, 4.4),
	BowSeat = Vector3.new(-3.4, 0, -5.2),
	PortSeat = Vector3.new(-3.6, 0, -1.4),
	StarboardSeat = Vector3.new(3.6, 0, -1.4),
}
local SEAT_POS: { [string]: Vector3 } = {
	HelmSeat = Vector3.new(0, 0.95, 4.4),
	BowSeat = Vector3.new(0, 0.95, -5.2),
	PortSeat = Vector3.new(-1.15, 0.95, -1.4),
	StarboardSeat = Vector3.new(1.15, 0.95, -1.4),
}

type Hidden = { [Instance]: number }

local folder: Folder? = nil
local hidden: { [number]: Hidden } = {} -- userId -> original transparencies
local dropped: { [string]: BasePart } = {} -- seat name -> the rod lying in the boat
local seatOfDead: { [number]: string } = {}
local silhouettes: { Model } = {}

local function fxFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = EntityPresenter.FOLDER
	nf.Parent = Workspace
	folder = nf
	return nf
end

-- A server Sound replicates to every client. Silent (nil) for id 0.
function EntityPresenter.play(name: string, parent: Instance): Sound?
	local entry = SoundRegistry.get(name)
	local uri = SoundRegistry.uri(name)
	if entry == nil or uri == nil then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = uri
	s.Volume = entry.volume or 0.5
	s.Looped = false
	if entry.spatial then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = entry.minDist or 10
		s.RollOffMaxDistance = entry.maxDist or 200
	end
	s.Parent = parent
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(20, function()
		if s.Parent then
			s:Destroy()
		end
	end)
	s:Play()
	return s
end

local function loosePart(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = fxFolder()
	return p
end

----------------------------------------------------------------------------------------
-- Deaths you can see

local function hideCharacter(player: Player)
	local char = player.Character
	if char == nil then
		return
	end
	local store: Hidden = hidden[player.UserId] or {}
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			if store[d] == nil then
				store[d] = (d :: any).Transparency
			end
			(d :: any).Transparency = 1
		end
	end
	hidden[player.UserId] = store
end

local function showCharacter(userId: number)
	local store = hidden[userId]
	if store == nil then
		return
	end
	for inst, t in store do
		if inst.Parent then
			(inst :: any).Transparency = t
		end
	end
	hidden[userId] = nil
end

-- The player's hat (a clone of the handle) or a stand-in cap, as one loose part.
local function hatFor(player: Player): BasePart
	local char = player.Character
	if char then
		for _, acc in char:GetChildren() do
			if acc:IsA("Accessory") and acc.AccessoryType == Enum.AccessoryType.Hat then
				local handle = acc:FindFirstChild("Handle")
				if handle and handle:IsA("BasePart") then
					local h = handle:Clone()
					for _, d in h:GetDescendants() do
						if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Attachment") then
							d:Destroy()
						end
					end
					h.Name = "FloatingHat"
					h.Anchored = true
					h.CanCollide = false
					h.CanQuery = false
					h.CanTouch = false
					h.Massless = true
					h.Transparency = 0
					h.Parent = fxFolder()
					return h
				end
			end
		end
	end
	-- Stand-in: a dark cloth cap with a brim.
	local cap = loosePart(
		"FloatingHat",
		Vector3.new(0.7, 1.3, 1.3),
		CFrame.new(),
		Color3.fromRGB(58, 52, 40),
		Enum.Material.Fabric
	)
	cap.Shape = Enum.PartType.Cylinder
	local brim =
		loosePart("Brim", Vector3.new(0.12, 1.9, 1.9), CFrame.new(), Color3.fromRGB(48, 43, 34), Enum.Material.Fabric)
	brim.Shape = Enum.PartType.Cylinder
	brim.Parent = cap
	local w = Instance.new("WeldConstraint")
	w.Part0 = cap
	w.Part1 = brim
	w.Parent = cap
	brim.Anchored = false
	brim.Massless = true
	return cap
end

-- The hat bobs on the water where they were, then slowly goes under.
local function floatHat(player: Player, seat: string)
	local b = BoatService.get()
	local side = SEAT_SIDE[seat] or SEAT_SIDE.HelmSeat
	local at = b.hull.CFrame:PointToWorldSpace(side)
	local wy = Config.Lake.waterY
	local hat = hatFor(player)
	-- Lay a stand-in cap crown-up (cylinders run along X).
	local tilt = if hat.Name == "FloatingHat"
			and hat:IsA("Part")
			and hat.Shape == Enum.PartType.Cylinder
		then CFrame.Angles(0, 0, math.rad(90))
		else CFrame.new()
	local start = CFrame.new(at.X, wy + 0.25, at.Z) * tilt
	hat.CFrame = start
	-- The brim follows the cap through its weld only if unanchored; keep it in place.
	local brim = hat:FindFirstChild("Brim")
	if brim and brim:IsA("BasePart") then
		brim.Anchored = true
		brim.CFrame = start * CFrame.new(-0.35, 0, 0)
	end
	task.spawn(function()
		local t0 = os.clock()
		while hat.Parent and os.clock() - t0 < EntityPresenter.HAT_FLOAT do
			local t = os.clock() - t0
			local drift = Vector3.new(math.sin(t * 0.3) * 0.6, math.sin(t * 1.7) * 0.08, t * 0.12)
			local cf = start + drift
			hat.CFrame = cf * CFrame.Angles(math.sin(t * 1.1) * 0.08, t * 0.05, 0)
			if brim and brim:IsA("BasePart") then
				brim.CFrame = hat.CFrame * CFrame.new(-0.35, 0, 0)
			end
			task.wait(1 / 15)
		end
		if hat.Parent == nil then
			return
		end
		local goal = hat.CFrame - Vector3.new(0, 2.2, 0)
		TweenService:Create(
			hat,
			TweenInfo.new(EntityPresenter.HAT_SINK, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
			{ CFrame = goal, Transparency = 1 }
		):Play()
		if brim and brim:IsA("BasePart") then
			TweenService:Create(
				brim,
				TweenInfo.new(EntityPresenter.HAT_SINK, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
				{ CFrame = goal * CFrame.new(-0.35, 0, 0), Transparency = 1 }
			):Play()
		end
		task.wait(EntityPresenter.HAT_SINK + 0.2)
		hat:Destroy()
	end)
end

-- The seat's rod comes out of its holder and clatters onto the floorboards.
local function dropRod(seat: string)
	local b = BoatService.get()
	local rod = b.model:FindFirstChild("Rod_" .. seat)
	if rod == nil or not rod:IsA("BasePart") or dropped[seat] then
		return
	end
	rod.Transparency = 1
	local seatPos = SEAT_POS[seat] or SEAT_POS.HelmSeat
	local len = rod.Size.Z
	-- Lying fore and aft on the floor beside the seat, slightly askew.
	local floorLocal = CFrame.new(seatPos.X * 0.6 + 0.9, 0.33, seatPos.Z - 0.4) * CFrame.Angles(0, 0.25, 0)
	local liftLocal = floorLocal * CFrame.new(0, 0.9, 0) * CFrame.Angles(0.35, 0, 0.5)
	local copy = Instance.new("Part")
	copy.Name = "DroppedRod_" .. seat
	copy.Size = Vector3.new(0.12, 0.12, len)
	copy.Color = rod.Color
	copy.Material = rod.Material
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.CastShadow = false
	copy.Massless = true
	copy.Anchored = false
	copy.CollisionGroup = "Boat"
	local function weldAt(localCf: CFrame)
		local old = copy:FindFirstChildOfClass("WeldConstraint")
		if old then
			old:Destroy()
		end
		-- Position first, then weld: the WeldConstraint keeps the offset it finds.
		copy.CFrame = b.hull.CFrame * localCf
		local w = Instance.new("WeldConstraint")
		w.Part0 = b.hull
		w.Part1 = copy
		w.Parent = copy
	end
	copy.Parent = b.model
	weldAt(liftLocal)
	dropped[seat] = copy
	task.delay(0.18, function()
		if copy.Parent then
			weldAt(floorLocal * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, 0.2))
			EntityPresenter.play("rod-clatter", b.hull)
		end
	end)
	task.delay(0.32, function()
		if copy.Parent then
			weldAt(floorLocal)
		end
	end)
end

local function seatNameOf(player: Player): string?
	local seat = BoatService.seatOf(player)
	if seat then
		return seat.Name
	end
	return nil
end

local function onDied(e: Event)
	local id = e.player
	if type(id) ~= "number" then
		return
	end
	local player = Players:GetPlayerByUserId(id)
	if player == nil then
		return
	end
	local seat = seatNameOf(player) or seatOfDead[id] or "HelmSeat"
	seatOfDead[id] = seat
	floatHat(player, seat)
	hideCharacter(player)
	if seat == "HelmSeat" then
		BoatService.setHelmInput(nil, 0, 0) -- the drowned never steer
	end
	dropRod(seat)
end

----------------------------------------------------------------------------------------
-- The Neighbor in your boat

local function buildSilhouette(seat: string): Model
	local b = BoatService.get()
	local m = Instance.new("Model")
	m.Name = "NeighborInTheBoat"
	local seatCf = b.hull.CFrame * CFrame.new(SEAT_POS[seat] or SEAT_POS.HelmSeat)
	local seatPart = b.seats[seat]
	if seatPart then
		seatCf = seatPart.CFrame
	end
	local black = Look.Palette.silhouette
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3?, neon: boolean?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color or black
		p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		p.Anchored = false
		p.CollisionGroup = "Boat"
		p.CFrame = seatCf * offset
		p.Parent = m
		local w = Instance.new("WeldConstraint")
		w.Part0 = b.hull
		w.Part1 = p
		w.Parent = p
		return p
	end
	-- Sitting, a little too tall, head bowed toward the water.
	piece("Torso", Vector3.new(1.5, 2.6, 0.8), CFrame.new(0, 1.6, 0.1))
	piece("Head", Vector3.new(0.9, 1.1, 0.9), CFrame.new(0, 3.35, -0.1) * CFrame.Angles(-0.25, 0, 0))
	piece("ThighL", Vector3.new(0.5, 0.5, 1.4), CFrame.new(-0.4, 0.45, -0.6))
	piece("ThighR", Vector3.new(0.5, 0.5, 1.4), CFrame.new(0.4, 0.45, -0.6))
	piece("ArmL", Vector3.new(0.4, 2.4, 0.4), CFrame.new(-0.95, 1.4, -0.2) * CFrame.Angles(0.3, 0, 0))
	piece("ArmR", Vector3.new(0.4, 2.4, 0.4), CFrame.new(0.95, 1.4, -0.2) * CFrame.Angles(0.3, 0, 0))
	m.Parent = b.model
	return m
end

local function onNeighborFail(e: Event)
	local data = e.data or {}
	local fx = data.effects
	if type(fx) ~= "table" or fx.silhouette ~= true then
		return
	end
	local seat = "BowSeat"
	local kill = fx.kill
	if type(kill) == "table" and type(kill[1]) == "number" then
		local p = Players:GetPlayerByUserId(kill[1])
		seat = (p and seatNameOf(p)) or seatOfDead[kill[1]] or seat
	end
	local m = buildSilhouette(seat)
	table.insert(silhouettes, m)
	task.delay(EntityPresenter.SILHOUETTE_SECONDS, function()
		if m.Parent then
			m:Destroy()
		end
	end)
end

----------------------------------------------------------------------------------------

local function onEvent(e: Event)
	if e.kind == "PlayerDied" then
		onDied(e)
	elseif e.kind == "EntityFail" and e.entity == "Neighbor" then
		onNeighborFail(e)
	end
end

local function onIntents(intents: { any })
	for _, it in intents do
		if it.kind == "Knock" then
			EntityPresenter.play("knock-answer", BoatService.get().hull)
		end
	end
end

-- A new night: everyone visible and back in the boat, the rods back, the props gone.
function EntityPresenter.reset()
	for userId in hidden do
		showCharacter(userId)
	end
	for seat, copy in dropped do
		copy:Destroy()
		local rod = BoatService.get().model:FindFirstChild("Rod_" .. seat)
		if rod and rod:IsA("BasePart") then
			rod.Transparency = 0
		end
	end
	dropped = {}
	for _, m in silhouettes do
		m:Destroy()
	end
	silhouettes = {}
	seatOfDead = {}
	local f = folder
	if f then
		f:ClearAllChildren()
	end
	for _, p in Players:GetPlayers() do
		if BoatService.seatOf(p) == nil and p.Character then
			BoatService.seatPlayer(p)
		end
	end
end

function EntityPresenter.init()
	Net.isDrowned = function(userId: number): boolean
		return hidden[userId] ~= nil
	end
	NightService.subscribe(onEvent)
	NightService.onIntents(onIntents)
	NightService.onStart(function()
		EntityPresenter.reset()
	end)
	Players.PlayerRemoving:Connect(function(p)
		hidden[p.UserId] = nil
		seatOfDead[p.UserId] = nil
	end)
end

-- For DebugDriver checks.
function EntityPresenter.snapshot(): { [string]: any }
	local h = {}
	for id in hidden do
		table.insert(h, id)
	end
	local d = {}
	for seat in dropped do
		table.insert(d, seat)
	end
	return { hidden = h, droppedRods = d, silhouettes = #silhouettes }
end

return EntityPresenter
