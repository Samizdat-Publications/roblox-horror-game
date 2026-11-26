--!strict
-- The only remotes in the game (docs/ARCHITECTURE.md, Remotes). Net creates them in a
-- Folder named FOLDER under ReplicatedStorage. Nothing else crosses the network.

export type RemoteName =
	"BoatInput"
	| "Gaze"
	| "Intent"
	| "Lobby"
	| "Cosmetic"
	| "View"
	| "Events"
	| "LobbyState"
	| "Profile"

local Remotes = {}

Remotes.FOLDER = "Remotes"

-- Client to server: intents only. A client can never send a catch, a quota change or a death.
Remotes.toServer = {
	"BoatInput", -- (throttle, steer)
	"Gaze", -- (yaw)
	"Intent", -- (kind, num?, flag?, text?)
	"Lobby", -- (action, value?)
	"Cosmetic", -- (slot, id)
} :: { RemoteName }

-- Server to client.
Remotes.toClient = {
	"View", -- (nightView)
	"Events", -- ({ Event })
	"LobbyState", -- (state)
	"Profile", -- (profile)
} :: { RemoteName }

function Remotes.all(): { RemoteName }
	local out = table.clone(Remotes.toServer)
	for _, name in Remotes.toClient do
		table.insert(out, name)
	end
	return out
end

return Remotes
