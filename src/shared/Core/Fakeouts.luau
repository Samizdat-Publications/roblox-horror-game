--!strict
-- Harmless scares (docs/DESIGN.md, Fake-outs): a loon that sounds like a scream, a branch
-- snapping on shore, a fish jumping at the gunwale, one knock (not three), the chorus
-- dipping for two seconds, a buoy clank that is nearly a bell, a lantern flicker, a far
-- light that turns out to be fireflies. The Director decides when (budget, spacing, never
-- near a real cue); this module picks which one and where it is.
--
--   Fakeouts.pick(cfg, rng, last) -> id         -- never the same id twice in a row
--   Fakeouts.event(cfg, rng, id, only, boatPos) -> Event

local Types = require(script.Parent.Types)
local Rng = require(script.Parent.Rng)
local LakeMap = require(script.Parent.LakeMap)

type Event = Types.Event
type Vec2 = Types.Vec2

local Fakeouts = {}

Fakeouts.DIP_SECONDS = 2 -- ChorusDip: the chorus drops one band for this long
Fakeouts.FLICKER_SECONDS = 0.6

function Fakeouts.pick(cfg: any, rng: Rng.RngState, last: string?): string
	local ids: { string } = {}
	for _, id in cfg.Fakeouts do
		if id ~= last then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return cfg.Fakeouts[1]
	end
	return Rng.pick(rng, ids)
end

-- A point on the shore at a random bearing from the boat (for shore sounds and lights).
local function shorePoint(cfg: any, rng: Rng.RngState, boatPos: Vec2): Vec2
	local a = Rng.range(rng, -math.pi, math.pi)
	local far = { x = boatPos.x + math.sin(a) * 2000, z = boatPos.z + math.cos(a) * 2000 }
	return LakeMap.nearestShorePoint(cfg, far)
end

function Fakeouts.event(cfg: any, rng: Rng.RngState, id: string, only: number?, boatPos: Vec2): Event
	local data: { [string]: any } = { id = id }
	if id == "LoonScream" or id == "BranchSnap" or id == "FireflyLight" then
		data.pos = shorePoint(cfg, rng, boatPos)
	elseif id == "FishJump" then
		local a = Rng.range(rng, -math.pi, math.pi)
		data.pos = { x = boatPos.x + math.sin(a) * 4, z = boatPos.z + math.cos(a) * 4 }
	elseif id == "SingleKnock" then
		data.pos = { x = boatPos.x, z = boatPos.z }
	elseif id == "BuoyClank" then
		data.pos = { x = cfg.Lake.buoy.x, z = cfg.Lake.buoy.z }
	elseif id == "ChorusDip" then
		data.seconds = Fakeouts.DIP_SECONDS
	elseif id == "LanternFlicker" then
		data.seconds = Fakeouts.FLICKER_SECONDS
	end
	return { kind = "Fakeout", only = only, data = data }
end

return Fakeouts
