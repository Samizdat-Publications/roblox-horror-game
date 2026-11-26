--!strict
-- The physical boat. One unanchored assembly owned by the server, driven by AlignPosition
-- and AlignOrientation toward the pose that the boat kinematics compute from helm input,
-- held at the water line with a small scripted bob. Four seats; only the helm steers.
--
-- The lantern and motor flags here mirror Core.Night: NightService calls setLantern and
-- setMotor from the NightView after every tick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local world = script.Parent:WaitForChild("world")
local BoatHull = require(world:WaitForChild("BoatHull"))
local Landmarks = require(world:WaitForChild("Landmarks"))

export type Kin = {
	x: number,
	z: number,
	heading: number, -- radians, atan2(look.x, look.z): 0 faces +z (north)
	speed: number, -- studs per second along the heading, negative when backing
}

local BoatService = {}

BoatService.INPUT_TIMEOUT = 0.6 -- helm input older than this counts as zero
BoatService.BOAT_RADIUS = 6.5 -- for keeping clear of the dock, steeple and buoy
BoatService.SHORE_MARGIN = 14
BoatService.TIE_OFFSET = 9 -- the boat ties up this far past the dock end, bow out

local built: BoatHull.Built? = nil
local kin: Kin = { x = 0, z = 0, heading = 0, speed = 0 }
local helm = { throttle = 0, steer = 0, at = -math.huge }
local motorOn = false
local lanternOn = true
local alignPos: AlignPosition? = nil
local alignOri: AlignOrientation? = nil
local clock = 0
local ownerWarned = false

----------------------------------------------------------------------------------------
-- SEAM: replace with Core.BoatModel
-- Pure kinematics from Config.Boat. Mutates and returns `s`.
local function stepKinematics(s: Kin, throttle: number, steer: number, motor: boolean, dt: number): Kin
	local b = Config.Boat
	local top = if motor then b.motorSpeed else b.rowSpeed
	local target = if throttle >= 0 then throttle * top else throttle * top * 0.5
	if math.abs(throttle) > 0.01 then
		local stepV = b.accel * dt
		s.speed += math.clamp(target - s.speed, -stepV, stepV)
	else
		s.speed -= s.speed * math.min(1, b.drag * dt)
		if math.abs(s.speed) < 0.05 then
			s.speed = 0
		end
	end
	-- Oars can pivot a still boat a little; steering bites harder with way on.
	local turnScale = 0.35 + 0.65 * math.min(1, math.abs(s.speed) / b.rowSpeed)
	-- steer +1 is a turn to starboard (right). Facing +z, right is -x, so heading decreases.
	s.heading -= steer * b.turnRate * turnScale * dt
	s.heading = math.atan2(math.sin(s.heading), math.cos(s.heading))
	s.x += math.sin(s.heading) * s.speed * dt
	s.z += math.cos(s.heading) * s.speed * dt
	return s
end
-- END SEAM
----------------------------------------------------------------------------------------

-- Keep the boat on the lake and clear of the dock, the steeple and the buoy. World parts
-- do not collide with the boat (collision groups), so this is the only thing that does.
local function confine(s: Kin)
	local lake = Config.Lake
	local r = BoatService.BOAT_RADIUS
	local rx, rz = lake.radiusX - BoatService.SHORE_MARGIN, lake.radiusZ - BoatService.SHORE_MARGIN
	local e = (s.x / rx) ^ 2 + (s.z / rz) ^ 2
	if e > 1 then
		local k = 1 / math.sqrt(e)
		s.x *= k
		s.z *= k
		s.speed *= 0.5
	end
	-- Dock: a rectangle from inland of its foot to its end, half width 4.5.
	local foot, tip = lake.dockFoot, lake.dockEnd
	local minX, maxX = math.min(foot.x, tip.x) - 4.5, math.max(foot.x, tip.x) + 4.5
	local minZ, maxZ = math.min(foot.z, tip.z) - 30, math.max(foot.z, tip.z) + 0.5
	local cx, cz = math.clamp(s.x, minX, maxX), math.clamp(s.z, minZ, maxZ)
	local dx, dz = s.x - cx, s.z - cz
	local d = math.sqrt(dx * dx + dz * dz)
	if d < r then
		if d < 1e-3 then
			dx, dz, d = 0, 1, 1
		end
		s.x = cx + dx / d * r
		s.z = cz + dz / d * r
		s.speed *= 0.5
	end
	-- Round obstacles.
	local sx, sz = Landmarks.steepleWaterline(Config)
	local circles = {
		{ x = sx, z = sz, r = 8 + r },
		{ x = lake.buoy.x, z = lake.buoy.z, r = 2.5 + r },
	}
	for _, c in circles do
		local ox, oz = s.x - c.x, s.z - c.z
		local od = math.sqrt(ox * ox + oz * oz)
		if od < c.r then
			if od < 1e-3 then
				ox, oz, od = 0, -1, 1
			end
			s.x = c.x + ox / od * c.r
			s.z = c.z + oz / od * c.r
			s.speed *= 0.5
		end
	end
end

local function countParts(inst: Instance): number
	local n = 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function poseFor(s: Kin, t: number, steer: number): CFrame
	local y = Config.Lake.waterY + 0.15 + 0.12 * math.sin(t * 1.3)
	local pitch = 0.015 * math.sin(t * 1.1 + 1)
	local roll = 0.02 * math.sin(t * 0.9) - steer * math.clamp(s.speed, -30, 30) * 0.003
	local pos = Vector3.new(s.x, y, s.z)
	local look = Vector3.new(math.sin(s.heading), 0, math.cos(s.heading))
	return CFrame.lookAt(pos, pos + look) * CFrame.Angles(pitch, 0, roll)
end

local function claimOwnership()
	local b = built
	if b == nil then
		return
	end
	local ok, err = pcall(function()
		b.hull:SetNetworkOwner(nil)
	end)
	if not ok and not ownerWarned then
		ownerWarned = true
		warn("[DeadCalm] boat: SetNetworkOwner(nil) failed: " .. tostring(err))
	end
end

-- Where the boat ties up: just past the dock end, bow pointing out along the dock.
function BoatService.tieSpot(): (number, number, number)
	local lake = Config.Lake
	local foot, tip = lake.dockFoot, lake.dockEnd
	local dx, dz = tip.x - foot.x, tip.z - foot.z
	local len = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / len, dz / len
	return tip.x + ux * BoatService.TIE_OFFSET, tip.z + uz * BoatService.TIE_OFFSET, math.atan2(ux, uz)
end

function BoatService.init(ctx: any)
	assert(built == nil, "BoatService.init called twice")
	local x, z, h = BoatService.tieSpot()
	kin = { x = x, z = z, heading = h, speed = 0 }
	local b = BoatHull.build(ctx, poseFor(kin, 0, 0))
	built = b

	local drive = Instance.new("Attachment")
	drive.Name = "Drive"
	drive.Parent = b.hull

	local ap = Instance.new("AlignPosition")
	ap.Name = "DrivePosition"
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = drive
	ap.MaxForce = 5e6
	ap.MaxVelocity = 200
	ap.Responsiveness = 40
	ap.Position = b.hull.Position
	ap.Parent = b.hull
	alignPos = ap

	local ao = Instance.new("AlignOrientation")
	ao.Name = "DriveOrientation"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = drive
	ao.MaxTorque = 5e6
	ao.MaxAngularVelocity = 20
	ao.Responsiveness = 40
	ao.CFrame = b.hull.CFrame
	ao.Parent = b.hull
	alignOri = ao

	b.model:SetAttribute("LanternOn", lanternOn)
	b.model:SetAttribute("MotorOn", motorOn)
	b.model.Parent = Workspace
	claimOwnership()

	for _, seat in b.seats do
		seat:SetAttribute("OccupantUserId", 0)
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local hum = seat.Occupant
			local plr = if hum then Players:GetPlayerFromCharacter(hum.Parent) else nil
			seat:SetAttribute("OccupantUserId", if plr then plr.UserId else 0)
			-- Sitting can hand physics to a client; take it back.
			claimOwnership()
		end)
	end
	BoatService.setLantern(true)
end

function BoatService.get(): BoatHull.Built
	local b = built
	if b == nil then
		error("BoatService used before init", 2)
	end
	return b
end

-- Called every Heartbeat by Main.
function BoatService.step(dt: number)
	local b = built
	if b == nil then
		return
	end
	clock += dt
	local throttle, steer = helm.throttle, helm.steer
	if clock - helm.at > BoatService.INPUT_TIMEOUT then
		throttle, steer = 0, 0
	end
	stepKinematics(kin, throttle, steer, motorOn, dt)
	confine(kin)
	local pose = poseFor(kin, clock, steer)
	local ap, ao = alignPos, alignOri
	if ap and ao then
		ap.Position = pose.Position
		ao.CFrame = pose
	end
end

-- The player in the helm seat, if any.
function BoatService.helmPlayer(): Player?
	local b = built
	if b == nil then
		return nil
	end
	local hum = b.seats.HelmSeat.Occupant
	if hum == nil then
		return nil
	end
	return Players:GetPlayerFromCharacter(hum.Parent)
end

-- Helm input after Net validated it. `from` must be the helm player; nil means a trusted
-- server caller (DebugDriver's direct path). Returns false if refused.
function BoatService.setHelmInput(from: Player?, throttle: number, steer: number): boolean
	if from ~= nil and from ~= BoatService.helmPlayer() then
		return false
	end
	helm.throttle = math.clamp(throttle, -1, 1)
	helm.steer = math.clamp(steer, -1, 1)
	helm.at = clock
	return true
end

-- Seat a player's character in the first free seat (helm, bow, port, starboard).
-- Returns the seat name, or nil if the boat is full or the character is not ready.
function BoatService.seatPlayer(player: Player): string?
	local b = built
	local char = player.Character
	if b == nil or char == nil then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum == nil or hum.Health <= 0 then
		return nil
	end
	for _, name in BoatHull.SEAT_ORDER do
		if b.seats[name].Occupant == hum then
			return name
		end
	end
	for _, name in BoatHull.SEAT_ORDER do
		local seat = b.seats[name]
		if seat.Occupant == nil then
			seat:Sit(hum)
			return name
		end
	end
	return nil
end

-- Move the boat at once (DebugDriver tour). Resets speed and input.
function BoatService.teleport(x: number, z: number, heading: number?)
	local b = built
	if b == nil then
		return
	end
	kin.x, kin.z, kin.speed = x, z, 0
	if heading then
		kin.heading = heading
	end
	confine(kin)
	helm.throttle, helm.steer = 0, 0
	local pose = poseFor(kin, clock, 0)
	b.model:PivotTo(pose)
	b.hull.AssemblyLinearVelocity = Vector3.zero
	b.hull.AssemblyAngularVelocity = Vector3.zero
	local ap, ao = alignPos, alignOri
	if ap and ao then
		ap.Position = pose.Position
		ao.CFrame = pose
	end
end

function BoatService.setLantern(on: boolean)
	lanternOn = on
	local b = built
	if b == nil then
		return
	end
	b.lanternLight.Enabled = on
	b.lanternGlow.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	b.lanternGlow.Transparency = if on then 0 else 0.3
	b.model:SetAttribute("LanternOn", on)
end

function BoatService.setMotor(on: boolean)
	motorOn = on
	local b = built
	if b then
		b.model:SetAttribute("MotorOn", on)
	end
end

function BoatService.lanternOn(): boolean
	return lanternOn
end

function BoatService.motorOn(): boolean
	return motorOn
end

-- Kinematic state (the target), not the physical hull.
function BoatService.kinematics(): Kin
	return table.clone(kin)
end

-- The helm input the boat is following right now (zero once it has timed out).
function BoatService.helmInput(): (number, number)
	if clock - helm.at > BoatService.INPUT_TIMEOUT then
		return 0, 0
	end
	return helm.throttle, helm.steer
end

-- The seat a player's character sits in on this boat, or nil.
function BoatService.seatOf(player: Player): Seat?
	local b = built
	local char = player.Character
	if b == nil or char == nil then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat and seat:IsA("Seat") and seat:IsDescendantOf(b.model) then
		return seat
	end
	return nil
end

-- Plain-data snapshot for DebugDriver "state" (no Instances, so it prints cleanly).
function BoatService.snapshot(): { [string]: any }
	local b = built
	if b == nil then
		return { built = false }
	end
	local p = b.hull.Position
	local v = b.hull.AssemblyLinearVelocity
	local seats = {}
	for _, name in BoatHull.SEAT_ORDER do
		local hum = b.seats[name].Occupant
		local plr = if hum then Players:GetPlayerFromCharacter(hum.Parent) else nil
		table.insert(seats, {
			seat = name,
			occupant = if plr then plr.Name elseif hum then hum.Parent and hum.Parent.Name or "?" else nil,
		})
	end
	local owner = nil
	local ok, res = pcall(function()
		return b.hull:GetNetworkOwner()
	end)
	if ok then
		owner = if res then (res :: Player).Name else "server"
	end
	return {
		built = true,
		position = { x = p.X, y = p.Y, z = p.Z },
		target = { x = kin.x, z = kin.z },
		heading = kin.heading,
		speed = Vector3.new(v.X, 0, v.Z).Magnitude,
		targetSpeed = kin.speed,
		helm = { throttle = helm.throttle, steer = helm.steer, age = clock - helm.at },
		seats = seats,
		lanternOn = lanternOn,
		motorOn = motorOn,
		networkOwner = owner,
		parts = countParts(b.model),
	}
end

return BoatService
