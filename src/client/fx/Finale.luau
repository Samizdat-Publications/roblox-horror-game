--!strict
-- Rule 6, the Lake Wakes. STUB: the finale's presentation is the next chunk (S4 with the
-- five-night flow). For now it only plays the bell when the finale starts and the shared
-- stings, so a forced Finale is not silent.

local client = script.Parent.Parent
local AudioDirector = require(client:WaitForChild("AudioDirector"))

local Finale = {}

function Finale.handle(e: any)
	if e.kind == "EntityCue" then
		AudioDirector.play("bell-dock-solo")
	end
end

function Finale.reset() end

return Finale
