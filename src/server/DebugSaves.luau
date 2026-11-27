--!strict
--[[
Studio-only S5 scenarios: saves, cosmetics and Endless. Registered into DebugDriver:

    return game:GetService("ServerScriptService"):WaitForChild("DeadCalmDebug"):Invoke("save_roundtrip")

    save_roundtrip   Writes a made-up profile (some stats, a Bucket Hat equipped) to a fresh
                     in-memory store through Core.SaveLogic, reads it back, and returns both
                     plus `same` (true when every stat and equipped item came back). Never
                     touches the real DataStore. Also returns the live store kind and each
                     player's session status. SCENARIO DONE save_roundtrip same | different.
    unlock_all_debug Every cosmetic unlocked for every player in the server, for a capture.
                     Those sessions never save afterwards (so a published place's real
                     profiles stay honest). opts.lantern, opts.paint, opts.hat equip items
                     at once (for example { lantern = "BlueHour", paint = "Oxblood",
                     hat = "Souwester" }). SCENARIO DONE unlock_all_debug unlocked.
    endless          Starts an Endless run at night 6 (opts.night for a later one) at a fast
                     clock: opts.seconds (default 90) and opts.quotaScale (default
                     seconds / Config.Night.realSeconds), opts.seed (default 6). The Endless
                     unlock is skipped. Returns the night's params. SCENARIO DONE endless
                     started | error:...
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Core = Shared:WaitForChild("Core")
local Profile = require(Core:WaitForChild("Profile")) :: any
local SaveLogic = require(Core:WaitForChild("SaveLogic")) :: any

local server = script.Parent
local NightService = require(server:WaitForChild("NightService"))
local LobbyService = require(server:WaitForChild("LobbyService"))
local DataService = require(server:WaitForChild("DataService"))
local DataStores = require(server:WaitForChild("DataStores"))
local Net = require(server:WaitForChild("Net"))
local DebugCrew = require(server:WaitForChild("DebugCrew"))

local DebugSaves = {}

type Opts = { [string]: any }

local H: any = nil

local function done(name: string, out: { [string]: any }): { [string]: any }
	out.scenario = name
	print(string.format("SCENARIO DONE %s %s", name, tostring(out.result)))
	return out
end

local function sessions(): { { [string]: any } }
	local out = {}
	for _, p in Players:GetPlayers() do
		local s = DataService.debugSession(p.UserId)
		table.insert(out, {
			player = p.DisplayName,
			status = if s then s.status else "none",
			canSave = if s then s.canSave else false,
			lastSave = if s then s.lastSave else nil,
		})
	end
	return out
end

local function saveRoundtrip(_opts: Opts): { [string]: any }
	local store = DataStores.memory()
	local key = DataStores.profileKey(1)
	local p = Profile.default(Config)
	Profile.recordNight(Config, p, {
		cleared = true,
		mode = "Story",
		difficulty = "Normal",
		night = 1,
		fishBanked = 7,
		scaresSurvived = 2,
	})
	Profile.equip(Config, p, "hat", "BucketHat")
	local written = Profile.serialize(p)
	local saved = SaveLogic.save(Config, store, key, p, { sleep = function() end }, true)
	local loaded = SaveLogic.load(Config, store, key, { sleep = function() end })
	local back = Profile.serialize(loaded.profile)
	local same = saved.ok and loaded.status == "Current"
	for k, v in written.stats do
		if back.stats[k] ~= v then
			same = false
		end
	end
	for k, v in written.equipped do
		if back.equipped[k] ~= v then
			same = false
		end
	end
	return done("save_roundtrip", {
		result = if same then "same" else "different",
		written = written,
		read = back,
		saveStatus = saved.status,
		loadStatus = loaded.status,
		liveStore = if DataService.memory() then "Memory" else "DataStore",
		sessions = sessions(),
	})
end

local function unlockAll(opts: Opts): { [string]: any }
	local n = 0
	for _, p in Players:GetPlayers() do
		if DataService.debugUnlockAll(p) then
			n += 1
			for _, slot in { "lantern", "paint", "hat" } do
				if type(opts[slot]) == "string" then
					Net.handlers.Cosmetic(p, slot, opts[slot])
				end
			end
		end
	end
	return done("unlock_all_debug", {
		result = if n > 0 then "unlocked" else "error:no loaded profiles",
		players = n,
		sessions = sessions(),
	})
end

local function endless(opts: Opts): { [string]: any }
	DebugCrew.stop()
	local remote = H.botRemote()
	if remote then
		for _, p in Players:GetPlayers() do
			remote:FireClient(p, { cmd = "clean", tapes = false })
		end
	end
	task.wait(0.4)
	LobbyService.toTitle()
	local seconds = tonumber(opts.seconds) or 90
	local ok = LobbyService.startRun({
		mode = "Endless",
		night = tonumber(opts.night) or 6,
		seed = tonumber(opts.seed) or 6,
		seconds = seconds,
		quotaScale = tonumber(opts.quotaScale) or seconds / Config.Night.realSeconds,
	})
	local p = NightService.params()
	if not ok or p == nil then
		return done("endless", { result = "error:could not start" })
	end
	return done("endless", {
		result = "started",
		night = p.night,
		mode = p.mode,
		rules = p.rules,
		amendments = p.amendments,
		quota = p.quota,
		seconds = seconds,
		run = NightService.runView(),
	})
end

function DebugSaves.register(driver: any)
	H = driver.helpers
	driver.register("save_roundtrip", saveRoundtrip)
	driver.register("unlock_all_debug", unlockAll)
	driver.register("endless", endless)
end

return DebugSaves
