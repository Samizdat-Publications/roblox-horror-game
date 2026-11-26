--[[
The rule-following crew bot for the bot-night simulations.

It plays the way a careful crew would: rows (never the motor) out of the dock light to a
spot in the Shallows, everyone fishes, every catch is checked against the Field Guide
(lantern lit), wrong fish go back, and the crew rows home to bank when the hold is full,
when the hold covers the rest of the quota, or when dawn is close. It refills the
lantern at the dock when the oil is under half. Reactions have human-ish delays.

    local crewbot = require("./crewbot")
    local out = crewbot.runNight(core, cfg, params, { stopAtQuota = true })

`core` is a table of loaded Core modules (Night, BoatModel, LakeMap, Rng, WrongCatch).
]]

local crewbot = {}

export type NightRun = {
	metAt: number?, -- real seconds into the night when the quota was first met
	cleared: boolean?, -- nil when the run stopped early at the quota
	banked: number,
	quota: number,
	trips: number,
	caught: number,
	keptWrong: number,
	thrownBack: number,
	seconds: number, -- simulated seconds
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

function crewbot.runNight(core: any, cfg: any, params: any, opts: any?): NightRun
	local o = opts or {}
	local Night, BoatModel, LakeMap, Rng, WrongCatch =
		core.Night, core.BoatModel, core.LakeMap, core.Rng, core.WrongCatch
	local s = Night.new(cfg, params)
	local rng = Rng.fork(Rng.new(params.seed), "bot")
	local L = cfg.Lake
	local dt = cfg.Night.tick
	local boat = BoatModel.new(L.dockEnd, 0)

	local mode = "ToSpot"
	local spot = nil
	local atDockTimer = 0
	local trips, thrownBack = 0, 0
	local metAt = nil

	local function pickSpot()
		local p = LakeMap.randomPointInZone(cfg, rng, "Shallows", { shoreMargin = 25, avoidSafe = true })
		-- Keep a little clear of the light's edge so drift never carries the boat back in.
		while p ~= nil and LakeMap.dist(p, L.dockEnd) < L.safeRadius + 20 do
			p = LakeMap.randomPointInZone(cfg, rng, "Shallows", { shoreMargin = 25, avoidSafe = true })
		end
		spot = p or { x = 0, z = L.dockEnd.z + 150 }
	end
	pickSpot()

	-- Per player: reaction timers and what the bot believes it is holding.
	local bots = {}
	for _, id in params.playerIds do
		bots[id] = { wait = Rng.range(rng, 0.5, 2), held = false, lastPhase = "Idle", think = 0 }
	end

	local players = {}
	for i, id in params.playerIds do
		players[i] = { id = id, seated = true, helm = i == 1, inWater = false, gazeYaw = 0, bookOpen = false }
	end

	local lanternOnWanted = true
	local seconds = 0
	local maxTicks = math.ceil(cfg.Night.realSeconds / dt) + 5

	for _ = 1, maxTicks do
		local intents = {}
		local function intent(kind, player, num, flag)
			table.insert(intents, { kind = kind, player = player, num = num, flag = flag })
		end
		local lead = params.playerIds[1]

		-- Lantern: lit whenever it can be.
		if lanternOnWanted and not s.lantern.on and s.lantern.oil > 0 and s.lantern.forcedFor <= 0 then
			intent("ToggleLantern", lead)
		end

		-- How many fish are already committed (in the hold or on a line past the bite).
		local inFlight = 0
		local holdValue = 0
		for _, c in s.hold do
			holdValue += if c.wrong then c.points * cfg.Fishing.wrongPointsMult else c.points
		end
		for _, id in params.playerIds do
			local ph = s.crew[id].fishing.phase
			if ph == "Reeling" or ph == "Deciding" then
				inFlight += 1
			end
		end
		local quotaLeft = s.quota.target - s.quota.banked
		local distHome = LakeMap.dist(boat.pos, L.dockEnd)
		local timeLeft = s.clock.length - s.clock.elapsed
		local tripHome = distHome / cfg.Boat.rowSpeed + 6
		local covers = quotaLeft > 0 and holdValue >= quotaLeft
		local enoughCommitted = (#s.hold + inFlight >= s.holdMax) or covers
		local dawnClose = #s.hold > 0 and timeLeft < tripHome + 10
		local wantHome = (#s.hold >= s.holdMax) or covers or dawnClose
		local stopCasting = enoughCommitted or dawnClose or mode ~= "Fishing"

		-- Crew and boat.
		local throttle, steer = 0, 0
		if mode == "Fishing" then
			if wantHome then
				-- Cut lines still waiting for a bite; let fights and choices finish.
				for _, id in params.playerIds do
					local ph = s.crew[id].fishing.phase
					if ph == "Waiting" or ph == "Bite" then
						intent("CutLine", id)
					end
				end
				if inFlight == 0 then
					mode = "ToDock"
				end
			end
		end
		local target = if mode == "ToSpot" then spot elseif mode == "ToDock" then L.dockEnd else nil
		if target ~= nil then
			local d = LakeMap.dist(boat.pos, target)
			local arrive = if mode == "ToDock" then L.bankRadius * 0.5 else 6
			if d > arrive then
				local err = wrap(angleTo(boat.pos, target) - boat.heading)
				steer = math.clamp(err * 2, -1, 1)
				local brake = math.clamp((d - arrive) / 10, 0.2, 1)
				throttle = if math.abs(err) < 0.6 then brake else 0.25
			elseif BoatModel.speedOf(boat) < cfg.Fishing.castSpeedLimit * 0.6 then
				if mode == "ToSpot" then
					mode = "Fishing"
				else
					mode = "AtDock"
					atDockTimer = Rng.range(rng, 2, 4)
				end
			end
		elseif mode == "AtDock" then
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

		-- Each angler.
		for _, id in params.playerIds do
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
			if f.phase == "Idle" then
				if not stopCasting and b.wait <= 0 and s.boatSpeed < cfg.Fishing.castSpeedLimit then
					intent("Cast", id, Rng.range(rng, 0.6, 1))
					b.wait = Rng.range(rng, 1.0, 2.5)
				end
			elseif f.phase == "Bite" then
				if b.wait <= 0 then
					intent("ReelHold", id, nil, true)
					b.held = true
				end
			elseif f.phase == "Reeling" then
				-- Thumbs update five times a second: hold below the band's middle, let go above.
				b.think -= dt
				if b.think <= 0 then
					b.think = 0.2
					local mid = f.center
					local want = f.tension < mid
					if want ~= b.held then
						intent("ReelHold", id, nil, want)
						b.held = want
					end
				end
			elseif f.phase == "Deciding" then
				if b.wait <= 0 then
					local c = f.catch
					local keep = c ~= nil and WrongCatch.matchesBook(cfg, c.species, c.traits)
					if not keep then
						thrownBack += 1
					end
					intent("CatchDecision", id, nil, keep)
					b.wait = 99
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
			if e.kind == "QuotaMet" and metAt == nil then
				metAt = s.quota.metAt
			end
		end
		if metAt ~= nil and o.stopAtQuota then
			break
		end
		if Night.result(s) ~= nil then
			break
		end
	end

	local result = Night.result(s)
	return {
		metAt = metAt,
		cleared = if result then result.cleared else nil,
		banked = s.quota.banked,
		quota = s.quota.target,
		trips = trips,
		caught = s.caught,
		keptWrong = s.keptWrong,
		thrownBack = thrownBack,
		seconds = seconds,
	}
end

return crewbot
