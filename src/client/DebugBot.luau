--!strict
-- Studio only. Plays DebugDriver scenarios through the real remotes: it steers by handing
-- Input an override, so every helm message goes out through Input.sendHelm and the
-- BoatInput remote exactly like a player's. The server seats players itself.
--
-- Commands on the DebugBot remote (server to client, tables):
--   { cmd = "autopilot", x, z, arrive }  steer toward (x, z) until told to stop
--   { cmd = "stop" }                     hands the helm back to the devices
-- Each command is answered with { ack = cmd, seat = <seat name or nil> }.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))
local Input = require(script.Parent:WaitForChild("Input"))

local DebugBot = {}

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
			else
				return
			end
			remote:FireServer({ ack = msg.cmd, seat = BoatClient.mySeat() })
		end)
	end)
end

return DebugBot
