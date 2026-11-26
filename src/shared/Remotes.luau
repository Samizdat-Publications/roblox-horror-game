--!strict
-- The only remotes in the game (docs/ARCHITECTURE.md, Remotes). Net creates them in a
-- Folder named FOLDER under ReplicatedStorage. Nothing else crosses the network, except the
-- Studio-only debug remotes below, which Net creates only when RunService:IsStudio().

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

-- Studio only: DebugDriver talks to the client's Camera and DebugBot through these.
Remotes.DEBUG_FOLDER = "DeadCalmDebugRemotes"
Remotes.debug = {
	"DebugCamera", -- server to client: (shot: string)
	"DebugBot", -- both ways: server sends a command table, the client answers with an ack table
}

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

-- Client side: wait for one remote. Errors loudly if the server never made it.
function Remotes.wait(name: RemoteName): RemoteEvent
	local rs = game:GetService("ReplicatedStorage")
	local folder = rs:WaitForChild(Remotes.FOLDER, 30)
	if folder == nil then
		error("[DeadCalm] Remotes folder never appeared (did Net.init run on the server?)")
	end
	local remote = folder:WaitForChild(name, 30)
	if remote == nil or not remote:IsA("RemoteEvent") then
		error(string.format("[DeadCalm] remote %s missing", name))
	end
	return remote :: RemoteEvent
end

return Remotes
