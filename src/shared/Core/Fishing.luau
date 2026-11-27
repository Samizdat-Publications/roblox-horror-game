--!strict
-- One player's line: cast, wait, bite, the reel bar, snap and slack, then the catch held
-- up for a keep or throw back choice. The hold and the quota belong to Night.
--
-- Reel bar: holding the reel raises tension, letting go lowers it. A safe band wanders
-- along the bar; progress fills while tension is inside it and drains outside. Full
-- tension for snapAfter seconds snaps the line; zero tension for slackAfter seconds
-- loses the fish. Bigger fish have a narrower, faster band and fill slower.

local Types = require(script.Parent.Types)
local Rng = require(script.Parent.Rng)
local FishTable = require(script.Parent.FishTable)
local WrongCatch = require(script.Parent.WrongCatch)

type Event = Types.Event
type Catch = Types.Catch
type FishingPhase = Types.FishingPhase

export type FishState = {
	phase: FishingPhase,
	timer: number, -- Waiting: until the bite. Bite: window left. Deciding: time to decide.
	held: boolean, -- the reel button is down
	-- What the cast rolled with, for the hook set.
	zone: string,
	hour: number,
	wrongChance: number,
	wrongTier: number,
	forceWrong: boolean,
	forceSpecies: string?, -- set before the hook: this species bites, true to the book (the Finale's order)
	-- The fish on the line (Reeling and Deciding).
	catch: Catch?,
	tension: number,
	center: number, -- middle of the safe band
	width: number,
	drift: number, -- signed band speed
	progress: number,
	overTime: number,
	slackTime: number,
	expired: boolean, -- Deciding ran out: Night keeps the fish
}

export type CastOpts = {
	boatSpeed: number,
	safe: boolean, -- boat is in the dock light
	zone: string,
	hour: number,
	wrongChance: number?,
	wrongTier: number?,
	forceWrong: boolean?,
	biteMult: number?, -- Lucky Lure shortens the wait
}

local Fishing = {}

Fishing.START_TENSION = 0.35
Fishing.FLIP_PER_SEC = 0.7 -- chance per second that the band changes direction

function Fishing.new(): FishState
	return {
		phase = "Idle",
		timer = 0,
		held = false,
		zone = "Open",
		hour = 22,
		wrongChance = 0,
		wrongTier = 1,
		forceWrong = false,
		catch = nil,
		tension = 0,
		center = 0.5,
		width = 0.3,
		drift = 0,
		progress = 0,
		overTime = 0,
		slackTime = 0,
		expired = false,
	}
end

local function sizeIndex(points: number): number
	return math.clamp(math.floor(points), 1, 3)
end

local function reset(f: FishState)
	f.phase = "Idle"
	f.timer = 0
	f.catch = nil
	f.tension = 0
	f.progress = 0
	f.overTime = 0
	f.slackTime = 0
	f.expired = false
	f.forceWrong = false
	f.forceSpecies = nil
end

local function lost(f: FishState, player: number, why: string): { Event }
	reset(f)
	return { { kind = "HookLost", player = player, data = { why = why } } }
end

-- The safe band, clamped to 0..1, for the view.
function Fishing.band(f: FishState): (number, number)
	return math.max(0, f.center - f.width / 2), math.min(1, f.center + f.width / 2)
end

-- Reeling right now (makes noise).
function Fishing.isReeling(f: FishState): boolean
	return f.phase == "Reeling" and f.held
end

-- Casts if the line is idle, the boat is nearly still, and the boat is outside the dock
-- light (fish do not bite in the beacon's light unless cfg.Fishing.biteInDockLight).
function Fishing.cast(cfg: any, f: FishState, rng: Rng.RngState, player: number, power: number, o: CastOpts): { Event }
	local F = cfg.Fishing
	if f.phase ~= "Idle" then
		return {}
	end
	if o.boatSpeed >= F.castSpeedLimit then
		return { { kind = "HookLost", player = player, data = { why = "Moving" } } }
	end
	if o.safe and not F.biteInDockLight then
		return { { kind = "HookLost", player = player, data = { why = "DockLight" } } }
	end
	reset(f)
	f.phase = "Waiting"
	f.timer = Rng.range(rng, F.biteMin, F.biteMax) * (o.biteMult or 1)
	f.zone = o.zone
	f.hour = o.hour
	f.wrongChance = o.wrongChance or 0
	f.wrongTier = o.wrongTier or 1
	f.forceWrong = o.forceWrong == true
	return { { kind = "CastOut", player = player, data = { power = math.clamp(power, 0, 1) } } }
end

-- Rolls the fish when the hook is set.
local function hook(cfg: any, f: FishState, rng: Rng.RngState)
	local F = cfg.Fishing
	local species = FishTable.pick(cfg, rng, f.zone, f.hour)
	local points = cfg.Fish[species].points
	local wrong = f.forceWrong or (f.wrongChance > 0 and Rng.next(rng) < f.wrongChance)
	if f.forceSpecies ~= nil and cfg.Fish[f.forceSpecies] ~= nil then
		-- The draws above are still taken so the stream does not shift.
		species = f.forceSpecies :: string
		points = cfg.Fish[species].points
		wrong = false
	end
	local traits, tier
	if wrong then
		traits = (WrongCatch.mutate(cfg, rng, species, f.wrongTier))
		tier = math.clamp(math.floor(f.wrongTier), 1, 3)
	else
		traits = WrongCatch.bookTraits(cfg, species)
		tier = 0
	end
	f.catch = { species = species, points = points, wrong = wrong, tier = tier, traits = traits }
	local i = sizeIndex(points)
	f.phase = "Reeling"
	f.tension = Fishing.START_TENSION
	f.width = F.zoneWidth[i]
	f.center = 0.5
	f.drift = if Rng.next(rng) < 0.5 then -F.zoneDrift[i] else F.zoneDrift[i]
	f.progress = 0
	f.overTime = 0
	f.slackTime = 0
end

-- The reel button. Pressing it during the bite window sets the hook.
function Fishing.reel(cfg: any, f: FishState, rng: Rng.RngState, held: boolean)
	f.held = held
	if held and f.phase == "Bite" then
		hook(cfg, f, rng)
	end
end

function Fishing.cut(f: FishState, player: number): { Event }
	if f.phase == "Waiting" or f.phase == "Bite" or f.phase == "Reeling" then
		return lost(f, player, "Cut")
	end
	return {}
end

-- A rule or a death takes the line away (no event if there was nothing on it).
function Fishing.interrupt(f: FishState, player: number, why: string): { Event }
	if f.phase == "Idle" then
		return {}
	end
	if f.phase == "Deciding" then
		reset(f)
		return {}
	end
	return lost(f, player, why)
end

-- The catch for the keep or throw back choice; the line goes idle.
function Fishing.take(f: FishState): Catch?
	if f.phase ~= "Deciding" then
		return nil
	end
	local c = f.catch
	reset(f)
	return c
end

-- What a client may see of a catch: never the wrong flag or the tier.
function Fishing.publicCatch(c: Catch): { [string]: any }
	return { species = c.species, points = c.points, traits = WrongCatch.copyTraits(c.traits) }
end

function Fishing.step(cfg: any, f: FishState, dt: number, rng: Rng.RngState, player: number): { Event }
	local F = cfg.Fishing
	if f.phase == "Waiting" then
		f.timer -= dt
		if f.timer <= 0 then
			f.phase = "Bite"
			f.timer = F.biteWindow
			return { { kind = "Bite", player = player } }
		end
	elseif f.phase == "Bite" then
		f.timer -= dt
		if f.timer <= 0 then
			return lost(f, player, "Missed")
		end
	elseif f.phase == "Reeling" then
		local c = f.catch :: Catch
		local i = sizeIndex(c.points)
		f.tension = math.clamp(f.tension + (if f.held then F.tensionUp else -F.tensionDown) * dt, 0, 1)
		-- The band wanders and bounces off the ends of the bar.
		if Rng.next(rng) < Fishing.FLIP_PER_SEC * dt then
			f.drift = -f.drift
		end
		local half = f.width / 2
		f.center += f.drift * dt
		if f.center < half then
			f.center = half
			f.drift = math.abs(f.drift)
		elseif f.center > 1 - half then
			f.center = 1 - half
			f.drift = -math.abs(f.drift)
		end
		local lo, hi = Fishing.band(f)
		if f.tension >= lo and f.tension <= hi then
			f.progress = math.min(1, f.progress + F.progressUp[i] * dt)
		else
			f.progress = math.max(0, f.progress - F.progressDown * dt)
		end
		f.overTime = if f.tension >= 1 then f.overTime + dt else 0
		f.slackTime = if f.tension <= 0 then f.slackTime + dt else 0
		if f.overTime >= F.snapAfter then
			return lost(f, player, "Snap")
		elseif f.slackTime >= F.slackAfter then
			return lost(f, player, "Slack")
		elseif f.progress >= 1 then
			f.phase = "Deciding"
			f.timer = F.decideSeconds
			f.held = false
			return { { kind = "Caught", player = player, data = { catch = Fishing.publicCatch(c) } } }
		end
	elseif f.phase == "Deciding" then
		f.timer -= dt
		if f.timer <= 0 then
			f.expired = true
		end
	end
	return {}
end

return Fishing
