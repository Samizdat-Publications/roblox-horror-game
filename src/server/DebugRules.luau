--!strict
--[[
Studio-only S3 scenarios: the rules on screen. Registered into DebugDriver, so they run
through the same bindable:

    return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("hum_pass")

Each one first resets to a clean state (11/26/2026): every client cleaned (no death card, no
night cards, no rule leftovers, first-person camera, the owner's tape cut and tapes muted),
then a fresh seeded quiet night (no director, no other rules) with everyone alive, the bot
in the helm, the lantern lit and the motor off; then it puts the boat where the rule can be
seen, forces the rule with Night.debugForce, and has the DebugBot on the
player's client play the counter (or the wrong action) through the real remotes: intents
through Input.sendIntent, knocks through Input.knock, callouts through Callouts.choose, the
gaze through the real camera. Each prints one console line when it ends:

    SCENARIO DONE <name> <result>

Results: "pass" or "fail" for the rule's outcome (the expected one for that scenario),
"timeout" if no outcome came, "error:<msg>" on a script error. Every scenario keeps the
camera in the first-person helm view (the bot turns the head where the rule needs it), except
wrongcatch_fail, which switches to the "dock" shot to watch the cooler and back.

Common opts: seed (default per scenario), via ("client" default, "net"), async (return at
once and poll "status"), reset (default true; false skips the reset and uses the night the
"reset" scenario just set up, so a recording started after the reset never shows the clock
jump back). Auto advance is turned off so the end of night card stays up.

    reset            just the clean start. opts.scenario = "<name>" also applies that
                     scenario's seed, spot and rule patch, so that scenario can then run
                     with { reset = false }. Returns the state it reached (helm, alive,
                     lantern, motor, rules, clock).

For captures the bot's head (the camera, which drives the gaze the server reads) tracks the
Neighbor and the Watcher every frame from the moment they appear (DebugBot "track") and stays
on them through a fail. The Neighbor scenarios bring it in close with rulesPatch (it shows
about 80 studs off and drifts slowly). Results carry gaze = { samples, meanDeg, worstDeg }:
how far the server's gaze was off the figure (off the edge offset in watcher_pass).

    hum_pass         lantern and motor on; at the cue the bot cuts both and sits still
    hum_fail         lantern out; when the hum rises the bot starts the motor (Death.Hum.Motor)
    wrongcatch_pass  the next fish is wrong; the bot looks at it, then throws it back
    wrongcatch_fail  the bot keeps it, rows home and banks it; the cooler knocks (the knock
                     delay is shortened to 8..10 s for the scenario with rulesPatch)
    neighbor_pass    opts.form ("Boat" default, "FalseBeacon"); the bot looks at it and puts
                     the lantern out; it gives up and drifts off
    neighbor_fail    the bot waves back from the callout wheel (Death.Neighbor.Waved)
    knocking_pass    three knocks; the bot answers with two
    knocking_fail    the bot answers three (wrong at once), then one to the harder knocks;
                     water comes in and the bot bails for 8 s. opts.sink = true waits for the
                     boat to go down (adds about 45 s)
    watcher_pass     by the west shore; the bot glances at it, then keeps it at the edge of
                     its sight until it is gone (about 40 s)
    watcher_fail     the bot stares at it; it lunges until it reaches the water
    fakeouts         plays every id in Config.Fakeouts in turn, opts.gap seconds apart
                     (default 4). ChorusDip shows no dip here (Night owns that timer)
    death_card       the bot is put over the side; Rule 0 takes them in 6 s and the death
                     card stays up (DeathCard.hold) until the next night
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Core = Shared:WaitForChild("Core")
local Rng = require(Core:WaitForChild("Rng"))
local Fakeouts = require(Core:WaitForChild("Fakeouts"))

local server = script.Parent
local BoatService = require(server:WaitForChild("BoatService"))
local Net = require(server:WaitForChild("Net"))
local NightService = require(server:WaitForChild("NightService"))

local DebugRules = {}

type Opts = { [string]: any }
type Bot = { player: Player, via: string, [string]: any }

local H: any = nil -- DebugDriver.helpers, set by register

----------------------------------------------------------------------------------------
-- Helpers

-- A command for the client DebugBot; in "net" mode `fallback` runs on the server instead.
local function botCmd(bot: Bot, msg: { [string]: any }, fallback: (() -> ())?)
	if bot.via == "client" then
		local remote = H.botRemote()
		if remote then
			remote:FireClient(bot.player, msg)
		end
	elseif fallback then
		fallback()
	end
end

local function view(): any
	return NightService.view()
end

local function setLantern(bot: Bot, on: boolean)
	local v = view()
	if v and v.lanternOn ~= on then
		H.botIntent(bot, "ToggleLantern")
		task.wait(0.4)
	end
end

local function setMotor(bot: Bot, on: boolean)
	local v = view()
	if v and v.motorOn ~= on then
		H.botIntent(bot, "ToggleMotor")
		task.wait(0.4)
	end
end

local function look(bot: Bot, pos: any?, offset: number?)
	if type(pos) == "table" and type(pos.x) == "number" and type(pos.z) == "number" then
		botCmd(bot, { cmd = "look", x = pos.x, z = pos.z, offset = offset or 0 })
	else
		botCmd(bot, { cmd = "look" })
	end
end

local function knock(bot: Bot)
	botCmd(bot, { cmd = "knock" }, function()
		Net.handlers.Intent(bot.player, "Knock", nil, nil, nil)
	end)
end

-- Event watcher: everything Night sends from now on.
type Watch = { cursor: number, seen: { any } }

local function watch(): Watch
	return { cursor = NightService.seq(), seen = {} }
end

local function poll(w: Watch): { any }
	local events, last = NightService.eventsSince(w.cursor)
	w.cursor = last
	for _, e in events do
		table.insert(w.seen, e)
	end
	return events
end

-- Waits for the first event matching `pred`, or nil after `timeout` seconds.
local function waitFor(w: Watch, pred: (any) -> boolean, timeout: number): any?
	for _, e in w.seen do
		if pred(e) then
			return e
		end
	end
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		for _, e in poll(w) do
			if pred(e) then
				return e
			end
		end
		task.wait(0.1)
	end
	return nil
end

local function isOutcome(rule: string): (any) -> boolean
	return function(e: any): boolean
		return e.entity == rule and (e.kind == "EntityPass" or e.kind == "EntityFail")
	end
end

local function isStage(rule: string, stage: string): (any) -> boolean
	return function(e: any): boolean
		return e.entity == rule and e.kind == "EntityStage" and type(e.data) == "table" and e.data.stage == stage
	end
end

local function isKind(rule: string, kind: string): (any) -> boolean
	return function(e: any): boolean
		return e.entity == rule and e.kind == kind
	end
end

local function outcomeName(e: any?): string
	if e == nil then
		return "timeout"
	end
	return if e.kind == "EntityPass" then "pass" else "fail"
end

-- Open water about 120 studs off the west shore, bow toward the lake center (the Watcher).
local WEST = { x = -470, z = -150, h = math.atan2(470, 150) }

-- The Neighbor close enough to read within a scenario (Studio only, through rulesPatch):
-- it shows about 80 studs off and drifts slowly, and with the lantern out it gives up
-- while still well past holdDist.
local NEIGHBOR_NEAR = {
	appearDist = 80,
	driftSpeed = 1.5,
	holdDist = 40,
	lingerMin = 12,
	lingerMax = 14,
	leaveDist = 120,
}

type Defaults = { seed: number, at: { x: number, z: number, h: number }?, rulesPatch: { [string]: any }? }

-- Per scenario: the seed, where the boat waits, and the Studio-only rule patch.
local DEFAULTS: { [string]: Defaults } = {
	hum_pass = { seed = 101 },
	hum_fail = { seed = 102 },
	wrongcatch_pass = { seed = 201 },
	wrongcatch_fail = { seed = 202, rulesPatch = { WrongCatch = { knockDelayMin = 8, knockDelayMax = 10 } } },
	neighbor_pass = { seed = 301, rulesPatch = { Neighbor = NEIGHBOR_NEAR } },
	neighbor_fail = { seed = 302, rulesPatch = { Neighbor = NEIGHBOR_NEAR } },
	knocking_pass = { seed = 401 },
	knocking_fail = { seed = 402 },
	watcher_pass = { seed = 501, at = WEST },
	watcher_fail = { seed = 502, at = WEST },
	fakeouts = { seed = 601 },
	death_card = { seed = 701 },
}

-- The patch for a scenario: its default, then opts.rulesPatch on top (field by field).
local function patchFor(name: string, opts: Opts): { [string]: any }?
	local base = (DEFAULTS[name] or {} :: any).rulesPatch
	local extra = opts.rulesPatch
	if base == nil and extra == nil then
		return nil
	end
	local out: { [string]: any } = {}
	for _, src in { base or {}, if type(extra) == "table" then extra else {} } do
		for rule, fields in src do
			local r = out[rule] or {}
			for k, v in fields do
				r[k] = v
			end
			out[rule] = r
		end
	end
	return out
end

-- Puts the player in the helm seat (out of any other seat first). True when seated there.
local function seatHelm(player: Player): boolean
	local b = BoatService.get()
	local helm = b.seats.HelmSeat
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum == nil then
		return false
	end
	local seat = BoatService.seatOf(player)
	if seat == helm then
		return true
	end
	if helm.Occupant ~= nil and helm.Occupant ~= hum then
		return false -- someone else has the helm (a two-player test); leave them
	end
	if seat then
		hum.Sit = false
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		task.wait(0.25)
	end
	helm:Sit(hum)
	task.wait(0.3)
	return BoatService.seatOf(player) == helm
end

-- A clean start (Studio and Neon fixes, 11/26/2026): every client cleaned first (no death
-- card, no night cards, no rule leftovers, camera in first person, tapes muted so the
-- owner's tape never plays), then a fresh seeded quiet night with everyone alive, the bot
-- in the helm, the lantern lit, the motor off, no active rules, and the boat at the
-- scenario's spot. Returns the bot and a plain report of the state it reached.
local function fullReset(opts: Opts, name: string): (Bot?, { [string]: any })
	local d: Defaults = DEFAULTS[name] or { seed = 1 }
	NightService.autoAdvance = false
	local players = Players:GetPlayers()
	if #players == 0 then
		return nil, { error = "no players" }
	end
	local remote = H.botRemote()
	if remote then
		for _, p in players do
			remote:FireClient(p, { cmd = "clean", tapes = false })
		end
	end
	task.wait(0.4)
	local p = NightService.start({
		night = tonumber(opts.night) or 1,
		seed = tonumber(opts.seed) or d.seed,
		quiet = true,
		seconds = 600,
		rulesPatch = patchFor(name, opts),
	})
	if p == nil then
		return nil, { error = "no players" }
	end
	task.wait(1.2) -- EntityPresenter shows everyone again and reseats anyone out of the boat
	local first = players[1]
	local helmOk = seatHelm(first)
	local bot = H.makeBot(if type(opts.via) == "string" then opts.via else nil)
	if bot == nil then
		return nil, { error = "no players" }
	end
	setLantern(bot, true)
	setMotor(bot, false)
	local at = d.at
	local x, z, h
	if at then
		x, z, h = at.x, at.z, at.h
	else
		x, z = H.fishingSpot()
		h = 0
	end
	BoatService.teleport(x, z, h)
	task.wait(1.5)
	local v = view()
	local alive = 0
	for _, pv in (if v then v.players else {}) :: { any } do
		if pv.alive then
			alive += 1
		end
	end
	local seat = BoatService.seatOf(first)
	return bot,
		{
			scenario = name,
			seed = p.seed,
			helm = helmOk,
			seat = if seat then seat.Name else nil,
			alive = alive,
			crew = #p.playerIds,
			lanternOn = if v then v.lanternOn else nil,
			motorOn = if v then v.motorOn else nil,
			rules = if v then #v.rules else nil,
			clock = if v then H.round(v.clock, 2) else nil,
		}
end

-- Every scenario starts here: a full reset (default), or with opts.reset = false the night
-- the caller just set up with the "reset" scenario (so a recording can start after the
-- reset and never shows the clock jump back).
local function prepare(opts: Opts, name: string): (Bot?, string?)
	if opts.reset == false and NightService.running() then
		local bot = H.makeBot(if type(opts.via) == "string" then opts.via else nil)
		if bot == nil then
			return nil, "no players"
		end
		return bot, nil
	end
	local bot, report = fullReset(opts, name)
	if bot == nil then
		return nil, tostring(report.error)
	end
	return bot, nil
end

-- Keeps the bot's head (the camera, and so the gaze the server reads) on a rule's figure.
local function track(bot: Bot, entity: string, offset: number?)
	botCmd(bot, { cmd = "track", entity = entity, offset = offset or 0 })
end

local function forceRule(rule: string, o: { [string]: any }?): { string }
	return NightService.debugForce(rule, o or {})
end

-- Runs a scenario body, prints SCENARIO DONE, supports opts.async.
local function runner(name: string, body: (Opts) -> { [string]: any })
	return function(opts: Opts)
		local function go(): { [string]: any }
			local ok, res = pcall(body, opts)
			local out: { [string]: any } = if ok and type(res) == "table" then res else { error = tostring(res) }
			local result = if ok then tostring(out.result or "done") else "error:" .. tostring(res)
			out.result = result
			out.scenario = name
			print(string.format("SCENARIO DONE %s %s", name, result))
			return out
		end
		if opts.async == true then
			local run = { name = name, done = false, progress = {}, startedAt = os.clock() }
			H.runs.last = run
			task.spawn(function()
				run.result = go()
				run.done = true
			end)
			return { started = true, poll = "status" }
		end
		return go()
	end
end

----------------------------------------------------------------------------------------
-- Rule 1, the Hum

local function humPass(opts: Opts)
	local bot, err = prepare(opts, "hum_pass")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	setLantern(bot, true)
	setMotor(bot, true)
	local w = watch()
	forceRule("Hum")
	local cue = waitFor(w, isKind("Hum", "EntityCue"), 5)
	task.wait(1)
	-- The counter: motor off, lantern out, hands off the reel, sit still.
	setMotor(bot, false)
	setLantern(bot, false)
	local out = waitFor(w, isOutcome("Hum"), 45)
	return { result = outcomeName(out), cue = cue ~= nil }
end

local function humFail(opts: Opts)
	local bot, err = prepare(opts, "hum_fail")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	setMotor(bot, false)
	setLantern(bot, false)
	local w = watch()
	forceRule("Hum")
	waitFor(w, isStage("Hum", "Window"), 8)
	-- The wrong thing: start the motor while the hum is up.
	H.botIntent(bot, "ToggleMotor")
	local out = waitFor(w, isOutcome("Hum"), 40)
	local died = waitFor(w, function(e)
		return e.kind == "PlayerDied"
	end, 2)
	task.wait(1)
	setMotor(bot, false)
	return { result = outcomeName(out), death = if died then died.data.text else nil }
end

----------------------------------------------------------------------------------------
-- Rule 2, Wrong Catch

local function wrongPass(opts: Opts)
	local bot, err = prepare(opts, "wrongcatch_pass")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	local w = watch()
	forceRule("WrongCatch")
	local r = H.fishOne(bot, false, true, tonumber(opts.hold) or 3, 60)
	task.wait(1)
	local started = waitFor(w, isKind("WrongCatch", "EntityCue"), 0.1)
	local result = if r.result == "Released" and started == nil then "pass" else "unexpected:" .. tostring(r.result)
	return { result = result, catch = r.catch, model = r.model }
end

local function wrongFail(opts: Opts)
	local bot, err = prepare(opts, "wrongcatch_fail")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	local w = watch()
	forceRule("WrongCatch")
	local r = H.fishOne(bot, true, true, tonumber(opts.hold) or 2, 60)
	if r.result ~= "Kept" then
		return { result = "unexpected:" .. tostring(r.result) }
	end
	local tx, tz, th = BoatService.tieSpot()
	BoatService.teleport(tx, tz, th)
	task.wait(1.5)
	local cam = Net.debugRemote("DebugCamera")
	if cam then
		cam:FireClient(bot.player, "dock")
	end
	H.botIntent(bot, "Bank")
	local cue = waitFor(w, isKind("WrongCatch", "EntityCue"), 5)
	local out = waitFor(w, isOutcome("WrongCatch"), 20)
	task.wait(3.5) -- the three knocks and the thump
	if cam then
		cam:FireClient(bot.player, "reset")
	end
	local eaten = nil
	if out and type(out.data) == "table" and type(out.data.effects) == "table" then
		eaten = out.data.effects.eaten
	end
	return { result = outcomeName(out), banked = cue ~= nil, eaten = eaten }
end

----------------------------------------------------------------------------------------
-- Rule 3, the Neighbor

-- How far (degrees) the gaze the server holds for the bot is off the bearing to `pos`.
local function gazeError(bot: Bot, pos: any): number?
	local yaw = Net.gazeOf(bot.player.UserId)
	if yaw == nil or type(pos) ~= "table" then
		return nil
	end
	local k = BoatService.kinematics()
	local want = math.atan2(pos.x - k.x, pos.z - k.z)
	local d = math.atan2(math.sin(want - yaw), math.cos(want - yaw))
	return math.deg(math.abs(d))
end

type GazeStats = { samples: number, worst: number, sum: number, off: number?, pos: any }

local function newGaze(off: number?): GazeStats
	return { samples = 0, worst = 0, sum = 0, off = off, pos = nil }
end

local function sampleGaze(g: GazeStats, bot: Bot, pos: any)
	local err = gazeError(bot, pos)
	if err == nil then
		return
	end
	err = math.abs(err - math.deg(g.off or 0))
	g.samples += 1
	g.sum += err
	g.worst = math.max(g.worst, err)
end

local function gazeReport(g: GazeStats): { [string]: any }
	return {
		samples = g.samples,
		meanDeg = if g.samples > 0 then H.round(g.sum / g.samples, 1) else nil,
		worstDeg = H.round(g.worst, 1),
	}
end

-- Watches until `stop` returns true or `timeout` passes, with the bot's head tracking the
-- figure (DebugBot "track"; the yaw-only "look" is the fallback) and the server's gaze
-- sampled against the figure's reported position.
local function followEntity(
	bot: Bot,
	w: Watch,
	rule: string,
	stop: (any) -> boolean,
	timeout: number,
	g: GazeStats
): any?
	local t0 = os.clock()
	local lastSample = 0
	while os.clock() - t0 < timeout do
		for _, e in poll(w) do
			if stop(e) then
				return e
			end
			if
				e.entity == rule
				and (e.kind == "EntityMoved" or e.kind == "EntityStage" or e.kind == "EntityCue")
				and type(e.data) == "table"
				and type(e.data.pos) == "table"
			then
				g.pos = e.data.pos
			end
		end
		if g.pos ~= nil and os.clock() - lastSample > 0.5 then
			lastSample = os.clock()
			sampleGaze(g, bot, g.pos)
		end
		task.wait(0.1)
	end
	for _, e in w.seen do
		if stop(e) then
			return e
		end
	end
	return nil
end

local function neighborPass(opts: Opts)
	local form = if opts.form == "FalseBeacon" then "FalseBeacon" else "Boat"
	if form == "FalseBeacon" and opts.rulesPatch == nil then
		opts.rulesPatch = { Neighbor = { falseBeaconSeconds = 20, falseBeaconDist = 140 } }
	end
	local bot, err = prepare(opts, "neighbor_pass")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	setLantern(bot, true)
	local w = watch()
	local g = newGaze()
	forceRule("Neighbor", { form = form })
	local cue = waitFor(w, isKind("Neighbor", "EntityCue"), 5)
	if cue and type(cue.data) == "table" then
		look(bot, cue.data.pos)
	end
	-- The head turns to it at once and stays on it.
	track(bot, "Neighbor")
	if form == "Boat" then
		waitFor(w, isStage("Neighbor", "Window"), 10)
		task.wait(3) -- a good look at it first
	else
		task.wait(3)
	end
	-- The counter: lantern out, keep away, never wave.
	setLantern(bot, false)
	local out = followEntity(bot, w, "Neighbor", isOutcome("Neighbor"), 55, g)
	task.wait(2) -- it fades into the fog in frame
	look(bot, nil)
	local fakes = 0
	for _, e in w.seen do
		if e.kind == "Callout" and type(e.data) == "table" and e.data.fake then
			fakes += 1
		end
	end
	return { result = outcomeName(out), form = form, fakeCallouts = fakes, gaze = gazeReport(g) }
end

local function neighborFail(opts: Opts)
	local bot, err = prepare(opts, "neighbor_fail")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	setLantern(bot, true)
	local w = watch()
	local g = newGaze()
	forceRule("Neighbor", { form = "Boat" })
	local cue = waitFor(w, isKind("Neighbor", "EntityCue"), 5)
	if cue and type(cue.data) == "table" then
		look(bot, cue.data.pos)
	end
	track(bot, "Neighbor")
	followEntity(bot, w, "Neighbor", isStage("Neighbor", "Window"), 10, g)
	followEntity(bot, w, "Neighbor", function()
		return false
	end, 4, g) -- a good look at it waving first
	-- The wrong thing: wave back, from the callout wheel.
	botCmd(bot, { cmd = "callout", phrase = "Wave" }, function()
		Net.handlers.Intent(bot.player, "Callout", nil, nil, "Wave")
		Net.handlers.Intent(bot.player, "Wave", nil, nil, nil)
	end)
	local out = followEntity(bot, w, "Neighbor", isOutcome("Neighbor"), 20, g)
	local died = waitFor(w, function(e)
		return e.kind == "PlayerDied"
	end, 2)
	-- The head stays where the boat was through the fail (the next reset lets go).
	return { result = outcomeName(out), death = if died then died.data.text else nil, gaze = gazeReport(g) }
end

----------------------------------------------------------------------------------------
-- Rule 4, the Knocking

local function knockingPass(opts: Opts)
	local bot, err = prepare(opts, "knocking_pass")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	local w = watch()
	forceRule("Knocking")
	waitFor(w, isStage("Knocking", "Window"), 10)
	task.wait(0.8)
	knock(bot)
	task.wait(0.7)
	knock(bot)
	local out = waitFor(w, isOutcome("Knocking"), 15)
	return { result = outcomeName(out) }
end

local function knockingFail(opts: Opts)
	local bot, err = prepare(opts, "knocking_fail")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	local w = watch()
	forceRule("Knocking")
	waitFor(w, isStage("Knocking", "Window"), 10)
	task.wait(0.8)
	for _ = 1, 3 do -- one too many: wrong at once
		knock(bot)
		task.wait(0.6)
	end
	local hard = waitFor(w, function(e)
		return isStage("Knocking", "Cue")(e) and e.data.hard == true
	end, 5)
	-- Round two: the harder knocks, then one answer (still wrong).
	local cursor = #w.seen
	local function secondWindow(e: any): boolean
		return isStage("Knocking", "Window")(e) and e.data.round == 2
	end
	waitFor(w, secondWindow, 10)
	task.wait(0.8)
	knock(bot)
	local out = waitFor(w, isOutcome("Knocking"), 15)
	local flooding = waitFor(w, function(e)
		return e.kind == "Flooding"
	end, 3)
	-- Let the water show, then bail a while.
	task.wait(3)
	botCmd(bot, { cmd = "bail", on = true }, function()
		Net.handlers.Intent(bot.player, "BailHold", nil, true, nil)
	end)
	task.wait(8)
	botCmd(bot, { cmd = "bail", on = false }, function()
		Net.handlers.Intent(bot.player, "BailHold", nil, false, nil)
	end)
	local sunk = nil
	if opts.sink == true then
		sunk = waitFor(w, function(e)
			return e.kind == "Sunk"
		end, 90)
	end
	local v = view()
	return {
		result = outcomeName(out),
		hardRound = hard ~= nil,
		flooding = flooding ~= nil,
		flood = if v then H.round(v.flood, 2) else nil,
		sunk = if opts.sink == true then sunk ~= nil else nil,
		eventsBeforeRound2 = cursor,
	}
end

----------------------------------------------------------------------------------------
-- Rule 5, the Watcher on the Shore

local function watcherPass(opts: Opts)
	local bot, err = prepare(opts, "watcher_pass")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	local w = watch()
	forceRule("Watcher")
	local cue = waitFor(w, isKind("Watcher", "EntityCue"), 5)
	if cue == nil or type(cue.data) ~= "table" then
		return { result = "error:no cue" }
	end
	-- A glance (the tone and the vignette start), then keep it at the edge of sight: the
	-- head stays on it with a fixed yaw offset, so it stays in frame near the edge.
	look(bot, cue.data.pos, 0)
	track(bot, "Watcher", 0)
	task.wait(1.6)
	local edge = tonumber(opts.edge) or 0.8
	look(bot, cue.data.pos, edge)
	track(bot, "Watcher", edge)
	local g = newGaze(edge)
	g.pos = cue.data.pos
	local out = followEntity(bot, w, "Watcher", isOutcome("Watcher"), 55, g)
	task.wait(2)
	look(bot, nil)
	return { result = outcomeName(out), gaze = gazeReport(g) }
end

local function watcherFail(opts: Opts)
	local bot, err = prepare(opts, "watcher_fail")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	local w = watch()
	forceRule("Watcher")
	local cue = waitFor(w, isKind("Watcher", "EntityCue"), 5)
	if cue == nil or type(cue.data) ~= "table" then
		return { result = "error:no cue" }
	end
	-- The wrong thing: stare straight at it, all the way to the waterline.
	look(bot, cue.data.pos, 0)
	track(bot, "Watcher", 0)
	local g = newGaze()
	g.pos = cue.data.pos
	local out = followEntity(bot, w, "Watcher", isOutcome("Watcher"), 45, g)
	local died = waitFor(w, function(e)
		return e.kind == "PlayerDied"
	end, 2)
	-- The head stays on it through the fail (the next reset lets go).
	local steps = 0
	for _, e in w.seen do
		if e.entity == "Watcher" and e.kind == "EntityMoved" then
			steps += 1
		end
	end
	return {
		result = outcomeName(out),
		moves = steps,
		death = if died then died.data.text else nil,
		gaze = gazeReport(g),
	}
end

----------------------------------------------------------------------------------------
-- Fake-outs and the death card

local function fakeouts(opts: Opts)
	local bot, err = prepare(opts, "fakeouts")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	setLantern(bot, true)
	local gap = tonumber(opts.gap) or 4
	local rng = Rng.new(tonumber(opts.seed) or 601)
	local played = {}
	for _, id in Config.Fakeouts do
		local k = BoatService.kinematics()
		local e = Fakeouts.event(NightService.config(), rng, id, nil, { x = k.x, z = k.z })
		NightService.debugEmit({ e :: any })
		table.insert(played, id)
		task.wait(gap)
	end
	return { result = string.format("played-%d", #played), ids = played }
end

local function deathCard(opts: Opts)
	local bot, err = prepare(opts, "death_card")
	if bot == nil then
		return { result = "error:" .. tostring(err) }
	end
	botCmd(bot, { cmd = "cardhold", on = true })
	local player = bot.player
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if char == nil or hum == nil then
		return { result = "error:no character" }
	end
	local seat = BoatService.seatOf(player)
	local w = watch()
	-- Over the side: off the seat and into the water beside the boat.
	hum.Sit = false
	if seat then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
	task.wait(0.2)
	local hull = BoatService.get().hull
	char:PivotTo(hull.CFrame * CFrame.new(9, 1, 0))
	local died = waitFor(w, function(e)
		return e.kind == "PlayerDied" and e.player == player.UserId
	end, 15)
	return {
		result = if died then "died" else "timeout",
		text = if died then died.data.text else nil,
		hold = "the card stays up until the next night (night_start)",
	}
end

----------------------------------------------------------------------------------------

function DebugRules.register(driver: any)
	H = driver.helpers
	driver.register("hum_pass", runner("hum_pass", humPass))
	driver.register("hum_fail", runner("hum_fail", humFail))
	driver.register("wrongcatch_pass", runner("wrongcatch_pass", wrongPass))
	driver.register("wrongcatch_fail", runner("wrongcatch_fail", wrongFail))
	driver.register("neighbor_pass", runner("neighbor_pass", neighborPass))
	driver.register("neighbor_fail", runner("neighbor_fail", neighborFail))
	driver.register("knocking_pass", runner("knocking_pass", knockingPass))
	driver.register("knocking_fail", runner("knocking_fail", knockingFail))
	driver.register("watcher_pass", runner("watcher_pass", watcherPass))
	driver.register("watcher_fail", runner("watcher_fail", watcherFail))
	driver.register("fakeouts", runner("fakeouts", fakeouts))
	driver.register("death_card", runner("death_card", deathCard))
	driver.register(
		"reset",
		runner("reset", function(opts: Opts)
			local name = if type(opts.scenario) == "string" then opts.scenario else "reset"
			local bot, report = fullReset(opts, name)
			report.result = if bot then "clean" else "error:" .. tostring(report.error)
			return report
		end)
	)
end

return DebugRules
