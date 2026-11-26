--!strict
-- The latest NightView. Until the server sends one (NightService arrives in S2), a local
-- stand-in is kept from Config and the boat's attributes, so the HUD and the audio mix
-- always have a NightView-shaped table to read.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Core"):WaitForChild("Types"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))

type NightView = Types.NightView

local ViewState = {}

ViewState.source = "local" :: "local" | "server"

local function defaultView(): NightView
	return {
		night = 1,
		mode = "Story",
		difficulty = "Normal",
		phase = "Night",
		clock = Config.Night.startHour,
		timeLeft = Config.Night.realSeconds,
		quota = Config.Nights[1].quota,
		banked = 0,
		hold = 0,
		holdMax = Config.Fishing.holdMax,
		oil = 1,
		refills = Config.Lantern.refillsPerNight,
		lanternOn = true,
		motorOn = false,
		chorus = 3,
		flood = 0,
		safe = true,
		rules = {},
		players = {},
	}
end

local view: NightView = defaultView()
local listeners: { (NightView) -> () } = {}

local function emit()
	for _, fn in listeners do
		task.spawn(fn, view)
	end
end

function ViewState.get(): NightView
	return view
end

function ViewState.onChange(fn: (NightView) -> ())
	table.insert(listeners, fn)
end

-- Only the fields the S1 world can know: lantern, motor, and whether the boat is in the
-- dock light. A server view, once it arrives, owns every field.
local function refreshLocal()
	if ViewState.source ~= "local" then
		return
	end
	local lantern = BoatClient.attr("LanternOn")
	local motor = BoatClient.attr("MotorOn")
	local pos = BoatClient.pose()
	local safe = view.safe
	if pos then
		local tip = Config.Lake.dockEnd
		safe = (pos.X - tip.x) ^ 2 + (pos.Z - tip.z) ^ 2 <= Config.Lake.safeRadius ^ 2
	end
	local changed = false
	if type(lantern) == "boolean" and lantern ~= view.lanternOn then
		view.lanternOn = lantern
		changed = true
	end
	if type(motor) == "boolean" and motor ~= view.motorOn then
		view.motorOn = motor
		changed = true
	end
	if safe ~= view.safe then
		view.safe = safe
		changed = true
	end
	if changed then
		emit()
	end
end

function ViewState.init()
	local remote = Remotes.wait("View")
	remote.OnClientEvent:Connect(function(v: any)
		if type(v) ~= "table" then
			return
		end
		ViewState.source = "server"
		view = v :: NightView
		emit()
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			refreshLocal()
		end
	end)
end

return ViewState
