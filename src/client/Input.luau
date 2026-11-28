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
--   Q or gamepad L1 (and a touch button): knock on the hull (the Knocking's answer).
--   C or gamepad D-pad up (and a touch button): the callout wheel (ui/Callouts). Wave lives
--   in the wheel.
--   Hold E or gamepad A while there is water in the boat (and no fish to decide on): bail.
--   While drowned, the cast button rings the ghost bell (Drowned sets the handler).
--   R or gamepad D-pad left: the rulebook. G or gamepad D-pad right: the Field Guide
--   (BookState sets the handler; Escape or B closes the book).
-- Touch: ui/MobileButtons draws a large button for every verb and calls the functions here
-- (no ContextActionService touch buttons). While the book covers the view, or the title
-- screen is up, the hands are blocked (Input.setBlocked): no casting, reeling, steering,
-- lantern, motor, knocking or bailing. On touch, Roblox's own thumbstick and jump button
-- also hide while blocked (applyTouchControls). Input.touch() is the one touch check the UI
-- uses for touch wording and layout.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BoatClient = require(script.Parent:WaitForChild("BoatClient"))
local ViewState = require(script.Parent:WaitForChild("ViewState"))
local Knocking = require(script.Parent:WaitForChild("fx"):WaitForChild("Knocking"))

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

-- Touch is how this player plays: UserInputService.PreferredInput when the engine has it
-- (Enum.PreferredInput.Touch: a touch device with no other input connected), else a touch
-- screen with no keyboard. Every touch-or-keys choice in the UI asks this one function.
function Input.touch(): boolean
	local ok, pref = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if ok and pref ~= nil then
		return string.find(tostring(pref), "Touch", 1, true) ~= nil
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local blocks: { [string]: boolean } = {}
local touchHidden = false -- true while we have hidden Roblox's touch thumbstick and jump

-- Roblox's own touch controls (move thumbstick, jump) hide while something covers the view
-- (the title, a full-screen book) and come back after. GuiService.TouchControlsEnabled
-- hides them; the PlayerModule's ControlModule:Disable() and :Enable() are the documented
-- fallback. Both are pcall'd. Only on touch: a keyboard player's controls are never touched.
local function applyTouchControls()
	local hide = next(blocks) ~= nil and Input.touch()
	if hide == touchHidden then
		return
	end
	touchHidden = hide
	pcall(function()
		GuiService.TouchControlsEnabled = not hide
	end)
	local c = controls
	if c ~= nil then
		pcall(function()
			if hide then
				c:Disable()
			else
				c:Enable(true)
			end
		end)
	end
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
		-- The title may already be up: hide the stick now that the module is here.
		if touchHidden and res ~= nil then
			pcall(function()
				res:Disable()
			end)
		end
	end
end

Input.CHARGE_SECONDS = 1 -- holding this long casts at full power

local castDown = false
local bookHandler: ((string) -> ())? = nil
local castDownAt = 0
local reelHeld = false
local bailHeld = false
local ghostHandler: (() -> ())? = nil
local calloutHandler: (() -> ())? = nil

-- Drowned: what the cast button does while you are one of the drowned (ring the bell).
function Input.setGhostHandler(fn: (() -> ())?)
	ghostHandler = fn
end

-- Callouts: what the callout key does (open or close the wheel).
function Input.setCalloutHandler(fn: (() -> ())?)
	calloutHandler = fn
end

-- True while something covers the view (the book, the title screen): no hands.
function Input.blocked(): boolean
	return next(blocks) ~= nil
end

-- BookState: what R and G (and the D-pad sides) do.
function Input.setBookHandler(fn: ((string) -> ())?)
	bookHandler = fn
end

function Input.openBook(page: string)
	local fn = bookHandler
	if fn then
		fn(page)
	end
end

local function amDrowned(): boolean
	local pv = ViewState.me()
	return pv ~= nil and pv.alive == false
end

-- One knock on the hull. The server plays it for everyone; you feel it at once.
function Input.knock()
	if amDrowned() or Input.blocked() then
		return
	end
	Input.sendIntent("Knock")
	Knocking.answered()
end

function Input.toggleCallouts()
	local fn = calloutHandler
	if fn then
		fn()
	end
end

-- Hold to bail (true) and let go (false). Only while there is water in the boat.
function Input.bail(down: boolean)
	if down then
		local flood = tonumber(ViewState.get().flood) or 0
		if flood > 0.005 and not amDrowned() and not bailHeld and not Input.blocked() then
			bailHeld = true
			Input.sendIntent("BailHold", nil, true)
			return
		end
	elseif bailHeld then
		bailHeld = false
		Input.sendIntent("BailHold", nil, false)
	end
end

function Input.bailing(): boolean
	return bailHeld
end

local function myPhase(): string
	local pv = ViewState.me()
	return if pv and pv.alive then pv.fishing else "None"
end

-- The cast and reel button went down (true) or up (false).
function Input.castButton(down: boolean)
	if down and Input.blocked() then
		return
	end
	if amDrowned() then
		local fn = ghostHandler
		if down and fn then
			fn()
		end
		castDown = false
		return
	end
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

-- Interact: keep the fish, else cut the waiting line, else bank or refill at the dock.
function Input.interact()
	if Input.blocked() then
		return
	end
	local phase = myPhase()
	local view = ViewState.get()
	if phase == "Deciding" then
		Input.sendIntent("CatchDecision", nil, true)
	elseif phase == "Waiting" then
		Input.sendIntent("CutLine")
	elseif ViewState.atDock() and view.hold > 0 then
		Input.sendIntent("Bank")
	elseif ViewState.atDock() and view.refills > 0 and view.oil < 0.9 then
		Input.sendIntent("RefillOil")
	end
end

-- Throw the fish back, else reel the line in.
function Input.throwBack()
	if Input.blocked() then
		return
	end
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

-- Blocks the hands for `reason` ("book", "title") while `on`. Letting go of the reel and
-- the bail happens at once, so nothing stays held.
function Input.setBlocked(reason: string, on: boolean)
	blocks[reason] = if on then true else nil
	applyTouchControls()
	if on then
		castDown = false
		if reelHeld then
			reelHeld = false
			Input.sendIntent("ReelHold", nil, false)
		end
		Input.bail(false)
	end
end

-- The Use button went down (true) or up (false): with water in the boat and no fish to
-- decide on it bails while held, else keep, bank or refill.
function Input.useButton(down: boolean)
	if down then
		local flood = tonumber(ViewState.get().flood) or 0
		if flood > 0.005 and myPhase() ~= "Deciding" then
			Input.bail(true)
		else
			Input.interact()
		end
	else
		Input.bail(false)
	end
end

-- Lantern or motor, from a key, a gamepad button or a touch button.
function Input.toggle(kind: string)
	if Input.blocked() or amDrowned() then
		return
	end
	if kind == "ToggleLantern" or kind == "ToggleMotor" then
		Input.sendIntent(kind)
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
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(applyTouchControls)
	end)

	UserInputService.InputBegan:Connect(function(io: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local kind = KEY_INTENTS[io.KeyCode]
		if kind then
			Input.toggle(kind)
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
	end, false, high, Enum.KeyCode.Space, Enum.KeyCode.ButtonR2)
	ContextActionService:BindActionAtPriority("DeadCalmUse", function(_name, state: Enum.UserInputState)
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			-- With water in the boat and no fish to decide on, E is bail (held).
			Input.useButton(true)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			Input.useButton(false)
		end
		return Enum.ContextActionResult.Sink
	end, false, high, Enum.KeyCode.E, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority("DeadCalmKnock", function(_name, state: Enum.UserInputState)
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			Input.knock()
		end
		return Enum.ContextActionResult.Sink
	end, false, high, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:BindActionAtPriority("DeadCalmCallouts", function(_name, state: Enum.UserInputState)
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			Input.toggleCallouts()
		end
		return Enum.ContextActionResult.Sink
	end, false, high, Enum.KeyCode.C, Enum.KeyCode.DPadUp)
	ContextActionService:BindActionAtPriority("DeadCalmThrow", function(_name, state: Enum.UserInputState)
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			Input.throwBack()
		end
		return Enum.ContextActionResult.Sink
	end, false, high, Enum.KeyCode.X, Enum.KeyCode.ButtonB)

	ContextActionService:BindActionAtPriority("DeadCalmBook", function(_name, state: Enum.UserInputState)
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			Input.openBook("rules")
		end
		return Enum.ContextActionResult.Sink
	end, false, high, Enum.KeyCode.R, Enum.KeyCode.DPadLeft)
	ContextActionService:BindActionAtPriority("DeadCalmGuide", function(_name, state: Enum.UserInputState)
		if UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin then
			Input.openBook("guide")
		end
		return Enum.ContextActionResult.Sink
	end, false, high, Enum.KeyCode.G, Enum.KeyCode.DPadRight)

	RunService.Heartbeat:Connect(function()
		-- Only the helm steers; the server would refuse anyone else anyway.
		-- The drowned stay in their seat (hidden) but never steer: their keys turn the view.
		local atHelm = BoatClient.mySeat() == "HelmSeat" and not amDrowned() and not Input.blocked()
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
