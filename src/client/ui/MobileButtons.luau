--!strict
-- Touch buttons for every verb (only when touch is how this player plays, Input.touch).
-- Large, paper and ink, all on the right half, laid out from the screen size so they fit the
-- smallest phone (705 by 338), never sit on the default jump button's area (Roblox's touch
-- jump button: 70 px, 95 px from the right and 90 px from the bottom on screens whose short
-- side is 500 px or less, else 120 px at 170 and 210; jumping is off while seated anyway),
-- and leave the bottom-left thumbstick zone (stickRect) and the HUD paper (top left) clear.
--   Bottom right: Cast (the big one: hold to charge and let go; hold to reel), Knock beside
--     it, Use (keep, bank, refill, or bail while held) above the jump area.
--   Above them, two rows of three: Lantern, Motor, Bail; Book, Guide, Call.
-- The labels follow what the press will do ("Reel", "Keep", "Bank", "Bell"). While drowned
-- only Bell and Call show; while the book or the title covers the view, none do.

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local client = script.Parent.Parent
local Input = require(client:WaitForChild("Input"))
local ViewState = require(client:WaitForChild("ViewState"))
local LobbyClient = require(client:WaitForChild("LobbyClient"))
local Drowned = require(client:WaitForChild("Drowned"))
local Paper = require(script.Parent:WaitForChild("Paper"))
local BookState = require(script.Parent:WaitForChild("BookState"))
local Callouts = require(script.Parent:WaitForChild("Callouts"))

local MobileButtons = {}

MobileButtons.GAP = 10
MobileButtons.EDGE = 12

type Btn = { button: TextButton, size: number, held: boolean, input: InputObject? }

local gui: ScreenGui? = nil
local btns: { [string]: Btn } = {}
local enabled = false

-- Touch is how this player plays: the preferred input when the engine reports it, else a
-- touch screen with no keyboard.
function MobileButtons.wanted(): boolean
	return Input.touch()
end

-- The default jump button's rectangle (left, top, right, bottom) for a screen size.
function MobileButtons.jumpRect(w: number, h: number): (number, number, number, number)
	local small = math.min(w, h) <= 500
	local size = if small then 70 else 120
	local x = w - (size * 1.5 - 10)
	local y = if small then h - size - 20 else h - size * 1.75
	return x, y, x + size, y + size
end

-- The bottom-left area kept clear for Roblox's move thumbstick (the helm steers with it on
-- touch): this share of the width and of the height, from the bottom-left corner.
MobileButtons.STICK_W = 0.4
MobileButtons.STICK_H = 0.45
MobileButtons.MIN_SIZE = 44

-- The thumbstick zone on a w by h screen (left, top, right, bottom).
function MobileButtons.stickRect(w: number, h: number): (number, number, number, number)
	return 0, h * (1 - MobileButtons.STICK_H), w * MobileButtons.STICK_W, h
end

-- Where every button goes on a w by h screen: name -> (center x, center y, size).
-- Everything sits in the right half (phone feedback 11/26/2026: the old left columns
-- covered the HUD paper and the thumbstick):
--   Cast (largest) bottom right, just left of the jump area; Knock left of Cast on the
--   bottom edge; Use above the jump area.
--   Light, Motor, Bail (lower row) and Book, Guide, Call (upper row): two rows of three
--   above Cast and Knock, ending just left of Use.
function MobileButtons.layout(w: number, h: number): { [string]: { x: number, y: number, size: number } }
	local k = math.clamp(math.min(w, h) / 338, 1, 1.6)
	local gap = MobileButtons.GAP * k
	local edge = MobileButtons.EDGE * k
	local minSize = MobileButtons.MIN_SIZE
	local cast = math.max(84 * k, minSize)
	local use = math.max(62 * k, minSize)
	local small = math.max(54 * k, minSize)
	local jl, jt, jr, _jb = MobileButtons.jumpRect(w, h)
	local out = {}
	-- Cast: bottom right, just left of the jump area.
	local cx = jl - gap - cast / 2
	local cy = h - edge - cast / 2
	out.Cast = { x = cx, y = cy, size = cast }
	-- Use: above the jump area.
	out.Use = { x = (jl + jr) / 2, y = jt - gap - use / 2, size = use }
	-- Knock: left of Cast, on the bottom edge.
	out.Knock = { x = cx - cast / 2 - gap - small / 2, y = h - edge - small / 2, size = small }
	-- Two rows of three above Cast, the right end just left of Use.
	local right = (jl + jr) / 2 - use / 2 - gap
	local rowBottom = cy - cast / 2 - gap
	local rows = { { "Lantern", "Motor", "Bail" }, { "Book", "Guide", "Call" } }
	for r, names in rows do
		local y = rowBottom - small / 2 - (r - 1) * (small + gap)
		for i, name in names do
			out[name] = { x = right - small / 2 - (3 - i) * (small + gap), y = y, size = small }
		end
	end
	return out
end

-- The top edge of the button cluster on a w by h screen (the prompt sits above it).
function MobileButtons.clusterTop(w: number, h: number): number
	local top = h
	for _, s in MobileButtons.layout(w, h) do
		top = math.min(top, s.y - s.size / 2)
	end
	return top
end

-- The left edge of the button cluster.
function MobileButtons.clusterLeft(w: number, h: number): number
	local left = w
	for _, s in MobileButtons.layout(w, h) do
		left = math.min(left, s.x - s.size / 2)
	end
	return left
end

local function makeButton(parent: Instance, name: string, label: string): Btn
	local b = Paper.button(parent, name, label, UDim2.fromOffset(60, 60))
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.BackgroundTransparency = 0.12
	b.TextWrapped = true
	b.Selectable = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = b
	local item: Btn = { button = b, size = 60, held = false }
	btns[name] = item
	return item
end

-- A button that does something while held (down on press, up on release or touch end).
local function holdable(item: Btn, fn: (boolean) -> ())
	item.button.InputBegan:Connect(function(io)
		local t = io.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			item.held = true
			item.input = io
			fn(true)
		end
	end)
	item.button.InputEnded:Connect(function(io)
		local t = io.UserInputType
		if item.held and (t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1) then
			item.held = false
			fn(false)
		end
	end)
end

local function place()
	local g = gui
	if g == nil then
		return
	end
	-- The gui's own area (the device safe area, so a notch never eats a button); the
	-- camera's viewport until the gui has a size.
	local vs = g.AbsoluteSize
	if vs.X < 1 or vs.Y < 1 then
		local cam = Workspace.CurrentCamera
		if cam == nil then
			return
		end
		vs = cam.ViewportSize
	end
	local spots = MobileButtons.layout(vs.X, vs.Y)
	for name, item in btns do
		local s = spots[name]
		if s then
			item.size = s.size
			item.button.Size = UDim2.fromOffset(s.size, s.size)
			item.button.Position = UDim2.fromOffset(s.x, s.y)
			item.button.TextSize = math.floor(math.clamp(s.size * 0.27, 13, 24))
		end
	end
	-- The callout feed keeps its default spot at the bottom left (text only: it never takes
	-- a touch from the thumbstick under it).
	Callouts.setFeedBottom(0)
end

local function phaseLabel(): (string, string)
	if Drowned.active() then
		return "Bell", "Use"
	end
	local pv = ViewState.me()
	local view = ViewState.get()
	local phase = if pv then pv.fishing else "None"
	local cast = if phase == "Bite" or phase == "Reeling" or phase == "Waiting" then "Reel" else "Cast"
	local use = "Use"
	local flood = tonumber(view.flood) or 0
	if phase == "Deciding" then
		use = "Keep"
	elseif flood > 0.005 then
		use = "Bail"
	elseif ViewState.atDock() and view.hold > 0 then
		use = "Bank"
	elseif ViewState.atDock() and view.refills > 0 and view.oil < 0.9 then
		use = "Oil"
	end
	return cast, use
end

local function refresh()
	local g = gui
	if g == nil then
		return
	end
	local covered = BookState.current() ~= nil or LobbyClient.get().phase == "Title" or LobbyClient.waiting()
	g.Enabled = enabled and not covered
	if not g.Enabled then
		return
	end
	local dead = Drowned.active()
	local cast, use = phaseLabel()
	btns.Cast.button.Text = cast
	btns.Use.button.Text = use
	local view = ViewState.get()
	btns.Lantern.button.Text = if view.lanternOn then "Light off" else "Light"
	btns.Motor.button.Text = if view.motorOn then "Motor off" else "Motor"
	local flood = tonumber(view.flood) or 0
	btns.Bail.button.BackgroundTransparency = if flood > 0.005 then 0.12 else 0.6
	-- While deciding on a fish, the catch card's own Keep and Throw back buttons sit at the
	-- bottom middle: Cast and Knock step aside (Use reads "Keep").
	local pv = ViewState.me()
	local deciding = pv ~= nil and pv.fishing == "Deciding"
	for name, item in btns do
		local show = not dead or name == "Cast" or name == "Call"
		if deciding and (name == "Cast" or name == "Knock") then
			show = false
		end
		item.button.Visible = show
	end
end

function MobileButtons.debugState(): { [string]: any }
	local out = { enabled = enabled, shown = gui ~= nil and (gui :: ScreenGui).Enabled }
	for name, item in btns do
		local b = item.button
		out[name] = { x = b.AbsolutePosition.X, y = b.AbsolutePosition.Y, size = b.AbsoluteSize.X, visible = b.Visible }
	end
	return out
end

function MobileButtons.init()
	local g = Paper.gui("DeadCalmMobileButtons", 5)
	g.IgnoreGuiInset = true
	-- Under Roblox's top bar is fine (the buttons sit low), but stay inside the device's safe
	-- area (ScreenInsets: DeviceSafeInsets).
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	end)
	g.Enabled = false
	gui = g

	holdable(makeButton(g, "Cast", "Cast"), function(down)
		Input.castButton(down)
	end)
	holdable(makeButton(g, "Use", "Use"), function(down)
		Input.useButton(down)
	end)
	makeButton(g, "Knock", "Knock").button.Activated:Connect(function()
		Input.knock()
	end)
	makeButton(g, "Lantern", "Light").button.Activated:Connect(function()
		Input.toggle("ToggleLantern")
	end)
	makeButton(g, "Motor", "Motor").button.Activated:Connect(function()
		Input.toggle("ToggleMotor")
	end)
	holdable(makeButton(g, "Bail", "Bail"), function(down)
		Input.bail(down)
	end)
	makeButton(g, "Book", "Book").button.Activated:Connect(function()
		BookState.toggle("rules")
	end)
	makeButton(g, "Guide", "Guide").button.Activated:Connect(function()
		BookState.toggle("guide")
	end)
	makeButton(g, "Call", "Call").button.Activated:Connect(function()
		Input.toggleCallouts()
	end)

	-- A finger that slides off a held button still lets go.
	UserInputService.TouchEnded:Connect(function(touch: InputObject)
		for name, item in btns do
			if item.held and item.input == touch then
				item.held = false
				if name == "Cast" then
					Input.castButton(false)
				elseif name == "Use" then
					Input.useButton(false)
				elseif name == "Bail" then
					Input.bail(false)
				end
			end
		end
	end)

	local function updateWanted()
		enabled = MobileButtons.wanted()
		-- The night widens the Watcher's cones on a touch screen (PlayerObs.touch).
		LobbyClient.send("Touch", if enabled then 1 else 0)
		refresh()
	end
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(updateWanted)
	end)
	updateWanted()
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(place)
	end
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()
	BookState.onChange(refresh)
	local sentTouch = false
	LobbyClient.onChange(function()
		if not sentTouch then
			-- The Lobby remote is ready once the first state arrives.
			sentTouch = true
			LobbyClient.send("Touch", if enabled then 1 else 0)
		end
		refresh()
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.15 then
			acc = 0
			refresh()
		end
	end)
end

return MobileButtons
