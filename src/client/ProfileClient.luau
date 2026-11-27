--!strict
-- This player's saved progress, as the server last sent it (Profile remote, S5): stats,
-- every cosmetic with whether it is unlocked and equipped, swatch colors and how to earn
-- each, and whether Endless Nights is open. Equipping sends a Cosmetic request; the server
-- checks the unlock and answers with a fresh copy (a refused pick snaps back).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local ProfileClient = {}

export type Item = {
	slot: string,
	id: string,
	name: string,
	color: Color3,
	text: string,
	unlocked: boolean,
	equipped: boolean,
}

export type State = {
	ready: boolean,
	memory: boolean,
	canSave: boolean,
	stats: { [string]: number },
	equipped: { [string]: string },
	items: { Item },
	slots: { string },
	slotNames: { [string]: string },
	new: { string },
	endless: boolean,
}

local state: State = {
	ready = false,
	memory = false,
	canSave = false,
	stats = {},
	equipped = {},
	items = {},
	slots = { "lantern", "paint", "hat" },
	slotNames = { lantern = "Lantern", paint = "Boat paint", hat = "Hat" },
	new = {},
	endless = false,
}
local listeners: { (State) -> () } = {}
local remote: RemoteEvent? = nil

local function clean(raw: any): State?
	if type(raw) ~= "table" then
		return nil
	end
	local items: { Item } = {}
	for _, it in (if type(raw.items) == "table" then raw.items else {}) do
		if type(it) == "table" and type(it.slot) == "string" and type(it.id) == "string" then
			table.insert(items, {
				slot = it.slot,
				id = it.id,
				name = if type(it.name) == "string" then it.name else it.id,
				color = if typeof(it.color) == "Color3" then it.color else Color3.new(0.5, 0.5, 0.5),
				text = if type(it.text) == "string" then it.text else "",
				unlocked = it.unlocked == true,
				equipped = it.equipped == true,
			})
		end
	end
	local stats = {}
	for k, v in (if type(raw.stats) == "table" then raw.stats else {}) do
		if type(k) == "string" and type(v) == "number" then
			stats[k] = v
		end
	end
	local equipped = {}
	for k, v in (if type(raw.equipped) == "table" then raw.equipped else {}) do
		if type(k) == "string" and type(v) == "string" then
			equipped[k] = v
		end
	end
	local slotNames = table.clone(state.slotNames)
	for k, v in (if type(raw.slotNames) == "table" then raw.slotNames else {}) do
		if type(k) == "string" and type(v) == "string" then
			slotNames[k] = v
		end
	end
	local new = {}
	for _, v in (if type(raw.new) == "table" then raw.new else {}) do
		if type(v) == "string" then
			table.insert(new, v)
		end
	end
	return {
		ready = raw.ready == true,
		memory = raw.memory == true,
		canSave = raw.canSave == true,
		stats = stats,
		equipped = equipped,
		items = items,
		slots = state.slots,
		slotNames = slotNames,
		new = new,
		endless = raw.endless == true,
	}
end

function ProfileClient.get(): State
	return state
end

function ProfileClient.onChange(fn: (State) -> ())
	table.insert(listeners, fn)
end

function ProfileClient.item(slot: string, id: string): Item?
	for _, it in state.items do
		if it.slot == slot and it.id == id then
			return it
		end
	end
	return nil
end

-- Asks the server to wear an item. Locked items are not even sent.
function ProfileClient.equip(slot: string, id: string): boolean
	local it = ProfileClient.item(slot, id)
	local r = remote
	if r == nil or it == nil or not it.unlocked or it.equipped then
		return false
	end
	r:FireServer(slot, id)
	return true
end

function ProfileClient.init()
	remote = Remotes.wait("Cosmetic")
	Remotes.wait("Profile").OnClientEvent:Connect(function(raw: any)
		local s = clean(raw)
		if s == nil then
			return
		end
		state = s
		for _, fn in listeners do
			task.spawn(fn, s)
		end
	end)
end

return ProfileClient
