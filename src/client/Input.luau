--!strict
-- Keyboard, touch and gamepad all map to the same intents.
--   Helm (only sent from the helm seat): W S / Up Down throttle, A D / Left Right steer, the left
--   gamepad stick, or the touch thumbstick (read through the default PlayerModule).
--   F or gamepad Y: lantern. M or gamepad X: motor.
--   Cast and reel: left mouse, Space or gamepad R2 (and a touch button). With the line idle,
--   hold to charge and let go to cast; during the bite or the fight, hold to reel and let go
--   to ease off (ReelHold intents).
--   E or gamepad A (and a touch button): keep the fish on the line, else bank the hold at the
--   dock, else refill the lantern at the dock.
--   X or gamepad B: throw the fish back, else reel the line in (CutLine).
-- Every helm message goes through Input.sendHelm, rate limited to Config.Net.boatHz.
-- DebugBot drives the helm through Input.setOverride and sends its intents through
-- Input.sendIntent, so it uses the same send paths as a player.
-- The other touch buttons arrive with MobileButtons in S4.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))
local ViewState = require(script.Parent:WaitForChild("ViewState"))

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

Input.CHARGE_SECONDS = 1 -- holding this long casts at full power

local castDown = false
local castDownAt = 0
local reelHeld = false

local function myPhase(): string
	local pv = ViewState.me()
	return if pv and pv.alive then pv.fishing else "None"
end

-- The cast and reel button went down (true) or up (false).
function Input.castButton(down: boolean)
	local phase = myPhase()
	if down then
		castDown = true
		castDownAt = os.clock()
		if phase == "Bite" or phase == "Reeling" or phase == "Waiting" then
			reelHeld = true
			Input.sendIntent("ReelHold", nil, true)
		end
		return
	end
	if not castDown then
		return
	end
	castDown = false
	if reelHeld then
		reelHeld = false
		Input.sendIntent("ReelHold", nil, false)
	elseif phase == "Idle" then
		local power = math.clamp((os.clock() - castDownAt) / Input.CHARGE_SECONDS, 0.2, 1)
		Input.sendIntent("Cast", power)
	end
end

-- Interact: keep the fish, else bank at the dock, else refill at the dock.
function Input.interact()
	local phase = myPhase()
	local view = ViewState.get()
	if phase == "Deciding" then
		Input.sendIntent("CatchDecision", nil, true)
	elseif ViewState.atDock() and view.hold > 0 then
		Input.sendIntent("Bank")
	elseif ViewState.atDock() and view.refills > 0 and view.oil < 0.9 then
		Input.sendIntent("RefillOil")
	end
end

-- Throw the fish back, else reel the line in.
function Input.throwBack()
	local phase = myPhase()
	if phase == "Deciding" then
		Input.sendIntent("CatchDecision", nil, false)
	elseif phase == "Waiting" or phase == "Bite" or phase == "Reeling" then
		Input.sendIntent("CutLine")
	end
end

-- Seconds the cast button has been held (0 when up), for a charge display.
function Input.charge(): number
	if not castDown or reelHeld then
		return 0
	end
	return math.clamp((os.clock() - castDownAt) / Input.CHARGE_SECONDS, 0, 1)
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
		elseif io.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.castButton(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.castButton(false)
		end
	end)

	-- Space and R2 are bound above the default jump (which is disabled while seated anyway),
	-- with a touch button on phones. E and X likewise.
	local high = Enum.ContextActionPriority.High.Value
	ContextActionService:BindActionAtPriority("DeadCalmCast", function(_name, state: Enum.UserInputState)
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			Input.castButton(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			Input.castButton(false)
		end
		return Enum.ContextActionResult.Sink
	end, true, high, Enum.KeyCode.Space, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("DeadCalmCast", "Cast")
	ContextActionService:BindActionAtPriority("DeadCalmUse", function(_name, state: Enum.UserInputState)
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			Input.interact()
		end
		return Enum.ContextActionResult.Sink
	end, true, high, Enum.KeyCode.E, Enum.KeyCode.ButtonA)
	ContextActionService:SetTitle("DeadCalmUse", "Use")
	ContextActionService:BindActionAtPriority("DeadCalmThrow", function(_name, state: Enum.UserInputState)
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			Input.throwBack()
		end
		return Enum.ContextActionResult.Sink
	end, false, high, Enum.KeyCode.X, Enum.KeyCode.ButtonB)

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
