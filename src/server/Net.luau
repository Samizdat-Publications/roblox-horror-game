--!strict
-- Creates the remotes listed in Shared/Remotes and checks every client message before it
-- touches the game: type and range checks, a token bucket per player per remote, and a
-- distance check where it matters (banking and refilling need the boat at the dock).
-- Malformed or over-rate messages are dropped silently and counted in Net.stats (a client
-- must not be able to flood the server console). Valid intents queue for the night loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))
local Validate = require(Shared:WaitForChild("Core"):WaitForChild("Validate")) :: any
local RateLimit = require(Shared:WaitForChild("Core"):WaitForChild("RateLimit"))

local BoatService = require(script.Parent:WaitForChild("BoatService"))

type Intent = Types.Intent

local Net = {}

Net.stats = {
	accepted = {} :: { [string]: number },
	rejected = {} :: { [string]: number },
}

local folder: Folder? = nil
local debugFolder: Folder? = nil
local intents: { Intent } = {}
local gaze: { [number]: number } = {}
-- Whether each player has the rulebook or the Field Guide open (Lobby "Book" action). The
-- night reads it as PlayerObs.bookOpen; a player with the book open has no hands.
local bookOpen: { [number]: boolean } = {}
-- Whether each player plays on a touch screen (Lobby "Touch"; the Watcher's cones are wider).
local touch: { [number]: boolean } = {}
-- Intents that need hands: refused while the book covers the view (letting go of the reel
-- or the bail is always allowed, so nothing stays held).
local HANDS: { [string]: boolean } = {
	ToggleLantern = true,
	ToggleMotor = true,
	Cast = true,
	Bank = true,
	RefillOil = true,
	Knock = true,
	CatchDecision = true,
}

-- Payload checks are Core.Validate and the token buckets Core.RateLimit, both covered by
-- the Lune specs (tests/Validate.spec.luau, tests/RateLimit.spec.luau), so what ships is
-- what is tested.

type Bucket = RateLimit.Bucket
local buckets: { [Player]: { [string]: Bucket } } = {}

-- Studio-only debug remotes get their own buckets (RateLimit.forPlayer covers the game's).
local DEBUG_LIMITS: { [string]: { burst: number, rate: number } } = {
	DebugBot = { burst = 10, rate = 10 },
	DebugCamera = { burst = 10, rate = 10 },
}

-- Takes one token from this player's bucket for `remote`. Unknown names are refused.
local function allow(player: Player, remote: string): boolean
	local per = buckets[player]
	if per == nil then
		per = RateLimit.forPlayer(Config)
		buckets[player] = per
	end
	local b = per[remote]
	if b == nil then
		local lim = DEBUG_LIMITS[remote]
		if lim == nil then
			return false
		end
		b = RateLimit.new(lim.burst, lim.rate)
		per[remote] = b
	end
	return RateLimit.take(b, os.clock())
end

local function count(tbl: { [string]: number }, key: string)
	tbl[key] = (tbl[key] or 0) + 1
end

local function boatAtDock(): boolean
	local k = BoatService.kinematics()
	local tip = Config.Lake.dockEnd
	local dx, dz = k.x - tip.x, k.z - tip.z
	-- The boat ties up a few studs past the dock end, so measure with that slack.
	local r = Config.Lake.bankRadius
	return dx * dx + dz * dz <= r * r
end

-- Handlers are public so DebugDriver can drive the exact path a client message takes.
Net.handlers = {}

-- EntityPresenter sets this: true for a player the lake has taken tonight. The drowned keep
-- their seat (hidden) but never steer.
Net.isDrowned = function(_userId: number): boolean
	return false
end

function Net.handlers.BoatInput(player: Player, rawThrottle: any, rawSteer: any): boolean
	if not allow(player, "BoatInput") or Net.isDrowned(player.UserId) then
		count(Net.stats.rejected, "BoatInput")
		return false
	end
	local ok, clean = Validate.BoatInput(Config, rawThrottle, rawSteer)
	if not ok then
		count(Net.stats.rejected, "BoatInput")
		return false
	end
	local throttle: number, steer: number = clean.throttle, clean.steer
	if bookOpen[player.UserId] then
		-- Reading, not steering: the helm goes slack.
		throttle, steer = 0, 0
	end
	if not BoatService.setHelmInput(player, throttle, steer) then
		count(Net.stats.rejected, "BoatInput")
		return false
	end
	count(Net.stats.accepted, "BoatInput")
	return true
end

function Net.handlers.Gaze(player: Player, rawYaw: any): boolean
	if not allow(player, "Gaze") then
		count(Net.stats.rejected, "Gaze")
		return false
	end
	local ok, yaw = Validate.Gaze(Config, rawYaw)
	if not ok then
		count(Net.stats.rejected, "Gaze")
		return false
	end
	gaze[player.UserId] = yaw
	count(Net.stats.accepted, "Gaze")
	return true
end

function Net.handlers.Intent(player: Player, kind: any, num: any, flag: any, text: any): boolean
	if not allow(player, "Intent") then
		count(Net.stats.rejected, "Intent")
		return false
	end
	local ok, clean = Validate.Intent(Config, kind, num, flag, text)
	if not ok then
		count(Net.stats.rejected, "Intent")
		return false
	end
	local intent: Intent = {
		kind = clean.kind,
		player = player.UserId,
		num = clean.num,
		flag = clean.flag,
		text = clean.text,
	}
	if HANDS[intent.kind] and bookOpen[player.UserId] then
		count(Net.stats.rejected, "Intent")
		return false
	end
	if (intent.kind == "Bank" or intent.kind == "RefillOil") and not boatAtDock() then
		count(Net.stats.rejected, "Intent")
		return false
	end
	table.insert(intents, intent)
	count(Net.stats.accepted, "Intent")
	return true
end

function Net.touchOf(userId: number): boolean
	return touch[userId] == true
end

function Net.bookOpenOf(userId: number): boolean
	return bookOpen[userId] == true
end

-- LobbyService sets this: what a valid Lobby message does (difficulty, start).
Net.onLobby = function(_player: Player, _action: string, _value: any) end

-- Lobby actions (Validate.LOBBY): "Difficulty" (value "Normal" | "Nightmare"), "Mode",
-- "Start", "Title", "Hello", "Book" (value 1 open, 0 closed), "Touch" (value 1 on a touch
-- screen, else 0). Type check and rate limit here; LobbyService decides.
function Net.handlers.Lobby(player: Player, rawAction: any, rawValue: any): boolean
	-- The book flag changes often (open, close): it spends only its own bucket.
	local bucket = if rawAction == "Book" then "Book" else "Lobby"
	local ok: boolean, clean: any = false, nil
	if allow(player, bucket) then
		ok, clean = Validate.Lobby(Config, rawAction, rawValue)
	end
	count(if ok then Net.stats.accepted else Net.stats.rejected, "Lobby")
	if not ok then
		return false
	end
	local action: string, value: any = clean.action, clean.value
	if action == "Touch" then
		touch[player.UserId] = if value == 1 then true else nil
		return true
	end
	if action == "Book" then
		local open = value == 1
		local was = bookOpen[player.UserId] == true
		bookOpen[player.UserId] = open or nil
		if open and not was then
			-- Hands off: let go of the reel and the bail at once.
			table.insert(intents, { kind = "ReelHold" :: any, player = player.UserId, flag = false })
			table.insert(intents, { kind = "BailHold" :: any, player = player.UserId, flag = false })
		end
		return true
	end
	Net.onLobby(player, action, value)
	return true
end

-- DataService sets this: equip an item (whether the player has unlocked it is Profile's call).
Net.onCosmetic = function(_player: Player, _slot: string, _id: string) end

function Net.handlers.Cosmetic(player: Player, slot: any, id: any): boolean
	local ok = allow(player, "Cosmetic") and (Validate.Cosmetic(Config, slot, id))
	count(if ok then Net.stats.accepted else Net.stats.rejected, "Cosmetic")
	if ok then
		Net.onCosmetic(player, slot, id)
	end
	return ok == true
end

function Net.init()
	assert(folder == nil, "Net.init called twice")
	local old = ReplicatedStorage:FindFirstChild(Remotes.FOLDER)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = Remotes.FOLDER
	for _, name in Remotes.all() do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = f
	end
	for _, name in Remotes.toServer do
		local handler = (Net.handlers :: any)[name]
		assert(handler, "no Net handler for " .. name)
		local remote = f:FindFirstChild(name) :: RemoteEvent
		remote.OnServerEvent:Connect(function(player: Player, ...)
			handler(player, ...)
		end)
	end
	-- Server-to-client remotes: a client firing one is dropped and counted. With no handler
	-- connected Roblox would queue the calls and warn, letting a client spam the console.
	for _, name in Remotes.toClient do
		local remote = f:FindFirstChild(name) :: RemoteEvent
		remote.OnServerEvent:Connect(function()
			count(Net.stats.rejected, name)
		end)
	end
	f.Parent = ReplicatedStorage
	folder = f

	if RunService:IsStudio() then
		local oldDebug = ReplicatedStorage:FindFirstChild(Remotes.DEBUG_FOLDER)
		if oldDebug then
			oldDebug:Destroy()
		end
		local df = Instance.new("Folder")
		df.Name = Remotes.DEBUG_FOLDER
		for _, name in Remotes.debug do
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = df
		end
		df.Parent = ReplicatedStorage
		debugFolder = df
	end

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
		gaze[player.UserId] = nil
		bookOpen[player.UserId] = nil
		touch[player.UserId] = nil
	end)
end

function Net.remote(name: Remotes.RemoteName): RemoteEvent
	local f = folder
	assert(f, "Net used before init")
	return f:FindFirstChild(name) :: RemoteEvent
end

-- Studio only. Nil outside Studio.
function Net.debugRemote(name: string): RemoteEvent?
	local f = debugFolder
	if f == nil then
		return nil
	end
	return f:FindFirstChild(name) :: RemoteEvent?
end

-- Studio only: rate limit a debug message from a client. DebugDriver uses this.
function Net.allowDebug(player: Player, remote: string): boolean
	return RunService:IsStudio() and allow(player, remote)
end

function Net.fireAll(name: Remotes.RemoteName, ...: any)
	Net.remote(name):FireAllClients(...)
end

function Net.fire(name: Remotes.RemoteName, player: Player, ...: any)
	Net.remote(name):FireClient(player, ...)
end

-- Validated intents since the last drain, in arrival order.
function Net.drainIntents(): { Intent }
	local out = intents
	intents = {}
	return out
end

function Net.gazeOf(userId: number): number?
	return gaze[userId]
end

return Net
