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
    "night_start"     opts.night (1..5), opts.seed, opts.quiet, opts.seconds, opts.quota,
                      opts.autoAdvance (default true). Starts or restarts the night.
    "quiet_night"     A bot fishes a whole quiet night (no rules) through the real remotes:
                      rows out, casts, auto-reels, keeps every fish, rows home and banks.
                      opts.seconds (night length, default Config 360), opts.seed (default
                      1), opts.quota, opts.via ("client" default, "net"), opts.timeout,
                      opts.async (return at once; poll with "status"), opts.hold (default
                      true: no auto advance afterwards, so the end card stays up).
                      Returns cleared, banked, quota, catches, banks, lost, seconds, via.
    "fish_once"       Casts, auto-reels and returns the catch shown (and the fish model's
                      visible traits). opts.keep (default true), opts.decide (default true;
                      false leaves the keep or throw back card up), opts.hold (seconds to
                      wait before deciding, default 1), opts.wrong (force the next fish
                      wrong via Night.debugForce), opts.via, opts.timeout (default 60).
    "force_rule"      opts.rule (RuleId), opts.variant, opts.teaching, opts.only, opts.form.
                      Calls Night.debugForce and returns the event kinds it caused.
    "status"          The last async run (quiet_night) with its progress or result.

S3 scenarios (the rules on screen) are in DebugRules.luau: <rule>_pass and <rule>_fail for
Hum, WrongCatch, Neighbor, Knocking and Watcher, "fakeouts", "death_card" and "reset" (the
clean start every rule scenario begins with). Rule scenarios mute the owner's tapes;
"night_start" and "quiet_night" turn them back on.

S5 scenarios (saves, cosmetics, Endless) are in DebugSaves.luau: "save_roundtrip",
"unlock_all_debug", "endless".

S4 scenarios (the front and back of a run) are in DebugRun.luau: "title", "rulebook",
"full_run" and "finale". Nights started here (night_start, quiet_night, the rule scenarios)
are outside the run: when they end nothing advances. "night_start" with opts.run = true
starts a run at that night instead (auto advance then plays the rest of the run).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local BoatService = require(script.Parent:WaitForChild("BoatService"))
local Net = require(script.Parent:WaitForChild("Net"))
local NightService = require(script.Parent:WaitForChild("NightService"))
local FishingService = require(script.Parent:WaitForChild("FishingService"))
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
		night = NightService.snapshot(),
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

----------------------------------------------------------------------------------------
-- S2: the night and the fishing bot

-- How the bot talks to the game. "client": commands go to the helm player's DebugBot, which
-- sends every helm input and intent through the real remotes (Input.sendHelm and
-- Input.sendIntent) and runs the auto-reel there. "net": the same Net handlers a client
-- message reaches, called from here (fallback when no DebugBot answers).
type Bot = {
	player: Player,
	via: string,
	reelOn: boolean,
	reelHeld: boolean,
	reelLastSend: number,
}

local runs: { [string]: any } = {}

local function botRemote(): RemoteEvent?
	return Net.debugRemote("DebugBot")
end

local function waitAck(name: string, timeout: number): boolean
	local t0 = os.clock()
	while botAcks[name] == nil and os.clock() - t0 < timeout do
		task.wait(0.05)
	end
	return botAcks[name] ~= nil
end

local function makeBot(via: string?): Bot?
	local player = BoatService.helmPlayer() or Players:GetPlayers()[1]
	if player == nil then
		return nil
	end
	local bot: Bot = { player = player, via = via or "client", reelOn = false, reelHeld = false, reelLastSend = 0 }
	if bot.via == "client" then
		local remote = botRemote()
		botAcks.hello = nil
		if remote then
			remote:FireClient(player, { cmd = "hello" })
		end
		if not waitAck("hello", 3) then
			bot.via = "net"
		end
	end
	return bot
end

local function myView(id: number): (any, any)
	local v = NightService.view()
	if v == nil then
		return nil, nil
	end
	for _, p in v.players do
		if p.id == id then
			return p, v
		end
	end
	return nil, v
end

local function botIntent(bot: Bot, kind: string, num: number?, flag: boolean?, text: string?)
	if bot.via == "client" then
		local remote = botRemote()
		if remote then
			remote:FireClient(bot.player, { cmd = "intent", kind = kind, num = num, flag = flag, text = text })
		end
	else
		Net.handlers.Intent(bot.player, kind, num, flag, text)
	end
end

-- The "net" auto-reel: the same law as the client DebugBot, sending ReelHold through the
-- Net handler. Runs until bot.reelOn goes false.
local function serverReel(bot: Bot)
	while bot.reelOn do
		task.wait(0.05)
		local pv = myView(bot.player.UserId)
		if pv == nil then
			continue
		end
		local want = bot.reelHeld
		if pv.fishing == "Bite" then
			want = true
		elseif pv.fishing == "Reeling" then
			local w = pv.zoneHi - pv.zoneLo
			local lo, hi = pv.zoneLo + w * 0.3, pv.zoneHi - w * 0.3
			if pv.tension < lo then
				want = true
			elseif pv.tension > hi then
				want = false
			end
			if pv.tension > 0.92 then
				want = false
			end
		else
			want = false
		end
		local nowT = os.clock()
		if want ~= bot.reelHeld and nowT - bot.reelLastSend >= 1 / (Config.Net.intentPerSec - 1) then
			if Net.handlers.Intent(bot.player, "ReelHold", nil, want, nil) then
				bot.reelHeld = want
			end
			bot.reelLastSend = nowT
		end
	end
end

local function setReel(bot: Bot, on: boolean)
	if bot.reelOn == on then
		return
	end
	bot.reelOn = on
	if bot.via == "client" then
		local remote = botRemote()
		if remote then
			remote:FireClient(bot.player, { cmd = "autoreel", on = on })
		end
	elseif on then
		task.spawn(serverReel, bot)
	end
end

local function kinSpeed(): number
	return math.abs(BoatService.kinematics().speed)
end

-- Drive the boat to (x, z) through the bot's path. Returns true on arrival.
local function driveTo(bot: Bot, x: number, z: number, arrive: number, timeout: number): boolean
	local remote = botRemote()
	if bot.via == "client" and remote then
		remote:FireClient(bot.player, { cmd = "autopilot", x = x, z = z, arrive = arrive })
	end
	local t0 = os.clock()
	local nextSend = 0
	local arrived = false
	while os.clock() - t0 < timeout do
		task.wait(0.05)
		local throttle, steer, dist = autopilot(x, z, arrive)
		if dist <= arrive then
			arrived = true
			break
		end
		if bot.via ~= "client" and os.clock() >= nextSend then
			nextSend = os.clock() + 0.1
			Net.handlers.BoatInput(bot.player, throttle, steer)
		end
	end
	if bot.via == "client" and remote then
		remote:FireClient(bot.player, { cmd = "stop" })
	end
	BoatService.setHelmInput(nil, 0, 0)
	-- Let the way come off.
	local t1 = os.clock()
	while kinSpeed() > Config.Fishing.castSpeedLimit * 0.5 and os.clock() - t1 < 8 do
		task.wait(0.1)
	end
	return arrived
end

-- One cast to a decision. Returns { result = "Kept" | "Released" | "Lost" | "Timeout", ... }.
local function fishOne(bot: Bot, keep: boolean, decide: boolean, hold: number, timeout: number): { [string]: any }
	local id = bot.player.UserId
	local t1 = os.clock()
	while kinSpeed() >= Config.Fishing.castSpeedLimit * 0.8 and os.clock() - t1 < 8 do
		task.wait(0.1)
	end
	local cursor = NightService.seq()
	setReel(bot, true)
	botIntent(bot, "Cast", 0.7, nil)
	local t0 = os.clock()
	local out: { [string]: any } = { result = "Timeout" }
	local caught = false
	local decidedAt: number? = nil
	while os.clock() - t0 < timeout do
		task.wait(0.05)
		local events, last = NightService.eventsSince(cursor)
		cursor = last
		for _, e in events do
			if e.player ~= id then
				continue
			end
			local data = e.data or {}
			if e.kind == "HookLost" then
				out.result = "Lost"
				out.why = data.why
			elseif e.kind == "Caught" then
				caught = true
				out.catch = NightService.sanitize(data.catch)
				out.model = FishingService.summaryOf(id)
				out.seconds = math.floor((os.clock() - t0) * 10 + 0.5) / 10
				decidedAt = os.clock() + hold
			elseif e.kind == "Kept" then
				out.result = "Kept"
				out.points = data.points
			elseif e.kind == "Released" then
				out.result = "Released"
				out.why = data.why
			end
		end
		if out.result ~= "Timeout" then
			break
		end
		if caught and not decide then
			out.result = "Deciding"
			break
		end
		local d = decidedAt
		if d ~= nil and os.clock() >= d then
			decidedAt = nil
			botIntent(bot, "CatchDecision", nil, keep)
		end
		if not NightService.running() then
			out.result = "NightOver"
			break
		end
	end
	setReel(bot, false)
	if out.result == "Timeout" then
		botIntent(bot, "CutLine", nil, nil)
	end
	return out
end

local function fishingSpot(): (number, number)
	local tip = Config.Lake.dockEnd
	return tip.x, tip.z + Config.Lake.safeRadius + 55
end

local function atDock(): boolean
	local k = BoatService.kinematics()
	local tip = Config.Lake.dockEnd
	return (k.x - tip.x) ^ 2 + (k.z - tip.z) ^ 2 <= (Config.Lake.bankRadius * 0.8) ^ 2
end

local function goHome(bot: Bot): boolean
	local tx, tz = BoatService.tieSpot()
	if atDock() then
		return true
	end
	return driveTo(bot, tx, tz, 6, 90)
end

-- Rule scenarios mute the owner's tapes on every client (DebugRules reset); a real night
-- started from here plays them again.
local function tapesOn()
	local remote = botRemote()
	if remote then
		for _, p in Players:GetPlayers() do
			remote:FireClient(p, { cmd = "tapes", on = true })
		end
	end
end

scenarios.night_start = function(opts: Opts)
	tapesOn()
	if opts.autoAdvance ~= nil then
		NightService.autoAdvance = opts.autoAdvance == true
	end
	if opts.run == true then
		local LobbyService = require(script.Parent:WaitForChild("LobbyService")) :: any
		LobbyService.startRun({
			night = tonumber(opts.night),
			seed = tonumber(opts.seed),
			seconds = tonumber(opts.seconds),
			quota = tonumber(opts.quota),
			difficulty = opts.difficulty,
		})
		local rp = NightService.params()
		return { started = rp ~= nil, run = NightService.runView(), night = rp and rp.night, quota = rp and rp.quota }
	end
	local p = NightService.start({
		night = tonumber(opts.night),
		seed = tonumber(opts.seed),
		quiet = opts.quiet == true,
		seconds = tonumber(opts.seconds),
		quota = tonumber(opts.quota),
	})
	if p == nil then
		return { started = false, why = "no players" }
	end
	return {
		started = true,
		night = p.night,
		seed = p.seed,
		quota = p.quota,
		rules = p.rules,
		crew = p.playerIds,
		seconds = NightService.config().Night.realSeconds,
	}
end

local function quietNight(opts: Opts, progress: { [string]: any }): { [string]: any }
	local seconds = tonumber(opts.seconds) or Config.Night.realSeconds
	local timeout = tonumber(opts.timeout) or seconds + 60
	if opts.hold ~= false then
		NightService.autoAdvance = false
	end
	tapesOn()
	local p = NightService.start({
		night = 1,
		seed = tonumber(opts.seed) or 1,
		quiet = true,
		seconds = seconds,
		quota = tonumber(opts.quota),
	})
	if p == nil then
		return { error = "no players" }
	end
	task.wait(1)
	local bot = makeBot(if type(opts.via) == "string" then opts.via else nil)
	if bot == nil then
		return { error = "no players" }
	end
	local holdMax = Config.Fishing.holdMax
	local catches, lost = {}, {}
	local banks = 0
	local keptPoints = 0
	local t0 = os.clock()
	local sx, sz = fishingSpot()
	local function bank()
		if goHome(bot) then
			local before = NightService.seq()
			botIntent(bot, "Bank", nil, nil)
			task.wait(0.6)
			local events = NightService.eventsSince(before)
			for _, e in events do
				if e.kind == "Banked" then
					banks += 1
					keptPoints = 0
				end
			end
		end
	end
	while NightService.result() == nil and os.clock() - t0 < timeout do
		local _, v = myView(bot.player.UserId)
		if v == nil then
			task.wait(0.5)
			continue
		end
		progress.banked, progress.quota, progress.hold, progress.timeLeft = v.banked, v.quota, v.hold, v.timeLeft
		progress.catches = #catches
		local need = v.quota - v.banked
		if need <= 0 then
			-- Quota banked: wait out the night at the dock.
			if not atDock() then
				goHome(bot)
			end
			task.wait(1)
		elseif v.hold >= holdMax or keptPoints >= need or (v.hold > 0 and v.timeLeft < 45) then
			bank()
		elseif v.timeLeft < 30 then
			goHome(bot)
			task.wait(1)
		else
			local k = BoatService.kinematics()
			if (k.x - sx) ^ 2 + (k.z - sz) ^ 2 > 20 ^ 2 then
				driveTo(bot, sx, sz, 10, 90)
			end
			local r = fishOne(bot, true, true, 0.8, 45)
			if r.result == "Kept" then
				keptPoints += tonumber(r.points) or 0
				table.insert(catches, {
					species = r.catch and r.catch.species,
					points = r.points,
					seconds = r.seconds,
				})
			else
				table.insert(lost, r.why or r.result)
			end
		end
	end
	-- Let the final tick land.
	local t1 = os.clock()
	while NightService.result() == nil and os.clock() - t1 < 5 do
		task.wait(0.2)
	end
	local res = NightService.result()
	return {
		via = bot.via,
		cleared = if res then res.cleared else false,
		banked = if res then res.banked else nil,
		quota = if res then res.quota else p.quota,
		caught = if res then res.caught else nil,
		catches = catches,
		kept = #catches,
		banks = banks,
		lost = lost,
		seconds = round(os.clock() - t0, 1),
		nightSeconds = seconds,
		finished = res ~= nil,
	}
end

scenarios.quiet_night = function(opts: Opts)
	if opts.async == true then
		local run = { name = "quiet_night", done = false, progress = {}, startedAt = os.clock() }
		runs.last = run
		task.spawn(function()
			local ok, res = pcall(quietNight, opts, run.progress)
			run.done = true
			run.result = if ok then res else { error = tostring(res) }
			print("SCENARIO DONE quiet_night " .. (if ok and res.cleared then "cleared" else "not-cleared"))
		end)
		return { started = true, poll = "status" }
	end
	local res = quietNight(opts, {})
	print("SCENARIO DONE quiet_night " .. (if res.cleared then "cleared" else "not-cleared"))
	return res
end

scenarios.status = function(_opts: Opts)
	local run = runs.last
	if run == nil then
		return { none = true }
	end
	return {
		name = run.name,
		done = run.done,
		elapsed = round(os.clock() - run.startedAt, 1),
		progress = run.progress,
		result = run.result,
	}
end

scenarios.fish_once = function(opts: Opts)
	if not NightService.running() then
		NightService.start({ night = 1, quiet = true })
		task.wait(1)
	end
	local bot = makeBot(if type(opts.via) == "string" then opts.via else nil)
	if bot == nil then
		return { error = "no players" }
	end
	local k = BoatService.kinematics()
	local tip = Config.Lake.dockEnd
	if (k.x - tip.x) ^ 2 + (k.z - tip.z) ^ 2 <= (Config.Lake.safeRadius + 5) ^ 2 then
		local sx, sz = fishingSpot()
		BoatService.teleport(sx, sz, 0)
		task.wait(1.5)
	end
	if opts.wrong == true then
		NightService.debugForce("WrongCatch", {})
	end
	local r =
		fishOne(bot, opts.keep ~= false, opts.decide ~= false, tonumber(opts.hold) or 1, tonumber(opts.timeout) or 60)
	r.via = bot.via
	return r
end

scenarios.force_rule = function(opts: Opts)
	local rule = opts.rule
	if type(rule) ~= "string" then
		error("force_rule: opts.rule must be a RuleId (Hum, WrongCatch, Neighbor, Knocking, Watcher, Finale)", 2)
	end
	if NightService.view() == nil then
		return { error = "no night running" }
	end
	local kinds = NightService.debugForce(rule, {
		variant = opts.variant,
		teaching = opts.teaching == true,
		only = tonumber(opts.only),
		form = opts.form,
	})
	return { rule = rule, events = kinds }
end

-- S3: the rules' scenarios live in DebugRules and register here with these helpers.
function DebugDriver.register(name: string, fn: (opts: Opts) -> ...any)
	scenarios[name] = fn
end

DebugDriver.helpers = {
	makeBot = makeBot,
	botIntent = botIntent,
	botRemote = botRemote,
	waitAck = waitAck,
	fishOne = fishOne,
	driveTo = driveTo,
	goHome = goHome,
	fishingSpot = fishingSpot,
	myView = myView,
	kinSpeed = kinSpeed,
	clearAck = function(name: string)
		botAcks[name] = nil
	end,
	runs = runs,
	round = round,
}

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
	require(script.Parent:WaitForChild("DebugRules")).register(DebugDriver)
	require(script.Parent:WaitForChild("DebugRun")).register(DebugDriver)
	require(script.Parent:WaitForChild("DebugSaves")).register(DebugDriver)
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
