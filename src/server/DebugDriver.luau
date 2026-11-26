--!strict
--[[
Studio-only scenario driver for captures and checks. Inert outside Studio.

Call it from server-side Luau (the Studio command bar on the server during Play, or the
Studio MCP `execute_luau` tool), one line:

    return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("hello")

That goes through the BindableFunction Main.server creates, so it reaches the live
server's copy of this module (and its state). Requiring this module by path from the
command bar gives a separate copy with no live state: use the bindable.

Scenarios (name, opts):
    "hello"           returns "hello from DebugDriver", Config.TITLE
    "state"           plain table: boat, seats, world part count, lantern, warnings, net stats
    "tour"            opts.hold (seconds per stop, default 3). Moves the boat to dock, mid
                      lake, steeple, buoy, reeds, narrows. Returns the stops with drift.
    "row_to_steeple"  opts.motor (default false), opts.timeout (default 150 s),
                      opts.via ("client" default, "net", "direct"), opts.fromDock (default
                      true). Drives the boat with helm input through the player input path.
                      Returns distance travelled, seconds, arrived, via.
    "camera"          opts.shot = "bow" | "dock" | "shore" | "steeple" | "top" | "reset",
                      opts.player (name, default all). Fires the Studio debug remote; the
                      client acks, and the ack shows up in "state" as lastCameraAck.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local BoatService = require(script.Parent:WaitForChild("BoatService"))
local Net = require(script.Parent:WaitForChild("Net"))
local WorldBuilder = require(script.Parent:WaitForChild("WorldBuilder"))
local Landmarks = require(script.Parent:WaitForChild("world"):WaitForChild("Landmarks"))

export type Opts = { [string]: any }

local DebugDriver = {}

DebugDriver.BINDABLE_NAME = "DeadCalmDebug"
DebugDriver.SHOTS = { "bow", "dock", "shore", "steeple", "top", "reset" }

-- Main appends startup warnings here (lighting, seating).
DebugDriver.warnings = {} :: { string }

local lastCameraAck: { [string]: any }? = nil
local botAcks: { [string]: any } = {}

local scenarios: { [string]: (opts: Opts) -> ...any } = {}

local function round(n: number, places: number?): number
	local m = 10 ^ (places or 1)
	return math.floor(n * m + 0.5) / m
end

local function boatXZ(): (number, number)
	local p = BoatService.get().hull.Position
	return p.X, p.Z
end

local function headingTo(fromX: number, fromZ: number, toX: number, toZ: number): number
	return math.atan2(toX - fromX, toZ - fromZ)
end

-- Throttle and steer that point the boat at (tx, tz). Same law as the client DebugBot.
local function autopilot(tx: number, tz: number, arriveDist: number): (number, number, number)
	local hull = BoatService.get().hull
	local p = hull.Position
	local look = hull.CFrame.LookVector
	local heading = math.atan2(look.X, look.Z)
	local want = headingTo(p.X, p.Z, tx, tz)
	local err = math.atan2(math.sin(want - heading), math.cos(want - heading))
	-- steer +1 turns right, which lowers the heading, so steer against the error.
	local steer = math.clamp(-err * 2, -1, 1)
	local dist = math.sqrt((tx - p.X) ^ 2 + (tz - p.Z) ^ 2)
	local throttle = if math.abs(err) > 1.2 then 0.3 else 1
	if dist < arriveDist * 2 then
		throttle *= 0.6
	end
	return throttle, steer, dist
end

scenarios.hello = function(_opts: Opts)
	return "hello from DebugDriver", Config.TITLE
end

scenarios.state = function(_opts: Opts)
	local w = WorldBuilder.last
	local warnings = {}
	if w then
		for _, s in w.warnings do
			table.insert(warnings, s)
		end
	end
	for _, s in DebugDriver.warnings do
		table.insert(warnings, s)
	end
	local players = {}
	for _, p in Players:GetPlayers() do
		table.insert(players, { name = p.Name, userId = p.UserId, gaze = Net.gazeOf(p.UserId) })
	end
	return {
		boat = BoatService.snapshot(),
		worldParts = if w then w.partCount else nil,
		worldPerModule = if w then w.perModule else nil,
		lanternOn = BoatService.lanternOn(),
		motorOn = BoatService.motorOn(),
		warnings = warnings,
		players = players,
		net = Net.stats,
		lastCameraAck = lastCameraAck,
	}
end

scenarios.tour = function(opts: Opts)
	local hold = tonumber(opts.hold) or 3
	local lake = Config.Lake
	local tieX, tieZ, tieH = BoatService.tieSpot()
	local sx, sz = Landmarks.steepleWaterline(Config)
	-- Each stop sits in open water near the point of interest, bow toward it.
	local function near(px: number, pz: number, back: number): (number, number)
		local d = math.sqrt(px * px + pz * pz)
		if d < 1e-3 then
			return px, pz
		end
		return px - px / d * back, pz - pz / d * back
	end
	local stops = {}
	local function add(name: string, x: number, z: number, h: number)
		table.insert(stops, { name = name, x = x, z = z, heading = h })
	end
	add("dock", tieX, tieZ, tieH)
	add("mid", 0, 0, 0)
	local stx, stz = near(sx, sz, 45)
	add("steeple", stx, stz, headingTo(stx, stz, sx, sz))
	local bx, bz = near(lake.buoy.x, lake.buoy.z, 25)
	add("buoy", bx, bz, headingTo(bx, bz, lake.buoy.x, lake.buoy.z))
	local rx, rz = near(lake.reeds.x, lake.reeds.z, 70)
	add("reeds", rx, rz, headingTo(rx, rz, lake.reeds.x, lake.reeds.z))
	add(
		"narrows",
		lake.narrows.x,
		lake.narrows.z,
		headingTo(lake.narrows.x, lake.narrows.z, -lake.radiusX, lake.radiusZ)
	)

	local out = {}
	for _, s in stops do
		BoatService.teleport(s.x, s.z, s.heading)
		task.wait(hold)
		local ax, az = boatXZ()
		table.insert(out, {
			name = s.name,
			target = { x = round(s.x), z = round(s.z) },
			actual = { x = round(ax), z = round(az) },
			drift = round(math.sqrt((ax - s.x) ^ 2 + (az - s.z) ^ 2), 2),
		})
	end
	return out
end

scenarios.row_to_steeple = function(opts: Opts)
	local motor = opts.motor == true
	local timeout = tonumber(opts.timeout) or 150
	local via = if type(opts.via) == "string" then opts.via else "client"
	local arrive = 12

	if opts.fromDock ~= false then
		local tx, tz, th = BoatService.tieSpot()
		BoatService.teleport(tx, tz, th)
		task.wait(1)
	end
	BoatService.setMotor(motor)

	-- Aim for open water short of the steeple, on the side facing the lake center.
	local sx, sz = Landmarks.steepleWaterline(Config)
	local d = math.sqrt(sx * sx + sz * sz)
	local tx, tz = sx - sx / d * 40, sz - sz / d * 40

	local helmPlayer = BoatService.helmPlayer()
	if via ~= "direct" and helmPlayer == nil then
		via = "direct"
	end
	if via == "client" then
		local remote = Net.debugRemote("DebugBot")
		botAcks.autopilot = nil
		if remote and helmPlayer then
			remote:FireClient(helmPlayer, { cmd = "autopilot", x = tx, z = tz, arrive = arrive })
			local t0 = os.clock()
			while botAcks.autopilot == nil and os.clock() - t0 < 3 do
				task.wait(0.1)
			end
		end
		if botAcks.autopilot == nil then
			via = "net" -- no DebugBot answered; drive the same Net handler from here
		end
	end

	local startX, startZ = boatXZ()
	local lastX, lastZ = startX, startZ
	local travelled = 0
	local t0 = os.clock()
	local arrived = false
	local sent, refused = 0, 0
	local nextSend = 0
	while os.clock() - t0 < timeout do
		task.wait()
		local x, z = boatXZ()
		travelled += math.sqrt((x - lastX) ^ 2 + (z - lastZ) ^ 2)
		lastX, lastZ = x, z
		local throttle, steer, dist = autopilot(tx, tz, arrive)
		if dist <= arrive then
			arrived = true
			break
		end
		if via ~= "client" and os.clock() >= nextSend then
			nextSend = os.clock() + 0.1 -- 10 Hz, under Config.Net.boatHz
			local ok
			if via == "net" and helmPlayer then
				ok = Net.handlers.BoatInput(helmPlayer, throttle, steer)
			else
				ok = BoatService.setHelmInput(nil, throttle, steer)
			end
			sent += 1
			if not ok then
				refused += 1
			end
		end
	end
	local seconds = os.clock() - t0

	if via == "client" and helmPlayer then
		local remote = Net.debugRemote("DebugBot")
		if remote then
			remote:FireClient(helmPlayer, { cmd = "stop" })
		end
	end
	BoatService.setHelmInput(nil, 0, 0)
	local fx, fz = boatXZ()
	return {
		via = via,
		motor = motor,
		arrived = arrived,
		seconds = round(seconds, 2),
		distance = round(travelled, 1),
		straightLine = round(math.sqrt((tx - startX) ^ 2 + (tz - startZ) ^ 2), 1),
		start = { x = round(startX), z = round(startZ) },
		finish = { x = round(fx), z = round(fz) },
		target = { x = round(tx), z = round(tz) },
		serverSends = sent,
		refused = refused,
		helmAccepted = Net.stats.accepted.BoatInput or 0,
	}
end

scenarios.camera = function(opts: Opts)
	local shot = opts.shot
	if type(shot) ~= "string" or not table.find(DebugDriver.SHOTS, shot) then
		error(string.format("camera: opts.shot must be one of %s", table.concat(DebugDriver.SHOTS, ", ")), 2)
	end
	local remote = Net.debugRemote("DebugCamera")
	assert(remote, "camera: debug remotes missing (not in Studio?)")
	local targets = {}
	for _, p in Players:GetPlayers() do
		if opts.player == nil or p.Name == opts.player then
			table.insert(targets, p)
		end
	end
	lastCameraAck = nil
	for _, p in targets do
		remote:FireClient(p, shot)
	end
	-- Wait briefly for the first ack so the caller sees the shot was applied.
	local t0 = os.clock()
	while lastCameraAck == nil and os.clock() - t0 < 2 and #targets > 0 do
		task.wait(0.05)
	end
	return { shot = shot, sentTo = #targets, ack = lastCameraAck }
end

function DebugDriver.active(): boolean
	return RunService:IsStudio()
end

-- Main calls this once in Studio, after Net.init.
function DebugDriver.init()
	local cam = Net.debugRemote("DebugCamera")
	if cam then
		cam.OnServerEvent:Connect(function(player: Player, shot: any, info: any)
			if not Net.allowDebug(player, "DebugCamera") then
				return
			end
			lastCameraAck = {
				player = player.Name,
				shot = if type(shot) == "string" then shot else "?",
				info = if type(info) == "table" then info else nil,
			}
		end)
	end
	local bot = Net.debugRemote("DebugBot")
	if bot then
		bot.OnServerEvent:Connect(function(player: Player, msg: any)
			if not Net.allowDebug(player, "DebugBot") or type(msg) ~= "table" or type(msg.ack) ~= "string" then
				return
			end
			botAcks[msg.ack] = { player = player.Name, seat = msg.seat }
		end)
	end
end

function DebugDriver.list(): { string }
	local names = {}
	for name in scenarios do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function DebugDriver.run(name: string, opts: Opts?): ...any
	if not DebugDriver.active() then
		error("DebugDriver runs only in Studio", 2)
	end
	local scenario = scenarios[name]
	if scenario == nil then
		error(
			string.format("unknown DebugDriver scenario %q (have: %s)", name, table.concat(DebugDriver.list(), ", ")),
			2
		)
	end
	return scenario(opts or {})
end

return DebugDriver
