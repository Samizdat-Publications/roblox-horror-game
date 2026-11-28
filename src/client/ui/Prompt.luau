--!strict
-- One small hint at the bottom of the screen: what the interact key or the cast button does
-- right now (bank the hold at the dock, refill the lantern, cast, wait for the bite).
-- Polish 3 (Neon's finale review): no hint at all during the finale, and no fishing hint
-- while the motor runs (the rule verbs, bail and knock, still show then).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Look = require(Shared:WaitForChild("Look"))

local client = script.Parent.Parent
local ViewState = require(client:WaitForChild("ViewState"))
local BoatClient = require(client:WaitForChild("BoatClient"))
local Knocking = require(client:WaitForChild("fx"):WaitForChild("Knocking"))
local BoatFx = require(client:WaitForChild("BoatFx"))
local Input = require(client:WaitForChild("Input"))
local Paper = require(script.Parent:WaitForChild("Paper"))
local MobileButtons = require(script.Parent:WaitForChild("MobileButtons"))
local DeathCard = require(script.Parent:WaitForChild("DeathCard"))

local Prompt = {}

-- The hint for a moment, or "" for none. Pure: easy to read and to check.
function Prompt.textFor(
	phase: string,
	atDock: boolean,
	safe: boolean,
	hold: number,
	oil: number,
	refills: number,
	touch: boolean
): string
	if phase == "Deciding" or phase == "Bite" or phase == "Reeling" then
		return ""
	end
	if atDock and hold > 0 then
		return if touch
			then string.format("Tap Use to bank the hold (%d)", hold)
			else string.format("E  Bank the hold (%d)", hold)
	end
	if atDock and refills > 0 and oil < 0.9 then
		return if touch then "Tap Use to refill the lantern" else "E  Refill the lantern"
	end
	if phase == "Waiting" then
		return if touch then "Wait for the bite, or tap Line in." else "Wait for the bite.  X  Reel in"
	end
	if phase == "Idle" and not safe then
		return if touch then "Hold Cast, let go to throw" else "Click or Space  Hold to cast, let go to throw"
	end
	if phase == "Idle" and safe then
		return "Row out of the beacon light to fish."
	end
	return ""
end

-- Where the hint goes (in the gui's own w by h area): (anchor x, x, bottom y, width,
-- text size, align right). Mouse and keys: bottom centre, 520 wide. Touch: on the right
-- half just above the button cluster (MobileButtons.clusterTop), right-aligned, no wider
-- than the cluster's side of the screen, so it never runs into a button or the thumbstick.
-- M8 polish (Neon: a hint was "microscopic"): never under MIN_TEXT pixels on any screen, and
-- a little larger on tall screens (Paper.fit scales with the viewport height).
Prompt.MIN_TEXT = 16

function Prompt.textSize(h: number, touch: boolean): number
	if touch and h < 450 then
		return Prompt.MIN_TEXT
	end
	return math.max(Prompt.MIN_TEXT, Paper.fit(18, 18, 24))
end

function Prompt.placement(w: number, h: number, touch: boolean): (number, number, number, number, number, boolean)
	if not touch then
		return 0.5, w / 2, h - 40, math.min(560, w - 24), Prompt.textSize(h, false), false
	end
	local edge = MobileButtons.EDGE
	local left = math.max(w * MobileButtons.STICK_W, math.min(w * 0.5, MobileButtons.clusterLeft(w, h)))
	local width = w - edge - left
	local size = Prompt.textSize(h, true)
	return 1, w - edge, MobileButtons.clusterTop(w, h) - 6, width, size, true
end

function Prompt.init()
	local gui = Paper.gui("DeadCalmPrompt", 4)
	-- Same frame as MobileButtons (full screen inside the device safe area), so the touch
	-- placement lines up with the buttons.
	gui.IgnoreGuiInset = true
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	local t = Paper.text(gui, "Hint", "", 18)
	t.TextColor3 = Look.UI.paper
	t.TextStrokeColor3 = Look.UI.ink
	t.TextStrokeTransparency = 0.35
	t.TextYAlignment = Enum.TextYAlignment.Bottom
	local function place()
		local size = gui.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		local ax, x, bottom, width, ts, right = Prompt.placement(size.X, size.Y, Input.touch())
		t.AnchorPoint = Vector2.new(ax, 1)
		t.Position = UDim2.fromOffset(x, bottom)
		-- Two lines of room: a long hint wraps upward instead of running sideways.
		t.Size = UDim2.fromOffset(width, ts * 2 + 8)
		t.TextSize = ts
		t.TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(place)
	end)
	place()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		-- The moment a fail lands (the boat thrown) or the death card is up, no hint at all
		-- (Neon saw "Hold to cast" stay on through the Hum fail, 11/26/2026).
		if BoatFx.capsizing() or BoatFx.plunging() or DeathCard.showing() then
			t.Text = ""
			acc = 0
			return
		end
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local view = ViewState.get()
		local pv = ViewState.me()
		local seated = BoatClient.mySeat() ~= nil
		if
			pv == nil
			or not pv.alive
			or not seated
			or view.phase == "Cleared"
			or view.phase == "Failed"
			or view.phase == "Finale"
		then
			t.Text = ""
			return
		end
		local touch = Input.touch()
		-- The rules' verbs come first: bail while the boat takes water, knock while it listens.
		-- (The hint names the key, never the answer: how many knocks is the book's business.)
		if (tonumber(view.flood) or 0) > 0.005 and pv.fishing ~= "Deciding" then
			t.Text = if touch then "Hold Use to bail" else "Hold E  Bail"
			return
		end
		if Knocking.windowOpen() then
			t.Text = if touch then "Tap Knock to knock on the hull" else "Q  Knock on the hull"
			return
		end
		if view.motorOn then
			t.Text = ""
			return
		end
		t.Text = Prompt.textFor(pv.fishing, ViewState.atDock(), view.safe, view.hold, view.oil, view.refills, touch)
	end)
end

return Prompt
