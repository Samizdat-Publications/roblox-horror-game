--!strict
-- Owns the run and the night: holds the Core.Run state (LobbyService starts it), builds
-- NightParams with Core.Run.nightParams, creates Core.Night, ticks it at Config.Night.tick, gathers observations
-- from the world (the boat from BoatService, every player's seat, gaze and whether they are
-- in the water), drains validated intents from Net, dispatches the events (world first,
-- then clients) and replicates the NightView at most 10 times per second.
--
-- Clients never receive a catch's `wrong` flag or tier: every outgoing event is copied
-- through `sanitize`, which drops those keys at any depth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Core = Shared:WaitForChild("Core")
local Types = require(Core:WaitForChild("Types"))
local Night = require(Core:WaitForChild("Night")) :: any
local LakeMap = require(Core:WaitForChild("LakeMap"))
local Run = require(Core:WaitForChild("Run")) :: any

local server = script.Parent
local BoatService = require(server:WaitForChild("BoatService"))
local Net = require(server:WaitForChild("Net"))
local FishingService = require(server:WaitForChild("FishingService"))
local Dock = require(server:WaitForChild("world"):WaitForChild("Dock"))

type Event = Types.Event
type NightView = Types.NightView
type NightParams = Types.NightParams
type PlayerObs = Types.PlayerObs

export type StartOpts = {
	night: number?, -- 1..5 (default: the current night, else 1)
	seed: number?,
	quiet: boolean?, -- no rules and no fake-outs: just fishing (DebugDriver quiet_night)
	seconds: number?, -- override Config.Night.realSeconds for this night
	quota: number?, -- override the scaled quota
	keepBoat: boolean?, -- do not move the boat back to the dock
	-- Studio scenarios only: patch fields of Config.Rules.<RuleId> in a copy of Config for
	-- this night (for example a shorter Wrong Catch knock delay). Config itself is untouched.
	rulesPatch: { [string]: { [string]: any } }?,
	run: boolean?, -- this night is the run's next night (LobbyService); night comes from the run
	difficulty: string?, -- a night outside the run: "Normal" (default) or "Nightmare"
	quotaScale: number?, -- multiply the quota (a fast clock in a Studio full run)
}

local NightService = {}

NightService.SEND_GAP = 0.1 -- at most 10 views per second
NightService.BETWEEN = 15 -- seconds from a night's end to the next night
NightService.MAX_STEPS = 5 -- per frame, so a hitch never spirals
NightService.LOG_SIZE = 400
NightService.autoAdvance = true

local state: any = nil
local params: NightParams? = nil
local cfg: any = Config
local acc = 0
local lastView: NightView? = nil
local lastSig = ""
local lastSentAt = -math.huge
local now = 0
local nightNumber = 1
local endedAt: number? = nil
local listeners: { (Event) -> () } = {}
local startListeners: { (NightParams) -> () } = {}
local intentListeners: { ({ any }) -> () } = {}
local log: { { seq: number, t: number, e: Event } } = {}
local seq = 0
local startOpts: StartOpts = {}

----------------------------------------------------------------------------------------
-- The run and NightParams (Core.Run)

-- The run in progress (LobbyService starts it), or nil on the title screen. Nights started
-- with StartOpts.run = true are the run's nights: their results go to Run.finishNight.
local run: any = nil
local runNight = false -- the current night belongs to the run
local runExtra: { seconds: number?, quotaScale: number? } = {}
local lastOutcome: string? = nil
local endListeners: { (any, string?, any) -> () } = {}

-- Params from Core.Run. A run night uses the run (crew set to who is here now); any other
-- night (Studio scenarios) uses a throwaway Normal first run at that night, with the seed
-- given as the night seed so a scenario replays exactly.
local function buildParams(night: number, seed: number, ids: { number }, o: StartOpts, c: any): NightParams
	local p: NightParams
	if o.run and run ~= nil then
		Run.setPlayers(run, ids)
		p = Run.nightParams(run)
		if o.seed then
			p.seed = seed
		end
	else
		local r = Run.new(c, {
			seed = seed,
			difficulty = if o.difficulty == "Nightmare" then "Nightmare" else "Normal",
			mode = "Story",
			playerIds = ids,
			firstRun = true,
		})
		r.night = math.clamp(night, 1, #c.Nights)
		p = Run.nightParams(r)
		p.seed = seed
	end
	if o.quiet then
		p.rules = {}
		p.newRules = {}
		p.amendments = {}
		p.real = 0
		p.fake = 0
	end
	local scale = o.quotaScale
	if scale and scale > 0 then
		p.quota = math.max(1, math.ceil(p.quota * scale))
	end
	if o.quota then
		p.quota = math.max(1, math.floor(o.quota))
	end
	return p
end

----------------------------------------------------------------------------------------
-- Events out

-- Deep copy of plain data without the keys a client must never see.
local HIDDEN = { wrong = true, tier = true }
local function sanitize(v: any, depth: number): any
	if type(v) ~= "table" then
		local t = typeof(v)
		if t == "number" or t == "string" or t == "boolean" then
			return v
		end
		return nil
	end
	if depth > 8 then
		return nil
	end
	local out = {}
	for k, x in v do
		if not (type(k) == "string" and HIDDEN[k]) then
			out[k] = sanitize(x, depth + 1)
		end
	end
	return out
end
NightService.sanitize = function(v: any): any
	return sanitize(v, 0)
end

local function record(e: Event)
	seq += 1
	table.insert(log, { seq = seq, t = now, e = e })
	if #log > NightService.LOG_SIZE then
		table.remove(log, 1)
	end
end

local function dispatch(events: { Event })
	if #events == 0 then
		return
	end
	FishingService.handle(events)
	for _, e in events do
		record(e)
		for _, fn in listeners do
			task.spawn(fn, e)
		end
	end
	-- Per player lists: an event with `only` goes to that player alone.
	local players = Players:GetPlayers()
	local out: { [Player]: { any } } = {}
	for _, e in events do
		local copy = sanitize(e, 0)
		if e.kind == "Caught" and e.player ~= nil and type(copy.data) == "table" then
			copy.data.serial = FishingService.serialOf(e.player)
		end
		for _, p in players do
			if e.only == nil or e.only == p.UserId then
				local list = out[p]
				if list == nil then
					list = {}
					out[p] = list
				end
				table.insert(list, copy)
			end
		end
	end
	for p, list in out do
		Net.fire("Events", p, list)
	end
end

----------------------------------------------------------------------------------------
-- View out

local function r(x: number, step: number): number
	return math.floor(x / step + 0.5)
end

-- A coarse fingerprint: the view is resent only when something a player could see changed.
local function signature(v: NightView): string
	local bits = {
		v.phase,
		v.night,
		r(v.timeLeft, 0.5),
		v.banked,
		v.quota,
		v.hold,
		r(v.oil, 0.005),
		v.refills,
		v.lanternOn,
		v.motorOn,
		v.chorus,
		r(v.flood, 0.01),
		v.safe,
		#v.rules,
		(v :: any).specialAboard,
	}
	for _, p in v.players do
		table.insert(bits, p.id)
		table.insert(bits, p.alive)
		table.insert(bits, p.fishing)
		table.insert(bits, r(p.tension, 0.01))
		table.insert(bits, r(p.zoneLo, 0.01))
		table.insert(bits, r(p.progress, 0.01))
		table.insert(bits, p.bailing)
	end
	local s = table.create(#bits)
	for i, b in bits do
		s[i] = tostring(b)
	end
	return table.concat(s, ",")
end

-- Polish 3: the finale night's objective for the HUD ("The owner's fish: aboard"). Only the
-- species is checked (any fish the players can see is a Steeple Cat), never whether it is
-- true to the book: that would leak a catch's `wrong` flag. Nil on other nights.
local function decorate(v: NightView, s: any): NightView
	local out: any = v
	if s ~= nil and s.finaleNight == true then
		local want = cfg.Rules.Finale.needSpecies
		local aboard = false
		for _, list in { s.hold or {}, s.cooler or {} } do
			for _, c in list do
				if type(c) == "table" and c.species == want then
					aboard = true
				end
			end
		end
		out.specialAboard = aboard
		out.specialSpecies = want
	end
	return out
end

local function replicate(v: NightView, force: boolean)
	lastView = v
	if not force and now - lastSentAt < NightService.SEND_GAP then
		return
	end
	local sig = signature(v)
	if not force and sig == lastSig then
		return
	end
	lastSig = sig
	lastSentAt = now
	Net.fireAll("View", v)
end

----------------------------------------------------------------------------------------
-- Observations

-- Studio full runs: a server crew bot can set gaze directly (DebugCrew).
local debugGaze: { [number]: number } = {}

local function inBoat(pos: Vector3): boolean
	local hull = BoatService.get().hull
	local lp = hull.CFrame:PointToObjectSpace(pos)
	return math.abs(lp.X) < 3.2 and lp.Z > -9.5 and lp.Z < 7 and lp.Y > -1.5 and lp.Y < 7
end

local function observePlayer(id: number): PlayerObs?
	local player = Players:GetPlayerByUserId(id)
	if player == nil then
		return nil
	end
	local seat = BoatService.seatOf(player)
	local inWater = false
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if seat == nil and root and root:IsA("BasePart") then
		local pos = root.Position
		local p2 = { x = pos.X, z = pos.Z }
		inWater = pos.Y < Config.Lake.waterY + Dock.DECK_HEIGHT
			and not inBoat(pos)
			and LakeMap.inside(Config, p2)
			and not LakeMap.isSafe(Config, p2)
	end
	return {
		id = id,
		seated = seat ~= nil,
		helm = seat ~= nil and seat.Name == "HelmSeat",
		inWater = inWater,
		gazeYaw = debugGaze[id] or Net.gazeOf(id) or 0,
		bookOpen = Net.bookOpenOf(id),
		touch = Net.touchOf(id),
	}
end

local function observe(dt: number, intents: { any }): any
	local k = BoatService.kinematics()
	local throttle, steer = BoatService.helmInput()
	local players = {}
	local p = params
	if p then
		for _, id in p.playerIds do
			local o = observePlayer(id)
			if o then
				table.insert(players, o)
			else
				-- Left the game: Core must not fill a seated default, or a rule could count
				-- or take a player who is not there.
				table.insert(players, {
					id = id,
					seated = false,
					helm = false,
					inWater = false,
					gazeYaw = 0,
					bookOpen = false,
					present = false,
				})
			end
		end
	end
	return {
		dt = dt,
		boat = {
			pos = { x = k.x, z = k.z },
			vel = { x = math.sin(k.heading) * k.speed, z = math.cos(k.heading) * k.speed },
			heading = k.heading,
			throttle = throttle,
			steer = steer,
		},
		players = players,
		intents = intents,
	}
end

----------------------------------------------------------------------------------------
-- The loop

local function syncWorld(v: NightView)
	if BoatService.lanternOn() ~= v.lanternOn then
		BoatService.setLantern(v.lanternOn)
	end
	if BoatService.motorOn() ~= v.motorOn then
		BoatService.setMotor(v.motorOn)
	end
	FishingService.syncHold(v.hold)
end

local function stepOnce(dt: number)
	local s = state
	if s == nil then
		return
	end
	local intents = Net.drainIntents()
	local crew = NightService.debugCrew
	if crew then
		-- Studio only: a server crew bot adds its intents (DebugCrew, full_run and finale).
		local ok, more = pcall(crew, dt, s)
		if ok and type(more) == "table" then
			for _, it in more do
				table.insert(intents, it)
			end
		elseif not ok then
			warn("[DeadCalm] debug crew: " .. tostring(more))
			NightService.debugCrew = nil
		end
	end
	if #intents > 0 then
		for _, fn in intentListeners do
			task.spawn(fn, intents)
		end
	end
	local events = Night.step(s, observe(dt, intents)) :: { Event }
	local v = decorate(Night.view(s) :: NightView, s)
	syncWorld(v)
	dispatch(events)
	FishingService.step(dt, v)
	local res = Night.result(s)
	local ended = res ~= nil
	replicate(v, ended)
	if ended and endedAt == nil then
		endedAt = now
		local outcome: string? = nil
		if runNight and run ~= nil and not run.over then
			outcome = Run.finishNight(run, res)
		end
		lastOutcome = outcome
		local rv = if run then Run.view(run) else nil
		for _, fn in endListeners do
			task.spawn(fn, res, outcome, rv)
		end
	end
end

-- Called every Heartbeat by Main.
function NightService.tick(dt: number)
	now += dt
	if state == nil then
		Net.drainIntents() -- nothing to apply them to yet
		return
	end
	if #Players:GetPlayers() == 0 then
		return -- an empty server holds the night still
	end
	local tick = cfg.Night.tick
	acc += dt
	local steps = 0
	while acc >= tick and steps < NightService.MAX_STEPS do
		acc -= tick
		steps += 1
		stepOnce(tick)
	end
	if steps >= NightService.MAX_STEPS then
		acc = 0
	end
	-- Between nights LobbyService decides what comes next (Run.finishNight's outcome).
end

-- Seconds since the current night ended, or nil while it runs (or with no night).
function NightService.endedFor(): number?
	local e = endedAt
	if e == nil then
		return nil
	end
	return now - e
end

----------------------------------------------------------------------------------------
-- The run

-- Starts a run (LobbyService, the host pressed Play). o.night (Studio) jumps to a night;
-- o.seconds and o.quotaScale (Studio full runs) apply to every night of the run.
function NightService.newRun(
	o: {
		mode: string?, -- "Story" (default) or "Endless" (Core.Run starts it at night 6)
		difficulty: string?,
		seed: number?,
		firstRun: boolean?,
		night: number?,
		seconds: number?,
		quotaScale: number?,
	}
): any
	local ids = {}
	for _, p in Players:GetPlayers() do
		table.insert(ids, p.UserId)
	end
	if #ids == 0 then
		return nil
	end
	run = Run.new(Config, {
		seed = o.seed or Random.new():NextInteger(1, 2 ^ 30),
		difficulty = if o.difficulty == "Nightmare" then "Nightmare" else "Normal",
		mode = if o.mode == "Endless" then "Endless" else "Story",
		playerIds = ids,
		firstRun = o.firstRun ~= false,
	})
	if o.night then
		if run.mode == "Endless" then
			run.night = math.max(Run.ENDLESS_FROM, math.floor(o.night))
		else
			run.night = math.clamp(math.floor(o.night), 1, #Config.Nights)
		end
	end
	runExtra = { seconds = o.seconds, quotaScale = o.quotaScale }
	lastOutcome = nil
	return run
end

-- Starts the run's next night (the night number comes from the run: a retry repeats it).
function NightService.startRunNight(extra: StartOpts?): NightParams?
	if run == nil or run.over then
		return nil
	end
	local o: StartOpts = table.clone(extra or {})
	o.run = true
	o.seconds = o.seconds or runExtra.seconds
	o.quotaScale = o.quotaScale or runExtra.quotaScale
	return NightService.start(o)
end

-- Ends the run and the night (back to the title screen).
function NightService.endRun()
	run = nil
	runNight = false
	lastOutcome = nil
	state = nil
	params = nil
	endedAt = nil
end

function NightService.run(): any
	return run
end

function NightService.runView(): any
	return if run then Run.view(run) else nil
end

function NightService.lastOutcome(): string?
	return lastOutcome
end

function NightService.isRunNight(): boolean
	return runNight
end

-- Called with (result, outcome?, runView?) when a night ends. outcome is Run.finishNight's
-- answer for a run night, nil for a night outside the run.
function NightService.onNightEnd(fn: (any, string?, any) -> ())
	table.insert(endListeners, fn)
end

-- Starts (or restarts) a night with every player in the server as the crew.
function NightService.start(o: StartOpts?): NightParams?
	local opts: StartOpts = o or {}
	local ids = {}
	for _, p in Players:GetPlayers() do
		table.insert(ids, p.UserId)
	end
	if #ids == 0 then
		return nil
	end
	local useRun = opts.run == true and run ~= nil
	local night = if useRun then run.night else math.clamp(math.floor(opts.night or nightNumber), 1, #Config.Nights)
	local seed = opts.seed or Random.new():NextInteger(1, 2 ^ 30)
	local c: any = Config
	if opts.seconds or opts.rulesPatch then
		c = table.clone(Config)
	end
	if opts.seconds then
		c.Night = table.clone(Config.Night)
		c.Night.realSeconds = math.max(10, opts.seconds)
	end
	if opts.rulesPatch then
		c.Rules = table.clone(Config.Rules)
		for id, patch in opts.rulesPatch do
			local base = (Config.Rules :: any)[id]
			if type(base) == "table" and type(patch) == "table" then
				local rule = table.clone(base)
				for k, v in patch do
					rule[k] = v
				end
				c.Rules[id] = rule
			end
		end
	end
	cfg = c
	local p = buildParams(night, seed, ids, opts, c)
	params = p
	nightNumber = night
	runNight = useRun
	lastOutcome = nil
	debugGaze = {}
	startOpts = opts
	state = Night.new(c, p)
	acc = 0
	endedAt = nil
	lastSig = ""
	FishingService.reset()
	if not opts.keepBoat then
		local x, z, h = BoatService.tieSpot()
		BoatService.teleport(x, z, h)
	end
	Net.drainIntents()
	local v = decorate(Night.view(state) :: NightView, state)
	syncWorld(v)
	replicate(v, true)
	for _, fn in startListeners do
		task.spawn(fn, p)
	end
	return p
end

-- Studio only: the raw NightState (DebugCrew reads it; the finale scenario sets the clock
-- and puts the owner's fish in the hold). Never used outside Studio scenarios.
function NightService.debugState(): any
	return state
end

-- Studio only: a server crew bot's gaze for a player (nil clears it).
function NightService.debugSetGaze(id: number, yaw: number?)
	debugGaze[id] = yaw
end

-- Studio only: a function called every tick with (dt, state) that returns extra intents.
NightService.debugCrew = nil :: ((number, any) -> { any }?)?

-- A late joiner gets the current view at once (they join the crew at the next night).
function NightService.onPlayerAdded(player: Player)
	local v = lastView
	if v then
		Net.fire("View", player, v)
	end
end

-- Studio scenarios: start a rule now. Returns the kinds of the events it caused.
function NightService.debugForce(rule: string, opts: any?): { string }
	local s = state
	if s == nil then
		return {}
	end
	local events = (Night.debugForce(s, rule, opts or {}) or {}) :: { Event }
	dispatch(events)
	local kinds = {}
	for _, e in events do
		table.insert(kinds, e.kind)
	end
	return kinds
end

-- Server listeners (DebugDriver). Called with every raw event, before sanitizing.
function NightService.subscribe(fn: (Event) -> ())
	table.insert(listeners, fn)
end

-- Raw events after sequence number `since` (DebugDriver). Returns them and the last seq.
function NightService.eventsSince(since: number): ({ Event }, number)
	local out = {}
	for _, item in log do
		if item.seq > since then
			table.insert(out, item.e)
		end
	end
	return out, seq
end

-- Called with the NightParams each time a night starts (EntityPresenter resets the world).
function NightService.onStart(fn: (NightParams) -> ())
	table.insert(startListeners, fn)
end

-- Called with each tick's validated intents before Night.step sees them (EntityPresenter
-- plays the knocks on the hull for everyone).
function NightService.onIntents(fn: ({ any }) -> ())
	table.insert(intentListeners, fn)
end

-- Studio scenarios only: send events that Core did not make (DebugDriver "fakeouts" plays
-- each fake-out in turn). They go through the same dispatch as Night's own events.
function NightService.debugEmit(events: { Event })
	dispatch(events)
end

function NightService.seq(): number
	return seq
end

function NightService.view(): NightView?
	local s = state
	if s == nil then
		return nil
	end
	return Night.view(s) :: NightView
end

function NightService.result(): any
	local s = state
	if s == nil then
		return nil
	end
	return Night.result(s)
end

function NightService.params(): NightParams?
	return params
end

function NightService.config(): any
	return cfg
end

function NightService.running(): boolean
	return state ~= nil and Night.result(state) == nil
end

-- Plain snapshot for DebugDriver "state".
function NightService.snapshot(): { [string]: any }
	local v = NightService.view()
	local p = params
	return {
		running = NightService.running(),
		night = nightNumber,
		quiet = startOpts.quiet == true,
		seed = if p then p.seed else nil,
		rules = if p then p.rules else nil,
		crew = if p then p.playerIds else nil,
		view = if v then sanitize(v, 0) else nil,
		result = NightService.result(),
		events = seq,
		autoAdvance = NightService.autoAdvance,
		runNight = runNight,
		run = if run then Run.view(run) else nil,
		outcome = lastOutcome,
	}
end

return NightService
