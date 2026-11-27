--!strict
-- Store adapters for DataService (docs/ARCHITECTURE.md, DataService). Two kinds, one shape:
--
--   profile store:  GetAsync(key), SetAsync(key, value), UpdateAsync(key, transform)
--   board store:    the same, plus top(n) -> { { key: string, value: number } } (best first)
--
-- `DataStores.open()` decides once per server: the real DataStoreService when this place can
-- reach it, else an in-memory store (an unpublished place, or a published one with Studio
-- access to API services off). The memory store lives as long as the server and is never
-- written anywhere; DataService says so once in the output.
--
-- Every real call waits (a little) for the request budget first
-- (DataStoreService:GetRequestBudgetForRequestType) and may still error: Core.SaveLogic
-- retries with backoff, so this module never retries on its own.

local DataStoreService = game:GetService("DataStoreService")

local DataStores = {}

DataStores.PROFILE_STORE = "DeadCalmProfiles_v1"
DataStores.BOARD_STORE = "DeadCalmBestEndless_v1"
DataStores.BUDGET_WAIT = 6 -- seconds a call waits for budget before trying anyway

export type Store = {
	kind: string, -- "DataStore" | "Memory"
	GetAsync: (self: Store, key: string) -> any,
	SetAsync: (self: Store, key: string, value: any) -> (),
	UpdateAsync: (self: Store, key: string, transform: (old: any) -> any) -> any,
	top: (self: Store, n: number) -> { { key: string, value: number } },
}

export type Opened = {
	profiles: Store,
	board: Store,
	memory: boolean,
	reason: string?, -- why the memory store is in use
}

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

----------------------------------------------------------------------------------------
-- Memory store

function DataStores.memory(): Store
	local data: { [string]: any } = {}
	local s = {} :: any
	s.kind = "Memory"
	function s.GetAsync(_self: Store, key: string): any
		return deepCopy(data[key])
	end
	function s.SetAsync(_self: Store, key: string, value: any)
		data[key] = deepCopy(value)
	end
	function s.UpdateAsync(_self: Store, key: string, transform: (any) -> any): any
		local new = transform(deepCopy(data[key]))
		if new == nil then
			return deepCopy(data[key])
		end
		data[key] = deepCopy(new)
		return deepCopy(new)
	end
	function s.top(_self: Store, n: number): { { key: string, value: number } }
		local out = {}
		for k, v in data do
			if type(v) == "number" then
				table.insert(out, { key = k, value = v })
			end
		end
		table.sort(out, function(a, b)
			return a.value > b.value
		end)
		while #out > n do
			table.remove(out)
		end
		return out
	end
	return s :: Store
end

----------------------------------------------------------------------------------------
-- Real stores

-- Budget types to check, legacy first (the new Standard and Ordered types where the
-- engine has them). A request type the engine refuses is skipped.
local BUDGET: { [string]: { string } } = {
	read = { "GetAsync", "StandardRead" },
	write = { "UpdateAsync", "StandardWrite" },
	set = { "SetIncrementAsync", "StandardWrite" },
	sorted = { "GetSortedAsync", "OrderedList" },
	orderedWrite = { "SetIncrementSortedAsync", "OrderedWrite" },
}

local function budgetOk(kind: string): boolean
	local seen = false
	for _, name in BUDGET[kind] do
		local ok, n = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType((Enum.DataStoreRequestType :: any)[name])
		end)
		if ok and type(n) == "number" then
			seen = true
			if n >= 1 then
				return true
			end
		end
	end
	return not seen -- no budget answer at all: do not block
end

local function waitBudget(kind: string)
	local waited = 0
	while not budgetOk(kind) and waited < DataStores.BUDGET_WAIT do
		waited += task.wait(0.5)
	end
end

-- `userOf(key)` gives the user id a key belongs to (Roblox's user data tag), or nil.
local function wrap(ds: any, ordered: boolean, userOf: ((string) -> number?)?): Store
	local s = {} :: any
	s.kind = "DataStore"
	function s.GetAsync(_self: Store, key: string): any
		waitBudget("read")
		return ds:GetAsync(key)
	end
	function s.SetAsync(_self: Store, key: string, value: any)
		waitBudget(if ordered then "orderedWrite" else "set")
		local uid = if userOf then userOf(key) else nil
		if uid and not ordered then
			ds:SetAsync(key, value, { uid })
		else
			ds:SetAsync(key, value)
		end
	end
	function s.UpdateAsync(_self: Store, key: string, transform: (any) -> any): any
		waitBudget(if ordered then "orderedWrite" else "write")
		local uid = if userOf then userOf(key) else nil
		return ds:UpdateAsync(key, function(old: any)
			local new = transform(old)
			if new == nil then
				return nil
			end
			if uid and not ordered then
				return new, { uid }
			end
			return new
		end)
	end
	function s.top(_self: Store, n: number): { { key: string, value: number } }
		if not ordered then
			return {}
		end
		waitBudget("sorted")
		local pages = ds:GetSortedAsync(false, math.clamp(math.floor(n), 1, 100))
		local out = {}
		for _, e in pages:GetCurrentPage() do
			if type(e) == "table" and type(e.value) == "number" then
				table.insert(out, { key = tostring(e.key), value = e.value })
			end
		end
		return out
	end
	return s :: Store
end

-- Profile keys look like "u_<userId>".
function DataStores.profileKey(userId: number): string
	return "u_" .. tostring(userId)
end

local function userOfKey(key: string): number?
	local id = string.match(key, "^u_(%d+)$")
	return if id then tonumber(id) else nil
end

-- Decides the backend once. Never errors.
function DataStores.open(): Opened
	local reason: string? = nil
	if game.PlaceId == 0 then
		reason = "this place is not published, so it has no DataStores"
	else
		local ok, res = pcall(function()
			local ds = DataStoreService:GetDataStore(DataStores.PROFILE_STORE)
			local od = DataStoreService:GetOrderedDataStore(DataStores.BOARD_STORE)
			ds:GetAsync("probe")
			return { ds = ds, od = od }
		end)
		if ok and type(res) == "table" then
			return {
				profiles = wrap(res.ds, false, userOfKey),
				board = wrap(res.od, true, nil),
				memory = false,
				reason = nil,
			}
		end
		reason = "DataStores refused (" .. string.sub(tostring(res), 1, 120) .. ")"
	end
	return { profiles = DataStores.memory(), board = DataStores.memory(), memory = true, reason = reason }
end

return DataStores
