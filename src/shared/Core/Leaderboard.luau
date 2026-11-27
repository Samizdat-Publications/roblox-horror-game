--!strict
-- The best Endless night board (docs/ARCHITECTURE.md, Other Core modules).
--
--   Leaderboard.compare(a, b) -> boolean         -- a ranks above b
--   Leaderboard.sort(entries)                    -- in place, best first
--   Leaderboard.top(entries, n) -> { Entry }     -- the best n, ranked (ties share a rank)
--   Leaderboard.submit(board, entry, max) -> boolean  -- keeps one entry per player, best only
--   Leaderboard.encode(bestNight, at) -> number  -- one integer for an ordered store
--   Leaderboard.decode(value) -> (bestNight, at)
--
-- Order: the higher best night first; on a tie, whoever reached it first (smaller `at`,
-- seconds since some epoch the server picks); then the smaller userId so the order is total.

export type Entry = {
	userId: number,
	bestNight: number,
	at: number, -- when it was reached (server time, seconds)
	rank: number?, -- filled by top()
}

local Leaderboard = {}

-- Room for `at` values up to about the year 2286 in Unix seconds.
Leaderboard.AT_SPAN = 1e10

function Leaderboard.compare(a: Entry, b: Entry): boolean
	if a.bestNight ~= b.bestNight then
		return a.bestNight > b.bestNight
	end
	if a.at ~= b.at then
		return a.at < b.at
	end
	return a.userId < b.userId
end

function Leaderboard.sort(entries: { Entry })
	table.sort(entries, Leaderboard.compare)
end

-- The best n entries, copied, with ranks. Entries with the same best night and the same
-- time share a rank (standard competition ranking: 1, 2, 2, 4).
function Leaderboard.top(entries: { Entry }, n: number): { Entry }
	local sorted: { Entry } = {}
	for _, e in entries do
		if type(e.bestNight) == "number" and e.bestNight > 0 then
			table.insert(sorted, { userId = e.userId, bestNight = e.bestNight, at = e.at })
		end
	end
	Leaderboard.sort(sorted)
	local out: { Entry } = {}
	for i = 1, math.min(math.max(0, math.floor(n)), #sorted) do
		local e = sorted[i]
		local prev = out[i - 1]
		if prev ~= nil and prev.bestNight == e.bestNight and prev.at == e.at then
			e.rank = prev.rank
		else
			e.rank = i
		end
		table.insert(out, e)
	end
	return out
end

-- Adds or improves a player's entry (a worse or equal result never replaces a better one)
-- and trims the board to `max` entries. Returns true if the board changed.
function Leaderboard.submit(board: { Entry }, entry: Entry, max: number): boolean
	if type(entry.bestNight) ~= "number" or entry.bestNight <= 0 then
		return false
	end
	local changed = false
	local found = false
	for i, e in board do
		if e.userId == entry.userId then
			found = true
			if entry.bestNight > e.bestNight then
				board[i] = { userId = entry.userId, bestNight = entry.bestNight, at = entry.at }
				changed = true
			end
			break
		end
	end
	if not found then
		table.insert(board, { userId = entry.userId, bestNight = entry.bestNight, at = entry.at })
		changed = true
	end
	Leaderboard.sort(board)
	while #board > max do
		local gone = table.remove(board)
		if gone ~= nil and gone.userId == entry.userId then
			changed = false -- it did not make the board
		end
	end
	return changed
end

-- One integer that sorts like compare() in a descending ordered store (best night, then
-- earlier time). Exact in doubles while bestNight stays under 900,000.
function Leaderboard.encode(bestNight: number, at: number): number
	local n = math.max(0, math.floor(bestNight))
	local t = math.clamp(math.floor(at), 0, Leaderboard.AT_SPAN - 1)
	return n * Leaderboard.AT_SPAN + (Leaderboard.AT_SPAN - 1 - t)
end

function Leaderboard.decode(value: number): (number, number)
	local n = math.floor(value / Leaderboard.AT_SPAN)
	local rest = value - n * Leaderboard.AT_SPAN
	return n, Leaderboard.AT_SPAN - 1 - rest
end

return Leaderboard
