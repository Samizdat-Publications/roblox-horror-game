--!strict
-- Loading and saving profiles through any key-value store, with retries and backoff
-- (docs/ARCHITECTURE.md, DataService). Pure: the store and the sleep function come in, so
-- the server passes a DataStore and task.wait, and the specs pass an in-memory store that
-- can be told to fail and a sleep that only records.
--
-- The store needs GetAsync(key), SetAsync(key, value) and UpdateAsync(key, transform),
-- called with `:`; any of them may error. UpdateAsync's transform returns the new value,
-- or nil to leave the stored value alone.
--
--   SaveLogic.retry(fn, opts) -> (ok, value, attempts, err)
--   SaveLogic.load(cfg, store, key, opts) -> LoadResult
--   SaveLogic.save(cfg, store, key, profile, opts) -> SaveResult
--   SaveLogic.submitBest(store, key, bestNight, at, opts) -> SaveResult   -- ordered store
--
-- Safety rules:
--   * A load that fails every attempt gives safe defaults with canSave = false, so a
--     store outage never writes an empty profile over a real one.
--   * A save from a newer SAVE_VERSION is never written over (status "Future").
--   * A save merges with what is stored (Profile.merge): two servers, or a stale session,
--     can never lower a stat or take away an unlock.

local Profile = require(script.Parent.Profile)
local Leaderboard = require(script.Parent.Leaderboard)

export type RetryOpts = {
	attempts: number?, -- tries in all (default cfg.Save.attempts, else 4)
	baseDelay: number?, -- seconds before the second try; doubles each time
	maxDelay: number?,
	sleep: ((seconds: number) -> ())?,
}

export type LoadResult = {
	profile: Profile.ProfileData,
	status: string, -- Profile.migrate's status, or "LoadFailed"
	canSave: boolean,
	attempts: number,
	err: string?,
}

export type SaveResult = {
	ok: boolean,
	status: string, -- "Saved" | "Unchanged" | "Future" | "Failed" | "NotAllowed"
	attempts: number,
	err: string?,
}

local SaveLogic = {}

local function optsFrom(cfg: any?, o: RetryOpts?): RetryOpts
	local S = if cfg ~= nil and cfg.Save ~= nil then cfg.Save else {}
	local given: RetryOpts = o or {}
	return {
		attempts = given.attempts or S.attempts or 4,
		baseDelay = given.baseDelay or S.baseDelay or 1,
		maxDelay = given.maxDelay or S.maxDelay or 8,
		sleep = given.sleep,
	}
end

-- Calls fn until it returns without error, up to `attempts` times, sleeping
-- baseDelay, 2 x baseDelay, ... (capped at maxDelay) between tries.
function SaveLogic.retry(fn: () -> any, o: RetryOpts?): (boolean, any, number, string?)
	local opts = optsFrom(nil, o)
	local attempts = math.max(1, math.floor(opts.attempts :: number))
	local delay = opts.baseDelay :: number
	local lastErr: string? = nil
	for k = 1, attempts do
		local ok, value = pcall(fn)
		if ok then
			return true, value, k, nil
		end
		lastErr = tostring(value)
		if k < attempts and opts.sleep ~= nil then
			(opts.sleep :: (number) -> ())(math.min(delay, opts.maxDelay :: number))
		end
		delay *= 2
	end
	return false, nil, attempts, lastErr
end

function SaveLogic.load(cfg: any, store: any, key: string, o: RetryOpts?): LoadResult
	local ok, raw, attempts, err = SaveLogic.retry(function()
		return store:GetAsync(key)
	end, optsFrom(cfg, o))
	if not ok then
		return { profile = Profile.default(cfg), status = "LoadFailed", canSave = false, attempts = attempts, err = err }
	end
	local p, status = Profile.migrate(cfg, raw)
	return { profile = p, status = status, canSave = status ~= "Future", attempts = attempts, err = nil }
end

-- Saves through UpdateAsync, merged with whatever is stored now. Pass the LoadResult's
-- canSave as `allowed` (false refuses at once).
function SaveLogic.save(
	cfg: any,
	store: any,
	key: string,
	profile: Profile.ProfileData,
	o: RetryOpts?,
	allowed: boolean?
): SaveResult
	if allowed == false then
		return { ok = false, status = "NotAllowed", attempts = 0, err = nil }
	end
	local future = false
	local ok, _, attempts, err = SaveLogic.retry(function()
		future = false
		return store:UpdateAsync(key, function(old: any)
			local stored, status = Profile.migrate(cfg, old)
			if status == "Future" then
				future = true
				return nil
			end
			local merged = if old == nil then profile else Profile.merge(cfg, profile, stored)
			return Profile.serialize(merged)
		end)
	end, optsFrom(cfg, o))
	if not ok then
		return { ok = false, status = "Failed", attempts = attempts, err = err }
	end
	if future then
		return { ok = false, status = "Future", attempts = attempts, err = nil }
	end
	return { ok = true, status = "Saved", attempts = attempts, err = nil }
end

-- Writes a player's best Endless night to an ordered store, only if it beats what is there.
function SaveLogic.submitBest(store: any, key: string, bestNight: number, at: number, o: RetryOpts?): SaveResult
	if bestNight <= 0 then
		return { ok = true, status = "Unchanged", attempts = 0, err = nil }
	end
	local value = Leaderboard.encode(bestNight, at)
	local changed = false
	local ok, _, attempts, err = SaveLogic.retry(function()
		changed = false
		return store:UpdateAsync(key, function(old: any)
			if type(old) == "number" then
				local oldNight = Leaderboard.decode(old)
				if oldNight >= bestNight then
					return nil
				end
			end
			changed = true
			return value
		end)
	end, optsFrom(nil, o))
	if not ok then
		return { ok = false, status = "Failed", attempts = attempts, err = err }
	end
	return { ok = true, status = if changed then "Saved" else "Unchanged", attempts = attempts, err = nil }
end

return SaveLogic
