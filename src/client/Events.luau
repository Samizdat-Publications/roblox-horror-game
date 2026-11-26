--!strict
-- The client's event bus: every list the server sends on the Events remote is handed to
-- the subscribers, one event at a time, in order. Malformed entries are skipped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

export type Event = { kind: string, entity: string?, player: number?, only: number?, data: { [string]: any }? }

local Events = {}

local byKind: { [string]: { (Event) -> () } } = {}
local any: { (Event) -> () } = {}

function Events.on(kind: string, fn: (Event) -> ())
	local list = byKind[kind]
	if list == nil then
		list = {}
		byKind[kind] = list
	end
	table.insert(list, fn)
end

function Events.onAny(fn: (Event) -> ())
	table.insert(any, fn)
end

local function deliver(e: Event)
	for _, fn in any do
		task.spawn(fn, e)
	end
	for _, fn in byKind[e.kind] or {} do
		task.spawn(fn, e)
	end
end

function Events.init()
	local remote = Remotes.wait("Events")
	remote.OnClientEvent:Connect(function(list: any)
		if type(list) ~= "table" then
			return
		end
		for _, e in list do
			if type(e) == "table" and type(e.kind) == "string" then
				if e.data ~= nil and type(e.data) ~= "table" then
					e.data = nil
				end
				deliver(e :: Event)
			end
		end
	end)
end

return Events
