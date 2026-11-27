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
--   { cmd = "cardhold", on }             keeps the death card up (DeathCard.hold)
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

local function lookStep()
	local la = lookAt
	local cam = Workspace.CurrentCamera
	if la == nil or cam == nil or cam.CameraType == Enum.CameraType.Scriptable then
		return
	end
	local pos = cam.CFrame.Position
	local yaw = math.atan2(la.x - pos.X, la.z - pos.Z) + la.offset
	cam.CFrame = CFrame.lookAt(pos, pos + Vector3.new(math.sin(yaw), -0.06, math.cos(yaw)))
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
			if msg.cmd == "autopilot" and type(msg.x) == "number" and type(msg.z) == "number" then
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
			elseif msg.cmd == "look" then
				if type(msg.x) == "number" and type(msg.z) == "number" then
					lookAt = {
						x = msg.x,
						z = msg.z,
						offset = if type(msg.offset) == "number" then msg.offset else 0,
					}
				else
					lookAt = nil
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
