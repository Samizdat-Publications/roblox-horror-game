--!strict
--[[
Studio-only S4 scenarios: the front and back of a run. Registered into DebugDriver, so they
run through the same bindable:

    return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("title")

    title       Back to the title screen (the run and the night end, the boat goes home).
                Every client shows the title: Play, Normal or Nightmare, the Lake Rules.
                Returns the lobby state. Prints SCENARIO DONE title shown.
    rulebook    A Normal first run started at night 5 (its one amendment is on the page),
                auto advance off, and the rulebook opened on the first player's client.
                opts.seed (default 1), opts.page ("rules" default, or "guide").
                Returns the night's rules and amendments. SCENARIO DONE rulebook open.
    full_run    A server crew bot (DebugCrew) plays a whole Normal run at a fast clock.
                opts.seconds (night length, default 150), opts.quotaScale (default
                seconds / Config.Night.realSeconds), opts.seed (default 1),
                opts.difficulty, opts.between (seconds between nights, default 8),
                opts.timeout, opts.async (default true: poll "status"). Returns cleared,
                the outcome and one line per night played. SCENARIO DONE full_run
                cleared | over | timeout.
    finale      Night 5 of a run at 3:50 AM with a true Steeple Cat in the hold, the boat at
                the steeple; the crew bot waits for the bell and runs home on the motor.
                opts.seed (default 905), opts.quota (default 3: the cat covers it),
                opts.hold (default true: the run-cleared card stays up), opts.async.
                Returns passed, outcome, strikes, deaths, seconds. SCENARIO DONE finale
                <outcome> (RunCleared when the crew gets home).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local server = script.Parent
local BoatService = require(server:WaitForChild("BoatService"))
local NightService = require(server:WaitForChild("NightService"))
local LobbyService = require(server:WaitForChild("LobbyService"))
local DebugCrew = require(server:WaitForChild("DebugCrew"))

local DebugRun = {}

type Opts = { [string]: any }

local H: any = nil -- DebugDriver.helpers

local function round(n: number?): number?
	if n == nil then
		return nil
	end
	return math.floor(n * 10 + 0.5) / 10
end

-- Every client: no death card, cards or rule leftovers, first-person camera, book shut.
local function cleanClients(tapes: boolean)
	local remote = H.botRemote()
	if remote then
		for _, p in Players:GetPlayers() do
			remote:FireClient(p, { cmd = "clean", tapes = tapes })
		end
	end
	task.wait(0.4)
end

local function runner(name: string, body: (Opts, { [string]: any }) -> { [string]: any }, asyncDefault: boolean?)
	return function(opts: Opts)
		local function go(progress: { [string]: any }): { [string]: any }
			local ok, res = pcall(body, opts, progress)
			local out: { [string]: any } = if ok and type(res) == "table" then res else { error = tostring(res) }
			local result = if ok then tostring(out.result or "done") else "error:" .. tostring(res)
			out.result = result
			out.scenario = name
			print(string.format("SCENARIO DONE %s %s", name, result))
			return out
		end
		local async = if opts.async == nil then asyncDefault == true else opts.async == true
		if async then
			local run = { name = name, done = false, progress = {}, startedAt = os.clock() }
			H.runs.last = run
			task.spawn(function()
				run.result = go(run.progress)
				run.done = true
			end)
			return { started = true, poll = "status" }
		end
		return go({})
	end
end

----------------------------------------------------------------------------------------

local function title(_opts: Opts, _progress: { [string]: any }): { [string]: any }
	DebugCrew.stop()
	cleanClients(true)
	LobbyService.toTitle()
	task.wait(0.5)
	local st = LobbyService.state()
	return { result = "shown", phase = st.phase, host = st.host, difficulty = st.difficulty }
end

local function rulebook(opts: Opts, _progress: { [string]: any }): { [string]: any }
	DebugCrew.stop()
	NightService.autoAdvance = false
	cleanClients(false)
	if not LobbyService.startRun({ night = 5, seed = tonumber(opts.seed) or 1, firstRun = true }) then
		return { result = "error:no players" }
	end
	task.wait(1.5)
	local p = NightService.params()
	local first = Players:GetPlayers()[1]
	local remote = H.botRemote()
	H.clearAck("book")
	if remote and first then
		remote:FireClient(first, { cmd = "book", page = if opts.page == "guide" then "guide" else "rules" })
	end
	local acked = H.waitAck("book", 3)
	local amended = 0
	for _ in (if p then p.amendments else {}) :: any do
		amended += 1
	end
	return {
		result = if acked then "open" else "no-ack",
		night = if p then p.night else nil,
		rules = if p then p.rules else nil,
		amendments = if p then p.amendments else nil,
		amended = amended,
	}
end

-- Night results as they come (full_run and finale).
local log: { { [string]: any } } = {}
local logging = false
local hooked = false
local failReason: string? = nil

local function hook()
	if hooked then
		return
	end
	hooked = true
	NightService.subscribe(function(e: any)
		if e.kind == "NightFailed" and type(e.data) == "table" then
			failReason = e.data.reason
		elseif e.kind == "NightStarted" then
			failReason = nil
		end
	end)
	NightService.onNightEnd(function(result: any, outcome: string?, rv: any)
		if not logging then
			return
		end
		task.wait(0.1) -- the NightFailed reason lands in the same tick
		local p = NightService.params()
		table.insert(log, {
			night = if p then p.night else nil,
			attempt = if rv then rv.attempt else nil,
			cleared = result.cleared,
			reason = if result.cleared then nil else failReason,
			banked = result.banked,
			quota = result.quota,
			deaths = #result.deaths,
			scares = result.scaresSurvived,
			outcome = outcome,
			crew = DebugCrew.stats(),
		})
	end)
end

local function fullRun(opts: Opts, progress: { [string]: any }): { [string]: any }
	hook()
	local seconds = tonumber(opts.seconds) or 150
	local scale = tonumber(opts.quotaScale) or seconds / Config.Night.realSeconds
	local between = tonumber(opts.between) or 8
	local timeout = tonumber(opts.timeout) or (seconds + between + 10) * 10 + 120
	cleanClients(true)
	local oldBetween = LobbyService.BETWEEN
	local oldEnd = LobbyService.RUN_END
	LobbyService.BETWEEN = between
	LobbyService.RUN_END = 600 -- the run-cleared card stays up while the scenario reports
	NightService.autoAdvance = true
	log = {}
	logging = true
	DebugCrew.start()
	local t0 = os.clock()
	local ok = LobbyService.startRun({
		seed = tonumber(opts.seed) or 1,
		seconds = seconds,
		quotaScale = scale,
		difficulty = opts.difficulty,
		firstRun = true,
	})
	local outcome: string? = nil
	if ok then
		while os.clock() - t0 < timeout do
			task.wait(0.5)
			outcome = NightService.lastOutcome()
			local v = NightService.view()
			progress.nights = #log
			progress.night = if v then v.night else nil
			progress.banked = if v then v.banked else nil
			progress.quota = if v then v.quota else nil
			progress.timeLeft = if v then round(v.timeLeft) else nil
			progress.crew = DebugCrew.stats()
			if outcome == "RunCleared" or outcome == "RunOver" then
				break
			end
		end
	end
	task.wait(0.3)
	logging = false
	DebugCrew.stop()
	LobbyService.BETWEEN = oldBetween
	LobbyService.RUN_END = oldEnd
	local result = if outcome == "RunCleared"
		then "cleared"
		elseif outcome == "RunOver" then "over"
		elseif ok then "timeout"
		else "error:no players"
	return {
		result = result,
		cleared = outcome == "RunCleared",
		outcome = outcome,
		nights = log,
		seconds = round(os.clock() - t0),
		nightSeconds = seconds,
		quotaScale = round(scale),
		run = NightService.runView(),
	}
end

local function finale(opts: Opts, progress: { [string]: any }): { [string]: any }
	hook()
	cleanClients(true)
	NightService.autoAdvance = opts.hold == false
	log = {}
	logging = true
	local ok = LobbyService.startRun({
		night = 5,
		seed = tonumber(opts.seed) or 905,
		quota = tonumber(opts.quota) or 3,
		firstRun = true,
	})
	if not ok then
		logging = false
		return { result = "error:no players" }
	end
	task.wait(0.5)
	local s = NightService.debugState()
	if s == nil then
		logging = false
		return { result = "error:no night" }
	end
	-- 3:50 AM.
	local N = Config.Night
	local hour = 27 + 50 / 60
	s.clock.elapsed = (hour - N.startHour) / (N.endHour - N.startHour) * s.clock.length
	-- A true Steeple Cat in the hold (caught by the steeple after three, as the book says).
	local def = Config.Fish.SteepleCat
	table.insert(s.hold, {
		species = "SteepleCat",
		points = def.points,
		wrong = false,
		tier = 0,
		traits = table.clone(def.traits),
	})
	-- The boat at the steeple's near edge, bow toward home.
	local L = Config.Lake
	local st, dk = L.steeple, L.dockEnd
	local dx, dz = dk.x - st.x, dk.z - st.z
	local d = math.sqrt(dx * dx + dz * dz)
	local r = L.steepleRadius - 15
	local x, z = st.x + dx / d * r, st.z + dz / d * r
	BoatService.teleport(x, z, math.atan2(dk.x - x, dk.z - z))
	DebugCrew.start({ steeple = true })
	local t0 = os.clock()
	local outcome: string? = nil
	while os.clock() - t0 < (tonumber(opts.timeout) or 150) do
		task.wait(0.25)
		local v = NightService.view()
		progress.phase = if v then v.phase else nil
		progress.oil = if v then round(v.oil) else nil
		progress.crew = DebugCrew.stats()
		if NightService.endedFor() ~= nil then
			task.wait(0.3)
			outcome = NightService.lastOutcome()
			break
		end
	end
	logging = false
	local stats = DebugCrew.stats()
	DebugCrew.stop()
	local res = NightService.result()
	return {
		result = outcome or "timeout",
		passed = res ~= nil and res.cleared == true,
		outcome = outcome,
		reason = failReason,
		strikes = stats.strikes or 0,
		deaths = stats.deaths or 0,
		seconds = round(os.clock() - t0),
		nights = log,
	}
end

function DebugRun.register(driver: any)
	H = driver.helpers
	driver.register("title", runner("title", title))
	driver.register("rulebook", runner("rulebook", rulebook))
	driver.register("full_run", runner("full_run", fullRun, true))
	driver.register("finale", runner("finale", finale))
end

return DebugRun
