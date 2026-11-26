--!strict
-- Keyboard, touch and gamepad all map to the same intents.
--   Helm (only sent from the helm seat): W S / Up Down throttle, A D / Left Right steer, the left
--   gamepad stick, or the touch thumbstick (read through the default PlayerModule).
--   F or gamepad Y: lantern. M or gamepad X: motor.
-- Every helm message goes through Input.sendHelm, rate limited to Config.Net.boatHz.
-- DebugBot drives the helm through Input.setOverride, so it uses the same send path.
-- Touch buttons for the other verbs arrive with MobileButtons in S4.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))

local Input = {}

Input.DEADZONE = 0.18
Input.KEEPALIVE = 0.25 -- resend a held input this often so the server's timeout never trips

local boatRemote: RemoteEvent? = nil
local intentRemote: RemoteEvent? = nil
local controls: any = nil -- the default ControlModule, if it loads
local override: (() -> (number, number))? = nil

local lastSentAt = -math.huge
local lastThrottle, lastSteer = 0, 0
local minGap = 1 / Config.Net.boatHz

local function keyAxis(pos: { Enum.KeyCode }, neg: { Enum.KeyCode }): number
	local v = 0
	for _, k in pos do
		if UserInputService:IsKeyDown(k) then
			v += 1
			break
		end
	end
	for _, k in neg do
		if UserInputService:IsKeyDown(k) then
			v -= 1
			break
		end
	end
	return v
end

local function gamepadStick(): (number, number)
	if not UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		return 0, 0
	end
	for _, io in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if io.KeyCode == Enum.KeyCode.Thumbstick1 then
			return io.Position.Y, io.Position.X
		end
	end
	return 0, 0
end

-- Throttle (+ forward) and steer (+ right) from whichever device is pushed hardest.
function Input.readDevices(): (number, number)
	local bestT, bestS, bestMag = 0, 0, 0
	local function offer(t: number, s: number)
		local mag = math.max(math.abs(t), math.abs(s))
		if mag > bestMag then
			bestT, bestS, bestMag = t, s, mag
		end
	end
	if not UserInputService:GetFocusedTextBox() then
		offer(
			keyAxis({ Enum.KeyCode.W, Enum.KeyCode.Up }, { Enum.KeyCode.S, Enum.KeyCode.Down }),
			keyAxis({ Enum.KeyCode.D, Enum.KeyCode.Right }, { Enum.KeyCode.A, Enum.KeyCode.Left })
		)
	end
	local gt, gs = gamepadStick()
	offer(gt, gs)
	if controls ~= nil then
		local ok, mv = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(mv) == "Vector3" then
			offer(-mv.Z, mv.X)
		end
	end
	if bestMag < Input.DEADZONE then
		return 0, 0
	end
	return math.clamp(bestT, -1, 1), math.clamp(bestS, -1, 1)
end

-- The single path every helm message takes. Returns true if it was sent.
function Input.sendHelm(throttle: number, steer: number): boolean
	local r = boatRemote
	if r == nil then
		return false
	end
	throttle = math.clamp(throttle, -1, 1)
	steer = math.clamp(steer, -1, 1)
	local now = os.clock()
	if now - lastSentAt < minGap then
		return false
	end
	local changed = math.abs(throttle - lastThrottle) > 0.05 or math.abs(steer - lastSteer) > 0.05
	local held = throttle ~= 0 or steer ~= 0
	if not changed and not (held and now - lastSentAt >= Input.KEEPALIVE) then
		return false
	end
	lastSentAt = now
	lastThrottle, lastSteer = throttle, steer
	r:FireServer(throttle, steer)
	return true
end

function Input.sendIntent(kind: string, num: number?, flag: boolean?, text: string?)
	local r = intentRemote
	if r then
		r:FireServer(kind, num, flag, text)
	end
end

-- DebugBot only: replace the devices with a function returning (throttle, steer).
function Input.setOverride(fn: (() -> (number, number))?)
	override = fn
end

local function loadControls()
	local player = Players.LocalPlayer
	local ps = player:WaitForChild("PlayerScripts", 10)
	local pm = ps and ps:WaitForChild("PlayerModule", 10)
	if pm == nil or not pm:IsA("ModuleScript") then
		return -- keyboard and gamepad still work; touch steering needs MobileButtons (S4)
	end
	local ok, res = pcall(function()
		return (require(pm) :: any):GetControls()
	end)
	if ok then
		controls = res
	end
end

local KEY_INTENTS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.F] = "ToggleLantern",
	[Enum.KeyCode.ButtonY] = "ToggleLantern",
	[Enum.KeyCode.M] = "ToggleMotor",
	[Enum.KeyCode.ButtonX] = "ToggleMotor",
}

function Input.init()
	boatRemote = Remotes.wait("BoatInput")
	intentRemote = Remotes.wait("Intent")
	task.spawn(loadControls)

	UserInputService.InputBegan:Connect(function(io: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local kind = KEY_INTENTS[io.KeyCode]
		if kind then
			Input.sendIntent(kind)
		end
	end)

	RunService.Heartbeat:Connect(function()
		-- Only the helm steers; the server would refuse anyone else anyway.
		local atHelm = BoatClient.mySeat() == "HelmSeat"
		if not atHelm and override == nil then
			if lastThrottle ~= 0 or lastSteer ~= 0 then
				Input.sendHelm(0, 0)
			end
			return
		end
		local fn = override
		local t, s
		if fn then
			t, s = fn()
		else
			t, s = Input.readDevices()
		end
		Input.sendHelm(t, s)
	end)
end

return Input
