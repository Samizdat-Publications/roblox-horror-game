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

----------------------------------------------------------------------------------------
-- SEAM: Core.Validate, Core.RateLimit
-- Local payload checks and token buckets until the Core modules land.

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function inRange(v: any, lo: number, hi: number): boolean
	return finite(v) and v >= lo and v <= hi
end

local INTENT_KINDS: { [string]: boolean } = {
	ToggleLantern = true,
	ToggleMotor = true,
	Cast = true,
	ReelHold = true,
	CutLine = true,
	CatchDecision = true,
	Bank = true,
	RefillOil = true,
	Knock = true,
	Wave = true,
	BailHold = true,
	GhostBell = true,
	Callout = true,
}

local CALLOUTS: { [string]: boolean } = {}
for _, phrase in Config.Callouts do
	CALLOUTS[phrase] = true
end

-- Returns a clean Intent or nil.
local function validateIntent(player: Player, kind: any, num: any, flag: any, text: any): Intent?
	if type(kind) ~= "string" or not INTENT_KINDS[kind] then
		return nil
	end
	if num ~= nil and not inRange(num, 0, 1) then
		return nil
	end
	if flag ~= nil and type(flag) ~= "boolean" then
		return nil
	end
	if text ~= nil and (type(text) ~= "string" or #text > 32) then
		return nil
	end
	if kind == "Callout" and (text == nil or not CALLOUTS[text]) then
		return nil
	end
	if kind == "Cast" and num == nil then
		return nil
	end
	if (kind == "ReelHold" or kind == "BailHold" or kind == "CatchDecision") and flag == nil then
		return nil
	end
	return {
		kind = kind :: any,
		player = player.UserId,
		num = num,
		flag = flag,
		text = text,
	}
end

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

local LIMITS: { [string]: { rate: number, burst: number } } = {
	BoatInput = { rate = Config.Net.boatHz, burst = Config.Net.boatHz },
	Gaze = { rate = Config.Net.gazeHz, burst = Config.Net.gazeHz },
	Intent = { rate = Config.Net.intentPerSec, burst = Config.Net.intentBurst },
	Lobby = { rate = 2, burst = 4 },
	Cosmetic = { rate = 2, burst = 4 },
	DebugBot = { rate = 10, burst = 10 },
	DebugCamera = { rate = 10, burst = 10 },
}

local function allow(player: Player, remote: string): boolean
	local lim = LIMITS[remote]
	local now = os.clock()
	local per = buckets[player]
	if per == nil then
		per = {}
		buckets[player] = per
	end
	local b = per[remote]
	if b == nil then
		b = { tokens = lim.burst, last = now }
		per[remote] = b
	end
	b.tokens = math.min(lim.burst, b.tokens + (now - b.last) * lim.rate)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end
-- END SEAM
----------------------------------------------------------------------------------------

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

function Net.handlers.BoatInput(player: Player, throttle: any, steer: any): boolean
	if not allow(player, "BoatInput") or not inRange(throttle, -1, 1) or not inRange(steer, -1, 1) then
		count(Net.stats.rejected, "BoatInput")
		return false
	end
	if not BoatService.setHelmInput(player, throttle, steer) then
		count(Net.stats.rejected, "BoatInput")
		return false
	end
	count(Net.stats.accepted, "BoatInput")
	return true
end

function Net.handlers.Gaze(player: Player, yaw: any): boolean
	if not allow(player, "Gaze") or not inRange(yaw, -math.pi - 0.01, math.pi + 0.01) then
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
	local intent = validateIntent(player, kind, num, flag, text)
	if intent == nil then
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

-- Lobby and Cosmetic have no service until S4 and S5: type check, rate limit, drop.
function Net.handlers.Lobby(player: Player, action: any, value: any): boolean
	local ok = allow(player, "Lobby")
		and type(action) == "string"
		and #action <= 24
		and (value == nil or type(value) == "string" or finite(value))
	count(if ok then Net.stats.accepted else Net.stats.rejected, "Lobby")
	return ok
end

function Net.handlers.Cosmetic(player: Player, slot: any, id: any): boolean
	local ok = allow(player, "Cosmetic")
		and type(slot) == "string"
		and type(id) == "string"
		and #slot <= 16
		and #id <= 24
	count(if ok then Net.stats.accepted else Net.stats.rejected, "Cosmetic")
	return ok
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
