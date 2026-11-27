--!strict
-- Routes the rules' events to their presentation: EntityCue, EntityStage, EntityMoved,
-- EntityPass and EntityFail by `entity` to client/fx/<RuleId>, Fakeout to fx/Fakeouts,
-- BoatRocked and Flooding to BoatFx. A new night resets every rule's leftovers.

local client = script.Parent
local Events = require(client:WaitForChild("Events"))
local BoatFx = require(client:WaitForChild("BoatFx"))
local LobbyClient = require(client:WaitForChild("LobbyClient"))
local fx = client:WaitForChild("fx")

local RulesFx = {}

type Fx = { handle: (any) -> (), reset: () -> () }

local modules: { [string]: Fx } = {
	Hum = require(fx:WaitForChild("Hum")) :: any,
	WrongCatch = require(fx:WaitForChild("WrongCatch")) :: any,
	Neighbor = require(fx:WaitForChild("Neighbor")) :: any,
	Knocking = require(fx:WaitForChild("Knocking")) :: any,
	Watcher = require(fx:WaitForChild("Watcher")) :: any,
	Finale = require(fx:WaitForChild("Finale")) :: any,
}
local Fakeouts = require(fx:WaitForChild("Fakeouts"))
local Watcher = require(fx:WaitForChild("Watcher"))

-- EntityStrike: the Finale takes someone and goes on (Core M5).
local ENTITY_KINDS = { "EntityCue", "EntityStage", "EntityMoved", "EntityPass", "EntityFail", "EntityStrike" }

function RulesFx.resetAll()
	for _, m in modules do
		m.reset()
	end
	BoatFx.reset()
end

function RulesFx.init()
	BoatFx.init()
	Watcher.init()
	for _, kind in ENTITY_KINDS do
		Events.on(kind, function(e)
			local m = if type(e.entity) == "string" then modules[e.entity] else nil
			if m then
				m.handle(e)
			end
		end)
	end
	Events.on("Fakeout", function(e)
		Fakeouts.handle(e)
	end)
	Events.on("BoatRocked", function()
		BoatFx.shake(1.2, 1.8)
	end)
	Events.on("Flooding", function(e)
		local data = e.data or {}
		BoatFx.setLeak(data.leak == true)
	end)
	Events.on("Sunk", function()
		BoatFx.shake(0.6, 2.5)
	end)
	Events.on("NightStarted", function()
		RulesFx.resetAll()
	end)
	-- Back on the title screen (after the run): no leftovers, no dawn tint.
	LobbyClient.onChange(function(s)
		if s.phase == "Title" then
			RulesFx.resetAll()
		end
	end)
end

return RulesFx
