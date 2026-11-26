--!strict
-- Builds the lake world at server start from Config.Lake, deterministic from SEED.
-- The geometry lives in world/*.luau (pure builders, also run by tools/shell/world_count.luau).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Look = require(Shared:WaitForChild("Look"))
local Rng = require(Shared:WaitForChild("Core"):WaitForChild("Rng"))

local world = script.Parent:WaitForChild("world")
local Parts = require(world:WaitForChild("Parts"))
local Assemble = require(world:WaitForChild("Assemble"))
local Water = require(world:WaitForChild("Water"))
local Shore = require(world:WaitForChild("Shore"))
local Dock = require(world:WaitForChild("Dock"))
local Landmarks = require(world:WaitForChild("Landmarks"))

export type Result = Assemble.Result

local WorldBuilder = {}

WorldBuilder.SEED = 20261126 -- keep in step with tools/shell/world_count.luau
WorldBuilder.GROUP_WORLD = "World"
WorldBuilder.GROUP_BOAT = "Boat"

WorldBuilder.last = nil :: Result?

-- Collision groups: the boat never collides with world geometry (BoatService keeps it off
-- the dock and the shore itself); characters (Default) collide with both. Uses the
-- WorldRoot methods, falling back to the deprecated PhysicsService ones.
function WorldBuilder.registerCollisionGroups(warnings: { string })
	local ws = Workspace :: any
	local function viaWorkspace()
		for _, g in { WorldBuilder.GROUP_WORLD, WorldBuilder.GROUP_BOAT } do
			if not ws:IsCollisionGroupRegistered(g) then
				ws:RegisterCollisionGroup(g)
			end
		end
		ws:CollisionGroupSetCollidable(WorldBuilder.GROUP_BOAT, WorldBuilder.GROUP_WORLD, false)
	end
	local ok, err = pcall(viaWorkspace)
	if ok then
		return
	end
	local ps = game:GetService("PhysicsService") :: any
	local ok2, err2 = pcall(function()
		for _, g in { WorldBuilder.GROUP_WORLD, WorldBuilder.GROUP_BOAT } do
			if not ps:IsCollisionGroupRegistered(g) then
				ps:RegisterCollisionGroup(g)
			end
		end
		ps:CollisionGroupSetCollidable(WorldBuilder.GROUP_BOAT, WorldBuilder.GROUP_WORLD, false)
	end)
	if not ok2 then
		local msg =
			string.format("collision groups failed: workspace (%s), PhysicsService (%s)", tostring(err), tostring(err2))
		table.insert(warnings, msg)
		warn("[DeadCalm] " .. msg)
	end
end

-- Fresh ctx for a builder (also used by BoatService for the hull).
function WorldBuilder.context(): any
	return {
		cfg = Config,
		look = Look,
		parts = Parts,
		Rng = Rng,
		rng = Rng.new(WorldBuilder.SEED),
		warnings = {},
		anchors = {},
	}
end

function WorldBuilder.build(): Result
	local old = Workspace:FindFirstChild(Assemble.ROOT_NAME)
	if old then
		old:Destroy()
	end
	local ctx = WorldBuilder.context()
	WorldBuilder.registerCollisionGroups(ctx.warnings)
	local result = Assemble.build(ctx, { Water, Shore, Dock, Landmarks })
	result.root.Parent = Workspace
	for _, w in result.warnings do
		warn("[DeadCalm] world: " .. w)
	end
	WorldBuilder.last = result
	return result
end

return WorldBuilder
