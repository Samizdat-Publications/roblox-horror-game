--!strict
-- Owns the night: builds NightParams (Core.Run when it exists, else straight from
-- Config.Nights), creates Core.Night, ticks it at Config.Night.tick, gathers observations
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
local Quota = require(Core:WaitForChild("Quota"))

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
-- NightParams

local function rulesFor(night: number): ({ any }, { any })
	local rules, newRules = {}, {}
	for n = 1, math.clamp(night, 1, #Config.Nights) do
		for _, r in Config.Nights[n].newRules do
			table.insert(rules, r)
			if n == night then
				table.insert(newRules, r)
			end
		end
	end
	return rules, newRules
end

-- SEAM: Core.Run.nightParams once Core.Run lands. Story, Normal, the book as printed.
local function buildParams(night: number, seed: number, ids: { number }, o: StartOpts, c: any): NightParams
	local crew = math.clamp(#ids, 1, 4)
	local N = c.Nights[math.clamp(night, 1, #c.Nights)]
	local D = c.Difficulty.Normal
	local rules, newRules = rulesFor(night)
	local p: NightParams = {
		seed = seed,
		night = night,
		mode = "Story",
		difficulty = "Normal",
		playerIds = ids,
		rules = rules :: any,
		newRules = newRules :: any,
		amendments = {},
		supplies = {},
		real = math.max(1, math.floor(N.real * c.Scaling.budget[crew] * D.budget + 0.5)),
		fake = N.fake,
		quietGap = N.quietGap * D.quiet,
		quota = Quota.scaled(c, N.quota, crew),
		maxConcurrent = N.maxConcurrent,
		warningScale = c.Scaling.warning[crew] * D.warning,
	}
	if o.quiet then
		p.rules = {}
		p.newRules = {}
		p.real = 0
		p.fake = 0
	end
	if o.quota then
		p.quota = math.max(1, math.floor(o.quota))
	end
	return p
end
-- END SEAM

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
		gazeYaw = Net.gazeOf(id) or 0,
		bookOpen = false, -- SEAM: rulebook and Field Guide (S4)
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
	if #intents > 0 then
		for _, fn in intentListeners do
			task.spawn(fn, intents)
		end
	end
	local events = Night.step(s, observe(dt, intents)) :: { Event }
	local v = Night.view(s) :: NightView
	syncWorld(v)
	dispatch(events)
	FishingService.step(dt, v)
	local ended = Night.result(s) ~= nil
	replicate(v, ended)
	if ended and endedAt == nil then
		endedAt = now
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
	-- Between nights: the next one starts by itself (a failed night restarts).
	local e = endedAt
	if e ~= nil and NightService.autoAdvance and now - e >= NightService.BETWEEN then
		local res = Night.result(state)
		local nextNight = nightNumber
		if res and res.cleared then
			nextNight = if nightNumber >= #Config.Nights then 1 else nightNumber + 1
		end
		NightService.start({ night = nextNight })
	end
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
	local night = math.clamp(math.floor(opts.night or nightNumber), 1, #Config.Nights)
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
	local v = Night.view(state) :: NightView
	syncWorld(v)
	replicate(v, true)
	for _, fn in startListeners do
		task.spawn(fn, p)
	end
	return p
end

-- Starts night 1 once the first player is seated (or after `waitSeconds` with players in).
function NightService.startWhenReady(waitSeconds: number)
	task.spawn(function()
		local since: number? = nil
		while state == nil do
			local players = Players:GetPlayers()
			local seated = false
			for _, p in players do
				if BoatService.seatOf(p) ~= nil then
					seated = true
				end
			end
			if #players > 0 and since == nil then
				since = os.clock()
			end
			if seated or (since ~= nil and os.clock() - since >= waitSeconds) then
				-- Give a seated player a moment to settle before the clock runs.
				task.wait(1)
				NightService.start({ night = 1 })
				return
			end
			task.wait(0.5)
		end
	end)
end

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
	}
end

return NightService
