--!strict
-- Touch buttons for every verb (only when touch is how this player plays). Large, paper and
-- ink, in the two bottom corners, laid out from the screen size so they fit the smallest
-- phone (705 by 338) and never sit on the default jump button's area (Roblox's touch jump
-- button: 70 px, 95 px from the right and 90 px from the bottom on screens whose short side
-- is 500 px or less, else 120 px at 170 and 210; jumping is off while seated anyway).
--   Bottom right: Cast (the big one: hold to charge and let go; hold to reel), Use (keep,
--     bank, refill, or bail while held when there is water in the boat), Knock.
--   Bottom left, along the edge (the move stick still starts anywhere to the right of it):
--     Lantern, Motor, Bail, Book, Guide, Call.
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
	local ok, pref = pcall(function()
		return (UserInputService :: any).PreferredInput
	end)
	if ok and pref ~= nil then
		return string.find(tostring(pref), "Touch", 1, true) ~= nil
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- The default jump button's rectangle (left, top, right, bottom) for a screen size.
function MobileButtons.jumpRect(w: number, h: number): (number, number, number, number)
	local small = math.min(w, h) <= 500
	local size = if small then 70 else 120
	local x = w - (size * 1.5 - 10)
	local y = if small then h - size - 20 else h - size * 1.75
	return x, y, x + size, y + size
end

-- Where every button goes on a w by h screen: name -> (center x, center y, size).
function MobileButtons.layout(w: number, h: number): { [string]: { x: number, y: number, size: number } }
	local k = math.clamp(math.min(w, h) / 338, 1, 1.6)
	local gap = MobileButtons.GAP * k
	local edge = MobileButtons.EDGE * k
	local cast, use, small = 84 * k, 62 * k, 54 * k
	local jl, jt, jr, _jb = MobileButtons.jumpRect(w, h)
	local out = {}
	-- Cast: bottom right, just left of the jump area.
	local cx = jl - gap - cast / 2
	local cy = h - edge - cast / 2
	out.Cast = { x = cx, y = cy, size = cast }
	-- Use: above the jump area.
	out.Use = { x = (jl + jr) / 2, y = jt - gap - use / 2, size = use }
	-- Knock: above Cast.
	out.Knock = { x = cx, y = cy - cast / 2 - gap - small / 2, size = small }
	-- Left edge: two columns of three, from the bottom up.
	local names = { "Lantern", "Motor", "Bail", "Book", "Guide", "Call" }
	for i, name in names do
		local col = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		out[name] = {
			x = edge + small / 2 + col * (small + gap),
			y = h - edge - small / 2 - row * (small + gap),
			size = small,
		}
	end
	return out
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
	local cam = Workspace.CurrentCamera
	local g = gui
	if cam == nil or g == nil then
		return
	end
	local vs = cam.ViewportSize
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
	-- The callout feed sits above the left column.
	local small = spots.Call
	if small then
		Callouts.setFeedBottom(vs.Y - (small.y - small.size / 2) + 8)
	end
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
