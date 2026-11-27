--!strict
-- Shape and range checks for every client-to-server remote (docs/ARCHITECTURE.md, Remotes).
-- Every check takes the raw, untrusted arguments and returns (true, cleaned) or
-- (false, reason). Net calls these before rate limits and distance checks.
-- Nothing here trusts a type annotation: arguments arrive as `any` from the network.

local Types = require(script.Parent.Types)

local Validate = {}

local MAX_TEXT = 32

-- Every IntentKind and what its optional fields must hold.
-- "num01": num in 0..1. "flag": flag must be a boolean. "callout": text from cfg.Callouts.
Validate.INTENTS = {
	ToggleLantern = "none",
	ToggleMotor = "none",
	Cast = "num01",
	ReelHold = "flag",
	CutLine = "none",
	CatchDecision = "flag",
	Bank = "none",
	RefillOil = "none",
	Knock = "none",
	Wave = "none",
	BailHold = "flag",
	GhostBell = "none",
	Callout = "callout",
} :: { [string]: string }

-- Lobby actions and the value each takes. "none", "difficulty", "mode", "supply", "flag",
-- "flag01" (the number 0 or 1: the client sends these as numbers).
-- Book: the rulebook or Field Guide is open (1) or closed (0). Touch: plays on a touch screen.
-- Title: the host leaves the end card. Hello: a client asks for the lobby state and profile.
Validate.LOBBY = {
	Start = "none",
	Ready = "flag",
	Difficulty = "difficulty",
	Mode = "mode",
	Supply = "supply",
	Retry = "none",
	Book = "flag01",
	Touch = "flag01",
	Title = "none",
	Hello = "none",
} :: { [string]: string }

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
Validate.isFinite = isFinite

local function isShortString(v: any): boolean
	return type(v) == "string" and #v > 0 and #v <= MAX_TEXT
end

local function listHas(list: { any }, v: any): boolean
	for _, x in list do
		if x == v then
			return true
		end
	end
	return false
end

-- BoatInput(throttle, steer): both finite numbers, clamped to -1..1.
function Validate.BoatInput(_cfg: any, throttle: any, steer: any): (boolean, any)
	if not isFinite(throttle) or not isFinite(steer) then
		return false, "BoatInput needs two finite numbers"
	end
	return true, { throttle = math.clamp(throttle, -1, 1), steer = math.clamp(steer, -1, 1) }
end

-- Gaze(yaw): a finite number within a few turns, wrapped to [-pi, pi).
function Validate.Gaze(_cfg: any, yaw: any): (boolean, any)
	if not isFinite(yaw) or math.abs(yaw) > 4 * math.pi then
		return false, "Gaze needs a finite yaw in radians"
	end
	local wrapped = (yaw + math.pi) % (2 * math.pi) - math.pi
	return true, wrapped
end

-- Intent(kind, num?, flag?, text?): returns an Intent without `player` (Net adds it).
function Validate.Intent(cfg: any, kind: any, num: any, flag: any, text: any): (boolean, any)
	if not isShortString(kind) then
		return false, "Intent kind must be a short string"
	end
	local shape = Validate.INTENTS[kind]
	if shape == nil then
		return false, "unknown Intent kind"
	end
	local out: { [string]: any } = { kind = kind }
	if shape == "num01" then
		if not isFinite(num) or num < 0 or num > 1 then
			return false, kind .. " needs num in 0..1"
		end
		out.num = num
	elseif shape == "flag" then
		if type(flag) ~= "boolean" then
			return false, kind .. " needs a boolean flag"
		end
		out.flag = flag
	elseif shape == "callout" then
		if not isShortString(text) or not listHas(cfg.Callouts, text) then
			return false, "Callout needs a phrase id from Config.Callouts"
		end
		out.text = text
	end
	return true, out
end

-- Lobby(action, value?)
function Validate.Lobby(cfg: any, action: any, value: any): (boolean, any)
	if not isShortString(action) then
		return false, "Lobby action must be a short string"
	end
	local shape = Validate.LOBBY[action]
	if shape == nil then
		return false, "unknown Lobby action"
	end
	if shape == "none" then
		return true, { action = action }
	elseif shape == "flag" then
		if type(value) ~= "boolean" then
			return false, action .. " needs a boolean"
		end
	elseif shape == "flag01" then
		if value ~= 0 and value ~= 1 then
			return false, action .. " needs 0 or 1"
		end
	elseif shape == "difficulty" then
		if not isShortString(value) or cfg.Difficulty[value] == nil then
			return false, "unknown difficulty"
		end
	elseif shape == "mode" then
		if value ~= "Story" and value ~= "Endless" then
			return false, "unknown mode"
		end
	elseif shape == "supply" then
		if not isShortString(value) or cfg.Supplies[value] == nil then
			return false, "unknown supply"
		end
	end
	return true, { action = action, value = value }
end

-- Cosmetic(slot, id): slot is a key of cfg.Cosmetics and id one of its entries.
-- (Whether the player has unlocked it is Profile's call, not this one.)
function Validate.Cosmetic(cfg: any, slot: any, id: any): (boolean, any)
	if not isShortString(slot) or not isShortString(id) then
		return false, "Cosmetic needs a slot and an id"
	end
	local list = cfg.Cosmetics[slot]
	if list == nil then
		return false, "unknown cosmetic slot"
	end
	if not listHas(list, id) then
		return false, "unknown cosmetic id"
	end
	return true, { slot = slot, id = id }
end

-- Dispatch by remote name. Server-to-client remotes are never accepted from a client.
function Validate.remote(cfg: any, name: any, ...: any): (boolean, any)
	if name == "BoatInput" then
		return Validate.BoatInput(cfg, ...)
	elseif name == "Gaze" then
		return Validate.Gaze(cfg, ...)
	elseif name == "Intent" then
		return Validate.Intent(cfg, ...)
	elseif name == "Lobby" then
		return Validate.Lobby(cfg, ...)
	elseif name == "Cosmetic" then
		return Validate.Cosmetic(cfg, ...)
	end
	return false, "not a client-to-server remote"
end

-- Keeps the Types import meaningful for strict mode readers: the cleaned Intent shape.
export type CleanIntent = {
	kind: Types.IntentKind,
	num: number?,
	flag: boolean?,
	text: string?,
}

return Validate
