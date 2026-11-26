--[[
Builds the world and the boat outside Studio and counts their parts.

    lune run tools/shell/world_count.luau

Run it from the project root. It loads src/server/world/*.luau exactly as WorldBuilder
does, with Instance, Vector3, CFrame, Color3 and Enum from Lune's Roblox library, so a
wrong property name or enum fails here before Studio sees it. Exit code 1 on any error,
any world warning, or more than BUDGET parts.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local BUDGET = 2500
local WORLD_SEED = 20261126 -- keep in step with WorldBuilder.SEED

local env = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

local function load(path: string): any
	local fn = luau.load(fs.readFile(path), { debugName = path, environment = env })
	return fn()
end

local Config = load("src/shared/Config.luau")
local Look = load("src/shared/Look.luau")
local Rng = load("src/shared/Core/Rng.luau")
local Parts = load("src/server/world/Parts.luau")
local Assemble = load("src/server/world/Assemble.luau")
local modules = {
	load("src/server/world/Water.luau"),
	load("src/server/world/Shore.luau"),
	load("src/server/world/Dock.luau"),
	load("src/server/world/Landmarks.luau"),
}
local BoatHull = load("src/server/world/BoatHull.luau")

local ctx = {
	cfg = Config,
	look = Look,
	parts = Parts,
	Rng = Rng,
	rng = Rng.new(WORLD_SEED),
	warnings = {},
	anchors = {},
}
local result = Assemble.build(ctx, modules)

local boatCtx = table.clone(ctx)
local boat = BoatHull.build(boatCtx, roblox.CFrame.new(0, 0.15, -375))
local boatParts = Assemble.countParts(boat.model)

local names = {}
for name in result.perModule do
	table.insert(names, name)
end
table.sort(names)
for _, name in names do
	print(string.format("  %-10s %5d parts", name, result.perModule[name]))
end
print(string.format("  %-10s %5d parts", "Boat", boatParts))
local total = result.partCount + boatParts
print(
	string.format(
		"WORLD: %d parts in the world, %d in the boat, %d total (budget %d)",
		result.partCount,
		boatParts,
		total,
		BUDGET
	)
)

local need = {
	"water",
	"dockEnd",
	"cooler",
	"oilCan",
	"beaconLamp",
	"beaconLight",
	"shackRadio",
	"shackWindow",
	"steeple",
	"steepleBell",
	"buoy",
	"reeds",
	"narrows",
}
local failures = 0
for _, key in need do
	if result.anchors[key] == nil then
		print("  MISSING anchor " .. key)
		failures += 1
	end
end
for _, seatName in BoatHull.SEAT_ORDER do
	if boat.seats[seatName] == nil or boat.seats[seatName].ClassName ~= "Seat" then
		print("  MISSING seat " .. seatName)
		failures += 1
	end
end
for _, w in result.warnings do
	print("  WARNING " .. w)
	failures += 1
end
if total > BUDGET then
	print("  OVER BUDGET")
	failures += 1
end
process.exit(if failures == 0 then 0 else 1)
