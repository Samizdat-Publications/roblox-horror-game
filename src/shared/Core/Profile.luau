--!strict
-- A player's saved progress (docs/DESIGN.md, Progress and cosmetics).
--
--   Profile.default(cfg) -> ProfileData
--   Profile.migrate(cfg, raw) -> (ProfileData, status)   -- any stored value -> a valid profile
--       status: "New" (nothing stored), "Current", "Migrated", "Repaired", "Future"
--   Profile.recordNight(cfg, p, info) -> { UnlockId }     -- after each night, per player
--   Profile.recordRun(cfg, p, info) -> { UnlockId }       -- when a run ends
--   Profile.unlocked(cfg, p, slot, id) -> boolean
--   Profile.equip(cfg, p, slot, id) -> boolean            -- refused unless unlocked
--   Profile.validate(cfg, p)                              -- equipped items must be unlocked
--   Profile.merge(cfg, a, b) -> ProfileData               -- never loses progress (saves use it)
--   Profile.serialize(p) -> table                         -- a plain copy for the store
--   Profile.UNLOCKS                                       -- the unlock rules, for the UI
--
-- Saved per player: nights cleared, runs cleared, best Endless night, fish banked, scares
-- survived, cosmetics. Cosmetics are earned by playing, never bought (Config.Cosmetics):
--   lantern: Amber (from the start), Bone White (clear a run), Marsh Green (clear night 3
--     on Nightmare), Blue Hour (reach Endless night 5: the fifth Endless night, night 10).
--   paint: Bare Wood (from the start), Oxblood (100 fish banked), Hull Black (25 scares
--     survived), Robin Egg (clear a run solo).
--   hat: None (from the start), Bucket Hat (clear night 1), Sou'wester (clear a run).
-- Unlocks are sticky: once earned they stay, even if a rule changes later.
-- A save from a newer SAVE_VERSION is kept as read ("Future"): SaveLogic never writes over it.

local Profile = {}

export type Stats = {
	nightsCleared: number,
	runsCleared: number,
	bestEndlessNight: number, -- highest Endless night cleared (0 = none)
	fishBanked: number, -- fish (not points) banked in nights the crew cleared or not
	scaresSurvived: number,
	nightmareRunsCleared: number,
	soloRunsCleared: number,
}

export type ProfileData = {
	version: number,
	stats: Stats,
	flags: { [string]: boolean }, -- one-off achievements: NightmareNight3, ...
	unlocked: { [string]: { [string]: boolean } }, -- slot -> id -> true
	equipped: { [string]: string }, -- slot -> id
}

export type UnlockRule = {
	slot: string,
	id: string,
	text: string, -- how to earn it, for the UI
	check: (p: ProfileData) -> boolean,
}

export type NightInfo = {
	cleared: boolean,
	mode: string, -- "Story" | "Endless"
	difficulty: string,
	night: number,
	fishBanked: number?,
	scaresSurvived: number?,
}

export type RunInfo = {
	cleared: boolean, -- a Story run cleared
	mode: string,
	difficulty: string,
	solo: boolean, -- played by one player all the way
	bestNight: number?, -- Endless: highest night cleared
}

Profile.ENDLESS_FROM = 6 -- matches Core.Run
Profile.BLUE_HOUR_NIGHT = 10 -- the fifth Endless night

local STAT_KEYS = {
	"nightsCleared",
	"runsCleared",
	"bestEndlessNight",
	"fishBanked",
	"scaresSurvived",
	"nightmareRunsCleared",
	"soloRunsCleared",
}

Profile.UNLOCKS = {
	{
		slot = "lantern",
		id = "Amber",
		text = "From the start.",
		check = function(_p)
			return true
		end,
	},
	{
		slot = "lantern",
		id = "BoneWhite",
		text = "Clear a run.",
		check = function(p)
			return p.stats.runsCleared >= 1
		end,
	},
	{
		slot = "lantern",
		id = "MarshGreen",
		text = "Clear night 3 on Nightmare.",
		check = function(p)
			return p.flags.NightmareNight3 == true
		end,
	},
	{
		slot = "lantern",
		id = "BlueHour",
		text = "Reach the fifth Endless night.",
		check = function(p)
			return p.stats.bestEndlessNight >= Profile.BLUE_HOUR_NIGHT
		end,
	},
	{
		slot = "paint",
		id = "BareWood",
		text = "From the start.",
		check = function(_p)
			return true
		end,
	},
	{
		slot = "paint",
		id = "Oxblood",
		text = "Bank 100 fish.",
		check = function(p)
			return p.stats.fishBanked >= 100
		end,
	},
	{
		slot = "paint",
		id = "HullBlack",
		text = "Survive 25 scares.",
		check = function(p)
			return p.stats.scaresSurvived >= 25
		end,
	},
	{
		slot = "paint",
		id = "RobinEgg",
		text = "Clear a run on your own.",
		check = function(p)
			return p.stats.soloRunsCleared >= 1
		end,
	},
	{
		slot = "hat",
		id = "None",
		text = "From the start.",
		check = function(_p)
			return true
		end,
	},
	{
		slot = "hat",
		id = "BucketHat",
		text = "Clear night 1.",
		check = function(p)
			return p.stats.nightsCleared >= 1
		end,
	},
	{
		slot = "hat",
		id = "Souwester",
		text = "Clear a run.",
		check = function(p)
			return p.stats.runsCleared >= 1
		end,
	},
} :: { UnlockRule }

local function slots(cfg: any): { string }
	local out: { string } = {}
	for slot in cfg.Cosmetics do
		table.insert(out, slot)
	end
	table.sort(out)
	return out
end

local function inList(list: { string }, v: any): boolean
	for _, x in list do
		if x == v then
			return true
		end
	end
	return false
end

local function count(n: any): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.max(0, math.floor(n))
end

function Profile.default(cfg: any): ProfileData
	local stats: Stats = {
		nightsCleared = 0,
		runsCleared = 0,
		bestEndlessNight = 0,
		fishBanked = 0,
		scaresSurvived = 0,
		nightmareRunsCleared = 0,
		soloRunsCleared = 0,
	}
	local unlocked: { [string]: { [string]: boolean } } = {}
	local equipped: { [string]: string } = {}
	for _, slot in slots(cfg) do
		unlocked[slot] = {}
		equipped[slot] = cfg.Cosmetics[slot][1]
	end
	local p: ProfileData =
		{ version = cfg.SAVE_VERSION, stats = stats, flags = {}, unlocked = unlocked, equipped = equipped }
	Profile.refresh(cfg, p)
	return p
end

-- Applies every unlock rule (sticky). Returns the ids newly unlocked, "slot.id".
function Profile.refresh(cfg: any, p: ProfileData): { string }
	local new: { string } = {}
	for _, rule in Profile.UNLOCKS do
		local items = cfg.Cosmetics[rule.slot]
		if items ~= nil and inList(items, rule.id) then
			p.unlocked[rule.slot] = p.unlocked[rule.slot] or {}
			if not p.unlocked[rule.slot][rule.id] and rule.check(p) then
				p.unlocked[rule.slot][rule.id] = true
				table.insert(new, rule.slot .. "." .. rule.id)
			end
		end
	end
	return new
end

function Profile.unlocked(cfg: any, p: ProfileData, slot: string, id: string): boolean
	local items = cfg.Cosmetics[slot]
	return items ~= nil and inList(items, id) and p.unlocked[slot] ~= nil and p.unlocked[slot][id] == true
end

-- Equipped items must exist and be unlocked; anything else goes back to the slot's first item.
function Profile.validate(cfg: any, p: ProfileData)
	for _, slot in slots(cfg) do
		local id = p.equipped[slot]
		if type(id) ~= "string" or not Profile.unlocked(cfg, p, slot, id) then
			p.equipped[slot] = cfg.Cosmetics[slot][1]
		end
	end
	for slot in p.equipped do
		if cfg.Cosmetics[slot] == nil then
			p.equipped[slot] = nil
		end
	end
end

function Profile.equip(cfg: any, p: ProfileData, slot: string, id: string): boolean
	if not Profile.unlocked(cfg, p, slot, id) then
		return false
	end
	p.equipped[slot] = id
	return true
end

-- Version 0 is anything saved before SAVE_VERSION existed: a flat table of stats
-- (nightsCleared, runsCleared, bestEndless, fishBanked, scaresSurvived) and an optional
-- `cosmetics` table { lantern, paint, hat } of equipped ids.
local MIGRATIONS: { [number]: (raw: { [string]: any }) -> { [string]: any } } = {
	[0] = function(raw)
		local cos = if type(raw.cosmetics) == "table" then raw.cosmetics else {}
		return {
			version = 1,
			stats = {
				nightsCleared = raw.nightsCleared,
				runsCleared = raw.runsCleared,
				bestEndlessNight = raw.bestEndlessNight or raw.bestEndless,
				fishBanked = raw.fishBanked,
				scaresSurvived = raw.scaresSurvived,
			},
			flags = {},
			unlocked = {},
			equipped = { lantern = cos.lantern, paint = cos.paint, hat = cos.hat },
		}
	end,
}

-- Rebuilds a valid profile from a current-version table, keeping what is sane.
local function repair(cfg: any, raw: { [string]: any }): (ProfileData, boolean)
	local p = Profile.default(cfg)
	local fixed = false
	local stats = if type(raw.stats) == "table" then raw.stats else {}
	if type(raw.stats) ~= "table" then
		fixed = true
	end
	for _, k in STAT_KEYS do
		local v = stats[k]
		if v ~= nil and count(v) ~= v then
			fixed = true
		end
		(p.stats :: any)[k] = count(v)
	end
	if type(raw.flags) == "table" then
		for k, v in raw.flags do
			if type(k) == "string" and v == true then
				p.flags[k] = true
			end
		end
	end
	if type(raw.unlocked) == "table" then
		for _, slot in slots(cfg) do
			local got = raw.unlocked[slot]
			if type(got) == "table" then
				for id, v in got do
					if v == true and inList(cfg.Cosmetics[slot], id) then
						p.unlocked[slot][id] = true
					end
				end
			end
		end
	end
	Profile.refresh(cfg, p)
	if type(raw.equipped) == "table" then
		for _, slot in slots(cfg) do
			local id = raw.equipped[slot]
			if type(id) == "string" then
				p.equipped[slot] = id
			end
		end
	end
	local before = table.clone(p.equipped)
	Profile.validate(cfg, p)
	for slot, id in before do
		if p.equipped[slot] ~= id then
			fixed = true
		end
	end
	return p, fixed
end

function Profile.migrate(cfg: any, raw: any): (ProfileData, string)
	if raw == nil then
		return Profile.default(cfg), "New"
	end
	if type(raw) ~= "table" then
		return Profile.default(cfg), "Repaired"
	end
	local version = if type(raw.version) == "number" then math.floor(raw.version) else 0
	if version > cfg.SAVE_VERSION then
		-- Written by a newer server. Read what we understand; never save over it.
		local p = repair(cfg, raw)
		p.version = version
		return p, "Future"
	end
	local data: { [string]: any } = raw
	local migrated = false
	while version < cfg.SAVE_VERSION do
		local step = MIGRATIONS[version]
		if step == nil then
			return Profile.default(cfg), "Repaired"
		end
		data = step(data)
		version = if type(data.version) == "number" then data.version else version + 1
		migrated = true
	end
	local p, fixed = repair(cfg, data)
	p.version = cfg.SAVE_VERSION
	if migrated then
		return p, "Migrated"
	end
	return p, if fixed then "Repaired" else "Current"
end

-- After a night, for one player who was in the crew. Returns new unlocks.
function Profile.recordNight(cfg: any, p: ProfileData, info: NightInfo): { string }
	p.stats.fishBanked += count(info.fishBanked)
	p.stats.scaresSurvived += count(info.scaresSurvived)
	if info.cleared then
		p.stats.nightsCleared += 1
		if info.mode == "Endless" then
			p.stats.bestEndlessNight = math.max(p.stats.bestEndlessNight, count(info.night))
		elseif info.difficulty == "Nightmare" and info.night == 3 then
			p.flags.NightmareNight3 = true
		end
	end
	return Profile.refresh(cfg, p)
end

-- When a run ends. Returns new unlocks.
function Profile.recordRun(cfg: any, p: ProfileData, info: RunInfo): { string }
	if info.mode == "Endless" then
		p.stats.bestEndlessNight = math.max(p.stats.bestEndlessNight, count(info.bestNight))
	elseif info.cleared then
		p.stats.runsCleared += 1
		if info.difficulty == "Nightmare" then
			p.stats.nightmareRunsCleared += 1
		end
		if info.solo then
			p.stats.soloRunsCleared += 1
		end
	end
	return Profile.refresh(cfg, p)
end

-- Two copies of one player's profile (this session's and the stored one): the larger of
-- every stat, every flag and unlock from either, `a`'s equipped items where still valid.
function Profile.merge(cfg: any, a: ProfileData, b: ProfileData): ProfileData
	local out = Profile.default(cfg)
	for _, k in STAT_KEYS do
		(out.stats :: any)[k] = math.max(count((a.stats :: any)[k]), count((b.stats :: any)[k]))
	end
	for _, src in { b, a } do
		for k, v in src.flags do
			if v == true then
				out.flags[k] = true
			end
		end
		for slot, ids in src.unlocked do
			if out.unlocked[slot] ~= nil then
				for id, v in ids do
					if v == true and inList(cfg.Cosmetics[slot], id) then
						out.unlocked[slot][id] = true
					end
				end
			end
		end
	end
	Profile.refresh(cfg, out)
	for slot, id in b.equipped do
		out.equipped[slot] = id
	end
	for slot, id in a.equipped do
		out.equipped[slot] = id
	end
	Profile.validate(cfg, out)
	out.version = cfg.SAVE_VERSION
	return out
end

-- A plain deep copy (what goes to the store).
function Profile.serialize(p: ProfileData): { [string]: any }
	local unlocked: { [string]: { [string]: boolean } } = {}
	for slot, ids in p.unlocked do
		unlocked[slot] = table.clone(ids)
	end
	return {
		version = p.version,
		stats = table.clone(p.stats) :: any,
		flags = table.clone(p.flags),
		unlocked = unlocked,
		equipped = table.clone(p.equipped),
	}
end

return Profile
