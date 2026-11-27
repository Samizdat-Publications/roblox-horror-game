--!strict
-- The front and back of a run (docs/ARCHITECTURE.md, LobbyService):
--   * The title screen: the first player in the server is the host. The host picks Normal or
--     Nightmare and presses Play (Lobby remote: "Difficulty", "Start").
--   * The five-night flow through Core.Run: NightService.newRun, then each night from the
--     run. When a night ends NightService calls Run.finishNight; BETWEEN seconds later the
--     next night starts (NextNight), the same night starts again (RetryNight), or, after
--     RUN_END seconds on the run-cleared or run-over card, everyone is back on the title.
--   * Endless Nights (S5): the host picks "Endless" (Lobby "Mode") once their profile has a
--     cleared run (DataService.endlessUnlocked); the run starts at night 6 in Core.Run's
--     Endless mode and goes on until a night is failed.
--   * The boat wears the host's lantern and paint (DataService profiles, Cosmetics).
--   * Late joiners wait as the drowned (hidden, never steering) until the next night, when
--     NightService takes every player in the server as the crew.
-- Every change goes out to every client on the LobbyState remote (see LobbyService.state).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local server = script.Parent
local Net = require(server:WaitForChild("Net"))
local NightService = require(server:WaitForChild("NightService"))
local BoatService = require(server:WaitForChild("BoatService"))
local FishingService = require(server:WaitForChild("FishingService"))
local EntityPresenter = require(server:WaitForChild("EntityPresenter"))
local DataService = require(server:WaitForChild("DataService"))
local Cosmetics = require(server:WaitForChild("Cosmetics"))

local LobbyService = {}

LobbyService.BETWEEN = 12 -- seconds on the end of night card before the next night
LobbyService.RUN_END = 30 -- seconds on the run-cleared or run-over card before the title

export type Phase = "Title" | "Playing" | "RunCleared" | "RunOver"

local phase: Phase = "Title"
local host: number? = nil
local difficulty = "Normal"
local mode = "Story" -- "Story" | "Endless"
local waiting: { [number]: boolean } = {}
local lastResult: any = nil
local runOpts: { [string]: any } = {}
local endedRun: any = nil -- the finished run's totals, for the run-cleared card

local function playerIds(): { number }
	local ids = {}
	for _, p in Players:GetPlayers() do
		table.insert(ids, p.UserId)
	end
	return ids
end

local function nameOf(id: number?): string?
	local p = if id then Players:GetPlayerByUserId(id) else nil
	return if p then p.DisplayName else nil
end

-- Plain data for clients. No sparse numeric keys (they do not survive a remote).
function LobbyService.state(): { [string]: any }
	local w = {}
	for id in waiting do
		table.insert(w, id)
	end
	local p = NightService.params()
	local night = nil
	if p then
		night = {
			night = p.night,
			mode = p.mode,
			difficulty = p.difficulty,
			rules = table.clone(p.rules),
			newRules = table.clone(p.newRules),
			amendments = table.clone(p.amendments or {}),
			quota = p.quota,
		}
	end
	local rv = NightService.runView()
	return {
		phase = phase,
		host = host,
		hostName = nameOf(host),
		difficulty = difficulty,
		players = playerIds(),
		waiting = w,
		run = rv,
		runNight = NightService.isRunNight(),
		outcome = NightService.lastOutcome(),
		night = night,
		totals = endedRun,
		nights = #Config.Nights,
		mode = mode,
		endlessOpen = DataService.endlessUnlocked(host),
		board = DataService.board(),
		memorySaves = DataService.memory(),
	}
end

function LobbyService.broadcast()
	Net.fireAll("LobbyState", LobbyService.state())
end

local function sendTo(player: Player)
	Net.fire("LobbyState", player, LobbyService.state())
end

-- The boat wears the host's lantern and paint (Amber and bare wood with no host profile).
local function dressBoat()
	local eq = DataService.equipped(host or 0) or {}
	Cosmetics.applyBoat(eq.lantern, eq.paint)
end

local function pickHost()
	if host and Players:GetPlayerByUserId(host) then
		return
	end
	local first = Players:GetPlayers()[1]
	host = if first then first.UserId else nil
	dressBoat()
end

-- Starts a run and its first night. Studio scenarios pass seed, night (a later first
-- night), seconds and quotaScale (a fast clock), firstRun.
function LobbyService.startRun(o: { [string]: any }?): boolean
	local opts = o or {}
	if opts.difficulty == "Normal" or opts.difficulty == "Nightmare" then
		difficulty = opts.difficulty
	end
	if opts.mode == "Story" or opts.mode == "Endless" then
		mode = opts.mode
	end
	local r = NightService.newRun({
		mode = mode,
		difficulty = difficulty,
		seed = tonumber(opts.seed),
		firstRun = opts.firstRun ~= false,
		night = tonumber(opts.night),
		seconds = tonumber(opts.seconds),
		quotaScale = tonumber(opts.quotaScale),
	})
	if r == nil then
		return false
	end
	runOpts = opts
	endedRun = nil
	lastResult = nil
	phase = "Playing"
	local p = NightService.startRunNight({ quota = tonumber(opts.quota) })
	LobbyService.broadcast()
	return p ~= nil
end

-- Back to the title screen: the run and the night end, the boat goes home, everyone shows.
function LobbyService.toTitle()
	NightService.endRun()
	phase = "Title"
	waiting = {}
	lastResult = nil
	FishingService.reset()
	EntityPresenter.reset()
	local x, z, h = BoatService.tieSpot()
	BoatService.teleport(x, z, h)
	if BoatService.lanternOn() ~= true then
		BoatService.setLantern(true)
	end
	if BoatService.motorOn() then
		BoatService.setMotor(false)
	end
	pickHost()
	LobbyService.broadcast()
end

function LobbyService.phase(): Phase
	return phase
end

function LobbyService.host(): number?
	return host
end

function LobbyService.setDifficulty(d: string)
	if d == "Normal" or d == "Nightmare" then
		difficulty = d
		LobbyService.broadcast()
	end
end

local function onLobby(player: Player, action: string, value: any)
	local isHost = player.UserId == host
	if action == "Difficulty" then
		if isHost and phase == "Title" and type(value) == "string" then
			LobbyService.setDifficulty(value)
		end
	elseif action == "Mode" then
		if isHost and phase == "Title" then
			if value == "Story" or (value == "Endless" and DataService.endlessUnlocked(host)) then
				mode = value
				LobbyService.broadcast()
			end
		end
	elseif action == "Start" then
		if isHost and phase == "Title" then
			if mode == "Endless" and not DataService.endlessUnlocked(host) then
				mode = "Story"
			end
			LobbyService.startRun({})
		end
	elseif action == "Title" then
		-- The host can leave the run-cleared or run-over card early.
		if isHost and (phase == "RunCleared" or phase == "RunOver") then
			LobbyService.toTitle()
		end
	elseif action == "Hello" then
		sendTo(player)
		DataService.resend(player)
	end
end

-- A late joiner: hidden as one of the drowned until the next night.
local function hideIfWaiting(player: Player)
	task.spawn(function()
		local waited = 0
		while not player:HasAppearanceLoaded() and waited < 10 do
			waited += task.wait(0.25)
		end
		task.wait(1)
		if waiting[player.UserId] and player.Parent then
			EntityPresenter.hideWaiting(player)
		end
	end)
end

local function onPlayerAdded(player: Player)
	pickHost()
	local p = NightService.params()
	if NightService.running() and p ~= nil and not table.find(p.playerIds, player.UserId) then
		waiting[player.UserId] = true
		player.CharacterAdded:Connect(function()
			if waiting[player.UserId] then
				hideIfWaiting(player)
			end
		end)
		if player.Character then
			hideIfWaiting(player)
		end
	end
	LobbyService.broadcast()
end

local function onPlayerRemoving(player: Player)
	waiting[player.UserId] = nil
	if host == player.UserId then
		host = nil
	end
	task.defer(function()
		pickHost()
		if #Players:GetPlayers() == 0 then
			if phase ~= "Title" then
				LobbyService.toTitle()
			end
		else
			LobbyService.broadcast()
		end
	end)
end

-- Called every Heartbeat by Main: what comes after a night.
function LobbyService.tick(_dt: number)
	if phase == "Title" or not NightService.autoAdvance then
		return
	end
	local e = NightService.endedFor()
	if e == nil then
		return
	end
	local outcome = NightService.lastOutcome()
	if outcome == "NextNight" or outcome == "RetryNight" then
		if e >= LobbyService.BETWEEN then
			NightService.startRunNight()
		end
	elseif outcome == "RunCleared" or outcome == "RunOver" then
		if e >= LobbyService.RUN_END then
			LobbyService.toTitle()
		end
	end
end

function LobbyService.debugState(): { [string]: any }
	return {
		state = LobbyService.state(),
		lastResult = lastResult,
		runOpts = runOpts,
	}
end

function LobbyService.mode(): string
	return mode
end

function LobbyService.init()
	Net.onLobby = onLobby
	DataService.onProfile(function(player: Player)
		if player.UserId == host then
			dressBoat()
		end
		LobbyService.broadcast()
	end)
	DataService.onBoard(function()
		LobbyService.broadcast()
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	NightService.onStart(function()
		waiting = {}
		-- Any night (a Studio scenario too) takes the title screen down.
		if phase ~= "Playing" then
			phase = "Playing"
		end
		LobbyService.broadcast()
	end)
	NightService.onNightEnd(function(result: any, outcome: string?, _rv: any)
		lastResult = result
		if outcome == "RunCleared" or outcome == "RunOver" then
			phase = if outcome == "RunCleared" then "RunCleared" else "RunOver"
			local r = NightService.run()
			if r then
				endedRun = {
					nightsCleared = r.nightsCleared,
					fishBanked = r.fishBanked,
					scaresSurvived = r.scaresSurvived,
					deaths = r.deaths,
					attempts = r.attempts,
					difficulty = r.difficulty,
					cleared = r.cleared,
					mode = r.mode,
					bestNight = r.bestNight,
				}
			end
		end
		LobbyService.broadcast()
	end)
end

return LobbyService
