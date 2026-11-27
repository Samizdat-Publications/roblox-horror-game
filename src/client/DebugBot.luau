--!strict
-- Studio only. Plays DebugDriver scenarios through the real remotes: it steers by handing
-- Input an override, so every helm message goes out through Input.sendHelm and the
-- BoatInput remote exactly like a player's. The server seats players itself.
--
-- Commands on the DebugBot remote (server to client, tables):
--   { cmd = "hello" }                    just an ack (DebugDriver checks the bot is there)
--   { cmd = "autopilot", x, z, arrive }  steer toward (x, z) until told to stop
--   { cmd = "stop" }                     hands the helm back to the devices
--   { cmd = "intent", kind, num, flag }  sends one intent through Input.sendIntent
--   { cmd = "autoreel", on }             Studio-only auto-reel: sets the hook on a bite and
--                                        holds the tension inside the band by sending the
--                                        same ReelHold intents the reel button sends (MCP
--                                        input is too slow for timed reeling)
--   { cmd = "knock" }                    one knock through Input.knock (the Q key's path)
--   { cmd = "bail", on }                 hold or let go of bailing through Input.bail
--   { cmd = "callout", phrase }          says a phrase through Callouts.choose (the wheel's
--                                        path; "Wave" also sends the Wave intent)
--   { cmd = "look", x, z, offset }       turns the camera to face (x, z) plus `offset`
--                                        radians of yaw, every frame, so the gaze the server
--                                        gets follows; { cmd = "look" } with no x lets go
--   { cmd = "track", entity, offset }    keeps the head on a rule's figure every frame
--                                        (entity "Neighbor" or "Watcher", from the fx
--                                        module's drawn position, pitch included), so the
--                                        server's gaze follows; offset is extra yaw
--                                        (radians) for the edge of sight. { cmd = "look" }
--                                        with no x lets go of both
--   { cmd = "cardhold", on }             keeps the death card up (DeathCard.hold)
--   { cmd = "clean", tapes }             scenario reset on this client: no death card, no
--                                        night cards, no catch card, rule leftovers and
--                                        camera effects cleared, camera back in first
--                                        person, the bot's helm and head let go, the tape cut;
--                                        tapes = false mutes tapes until { cmd = "tapes" }
--   { cmd = "tapes", on }                tapes allowed again (on = true) or muted
--   { cmd = "book", page }               opens the rulebook ("rules"), the Field Guide
--                                        ("guide") or the Lake Rules ("lake"), or shuts
--                                        the book (page "none"), through BookState
--   { cmd = "play_sound", name, seconds, ambience }
--                                        listening test: plays any SoundRegistry name on
--                                        this client through AudioDirector (real, library
--                                        stand-in or derived alike) the way the real fx do:
--                                        same place relative to the boat (the Neighbor 200
--                                        studs off the bow, the Watcher on the nearest shore,
--                                        knocks under the keel; AudioDirector.auditionSpot),
--                                        same group, same ambience ducking. ambience = true
--                                        holds the full band-3 chorus underneath. Loops stop
--                                        after `seconds` (default 8). The ack carries
--                                        played = true/false and spot
--   { cmd = "stop_sound" }               stops every play_sound sound and the held chorus
-- Each command is answered with { ack = cmd, seat = <seat name or nil> }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))
local Input = require(script.Parent:WaitForChild("Input"))
local ViewState = require(script.Parent:WaitForChild("ViewState"))
local ui = script.Parent:WaitForChild("ui")
local Callouts = require(ui:WaitForChild("Callouts"))
local DeathCard = require(ui:WaitForChild("DeathCard"))
local NightCards = require(ui:WaitForChild("NightCards"))
local BookState = require(ui:WaitForChild("BookState"))
local AudioDirector = require(script.Parent:WaitForChild("AudioDirector"))
local BoatFx = require(script.Parent:WaitForChild("BoatFx"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local RulesFx = require(script.Parent:WaitForChild("RulesFx"))
local fx = script.Parent:WaitForChild("fx")
local NeighborFx = require(fx:WaitForChild("Neighbor"))
local WatcherFx = require(fx:WaitForChild("Watcher"))

local DebugBot = {}

-- Auto-reel state. The bot predicts tension between views (at most 10 a second) from the
-- reel rates in Config.Fishing, and keeps its own token bucket under Net's intent limit.
local reel = {
	on = false,
	held = false,
	viewAt = 0,
	tension = 0,
	tokens = 4,
	lastRefill = 0,
}
DebugBot.REEL_RATE = Config.Net.intentPerSec - 1 -- intents per second, under Net's limit

local function sendReel(held: boolean): boolean
	local now = os.clock()
	reel.tokens = math.min(4, reel.tokens + (now - reel.lastRefill) * DebugBot.REEL_RATE)
	reel.lastRefill = now
	if reel.tokens < 1 then
		return false
	end
	reel.tokens -= 1
	reel.held = held
	Input.sendIntent("ReelHold", nil, held)
	return true
end

local function reelStep()
	if not reel.on then
		return
	end
	local pv = ViewState.me()
	if pv == nil then
		return
	end
	local F = Config.Fishing
	if pv.fishing == "Bite" then
		if not reel.held then
			sendReel(true)
		end
		return
	elseif pv.fishing ~= "Reeling" then
		if reel.held then
			sendReel(false)
		end
		return
	end
	local dt = os.clock() - reel.viewAt
	local predicted = reel.tension + (if reel.held then F.tensionUp else -F.tensionDown) * dt
	local w = pv.zoneHi - pv.zoneLo
	local lo, hi = pv.zoneLo + w * 0.3, pv.zoneHi - w * 0.3
	if predicted > 0.92 then
		hi = math.min(hi, 0.9)
	end
	if predicted < lo and not reel.held then
		sendReel(true)
	elseif predicted > hi and reel.held then
		sendReel(false)
	end
end

-- Where the bot looks (scenarios that need the gaze: the Neighbor, the Watcher).
local lookAt: { x: number, z: number, offset: number }? = nil
-- Or a rule's figure, followed every frame (captures: keep the threat in frame).
local track: { entity: string, offset: number }? = nil

local function trackPoint(entity: string): Vector3?
	if entity == "Neighbor" then
		return NeighborFx.focus()
	elseif entity == "Watcher" then
		return WatcherFx.focus()
	end
	return nil
end

local function lookStep()
	local cam = Workspace.CurrentCamera
	if cam == nil or cam.CameraType == Enum.CameraType.Scriptable then
		return
	end
	local pos = cam.CFrame.Position
	local tr = track
	if tr then
		local p = trackPoint(tr.entity)
		if p then
			local flat = math.sqrt((p.X - pos.X) ^ 2 + (p.Z - pos.Z) ^ 2)
			local yaw = math.atan2(p.X - pos.X, p.Z - pos.Z) + tr.offset
			-- Pitch toward it, kept gentle so the water line stays in the shot.
			local pitch = math.clamp(math.atan2(p.Y - pos.Y, math.max(flat, 1)), -0.25, 0.3)
			local dir = Vector3.new(math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch))
			cam.CFrame = CFrame.lookAt(pos, pos + dir)
			return
		end
	end
	local la = lookAt
	if la == nil then
		return
	end
	local yaw = math.atan2(la.x - pos.X, la.z - pos.Z) + la.offset
	cam.CFrame = CFrame.lookAt(pos, pos + Vector3.new(math.sin(yaw), -0.06, math.cos(yaw)))
end

-- Scenario reset on this client (DebugRules.fullReset).
local function clean(tapesOn: boolean)
	AudioDirector.muteTapes(not tapesOn)
	AudioDirector.stopTape(false)
	DeathCard.hold = false
	DeathCard.close()
	NightCards.hide()
	BookState.close()
	Callouts.setOpen(false)
	RulesFx.resetAll()
	BoatFx.clearCamera()
	lookAt = nil
	track = nil
	Input.setOverride(nil)
	Camera.applyShot("reset")
end

-- Throttle and steer toward (tx, tz). Same law as DebugDriver's server autopilot.
function DebugBot.steerToward(tx: number, tz: number, arrive: number): (number, number)
	local pos, heading = BoatClient.pose()
	if pos == nil or heading == nil then
		return 0, 0
	end
	local want = math.atan2(tx - pos.X, tz - pos.Z)
	local err = math.atan2(math.sin(want - heading), math.cos(want - heading))
	local steer = math.clamp(-err * 2, -1, 1)
	local dist = math.sqrt((tx - pos.X) ^ 2 + (tz - pos.Z) ^ 2)
	if dist <= arrive then
		return 0, 0
	end
	local throttle = if math.abs(err) > 1.2 then 0.3 else 1
	if dist < arrive * 2 then
		throttle *= 0.6
	end
	return throttle, steer
end

function DebugBot.init()
	if not RunService:IsStudio() then
		return
	end
	ViewState.onChange(function()
		local pv = ViewState.me()
		if pv then
			reel.tension = pv.tension
			reel.viewAt = os.clock()
		end
	end)
	RunService.Heartbeat:Connect(reelStep)
	-- After the camera scripts (Enum.RenderPriority.Camera is 200), so this frame shows it.
	RunService:BindToRenderStep("DeadCalmBotLook", Enum.RenderPriority.Camera.Value + 1, lookStep)
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild(Remotes.DEBUG_FOLDER, 10)
		local remote = folder and folder:FindFirstChild("DebugBot")
		if remote == nil or not remote:IsA("RemoteEvent") then
			return
		end
		remote.OnClientEvent:Connect(function(msg: any)
			if type(msg) ~= "table" or type(msg.cmd) ~= "string" then
				return
			end
			if msg.cmd == "play_sound" and type(msg.name) == "string" then
				local played, spot = AudioDirector.audition(
					msg.name,
					if type(msg.seconds) == "number" then msg.seconds else nil,
					{ ambience = msg.ambience == true }
				)
				print(
					string.format(
						"[DebugBot] play_sound %s: %s (at %s%s)",
						msg.name,
						if played then "playing" else "nothing to play",
						tostring(spot),
						if msg.ambience == true then ", full chorus under it" else ""
					)
				)
				remote:FireServer({
					ack = msg.cmd,
					seat = BoatClient.mySeat(),
					name = msg.name,
					played = played,
					spot = spot,
				})
				return
			elseif msg.cmd == "stop_sound" then
				AudioDirector.stopAuditions()
			elseif msg.cmd == "autopilot" and type(msg.x) == "number" and type(msg.z) == "number" then
				local tx, tz = msg.x, msg.z
				local arrive = if type(msg.arrive) == "number" then msg.arrive else 12
				Input.setOverride(function()
					return DebugBot.steerToward(tx, tz, arrive)
				end)
			elseif msg.cmd == "stop" then
				Input.setOverride(nil)
				Input.sendHelm(0, 0)
			elseif msg.cmd == "intent" and type(msg.kind) == "string" then
				local num = if type(msg.num) == "number" then msg.num else nil
				local flag = if type(msg.flag) == "boolean" then msg.flag else nil
				local text = if type(msg.text) == "string" then msg.text else nil
				Input.sendIntent(msg.kind, num, flag, text)
			elseif msg.cmd == "knock" then
				Input.knock()
			elseif msg.cmd == "bail" then
				Input.bail(msg.on == true)
			elseif msg.cmd == "callout" and type(msg.phrase) == "string" then
				Callouts.choose(msg.phrase)
			elseif msg.cmd == "track" and type(msg.entity) == "string" then
				track = {
					entity = msg.entity,
					offset = if type(msg.offset) == "number" then msg.offset else 0,
				}
			elseif msg.cmd == "clean" then
				clean(msg.tapes == true)
			elseif msg.cmd == "tapes" then
				AudioDirector.muteTapes(msg.on ~= true)
			elseif msg.cmd == "look" then
				if type(msg.x) ~= "number" then
					track = nil
				end
				if type(msg.x) == "number" and type(msg.z) == "number" then
					lookAt = {
						x = msg.x,
						z = msg.z,
						offset = if type(msg.offset) == "number" then msg.offset else 0,
					}
				else
					lookAt = nil
				end
			elseif msg.cmd == "book" then
				if msg.page == "none" then
					BookState.close()
				elseif type(msg.page) == "string" then
					-- The night's page reaches the client on LobbyState; give it a moment.
					local t0 = os.clock()
					while not BookState.open(msg.page) and os.clock() - t0 < 2 do
						task.wait(0.1)
					end
				end
			elseif msg.cmd == "cardhold" then
				DeathCard.hold = msg.on == true
			elseif msg.cmd == "autoreel" then
				reel.on = msg.on == true
				if not reel.on and reel.held then
					sendReel(false)
				end
			elseif msg.cmd ~= "hello" then -- hello is an ack only
				return
			end
			remote:FireServer({ ack = msg.cmd, seat = BoatClient.mySeat() })
		end)
	end)
end

return DebugBot
