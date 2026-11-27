--!strict
-- Saves (docs/ARCHITECTURE.md, DataService): each player's Core.Profile, loaded on join and
-- saved when a run night ends, when they leave, and when the server shuts down
-- (game:BindToClose). Everything goes through Core.SaveLogic (pcall, retries with backoff,
-- merge on save, never over a newer save) and a store adapter from DataStores (the real
-- DataStore, or memory when this place has none). Nothing here can error a player out: a
-- load that fails plays on safe defaults and never saves over the real profile.
--
-- Also: cosmetics (equip, validated against the profile; the hat on the character; the
-- boat wears the host's lantern and paint, see LobbyService), the best Endless night board
-- (an ordered store through the same adapter), and the Profile remote to each client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Core = Shared:WaitForChild("Core")
local Profile = require(Core:WaitForChild("Profile")) :: any
local SaveLogic = require(Core:WaitForChild("SaveLogic")) :: any
local Leaderboard = require(Core:WaitForChild("Leaderboard")) :: any

local server = script.Parent
local Net = require(server:WaitForChild("Net"))
local NightService = require(server:WaitForChild("NightService"))
local Cosmetics = require(server:WaitForChild("Cosmetics"))
local DataStores = require(server:WaitForChild("DataStores"))

local DataService = {}

DataService.BOARD_SIZE = 10 -- rows on the title screen's list
DataService.BOARD_REFRESH = 60 -- seconds between board reads (at most)
DataService.CLOSE_WAIT = 25 -- seconds BindToClose waits for saves (Roblox allows about 30)

type Session = {
	userId: number,
	profile: any,
	status: string,
	canSave: boolean,
	loaded: boolean,
	saving: boolean,
	again: boolean,
	noSave: boolean, -- Studio unlock_all_debug: never write this session
	lastSave: string?,
}

local stores: DataStores.Opened? = nil
local sessions: { [number]: Session } = {}
local profileListeners: { (Player) -> () } = {}
local boardListeners: { () -> () } = {}
local board: { { rank: number, name: string, night: number } } = {}
local boardAt = -math.huge
local boardBusy = false
local names: { [number]: string } = {}
local closing = false

local UNLOCK_TEXT: { [string]: string } = {}
for _, rule in Profile.UNLOCKS do
	UNLOCK_TEXT[rule.slot .. "." .. rule.id] = rule.text
end

local function retryOpts(): { [string]: any }
	return { sleep = task.wait }
end

local function opened(): DataStores.Opened
	local s = stores
	if s == nil then
		s = DataStores.open()
		stores = s
		if s.memory then
			-- The one line the brief asks for: saves do not outlive this server.
			print("[DeadCalm] saves are in memory this session: " .. tostring(s.reason))
		end
	end
	return s :: DataStores.Opened
end

----------------------------------------------------------------------------------------
-- The client's copy

local function payload(s: Session, new: { string }?): { [string]: any }
	local p = s.profile
	local st = opened()
	return {
		ready = s.loaded,
		status = s.status,
		memory = st.memory,
		canSave = s.canSave and not s.noSave,
		stats = table.clone(p.stats),
		equipped = table.clone(p.equipped),
		items = Cosmetics.catalog(p, UNLOCK_TEXT),
		slots = { "lantern", "paint", "hat" },
		slotNames = table.clone(Cosmetics.SLOT_NAMES),
		new = new or {},
		endless = p.stats.runsCleared >= 1,
	}
end

local function send(player: Player, new: { string }?)
	local s = sessions[player.UserId]
	if s == nil then
		return
	end
	pcall(Net.fire, "Profile", player, payload(s, new))
	for _, fn in profileListeners do
		task.spawn(fn, player)
	end
end

----------------------------------------------------------------------------------------
-- Load and save

local function saveSession(s: Session): string
	if s.noSave then
		return "NotAllowed"
	end
	if not s.loaded then
		return "NotLoaded"
	end
	if s.saving then
		s.again = true
		return "Queued"
	end
	s.saving = true
	local status = "Failed"
	repeat
		s.again = false
		local res = SaveLogic.save(
			Config,
			opened().profiles,
			DataStores.profileKey(s.userId),
			s.profile,
			retryOpts(),
			s.canSave
		)
		status = res.status
		if not res.ok and res.status == "Failed" then
			warn(
				string.format(
					"[DeadCalm] save failed for %d after %d tries: %s",
					s.userId,
					res.attempts,
					tostring(res.err)
				)
			)
		end
	until not s.again
	s.saving = false
	s.lastSave = status
	return status
end

-- Sends this player's copy again (the client says Hello once it is listening).
function DataService.resend(player: Player)
	local s = sessions[player.UserId]
	if s and s.loaded then
		pcall(Net.fire, "Profile", player, payload(s, nil))
	end
end

function DataService.save(player: Player): string
	local s = sessions[player.UserId]
	if s == nil then
		return "NoSession"
	end
	return saveSession(s)
end

local function applyHat(player: Player)
	local s = sessions[player.UserId]
	if s and s.loaded then
		Cosmetics.applyHat(player, s.profile.equipped.hat)
	end
end

local function load(player: Player)
	local userId = player.UserId
	local s: Session = {
		userId = userId,
		profile = Profile.default(Config),
		status = "Loading",
		canSave = false,
		loaded = false,
		saving = false,
		again = false,
		noSave = false,
	}
	sessions[userId] = s
	local ok, res = pcall(SaveLogic.load, Config, opened().profiles, DataStores.profileKey(userId), retryOpts())
	if sessions[userId] ~= s then
		return -- left while loading
	end
	if ok and type(res) == "table" then
		s.profile = res.profile
		s.status = res.status
		s.canSave = res.canSave
		if res.status == "LoadFailed" then
			warn(string.format("[DeadCalm] profile load failed for %d; playing on defaults, not saving", userId))
		end
	else
		s.status = "LoadFailed"
		s.canSave = false
		warn("[DeadCalm] profile load error: " .. tostring(res))
	end
	s.loaded = true
	names[userId] = player.DisplayName
	applyHat(player)
	send(player)
end

----------------------------------------------------------------------------------------
-- The board

local function lookupNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if names[id] == nil then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			if type(info) == "table" and type(info.Id) == "number" then
				local dn = info.DisplayName
				names[info.Id] = if type(dn) == "string" and dn ~= "" then dn else "A fisher"
			end
		end
	end
end

-- Reads the board (at most every BOARD_REFRESH seconds unless forced). Never errors.
function DataService.refreshBoard(force: boolean?)
	if boardBusy or (not force and os.clock() - boardAt < DataService.BOARD_REFRESH) then
		return
	end
	boardBusy = true
	boardAt = os.clock()
	local ok, rows = SaveLogic.retry(function()
		return opened().board:top(math.max(DataService.BOARD_SIZE, 1))
	end, { attempts = 2, baseDelay = 2, sleep = task.wait })
	if ok and type(rows) == "table" then
		local entries = {}
		for _, row in rows do
			local id = tonumber(row.key)
			if id then
				local night, at = Leaderboard.decode(row.value)
				table.insert(entries, { userId = id, bestNight = night, at = at })
			end
		end
		local top = Leaderboard.top(entries, DataService.BOARD_SIZE)
		local ids = {}
		for _, e in top do
			table.insert(ids, e.userId)
		end
		lookupNames(ids)
		local out = {}
		for _, e in top do
			-- Display names only, never user ids, on screen.
			table.insert(out, { rank = e.rank, name = names[e.userId] or "A fisher", night = e.bestNight })
		end
		board = out
		for _, fn in boardListeners do
			task.spawn(fn)
		end
	end
	boardBusy = false
end

function DataService.board(): { { rank: number, name: string, night: number } }
	return board
end

function DataService.onBoard(fn: () -> ())
	table.insert(boardListeners, fn)
end

local function submitBest(s: Session)
	if s.noSave then
		return
	end
	local best = s.profile.stats.bestEndlessNight
	if best <= 0 then
		return
	end
	local res = SaveLogic.submitBest(opened().board, tostring(s.userId), best, os.time(), retryOpts())
	if res.ok and res.status == "Saved" then
		DataService.refreshBoard(true)
	elseif not res.ok then
		warn("[DeadCalm] board submit failed: " .. tostring(res.err))
	end
end

----------------------------------------------------------------------------------------
-- Progress from the nights

local function onNightEnd(result: any, outcome: string?, _rv: any)
	if outcome == nil or type(result) ~= "table" then
		return -- a Studio scenario night outside a run earns nothing
	end
	local p = NightService.params()
	local run = NightService.run()
	if p == nil then
		return
	end
	for _, id in p.playerIds do
		local s = sessions[id]
		local player = Players:GetPlayerByUserId(id)
		if s and s.loaded and player then
			local new = Profile.recordNight(Config, s.profile, {
				cleared = result.cleared == true,
				mode = p.mode,
				difficulty = p.difficulty,
				night = p.night,
				fishBanked = result.bankedFish,
				scaresSurvived = result.scaresSurvived,
			})
			if (outcome == "RunCleared" or outcome == "RunOver") and run ~= nil then
				for _, u in
					Profile.recordRun(Config, s.profile, {
						cleared = run.cleared == true,
						mode = run.mode,
						difficulty = run.difficulty,
						solo = run.soloRun == true,
						bestNight = run.bestNight,
					})
				do
					table.insert(new, u)
				end
			end
			send(player, new)
			task.spawn(function()
				saveSession(s)
				if p.mode == "Endless" and result.cleared then
					submitBest(s)
				end
			end)
		end
	end
end

----------------------------------------------------------------------------------------
-- Cosmetics

-- Net.onCosmetic: the slot and id are already known to exist (Core.Validate).
local function equip(player: Player, slot: string, id: string)
	local s = sessions[player.UserId]
	if s == nil or not s.loaded then
		return
	end
	if not Profile.equip(Config, s.profile, slot, id) then
		send(player) -- refused: the client's copy snaps back
		return
	end
	if slot == "hat" then
		applyHat(player)
	end
	send(player)
end

function DataService.equipped(userId: number): { [string]: string }?
	local s = sessions[userId]
	return if s and s.loaded then table.clone(s.profile.equipped) else nil
end

function DataService.endlessUnlocked(userId: number?): boolean
	local s = if userId then sessions[userId] else nil
	return s ~= nil and s.loaded and s.profile.stats.runsCleared >= 1
end

function DataService.onProfile(fn: (Player) -> ())
	table.insert(profileListeners, fn)
end

function DataService.memory(): boolean
	return opened().memory
end

----------------------------------------------------------------------------------------
-- Studio helpers (DebugSaves)

function DataService.debugSession(userId: number): any
	return sessions[userId]
end

-- Studio only: every cosmetic unlocked for a capture. The session never saves afterwards.
function DataService.debugUnlockAll(player: Player): boolean
	local s = sessions[player.UserId]
	if s == nil or not s.loaded then
		return false
	end
	s.noSave = true
	for slot, ids in Config.Cosmetics :: any do
		s.profile.unlocked[slot] = s.profile.unlocked[slot] or {}
		for _, id in ids do
			s.profile.unlocked[slot][id] = true
		end
	end
	send(player)
	return true
end

----------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			local waited = 0
			while not player:HasAppearanceLoaded() and waited < 10 do
				waited += task.wait(0.25)
			end
			if player.Character == character then
				applyHat(player)
			end
		end)
	end)
	load(player)
end

local function onPlayerRemoving(player: Player)
	local s = sessions[player.UserId]
	if s == nil then
		return
	end
	saveSession(s)
	if sessions[player.UserId] == s then
		sessions[player.UserId] = nil
	end
end

local function onClose()
	if closing then
		return
	end
	closing = true
	local pending = 0
	for _, s in sessions do
		pending += 1
		task.spawn(function()
			pcall(saveSession, s)
			pending -= 1
		end)
	end
	local t0 = os.clock()
	while pending > 0 and os.clock() - t0 < DataService.CLOSE_WAIT do
		task.wait(0.1)
	end
end

function DataService.init()
	opened()
	Net.onCosmetic = equip
	NightService.onNightEnd(onNightEnd)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end
	game:BindToClose(onClose)
	task.spawn(DataService.refreshBoard, true)
end

return DataService
