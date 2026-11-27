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

`core` is a table of loaded Core modules (Night, BoatModel, LakeMap, Rng, FishMutations, Director).
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

-- Every rule id (Types.RuleId): a death with one of these as its rule came from a rule.
local RULE_IDS = { Hum = true, WrongCatch = true, Neighbor = true, Knocking = true, Watcher = true, Finale = true }

local ANSWERS = { AnswerTwo = 2, AnswerOne = 1, AnswerNone = 0 }

function crewbot.runNight(core: any, cfg: any, params: any, opts: any?): NightRun
	local o = opts or {}
	local policy = o.policy or "follow"
	local follows = policy ~= "blind" -- answers the rules
	local keepsAll = policy ~= "follow"
	local motors = policy == "greedy"
	local Night, BoatModel, LakeMap, Rng, FishMutations =
		core.Night, core.BoatModel, core.LakeMap, core.Rng, core.FishMutations
	local s = Night.new(cfg, params)
	local rng = Rng.fork(Rng.new(params.seed), "bot:" .. policy)
	local L = cfg.Lake
	local dt = cfg.Night.tick
	local boat = BoatModel.new(L.dockEnd, 0)
	local amend = params.amendments or {}

	local mode = "ToSpot"
	local spot = nil

	-- Night 5 (the Finale): the owner wants one Steeple Cat, and they bite only by the
	-- steeple after 3 AM. The follow and greedy crews fish the Shallows, then bank, refill and
	-- take the motor out to the steeple's near edge to be there by 3 AM, fish for the cat
	-- (keeping a slot for it), and at the bell motor straight home, steering clear of every
	-- Neighbor boat and false beacon, never stopping. The blind crew does none of this.
	local finaleNight = false
	for _, r in params.rules do
		if r == "Finale" then
			finaleNight = true
		end
	end
	finaleNight = finaleNight and follows
	local F = cfg.Rules.Finale
	local need = F.needSpecies
	local hourSec = cfg.Night.realSeconds / (cfg.Night.endHour - cfg.Night.startHour)
	local catAt = ((cfg.Fish[need].afterHour or cfg.Night.startHour) - cfg.Night.startHour) * hourSec
	local bellAt = (F.hour - cfg.Night.startHour) * hourSec
	local leaveAt = catAt - (o.steepleLead or 30)
	local steepleSpot = nil
	do
		local st, dk = L.steeple, L.dockEnd
		local dx, dz = dk.x - st.x, dk.z - st.z
		local d = math.sqrt(dx * dx + dz * dz)
		local r = L.steepleRadius - 15
		steepleSpot = { x = st.x + dx / d * r, z = st.z + dz / d * r }
	end
	local steeplePlan = false -- heading to (or at) the steeple
	local finaleOn = false
	local hazards = {} -- Finale hazards by id: { form, pos }
	local failReason = nil
	local fdbg = {} -- night 5 timings for tuning: steepleAt, catAt, bellDist, homeAt
	local atDockTimer = 0
	local trips, thrownBack = 0, 0
	local metAt = nil
	local deaths = {}
	local passes, fails = 0, 0
	local timeline = {}
	-- The rule contract, checked from the events: one cue, then exactly one outcome, and
	-- never a fail before the cue's warning time (director rules; Wrong Catch can overlap).
	-- A director rule is paused in the dock light, so the warning time counts only the
	-- seconds the boat spent outside the light since the cue (`ran`), and no director rule
	-- may reach its outcome while the boat is in the light (except rules let go by the
	-- Finale's bell).
	local open = {} -- entity -> { at, warn, outcomes, ran }
	local contractChecks, contractBad = 0, {}
	-- Every player a rule kills must have received that rule's cue: the last EntityCue of
	-- that rule went to everyone, or to that player (`only`). Deaths not from a rule (the
	-- water) are not checked.
	local cueTo = {} -- entity -> { only = PlayerId? }, the rule's latest cue
	local cueChecks, cueBad = 0, {}

	-- A Shallows spot, kept with the chance a bite comes there (Fishing.dockFactor): a crew
	-- learns that fish do not bite near the dock and fishes further out.
	local Fishing = core.Fishing
	local function pickSpot()
		local p = nil
		for _ = 1, 40 do
			p = LakeMap.randomPointInZone(cfg, rng, "Shallows", { shoreMargin = 25, avoidSafe = true })
			if p ~= nil and LakeMap.dist(p, L.dockEnd) >= L.safeRadius + 20 then
				local chance = if Fishing then Fishing.dockFactor(cfg, p) else 1
				if Rng.next(rng) < chance then
					break
				end
			end
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
		if nbOn and nb.form == "Boat" then
			wantLantern = false
		end
		if humOn then
			-- The Hum outranks the Neighbor: it is short and it ends the moment you comply.
			wantLantern = (hum.variant == "LanternLit")
		end
		local lightIt = wantLantern and not s.lantern.on and s.lantern.oil > 0 and s.lantern.forcedFor <= 0
		if lightIt or (not wantLantern and s.lantern.on) then
			intent("ToggleLantern", lead)
		end

		-- Motor.
		local steepleRun = finaleNight
			and (
				finaleOn
				or (steeplePlan and mode == "ToSpot" and spot ~= nil and LakeMap.dist(boat.pos, spot) > 60)
				or (s.clock.elapsed >= leaveAt and not steeplePlan and (mode == "ToDock" or mode == "ToSpot"))
			)
		local wantMotor = (motors or steepleRun) and not humOn
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
		local hasCat = false
		if finaleNight then
			if steeplePlan and mode == "Fishing" and fdbg.steepleAt == nil then
				fdbg.steepleAt = s.clock.elapsed
			end
			if finaleOn and fdbg.bellDist == nil then
				fdbg.bellDist = LakeMap.dist(boat.pos, L.dockEnd)
				fdbg.bellMode = mode
			end
			for _, list in { s.hold, s.cooler } do
				for _, c in list do
					if c.species == need and FishMutations.matchesBook(cfg, c.species, c.traits) then
						hasCat = true
						fdbg.catAt = fdbg.catAt or s.clock.elapsed
					end
				end
			end
			local now = s.clock.elapsed
			if steeplePlan then
				-- At the steeple: stay until the bell; keep a slot for the cat.
				wantHome = false
				local full = #s.hold + inFlight >= s.holdMax
				stopCasting = mode ~= "Fishing"
					or humOn
					or bailing
					or finaleOn
					or (hasCat and (full or now >= bellAt - 4))
			elseif now >= leaveAt or quotaLeft <= 0 then
				wantHome = true -- bank, refill, then out to the steeple
				stopCasting = true
			end
		end

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
		if nbOn and nb.form == "Boat" and nb.pos ~= nil and not humOn then
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
		-- In the dock light every director rule is paused (Night.rulePaused), so waiting
		-- there never ends one. The crew banks and refills, then leaves: against a paused
		-- Hum it creeps out below the Hum's still speed and holds once outside; against a
		-- Neighbor it goes about its business (rowing away if it is close).
		local creep = false
		if LakeMap.isSafe(cfg, boat.pos) and not finaleOn and follows then
			if humOn then
				hold = bailing
				creep = true
			elseif nbOn then
				hold = bailing
			end
		end
		local target = if away
			then away
			elseif hold then nil
			elseif mode == "ToSpot" then spot
			elseif mode == "ToDock" then L.dockEnd
			else nil
		local exiting = false
		if creep and mode ~= "AtDock" then
			-- A paused Hum: out of the light by the shortest way (the bank can wait), unless
			-- already at the dock, then bank first (AtDock) and creep out toward the spot.
			local dHome = LakeMap.dist(boat.pos, L.dockEnd)
			if mode == "ToDock" and dHome > L.bankRadius then
				local a = angleTo(L.dockEnd, boat.pos)
				local r = L.safeRadius + 4
				target = { x = L.dockEnd.x + math.sin(a) * r, z = L.dockEnd.z + math.cos(a) * r }
				exiting = true
			end
		end
		if target ~= nil then
			local d = LakeMap.dist(boat.pos, target)
			local arrive = if away or exiting then 0 elseif mode == "ToDock" then L.bankRadius * 0.5 else 6
			if d > arrive then
				local err = wrap(angleTo(boat.pos, target) - boat.heading)
				steer = math.clamp(err * 2, -1, 1)
				local brake = math.clamp((d - arrive) / 10, 0.2, 1)
				throttle = if away
					then (if math.abs(err) < 0.8 then 1 else 0) -- turn in place first
					elseif math.abs(err) < 0.6 then brake
					else 0.25
				if creep then
					throttle = math.min(throttle, 0.1) -- under Boat.stillSpeed on the oars
				end
			elseif BoatModel.speedOf(boat) < cfg.Fishing.castSpeedLimit * 0.6 and not away and not exiting then
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
				if finaleNight and (s.clock.elapsed >= leaveAt or quotaLeft - holdValue <= 0) then
					spot = { x = steepleSpot.x, z = steepleSpot.z }
					steeplePlan = true
				end
			end
		end
		if away and mode == "Fishing" then
			mode = "ToSpot" -- moved off the spot: settle again wherever it ends
			spot = { x = away.x, z = away.z }
		end
		-- Settled where fish hardly bite (pushed toward the dock): idle lines move on.
		if mode == "Fishing" and not away and not steeplePlan and inFlight == 0 and Fishing ~= nil then
			if Fishing.dockFactor(cfg, boat.pos) < 0.5 then
				local idle = true
				for _, id in alive do
					if s.crew[id].fishing.phase ~= "Idle" and s.crew[id].fishing.phase ~= "Waiting" then
						idle = false
					end
				end
				if idle then
					for _, id in alive do
						if s.crew[id].fishing.phase == "Waiting" then
							intent("CutLine", id)
						end
					end
					pickSpot()
					mode = "ToSpot"
				end
			end
		end

		-- The bell: lines in, motor home, around every hazard, never stopping.
		if finaleOn then
			mode = "Finale"
			for _, id in alive do
				local ph = s.crew[id].fishing.phase
				if ph == "Waiting" or ph == "Bite" or ph == "Reeling" then
					intent("CutLine", id)
				end
			end
			if not LakeMap.isSafe(cfg, boat.pos) then
				local home = angleTo(boat.pos, L.dockEnd)
				local vx, vz = math.sin(home), math.cos(home)
				for _, h in hazards do
					local d = LakeMap.dist(boat.pos, h.pos)
					local reach = if h.form == "Boat" then 130 else 110
					if d < reach and d > 1e-3 then
						local w = 2.5 * (reach - d) / reach
						vx += (boat.pos.x - h.pos.x) / d * w
						vz += (boat.pos.z - h.pos.z) / d * w
					end
				end
				local err = wrap(math.atan2(vx, vz) - boat.heading)
				steer = math.clamp(err * 2, -1, 1)
				throttle = 1
			else
				throttle, steer = 0, 0
			end
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
					local keep = keepsAll or (c ~= nil and FishMutations.matchesBook(cfg, c.species, c.traits))
					if keep and steeplePlan and not hasCat and c ~= nil and c.species ~= need then
						-- Keep a slot for the owner's fish.
						keep = #s.hold < s.holdMax - 1
					end
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
		if o.trace then
			o.trace(s, mode, boat, events)
		end
		if not s.safe or s.finaleStarted then
			for _, rec in open do
				if rec.outcomes == 0 then
					rec.ran += dt
				end
			end
		end
		for _, e in events do
			local kind = e.kind
			if kind == "Banked" then
				table.insert(timeline, { t = s.clock.elapsed, banked = s.quota.banked })
			end
			if kind == "QuotaMet" and metAt == nil then
				metAt = s.quota.metAt
			elseif kind == "EntityMoved" and e.entity == "Finale" then
				local id = e.data.hazard
				if id ~= nil then
					if e.data.gone then
						hazards[id] = nil
					else
						hazards[id] = { form = e.data.form, pos = e.data.pos }
					end
				end
			elseif kind == "EntityCue" and e.entity ~= nil then
				if e.entity == "Finale" and finaleNight then
					finaleOn = true
				end
				if e.entity ~= "WrongCatch" then
					contractChecks += 1
					local prev = open[e.entity]
					if prev ~= nil and prev.outcomes == 0 then
						table.insert(contractBad, e.entity .. ": a new cue before an outcome")
					end
					open[e.entity] = { at = s.clock.elapsed, warn = e.data.warn or 0, outcomes = 0, ran = 0 }
				end
				cueTo[e.entity] = { only = e.only }
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
						if kind == "EntityFail" and rec.ran < rec.warn - 0.15 then
							table.insert(
								contractBad,
								string.format(
									"%s: fail %.1f s of rule time after the cue, warn %.1f",
									e.entity,
									rec.ran,
									rec.warn
								)
							)
						end
						local letGo = e.data ~= nil and e.data.endedBy == "Finale"
						if e.entity ~= "Finale" and s.safe and not s.finaleStarted and not letGo then
							table.insert(contractBad, e.entity .. ": an outcome while paused in the dock light")
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
				local rule = e.data.rule
				if RULE_IDS[rule] then
					cueChecks += 1
					local c = cueTo[rule]
					if c == nil then
						table.insert(cueBad, string.format("%s: took player %s with no cue", rule, tostring(e.player)))
					elseif c.only ~= nil and c.only ~= e.player then
						table.insert(
							cueBad,
							string.format(
								"%s: took player %s, but its cue went only to player %s",
								rule,
								tostring(e.player),
								tostring(c.only)
							)
						)
					end
				end
				table.insert(deaths, { t = s.clock.elapsed, rule = e.data.rule, player = e.player, text = e.data.text })
			elseif kind == "NightFailed" then
				failReason = e.data.reason
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
		cueChecks = cueChecks,
		cueBad = cueBad,
		result = result,
		finalePassed = s.finalePassed,
		finaleDebug = fdbg,
		failReason = failReason,
	}
end

return crewbot
