--!strict
-- The lobby on this client: the latest LobbyState from the server (phase, host, difficulty,
-- the run, tonight's page of the book, who is waiting for the next night) and the Lobby
-- actions this client may send (difficulty, start, back to the title, the book flag).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local LobbyClient = {}

export type NightInfo = {
	night: number,
	mode: string?,
	difficulty: string?,
	rules: { string },
	newRules: { string },
	amendments: { [string]: string },
	quota: number?,
}

export type State = {
	phase: string, -- "Title" | "Playing" | "RunCleared" | "RunOver"
	host: number?,
	hostName: string?,
	difficulty: string,
	players: { number },
	waiting: { number },
	run: { [string]: any }?,
	runNight: boolean?,
	outcome: string?,
	night: NightInfo?,
	totals: { [string]: any }?,
	nights: number?,
}

local state: State = {
	phase = "Title",
	host = nil,
	difficulty = "Normal",
	players = {},
	waiting = {},
}
local received = false
local listeners: { (State) -> () } = {}
local remote: RemoteEvent? = nil

local function clean(raw: any): State?
	if type(raw) ~= "table" or type(raw.phase) ~= "string" then
		return nil
	end
	local function list(v: any): { any }
		return if type(v) == "table" then v else {}
	end
	local night: NightInfo? = nil
	if type(raw.night) == "table" and type(raw.night.night) == "number" then
		night = {
			night = raw.night.night,
			mode = raw.night.mode,
			difficulty = raw.night.difficulty,
			rules = list(raw.night.rules),
			newRules = list(raw.night.newRules),
			amendments = list(raw.night.amendments) :: any,
			quota = tonumber(raw.night.quota),
		}
	end
	return {
		phase = raw.phase,
		host = tonumber(raw.host),
		hostName = if type(raw.hostName) == "string" then raw.hostName else nil,
		difficulty = if raw.difficulty == "Nightmare" then "Nightmare" else "Normal",
		players = list(raw.players),
		waiting = list(raw.waiting),
		run = if type(raw.run) == "table" then raw.run else nil,
		runNight = raw.runNight == true,
		outcome = if type(raw.outcome) == "string" then raw.outcome else nil,
		night = night,
		totals = if type(raw.totals) == "table" then raw.totals else nil,
		nights = tonumber(raw.nights),
	}
end

function LobbyClient.get(): State
	return state
end

-- True once the server has sent a state.
function LobbyClient.ready(): boolean
	return received
end

function LobbyClient.onChange(fn: (State) -> ())
	table.insert(listeners, fn)
end

function LobbyClient.isHost(): boolean
	return state.host == Players.LocalPlayer.UserId
end

-- This player joined while a night was running: they wait as one of the drowned.
function LobbyClient.waiting(): boolean
	return table.find(state.waiting, Players.LocalPlayer.UserId) ~= nil
end

function LobbyClient.send(action: string, value: (string | number)?)
	local r = remote
	if r then
		r:FireServer(action, value)
	end
end

function LobbyClient.init()
	remote = Remotes.wait("Lobby")
	local incoming = Remotes.wait("LobbyState")
	incoming.OnClientEvent:Connect(function(raw: any)
		local s = clean(raw)
		if s == nil then
			return
		end
		state = s
		received = true
		for _, fn in listeners do
			task.spawn(fn, s)
		end
	end)
	LobbyClient.send("Hello")
end

return LobbyClient
