--[[
The crew bot for the bot-night simulations, with three policies:

  "follow" (default): the careful crew. Rows (never the motor) to a spot in the Shallows,
      everyone fishes, every catch is checked against the Field Guide and wrong fish go
      back, the crew rows home to bank when the hold is full, covers the rest of the quota,
      or dawn is close, and refills the lantern under half oil. It answers every rule
      correctly, amendments included (it reads tonight's page: params.amendments):
        Hum: stop reeling, motor off, lantern out (or lit when amended), hold still.
        Neighbor: lantern out until it is gone, keep (or row) away from it, never wave,
          ignore callouts; a false beacon: stay put until it goes out.
        Knocking: one crewmate answers with the right count; everyone bails a leak.
        Watcher: one crewmate keeps it at the edge of sight (or stares it down when
          amended), the rest look away.
  "blind": fishes and banks the same way but ignores every cue: keeps every catch, the
      lantern always lit, never knocks, never bails, eyes wherever their seat faces.
  "greedy": keeps every catch (wrong fish included) and always runs the motor; it answers
      the rules like "follow" otherwise (it cuts the motor for the Hum because it must).

Reactions have human-ish delays. The bot only uses what a crew could know: the events,
the view, and the rule book (params.amendments).

    local crewbot = require("./crewbot")
    local out = crewbot.runNight(core, cfg, params, { policy = "follow", stopAtQuota = false })

`core` is a table of loaded Core modules (Night, BoatModel, LakeMap, Rng, WrongCatch, Director).
]]

local crewbot = {}

export type NightRun = {
	metAt: number?, -- real seconds into the night when the quota was first met
	cleared: boolean?, -- nil when the run stopped early at the quota
	reason: string?,
	banked: number,
	quota: number,
	trips: number,
	caught: number,
	keptWrong: number,
	thrownBack: number,
	seconds: number, -- simulated seconds
	deaths: { { t: number, rule: string, player: number } },
	wiped: boolean,
	realSpawns: { number }, -- night times of real (director) scares
	spawnRules: { string },
	fakes: number,
	passes: number,
	fails: number,
	timeline: { { t: number, banked: number } }, -- banked points after each bank
}

local function angleTo(from, to): number
	return math.atan2(to.x - from.x, to.z - from.z)
end

local function wrap(a: number): number
	a = a % (2 * math.pi)
	if a > math.pi then
		a -= 2 * math.pi
	end
	return a
end

local ANSWERS = { AnswerTwo = 2, AnswerOne = 1, AnswerNone = 0 }

function crewbot.runNight(core: any, cfg: any, params: any, opts: any?): NightRun
	local o = opts or {}
	local policy = o.policy or "follow"
	local follows = policy ~= "blind" -- answers the rules
	local keepsAll = policy ~= "follow"
	local motors = policy == "greedy"
	local Night, BoatModel, LakeMap, Rng, WrongCatch =
		core.Night, core.BoatModel, core.LakeMap, core.Rng, core.WrongCatch
	local s = Night.new(cfg, params)
	local rng = Rng.fork(Rng.new(params.seed), "bot:" .. policy)
	local L = cfg.Lake
	local dt = cfg.Night.tick
	local boat = BoatModel.new(L.dockEnd, 0)
	local amend = params.amendments or {}

	local mode = "ToSpot"
	local spot = nil
	local atDockTimer = 0
	local trips, thrownBack = 0, 0
	local metAt = nil
	local deaths = {}
	local passes, fails = 0, 0
	local timeline = {}
	-- The rule contract, checked from the events: one cue, then exactly one outcome, and
	-- never a fail before the cue's warning time (director rules; Wrong Catch can overlap).
	local open = {} -- entity -> { at, warn, outcomes }
	local contractChecks, contractBad = 0, {}

	local function pickSpot()
		local p = LakeMap.randomPointInZone(cfg, rng, "Shallows", { shoreMargin = 25, avoidSafe = true })
		while p ~= nil and LakeMap.dist(p, L.dockEnd) < L.safeRadius + 20 do
			p = LakeMap.randomPointInZone(cfg, rng, "Shallows", { shoreMargin = 25, avoidSafe = true })
		end
		spot = p or { x = 0, z = L.dockEnd.z + 150 }
	end
	pickSpot()

	local bots = {}
	for i, id in params.playerIds do
		bots[id] = { wait = Rng.range(rng, 0.5, 2), held = false, lastPhase = "Idle", think = 0, seat = i, drift = 0 }
	end
	local players = {}
	for i, id in params.playerIds do
		players[i] = { id = id, seated = true, helm = i == 1, inWater = false, gazeYaw = 0, bookOpen = false }
	end

	-- What the crew knows of the rules out there (from events).
	local known = {} -- entity -> { variant, pos, form, only, stage, round, react, knocksLeft, knockWait, ended }

	local seconds = 0
	local maxTicks = math.ceil(cfg.Night.realSeconds / dt) + 5

	for _ = 1, maxTicks do
		local intents = {}
		local function intent(kind, player, num, flag)
			table.insert(intents, { kind = kind, player = player, num = num, flag = flag })
		end
		local alive = {}
		for _, id in params.playerIds do
			if s.crew[id].alive then
				table.insert(alive, id)
			end
		end
		local lead = alive[1]
		if lead == nil then
			break
		end

		-- Rule reactions (follow and greedy).
		for _, k in known do
			k.react -= dt
		end
		local hum = known.Hum
		local humOn = follows and hum ~= nil and not hum.ended and hum.react <= 0
		local nb = known.Neighbor
		local nbOn = follows and nb ~= nil and not nb.ended and nb.react <= 0
		local kn = known.Knocking
		local wt = known.Watcher
		local wtOn = follows and wt ~= nil and not wt.ended and wt.react <= 0

		-- Lantern.
		local wantLantern = true
		if humOn then
			wantLantern = (hum.variant == "LanternLit")
		end
		if nbOn and nb.form == "Boat" then
			wantLantern = false
		end
		local lightIt = wantLantern and not s.lantern.on and s.lantern.oil > 0 and s.lantern.forcedFor <= 0
		if lightIt or (not wantLantern and s.lantern.on) then
			intent("ToggleLantern", lead)
		end

		-- Motor.
		local wantMotor = motors and not humOn
		if wantMotor ~= s.motorOn then
			intent("ToggleMotor", lead)
		end

		-- Knocking: answer with the book's count once the window opens.
		if follows and kn ~= nil and not kn.ended and kn.stage == "Window" and kn.react <= 0 then
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
		local bailing = follows and s.flood > 0
		for _, id in alive do
			if bailing ~= s.crew[id].bailing then
				intent("BailHold", id, nil, bailing)
			end
		end

		-- Hold and quota bookkeeping.
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
		local distHome = LakeMap.dist(boat.pos, L.dockEnd)
		local timeLeft = s.clock.length - s.clock.elapsed
		local speed = if motors then cfg.Boat.motorSpeed else cfg.Boat.rowSpeed
		local tripHome = distHome / speed + 6
		local covers = quotaLeft > 0 and holdValue >= quotaLeft
		local enoughCommitted = (#s.hold + inFlight >= s.holdMax) or covers
		local dawnClose = #s.hold > 0 and timeLeft < tripHome + 10
		local wantHome = (#s.hold >= s.holdMax) or covers or dawnClose
		local stopCasting = enoughCommitted or dawnClose or mode ~= "Fishing" or humOn or bailing

		-- Boat.
		local throttle, steer = 0, 0
		if mode == "Fishing" and wantHome then
			for _, id in alive do
				local ph = s.crew[id].fishing.phase
				if ph == "Waiting" or ph == "Bite" then
					intent("CutLine", id)
				end
			end
			if inFlight == 0 then
				mode = "ToDock"
			end
		end
		local hold = humOn or bailing or (nbOn and nb.form == "FalseBeacon")
		local away = nil
		if nbOn and nb.form == "Boat" and nb.pos ~= nil then
			local d = LakeMap.dist(boat.pos, nb.pos)
			if d < cfg.Rules.Neighbor.holdDist + 50 or nb.variant == "NoWaveRowAway" then
				-- Row away from it: straight away, else off to one side (never toward it).
				local a0 = angleTo(nb.pos, boat.pos)
				for _, da in { 0, 0.6, -0.6, 1.2, -1.2, 1.5, -1.5 } do
					local p = { x = boat.pos.x + math.sin(a0 + da) * 60, z = boat.pos.z + math.cos(a0 + da) * 60 }
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
			elseif mode == "ToSpot" then spot
			elseif mode == "ToDock" then L.dockEnd
			else nil
		if target ~= nil then
			local d = LakeMap.dist(boat.pos, target)
			local arrive = if away then 0 elseif mode == "ToDock" then L.bankRadius * 0.5 else 6
			if d > arrive then
				local err = wrap(angleTo(boat.pos, target) - boat.heading)
				steer = math.clamp(err * 2, -1, 1)
				local brake = math.clamp((d - arrive) / 10, 0.2, 1)
				throttle = if away
					then (if math.abs(err) < 0.8 then 1 else 0) -- turn in place first
					elseif math.abs(err) < 0.6 then brake
					else 0.25
			elseif BoatModel.speedOf(boat) < cfg.Fishing.castSpeedLimit * 0.6 and not away then
				if mode == "ToSpot" then
					mode = "Fishing"
				else
					mode = "AtDock"
					atDockTimer = Rng.range(rng, 2, 4)
				end
			end
		elseif mode == "AtDock" and not hold then
			atDockTimer -= dt
			if atDockTimer <= 0 then
				if #s.hold > 0 then
					intent("Bank", lead)
					trips += 1
				end
				if s.lantern.oil < 0.5 and s.lantern.refills > 0 then
					intent("RefillOil", lead)
				end
				pickSpot()
				mode = "ToSpot"
			end
		end
		if away and mode == "Fishing" then
			mode = "ToSpot" -- moved off the spot: settle again wherever it ends
			spot = { x = away.x, z = away.z }
		end

		-- Each angler.
		for _, id in alive do
			local b = bots[id]
			local f = s.crew[id].fishing
			if f.phase ~= b.lastPhase then
				if f.phase == "Bite" then
					b.wait = Rng.range(rng, 0.3, 0.9)
				elseif f.phase == "Deciding" then
					b.wait = Rng.range(rng, 1.0, 2.5)
				elseif f.phase == "Idle" then
					b.wait = Rng.range(rng, 1.0, 2.5)
					b.held = false
				end
				b.lastPhase = f.phase
			end
			b.wait -= dt
			if s.crew[id].bailing then
				continue
			end
			if f.phase == "Idle" then
				if not stopCasting and b.wait <= 0 and s.boatSpeed < cfg.Fishing.castSpeedLimit then
					intent("Cast", id, Rng.range(rng, 0.6, 1))
					b.wait = Rng.range(rng, 1.0, 2.5)
				end
			elseif f.phase == "Bite" then
				if b.wait <= 0 and not humOn then
					intent("ReelHold", id, nil, true)
					b.held = true
				end
			elseif f.phase == "Reeling" then
				if humOn then
					if b.held then
						intent("ReelHold", id, nil, false)
						b.held = false
					end
				else
					b.think -= dt
					if b.think <= 0 then
						b.think = 0.2
						local want = f.tension < f.center
						if want ~= b.held then
							intent("ReelHold", id, nil, want)
							b.held = want
						end
					end
				end
			elseif f.phase == "Deciding" then
				if b.wait <= 0 then
					local c = f.catch
					local keep = keepsAll or (c ~= nil and WrongCatch.matchesBook(cfg, c.species, c.traits))
					if not keep then
						thrownBack += 1
					end
					intent("CatchDecision", id, nil, keep)
					b.wait = 99
				end
			end
		end

		-- Eyes: seats face ahead, ahead, port, starboard, with a slow wander.
		for _, p in players do
			local b = bots[p.id]
			b.drift = math.clamp(b.drift + Rng.range(rng, -0.3, 0.3) * dt, -0.6, 0.6)
			local seatFace = ({ 0, 0, -math.pi / 2, math.pi / 2 })[b.seat] or 0
			p.gazeYaw = wrap(boat.heading + seatFace + b.drift)
		end
		if wtOn and wt.pos ~= nil then
			local bearing = angleTo(boat.pos, wt.pos)
			local eyes = if wt.only ~= nil and s.crew[wt.only].alive then wt.only else lead
			for _, p in players do
				if p.id == eyes then
					p.gazeYaw = wrap(bearing + (if wt.variant == "StareItDown" then 0 else 0.8))
				else
					p.gazeYaw = wrap(bearing + math.pi)
				end
			end
		end

		BoatModel.step(cfg, boat, dt, throttle, steer, { motorOn = s.motorOn })
		local events = Night.step(s, {
			dt = dt,
			boat = BoatModel.toObs(boat),
			players = players,
			intents = intents,
		})
		seconds += dt
		for _, e in events do
			local kind = e.kind
			if kind == "Banked" then
				table.insert(timeline, { t = s.clock.elapsed, banked = s.quota.banked })
			end
			if kind == "QuotaMet" and metAt == nil then
				metAt = s.quota.metAt
			elseif kind == "EntityCue" and e.entity ~= nil then
				if e.entity ~= "WrongCatch" then
					contractChecks += 1
					local prev = open[e.entity]
					if prev ~= nil and prev.outcomes == 0 then
						table.insert(contractBad, e.entity .. ": a new cue before an outcome")
					end
					open[e.entity] = { at = s.clock.elapsed, warn = e.data.warn or 0, outcomes = 0 }
				end
				known[e.entity] = {
					variant = e.data.variant,
					pos = e.data.pos,
					form = e.data.form,
					only = e.only,
					stage = "Cue",
					react = Rng.range(rng, 0.6, 1.5),
					ended = false,
				}
			elseif kind == "EntityStage" and e.entity ~= nil and known[e.entity] ~= nil then
				local k = known[e.entity]
				if e.data.stage ~= k.stage then
					k.stage = e.data.stage
					if e.data.stage == "Window" or e.data.stage == "Cue" then
						k.knocksLeft = nil
						k.react = Rng.range(rng, 0.6, 1.5)
					end
				end
				if e.data.stage == "Cooldown" then
					known[e.entity] = nil
				end
			elseif kind == "EntityMoved" and e.entity ~= nil and known[e.entity] ~= nil then
				known[e.entity].pos = e.data.pos
			elseif (kind == "EntityPass" or kind == "EntityFail") and e.entity ~= nil then
				local rec = open[e.entity]
				if e.entity ~= "WrongCatch" then
					contractChecks += 1
					if rec == nil then
						table.insert(contractBad, e.entity .. ": an outcome with no cue")
					else
						rec.outcomes += 1
						if rec.outcomes > 1 then
							table.insert(contractBad, e.entity .. ": two outcomes")
						end
						if kind == "EntityFail" and s.clock.elapsed - rec.at < rec.warn - 0.15 then
							table.insert(
								contractBad,
								string.format(
									"%s: fail %.1f s after the cue, warn %.1f",
									e.entity,
									s.clock.elapsed - rec.at,
									rec.warn
								)
							)
						end
					end
				end
				if known[e.entity] ~= nil then
					known[e.entity].ended = true
				end
				if e.entity ~= "WrongCatch" then
					if kind == "EntityPass" then
						passes += 1
					else
						fails += 1
					end
				end
			elseif kind == "PlayerDied" then
				table.insert(deaths, { t = s.clock.elapsed, rule = e.data.rule, player = e.player })
			end
		end
		if metAt ~= nil and o.stopAtQuota then
			break
		end
		if Night.result(s) ~= nil then
			break
		end
	end

	local realSpawns, spawnRules, fakes = {}, {}, 0
	for _, entry in core.Director.log(s.director) do
		if entry.kind == "Spawn" then
			table.insert(realSpawns, entry.t)
			table.insert(spawnRules, entry.id)
		elseif entry.kind == "Fakeout" then
			fakes += 1
		end
	end
	local result = Night.result(s)
	local anyAlive = false
	for _, id in params.playerIds do
		if s.crew[id].alive then
			anyAlive = true
		end
	end
	return {
		metAt = metAt,
		cleared = if result then result.cleared else nil,
		reason = if s.phase == "Failed"
			then (if anyAlive then "QuotaShort" elseif s.sunk then "Sunk" else "CrewLost")
			else nil,
		banked = s.quota.banked,
		quota = s.quota.target,
		trips = trips,
		caught = s.caught,
		keptWrong = s.keptWrong,
		thrownBack = thrownBack,
		seconds = seconds,
		deaths = deaths,
		wiped = not anyAlive,
		realSpawns = realSpawns,
		spawnRules = spawnRules,
		fakes = fakes,
		passes = passes,
		fails = fails,
		timeline = timeline,
		amendments = amend,
		contractChecks = contractChecks,
		contractBad = contractBad,
	}
end

return crewbot
