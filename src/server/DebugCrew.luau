--!strict
-- Studio only: a server crew bot for whole-run scenarios (DebugRun: full_run, finale).
-- A port of the "follow" policy of tools/sim/crewbot.luau to the live server: every tick it
-- reads the raw night (NightService.debugState) and the real boat (BoatService), steers the
-- real boat through BoatService.setHelmInput, sets each player's gaze, and hands Night its
-- intents through NightService.debugCrew (they skip Net: the remote paths are covered by the
-- S2 and S3 scenarios, and a five-night run would trip the per-player rate limits).
--
-- It fishes the Shallows, checks every catch against the Field Guide (WrongCatch.matchesBook
-- on the visible traits), banks when the hold is full or covers the quota, refills the
-- lantern, and answers every rule as tonight's page says (amendments included): the Hum,
-- the Neighbor (lantern out, keep or row away, never wave), the Knocking (the right count),
-- the Watcher (one player at the edge of sight or staring it down, the rest look away), and
-- bails a leak. Night 5: out to the steeple by 3 AM for the Steeple Cat, and at the bell
-- straight home on the motor around every Neighbor boat and false beacon, never stopping.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local LakeMap = require(Core:WaitForChild("LakeMap")) :: any
local WrongCatch = require(Core:WaitForChild("FishMutations")) :: any
local Rng = require(Core:WaitForChild("Rng")) :: any

local server = script.Parent
local NightService = require(server:WaitForChild("NightService"))
local BoatService = require(server:WaitForChild("BoatService"))

local DebugCrew = {}

local ANSWERS = { AnswerTwo = 2, AnswerOne = 1, AnswerNone = 0 }

local rnd = Random.new(20261126)

local function angleTo(from: any, to: any): number
	return math.atan2(to.x - from.x, to.z - from.z)
end

local function wrap(a: number): number
	a = a % (2 * math.pi)
	if a > math.pi then
		a -= 2 * math.pi
	end
	return a
end

local function range(lo: number, hi: number): number
	return rnd:NextNumber(lo, hi)
end

local active = false
local subscribed = false
local bot: any = nil -- per night memory, rebuilt when the night changes
local stats: { [string]: any } = {}

local function freshBot(s: any): any
	local cfg = s.cfg
	local L = cfg.Lake
	local F = cfg.Rules.Finale
	local length = s.clock.length
	local hourSec = length / (cfg.Night.endHour - cfg.Night.startHour)
	local need = F.needSpecies
	local catAt = ((cfg.Fish[need].afterHour or cfg.Night.startHour) - cfg.Night.startHour) * hourSec
	local bellAt = (F.hour - cfg.Night.startHour) * hourSec
	local st, dk = L.steeple, L.dockEnd
	local dx, dz = dk.x - st.x, dk.z - st.z
	local d = math.sqrt(dx * dx + dz * dz)
	local r = L.steepleRadius - 15
	local b = {
		state = s,
		mode = "ToSpot",
		spot = nil :: any,
		finaleNight = table.find(s.params.rules, "Finale") ~= nil,
		need = need,
		catAt = catAt,
		bellAt = bellAt,
		leaveAt = catAt - 40,
		steepleSpot = { x = st.x + dx / d * r, z = st.z + dz / d * r },
		steeplePlan = false,
		finaleOn = false,
		hazards = {} :: { [number]: any },
		atDockTimer = 0,
		known = {} :: { [string]: any },
		anglers = {} :: { [number]: any },
	}
	return b
end

local function pickSpot(b: any)
	local cfg = b.state.cfg
	local L = cfg.Lake
	local r = Rng.new(rnd:NextInteger(1, 2 ^ 30))
	local q = nil
	for _ = 1, 8 do
		q = LakeMap.randomPointInZone(cfg, r, "Shallows", { shoreMargin = 25, avoidSafe = true })
		if q == nil or LakeMap.dist(q, L.dockEnd) >= L.safeRadius + 20 then
			break
		end
	end
	b.spot = q or { x = L.dockEnd.x, z = L.dockEnd.z + L.safeRadius + 55 }
end

local function onEvent(e: any)
	local b = bot
	if not active or b == nil then
		return
	end
	local kind = e.kind
	local data = e.data or {}
	if kind == "EntityMoved" and e.entity == "Finale" then
		local id = data.hazard
		if id ~= nil then
			if data.gone then
				b.hazards[id] = nil
			elseif data.pos then
				b.hazards[id] = { form = data.form, pos = data.pos }
			end
		end
	elseif kind == "EntityCue" and e.entity ~= nil then
		if e.entity == "Finale" and b.finaleNight then
			b.finaleOn = true
		end
		b.known[e.entity] = {
			variant = data.variant,
			pos = data.pos,
			form = data.form,
			only = e.only,
			stage = "Cue",
			react = range(0.6, 1.5),
			ended = false,
		}
	elseif kind == "EntityStage" and e.entity ~= nil and b.known[e.entity] ~= nil then
		local k = b.known[e.entity]
		if data.stage ~= k.stage then
			k.stage = data.stage
			if data.stage == "Window" or data.stage == "Cue" then
				k.knocksLeft = nil
				k.react = range(0.6, 1.5)
			end
		end
		if data.stage == "Cooldown" then
			b.known[e.entity] = nil
		end
	elseif kind == "EntityMoved" and e.entity ~= nil and b.known[e.entity] ~= nil then
		b.known[e.entity].pos = data.pos
	elseif (kind == "EntityPass" or kind == "EntityFail") and e.entity ~= nil then
		if b.known[e.entity] ~= nil then
			b.known[e.entity].ended = true
		end
		local key = if kind == "EntityPass" then "passes" else "fails"
		stats[key] = (stats[key] or 0) + 1
	elseif kind == "EntityStrike" then
		stats.strikes = (stats.strikes or 0) + 1
	elseif kind == "PlayerDied" then
		stats.deaths = (stats.deaths or 0) + 1
	end
end

-- One tick of the crew. Returns Night intents; steers the boat and sets gazes itself.
local function step(dt: number, s: any): { any }
	if bot == nil or bot.state ~= s then
		bot = freshBot(s)
		pickSpot(bot)
	end
	local b = bot
	local cfg = s.cfg
	local L = cfg.Lake
	local intents = {}
	local function intent(kind: string, player: number, num: number?, flag: boolean?)
		table.insert(intents, { kind = kind, player = player, num = num, flag = flag })
	end
	if s.phase == "Cleared" or s.phase == "Failed" then
		BoatService.setHelmInput(nil, 0, 0)
		return intents
	end
	local k = BoatService.kinematics()
	local boatPos = { x = k.x, z = k.z }
	local heading = k.heading
	local speed = math.abs(k.speed)

	local alive = {}
	for _, id in s.order do
		if s.crew[id].alive then
			table.insert(alive, id)
		end
	end
	local lead = alive[1]
	if lead == nil then
		BoatService.setHelmInput(nil, 0, 0)
		return intents
	end

	for _, kn in b.known do
		kn.react -= dt
	end
	local hum = b.known.Hum
	local humOn = hum ~= nil and not hum.ended and hum.react <= 0
	local nb = b.known.Neighbor
	local nbOn = nb ~= nil and not nb.ended and nb.react <= 0
	local kn = b.known.Knocking
	local wt = b.known.Watcher
	local wtOn = wt ~= nil and not wt.ended and wt.react <= 0

	-- Lantern (locked on in the finale: toggles do nothing then).
	local wantLantern = true
	if nbOn and nb.form == "Boat" then
		wantLantern = false
	end
	if humOn then
		wantLantern = hum.variant == "LanternLit"
	end
	local l = s.lantern
	local lightIt = wantLantern and not l.on and l.oil > 0 and l.forcedFor <= 0
	if not b.finaleOn and (lightIt or (not wantLantern and l.on)) then
		intent("ToggleLantern", lead)
	end

	-- Motor: only for the steeple run and the run home.
	local now = s.clock.elapsed
	local steepleRun = b.finaleNight
		and (
			b.finaleOn
			or (b.steeplePlan and b.mode == "ToSpot" and b.spot ~= nil and LakeMap.dist(boatPos, b.spot) > 60)
			or (now >= b.leaveAt and not b.steeplePlan and (b.mode == "ToDock" or b.mode == "ToSpot"))
		)
	local wantMotor = steepleRun and not humOn
	if wantMotor ~= s.motorOn then
		intent("ToggleMotor", lead)
	end

	-- Knocking.
	if kn ~= nil and not kn.ended and kn.stage == "Window" and kn.react <= 0 then
		if kn.knocksLeft == nil then
			kn.knocksLeft = ANSWERS[kn.variant] or 2
			kn.knockWait = 0
		end
		kn.knockWait -= dt
		if kn.knocksLeft > 0 and kn.knockWait <= 0 then
			intent("Knock", lead)
			kn.knocksLeft -= 1
			kn.knockWait = 0.4
		end
	end

	-- Bailing.
	local bailing = s.flood > 0
	for _, id in alive do
		if bailing ~= s.crew[id].bailing then
			intent("BailHold", id, nil, bailing)
		end
	end

	-- Hold and quota.
	local inFlight, holdValue = 0, 0
	for _, c in s.hold do
		holdValue += if c.wrong then c.points * cfg.Fishing.wrongPointsMult else c.points
	end
	for _, id in alive do
		local ph = s.crew[id].fishing.phase
		if ph == "Reeling" or ph == "Deciding" then
			inFlight += 1
		end
	end
	local quotaLeft = s.quota.target - s.quota.banked
	local distHome = LakeMap.dist(boatPos, L.dockEnd)
	local timeLeft = s.clock.length - now
	local tripHome = distHome / cfg.Boat.rowSpeed + 6
	local covers = quotaLeft > 0 and holdValue >= quotaLeft
	local enoughCommitted = (#s.hold + inFlight >= s.holdMax) or covers
	local dawnClose = #s.hold > 0 and timeLeft < tripHome + 10
	local wantHome = (#s.hold >= s.holdMax) or covers or dawnClose
	local stopCasting = enoughCommitted or dawnClose or b.mode ~= "Fishing" or humOn or bailing
	local hasCat = false
	if b.finaleNight then
		for _, list in { s.hold, s.cooler } do
			for _, c in list do
				if c.species == b.need and WrongCatch.matchesBook(cfg, c.species, c.traits) then
					hasCat = true
				end
			end
		end
		if b.steeplePlan then
			wantHome = false
			local full = #s.hold + inFlight >= s.holdMax
			stopCasting = b.mode ~= "Fishing"
				or humOn
				or bailing
				or b.finaleOn
				or (hasCat and (full or now >= b.bellAt - 4))
		elseif now >= b.leaveAt or quotaLeft <= 0 then
			wantHome = true
			stopCasting = true
		end
	end
	stats.hasCat = hasCat

	-- Boat.
	local throttle, steer = 0, 0
	if b.mode == "Fishing" and wantHome then
		for _, id in alive do
			local ph = s.crew[id].fishing.phase
			if ph == "Waiting" or ph == "Bite" then
				intent("CutLine", id)
			end
		end
		if inFlight == 0 then
			b.mode = "ToDock"
		end
	end
	local hold = humOn or bailing or (nbOn and nb.form == "FalseBeacon")
	local away = nil
	if nbOn and nb.form == "Boat" and nb.pos ~= nil and not humOn then
		local d = LakeMap.dist(boatPos, nb.pos)
		if d < cfg.Rules.Neighbor.holdDist + 50 or nb.variant == "NoWaveRowAway" then
			local a0 = angleTo(nb.pos, boatPos)
			for _, da in { 0, 0.6, -0.6, 1.2, -1.2, 1.5, -1.5 } do
				local p = { x = boatPos.x + math.sin(a0 + da) * 60, z = boatPos.z + math.cos(a0 + da) * 60 }
				if LakeMap.inside(cfg, p) and LakeMap.distanceToShore(cfg, p) >= 15 then
					away = p
					break
				end
			end
			if away == nil then
				hold = true
			end
		else
			hold = true
		end
	end
	local target = if away
		then away
		elseif hold then nil
		elseif b.mode == "ToSpot" then b.spot
		elseif b.mode == "ToDock" then L.dockEnd
		else nil
	if target ~= nil then
		local d = LakeMap.dist(boatPos, target)
		local arrive = if away then 0 elseif b.mode == "ToDock" then L.bankRadius * 0.5 else 6
		if d > arrive then
			local err = wrap(angleTo(boatPos, target) - heading)
			steer = math.clamp(-err * 2, -1, 1)
			local brake = math.clamp((d - arrive) / 10, 0.2, 1)
			throttle = if away
				then (if math.abs(err) < 0.8 then 1 else 0)
				elseif math.abs(err) < 0.6 then brake
				else 0.25
		elseif speed < cfg.Fishing.castSpeedLimit * 0.6 and not away then
			if b.mode == "ToSpot" then
				b.mode = "Fishing"
			else
				b.mode = "AtDock"
				b.atDockTimer = range(2, 4)
			end
		end
	elseif b.mode == "AtDock" and not hold then
		b.atDockTimer -= dt
		if b.atDockTimer <= 0 then
			if #s.hold > 0 then
				intent("Bank", lead)
				stats.trips = (stats.trips or 0) + 1
			end
			if l.oil < 0.5 and l.refills > 0 then
				intent("RefillOil", lead)
			end
			pickSpot(b)
			b.mode = "ToSpot"
			if b.finaleNight and (now >= b.leaveAt or quotaLeft - holdValue <= 0) then
				b.spot = { x = b.steepleSpot.x, z = b.steepleSpot.z }
				b.steeplePlan = true
			end
		end
	end
	if away and b.mode == "Fishing" then
		b.mode = "ToSpot"
		b.spot = { x = away.x, z = away.z }
	end

	-- The bell: lines in, motor home, around every hazard, never stopping.
	if b.finaleOn then
		b.mode = "Finale"
		for _, id in alive do
			local ph = s.crew[id].fishing.phase
			if ph == "Waiting" or ph == "Bite" or ph == "Reeling" then
				intent("CutLine", id)
			end
		end
		if not LakeMap.isSafe(cfg, boatPos) then
			local home = angleTo(boatPos, L.dockEnd)
			local vx, vz = math.sin(home), math.cos(home)
			for _, h in b.hazards do
				local d = LakeMap.dist(boatPos, h.pos)
				local reach = if h.form == "Boat" then 130 else 110
				if d < reach and d > 1e-3 then
					local w = 2.5 * (reach - d) / reach
					vx += (boatPos.x - h.pos.x) / d * w
					vz += (boatPos.z - h.pos.z) / d * w
				end
			end
			local err = wrap(math.atan2(vx, vz) - heading)
			steer = math.clamp(-err * 2, -1, 1)
			throttle = 1
		else
			throttle, steer = 0, 0
		end
	end
	-- The shell's steer convention: +1 turns to starboard (heading decreases), hence -err.
	BoatService.setHelmInput(nil, throttle, steer)

	-- Each angler.
	for _, id in alive do
		local a = b.anglers[id]
		if a == nil then
			a = { wait = range(0.5, 2), held = false, lastPhase = "Idle", think = 0 }
			b.anglers[id] = a
		end
		local f = s.crew[id].fishing
		if f.phase ~= a.lastPhase then
			if f.phase == "Bite" then
				a.wait = range(0.3, 0.9)
			elseif f.phase == "Deciding" then
				a.wait = range(1.0, 2.5)
			elseif f.phase == "Idle" then
				a.wait = range(1.0, 2.5)
				a.held = false
			end
			a.lastPhase = f.phase
		end
		a.wait -= dt
		if s.crew[id].bailing then
			continue
		end
		if f.phase == "Idle" then
			if not stopCasting and a.wait <= 0 and speed < cfg.Fishing.castSpeedLimit then
				intent("Cast", id, range(0.6, 1))
				a.wait = range(1.0, 2.5)
			end
		elseif f.phase == "Bite" then
			if a.wait <= 0 and not humOn then
				intent("ReelHold", id, nil, true)
				a.held = true
			end
		elseif f.phase == "Reeling" then
			if humOn then
				if a.held then
					intent("ReelHold", id, nil, false)
					a.held = false
				end
			else
				a.think -= dt
				if a.think <= 0 then
					a.think = 0.2
					local want = f.tension < f.center
					if want ~= a.held then
						intent("ReelHold", id, nil, want)
						a.held = want
					end
				end
			end
		elseif f.phase == "Deciding" then
			if a.wait <= 0 then
				local c = f.catch
				local keep = c ~= nil and WrongCatch.matchesBook(cfg, c.species, c.traits)
				if keep and b.steeplePlan and not hasCat and c ~= nil and c.species ~= b.need then
					keep = #s.hold < s.holdMax - 1
				end
				if not keep then
					stats.thrownBack = (stats.thrownBack or 0) + 1
				end
				intent("CatchDecision", id, nil, keep)
				a.wait = 99
			end
		end
	end

	-- Eyes: ahead, port, starboard, behind; the Watcher as the page says.
	local faces = { 0, -math.pi / 2, math.pi / 2, math.pi }
	for i, id in s.order do
		NightService.debugSetGaze(id, wrap(heading + (faces[i] or 0)))
	end
	if wtOn and wt.pos ~= nil then
		local bearing = angleTo(boatPos, wt.pos)
		local eyes = if wt.only ~= nil and s.crew[wt.only] and s.crew[wt.only].alive then wt.only else lead
		for _, id in s.order do
			if id == eyes then
				NightService.debugSetGaze(id, wrap(bearing + (if wt.variant == "StareItDown" then 0 else 0.8)))
			else
				NightService.debugSetGaze(id, wrap(bearing + math.pi))
			end
		end
	end
	stats.mode = b.mode
	return intents
end

-- Hands the crew to the night. `o.steeple = true` starts with the steeple plan already
-- made (the finale scenario puts the boat there with the owner's fish aboard).
function DebugCrew.start(o: { [string]: any }?)
	local opts = o or {}
	if not subscribed then
		subscribed = true
		NightService.subscribe(onEvent)
	end
	active = true
	bot = nil
	stats = {}
	NightService.debugCrew = function(dt: number, s: any): { any }?
		if not active then
			return nil
		end
		local fresh = bot == nil or bot.state ~= s
		local out = step(dt, s)
		if fresh and opts.steeple and bot then
			bot.steeplePlan = true
			bot.mode = "Fishing"
			bot.spot = { x = bot.steepleSpot.x, z = bot.steepleSpot.z }
		end
		return out
	end
end

function DebugCrew.stop()
	active = false
	bot = nil
	NightService.debugCrew = nil
	BoatService.setHelmInput(nil, 0, 0)
end

function DebugCrew.stats(): { [string]: any }
	return table.clone(stats)
end

return DebugCrew
